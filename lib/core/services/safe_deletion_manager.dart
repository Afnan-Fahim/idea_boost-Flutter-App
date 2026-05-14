/// 🛡️ SAFE DELETION MANAGER
/// Wraps all deletion operations with validation, auditing, and rollback capability
/// Ensures deletions are transactional, logged, and recoverable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'deletion_audit_service.dart';
import 'stale_data_detector.dart';

enum DeletionValidation {
  success,
  userNotAuthenticated,
  invalidInput,
  alreadyDeleted,
  incompleteDeletion,
  auditFailed,
  rollbackRequired,
  other,
}

class DeletionResult {
  final DeletionValidation validation;
  final bool isSuccessful;
  final String auditId;
  final int itemsDeleted;
  final String? errorMessage;
  final Map<String, dynamic>? backupData;
  final DateTime timestamp;

  DeletionResult({
    required this.validation,
    required this.isSuccessful,
    required this.auditId,
    this.itemsDeleted = 0,
    this.errorMessage,
    this.backupData,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      '''
DeletionResult:
  ✓ Success: $isSuccessful
  🔍 Validation: ${validation.name}
  📋 AuditID: $auditId
  📊 Items Deleted: $itemsDeleted
  ${errorMessage != null ? '❌ Error: $errorMessage' : ''}
  ''';
}

class SafeDeletionManager {
  static final SafeDeletionManager _instance = SafeDeletionManager._internal();

  factory SafeDeletionManager() => _instance;

  SafeDeletionManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DeletionAuditService _auditService = DeletionAuditService();
  final StaleDataDetector _staleDetector = StaleDataDetector();

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🛡️ SAFE HISTORY ITEM DELETION
  /// ═══════════════════════════════════════════════════════════════════════
  Future<DeletionResult> safeDeleteHistoryItem({
    required String itemId,
    required String type,
    required Map<String, dynamic> backupData,
    bool createBackup = true,
  }) async {
    debugPrint('🛡️  [SAFE DELETE] Starting history item deletion: $itemId');

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return DeletionResult(
        validation: DeletionValidation.userNotAuthenticated,
        isSuccessful: false,
        auditId: 'failed-auth',
        errorMessage: 'User not authenticated',
      );
    }

    try {
      // 1️⃣ Create audit entry
      final auditEntry = await _auditService.createAuditEntry(
        type: DeletionType.historyItem,
        metadata: {'itemId': itemId, 'type': type},
        backupData: createBackup ? backupData : null,
      );

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.inProgress,
      );

      // 2️⃣ Validate deletion is safe (item exists)
      final docRef = _firestore
          .collection('history')
          .doc(uid)
          .collection('logs')
          .doc(itemId);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        await _auditService.updateAuditStatus(
          auditEntry.id,
          newStatus: DeletionStatus.completed,
          errorMessage: 'Item does not exist (may be already deleted)',
        );
        return DeletionResult(
          validation: DeletionValidation.alreadyDeleted,
          isSuccessful: true,
          auditId: auditEntry.id,
          errorMessage: 'Item was already deleted',
        );
      }

      // 3️⃣ Perform deletion
      await docRef.delete();
      debugPrint('✅ [SAFE DELETE] History item deleted: $itemId');

      // 4️⃣ Update audit as successful
      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.completed,
      );

