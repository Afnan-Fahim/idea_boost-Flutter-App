import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shows a SnackBar after clearing any existing SnackBars to prevent queue buildup.
/// This prevents multiple SnackBars from stacking when buttons are clicked rapidly.
void showSnackBarSafe(BuildContext context, SnackBar snackBar) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(snackBar);
}

/// Get the current app language code with proper fallback.
/// CRITICAL: Ensures language is NEVER null and is always valid.
///
/// Returns user's selected language or falls back to device language.
/// Supports: en, ru, uz, ar, de, es, fr, hi, id, ms, pt, vi
String getAppLanguageCode(BuildContext context) {
  try {
    // Get the current locale from easy_localization context
    final currentLocale = context.locale;
    final langCode = currentLocale.languageCode;

    // Validate it's a supported language
    const supportedLanguages = {
      'en',
      'ru',
      'uz',
      'ar',
      'de',
      'es',
      'fr',
      'hi',
      'id',
      'ms',
      'pt',
      'vi',
    };
    if (supportedLanguages.contains(langCode)) {
      return langCode;
    }

    // Fallback if language isn't supported
    return 'en';
  } catch (e) {
    // Emergency fallback
    return 'en';
  }
}

/// Get valid OS-level locale with proper normalization.
/// Returns locale in "en-PK" format (language-REGION).
///
/// ✅ Normalizes Platform.localeName (which uses underscores) to hyphens
/// ✅ Validates that locale has proper structure (lang-REGION or lang)
/// ✅ Fallback: "en-US" if OS locale cannot be determined
///
/// Examples:
///   - "en_PK" (Android/iOS) → "en-PK" ✅
///   - "en" (some devices) → "en" ✅
///   - null/empty → "en-US" (fallback) ✅
String getValidOsLocale() {
  try {
    // Get OS-level locale from Platform
    final osLocale = Platform.localeName;

    if (osLocale.isEmpty) {
      return 'en-US'; // Fallback if empty
    }

    // Normalize: replace underscore with hyphen (Android/iOS uses "_")
    final normalized = osLocale.replaceAll('_', '-');

    // Validate structure: should be "lang" or "lang-REGION"
    final parts = normalized.split('-');
    if (parts.isEmpty || parts[0].isEmpty) {
      return 'en-US'; // Fallback if invalid
    }

    return normalized;
  } catch (e) {
    // Fallback on any error
    return 'en-US';
  }
}
