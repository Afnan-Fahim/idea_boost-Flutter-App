/**
 * Execute AI via Grok API
 *
 * Uses AI_MODEL_URL from .env (configurable for Grok or any API endpoint)
 * Token caps are enforced BEFORE sending to API
 */

const axios = require("axios");
const config = require("../config");
const contextBuilder = require("./contextBuilder");

/**
 * Get AI model endpoint URL from environment
 * @return {string} - API endpoint URL
 */
function getAiModelUrl() {
  const url = process.env.AI_MODEL_URL;

  if (!url) {
    throw new Error(
        "AI_MODEL_URL not configured in .env - " +
      "set it to your Grok API endpoint or alternative",
    );
  }

  return url;
}

/**
 * Get API key/token for authentication
 * @return {string} - API authentication key
 */
function getApiKey() {
  const key = process.env.AI_API_KEY;

  if (!key) {
    throw new Error("AI_API_KEY not configured in .env");
  }

  return key;
}

/**
 * Select AI model based on user tier and plan
 * @param {object} user - User document
 * @param {string} quality - "standard" or "premium"
 * @return {string} - Model identifier
 */
function selectModel(user, quality = "standard") {
  // Tier-1 PRO with premium quality → premium model
  if (user.isPro && user.regionTier === "tier1" && quality === "premium") {
    return config.AI_MODELS.premium; // grok-premium or equivalent
  }

  // All others → default model
  return config.AI_MODELS.default; // grok-default or equivalent
}

/**
 * Build Grok API request payload
 * Token caps ALREADY applied in tokenLimits.js
 * NOTE: Grok API doesn't support "system" field - prepend system prompt to first message
 * @param {object} params - Request parameters
 * @return {object} - Payload for Grok API
 */
function buildApiRequest(params) {
  const {
    messages,
    maxOutputTokens,
    model,
    temperature = 0.5,
    systemPrompt,
  } = params;

  if (!messages || messages.length === 0) {
    throw new Error("No messages provided");
  }

  // Grok API doesn't support "system" field - incorporate system prompt into first message
  const formattedMessages = [...messages];

  if (systemPrompt && formattedMessages.length > 0) {
    // Prepend system prompt to first user message
    if (formattedMessages[0].role === "user") {
      formattedMessages[0].content = `${systemPrompt}\n\n${formattedMessages[0].content}`;
    } else if (formattedMessages[0].role === "assistant") {
      // If first is assistant, add system context before
      formattedMessages.unshift({
        role: "user",
        content: systemPrompt,
      });
      formattedMessages.splice(1, 0, {
        role: "assistant",
        content: "Understood. I'll follow your instructions.",
      });
    }
  }

  return {
    model,
    messages: formattedMessages,
    max_tokens: maxOutputTokens, // Token cap from server (MANDATORY)
    temperature,
    // NOTE: DO NOT include "system" field - Grok API doesn't support it
  };
}

/**
 * Call Grok API (or configured endpoint)
 * @param {object} payload - API request payload
 * @return {Promise<object>} - API response
 */
async function callGrokApi(payload) {
  const url = getAiModelUrl();
  const apiKey = getApiKey();

  try {
    const response = await axios.post(url, payload, {
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      timeout: 30000, // 30 second timeout
    });

    if (!response.data) {
      throw new Error("Empty response from Grok API");
    }

    return response.data;
  } catch (error) {
    console.error(
        `❌ Grok API error | ${error.message} | ` +
      `Status: ${error.response?.status}`,
    );

    // Map HTTP status codes to user-friendly messages (never expose raw API errors)
    const status = error.response?.status;
    if (status === 429) {
      throw new Error("AI service is busy. Please try again in a moment.");
    } else if (status === 401 || status === 403) {
      throw new Error("AI service authentication error. Please contact support.");
    } else if (status === 400) {
      throw new Error("Invalid request to AI service. Please try again.");
    } else if (error.code === "ECONNABORTED" || error.code === "ETIMEDOUT") {
      throw new Error("AI service timed out. Please try again.");
    } else {
      throw new Error("AI service is temporarily unavailable. Please try again.");
    }
  }
}

/**
 * Validate AI response quality - ensure response is usable and not incomplete
 * Returns validation result with detailed reason if validation fails
 * @param {string} response - AI response text
 * @param {object} parsedJson - Parsed JSON object (for structural validation)
 * @return {object} - { isValid: boolean, reason?: string }
 */
