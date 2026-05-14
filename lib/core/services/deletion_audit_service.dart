/// 🔐 DELETION AUDIT SERVICE
/// Centralized audit logging for all deletion operations
/// Provides complete traceability and rollback capability

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum DeletionType {
  historyItem,
  favorite,
  userAccount,
  bulkHistoryItems,
  bulkFavorites,
  expiredToken,
  staleSession,
  cacheEntry,
  other,
}

enum DeletionStatus { pending, inProgress, completed, failed, rolledBack }

class DeletionAuditEntry {
  final String id;
  final String uid;
  final DeletionType type;
  final DeletionStatus status;
  final DateTime initiatedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic>? backupData;
  final String? errorMessage;
  final String? failureReason;
  final int itemsAffected;

  DeletionAuditEntry({
    required this.id,
    required this.uid,
    required this.type,
    required this.status,
    required this.initiatedAt,
    this.completedAt,
    required this.metadata,
    this.backupData,
    this.errorMessage,
    this.failureReason,
    this.itemsAffected = 1,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'uid': uid,
    'type': type.toString().split('.').last,
    'status': status.toString().split('.').last,
    'initiatedAt': Timestamp.fromDate(initiatedAt),
    'completedAt': completedAt != null
        ? Timestamp.fromDate(completedAt!)
        : null,
    'metadata': metadata,
    'backupData': backupData,
    'errorMessage': errorMessage,
    'failureReason': failureReason,
    'itemsAffected': itemsAffected,
  };
}

class DeletionAuditService {
  static final DeletionAuditService _instance =
      DeletionAuditService._internal();

  factory DeletionAuditService() => _instance;

  DeletionAuditService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Create a new deletion audit entry
  Future<DeletionAuditEntry> createAuditEntry({
    required DeletionType type,
    required Map<String, dynamic> metadata,
    Map<String, dynamic>? backupData,
    int itemsAffected = 1,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final entry = DeletionAuditEntry(
      id: _firestore.collection('deletion_audit').doc().id,
      uid: uid,
      type: type,
      status: DeletionStatus.pending,
      initiatedAt: DateTime.now(),
      metadata: metadata,
      backupData: backupData,
      itemsAffected: itemsAffected,
    );

    await _firestore
        .collection('deletion_audit')
        .doc(entry.id)
        .set(entry.toFirestore(), SetOptions(merge: true));

    debugPrint('📋 [AUDIT] Deletion entry created: ${entry.id} (${type.name})');
    return entry;
  }

  /// Update audit entry status
  Future<void> updateAuditStatus(
    String auditId, {
    required DeletionStatus newStatus,
    String? errorMessage,
    String? failureReason,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final updates = {
      'status': newStatus.toString().split('.').last,
      if (newStatus == DeletionStatus.completed) 'completedAt': Timestamp.now(),
      if (newStatus == DeletionStatus.failed) ...{
        'errorMessage': errorMessage,
        'failureReason': failureReason,
      },
    };

    await _firestore.collection('deletion_audit').doc(auditId).update(updates);

    debugPrint('📋 [AUDIT] Status updated: $auditId → ${newStatus.name}');
  }

  /// Get audit entries for current user
  Future<List<DeletionAuditEntry>> getAuditHistory({
    int limit = 50,
    DeletionStatus? filterStatus,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    Query query = _firestore
        .collection('deletion_audit')
        .where('uid', isEqualTo: uid)
        .orderBy('initiatedAt', descending: true)
        .limit(limit);

    if (filterStatus != null) {
      query = query.where(
        'status',
        isEqualTo: filterStatus.toString().split('.').last,
      );
    }

    final snapshot = await query.get();
    // ignore: unnecessary_cast
    return snapshot.docs
        .map((doc) => _parseAuditEntry(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Check if deletion is safe (has proper audit trail)
  Future<bool> isDeletionProperlySafe(String auditId) async {
    try {
      final doc = await _firestore
          .collection('deletion_audit')
          .doc(auditId)
          .get();
      if (!doc.exists) return false;

      final data = doc.data() as Map<String, dynamic>;
      final backupExists = data['backupData'] != null;
      final metadataComplete = (data['metadata'] as Map?)?.isNotEmpty ?? false;

      return backupExists && metadataComplete;
    } catch (e) {
      debugPrint('⚠️  [AUDIT] Safety check failed: $e');
      return false;
    }
  }

  /// Get failed deletion entries for retry/debugging
  Future<List<DeletionAuditEntry>> getFailedDeletions() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await _firestore
        .collection('deletion_audit')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'failed')
        .orderBy('initiatedAt', descending: true)
        .limit(20)
        .get();

    return snapshot.docs
        // ignore: unnecessary_cast
        .map((doc) => _parseAuditEntry(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Cleanup old audit entries (older than 90 days)
  Future<int> cleanupOldAuditEntries() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;

    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));

    final snapshot = await _firestore
        .collection('deletion_audit')
        .where('uid', isEqualTo: uid)
        .where('initiatedAt', isLessThan: Timestamp.fromDate(cutoffDate))
        .limit(100)
        .get();

    int deletedCount = 0;
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      deletedCount++;
    }

    if (deletedCount > 0) {
      await batch.commit();
      debugPrint('🧹 [AUDIT] Cleaned up $deletedCount old audit entries');
    }

    return deletedCount;
  }

  /// Parse audit entry from Firestore document
  DeletionAuditEntry _parseAuditEntry(Map<String, dynamic> data) {
    return DeletionAuditEntry(
      id: data['id'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      type: _parseDeletionType(data['type'] as String?),
      status: _parseDeletionStatus(data['status'] as String?),
      initiatedAt: _parseTimestamp(data['initiatedAt']),
      completedAt: data['completedAt'] != null
          ? _parseTimestamp(data['completedAt'])
          : null,
      metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
      backupData: (data['backupData'] as Map?)?.cast<String, dynamic>(),
      errorMessage: data['errorMessage'] as String?,
      failureReason: data['failureReason'] as String?,
      itemsAffected: data['itemsAffected'] as int? ?? 1,
    );
  }

  DeletionType _parseDeletionType(String? type) {
    if (type == null) return DeletionType.other;
    try {
      return DeletionType.values.firstWhere(
        (e) => e.toString().split('.').last == type,
        orElse: () => DeletionType.other,
      );
    } catch (_) {
      return DeletionType.other;
    }
  }

  DeletionStatus _parseDeletionStatus(String? status) {
    if (status == null) return DeletionStatus.pending;
    try {
      return DeletionStatus.values.firstWhere(
        (e) => e.toString().split('.').last == status,
        orElse: () => DeletionStatus.pending,
      );
    } catch (_) {
      return DeletionStatus.pending;
    }
  }

  DateTime _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return DateTime.now();
  }
}
