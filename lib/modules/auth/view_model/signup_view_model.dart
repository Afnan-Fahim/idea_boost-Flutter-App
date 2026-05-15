import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/repository/auth_repository.dart';

class SignupViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  // User data & auth state
  Map<String, dynamic>? _currentUserData;
  StreamSubscription? _userSubscription;
  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;

  // Form fields
  String name = '';
  String email = '';
  String password = '';
  String confirmPassword = '';
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  // Status
  bool isLoading = false;
  String? errorMessage;

  SignupViewModel(this._authRepository) {
    // Listen to auth state changes via repository public stream
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
      if (connectivity.contains(ConnectivityResult.none)) {
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

  // Getters
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
  /// Toggle visibility
  /// ---------------------------
  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    obscureConfirmPassword = !obscureConfirmPassword;
    notifyListeners();
  }

  /// ---------------------------
  /// Initialize real-time user stream
  /// ---------------------------
  void _initializeUserStream(String uid) {
    // Cancel previous subscription
    _userSubscription?.cancel();

    // Subscribe to real-time user document
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
  /// SIGNUP WITH EMAIL/PASSWORD
  /// ---------------------------
  Future<bool> signup() async {
    // Validation
    if (name.trim().isEmpty) {
      errorMessage = 'Please enter your full name';
      notifyListeners();
      return false;
    }

    if (!isEmailValid) {
      errorMessage = 'errors.invalid_email_format'.tr();
      notifyListeners();
      return false;
    }

    if (password.isEmpty || confirmPassword.isEmpty) {
      errorMessage = 'errors.password_fields_empty'.tr();
      notifyListeners();
      return false;
    }

    if (password != confirmPassword) {
      errorMessage = 'errors.passwords_mismatch'.tr();
      notifyListeners();
      return false;
    }

    // Check internet
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      errorMessage = 'errors.no_internet'.tr();
      notifyListeners();
      return false;
    }

    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      final user = await _authRepository.signup(email, password, displayName: name.trim());

      if (user != null) {
        debugPrint('✅ User signed up successfully: ${user.email}');
        isLoading = false;
        notifyListeners();
        return true;
      }

      isLoading = false;
      errorMessage = 'errors.signup_failed'.tr();
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      // Map Firebase error codes to user-friendly messages
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'errors.weak_password'.tr();
          break;
        case 'email-already-in-use':
          errorMessage = 'errors.email_registered_sign_in'.tr();
          break;
        case 'invalid-email':
          errorMessage = 'errors.invalid_email_format'.tr();
          break;
        case 'network-request-failed':
          errorMessage = 'errors.no_internet'.tr();
          break;
        case 'operation-not-allowed':
          errorMessage = 'errors.signup_failed'.tr();
          break;
        default:
          errorMessage = 'errors.signup_failed'.tr();
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
  /// GOOGLE SIGN-IN/SIGNUP
  /// ---------------------------
  Future<bool> signupWithGoogle() async {
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

      final user = await _authRepository.signupWithGoogle();

      if (user != null) {
        // Real-time stream will be initialized automatically by authStateChanges listener
        isLoading = false;
        notifyListeners();
        return true;
      }

      isLoading = false;
      notifyListeners();
      return false;
    } catch (e, stack) {
      isLoading = false;
      debugPrint('❌ Google Sign-Up Error: $e');
      debugPrint('❌ Stack Trace: $stack');

      // Handle account linking scenario
      final msg = e.toString().toLowerCase();
      if (msg.contains('credential-already-in-use')) {
        errorMessage = 'errors.email_linked_use_different'.tr();
      } else if (msg.contains('account-exists-with-different-credential')) {
        errorMessage = 'errors.email_registered_sign_in'.tr();
      } else if (msg.contains('canceled') ||
          msg.contains('cancelled') ||
          msg.contains('user-dismissed') ||
          msg.contains('activity is cancelled by the user')) {
        // User dismissed the Google Auth dialog
        errorMessage = 'signup.google_auth_dismissed'.tr();
      } else {
        // Other Google auth errors (network, setup issues, etc)
        errorMessage = 'signup.google_auth_failed'.tr();
      }

      notifyListeners();
      return false;
    }
  }

  /// ---------------------------
  /// APPLE SIGN-IN/SIGNUP
  /// ---------------------------
  Future<bool> signupWithApple() async {
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
        // Real-time stream will be initialized automatically by authStateChanges listener
        isLoading = false;
        notifyListeners();
        return true;
      }

      isLoading = false;
      errorMessage = 'errors.apple_sign_in_failed'.tr();
      notifyListeners();
      return false;
    } catch (e) {
      isLoading = false;

      // Handle account linking scenario
      if (e.toString().contains('credential-already-in-use')) {
        errorMessage = 'errors.email_linked_use_different'.tr();
      } else if (e.toString().contains(
        'account-exists-with-different-credential',
      )) {
        errorMessage = 'errors.email_registered_sign_in'.tr();
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
  /// SEND PROFESSIONAL VERIFICATION EMAIL
  /// ---------------------------
  Future<bool> sendCustomVerificationEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://sendcustomverificationemail-onbmw23m6a-uc.a.run.app',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Custom Verification Email Error: $e');
      return false;
    }
  }
}
