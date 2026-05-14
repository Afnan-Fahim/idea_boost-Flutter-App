import 'dart:convert';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

/// Resolves idea [niche] / [format] / [level] strings stored on history &
/// favorites (which may be English slugs or a previous locale’s labels) into
/// labels for the **currently selected app language**, using bundled JSON
/// (ideas / youth / seasonal) paired by index with English.
class IdeaAttributeLabels {
  IdeaAttributeLabels._();
  static final IdeaAttributeLabels instance = IdeaAttributeLabels._();

  static const List<String> _datasets = ['ideas', 'youth', 'seasonal'];

  /// Languages with at least one localized ideas file in assets (except en).
  static const List<String> _langsForSlugMap = [
    'ar',
    'de',
    'es',
    'fr',
    'hi',
    'id',
    'ms',
    'pt',
    'ru',
    'uz',
    'vi',
  ]; // paired with en to map any localized stored value → English slug

  bool _slugsReady = false;
  String? _displayLang;

  final Map<String, String> _nicheRawToSlug = {};
  final Map<String, String> _formatRawToSlug = {};
  final Map<String, String> _levelRawToSlug = {};

  final Map<String, String> _nicheSlugToLabel = {};
  final Map<String, String> _formatSlugToLabel = {};
  final Map<String, String> _levelSlugToLabel = {};

  Future<List<dynamic>?> _loadList(String path) async {
    try {
      final s = await rootBundle.loadString(path);
      final d = json.decode(s);
      if (d is List<dynamic>) return d;
    } catch (_) {}
    return null;
  }

  void _mergeRawToSlug(List<dynamic> en, List<dynamic> loc) {
    final n = min(en.length, loc.length);
    for (var i = 0; i < n; i++) {
      final enM = en[i] as Map<String, dynamic>;
      final locM = loc[i] as Map<String, dynamic>;

      final enNiche = enM['niche'] as String?;
      final enFormat = enM['format'] as String?;
      final enLevel = enM['level'] as String?;

      if (enNiche != null && enNiche.isNotEmpty) {
        _nicheRawToSlug[enNiche] = enNiche;
        final v = locM['niche'] as String?;
        if (v != null && v.isNotEmpty) _nicheRawToSlug[v] = enNiche;
      }
      if (enFormat != null && enFormat.isNotEmpty) {
        _formatRawToSlug[enFormat] = enFormat;
        final v = locM['format'] as String?;
        if (v != null && v.isNotEmpty) _formatRawToSlug[v] = enFormat;
      }
      if (enLevel != null && enLevel.isNotEmpty) {
        _levelRawToSlug[enLevel] = enLevel;
        final v = locM['level'] as String?;
        if (v != null && v.isNotEmpty) _levelRawToSlug[v] = enLevel;
      }
    }
  }

  void _mergeSlugToLabel(List<dynamic> en, List<dynamic> loc) {
    final n = min(en.length, loc.length);
    for (var i = 0; i < n; i++) {
      final enM = en[i] as Map<String, dynamic>;
      final locM = loc[i] as Map<String, dynamic>;

      final slugN = enM['niche'] as String?;
      final slugF = enM['format'] as String?;
      final slugL = enM['level'] as String?;

      if (slugN != null && slugN.isNotEmpty) {
        final lab = locM['niche'] as String?;
        if (lab != null && lab.isNotEmpty) _nicheSlugToLabel[slugN] = lab;
      }
      if (slugF != null && slugF.isNotEmpty) {
        final lab = locM['format'] as String?;
        if (lab != null && lab.isNotEmpty) _formatSlugToLabel[slugF] = lab;
      }
      if (slugL != null && slugL.isNotEmpty) {
        final lab = locM['level'] as String?;
        if (lab != null && lab.isNotEmpty) _levelSlugToLabel[slugL] = lab;
      }
    }
  }

  /// Build raw value → English slug maps using en + every bundled language.
  Future<void> ensureSlugsLoaded() async {
    if (_slugsReady) return;

    for (final d in _datasets) {
      final en = await _loadList('assets/${d}_en.json');
      if (en == null) continue;
      for (final lang in _langsForSlugMap) {
        final loc = await _loadList('assets/${d}_$lang.json');
        if (loc == null) continue;
        _mergeRawToSlug(en, loc);
      }
    }
    _slugsReady = true;
  }

  /// Fill slug → label for [languageCode] (falls back to English file).
  Future<void> setDisplayLocale(String languageCode) async {
    await ensureSlugsLoaded();
    if (_displayLang == languageCode) return;

    _nicheSlugToLabel.clear();
    _formatSlugToLabel.clear();
    _levelSlugToLabel.clear();

    for (final d in _datasets) {
      final en = await _loadList('assets/${d}_en.json');
      if (en == null) continue;
      var loc = await _loadList('assets/${d}_$languageCode.json');
      loc ??= en;
      _mergeSlugToLabel(en, loc);
    }
    _displayLang = languageCode;
  }

  String labelNiche(String stored) {
    final slug = _nicheRawToSlug[stored] ?? stored;
    return _nicheSlugToLabel[slug] ?? stored;
  }

  String labelFormat(String stored) {
    final slug = _formatRawToSlug[stored] ?? stored;
    return _formatSlugToLabel[slug] ?? stored;
  }

  String labelLevel(String stored) {
    if (stored.trim() == "Expert (AI Enhanced)") {
      return 'idea_details.expert_ai_enhanced'.tr();
    }
    if (stored.trim() == "Pro (AI Enhanced)") {
      return 'idea_details.pro_ai_enhanced'.tr();
    }
    final slug = _levelRawToSlug[stored] ?? stored;
    return _levelSlugToLabel[slug] ?? stored;
  }
}
