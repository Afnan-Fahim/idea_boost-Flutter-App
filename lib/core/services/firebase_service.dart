import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models/user_model.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Users collection reference
  CollectionReference get _users => _firestore.collection('users');

  /// Get current user UID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Fetch current user from Firestore
  Future<UserModel?> getCurrentUser() async {
    try {
      final uid = currentUserId;
      if (uid == null) return null;

      final doc = await _users.doc(uid).get();
      if (!doc.exists) return null;

      return UserModel.fromFirestore(doc);
    } catch (e) {
      print("Error fetching current user: $e");
      return null;
    }
  }

  /// Update user fields in Firestore
  Future<void> updateUser(UserModel user) async {
    try {
      final uid = currentUserId;
      if (uid == null) return;

      await _users.doc(uid).update(user.toMap());
    } catch (e) {
      print("Error updating user: $e");
      rethrow;
    }
  }
}
