/**
 * Remote Config Helper
 * Safely fetches configuration from Firebase Remote Config
 * with fallback defaults and error handling
 *
 * Spec: M.3 - Tier-2/3 Instant Remote Config Disable
 */

const {getRemoteConfig} = require("firebase-admin/remote-config");
const logger = require("firebase-functions/logger");

/**
 * Cache for Remote Config values (in-memory)
 * Prevents excessive API calls
 */
let remoteConfigCache = {
  timestamp: null,
  values: {},
  ttlMs: 1 * 1000, // 1 second cache (for testing - change to 5*60*1000 for production)
};

/**
 * Initialize Remote Config (called once at startup)
 */
async function initRemoteConfig() {
  try {
    logger.info("🔧 Initializing Remote Config...");
    const remoteConfig = getRemoteConfig();
    await remoteConfig.getTemplate();
    logger.info("✅ Remote Config initialized successfully");
    return true;
  } catch (error) {
    logger.warn(`⚠️ Remote Config init failed: ${error.message}`);
    return false;
  }
}

/**
 * Get a Remote Config value with fallback
 * @param {string} key - Config parameter name
 * @param {*} defaultValue - Fallback value if fetch fails
 * @return {*} - Config value or default
 */
async function getRemoteConfigValue(key, defaultValue) {
  try {
    // Check cache first
    if (isCacheValid()) {
      if (Object.prototype.hasOwnProperty.call(remoteConfigCache.values, key)) {
        logger.debug(`📦 Remote Config cache hit: ${key}`);
        return remoteConfigCache.values[key];
      }
    } else {
      // Cache expired — clear ALL stale values so no old keys linger
      remoteConfigCache.values = {};
      remoteConfigCache.timestamp = null;
    }

    // Fetch from Remote Config with timeout
    const remoteConfig = getRemoteConfig();
    const template = await remoteConfig.getTemplate();

    if (!template.parameters[key]) {
      logger.warn(`⚠️ Remote Config key not found: ${key}, using default: ${defaultValue}`);
      return defaultValue;
    }

    const value = template.parameters[key].defaultValue?.value;

    if (value === undefined || value === null) {
      logger.warn(`⚠️ Remote Config key has no value: ${key}, using default: ${defaultValue}`);
      return defaultValue;
    }

    // Parse boolean strings if needed
    let parsedValue = value;
    if (typeof defaultValue === "boolean" && typeof value === "string") {
      parsedValue = value.toLowerCase() === "true";
    }
    // Parse numeric strings if needed
    if (typeof defaultValue === "number" && typeof value === "string") {
      parsedValue = parseInt(value, 10);
    }

    // Update cache
    remoteConfigCache.values[key] = parsedValue;
    remoteConfigCache.timestamp = Date.now();

    logger.info(`✅ Remote Config fetched: ${key} = ${parsedValue}`);
    return parsedValue;
  } catch (error) {
    logger.error(`❌ Remote Config fetch failed for ${key}: ${error.message}`);
    logger.warn(`⚠️ Falling back to default value for ${key}: ${defaultValue}`);
    return defaultValue;
  }
}

/**
 * Check if cache is still valid
 */
function isCacheValid() {
  if (!remoteConfigCache.timestamp) return false;
  const age = Date.now() - remoteConfigCache.timestamp;
  return age < remoteConfigCache.ttlMs;
}

/**
 * Clear cache (useful for testing)
 */
function clearCache() {
  remoteConfigCache = {
    timestamp: null,
    values: {},
    ttlMs: 5 * 60 * 1000,
  };
  logger.info("🔄 Remote Config cache cleared");
}

/**
 * Fetch failsafe configuration
 * @return {object} - Failsafe settings from Remote Config
 */
async function getFailsafeConfig() {
  return {
    failsafeModeEnabled: await getRemoteConfigValue(
        "failsafeModeEnabled",
        false, // Default: failsafe disabled (safe)
    ),
    adsEnabled_tier1: await getRemoteConfigValue(
        "adsEnabled_tier1",
        true, // Default: Tier-1 ads enabled
    ),
    adsEnabled_tier2: await getRemoteConfigValue(
        "adsEnabled_tier2",
        true, // Default: Tier-2 ads enabled
    ),
    adsEnabled_tier3: await getRemoteConfigValue(
        "adsEnabled_tier3",
        true, // Default: Tier-3 ads enabled
    ),
  };
}

/**
 * Check if ads are enabled for a specific tier
 * @param {string} tier - "tier1", "tier2", or "tier3"
 * @return {boolean} - true if ads enabled, false if disabled
 */
async function areAdsEnabledForTier(tier) {
  const failsafeConfig = await getFailsafeConfig();

  switch (tier) {
    case "tier1":
      return failsafeConfig.adsEnabled_tier1;
    case "tier2":
      return failsafeConfig.adsEnabled_tier2;
    case "tier3":
      return failsafeConfig.adsEnabled_tier3;
    default:
      logger.warn(`⚠️ Unknown tier: ${tier}, defaulting to true`);
      return true;
  }
}

/**
 * Get all failsafe settings
 * @return {object} - Complete failsafe configuration
 */
async function getAllFailsafeSettings() {
  try {
    const remoteConfig = getRemoteConfig();
    const template = await remoteConfig.getTemplate();

    const settings = {};
    const failsafeKeys = [
      "failsafeModeEnabled",
      "adsEnabled_tier1",
      "adsEnabled_tier2",
      "adsEnabled_tier3",
      "fillRateThreshold_tier2",
      "fillRateThreshold_tier3",
    ];

    for (const key of failsafeKeys) {
      if (template.parameters[key]) {
        settings[key] = template.parameters[key].defaultValue?.value;
      }
    }

    logger.info(`✅ Fetched all failsafe settings: ${Object.keys(settings).length} parameters`);
    return settings;
  } catch (error) {
    logger.error(`❌ Failed to get all failsafe settings: ${error.message}`);
    return {};
  }
}

/**
 * Check if a specific tier has ads disabled via Remote Config
 * @param {string} tier - "tier1", "tier2", or "tier3"
 * @return {boolean} - true if tier is disabled, false if enabled
 */
async function isTierDisabledInRemoteConfig(tier) {
  const adsEnabled = await areAdsEnabledForTier(tier);
  const isDisabled = !adsEnabled;

  if (isDisabled) {
    logger.warn(`🚨 Tier ${tier} disabled via Remote Config`);
  }

  return isDisabled;
}

module.exports = {
  initRemoteConfig,
  getRemoteConfigValue,
  getFailsafeConfig,
  areAdsEnabledForTier,
  isTierDisabledInRemoteConfig,
  getAllFailsafeSettings,
  clearCache, // Export for testing
};
