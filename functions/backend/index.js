/**
 * Firebase Cloud Functions Entry Point
 * Registers all monetization endpoints and scheduled functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

// Import analytics initializer
const analyticsModule = require("./common/analytics");

// Import security modules
const resetLock = require("./security/resetLock");
const failsafe = require("./security/failsafe");
const remoteConfigHelper = require("./common/remoteConfigHelper");

// Import Cloud Function endpoints
const generateAi = require("./endpoints/generateAi");
const claimReward = require("./endpoints/claimReward");
const testCheatProUpgrade = require("./endpoints/testCheatProUpgrade");

// Import Firestore triggers
const onUserCreate = require("./triggers/onUserCreate");

// Initialize Firebase
initializeApp();
const db = getFirestore();

setGlobalOptions({maxInstances: 1}); // Resource optimization

// ════════════════════════════════════════════════════════════════
// ANALYTICS INITIALIZATION
// ════════════════════════════════════════════════════════════════

logger.info("🚀 Initializing Firebase Analytics...");
analyticsModule.initAnalytics(require("firebase-admin/app").getApps()[0]);

// ════════════════════════════════════════════════════════════════
// REMOTE CONFIG INITIALIZATION (M.3: Tier Disable)
// ════════════════════════════════════════════════════════════════

logger.info("🚀 Initializing Remote Config...");
remoteConfigHelper.initRemoteConfig().then((success) => {
  if (success) {
    logger.info("✅ Remote Config initialized for tier disable failsafe");
  }
}).catch((err) => {
  logger.warn(`⚠️ Remote Config init failed: ${err.message}`);
});

// ════════════════════════════════════════════════════════════════
// FAILSAFE STATE RESTORATION (M.3: Persist Failsafe)
// ════════════════════════════════════════════════════════════════

logger.info("🚀 Loading failsafe state from Firestore...");
failsafe.loadFailsafeStateOnStartup().then(() => {
  logger.info("✅ Failsafe state loaded");
}).catch((err) => {
  logger.warn(`⚠️ Failsafe state load failed: ${err.message}`);
});

// ════════════════════════════════════════════════════════════════
// SCHEDULED FUNCTION: Daily Reset at 12:00 AM GMT+5
// ════════════════════════════════════════════════════════════════

const resetDailyLimitsHandler = async () => {
  logger.info("🔄 Daily reset started (12:00 AM Asia/Karachi)");

  try {
    // ════════════════════════════════════════════════════════════════
    // STEP 1: ACQUIRE RESET LOCK (PREVENT RACE CONDITIONS)
    // ════════════════════════════════════════════════════════════════

    const lockResult = await resetLock.acquireResetLock();
    if (!lockResult.success) {
      logger.error("❌ Failed to acquire reset lock, aborting reset");
      return;
    }

    logger.info("🔒 Reset lock acquired - all AI requests temporarily blocked");

    // Fetch Remote Config for reset behavior (optional)
    // Can control reset via Remote Config if needed

    // Query users that have non-zero counters (optimization)
    const usersRef = db.collection("users");
    const usersSnapshot = await usersRef.get();

    if (usersSnapshot.empty) {
      logger.info("✅ No users in system");
      await resetLock.releaseResetLock();
      return;
    }

    logger.info(`📊 Processing ${usersSnapshot.size} users for daily reset`);

    const batch = db.batch();
    let resetCount = 0;

    usersSnapshot.docs.forEach((doc) => {
      const userData = doc.data();

      // Only reset if user has been active
      if (
        userData.aiNanoUsedToday > 0 ||
          userData.aiMiniUsedToday > 0 ||
          userData.rewardedAdsWatchedToday > 0
      ) {
        batch.update(doc.ref, {
          aiNanoUsedToday: 0,
          aiMiniUsedToday: 0,
          rewardedAdsWatchedToday: 0,
          claimedRewards: null,
          activeRewardTokens: null,
          recentPrompts: null,
          recentRequestTimestamps: null,
          dailyResetAt: FieldValue.serverTimestamp(),
        });

        resetCount++;
      }
    });

    if (resetCount > 0) {
      await batch.commit();
      logger.info(`🎉 Daily reset complete | Total reset: ${resetCount}`);
    } else {
      logger.info("✅ No resets needed today");
    }

    // ════════════════════════════════════════════════════════════════
    // STEP 1.5: PERSIST FAILSAFE STATE (M.3)
    // ════════════════════════════════════════════════════════════════

    await failsafe.persistFailsafeState();
    logger.info("✅ Failsafe state persisted to Firestore");

    // ════════════════════════════════════════════════════════════════
    // STEP 2: RELEASE RESET LOCK
    // ════════════════════════════════════════════════════════════════

    await resetLock.releaseResetLock();
    logger.info("🔓 Reset lock released - AI requests can resume");
  } catch (error) {
    logger.error("❌ Daily reset failed", error);

    // Ensure lock is released even on error
    try {
      await resetLock.releaseResetLock();
      logger.info("🔓 Reset lock released after error");
    } catch (lockError) {
      logger.error("❌ Failed to release reset lock", lockError);
    }
  }
};

exports.resetDailyLimitsScheduled = onSchedule(
    {
      schedule: "0 0 * * *", // 12:00 AM every day
      timeZone: "Asia/Karachi",
    },
    resetDailyLimitsHandler,
);

// ════════════════════════════════════════════════════════════════
// CLOUD FUNCTION ENDPOINTS - HTTP TRIGGERS
// ════════════════════════════════════════════════════════════════

const {onRequest} = require("firebase-functions/v2/https");

// ════════════════════════════════════════════════════════════════
// FIRESTORE TRIGGERS
// ════════════════════════════════════════════════════════════════

/**
 * Trigger: onCreate users/{userId}
 * Auto-resolve regionTier when a new user document is created
 */
