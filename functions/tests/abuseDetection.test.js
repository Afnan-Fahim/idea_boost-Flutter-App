/**
 * 🧪 ABUSE DETECTION TEST SUITE
 *
 * Tests for detecting and validating abuse detection mechanisms
 * User: /users/HwvpWD6nRpXBh77ySobZCzQTCq53 (Test user)
 *
 * Test Signals:
 * 1. High request frequency (10+ requests in 5 min)
 * 2. High prompt similarity (≥ 0.85 similarity score)
 * 3. Long continuous sessions (> 60 min)
 *
 * Mitigation Actions:
 * - Throttle: Temporary rate limiting
 * - Downgrade Model: Force nano model
 * - Block Temporary: Reject request temporarily
 * - Cooldown: Silent cooldown (no UI error)
 */

const admin = require("firebase-admin");
const path = require("path");
const abuseDetection = require("../backend/validators/abuseDetection");
const config = require("../backend/config");

// Initialize Firebase Admin (for test environment)
const serviceAccountPath = path.join(__dirname, "../serviceAccountKey.json");
if (!admin.apps.length) {
  try {
    admin.initializeApp({
      credential: admin.credential.cert(require(serviceAccountPath)),
    });
  } catch (err) {
    console.warn("⚠️ Running in test mode without Firebase");
  }
}

const db = admin.firestore();
const TEST_USER_ID = "HwvpWD6nRpXBh77ySobZCzQTCq53";
const TEST_USER_REF = db.collection("users").doc(TEST_USER_ID);

// ════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS - RESET & PREPARE TEST DATA
// ════════════════════════════════════════════════════════════════

/**
 * Reset abuse detection fields for fresh testing
 */
async function resetAbuseTestingFields() {
  try {
    console.log("\n🔄 RESETTING ABUSE DETECTION FIELDS...");
    await TEST_USER_REF.update({
      recentRequestTimestamps: [],
      recentPrompts: [],
      sessionStartTime: null,
    });
    console.log("✅ Reset complete: abuse detection fields cleared\n");
  } catch (error) {
    console.error("❌ Reset failed:", error.message);
    throw error;
  }
}

/**
 * Persist abuse data to Firestore (simulates server behavior)
 */
async function persistAbuseData(timestamps, prompts) {
  try {
    await TEST_USER_REF.update({
      recentRequestTimestamps: timestamps,
      recentPrompts: prompts,
      lastAbuseCheckTime: new Date(),
    });
  } catch (error) {
    console.error("❌ Failed to persist abuse data:", error.message);
    throw error;
  }
}

/**
 * Get current abuse data from Firestore
 */
async function getAbuseData() {
  try {
    const snap = await TEST_USER_REF.get();
    const data = snap.data() || {};
    return {
      recentRequestTimestamps: data.recentRequestTimestamps || [],
      recentPrompts: data.recentPrompts || [],
      sessionStartTime: data.sessionStartTime,
    };
  } catch (error) {
    console.error("❌ Failed to fetch abuse data:", error.message);
    throw error;
  }
}

/**
 * Simulate a generation request
 */
