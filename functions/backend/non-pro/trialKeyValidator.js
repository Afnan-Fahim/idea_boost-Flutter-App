/**
 * Trial Key Global Validator
 * Cross-device trial key validation to prevent reinstall farming
 *
 * Tracks trial keys globally to ensure each physical device can only
 * use trial once, regardless of reinstalls or account changes
 */

const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

/**
 * Check if trial key has been used before (globally)
 * @param {string} trialKey - Device fingerprint trial key
 * @return {Promise<object>} - { alreadyUsed: boolean, usedBy?: array, firstUsedAt?: date }
 */
async function checkTrialKeyUsage(trialKey) {
  if (!trialKey) {
    return {
      alreadyUsed: false,
    };
  }

  try {
    const db = getFirestore();
    const trialKeyDoc = await db
        .collection("system")
        .doc("trialKeys")
        .collection("keys")
        .doc(trialKey)
        .get();

    if (trialKeyDoc.exists) {
      const data = trialKeyDoc.data();
      logger.warn(
          `⚠️ Trial key already used | Key: ${trialKey.substring(0, 8)}... | ` +
          `First used: ${data.firstUsedAt} | Users: ${data.usedBy.length}`,
      );

      return {
        alreadyUsed: true,
        usedBy: data.usedBy,
        firstUsedAt: data.firstUsedAt,
      };
    }

    return {
      alreadyUsed: false,
    };
  } catch (error) {
    logger.error(`❌ Failed to check trial key: ${error.message}`);
    // On error, allow trial (fail-open for better UX)
    return {
      alreadyUsed: false,
      error: error.message,
    };
  }
}

/**
 * Register trial key as used
 * Called when user starts their trial
 * @param {string} trialKey - Device fingerprint trial key
 * @param {string} userId - User UID who used the trial
 * @return {Promise<object>} - { success: boolean }
 */
async function registerTrialKeyUsage(trialKey, userId) {
  if (!trialKey || !userId) {
    return {
      success: false,
      error: "Missing trialKey or userId",
    };
  }

  try {
    const db = getFirestore();
    const trialKeyRef = db
        .collection("system")
        .doc("trialKeys")
        .collection("keys")
        .doc(trialKey);

    const trialKeyDoc = await trialKeyRef.get();

    if (trialKeyDoc.exists) {
      // Key already exists, add this user to the list
      const data = trialKeyDoc.data();
      if (!data.usedBy.includes(userId)) {
        await trialKeyRef.update({
          usedBy: [...data.usedBy, userId],
          lastUsedAt: new Date(),
          useCount: (data.useCount || 1) + 1,
        });
      }
    } else {
      // First time this key is used
      await trialKeyRef.set({
        trialKey,
        usedBy: [userId],
        firstUsedAt: new Date(),
        lastUsedAt: new Date(),
        useCount: 1,
      });
    }

    logger.info(`✅ Trial key registered | Key: ${trialKey.substring(0, 8)}... | User: ${userId}`);

    return {
      success: true,
    };
  } catch (error) {
    logger.error(`❌ Failed to register trial key: ${error.message}`);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Validate trial eligibility including cross-device check
 * @param {object} user - User document data
 * @param {string} trialKey - Device fingerprint trial key
 * @return {Promise<object>} - { eligible: boolean, reason?: string }
 */
async function validateTrialEligibility(user, trialKey) {
  if (!user) {
    return {
      eligible: false,
      reason: "User not found",
    };
  }

  // Check if user already used trial
  if (user.hasUsedTrial) {
    return {
      eligible: false,
      reason: "User already completed trial",
    };
  }

  // Check if trial key has been used before (cross-device check)
  const keyCheck = await checkTrialKeyUsage(trialKey);
  if (keyCheck.alreadyUsed) {
    // CRITICAL FIX: Allow the SAME user to continue their own trial session.
    // After startTrial() registers the key, the same user's subsequent
    // trial generations must NOT be blocked by their own key registration.
    if (keyCheck.usedBy && keyCheck.usedBy.includes(user.uid)) {
      logger.info(
          `✅ Trial key belongs to same user - allowing trial continuation | ` +
          `Key: ${trialKey.substring(0, 8)}... | User: ${user.uid}`,
      );
      return {eligible: true};
    }

    // Different user used this key on this device - cross-device violation
    return {
      eligible: false,
      reason: "Trial already used on this device",
      crossDeviceViolation: true,
    };
  }

  return {
    eligible: true,
  };
}

module.exports = {
  checkTrialKeyUsage,
  registerTrialKeyUsage,
  validateTrialEligibility,
};
