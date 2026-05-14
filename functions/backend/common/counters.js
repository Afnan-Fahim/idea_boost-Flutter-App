/**
 * Counter Management
 * Manages daily AI usage and rewarded ad counters
 *
 * Counters reset at 12:00 AM GMT+5 (via scheduled function)
 * Spec: 7. REQUIRED FIRESTORE FIELDS
 */

const {FieldValue} = require("firebase-admin/firestore");

/**
 * Increment AI nano model usage counter
 * @param {DocumentReference} userRef - Firestore user document reference
 * @param {number} amount - Increment amount (default 1)
 * @return {Promise<void>}
 */
async function incrementAiNano(userRef, amount = 1) {
  await userRef.update({
    aiNanoUsedToday: FieldValue.increment(amount),
  });
}

/**
 * Increment AI mini model usage counter
 * @param {DocumentReference} userRef - Firestore user document reference
 * @param {number} amount - Increment amount (default 1)
 * @return {Promise<void>}
 */
async function incrementAiMini(userRef, amount = 1) {
  await userRef.update({
    aiMiniUsedToday: FieldValue.increment(amount),
  });
}

/**
 * Increment rewarded ads watched counter
 * @param {DocumentReference} userRef - Firestore user document reference
 * @param {number} amount - Increment amount (default 1)
 * @return {Promise<void>}
 */
async function incrementRewardedAds(userRef, amount = 1) {
  await userRef.update({
    rewardedAdsWatchedToday: FieldValue.increment(amount),
  });
}

/**
 * Get current counter values
 * @param {DocumentSnapshot} userDoc - Firestore user document snapshot
 * @return {object} - { aiNanoUsedToday, aiMiniUsedToday, rewardedAdsWatchedToday }
 */
function getCurrentCounters(userDoc) {
  if (!userDoc.exists) {
    return {
      aiNanoUsedToday: 0,
      aiMiniUsedToday: 0,
      rewardedAdsWatchedToday: 0,
    };
  }

  const data = userDoc.data();
  return {
    aiNanoUsedToday: data.aiNanoUsedToday || 0,
    aiMiniUsedToday: data.aiMiniUsedToday || 0,
    rewardedAdsWatchedToday: data.rewardedAdsWatchedToday || 0,
  };
}

/**
 * Reset all daily counters to 0
 * Called by daily scheduler at 12:00 AM GMT+5
 * @param {DocumentReference} userRef - Firestore user document reference
 * @return {Promise<void>}
 */
async function resetDailyCounters(userRef) {
  // Set dailyResetAt to 24 hours from NOW (the NEXT reset time)
  const nextReset = new Date(Date.now() + 24 * 60 * 60 * 1000);

  await userRef.update({
    aiNanoUsedToday: 0,
    aiMiniUsedToday: 0,
    rewardedAdsWatchedToday: 0,
    dailyResetAt: nextReset,
  });
}

/**
 * Get total AI generations for non-PRO user today
 * @param {object} counters - Counter object from getCurrentCounters()
 * @return {number} - Total AI generations
 */
function getTotalAiGenerationsToday(counters) {
  return (counters.aiNanoUsedToday || 0) + (counters.aiMiniUsedToday || 0);
}

/**
 * Check if counter needs reset (based on server time)
 * Prevents client-based date-change exploits
 * @param {Timestamp} lastResetAt - Firestore timestamp from user doc
 * @return {boolean} - true if 24+ hours have passed
 */
function needsReset(lastResetAt) {
  if (!lastResetAt) return true; // First time setup

  const now = new Date();
  const lastReset = lastResetAt.toDate ? lastResetAt.toDate() : lastResetAt;
  const hoursPassed = (now - lastReset) / (1000 * 60 * 60);

  return hoursPassed >= 24;
}

module.exports = {
  incrementAiNano,
  incrementAiMini,
  incrementRewardedAds,
  getCurrentCounters,
  resetDailyCounters,
  getTotalAiGenerationsToday,
  needsReset,
};