function validateResponseQuality(response, parsedJson) {
  // Check 1: Response is null or undefined
  if (!response) {
    return {
      isValid: false,
      reason: "Response is null or undefined - AI returned nothing",
    };
  }

  // Check 2: Response is empty string
  if (response.trim().length === 0) {
    return {
      isValid: false,
      reason: "Response is empty string - AI generated no content",
    };
  }

  // Check 3: Response is too short (likely incomplete) - less than 3 meaningful words
  const words = response.trim().split(/\s+/).filter((w) => w.length > 0);
  if (words.length < 3) {
    return {
      isValid: false,
      reason: `Response too short (${words.length} words) - AI generation incomplete | ` +
        `Content: "${response.substring(0, 100)}"`,
    };
  }

  // Check 4: Response is just empty JSON structures with no meaningful content
  // Pattern: {}, [], {"key": {}}, etc with minimal non-whitespace chars
  if (parsedJson && typeof parsedJson === "object") {
    const jsonString = JSON.stringify(parsedJson);

    // If JSON is empty or nearly empty (less than 10 characters of actual data)
    if (jsonString.length < 10) {
      return {
        isValid: false,
        reason: `Response is empty JSON structure - no meaningful content | ` +
          `Structure: ${jsonString}`,
      };
    }

    // Check if all values in the JSON object are null, empty strings, or empty arrays
    const isEmpty = (obj) => {
      if (obj === null || obj === undefined) return true;
      if (obj === "" || obj.length === 0) return true;
      if (typeof obj === "object") {
        const values = Array.isArray(obj) ? obj : Object.values(obj);
        return values.length === 0 || values.every(isEmpty);
      }
      return false;
    };

    if (isEmpty(parsedJson)) {
      return {
        isValid: false,
        reason: `Response JSON is empty or contains only empty values - no useful content generated`,
      };
    }
  }

  // All checks passed
  return {isValid: true};
}

/**
 * Ensure JSON response is properly closed even if truncated
 * Grok API might truncate mid-word when hitting token limit
 * This function completes the JSON structure gracefully
 * @param {string} response - Raw response from AI
 * @return {string} - Valid JSON with closed structures
 */
