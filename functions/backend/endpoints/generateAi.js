/**
 * Cloud Function: Generate AI
 * HTTP Trigger Endpoint: POST /api/generateAi
 *
 * Spec: Main AI generation endpoint with full monetization checks
 */

const {onRequest} = require("firebase-functions/v2/https");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

// Internal modules
const aiExecute = require("../ai/executeAi");
const firestoreSchema = require("../security/firestoreSchema");
const aiGuard = require("../security/aiGuard");
const dailyLimitValidator = require("../validators/dailyLimitValidator");
const abuseDetection = require("../validators/abuseDetection");
const counters = require("../common/counters");
const analytics = require("../common/analytics");
const proAccess = require("../pro/proAccess");
const proLimits = require("../pro/proLimits");
const nonProAccess = require("../non-pro/nonProAccess");
const rewardTokenManager = require("../non-pro/rewardTokenManager");
const resetLock = require("../security/resetLock");
const regionTier = require("../common/regionTier");
const config = require("../config");
const remoteConfigHelper = require("../common/remoteConfigHelper");

/**
 * Main AI generation endpoint
 * Request body:
 * {
 *   prompt: string,
 *   conversationHistory: Array,
 *   quality?: "standard" | "premium",
 *   rewardGrantToken?: string (if using rewarded access),
 *   locale?: string (full locale tag for cultural adaptation, e.g. "en-US", "ru-RU")
 * }
 */
