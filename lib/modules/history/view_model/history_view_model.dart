import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repository/history_repository.dart';
import '../model/history_item_model.dart';

enum DateFilter { all, today, week, month }

class HistoryViewModel extends ChangeNotifier {
  final HistoryRepository _repo = HistoryRepository();

  List<HistoryItem> _items = [];
  List<HistoryItem> get items => _items;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _typeFilter;
  String? get typeFilter => _typeFilter;

  DateFilter _dateFilter = DateFilter.all;
  DateFilter get dateFilter => _dateFilter;

  final Set<String> _selected = {};
  Set<String> get selected => _selected;

  StreamSubscription<List<HistoryItem>>? _sub;

  // Undo system: store deleted items temporarily
  final Map<String, HistoryItem> _deletedItems = {};
  final Map<String, Timer> _deletionTimers = {};

  // OPTIMIZED CACHING SYSTEM
  // ========================

  // Multi-level cache with fingerprinting
  Map<String, List<HistoryItem>> _multiLevelCache = {};
  String? _lastDataFingerprint;

  // Available filters cache
  Map<String, Set<String>>? _cachedAvailableFilters;
  DateTime? _filtersCacheTime;
  static const Duration _filtersCacheDuration = Duration(seconds: 5);

  // Debounce timers
  Timer? _filterDebounceTimer;
  Timer? _filterCacheInvalidationTimer;

  /// Generate cache key from filter state
  String _generateCacheKey(String? typeFilter, DateFilter dateFilter) {
    return '$typeFilter#${dateFilter.name}';
  }

  /// Generate fingerprint of current data
  String _generateDataFingerprint() {
    if (_items.isEmpty) return 'empty';
    return '${_items.length}#${_items.first.id}#${_items.last.generatedAt.millisecondsSinceEpoch}';
  }

