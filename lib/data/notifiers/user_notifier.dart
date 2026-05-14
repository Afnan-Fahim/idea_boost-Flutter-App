import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/core/services/profile_image_service.dart';
import 'package:ideaboost/data/models/user_model.dart';

class UserNotifier extends ChangeNotifier {
  final UserService _userService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  UserModel _userModel = UserModel(
    id: '',
    email: '',
    name: '',
    plan: 'free',
    language: 'en',
    dailyLimit: 3,
  );

  UserModel get userModel => _userModel;

  UserNotifier(this._userService) {
    // Listen for auth changes and switch the Firestore doc listener accordingly
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthStateChanged,
    );

    // Bootstrap with current user if already signed in
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      _subscribeToUserDoc(current.uid);
    }
  }

  void _onAuthStateChanged(User? fbUser) {
    if (fbUser == null) {
      // Signed out: cancel user doc subscription and clear model
      _userSubscription?.cancel();
      _userModel = UserModel(
        id: '',
        email: '',
        name: '',
        plan: 'free',
        language: 'en',
        dailyLimit: 3,
      );
      notifyListeners();
    } else {
      // Signed in: listen to the new user's document
      _subscribeToUserDoc(fbUser.uid);
    }
  }

  void _subscribeToUserDoc(String uid) {
    _userSubscription?.cancel();

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!snapshot.exists) {
              _userModel = UserModel(
                id: uid,
                email: '',
                name: '',
                plan: 'free',
                language: 'en',
                dailyLimit: 3,
              );
              notifyListeners();
              return;
            }

            try {
              _userModel = UserModel.fromFirestore(snapshot);
              debugPrint(
                '🔍 UserNotifier: Loaded from Firestore - photoUrl: ${_userModel.photoUrl}',
              );
            } catch (_) {
              // Fallback mapping if your fromFirestore throws
              final data = snapshot.data() as Map<String, dynamic>;
              _userModel = UserModel(
                id: snapshot.id,
                email: data['email'] ?? '',
                name: data['name'] ?? '',
                plan: data['plan'] ?? 'free',
                language: data['language'] ?? 'en',
                dailyLimit: (data['dailyLimit'] ?? 3) as int,
                photoUrl: data['photoUrl'] as String?,
              );
              debugPrint(
                '🔍 UserNotifier: Loaded fallback - photoUrl: ${_userModel.photoUrl}',
              );
            }

            // Best-effort: cache the Firestore photoUrl locally for faster loading
            // IMPORTANT: Always prioritize Firestore photoUrl over cached value
            try {
              final firestorePhotoUrl = _userModel.photoUrl ?? '';
              debugPrint(
                '🔍 UserNotifier: Firestore photoUrl: "$firestorePhotoUrl"',
              );

              if (firestorePhotoUrl.isNotEmpty) {
                // Firestore has a photoUrl - cache it and use it
                debugPrint('✅ UserNotifier: Caching photoUrl from Firestore');
                await ProfileImageService.saveLocalProfileUrl(
                  uid,
                  firestorePhotoUrl,
                );
              } else {
                // No photoUrl in Firestore - check if we have a cached one as fallback
                final cached = await ProfileImageService.getLocalProfileUrl(
                  uid,
                );
                debugPrint('🔍 UserNotifier: Cached photoUrl: "$cached"');
                if (cached != null && cached.isNotEmpty) {
                  debugPrint('✅ UserNotifier: Using cached photoUrl');
                  _userModel = _userModel.copyWith(photoUrl: cached);
                } else {
                  debugPrint(
                    '⚠️ UserNotifier: No photoUrl in Firestore or cache',
                  );
                }
              }
            } catch (_) {
              // ignore caching failures
            }

            debugPrint(
              '🎯 UserNotifier: Final photoUrl: ${_userModel.photoUrl}',
            );
            notifyListeners();
          },
          onError: (err) {
            // optional: handle/log error
          },
        );
  }

  /// Force a one-time reload of the current user doc (useful after login)
  Future<void> reload({bool forceServer = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final doc = forceServer
        ? await docRef.get(const GetOptions(source: Source.server))
        : await docRef.get();
    if (!doc.exists) return;

    try {
      _userModel = UserModel.fromFirestore(doc);
    } catch (_) {
      final data = doc.data() as Map<String, dynamic>;
      _userModel = UserModel(
        id: doc.id,
        email: data['email'] ?? '',
        name: data['name'] ?? '',
        plan: data['plan'] ?? 'free',
        language: data['language'] ?? 'en',
        dailyLimit: (data['dailyLimit'] ?? 3) as int,
      );
    }

    notifyListeners();
  }

  // Expose UserService for accessing history
  UserService get userService => _userService;

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }
}
