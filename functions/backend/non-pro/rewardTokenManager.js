/**
 * Reward Token Manager
 * Handles storage, validation, and consumption of reward grant tokens
 *
 * CRITICAL SECURITY: Ensures tokens are:
 * 1. Stored server-side after reward claim
 * 2. Validated before AI execution
 * 3. One-time use only (consumed after use)
 * 4. Expire after reasonable time
 */

const logger = require("firebase-functions/logger");

/**
 * Store reward token in Firestore
 * Called after reward claim is approved
 * @param {object} userRef - Firestore user document reference
 * @param {string} token - Generated reward grant token
 * @param {object} metadata - Token metadata
 * @return {Promise<object>} - { success: boolean }
 */
async function storeRewardToken(userRef, token, metadata) {
  try {
    const {rewardId, aiUnlocksGranted} = metadata;

    await userRef.update({
      [`activeRewardTokens.${token}`]: {
        createdAt: new Date(),
        consumed: false,
        rewardId,
        aiUnlocksRemaining: aiUnlocksGranted,
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24 hours
      },
    });

    logger.info(`✅ Reward token stored | Token: ${token.substring(0, 8)}...`);

    return {
      success: true,
    };
  } catch (error) {
    logger.error(`❌ Failed to store reward token: ${error.message}`);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Validate reward token
 * Checks if token exists, not consumed, not expired, and has unlocks remaining
 * @param {object} user - User document data
 * @param {string} token - Token to validate
 * @return {object} - { valid: boolean, reason?: string, tokenData?: object }
 */
function validateRewardToken(user, token) {
  if (!token) {
    return {
      valid: false,
      reason: "Missing reward token",
    };
  }

  if (!user.activeRewardTokens || !user.activeRewardTokens[token]) {
    return {
      valid: false,
      reason: "Invalid or unrecognized reward token",
    };
  }

  const tokenData = user.activeRewardTokens[token];

  // Check if already consumed
  if (tokenData.consumed) {
    return {
      valid: false,
      reason: "Reward token already used",
    };
  }

  // Check if expired
  if (tokenData.expiresAt && new Date(tokenData.expiresAt) < new Date()) {
    return {
      valid: false,
      reason: "Reward token expired",
    };
  }

  // Check if has unlocks remaining
  if (tokenData.aiUnlocksRemaining <= 0) {
    return {
      valid: false,
      reason: "No AI unlocks remaining for this token",
    };
  }

  return {
    valid: true,
    tokenData,
  };
}

/**
 * Consume one AI unlock from reward token
 * Called after successful AI generation
 * @param {object} userRef - Firestore user document reference
 * @param {string} token - Token to consume
 * @param {number} currentUnlocks - Current unlocks remaining
 * @return {Promise<object>} - { success: boolean, remaining: number }
 */
async function consumeRewardToken(userRef, token, currentUnlocks) {
  try {
    const remaining = currentUnlocks - 1;
    const isFullyConsumed = remaining <= 0;

    await userRef.update({
      [`activeRewardTokens.${token}.aiUnlocksRemaining`]: remaining,
      [`activeRewardTokens.${token}.consumed`]: isFullyConsumed,
      [`activeRewardTokens.${token}.lastUsedAt`]: new Date(),
    });

    logger.info(
        `✅ Token consumed | Remaining unlocks: ${remaining} | ` +
        `Fully consumed: ${isFullyConsumed}`,
    );

    return {
      success: true,
      remaining,
      fullyConsumed: isFullyConsumed,
    };
  } catch (error) {
    logger.error(`❌ Failed to consume token: ${error.message}`);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Cleanup expired tokens (called periodically or on request)
 * Removes tokens older than 24 hours
 * @param {object} userRef - Firestore user document reference
 * @param {object} activeTokens - Current active tokens object
 * @return {Promise<number>} - Number of tokens cleaned up
 */
async function cleanupExpiredTokens(userRef, activeTokens) {
  if (!activeTokens) {
    return 0;
  }

  const now = new Date();
  let cleanedCount = 0;
  const updates = {};

  Object.keys(activeTokens).forEach((token) => {
    const tokenData = activeTokens[token];
    const expiresAt = new Date(tokenData.expiresAt);

    if (expiresAt < now || tokenData.consumed) {
      updates[`activeRewardTokens.${token}`] = null; // Delete field
      cleanedCount++;
    }
  });

  if (cleanedCount > 0) {
    await userRef.update(updates);
    logger.info(`🧹 Cleaned up ${cleanedCount} expired/consumed tokens`);
  }

  return cleanedCount;
}

/**
 * Check if user has any valid reward tokens
 * @param {object} user - User document data
 * @return {object} - { hasValidTokens: boolean, validCount: number }
 */
function hasValidRewardTokens(user) {
  if (!user.activeRewardTokens) {
    return {
      hasValidTokens: false,
      validCount: 0,
    };
  }

  const now = new Date();
  let validCount = 0;

  Object.values(user.activeRewardTokens).forEach((tokenData) => {
    if (
      !tokenData.consumed &&
      tokenData.aiUnlocksRemaining > 0 &&
      new Date(tokenData.expiresAt) > now
    ) {
      validCount++;
    }
  });

  return {
    hasValidTokens: validCount > 0,
    validCount,
  };
}

module.exports = {
  storeRewardToken,
  validateRewardToken,
  consumeRewardToken,
  cleanupExpiredTokens,
  hasValidRewardTokens,
};
