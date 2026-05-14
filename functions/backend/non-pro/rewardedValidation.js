/**
 * Rewarded Validation for Non-PRO Users
 * Spec: H1) Reward Granting (CRITICAL)
 *
 * Server-side validation before granting rewarded access
 * Client is NOT trusted
 */

const config = require("../config");
const dailyLimitValidator = require("../validators/dailyLimitValidator");

/**
 * Validate user is eligible for rewarded unlocks
 * @param {object} user - User document
 * @return {object} - { eligible: boolean, reason?: string }
 */
function isEligibleForRewarded(user) {
  if (!user) {
    return {
      eligible: false,
      reason: "User not found",
    };
  }

  // Tier-3 only has rewarded access (no trial, no PRO)
  // Tier-1/2 have mixed access

  // PRO users shouldn't use rewarded
  if (user.isPro) {
    return {
      eligible: false,
      reason: "PRO users should not use rewarded ads",
    };
  }

  return {
    eligible: true,
    tier: user.regionTier,
  };
}

/**
 * Pre-validation before user watches rewarded ad
 * Check if user can watch another ad today
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @return {object} - { canWatch: boolean, message?: string }
 */
function validateBeforeAdWatch(user, counters) {
  if (!user || !counters) {
    return {
      canWatch: false,
      message: "Invalid user data",
    };
  }

  const limits = dailyLimitValidator.getDailyLimits(user);
  const watched = counters.rewardedAdsWatchedToday || 0;

  if (watched >= limits.dailyRewardedLimit) {
    return {
      canWatch: false,
      message: config.MESSAGES.LIMIT_REACHED_TIER2_3,
      dailyLimit: limits.dailyRewardedLimit,
      alreadyWatched: watched,
    };
  }

  return {
    canWatch: true,
    remainingToday: limits.dailyRewardedLimit - watched,
  };
}

/**
 * Post-validation after user completes rewarded ad
 * Verify ad callback and user is eligible for reward
 * @param {object} validationData - Data to validate
 * @return {object} - { valid: boolean, error?: string }
 */
function validateAfterAdCompletion(validationData) {
  const {rewardCallback, user, counters} = validationData;

  // Check 1: Reward callback received
  if (!rewardCallback) {
    return {
      valid: false,
      error: "Missing reward callback - ad completion not verified",
    };
  }

  // Check 2: User still eligible
  const eligibility = isEligibleForRewarded(user);
  if (!eligibility.eligible) {
    return {
      valid: false,
      error: eligibility.reason,
    };
  }

  // Check 3: Limits still allow this reward
  const limitCheck = validateBeforeAdWatch(user, counters);
  if (!limitCheck.canWatch) {
    return {
      valid: false,
      error: limitCheck.message,
    };
  }

  return {
    valid: true,
  };
}

/**
 * Full rewarded validation pipeline
 * Called by claimReward endpoint
 * @param {object} params - Full validation parameters
 * @return {object} - { valid: boolean, errors: Array }
 */
function performFullRewardedValidation(params) {
  const {user, counters, rewardClaim, rewardCallback} = params;

  const errors = [];

  // Check 1: User eligible
  const eligibility = isEligibleForRewarded(user);
  if (!eligibility.eligible) {
    errors.push(eligibility.reason);
  }

  // Check 2: Can watch more ads
  if (user && counters) {
    const watchCheck = validateBeforeAdWatch(user, counters);
    if (!watchCheck.canWatch) {
      errors.push(watchCheck.message);
    }
  }

  // Check 3: Reward callback
  if (!rewardCallback) {
    errors.push("Reward callback missing - verify ad completion");
  }

  // Check 4: Reward claim structure
  if (!rewardClaim || !rewardClaim.rewardId) {
    errors.push("Invalid reward claim structure");
  }

  // Check 5: Won't exceed AI limit
  if (user && counters) {
    const limits = dailyLimitValidator.getDailyLimits(user);
    const aiUsed = (counters.aiNanoUsedToday || 0) + (counters.aiMiniUsedToday || 0);
    const aiPerReward = limits.dailyAiPerReward;

    if (aiUsed + aiPerReward > limits.dailyAiLimit) {
      errors.push(
          `Claim would exceed daily AI limit (${aiUsed + aiPerReward} > ${limits.dailyAiLimit})`,
      );
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

module.exports = {
  isEligibleForRewarded,
  validateBeforeAdWatch,
  validateAfterAdCompletion,
  performFullRewardedValidation,
};
