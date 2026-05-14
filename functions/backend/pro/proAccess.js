/**
 * PRO User Access Control
 * Enforces PRO-specific rules and restrictions
 */

const proEligibility = require("./proEligibility");
const proLimits = require("./proLimits");

/**
 * Check if user is PRO and subscription is valid
 * @param {object} user - User document
 * @return {object} - { isPro: boolean, valid?: boolean }
 */
function verifyProStatus(user) {
  if (!user || !user.isPro) {
    return {
      isPro: false,
    };
  }

  // Check tier eligibility
  const eligibility = proEligibility.verifyProStatus(user);
  if (!eligibility.valid) {
    return {
      isPro: false,
      invalid: true,
      reason: eligibility.reason,
    };
  }

  return {
    isPro: true,
    valid: true,
  };
}

/**
 * Enforce PRO restrictions on AI generation
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @param {string} requestedModel - "nano" or "mini"
 * @return {object} - { allowed: boolean, reason?: string }
 */
function enforceProRestrictions(user, counters, requestedModel = "nano") {
  if (!user || !user.isPro) {
    return {
      allowed: false,
      reason: "User is not PRO",
    };
  }

  // REMOVED: checkHardCap() was too restrictive and blocked model switching
  // Now only check the SPECIFIC requested model's hard cap
  // This allows: Nano 20 → Mini available → Mini 20 → Nano available, etc.

  // Check model-specific hard cap (INDIVIDUAL per-model enforcement)
  const modelCheck = proLimits.canGenerateWithModel(counters, requestedModel);
  if (!modelCheck.canGenerate) {
    return {
      allowed: false,
      reason: modelCheck.message,
    };
  }

  return {
    allowed: true,
    requestedModel,
  };
}

/**
 * Get PRO access summary
 * @param {object} user - User document
 * @param {object} counters - Daily counters
 * @return {object} - Complete PRO status summary
 */
function getProAccessSummary(user, counters) {
  if (!user || !user.isPro) {
    return {
      isPro: false,
    };
  }

  const status = verifyProStatus(user);
  if (!status.valid) {
    return {
      isPro: false,
      invalid: true,
      reason: status.reason,
    };
  }

  const features = proEligibility.getProFeatures(user.regionTier);
  const dailyStatus = proLimits.getProDailyStatus(counters);
  const softCapStatus = proLimits.checkSoftCap(counters);

  return {
    isPro: true,
    tier: user.regionTier,
    features: features.features,
    limits: features.limits,
    dailyUsage: dailyStatus,
    softCapWarning: softCapStatus.exceedsSoft ? softCapStatus.message : null,
    canGenerateNano: proLimits.canGenerateWithModel(counters, "nano").canGenerate,
    canGenerateMini: proLimits.canGenerateWithModel(counters, "mini").canGenerate,
  };
}

/**
 * Format PRO limit message for UI
 * @param {object} counters - Daily counters
 * @return {string} - User-facing message
 */
function getProLimitMessage(counters) {
  const softCapCheck = proLimits.checkSoftCap(counters);

  if (softCapCheck.exceedsSoft) {
    return `You've exceeded your soft limit today (${softCapCheck.message})`;
  }

  return "You have unlimited access within daily limits.";
}

module.exports = {
  verifyProStatus,
  enforceProRestrictions,
  getProAccessSummary,
  getProLimitMessage,
};
