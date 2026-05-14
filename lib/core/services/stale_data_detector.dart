/// 🚨 STALE DATA DETECTOR
/// Consolidated service for detecting and managing stale data across the app
/// Handles token staleness, session expiry, cache expiration, and timeout detection

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum StaleDataType {
  authToken,
  session,
  cacheData,
  remoteConfig,
  rewardToken,
  resetLock,
  userSession,
  other,
}

class StaleDataIndicator {
  final StaleDataType type;
  final bool isStale;
  final Duration? timeSinceCreation;
  final Duration? timeUntilStale;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? reason;
  final Map<String, dynamic>? metadata;

  StaleDataIndicator({
    required this.type,
    required this.isStale,
    this.timeSinceCreation,
    this.timeUntilStale,
    this.createdAt,
    this.expiresAt,
    this.reason,
    this.metadata,
  });

  @override
  String toString() {
    final staleStatus = isStale ? '🔴 STALE' : '🟢 FRESH';
    final age = timeSinceCreation != null
        ? '${timeSinceCreation!.inSeconds}s'
        : 'unknown';
    final remaining = timeUntilStale != null
        ? ' (${timeUntilStale!.inSeconds}s remaining)'
        : '';
    return '[$staleStatus] ${type.name} - Age: $age$remaining';
  }
}

class StaleDataDetector {
  static final StaleDataDetector _instance = StaleDataDetector._internal();

  factory StaleDataDetector() => _instance;

  StaleDataDetector._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 🎯 CRITICAL: Store session start time to check session age independently
  /// This avoids Firebase's auto-refresh that happens with getIdTokenResult()
  static DateTime? _sessionStartTime;

  /// Record session start when user logs in
  static void recordSessionStart() {
    _sessionStartTime = DateTime.now();
    debugPrint('📍 [SESSION TRACKER] Session started at $_sessionStartTime');
  }

  /// Reset session when user logs out
  static void resetSession() {
    _sessionStartTime = null;
    debugPrint('📍 [SESSION TRACKER] Session reset');
  }

  /// Define stale thresholds for each data type
  /// 🧪 NOTE: Auth token threshold set to 60 seconds (1 minute) for testing
  /// Change back to 300 (5 min) after testing complete
  static const int _authTokenStaleThresholdSeconds = 60; // 1 minute
  static const int _sessionStaleThresholdSeconds = 3600; // 1 hour
  static const int _cacheStaleThresholdSeconds = 1800; // 30 minutes
  static const int _remoteConfigStaleThresholdSeconds = 3600; // 1 hour
  static const int _rewardTokenStaleThresholdSeconds = 86400; // 24 hours
  static const int _resetLockStaleThresholdSeconds = 900; // 15 minutes

  /// ============================================================================
  /// PRIMARY: Check if auth token is stale (using SESSION TIME, not Firebase call)
  /// ============================================================================
  Future<StaleDataIndicator> checkAuthTokenFreshness() async {
    debugPrint('🔍 [STALE DETECTOR] Checking auth token freshness...');

    final user = _auth.currentUser;
    if (user == null) {
      return StaleDataIndicator(
        type: StaleDataType.authToken,
        isStale: true,
        reason: 'No user authenticated',
      );
    }

    // 🎯 CRITICAL FIX: Use _sessionStartTime, NOT getIdTokenResult()
    // because getIdTokenResult() auto-refreshes token making the check useless!
    if (_sessionStartTime == null) {
      debugPrint('⚠️  [STALE DETECTOR] No session start time recorded');
      return StaleDataIndicator(
        type: StaleDataType.authToken,
        isStale: true,
        reason: 'Session start time not recorded',
      );
    }

    try {
      final nowTime = DateTime.now();
      final ageInSeconds = nowTime.difference(_sessionStartTime!).inSeconds;
      final isStale = ageInSeconds >= _authTokenStaleThresholdSeconds;
      final secondsRemaining = _authTokenStaleThresholdSeconds - ageInSeconds;

      final indicator = StaleDataIndicator(
        type: StaleDataType.authToken,
        isStale: isStale,
        timeSinceCreation: Duration(seconds: ageInSeconds),
        timeUntilStale: isStale
            ? Duration.zero
            : Duration(seconds: secondsRemaining),
        createdAt: _sessionStartTime,
        expiresAt: _sessionStartTime!.add(
          Duration(seconds: _authTokenStaleThresholdSeconds),
        ),
        reason: isStale
            ? 'Session older than ${_authTokenStaleThresholdSeconds}s'
            : 'Session is fresh',
        metadata: {
          'ageInSeconds': ageInSeconds,
          'threshold': _authTokenStaleThresholdSeconds,
          'sessionStartTime': _sessionStartTime.toString(),
        },
      );

      debugPrint('✅ [STALE DETECTOR] $indicator');
      return indicator;
    } catch (e) {
      debugPrint('❌ [STALE DETECTOR] Error checking token: $e');
      return StaleDataIndicator(
        type: StaleDataType.authToken,
        isStale: true,
        reason: 'Could not verify token freshness: $e',
      );
    }
  }

