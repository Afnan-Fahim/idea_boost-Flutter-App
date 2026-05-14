// lib/data/models/user_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String plan; // 'free' | 'pro'
  final String language; // 'en' | 'ru' | 'uz'
  final int dailyLimit; // Kept for backwards compatibility
  final String name;
  final String email;
  final String? photoUrl;

  // NEW: Monetization fields
  final String regionTier; // 'tier1' | 'tier2' | 'tier3'
  final bool hasUsedTrial;
  final int aiNanoUsedToday;
  final int aiMiniUsedToday;
  final int rewardedAdsWatchedToday;
  final int? maxRewardedAdsPerDay; // From Firestore config
  final int? aiPerRewardedAd; // From Firestore config
  final int? trialGenerationsAvailable; // From Firestore config
  final int?
  trialGenerationsRemaining; // Currently remaining trials (decrements as used)
  final int? dailyAiLimit; // From Firestore config
  final DateTime? dailyResetAt; // Last reset timestamp for countdown
  final Map<String, dynamic>?
  activeRewardTokens; // Reward tokens with consumed status

  UserModel({
    required this.id,
    required this.plan,
    required this.language,
    required this.dailyLimit,
    required this.name,
    required this.email,
    this.photoUrl,
    this.regionTier =
        '', // Backend automatically resolves tier based on region data
    this.hasUsedTrial = false,
    this.aiNanoUsedToday = 0,
    this.aiMiniUsedToday = 0,
    this.rewardedAdsWatchedToday = 0,
    this.maxRewardedAdsPerDay,
    this.aiPerRewardedAd,
    this.trialGenerationsAvailable,
    this.trialGenerationsRemaining,
    this.dailyAiLimit,
    this.dailyResetAt,
    this.activeRewardTokens,
  });

  // 💡 CENTRALIZED LOGIC: Public Static Helper for Default Limits (from Version 2)
  static int calculateDefaultLimit(String plan) {
    switch (plan.toLowerCase()) {
      case 'pro':
        return 50; // PRO Limit
      case 'free':
      default:
        return 3; // FREE Limit
    }
  }

  // From Firestore
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Determine the plan early to use it for limit calculation
    final String currentPlan = data['plan'] as String? ?? 'free';

    return UserModel(
      id: doc.id,
      plan: currentPlan,
      language: data['language'] as String? ?? 'en',
      dailyLimit:
          data['dailyLimit'] as int? ??
          UserModel.calculateDefaultLimit(currentPlan),
      name: data['name'] as String? ?? 'User',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      // NEW: Parse monetization fields
      regionTier: data['regionTier'] as String? ?? '', // Backend resolves tier
      hasUsedTrial: data['hasUsedTrial'] as bool? ?? false,
      aiNanoUsedToday: data['aiNanoUsedToday'] as int? ?? 0,
      aiMiniUsedToday: data['aiMiniUsedToday'] as int? ?? 0,
      rewardedAdsWatchedToday: data['rewardedAdsWatchedToday'] as int? ?? 0,
      maxRewardedAdsPerDay: data['maxRewardedAdsPerDay'] as int?,
      aiPerRewardedAd: data['aiPerRewardedAd'] as int?,
      trialGenerationsAvailable: data['trialGenerationsAvailable'] as int?,
      trialGenerationsRemaining: data['trialGenerationsRemaining'] as int?,
      dailyAiLimit: data['dailyAiLimit'] as int?,
      dailyResetAt: data['dailyResetAt'] != null
          ? (data['dailyResetAt'] as Timestamp).toDate()
          : null,
      activeRewardTokens: data['activeRewardTokens'] as Map<String, dynamic>?,
    );
  }

  // To Firestore (includes all fields for saving)
  Map<String, dynamic> toMap() {
    return {
      'plan': plan,
      'language': language,
      'dailyLimit': dailyLimit,
      'name': name,
      'email': email,
      if (photoUrl != null) 'photoUrl': photoUrl,
      // regionTier is resolved by backend - don't include it in client writes
      'hasUsedTrial': hasUsedTrial,
      'aiNanoUsedToday': aiNanoUsedToday,
      'aiMiniUsedToday': aiMiniUsedToday,
      'rewardedAdsWatchedToday': rewardedAdsWatchedToday,
    };
  }

  // ⚙️ Essential copyWith method
  UserModel copyWith({
    String? id,
    String? plan,
    String? language,
    int? dailyLimit,
    String? name,
    String? email,
    String? photoUrl,
    String? regionTier,
    bool? hasUsedTrial,
    int? aiNanoUsedToday,
    int? aiMiniUsedToday,
    int? rewardedAdsWatchedToday,
    int? maxRewardedAdsPerDay,
    int? aiPerRewardedAd,
    int? trialGenerationsAvailable,
    int? trialGenerationsRemaining,
    int? dailyAiLimit,
    DateTime? dailyResetAt,
    Map<String, dynamic>? activeRewardTokens,
  }) {
    return UserModel(
      id: id ?? this.id,
      plan: plan ?? this.plan,
      language: language ?? this.language,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      regionTier: regionTier ?? this.regionTier,
      hasUsedTrial: hasUsedTrial ?? this.hasUsedTrial,
      aiNanoUsedToday: aiNanoUsedToday ?? this.aiNanoUsedToday,
      aiMiniUsedToday: aiMiniUsedToday ?? this.aiMiniUsedToday,
      rewardedAdsWatchedToday:
          rewardedAdsWatchedToday ?? this.rewardedAdsWatchedToday,
      maxRewardedAdsPerDay: maxRewardedAdsPerDay ?? this.maxRewardedAdsPerDay,
      aiPerRewardedAd: aiPerRewardedAd ?? this.aiPerRewardedAd,
      trialGenerationsAvailable:
          trialGenerationsAvailable ?? this.trialGenerationsAvailable,
      trialGenerationsRemaining:
          trialGenerationsRemaining ?? this.trialGenerationsRemaining,
      dailyAiLimit: dailyAiLimit ?? this.dailyAiLimit,
      dailyResetAt: dailyResetAt ?? this.dailyResetAt,
      activeRewardTokens: activeRewardTokens ?? this.activeRewardTokens,
    );
  }

  // Convenience getter (from Version 1)
  // Compatibility shim: legacy callers may check this flag.
  // With `lastReset` fields removed, resetting is disabled by default.
  bool get shouldResetLimit => false;

  bool get isPro => plan == 'pro';

  // Debugging helper (from Version 1)
  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email, plan: $plan, lang: $language, limit: $dailyLimit)';
  }
}
