import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';

class FavoritesViewModel extends ChangeNotifier {
  final FavoritesRepository _repository;

  FavoritesViewModel(this._repository);

  // Expose repository for screen access
  FavoritesRepository get repository => _repository;

  bool isLoading = false;
  String error = '';
  List<Map<String, dynamic>> favorites = [];

  StreamSubscription<FavoritesChangeEvent>? _changeSubscription;

  FavoritesViewModel(this._repository) {
    _changeSubscription = FavoritesRepository.onChange.listen(_handleFavoritesChange);
  }

  void _handleFavoritesChange(FavoritesChangeEvent event) {
    if (event.isDeleted) {
      final index = favorites.indexWhere(
        (item) => item['id'] == event.itemId || item['itemId'] == event.itemId,
      );
      if (index != -1) {
        favorites.removeAt(index);
        _invalidateFilterCache();
        notifyListeners();
      }
    } else {
      final exists = favorites.any(
        (item) => item['id'] == event.itemId || item['itemId'] == event.itemId,
      );
      if (!exists) {
        _repository.getFavoriteItem(event.type, event.itemId).then((item) {
          if (item != null) {
            final stillExists = favorites.any(
              (i) => i['id'] == event.itemId || i['itemId'] == event.itemId,
            );
            if (!stillExists) {
              favorites.add({...item, 'type': event.type});
              favorites.sort((a, b) {
                final aTime = a['savedAt'];
                final bTime = b['savedAt'];
                DateTime aDate = aTime.runtimeType.toString().contains('Timestamp')
                    ? aTime.toDate()
                    : DateTime.tryParse(aTime.toString()) ?? DateTime.now();
                DateTime bDate = bTime.runtimeType.toString().contains('Timestamp')
                    ? bTime.toDate()
                    : DateTime.tryParse(bTime.toString()) ?? DateTime.now();
                return bDate.compareTo(aDate);
              });
              _invalidateFilterCache();
              notifyListeners();
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    _filterCacheInvalidationTimer?.cancel();
    super.dispose();
  }

  // OPTIMIZED CACHING
  Map<String, Set<String>>? _cachedAvailableFilters;
  DateTime? _filtersCacheTime;
  static const Duration _filtersCacheDuration = Duration(seconds: 5);
  Timer? _filterCacheInvalidationTimer;

  int get favoritesCount => favorites.length;

  void _invalidateFilterCache() {
    _cachedAvailableFilters = null;
    _filterCacheInvalidationTimer?.cancel();
  }

  /// Load favorites for the selected types
  Future<void> loadFavorites({List<String>? types}) async {
    if (types == null || types.isEmpty) {
      favorites = [];
      notifyListeners();
      return;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final List<Map<String, dynamic>> allFavorites = [];

      for (var type in types) {
        final items = await _repository.getFavorites(type);
        allFavorites.addAll(items.map((e) => {...e, 'type': type}));
      }

      // Sort by savedAt descending
      allFavorites.sort((a, b) {
        final aTime = a['savedAt'];
        final bTime = b['savedAt'];

        DateTime aDate;
        DateTime bDate;

        if (aTime.runtimeType.toString().contains('Timestamp')) {
          aDate = aTime.toDate();
        } else {
          aDate = DateTime.tryParse(aTime.toString()) ?? DateTime.now();
        }

        if (bTime.runtimeType.toString().contains('Timestamp')) {
          bDate = bTime.toDate();
        } else {
          bDate = DateTime.tryParse(bTime.toString()) ?? DateTime.now();
        }

        return bDate.compareTo(aDate);
      });

      favorites = allFavorites;
    } catch (e) {
      debugPrint('FavoritesViewModel load error: $e');
      error = 'errors.failed_load_favorites'.tr();
      favorites = [];
    } finally {
      isLoading = false;
      _invalidateFilterCache(); // Clear cache when data loads
      notifyListeners();
    }
  }

  /// Get cached available filters
  Map<String, Set<String>> getAvailableFilters() {
    // Return cached if still valid
    if (_cachedAvailableFilters != null && _filtersCacheTime != null) {
      if (DateTime.now().difference(_filtersCacheTime!).inSeconds <
          _filtersCacheDuration.inSeconds) {
        return _cachedAvailableFilters!;
      }
    }

    // Build filter cache
    final niches = <String>{};
    final formats = <String>{};
    final levels = <String>{};

    for (final item in favorites) {
      final type = item['type'] as String? ?? '';
      if (type.contains('script') ||
          type.contains('ai_refined') ||
          type.contains('idea_details') ||
          type.contains('youth_ideas') ||
          type.contains('seasonal_ideas')) {
        try {
          String? niche, format, level;

          if (type == 'idea_details' ||
              type == 'youth_ideas' ||
              type == 'seasonal_ideas') {
            final content = item['content'] as Map<String, dynamic>? ?? {};
            niche = content['niche'] as String?;
            format = content['format'] as String?;
            level = content['level'] as String?;
          } else {
            final groups = (item['groups'] as List<dynamic>?) ?? [];
            if (groups.isNotEmpty) {
              final firstGroup = groups[0] as Map<String, dynamic>? ?? {};
              if (firstGroup.containsKey('idea')) {
                final ideaMap =
                    firstGroup['idea'] as Map<String, dynamic>? ?? {};
                niche = ideaMap['niche'] as String?;
                format = ideaMap['format'] as String?;
                level = ideaMap['level'] as String?;
              }
            }
          }

          if (niche != null) niches.add(niche);
          if (format != null) formats.add(format);
          if (level != null) levels.add(level);
        } catch (_) {}
      }
    }

    _cachedAvailableFilters = {
      'niches': niches,
      'formats': formats,
      'levels': levels,
    };
    _filtersCacheTime = DateTime.now();

    return _cachedAvailableFilters!;
  }

  /// ULTRA-OPTIMIZED: Complete filtering in single pass
  List<Map<String, dynamic>> getFullyFilteredFavorites({
    required String selectedType,
    required String searchQuery,
    String? selectedNiche,
    String? selectedFormat,
    String? selectedLevel,
  }) {
    var filtered = favorites;

    // Single-pass multi-criteria filtering
    if (selectedType != 'All' ||
        searchQuery.isNotEmpty ||
        selectedNiche != null ||
        selectedFormat != null ||
        selectedLevel != null) {
      final lowerSearchQuery = searchQuery.toLowerCase();

      filtered = filtered.where((item) {
        final type = item['type'] as String? ?? '';

        // Type filter
        if (selectedType != 'All' && !type.contains(selectedType)) {
          return false;
        }

        // Search filter
        if (searchQuery.isNotEmpty) {
          final title = (item['title'] as String? ?? '').toLowerCase();
          final content = item['content'].toString().toLowerCase();
          if (!title.contains(lowerSearchQuery) &&
              !content.contains(lowerSearchQuery)) {
            return false;
          }
        }

        // Attribute filters
        if (selectedNiche != null ||
            selectedFormat != null ||
            selectedLevel != null) {
          if (!type.contains('script') &&
              !type.contains('ai_refined') &&
              !type.contains('idea_details') &&
              !type.contains('youth_ideas') &&
              !type.contains('seasonal_ideas')) {
            return false;
          }

          try {
            String? niche, format, level;

            if (type == 'idea_details' ||
                type == 'youth_ideas' ||
                type == 'seasonal_ideas') {
              final content = item['content'] as Map<String, dynamic>? ?? {};
              niche = content['niche'] as String?;
              format = content['format'] as String?;
              level = content['level'] as String?;
            } else {
              final groups = (item['groups'] as List<dynamic>?) ?? [];
              if (groups.isEmpty) return false;

              final firstGroup = groups[0] as Map<String, dynamic>? ?? {};
              if (firstGroup.containsKey('idea')) {
                final ideaMap =
                    firstGroup['idea'] as Map<String, dynamic>? ?? {};
                niche = ideaMap['niche'] as String?;
                format = ideaMap['format'] as String?;
                level = ideaMap['level'] as String?;
              }
            }

            if (selectedNiche != null && niche != selectedNiche) return false;
            if (selectedFormat != null && format != selectedFormat)
              return false;
            if (selectedLevel != null && level != selectedLevel) return false;
          } catch (_) {
            return false;
          }
        }

        return true;
      }).toList();
    }

    return filtered;
  }

  /// Remove a favorite item with undo support (3-second window)
  void removeFromFavoritesWithUndo(
    String type,
    String itemId,
    VoidCallback onUndoExpired,
  ) {
    // Find item first
    final itemIndex = favorites.indexWhere(
      (item) => item['id'] == itemId || item['itemId'] == itemId,
    );

    if (itemIndex == -1) return;

    // Remove from UI immediately (with animation)
    favorites.removeAt(itemIndex);
    _invalidateFilterCache();
    notifyListeners();

    // Delegate to repository
    _repository.removeFromFavoritesWithUndo(
      type: type,
      itemId: itemId,
      onUndoExpired: onUndoExpired,
    );
  }

  /// Restore a deleted item within undo window
  bool restoreFromFavorites(String itemId) {
    final restoredItem = _repository.restoreFromFavorites(itemId);
    if (restoredItem == null) return false;

    // Add back to VM list
    favorites.add(restoredItem);

    // Re-sort
    favorites.sort((a, b) {
      final aTime = a['savedAt'];
      final bTime = b['savedAt'];
      DateTime aDate = aTime.runtimeType.toString().contains('Timestamp')
          ? aTime.toDate()
          : DateTime.tryParse(aTime.toString()) ?? DateTime.now();
      DateTime bDate = bTime.runtimeType.toString().contains('Timestamp')
          ? bTime.toDate()
          : DateTime.tryParse(bTime.toString()) ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    _invalidateFilterCache();
    notifyListeners();
    return true;
  }

  /// Remove a favorite item (old method - without undo)
  Future<void> removeFromFavorites(String type, String itemId) async {
    try {
      await _repository.removeFromFavorites(type, itemId);
      favorites.removeWhere(
        (item) => item['id'] == itemId || item['itemId'] == itemId,
      );
      _invalidateFilterCache();
      error = '';
      notifyListeners();
    } catch (e) {
      debugPrint('FavoritesViewModel remove error: $e');
      error = 'errors.failed_to_remove'.tr();
      notifyListeners();
      rethrow;
    }
  }

  /// Clear all favorites for a type
  Future<void> clearAllFavorites(String type) async {
    try {
      await _repository.clearAllFavorites(type);
      favorites.removeWhere((item) => item['type'] == type);
      _invalidateFilterCache();
      error = '';
      notifyListeners();
    } catch (e) {
      debugPrint('FavoritesViewModel clear error: $e');
      error = 'errors.failed_clear_favorites'.tr();
      notifyListeners();
    }
  }

  /// Search within current favorites
  List<Map<String, dynamic>> searchFavorites(String query) {
    if (query.isEmpty) return favorites;
    final q = query.toLowerCase();
    return favorites
        .where(
          (item) =>
              (item['title'] as String? ?? '').toLowerCase().contains(q) ||
              (item['content'].toString().toLowerCase().contains(q)),
        )
        .toList();
  }
}
