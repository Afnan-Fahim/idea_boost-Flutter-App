/**
 * Rewarded Ad Limits for Non-PRO Users
 * Spec: 3.3 (Tier-1), 4.3 (Tier-2), 5.3 (Tier-3)
 */

const config = require("../config");

/**
 * Get rewarded ad settings for tier
 * @param {string} tier - User's region tier
 * @return {object} - { maxPerDay, aiPerReward }
 */
function getRewardedLimits(tier) {
  const limits = config.REWARDED_ADS[tier];

  if (!limits) {
    console.warn(`⚠️ No rewarded limits for tier ${tier}, using tier3 defaults`);
    return config.REWARDED_ADS.tier3;
  }

  return limits;
}

/**
 * Check if user can claim another rewarded ad unlock today
 * @param {object} user - User document
 * @param {object} counters - Current daily counters
 * @return {object} - { canClaim: boolean, message?: string, remaining: number }
 */
function canClaimRewardedUnlock(user, counters) {
  if (!user || !counters) {
    return {
      canClaim: false,
      message: "Invalid user data",
      remaining: 0,
    };
  }

  // PRO users don't use rewarded ads
  if (user.isPro) {
    return {
      canClaim: false,
      message: "PRO users do not need ads",
      remaining: 0,
    };
  }

  const limits = getRewardedLimits(user.regionTier);
  const watched = counters.rewardedAdsWatchedToday || 0;
  const maxPerDay = limits.max_per_day;

  if (watched >= maxPerDay) {
    const message = user.regionTier === "tier1" ?
        config.MESSAGES.LIMIT_REACHED_TIER1 :
        config.MESSAGES.LIMIT_REACHED_TIER2_3;

    return {
      canClaim: false,
      message,
      remaining: 0,
      tier: user.regionTier,
      watched,
      maxPerDay,
    };
  }

  const remaining = maxPerDay - watched;

  return {
    canClaim: true,
    remaining,
    tier: user.regionTier,
    watched,
    maxPerDay,
  };
}

/**
 * Get AI generations granted per rewarded ad for tier
 * @param {string} tier - User's region tier
 * @return {number} - AI generations per reward
 */
function getAiPerReward(tier) {
  const limits = getRewardedLimits(tier);
  return limits.ai_per_reward;
}

/**
 * Format rewarded ad prompt message for user
 * Spec: H3) Policy-safe UI copy
 * @param {string} tier - User's region tier
 * @return {string} - User-facing message
 */
function getRewardedPromptMessage(tier) {
  const limits = getRewardedLimits(tier);
  const aiPerReward = limits.ai_per_reward;

  if (tier === "tier1") {
    return `Watch a short ad to unlock ${aiPerReward} AI generations.`;
  }

  return `Watch a short ad to unlock ${aiPerReward} AI generation.`;
}

/**
 * Get remaining rewarded ads for today
 * @param {object} counters - Current daily counters
 * @param {string} tier - User's region tier
 * @return {object} - { watched: number, maxPerDay: number, remaining: number }
 */
function getRewardedStatus(counters, tier) {
  const limits = getRewardedLimits(tier);
  const watched = counters?.rewardedAdsWatchedToday || 0;
  const maxPerDay = limits.max_per_day;
  const remaining = Math.max(0, maxPerDay - watched);

  return {
    watched,
    maxPerDay,
    remaining,
  };
}

module.exports = {
  getRewardedLimits,
  canClaimRewardedUnlock,
  getAiPerReward,
  getRewardedPromptMessage,
  getRewardedStatus,
};