async function generateAiHandler(req, res) {
  const db = getFirestore();
  let userId;
  let userRef = null;
  let consumedCounter = null; // "nano", "mini", or "trial" — hoisted for rollback in outer catch
  let trialResult = null;
  let accessMethod = "unknown"; // hoisted for rollback in outer catch

  // ════════════════════════════════════════════════════════════════
  // 0. CHECK DAILY RESET LOCK (PREVENT RACE CONDITIONS)
  // ════════════════════════════════════════════════════════════════

  const lockStatus = await resetLock.isResetLocked();
  if (lockStatus.isLocked) {
    logger.warn("⏸️ Request blocked: Daily reset in progress");
    return res.status(503).json({
      error: "System maintenance in progress. Please try again in 1 minute.",
      resetInProgress: true,
    });
  }

  // ════════════════════════════════════════════════════════════════
  // 1. AUTHENTICATION & USER VALIDATION
  // ════════════════════════════════════════════════════════════════

  try {
    // Get Firebase Auth token from headers
    const authToken = req.headers.authorization?.split("Bearer ")[1];
    if (!authToken) {
      logger.warn("❌ Auth failed: Missing authentication token");
      return res.status(401).json({error: "Missing authentication token"});
    }

    // Verify Firebase ID token
    const {getAuth} = require("firebase-admin/auth");
    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(authToken);
      userId = decodedToken.uid;
      logger.info(`✅ Auth passed | User: ${userId} | Email: ${decodedToken.email}`);
    } catch (authError) {
      logger.warn(`❌ Auth failed: Invalid token - ${authError.message}`);
      return res.status(401).json({error: "Invalid authentication"});
    }

    logger.info(`📥 AI Request | Prompt length: ${req.body?.prompt?.length || 0} chars`);
    logger.info(`🎯 Quality: ${req.body?.quality || "default"}`);
    logger.info(`🌍 Locale: ${req.body?.locale || "not provided"}`);
    logger.info(`🗣️  Language: ${req.body?.language || "en (default)"}`);

    // ════════════════════════════════════════════════════════════════
    // 2. FETCH USER DOCUMENT & VALIDATE SCHEMA
    // ════════════════════════════════════════════════════════════════

    userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(404).json({error: "User not found"});
    }

    // Auto-repair user document if needed
    const schemaCheck = firestoreSchema.ensureValidUserDocument(userDoc.data());
    const user = schemaCheck.user;

    if (schemaCheck.wasRepaired) {
      await userRef.update(user);
      logger.warn("🔧 User document repaired with missing fields");
    }

    // CRITICAL: Stamp uid from auth token — Firestore doc.data() does NOT include the document ID,
    // and many user docs were created before createUserDocument() started setting uid.
    // This is the authoritative source (verified Firebase Auth token).
    user.uid = userId;

    // Derive isPro from plan field (Firestore stores "plan" not "isPro")
    user.isPro = user.plan?.toLowerCase() === "pro" || user.isPro === true;

    logger.info(`👤 User fetched | Tier: ${user.regionTier} | PRO: ${user.isPro} | UID: ${user.uid}`);

    // ════════════════════════════════════════════════════════════════
    // 2.1 RE-EVALUATE REGION TIER ON APP VERSION CHANGE
    // ════════════════════════════════════════════════════════════════

    const currentAppVersion = req.headers["x-app-version"];
    if (currentAppVersion && user.regionTierAppVersion !== currentAppVersion) {
      logger.info(
          `🔄 App version changed: ${user.regionTierAppVersion} → ${currentAppVersion}. ` +
          `Re-evaluating region tier...`,
      );

      const newTier = regionTier.resolveRegionTier({
        storeCountry: req.headers["x-store-country"],
        deviceLocale: req.headers["x-device-locale"],
        ipCountry: req.headers["x-ip-country"],
      });

      if (newTier !== user.regionTier) {
        logger.warn(`⚠️ Region tier changed: ${user.regionTier} → ${newTier}`);
        user.regionTier = newTier;
        await userRef.update({
          regionTier: newTier,
          regionTierAppVersion: currentAppVersion,
          regionTierResolvedAt: new Date(),
        });
      } else {
        await userRef.update({
          regionTierAppVersion: currentAppVersion,
        });
      }
    }

    // ════════════════════════════════════════════════════════════════
    // 2.5 VERIFY TIER-SPECIFIC CONSTRAINTS
    // ════════════════════════════════════════════════════════════════

    // Premium quality (mini model) is Tier-1 PRO ONLY
    if (req.body.quality === "premium" && (!user.isPro || user.regionTier !== "tier1")) {
      logger.warn(`⚠️ Tier ${user.regionTier} user attempted premium quality (mini model) - blocked`);
      return res.status(403).json({
        error: "Premium AI model is only available for Tier-1 PRO members",
        tierRestriction: true,
      });
    }

    // PRO subscription only available in Tier-1
    if (user.isPro && user.regionTier !== "tier1") {
      logger.warn(`⚠️ PRO flag set for Tier ${user.regionTier} user - downgrading to non-PRO`);
      user.isPro = false; // Force downgrade to non-PRO
    }

    logger.info(`👤 User fetched | Tier: ${user.regionTier} | PRO: ${user.isPro}`);

    // ════════════════════════════════════════════════════════════════
    // 3. GET DAILY COUNTERS
    // ════════════════════════════════════════════════════════════════

    const countersData = counters.getCurrentCounters(userDoc);
    logger.info(
        `📊 Daily counters | Nano: ${countersData.aiNanoUsedToday}, ` +
        `Mini: ${countersData.aiMiniUsedToday}, ` +
        `Rewarded ads: ${countersData.rewardedAdsWatchedToday}`,
    );

    // ════════════════════════════════════════════════════════════════
    // 4. DETERMINE ACCESS METHOD (PRO vs Non-PRO)
    // ════════════════════════════════════════════════════════════════

    accessMethod = "unknown";

    if (user.isPro) {
      // ════════════════════════════════════════════════════════════════
      // PRO USER PATH: Trial first → Then nano/mini (max 20 each)
      // ════════════════════════════════════════════════════════════════

      // STEP 1: Check if PRO user has pending trial generations
      if (!user.hasUsedTrial && user.regionTier !== "tier3") {
        accessMethod = "trial";
        req.body.quality = "nano"; // Trial uses nano model
        logger.info(`🎁 PRO user has pending trial - using trial first | User: ${userId}`);
      } else {
        // STEP 2: Auto-select model (nano or mini, max 20 each)
        const proPhase = proLimits.getProModelPhase(countersData);

        if (proPhase.phase === "exhausted") {
          logger.info(`🚫 PRO user all quota exhausted | User: ${userId}`);
          return res.status(429).json({
            error: "All daily AI generations used. Come back tomorrow!",
            blocked: true,
            phase: "exhausted",
          });
        }

        // Server-authoritative: override client quality with best available model
        req.body.quality = proPhase.model; // "nano" or "mini"

        const proRestrictions = proAccess.enforceProRestrictions(
            user,
            countersData,
            proPhase.model,
        );

        if (!proRestrictions.allowed) {
          return res.status(429).json({
            error: proRestrictions.reason,
            blocked: true,
          });
        }

        accessMethod = "pro";
        logger.info(
            `✅ PRO allocation: Model=${proPhase.model} | ` +
            `Remaining: ${proPhase.remaining} | User: ${userId}`,
        );
      }
    } else {
      // Non-PRO user path
      const accessMethodInfo = await nonProAccess.getAccessMethod(
          user,
          countersData,
          req.body.rewardGrantToken, // Pass token to skip ad quota check if provided
      );

      if (accessMethodInfo.accessMethod === "blocked") {
        return res.status(429).json({
          error: accessMethodInfo.message,
          blocked: true,
        });
      }

      accessMethod = accessMethodInfo.accessMethod;

      // ════════════════════════════════════════════════════════════════
      // 4.0 SAFETY CHECK: Is this tier's ads disabled in Remote Config?
      // ════════════════════════════════════════════════════════════════

      if (accessMethod === "rewarded") {
        const tierDisabled = await remoteConfigHelper.isTierDisabledInRemoteConfig(user.regionTier);
        if (tierDisabled) {
          logger.warn(
              `🚨 Tier ${user.regionTier} has ads disabled in Remote Config | User: ${userId}`,
          );

          await analytics.logAiGenerationBlocked(
              userId,
              user.regionTier,
              "tier_disabled_remote_config",
          );

          return res.status(503).json({
            error: "AI service temporarily unavailable for your region",
            tierDisabled: true,
            reason: "Ad system disabled via Remote Config",
          });
        }
      }

      // ════════════════════════════════════════════════════════════════
      // 4.1 VALIDATE REWARD TOKEN (CRITICAL SECURITY FIX)
      // ════════════════════════════════════════════════════════════════

      // If using rewarded access, validate reward grant token
      if (accessMethod === "rewarded") {
        const rewardToken = req.body.rewardGrantToken;

        // MANDATORY CHECK: Token must be provided
        if (!rewardToken) {
          logger.warn(`🚫 Rewarded access denied: Missing reward token | User: ${userId}`);
          return res.status(403).json({
            error: "Missing reward grant token. Please watch an ad first.",
            blocked: true,
            requiresReward: true,
          });
        }

        // MANDATORY CHECK: Validate token against stored tokens
        const tokenValidation = rewardTokenManager.validateRewardToken(user, rewardToken);
        if (!tokenValidation.valid) {
          logger.warn(
              `🚫 Rewarded access denied: ${tokenValidation.reason} | ` +
              `User: ${userId} | Token: ${rewardToken.substring(0, 8)}...`,
          );

          await analytics.logAiGenerationBlocked(
              userId,
              user.regionTier,
              "invalid_reward_token",
          );

          return res.status(403).json({
            error: tokenValidation.reason,
            blocked: true,
            requiresReward: true,
          });
        }

        logger.info(
            `✅ Reward token validated | User: ${userId} | ` +
            `Unlocks remaining: ${tokenValidation.tokenData.aiUnlocksRemaining}`,
        );

        // Store token data for consumption after successful AI generation
        req.rewardTokenData = {
          token: rewardToken,
          unlocks: tokenValidation.tokenData.aiUnlocksRemaining,
        };
      }

      // ════════════════════════════════════════════════════════════════
      // 4.2 TIER-3 IMMEDIATE CONSUMPTION CHECK
      // ════════════════════════════════════════════════════════════════

      // Tier-3 requires fresh token for EACH generation (no stored unlocks)
      if (user.regionTier === "tier3" && accessMethod === "rewarded") {
        const rewardedConfig = config.REWARDED_ADS.tier3;
        if (rewardedConfig.immediate_consumption) {
          // For Tier-3, we already validated token above
          // Token must be freshly claimed (from this session)
          logger.info("✅ Tier-3 immediate consumption check passed");
        }
      }
    }

    // ════════════════════════════════════════════════════════════════
    // 5. PERFORM PRE-EXECUTION GUARDS
    // ════════════════════════════════════════════════════════════════

    const guardResults = aiGuard.performPreExecutionGuards({
      requiresReward: accessMethod === "rewarded",
      accessMethod: accessMethod,
      userLimits: dailyLimitValidator.getDailyLimits(user),
      userCounters: countersData,
      adState: req.body.adState, // If using rewarded
      rewardData: req.body.rewardData, // If using rewarded
      approvalResult: req.body.approvalResult, // If using rewarded
      providedToken: req.body.rewardGrantToken,
    });

    if (!guardResults.canExecute) {
      logger.warn(`🚫 Guard check failed | User: ${userId} | Failures: ${guardResults.failures.length}`);
      guardResults.failures.forEach((f) => logger.warn(`   - ${f}`));

      await analytics.logAiGenerationBlocked(userId, user.regionTier, "guard_check_failed");

      return res.status(403).json({
        error: "Pre-execution guard failed",
        failures: guardResults.failures,
      });
    }

    logger.info(`✅ All guards passed | User: ${userId}`);

    // ════════════════════════════════════════════════════════════════
    // 6. ABUSE DETECTION
    // ════════════════════════════════════════════════════════════════

    const abuseCheckResult = abuseDetection.performAbuseCheck({
      recentRequestTimestamps: user.recentRequestTimestamps || [],
      recentPrompts: user.recentPrompts || [],
      currentPrompt: req.body.prompt,
      sessionData: req.body.sessionData,
    });

    if (abuseCheckResult.abuseDetected) {
      console.warn(
          `⚠️ Abuse detected (${abuseCheckResult.severity}) | ` +
          `Signals: ${abuseCheckResult.signalCount}`,
      );

      if (abuseCheckResult.severity === "high") {
        return res.status(429).json({
          error: "Rate limit exceeded - please try again later",
          abused: true,
        });
      }

      // For medium abuse, force nano model
      req.body.quality = "standard";
    }

    // ════════════════════════════════════════════════════════════════
    // 7. CONSUME COUNTERS & TRIAL (ON REQUEST, BEFORE AI CALL)
    //    Counters consumed when request arrives — not after AI success.
    //    If AI fails → counter is REVERSED (rollback).
    // ════════════════════════════════════════════════════════════════

    // consumedCounter & trialResult are hoisted to outer scope for rollback safety

    // trial → trialGenerationsRemaining-- (no nano/mini increment)
    // pro   → aiMiniUsedToday++ OR aiNanoUsedToday++
    // non-pro rewarded → aiNanoUsedToday++ (always nano)
    if (accessMethod === "trial") {
      const trial = require("../non-pro/trial");

      if (!user.trialStartedAt) {
        logger.info(`🎁 [CONSUME] Starting trial for user ${userId} | Tier: ${user.regionTier}`);
        await trial.startTrial(userRef, user.regionTier);
      }

      trialResult = await trial.decrementTrial(userRef);
      consumedCounter = "trial";
      logger.info(`📉 [CONSUME] trialGenerationsRemaining-- | Remaining: ${trialResult.remaining} | User: ${userId}`);

      if (trialResult.trialComplete) {
        logger.info(`🎁 [CONSUME] Trial completed for user ${userId}`);
        await analytics.logTrialCompleted(userId, user.regionTier, trialResult.remaining);
      }
    } else if (req.body.quality === "mini" && user.isPro) {
      await counters.incrementAiMini(userRef);
      consumedCounter = "mini";
      logger.info(`📊 [CONSUME] aiMiniUsedToday++ | User: ${userId}`);
    } else {
      await counters.incrementAiNano(userRef);
      consumedCounter = "nano";
      logger.info(`📊 [CONSUME] aiNanoUsedToday++ | User: ${userId}`);
    }

    // Consume reward token (if rewarded access)
    if (accessMethod === "rewarded" && req.rewardTokenData) {
      const consumeResult = await rewardTokenManager.consumeRewardToken(
          userRef,
          req.rewardTokenData.token,
          req.rewardTokenData.unlocks,
      );

      if (!consumeResult.success) {
        logger.error(`❌ Failed to consume reward token: ${consumeResult.error}`);
      } else {
        logger.info(
            `✅ Reward token consumed | Remaining: ${consumeResult.remaining} | ` +
            `Fully consumed: ${consumeResult.fullyConsumed}`,
        );
      }
    }

    // Persist abuse detection data
    try {
      const timestamps = user.recentRequestTimestamps || [];
      const newTimestamps = [...timestamps, new Date()].slice(-20);

      const prompts = user.recentPrompts || [];
      const newPrompts = [
        ...prompts,
        {
          prompt: req.body.prompt.substring(0, 100),
          timestamp: new Date(),
        },
      ].slice(-10);

      await userRef.update({
        recentRequestTimestamps: newTimestamps,
        recentPrompts: newPrompts,
      });
    } catch (error) {
      logger.warn(`⚠️ Failed to persist abuse data: ${error.message}`);
    }

    // ════════════════════════════════════════════════════════════════
    // 8. EXECUTE AI GENERATION
    // ════════════════════════════════════════════════════════════════

    const aiResult = await aiExecute.executeAiGeneration({
      user,
      userPrompt: req.body.prompt,
      conversationHistory: req.body.conversationHistory || [],
      quality: req.body.quality || "standard",
      systemPrompt: req.body.systemPrompt,
      locale: req.body.locale || null,
      language: req.body.language || "en",
    });

    if (!aiResult.success) {
      // ════════════════════════════════════════════════════════════════
      // 8.1 GUARANTEED ROLLBACK — AI failed, MUST give the user their count back
      // ════════════════════════════════════════════════════════════════
      logger.error(`❌ [AI FAILED] AI execution failed | User: ${userId} | Error: ${aiResult.error}`);
      logger.warn(`🔄 [ROLLBACK] Reversing consumed counter: ${consumedCounter} | User: ${userId}`);

      let rollbackSuccess = false;
      let rollbackAttempts = 0;
      const MAX_ROLLBACK_RETRIES = 3;
      const ROLLBACK_RETRY_DELAY_MS = 500;

      // 🚀 GUARANTEED ROLLBACK: Retry up to 3 times if it fails
      while (rollbackAttempts < MAX_ROLLBACK_RETRIES && !rollbackSuccess) {
        rollbackAttempts++;
        try {
          if (consumedCounter === "nano") {
            const {FieldValue} = require("firebase-admin/firestore");
            const rollbackData = {aiNanoUsedToday: FieldValue.increment(-1)};
            if (accessMethod === "rewarded" && req.rewardTokenData) {
              const token = req.rewardTokenData.token;
              rollbackData[`activeRewardTokens.${token}.aiUnlocksRemaining`] = FieldValue.increment(1);
              rollbackData[`activeRewardTokens.${token}.consumed`] = false;
            }
            await userRef.update(rollbackData);
            logger.info(`✅ [ROLLBACK] aiNanoUsedToday-- (reversed) | User: ${userId}`);
            if (accessMethod === "rewarded" && req.rewardTokenData) {
              logger.info(`✅ [ROLLBACK] rewardToken restored | Token: ${req.rewardTokenData.token}`);
            }
            rollbackSuccess = true;
          } else if (consumedCounter === "mini") {
            await counters.incrementAiMini(userRef, -1);
            logger.info(`✅ [ROLLBACK] aiMiniUsedToday-- (reversed) | User: ${userId}`);
            rollbackSuccess = true;
          } else if (consumedCounter === "trial") {
            // Reverse: trialGenerationsRemaining++ and undo hasUsedTrial if it was just completed
            const {FieldValue} = require("firebase-admin/firestore");
            const rollbackData = {
              trialGenerationsRemaining: FieldValue.increment(1),
            };
            // If trial was marked complete by this request, undo that
            if (trialResult && trialResult.trialComplete) {
              rollbackData.hasUsedTrial = false;
              rollbackData.trialCompletedAt = null;
              logger.info(`🔄 [ROLLBACK] Undoing hasUsedTrial=true (trial wasn't actually used) | User: ${userId}`);
            }
            await userRef.update(rollbackData);
            logger.info(`✅ [ROLLBACK] trialGenerationsRemaining++ (reversed) | User: ${userId}`);
            rollbackSuccess = true;
          }
        } catch (rollbackError) {
          logger.warn(
              `⚠️ [ROLLBACK ATTEMPT ${rollbackAttempts}/${MAX_ROLLBACK_RETRIES}] Failed | ` +
              `User: ${userId} | Error: ${rollbackError.message}`,
          );

          // Wait before retrying (exponential backoff)
          if (rollbackAttempts < MAX_ROLLBACK_RETRIES) {
            const baseDelay = ROLLBACK_RETRY_DELAY_MS * Math.pow(2, rollbackAttempts - 1);
            const jitter = Math.floor(Math.random() * 200);
            await new Promise((resolve) => setTimeout(resolve, baseDelay + jitter));
          }
        }
      }

      // 🚨 CRITICAL: If rollback failed after all retries, return special status
      if (!rollbackSuccess) {
        logger.error(
            `🚨 [ROLLBACK PERMANENT FAILURE] Counter NOT reversed after ${MAX_ROLLBACK_RETRIES} attempts | ` +
            `User: ${userId} | Counter: ${consumedCounter}`,
        );

        await analytics.logAiGenerationBlocked(
            userId,
            user.regionTier,
            "ai_execution_error_rollback_failed",
        );

        // Return status 500 + special flag so frontend knows to force-reload user data
        return res.status(500).json({
          error: aiResult.error || "AI generation failed",
          rollbackFailed: true,
          forceReloadUser: true,
        });
      }

      await analytics.logAiGenerationBlocked(
          userId,
          user.regionTier,
          "ai_execution_error",
      );

      return res.status(500).json({
        error: aiResult.error || "AI generation failed",
        rollbackSuccess: true,
      });
    }

    // ════════════════════════════════════════════════════════════════
    // 9. LOG ANALYTICS
    // ════════════════════════════════════════════════════════════════

    logger.info(`📈 Logging analytics | Event: ai_generation_success | Model: ${aiResult.model}`);

    await analytics.logAiGenerationSuccess(
        userId,
        user.regionTier,
        accessMethod,
        aiResult.model,
        req.body.prompt.length,
        aiResult.response.length,
    );

    // ════════════════════════════════════════════════════════════════
    // 10. RETURN RESPONSE
    // ════════════════════════════════════════════════════════════════

    logger.info(`✅ AI generation complete | User: ${userId} | Response length: ${aiResult.response.length} chars`);

    console.log("═════ RESPONSE OBJECT ═════");
    console.log(`Response type: ${typeof aiResult.response}`);
    console.log(`Response length: ${aiResult.response?.length || "N/A"}`);
    console.log(`Response preview: ${aiResult.response.substring(0, 200)}...`);
    console.log(`Response end: ...${aiResult.response.substring(aiResult.response.length - 100)}`);
    console.log("═════════════════════════");

    return res.status(200).json({
      success: true,
      response: aiResult.response,
      model: aiResult.model,
      accessMethod,
      warning: aiResult.warning,
    });
  } catch (error) {
    logger.error(`❌ generateAi handler error | User: ${userId} | Error: ${error.message}`, error);

    // ════════════════════════════════════════════════════════════════
    // OUTER CATCH ROLLBACK — GUARANTEED — if counter was consumed but an unexpected
    // crash happened (not caught by section 8.1), MUST revert it here with retries.
    // ════════════════════════════════════════════════════════════════
    if (consumedCounter && userRef) {
      logger.warn(`🔄 [OUTER ROLLBACK] Reversing consumed counter: ${consumedCounter} | User: ${userId}`);

      let rollbackSuccess = false;
      let rollbackAttempts = 0;
      const MAX_ROLLBACK_RETRIES = 3;
      const ROLLBACK_RETRY_DELAY_MS = 500;

      // 🚀 GUARANTEED ROLLBACK: Retry up to 3 times if it fails
      while (rollbackAttempts < MAX_ROLLBACK_RETRIES && !rollbackSuccess) {
        rollbackAttempts++;
        try {
          if (consumedCounter === "nano") {
            const {FieldValue} = require("firebase-admin/firestore");
            const rollbackData = {aiNanoUsedToday: FieldValue.increment(-1)};
            if (accessMethod === "rewarded" && req.rewardTokenData) {
              const token = req.rewardTokenData.token;
              rollbackData[`activeRewardTokens.${token}.aiUnlocksRemaining`] = FieldValue.increment(1);
              rollbackData[`activeRewardTokens.${token}.consumed`] = false;
            }
            await userRef.update(rollbackData);
            logger.info(`✅ [OUTER ROLLBACK] aiNanoUsedToday-- (reversed) | User: ${userId}`);
            if (accessMethod === "rewarded" && req.rewardTokenData) {
              logger.info(`✅ [OUTER ROLLBACK] rewardToken restored | Token: ${req.rewardTokenData.token}`);
            }
            rollbackSuccess = true;
          } else if (consumedCounter === "mini") {
            await counters.incrementAiMini(userRef, -1);
            logger.info(`✅ [OUTER ROLLBACK] aiMiniUsedToday-- (reversed) | User: ${userId}`);
            rollbackSuccess = true;
          } else if (consumedCounter === "trial") {
            const {FieldValue} = require("firebase-admin/firestore");
            const rollbackData = {trialGenerationsRemaining: FieldValue.increment(1)};
            if (trialResult && trialResult.trialComplete) {
              rollbackData.hasUsedTrial = false;
              rollbackData.trialCompletedAt = null;
              logger.info(`🔄 [OUTER ROLLBACK] Undoing hasUsedTrial=true | User: ${userId}`);
            }
            await userRef.update(rollbackData);
            logger.info(`✅ [OUTER ROLLBACK] trialGenerationsRemaining++ (reversed) | User: ${userId}`);
            rollbackSuccess = true;
          }
        } catch (rollbackErr) {
          logger.warn(
              `⚠️ [OUTER ROLLBACK ATTEMPT ${rollbackAttempts}/${MAX_ROLLBACK_RETRIES}] Failed | ` +
              `User: ${userId} | Error: ${rollbackErr.message}`,
          );

          // Wait before retrying (exponential backoff)
          if (rollbackAttempts < MAX_ROLLBACK_RETRIES) {
            const baseDelay = ROLLBACK_RETRY_DELAY_MS * Math.pow(2, rollbackAttempts - 1);
            const jitter = Math.floor(Math.random() * 200);
            await new Promise((resolve) => setTimeout(resolve, baseDelay + jitter));
          }
        }
      }

      // 🚨 CRITICAL: If rollback failed after all retries, return special status
      if (!rollbackSuccess) {
        logger.error(
            `🚨 [OUTER ROLLBACK PERMANENT FAILURE] Counter NOT reversed after ${MAX_ROLLBACK_RETRIES} attempts | ` +
            `User: ${userId} | Counter: ${consumedCounter} | Original error: ${error.message}`,
        );

        return res.status(500).json({
          error: "Something went wrong. Please try again.",
          rollbackFailed: true,
          forceReloadUser: true,
        });
      }
    }

    return res.status(500).json({
      error: "Something went wrong. Please try again.",
    });
  }
}

// Export as Cloud Function (HTTP trigger)
module.exports = onRequest(
    {region: "us-central1", timeoutSeconds: 60},
    generateAiHandler,
);
