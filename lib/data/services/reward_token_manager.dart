import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service for managing reward token lifecycle
/// Handles: retrieval, validation, consumption
class RewardTokenManager {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Retrieve first unconsumed token from user's activeRewardTokens map
  /// Returns token ID or null if none available
  Future<String?> getFirstUnconsumedToken(String userId) async {
    try {
      debugPrint('🔍 RewardTokenManager: Fetching token for user: $userId');

      final userDoc = await _db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        debugPrint('❌ User document not found');
        return null;
      }

      final userData = userDoc.data();
      if (userData == null) {
        debugPrint('❌ User data is null');
        return null;
      }

      // Get activeRewardTokens from the map field (NOT a subcollection!)
      final activeRewardTokensMap =
          userData['activeRewardTokens'] as Map<String, dynamic>?;

      if (activeRewardTokensMap == null) {
        debugPrint('⚠️ activeRewardTokens field is null or missing');
        return null;
      }

      debugPrint('✅ Found ${activeRewardTokensMap.length} tokens in map');

      // Find first unconsumed token
      debugPrint('🔎 Looking for unconsumed tokens...');
      for (var entry in activeRewardTokensMap.entries) {
        final tokenId = entry.key;
        final tokenData = entry.value as Map<String, dynamic>?;
        if (tokenData == null) continue;

        final consumed = tokenData['consumed'] as bool? ?? false;

        if (!consumed) {
          debugPrint('✅ Found unconsumed token: $tokenId');
          return tokenId;
        }
      }

      debugPrint('⚠️ No unconsumed tokens found');
      return null;
    } catch (e) {
      debugPrint('❌ Error retrieving token: $e');
      rethrow;
    }
  }

  /// Mark reward token as consumed
  Future<void> markTokenAsConsumed(String userId, String tokenId) async {
    try {
      debugPrint('📝 Marking token as consumed: $tokenId');

      // Update the token in the map field using dot notation
      await _db.collection('users').doc(userId).update({
        'activeRewardTokens.$tokenId.consumed': true,
        'activeRewardTokens.$tokenId.consumedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Token $tokenId marked as consumed');
    } catch (e) {
      debugPrint('❌ Error marking token as consumed: $e');
      rethrow;
    }
  }

  /// Get current user ID
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }
}
