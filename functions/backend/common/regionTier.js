/**
 * Region Tier Resolver
 * Spec: 1.1 REGION TIER RESOLUTION (ANTI-VPN)
 *
 * Determines user tier as the LOWEST of:
 * 1. App Store / Play Store country (primary)
 * 2. Device locale (secondary)
 * 3. IP-based region (fallback)
 *
 * If mismatch detected → downgrade to lowest tier
 */

const config = require("../config");

/**
 * Determine tier ranking (lower = more restrictive)
 * @param {string} countryCode - ISO-3166 country code (e.g., "US", "IN")
 * @return {number} - Tier ranking (0 = Tier-1, 1 = Tier-2, 2 = Tier-3)
 */
function getTierRank(countryCode) {
  const code = countryCode?.toUpperCase();

  if (config.TIER_1_COUNTRIES.includes(code)) {
    return 0; // Tier-1 (highest value)
  } else if (config.TIER_2_COUNTRIES.includes(code)) {
    return 1; // Tier-2 (mid value)
  } else if (config.TIER_3_COUNTRIES.includes(code)) {
    return 2; // Tier-3 (lowest value)
  }

  // Unknown country defaults to Tier-3 (most restrictive)
  return 2;
}

/**
 * Convert tier rank to tier string
 * @param {number} rank - 0, 1, or 2
 * @return {string} - "tier1", "tier2", or "tier3"
 */
function rankToTier(rank) {
  const tiers = ["tier1", "tier2", "tier3"];
  return tiers[rank] || "tier3";
}

/**
 * Resolve user's region tier (takes lowest/most restrictive)
 * @param {object} userData - User data object
 * @param {string} userData.storeCountry - App Store / Play Store country (primary)
 * @param {string} userData.deviceLocale - Device locale country code (secondary)
 * @param {string} userData.ipCountry - IP-detected country (fallback)
 * @return {string} - "tier1", "tier2", or "tier3"
 */
function resolveRegionTier(userData) {
  if (!userData) {
    console.warn("⚠️ Missing user data for tier resolution, defaulting to tier3");
    return "tier3";
  }

  const {storeCountry, deviceLocale, ipCountry} = userData;

  // Get ranks for each region (lower = more restrictive)
  const storeRank = getTierRank(storeCountry);
  const deviceRank = getTierRank(deviceLocale);
  const ipRank = getTierRank(ipCountry);

  // Take the LOWEST tier (most restrictive)
  const lowestRank = Math.max(storeRank, deviceRank, ipRank);
  const resolvedTier = rankToTier(lowestRank);

  // Detect mismatch (anti-VPN)
  const hasMismatch = !(storeRank === deviceRank && deviceRank === ipRank);

  if (hasMismatch) {
    console.warn(
        `🚨 Region mismatch detected | Store: ${storeCountry}(${storeRank}), ` +
        `Device: ${deviceLocale}(${deviceRank}), IP: ${ipCountry}(${ipRank}). ` +
        `Downgrading to ${resolvedTier}`,
    );
  }

  return resolvedTier;
}

/**
 * Verify tier matches user's actual location (anti-fraud check)
 * Returns false if suspicion levels are high
 * @param {string} tier - Current user tier
 * @param {object} geoData - Current geolocation data
 * @return {boolean} - true if tier is valid, false if suspicious
 */
function isTierValid(tier, geoData) {
  if (!tier || !geoData) return false;

  const currentRank = getTierRank(geoData.country);
  const tierRank = tier === "tier1" ? 0 : tier === "tier2" ? 1 : 2;

  // If user's current location is HIGHER tier than assigned tier → okay (conservative)
  // If user's current location is LOWER tier than assigned tier → SUSPICIOUS (VPN flag)
  const isSuspicious = currentRank > tierRank;

  if (isSuspicious) {
    console.warn(
        `⚠️ Tier validity check failed | Assigned: ${tier}(${tierRank}), ` +
        `Current location: ${geoData.country}(${currentRank})`,
    );
  }

  return !isSuspicious;
}

module.exports = {
  resolveRegionTier,
  isTierValid,
  getTierRank,
  rankToTier,
};
