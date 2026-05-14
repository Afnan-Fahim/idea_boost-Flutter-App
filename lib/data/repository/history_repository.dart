import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../modules/history/model/history_item_model.dart';

class HistoryRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static List<HistoryItem>? _historyCache;
  static DateTime? _historyLastFetch;

  static void clearCache() {
    _historyCache = null;
    _historyLastFetch = null;
  }

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _logsRef() {
    if (_currentUserId.isEmpty) {
      throw Exception('User not authenticated');
    }
    return _firestore
        .collection('history')
        .doc(_currentUserId)
        .collection('logs');
  }

  Future<void> addLog({
    required String type,
    required String prompt,
    required Map<String, dynamic> output,
    DateTime? generatedAt,
    Map<String, dynamic>? meta,
  }) async {
    final data = {
      'type': type,
      'prompt': prompt,
      'output': output,
      'generatedAt': generatedAt != null
          ? Timestamp.fromDate(generatedAt)
          : FieldValue.serverTimestamp(),
      'meta': meta ?? {},
    };
    await _logsRef().add(data);
    
    if (_historyCache != null) {
      // Optimitistic update for memory cache
      _historyCache!.insert(0, HistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temp ID
        type: type,
        prompt: prompt,
        output: output,
        generatedAt: generatedAt ?? DateTime.now(),
        meta: meta ?? {},
      ));
    }
  }

  Stream<List<HistoryItem>> getLogsStream({String? type}) {
    debugPrint(
      '📜 HistoryRepository: Creating stream for type: ${type ?? "All"}',
    );
    
    Query<Map<String, dynamic>> q = _logsRef().orderBy(
      'generatedAt',
      descending: true,
    );
    if (type != null && type.isNotEmpty) q = q.where('type', isEqualTo: type);
    
    return q.snapshots().map((s) {
      debugPrint(
        '📜 HistoryRepository: Snapshot received with ${s.docs.length} documents',
      );
      final items = s.docs.map((d) => HistoryItem.fromFirestore(d)).toList();
      if (type == null || type.isEmpty) {
        _historyCache = List<HistoryItem>.from(items);
        _historyLastFetch = DateTime.now();
      }
      return items;
    });
  }

  Future<List<HistoryItem>> getLogs({String? type, int limit = 100}) async {
    if (_historyCache != null) {
      var items = _historyCache!;
      if (type != null && type.isNotEmpty) {
        items = items.where((item) => item.type == type).toList();
      }
      return items.take(limit).toList();
    }

    Query<Map<String, dynamic>> q = _logsRef()
        .orderBy('generatedAt', descending: true)
        .limit(limit);
    if (type != null && type.isNotEmpty) q = q.where('type', isEqualTo: type);
    final s = await q.get();
    final results = s.docs.map((d) => HistoryItem.fromFirestore(d)).toList();
    
    if (type == null || type.isEmpty) {
        _historyCache = List<HistoryItem>.from(results);
        _historyLastFetch = DateTime.now();
    }
    return results;
  }

  Future<void> removeLog(String docId) async {
    await _logsRef().doc(docId).delete();
  }

  Future<void> clearAll() async {
    final s = await _logsRef().get();
    final b = _firestore.batch();
    for (final doc in s.docs) b.delete(doc.reference);
    await b.commit();
    _historyCache?.clear();
  }

  Future<void> removeMany(List<String> ids) async {
    final b = _firestore.batch();
    for (final id in ids) b.delete(_logsRef().doc(id));
    await b.commit();
    if (_historyCache != null) {
      _historyCache!.removeWhere((item) => ids.contains(item.id));
    }
  }
}
