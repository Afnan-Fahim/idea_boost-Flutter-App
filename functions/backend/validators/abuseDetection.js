/**
 * Abuse Detection
 * Spec: 6.1 ABUSE DETECTION (LIGHTWEIGHT)
 *
 * Signals:
 * - Extremely high request frequency
 * - High prompt similarity ratio
 * - Continuous usage beyond normal session duration
 *
 * Mitigation:
 * - Temporary throttling
 * - Forced downgrade to nano model
 * - Silent cooldown (no UI penalties)
 */

const config = require("../config");

/**
 * Simple string similarity using Levenshtein distance
 * (Fast, works for prompt comparison)
 * @param {string} str1 - First string
 * @param {string} str2 - Second string
 * @return {number} - Similarity score 0-1 (1 = identical)
 */
function stringSimilarity(str1, str2) {
  // Handle null/undefined/non-string inputs
  if (!str1 || !str2 || typeof str1 !== "string" || typeof str2 !== "string") {
    return 0;
  }

  const s1 = str1.toLowerCase().trim();
  const s2 = str2.toLowerCase().trim();

  if (s1 === s2) return 1;

  const longer = s1.length > s2.length ? s1 : s2;
  const shorter = s1.length > s2.length ? s2 : s1;

  if (longer.length === 0) return 1;

  const editDistance = getEditDistance(shorter, longer);
  return (longer.length - editDistance) / longer.length;
}

/**
 * Calculate edit distance (Levenshtein)
 * @param {string} s1 - First string
 * @param {string} s2 - Second string
 * @return {number} - Edit distance
 */
function getEditDistance(s1, s2) {
  const costs = [];
  for (let i = 0; i <= s1.length; i++) {
    let lastValue = i;
    for (let j = 0; j <= s2.length; j++) {
      if (i === 0) {
        costs[j] = j;
      } else if (j > 0) {
        let newValue = costs[j - 1];
        if (s1.charAt(i - 1) !== s2.charAt(j - 1)) {
          newValue = Math.min(Math.min(newValue, lastValue), costs[j]) + 1;
        }
        costs[j - 1] = lastValue;
        lastValue = newValue;
      }
    }
    if (i > 0) costs[s2.length] = lastValue;
  }
  return costs[s2.length];
}

/**
 * Check for high request frequency abuse
 * @param {Array} recentRequests - Recent request timestamps
 * @return {object} - { isAbuse: boolean, requestsInWindow: number, threshold: number }
 */
function checkHighFrequency(recentRequests) {
  if (!recentRequests || recentRequests.length === 0) {
    return {
      isAbuse: false,
      requestsInWindow: 0,
      threshold: config.ABUSE_DETECTION.high_frequency_threshold,
    };
  }

  const now = Date.now();
  const windowMs = config.ABUSE_DETECTION.high_frequency_window_minutes * 60 * 1000;
  const recentCount = recentRequests.filter((ts) => now - ts < windowMs).length;
  const threshold = config.ABUSE_DETECTION.high_frequency_threshold;
  const isAbuse = recentCount >= threshold;

  if (isAbuse) {
    console.warn(
        `🚨 High frequency abuse detected | ${recentCount} requests in ` +
        `${config.ABUSE_DETECTION.high_frequency_window_minutes} min (threshold: ${threshold})`,
    );
  }

  return {
    isAbuse,
    requestsInWindow: recentCount,
    threshold,
  };
}

/**
 * Check for high prompt similarity abuse (spam detection)
 * @param {Array} recentPrompts - Recent user prompts
 * @param {string} currentPrompt - Current user prompt
 * @return {object} - { isAbuse: boolean, maxSimilarity: number, threshold: number }
 */