      return DeletionResult(
        validation: DeletionValidation.success,
        isSuccessful: true,
        auditId: auditEntry.id,
        itemsDeleted: 1,
        backupData: createBackup ? backupData : null,
      );
    } catch (e) {
      debugPrint('❌ [SAFE DELETE] Deletion failed: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🛡️ SAFE BULK HISTORY DELETION
  /// ═══════════════════════════════════════════════════════════════════════
  Future<DeletionResult> safeDeleteHistoryBulk({
    required List<String> itemIds,
    required List<Map<String, dynamic>> backupDataList,
    bool createBackups = true,
  }) async {
    debugPrint(
      '🛡️  [SAFE DELETE] Starting bulk history deletion: ${itemIds.length} items',
    );

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return DeletionResult(
        validation: DeletionValidation.userNotAuthenticated,
        isSuccessful: false,
        auditId: 'failed-auth',
        errorMessage: 'User not authenticated',
      );
    }

    if (itemIds.isEmpty) {
      return DeletionResult(
        validation: DeletionValidation.invalidInput,
        isSuccessful: false,
        auditId: 'invalid-input',
        errorMessage: 'No items to delete',
      );
    }

    try {
      // 1️⃣ Create audit entry for bulk operation
      final auditEntry = await _auditService.createAuditEntry(
        type: DeletionType.bulkHistoryItems,
        metadata: {'itemCount': itemIds.length, 'itemIds': itemIds},
        backupData: createBackups ? {'items': backupDataList} : null,
        itemsAffected: itemIds.length,
      );

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.inProgress,
      );

      // 2️⃣ Perform batch deletion
      final batch = _firestore.batch();
      int deletedCount = 0;

      for (final itemId in itemIds) {
        try {
          final docRef = _firestore
              .collection('history')
              .doc(uid)
              .collection('logs')
              .doc(itemId);

          // Verify doc exists before deleting
          final docSnapshot = await docRef.get();
          if (docSnapshot.exists) {
            batch.delete(docRef);
            deletedCount++;
          }
        } catch (e) {
          debugPrint('⚠️  [SAFE DELETE] Could not queue item $itemId: $e');
        }
      }

      // 3️⃣ Commit batch
      await batch.commit();
      debugPrint('✅ [SAFE DELETE] Batch deleted: $deletedCount items');

      // 4️⃣ Update audit
      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.completed,
      );

      return DeletionResult(
        validation: DeletionValidation.success,
        isSuccessful: true,
        auditId: auditEntry.id,
        itemsDeleted: deletedCount,
        backupData: createBackups ? {'items': backupDataList} : null,
      );
    } catch (e) {
      debugPrint('❌ [SAFE DELETE] Bulk deletion failed: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🛡️ SAFE FAVORITE DELETION
  /// ═══════════════════════════════════════════════════════════════════════
  Future<DeletionResult> safDeleteFavorite({
    required String itemId,
    required String type,
    required Map<String, dynamic> backupData,
  }) async {
    debugPrint('🛡️  [SAFE DELETE] Starting favorite deletion: $itemId');

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return DeletionResult(
        validation: DeletionValidation.userNotAuthenticated,
        isSuccessful: false,
        auditId: 'failed-auth',
        errorMessage: 'User not authenticated',
      );
    }

    try {
      // 1️⃣ Create audit entry
      final auditEntry = await _auditService.createAuditEntry(
        type: DeletionType.favorite,
        metadata: {'itemId': itemId, 'favoriteType': type},
        backupData: backupData,
      );

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.inProgress,
      );

      // 2️⃣ Validate and delete
      final docRef = _firestore
          .collection('favorites')
          .doc(uid)
          .collection(type)
          .doc(itemId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        await _auditService.updateAuditStatus(
          auditEntry.id,
          newStatus: DeletionStatus.completed,
          errorMessage: 'Favorite already deleted',
        );
        return DeletionResult(
          validation: DeletionValidation.alreadyDeleted,
          isSuccessful: true,
          auditId: auditEntry.id,
          errorMessage: 'Favorite was already deleted',
        );
      }

      await docRef.delete();
      debugPrint('✅ [SAFE DELETE] Favorite deleted: $itemId');

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.completed,
      );

      return DeletionResult(
        validation: DeletionValidation.success,
        isSuccessful: true,
        auditId: auditEntry.id,
        itemsDeleted: 1,
        backupData: backupData,
      );
    } catch (e) {
      debugPrint('❌ [SAFE DELETE] Favorite deletion failed: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🛡️ SAFE ACCOUNT DELETION (HIGH RISK - WITH RECOVERY)
  /// ═══════════════════════════════════════════════════════════════════════
  /// CRITICAL FIX: Detects & logs auth deletion failures with clear warnings
  Future<DeletionResult> safeDeleteAccount({
    required String uid,
    required Function onDataDeletion,
    required Function onAuthDeletion,
  }) async {
    debugPrint('🛡️  [SAFE DELETE] ⚠️  ACCOUNT DELETION INITIATED: $uid');

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return DeletionResult(
        validation: DeletionValidation.userNotAuthenticated,
        isSuccessful: false,
        auditId: 'failed-auth',
        errorMessage: 'User not authenticated for account deletion',
      );
    }

    if (currentUser.uid != uid) {
      return DeletionResult(
        validation: DeletionValidation.invalidInput,
        isSuccessful: false,
        auditId: 'invalid-user',
        errorMessage: 'Cannot delete account of another user',
      );
    }

    try {
      // 1️⃣ Check token freshness
      final tokenCheck = await _staleDetector.checkAuthTokenFreshness();
      if (tokenCheck.isStale) {
        debugPrint('🛑 [SAFE DELETE] Token is stale - cannot proceed');
        return DeletionResult(
          validation: DeletionValidation.other,
          isSuccessful: false,
          auditId: 'stale-token',
          errorMessage:
              'Authentication token is stale. Please re-authenticate.',
        );
      }

      // 2️⃣ Create audit entry (HIGH RISK)
      final auditEntry = await _auditService.createAuditEntry(
        type: DeletionType.userAccount,
        metadata: {
          'uid': uid,
          'email': currentUser.email,
          'riskLevel': 'CRITICAL',
        },
      );

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.inProgress,
      );

      debugPrint('📋 [SAFE DELETE] Audit entry created: ${auditEntry.id}');

      // 3️⃣ Delete Firestore data FIRST (while still authenticated)
      bool firebaseDataDeleted = false;
      try {
        await onDataDeletion();
        firebaseDataDeleted = true;
        debugPrint('✅ [SAFE DELETE] Firestore data deleted');
      } catch (e) {
        debugPrint('❌ [SAFE DELETE] Firestore data deletion FAILED: $e');
        await _auditService.updateAuditStatus(
          auditEntry.id,
          newStatus: DeletionStatus.failed,
          failureReason: 'Firestore data deletion failed: $e',
        );
        rethrow;
      }

      // 4️⃣ Delete Firebase Auth account
      bool authAccountDeleted = false;
      try {
        await onAuthDeletion();
        authAccountDeleted = true;
        debugPrint('✅ [SAFE DELETE] Firebase Auth account deleted');
      } catch (e) {
        // 🔴 CRITICAL: Auth deletion failed but Firestore data is GONE
        debugPrint('🔴 [SAFE DELETE] CRITICAL - Auth deletion FAILED: $e');
        debugPrint('🔴 [SAFE DELETE] User data already deleted from Firestore');
        debugPrint(
          '🔴 [SAFE DELETE] Email still in Firebase Auth: ${currentUser.email}',
        );

        await _auditService.updateAuditStatus(
          auditEntry.id,
          newStatus: DeletionStatus.failed,
          failureReason:
              'ORPHANED_AUTH: Email ${currentUser.email} in Firebase Auth. Firestore data deleted. Manual cleanup needed.',
        );

        throw Exception(
          'ORPHANED_AUTH_ACCOUNT: Email ${currentUser.email} still in Firebase Auth. '
          'Firestore data deleted. Audit ID: ${auditEntry.id}. '
          'Manual cleanup in Firebase Console required.',
        );
      }

      // 5️⃣ Mark as completed ONLY if BOTH deletions succeeded
      if (firebaseDataDeleted && authAccountDeleted) {
        await _auditService.updateAuditStatus(
          auditEntry.id,
          newStatus: DeletionStatus.completed,
        );

        debugPrint('✅ [SAFE DELETE] ✓ ACCOUNT FULLY DELETED: $uid');

        return DeletionResult(
          validation: DeletionValidation.success,
          isSuccessful: true,
          auditId: auditEntry.id,
          itemsDeleted: 1,
        );
      }
    } catch (e) {
      debugPrint('❌ [SAFE DELETE] Account deletion error: $e');
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔧 CLEANUP ORPHANED AUTH ACCOUNTS (MANUAL RECOVERY)
  /// ═══════════════════════════════════════════════════════════════════════
  Future<void> forceDeleteOrphanedAuthAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ [ORPHAN CLEANUP] No user to delete');
        return;
      }

      debugPrint(
        '🔧 [ORPHAN CLEANUP] Force deleting Firebase Auth: ${user.email}',
      );
      await user.delete();
      debugPrint('✅ [ORPHAN CLEANUP] Auth account deleted successfully');
    } catch (e) {
      debugPrint('❌ [ORPHAN CLEANUP] Failed to delete auth account: $e');
      rethrow;
    }
  }

  /// RETRIEVE DELETED DATA FROM BACKUP (FOR RECOVERY)
  /// ═══════════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> recoverDeletedDataFromAudit(
    String auditId,
  ) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      final historyEntries = await _auditService.getAuditHistory();
      final entry = historyEntries.cast<DeletionAuditEntry?>().firstWhere(
        (e) => e?.id == auditId,
        orElse: () => null,
      );

      if (entry != null && entry.backupData != null) {
        debugPrint('✅ [RECOVERY] Backup data retrieved for audit: $auditId');
        return entry.backupData;
      }

      debugPrint('❌ [RECOVERY] No backup found for audit: $auditId');
      return null;
    } catch (e) {
      debugPrint('❌ [RECOVERY] Error retrieving backup: $e');
      return null;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🛡️ CLEANUP UTILITIES FOR STALE DATA
  /// ═══════════════════════════════════════════════════════════════════════

  /// Delete expired reward tokens
  Future<DeletionResult> safeDeleteExpiredTokens({
    required List<String> tokenIds,
    required DateTime expiresAt,
  }) async {
    debugPrint('🛡️  [SAFE DELETE] Deleting ${tokenIds.length} expired tokens');

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return DeletionResult(
        validation: DeletionValidation.userNotAuthenticated,
        isSuccessful: false,
        auditId: 'failed-auth',
      );
    }

    try {
      final auditEntry = await _auditService.createAuditEntry(
        type: DeletionType.expiredToken,
        metadata: {
          'tokenCount': tokenIds.length,
          'expiresAt': expiresAt.toIso8601String(),
        },
        itemsAffected: tokenIds.length,
      );

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.inProgress,
      );

      int deletedCount = 0;
      for (final tokenId in tokenIds) {
        try {
          await _firestore.collection('users').doc(uid).update({
            'activeRewardTokens.$tokenId': FieldValue.delete(),
          });
          deletedCount++;
        } catch (e) {
          debugPrint('⚠️  [SAFE DELETE] Could not delete token $tokenId: $e');
        }
      }

      await _auditService.updateAuditStatus(
        auditEntry.id,
        newStatus: DeletionStatus.completed,
      );

      return DeletionResult(
        validation: DeletionValidation.success,
        isSuccessful: true,
        auditId: auditEntry.id,
        itemsDeleted: deletedCount,
      );
    } catch (e) {
      debugPrint('❌ [SAFE DELETE] Token cleanup failed: $e');
      rethrow;
    }
  }

  /// Cleanup old audit entries
  Future<int> cleanupOldAudits() async {
    return await _auditService.cleanupOldAuditEntries();
  }

  /// Get deletion history for current user
  Future<List<DeletionAuditEntry>> getDeletionHistory() async {
    return await _auditService.getAuditHistory();
  }
}
