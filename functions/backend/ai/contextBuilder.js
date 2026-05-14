/**
 * Context Builder
 * Spec: 2.1 Context control (cost safety)
 * - Limit conversation history sent to the model
 * - Enforce max user input length
 * - Prepare context for Grok API
 *
 * NOTE: All context limits now read from Remote Config
 */

const tokenLimits = require("../common/tokenLimits");
const logger = require("firebase-functions/logger");

/**
 * Build conversation context for AI model
 * Takes only last N messages to reduce token cost
 * Reads max messages from Remote Config
 * @param {Array} conversationHistory - Full message history
 * @return {Promise<Array>} - Trimmed message history
 */
async function buildContextMessages(conversationHistory) {
  try {
    if (!conversationHistory || !Array.isArray(conversationHistory)) {
      return [];
    }

    const maxMessages = await tokenLimits.getMaxContextMessages();
    const trimmed = conversationHistory.slice(-maxMessages);

    logger.info(
        `📝 Context built | Total messages: ${conversationHistory.length}, ` +
        `Sent to model: ${trimmed.length} (max: ${maxMessages})`,
    );

    return trimmed;
  } catch (error) {
    logger.error(`❌ Error building context messages: ${error.message}`);
    // Fail open - return all messages
    return conversationHistory || [];
  }
}

/**
 * Format messages for Grok API
 * Converts app message format to API format
 * @param {Array} messages - Messages in app format
 * @return {Array} - Messages in Grok API format
 */
function formatForGrokApi(messages) {
  if (!messages || messages.length === 0) {
    return [];
  }

  return messages.map((msg) => ({
    role: msg.role || "user", // "user" or "assistant"
    content: msg.content || msg.text || "",
  }));
}

/**
 * Validate and prepare user prompt
 * Reads max input length from Remote Config
 * @param {string} userPrompt - Raw user input
 * @return {Promise<object>} - { valid: boolean, prompt: string, message?: string }
 */
async function prepareUserPrompt(userPrompt) {
  try {
    const validation = await tokenLimits.validateUserInput(userPrompt);

    if (!validation.valid) {
      return {
        valid: false,
        prompt: "",
        message: validation.message,
      };
    }

    // Trim whitespace
    const trimmed = validation.input.trim();

    if (trimmed.length === 0) {
      return {
        valid: false,
        prompt: "",
        message: "Prompt cannot be empty",
      };
    }

    return {
      valid: true,
      prompt: trimmed,
    };
  } catch (error) {
    logger.error(`❌ Error preparing user prompt: ${error.message}`);
    throw error;
  }
}

/**
 * Build complete context object for Grok request
 * Reads all limits from Remote Config
 * @param {object} params - Context parameters
 * @return {Promise<object>} - Complete context for API
 */
async function buildCompleteContext(params) {
  try {
    const {
      userPrompt,
      conversationHistory,
      user,
      systemPrompt,
    } = params;

    // Validate user prompt (reads from Remote Config)
    const promptValidation = await prepareUserPrompt(userPrompt);
    if (!promptValidation.valid) {
      throw new Error(promptValidation.message);
    }

    // Build conversation context (reads from Remote Config)
    const contextMessages = await buildContextMessages(conversationHistory);

    // Format for API
    const formattedMessages = formatForGrokApi(contextMessages);

    // Add current user message
    const allMessages = [
      ...formattedMessages,
      {
        role: "user",
        content: promptValidation.prompt,
      },
    ];

    // Get max tokens from Remote Config
    const maxTokens = await tokenLimits.getMaxOutputTokens(user);

    return {
      systemPrompt: systemPrompt || "You are a helpful AI assistant.",
      messages: allMessages,
      userPrompt: promptValidation.prompt,
      contextSize: allMessages.length,
      maxTokens: maxTokens,
    };
  } catch (error) {
    logger.error(`❌ Error building complete context: ${error.message}`);
    throw error;
  }
}

/**
 * Estimate token count for context
 * (Rough estimate: ~4 chars per token)
 * @param {Array} messages - Messages array
 * @return {number} - Estimated token count
 */
function estimateContextTokens(messages) {
  if (!messages || messages.length === 0) {
    return 0;
  }

  const totalChars = messages.reduce((sum, msg) => {
    const content = msg.content || "";
    return sum + content.length;
  }, 0);

  return Math.ceil(totalChars / 4);
}

module.exports = {
  buildContextMessages,
  formatForGrokApi,
  prepareUserPrompt,
  buildCompleteContext,
  estimateContextTokens,
};
