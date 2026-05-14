import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics Service
/// Handles crash reporting and non-fatal error tracking to Firebase Crashlytics
class CrashlyticsService {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  /// Initialize Crashlytics
  /// Should be called in main() before runApp()
  static Future<void> initialize() async {
    try {
      // Only enable Crashlytics in production (non-debug)
      if (kDebugMode) {
        debugPrint('🔧 Crashlytics: Debug mode - crash reporting disabled');
        // In debug mode, we still initialize but crashes aren't sent
        await _crashlytics.setCrashlyticsCollectionEnabled(false);
      } else {
        debugPrint('🚀 Crashlytics: Production mode - crash reporting enabled');
        await _crashlytics.setCrashlyticsCollectionEnabled(true);
      }

      // Capture Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails errorDetails) async {
        debugPrint('❌ Flutter Framework Error: ${errorDetails.exception}');
        debugPrint('   Stack trace: ${errorDetails.stack}');

        if (kDebugMode) {
          FlutterError.presentError(errorDetails);
        } else {
          // Send to Crashlytics in production
          await _crashlytics.recordFlutterError(errorDetails);
        }
      };

      debugPrint('✅ Crashlytics initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize Crashlytics: $e');
    }
  }

  /// Log a non-fatal exception (error that doesn't crash the app)
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Iterable<Object> information = const [],
    bool printDetails = true,
  }) async {
    try {
      if (printDetails) {
        debugPrint('⚠️ Recording non-fatal error: $exception');
        if (reason != null) {
          debugPrint('   Reason: $reason');
        }
        if (stackTrace != null) {
          debugPrint('   Stack trace: $stackTrace');
        }
      }

      if (!kDebugMode) {
        await _crashlytics.recordError(
          exception,
          stackTrace,
          reason: reason,
          information: information,
          fatal: false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to record error to Crashlytics: $e');
    }
  }

  /// Log a fatal exception (crash)
  static Future<void> recordFatalError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
  }) async {
    try {
      debugPrint('🔴 Recording FATAL error: $exception');
      if (reason != null) {
        debugPrint('   Reason: $reason');
      }

      if (!kDebugMode) {
        await _crashlytics.recordError(
          exception,
          stackTrace,
          reason: reason,
          fatal: true,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to record fatal error to Crashlytics: $e');
    }
  }

  /// Set custom user ID for tracking
  static Future<void> setUserId(String userId) async {
    try {
      await _crashlytics.setUserIdentifier(userId);
      debugPrint('🔐 Crashlytics: User ID set to $userId');
    } catch (e) {
      debugPrint('⚠️ Failed to set Crashlytics user ID: $e');
    }
  }

  /// Clear user ID
  static Future<void> clearUserId() async {
    try {
      await _crashlytics.setUserIdentifier('');
      debugPrint('🔐 Crashlytics: User ID cleared');
    } catch (e) {
      debugPrint('⚠️ Failed to clear Crashlytics user ID: $e');
    }
  }

  /// Add custom key-value data to crash reports
  static Future<void> setCustomKey(String key, dynamic value) async {
    try {
      if (value is String) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is int) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is double) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is bool) {
        await _crashlytics.setCustomKey(key, value);
      } else {
        await _crashlytics.setCustomKey(key, value.toString());
      }
      debugPrint('📝 Crashlytics: Custom key set - $key: $value');
    } catch (e) {
      debugPrint('⚠️ Failed to set custom key in Crashlytics: $e');
    }
  }

  /// Set multiple custom keys at once
  static Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    for (final entry in keys.entries) {
      await setCustomKey(entry.key, entry.value);
    }
  }

  /// Log a breadcrumb (informational log for crash context)
  static Future<void> logBreadcrumb(String message) async {
    try {
      if (!kDebugMode) {
        await _crashlytics.log(message);
      }
      debugPrint('📍 Breadcrumb: $message');
    } catch (e) {
      debugPrint('⚠️ Failed to log breadcrumb: $e');
    }
  }

  /// Check if Crashlytics collection is enabled
  static bool isEnabled() {
    return !kDebugMode;
  }
}
