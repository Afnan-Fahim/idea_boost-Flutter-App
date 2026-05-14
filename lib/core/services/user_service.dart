// lib/core/services/user_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:ideaboost/data/models/comments_model.dart';
import 'package:ideaboost/data/models/user_model.dart';
import 'package:ideaboost/core/services/region_service.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RegionService _regionService = RegionService();

  String? get currentUserId => _auth.currentUser?.uid;

  // Check if user document exists in Firestore
  Future<bool> userDocumentExists(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      debugPrint('Error checking user document: $e');
      return false;
    }
  }

  // Create user with correct daily reset fields
  // ⚠️ NOTE: Do NOT assign any avatar (photoUrl) on user creation.
  // Avatar should only be set when user explicitly uploads one.
  // 🔒 NEW: Uses server timestamp for secure daily limit resets
  // 🌍 NEW: Collects region data for ANTI-VPN tier resolution
  // 🌍 NEW: Captures device language on signup
  Future<void> createNewUser(
    String uid,
    String email, {
    String? deviceLanguage,
  }) async {
    debugPrint('🚨🚨🚨 createNewUser CALLED for $uid');
    // Collect region data for tier resolution
    var regionData = await _regionService.collectRegionData();
    debugPrint('🚨 REAL region data: ${regionData.toString()}');

    // ═══════════════════════════════════════════════════════════════════════
    // 🧪 TESTING: Uncomment ONE of these sets to test tier behavior
    // Backend takes LOWEST tier: max(tier1=0, tier2=1, tier3=2)
    // ═══════════════════════════════════════════════════════════════════════

    // 🧪 TEST SET 1: HARDCODE USER AS TIER1 (all TIER1 countries)
    // var df = regionData['deviceFingerprint'];
    // regionData = {
    //   'deviceLocale': 'US', // TIER1
    //   'storeCountry': 'US', // TIER1
    //   'ipCountry': 'US', // TIER1
    //   'deviceFingerprint': df,
    // };
    // debugPrint('🧪 TEST: Tier1 user (US + US + US)');

    // 🧪 TEST SET 2: HARDCODE USER AS TIER2 (mismatch with TIER2 as lowest)
    // var df = regionData['deviceFingerprint'];
    // regionData = {
    //   'deviceLocale': 'US', // TIER1
    //   'storeCountry': 'TR', // TIER2 ← lowest, resolves to tier2
    //   'ipCountry': 'US', // TIER1
    //   'deviceFingerprint': df,
    // };
    // debugPrint('🧪 TEST: Tier2 user (US + TR + US = tier2)');

    // 🧪 TEST SET 3: HARDCODE USER AS TIER3 (all TIER3 countries)
    // regionData = {
    //   'deviceLocale': 'IN',  // TIER3
    //   'storeCountry': 'IN',  // TIER3
    //   'ipCountry': 'IN',     // TIER3
    //   'deviceFingerprint': 'test-tier3-device-${DateTime.now().millisecondsSinceEpoch}',
    // };
    // debugPrint('🧪 TEST: Tier3 user (IN + IN + IN)');

    final defaultUser = UserModel(
      id: uid,
      email: email,
      name: 'User',
      plan: 'free',
      language: deviceLanguage ?? 'en',
      dailyLimit: 3,
      photoUrl: null, // ✅ Explicitly null - no default avatar
    );

    // Create user document with region data
    final userMap = defaultUser.toMap();

    // Add region data for backend tier resolution (ANTI-VPN per spec 1.1)
    userMap['deviceLocale'] = regionData['deviceLocale'] ?? 'unknown';
    userMap['storeCountry'] = regionData['storeCountry'] ?? 'unknown';
    userMap['ipCountry'] = regionData['ipCountry'] ?? 'unknown';
    userMap['trialKey'] =
        regionData['deviceFingerprint'] ?? DateTime.now().toString();

    // DEBUG: Verify what's being sent to Firebase
    debugPrint(
      '📤 SENDING TO FIREBASE: Store=${userMap['storeCountry']}, Device=${userMap['deviceLocale']}, IP=${userMap['ipCountry']}, Language=${userMap['language']}',
    );

    // ⚠️ IMPORTANT: Remove regionTier from client-side creation
    // Backend will calculate it based on deviceLocale/storeCountry/ipCountry
    userMap.remove('regionTier');

    await _db
        .collection('users')
        .doc(uid)
        .set(userMap, SetOptions(merge: true));

    debugPrint(
      '✅ User created with region data for tier resolution and language: ${userMap['language']}',
    );
  }

  // Save to favorites
  Future<void> saveToFavorites(CommentOutput output) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("User not logged in");

    final favoritesRef = _db
        .collection('favorites')
        .doc(uid)
        .collection('items');
    await favoritesRef.add({
      'title': output.inputText.length > 50
          ? "${output.inputText.substring(0, 50)}..."
          : output.inputText,
      'type': 'comment_set',
      'content': output.toJson(),
      'generatedAt': output.generatedAt,
      'savedAt': FieldValue.serverTimestamp(),
      'originalInput': output.inputText,
    });
  }

  // Save a structured history entry (generic for all generator types)
  Future<void> saveMapToHistory({
    required String type,
    required String prompt,
    required Map<String, dynamic> output,
    Map<String, dynamic>? meta,
    DateTime? generatedAt,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final historyRef = _db.collection('history').doc(uid).collection('logs');
    final data = {
      'type': type,
      'prompt': prompt,
      'output': output,
      'meta': meta ?? {},
      'generatedAt': generatedAt != null
          ? Timestamp.fromDate(generatedAt)
          : FieldValue.serverTimestamp(),
    };
    await historyRef.add(data);
  }

  // Get user data
  Future<UserModel?> getUserData() async {
    final uid = currentUserId;
    if (uid == null) return null;

    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;

    return UserModel.fromFirestore(doc);
  }

  // Grant +1 from rewarded ad
  // Get recent history items
  Future<List<Map<String, dynamic>>> getRecentHistory({int limit = 6}) async {
    final uid = currentUserId;
    if (uid == null) return [];

    try {
      final snapshot = await _db
          .collection('history')
          .doc(uid)
          .collection('logs')
          .orderBy('generatedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'type': data['type'] ?? '',
          'prompt': data['prompt'] ?? '',
          'output': data['output'] ?? {},
          'meta': data['meta'] ?? {},
          'outputSummary': data['outputSummary'] ?? '',
          'generatedAt': data['generatedAt'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Delete all user data from Firestore (used on account deletion).
  /// Deletes subcollection documents first, then the parent documents.
  Future<void> deleteAllUserData(String uid) async {
    try {
      debugPrint('🗑️  Starting comprehensive user data deletion for $uid...');

      final batch = _db.batch();
      int deletedCount = 0;

      // ═══════════════════════════════════════════════════════════════════════
      // 🔴 LEVEL 1: TOP-LEVEL COLLECTIONS
      // ═══════════════════════════════════════════════════════════════════════

      // 1️⃣ Delete history/{uid}/logs/{logId}
      debugPrint('📋 Deleting history/{uid}/logs...');
      try {
        final historyLogs = await _db
            .collection('history')
            .doc(uid)
            .collection('logs')
            .get();
        debugPrint('   Found ${historyLogs.docs.length} history logs');
        for (final doc in historyLogs.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading history logs: $e');
      }

      // 2️⃣ Delete history/{uid} parent doc
      debugPrint('📋 Deleting history/{uid}...');
      batch.delete(_db.collection('history').doc(uid));
      deletedCount++;

      // 3️⃣ Delete favorites/{uid}/items/{itemId} (old flat structure)
      debugPrint('⭐ Deleting favorites/{uid}/items...');
      try {
        final favItemsFlat = await _db
            .collection('favorites')
            .doc(uid)
            .collection('items')
            .get();
        debugPrint(
          '   Found ${favItemsFlat.docs.length} favorite items (flat)',
        );
        for (final doc in favItemsFlat.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading flat favorites: $e');
      }

      // 4️⃣ Delete favorites/{uid}/types/{type}/items/{itemId} (new typed structure)
      debugPrint('⭐ Deleting favorites/{uid}/types/{type}/items...');
      try {
        final favTypes = await _db
            .collection('favorites')
            .doc(uid)
            .collection('types')
            .get();
        debugPrint('   Found ${favTypes.docs.length} favorite types');
        for (final typeDoc in favTypes.docs) {
          final items = await _db
              .collection('favorites')
              .doc(uid)
              .collection('types')
              .doc(typeDoc.id)
              .collection('items')
              .get();
          debugPrint('   Type ${typeDoc.id} has ${items.docs.length} items');
          for (final item in items.docs) {
            batch.delete(item.reference);
            deletedCount++;
          }
          batch.delete(typeDoc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading typed favorites: $e');
      }

      // 5️⃣ Delete favorites/{uid} parent doc
      debugPrint('⭐ Deleting favorites/{uid}...');
      batch.delete(_db.collection('favorites').doc(uid));
      deletedCount++;

      // ═══════════════════════════════════════════════════════════════════════
      // 🔴 LEVEL 2: NESTED SUBCOLLECTIONS UNDER users/{uid}
      // ═══════════════════════════════════════════════════════════════════════

      // 6️⃣ Delete users/{uid}/history/{historyId}
      debugPrint('📋 Deleting users/{uid}/history subcollection...');
      try {
        final userHistory = await _db
            .collection('users')
            .doc(uid)
            .collection('history')
            .get();
        debugPrint('   Found ${userHistory.docs.length} user history docs');
        for (final doc in userHistory.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading users/{uid}/history: $e');
      }

      // 7️⃣ Delete users/{uid}/favorites/{favoriteId}
      debugPrint('⭐ Deleting users/{uid}/favorites subcollection...');
      try {
        final userFavorites = await _db
            .collection('users')
            .doc(uid)
            .collection('favorites')
            .get();
        debugPrint('   Found ${userFavorites.docs.length} user favorite docs');
        for (final doc in userFavorites.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading users/{uid}/favorites: $e');
      }

      // 8️⃣ Delete users/{uid}/rewardTokens
      debugPrint('🎁 Deleting users/{uid}/rewardTokens subcollection...');
      try {
        final rewardTokens = await _db
            .collection('users')
            .doc(uid)
            .collection('rewardTokens')
            .get();
        debugPrint('   Found ${rewardTokens.docs.length} reward token docs');
        for (final doc in rewardTokens.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading users/{uid}/rewardTokens: $e');
      }

      // 9️⃣ Delete users/{uid}/activeRewardTokens
      debugPrint('🎁 Deleting users/{uid}/activeRewardTokens subcollection...');
      try {
        final activeRewardTokens = await _db
            .collection('users')
            .doc(uid)
            .collection('activeRewardTokens')
            .get();
        debugPrint(
          '   Found ${activeRewardTokens.docs.length} active reward token docs',
        );
        for (final doc in activeRewardTokens.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading users/{uid}/activeRewardTokens: $e');
      }

      // 🔟 Delete users/{uid}/trialKeys
      debugPrint('🔑 Deleting users/{uid}/trialKeys subcollection...');
      try {
        final trialKeys = await _db
            .collection('users')
            .doc(uid)
            .collection('trialKeys')
            .get();
        debugPrint('   Found ${trialKeys.docs.length} trial key docs');
        for (final doc in trialKeys.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('   Error reading users/{uid}/trialKeys: $e');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // 🔴 FINAL: Delete users/{uid} parent document
      // ═══════════════════════════════════════════════════════════════════════
      debugPrint('👤 Deleting users/{uid} parent document...');
      batch.delete(_db.collection('users').doc(uid));
      deletedCount++;

      // ✅ Commit all deletions in one atomic transaction
      debugPrint('💾 Committing batch deletion ($deletedCount items)...');
      await batch.commit();

      debugPrint(
        '✅✅✅ ALL user data deleted successfully! Deleted $deletedCount items total.',
      );
    } catch (e) {
      debugPrint('❌❌❌ Error deleting user data for $uid: $e');
      rethrow;
    }
  }
}
