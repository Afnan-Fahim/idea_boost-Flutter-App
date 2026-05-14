/**
 * Non-PRO User Access Control
 * Routes non-PRO users to correct access method
 */

const config = require("../config");
const trial = require("./trial");
const rewardedLimits = require("./rewardedLimits");
const dailyLimitValidator = require("../validators/dailyLimitValidator");

/**
 * Determine access method for non-PRO user
 * PROPER LOGIC (SPEC COMPLIANT):
 * 1. CHECK IF REWARD TOKEN PROVIDED (if yes, skip ad quota check)
 * 2. CHECK TRIAL FIRST (if hasUsedTrial == false)
 * 3. If trial used/unavailable, check daily AI limit (aiNanoUsedToday < dailyAiLimit)
 * 4. If AI quota available, check rewarded ad quota (adsWatchedToday < maxAds)
 * 5. If both available → allow as "rewarded"
 * 6. If exhausted → block
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @param {string} rewardToken - Optional reward token being consumed (bypasses ad quota check)
 * @return {Promise<object>} - { accessMethod: "trial"|"rewarded"|"blocked", message: string, remaining?: number }
 */
async function getAccessMethod(user, counters, rewardToken) {
  if (!user || !counters) {
    return {
      accessMethod: "blocked",
      message: "Invalid user data",
    };
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 1: CHECK TRIAL (HIGHEST PRIORITY) - NOW ASYNC
  // ════════════════════════════════════════════════════════════════
  const trialCheck = await trial.canAccessTrial(user);
  if (trialCheck.canAccess) {
    // User has trial available
    return {
      accessMethod: "trial",
      message: trialCheck.message,
      freeGenerations: trialCheck.freeGenerations,
      tier: user.regionTier,
    };
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 2: CHECK DAILY AI LIMIT (aiNanoUsedToday < dailyAiLimit)
  // ════════════════════════════════════════════════════════════════
  const limits = dailyLimitValidator.getDailyLimits(user);
  const aiUsedToday = counters.aiNanoUsedToday || 0;
  const aiQuotaRemaining = limits.dailyAiLimit - aiUsedToday;

  if (aiQuotaRemaining <= 0) {
    // Daily AI limit reached
    const message = user.regionTier === "tier1" ?
      config.MESSAGES.LIMIT_REACHED_TIER1 :
      config.MESSAGES.LIMIT_REACHED_TIER2_3;

    return {
      accessMethod: "blocked",
      message: message,
      reason: "Daily AI limit reached",
    };
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 3: CHECK REWARDED AD QUOTA (SKIP IF CONSUMING EXISTING TOKEN)
  // ════════════════════════════════════════════════════════════════
  // Always calculate remaining ads, but only block if trying to WATCH a new ad
  const adsWatchedToday = counters.rewardedAdsWatchedToday || 0;
  const adsQuotaRemaining = limits.dailyRewardedLimit - adsWatchedToday;

  // If rewardToken is provided, user is consuming an EXISTING token
  // from a previous ad watch, so ad quota check doesn't apply
  if (!rewardToken && adsQuotaRemaining <= 0) {
    // No more rewarded ads available today
    return {
      accessMethod: "blocked",
      message: "No rewarded ads available today. Try again tomorrow.",
      reason: "Rewarded ad limit exhausted",
    };
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 4: BOTH AI & AD QUOTA AVAILABLE → ALLOW REWARDED
  // ════════════════════════════════════════════════════════════════
  const promptMsg = rewardedLimits.getRewardedPromptMessage(user.regionTier);
  return {
    accessMethod: "rewarded",
    message: promptMsg,
    aiRemaining: aiQuotaRemaining,
    adsRemaining: adsQuotaRemaining,
    aiPerReward: limits.dailyAiPerReward,
  };
}

/**
 * Get comprehensive access status for non-PRO user
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @return {Promise<object>} - Complete access status
 */
async function getNonProStatus(user, counters) {
  if (!user || !counters) {
    return null;
  }

  const dailyStatus = dailyLimitValidator.getDailyStatus(user, counters);
  const accessMethod = await getAccessMethod(user, counters);

  return {
    tier: user.regionTier,
    isPro: false,
    daily: dailyStatus,
    accessMethod: accessMethod.accessMethod,
    message: accessMethod.message,
    trial: {
      available: (await trial.canAccessTrial(user)).canAccess,
      status: trial.getTrialStatus(user),
    },
    rewarded: {
      available: accessMethod.accessMethod === "rewarded",
      status: rewardedLimits.getRewardedStatus(counters, user.regionTier),
    },
  };
}

/**
 * Enforce non-PRO restrictions on request
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @return {Promise<object>} - { allowed: boolean, reason?: string }
 */
async function enforceNonProRestrictions(user, counters) {
  if (!user || user.isPro) {
    return {
      allowed: false,
      reason: "User is PRO or missing data",
    };
  }

  const access = await getAccessMethod(user, counters);

  if (access.accessMethod === "blocked") {
    return {
      allowed: false,
      reason: access.message,
    };
  }

  return {
    allowed: true,
    accessMethod: access.accessMethod,
  };
}

module.exports = {
  getAccessMethod,
  getNonProStatus,
  enforceNonProRestrictions,
};
