/// 🎯 DATA INTEGRITY MANAGER (FACADE)
/// Single entry point for all deletion, stale detection, and audit operations
/// Consolidates DeletionAuditService, StaleDataDetector, and SafeDeletionManager

import 'package:flutter/foundation.dart';

import 'deletion_audit_service.dart';
import 'stale_data_detector.dart';
import 'safe_deletion_manager.dart';

class DataIntegrityManager {
  static final DataIntegrityManager _instance =
      DataIntegrityManager._internal();

  factory DataIntegrityManager() => _instance;

  DataIntegrityManager._internal();

  // Private instances of the three core services
  late final DeletionAuditService _auditService = DeletionAuditService();
  late final StaleDataDetector _staleDetector = StaleDataDetector();
  late final SafeDeletionManager _deletionManager = SafeDeletionManager();

  // ═══════════════════════════════════════════════════════════════════════
  // 📋 AUDIT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get the audit service for direct access if needed
  DeletionAuditService get auditService => _auditService;

  /// Get deletion history for current user
  Future<List<DeletionAuditEntry>> getDeletionHistory({
    int limit = 50,
    DeletionStatus? filterStatus,
  }) {
    return _auditService.getAuditHistory(
      limit: limit,
      filterStatus: filterStatus,
    );
  }

  /// Get failed deletions for debugging/recovery
  Future<List<DeletionAuditEntry>> getFailedDeletions() {
    return _auditService.getFailedDeletions();
  }

