import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:ideaboost/data/repository/favorite_save_outcome.dart';

export 'package:ideaboost/data/repository/favorite_save_outcome.dart';

/// Result of adding to favorites
enum SaveFavoriteResult {
  /// Successfully saved new favorite
  saved,

  /// Item already exists in favorites (duplicate prevented)
  alreadyExists,

  /// Timestamp updated for existing favorite
  updated,
}

class FavoritesChangeEvent {
  final String type;
  final String itemId;
  final String? inputHash;
  final bool isDeleted;

  FavoritesChangeEvent({
    required this.type,
    required this.itemId,
    this.inputHash,
    required this.isDeleted,
  });
}

class FavoritesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final Map<String, List<Map<String, dynamic>>> _favoritesCache = {};
  static final Map<String, DateTime> _favoritesLastFetch = {};

  static final StreamController<FavoritesChangeEvent> _changeController =
      StreamController<FavoritesChangeEvent>.broadcast();

  static Stream<FavoritesChangeEvent> get onChange => _changeController.stream;

  static final Map<String, Map<String, dynamic>> _pendingDeletedItems = {};
  static final Map<String, Timer> _pendingTimers = {};

  static void clearCache() {
    _favoritesCache.clear();
    _favoritesLastFetch.clear();
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _pendingDeletedItems.clear();
  }

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  /// Path: favorites/{uid}/types/{type}/items/{itemId}
  CollectionReference<Map<String, dynamic>> _itemsRef(String type) {
    if (_currentUserId.isEmpty) {
      throw Exception('User not authenticated');
    }

    // favorites (collection) / {uid} (doc) / types (collection) / {type} (doc) / items (collection)
    return _firestore
        .collection('favorites')
        .doc(_currentUserId)
        .collection('types')
        .doc(type)
        .collection('items');
  }

  /// Generates a unique hash based on input/prompt, tones, and type.
  /// This ensures the same prompt won't be saved twice WITH THE SAME TONES.
  /// But allows saving the same input with different tones/regenerations.
  String generateInputHash({
    required String type,
    required String input,
    List<String>? tones,
  }) {
    // Normalize the input (trim and lowercase for consistent matching)
    final normalizedInput = input.trim().toLowerCase();
    // If tones provided, include them in the hash to differentiate regenerations
    final tonesPart = tones != null && tones.isNotEmpty
        ? ':' + (List.from(tones)..sort()).join(',')
        : '';
    final hashInput = '$type:$normalizedInput$tonesPart';
    final bytes = utf8.encode(hashInput);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

    // Helper to retry Firestore operations with exponential backoff (max 3 attempts)
    Future<T> _runWithRetry<T>(Future<T> Function() operation) async {
      int attempts = 0;
      while (true) {
        try {
          return await operation();
        } catch (e) {
          attempts++;
          if (attempts >= 3) rethrow;
          // exponential backoff
          await Future.delayed(Duration(milliseconds: 200 * attempts * attempts));
        }
      }
    }

Future<String?> findExistingFavorite({
    required String type,
    required String inputHash,
  }) async {
    if (_favoritesCache.containsKey(type)) {
      final cachedList = _favoritesCache[type]!;
      for (final item in cachedList) {
        if (item['inputHash'] == inputHash) {
          return item['id'] ?? item['itemId'];
        }
      }
      return null;
    }

    final snapshot = await _itemsRef(
      type,
    ).where('inputHash', isEqualTo: inputHash).limit(1).get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.id;
    }
    return null;
  }

  // CORE - Now with duplicate detection based on INPUT/PROMPT
  /// [input] - The user's input/prompt text used for duplicate detection.
  /// Duplicates are detected by hashing the input text + type.
  Future<FavoriteSaveOutcome> addToFavorites({
    required String type,
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required List<dynamic> groups,
    required String generatedAt,
    required String input,
    List<String>? tones,
  }) async {
    // Generate hash based on INPUT + TONES for duplicate detection
    // This allows same input with different tones to be saved separately
    final inputHash = generateInputHash(type: type, input: input, tones: tones);

    // Check if this input/prompt was already saved
    final existingId = await findExistingFavorite(
      type: type,
      inputHash: inputHash,
    );

    final dataToSave = {
      'userId': _currentUserId,
      'title': title,
      'content': content,
      'inputHash': inputHash,
      'groups': groups,
      'generatedAt': generatedAt,
      'savedAt': FieldValue.serverTimestamp(),
    };

    if (existingId != null) {
      // Same prompt — refresh stored output and timestamp (do not block the user)
      final merged = {
        ...dataToSave,
        'itemId': existingId,
      };
    // Use retry helper for Firestore update (duplicate case)
    await _runWithRetry(() => _itemsRef(type).doc(existingId).set(merged, SetOptions(merge: true)));
      _upsertCacheEntry(
        type,
        existingId,
        {...merged, 'savedAt': Timestamp.now()},
      );

      _changeController.add(FavoritesChangeEvent(
        type: type,
        itemId: existingId,
        inputHash: inputHash,
        isDeleted: false,
      ));

      return FavoriteSaveOutcome(
        result: SaveFavoriteResult.updated,
        itemId: existingId,
      );
    }

    // New prompt - save with hash
    final newData = {
      ...dataToSave,
      'itemId': itemId,
    };

    // Use retry helper for Firestore set operation
    await _runWithRetry(() => _itemsRef(type).doc(itemId).set(newData));

    _upsertCacheEntry(
      type,
      itemId,
      {...newData, 'savedAt': Timestamp.now()},
    );

    _changeController.add(FavoritesChangeEvent(
      type: type,
      itemId: itemId,
      inputHash: inputHash,
      isDeleted: false,
    ));

    return FavoriteSaveOutcome(
      result: SaveFavoriteResult.saved,
      itemId: itemId,
    );
  }

  void _upsertCacheEntry(
    String type,
    String itemId,
    Map<String, dynamic> data,
  ) {
    if (!_favoritesCache.containsKey(type)) return;
    final list = _favoritesCache[type]!;
    list.removeWhere(
      (item) => item['id'] == itemId || item['itemId'] == itemId,
    );
    list.insert(0, {...data, 'id': itemId});
  }

  Future<void> removeFromFavorites(String type, String itemId) async {
    String? inputHash;
    if (_favoritesCache.containsKey(type)) {
      final list = _favoritesCache[type]!;
      final idx = list.indexWhere((item) => item['id'] == itemId || item['itemId'] == itemId);
      if (idx != -1) {
        inputHash = list[idx]['inputHash']?.toString();
      }
    }

    // Use retry helper for Firestore delete operation
    await _runWithRetry(() => _itemsRef(type).doc(itemId).delete());
    if (_favoritesCache.containsKey(type)) {
      _favoritesCache[type]!.removeWhere((item) => item['id'] == itemId || item['itemId'] == itemId);
    }

    _changeController.add(FavoritesChangeEvent(
      type: type,
      itemId: itemId,
      inputHash: inputHash,
      isDeleted: true,
    ));
  }

  /// Immediately removes item from cache and schedules database deletion.
  /// If the timer expires, it permanently deletes from Firestore.
  void removeFromFavoritesWithUndo({
    required String type,
    required String itemId,
    required VoidCallback onUndoExpired,
  }) {
    Map<String, dynamic>? deletedItem;
    if (_favoritesCache.containsKey(type)) {
      final list = _favoritesCache[type]!;
      final index = list.indexWhere((item) => item['id'] == itemId || item['itemId'] == itemId);
      if (index != -1) {
        deletedItem = list[index];
        list.removeAt(index);
      }
    }

    // Cancel any existing timer for this item
    _pendingTimers[itemId]?.cancel();

    if (deletedItem != null) {
      _pendingDeletedItems[itemId] = {...deletedItem, 'type': type};
    } else {
      _pendingDeletedItems[itemId] = {'id': itemId, 'type': type};
    }

    _changeController.add(FavoritesChangeEvent(
      type: type,
      itemId: itemId,
      inputHash: deletedItem?['inputHash']?.toString(),
      isDeleted: true,
    ));

    _pendingTimers[itemId] = Timer(const Duration(seconds: 3), () async {
      if (_pendingDeletedItems.containsKey(itemId)) {
        _pendingDeletedItems.remove(itemId);
        _pendingTimers.remove(itemId);

        try {
        // Use retry helper for Firestore delete operation
    await _runWithRetry(() => _itemsRef(type).doc(itemId).delete());
          onUndoExpired();
        } catch (e) {
          debugPrint('FavoritesRepository background delete error: $e');
        }
      }
    });
  }

  /// Restores a pending deleted item within undo window.
  Map<String, dynamic>? restoreFromFavorites(String itemId) {
    if (!_pendingDeletedItems.containsKey(itemId)) return null;

    final item = _pendingDeletedItems[itemId]!;
    final type = item['type'] as String;

    _pendingDeletedItems.remove(itemId);
    _pendingTimers[itemId]?.cancel();
    _pendingTimers.remove(itemId);

    // Re-insert into cache
    if (_favoritesCache.containsKey(type)) {
      final list = _favoritesCache[type]!;
      list.add(item);
      list.sort((a, b) {
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
    }

    _changeController.add(FavoritesChangeEvent(
      type: type,
      itemId: itemId,
      inputHash: item['inputHash']?.toString(),
      isDeleted: false,
    ));

    return item;
  }

  Stream<List<Map<String, dynamic>>> getFavoritesStream(String type) {
    return _itemsRef(type).orderBy('savedAt', descending: true).snapshots().map((s) {
      final items = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _favoritesCache[type] = List<Map<String, dynamic>>.from(items);
      _favoritesLastFetch[type] = DateTime.now();
      return items;
    });
  }

  Future<List<Map<String, dynamic>>> getFavorites(String type) async {
    if (_favoritesCache.containsKey(type)) {
      return List<Map<String, dynamic>>.from(_favoritesCache[type]!);
    }

    final s = await _itemsRef(type).orderBy('savedAt', descending: true).get();
    final results = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    _favoritesCache[type] = List<Map<String, dynamic>>.from(results);
    _favoritesLastFetch[type] = DateTime.now();
    return results;
  }

  Future<Map<String, dynamic>?> getFavoriteItem(
    String type,
    String itemId,
  ) async {
    if (_favoritesCache.containsKey(type)) {
      try {
        return _favoritesCache[type]!.firstWhere((item) => item['id'] == itemId || item['itemId'] == itemId);
      } catch (_) {
        return null;
      }
    }
    final d = await _itemsRef(type).doc(itemId).get();
    return d.exists ? {'id': d.id, ...d.data()!} : null;
  }

  Future<bool> isFavorited(String type, String itemId) async {
    if (_favoritesCache.containsKey(type)) {
      return _favoritesCache[type]!.any((item) => item['id'] == itemId || item['itemId'] == itemId);
    }
    final d = await _itemsRef(type).doc(itemId).get();
    return d.exists;
  }

  Future<void> clearAllFavorites(String type) async {
    // Use retry helper for batch delete in clearAllFavorites
    await _runWithRetry(() async {
      final s = await _itemsRef(type).get();
      final b = _firestore.batch();
      for (final doc in s.docs) {
        b.delete(doc.reference);
      }
      await b.commit();
    });
    _favoritesCache.remove(type);
    _favoritesLastFetch.remove(type);
  }

  Future<int> getFavoritesCount(String type) async {
    final agg = await _itemsRef(type).count().get();
    return agg.count ?? 0;
  }

  Future<List<Map<String, dynamic>>> getFavoritesWithPagination({
    required String type,
    required int limit,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _itemsRef(
      type,
    ).orderBy('savedAt', descending: true).limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final s = await q.get();
    return s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> searchFavorites(
    String type,
    String query,
  ) async {
    final s = await _itemsRef(type).get();
    final q = query.toLowerCase();
    return s.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((m) => ((m['title'] as String? ?? '').toLowerCase().contains(q)))
        .toList();
  }

  // Wrappers - Now return SaveFavoriteResult to handle duplicates based on input
  Future<FavoriteSaveOutcome> addCommentToFavorites({
    required String itemId,
    required String comment,
    required String input,
    List<Map<String, dynamic>> groups = const [],
  }) async {
    return await addToFavorites(
      type: 'comments',
      itemId: itemId,
      title: comment.length > 60 ? '${comment.substring(0, 60)}...' : comment,
      content: {'text': comment},
      groups: groups,
      generatedAt: DateTime.now().toIso8601String(),
      input: input,
    );
  }

  Future<FavoriteSaveOutcome> addScriptToFavorites({
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required List<Map<String, dynamic>> groups,
    required String generatedAt,
    required String input,
  }) async {
    return await addToFavorites(
      type: 'script',
      itemId: itemId,
      title: title,
      content: content,
      groups: groups,
      generatedAt: generatedAt,
      input: input,
    );
  }

  Future<FavoriteSaveOutcome> addAiRefinedScriptToFavorites({
    required String itemId,
    required String title,
    required String originalScript,
    required String refinedScript,
    String? dataset,
    String favoriteType = 'ai_refined',
    List<Map<String, dynamic>> groups = const [],
  }) async {
    return await addToFavorites(
      type: favoriteType,
      itemId: itemId,
      title: title,
      content: {
        'original': originalScript,
        'refined': refinedScript,
        if (dataset != null) 'dataset': dataset,
      },
      groups: groups,
      generatedAt: DateTime.now().toIso8601String(),
      input:
          originalScript, // Use original script as input for duplicate detection
    );
  }

  Future<FavoriteSaveOutcome> addIdeaDetailsToFavorites({
    required int id,
    required String title,
    required String description,
    required String niche,
    required String format,
    required String level,
    required List<String> steps,
    required String cta,
    required String timestamp,
    String? dataset,
    String favoriteType = 'idea_details',
    List<Map<String, dynamic>> groups = const [],
  }) async {
    return await addToFavorites(
      type: favoriteType,
      itemId: id.toString(),
      title: title,
      content: {
        'id': id,
        'title': title,
        'description': description,
        'niche': niche,
        'format': format,
        'level': level,
        'steps': steps,
        'cta': cta,
        'timestamp': timestamp,
        if (dataset != null) 'dataset': dataset,
      },
      groups: groups.isNotEmpty
          ? groups
          : [
              {
                'type': favoriteType,
                'generatedAt': timestamp,
                if (dataset != null) 'dataset': dataset,
              },
            ],
      generatedAt: timestamp,
      input: '$id:$title', // Use id+title as input for duplicate detection
    );
  }

  // Quick tools wrappers
  Future<FavoriteSaveOutcome> addHashtagToFavorites({
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required String input,
    List<Map<String, dynamic>> groups = const [],
    required String generatedAt,
  }) async {
    return await addToFavorites(
      type: 'hashtag',
      itemId: itemId,
      title: title,
      content: content,
      groups: groups,
      generatedAt: generatedAt,
      input: input,
    );
  }

  Future<FavoriteSaveOutcome> addShortIdeasToFavorites({
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required String input,
    List<Map<String, dynamic>> groups = const [],
    required String generatedAt,
  }) async {
    return await addToFavorites(
      type: 'shot_ideas',
      itemId: itemId,
      title: title,
      content: content,
      groups: groups,
      generatedAt: generatedAt,
      input: input,
    );
  }

  Future<FavoriteSaveOutcome> addViralRewriteToFavorites({
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required String input,
    List<Map<String, dynamic>> groups = const [],
    required String generatedAt,
  }) async {
    return await addToFavorites(
      type: 'viral_rewrite',
      itemId: itemId,
      title: title,
      content: content,
      groups: groups,
      generatedAt: generatedAt,
      input: input,
    );
  }
}
