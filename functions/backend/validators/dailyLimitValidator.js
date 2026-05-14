/**
 * Daily Limit Validator
 * Validates if user has exceeded daily AI or rewarded ad limits
 *
 * Spec: Section 3, 4, 5 - Daily limits per tier
 * Hard rule: Server-side enforcement is mandatory
 */

const config = require("../config");
const counters = require("../common/counters");

/**
 * Get daily limit for user's tier and plan
 * @param {object} user - User document from Firestore
 * @return {object} - { dailyAiLimit, dailyRewardedLimit, dailyAiPerReward }
 */
function getDailyLimits(user) {
  if (!user) {
    console.warn("⚠️ Missing user for limit check, defaulting to tier3");
    return config.DAILY_AI_LIMITS.tier3 || 3;
  }

  const {regionTier, isPro} = user;

  // PRO users: Individual per-model hard caps (checked separately in canGenerateAi)
  if (isPro && regionTier === "tier1") {
    return {
      dailyAiLimit: null, // Not used - checked per model instead
      dailyRewardedLimit: 0, // PRO users don't watch ads
      dailyAiPerReward: 0,
      tier: "tier1_pro",
      perModelLimits: {
        nano_hard_cap: config.PRO_LIMITS.hard_cap_nano,
        mini_hard_cap: config.PRO_LIMITS.hard_cap_mini,
      },
      note: "Per-model hard caps: Mini 20/day (Phase 1), Nano 80/day (Phase 2) = 100 total",
    };
  }

  // Non-PRO users (rewarded only)
  const tierLimits = config.DAILY_AI_LIMITS[regionTier] || config.DAILY_AI_LIMITS.tier3;
  const rewardedConfig = config.REWARDED_ADS[regionTier];

  return {
    dailyAiLimit: tierLimits,
    dailyRewardedLimit: rewardedConfig.max_per_day,
    dailyAiPerReward: rewardedConfig.ai_per_reward,
    tier: regionTier,
  };
}

/**
 * Check if user can generate AI (has not exceeded daily limit)
 * SPEC: Section 3.4 - PRO users have separate hard caps per model
 * @param {object} user - User document with counters
 * @param {object} countersData - Current counter values
 * @param {string} modelType - "nano" or "mini" (which model user wants to use)
 * @return {object} - { allowed: boolean, remainingToday: number, message?: string }
 */
function canGenerateAi(user, countersData, modelType = "nano") {
  if (!user || !countersData) {
    return {
      allowed: false,
      remainingToday: 0,
      message: "Invalid user data",
    };
  }

  const limits = getDailyLimits(user);

  // PRO users: Phased per-model limits (20 mini Phase 1 + 80 nano Phase 2 = 100 total)
  if (user.isPro && user.regionTier === "tier1") {
    const nanoUsed = countersData.aiNanoUsedToday || 0;
    const miniUsed = countersData.aiMiniUsedToday || 0;
    const nanoCap = config.PRO_LIMITS.soft_cap_nano; // 80

    // Apply hard cap as safety net
    const effectiveCap = modelType === "mini" ?
        Math.min(config.PRO_LIMITS.soft_cap_mini, config.PRO_LIMITS.hard_cap_mini) : // 20
        Math.min(nanoCap, config.PRO_LIMITS.hard_cap_nano); // 80

    const used = modelType === "mini" ? miniUsed : nanoUsed;
    const remaining = effectiveCap - used;

    if (remaining <= 0) {
      return {
        allowed: false,
        remainingToday: 0,
        message: config.MESSAGES.LIMIT_REACHED_TIER1,
        tier: user.regionTier,
        model: modelType,
        effectiveCap,
        alreadyUsed: used,
      };
    }

    return {
      allowed: true,
      remainingToday: remaining,
      tier: user.regionTier,
      model: modelType,
      effectiveCap,
    };
  }

  // Non-PRO users: Check combined daily limit
  const totalUsed = counters.getTotalAiGenerationsToday(countersData);
  const remaining = limits.dailyAiLimit - totalUsed;

  if (remaining <= 0) {
    const message = user.regionTier === "tier1" ?
        config.MESSAGES.LIMIT_REACHED_TIER1 :
        config.MESSAGES.LIMIT_REACHED_TIER2_3;

    return {
      allowed: false,
      remainingToday: 0,
      message,
      tier: user.regionTier,
      dailyLimit: limits.dailyAiLimit,
      alreadyUsed: totalUsed,
    };
  }

  return {
    allowed: true,
    remainingToday: remaining,
    tier: user.regionTier,
    dailyLimit: limits.dailyAiLimit,
  };
}

