/**
 * Daily Reset Lock Manager
 * Prevents race conditions during daily reset window
 *
 * When daily reset is running, all AI generation requests are temporarily
 * blocked to prevent double-counting or inconsistent state
 */

const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const RESET_LOCK_DURATION_MS = 60000; // 1 minute max

/**
 * Check if daily reset is currently in progress
 * @return {Promise<object>} - { isLocked: boolean, lockedAt?: date }
 */
async function isResetLocked() {
  try {
    const db = getFirestore();
    const lockDoc = await db
        .collection("system")
        .doc("resetLock")
        .get();

    if (!lockDoc.exists) {
      return {
        isLocked: false,
      };
    }

    const lockData = lockDoc.data();
    const lockedAt = new Date(lockData.lockedAt);
    const now = new Date();
    const timeSinceLock = now - lockedAt;

    // If lock is older than max duration, consider it stale
    if (timeSinceLock > RESET_LOCK_DURATION_MS) {
      logger.warn(`⚠️ Stale reset lock detected, removing (${timeSinceLock}ms old)`);
      await releaseResetLock();
      return {
        isLocked: false,
      };
    }

    return {
      isLocked: lockData.locked === true,
      lockedAt: lockData.lockedAt,
    };
  } catch (error) {
    logger.error(`❌ Failed to check reset lock: ${error.message}`);
    // On error, assume not locked (fail-open)
    return {
      isLocked: false,
    };
  }
}

/**
 * Acquire reset lock
 * Called at the start of daily reset
 * @return {Promise<object>} - { success: boolean }
 */
async function acquireResetLock() {
  try {
    const db = getFirestore();
    await db
        .collection("system")
        .doc("resetLock")
        .set({
          locked: true,
          lockedAt: new Date(),
          reason: "Daily reset in progress",
        });

    logger.info("🔒 Reset lock acquired");

    return {
      success: true,
    };
  } catch (error) {
    logger.error(`❌ Failed to acquire reset lock: ${error.message}`);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Release reset lock
 * Called at the end of daily reset
 * @return {Promise<object>} - { success: boolean }
 */
async function releaseResetLock() {
  try {
    const db = getFirestore();
    await db
        .collection("system")
        .doc("resetLock")
        .set({
          locked: false,
          lastResetAt: new Date(),
        });

    logger.info("🔓 Reset lock released");

    return {
      success: true,
    };
  } catch (error) {
    logger.error(`❌ Failed to release reset lock: ${error.message}`);
    return {
      success: false,
      error: error.message,
    };
  }
}

module.exports = {
  isResetLocked,
  acquireResetLock,
  releaseResetLock,
};
