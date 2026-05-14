/**
 * PRO Eligibility Check
 * Spec: 3.4 PRO SUBSCRIPTION (TIER-1 ONLY)
 *
 * PRO is only available in Tier-1
 */

const config = require("../config");

/**
 * Check if user's tier allows PRO subscription
 * @param {string} tier - User's region tier
 * @return {boolean} - true if PRO available in this tier
 */
function isProAvailableForTier(tier) {
  // PRO only in Tier-1
  return tier === "tier1";
}

/**
 * Get PRO availability message for tier
 * @param {string} tier - User's region tier
 * @return {object} - { available: boolean, message: string }
 */
function getProAvailabilityMessage(tier) {
  if (isProAvailableForTier(tier)) {
    return {
      available: true,
      message: "PRO subscription available",
    };
  }

  return {
    available: false,
    message: config.MESSAGES.PRO_NOT_AVAILABLE,
  };
}

/**
 * Check if user can be upgraded to PRO
 * @param {object} user - User document
 * @return {object} - { canUpgrade: boolean, reason?: string }
 */
function canUpgradeToPro(user) {
  if (!user) {
    return {
      canUpgrade: false,
      reason: "User not found",
    };
  }

  // Already PRO
  if (user.isPro) {
    return {
      canUpgrade: false,
      reason: "Already a PRO member",
    };
  }

  // Not in Tier-1
  if (!isProAvailableForTier(user.regionTier)) {
    return {
      canUpgrade: false,
      reason: config.MESSAGES.PRO_NOT_AVAILABLE,
    };
  }

  return {
    canUpgrade: true,
    tier: user.regionTier,
  };
}

/**
 * Get PRO feature summary for tier
 * @param {string} tier - User's region tier
 * @return {object} - PRO features and limits
 */
function getProFeatures(tier) {
  if (!isProAvailableForTier(tier)) {
    return {
      available: false,
      message: config.MESSAGES.PRO_NOT_AVAILABLE,
    };
  }

  return {
    available: true,
    features: {
      noAds: true,
      unlimitedAccess: "within caps",
      premiumAiModel: true, // gpt-4.1-mini
    },
    limits: {
      soft_cap: {
        nano: config.PRO_LIMITS.soft_cap_nano,
        mini: config.PRO_LIMITS.soft_cap_mini,
      },
      hard_cap: {
        nano: config.PRO_LIMITS.hard_cap_nano,
        mini: config.PRO_LIMITS.hard_cap_mini,
      },
    },
  };
}

/**
 * Verify PRO status is valid for user's tier
 * Prevents tier/PRO status mismatch
 * @param {object} user - User document
 * @return {object} - { valid: boolean, correction?: string }
 */
function verifyProStatus(user) {
  if (!user) {
    return {
      valid: false,
      reason: "User not found",
    };
  }

  // User is PRO but not in Tier-1
  if (user.isPro && !isProAvailableForTier(user.regionTier)) {
    return {
      valid: false,
      reason: "PRO not available in this tier - mismatch detected",
      correction: "downgrade_from_pro",
    };
  }

  return {
    valid: true,
  };
}

module.exports = {
  isProAvailableForTier,
  getProAvailabilityMessage,
  canUpgradeToPro,
  getProFeatures,
  verifyProStatus,
};