  /// ============================================================================
  /// Check if session data is stale
  /// ============================================================================
  StaleDataIndicator checkSessionStaleness({
    required DateTime lastActivityTime,
  }) {
    final nowTime = DateTime.now();
    final ageInSeconds = nowTime.difference(lastActivityTime).inSeconds;
    final isStale = ageInSeconds >= _sessionStaleThresholdSeconds;
    final secondsRemaining = _sessionStaleThresholdSeconds - ageInSeconds;

    return StaleDataIndicator(
      type: StaleDataType.session,
      isStale: isStale,
      timeSinceCreation: Duration(seconds: ageInSeconds),
      timeUntilStale: isStale
          ? Duration.zero
          : Duration(seconds: secondsRemaining),
      createdAt: lastActivityTime,
      expiresAt: lastActivityTime.add(const Duration(hours: 1)),
      reason: isStale ? 'Session inactive for > 1 hour' : 'Session active',
      metadata: {
        'ageInSeconds': ageInSeconds,
        'threshold': _sessionStaleThresholdSeconds,
      },
    );
  }

  /// ============================================================================
  /// Check if cached data is stale
  /// ============================================================================
  StaleDataIndicator checkCacheStaleness({required DateTime cacheCreatedAt}) {
    final nowTime = DateTime.now();
    final ageInSeconds = nowTime.difference(cacheCreatedAt).inSeconds;
    final isStale = ageInSeconds >= _cacheStaleThresholdSeconds;
    final secondsRemaining = _cacheStaleThresholdSeconds - ageInSeconds;

    return StaleDataIndicator(
      type: StaleDataType.cacheData,
      isStale: isStale,
      timeSinceCreation: Duration(seconds: ageInSeconds),
      timeUntilStale: isStale
          ? Duration.zero
          : Duration(seconds: secondsRemaining),
      createdAt: cacheCreatedAt,
      expiresAt: cacheCreatedAt.add(const Duration(minutes: 30)),
      reason: isStale ? 'Cache older than 30 minutes' : 'Cache is fresh',
      metadata: {
        'ageInSeconds': ageInSeconds,
        'threshold': _cacheStaleThresholdSeconds,
      },
    );
  }

  /// ============================================================================
  /// Check if remote config is stale
  /// ============================================================================
  StaleDataIndicator checkRemoteConfigStaleness({
    required DateTime lastFetchTime,
  }) {
    final nowTime = DateTime.now();
    final ageInSeconds = nowTime.difference(lastFetchTime).inSeconds;
    final isStale = ageInSeconds >= _remoteConfigStaleThresholdSeconds;
    final secondsRemaining = _remoteConfigStaleThresholdSeconds - ageInSeconds;

    return StaleDataIndicator(
      type: StaleDataType.remoteConfig,
      isStale: isStale,
      timeSinceCreation: Duration(seconds: ageInSeconds),
      timeUntilStale: isStale
          ? Duration.zero
          : Duration(seconds: secondsRemaining),
      createdAt: lastFetchTime,
      expiresAt: lastFetchTime.add(const Duration(hours: 1)),
      reason: isStale
          ? 'Remote config not fetched for > 1 hour'
          : 'Remote config is current',
      metadata: {
        'ageInSeconds': ageInSeconds,
        'threshold': _remoteConfigStaleThresholdSeconds,
      },
    );
  }

