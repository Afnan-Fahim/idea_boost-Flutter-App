import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:ideaboost/core/constants/locale_config.dart';

/// Service for managing app language detection and restoration.
///
/// - **New User Detection:** Captures device language on first app launch
/// - **Auto-Login Restoration:** Restores saved language when returning user auto-logs in
/// - **Language Sync:** Ensures Firestore language preference is reflected in the UI
class LanguageService {
  /// ⚡ OPTIMIZATION: Cache device language detection result
  static String? _cachedDeviceLanguage;

  /// Get the device's system locale, or a supported fallback.
  /// Cached for performance - only computed once per app session.
  static String getDeviceLanguageCode() {
    // Return cached result if already computed
    if (_cachedDeviceLanguage != null) {
      return _cachedDeviceLanguage!;
    }

    final deviceLocale = WidgetsBinding.instance.window.locale;
    final langCode = deviceLocale.languageCode;

    // Check if device language is supported by the app
    final isSupported = supportedAppLocales.any(
      (locale) => locale.languageCode == langCode,
    );

    // Cache the result
    _cachedDeviceLanguage = isSupported ? langCode : 'en';
    return _cachedDeviceLanguage!;
  }

  /// Set the app locale and persist to shared storage.
  ///
  /// This should be called when:
  /// - User first signs up (with device language)
  /// - User logs in (with saved Firestore language)
  /// - User changes language in profile
  static Future<void> setAppLocale(
    BuildContext context,
    String languageCode,
  ) async {
    try {
      await context.setLocale(Locale(languageCode));
    } catch (e) {
      debugPrint('Error setting locale to $languageCode: $e');
    }
  }

  /// Get the current app locale code (e.g., 'en', 'ru', 'ar')
  static String getCurrentLocaleCode(BuildContext context) {
    return context.locale.languageCode;
  }
}
