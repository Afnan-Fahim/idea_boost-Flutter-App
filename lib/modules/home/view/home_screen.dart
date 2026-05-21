// lib/modules/home/view/home_screen.dart
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../../../core/constants/colors.dart' as core_colors;
import '../../../core/services/admob_service.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';
import '../../../data/models/user_model.dart';
import '../../history/view/history_screen.dart';
import '../../../data/models/idea_model.dart';
import '../../ideas_list/view/ideas_list_screen.dart';
import '../../script_generator/view/script_generator_screen.dart';
import '../../comment_generator/view/comment_generator_screen.dart';
import '../../quick_tools/view/viral_rewrite_screen.dart';
import '../../quick_tools/view/shot_ideas_screen.dart';
import '../../quick_tools/view/hashtag_generator_screen.dart';
import '../../profile/view/profile_screen.dart';
import 'package:ideaboost/modules/favorites/view/favorites_screen.dart';
import '../../idea_details/view/idea_details_screen.dart';
import 'dart:async';
import '../../../data/network/api_client.dart';
import '../../../data/repository/history_repository.dart';
import '../../../core/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/hashtag_parser.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentActivities = [];
  bool _isLoadingHistory = true;
  StreamSubscription? _historySubscription;
  bool _isAdLoading = false;
  Timer? _countdownTimer;
  Timer? _serverSyncTimer;
  // 🚀 PERF: ValueNotifier so countdown rebuilds ONLY its own widget, not the entire screen
  final ValueNotifier<int> _secondsUntilReset = ValueNotifier<int>(0);

  // Countdown base is computed once (preferably using server time) and then
  // decremented using a monotonic clock so device time changes don't break UI.
  final Stopwatch _resetCountdownStopwatch = Stopwatch();
  int? _resetSecondsAtStart;
  bool _postResetRefreshInProgress = false;

  void _logReset(String message) {
    debugPrint('[ResetTimer] $message');
  }

  // 🔒 CACHED reset time (read once on init, not every second)
  DateTime? _cachedResetTime;

  // 🚀 PERF: Remote config cache — fetched once at startup, refreshed every 30 min
  final Map<String, bool> _adEnabledCache = {};
  DateTime? _adConfigLastFetched;
  static const Duration _adConfigCacheDuration = Duration(minutes: 30);

  // ===== DEBUG CHEAT FUNCTION VARIABLES =====
  // To enable: Uncomment the lines calling _cheatDailyCardClickDetection()
  // Location: Line ~575 in _buildDailyUsageCard() - wrap GestureDetector around the card
  List<DateTime> _dailyCardClicks = [];
  static const int _cheatClickThreshold = 15;
  static const Duration _cheatClickWindow = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _logReset('initState: starting reset schedule load');
    // 🚀 PERF FIX: Defer AdMobService.init() to after first frame
    // Prevents blocking critical startup path with ad SDK initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      adMobService.init();

      // Setup callbacks for ad loading state and messages
      adMobService.onLoadingStateChanged = (isLoading) {
        if (mounted) {
          setState(() {
            _isAdLoading = isLoading;
          });
        }
      };

      adMobService.onMessageShown = (message, color) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          final duration = message == 'general.ad_failed_to_load'
              ? const Duration(seconds: 4)
              : message == 'general.reward_failed'
              ? const Duration(seconds: 3)
              : const Duration(seconds: 2);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message.tr()),
              backgroundColor: color,
              duration: duration,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      };

      adMobService.loadBanner(
        onLoaded: () {
          if (mounted) setState(() {});
        },
      );
    });

    // 🔒 Load reset time FIRST, then start countdown timer
    _loadResetTimeOnce().then((_) {
      if (!mounted) return;
      _startCountdownTimer();
      _startServerSyncTimer();
    });

    // 🚀 PERF: Defer Firestore reads + remote config to AFTER first frame renders.
    // This eliminates the startup jank by not blocking the initial build with
    // heavy network calls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRecentHistory();
      _resetDailyLimitOnHomeLoad();
      _loadRemoteConfigCache();
    });
  }

  ImageProvider? _imageProviderFromUrl(String? url, String id) {
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('assets/')) return AssetImage(url);
      if (url.startsWith('http') || url.startsWith('https'))
        return NetworkImage(url);
    }

    // Return null if no valid avatar URL is set
    return null;
  }

  // Premium avatar for app bar
  Widget _buildUserAvatarPremium(String? photoUrl) {
    final imageProvider = _imageProviderFromUrl(photoUrl, '');

    // Only show avatar if user has set one
    if (imageProvider == null) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.white.withOpacity(0.9),
        child: Icon(
          Icons.account_circle_outlined,
          color: Colors.white,
          size: 20,
        ),
      );
    }

    // Show avatar if user has set one
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.white,
      backgroundImage: imageProvider,
    );
  }

  Future<void> _resetDailyLimitOnHomeLoad({bool forceServer = false}) async {
    try {
      final userNotifier = context.read<UserNotifier>();
      // Reload user data to reflect the reset from server
      await userNotifier.reload(forceServer: forceServer);
    } catch (e) {
      // Silently fail - don't disrupt user experience
    }
  }

  // 🚀 PERF: Fetch remote config once and cache tier ad-enable flags.
  // Re-fetches only after _adConfigCacheDuration (30 min) to avoid network
  // round-trips on every ad button press.
  Future<void> _loadRemoteConfigCache() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      // 🚀 PERF FIX: Reduced timeout from 10s to 2s - app should not hang on startup
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 2),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await remoteConfig.fetchAndActivate();
      _adEnabledCache['tier1'] = remoteConfig
          .getValue('adsEnabled_tier1')
          .asBool();
      _adEnabledCache['tier2'] = remoteConfig
          .getValue('adsEnabled_tier2')
          .asBool();
      _adEnabledCache['tier3'] = remoteConfig
          .getValue('adsEnabled_tier3')
          .asBool();
      _adConfigLastFetched = DateTime.now();
      print(
        '✅ Remote config cached: tier1=${_adEnabledCache['tier1']}, '
        'tier2=${_adEnabledCache['tier2']}, tier3=${_adEnabledCache['tier3']}',
      );
    } catch (e) {
      print('⚠️ Remote config cache failed: $e');
      // Default to enabled as safe fallback
      _adEnabledCache['tier1'] = true;
      _adEnabledCache['tier2'] = true;
      _adEnabledCache['tier3'] = true;
    }
  }

  void _startCountdownTimer() {
    //print('🕐 _startCountdownTimer called');
    _countdownTimer?.cancel();
    _updateCountdown(); // Initial call
    _logReset(
      'countdown started: startSeconds=$_resetSecondsAtStart stopwatchRunning=${_resetCountdownStopwatch.isRunning}',
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  // Uses only the cached reset time — NO Firestore calls per tick.
  // _loadResetTimeOnce() populates _cachedResetTime once at startup.
  void _updateCountdown() {
    if (!mounted) return;

    final secondsAtStart = _resetSecondsAtStart;
    if (secondsAtStart == null) return;

    final elapsedSeconds = _resetCountdownStopwatch.elapsed.inSeconds;
    var secondsLeft = secondsAtStart - elapsedSeconds;

    // Product: never expose 00:00:00.
    if (secondsLeft <= 0) {
      _logReset(
        'countdown reached <=0 (elapsed=$elapsedSeconds, start=$secondsAtStart). Triggering refresh.',
      );
      secondsLeft = 1;
      _secondsUntilReset.value = secondsLeft;
      _refreshResetScheduleAfterZero();
      return;
    }

    // 🚀 PERF: Only update the ValueNotifier — no setState, no full rebuild
    _secondsUntilReset.value = secondsLeft;
  }

  void _initializeCountdownFromSeconds(int secondsRemaining) {
    final safeSeconds = secondsRemaining <= 0 ? 1 : secondsRemaining;
    _resetSecondsAtStart = safeSeconds;
    _resetCountdownStopwatch
      ..reset()
      ..start();
    _secondsUntilReset.value = safeSeconds;
    _logReset('countdown base initialized: seconds=$safeSeconds');
  }

  void _startServerSyncTimer() {
    _serverSyncTimer?.cancel();
    _logReset('server sync timer started: interval=60s');
    _serverSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      await _syncCountdownBaseWithServerTime();
    });
  }

  Future<void> _syncCountdownBaseWithServerTime() async {
    final resetTime = _cachedResetTime;
    if (resetTime == null) return;

    try {
      _logReset('server sync tick: requesting serverNow from /health');
      final serverNow = await ApiClient().fetchServerNow();
      if (serverNow == null) {
        _logReset('server sync tick: serverNow=null (keeping local countdown)');
        return;
      }

      var secondsRemaining = resetTime.difference(serverNow).inSeconds;
      if (secondsRemaining <= 0) {
        _logReset(
          'server sync tick: secondsRemaining<=0 ($secondsRemaining). Clamping to 59s.',
        );
        secondsRemaining = 59;
      }
      const maxWindowSeconds = 24 * 60 * 60;
      if (secondsRemaining > maxWindowSeconds) {
        _logReset(
          'server sync tick: secondsRemaining too large ($secondsRemaining). Clamping to 24h.',
        );
        secondsRemaining = maxWindowSeconds;
      }

      _logReset(
        'server sync tick: serverNow=${serverNow.toIso8601String()} resetTime=${resetTime.toIso8601String()} secondsRemaining=$secondsRemaining',
      );

      _initializeCountdownFromSeconds(secondsRemaining);
    } catch (e) {
      _logReset('server sync tick failed: $e');
      // Ignore sync failures; local countdown remains stable.
    }
  }

  Future<void> _refreshResetScheduleAfterZero() async {
    if (_postResetRefreshInProgress) return;
    _postResetRefreshInProgress = true;
    try {
      _logReset('post-zero refresh: starting (delay 2s)');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      await _resetDailyLimitOnHomeLoad();
      await _loadResetTimeOnce();
    } catch (_) {
      // Ignore refresh failures; UI already shows a safe state.
    } finally {
      _logReset('post-zero refresh: done');
      _postResetRefreshInProgress = false;
    }
  }

  // 🔒 Load reset time ONCE at startup (called in initState)
  // 🔒 SECURITY: Also calculates server time offset to prevent device time manipulation
  Future<void> _loadResetTimeOnce({bool forceServer = false}) async {
    try {
      _logReset('loadResetTimeOnce: reading system/resetLock');
      final db = FirebaseFirestore.instance;
      final resetLockRef = db.collection('system').doc('resetLock');
      final resetLockDoc = forceServer
          ? await resetLockRef.get(const GetOptions(source: Source.server))
          : await resetLockRef.get();

      if (resetLockDoc.exists && resetLockDoc['lastResetAt'] != null) {
        // 🔒 Use lastResetAt to calculate the next reset time
        final lastResetTimestamp = resetLockDoc['lastResetAt'] as Timestamp;
        final lastResetTime = lastResetTimestamp.toDate();
        _cachedResetTime = lastResetTime.add(const Duration(hours: 24));

        _logReset(
          'loadResetTimeOnce: lastResetAt=${lastResetTime.toIso8601String()} cachedResetTime=${_cachedResetTime!.toIso8601String()}',
        );

        // Server time offset removed (not currently used for device time validation)
      } else {
        print('⚠️ DEBUG: system/resetLock not found, using user.dailyResetAt');
        final userNotifier = context.read<UserNotifier>();
        _cachedResetTime = userNotifier.userModel.dailyResetAt;
      }

      final resetTime = _cachedResetTime;
      if (resetTime == null) {
        _logReset(
          'loadResetTimeOnce: resetTime=null -> initializing safe countdown',
        );
        _initializeCountdownFromSeconds(1);
        return;
      }

      // Prefer server time (time API) for correct remaining time.
      DateTime? serverNow;
      try {
        _logReset('loadResetTimeOnce: requesting serverNow from /health');
        serverNow = await ApiClient().fetchServerNow();
      } catch (e) {
        _logReset('loadResetTimeOnce: serverNow request failed: $e');
      }
      final referenceNow = serverNow ?? DateTime.now();

      if (serverNow == null) {
        _logReset(
          'loadResetTimeOnce: serverNow=null -> using device time (may be manipulated).',
        );
      } else {
        _logReset(
          'loadResetTimeOnce: serverNow=${serverNow.toIso8601String()}',
        );
      }

      var secondsRemaining = resetTime.difference(referenceNow).inSeconds;
      if (secondsRemaining <= 0) {
        _logReset(
          'loadResetTimeOnce: secondsRemaining<=0 ($secondsRemaining) -> clamping to 59s',
        );
        secondsRemaining = 59;
      }
      const maxWindowSeconds = 24 * 60 * 60;
      if (secondsRemaining > maxWindowSeconds) {
        _logReset(
          'loadResetTimeOnce: secondsRemaining too large ($secondsRemaining) -> clamping to 24h',
        );
        secondsRemaining = maxWindowSeconds;
      }

      _logReset(
        'loadResetTimeOnce: computed secondsRemaining=$secondsRemaining (resetTime=${resetTime.toIso8601String()})',
      );

      _initializeCountdownFromSeconds(secondsRemaining);
    } catch (e) {
      _logReset('loadResetTimeOnce failed: $e');
      // Use user's dailyResetAt as fallback
      final userNotifier = context.read<UserNotifier>();
      _cachedResetTime = userNotifier.userModel.dailyResetAt;

      final resetTime = _cachedResetTime;
      if (resetTime == null) {
        _logReset(
          'loadResetTimeOnce fallback: resetTime=null -> safe countdown',
        );
        _initializeCountdownFromSeconds(1);
        return;
      }

      var secondsRemaining = resetTime.difference(DateTime.now()).inSeconds;
      if (secondsRemaining <= 0) {
        _logReset(
          'loadResetTimeOnce fallback: secondsRemaining<=0 ($secondsRemaining) -> clamping to 59s',
        );
        secondsRemaining = 59;
      }
      const maxWindowSeconds = 24 * 60 * 60;
      if (secondsRemaining > maxWindowSeconds) {
        _logReset(
          'loadResetTimeOnce fallback: secondsRemaining too large ($secondsRemaining) -> clamping to 24h',
        );
        secondsRemaining = maxWindowSeconds;
      }
      _initializeCountdownFromSeconds(secondsRemaining);
    }
  }

  String _formatCountdown(int seconds) {
    if (seconds <= 0) return '00:00:01';

    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');

    return '$hours:$minutes:$secs';
  }

  // 🧪 TRIAL INDICATOR HELPER - Safe, Architecture-Compliant
  /// Check if trial generation indicator should be shown
  /// For T1, T2 users who haven't used trial yet and have trial available
  bool _shouldShowTrialIndicator(UserModel user) {
    // Show for tiers (tier1, tier2)
    final isTierWithTrial =
        user.regionTier == 'tier1' || user.regionTier == 'tier2';

    // Trial must be available and not yet used
    final trialAvailable = (user.trialGenerationsAvailable ?? 0) > 0;
    final notUsedYet = !user.hasUsedTrial;

    return isTierWithTrial && trialAvailable && notUsedYet;
  }

  /// Check if ads are enabled for the user's tier.
  /// Uses a 30-minute in-memory cache populated at startup to avoid a
  /// network round-trip (setConfigSettings + fetch + activate) on every tap.
  Future<bool> _isAdEnabledForTier(UserModel user) async {
    try {
      final tier = user.regionTier.toLowerCase();

      // Refresh cache only if it's empty or older than 30 minutes
      final isExpired =
          _adConfigLastFetched == null ||
          DateTime.now().difference(_adConfigLastFetched!) >
              _adConfigCacheDuration;

      if (isExpired || _adEnabledCache.isEmpty) {
        print('🔄 Remote config cache stale — refreshing...');
        await _loadRemoteConfigCache();
      }

      final isEnabled = _adEnabledCache[tier] ?? false;
      print('🔍 Cache hit: adsEnabled_$tier = $isEnabled');
      return isEnabled;
    } catch (e) {
      print('❌ Error checking ads config: $e');
      return false;
    }
  }

  Future<void> _loadRecentHistory({bool force = false}) async {
    if (force) {
      await _historySubscription?.cancel();
      _historySubscription = null;
    }

    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
      });
    }

    final historyRepo = HistoryRepository();
    final completer = Completer<void>();
    var completed = false;

    _historySubscription = historyRepo.getLogsStream().listen(
      (historyItems) {
        if (!mounted) return;

        if (historyItems.isEmpty) {
          // No history: keep list empty so UI shows an empty-state message
          setState(() {
            _recentActivities = [];
            _isLoadingHistory = false;
          });
        } else {
          // Take only first 6 items and extract data
          final recentItems = historyItems.take(6).toList();
          setState(() {
            _recentActivities = recentItems.map((item) {
              final prompt = item.prompt;
              final label = prompt.length > 20
                  ? prompt.substring(0, 20).trim() + '...'
                  : prompt;
              return {
                'label': label,
                'type': item.type,
                'data': {
                  'type': item.type,
                  'prompt': item.prompt,
                  'output': item.output,
                  'meta': item.meta,
                  'generatedAt': item.generatedAt,
                },
              };
            }).toList();
            _isLoadingHistory = false;
          });
        }

        if (!completed) {
          completed = true;
          completer.complete();
        }
      },
      onError: (e) {
        if (!mounted) return;
        // On error show empty state rather than dummy data
        setState(() {
          _recentActivities = [];
          _isLoadingHistory = false;
        });
        if (!completed) {
          completed = true;
          completer.complete();
        }
      },
    );

    // Don't hang pull-to-refresh forever if the stream is slow.
    await completer.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
  }

  Future<void> _handlePullToRefresh() async {
    try {
      // Fire backend syncs without blocking the pull-to-refresh UI
      _resetDailyLimitOnHomeLoad(forceServer: true);
      _loadResetTimeOnce(forceServer: true);
      _loadRemoteConfigCache();

      // Force a fresh stream subscription for "recent activity".
      await _loadRecentHistory(force: true);
    } catch (_) {
      // Swallow errors; refresh gesture should never crash the screen.
    }
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    _countdownTimer?.cancel();
    _serverSyncTimer?.cancel();
    _secondsUntilReset.dispose();
    adMobService.disposeBanner();
    super.dispose();
  }

  // ===== DEBUG CHEAT FUNCTION - FOR TESTING ONLY =====
  // Location: This function is called from _buildDailyUsageCard()
  // Purpose: Click the daily card 5 times within 5 seconds to reset testing values
  // What it resets:
  // - activeRewardTokens: Mark all tokens as consumed=false
  // - aiUnlocksRemaining: 0 → 1 (for each token)
  // - aiNanoUsed: 0 (reset daily usage)
  // To use this cheat:
  // 1. Find line ~575 in _buildDailyUsageCard() (the Container return statement)
  // 2. Wrap it with: GestureDetector(onTap: _cheatDailyCardClickDetection, child: ...)
  // 3. Then click the card 5 times in 5 seconds
  // To disable: Remove the GestureDetector wrapper or comment out this function call
  Future<void> _cheatDailyCardClickDetection() async {
    final now = DateTime.now();

    // Remove clicks older than the window
    _dailyCardClicks.removeWhere(
      (click) => now.difference(click) > _cheatClickWindow,
    );

    // Add current click
    _dailyCardClicks.add(now);

    print(
      '🧪 DEBUG: Daily card click ${_dailyCardClicks.length}/$_cheatClickThreshold',
    );

    // Check if we've reached the threshold
    if (_dailyCardClicks.length >= _cheatClickThreshold) {
      _dailyCardClicks.clear(); // Reset click counter
      await _resetTestingFields();
    }
  }

  Future<void> _resetTestingFields() async {
    try {
      print('🧪 DEBUG: CHEAT ACTIVATED! Resetting testing fields...');

      final userService = UserService();
      final userId = userService.currentUserId;

      if (userId == null) {
        print('❌ DEBUG: No user ID found');
        return;
      }

      final db = FirebaseFirestore.instance;
      final userDoc = db.collection('users').doc(userId);

      // Get current user data
      final userSnapshot = await userDoc.get();
      final userData = userSnapshot.data() ?? {};

      // Reset activeRewardTokens - mark all as consumed=false
      final activeRewardTokens =
          (userData['activeRewardTokens'] as Map<String, dynamic>?) ?? {};

      Map<String, dynamic> updatedTokens = {};
      activeRewardTokens.forEach((tokenId, tokenData) {
        if (tokenData is Map) {
          updatedTokens[tokenId] = {
            ...tokenData,
            'consumed': false,
            'aiUnlocksRemaining': 1,
          };
          print(
            '✅ DEBUG: Token $tokenId - consumed=false, aiUnlocksRemaining=1',
          );
        }
      });

      // Update Firestore
      await userDoc.update({
        'activeRewardTokens': updatedTokens,
        'aiNanoUsedToday': 0,
      });

      print('✅ DEBUG: Reset complete!');
      print('  - All tokens: consumed → false');
      print('  - All tokens: aiUnlocksRemaining → 1');
      print('  - aiNanoUsedToday → 0');

      // Show success message
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(
      //       content: Text(
      //         '🧪 CHEAT: Testing fields reset! (consumed=false, aiUnlocksRemaining=1, aiNanoUsedToday=0)',
      //       ),
      //       backgroundColor: Colors.green,
      //       duration: Duration(seconds: 3),
      //       behavior: SnackBarBehavior.floating,
      //     ),
      //   );
      // }
    } catch (e) {
      print('❌ DEBUG: Error resetting fields: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('errors.unexpected_error'.tr()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Consumer<UserNotifier>(
      builder: (context, userNotifier, child) {
        final user = userNotifier.userModel;
        final usageDisplay = _calculateUsageDisplay(user);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: const Color.fromARGB(0, 231, 229, 229),
            elevation: 0,
            toolbarHeight: 64,
            titleSpacing: 16,
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 53, 53, 53).withOpacity(0.5),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            title: Image.asset(
              'assets/splash.png',
              height: 50,
              fit: BoxFit.contain,
            ),

            actions: [
              // Favorites Button - Premium Style
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.red.shade400, Colors.pink.shade600],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FavoritesScreen(),
                        ),
                      ),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // History Button - Premium Style
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.cyan.shade400, Colors.blue.shade600],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistoryScreen(),
                        ),
                      ),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.history,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Profile Button - Premium Style
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.purple.shade400, Colors.indigo.shade600],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: _buildUserAvatarPremium(
                          userNotifier.userModel.photoUrl,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          bottomNavigationBar: (!user.isPro && adMobService.isBannerLoaded)
              ? SafeArea(
                  child: Container(
                    color: Colors.white,
                    child: SizedBox(
                      height: adMobService.bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: adMobService.bannerAd!),
                    ),
                  ),
                )
              : const SizedBox.shrink(),

          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              ),
            ),
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: _handlePullToRefresh,
                color: core_colors.AppColors.accent,
                backgroundColor: core_colors.AppColors.surface,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: isMobile ? 12 : 20,
                    right: isMobile ? 12 : 20,
                    top: 8,
                    bottom: 8 + 30 + MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 2),

                      // Hero Text - Single line with moderate margin
                      // Center(
                      //   child: Text(
                      //'home.hero_text'.tr(),
                      //textAlign: TextAlign.center,
                      //     style: TextStyle(
                      //       fontSize: isMobile ? 22 : 28,
                      //       fontWeight: FontWeight.w900,
                      //       color: Colors.white,
                      //       height: 1.0,
                      //       letterSpacing: -0.3,
                      //       shadows: const [
                      //         Shadow(
                      //           color: Colors.black45,
                      //           blurRadius: 10,
                      //           offset: Offset(0, 4),
                      //         ),
                      //       ],
                      //     ),
                      //     maxLines: 1,
                      //     overflow: TextOverflow.visible,
                      //   ),
                      // ),
                      const SizedBox(height: 2),

                      // Daily Usage Card - FIXED for overflow
                      _buildDailyUsageCard(usageDisplay, isMobile),

                      const SizedBox(height: 16),

                      // Main Generators in 2x2 Grid: 1.Ideas 2.Scripts 3.Comments 4.Youth
                      _buildGeneratorsGrid(isMobile, context),

                      const SizedBox(height: 16),

                      // Seasonal Ideas - Aligned with grid
                      _buildSeasonalCard(isMobile, context),

                      const SizedBox(height: 16),

                      // Quick Tools Section - FIXED
                      AutoSizeText(
                        'home.quick_tools'.tr(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        minFontSize: 14,
                      ),
                      const SizedBox(height: 10),

                      // Quick Tools Grid - RESPONSIVE
                      _buildQuickToolsGrid(isMobile),

                      //const SizedBox(height: 4),

                      // Recent Activity - Bold like Quick Tools
                      AutoSizeText(
                        'home.recent_activity'.tr(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        minFontSize: 14,
                      ),
                      const SizedBox(height: 10),

                      _buildChipsWrap(),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Dynamic Icon + Text Alignment Helper
  /// Mathematically centers icon and text based on their sizes for perfect visual alignment
  /// Formula: verticalPadding = (max(iconHeight, textHeight) - min(iconHeight, textHeight)) / 2
  Widget _buildCenteredIconTextButton({
    required Widget icon,
    required Widget text,
    required double iconSize,
    required double textMaxWidth,
    required double gap,
    required double scaleFactor,
  }) {
    // SENIOR UX/UI DESIGNER SOLUTION - Perfect Visual Balance
    // ==========================================================
    // Professional Icon-Text Centering Strategy:
    //
    // For perfect optical balance:
    // 1. Icon and text baseline-align to horizontal center
    // 2. Icon anchors the vertical center point
    // 3. Text wraps with proper center alignment
    // 4. Gap creates readable, unified visual pair
    //
    // Clean, robust formula (no intrinsic calculations):
    // - Row with center alignment ensures both elements sit on same baseline
    // - Icon is size-constrained and centered
    // - Text uses Align center to match icon's visual center
    // - ConstrainedBox prevents overflow
    // - Result: Pixel-perfect balance that works within LayoutBuilder

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon: Perfectly centered in its bounding box
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: Center(child: icon),
        ),
        // Compact gap keeps icon and label visually tied together
        SizedBox(width: gap),
        // Text: Tight, centered label that hugs the icon
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: textMaxWidth),
          child: text,
        ),
      ],
    );
  }

  // Calculate usage display based on new monetization logic
  String _calculateUsageDisplay(UserModel user) {
    final bool isPro = user.plan == 'pro';

    if (isPro) {
      // PRO: Show combined usage with phased total (20+20 base + 20+20 bonus = 80)
      final total = user.aiNanoUsedToday + user.aiMiniUsedToday;
      return '$total / 80';
    } else {
      // FREE: Show remaining generations from Firestore
      final maxGenerations = user.dailyAiLimit ?? 0;
      final remaining = (maxGenerations - user.aiNanoUsedToday).clamp(
        0,
        maxGenerations,
      );
      return '$remaining / $maxGenerations';
    }
  }

  // Calculate AI Generation Used for non-pro users (pure token-based)
  // Formula: used = totalGranted - totalRemaining
  //   Only counts non-expired tokens (expiresAt > now)
  //   totalGranted   = count(valid tokens) × aiPerRewardedAd
  //   totalRemaining = sum(aiUnlocksRemaining) from valid tokens
  //   progress       = used / totalGranted
  Map<String, int> _calculateConsumedTokens(UserModel user) {
    if (user.activeRewardTokens == null || user.activeRewardTokens!.isEmpty) {
      return {'used': 0, 'total': 0};
    }

    final int aiPerAd = user.aiPerRewardedAd ?? 1;
    final now = DateTime.now();
    int tokenCount = 0;
    int totalRemaining = 0;

    user.activeRewardTokens!.forEach((tokenId, tokenData) {
      if (tokenData is Map<String, dynamic>) {
        // Skip expired tokens — they are stale from previous days
        final expiresAt = tokenData['expiresAt'];
        if (expiresAt != null) {
          DateTime? expiry;
          if (expiresAt is Timestamp) {
            expiry = expiresAt.toDate();
          } else if (expiresAt is DateTime) {
            expiry = expiresAt;
          }
          if (expiry != null && expiry.isBefore(now)) {
            return; // Skip this expired token
          }
        }

        tokenCount++;
        final aiUnlocks = tokenData['aiUnlocksRemaining'] as int? ?? 0;
        totalRemaining += aiUnlocks;
      }
    });

    final int totalGranted = tokenCount * aiPerAd;
    final int used = totalGranted - totalRemaining;

    return {'used': used, 'total': totalGranted};
  }

  // NEW: Daily Usage Card with tier-aware display
  Widget _buildDailyUsageCard(String usageDisplay, bool isMobile) {
    // Relative unit helpers scoped to this card
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    double s(double v) => v * screenW / 390;
    double sv(double v) => v * screenH / 844;
    double fs(double v) => (v * screenW / 390).clamp(v * 0.85, v * 1.4);

    // No Consumer needed - data already available from parent Consumer
    return Builder(
      builder: (context) {
        final userNotifier = context.read<UserNotifier>();
        final user = userNotifier.userModel;

        // Use values from Firestore - NO HARDCODED FALLBACKS!
        final int adReward = user.aiPerRewardedAd ?? 0;
        final int maxAdsAllowed = user.maxRewardedAdsPerDay ?? 0;
        final int adsWatched = user.rewardedAdsWatchedToday;
        final int totalTokensEarned = (adsWatched * adReward);
        final int maxTokensAvailable = maxAdsAllowed * adReward;

        return GestureDetector(
          onTap: _cheatDailyCardClickDetection,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(s(22)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(s(16)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1E3C72).withOpacity(0.85),
                      const Color(0xFF2A5298).withOpacity(0.75),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(s(22)),
                  boxShadow: [
                    // Blueish glow emitting around the card
                    BoxShadow(
                      color: const Color(0xFF2A5298).withOpacity(0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top Header: Title + Badge ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AutoSizeText(
                                'daily_ai_generations'.tr(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: fs(16),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.visible,
                                minFontSize: 12,
                              ),
                              SizedBox(height: sv(8)),
                              // ── Tier & Reset stacked vertically ──
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Tier chip (HIDDEN FOR PRO USERS)
                                  if (!user.isPro) ...[
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.public,
                                          color: Colors.white.withOpacity(0.55),
                                          size: s(13),
                                        ),
                                        SizedBox(width: s(3)),
                                        Flexible(
                                          child: Text(
                                            '${user.regionTier.toUpperCase()} • +$adReward/ad',
                                            style: TextStyle(
                                              color: const Color(
                                                0xFF3791FF,
                                              ).withOpacity(0.7),
                                              fontSize: fs(11),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.visible,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: sv(6)),
                                  ],
                                  // Reset countdown
                                  ValueListenableBuilder<int>(
                                    valueListenable: _secondsUntilReset,
                                    builder: (context, seconds, _) => Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.schedule,
                                          color: Colors.amber.shade300,
                                          size: s(13),
                                        ),
                                        SizedBox(width: s(3)),
                                        Flexible(
                                          child: Text(
                                            'home.reset_in'.tr(
                                              args: [_formatCountdown(seconds)],
                                            ),
                                            style: TextStyle(
                                              color: Colors.amber.shade300,
                                              fontSize: fs(11),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.visible,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // PRO Status Message (if user is PRO) - SIMPLIFIED TO JUST NO ADS
                              if (user.isPro) ...[
                                SizedBox(height: sv(6)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.block_rounded,
                                      color: Colors.amber.shade300,
                                      size: s(13),
                                    ),
                                    SizedBox(width: s(4)),
                                    Flexible(
                                      child: Text(
                                        'home.no_ads'.tr(),
                                        style: TextStyle(
                                          color: Colors.amber.shade300,
                                          fontSize: fs(11),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: s(6)),
                        // Show either PRO badge or Reward badge — glass pill
                        if (user.isPro)
                          _buildGlassBadge(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  color: Colors.white,
                                  size: s(14),
                                ),
                                SizedBox(width: s(4)),
                                AutoSizeText(
                                  'profile.badge_pro'.tr(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: fs(12),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.visible,
                                  minFontSize: 10,
                                ),
                              ],
                            ),
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.shade600,
                                Colors.amber.shade400,
                              ],
                            ),
                            borderColor: Colors.amber.shade200,
                            glowColor: Colors.amber,
                            s: s,
                          )
                        else
                          _buildGlassBadge(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.stars,
                                  color: Colors.amber,
                                  size: s(14),
                                ),
                                SizedBox(width: s(4)),
                                Flexible(
                                  child: Text(
                                    '$totalTokensEarned / $maxTokensAvailable',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: fs(12),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              ],
                            ),
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.20),
                                Colors.amber.withOpacity(0.10),
                              ],
                            ),
                            borderColor: Colors.amber.withOpacity(0.5),
                            glowColor: Colors.amber,
                            s: s,
                          ),
                      ],
                    ),

                    SizedBox(height: sv(10)),

                    // ── Progress Bars Section — frosted inner panel ──
                    ClipRRect(
                      borderRadius: BorderRadius.circular(s(14)),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: EdgeInsets.all(s(12)),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(s(14)),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Ads Progress (ONLY FOR NON-PRO USERS)
                              if (!user.isPro)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: AutoSizeText(
                                        'ads_watched'.tr(),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: fs(12),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.visible,
                                        minFontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AutoSizeText(
                                      '$adsWatched / $maxAdsAllowed',
                                      style: TextStyle(
                                        color: Colors.cyan,
                                        fontSize: fs(11),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.visible,
                                      minFontSize: 9,
                                    ),
                                  ],
                                ),
                              if (!user.isPro) SizedBox(height: sv(5)),
                              if (!user.isPro)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(s(4)),
                                  child: LinearProgressIndicator(
                                    value: (adsWatched / maxAdsAllowed).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    minHeight: s(6),
                                    backgroundColor: Colors.white.withOpacity(
                                      0.12,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      adsWatched >= maxAdsAllowed
                                          ? Colors.green.shade400
                                          : Colors.cyan,
                                    ),
                                  ),
                                ),
                              if (!user.isPro) SizedBox(height: sv(10)),
                              // AI Generations Used Progress (actual consumption)
                              Builder(
                                builder: (context) {
                                  // For non-pro users: Show consumed tokens / total tokens
                                  // For PRO users: Show separate nano and mini usage with soft caps
                                  final bool isPro = user.plan == 'pro';

                                  if (isPro) {
                                    // PRO: Mini phase (0→20) then Nano phase (0→80) = 100 total
                                    final nanoUsed = user.aiNanoUsedToday;
                                    final miniUsed = user.aiMiniUsedToday;
                                    const miniCap = 20; // Phase 1
                                    const nanoCap = 80; // Phase 2

                                    return Column(
                                      children: [
                                        // MINI MODEL USAGE (Phase 1 — shown first)
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: AutoSizeText(
                                                'home.model_mini_premium'.tr(),
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  fontSize: fs(12),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.visible,
                                                minFontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            AutoSizeText(
                                              '$miniUsed / $miniCap',
                                              style: TextStyle(
                                                color: miniUsed >= miniCap
                                                    ? Colors.orange
                                                    : Colors.amber,
                                                fontSize: fs(11),
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.visible,
                                              minFontSize: 9,
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: sv(5)),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            s(4),
                                          ),
                                          child: LinearProgressIndicator(
                                            value: (miniUsed / miniCap).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            minHeight: s(6),
                                            backgroundColor: Colors.white
                                                .withOpacity(0.12),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  miniUsed >= miniCap
                                                      ? Colors.red.shade400
                                                      : Colors.amber,
                                                ),
                                          ),
                                        ),
                                        SizedBox(height: sv(10)),
                                        // NANO MODEL USAGE (Phase 2 — shown second)
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: AutoSizeText(
                                                'home.model_nano'.tr(),
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  fontSize: fs(12),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.visible,
                                                minFontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            AutoSizeText(
                                              '$nanoUsed / $nanoCap',
                                              style: TextStyle(
                                                color: nanoUsed >= nanoCap
                                                    ? Colors.orange
                                                    : Colors.purpleAccent,
                                                fontSize: fs(11),
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.visible,
                                              minFontSize: 9,
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: sv(5)),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            s(4),
                                          ),
                                          child: LinearProgressIndicator(
                                            value: (nanoUsed / nanoCap).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            minHeight: s(6),
                                            backgroundColor: Colors.white
                                                .withOpacity(0.12),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  nanoUsed >= nanoCap
                                                      ? Colors.red.shade400
                                                      : Colors.purpleAccent,
                                                ),
                                          ),
                                        ),
                                      ],
                                    );
                                  } else {
                                    // NON-PRO (T1, T2, T3): used = totalGranted - totalRemaining
                                    final tokenStats = _calculateConsumedTokens(
                                      user,
                                    );
                                    final int used = tokenStats['used'] ?? 0;
                                    final int total = tokenStats['total'] ?? 0;

                                    return Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: AutoSizeText(
                                                'ai_generations_used'.tr(),
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  fontSize: fs(12),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.visible,
                                                minFontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            AutoSizeText(
                                              '$used / $total',
                                              style: TextStyle(
                                                color: Colors.purpleAccent,
                                                fontSize: fs(11),
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.visible,
                                              minFontSize: 9,
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: sv(5)),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            s(4),
                                          ),
                                          child: LinearProgressIndicator(
                                            value:
                                                (total > 0
                                                        ? (used / total)
                                                        : 0.0)
                                                    .clamp(0.0, 1.0),
                                            minHeight: s(6),
                                            backgroundColor: Colors.white
                                                .withOpacity(0.12),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  used >= total && total > 0
                                                      ? Colors.red.shade400
                                                      : Colors.purpleAccent,
                                                ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),

                              // 🧪 TRIAL GENERATION INDICATOR (Tier1 & Tier2 only)
                              // Shows only if: trialGenerationsAvailable > 0 && hasUsedTrial == false
                              if (_shouldShowTrialIndicator(user)) ...[
                                SizedBox(height: sv(10)),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: AutoSizeText(
                                        'ai_trial_generation_used'.tr(),
                                        style: TextStyle(
                                          color: Colors.amber.withOpacity(0.8),
                                          fontSize: fs(12),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.visible,
                                        minFontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AutoSizeText(
                                      '${(user.trialGenerationsAvailable ?? 0) - (user.trialGenerationsRemaining ?? user.trialGenerationsAvailable ?? 0)} / ${user.trialGenerationsAvailable ?? 0}',
                                      style: TextStyle(
                                        color: Colors.amber.shade300,
                                        fontSize: fs(11),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.visible,
                                      minFontSize: 9,
                                    ),
                                  ],
                                ),
                                SizedBox(height: sv(5)),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(s(4)),
                                  child: LinearProgressIndicator(
                                    value:
                                        ((user.trialGenerationsAvailable ?? 0) -
                                            (user.trialGenerationsRemaining ??
                                                user.trialGenerationsAvailable ??
                                                0)) /
                                        (user.trialGenerationsAvailable ?? 1)
                                            .clamp(1, double.infinity),
                                    minHeight: s(6),
                                    backgroundColor: Colors.white.withOpacity(
                                      0.12,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.amber.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: sv(12)),

                    // Watch Ad Button (ONLY FOR NON-PRO USERS)
                    Consumer<UserNotifier>(
                      builder: (context, userNotifier, child) {
                        final user = userNotifier.userModel;

                        // Hide watch ad button for PRO users
                        if (user.isPro) {
                          return const SizedBox.shrink();
                        }

                        // ✅ REAL-TIME CHECK: Force fresh fetch bypassing cache
                        final maxAdsAllowed = user.maxRewardedAdsPerDay ?? 0;
                        final adsWatched = user.rewardedAdsWatchedToday;
                        final maxReached = adsWatched >= maxAdsAllowed;

                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isAdLoading || maxReached
                                ? () {
                                    if (maxReached && !_isAdLoading) {
                                      HapticFeedback.lightImpact();
                                      // Show message when max ads reached
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'max_ads_reached_message'.tr(
                                              namedArgs: {
                                                'count': '$maxAdsAllowed',
                                              },
                                            ),
                                          ),
                                          backgroundColor: Colors.blue.shade700,
                                          duration: const Duration(seconds: 4),
                                          behavior: SnackBarBehavior.floating,
                                          margin: EdgeInsets.all(s(16)),
                                        ),
                                      );
                                    }
                                  }
                                : () async {
                                    HapticFeedback.mediumImpact();
                                    print(
                                      '📱 DEBUG: Watch Ad button clicked for tier ${user.regionTier}',
                                    );

                                    // 🔒 Check if ads are enabled for this tier
                                    final isAdEnabled =
                                        await _isAdEnabledForTier(user);

                                    print(
                                      '📱 DEBUG: isAdEnabled = $isAdEnabled',
                                    );

                                    if (!isAdEnabled) {
                                      print(
                                        '🚫 DEBUG: Ads are BLOCKED for ${user.regionTier}',
                                      );
                                      // Ads are blocked for this tier
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ads_disabled_for_tier'.tr(),
                                            ),
                                            backgroundColor:
                                                Colors.red.shade700,
                                            duration: const Duration(
                                              seconds: 4,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                            margin: EdgeInsets.all(s(16)),
                                          ),
                                        );
                                      }
                                      return;
                                    }

                                    // ✅ Ads are enabled, show the ad
                                    print(
                                      '✅ DEBUG: Ads are ENABLED, showing ad...',
                                    );
                                    adMobService.showRewardedAd(
                                      context: context,
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isAdLoading || maxReached
                                  ? Colors.grey.withOpacity(0.4)
                                  : Colors.amber.withOpacity(0.9),
                              foregroundColor: const Color(0xFF1A1A2E),
                              padding: EdgeInsets.symmetric(
                                horizontal: s(20),
                                vertical: sv(14),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(s(12)),
                              ),
                              elevation: (_isAdLoading || maxReached) ? 0 : 4,
                              shadowColor: Colors.amber.withOpacity(0.4),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final buttonText = () {
                                  if (_isAdLoading) {
                                    return 'loading_ad'.tr();
                                  }
                                  if (maxReached) {
                                    return 'max_ads_watched'.tr();
                                  }
                                  final genCount = user.regionTier == 'tier1'
                                      ? 2
                                      : 1;
                                  return 'watch_ad_earn_generations'.tr(
                                    namedArgs: {'count': '$genCount'},
                                  );
                                }();

                                final textStyle = TextStyle(
                                  fontSize: fs(13),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                );

                                // Determine icon widget based on state
                                final iconWidget = _isAdLoading
                                    ? SizedBox(
                                        width: s(18),
                                        height: s(18),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.amber.shade700,
                                                ),
                                          ),
                                        ),
                                      )
                                    : maxReached
                                    ? SizedBox(
                                        width: s(18),
                                        height: s(18),
                                        child: Center(
                                          child: Icon(
                                            Icons.check_circle,
                                            size: s(18),
                                            color: Colors.green,
                                          ),
                                        ),
                                      )
                                    : SizedBox(
                                        width: s(23),
                                        height: s(23),
                                        child: Center(
                                          child: Icon(
                                            Icons.play_circle_filled,
                                            size: s(23),
                                            color: const Color(0xFF1A1A2E),
                                          ),
                                        ),
                                      );

                                return _buildCenteredIconTextButton(
                                  icon: iconWidget,
                                  text: AutoSizeText(
                                    buttonText,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    minFontSize: 10,
                                    style: textStyle,
                                  ),
                                  iconSize: _isAdLoading
                                      ? s(18)
                                      : maxReached
                                      ? s(18)
                                      : s(23),
                                  textMaxWidth:
                                      MediaQuery.of(context).size.width * 0.40,
                                  gap: s(6),
                                  scaleFactor: s(1),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Glassmorphic badge pill used in the daily card header.
  Widget _buildGlassBadge({
    required Widget child,
    required Gradient gradient,
    required Color borderColor,
    required Color glowColor,
    required double Function(double) s,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(8)),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(s(12)),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.25),
            blurRadius: s(10),
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  } // UPDATED: Premium Card with better text handling

  // NEW: Quick Tools Grid - RESPONSIVE
  Widget _buildQuickToolsGrid(bool isMobile) {
    final tools = [
      {
        'icon': Icons.auto_awesome,
        'label': 'home.quick_make_viral'.tr(),
        'color': Colors.amber,
        'screen': const ViralRewriteScreen(),
      },
      {
        'icon': Icons.movie_creation,
        'label': 'home.quick_shot_ideas'.tr(),
        'color': Colors.purple,
        'screen': const ShotIdeasScreen(),
      },
      {
        'icon': Icons.tag,
        'label': 'home.quick_hashtags'.tr(),
        'color': Colors.cyan,
        'screen': const HashtagGeneratorScreen(),
      },
    ];

    // On mobile, show as grid 3 columns. On larger screens, show in row
    if (isMobile) {
      return GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: tools.map((tool) {
          return _buildQuickTool(
            icon: tool['icon'] as IconData,
            label: tool['label'] as String,
            color: tool['color'] as Color,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => tool['screen'] as Widget),
            ),
            isMobile: true,
          );
        }).toList(),
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((tool) {
          return Expanded(
            child: _buildQuickTool(
              icon: tool['icon'] as IconData,
              label: tool['label'] as String,
              color: tool['color'] as Color,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => tool['screen'] as Widget),
              ),
              isMobile: false,
            ),
          );
        }).toList(),
      );
    }
  }

  // NEW: Generators Grid (2x2) - Best practices for mobile/desktop
  Widget _buildGeneratorsGrid(bool isMobile, BuildContext context) {
    final generators = [
      {
        'icon': Icons.lightbulb,
        'label': 'home.generate_ideas'.tr(),
        'color': const Color(0xFFFFD700),
        'subtitle': 'home.generate_ideas_sub'.tr(),
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IdeasListScreen()),
        ),
      },
      {
        'icon': Icons.description,
        'label': 'home.generate_scripts'.tr(),
        'color': const Color(0xFF3B82F6),
        'subtitle': 'home.generate_scripts_sub'.tr(),
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScriptGeneratorScreen()),
        ),
      },
      {
        'icon': Icons.comment,
        'label': 'home.generate_comments'.tr(),
        'color': const Color(0xFFFB923C),
        'subtitle': 'home.generate_comments_sub'.tr(),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CommentGeneratorScreen()),
          );
        },
      },
      {
        'icon': Icons.people,
        'label': 'home.youth_ideas'.tr(),
        'color': const Color(0xFFEC4899),
        'subtitle': 'home.youth_ideas_sub'.tr(),
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const IdeasListScreen(dataset: 'youth'),
          ),
        ),
      },
    ];

    // Compute aspect ratio dynamically so cards look correct on all phone sizes
    final screenWidth = MediaQuery.of(context).size.width;
    final hPadding = isMobile ? 32.0 : 48.0; // 16*2 or 24*2
    const crossSpacing = 10.0;
    final cellWidth = (screenWidth - hPadding - crossSpacing) / 2;
    // Cards need at least 108dp tall for icon + text + padding
    const minCellHeight = 108.0;
    final aspectRatio = (cellWidth / minCellHeight).clamp(1.0, 1.6);

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: aspectRatio,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: generators.map((gen) {
        return _buildGeneratorCard(
          icon: gen['icon'] as IconData,
          label: gen['label'] as String,
          subtitle: gen['subtitle'] as String,
          color: gen['color'] as Color,
          onTap: gen['onTap'] as VoidCallback,
        );
      }).toList(),
    );
  }

  // Seasonal Card - Horizontal aligned with grid
  Widget _buildSeasonalCard(bool isMobile, BuildContext context) {
    const Color seasonalColor = Color(0xFF8B5CF6);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const IdeasListScreen(dataset: 'seasonal'),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const IdeasListScreen(dataset: 'seasonal'),
              ),
            ),
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [seasonalColor, seasonalColor.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.celebration,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        'home.seasonal_ideas'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        minFontSize: 12,
                      ),
                      const SizedBox(height: 2),
                      AutoSizeText(
                        'home.seasonal_ideas_sub'.tr(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        minFontSize: 9,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Grid Generator Card - Compact & Beautiful
  Widget _buildGeneratorCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon Container - With wrapping
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 3),
                  // Text content - allow wrapping without clipping words
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AutoSizeText(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        minFontSize: 8,
                      ),
                      const SizedBox(height: 2),
                      AutoSizeText(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 9,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        minFontSize: 6,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // UPDATED: Quick Tool Card
  Widget _buildQuickTool({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 14 : 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.4)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: isMobile ? 28 : 36),
          ),
          SizedBox(height: isMobile ? 8 : 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: isMobile ? 11 : 13,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Chips wrap with proper spacing - now dynamic and clickable
  Widget _buildChipsWrap() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(
            color: core_colors.AppColors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_recentActivities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'home.recent_history_empty'.tr(),
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _recentActivities.map((item) => _buildGlassChip(item)).toList(),
    );
  }

  // Navigate to appropriate screen based on history item type
  void _navigateToHistoryItem(Map<String, dynamic> item) {
    final type = item['type'] as String;
    if (type == 'dummy') return; // Don't navigate for dummy data

    final data = item['data'] as Map<String, dynamic>;

    // Show detail modal instead of navigating
    _showDetailModal(data);
  }

  // UPDATED: Glass Chip - flexible width and clickable
  Widget _buildGlassChip(Map<String, dynamic> item) {
    final label = item['label'] as String;
    final isClickable = item['type'] != 'dummy';

    return GestureDetector(
      onTap: isClickable ? () => _navigateToHistoryItem(item) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isClickable ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withOpacity(isClickable ? 0.3 : 0.2),
          ),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  // Show detail modal for recent activity item
  void _showDetailModal(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final prompt = data['prompt'] as String? ?? '';
    final output = data['output'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};

    showModalBottomSheet(
      context: context,
      backgroundColor: core_colors.AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Title
                  AutoSizeText(
                    _getDisplayTitle(type, prompt, meta),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    minFontSize: 16,
                  ),
                  const SizedBox(height: 8),
                  AutoSizeText(
                    'home.content'.tr(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    minFontSize: 10,
                  ),
                  const SizedBox(height: 20),
                  // Content
                  _buildDetailContent(type, prompt, output, meta),
                  const SizedBox(height: 24),
                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _navigateToGenerator(type, prompt, output, meta);
                      },
                      icon: const Icon(Icons.edit),
                      label: Text('home.open_generator'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getTypeColor(type),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getDisplayTitle(
    String type,
    String prompt,
    Map<String, dynamic> meta,
  ) {
    if (type.contains('script') && meta.containsKey('idea')) {
      try {
        final ideaMap = meta['idea'] as Map<String, dynamic>;
        final title = ideaMap['title'] as String?;
        if (title != null && title.isNotEmpty) return title;
      } catch (e) {
        // Fall through
      }
    }
    return prompt.isEmpty
        ? 'home.content'.tr()
        : (prompt.length > 50 ? '${prompt.substring(0, 50)}...' : prompt);
  }

  Color _getTypeColor(String type) {
    if (type.contains('comment')) return const Color(0xFF06B6D4);
    if (type.contains('viral')) return const Color(0xFFEC4899);
    if (type.contains('hashtag')) return const Color(0xFF8B5CF6);
    if (type.contains('shot') || type.contains('short'))
      return const Color(0xFFF59E0B);
    if (type.contains('script')) return const Color(0xFFEC4899);
    if (type.contains('ai_refined')) return const Color(0xFF10B981);
    if (type.contains('idea_details')) return const Color(0xFFFBBF24);
    return const Color(0xFF6366F1);
  }

  String _normalizeCommentToneCode(String tone) {
    switch (tone.trim()) {
      // Backward compatibility for older saved history items.
      case 'Friendly':
        return 'friendly';
      case 'Engaging Comment':
      case 'Engaging':
        return 'engaging_question';
      case 'Humorous':
        return 'humorous';
      case 'Supportive':
        return 'supportive';
      case 'Thought-Provoking':
        return 'thought_provoking';
      case 'Transform to Art':
        return 'hate_to_art';
      default:
        return tone.trim();
    }
  }

  String _localizeCommentTone(String tone, {required String unknownKey}) {
    final normalized = tone.trim();
    if (normalized.isEmpty || normalized == 'Unknown') return unknownKey.tr();

    final code = _normalizeCommentToneCode(normalized);
    const supportedCodes = {
      'friendly',
      'engaging_question',
      'humorous',
      'supportive',
      'thought_provoking',
      'hate_to_art',
    };

    if (supportedCodes.contains(code)) {
      return 'comment_generator.tone_$code'.tr();
    }

    return normalized;
  }

  Widget _buildDetailContent(
    String type,
    String prompt,
    Map<String, dynamic> output,
    Map<String, dynamic> meta,
  ) {
    if (type.contains('comment')) {
      return _buildCommentDetail(output, prompt);
    } else if (type.contains('viral')) {
      return _buildViralDetail(output, prompt);
    } else if (type.contains('hashtag')) {
      return _buildHashtagDetail(output, prompt);
    } else if (type.contains('shot') || type.contains('short')) {
      return _buildShotIdeasDetail(output, prompt);
    } else if (type.contains('script')) {
      return _buildScriptDetail(output, meta);
    } else if (type.contains('youth_ideas') ||
        type.contains('seasonal_ideas')) {
      return _buildYouthSeasonalDetail(output, prompt);
    } else if (type.contains('ai_refined')) {
      return _buildAiRefinedDetail(output, prompt);
    } else if (type.contains('idea_details')) {
      return _buildIdeaDetail(output);
    }
    return _detailSection('home.content'.tr(), prompt);
  }

  Widget _buildCommentDetail(Map<String, dynamic> output, String prompt) {
    final groups = (output['groups'] as List<dynamic>?) ?? [];
    final inputText = output['inputText'] as String? ?? prompt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('history.detail.original_prompt'.tr(), inputText),
        const SizedBox(height: 20),
        ...groups.map((group) {
          final groupMap = group as Map<String, dynamic>;
          final rawTone = groupMap['tone'] as String? ?? '';
          final tone = _localizeCommentTone(
            rawTone,
            unknownKey: 'home.detail_unknown_tone',
          );
          final comments = (groupMap['comments'] as List<dynamic>?) ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoSizeText(
                tone,
                style: TextStyle(
                  color: core_colors.AppColors.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.visible,
                minFontSize: 12,
              ),
              const SizedBox(height: 8),
              ...comments.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: core_colors.AppColors.surfaceBright,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      '${entry.key + 1}. ${entry.value}',
                      style: TextStyle(
                        color: core_colors.AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildViralDetail(Map<String, dynamic> output, String prompt) {
    final rewritten =
        output['rewritten_content'] as String? ??
        output['rewritten'] as String? ??
        '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('history.detail.original_prompt'.tr(), prompt),
        const SizedBox(height: 16),
        _detailSection('history.detail.viral_rewrite'.tr(), rewritten),
      ],
    );
  }

  Widget _buildHashtagDetail(Map<String, dynamic> output, String prompt) {
    List<String> directTags = [];
    List<Map<String, dynamic>> structuredHashtags = [];
    
    // Try to get hashtags from different possible locations
    dynamic hashtagsRaw = output['hashtags'] ?? output['content'];
    
    // Normalize hashtags: could be List, String, or null
    if (hashtagsRaw is List) {
      for (final ht in hashtagsRaw) {
        if (ht is Map<String, dynamic>) {
          // Structured hashtag with category
          structuredHashtags.add(ht);
        } else if (ht is String && ht.isNotEmpty) {
          // Parse string for individual hashtags (#tag1 #tag2 or comma-separated)
          _parseHashtagString(ht, directTags);
        }
      }
    } else if (hashtagsRaw is String && hashtagsRaw.isNotEmpty) {
      // Single hashtag string: parse it for individual tags
      _parseHashtagString(hashtagsRaw, directTags);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('history.detail.original_prompt'.tr(), prompt),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoSizeText(
                'history.detail.hashtags'.tr(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: core_colors.AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: _buildHashtagPillsWidget(structuredHashtags, directTags),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build hashtag pills widget (renders hashtags as formatted pills)
  Widget _buildHashtagPillsWidget(
    List<Map<String, dynamic>> structuredHashtags,
    List<String> directTags,
  ) {
    final children = <Widget>[];

    // Handle structured hashtag maps (with category)
    if (structuredHashtags.isNotEmpty) {
      for (final item in structuredHashtags) {
        final category = (item['category'] ?? '').toString().trim();
        final tags = item['tags'] ?? item['hashtags'] ?? [];
        
        if (category.isNotEmpty || (tags is List && tags.isNotEmpty)) {
          if (children.isNotEmpty) {
            children.add(const SizedBox(height: 12));
          }

          if (category.isNotEmpty) {
            children.add(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF06B6D4).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: AutoSizeText(
                  category,
                  style: const TextStyle(
                    color: Color(0xFF06B6D4),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }

          if (tags is List && tags.isNotEmpty) {
            final tagStrings = tags
                .map((t) {
                  final str = t.toString().trim();
                  return str.startsWith('#') ? str : '#$str';
                })
                .where((t) => t.isNotEmpty)
                .toList();

            if (tagStrings.isNotEmpty) {
              children.add(const SizedBox(height: 8));
              children.add(
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tagStrings
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF06B6D4).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: AutoSizeText(
                            tag,
                            style: const TextStyle(
                              color: Color(0xFF06B6D4),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            }
          }
        }
      }
    }

    // Handle direct hashtags as pills
    if (directTags.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: directTags
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF06B6D4).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    tag,
                    style: const TextStyle(
                      color: Color(0xFF06B6D4),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    return children.isEmpty
        ? Text(
            'home.no_hashtags'.tr(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
  }

  void _parseHashtagString(String input, List<String> tags) =>
      HashtagParser.parseInto(input, tags);

  Widget _buildShotIdeasDetail(Map<String, dynamic> output, String prompt) {
    final content = output['content'];
    List<dynamic> ideas = [];

    if (content is List) {
      ideas = content;
    } else if (content is String && content.isNotEmpty) {
      ideas = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
    } else {
      ideas = (output['ideas'] as List<dynamic>?) ?? [];
    }

    final ideas_text = ideas
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('history.detail.original_prompt'.tr(), prompt),
        const SizedBox(height: 16),
        _detailSection(
          'history.detail.ideas_created'.tr(),
          '${ideas.length} ${'home.detail_ideas_count'.tr()}',
        ),
        const SizedBox(height: 16),
        _detailSection('history.detail.content'.tr(), ideas_text),
      ],
    );
  }

  Widget _buildScriptDetail(
    Map<String, dynamic> output,
    Map<String, dynamic> meta,
  ) {
    final hook = output['hook'] as String? ?? '';
    final cta = output['cta'] as String? ?? '';
    final hashtags = output['hashtags'] as List? ?? [];
    final shots = (output['shots'] as List?) ?? [];
    final voiceovers = (output['voiceover'] as List?) ?? [];

    // Extract idea details from meta if available
    String? ideaTitle;
    String? ideaDescription;
    if (meta.containsKey('idea')) {
      try {
        final ideaMap = meta['idea'] as Map<String, dynamic>;
        ideaTitle = ideaMap['title'] as String?;
        ideaDescription = ideaMap['description'] as String?;
      } catch (e) {
        // Fall back if parsing fails
      }
    }

    // Format shots list
    String shotsText = '';
    if (shots.isNotEmpty) {
      shotsText = shots
          .asMap()
          .entries
          .map((e) {
            final shot = e.value;
            if (shot is Map<String, dynamic>) {
              final duration = shot['duration'] as String? ?? '';
              final description = shot['description'] as String? ?? '';
              return '${e.key + 1}. [${duration}]\n$description';
            }
            return '${e.key + 1}. ${shot.toString()}';
          })
          .join('\n\n');
    }

    // Format voiceover list
    String voiceoverText = '';
    if (voiceovers.isNotEmpty) {
      voiceoverText = voiceovers
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n\n');
    }

    // Format hashtags list
    String hashtagsText = hashtags.isNotEmpty
        ? hashtags.join(' ')
        : 'home.no_hashtags'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ideaTitle != null && ideaTitle.isNotEmpty) ...[
          _detailSection('home.detail_idea_title'.tr(), ideaTitle),
          const SizedBox(height: 16),
        ],
        if (ideaDescription != null && ideaDescription.isNotEmpty) ...[
          _detailSection('home.detail_idea_description'.tr(), ideaDescription),
          const SizedBox(height: 16),
        ],
        if (hook.isNotEmpty) ...[
          _detailSection('home.detail_hook'.tr(), hook),
          const SizedBox(height: 16),
        ],
        if (shotsText.isNotEmpty) ...[
          _detailSection(
            'home.detail_scenes'.tr(args: [shots.length.toString()]),
            shotsText,
          ),
          const SizedBox(height: 16),
        ],
        if (voiceoverText.isNotEmpty) ...[
          _detailSection(
            'home.detail_voiceover'.tr(args: [voiceovers.length.toString()]),
            voiceoverText,
          ),
          const SizedBox(height: 16),
        ],
        if (cta.isNotEmpty) ...[
          _detailSection('home.detail_cta'.tr(), cta),
          const SizedBox(height: 16),
        ],
        _detailSection('home.detail_hashtags'.tr(), hashtagsText),
      ],
    );
  }

  Widget _buildAiRefinedDetail(Map<String, dynamic> output, String prompt) {
    final refinedTitle = output['refined_title'] as String? ?? '';
    final refinedDescription = output['refined_description'] as String? ?? '';
    final refinedSteps = output['refined_steps'] as List? ?? [];
    final refinedCta = output['refined_cta'] as String? ?? '';
    final refinedLevel = output['refined_level'] as String? ?? '';

    final stepsText = refinedSteps.isNotEmpty
        ? refinedSteps
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n')
        : 'home.no_steps'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('home.detail_original_idea'.tr(), prompt),
        const SizedBox(height: 16),
        if (refinedTitle.isNotEmpty) ...[
          _detailSection('home.detail_refined_title'.tr(), refinedTitle),
          const SizedBox(height: 16),
        ],
        if (refinedDescription.isNotEmpty) ...[
          _detailSection(
            'home.detail_refined_description'.tr(),
            refinedDescription,
          ),
          const SizedBox(height: 16),
        ],
        if (refinedSteps.isNotEmpty) ...[
          _detailSection('home.detail_refined_steps'.tr(), stepsText),
          const SizedBox(height: 16),
        ],
        if (refinedCta.isNotEmpty) ...[
          _detailSection('home.detail_refined_cta'.tr(), refinedCta),
          const SizedBox(height: 16),
        ],
        if (refinedLevel.isNotEmpty) ...[
          _detailSection('home.detail_refined_level'.tr(), refinedLevel),
        ],
      ],
    );
  }

  Widget _buildYouthSeasonalDetail(Map<String, dynamic> output, String prompt) {
    final title = output['title'] as String? ?? '';
    final description = output['description'] as String? ?? '';
    final niche = output['niche'] as String? ?? '';
    final format = output['format'] as String? ?? '';
    final level = output['level'] as String? ?? '';
    final steps = output['steps'] as List? ?? [];
    final cta = output['cta'] as String? ?? '';

    final stepsText = steps.isNotEmpty
        ? steps
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n')
        : 'home.no_steps'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          _detailSection('home.detail_idea_title'.tr(), title),
          const SizedBox(height: 16),
        ],
        if (description.isNotEmpty) ...[
          _detailSection('home.detail_description'.tr(), description),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            if (niche.isNotEmpty)
              Expanded(child: _detailSection('home.detail_niche'.tr(), niche)),
            if (format.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _detailSection('home.detail_format'.tr(), format),
              ),
            ],
            if (level.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(child: _detailSection('home.detail_level'.tr(), level)),
            ],
          ],
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailSection('home.detail_steps'.tr(), stepsText),
        ],
        if (cta.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailSection('home.detail_cta'.tr(), cta),
        ],
      ],
    );
  }

  Widget _buildIdeaDetail(Map<String, dynamic> output) {
    // Check if this is a script generated from an idea (will have hook, shots, etc.)
    final hook = output['hook'] as String? ?? '';
    final hasScriptOutput = hook.isNotEmpty;

    if (hasScriptOutput) {
      // This is a script generated from a predefined idea - display as script
      final cta = output['cta'] as String? ?? '';
      final hashtags = output['hashtags'] as List? ?? [];
      final shots = (output['shots'] as List?) ?? [];
      final voiceovers = (output['voiceover'] as List?) ?? [];

      // Format shots list
      String shotsText = '';
      if (shots.isNotEmpty) {
        shotsText = shots
            .asMap()
            .entries
            .map((e) {
              final shot = e.value;
              if (shot is Map<String, dynamic>) {
                final duration = shot['duration'] as String? ?? '';
                final description = shot['description'] as String? ?? '';
                return '${e.key + 1}. [${duration}]\n$description';
              }
              return '${e.key + 1}. ${shot.toString()}';
            })
            .join('\n\n');
      }

      // Format voiceover list
      String voiceoverText = '';
      if (voiceovers.isNotEmpty) {
        voiceoverText = voiceovers
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n\n');
      }

      // Format hashtags list
      String hashtagsText = hashtags.isNotEmpty
          ? hashtags.join(' ')
          : 'home.no_hashtags'.tr();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hook.isNotEmpty) ...[
            _detailSection('home.detail_hook'.tr(), hook),
            const SizedBox(height: 16),
          ],
          if (shotsText.isNotEmpty) ...[
            _detailSection(
              'home.detail_scenes'.tr(args: [shots.length.toString()]),
              shotsText,
            ),
            const SizedBox(height: 16),
          ],
          if (voiceoverText.isNotEmpty) ...[
            _detailSection(
              'home.detail_voiceover'.tr(args: [voiceovers.length.toString()]),
              voiceoverText,
            ),
            const SizedBox(height: 16),
          ],
          if (cta.isNotEmpty) ...[
            _detailSection('home.detail_cta'.tr(), cta),
            const SizedBox(height: 16),
          ],
          _detailSection('home.detail_hashtags'.tr(), hashtagsText),
        ],
      );
    } else {
      // This is a regular predefined idea - display idea details
      final title = output['title'] as String? ?? '';
      final description = output['description'] as String? ?? '';
      final niche = output['niche'] as String? ?? '';
      final format = output['format'] as String? ?? '';
      final level = output['level'] as String? ?? '';
      final steps = output['steps'] as List? ?? [];
      final cta = output['cta'] as String? ?? '';

      final stepsText = steps.isNotEmpty
          ? steps
                .asMap()
                .entries
                .map((e) => '${e.key + 1}. ${e.value}')
                .join('\n')
          : 'home.no_steps'.tr();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            _detailSection('home.detail_idea_title'.tr(), title),
            const SizedBox(height: 16),
          ],
          if (description.isNotEmpty) ...[
            _detailSection('home.detail_description'.tr(), description),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              if (niche.isNotEmpty)
                Expanded(
                  child: _detailSection('home.detail_niche'.tr(), niche),
                ),
              if (format.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _detailSection('home.detail_format'.tr(), format),
                ),
              ],
              if (level.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _detailSection('home.detail_level'.tr(), level),
                ),
              ],
            ],
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('home.detail_steps'.tr(), stepsText),
          ],
          if (cta.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('home.detail_cta'.tr(), cta),
          ],
        ],
      );
    }
  }

  List<InlineSpan> _buildStyledDetailSpans(String value) {
    final spans = <InlineSpan>[];
    final normalized = value
        .split('\n')
        .map(
          (line) => line.replaceFirst(RegExp(r'^(\s*\d+\.\s*)\d+\.\s+'), r'$1'),
        )
        .join('\n');
    // Updated regex to support Unicode letters (Cyrillic, Arabic, etc.)
    final exp = HashtagParser.inlineFormatPattern;
    int start = 0;

    for (final match in exp.allMatches(normalized)) {
      if (match.start > start) {
        spans.add(TextSpan(text: normalized.substring(start, match.start)));
      }

      if (match.group(1) != null) {
        // Bold Markdown
        spans.add(
          TextSpan(
            text: match.group(1) ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF06B6D4),
            ),
          ),
        );
      } else if (match.group(2) != null) {
        // Hashtag match
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.only(right: 4, bottom: 4, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF06B6D4).withOpacity(0.3),
                ),
              ),
              child: Text(
                HashtagParser.cleanToken(match.group(2)!),
                style: const TextStyle(
                  color: Color(0xFF06B6D4),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        );
      }
      start = match.end;
    }

    if (start < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(start)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: normalized));
    }

    return spans;
  }

  Widget _detailSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoSizeText(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.visible,
          minFontSize: 10,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: core_colors.AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          ),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 14,
                height: 1.6,
              ),
              children: _buildStyledDetailSpans(value.isEmpty ? 'N/A' : value),
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToGenerator(
    String type,
    String prompt,
    Map<String, dynamic> output,
    Map<String, dynamic> meta,
  ) {
    if (type.contains('comment')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommentGeneratorScreen(initialInput: prompt),
        ),
      );
    } else if (type.contains('viral')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViralRewriteScreen(initialInput: prompt),
        ),
      );
    } else if (type.contains('hashtag')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HashtagGeneratorScreen(initialInput: prompt),
        ),
      );
    } else if (type.contains('shot') || type.contains('short')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShotIdeasScreen(initialInput: prompt),
        ),
      );
    } else if (type.contains('script')) {
      if (meta.containsKey('idea')) {
        try {
          final ideaMap = Map<String, dynamic>.from(meta['idea'] as Map);
          final idea = IdeaModel.fromMap(ideaMap);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ScriptGeneratorScreen(idea: idea, initialPrompt: prompt),
            ),
          );
        } catch (e) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScriptGeneratorScreen(initialPrompt: prompt),
            ),
          );
        }
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScriptGeneratorScreen(initialPrompt: prompt),
          ),
        );
      }
    } else if (type.contains('idea_details') || type.contains('ai_refined')) {
      if (meta.containsKey('idea')) {
        try {
          final ideaMap = Map<String, dynamic>.from(meta['idea'] as Map);
          final idea = IdeaModel.fromMap(ideaMap);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IdeaDetailsScreen(idea: idea)),
          );
        } catch (e) {
          // Fallback
        }
      }
    }
  }
}
