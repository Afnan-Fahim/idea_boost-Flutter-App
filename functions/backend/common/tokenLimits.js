/**
 * Token Limits Enforcement v2
 * Spec: 2.1 OUTPUT LENGTH LIMITS (MANDATORY, SERVER-SIDE)
 *
 * ALL AI responses MUST be capped using max_output_tokens
 * Server-side enforcement is MANDATORY (client values ignored)
 * Hard rule: AI generation executed ONLY AFTER token cap applied
 *
 * NOTE: All limits are read from Remote Config with hardcoded fallback defaults
 * This allows dynamic adjustment without redeployment (per spec requirement)
 */

const config = require("../config");
const remoteConfigHelper = require("./remoteConfigHelper");
const logger = require("firebase-functions/logger");

/**
 * Get max output tokens for user based on tier and plan
 * Reads from Remote Config with fallback to config defaults
 * @param {object} user - User document from Firestore
 * @return {Promise<number>} - max_output_tokens for this user
 */
async function getMaxOutputTokens(user) {
  try {
    if (!user) {
      logger.warn("⚠️ User data missing for token limit, defaulting to tier3");
      return config.TOKEN_LIMITS.tier3;
    }

    const {regionTier, isPro} = user;

    // Tier-1 PRO users get premium limits
    if (isPro && regionTier === "tier1") {
      const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
          "maxOutputTokens_tier1_pro",
          config.TOKEN_LIMITS.tier1_pro,
      );
      logger.info(`📊 Token limit for Tier-1 PRO: ${remoteValue} (from Remote Config)`);
      return remoteValue;
    }

    // Non-PRO users (all rewarded)
    if (regionTier === "tier1") {
      const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
          "maxOutputTokens_tier1_free",
          config.TOKEN_LIMITS.tier1_free,
      );
      logger.info(`📊 Token limit for Tier-1 Free: ${remoteValue} (from Remote Config)`);
      return remoteValue;
    }
    if (regionTier === "tier2") {
      const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
          "maxOutputTokens_tier2",
          config.TOKEN_LIMITS.tier2,
      );
      logger.info(`📊 Token limit for Tier-2: ${remoteValue} (from Remote Config)`);
      return remoteValue;
    }
    if (regionTier === "tier3") {
      const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
          "maxOutputTokens_tier3",
          config.TOKEN_LIMITS.tier3,
      );
      logger.info(`📊 Token limit for Tier-3: ${remoteValue} (from Remote Config)`);
      return remoteValue;
    }

    return config.TOKEN_LIMITS.tier3; // Fallback
  } catch (error) {
    logger.error(`❌ Error getting token limit from Remote Config: ${error.message}`);
    logger.warn(`⚠️ Falling back to hardcoded defaults`);
    return config.TOKEN_LIMITS.tier3;
  }
}

/**
 * Get max context messages allowed
 * Reads from Remote Config with fallback to config defaults
 * Spec: 2.1 Context control - limit conversation history
 * @return {Promise<number>} - max messages to send to model
 */
async function getMaxContextMessages() {
  try {
    const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
        "maxContextMessages",
        config.CONTEXT_LIMITS.max_context_messages,
    );
    logger.info(`📊 Max context messages: ${remoteValue} (from Remote Config)`);
    return remoteValue;
  } catch (error) {
    logger.error(`❌ Error getting maxContextMessages: ${error.message}`);
    return config.CONTEXT_LIMITS.max_context_messages;
  }
}

/**
 * Get max user input character limit
 * Reads from Remote Config with fallback to config defaults
 * Spec: 2.1 Enforce max user input length (server-side)
 * @return {Promise<number>} - max characters for user input
 */
async function getMaxUserInputLength() {
  try {
    const remoteValue = await remoteConfigHelper.getRemoteConfigValue(
        "maxUserInputChars",
        config.CONTEXT_LIMITS.max_user_input_chars,
    );
    logger.info(`📊 Max user input chars: ${remoteValue} (from Remote Config)`);
    return remoteValue;
  } catch (error) {
    logger.error(`❌ Error getting maxUserInputChars: ${error.message}`);
    return config.CONTEXT_LIMITS.max_user_input_chars;
  }
}

/**
 * Validate and truncate user input
 * Reads max length from Remote Config
 * @param {string} userInput - Raw user input from client
 * @return {Promise<object>} - { valid: boolean, input: string, message?: string }
 */
async function validateUserInput(userInput) {
  try {
    if (!userInput || typeof userInput !== "string") {
      return {
        valid: false,
        input: "",
        message: "Invalid input: must be non-empty string",
      };
    }

    const maxLength = await getMaxUserInputLength();
    if (userInput.length > maxLength) {
      logger.warn(
          `⚠️ User input truncated from ${userInput.length} to ${maxLength} characters`,
      );
      return {
        valid: true,
        input: userInput.substring(0, maxLength),
        message: `Input truncated from ${userInput.length} to ${maxLength} characters`,
      };
    }

    return {
      valid: true,
      input: userInput,
    };
  } catch (error) {
    logger.error(`❌ Error validating user input: ${error.message}`);
    // Fail open - allow input, let other guards catch issues
    return {
      valid: true,
      input: userInput,
    };
  }
}