  /// Cleanup old audit entries (> 90 days)
  Future<int> cleanupOldAuditTrail() {
    return _auditService.cleanupOldAuditEntries();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🚨 STALE DATA DETECTION
  // ═══════════════════════════════════════════════════════════════════════

  /// Get the stale detector service for direct access if needed
  StaleDataDetector get staleDetector => _staleDetector;

  /// Quick check: Is auth token stale?
  Future<bool> isAuthTokenStale() async {
    final indicator = await _staleDetector.checkAuthTokenFreshness();
    return indicator.isStale;
  }

  /// Quick check: Get auth token freshness info
  Future<StaleDataIndicator> getAuthTokenFreshness() {
    return _staleDetector.checkAuthTokenFreshness();
  }

  /// Check if session is stale
  bool isSessionStale(DateTime lastActivityTime) {
    final indicator = _staleDetector.checkSessionStaleness(
      lastActivityTime: lastActivityTime,
    );
    return indicator.isStale;
  }

  /// Check if cache is stale
  bool isCacheStale(DateTime cacheCreatedAt) {
    final indicator = _staleDetector.checkCacheStaleness(
      cacheCreatedAt: cacheCreatedAt,
    );
    return indicator.isStale;
  }

  /// Check if remote config is stale
  bool isRemoteConfigStale(DateTime lastFetchTime) {
    final indicator = _staleDetector.checkRemoteConfigStaleness(
      lastFetchTime: lastFetchTime,
    );
    return indicator.isStale;
  }

  /// Perform comprehensive stale data check
  Future<ComprehensiveStaleReport> checkSystemHealth() async {
    debugPrint(
      '🏥 [DATA INTEGRITY] Running comprehensive system health check...',
    );

    final tokenFreshness = await _staleDetector.checkAuthTokenFreshness();
    final hasStaleAuth = tokenFreshness.isStale;

    final report = ComprehensiveStaleReport(
      timestamp: DateTime.now(),
      authTokenFresh: !hasStaleAuth,
      authTokenDetails: tokenFreshness,
      overallHealthy: !hasStaleAuth, // Add more checks as needed
    );

    debugPrint('''
🏥 [SYSTEM HEALTH REPORT]
  Auth Token Fresh: ${report.authTokenFresh}
  Overall Healthy: ${report.overallHealthy}
  Report Time: ${report.formattedTime}
    ''');

    return report;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🛡️ SAFE DELETION OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get the deletion manager service for direct access if needed
  SafeDeletionManager get deletionManager => _deletionManager;

  /// Safe delete single history item
  Future<DeletionResult> deleteHistoryItem({
    required String itemId,
    required String type,
    required Map<String, dynamic> backupData,
  }) {
    return _deletionManager.safeDeleteHistoryItem(
      itemId: itemId,
      type: type,
      backupData: backupData,
      createBackup: true,
    );
  }

  /// Safe delete multiple history items
  Future<DeletionResult> deleteHistoryItems({
    required List<String> itemIds,
    required List<Map<String, dynamic>> backupDataList,
  }) {
    return _deletionManager.safeDeleteHistoryBulk(
      itemIds: itemIds,
      backupDataList: backupDataList,
      createBackups: true,
    );
  }

  /// Safe delete favorite
  Future<DeletionResult> deleteFavorite({
    required String itemId,
    required String type,
    required Map<String, dynamic> backupData,
  }) {
    return _deletionManager.safDeleteFavorite(
      itemId: itemId,
      type: type,
      backupData: backupData,
    );
  }

  /// Safe delete user account (HIGH RISK - requires re-authentication)
  Future<DeletionResult> deleteUserAccount({
    required String uid,
    required Function onDataDeletion,
    required Function onAuthDeletion,
  }) {
    return _deletionManager.safeDeleteAccount(
      uid: uid,
      onDataDeletion: onDataDeletion,
      onAuthDeletion: onAuthDeletion,
    );
  }

  /// Recover deleted data from audit backup
  Future<Map<String, dynamic>?> recoverDeletedData(String auditId) {
    return _deletionManager.recoverDeletedDataFromAudit(auditId);
  }

  /// Force delete orphaned auth account (for recovery after auth deletion failures)
  Future<void> forceCleanupOrphanedAuthAccount() {
    return _deletionManager.forceDeleteOrphanedAuthAccount();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Delete expired reward tokens
  Future<DeletionResult> deleteExpiredRewardTokens({
    required List<String> tokenIds,
    required DateTime expiresAt,
  }) {
    return _deletionManager.safeDeleteExpiredTokens(
      tokenIds: tokenIds,
      expiresAt: expiresAt,
    );
  }

  /// Perform comprehensive cleanup (audits + stale data)
  Future<CleanupReport> performComprehensiveCleanup() async {
    debugPrint('🧹 [DATA INTEGRITY] Starting comprehensive cleanup...');

    int auditsCleaned = 0;
    int failedOps = 0;

    try {
      auditsCleaned = await _deletionManager.cleanupOldAudits();
      debugPrint('✅ Cleaned up $auditsCleaned old audit entries');
    } catch (e) {
      debugPrint('❌ Error cleaning audits: $e');
      failedOps++;
    }

    final failedDeletions = await _auditService.getFailedDeletions();

    return CleanupReport(
      timestamp: DateTime.now(),
      auditEntriesRemoved: auditsCleaned,
      failedDeleteionsFound: failedDeletions.length,
      isSuccessful: failedOps == 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔐 SECURITY OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Verify deletion is properly audited and safe
  Future<bool> isDeletionProperlyAudited(String auditId) {
    return _auditService.isDeletionProperlySafe(auditId);
  }

  /// Validate all recent deletions are properly logged
  Future<DeletionValidationReport> validateRecentDeletions() async {
    debugPrint('🔐 [VALIDATION] Validating recent deletions...');

    try {
      final history = await _auditService.getAuditHistory(limit: 20);

      int totalAudited = history.length;
      int properlyBackedUp = history.where((e) => e.backupData != null).length;
      int completed = history
          .where((e) => e.status == DeletionStatus.completed)
          .length;
      int failed = history
          .where((e) => e.status == DeletionStatus.failed)
          .length;

      return DeletionValidationReport(
        timestamp: DateTime.now(),
        totalAudited: totalAudited,
        properlyBackedUp: properlyBackedUp,
        completedOperations: completed,
        failedOperations: failed,
        isValid:
            (properlyBackedUp / (totalAudited + 1)) > 0.95, // 95% backup rate
      );
    } catch (e) {
      debugPrint('❌ Validation failed: $e');
      return DeletionValidationReport(
        timestamp: DateTime.now(),
        totalAudited: 0,
        properlyBackedUp: 0,
        completedOperations: 0,
        failedOperations: 0,
        isValid: false,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 📊 REPORT MODELS
// ═══════════════════════════════════════════════════════════════════════

class ComprehensiveStaleReport {
  final DateTime timestamp;
  final bool authTokenFresh;
  final StaleDataIndicator authTokenDetails;
  final bool overallHealthy;

  ComprehensiveStaleReport({
    required this.timestamp,
    required this.authTokenFresh,
    required this.authTokenDetails,
    required this.overallHealthy,
  });

  String get formattedTime => timestamp.toIso8601String();
  String get status => overallHealthy ? '✅ HEALTHY' : '🔴 DEGRADED';

  @override
  String toString() =>
      '''
╔════════════════════════════════════════════╗
║   SYSTEM HEALTH REPORT                   ║
╚════════════════════════════════════════════╝
Status: $status
Time: $formattedTime
Auth Token: ${authTokenFresh ? '🟢 FRESH' : '🔴 STALE'}
  └─ $authTokenDetails
    ''';
}

class CleanupReport {
  final DateTime timestamp;
  final int auditEntriesRemoved;
  final int failedDeleteionsFound;
  final bool isSuccessful;

  CleanupReport({
    required this.timestamp,
    required this.auditEntriesRemoved,
    required this.failedDeleteionsFound,
    required this.isSuccessful,
  });

  @override
  String toString() =>
      '''
╔════════════════════════════════════════════╗
║   CLEANUP REPORT                         ║
╚════════════════════════════════════════════╝
Time: ${timestamp.toIso8601String()}
Audit Entries Removed: $auditEntriesRemoved
Failed Deletions Found: $failedDeleteionsFound
Status: ${isSuccessful ? '✅ SUCCESS' : '⚠️  WARNINGS'}
  ''';
}

class DeletionValidationReport {
  final DateTime timestamp;
  final int totalAudited;
  final int properlyBackedUp;
  final int completedOperations;
  final int failedOperations;
  final bool isValid;

  DeletionValidationReport({
    required this.timestamp,
    required this.totalAudited,
    required this.properlyBackedUp,
    required this.completedOperations,
    required this.failedOperations,
    required this.isValid,
  });

  double get backupCoverage =>
      totalAudited > 0 ? (properlyBackedUp / totalAudited) * 100 : 0;

  @override
  String toString() =>
      '''
╔════════════════════════════════════════════╗
║   DELETION VALIDATION REPORT             ║
╚════════════════════════════════════════════╝
Time: ${timestamp.toIso8601String()}
Total Audited: $totalAudited
Properly Backed Up: $properlyBackedUp (${backupCoverage.toStringAsFixed(1)}%)
Completed: $completedOperations
Failed: $failedOperations
Overall Valid: ${isValid ? '✅ YES' : '⚠️  NO'}
  ''';
}