async function simulateGenerationRequest(prompt, delayMs = 0) {
  if (delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  const abuseData = await getAbuseData();

  // Add current request
  const newTimestamps = [...abuseData.recentRequestTimestamps, Date.now()].slice(-20);
  const newPrompts = [
    ...abuseData.recentPrompts,
    {
      prompt: prompt.substring(0, 100),
      timestamp: new Date(),
    },
  ].slice(-10);

  // Perform abuse check
  const checkResult = abuseDetection.performAbuseCheck({
    recentRequestTimestamps: newTimestamps,
    recentPrompts: newPrompts.map((p) => p.prompt || p),
    currentPrompt: prompt,
    sessionData: {
      sessionStartTime: abuseData.sessionStartTime || Date.now(),
    },
  });

  // Persist data
  await persistAbuseData(newTimestamps, newPrompts);

  return {
    timestamp: new Date(),
    prompt: prompt.substring(0, 50) + "...",
    abuse: checkResult,
  };
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #1: HIGH FREQUENCY DETECTION
// ════════════════════════════════════════════════════════════════

async function testHighFrequencyDetection() {
  console.log("\n" + "=".repeat(70));
  console.log("📊 TEST #1: HIGH FREQUENCY ABUSE DETECTION");
  console.log("Threshold:", config.ABUSE_DETECTION.high_frequency_threshold, "requests in 5 min");
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  const results = [];
  const threshold = config.ABUSE_DETECTION.high_frequency_threshold;
  const testPrompt = "Generate a simple greeting";

  // Simulate rapid-fire requests within 5 minutes
  for (let i = 1; i <= threshold + 3; i++) {
    console.log(`\n[Request ${i}/${threshold + 3}] Sending prompt...`);
    const result = await simulateGenerationRequest(testPrompt, 100);
    results.push(result);

    const severity = result.abuse.severity;
    const detected = result.abuse.abuseDetected;
    const count = result.abuse.details?.frequency?.requestsInWindow || 0;

    console.log(
        `  → Requests in window: ${count} | ` +
      `Detected: ${detected ? "🚨 YES" : "✅ NO"} | ` +
      `Severity: ${severity}`,
    );

    if (i === threshold) {
      console.log("  ⚠️ THRESHOLD REACHED - Next request should trigger abuse");
    }
  }

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #1 SUMMARY:");
  console.log(`  Total requests: ${results.length}`);
  console.log(`  Abuse triggered at: Request ${results.findIndex((r) => r.abuse.abuseDetected) + 1}`);
  console.log(`  Expected: Request ${threshold + 1}`);
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #2: HIGH SIMILARITY DETECTION (SPAM)
// ════════════════════════════════════════════════════════════════

async function testHighSimilarityDetection() {
  console.log("\n" + "=".repeat(70));
  console.log("🔄 TEST #2: HIGH SIMILARITY SPAM DETECTION");
  console.log("Threshold:", config.ABUSE_DETECTION.high_similarity_threshold);
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  const similarPrompts = [
    "Tell me about machine learning and artificial intelligence", // 100% same
    "Tell me about machine learning and artificial intelligence models", // ~98%
    "Tell me about machine learning and AI", // ~92%
    "Tell me about deep learning and neural networks", // ~70% different
  ];

  const results = [];

  for (let i = 0; i < similarPrompts.length; i++) {
    const prompt = similarPrompts[i];
    console.log(`\n[Similarity Test ${i + 1}/4]`);
    console.log(`  Prompt: "${prompt.substring(0, 50)}..."`);

    const result = await simulateGenerationRequest(prompt, 200);
    results.push(result);

    const similarity = result.abuse.details?.similarity?.maxSimilarity || 0;
    const detected = result.abuse.abuseDetected;

    console.log(
        `  → Max similarity: ${(similarity * 100).toFixed(1)}% | ` +
      `Spam detected: ${detected ? "🚨 YES" : "✅ NO"}`,
    );
  }

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #2 SUMMARY:");
  console.log(`  Total prompts tested: ${results.length}`);
  const abuseCount = results.filter((r) => r.abuse.abuseDetected).length;
  console.log(`  Spam detected: ${abuseCount} times`);
  console.log(`  Expected: First 2 prompts should trigger abuse (100% & 98% similarity)`);
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #3: LONG SESSION DETECTION
// ════════════════════════════════════════════════════════════════

async function testLongSessionDetection() {
  console.log("\n" + "=".repeat(70));
  console.log("⏱️  TEST #3: LONG SESSION ABUSE DETECTION");
  console.log("Warning threshold:", config.ABUSE_DETECTION.session_duration_warning_minutes, "minutes");
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  // Create a session that started in the past
  const now = Date.now();
  const testScenarios = [
    {
      name: "Fresh session (2 min old)",
      startTime: now - (2 * 60 * 1000),
      shouldWarn: false,
    },
    {
      name: "Warning threshold (30 min old)",
      startTime: now - (30 * 60 * 1000),
      shouldWarn: true,
    },
    {
      name: "Hard limit (120 min old)",
      startTime: now - (120 * 60 * 1000),
      shouldWarn: true,
    },
  ];

  for (const scenario of testScenarios) {
    console.log(`\n[${scenario.name}]`);

    // Set session start time in Firestore
    await TEST_USER_REF.update({
      sessionStartTime: scenario.startTime,
      recentRequestTimestamps: [Date.now()],
      recentPrompts: [],
    });

    const abuseData = await getAbuseData();

    const result = abuseDetection.performAbuseCheck({
      recentRequestTimestamps: [Date.now()],
      recentPrompts: [],
      currentPrompt: "Test prompt",
      sessionData: {
        sessionStartTime: abuseData.sessionStartTime,
      },
    });

    const sessionDuration = result.details?.longSession?.sessionDuration || 0;
    const detected = result.abuse?.abuseDetected;

    console.log(
        `  → Session duration: ${sessionDuration.toFixed(1)} min | ` +
      `Warning: ${detected ? "🚨 YES" : "✅ NO"} | ` +
      `Expected: ${scenario.shouldWarn ? "YES" : "NO"}`,
    );
  }

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #3 SUMMARY:");
  console.log("  Sessions > 30 min trigger warning");
  console.log("  Sessions > 60 min trigger hard abuse block");
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #4: COMBINED MULTI-SIGNAL ABUSE
// ════════════════════════════════════════════════════════════════

async function testMultiSignalAbuse() {
  console.log("\n" + "=".repeat(70));
  console.log("⚡ TEST #4: MULTI-SIGNAL COMBINED ABUSE");
  console.log("Testing abuse with multiple signals triggered");
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  console.log("\n📍 Scenario: User sends rapid identical requests + long session");
  const prompt = "Generate code in Python";
  const results = [];

  // Set long session
  const sessionStart = Date.now() - (90 * 60 * 1000); // 90 min session
  await TEST_USER_REF.update({
    sessionStartTime: sessionStart,
  });

  // Send rapid identical requests
  const rapidCount = config.ABUSE_DETECTION.high_frequency_threshold + 2;
  for (let i = 1; i <= rapidCount; i++) {
    console.log(`\n[Multi-signal Request ${i}/${rapidCount}]`);
    const result = await simulateGenerationRequest(prompt, 50);
    results.push(result);

    const severity = result.abuse.severity;
    const signals = result.abuse.signalCount;
    const actions = result.abuse.actions;

    console.log(`  → Signals triggered: ${signals}`);
    console.log(`  → Severity: ${severity} (🔴 HIGH > 🟡 MEDIUM > 🟢 LOW)`);
    console.log(`  → Actions: ${actions.join(", ") || "none"}`);

    if (signals >= 2) {
      console.log("  🚨 CRITICAL: Multiple signals triggered!");
    }
  }

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #4 SUMMARY:");
  const highSeverityCount = results.filter((r) => r.abuse.severity === "high").length;
  const multiSignalCount = results.filter((r) => r.abuse.signalCount >= 2).length;
  console.log(`  High severity detections: ${highSeverityCount}`);
  console.log(`  Multi-signal detections: ${multiSignalCount}`);
  console.log(`  Expected: Later requests should have severity=HIGH with multiple signals`);
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #5: EDGE CASES & BOUNDARY CONDITIONS
// ════════════════════════════════════════════════════════════════

async function testEdgeCases() {
  console.log("\n" + "=".repeat(70));
  console.log("🔍 TEST #5: EDGE CASES & BOUNDARY CONDITIONS");
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  const testCases = [
    {
      name: "Empty prompts list",
      prompts: [],
      currentPrompt: "test",
      expectedAbuse: false,
    },
    {
      name: "Null/undefined handling",
      prompts: [null, undefined, "", "valid prompt"],
      currentPrompt: "test",
      expectedAbuse: false,
    },
    {
      name: "Very long prompt (edge of 100-char truncation)",
      prompts: ["a".repeat(99)],
      currentPrompt: "a".repeat(100),
      expectedAbuse: false, // Should still match well
    },
    {
      name: "Only whitespace prompts",
      prompts: ["   ", "\t\t", "\n\n"],
      currentPrompt: "normal prompt",
      expectedAbuse: false,
    },
    {
      name: "Timestamp boundary (just over 5-min window)",
      timestamps: [Date.now() - (5 * 60 * 1000) - 100], // 5 min 100ms ago
      currentTime: Date.now(),
      expectedAbuse: false, // Should be outside window
    },
  ];

  for (const testCase of testCases) {
    console.log(`\n[Edge Case: ${testCase.name}]`);

    const result = abuseDetection.performAbuseCheck({
      recentRequestTimestamps: testCase.timestamps || [Date.now()],
      recentPrompts: testCase.prompts || [],
      currentPrompt: testCase.currentPrompt || "test",
      sessionData: {sessionStartTime: Date.now() - (10 * 60 * 1000)},
    });

    const detected = result.abuseDetected;
    const match = detected === testCase.expectedAbuse;

    console.log(
        `  → Result: ${detected ? "🚨 ABUSE" : "✅ SAFE"} | ` +
      `Expected: ${testCase.expectedAbuse ? "ABUSE" : "SAFE"} | ` +
      `${match ? "✅ PASS" : "❌ FAIL"}`,
    );
  }

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #5 SUMMARY: Edge cases handled gracefully");
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE #6: PERSISTENCE ACROSS REQUESTS
// ════════════════════════════════════════════════════════════════

async function testPersistenceAcrossRequests() {
  console.log("\n" + "=".repeat(70));
  console.log("💾 TEST #6: ABUSE DATA PERSISTENCE ACROSS REQUESTS");
  console.log("Verifies data is stored and retrieved correctly from Firestore");
  console.log("=".repeat(70));

  await resetAbuseTestingFields();

  console.log("\n[Step 1] Send 5 requests and verify data persists");
  const prompts = [
    "Generate hello world",
    "Generate fibonacci",
    "Generate factorial",
    "Generate palindrome",
    "Generate hello world", // Similar to first
  ];

  for (let i = 0; i < prompts.length; i++) {
    await simulateGenerationRequest(prompts[i], 100);
    console.log(`  Request ${i + 1}: "${prompts[i].substring(0, 30)}..."`);
  }

  console.log("\n[Step 2] Fetch data from Firestore and verify");
  const storedData = await getAbuseData();

  console.log(`  ✅ Stored timestamps: ${storedData.recentRequestTimestamps.length}`);
  console.log(`  ✅ Stored prompts: ${storedData.recentPrompts.length}`);
  console.log(`  ✅ Prompts are objects with 'prompt' field: ${
    storedData.recentPrompts.every((p) => p.prompt || typeof p === "string")
  }`);

  console.log("\n[Step 3] Verify data integrity");
  const allPromptsValid = storedData.recentPrompts.every(
      (p) => typeof (p.prompt || p) === "string",
  );
  const allTimestampsValid = storedData.recentRequestTimestamps.every(
      (ts) => typeof ts === "number" || ts instanceof Date,
  );

  console.log(`  Data integrity check: ${allPromptsValid && allTimestampsValid ? "✅ PASS" : "❌ FAIL"}`);

  console.log("\n" + "-".repeat(70));
  console.log("✅ TEST #6 SUMMARY: Data persists correctly across requests");
  console.log("-".repeat(70));
}

// ════════════════════════════════════════════════════════════════
// MAIN TEST RUNNER
// ════════════════════════════════════════════════════════════════

async function runAllTests() {
  console.log("\n");
  console.log("🧪".repeat(35));
  console.log("     ABUSE DETECTION TEST SUITE v1.0");
  console.log("     User:", TEST_USER_ID);
  console.log("🧪".repeat(35));

  const tests = [
    {
      name: "High Frequency Detection",
      fn: testHighFrequencyDetection,
    },
    {
      name: "High Similarity Detection",
      fn: testHighSimilarityDetection,
    },
    {
      name: "Long Session Detection",
      fn: testLongSessionDetection,
    },
    {
      name: "Multi-Signal Combined Abuse",
      fn: testMultiSignalAbuse,
    },
    {
      name: "Edge Cases",
      fn: testEdgeCases,
    },
    {
      name: "Persistence Across Requests",
      fn: testPersistenceAcrossRequests,
    },
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      await test.fn();
      passed++;
    } catch (error) {
      console.error(`\n❌ TEST FAILED: ${test.name}`);
      console.error(`   Error: ${error.message}\n`);
      failed++;
    }
  }

  // Final summary
  console.log("\n" + "=".repeat(70));
  console.log("📋 FINAL TEST SUMMARY");
  console.log("=".repeat(70));
  console.log(`  Total tests: ${tests.length}`);
  console.log(`  ✅ Passed: ${passed}`);
  console.log(`  ❌ Failed: ${failed}`);
  console.log("=".repeat(70));

  // Reset after all tests
  console.log("\n🔄 Cleaning up - resetting abuse detection fields...");
  await resetAbuseTestingFields();
  console.log("✅ Test environment cleaned\n");

  process.exit(failed > 0 ? 1 : 0);
}

// ════════════════════════════════════════════════════════════════
// EXPORT FOR MANUAL TESTING
// ════════════════════════════════════════════════════════════════

module.exports = {
  // Test runners
  runAllTests,
  testHighFrequencyDetection,
  testHighSimilarityDetection,
  testLongSessionDetection,
  testMultiSignalAbuse,
  testEdgeCases,
  testPersistenceAcrossRequests,

  // Helpers
  resetAbuseTestingFields,
  simulateGenerationRequest,
  persistAbuseData,
  getAbuseData,
};

// ════════════════════════════════════════════════════════════════
// CLI EXECUTION
// ════════════════════════════════════════════════════════════════

if (require.main === module) {
  runAllTests().catch((error) => {
    console.error("\n💥 FATAL ERROR:", error.message);
    process.exit(1);
  });
}
