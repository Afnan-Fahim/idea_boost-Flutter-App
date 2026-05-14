/**
 * Reward Validator
 * Spec: H1) Reward Granting (CRITICAL)
 *
 * AI unlock ONLY after onUserEarnedReward callback
 * Server-side reward claim validation is MANDATORY (client not trusted)
 *
 * Hard rule: AI must never execute if:
 * - reward callback was not received
 * - server did not approve reward claim
 */

const crypto = require("crypto");

/**
 * Generate one-time reward grant token
 * This token must be included in the AI generation request
 * Ensures reward is claimed exactly once per ad watch
 * @param {string} userId - User UID
 * @param {string} rewardId - Unique reward identifier from AdMob
 * @return {string} - Secure one-time token
 */
function generateRewardGrantToken(userId, rewardId) {
  if (!userId || !rewardId) {
    throw new Error("Missing userId or rewardId for token generation");
  }

  // Hash combination of userId + rewardId + timestamp to create unique token
  const data = `${userId}:${rewardId}:${Date.now()}`;
  const token = crypto.createHash("sha256").update(data).digest("hex");

  console.log(`🎁 Reward grant token generated | User: ${userId}, Reward: ${rewardId}`);
  return token;
}

/**
 * Validate reward claim from client
 * Called BEFORE granting any AI access
 * @param {object} rewardClaim - Claim data from client
 * @param {string} rewardClaim.rewardId - AdMob reward ID
 * @param {string} rewardClaim.rewardToken - Token from AdMob SDK
 * @param {string} userId - Expected user UID
 * @return {object} - { valid: boolean, message?: string, error?: string }
 */
function validateRewardClaim(rewardClaim, userId) {
  if (!rewardClaim) {
    return {
      valid: false,
      error: "Missing reward claim data",
    };
  }

  const {rewardId, rewardToken} = rewardClaim;

  // Check required fields
  if (!rewardId) {
    return {
      valid: false,
      error: "Missing rewardId in claim",
    };
  }

  if (!rewardToken) {
    return {
      valid: false,
      error: "Missing rewardToken in claim - ad callback not received",
    };
  }

  // TODO: Validate rewardToken against AdMob backend (requires AdMob API)
  // For now, validate it's properly formatted
  if (rewardToken.length < 10) {
    return {
      valid: false,
      error: "Invalid rewardToken format",
    };
  }

  // Log successful validation
  console.log(`✅ Reward claim validated | User: ${userId}, Reward: ${rewardId}`);

  return {
    valid: true,
    message: "Reward claim accepted",
    rewardId,
  };
}

/**
 * Check if reward has already been claimed (idempotency)
 * Prevents double-spending of rewards
 * @param {object} claimedRewards - User's previously claimed reward IDs (from Firestore)
 * @param {string} rewardId - Current reward to check
 * @return {object} - { alreadyClaimed: boolean, claimCount?: number }
 */
function isRewardAlreadyClaimed(claimedRewards, rewardId) {
  if (!claimedRewards || !rewardId) {
    return {
      alreadyClaimed: false,
    };
  }

  const claimCount = (claimedRewards[rewardId] || 0);
  const alreadyClaimed = claimCount > 0;

  if (alreadyClaimed) {
    console.warn(
        `⚠️ Reward already claimed | RewardId: ${rewardId}, ` +
        `Claim count: ${claimCount}`,
    );
  }

  return {
    alreadyClaimed,
    claimCount,
  };
}

/**
 * Server-side reward approval
 * Performs all checks before approving reward
 * @param {object} params - Approval parameters
 * @param {string} params.userId - User UID
 * @param {object} params.rewardClaim - Reward claim from client
 * @param {object} params.claimedRewards - Previously claimed rewards
 * @param {object} params.userCounters - Current daily counters
 * @param {object} params.userLimits - User's daily limits
 * @return {object} - { approved: boolean, token?: string, error?: string }
 */
function approveReward(params) {
  const {userId, rewardClaim, claimedRewards, userCounters, userLimits} = params;

  if (!userId) {
    return {
      approved: false,
      error: "Missing userId",
    };
  }

  // Check 1: Validate claim format and AdMob callback
  const claimValidation = validateRewardClaim(rewardClaim, userId);
  if (!claimValidation.valid) {
    return {
      approved: false,
      error: claimValidation.error,
    };
  }

  // Check 2: Prevent double-claiming
  const doubleClaimCheck = isRewardAlreadyClaimed(claimedRewards, rewardClaim.rewardId);
  if (doubleClaimCheck.alreadyClaimed) {
    return {
      approved: false,
      error: "Reward already claimed",
    };
  }

  // Check 3: Verify user hasn't exceeded rewarded ad limit today
  const rewardedWatched = userCounters?.rewardedAdsWatchedToday || 0;
  const rewardedLimit = userLimits?.dailyRewardedLimit || 3;

  if (rewardedWatched >= rewardedLimit) {
    return {
      approved: false,
      error: "Daily rewarded ad limit reached",
    };
  }

  // Check 4: Verify user will not exceed AI limit after this reward
  const aiUsed = (userCounters?.aiNanoUsedToday || 0) + (userCounters?.aiMiniUsedToday || 0);
  const aiLimit = userLimits?.dailyAiLimit || 3;
  const aiPerReward = userLimits?.dailyAiPerReward || 1;

  if (aiUsed + aiPerReward > aiLimit) {
    return {
      approved: false,
      error: "Daily AI limit will be exceeded",
      aiUnlocksAvailable: aiLimit - aiUsed,
    };
  }

  // All checks passed - generate one-time token
  const token = generateRewardGrantToken(userId, rewardClaim.rewardId);

  console.log(
      `🎉 Reward approved | User: ${userId}, RewardId: ${rewardClaim.rewardId}, ` +
      `AI unlocks: ${aiPerReward}`,
  );

  return {
    approved: true,
    token,
    rewardId: rewardClaim.rewardId,
    aiUnlocksGranted: aiPerReward,
  };
}

/**
 * Record reward claim in Firestore
 * Called after AI generation succeeds with reward grant token
 * @param {string} rewardId - Reward ID from AdMob
 * @param {object} claimedRewards - Current claimed rewards object
 * @return {object} - Updated claimed rewards object
 */
function recordRewardClaim(rewardId, claimedRewards = {}) {
  if (!rewardId) {
    return claimedRewards;
  }

  const updated = {...claimedRewards};
  updated[rewardId] = (updated[rewardId] || 0) + 1;

  return updated;
}

/**
 * Validate reward grant token in AI request
 * Must match token from approveReward()
 * @param {string} token - Token from AI request
 * @param {string} expectedToken - Token stored in server session
 * @return {boolean} - true if tokens match
 */
function validateRewardGrantToken(token, expectedToken) {
  if (!token || !expectedToken) {
    console.warn("⚠️ Missing reward grant token in AI request");
    return false;
  }

  const isValid = token === expectedToken;

  if (!isValid) {
    console.warn("🚨 Reward grant token mismatch - possible tampering attempt");
  }

  return isValid;
}

module.exports = {
  generateRewardGrantToken,
  validateRewardClaim,
  isRewardAlreadyClaimed,
  approveReward,
  recordRewardClaim,
  validateRewardGrantToken,
};
