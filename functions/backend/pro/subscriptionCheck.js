/**
 * PRO Subscription Check
 * Validates PRO subscription status from Play Store / App Store
 *
 * Note: Full receipt validation requires integration with:
 * - Google Play Billing Library
 * - Apple StoreKit
 * - Or RevenueCat/App Store Server API
 */

/**
 * Check if user has active PRO subscription
 * @param {object} subscriptionData - Subscription info from client
 * @return {object} - { active: boolean, reason?: string, expiryDate?: Date }
 */
function isSubscriptionActive(subscriptionData) {
  if (!subscriptionData) {
    return {
      active: false,
      reason: "No subscription data provided",
    };
  }

  const {subscriptionId, purchaseToken, expiryTimestamp} = subscriptionData;

  if (!subscriptionId || !purchaseToken) {
    return {
      active: false,
      reason: "Missing subscription credentials",
    };
  }

  // Check expiry
  if (expiryTimestamp) {
    const expiryDate = new Date(expiryTimestamp);
    const now = new Date();

    if (now > expiryDate) {
      return {
        active: false,
        reason: "Subscription expired",
        expiryDate,
      };
    }

    return {
      active: true,
      expiryDate,
      subscriptionId,
    };
  }

  // If no expiry info, assume valid (should be verified server-side)
  return {
    active: true,
    subscriptionId,
    warning: "Expiry date not provided - verify with Play Store/App Store",
  };
}

/**
 * Validate subscription token with Play Store or App Store
 * This is a placeholder - actual implementation requires:
 * - Google Play Billing Library API calls
 * - Apple StoreKit Server API calls
 * - Or RevenueCat API integration
 * @param {object} params - Validation parameters
 * @return {Promise<object>} - { valid: boolean, error?: string }
 */
async function validateSubscriptionToken(params) {
  const {platform, subscriptionId, purchaseToken} = params;

  if (!platform || !subscriptionId || !purchaseToken) {
    return {
      valid: false,
      error: "Missing validation parameters",
    };
  }

  // TODO: Implement actual server-side receipt validation
  // Example structure:
  // if (platform === "android") {
  //   return validateGooglePlayReceipt(subscriptionId, purchaseToken, userId);
  // } else if (platform === "ios") {
  //   return validateAppleAppStoreReceipt(subscriptionId, purchaseToken, userId);
  // }

  console.warn(
      `⚠️ Subscription token validation not implemented | ` +
      `Platform: ${platform}, Subscription: ${subscriptionId}`,
  );

  return {
    valid: true, // For now, trust client (should be server-verified in production)
    warning: "Receipt validation not yet implemented",
  };
}

/**
 * Verify subscription status is accurate for user
 * @param {object} user - User document
 * @param {object} subscriptionData - Current subscription data
 * @return {object} - { statusOk: boolean, action?: string }
 */
function verifySubscriptionStatus(user, subscriptionData) {
  if (!user || !user.isPro) {
    return {
      statusOk: true,
      action: "none",
    };
  }

  // User is marked PRO - verify subscription is still active
  const activeCheck = isSubscriptionActive(subscriptionData);

  if (!activeCheck.active) {
    return {
      statusOk: false,
      action: "downgrade_from_pro",
      reason: activeCheck.reason,
    };
  }

  return {
    statusOk: true,
    action: "none",
    expiryDate: activeCheck.expiryDate,
  };
}

/**
 * Handle subscription renewal/expiry
 * @param {object} userRef - Firestore user document reference
 * @param {string} action - "renew" | "expire"
 * @return {Promise<object>} - { success: boolean }
 */
async function handleSubscriptionChange(userRef, action) {
  if (!userRef) {
    return {
      success: false,
      error: "Invalid user reference",
    };
  }

  try {
    if (action === "renew") {
      await userRef.update({
        isPro: true,
        proRenewedAt: new Date(),
      });
      console.log("✅ Subscription renewed");
    } else if (action === "expire") {
      await userRef.update({
        isPro: false,
        proExpiredAt: new Date(),
      });
      console.log("✅ Subscription downgraded (expired)");
    }

    return {
      success: true,
    };
  } catch (error) {
    console.error("❌ Failed to handle subscription change:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

module.exports = {
  isSubscriptionActive,
  validateSubscriptionToken,
  verifySubscriptionStatus,
  handleSubscriptionChange,
};
