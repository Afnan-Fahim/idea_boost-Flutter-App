/**
 * Tier Resolver (Internal Utility)
 * Used when:
 * - User initiates trial flow
 * - User clicks PRO upgrade
 *
 * NOT an HTTP endpoint - called internally by app logic
 */

const config = require("../config");

/**
 * Check if user can access PRO subscription
 * PRO is only available in Tier-1
 * @param {string} regionTier - User's region tier ("tier1", "tier2", "tier3")
 * @return {boolean} - true if PRO is available
 */
function isProAvailable(regionTier) {
  return regionTier === "tier1";
}

/**
 * Get subscription availability message for user
 * @param {string} regionTier - User's region tier
 * @return {object} - { available: boolean, message: string }
 */
function getProAvailability(regionTier) {
  if (!isProAvailable(regionTier)) {
    return {
      available: false,
      message: config.MESSAGES.PRO_NOT_AVAILABLE,
      tier: regionTier,
    };
  }

  return {
    available: true,
    message: "PRO subscription available",
    tier: regionTier,
  };
}

/**
 * Get trial availability info for user
 * @param {object} user - User document from Firestore
 * @return {object} - { canUseTrial: boolean, message: string, remainingUses: number }
 */
function getTrialInfo(user) {
  if (!user) {
    return {
      canUseTrial: false,
      message: "User not found",
      remainingUses: 0,
    };
  }

  const {regionTier, hasUsedTrial} = user;

  // Trial not available for Tier-3
  if (regionTier === "tier3") {
    return {
      canUseTrial: false,
      message: "Trial not available in your region",
      remainingUses: 0,
    };
  }

  // Already used trial
  if (hasUsedTrial) {
    return {
      canUseTrial: false,
      message: config.MESSAGES.TRIAL_ALREADY_USED,
      remainingUses: 0,
    };
  }

  // Can use trial
  const trialLimit = config.TRIAL[regionTier] || 0;
  return {
    canUseTrial: true,
    message: `You have ${trialLimit} free AI generations available`,
    remainingUses: trialLimit,
    tier: regionTier,
  };
}

/**
 * Validate tier for API consistency
 * Ensures tier hasn't been tampered with
 * @param {string} assignedTier - Tier from Firestore
 * @param {string} claimedTier - Tier from client request
 * @return {boolean} - true if they match or claim is more restrictive
 */
function isValidTierClaim(assignedTier, claimedTier) {
  const tierOrder = {tier1: 0, tier2: 1, tier3: 2};
  const assigned = tierOrder[assignedTier] ?? 2;
  const claimed = tierOrder[claimedTier] ?? 2;

  // Allow if claimed tier is same or MORE restrictive (higher number = more restrictive)
  return claimed >= assigned;
}

module.exports = {
  isProAvailable,
  getProAvailability,
  getTrialInfo,
  isValidTierClaim,
};
