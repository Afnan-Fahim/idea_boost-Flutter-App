import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user document
  Future<DocumentSnapshot> getUserDocument(String userId) async {
    return await _firestore.collection('users').doc(userId).get();
  }

  // Update user document
  Future<void> updateUserDocument(String userId, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(userId).set(data, SetOptions(merge: true));
  }

  // Get favorites collection for a user
  CollectionReference getFavoritesCollection(String userId) {
    return _firestore.collection('favorites').doc(userId).collection('items');
  }

  // Get history collection for a user
  CollectionReference getHistoryCollection(String userId) {
    return _firestore.collection('history').doc(userId).collection('generations');
  }

  // Add to favorites (example method, expand as needed)
  Future<void> addToFavorites(String userId, Map<String, dynamic> item) async {
    await getFavoritesCollection(userId).add(item);
  }

  // Add to history (example method, include timestamp)
  Future<void> addToHistory(String userId, Map<String, dynamic> generation) async {
    generation['timestamp'] = FieldValue.serverTimestamp();
    await getHistoryCollection(userId).add(generation);
  }
}