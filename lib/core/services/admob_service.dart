import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'reward_service.dart';

class AdMobService {
  BannerAd? bannerAd;
  bool isBannerLoaded = false;
  bool rewardEarned = false;
  bool rewardProcessing = false;
  RewardedAd? rewardedAd;
  bool isRewardedAdLoaded = false;
  bool isAdLoading = false;

  // Callback functions for UI feedback
  Function(bool isLoading)? onLoadingStateChanged;
  Function(String message, Color color)? onMessageShown;

  /// Load a banner ad (test mode)
  void loadBanner({VoidCallback? onLoaded}) {
    // Dispose previous banner if exists
    bannerAd?.dispose();
    isBannerLoaded = false;

    bannerAd = BannerAd(
      // Official Google test banner ad unit ID
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          print('✅ Banner ad loaded successfully');
          isBannerLoaded = true;
          if (onLoaded != null) onLoaded();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          print(
            '⚠️ Banner ad failed to load: Code ${error.code}, Msg: ${error.message}',
          );
          ad.dispose();
          bannerAd = null;
          isBannerLoaded = false;
          // Do NOT retry automatically - wait for explicit request
        },
      ),
    )..load();
  }

  /// Dispose banner ad
  void disposeBanner() {
    bannerAd?.dispose();
    bannerAd = null;
    isBannerLoaded = false;
  }

  /// Load a rewarded ad (test mode)
  /// Automatically retries up to maxRetries times if loading fails
  /// Notifies UI of loading state changes
  /// [showErrorMessage] - If true, shows snackbar on failure (set false for background loading)
  Future<bool> loadRewardedAd({
    int maxRetries = 3,
    int retryDelayMs = 2000,
    bool showErrorMessage = false,
  }) async {
    // Dispose previous rewarded ad if exists
    rewardedAd?.dispose();
    isRewardedAdLoaded = false;
    isAdLoading = true;
    onLoadingStateChanged?.call(true);

    int attempt = 0;
    while (attempt < maxRetries && !isRewardedAdLoaded) {
      attempt++;
      print('🔄 Loading rewarded ad (attempt $attempt/$maxRetries)...');

      try {
        await RewardedAd.load(
          // Official Google test rewarded ad unit ID
          adUnitId: 'ca-app-pub-3940256099942544/5224354917',
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              print('✅ Rewarded ad loaded successfully on attempt $attempt');
              rewardedAd = ad;
              isRewardedAdLoaded = true;
              isAdLoading = false;
              onLoadingStateChanged?.call(false);
            },
            onAdFailedToLoad: (error) {
              print(
                '⚠️ Rewarded ad failed to load (attempt $attempt): ${error.message}',
              );
              rewardedAd = null;
              isRewardedAdLoaded = false;
            },
          ),
        );

        // Wait a bit to see if ad loaded
        await Future.delayed(Duration(milliseconds: 500));

        if (isRewardedAdLoaded) {
          print('✅ Rewarded ad ready after $attempt attempt(s)');
          break;
        }

        // If not loaded and not last attempt, wait before retry
        if (attempt < maxRetries && !isRewardedAdLoaded) {
          print('⏳ Waiting ${retryDelayMs}ms before retry...');
          await Future.delayed(Duration(milliseconds: retryDelayMs));
        }
      } catch (e) {
        print('❌ Exception loading rewarded ad (attempt $attempt): $e');
        if (attempt >= maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: retryDelayMs));
      }
    }

    isAdLoading = false;
    onLoadingStateChanged?.call(false);

    // Only show error message if:
    // 1. showErrorMessage is true (user clicked button, not background loading)
    // 2. AND ad really failed to load
    if (!isRewardedAdLoaded) {
      print('❌ Failed to load rewarded ad after $maxRetries attempts');
      if (showErrorMessage) {
        onMessageShown?.call('general.ad_failed_to_load', Colors.red);
      }
      return false;
    }
    print('✅ Rewarded ad loaded successfully');
    return true;
  }

  /// Show rewarded ad and claim reward
  /// Returns the grant token if successful, null otherwise
  Future<String?> showRewardedAd({
    required BuildContext context,
    VoidCallback? onRewarded,
  }) async {
    print('╔════════════════════════════════════════════════════════════════╗');
    print('║         🎬 STARTING REWARDED AD FLOW                          ║');
    print('║ Time: ${DateTime.now().toIso8601String()}');
    print('╚════════════════════════════════════════════════════════════════╝');

    if (!isRewardedAdLoaded || rewardedAd == null) {
      // Attempt to load ad - ONLY show error if this user-initiated load fails
      print('⚠️  Ad not loaded, attempting to load...');
      isAdLoading = true;
      onLoadingStateChanged?.call(true);

      final loaded = await loadRewardedAd(showErrorMessage: true);

      // If still not loaded after single attempt, show error and return
      if (!loaded || !isRewardedAdLoaded || rewardedAd == null) {
        print('❌ Ad failed to load');
        isAdLoading = false;
        onLoadingStateChanged?.call(false);
        print(
          '╔════════════════════════════════════════════════════════════════╗',
        );
        print('║ ❌ REWARDED AD FLOW FAILED - Ad Load Error');
        print(
          '╚════════════════════════════════════════════════════════════════╝',
        );
        return null;
      }
    }

    // Use a Completer to properly wait for the reward callback
    final completer = Completer<String?>();

    // Set full screen content callback
    rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        print('👋 [AdMob] Ad dismissed');

        ad.dispose();
        rewardedAd = null;
        isRewardedAdLoaded = false;

        // 🔥 CRITICAL FIX
        if (!completer.isCompleted && !rewardEarned && !rewardProcessing) {
          print('⚠️ No reward earned — completing null');
          completer.complete(null);
        } else {
          print('✅ Dismiss ignored (reward already handled or processing)');
        }

        loadRewardedAd(maxRetries: 3);
      },

      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        rewardedAd = null;
        isRewardedAdLoaded = false;

        if (!completer.isCompleted && !rewardProcessing) {
          completer.complete(null);
        }
      },
    );

    // Show the ad and wait for completion
    try {
      print('🎬 [AdMob] Showing rewarded ad now...');
      final startTime = DateTime.now();

      await rewardedAd!.show(
        onUserEarnedReward: (ad, reward) async {
          rewardEarned = true;
          rewardProcessing = true;

          print('✅ [AdMob] USER EARNED REWARD CALLBACK FIRED');

          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final random = (DateTime.now().microsecond % 10000)
                .toString()
                .padLeft(5, '0');
            final randomSuffix = (timestamp % 100000).toString().padLeft(
              5,
              '0',
            );

            String rewardId = '${reward.type}_${timestamp}_${randomSuffix}';
            String rewardToken = '${timestamp}_${random}_${reward.amount}';

            String? grantToken = await rewardService.claimReward(
              rewardId: rewardId,
              rewardToken: rewardToken,
            );

            if (grantToken != null) {
              await rewardService.storeRewardToken(grantToken);

              onMessageShown?.call('general.reward_granted', Colors.green);

              if (!completer.isCompleted) {
                completer.complete(grantToken);
              }

              onRewarded?.call();
            } else {
              // 🔥 IMPORTANT: do NOT lose reward
              print(
                '⚠️ Backend failed, but reward was earned — preserving success',
              );

              if (!completer.isCompleted) {
                completer.complete("LOCAL_REWARD_FALLBACK");
              }

              onMessageShown?.call('general.reward_granted', Colors.green);
            }
          } catch (e) {
            print('❌ Error during reward processing: $e');

            // 🔥 STILL do not lose reward
            if (!completer.isCompleted) {
              completer.complete("LOCAL_REWARD_FALLBACK");
            }
          } finally {
            rewardProcessing = false;

            isAdLoading = false;
            onLoadingStateChanged?.call(false);
          }
        },
      );

      // Wait for the completer to finish (either reward claimed or ad dismissed)
      print('⏳ [AdMob] Waiting for ad completion...');
      final result = await completer.future;
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      print(
        '╔════════════════════════════════════════════════════════════════╗',
      );
      if (result != null) {
        print(
          '║ ✅ REWARDED AD FLOW COMPLETED SUCCESSFULLY                   ║',
        );
        print('║ Result Token: ${result.substring(0, 10)}...');
      } else {
        print(
          '║ ⚠️  REWARDED AD FLOW COMPLETED - NO REWARD GRANTED          ║',
        );
      }
      print('║ Duration: ${duration.inMilliseconds}ms');
      print('║ End Time: ${endTime.toIso8601String()}');
      print(
        '╚════════════════════════════════════════════════════════════════╝',
      );

      isAdLoading = false;
      onLoadingStateChanged?.call(false);

      return result;
    } catch (e) {
      print('❌ [AdMob] Error showing rewarded ad: $e');
      print('   └─ Stack Trace: $e');
      rewardedAd?.dispose();
      rewardedAd = null;
      isRewardedAdLoaded = false;
      isAdLoading = false;
      onLoadingStateChanged?.call(false);
      print(
        '╔════════════════════════════════════════════════════════════════╗',
      );
      print('║ ❌ REWARDED AD FLOW FAILED - Exception');
      print('║ Error: $e');
      print(
        '╚════════════════════════════════════════════════════════════════╝',
      );
      return null;
    }
  }

  /// Dispose rewarded ad
  void disposeRewardedAd() {
    rewardedAd?.dispose();
    rewardedAd = null;
    isRewardedAdLoaded = false;
  }

  /// Initialize - preload ads
  void init() {
    loadBanner();
    loadRewardedAd();
  }

  /// Dispose all ads
  void disposeAll() {
    disposeBanner();
    disposeRewardedAd();
  }
}

/// Singleton instance
final adMobService = AdMobService();
