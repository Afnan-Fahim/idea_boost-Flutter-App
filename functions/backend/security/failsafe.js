/**
 * AdMob Failsafe Mode
 * Spec: 6.2 ADMOB FAILSAFE MODE & I) AdMob Failsafe Mode
 *
 * If ANY trigger fires:
 * - Disable rewarded ads for Tier-2/3
 * - Lock AI for non-PRO users
 * - Tier-1 PRO users remain unaffected
 */

const config = require("../config");
const remoteConfigHelper = require("../common/remoteConfigHelper");
const logger = require("firebase-functions/logger");

/**
 * Failsafe state tracker
 * Persisted in Firestore or Remote Config
 */
class FailsafeManager {
  constructor() {
    this.isActive = false;
    this.triggerReason = null;
    this.triggeredAt = null;
    this.affectedTiers = ["tier2", "tier3"];
  }

  /**
   * Activate failsafe mode
   * @param {string} reason - Why failsafe was triggered
   */
  activate(reason) {
    this.isActive = true;
    this.triggerReason = reason;
    this.triggeredAt = new Date();

    console.error(`🚨 FAILSAFE ACTIVATED | Reason: ${reason}`);

    // Log to analytics/monitoring
    // sendFailsafeAlert(reason);
  }

  /**
   * Deactivate failsafe mode (manual or after TTL)
   */
  deactivate() {
    this.isActive = false;
    this.triggerReason = null;
    this.triggeredAt = null;

    console.warn("✅ Failsafe deactivated");
  }

  /**
   * Get current failsafe state
   */
  getState() {
    return {
      isActive: this.isActive,
      reason: this.triggerReason,
      triggeredAt: this.triggeredAt,
      affectedTiers: this.affectedTiers,
    };
  }
}

const failsafeManager = new FailsafeManager();

/**
 * Check fill rate for ad serving viability
 * Trigger failsafe if fill rate too low
 * @param {object} adMetrics - Ad performance metrics
 * @return {object} - { shouldTrigger: boolean, reason?: string, fillRate: number }
 */
function checkFillRate(adMetrics) {
  if (!adMetrics || adMetrics.impressions === 0) {
    return {
      shouldTrigger: false,
      fillRate: 0,
    };
  }

  const fillRate = adMetrics.impressions / adMetrics.requests;
  const threshold = config.FAILSAFE.fill_rate_threshold;

  if (fillRate < threshold) {
    return {
      shouldTrigger: true,
      reason: `Fill rate ${fillRate.toFixed(2)} below threshold ${threshold}`,
      fillRate,
      threshold,
    };
  }

  return {
    shouldTrigger: false,
    fillRate,
    threshold,
  };
}

/**
 * Detect AdMob account warnings/suspensions
 * @param {object} admobStatus - AdMob account status from API
 * @return {object} - { shouldTrigger: boolean, reason?: string }
 */
function checkAdmobAccountStatus(admobStatus) {
  if (!admobStatus) {
    return {
      shouldTrigger: false,
    };
  }

  const warnings = admobStatus.warnings || [];
  if (warnings.length > 0) {
    return {
      shouldTrigger: true,
      reason: `AdMob account warnings: ${warnings.join(", ")}`,
      warnings,
    };
  }

  if (admobStatus.suspended) {
    return {
      shouldTrigger: true,
      reason: "AdMob account suspended",
    };
  }

  return {
    shouldTrigger: false,
  };
}

/**
 * Detect suspicious rewarded spike (fraud detection)
 * @param {object} rewardMetrics - Recent reward metrics
 * @return {object} - { shouldTrigger: boolean, reason?: string }
 */
function checkRewardSpike(rewardMetrics) {
  if (!rewardMetrics) {
    return {
      shouldTrigger: false,
    };
  }

  // Example: detect if reward clicks 3x higher than baseline in 1 hour
  const baseline = rewardMetrics.hourlyBaseline || 100;
  const current = rewardMetrics.lastHourClicks || 0;
  const spikeThreshold = 3;

  if (current > baseline * spikeThreshold) {
    return {
      shouldTrigger: true,
      reason: `Reward spike detected (${current} vs baseline ${baseline})`,
      spikeMultiplier: current / baseline,
    };
  }

  return {
    shouldTrigger: false,
  };
}

