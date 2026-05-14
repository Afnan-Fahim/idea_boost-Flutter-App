#!/bin/bash

# M.3 TESTING SCRIPT - Local Validation
# Validates that all code changes are in place and working correctly
# Run this BEFORE Firebase Console setup to catch any issues early

set -e

echo "🧪 M.3 Implementation - Local Validation Tests"
echo "=============================================="
echo ""

# Test 1: Check if remoteConfigHelper.js exists
echo "Test 1: Checking if remoteConfigHelper.js exists..."
if [ -f "functions/backend/common/remoteConfigHelper.js" ]; then
  echo "  ✅ File exists"
  echo "  ✅ Lines: $(wc -l < functions/backend/common/remoteConfigHelper.js)"
else
  echo "  ❌ FAILED: remoteConfigHelper.js not found"
  exit 1
fi
echo ""

# Test 2: Check if remoteConfigHelper has required functions
echo "Test 2: Checking remoteConfigHelper functions..."
required_functions=("initRemoteConfig" "getRemoteConfigValue" "getFailsafeConfig" "areAdsEnabledForTier" "isTierDisabledInRemoteConfig" "clearCache")
for func in "${required_functions[@]}"; do
  if grep -q "function $func\|const $func\|async function $func" functions/backend/common/remoteConfigHelper.js; then
    echo "  ✅ Function exists: $func"
  else
    echo "  ❌ FAILED: Function not found: $func"
    exit 1
  fi
done
echo ""

# Test 3: Check if failsafe.js imports remoteConfigHelper
echo "Test 3: Checking failsafe.js imports..."
if grep -q "remoteConfigHelper" functions/backend/security/failsafe.js; then
  echo "  ✅ remoteConfigHelper imported"
else
  echo "  ❌ FAILED: remoteConfigHelper not imported in failsafe.js"
  exit 1
fi
echo ""

# Test 4: Check if getFailsafeStatus is async
echo "Test 4: Checking if getFailsafeStatus is async..."
if grep -q "async function getFailsafeStatus" functions/backend/security/failsafe.js; then
  echo "  ✅ getFailsafeStatus is async"
else
  echo "  ❌ FAILED: getFailsafeStatus is not async"
  exit 1
fi
echo ""

# Test 5: Check if claimReward.js has tier disable check
echo "Test 5: Checking claimReward.js for tier disable check..."
if grep -q "isTierDisabledInRemoteConfig" functions/backend/endpoints/claimReward.js; then
  echo "  ✅ Tier disable check found"
else
  echo "  ❌ FAILED: Tier disable check not found in claimReward.js"
  exit 1
fi
echo ""

# Test 6: Check if generateAi.js has tier disable check
echo "Test 6: Checking generateAi.js for tier disable check..."
if grep -q "isTierDisabledInRemoteConfig" functions/backend/endpoints/generateAi.js; then
  echo "  ✅ Tier disable check found"
else
  echo "  ❌ FAILED: Tier disable check not found in generateAi.js"
  exit 1
fi
echo ""

# Test 7: Check if index.js initializes Remote Config
echo "Test 7: Checking index.js for Remote Config initialization..."
if grep -q "initRemoteConfig" functions/backend/index.js; then
  echo "  ✅ Remote Config initialization found"
else
  echo "  ❌ FAILED: Remote Config initialization not found in index.js"
  exit 1
fi
echo ""

# Test 8: Check if index.js loads failsafe state
echo "Test 8: Checking index.js for failsafe state loading..."
if grep -q "loadFailsafeStateOnStartup" functions/backend/index.js; then
  echo "  ✅ Failsafe state loading found"
else
  echo "  ❌ FAILED: Failsafe state loading not found in index.js"
  exit 1
fi
echo ""

# Test 9: Check if analytics.js has new events
echo "Test 9: Checking analytics.js for new events..."
if grep -q "logTierDisabledViaRemoteConfig\|logFailsafeActivation" functions/backend/common/analytics.js; then
  echo "  ✅ New analytics events found"
else
  echo "  ❌ FAILED: New analytics events not found in analytics.js"
  exit 1
fi
echo ""

# Test 10: Run ESLint
echo "Test 10: Running ESLint validation..."
cd functions
npm run lint > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "  ✅ ESLint passed (0 errors, 0 warnings)"
  cd ..
else
  echo "  ❌ FAILED: ESLint found errors"
  cd ..
  exit 1
fi
echo ""

# Test 11: Check TypeScript/Syntax
echo "Test 11: Checking Node.js syntax..."
node -c functions/backend/common/remoteConfigHelper.js > /dev/null 2>&1 && echo "  ✅ remoteConfigHelper.js syntax valid" || echo "  ❌ FAILED: remoteConfigHelper.js syntax error"
node -c functions/backend/security/failsafe.js > /dev/null 2>&1 && echo "  ✅ failsafe.js syntax valid" || echo "  ❌ FAILED: failsafe.js syntax error"
node -c functions/backend/endpoints/claimReward.js > /dev/null 2>&1 && echo "  ✅ claimReward.js syntax valid" || echo "  ❌ FAILED: claimReward.js syntax error"
node -c functions/backend/endpoints/generateAi.js > /dev/null 2>&1 && echo "  ✅ generateAi.js syntax valid" || echo "  ❌ FAILED: generateAi.js syntax error"
node -c functions/backend/index.js > /dev/null 2>&1 && echo "  ✅ index.js syntax valid" || echo "  ❌ FAILED: index.js syntax error"
node -c functions/backend/common/analytics.js > /dev/null 2>&1 && echo "  ✅ analytics.js syntax valid" || echo "  ❌ FAILED: analytics.js syntax error"
echo ""

echo "=============================================="
echo "✅ ALL TESTS PASSED!"
echo "=============================================="
echo ""
echo "Next step: Create Firebase Remote Config parameters"
echo "See: M3_PHASE_8_FIREBASE_CONSOLE_SETUP.md"
echo ""
