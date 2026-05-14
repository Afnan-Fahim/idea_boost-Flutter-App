// lib/modules/profile/view_model/profile_view_model.dart

import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../core/services/firebase_service.dart';

class ProfileViewModel extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();

  UserModel? user;
  bool isLoading = false;

  /// Load current user from Firebase
  /// This is the method we call from main.dart → ProfileViewModel()..loadUserData()
  Future<void> loadUserData() async {
    await loadUser(); // Reuses your existing logic
  }

  /// Load current user from Firebase (your original method)
  Future<void> loadUser() async {
    if (isLoading) return; // Prevent double loading

    try {
      isLoading = true;
      notifyListeners();

      // Fetch fresh user data
      user = await _firebaseService.getCurrentUser();

      // If user is still null (e.g. not logged in), keep it null
    } catch (e) {
      debugPrint("Error loading user: $e");
      user = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Update user fields (name, email, language)
  Future<void> updateUser({
    String? name,
    String? email,
    String? language,
  }) async {
    if (user == null) return;

    isLoading = true;
    notifyListeners();

    try {
      final updatedUser = user!.copyWith(
        name: name,
        email: email,
        language: language,
      );

      await _firebaseService.updateUser(updatedUser);
      user = updatedUser;

      notifyListeners();
    } catch (e) {
      debugPrint("Error updating user: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Change language locally (no need to save immediately if you save on edit)
  void changeLanguage(String newLang) {
    if (user == null || user!.language == newLang) return;

    user = user!.copyWith(language: newLang);
    notifyListeners();
  }

  /// Check if user has PRO plan
  bool get isProUser => user?.plan == 'pro';

  /// Optional: Refresh user data manually
  Future<void> refresh() => loadUser();
}
