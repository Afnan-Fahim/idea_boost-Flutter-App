// lib/core/services/user_access_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:ideaboost/data/models/user_model.dart';

/// User Access Service
/// Manages real-time access control based on Firestore user data
class UserAccessService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Stream user data in real-time
  // Stream<UserModel?> getUserStream() {
  //   final uid = currentUserId;
  //   if (uid == null) return Stream.value(null);

  //   return _db.collection('users').doc(uid).snapshots().map((doc) {
  //     if (!doc.exists) return null;
  //     return UserModel.fromFirestore(doc);
  //   });
  // }

  /// Get current user data (one-time fetch)
  Future<UserModel?> getCurrentUser() async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Error fetching user: $e');
      return null;
    }
  }

  /// Check if user has trial available
  Future<bool> hasTrialAvailable() async {
    final user = await getCurrentUser();
    if (user == null) return false;
    return !user.hasUsedTrial;
  }

  /// Check if user is PRO
  Future<bool> isPro() async {
    final user = await getCurrentUser();
    if (user == null) return false;
    return user.plan.toLowerCase() == 'pro';
  }

  /// Get daily limits based on region tier
  Map<String, int> getDailyLimits(String regionTier) {
    switch (regionTier) {
      case 'tier1':
        return {
          'dailyAiLimit': 10,
          'dailyRewardedLimit': 10,
          'dailyAiPerReward': 2,
        };
      case 'tier2':
        return {
          'dailyAiLimit': 8,
          'dailyRewardedLimit': 8,
          'dailyAiPerReward': 2,
        };
      case 'tier3':
      default:
        return {
          'dailyAiLimit': 5,
          'dailyRewardedLimit': 5,
          'dailyAiPerReward': 1,
        };
    }
  }

  Future<Map<String, dynamic>> getAccessStatus() async {
    final user = await getCurrentUser();

    if (user == null) {
      return {
        'accessMethod': 'blocked',
        'requiresAd': false,
        'message': 'errors.user_not_found'.tr(),
      };
    }

    // PRO users: check trial first, then phased access
    // PRO subscription is ONLY available for tier1 (per spec Section 3.4)
    if (user.plan.toLowerCase() == 'pro' && user.regionTier == 'tier1') {
      // Check if PRO user has pending trial generations
      // MUST also verify trialGenerationsAvailable > 0 (backend sets it to 0
      // when cross-device trial is blocked via trialKey validation)
      final trialAvail = user.trialGenerationsAvailable ?? 0;

      if (!user.hasUsedTrial && user.regionTier != 'tier3' && trialAvail > 0) {
        final trialGens = trialAvail > 0
            ? trialAvail
            : _getTrialGenerations(user.regionTier);
        return {
          'accessMethod': 'trial',
          'requiresAd': false,
          'message': 'Use your $trialGens free trial generations first!',
          'freeGenerations': trialGens,
        };
      }

      // PRO access check: Mini phase (0-20) then Nano phase (0-80) = 100 total/day
      final nanoUsed = user.aiNanoUsedToday;
      final miniUsed = user.aiMiniUsedToday;
      const miniCap = 20; // Phase 1: 20 mini/day
      const nanoCap = 80; // Phase 2: 80 nano/day
      final allExhausted = nanoUsed >= nanoCap && miniUsed >= miniCap;

      if (allExhausted) {
        return {
          'accessMethod': 'blocked',
          'requiresAd': false,
          'message': 'All daily AI generations used. Come back tomorrow!',
        };
      }

      return {
        'accessMethod': 'pro',
        'requiresAd': false,
        'message': 'PRO access',
      };
    }

    // Check trial ONLY for tier-1 and tier-2
    // Tier-3 has NO trial (per requirements Section 5.2)
    // MUST also verify trialGenerationsAvailable > 0 (backend sets it to 0
    // when cross-device trial is blocked via trialKey validation)
    final nonProTrialAvail = user.trialGenerationsAvailable ?? 0;
    if (!user.hasUsedTrial &&
        user.regionTier != 'tier3' &&
        nonProTrialAvail > 0) {
      final trialGens = nonProTrialAvail > 0
          ? nonProTrialAvail
          : _getTrialGenerations(user.regionTier);
      return {
        'accessMethod': 'trial',
        'requiresAd': false,
        'message': 'Trial available: $trialGens generations',
        'freeGenerations': trialGens,
      };
    }

    // Get limits for user's tier
    final limits = getDailyLimits(user.regionTier);
    final aiLimit = limits['dailyAiLimit']!;
    final rewardedLimit = limits['dailyRewardedLimit']!;

    // Check if AI quota exhausted
    final aiUsed = user.aiNanoUsedToday;
    final aiRemaining = aiLimit - aiUsed;

    if (aiRemaining <= 0) {
      return {
        'accessMethod': 'blocked',
        'requiresAd': false,
        'message':
            'Daily AI limit reached ($aiLimit/$aiLimit). Try again tomorrow!',
      };
    }

    // Check rewarded ad quota
    final adsWatched = user.rewardedAdsWatchedToday;
    final adsRemaining = rewardedLimit - adsWatched;

    if (adsRemaining <= 0) {
      return {
        'accessMethod': 'blocked',
        'requiresAd': false,
        'message': 'Daily ad limit reached. Try again tomorrow!',
      };
    }

    // Both quotas available - require rewarded ad
    return {
      'accessMethod': 'rewarded',
      'requiresAd': true,
      'message': 'Watch an ad to unlock AI generation',
      'aiRemaining': aiRemaining,
      'adsRemaining': adsRemaining,
      'aiPerReward': limits['dailyAiPerReward']!,
    };
  }

  /// Get trial generations based on tier
  /// MUST match backend config.js TRIAL values exactly
  int _getTrialGenerations(String regionTier) {
    switch (regionTier) {
      case 'tier1':
        return 2; // Backend: config.TRIAL.tier1 = 2
      case 'tier2':
        return 1; // Backend: config.TRIAL.tier2 = 1
      case 'tier3':
      default:
        return 0; // Backend: config.TRIAL.tier3 = 0 (no trial)
    }
  }

  /// Check if daily limit exceeded (for backwards compatibility)
  Future<bool> checkDailyLimitExceeded() async {
    final status = await getAccessStatus();
    return status['accessMethod'] == 'blocked';
  }

  /// Get formatted status message for UI
  Future<String> getStatusMessage() async {
    final status = await getAccessStatus();
    return status['message'] as String;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🧪 TRIAL INDICATOR LOGIC - Safe, Architecture-Compliant
  // ═══════════════════════════════════════════════════════════════════════

  /// 🧪 Check if trial should be shown in UI
  /// Returns true only for Tier2 & Tier3 users who haven't used trial yet
  bool shouldShowTrialIndicator(UserModel user) {
    // Only show trial for Tier2 & Tier3 (Tier1 doesn't have meaningful trial)
    final isTier2or3 = user.regionTier == 'tier2' || user.regionTier == 'tier3';

    // Only show if trial is available and not yet used
    final trialAvailable = (user.trialGenerationsAvailable ?? 0) > 0;
    final notUsedYet = !user.hasUsedTrial;

    return isTier2or3 && trialAvailable && notUsedYet;
  }

  /// 🧪 Get trial status for display
  /// Returns map with: {used: bool, available: int, progress: double}
  Map<String, dynamic> getTrialDisplayInfo(UserModel user) {
    final trialAvailable = user.trialGenerationsAvailable ?? 0;
    final hasUsedTrial = user.hasUsedTrial;

    return {
      'shouldShow': shouldShowTrialIndicator(user),
      'available': trialAvailable,
      'used': hasUsedTrial ? 1 : 0, // 0 = not used, 1 = used
      'progress': hasUsedTrial ? 1.0 : 0.0, // For progress bar
      'label': 'AI Trial Generation Used',
    };
  }
}