  void init({String? type}) {
    _typeFilter = type;
    _isLoading = true;
    _multiLevelCache.clear();
    _lastDataFingerprint = null;
    notifyListeners();
    _sub?.cancel();
    _sub = _repo
        .getLogsStream(type: _typeFilter)
        .listen(
          (list) {
            _items = list;
            _isLoading = false;

            // Only invalidate cache if data actually changed
            final newFingerprint = _generateDataFingerprint();
            if (_lastDataFingerprint != newFingerprint) {
              _lastDataFingerprint = newFingerprint;
              _multiLevelCache.clear();
              _invalidateFilterCache();
            }
            notifyListeners();
          },
          onError: (error) {
            debugPrint('Error loading history: $error');
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  void disposeViewModel() {
    _sub?.cancel();
    _filterDebounceTimer?.cancel();
    _filterCacheInvalidationTimer?.cancel();
    for (var timer in _deletionTimers.values) {
      timer.cancel();
    }
  }

  void setTypeFilter(String? type) {
    _typeFilter = type;
    init(type: _typeFilter);
  }

  void setDateFilter(DateFilter f) {
    if (f == _dateFilter) return;
    _dateFilter = f;
    _multiLevelCache.clear();

    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      notifyListeners();
    });
  }

  void _invalidateFilterCache() {
    _cachedAvailableFilters = null;
    _filterCacheInvalidationTimer?.cancel();
  }

  /// Select all currently visible (filtered) items
  void selectAllVisible() {
    final ids = filteredItems().map((e) => e.id);
    _selected.addAll(ids);
    notifyListeners();
  }

  /// Clear all history documents from backend
  Future<void> clearAll() async {
    await _repo.clearAll();
    _items = [];
    _selected.clear();
    _multiLevelCache.clear();
    _lastDataFingerprint = null;
    notifyListeners();
  }

  /// HIGH-PERFORMANCE: Optimized filtered items with multi-level caching
  List<HistoryItem> filteredItems() {
    // Generate cache key
    final cacheKey = _generateCacheKey(_typeFilter, _dateFilter);

    // Return cached result if available
    if (_multiLevelCache.containsKey(cacheKey)) {
      return _multiLevelCache[cacheKey]!;
    }

    // Apply date filter (fast path)
    final filtered = _applyDateFilter(_items);

    // Cache and return
    _multiLevelCache[cacheKey] = filtered;
    return filtered;
  }

  /// Fast date filtering with optimized logic
  List<HistoryItem> _applyDateFilter(List<HistoryItem> items) {
    if (_dateFilter == DateFilter.all) return items;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return items.where((it) {
      final itemDate = DateTime(
        it.generatedAt.year,
        it.generatedAt.month,
        it.generatedAt.day,
      );

      switch (_dateFilter) {
        case DateFilter.today:
          return itemDate == today;
        case DateFilter.week:
          return it.generatedAt.isAfter(now.subtract(Duration(days: 7)));
        case DateFilter.month:
          return it.generatedAt.isAfter(
            DateTime(now.year, now.month - 1, now.day),
          );
        case DateFilter.all:
          return true;
      }
    }).toList();
  }

  /// Get cached available filters for the current filtered set
  Map<String, Set<String>> getAvailableFilters() {
    // Return cached if still valid
    if (_cachedAvailableFilters != null && _filtersCacheTime != null) {
      if (DateTime.now().difference(_filtersCacheTime!).inSeconds <
          _filtersCacheDuration.inSeconds) {
        return _cachedAvailableFilters!;
      }
    }

    // Build filter cache from filtered items
    final filtered = filteredItems();
    final niches = <String>{};
    final formats = <String>{};
    final levels = <String>{};

    // Only iterate once through filtered data
    for (final item in filtered) {
      if (item.type.contains('script') ||
          item.type.contains('ai_refined') ||
          item.type.contains('idea_details') ||
          item.type.contains('youth_ideas') ||
          item.type.contains('seasonal_ideas')) {
        if (item.meta.containsKey('idea')) {
          try {
            final ideaMap = item.meta['idea'] as Map<String, dynamic>;
            final n = ideaMap['niche'] as String?;
            final f = ideaMap['format'] as String?;
            final l = ideaMap['level'] as String?;

            if (n != null && n.isNotEmpty) niches.add(n);
            if (f != null && f.isNotEmpty) formats.add(f);
            if (l != null && l.isNotEmpty) levels.add(l);
          } catch (_) {}
        }
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

  /// ULTRA-OPTIMIZED: Complete filtering with all criteria in ONE pass
  /// This is called by the UI only once per render cycle
  List<HistoryItem> getFullyFilteredItems({
    required String selectedType,
    required String searchQuery,
    String? selectedNiche,
    String? selectedFormat,
    String? selectedLevel,
  }) {
    // Start with date-filtered items (already cached from filteredItems())
    var filtered = filteredItems();

    // Single-pass filtering combining all criteria
    if (selectedType != 'All' ||
        searchQuery.isNotEmpty ||
        selectedNiche != null ||
        selectedFormat != null ||
        selectedLevel != null) {
      final lowerSearchQuery = searchQuery.toLowerCase();

      filtered = filtered.where((item) {
        // Type filter
        if (selectedType != 'All' &&
            !item.type.toLowerCase().contains(selectedType.toLowerCase())) {
          return false;
        }

        // Search filter
        if (searchQuery.isNotEmpty &&
            !item.prompt.toLowerCase().contains(lowerSearchQuery) &&
            !item.type.toLowerCase().contains(lowerSearchQuery)) {
          return false;
        }

        // Attribute filters (only for types that support them)
        if (selectedNiche != null ||
            selectedFormat != null ||
            selectedLevel != null) {
          if (!item.type.contains('script') &&
              !item.type.contains('ai_refined') &&
              !item.type.contains('idea_details') &&
              !item.type.contains('youth_ideas') &&
              !item.type.contains('seasonal_ideas')) {
            return false;
          }

          if (!item.meta.containsKey('idea')) return false;

          try {
            final ideaMap = item.meta['idea'] as Map<String, dynamic>;
            final niche = ideaMap['niche'] as String?;
            final format = ideaMap['format'] as String?;
            final level = ideaMap['level'] as String?;

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

  String formatDate(DateTime d) => DateFormat('yyyy-MM-dd – kk:mm').format(d);

  void toggleSelect(String id) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      _selected.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  bool anySelected() => _selected.isNotEmpty;

  Future<void> deleteSelected() async {
    final ids = _selected.toList();
    _selected.clear();

    // Remove from UI immediately
    _items.removeWhere((item) => ids.contains(item.id));
    _multiLevelCache.clear();
    _invalidateFilterCache();
    notifyListeners();

    // Delete in background
    Timer(const Duration(seconds: 3), () async {
      try {
        await _repo.removeMany(ids);
      } catch (e) {
        debugPrint('History background delete error: $e');
      }
    });
  }

  /// Delete one item with undo support (3-second window)
  void deleteOneWithUndo(String id, Function? onUndoExpired) {
    final itemIndex = _items.indexWhere((item) => item.id == id);
    if (itemIndex == -1) return;

    final deletedItem = _items[itemIndex];

    // Cancel any existing timer for this item
    _deletionTimers[id]?.cancel();

    // Store for potential undo
    _deletedItems[id] = deletedItem;

    // Remove from UI immediately
    _items.removeAt(itemIndex);
    _multiLevelCache.clear();
    _invalidateFilterCache();
    _selected.remove(id);
    notifyListeners();

    // 3-second undo window - then permanently delete
    _deletionTimers[id] = Timer(const Duration(seconds: 3), () async {
      if (_deletedItems.containsKey(id)) {
        _deletedItems.remove(id);
        _deletionTimers.remove(id);

        // Permanently delete from backend in background
        try {
          await _repo.removeLog(id);
          onUndoExpired?.call();
        } catch (e) {
          debugPrint('History background delete error: $e');
        }
      }
    });
  }

  /// Restore a deleted item within undo window
  bool restoreFromDelete(String id) {
    if (!_deletedItems.containsKey(id)) return false;

    final item = _deletedItems[id]!;
    _items.add(item);

    _deletedItems.remove(id);
    _deletionTimers[id]?.cancel();
    _deletionTimers.remove(id);
    _multiLevelCache.clear();
    _invalidateFilterCache();

    notifyListeners();
    return true;
  }

  /// Old delete method (without undo)
  Future<void> deleteOne(String id) async {
    await _repo.removeLog(id);
    _selected.remove(id);
  }
}