function checkHighSimilarity(recentPrompts, currentPrompt) {
  // Ensure inputs are valid
  if (!Array.isArray(recentPrompts) || recentPrompts.length === 0 ||
      !currentPrompt || typeof currentPrompt !== "string") {
    return {
      isAbuse: false,
      maxSimilarity: 0,
      threshold: config.ABUSE_DETECTION.high_similarity_threshold,
    };
  }

  const threshold = config.ABUSE_DETECTION.high_similarity_threshold;
  let maxSimilarity = 0;

  for (const prompt of recentPrompts) {
    // Skip non-string prompts
    if (typeof prompt !== "string") {
      continue;
    }

    const similarity = stringSimilarity(prompt, currentPrompt);
    if (similarity > maxSimilarity) {
      maxSimilarity = similarity;
    }
    if (similarity >= threshold) {
      console.warn(
          `🚨 High similarity spam detected | Similarity: ${similarity.toFixed(2)} ` +
          `(threshold: ${threshold})`,
      );
      return {
        isAbuse: true,
        maxSimilarity: similarity,
        threshold,
      };
    }
  }

  return {
    isAbuse: false,
    maxSimilarity,
    threshold,
  };
}

/**
 * Check for continuous long session abuse
 * @param {object} sessionData - Session tracking data
 * @return {object} - { isAbuse: boolean, sessionDuration: number, warningThreshold: number }
 */
function checkLongSession(sessionData) {
  if (!sessionData || !sessionData.sessionStartTime) {
    return {
      isAbuse: false,
      sessionDuration: 0,
      warningThreshold: config.ABUSE_DETECTION.session_duration_warning_minutes,
    };
  }

  const now = Date.now();
  const durationMs = now - sessionData.sessionStartTime;
  const durationMinutes = durationMs / (1000 * 60);
  const warningThreshold = config.ABUSE_DETECTION.session_duration_warning_minutes;

  const isAbuse = durationMinutes > warningThreshold * 2; // 2x threshold = hard abuse

  if (durationMinutes > warningThreshold) {
    const level = isAbuse ? "ABUSE" : "WARNING";
    console.warn(
        `⚠️ [${level}] Long session detected | ${durationMinutes.toFixed(1)} min ` +
        `(warning at ${warningThreshold} min, hard limit ${warningThreshold * 2} min)`,
    );
  }

  return {
    isAbuse,
    sessionDuration: durationMinutes,
    warningThreshold,
  };
}

/**
 * Aggregate abuse signals and return mitigation action
 * @param {object} checkResults - Results from individual checks
 * @return {object} - { abuseDetected: boolean, severity: "low"|"medium"|"high", actions: Array }
 */
function evaluateAbuseSignals(checkResults) {
  const {frequency, similarity, longSession} = checkResults;

  let signals = 0;
  const actions = [];

  // Count abuse signals
  if (frequency?.isAbuse) {
    signals++;
    actions.push("throttle"); // Temporary throttling
  }
  if (similarity?.isAbuse) {
    signals++;
    actions.push("downgrade_model"); // Force nano model
  }
  if (longSession?.isAbuse) {
    signals++;
    actions.push("cooldown"); // Silent cooldown
  }

  let severity = "low";
  if (signals >= 2) {
    severity = "high";
    actions.push("block_temporary");
  } else if (signals === 1) {
    severity = "medium";
  }

  const abuseDetected = signals > 0;

  return {
    abuseDetected,
    severity,
    signalCount: signals,
    actions: [...new Set(actions)], // Remove duplicates
    details: checkResults,
  };
}

/**
 * Full abuse check pipeline
 * @param {object} abusyData - User abuse tracking data
 * @return {object} - Complete abuse evaluation
 */
function performAbuseCheck(abuseData) {
  if (!abuseData) {
    return {
      abuseDetected: false,
      severity: "low",
      signalCount: 0,
      actions: [],
    };
  }

  const frequencyCheck = checkHighFrequency(abuseData.recentRequestTimestamps);
  const similarityCheck = checkHighSimilarity(abuseData.recentPrompts, abuseData.currentPrompt);
  const sessionCheck = checkLongSession(abuseData.sessionData);

  return evaluateAbuseSignals({
    frequency: frequencyCheck,
    similarity: similarityCheck,
    longSession: sessionCheck,
  });
}

module.exports = {
  stringSimilarity,
  checkHighFrequency,
  checkHighSimilarity,
  checkLongSession,
  evaluateAbuseSignals,
  performAbuseCheck,
};
