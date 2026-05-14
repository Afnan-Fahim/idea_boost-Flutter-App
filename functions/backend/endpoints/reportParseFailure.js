/**
 * Cloud Function: Report JSON Parse Failure
 * HTTP Trigger Endpoint: POST /api/reportParseFailure
 *
 * Purpose: Allow client to report if it couldn't parse the JSON response from AI generation
 * Backend will then rollback the consumption counter since the generation was unusable
 *
 * Request body:
 * {
 *   requestId: string (optional, for matching with generation request),
 *   responseLength: number (for debugging),
 *   parseErrorMessage: string (for logging),
 *   responsePreview: string (first 200 chars, for debugging)
 * }
 */

const {onRequest} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const counters = require("../common/counters");
const analytics = require("../common/analytics");

async function reportParseFailureHandler(req, res) {
  const db = getFirestore();
  let userId;

  try {
    // ════════════════════════════════════════════════════════════════
    // 1. AUTHENTICATION
    // ════════════════════════════════════════════════════════════════

    const authToken = req.headers.authorization?.split("Bearer ")[1];
    if (!authToken) {
      logger.warn("❌ Auth failed: Missing authentication token");
      return res.status(401).json({error: "Missing authentication token"});
    }

    const {getAuth} = require("firebase-admin/auth");
    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(authToken);
      userId = decodedToken.uid;
      logger.info(`✅ Auth passed | User: ${userId}`);
    } catch (authError) {
      logger.warn(`❌ Auth failed: Invalid token`);
      return res.status(401).json({error: "Invalid authentication"});
    }

    // ════════════════════════════════════════════════════════════════
    // 2. VALIDATE REQUEST
    // ════════════════════════════════════════════════════════════════

    const {parseErrorMessage, responsePreview} = req.body;

    if (!parseErrorMessage) {
      return res.status(400).json({
        error: "Missing parseErrorMessage in request body",
      });
    }

    logger.error(
        `📛 Client reported JSON parse failure | User: ${userId} | ` +
        `Error: ${parseErrorMessage} | Response preview: ${responsePreview || "N/A"}`,
    );

    // ════════════════════════════════════════════════════════════════
    // 3. ROLLBACK CONSUMPTION
    // ════════════════════════════════════════════════════════════════

    // Get user document to determine what counter to rollback
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(404).json({error: "User not found"});
    }

    const user = userDoc.data();

    // Determine which counter to rollback based on last consumption
    // This is a heuristic - we rollback the MOST RECENTLY used counter
    // In an ideal scenario, the client would specify which type was just attempted
    // For now, we check what was just consumed based on timing

    // Check trial first (if user had trial active)
    if (user.hasUsedTrial && user.trialGenerationsRemaining !== undefined) {
      await userRef.update({
        trialGenerationsRemaining: FieldValue.increment(1),
      });
      logger.info(`✅ [ROLLBACK] Rolled back trial consumption | User: ${userId}`);

      await analytics.logAiGenerationBlocked(
          userId,
          user.regionTier || "unknown",
          "parse_failure_trial_rollback",
      );

      return res.status(200).json({
        success: true,
        message: "Trial generation rollback completed",
        method: "trial",
      });
    }

    // Otherwise rollback nano (most common for non-pro)
    await counters.incrementAiNano(userRef, -1);
    logger.info(`✅ [ROLLBACK] Rolled back nano consumption | User: ${userId}`);

    await analytics.logAiGenerationBlocked(
        userId,
        user.regionTier || "unknown",
        "parse_failure_nano_rollback",
    );

    return res.status(200).json({
      success: true,
      message: "Nano generation rollback completed",
      method: "nano",
    });
  } catch (error) {
    logger.error(
        `❌ reportParseFailure handler error | User: ${userId || "unknown"} | ` +
        `Error: ${error.message}`,
        error,
    );

    return res.status(500).json({
      error: "Failed to process parse failure report",
      details: error.message,
    });
  }
}

// Export as both module and Cloud Function
module.exports = {
  reportParseFailureHandler,
  function: onRequest(
      {
        region: "us-central1",
        cors: "https://ideaboost.app",
        minInstances: 0,
      },
      reportParseFailureHandler,
  ),
};
