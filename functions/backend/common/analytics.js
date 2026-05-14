/**
 * Analytics Event Logger
 * Spec: 8. ANALYTICS (NO NEW APIs)
 *
 * Logs monetization events for tracking and debugging
 * Uses Firebase Firestore collection for event persistence
 */

const logger = require("firebase-functions/logger");
const config = require("../config");

// Get Firestore instance for storing analytics events
// eslint-disable-next-line no-unused-vars
let analyticsInitialized = false;

function initAnalytics(app) {
  try {
    // Analytics events stored in Firestore collection: analytics_events
    analyticsInitialized = true;
    logger.info("✅ Analytics logging initialized");
  } catch (error) {
    logger.warn("⚠️ Analytics initialization warning:", error.message);
  }
}

/**
 * Log trial started event
 * @param {string} userId - User UID from Firebase Auth
 * @param {string} tier - User's region tier
 */
async function logTrialStarted(userId, tier) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    // Log to console (for debugging)
    logger.info(`📊 Event: trial_started | User: ${userId}, Tier: ${tier}`);

    // Store event in Firestore for analytics tracking
    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.TRIAL_STARTED,
      userId,
      tier,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(`📊 Event: trial_started | User: ${userId}, Tier: ${tier}`);
  } catch (error) {
    logger.error("❌ Failed to log trial_started:", error.message);
  }
}

/**
 * Log trial completed event
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {number} aiGenerationsUsed - Number of free AI generations used
 */
async function logTrialCompleted(userId, tier, aiGenerationsUsed) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: trial_completed | User: ${userId}, Tier: ${tier}, AI used: ${aiGenerationsUsed}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.TRIAL_COMPLETED,
      userId,
      tier,
      aiGenerationsUsed,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: trial_completed | User: ${userId}, ` +
        `Tier: ${tier}, AI used: ${aiGenerationsUsed}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log trial_completed:", error.message);
  }
}

/**
 * Log rewarded ad watched event
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {string} rewardType - Type of reward ("ai_unlock")
 */
async function logRewardedWatched(userId, tier, rewardType) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: rewarded_watched | User: ${userId}, Tier: ${tier}, Reward: ${rewardType}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_WATCHED,
      userId,
      tier,
      rewardType,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: rewarded_watched | User: ${userId}, ` +
        `Tier: ${tier}, Reward: ${rewardType}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log rewarded_watched:", error.message);
  }
}

/**
 * Log AI generation success
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {string} plan - "free", "rewarded", or "pro"
 * @param {string} model - Model used ("grok-default" or "grok-premium")
 * @param {number} promptLength - Length of user input
 * @param {number} responseLength - Length of AI response
 */
async function logAiGenerationSuccess(userId, tier, plan, model, promptLength, responseLength) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: ai_generation_success | User: ${userId}, Tier: ${tier}, Plan: ${plan}, Model: ${model}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.AI_GENERATION_SUCCESS,
      userId,
      tier,
      plan,
      model,
      promptLength,
      responseLength,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: ai_generation_success | User: ${userId}, ` +
        `Tier: ${tier}, Plan: ${plan}, Model: ${model}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log ai_generation_success:", error.message);
  }
}

/**
 * Log AI generation blocked due to limit
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {string} reason - Block reason ("daily_limit" | "pro_cap" | "abuse")
 */
async function logAiGenerationBlocked(userId, tier, reason) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: ai_generation_blocked | User: ${userId}, Tier: ${tier}, Reason: ${reason}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.AI_GENERATION_BLOCKED_LIMIT,
      userId,
      tier,
      reason,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: ai_generation_blocked | User: ${userId}, ` +
        `Tier: ${tier}, Reason: ${reason}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log ai_generation_blocked:", error.message);
  }
}

/**
 * Log PRO upgrade click (user intent)
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {string} source - Where click came from ("home_screen" | "paywall" | "settings")
 */
async function logProUpgradeClicked(userId, tier, source) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: pro_upgrade_clicked | User: ${userId}, Tier: ${tier}, Source: ${source}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.PRO_UPGRADE_CLICKED,
      userId,
      tier,
      source,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: pro_upgrade_clicked | User: ${userId}, ` +
        `Tier: ${tier}, Source: ${source}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log pro_upgrade_clicked:", error.message);
  }
}

/**
 * Log PRO subscription started (conversion)
 * @param {string} userId - User UID
 * @param {string} tier - User's region tier
 * @param {string} subscriptionId - Play Store / App Store subscription ID
 */
async function logProSubscriptionStarted(userId, tier, subscriptionId) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.info(`📊 Event: pro_subscription_started | User: ${userId}, Tier: ${tier}, Subscription: ${subscriptionId}`);

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.PRO_SUBSCRIPTION_STARTED,
      userId,
      tier,
      subscriptionId,
      timestamp: new Date(),
      createdAt: new Date(),
    });

    console.log(
        `📊 Event: pro_subscription_started | User: ${userId}, ` +
        `Tier: ${tier}, Subscription: ${subscriptionId}`,
    );
  } catch (error) {
    logger.error("❌ Failed to log pro_subscription_started:", error.message);
  }
}

// ════════════════════════════════════════════════════════════════
// ADMOB/REWARD PIPELINE EVENTS (8 NEW EVENTS - SPEC K)
// ════════════════════════════════════════════════════════════════

/**
 * Log rewarded ad requested (client initiates ad load)
 * Called from: Flutter AdMob request handler
 */
