// lib/core/constants/locale_config.dart
//
// ┌─────────────────────────────────────────────────────────┐
// │  GLOBAL LANGUAGES TOGGLE                                │
// │                                                         │
// │  true  → All 9 languages (en, ru, uz + es, pt, ar,      │
// │          hi, fr, de)                                    │
// │  false → Only 3 original languages (en, ru, uz)         │
// └─────────────────────────────────────────────────────────┘
import 'package:flutter/material.dart';

const bool enableExtendedLanguages = true;

// ── Base locales (always active) ──
const List<Locale> _baseLocales = [
  Locale('en'), // English
  Locale('ru'), // Russian
  Locale('uz'), // Uzbek
];

// ── Extended locales (only when toggle = true) ──
const List<Locale> _extendedLocales = [
  Locale('es'), // Spanish
  Locale('pt'), // Portuguese
  Locale('ar'), // Arabic
  Locale('hi'), // Hindi
  Locale('fr'), // French
  Locale('de'), // German
  Locale('vi'), // Vietnamese
  Locale('id'), // Indonesian
  Locale('ms'), // Malay
];

/// Returns the list of supported locales based on the toggle.
/// 🚀 PERF: Cached — computed once, reused on every access.
final List<Locale> supportedAppLocales = enableExtendedLanguages
    ? [..._baseLocales, ..._extendedLocales]
    : [..._baseLocales];

/// Language display names (used in UI pickers).
/// Keys match the language code strings.
const Map<String, String> languageNativeNames = {
  'en': '🇬🇧  English',
  'ru': '🇷🇺  Русский',
  'uz': '🇺🇿  O\'zbekcha',
  'es': '🇪🇸  Español',
  'pt': '🇧🇷  Português',
  'ar': '🇸🇦  العربية',
  'hi': '🇮🇳  Hindi / Urdu',
  'fr': '🇫🇷  Français',
  'de': '🇩🇪  Deutsch',
  'vi': '🇻🇳  Tiếng Việt',
  'id': '🇮🇩  Bahasa Indonesia',
  'ms': '🇲🇾  Bahasa Melayu',
};

/// Returns only the language codes that are currently enabled.
/// 🚀 PERF: Cached — computed once, reused on every access.
final List<String> supportedLangCodes = supportedAppLocales
    .map((l) => l.languageCode)
    .toList();

/// Returns display-name entries for the currently enabled languages.
/// 🚀 PERF: Cached — computed once, reused on every access.
final Map<String, String> activeLangNames = {
  for (final code in supportedLangCodes)
    if (languageNativeNames.containsKey(code)) code: languageNativeNames[code]!,
};