/**
 * Check if AI was executed without server-approved reward
 * Critical security violation
 * @param {string} rewardGrantToken - Token from request
 * @param {boolean} hasApprovedReward - Whether server approved reward
 * @return {object} - { shouldTrigger: boolean, reason?: string }
 */
function checkUnauthorizedAiExecution(rewardGrantToken, hasApprovedReward) {
  // If request includes reward token but server didn't approve it
  if (rewardGrantToken && !hasApprovedReward) {
    return {
      shouldTrigger: true,
      reason: "AI executed with unapproved reward token - security violation",
    };
  }

  return {
    shouldTrigger: false,
  };
}

/**
 * Perform all failsafe checks
 * @param {object} checks - All check data
 * @return {object} - { shouldTrigger: boolean, reason?: string, violations: number }
 */
function performFailsafeChecks(checks) {
  if (!checks) {
    return {
      shouldTrigger: false,
      violations: 0,
    };
  }

  const violations = [];

  // Check 1: Fill rate
  if (checks.adMetrics) {
    const fillRateCheck = checkFillRate(checks.adMetrics);
    if (fillRateCheck.shouldTrigger) {
      violations.push(fillRateCheck.reason);
    }
  }

  // Check 2: AdMob account status
  if (checks.admobStatus) {
    const statusCheck = checkAdmobAccountStatus(checks.admobStatus);
    if (statusCheck.shouldTrigger) {
      violations.push(statusCheck.reason);
    }
  }

  // Check 3: Reward spike
  if (checks.rewardMetrics) {
    const spikeCheck = checkRewardSpike(checks.rewardMetrics);
    if (spikeCheck.shouldTrigger) {
      violations.push(spikeCheck.reason);
    }
  }

  // Check 4: Unauthorized AI execution
  if (checks.rewardGrantToken !== undefined) {
    const authCheck = checkUnauthorizedAiExecution(
        checks.rewardGrantToken,
        checks.hasApprovedReward,
    );
    if (authCheck.shouldTrigger) {
      violations.push(authCheck.reason);
    }
  }

  return {
    shouldTrigger: violations.length > 0,
    reason: violations.join(" | "),
    violations: violations.length,
  };
}

/**
 * Apply failsafe restrictions to user access
 * Now checks Remote Config for tier-specific disable status
 * @param {object} user - User document
 * @return {object} - { canAccessRewards: boolean, canAccessAi: boolean, reason?: string }
 */
async function applyFailsafeRestrictions(user) {
  if (!user) {
    return {
      canAccessRewards: true,
      canAccessAi: true,
    };
  }

  // Get Remote Config status
  const failsafeConfig = await remoteConfigHelper.getFailsafeConfig();
  const failsafeActive = failsafeManager.isActive || failsafeConfig.failsafeModeEnabled;

  // Tier-1 PRO users unaffected
  if (user.isPro && user.regionTier === "tier1") {
    return {
      canAccessRewards: true,
      canAccessAi: true,
      reason: "Tier-1 PRO exempted from failsafe",
    };
  }

  // Check if tier is specifically disabled in Remote Config
  if (user.regionTier === "tier2" && !failsafeConfig.adsEnabled_tier2) {
    logger.warn(`🚨 Tier-2 ads disabled via Remote Config for user: ${user.userId}`);
    return {
      canAccessRewards: false,
      canAccessAi: false,
      reason: "Tier-2 ads disabled via Remote Config",
    };
  }

  if (user.regionTier === "tier3" && !failsafeConfig.adsEnabled_tier3) {
    logger.warn(`🚨 Tier-3 ads disabled via Remote Config for user: ${user.userId}`);
    return {
      canAccessRewards: false,
      canAccessAi: false,
      reason: "Tier-3 ads disabled via Remote Config",
    };
  }

  // Apply general failsafe
  if (failsafeActive && failsafeManager.affectedTiers.includes(user.regionTier)) {
    return {
      canAccessRewards: false,
      canAccessAi: false,
      reason: failsafeManager.triggerReason,
    };
  }

  // Tier-1 non-PRO: can use PRO or... blocked from rewarded
  if (user.regionTier === "tier1" && !user.isPro) {
    return {
      canAccessRewards: false, // No more rewarded ads
      canAccessAi: user.isPro, // Only via PRO
      reason: "Rewarded ads disabled due to failsafe",
    };
  }

  return {
    canAccessRewards: true,
    canAccessAi: true,
  };
}

