// lib/modules/ideas_list/view_model/ideas_list_view_model.dart
import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import '../../../main.dart';

class IdeasListViewModel extends ChangeNotifier {
  final String dataset;
  List<IdeaModel> ideas = [];
  List<IdeaModel> filteredIdeas = [];
  String? selectedNiche;
  String? selectedFormat;
  String? selectedLevel;
  Set<String> niches = {};
  Set<String> formats = {};
  Set<String> levels = {};
  bool isLoading = true;
  String? errorMessage;
  String _searchQueryCache = '';
  Timer? _filterDebounceTimer;

  IdeasListViewModel({this.dataset = 'ideas'}) {
    loadIdeas();
  }

  // Add this method to allow reloading when language changes
  Future<void> reloadIdeas({String? language}) async {
    await loadIdeas(language: language);
  }

  Future<void> loadIdeas({String? language}) async {
    try {
      isLoading = true;
      notifyListeners();

      String fileName;

      // Use provided language or detect from context - default to 'en' if unavailable
      final lang = language ?? _getCurrentLanguage();

      // Load language-specific files for all datasets
      if (dataset == 'youth') {
        fileName = 'assets/youth_$lang.json';
      } else if (dataset == 'seasonal') {
        fileName = 'assets/seasonal_$lang.json';
      } else {
        fileName = 'assets/ideas_$lang.json';
      }

      // Fallback to English if translation file doesn't exist
      try {
        await rootBundle.loadString(fileName);
      } catch (_) {
        fileName = 'assets/${dataset}_en.json';
        try {
          await rootBundle.loadString(fileName);
        } catch (_) {
          fileName = 'assets/ideas_en.json'; // Final fallback
        }
      }

      final String jsonString = await rootBundle.loadString(fileName);

      // 🚀 PERF: Parse JSON in separate isolate to avoid blocking main thread
      final List<dynamic> jsonList = await compute(_parseJson, jsonString);

      // Add dataset field to each idea based on the current dataset being loaded
      ideas = jsonList.map((json) {
        final jsonWithDataset = {
          ...json as Map<String, dynamic>,
          'dataset': dataset,
        };
        return IdeaModel.fromJson(jsonWithDataset);
      }).toList();

      filteredIdeas = List.from(ideas);

      niches = ideas.map((idea) => idea.niche).toSet();
      formats = ideas.map((idea) => idea.format).toSet();
      levels = ideas.map((idea) => idea.level).toSet();

      errorMessage = null;
    } catch (e) {
      errorMessage = 'errors.something_went_wrong_try_again'.tr();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void updateNiche(String? value) {
    selectedNiche = value;
    _debouncedApplyFilters();
  }

  void updateFormat(String? value) {
    selectedFormat = value;
    _debouncedApplyFilters();
  }

  void updateLevel(String? value) {
    selectedLevel = value;
    _debouncedApplyFilters();
  }

  void searchIdeas(String query) {
    _searchQueryCache = query.toLowerCase();
    _debouncedApplyFilters();
  }

  // 🚀 PERF: Debounce filter updates to prevent excessive rebuilds
  void _debouncedApplyFilters() {
    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(
      const Duration(milliseconds: 100),
      _applyFilters,
    );
  }

  void _applyFilters() {
    if (_searchQueryCache.isEmpty) {
      filteredIdeas = ideas.where(_matchesFilters).toList();
    } else {
      filteredIdeas = ideas.where((idea) {
        final matchesQuery =
            idea.title.toLowerCase().contains(_searchQueryCache) ||
            idea.description.toLowerCase().contains(_searchQueryCache);
        return matchesQuery && _matchesFilters(idea);
      }).toList();
    }
    notifyListeners();
  }

  bool _matchesFilters(IdeaModel idea) {
    final matchesNiche = selectedNiche == null || idea.niche == selectedNiche;
    final matchesFormat =
        selectedFormat == null || idea.format == selectedFormat;
    final matchesLevel = selectedLevel == null || idea.level == selectedLevel;
    return matchesNiche && matchesFormat && matchesLevel;
  }

  String _getCurrentLanguage() {
    try {
      final context = navigatorKey.currentContext;
      if (context != null) {
        final localization = EasyLocalization.of(context);
        if (localization != null) {
          final langCode = localization.locale.languageCode;
          // 🚀 DEBUG: Log language detection
          debugPrint('IdeasListViewModel: Detected language = $langCode');
          return langCode;
        }
      }
    } catch (e) {
      debugPrint('IdeasListViewModel: Error detecting language = $e');
    }
    debugPrint('IdeasListViewModel: Falling back to English (en)');
    return 'en';
  }

  @override
  void dispose() {
    _filterDebounceTimer?.cancel();
    super.dispose();
  }
}

// 🚀 PERF: Top-level function for compute() - parses JSON in background isolate
List<dynamic> _parseJson(String jsonString) {
  return json.decode(jsonString) as List<dynamic>;
}
