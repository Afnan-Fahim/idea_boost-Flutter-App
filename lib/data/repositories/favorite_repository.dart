import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoritesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  /// Root reference:
  /// favorites/{uid}/types/{type}/items/{itemId}
  CollectionReference<Map<String, dynamic>> _itemsRef(String type) {
    if (_currentUserId.isEmpty) {
      throw Exception('User not authenticated');
    }

    return _firestore
        .collection('favorites')
        .doc(_currentUserId)
        .collection('types')
        .doc(type)
        .collection('items');
  }

  // ============================================================
  // CORE (DO NOT TOUCH)
  // ============================================================

  Future<void> addToFavorites({
    required String type,
    required String itemId,
    required String title,
    required Map<String, dynamic> content,
    required List<dynamic> groups,
    required String generatedAt,
  }) async {
    await _itemsRef(type).doc(itemId).set({
      'itemId': itemId,
      'userId': _currentUserId,
      'title': title,
      'content': content,
      'groups': groups,
      'generatedAt': generatedAt,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFromFavorites(String type, String itemId) async {
    await _itemsRef(type).doc(itemId).delete();
  }

  Stream<List<Map<String, dynamic>>> getFavoritesStream(String type) {
    return _itemsRef(type)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<List<Map<String, dynamic>>> getFavorites(String type) async {
    final s = await _itemsRef(type).orderBy('savedAt', descending: true).get();

    return s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<Map<String, dynamic>?> getFavoriteItem(
    String type,
    String itemId,
  ) async {
    final d = await _itemsRef(type).doc(itemId).get();
    return d.exists ? {'id': d.id, ...d.data()!} : null;
  }

  // ============================================================
  // WRAPPER FUNCTIONS (PER TYPE)
  // ============================================================

  /// 1️⃣ COMMENTS
  Future<void> addCommentToFavorites({
    required String itemId,
    required String comment,
    List<String> groups = const [],
  }) async {
    await addToFavorites(
      type: 'comments',
      itemId: itemId,
      title: comment.length > 50 ? '${comment.substring(0, 50)}...' : comment,
      content: {'text': comment},
      groups: groups,
      generatedAt: DateTime.now().toIso8601String(),
    );
  }

  /// 2️⃣ SCRIPTS
  Future<void> addScriptToFavorites({
    required String itemId,
    required String title,
    required String script,
    required List<String> groups,
    required String generatedAt,
  }) async {
    await addToFavorites(
      type: 'script',
      itemId: itemId,
      title: title,
      content: {'script': script},
      groups: groups,
      generatedAt: generatedAt,
    );
  }

  /// 3️⃣ AI-REFINED SCRIPT
  Future<void> addAiRefinedScriptToFavorites({
    required String itemId,
    required String title,
    required String originalScript,
    required String refinedScript,
    List<String> groups = const [],
  }) async {
    await addToFavorites(
      type: 'ai_refined',
      itemId: itemId,
      title: title,
      content: {'original': originalScript, 'refined': refinedScript},
      groups: groups,
      generatedAt: DateTime.now().toIso8601String(),
    );
  }

  /// 4️⃣ IDEA DETAILS
  Future<void> addIdeaDetailsToFavorites({
    required int id,
    required String title,
    required String description,
    required String niche,
    required String format,
    required String level,
    required List<String> steps,
    required String cta,
    required String timestamp,
    List<String> groups = const [],
  }) async {
    await addToFavorites(
      type: 'idea_details',
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
      },
      groups: groups,
      generatedAt: timestamp,
    );
  }
}