async function logRewardedAdRequested(userId, tier) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: rewarded_ad_requested | User: ${userId}, Tier: ${tier}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_AD_REQUESTED,
      userId,
      tier,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log rewarded_ad_requested:", error.message);
  }
}

/**
 * Log rewarded ad loaded (ad ready to show)
 * Called from: Flutter AdMob onAdLoaded callback
 */
async function logRewardedAdLoaded(userId, tier) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: rewarded_ad_loaded | User: ${userId}, Tier: ${tier}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_AD_LOADED,
      userId,
      tier,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log rewarded_ad_loaded:", error.message);
  }
}

/**
 * Log rewarded ad failed (load or show failure)
 * Called from: Flutter AdMob onAdFailedToLoad/onAdFailedToShow callbacks
 */
async function logRewardedAdFailed(userId, tier, reason) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: rewarded_ad_failed | User: ${userId}, Tier: ${tier}, ` +
        `Reason: ${reason}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_AD_FAILED,
      userId,
      tier,
      reason,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log rewarded_ad_failed:", error.message);
  }
}

/**
 * Log rewarded ad rewarded (user earned reward from ad)
 * Called from: Flutter AdMob onUserEarnedReward callback
 */
async function logRewardedAdRewarded(userId, tier, rewardType) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: rewarded_ad_rewarded | User: ${userId}, Tier: ${tier}, ` +
        `RewardType: ${rewardType}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_AD_REWARDED,
      userId,
      tier,
      rewardType,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log rewarded_ad_rewarded:", error.message);
  }
}

/**
 * Log rewarded ad blocked by daily limit
 * Called from: Flutter when user tries to watch but daily limit reached
 */
async function logRewardedAdBlockedLimit(userId, tier, currentCount, dailyLimit) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: rewarded_ad_blocked_limit | User: ${userId}, Tier: ${tier}, ` +
        `Current: ${currentCount}/${dailyLimit}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARDED_AD_BLOCKED_LIMIT,
      userId,
      tier,
      currentCount,
      dailyLimit,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log rewarded_ad_blocked_limit:", error.message);
  }
}

/**
 * Log reward claim sent (user sends reward verification to server)
 * Called from: claimReward.js when request received
 */
async function logRewardClaimSent(userId, tier, rewardId) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: reward_claim_sent | User: ${userId}, Tier: ${tier}, ` +
        `RewardID: ${rewardId}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARD_CLAIM_SENT,
      userId,
      tier,
      rewardId,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log reward_claim_sent:", error.message);
  }
}

/**
 * Log reward claim approved (server validated reward)
 * Called from: claimReward.js when approval granted
 */
async function logRewardClaimApproved(userId, tier, rewardId, aiUnlocksGranted) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: reward_claim_approved | User: ${userId}, Tier: ${tier}, ` +
        `RewardID: ${rewardId}, AIUnlocks: ${aiUnlocksGranted}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARD_CLAIM_APPROVED,
      userId,
      tier,
      rewardId,
      aiUnlocksGranted,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log reward_claim_approved:", error.message);
  }
}

/**
 * Log reward claim denied (server rejected reward)
 * Called from: claimReward.js when claim rejected
 */
async function logRewardClaimDenied(userId, tier, rewardId, reason) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    console.log(
        `📊 Event: reward_claim_denied | User: ${userId}, Tier: ${tier}, ` +
        `RewardID: ${rewardId}, Reason: ${reason}`,
    );

    await db.collection("analytics_events").doc().set({
      event: config.ANALYTICS_EVENTS.REWARD_CLAIM_DENIED,
      userId,
      tier,
      rewardId,
      reason,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log reward_claim_denied:", error.message);
  }
}

/**
 * Log when a tier is disabled via Remote Config (M.3)
 * @param {string} tier - User's region tier (tier1, tier2, tier3)
 * @param {string} reason - Reason for disabling
 */
async function logTierDisabledViaRemoteConfig(tier, reason) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.warn(`📊 Event: tier_disabled_remote_config | Tier: ${tier}, Reason: ${reason}`);

    await db.collection("analytics_events").doc().set({
      event: "tier_disabled_remote_config",
      tier,
      reason,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log tier_disabled_remote_config:", error.message);
  }
}

/**
 * Log when failsafe is activated
 * @param {string} reason - Reason for failsafe activation
 */
async function logFailsafeActivation(reason) {
  try {
    const {getFirestore} = require("firebase-admin/firestore");
    const db = getFirestore();

    logger.warn(`📊 Event: failsafe_activated | Reason: ${reason}`);

    await db.collection("analytics_events").doc().set({
      event: "failsafe_activated",
      reason,
      timestamp: new Date(),
      createdAt: new Date(),
    });
  } catch (error) {
    logger.error("❌ Failed to log failsafe_activated:", error.message);
  }
}

module.exports = {
  initAnalytics,
  logTrialStarted,
  logTrialCompleted,
  logRewardedWatched,
  logAiGenerationSuccess,
  logAiGenerationBlocked,
  logProUpgradeClicked,
  logProSubscriptionStarted,
  // AdMob/Reward Pipeline Events
  logRewardedAdRequested,
  logRewardedAdLoaded,
  logRewardedAdFailed,
  logRewardedAdRewarded,
  logRewardedAdBlockedLimit,
  logRewardClaimSent,
  logRewardClaimApproved,
  logRewardClaimDenied,
  // M.3 Remote Config Events
  logTierDisabledViaRemoteConfig,
  logFailsafeActivation,
};