exports.onUserCreated = onDocumentCreated(
    "users/{userId}",
    async (event) => {
      await onUserCreate.handleUserCreate(event.data, event);
    },
);

// ════════════════════════════════════════════════════════════════
// API ENDPOINTS
// ════════════════════════════════════════════════════════════════

/**
 * POST /api/generateAi
 * Main AI generation endpoint
 * Request: { prompt, conversationHistory, quality?, rewardGrantToken? }
 * Response: { success, response, model, accessMethod }
 */
exports.generateAi = generateAi;

/**
 * POST /api/claimReward
 * Claim rewarded ad unlock
 * Request: { rewardId, rewardToken }
 * Response: { success, rewardGrantToken, aiUnlocksGranted }
 */
exports.claimReward = claimReward;

/**
 * POST /api/testCheatProUpgrade
 * Test cheat endpoint to enable PRO (Tier-1 only)
 * Request: (empty)
 * Response: { success, message, plan, userId, tier }
 */
exports.testCheatProUpgrade = onRequest(
    {region: "europe-west1"},
    testCheatProUpgrade,
);

// ════════════════════════════════════════════════════════════════
// HEALTH CHECK ENDPOINT (optional, for monitoring)
// ════════════════════════════════════════════════════════════════

exports.health = onRequest(
    {region: "us-central1"},
    (req, res) => {
      res.status(200).json({
        status: "healthy",
        version: "1.0.0",
        timestamp: new Date().toISOString(),
      });
    },
);

// ════════════════════════════════════════════════════════════════
// LOGGING ON STARTUP
// ════════════════════════════════════════════════════════════════

logger.info("✅ Cloud Functions initialized");
logger.info("📝 Registered endpoints:");
logger.info("  - POST /api/generateAi (AI generation)");
logger.info("  - POST /api/claimReward (Reward claiming)");
logger.info("  - POST /api/testCheatProUpgrade (Test cheat: Enable PRO)");
logger.info("  - GET /health (Health check)");
logger.info("  - TRIGGER: onUserCreated (Auto-resolve regionTier)");
logger.info("  - SCHEDULED: Daily reset at 00:00 GMT+5");
