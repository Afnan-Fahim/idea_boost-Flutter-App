// lib/modules/quick_tools/view/hashtag_generator_screen.dart
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/services/admob_service.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/modules/quick_tools/view_model/hashtag_generator_view_model.dart';
import 'package:provider/provider.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';

class HashtagGeneratorScreen extends StatefulWidget {
  final String? initialInput;
  final String? initialRewardToken;
  const HashtagGeneratorScreen({
    Key? key,
    this.initialInput,
    this.initialRewardToken,
  }) : super(key: key);

  @override
  State<HashtagGeneratorScreen> createState() => _HashtagGeneratorScreenState();
}

class _HashtagGeneratorScreenState extends State<HashtagGeneratorScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isButtonDebouncing = false;

  // Streaming text animation
  bool _isOutputStreaming = false;
  String _displayedOutput = '';
  Timer? _streamTimer;
  String? _lastStreamedOutput;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;
  bool _shimmerRunning = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerAnim = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialInput != null && widget.initialInput!.isNotEmpty) {
        _textController.text = widget.initialInput!;
        final vm = Provider.of<HashtagGeneratorViewModel>(
          context,
          listen: false,
        );
        vm.updateInput(widget.initialInput!);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _shimmerCtrl.dispose();
    _streamTimer?.cancel();
    super.dispose();
  }

  // ======================== STREAMING ========================
  void _startStreamingText(String output) {
    if (_lastStreamedOutput == output) return;
    _lastStreamedOutput = output;
    _streamTimer?.cancel();
    _displayedOutput = '';
    setState(() {
      _isOutputStreaming = true;
    });
    int charIdx = 0;
    _streamTimer = Timer.periodic(const Duration(milliseconds: 18), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (charIdx >= output.length) {
        setState(() {
          _isOutputStreaming = false;
        });
        timer.cancel();
        // 🔄 Issue #3 fix: Refresh user limits from server after generation.
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          try {
            final notifier = context.read<UserNotifier>();
            notifier.reload(forceServer: true);
          } catch (_) {}
        });
        return;
      }
      final end = (charIdx + 6).clamp(0, output.length);
      setState(() {
        _displayedOutput = output.substring(0, end);
      });
      charIdx = end;
    });
  }

  // ======================== DIALOGS (unchanged logic) ========================
  void _showLimitExceededDialog(
    BuildContext context,
    HashtagGeneratorViewModel vm, {
    bool isPro = false,
  }) {
    if (isPro) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.warning,
                        AppColors.warning.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                AutoSizeText(
                  'errors.pro_daily_limit_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 16,
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'errors.pro_daily_limit_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 12,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'general.ok'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.warning,
                        AppColors.warning.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                AutoSizeText(
                  'hashtag_generator.limit_dialog_title'.tr(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 18,
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'hashtag_generator.limit_dialog_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 12,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await adMobService.showRewardedAd(
                            context: context,
                            onRewarded: () {
                              showSnackBarSafe(
                                context,
                                SnackBar(
                                  content: Text(
                                    'hashtag_generator.snack_reward'.tr(),
                                  ),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: BorderSide(
                            color: AppColors.success.withOpacity(0.3),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_circle_outline, size: 20),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'hashtag_generator.reward_button'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          showSnackBarSafe(
                            context,
                            SnackBar(
                              content: Text(
                                'hashtag_generator.snack_pro_navigating'.tr(),
                              ),
                              backgroundColor: AppColors.accent,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'hashtag_generator.go_pro_button'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAbuseContentDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.error,
                        AppColors.error.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                AutoSizeText(
                  'general.content_blocked'.tr(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 18,
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.visible,
                  minFontSize: 12,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'general.understood'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message, {Color? color}) {
    showSnackBarSafe(
      context,
      SnackBar(
        content: Center(child: Text(message, textAlign: TextAlign.center)),
        backgroundColor: color ?? AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyHashtags(BuildContext context, String hashtags) {
    Clipboard.setData(ClipboardData(text: hashtags)).then((_) {
      _showFeedback(
        context,
        'hashtag_generator.snack_copy'.tr(),
        color: AppColors.success,
      );
    });
  }

  // ======================== FORMAT PARSER ========================
  List<InlineSpan> _parseFormattedText(String text, Color accentColor) {
    final spans = <InlineSpan>[];
    // Matches **bold text** or #hashtags (including non-Latin characters)
    // Updated regex: #[^\s]+ matches # followed by any non-whitespace characters
    final regex = RegExp(r'\*\*(.*?)\*\*|(#[^\s]+)', unicode: true);
    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        // Bold match
        spans.add(
          TextSpan(
            text: match.group(1),
            style: TextStyle(fontWeight: FontWeight.w700, color: accentColor),
          ),
        );
      } else if (match.group(2) != null) {
        // Hashtag match -> Render as a beautiful pill
        var hashtag = match.group(2)!;
        // Clean trailing punctuation except # at start
        hashtag = hashtag.replaceAll(RegExp(r'[^\w#]$', unicode: true), '');
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.only(right: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Text(
                hashtag,
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        );
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  // ======================== BUILD ========================
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HashtagGeneratorViewModel(
        Provider.of<UserRepository>(context, listen: false),
        initialRewardToken: widget.initialRewardToken,
      ),
      child: Consumer<HashtagGeneratorViewModel>(
        builder: (context, vm, child) {
          // Shimmer control
          if (vm.isLoading && vm.output == null) {
            if (!_shimmerRunning) {
              _shimmerCtrl.repeat();
              _shimmerRunning = true;
            }
          } else if (_shimmerRunning) {
            _shimmerCtrl.stop();
            _shimmerRunning = false;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final error = vm.errorMessage;
            if (error != null) {
              if (error.contains('errors.content_blocked_ai') ||
                  error.contains('errors.content_violates_safety')) {
                vm.clearError();
                _showAbuseContentDialog(context, error.tr());
              } else {
                _showFeedback(context, error.tr(), color: AppColors.error);
                vm.clearError();
              }
            }
            // Stream output text
            if (vm.output != null && !vm.isLoading) {
              _startStreamingText(vm.output!);
            }
          });

          final isLocked = vm.isLoading || _isOutputStreaming;

          return PopScope(
            canPop: !isLocked,
            onPopInvoked: (didPop) {
              if (isLocked) return;
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF131316),
              resizeToAvoidBottomInset: true,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(0),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                ),
              ),
              body: AbsorbPointer(
                absorbing: isLocked,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF131316), Color(0xFF0D0D10)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        // ─── Top Bar ───
                        _buildTopBar(context, vm),

                        // ─── Content ───
                        Expanded(
                          child: vm.isLoading && vm.output == null
                              ? _buildSkeletonLoader()
                              : vm.output == null
                              ? _buildEmptyState()
                              : _buildResultsView(context, vm),
                        ),

                        // ─── Input Bar (pre-generation) ───
                        if (vm.output == null) _buildInputBar(context, vm),

                        // ─── Bottom bar (post-generation) ───
                        if (vm.output != null && !vm.isLoading)
                          _buildBottomBar(context, vm),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ======================== TOP BAR ========================
  Widget _buildTopBar(BuildContext context, HashtagGeneratorViewModel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (vm.isLoading) return;
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  'hashtag_generator.title'.tr(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  minFontSize: 13,
                ),
                if (vm.isLoading)
                  AutoSizeText(
                    'hashtag_generator.generating'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    minFontSize: 10,
                  ),
              ],
            ),
          ),
          if (vm.output != null && !vm.isLoading) ...[
            _topBarIcon(
              icon: Icons.copy_all_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                _copyHashtags(context, vm.output!);
              },
            ),
            const SizedBox(width: 8),
            _topBarIcon(
              icon: vm.isFavorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: vm.isFavorited ? AppColors.error : Colors.white60,
              onTap: () async {
                HapticFeedback.mediumImpact();
                if (vm.isFavorited) {
                  await vm.removeFromFavorites();
                  if (mounted) {
                    _showFeedback(
                      context,
                      'general.removed_from_favorites'.tr(),
                      color: Colors.grey,
                    );
                  }
                } else {
                  final result = await vm.saveToFavorites();
                  if (mounted) {
                    final message = result == SaveFavoriteResult.alreadyExists
                        ? 'general.snack_already_saved'.tr()
                        : 'general.snack_saved'.tr();
                    final color = result == SaveFavoriteResult.alreadyExists
                        ? AppColors.warning
                        : AppColors.success;
                    _showFeedback(context, message, color: color);
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBarIcon({
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, size: 18, color: color ?? Colors.white60),
      ),
    );
  }

  // ======================== EMPTY STATE ========================
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tag_rounded,
                color: AppColors.success,
                size: 28,
              ),
            ),
            const SizedBox(height: 24),
            AutoSizeText(
              'hashtag_generator.input_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.35,
                letterSpacing: -0.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.visible,
              minFontSize: 18,
            ),
            const SizedBox(height: 12),
            AutoSizeText(
              'hashtag_generator.input_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.35),
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.visible,
              minFontSize: 11,
            ),
            const SizedBox(height: 28),
            AutoSizeText(
              'hashtag_generator.supports'.tr(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.visible,
              minFontSize: 9,
            ),
          ],
        ),
      ),
    );
  }

  // ======================== SKELETON LOADER ========================
  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI avatar + typing dots
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.success.withOpacity(0.35),
                        AppColors.success.withOpacity(0.12),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.tag_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                _HashtagTypingDots(),
              ],
            ),
            const SizedBox(height: 24),
            _shimmerBar(double.infinity, 14, _shimmerAnim.value),
            const SizedBox(height: 12),
            _shimmerBar(280, 14, _shimmerAnim.value),
            const SizedBox(height: 12),
            _shimmerBar(220, 14, _shimmerAnim.value),
            const SizedBox(height: 12),
            _shimmerBar(300, 14, _shimmerAnim.value),
            const SizedBox(height: 12),
            _shimmerBar(180, 14, _shimmerAnim.value),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBar(double width, double height, double animVal) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(
          begin: Alignment(animVal - 1, 0),
          end: Alignment(animVal, 0),
          colors: [
            Colors.white.withOpacity(0.04),
            Colors.white.withOpacity(0.09),
            Colors.white.withOpacity(0.04),
          ],
        ),
      ),
    );
  }

  // ======================== RESULTS VIEW ========================
  Widget _buildResultsView(BuildContext context, HashtagGeneratorViewModel vm) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // User prompt bubble
        if (vm.input.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
                border: Border.all(color: AppColors.success.withOpacity(0.1)),
              ),
              child: Text(
                vm.input,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // AI Response
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, value, ch) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)),
                child: ch,
              ),
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI avatar
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withOpacity(0.35),
                      AppColors.success.withOpacity(0.12),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tag_rounded,
                  size: 14,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText.rich(
                        TextSpan(
                          children: _parseFormattedText(
                            _displayedOutput.isNotEmpty
                                ? _displayedOutput
                                : vm.output ?? '',
                            AppColors.success,
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ======================== INPUT BAR ========================
  Widget _buildInputBar(BuildContext context, HashtagGeneratorViewModel vm) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: IgnorePointer(
                  ignoring: vm.isLoading,
                  child: TextField(
                    controller: _textController,
                    onChanged: vm.updateInput,
                    maxLines: 4,
                    minLines: 1,
                    readOnly: vm.isLoading,
                    enableInteractiveSelection: !vm.isLoading,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'hashtag_generator.input_hint'.tr(),
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.28),
                        fontSize: 14,
                      ),
                      hintMaxLines: 1,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    ),
                  ),
                ),
              ),
              // Bottom controls
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 10, 10),
                child: Row(
                  children: [
                    const Spacer(),
                    // Send button
                    GestureDetector(
                      onTap:
                          (vm.input.isEmpty ||
                              vm.isLoading ||
                              _isButtonDebouncing)
                          ? null
                          : () async {
                              if (_isButtonDebouncing) return;
                              setState(() => _isButtonDebouncing = true);
                              FocusScope.of(context).unfocus();
                              await Future.delayed(
                                const Duration(milliseconds: 100),
                              );
                              HapticFeedback.mediumImpact();
                              await vm.generateHashtags(
                                language: getAppLanguageCode(context),
                                locale: getValidOsLocale(),
                              );
                              if (mounted) {
                                setState(() => _isButtonDebouncing = false);
                              }
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: vm.input.isNotEmpty && !vm.isLoading
                              ? AppColors.success
                              : Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: vm.isLoading
                            ? Padding(
                                padding: const EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                                color: vm.input.isNotEmpty
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.2),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ======================== BOTTOM BAR ========================
  Widget _buildBottomBar(BuildContext context, HashtagGeneratorViewModel vm) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF131316).withOpacity(0.95),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: Row(
          children: [
            // Regenerate
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    vm.regenerate(
                      language: getAppLanguageCode(context),
                      locale: getValidOsLocale(),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [const Icon(Icons.refresh_rounded, size: 18)],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Copy All
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _copyHashtags(context, vm.output!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.content_copy_rounded, size: 16)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================== TYPING DOTS ========================
class _HashtagTypingDots extends StatefulWidget {
  @override
  State<_HashtagTypingDots> createState() => _HashtagTypingDotsState();
}

class _HashtagTypingDotsState extends State<_HashtagTypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _sinApprox(double x) =>
      x - (x * x * x) / 6.0 + (x * x * x * x * x) / 120.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final bounce = _sinApprox(t * 3.14159);
            return Container(
              margin: EdgeInsetsDirectional.only(end: index < 2 ? 5 : 0),
              child: Transform.translate(
                offset: Offset(0, -3.5 * bounce),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.35 + 0.45 * bounce),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
