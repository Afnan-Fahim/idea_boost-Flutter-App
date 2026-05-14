/**
 * Test Script: Region Tier Anti-VPN Detection
 * Tests various country mismatch scenarios to verify anti-VPN logic
 */

const regionTier = require("./common/regionTier");

// Color codes for terminal output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

/**
 * Test a scenario and display results
 */
function testScenario(description, userData, expectedTier, shouldDetectMismatch) {
  console.log(`\n${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`);
  console.log(`${colors.bright}Test: ${description}${colors.reset}`);
  console.log(`${colors.blue}Input:${colors.reset}`);
  console.log(`  Store Country: ${userData.storeCountry || "N/A"}`);
  console.log(`  Device Locale: ${userData.deviceLocale || "N/A"}`);
  console.log(`  IP Country: ${userData.ipCountry || "N/A"}`);

  const result = regionTier.resolveRegionTier(userData);
  const storeRank = regionTier.getTierRank(userData.storeCountry);
  const deviceRank = regionTier.getTierRank(userData.deviceLocale);
  const ipRank = regionTier.getTierRank(userData.ipCountry);

  const hasMismatch = !(storeRank === deviceRank && deviceRank === ipRank);

  console.log(`\n${colors.yellow}Analysis:${colors.reset}`);
  console.log(`  Store Rank: ${storeRank} (${rankToTierName(storeRank)})`);
  console.log(`  Device Rank: ${deviceRank} (${rankToTierName(deviceRank)})`);
  console.log(`  IP Rank: ${ipRank} (${rankToTierName(ipRank)})`);
  console.log(`  Mismatch Detected: ${hasMismatch ? "🚨 YES" : "✅ NO"}`);

  console.log(`\n${colors.green}Result: ${result}${colors.reset}`);

  const passed = result === expectedTier && hasMismatch === shouldDetectMismatch;
  if (passed) {
    console.log(`${colors.green}✅ TEST PASSED${colors.reset}`);
  } else {
    console.log(`${colors.red}❌ TEST FAILED${colors.reset}`);
    console.log(`  Expected: ${expectedTier}, Got: ${result}`);
    console.log(`  Expected mismatch: ${shouldDetectMismatch}, Got: ${hasMismatch}`);
  }

  return passed;
}

function rankToTierName(rank) {
  return ["tier1", "tier2", "tier3"][rank] || "unknown";
}

// ════════════════════════════════════════════════════════════════
// TEST SUITE
// ════════════════════════════════════════════════════════════════

console.log(`${colors.bright}${colors.cyan}`);
console.log("╔═══════════════════════════════════════════════════════════════╗");
console.log("║     ANTI-VPN DETECTION TEST SUITE                            ║");
console.log("║     Testing Region Tier Mismatch Logic                       ║");
console.log("╚═══════════════════════════════════════════════════════════════╝");
console.log(colors.reset);

const results = [];

