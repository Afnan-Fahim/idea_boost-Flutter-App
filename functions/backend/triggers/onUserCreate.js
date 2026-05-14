/**
 * Firestore Trigger: On User Document Creation
 * Automatically resolves regionTier when a new user is created
 */
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const regionTierResolver = require("../common/regionTier");
const trialKeyValidator = require("../non-pro/trialKeyValidator");
const config = require("../config");

/**
 * Triggered when a new user document is created
 * Resolves regionTier based on deviceLocale/storeCountry
 * @param {object} snapshot - Firestore snapshot
 * @param {object} context - Event context
 */
async function handleUserCreate(snapshot, context) {
  const userId = context.params.userId;
  const userData = snapshot.data();

  logger.info(`🆕 New user created: ${userId}`);

  try {
    // Check if regionTier is already set
    if (userData.regionTier && userData.regionTier !== "") {
      logger.info(`✅ User ${userId} already has regionTier: ${userData.regionTier}`);
      return;
    }

    // Resolve tier from region data
    const resolvedTier = regionTierResolver.resolveRegionTier({
      storeCountry: userData.storeCountry,
      deviceLocale: userData.deviceLocale,
      ipCountry: userData.ipCountry,
    });

    logger.info(
        `🌍 Region tier resolved for user ${userId}: ${resolvedTier} | ` +
        `Store: ${userData.storeCountry || "N/A"}, ` +
        `Device: ${userData.deviceLocale || "N/A"}, ` +
        `IP: ${userData.ipCountry || "N/A"}`,
    );

    // ════════════════════════════════════════════════════════════════════════
    // CHECK: Device-level trial eligibility (anti-farming via trialKey)
    // ════════════════════════════════════════════════════════════════════════
    let allowTrial = true;
    const trialKey = userData.trialKey;

    if (!trialKey) {
      logger.warn(`⚠️ User ${userId} missing trialKey - trial disabled`);
      allowTrial = false;
    } else {
      const db = getFirestore();

      // CHECK 1: Global registry (most reliable)
      const keyCheck = await trialKeyValidator.checkTrialKeyUsage(trialKey);
      if (keyCheck.alreadyUsed) {
        logger.warn(
            `🚫 Device ${trialKey.substring(0, 8)}... already used trial (global registry). ` +
            `Previous users: ${keyCheck.usedBy.join(", ")}. Trial disabled.`,
        );
        allowTrial = false;
      } else {
        // CHECK 2: Verify against all user documents (belt-and-suspenders)
        // Exclude current user - only check for OTHER users with same trialKey
        const allUsersWithKey = await db
            .collection("users")
            .where("trialKey", "==", trialKey)
            .get();

        const otherUsersWithKey = allUsersWithKey.docs.filter((doc) => doc.id !== userId);

        if (otherUsersWithKey.length > 0) {
          const existingUser = otherUsersWithKey[0];
          logger.warn(
              `🚫 Device ${trialKey.substring(0, 8)}... already exists on another account. ` +
              `Previous user: ${existingUser.id}. Trial disabled.`,
          );
          allowTrial = false;
        } else {
          logger.info(`✅ Device ${trialKey.substring(0, 8)}... eligible for trial (first-time)`);
        }
      }
    }

    let tierConfig;

    if (resolvedTier === "tier1") {
      logger.info(`🎯 Tier-1 user setup | Trial: ${allowTrial ? config.TRIAL.tier1 : 0}, Daily Limit: 4, Max Ads: 2`);
      tierConfig = {
        trialGenerationsAvailable: allowTrial ? config.TRIAL.tier1 : 0,
        dailyAiLimit: config.DAILY_AI_LIMITS.tier1,
        maxRewardedAdsPerDay: config.REWARDED_ADS.tier1.max_per_day,
        aiPerRewardedAd: config.REWARDED_ADS.tier1.ai_per_reward,
      };
    } else if (resolvedTier === "tier2") {
      logger.info(`🎯 Tier-2 user setup | Trial: ${allowTrial ? config.TRIAL.tier2 : 0}, Daily Limit: 3, Max Ads: 3`);
      tierConfig = {
        trialGenerationsAvailable: allowTrial ? config.TRIAL.tier2 : 0,
        dailyAiLimit: config.DAILY_AI_LIMITS.tier2,
        maxRewardedAdsPerDay: config.REWARDED_ADS.tier2.max_per_day,
        aiPerRewardedAd: config.REWARDED_ADS.tier2.ai_per_reward,
      };
    } else if (resolvedTier === "tier3") {
      logger.info(`🎯 Tier-3 user setup | Trial: 0, Daily Limit: 3, Max Ads: 3`);
      tierConfig = {
        trialGenerationsAvailable: 0, // tier3 never gets trial
        dailyAiLimit: config.DAILY_AI_LIMITS.tier3,
        maxRewardedAdsPerDay: config.REWARDED_ADS.tier3.max_per_day,
        aiPerRewardedAd: config.REWARDED_ADS.tier3.ai_per_reward,
      };
    }

    // Update user document with resolved tier and tier-specific config
    const db = getFirestore();
    await db.collection("users").doc(userId).update({
      regionTier: resolvedTier,
      regionTierResolvedAt: new Date(),
      trialGenerationsAvailable: tierConfig.trialGenerationsAvailable,
      dailyAiLimit: tierConfig.dailyAiLimit,
      maxRewardedAdsPerDay: tierConfig.maxRewardedAdsPerDay,
      aiPerRewardedAd: tierConfig.aiPerRewardedAd,
      trialEligibility: allowTrial ? "eligible" : "ineligible", // For debugging
    });

    // ════════════════════════════════════════════════════════════════════════
    // RESERVE TRIAL KEY (Prevent cross-account trial farming on same device)
    // ════════════════════════════════════════════════════════════════════════
    // If user is eligible for trial, immediately register the trialKey globally
    // This blocks other accounts on the same device from also claiming a trial
    if (allowTrial && trialKey) {
      try {
        await trialKeyValidator.registerTrialKeyUsage(trialKey, userId);
        logger.info(`🔐 Trial key reserved for user ${userId} (prevents cross-account reuse)`);
      } catch (err) {
        logger.warn(`⚠️ Failed to reserve trial key: ${err.message}`);
        // Don't fail the user creation if reservation fails
      }
    }

    logger.info(`✅ Region tier set for user ${userId}: ${resolvedTier}`);
  } catch (error) {
    logger.error(`❌ Error resolving tier for user ${userId}:`, error);
    // Don't throw - allow user creation to succeed even if tier resolution fails
  }
}

module.exports = {
  handleUserCreate,
};