/**
 * Get failsafe status for client
 * Now checks Remote Config for tier disable status
 * @return {object} - Failsafe status for UI
 */
async function getFailsafeStatus() {
  const state = failsafeManager.getState();
  const failsafeConfig = await remoteConfigHelper.getFailsafeConfig();

  // Check if failsafe is active OR failsafe mode is enabled in Remote Config
  const failsafeActive = state.isActive || failsafeConfig.failsafeModeEnabled;

  return {
    failsafeActive: failsafeActive,
    rewardsDisabled: failsafeActive,
    aiLocked: failsafeActive,
    failsafeConfig: failsafeConfig,
    message: failsafeActive ?
        "Our ad system is temporarily unavailable. Please try again later." :
        null,
  };
}

/**
 * Check if a specific tier has ads disabled via Remote Config
 * @param {string} tier - "tier1", "tier2", or "tier3"
 * @return {boolean} - true if tier is disabled, false if enabled
 */
async function isTierDisabledInRemoteConfig(tier) {
  const adsEnabled = await remoteConfigHelper.areAdsEnabledForTier(tier);
  const isDisabled = !adsEnabled;

  if (isDisabled) {
    logger.warn(`🚨 Tier ${tier} disabled via Remote Config`);
  }

  return isDisabled;
}

/**
 * Persist failsafe state to Firestore
 * Survives server restarts
 */
async function persistFailsafeState() {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    const state = failsafeManager.getState();

    await db.collection("system").doc("failsafeState").set({
      isActive: state.isActive,
      reason: state.reason,
      triggeredAt: state.triggeredAt,
      affectedTiers: state.affectedTiers,
      updatedAt: new Date(),
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24hr TTL
    }, {merge: true});

    logger.info(`✅ Failsafe state persisted: isActive=${state.isActive}`);
  } catch (error) {
    logger.error(`❌ Failed to persist failsafe state: ${error.message}`);
  }
}

/**
 * Load failsafe state from Firestore on startup
 */
async function loadFailsafeStateOnStartup() {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    const doc = await db.collection("system").doc("failsafeState").get();
    if (!doc.exists) {
      logger.info("✅ No persisted failsafe state found (normal on first startup)");
      return;
    }

    const data = doc.data();
    if (data.isActive && data.expiresAt.toDate() > new Date()) {
      failsafeManager.isActive = data.isActive;
      failsafeManager.triggerReason = data.reason;
      failsafeManager.triggeredAt = data.triggeredAt;
      logger.warn(`⚠️ Failsafe restored from Firestore: ${data.reason}`);
    } else {
      logger.info("✅ Persisted failsafe state expired or inactive");
    }
  } catch (error) {
    logger.error(`❌ Failed to load failsafe state: ${error.message}`);
  }
}

module.exports = {
  failsafeManager,
  checkFillRate,
  checkAdmobAccountStatus,
  checkRewardSpike,
  checkUnauthorizedAiExecution,
  performFailsafeChecks,
  applyFailsafeRestrictions,
  getFailsafeStatus,
  isTierDisabledInRemoteConfig,
  persistFailsafeState,
  loadFailsafeStateOnStartup,
};
