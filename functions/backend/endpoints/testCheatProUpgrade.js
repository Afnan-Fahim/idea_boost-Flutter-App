/**
 * Cloud Function: Test Cheat - Enable PRO
 * HTTP Trigger Endpoint: POST /api/testCheatProUpgrade
 *
 * TESTING ONLY - Debug endpoint to quickly enable PRO for Tier-1 users
 * Used for testing PRO features without dealing with subscription flow
 *
 * Security:
 * - Only works for Tier-1 users (Tier-2/3 are denied)
 * - Requires Firebase Auth
 * - Server-side validation mandatory
 * - Uses proEligibility module for tier validation
 * - Logs cheat activation for monitoring
 */

const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");
const proEligibility = require("../pro/proEligibility");

/**
 * Enable PRO for tier-1 user (CHEAT/DEBUG ONLY)
 * Validates on backend before updating Firestore
 */
async function testCheatProUpgradeHandler(req, res) {
  const db = getFirestore();
  let userId;

  try {
    // ════════════════════════════════════════════════════════════════
    // 1. AUTHENTICATION & USER VALIDATION
    // ════════════════════════════════════════════════════════════════
    const authToken = req.headers.authorization?.split("Bearer ")[1];
    if (!authToken) {
      logger.warn("❌ Cheat auth failed: Missing authentication token");
      return res.status(401).json({error: "Missing authentication token"});
    }

    // Verify Firebase ID token
    let decodedToken;
    try {
      const auth = getAuth();
      decodedToken = await auth.verifyIdToken(authToken);
      userId = decodedToken.uid;
    } catch (error) {
      logger.warn(`❌ Invalid auth token: ${error.message}`);
      return res.status(401).json({error: "Invalid authentication token"});
    }

    // Get user document
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      logger.warn(`❌ Cheat failed: User not found: ${userId}`);
      return res.status(404).json({error: "User not found"});
    }

    const user = userDoc.data();

    // ════════════════════════════════════════════════════════════════
    // 2. TIER VALIDATION - Use proEligibility module
    // ════════════════════════════════════════════════════════════════
    if (!proEligibility.isProAvailableForTier(user.regionTier)) {
      const availability = proEligibility.getProAvailabilityMessage(user.regionTier);
      logger.warn(
          `❌ Cheat blocked: PRO not available for ${user.regionTier} | ` +
          `UID: ${userId} | Reason: ${availability.message}`,
      );
      return res.status(403).json({
        error: availability.message,
        currentTier: user.regionTier,
      });
    }

    // ════════════════════════════════════════════════════════════════
    // 3. UPDATE FIRESTORE - Set isPro to true (tier-1 PRO flag)
    // ════════════════════════════════════════════════════════════════
    await db.collection("users").doc(userId).update({
      isPro: true,
      plan: "pro",
      proActivatedAt: new Date(),
      updatedAt: new Date(),
    });

    logger.info(
        `🧪 CHEAT ACTIVATED! User ${userId} (${user.regionTier}) upgraded to PRO`,
    );

    // ════════════════════════════════════════════════════════════════
    // 4. RESPONSE
    // ════════════════════════════════════════════════════════════════
    return res.status(200).json({
      success: true,
      message: "Cheat activated! User upgraded to PRO",
      plan: "pro",
      userId: userId,
      tier: user.regionTier,
    });
  } catch (error) {
    logger.error(`❌ Cheat error: ${error.message}`);
    return res.status(500).json({
      error: "Cheat failed",
      message: error.message,
    });
  }
}

// Export the handler function (will be wrapped in index.js)
module.exports = testCheatProUpgradeHandler;