function ensureValidJson(response) {
  if (!response || !response.trim().startsWith("{")) {
    return response; // Not JSON or empty, return as-is
  }

  let text = response.trim();

  // STEP 1: Check if we're mid-string and close it
  let inString = false;
  let isEscaped = false;
  let lastValidStringEnd = -1;

  for (let i = 0; i < text.length; i++) {
    const char = text[i];

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
    text = text.substring(0, lastValidStringEnd + 1);
  }

  // STEP 1b: Strip any trailing orphan key left by the truncation.
  // When the AI is cut off mid-value the last closed string is the KEY, not a value.
  // This leaves patterns like {"key" or {..., "key" with no colon/value.
  // Remove them so we never emit {"key"} to the client.
  text = text.replace(/,\s*"[^"]*"\s*:\s*\[$/, ",");
  text = text.replace(/,\s*"[^"]*"\s*:\s*$/, "");
  text = text.replace(/,\s*"[^"]*"\s*$/, "");
  text = text.replace(/\{\s*"[^"]*"\s*$/, "{");

  // STEP 2: Count braces and brackets to close them properly
  let braceCount = 0;
  let bracketCount = 0;
  inString = false;
  isEscaped = false;

  for (let i = 0; i < text.length; i++) {
    const char = text[i];

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

  // STEP 3: Close any open structures
  // If we're still in a string, close it
  if (inString) {
    text += "\"";
  }
  // Close open brackets (they need to be closed before braces)
  if (bracketCount > 0) {
    text += "]".repeat(bracketCount);
  }
  // Close open braces
  if (braceCount > 0) {
    text += "}".repeat(braceCount);
  }

  return text;
}

/**
 * Execute AI generation end-to-end
 * Called from endpoint after all guards passed
 * @param {object} params - Full execution parameters
 * @return {Promise<object>} - { success: boolean, response?: string, error?: string }
 */
async function executeAiGeneration(params) {
  const {
    user,
    userPrompt,
    conversationHistory,
    quality = "standard",
    systemPrompt,
    locale,
    language,
  } = params;

  if (!user || !userPrompt) {
    throw new Error("Missing user or prompt data");
  }

  try {
    // Step 0: Build system prompt with strict JSON rules.
    // NOTE: Cultural/locale adaptation is now handled in Priority 3 of the
    // Flutter PromptHandler (_getCulturalInstruction). The assembled prompt
    // already contains the locale-specific tone instructions before reaching here.
    const effectiveSystemPrompt = systemPrompt || "";

    // JSON generation rules are now managed exclusively by the Flutter PromptSystem
    // (via PromptHandler Priority 5 or direct generic template rules).
    console.log(`🌍 Locale "${locale || "none"}" (Lang: ${language || "none"}) — cultural adaptation handled by Flutter PromptHandler Priority 3`);

    // Step 1: Build context with token enforcement (now async, reads from Remote Config)
    console.log("🔨 Building context...");
    const context = await contextBuilder.buildCompleteContext({
      userPrompt,
      conversationHistory,
      user,
      systemPrompt: effectiveSystemPrompt,
    });

    // Step 2: Select model based on user tier/plan
    const model = selectModel(user, quality);
    console.log(`🤖 Selected model: ${model}`);

    // Step 3: Build API request (token cap already applied)
    const payload = buildApiRequest({
      messages: context.messages,
      maxOutputTokens: context.maxTokens,
      model,
      temperature: 0.7,
      systemPrompt: context.systemPrompt,
    });

    console.log(
        `📤 Sending to Grok | Model: ${model}, Messages: ${context.contextSize}, ` +
      `Max tokens: ${context.maxTokens}`,
    );

    // Step 4: Call Grok API
    const apiResponse = await callGrokApi(payload);

    if (!apiResponse.choices || apiResponse.choices.length === 0) {
      throw new Error("No response choices from API");
    }

    // Step 5: Extract response content
    const aiResponse = apiResponse.choices[0].message.content ||
      apiResponse.choices[0].text ||
      "";

    if (!aiResponse) {
      throw new Error("Empty response from AI model");
    }

    const tokensUsed = apiResponse.usage?.completion_tokens || 0;

    // Step 6: Ensure response JSON is valid (close any incomplete structures)
    // This is necessary because Grok API might truncate mid-word when hitting token limit
    const fixedResponse = ensureValidJson(aiResponse);

    // Step 7: CRITICAL - Validate that the "fixed" JSON is actually parseable
    // If AI response is malformed beyond repair, we should fail and rollback
    let isValidJson = false;
    let parseError = null;
    try {
      JSON.parse(fixedResponse);
      isValidJson = true;
      console.log(`✅ JSON validation passed - response is parseable`);
    } catch (jsonError) {
      isValidJson = false;
      parseError = jsonError.message;
      console.error(
          `❌ JSON validation FAILED - Response cannot be parsed even after repair | ` +
        `Error: ${parseError}`,
      );
      console.error(`   Original response length: ${aiResponse.length}`);
      console.error(
          `   Original response preview: ${aiResponse.substring(0, 150)}...`,
      );
      console.error(`   Fixed response length: ${fixedResponse.length}`);
      console.error(
          `   Fixed response preview: ${fixedResponse.substring(0, 150)}...`,
      );
    }

    // If JSON is malformed even after fix, return error (will trigger backend rollback)
    if (!isValidJson) {
      throw new Error(
          `AI response exceeds repair capabilities: ${parseError || "Unknown JSON error"}`,
      );
    }

    // Step 8: QUALITY VALIDATION - Check if response is incomplete or too short
    let parsedJson = null;
    try {
      parsedJson = JSON.parse(fixedResponse);
    } catch (e) {
      // Already validated above, just for quality check
    }

    const qualityCheck = validateResponseQuality(fixedResponse, parsedJson);
    if (!qualityCheck.isValid) {
      throw new Error(
          `🚨 RESPONSE QUALITY FAILED (WILL TRIGGER ROLLBACK): ${qualityCheck.reason}`,
      );
    }

    const estimatedTokens = Math.ceil(fixedResponse.length / 4);

    console.log(
        `✅ AI generation success | ` +
      `Original: ${aiResponse.length} chars | ` +
      `Fixed: ${fixedResponse.length} chars | ` +
      `Tokens used (API): ${tokensUsed} | ` +
      `Estimated tokens (chars/4): ${estimatedTokens} | ` +
      `JSON Valid: ${isValidJson} | ` +
      `Quality Valid: ${qualityCheck.isValid}`,
    );

    return {
      success: true,
      response: fixedResponse, // Return with JSON validation/closing
      model,
      tokensUsed,
      jsonValidated: true,
    };
  } catch (error) {
    console.error(`❌ AI execution failed | ${error.message}`);

    return {
      success: false,
      error: error.message,
    };
  }
}

module.exports = {
  getAiModelUrl,
  getApiKey,
  selectModel,
  buildApiRequest,
  callGrokApi,
  validateResponseQuality,
  ensureValidJson,
  executeAiGeneration,
};

