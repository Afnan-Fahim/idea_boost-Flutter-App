/**
 * Manual Script: Fix Region Tier for Existing Users
 * Run this script to update regionTier for users who don't have it set
 *
 * Usage: node fixRegionTier.js
 */

const admin = require("firebase-admin");
const regionTierResolver = require("./backend/common/regionTier");

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function fixUserRegionTier(userId) {
  try {
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found`);
      return false;
    }

    const userData = userDoc.data();

    // Check if regionTier is already set
    if (userData.regionTier && userData.regionTier !== "") {
      console.log(`✅ User ${userId} already has regionTier: ${userData.regionTier}`);
      return true;
    }

    // Resolve tier from region data
    const resolvedTier = regionTierResolver.resolveRegionTier({
      storeCountry: userData.storeCountry,
      deviceLocale: userData.deviceLocale,
      ipCountry: userData.ipCountry,
    });

    console.log(
        `🌍 Resolved tier for user ${userId}: ${resolvedTier}\n` +
        `   Store: ${userData.storeCountry || "N/A"}, ` +
        `Device: ${userData.deviceLocale || "N/A"}, ` +
        `IP: ${userData.ipCountry || "N/A"}`,
    );

    // Update user document
    await userRef.update({
      regionTier: resolvedTier,
      regionTierResolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ Region tier updated for user ${userId}: ${resolvedTier}\n`);
    return true;
  } catch (error) {
    console.error(`❌ Error fixing user ${userId}:`, error.message);
    return false;
  }
}

async function fixAllUsers() {
  try {
    console.log("🔍 Searching for users without regionTier...\n");

    const usersSnapshot = await db.collection("users").get();
    let fixedCount = 0;
    let alreadySetCount = 0;
    let errorCount = 0;

    for (const doc of usersSnapshot.docs) {
      const userData = doc.data();

      if (!userData.regionTier || userData.regionTier === "") {
        const success = await fixUserRegionTier(doc.id);
        if (success) {
          fixedCount++;
        } else {
          errorCount++;
        }
      } else {
        alreadySetCount++;
      }
    }

    console.log("\n📊 Summary:");
    console.log(`   Total users: ${usersSnapshot.size}`);
    console.log(`   Already set: ${alreadySetCount}`);
    console.log(`   Fixed: ${fixedCount}`);
    console.log(`   Errors: ${errorCount}`);
  } catch (error) {
    console.error("❌ Error scanning users:", error);
  } finally {
    process.exit(0);
  }
}

// Run the script
console.log("🚀 Starting region tier fix script...\n");

// Check if userId is provided as argument
const userId = process.argv[2];

if (userId) {
  console.log(`Fixing single user: ${userId}\n`);
  fixUserRegionTier(userId).then(() => process.exit(0));
} else {
  console.log("Fixing all users without regionTier...\n");
  fixAllUsers();
}
