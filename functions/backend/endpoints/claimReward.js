/**
 * Cloud Function: Claim Reward
 * HTTP Trigger Endpoint: POST /api/claimReward
 *
 * Spec: H1) Reward Granting (CRITICAL)
 * Called AFTER user completes rewarded ad
 * Returns one-time rewardGrantToken to use in generateAi endpoint
 */

const {onRequest} = require("firebase-functions/v2/https");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

// Internal modules
const rewardValidator = require("../validators/rewardValidator");
const dailyLimitValidator = require("../validators/dailyLimitValidator");
const counters = require("../common/counters");
const analytics = require("../common/analytics");
const firestoreSchema = require("../security/firestoreSchema");
const failsafe = require("../security/failsafe");
const rewardedValidation = require("../non-pro/rewardedValidation");
const rewardTokenManager = require("../non-pro/rewardTokenManager");
const remoteConfigHelper = require("../common/remoteConfigHelper");

/**
 * Claim rewarded ad unlock
 * Request body:
 * {
 *   rewardId: string (unique from AdMob),
 *   rewardToken: string (from onUserEarnedReward callback),
 * }
 */
async function claimRewardHandler(req, res) {
  const db = getFirestore();
  let userId;
  // ════════════════════════════════════════════════════════════════
  // 1. AUTHENTICATION & USER VALIDATION
  // ════════════════════════════════════════════════════════════════

  try {
    // Get Firebase Auth token from headers
    const authToken = req.headers.authorization?.split("Bearer ")[1];
    if (!authToken) {
      logger.warn("❌ Reward claim auth failed: Missing authentication token");
      return res.status(401).json({error: "Missing authentication token"});
    }

    // Verify Firebase ID token
    const {getAuth} = require("firebase-admin/auth");
    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(authToken);
      userId = decodedToken.uid;
      logger.info(`✅ Reward claim auth passed | User: ${userId} | Email: ${decodedToken.email}`);
    } catch (authError) {
      logger.warn(`❌ Reward claim auth failed: Invalid token - ${authError.message}`);
      return res.status(401).json({error: "Invalid authentication"});
    }

    logger.info(`🎁 Reward claim | RewardID: ${req.body?.rewardId}`);

    // ════════════════════════════════════════════════════════════════
    // 2. CHECK FAILSAFE MODE
    // ════════════════════════════════════════════════════════════════

    const failsafeStatus = await failsafe.getFailsafeStatus();
    if (failsafeStatus.failsafeActive) {
      logger.warn(`🚨 Failsafe active | ${failsafeStatus.message}`);
      return res.status(503).json({
        error: failsafeStatus.message,
        failsafeActive: true,
      });
    }

    logger.info("✅ Failsafe check passed");

    // ════════════════════════════════════════════════════════════════
    // 3. FETCH USER DOCUMENT & VALIDATE SCHEMA
    // ════════════════════════════════════════════════════════════════

    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      logger.warn(`❌ User not found | User: ${userId}`);
      return res.status(404).json({error: "User not found"});
    }

    const schemaCheck = firestoreSchema.ensureValidUserDocument(userDoc.data());
    const user = schemaCheck.user;

    if (schemaCheck.wasRepaired) {
      logger.warn(`🔧 User document repaired | User: ${userId}`);
      await userRef.update(user);
    }

    logger.info(`👤 User fetched | Tier: ${user.regionTier}`);

    // ════════════════════════════════════════════════════════════════
    // 3.1 CHECK REMOTE CONFIG: IS THIS TIER'S ADS DISABLED?
    // ════════════════════════════════════════════════════════════════

    const tierDisabledInRemoteConfig = await remoteConfigHelper.isTierDisabledInRemoteConfig(user.regionTier);
    if (tierDisabledInRemoteConfig) {
      logger.warn(`🚨 Tier ${user.regionTier} ads disabled via Remote Config | User: ${userId}`);

      // SPEC K: Log analytics event
      await analytics.logRewardClaimDenied(
          userId,
          user.regionTier,
          req.body.rewardId || "unknown",
          "tier_disabled_remote_config",
      );

      return res.status(503).json({
        error: `Ad system temporarily unavailable for your region (${user.regionTier})`,
        tierDisabled: true,
        tier: user.regionTier,
      });
    }

    logger.info(`✅ Tier ${user.regionTier} ads are enabled in Remote Config`);

    // ════════════════════════════════════════════════════════════════
    // 4. LOG REWARD CLAIM SENT (SPEC K)
    // ════════════════════════════════════════════════════════════════

    await analytics.logRewardClaimSent(userId, user.regionTier, req.body.rewardId);
    logger.info(`📈 Logged analytics event: reward_claim_sent | User: ${userId}`);

    // ════════════════════════════════════════════════════════════════
    // 5. VALIDATE REWARD CLAIM
    // ════════════════════════════════════════════════════════════════

    const rewardClaim = {
      rewardId: req.body.rewardId,
      rewardToken: req.body.rewardToken,
    };

    // Validate claim structure and AdMob callback
    const claimValidation = rewardValidator.validateRewardClaim(rewardClaim, userId);

    if (!claimValidation.valid) {
      // Log potential fraud attempt
      console.warn(`⚠️ Invalid reward claim | User: ${userId}, Error: ${claimValidation.error}`);

      // SPEC K: Log analytics event
      await analytics.logRewardClaimDenied(
          userId,
          user.regionTier,
          req.body.rewardId || "unknown",
          "invalid_claim",
      );

      return res.status(400).json({
        error: claimValidation.error,
      });
    }

    // ════════════════════════════════════════════════════════════════
    // 5. VALIDATE REWARDED AD ELIGIBILITY
    // ════════════════════════════════════════════════════════════════

    const countersData = counters.getCurrentCounters(userDoc);
    const rewardedEligibility = rewardedValidation.isEligibleForRewarded(user);

    if (!rewardedEligibility.eligible) {
      // SPEC K: Log analytics event
      await analytics.logRewardClaimDenied(
          userId,
          user.regionTier,
          req.body.rewardId || "unknown",
          "not_eligible",
      );

      return res.status(403).json({
        error: rewardedEligibility.reason,
      });
    }

    // ════════════════════════════════════════════════════════════════
    // 6. VALIDATE AGAINST DAILY LIMITS
    // ════════════════════════════════════════════════════════════════

    const userLimits = dailyLimitValidator.getDailyLimits(user);

    const approvalResult = rewardValidator.approveReward({
      userId,
      rewardClaim,
      claimedRewards: user.claimedRewards || {},
      userCounters: countersData,
      userLimits,
    });

    if (!approvalResult.approved) {
      // Log blocked reward
      await analytics.logAiGenerationBlocked(
          userId,
          user.regionTier,
          "reward_limit_exceeded",
      );

      return res.status(429).json({
        error: approvalResult.error,
      });
    }

    // ════════════════════════════════════════════════════════════════
    // 8. INCREMENT REWARDED ADS COUNTER (CRITICAL - PER SPEC)
    // ════════════════════════════════════════════════════════════════

    // SPEC REQUIREMENT: rewardedAdsWatchedToday++ MUST happen in callback
    // This prevents race condition exploits where user watches multiple ads
    // before redeeming tokens
    await counters.incrementRewardedAds(userRef);

    logger.info(
        `📊 Rewarded ad counter incremented | User: ${userId} | ` +
        `New count: ${countersData.rewardedAdsWatchedToday + 1}`,
    );

    // ════════════════════════════════════════════════════════════════
    // 9. RECORD REWARD CLAIM IN FIRESTORE
    // ════════════════════════════════════════════════════════════════

    const updatedClaimedRewards = rewardValidator.recordRewardClaim(
        rewardClaim.rewardId,
        user.claimedRewards || {},
    );

    await userRef.update({
      claimedRewards: updatedClaimedRewards,
    });

    // ════════════════════════════════════════════════════════════════
    // 10. STORE REWARD TOKEN IN FIRESTORE (CRITICAL SECURITY FIX)
    // ════════════════════════════════════════════════════════════════

    // SPEC REQUIREMENT: Server-side token storage for validation
    // Token must be stored before returning to client to enable validation in generateAi
    const tokenStoreResult = await rewardTokenManager.storeRewardToken(
        userRef,
        approvalResult.token,
        {
          rewardId: approvalResult.rewardId,
          aiUnlocksGranted: approvalResult.aiUnlocksGranted,
        },
    );

    if (!tokenStoreResult.success) {
      logger.error(`❌ Failed to store reward token: ${tokenStoreResult.error}`);
      return res.status(500).json({
        error: "Failed to store reward token",
      });
    }

    logger.info(`✅ Reward token stored securely | User: ${userId}`);

    // ════════════════════════════════════════════════════════════════
    // 11. LOG ANALYTICS EVENTS (REWARD APPROVED)
    // ════════════════════════════════════════════════════════════════

    // Log reward claim approved
    await analytics.logRewardClaimApproved(
        userId,
        user.regionTier,
        approvalResult.rewardId,
        approvalResult.aiUnlocksGranted,
    );

    logger.info(`📈 Logged analytics event: reward_claim_approved | User: ${userId}`);

    await analytics.logRewardedWatched(
        userId,
        user.regionTier,
        "ai_unlock",
    );

    logger.info(`📈 Logged analytics event: rewarded_watched | User: ${userId}`);

    // ════════════════════════════════════════════════════════════════
    // 12. RETURN REWARD GRANT TOKEN
    // ════════════════════════════════════════════════════════════════

    logger.info(
        `✅ Reward claim complete | User: ${userId} | Token generated | ` +
        `AI unlocks: ${approvalResult.aiUnlocksGranted}`,
    );

    return res.status(200).json({
      success: true,
      rewardGrantToken: approvalResult.token,
      rewardId: approvalResult.rewardId,
      aiUnlocksGranted: approvalResult.aiUnlocksGranted,
      message: `You've unlocked ${approvalResult.aiUnlocksGranted} AI ${
          approvalResult.aiUnlocksGranted === 1 ? "generation" : "generations"
      }. Use the token to generate AI.`,
    });
  } catch (error) {
    logger.error(`❌ claimReward handler error | User: ${userId} | Error: ${error.message}`, error);

    // Check if this is an unauthorized AI execution (security violation)
    if (error.message.includes("token mismatch")) {
      // Potential failsafe trigger
      logger.error(`🚨 SECURITY VIOLATION: Unauthorized AI execution attempted | User: ${userId}`);
      // failsafe could be triggered here for severe violations
    }

    return res.status(500).json({
      error: "Failed to process your reward. Please try again.",
    });
  }
}

// Export as Cloud Function (HTTP trigger)
module.exports = onRequest(
    {region: "us-central1", timeoutSeconds: 30},
    claimRewardHandler,
);