/**
 * Build AI request payload with token caps enforced
 * This is called BEFORE sending to Grok API
 * Reads all limits from Remote Config
 * @param {object} params - AI request parameters
 * @param {string} params.prompt - User prompt/input
 * @param {Array} params.messages - Conversation history
 * @param {object} params.user - User document
 * @return {Promise<object>} - Validated payload with token caps
 */
async function buildAiRequestPayload(params) {
  try {
    const {prompt, messages, user} = params;

    // Validate user input (now async, reads from Remote Config)
    const inputValidation = await validateUserInput(prompt);
    if (!inputValidation.valid) {
      throw new Error(inputValidation.message);
    }

    // Get max tokens for this user (reads from Remote Config)
    const maxOutputTokens = await getMaxOutputTokens(user);
    // Get max context messages (reads from Remote Config)
    const maxContextMessages = await getMaxContextMessages();

    // Truncate conversation history to last N messages
    const contextMessages = messages ? messages.slice(-maxContextMessages) : [];

    // Log token cap enforcement
    logger.info(
        `🔒 Token cap enforced | User: ${user.uid}, ` +
        `Tier: ${user.regionTier}, ` +
        `Max output tokens: ${maxOutputTokens}, ` +
        `Context messages: ${contextMessages.length}`,
    );

    return {
      prompt: inputValidation.input,
      messages: contextMessages,
      max_output_tokens: maxOutputTokens, // MANDATORY server-side cap
      model: params.model || "grok-default", // Set by modelSelector
    };
  } catch (error) {
    logger.error(`❌ Error building AI request payload: ${error.message}`);
    throw error;
  }
}

/**
 * Enforce token cap on response (defensive check)
 * Even if model responds with more tokens, truncate here
 * Special handling: For JSON responses, ensure complete JSON object
 * @param {string} response - AI model response
 * @param {object} user - User document
 * @return {object} - { response: string, tokensCut: boolean }
 */
function enforceResponseTokenCap(response, user) {
  const maxTokens = getMaxOutputTokens(user);

  // Estimate token count (rough: ~4 chars per token)
  const estimatedTokens = Math.ceil(response.length / 4);

  if (estimatedTokens > maxTokens) {
    // For JSON responses, find the last complete JSON object
    // This prevents truncating JSON mid-way
    const charLimit = maxTokens * 4;
    let truncated = response.substring(0, charLimit);

    // If response looks like JSON, try to close it properly
    if (response.trim().startsWith("{")) {
      // FIRST: Find the last unescaped quote to handle mid-string truncation
      let inString = false;
      let isEscaped = false;
      let lastValidStringEnd = -1;

      for (let i = 0; i < truncated.length; i++) {
        const char = truncated[i];

        // Track escape sequences
        if (char === "\\" && !isEscaped) {
          isEscaped = true;
          continue;
        }

        // Track string boundaries
        if (char === "\"" && !isEscaped) {
          inString = !inString;
          if (!inString) {
            // We just closed a string
            lastValidStringEnd = i;
          }
        }

        isEscaped = false;
      }

      // If we ended inside a string, truncate at the last closed string
      if (inString && lastValidStringEnd > 0) {
        truncated = truncated.substring(0, lastValidStringEnd + 1);
      }

      // SECOND: Now count braces and brackets from the truncated string
      let braceCount = 0;
      let bracketCount = 0;
      inString = false;
      isEscaped = false;

      for (let i = 0; i < truncated.length; i++) {
        const char = truncated[i];

        // Track escape sequences
        if (char === "\\" && !isEscaped) {
          isEscaped = true;
          continue;
        }

        // Track string state
        if (char === "\"" && !isEscaped) {
          inString = !inString;
        }

        isEscaped = false;

        // Only count structural characters outside strings
        if (!inString) {
          if (char === "{") braceCount++;
          else if (char === "}") braceCount--;
          else if (char === "[") bracketCount++;
          else if (char === "]") bracketCount--;
        }
      }

      // THIRD: Close any open structures
      // If we're still in a string, close it
      if (inString) {
        truncated += "\"";
      }
      // Close open brackets (they need to be closed before braces)
      if (bracketCount > 0) {
        truncated += "]".repeat(bracketCount);
      }
      // Close open braces
      if (braceCount > 0) {
        truncated += "}".repeat(braceCount);
      }

      console.log(
          `✅ Response truncated properly | Original: ${response.length} chars, ` +
          `Truncated: ${truncated.length} chars, ` +
          `Braces to close: ${braceCount}, Brackets to close: ${bracketCount}`,
      );
    }

    console.warn(
        `⚠️ Response truncated | User: ${user.uid}, ` +
        `Estimated tokens: ${estimatedTokens} > ${maxTokens} max, ` +
        `Original length: ${response.length}, Truncated length: ${truncated.length}`,
    );

    return {
      response: truncated,
      tokensCut: true,
      warning: `Response trimmed to fit tier limit (${maxTokens} tokens max)`,
    };
  }

  return {
    response,
    tokensCut: false,
  };
}

module.exports = {
  getMaxOutputTokens,
  getMaxContextMessages,
  getMaxUserInputLength,
  validateUserInput,
  buildAiRequestPayload,
  enforceResponseTokenCap,
};