  /// ============================================================================
  /// Check if reward token is stale
  /// ============================================================================
  StaleDataIndicator checkRewardTokenStaleness({
    required DateTime tokenCreatedAt,
    required bool isConsumed,
  }) {
    if (isConsumed) {
      return StaleDataIndicator(
        type: StaleDataType.rewardToken,
        isStale: true,
        createdAt: tokenCreatedAt,
        reason: 'Token has been consumed',
        metadata: {'consumed': true},
      );
    }

    final nowTime = DateTime.now();
    final ageInSeconds = nowTime.difference(tokenCreatedAt).inSeconds;
    final isStale = ageInSeconds >= _rewardTokenStaleThresholdSeconds;
    final secondsRemaining = _rewardTokenStaleThresholdSeconds - ageInSeconds;

    return StaleDataIndicator(
      type: StaleDataType.rewardToken,
      isStale: isStale,
      timeSinceCreation: Duration(seconds: ageInSeconds),
      timeUntilStale: isStale
          ? Duration.zero
          : Duration(seconds: secondsRemaining),
      createdAt: tokenCreatedAt,
      expiresAt: tokenCreatedAt.add(const Duration(hours: 24)),
      reason: isStale ? 'Token older than 24 hours' : 'Token is valid',
      metadata: {
        'ageInSeconds': ageInSeconds,
        'threshold': _rewardTokenStaleThresholdSeconds,
      },
    );
  }

  /// ============================================================================
  /// Check if reset lock is stale
  /// ============================================================================
  StaleDataIndicator checkResetLockStaleness({
    required DateTime lockCreatedAt,
  }) {
    final nowTime = DateTime.now();
    final ageInSeconds = nowTime.difference(lockCreatedAt).inSeconds;
    final isStale = ageInSeconds >= _resetLockStaleThresholdSeconds;
    final secondsRemaining = _resetLockStaleThresholdSeconds - ageInSeconds;

    return StaleDataIndicator(
      type: StaleDataType.resetLock,
      isStale: isStale,
      timeSinceCreation: Duration(seconds: ageInSeconds),
      timeUntilStale: isStale
          ? Duration.zero
          : Duration(seconds: secondsRemaining),
      createdAt: lockCreatedAt,
      expiresAt: lockCreatedAt.add(const Duration(minutes: 15)),
      reason: isStale ? 'Lock older than 15 minutes' : 'Lock is active',
      metadata: {
        'ageInSeconds': ageInSeconds,
        'threshold': _resetLockStaleThresholdSeconds,
      },
    );
  }

  /// ============================================================================
  /// Comprehensive stale data check - checks all critical data
  /// ============================================================================
  Future<Map<StaleDataType, StaleDataIndicator>> performComprehensiveCheck({
    DateTime? lastSessionActivity,
    DateTime? cacheCreatedAt,
    DateTime? lastRemoteConfigFetch,
    DateTime? lastRewardTokenCreated,
    bool? isRewardTokenConsumed,
    DateTime? lockCreatedAt,
  }) async {
    final results = <StaleDataType, StaleDataIndicator>{};

    // Check auth token
    results[StaleDataType.authToken] = await checkAuthTokenFreshness();

    // Check session if provided
    if (lastSessionActivity != null) {
      results[StaleDataType.session] = checkSessionStaleness(
        lastActivityTime: lastSessionActivity,
      );
    }

    // Check cache if provided
    if (cacheCreatedAt != null) {
      results[StaleDataType.cacheData] = checkCacheStaleness(
        cacheCreatedAt: cacheCreatedAt,
      );
    }

    // Check remote config if provided
    if (lastRemoteConfigFetch != null) {
      results[StaleDataType.remoteConfig] = checkRemoteConfigStaleness(
        lastFetchTime: lastRemoteConfigFetch,
      );
    }

    // Check reward token if provided
    if (lastRewardTokenCreated != null) {
      results[StaleDataType.rewardToken] = checkRewardTokenStaleness(
        tokenCreatedAt: lastRewardTokenCreated,
        isConsumed: isRewardTokenConsumed ?? false,
      );
    }

    // Check reset lock if provided
    if (lockCreatedAt != null) {
      results[StaleDataType.resetLock] = checkResetLockStaleness(
        lockCreatedAt: lockCreatedAt,
      );
    }

    debugPrint('📊 [STALE DETECTOR] Comprehensive check completed');
    for (final entry in results.entries) {
      debugPrint('  • ${entry.value}');
    }

    return results;
  }

  /// ============================================================================
  /// Utility: Check if ANY data is stale
  /// ============================================================================
  bool hasAnyStaleData(Map<StaleDataType, StaleDataIndicator> checkResults) {
    return checkResults.values.any((indicator) => indicator.isStale);
  }

  /// ============================================================================
  /// Utility: Get critical stale data (for emergency cleanup)
  /// ============================================================================
  List<StaleDataIndicator> getCriticalStaleData(
    Map<StaleDataType, StaleDataIndicator> checkResults,
  ) {
    return checkResults.values.where((indicator) => indicator.isStale).toList();
  }
}