// ════════════════════════════════════════════════════════════════
// SCENARIO 1: No VPN - All Tier 1 Countries Match
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "Legitimate Tier 1 User - No VPN (USA)",
    {
      storeCountry: "US",
      deviceLocale: "US",
      ipCountry: "US",
    },
    "tier1",
    false, // No mismatch expected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 2: No VPN - All Tier 3 Countries Match
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "Legitimate Tier 3 User - No VPN (Pakistan)",
    {
      storeCountry: "PK",
      deviceLocale: "PK",
      ipCountry: "PK",
    },
    "tier3",
    false, // No mismatch expected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 3: VPN Detected - Pakistan User Using Canada VPN
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "🚨 VPN DETECTED - Pakistan User Connected to Canada VPN",
    {
      storeCountry: "PK",
      deviceLocale: "PK",
      ipCountry: "CA", // VPN showing Canada
    },
    "tier3", // Should downgrade to tier3 (lowest/most restrictive)
    true, // Mismatch should be detected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 4: VPN Detected - Tier 3 User Trying to Access Tier 1
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "🚨 VPN DETECTED - India User Using USA VPN",
    {
      storeCountry: "IN",
      deviceLocale: "IN",
      ipCountry: "US", // VPN showing USA
    },
    "tier3", // Should downgrade to tier3
    true, // Mismatch should be detected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 5: VPN Detected - Tier 1 User Using Tier 3 VPN
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "🚨 VPN DETECTED - USA User Using Pakistan VPN (Unusual)",
    {
      storeCountry: "US",
      deviceLocale: "US",
      ipCountry: "PK", // VPN showing Pakistan
    },
    "tier3", // Should downgrade to tier3 (lowest)
    true, // Mismatch should be detected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 6: Partial Mismatch - Device Locale Changed
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "🚨 Mismatch - Store and IP Match, Device Changed",
    {
      storeCountry: "US",
      deviceLocale: "GB", // User changed device locale
      ipCountry: "US",
    },
    "tier1", // Should downgrade to tier1 (lowest of US and GB)
    true, // Mismatch should be detected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 7: All Different - Maximum Fraud Risk
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "🚨 HIGH RISK - All Three Countries Different",
    {
      storeCountry: "US", // Tier 1
      deviceLocale: "GB", // Tier 2
      ipCountry: "PK", // Tier 3
    },
    "tier3", // Should downgrade to tier3 (most restrictive)
    true, // Mismatch should be detected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 8: Tier 2 Countries Match
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "Legitimate Tier 2 User - No VPN (UK)",
    {
      storeCountry: "GB",
      deviceLocale: "GB",
      ipCountry: "GB",
    },
    "tier2",
    false, // No mismatch expected
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 9: Missing Data - Should Default to Tier 3
// ════════════════════════════════════════════════════════════════
results.push(testScenario(
    "Missing IP Data - Should Default to Tier 3",
    {
      storeCountry: "US",
      deviceLocale: "US",
      ipCountry: null,
    },
    "tier3", // Should default to tier3 when data missing
    true, // Mismatch detected (null vs US)
));

// ════════════════════════════════════════════════════════════════
// SCENARIO 10: Your Real Case - VPN with Pakistan Store
// ════════════════════════════════════════════════════════════════
console.log(`\n${colors.bright}${colors.yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`);
console.log(`${colors.bright}YOUR ACTUAL CASE:${colors.reset}`);
results.push(testScenario(
    "🚨 YOUR SCENARIO - If VPN was Detected as Canada",
    {
      storeCountry: "PK",
      deviceLocale: "PK",
      ipCountry: "CA", // What should happen if VPN detected correctly
    },
    "tier3",
    true,
));

// ════════════════════════════════════════════════════════════════
// RESULTS SUMMARY
// ════════════════════════════════════════════════════════════════

console.log(`\n${colors.bright}${colors.cyan}`);
console.log("╔═══════════════════════════════════════════════════════════════╗");
console.log("║     TEST RESULTS SUMMARY                                     ║");
console.log("╚═══════════════════════════════════════════════════════════════╝");
console.log(colors.reset);

const passed = results.filter((r) => r).length;
const total = results.length;
const passRate = ((passed / total) * 100).toFixed(1);

console.log(`\nTotal Tests: ${total}`);
console.log(`${colors.green}Passed: ${passed}${colors.reset}`);
console.log(`${colors.red}Failed: ${total - passed}${colors.reset}`);
console.log(`Pass Rate: ${passRate}%`);

if (passed === total) {
  console.log(`\n${colors.green}${colors.bright}✅ ALL TESTS PASSED - Anti-VPN Detection Working!${colors.reset}`);
} else {
  console.log(`\n${colors.red}${colors.bright}❌ SOME TESTS FAILED - Review Implementation${colors.reset}`);
}

console.log(`\n${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`);
console.log(`${colors.yellow}Note: Your logs showed all three as PK, which means:`);
console.log(`  1. VPN IP detection didn't show CA (Canada)`);
console.log(`  2. The IP geolocation service returned PK despite VPN`);
console.log(`  3. This indicates ipapi.co may have cached/failed to detect VPN${colors.reset}`);
console.log(`${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}\n`);

process.exit(passed === total ? 0 : 1);