/**
 * Check if user can watch rewarded ad (has not exceeded rewarded limit)
 * @param {object} user - User document
 * @param {object} countersData - Current counter values
 * @return {object} - { allowed: boolean, remainingToday: number, message?: string }
 */
function canWatchRewardedAd(user, countersData) {
  if (!user || !countersData) {
    return {
      allowed: false,
      remainingToday: 0,
      message: "Invalid user data",
    };
  }

  // PRO users cannot watch ads
  if (user.isPro) {
    return {
      allowed: false,
      remainingToday: 0,
      message: "PRO users do not need ads",
    };
  }

  const limits = getDailyLimits(user);
  const rewardedWatched = countersData.rewardedAdsWatchedToday || 0;
  const remaining = limits.dailyRewardedLimit - rewardedWatched;

  if (remaining <= 0) {
    return {
      allowed: false,
      remainingToday: 0,
      message: config.MESSAGES.LIMIT_REACHED_TIER2_3,
      tier: user.regionTier,
      dailyLimit: limits.dailyRewardedLimit,
      alreadyWatched: rewardedWatched,
    };
  }

  return {
    allowed: true,
    remainingToday: remaining,
    tier: user.regionTier,
    dailyLimit: limits.dailyRewardedLimit,
  };
}

/**
 * Check if user is using trial (still has free generations left)
 * @param {object} user - User document
 * @param {object} countersData - Current counter values
 * @return {object} - { inTrial: boolean, remainingFree: number }
 */
function getTrialStatus(user, countersData) {
  if (!user || user.hasUsedTrial) {
    return {
      inTrial: false,
      remainingFree: 0,
    };
  }

  // Check if tier3 has trial (it doesn't)
  if (user.regionTier === "tier3") {
    return {
      inTrial: false,
      remainingFree: 0,
    };
  }

  const trialLimit = config.TRIAL[user.regionTier] || 0;
  const totalUsed = counters.getTotalAiGenerationsToday(countersData);
  const remaining = Math.max(0, trialLimit - totalUsed);

  return {
    inTrial: remaining > 0,
    remainingFree: remaining,
    tier: user.regionTier,
  };
}

/**
 * Validate if user can claim rewarded access
 * Checks both rewarded limit and resulting AI limit
 * @param {object} user - User document
 * @param {object} countersData - Current counter values
 * @return {object} - { allowed: boolean, message?: string, aiUnlocksAvailable: number }
 */
function canClaimRewardAccess(user, countersData) {
  // First check: can watch more ads
  const adCheck = canWatchRewardedAd(user, countersData);
  if (!adCheck.allowed) {
    return {
      allowed: false,
      message: adCheck.message,
    };
  }

  // Second check: can generate AI after this reward
  const limits = getDailyLimits(user);
  const totalUsed = counters.getTotalAiGenerationsToday(countersData);
  const aiUnlockedByReward = limits.dailyAiPerReward;
  const totalAfterReward = totalUsed + aiUnlockedByReward;

  if (totalAfterReward > limits.dailyAiLimit) {
    return {
      allowed: false,
      message: config.MESSAGES.LIMIT_REACHED_TIER2_3,
      aiUnlocksAvailable: limits.dailyAiLimit - totalUsed,
    };
  }

  return {
    allowed: true,
    aiUnlocksAvailable: aiUnlockedByReward,
    tier: user.regionTier,
  };
}

/**
 * Summary of user's daily status
 * @param {object} user - User document
 * @param {object} countersData - Current counter values
 * @return {object} - Complete daily status
 */
function getDailyStatus(user, countersData) {
  if (!user || !countersData) {
    return null;
  }

  const limits = getDailyLimits(user);
  const aiCheck = canGenerateAi(user, countersData);
  const rewardedCheck = canWatchRewardedAd(user, countersData);
  const trialCheck = getTrialStatus(user, countersData);

  return {
    tier: user.regionTier,
    isPro: user.isPro,
    limits,
    ai: {
      allowed: aiCheck.allowed,
      remainingToday: aiCheck.remainingToday,
      dailyLimit: aiCheck.dailyLimit || limits.dailyAiLimit,
      alreadyUsed: (countersData.aiNanoUsedToday || 0) + (countersData.aiMiniUsedToday || 0),
    },
    rewarded: {
      allowed: rewardedCheck.allowed,
      remainingToday: rewardedCheck.remainingToday,
      dailyLimit: rewardedCheck.dailyLimit || limits.dailyRewardedLimit,
      alreadyWatched: countersData.rewardedAdsWatchedToday || 0,
    },
    trial: trialCheck,
  };
}

module.exports = {
  getDailyLimits,
  canGenerateAi,
  canWatchRewardedAd,
  getTrialStatus,
  canClaimRewardAccess,
  getDailyStatus,
};
