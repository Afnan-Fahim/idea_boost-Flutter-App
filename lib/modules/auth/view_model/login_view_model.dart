import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../../../data/repository/auth_repository.dart';

class LoginViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  // Auth / user stream
  Map<String, dynamic>? _currentUserData;
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;

  // Form fields
  String email = '';
  String password = '';

  bool obscurePassword = true;
  bool isLoading = false;
  String? errorMessage;

  LoginViewModel(this._authRepository) {
    // listen to auth state changes and keep user data in sync
    _authSubscription = _authRepository.authStateChanges.listen((user) {
      _currentUser = user;
      if (user != null) {
        _initializeUserStream(user.uid);
      } else {
        _userSubscription?.cancel();
        _currentUserData = null;
      }
      notifyListeners();
    });
  }

  // Getters for UI
  Map<String, dynamic>? get currentUserData => _currentUserData;
  User? get currentUser => _currentUser;
  String? get userEmail => _currentUserData?['email'];
  String? get userDisplayName => _currentUserData?['displayName'];
  String? get userPhotoUrl => _currentUserData?['photoUrl'];

  /// ---------------------------
  /// Validate email format
  /// ---------------------------
  bool get isEmailValid {
    final regex = RegExp(r'^\S+@\S+\.\S+$');
    return regex.hasMatch(email);
  }

  /// ---------------------------
  /// Toggle Password Visibility
  /// ---------------------------
  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  /// ---------------------------
  /// Initialize real-time user stream
  /// ---------------------------
  void _initializeUserStream(String uid) {
    // cancel previous
    _userSubscription?.cancel();

    _userSubscription = _authRepository
        .getUserStream(uid)
        .listen(
          (snapshot) {
            _currentUserData = snapshot.data() as Map<String, dynamic>?;
            errorMessage = null;
            notifyListeners();
          },
          onError: (e) {
            errorMessage = 'errors.sync_failed'.tr();
            notifyListeners();
          },
        );
  }

  /// ---------------------------
  /// LOGIN FUNCTION
  /// ---------------------------
  Future<bool> login() async {
    if (email.isEmpty || password.isEmpty) {
      errorMessage = 'errors.email_password_required'.tr();
      notifyListeners();
      return false;
    }

    if (!isEmailValid) {
      errorMessage = 'errors.invalid_email_format'.tr();
      notifyListeners();
      return false;
    }

    // Check internet connection
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      errorMessage = 'errors.no_internet'.tr();
      notifyListeners();
      return false;
    }

    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final user = await _authRepository.login(email, password);

      // ensure stream is initialized (authStateChanges will also handle it)
      if (user != null) {
        _initializeUserStream(user.uid);
      }

      isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      // Map Firebase error codes to user-friendly messages
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'errors.account_not_found'.tr();
          break;
        case 'wrong-password':
          errorMessage = 'errors.invalid_password'.tr();
          break;
        case 'user-disabled':
          errorMessage = 'errors.user_disabled'.tr();
          break;
        case 'too-many-requests':
          errorMessage = 'errors.too_many_login_attempts'.tr();
          break;
        case 'invalid-email':
          errorMessage = 'errors.invalid_email_format'.tr();
          break;
        case 'network-request-failed':
          errorMessage = 'errors.no_internet'.tr();
          break;
        default:
          errorMessage = 'errors.sign_in_failed_credentials'.tr();
      }
      notifyListeners();
      return false;
    } catch (e) {
      isLoading = false;
      errorMessage = 'errors.unexpected_error'.tr();
      notifyListeners();
      return false;
    }
  }

  /// ---------------------------
  /// LOGIN WITH GOOGLE
  /// ---------------------------
  Future<bool> loginWithGoogle() async {
    // Check actual internet connectivity first
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      isLoading = false;
      errorMessage = 'errors.no_internet'.tr();
      notifyListeners();
      return false;
    }

    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      debugPrint('🔵 Google Sign-In: Starting authentication...');

      final user = await _authRepository.signupWithGoogle();
      debugPrint(
        '🟢 Google Sign-In: Authentication successful, uid=${user?.uid}',
      );

      if (user != null) {
        // initialize stream
        _initializeUserStream(user.uid);
      }

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      isLoading = false;

      debugPrint('❌ Google Sign-In Error: $e');
      debugPrint('❌ Error Type: ${e.runtimeType}');

      // provide clearer messages for common account linking errors
      final msg = e.toString();
      if (msg.contains('credential-already-in-use')) {
        errorMessage = 'errors.email_already_linked'.tr();
      } else if (msg.contains('account-exists-with-different-credential')) {
        errorMessage = 'errors.account_different_credential'.tr();
      } else if (msg.contains('canceled') ||
          msg.contains('activity is cancelled by the user')) {
        // User dismissed the Google Auth dialog
        errorMessage = 'login.google_auth_dismissed'.tr();
      } else if (msg.contains('initialize')) {
        errorMessage = 'login.google_auth_failed'.tr();
      } else if (msg.contains('permission') || msg.contains('denied')) {
        errorMessage = 'login.google_auth_failed'.tr();
      } else {
        // Other Google auth errors
        errorMessage = 'login.google_auth_failed'.tr();
      }

      debugPrint('🔴 Final Error Message: $errorMessage');
      notifyListeners();
      return false;
    }
  }

  /// ---------------------------
  /// LOGIN WITH APPLE
  /// ---------------------------
  Future<bool> loginWithApple() async {
    // Check actual internet connectivity first
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      isLoading = false;
      errorMessage = 'errors.no_internet'.tr();
      notifyListeners();
      return false;
    }

    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final user = await _authRepository.signupWithApple();

      if (user != null) {
        _initializeUserStream(user.uid);
      }

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      isLoading = false;

      final msg = e.toString();
      if (msg.contains('credential-already-in-use')) {
        errorMessage = 'errors.email_already_linked'.tr();
      } else if (msg.contains('account-exists-with-different-credential')) {
        errorMessage = 'errors.account_different_credential'.tr();
      } else {
        errorMessage = 'errors.apple_sign_in_failed'.tr();
      }

      notifyListeners();
      return false;
    }
  }

  /// ---------------------------
  /// LOGOUT
  /// ---------------------------
  Future<void> logout() async {
    try {
      _userSubscription?.cancel();
      _authSubscription?.cancel();
      await _authRepository.logout();
      _currentUserData = null;
      _currentUser = null;
      errorMessage = null;
      notifyListeners();
    } catch (e) {
      errorMessage = 'errors.sign_out_failed'.tr();
      notifyListeners();
    }
  }

  /// ---------------------------
  /// SEND PASSWORD RESET EMAIL (Deep Link Strategy)
  /// ---------------------------
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://sendcustomresetemail-onbmw23m6a-uc.a.run.app',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Custom Reset Email Error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  /// ---------------------------
  /// CHECK ACTUAL INTERNET CONNECTIVITY
  /// ---------------------------
  Future<bool> _hasInternetConnection() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        return false;
      }

      // Check if the network actually has internet by pinging a reliable server
      try {
        final response = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      } catch (e) {
        // If Google fails, try another server
        try {
          final response = await http
              .get(Uri.parse('https://www.cloudflare.com'))
              .timeout(const Duration(seconds: 5));
          return response.statusCode == 200;
        } catch (e) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
  }
}
