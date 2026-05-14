/**
 * Trial Access Management
 * Spec: 3.1 FIRST-TIME ONBOARDING & 4.1 ONBOARDING
 *
 * One-time trial protected by device fingerprint
 * Tier-1: 2 free AI generations
 * Tier-2: 1 free AI generation
 * Tier-3: 0 free (no trial)
 */

const config = require("../config");
const trialKeyValidator = require("./trialKeyValidator");
const analytics = require("../common/analytics");

/**
 * Check if user can access trial
 * Includes cross-device trial key validation
 * @param {object} user - User document from Firestore
 * @return {Promise<object>} - { canAccess: boolean, message?: string, freeGenerations?: number }
 */
async function canAccessTrial(user) {
  if (!user) {
    return {
      canAccess: false,
      message: "User not found",
    };
  }

  // Tier-3 has no trial
  if (user.regionTier === "tier3") {
    return {
      canAccess: false,
      message: config.MESSAGES.NO_TRIAL,
      tier: "tier3",
    };
  }

  // Already used trial
  if (user.hasUsedTrial) {
    return {
      canAccess: false,
      message: config.MESSAGES.TRIAL_ALREADY_USED,
    };
  }

  // CRITICAL: Cross-device trial key validation
  if (user.trialKey) {
    const eligibility = await trialKeyValidator.validateTrialEligibility(
        user,
        user.trialKey,
    );

    if (!eligibility.eligible) {
      return {
        canAccess: false,
        message: eligibility.reason,
        crossDeviceBlocked: eligibility.crossDeviceViolation,
      };
    }
  }

  // Trial available
  const freeGenerations = config.TRIAL[user.regionTier] || 0;

  return {
    canAccess: true,
    message: `You have ${freeGenerations} free AI generations available`,
    freeGenerations,
    tier: user.regionTier,
  };
}

/**
 * Start trial session for user
 * Called on first AI generation attempt
 * Registers trial key globally to prevent cross-device reuse
 * @param {object} userRef - Firestore user document reference
 * @param {string} tier - User's region tier
 * @return {Promise<object>} - { success: boolean, trialStarted: boolean }
 */
async function startTrial(userRef, tier) {
  if (!userRef) {
    return {
      success: false,
      message: "Invalid user reference",
    };
  }

  try {
    const trialLimit = config.TRIAL[tier] || 0;

    if (trialLimit === 0) {
      return {
        success: false,
        message: "Trial not available for this tier",
      };
    }

    // Get user data to extract trial key
    const userDoc = await userRef.get();
    const userData = userDoc.data();
    // Use userRef.id as authoritative UID — userData.uid may not exist in older docs
    const resolvedUid = userData.uid || userRef.id;

    // Register trial key globally (cross-device protection)
    if (userData.trialKey) {
      await trialKeyValidator.registerTrialKeyUsage(userData.trialKey, resolvedUid);
    }

    // Update user document
    await userRef.update({
      trialStartedAt: new Date(),
      trialGenerationsRemaining: trialLimit,
    });

    console.log(`🎁 Trial started | Tier: ${tier}, Free generations: ${trialLimit}`);

    // SPEC K: Log analytics event
    await analytics.logTrialStarted(resolvedUid, tier);

    return {
      success: true,
      trialStarted: true,
      generationsAvailable: trialLimit,
    };
  } catch (error) {
    console.error("❌ Failed to start trial:", error.message);
    return {
      success: false,
      message: error.message,
    };
  }
}

/**
 * Decrement trial generations counter
 * Called after each trial AI generation
 * @param {object} userRef - Firestore user document reference
 * @return {Promise<object>} - { remaining: number, trialComplete: boolean }
 */
async function decrementTrial(userRef) {
  if (!userRef) {
    return {
      success: false,
      message: "Invalid user reference",
    };
  }

  try {
    // Increment trialed counter, check remaining
    const doc = await userRef.get();
    const current = doc.data().trialGenerationsRemaining || 0;
    const remaining = Math.max(0, current - 1);

    const isComplete = remaining === 0;

    await userRef.update({
      trialGenerationsRemaining: remaining,
      ...(isComplete && {hasUsedTrial: true, trialCompletedAt: new Date()}),
    });

    console.log(
        `📉 Trial decremented | Remaining: ${remaining}, ` +
        `${isComplete ? "TRIAL COMPLETE" : ""}`,
    );

    return {
      success: true,
      remaining,
      trialComplete: isComplete,
    };
  } catch (error) {
    console.error("❌ Failed to decrement trial:", error.message);
    return {
      success: false,
      message: error.message,
    };
  }
}

/**
 * Mark trial as used (via reward or by exhausting limit)
 * @param {object} userRef - Firestore user document reference
 * @return {Promise<object>} - { success: boolean }
 */
async function completeTrial(userRef) {
  if (!userRef) {
    return {
      success: false,
      message: "Invalid user reference",
    };
  }

  try {
    await userRef.update({
      hasUsedTrial: true,
      trialCompletedAt: new Date(),
      trialGenerationsRemaining: 0,
    });

    console.log("✅ Trial marked as complete");

    return {
      success: true,
    };
  } catch (error) {
    console.error("❌ Failed to complete trial:", error.message);
    return {
      success: false,
      message: error.message,
    };
  }
}

/**
 * Get trial status for display
 * @param {object} user - User document
 * @return {object} - Trial status info
 */
function getTrialStatus(user) {
  if (!user) {
    return {
      inTrial: false,
      available: false,
    };
  }

  if (user.hasUsedTrial) {
    return {
      inTrial: false,
      available: false,
      completedAt: user.trialCompletedAt,
    };
  }

  if (user.trialStartedAt && user.trialGenerationsRemaining > 0) {
    return {
      inTrial: true,
      available: true,
      remaining: user.trialGenerationsRemaining,
      startedAt: user.trialStartedAt,
    };
  }

  return {
    inTrial: false,
    available: true,
    tier: user.regionTier,
  };
}

module.exports = {
  canAccessTrial,
  startTrial,
  decrementTrial,
  completeTrial,
  getTrialStatus,
};
