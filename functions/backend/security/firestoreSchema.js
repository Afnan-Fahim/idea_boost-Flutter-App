/**
 * Firestore Schema Validation
 * Spec: 7. REQUIRED FIRESTORE FIELDS
 *
 * Validates user document structure and ensures all required fields exist
 * Prevents corrupt data from causing runtime errors
 */

const config = require("../config");
const regionTierResolver = require("../common/regionTier");

/**
 * Initialize user document with required fields
 * Called when user first signs in
 * @param {string} userId - User UID
 * @param {string} regionTier - Resolved region tier ("tier1", "tier2", "tier3")
 * @param {string} trialKey - Device fingerprint for trial protection
 * @return {object} - Complete user document structure
 */
function createUserDocument(userId, regionTier, trialKey) {
  if (!userId || !regionTier || !trialKey) {
    throw new Error("Missing userId, regionTier, or trialKey for user document creation");
  }

  return {
    uid: userId,
    regionTier,
    hasUsedTrial: false,
    trialKey,
    aiNanoUsedToday: 0,
    aiMiniUsedToday: 0,
    rewardedAdsWatchedToday: 0,
    dailyResetAt: new Date(),
    isPro: false,
    claimedRewards: {},
    activeRewardTokens: {}, // NEW: Reward token storage
    regionTierAppVersion: "", // NEW: App version for tier caching
    recentRequestTimestamps: [], // NEW: For abuse detection
    recentPrompts: [], // NEW: For abuse detection
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

/**
 * Validate user document has all required fields
 * @param {object} userDoc - User document from Firestore
 * @return {object} - { valid: boolean, missingFields: Array, errors: Array }
 */
function validateUserDocument(userDoc) {
  if (!userDoc) {
    return {
      valid: false,
      missingFields: config.FIRESTORE.REQUIRED_FIELDS,
      errors: ["User document is missing"],
    };
  }

  const missingFields = [];
  const errors = [];

  // Check each required field
  config.FIRESTORE.REQUIRED_FIELDS.forEach((field) => {
    if (!(field in userDoc)) {
      missingFields.push(field);
      errors.push(`Missing required field: ${field}`);
    }
  });

  // Type validations
  if (userDoc.regionTier && !["tier1", "tier2", "tier3"].includes(userDoc.regionTier)) {
    errors.push(`Invalid regionTier: ${userDoc.regionTier}`);
  }

  if (userDoc.hasUsedTrial && typeof userDoc.hasUsedTrial !== "boolean") {
    errors.push("hasUsedTrial must be boolean");
  }

  if (typeof userDoc.aiNanoUsedToday !== "number") {
    errors.push("aiNanoUsedToday must be number");
  }

  if (typeof userDoc.aiMiniUsedToday !== "number") {
    errors.push("aiMiniUsedToday must be number");
  }

  if (typeof userDoc.rewardedAdsWatchedToday !== "number") {
    errors.push("rewardedAdsWatchedToday must be number");
  }

  const valid = missingFields.length === 0 && errors.length === 0;

  if (!valid) {
    console.warn(`⚠️ User document validation failed | Errors: ${errors.join(", ")}`);
  }

  return {
    valid,
    missingFields,
    errors,
  };
}

/**
 * Auto-repair user document by adding missing required fields
 * Used for backward compatibility with old user docs
 * @param {object} userDoc - Incomplete user document
 * @return {object} - Repaired user document
 */
function repairUserDocument(userDoc) {
  const validation = validateUserDocument(userDoc);

  if (validation.valid) {
    return userDoc; // No repair needed
  }

  const repaired = {...userDoc};

  // Add missing fields with defaults
  if (!("regionTier" in repaired)) {
    // 🌍 ANTI-VPN: Resolve tier from region data if available
    if (repaired.storeCountry || repaired.deviceLocale || repaired.ipCountry) {
      const resolvedTier = regionTierResolver.resolveRegionTier({
        storeCountry: repaired.storeCountry,
        deviceLocale: repaired.deviceLocale,
        ipCountry: repaired.ipCountry,
      });
      repaired.regionTier = resolvedTier;
      console.log(
          `🎯 Region tier resolved using ANTI-VPN logic: ${resolvedTier} | ` +
          `Store: ${repaired.storeCountry || "N/A"}, ` +
          `Device: ${repaired.deviceLocale || "N/A"}, ` +
          `IP: ${repaired.ipCountry || "N/A"}`,
      );
    } else {
      // No region data available, use conservative default
      repaired.regionTier = "tier3";
      console.warn("⚠️ No region data available for tier resolution, defaulting to tier3");
    }
  }

  if (!("hasUsedTrial" in repaired)) {
    repaired.hasUsedTrial = false;
  }

  if (!("trialKey" in repaired)) {
    repaired.trialKey = ""; // Will be set on next app start
  }

  if (!("aiNanoUsedToday" in repaired)) {
    repaired.aiNanoUsedToday = 0;
  }

  if (!("aiMiniUsedToday" in repaired)) {
    repaired.aiMiniUsedToday = 0;
  }

  if (!("rewardedAdsWatchedToday" in repaired)) {
    repaired.rewardedAdsWatchedToday = 0;
  }

  if (!("dailyResetAt" in repaired)) {
    repaired.dailyResetAt = new Date();
  }

  if (!("activeRewardTokens" in repaired)) {
    repaired.activeRewardTokens = {};
  }

  if (!("regionTierAppVersion" in repaired)) {
    repaired.regionTierAppVersion = "";
  }

  if (!("recentRequestTimestamps" in repaired)) {
    repaired.recentRequestTimestamps = [];
  }

  if (!("recentPrompts" in repaired)) {
    repaired.recentPrompts = [];
  }

  console.warn(
      `🔧 User document auto-repaired | Fields added: ${validation.missingFields.join(", ")}`,
  );

  return repaired;
}

/**
 * Ensure user document structure before using in logic
 * Combines validation and repair
 * @param {object} userDoc - User document from Firestore
 * @return {object} - { user: object, wasRepaired: boolean }
 */
function ensureValidUserDocument(userDoc) {
  const validation = validateUserDocument(userDoc);

  if (validation.valid) {
    return {
      user: userDoc,
      wasRepaired: false,
    };
  }

  const repaired = repairUserDocument(userDoc);

  return {
    user: repaired,
    wasRepaired: true,
  };
}

/**
 * Validate counter values are within reasonable bounds
 * Prevents overflow/underflow exploits
 * @param {object} counters - Counter object
 * @param {object} limits - User limits
 * @return {object} - { valid: boolean, errors: Array }
 */
function validateCounterBounds(counters, limits) {
  if (!counters || !limits) {
    return {
      valid: true, // Skip if data missing
      errors: [],
    };
  }

  const errors = [];
  const safetyMargin = 2; // Allow 2x limit as safety buffer

  if (counters.aiNanoUsedToday > limits.dailyAiLimit * safetyMargin) {
    errors.push(
        `aiNanoUsedToday (${counters.aiNanoUsedToday}) exceeds safe limit ` +
        `(${limits.dailyAiLimit * safetyMargin})`,
    );
  }

  if (counters.aiMiniUsedToday > limits.dailyAiLimit * safetyMargin) {
    errors.push(
        `aiMiniUsedToday (${counters.aiMiniUsedToday}) exceeds safe limit ` +
        `(${limits.dailyAiLimit * safetyMargin})`,
    );
  }

  if (counters.rewardedAdsWatchedToday > limits.dailyRewardedLimit * safetyMargin) {
    errors.push(
        `rewardedAdsWatchedToday (${counters.rewardedAdsWatchedToday}) exceeds safe limit ` +
        `(${limits.dailyRewardedLimit * safetyMargin})`,
    );
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

module.exports = {
  createUserDocument,
  validateUserDocument,
  repairUserDocument,
  ensureValidUserDocument,
  validateCounterBounds,
};
