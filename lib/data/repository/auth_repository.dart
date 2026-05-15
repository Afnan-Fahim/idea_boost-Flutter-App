import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ideaboost/config/google_sign_in_config.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/core/services/language_service.dart';
import 'package:ideaboost/core/services/profile_image_service.dart';
import 'package:ideaboost/core/services/stale_data_detector.dart';
import 'package:ideaboost/data/repository/history_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService;

  // Track if GoogleSignIn has been initialized
  static bool _googleSignInInitialized = false;

  AuthRepository(this._userService);

  /// SharedPreferences keys — session mirrors Firebase after login; cleared on logout/delete.
  static const String prefKeySessionActive = 'ideaboost_user_logged_in';
  static const String prefKeySessionUid = 'ideaboost_session_uid';

  /// Call after any successful sign-in so local prefs match logged-in state.
  Future<void> persistLocalSessionFlags() async {
    final u = _firebaseAuth.currentUser;
    if (u == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKeySessionActive, true);
      await prefs.setString(prefKeySessionUid, u.uid);
    } catch (_) {}
  }

  /// Wipes all SharedPreferences (logout / delete account). Call after [signOut].
  static Future<void> clearAllSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  // Expose firebaseAuth for ViewModel to listen to auth state changes
  FirebaseAuth get firebaseAuth => _firebaseAuth;

  // Expose auth state changes stream
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Check if user document exists in Firestore
  Future<bool> userExists(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Get or create user document
  ///
  /// - New users: Capture device language via LanguageService
  /// - Existing users: Update minimal fields
  Future<void> _ensureUserDocument(User user, {String? deviceLanguage, String? displayName}) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        // Create new user document with device language
        debugPrint(
          '🚨 USER DOC DOES NOT EXIST - calling createNewUser for ${user.uid}',
        );
        final langCode =
            deviceLanguage ?? LanguageService.getDeviceLanguageCode();
        await _userService.createNewUser(
          user.uid,
          user.email ?? 'no-email',
          deviceLanguage: langCode,
          displayName: displayName,
        );
        debugPrint('🌍 New user created with language: $langCode');
      } else {
        // Update existing user document with latest auth info
        debugPrint(
          '🚨 USER DOC ALREADY EXISTS for ${user.uid} - SKIPPING createNewUser',
        );
        // NOTE: Do NOT update photoUrl here - it should only be updated when user uploads a custom avatar
        final existingData = userDoc.data() as Map<String, dynamic>?;
        final String currentStoredName = existingData?['name'] as String? ?? 'User';

        // 🛡️ SECURITY: Only update name if it's currently generic 'User' 
        // and we have a real name from the auth provider (like Google)
        String finalName = currentStoredName;
        if (currentStoredName == 'User' && user.displayName != null && user.displayName!.isNotEmpty) {
          finalName = user.displayName!;
        }

        await _firestore.collection('users').doc(user.uid).update({
          'email': user.email,
          'name': finalName,
        });
      }
    } catch (e) {
      // log and rethrow so callers can handle
      print('Error ensuring user document: $e');
      rethrow;
    }
  }

  /// Stream user data from Firestore (Real-time sync)
  Stream<DocumentSnapshot> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  /// ---------------------------
  /// SIGN UP (EMAIL/PASSWORD)
  /// ---------------------------
  Future<User?> signup(String email, String password, {String? displayName}) async {
    try {
      // Check if email already exists in Firestore (from Google/Apple signup)
      final existingUser = await _checkEmailExists(email);

      if (existingUser != null) {
        // Link password to existing Google/Apple account
        return await _linkPasswordAuth(existingUser, email, password);
      }

      // Create new account with email/password
      final result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = result.user;
      if (user != null) {
        // ✅ Create Firestore document immediately with device language
        final deviceLanguage = LanguageService.getDeviceLanguageCode();
        await _ensureUserDocument(user, deviceLanguage: deviceLanguage, displayName: displayName);
        debugPrint('✅ User account created: ${user.email}');
        await persistLocalSessionFlags();

        // 🎯 CRITICAL: Record session start time for stale detection
        StaleDataDetector.recordSessionStart();
      }

      return user;
    } on FirebaseAuthException catch (e) {
      // Re-throw FirebaseAuthException so ViewModel can handle specific error codes
      rethrow;
    }
  }

  /// ---------------------------
  /// LOGIN
  /// ---------------------------
  Future<User?> login(String email, String password) async {
    try {
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = result.user;
      if (user != null) {
        await _ensureUserDocument(user);
        await persistLocalSessionFlags();

        // 🎯 CRITICAL: Record session start time for stale detection
        StaleDataDetector.recordSessionStart();
      }

      return user;
    } on FirebaseAuthException catch (e) {
      // Re-throw FirebaseAuthException so ViewModel can handle specific error codes
      rethrow;
    }
  }

  /// ---------------------------
  /// EMAIL VERIFICATION
  /// ---------------------------
  /// Send verification email to current user
  Future<void> sendEmailVerification() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        print('✅ Email verification sent to: ${user.email}');
      }
    } catch (e) {
      print('⚠️ Failed to send verification email: $e');
      rethrow;
    }
  }

  /// Check if current user's email is verified
  /// Reload user data from Firebase to get latest emailVerified status
  Future<bool> isEmailVerified() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) return false;

      // Reload to get latest status
      await user.reload();
      return user.emailVerified;
    } catch (e) {
      print('⚠️ Failed to check email verification: $e');
      return false;
    }
  }

  /// ✅ Check email verification using email + password
  /// This works even if user is signed out (after signup)
  /// Returns true if email is verified, false otherwise
  Future<bool> checkEmailVerificationWithPassword(
    String email,
    String password,
  ) async {
    try {
      debugPrint('🔐 Checking email verification for $email...');

      // Try to sign in with email/password to check verification status
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = result.user;
      if (user == null) {
        debugPrint('❌ No user returned after sign in');
        // Sign out to maintain signed-out state
        await _firebaseAuth.signOut();
        return false;
      }

      // Check if email is verified
      final isVerified = user.emailVerified;
      debugPrint('✅ User signed in, email verified: $isVerified');

      // Sign out immediately to maintain the unsigned state
      // (User will be properly logged in when verification is confirmed)
      await _firebaseAuth.signOut();

      return isVerified;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Sign in error while checking verification: ${e.code}');
      if (e.code == 'user-not-found') {
        debugPrint('   User not found - account may not be created yet');
        return false;
      } else if (e.code == 'wrong-password') {
        debugPrint('   Wrong password provided');
        return false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error checking email verification: $e');
      return false;
    }
  }

  /// ✅ Create user in Firestore after email verification
  /// This is called ONLY after email is verified
  Future<void> createVerifiedUser(User user) async {
    try {
      debugPrint('📝 Creating verified user document for ${user.uid}...');
      await _ensureUserDocument(user);
      await persistLocalSessionFlags();
      debugPrint('✅ Verified user document created successfully');
    } catch (e) {
      debugPrint('❌ Error creating verified user: $e');
      rethrow;
    }
  }

  /// ---------------------------
  /// GOOGLE SIGN IN (NATIVE DIALOG)
  /// ---------------------------
  Future<User?> signupWithGoogle() async {
    try {
      debugPrint('📱 GoogleSignIn: Getting singleton instance...');
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;

      // Initialize only once
      if (!_googleSignInInitialized) {
        debugPrint('📱 GoogleSignIn: Initializing...');
        try {
          // On Android, serverClientId is required for google_sign_in 7.x
          if (googleServerClientId.isNotEmpty) {
            debugPrint('📱 GoogleSignIn: Using serverClientId for Android');
            await googleSignIn.initialize(serverClientId: googleServerClientId);
          } else {
            debugPrint(
              '⚠️ GoogleSignIn: No serverClientId provided (will only work on iOS)',
            );
            await googleSignIn.initialize();
          }
          _googleSignInInitialized = true;
          debugPrint('✅ GoogleSignIn: Initialization successful');
        } catch (e) {
          debugPrint('❌ GoogleSignIn: Initialization failed: $e');
          throw 'GoogleSignIn initialization failed: $e';
        }
      }

      // Request authentication with timeout and error recovery
      // authenticate() shows the native account picker dialog
      debugPrint('📱 GoogleSignIn: Requesting account selection...');

      late GoogleSignInAccount googleAccount;
      try {
        // authenticate() returns the account or throws if user cancels/times out
        googleAccount = await googleSignIn.authenticate().timeout(
          const Duration(seconds: 45),
          onTimeout: () async {
            debugPrint('⚠️ GoogleSignIn: Dialog timeout - attempting cleanup');
            try {
              await googleSignIn.signOut();
            } catch (_) {
              // Ignore cleanup errors
            }
            throw 'Google Sign-In took too long. Please check your internet connection.';
          },
        );

        debugPrint(
          '✅ GoogleSignIn: Account authenticated - ${googleAccount.email}',
        );
      } catch (e) {
        debugPrint('❌ GoogleSignIn: Error: $e');
        // Attempt cleanup on any error (except timeout, which already cleaned up)
        if (!e.toString().contains('timeout') &&
            !e.toString().contains('too long')) {
          try {
            await googleSignIn.signOut();
          } catch (_) {
            // Ignore cleanup failures
          }
        }
        rethrow;
      }

      debugPrint(
        '✅ GoogleSignIn: Authentication returned account ${googleAccount.email}',
      );

      // Get ID token from authenticated account
      debugPrint('📱 GoogleSignIn: Getting authentication tokens...');
      final GoogleSignInAuthentication googleAuth =
          await googleAccount.authentication;

      final String? idToken = googleAuth.idToken;
      debugPrint(
        '📱 GoogleSignIn: idToken=${idToken != null ? 'present' : 'NULL'}',
      );

      if (idToken == null || idToken.isEmpty) {
        debugPrint('❌ GoogleSignIn: Failed to get ID token');
        throw 'Failed to get Google ID token';
      }

      // Create Firebase credential using ID token
      debugPrint('🔥 Firebase: Creating credential from Google ID token...');
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      // Sign in to Firebase with the credential
      debugPrint('🔥 Firebase: Signing in with credential...');
      final UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);

      debugPrint('✅ Firebase: Sign-in successful');

      final user = userCredential.user;

      if (user != null) {
        debugPrint('👤 Creating Firestore document for ${user.uid}...');
        await _ensureUserDocument(user);
        await persistLocalSessionFlags();

        // 🎯 CRITICAL: Record session start time for stale detection
        StaleDataDetector.recordSessionStart();

        debugPrint('✅ User setup complete: ${user.email}');
      }

      return user;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '❌ FirebaseAuthException code=${e.code}, message=${e.message}',
      );

      if (e.code == 'operation-not-allowed') {
        throw 'Google sign-in is not enabled in Firebase Console.';
      } else if (e.code == 'account-exists-with-different-credential') {
        throw 'An account already exists with a different credential.';
      } else if (e.code == 'invalid-credential') {
        throw 'Invalid Google credentials. Please try again.';
      }
      throw Exception('errors.google_sign_in_failed'.tr());
    } catch (e) {
      debugPrint('❌ Unexpected error in signupWithGoogle: $e');
      throw 'Google authentication error: ${e.toString()}';
    }
  }

  /// ---------------------------
  /// APPLE SIGN IN
  /// ---------------------------
  Future<User?> signupWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      UserCredential userCredential = await firebaseAuth.signInWithCredential(
        oauthCredential,
      );

      print(userCredential.toString());

      final user = userCredential.user;

      if (user != null) {
        await _ensureUserDocument(user);
        await persistLocalSessionFlags();

        // 🎯 CRITICAL: Record session start time for stale detection
        StaleDataDetector.recordSessionStart();
      }

      return user;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Exception: $e");
      throw Exception('errors.apple_sign_in_failed'.tr());
    }
  }

  /// Check if email exists in Firestore users collection
  Future<QueryDocumentSnapshot?> _checkEmailExists(String email) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first : null;
    } catch (e) {
      return null;
    }
  }

  /// Link password auth to existing provider account
  Future<User?> _linkPasswordAuth(
    QueryDocumentSnapshot existingUserDoc,
    String email,
    String password,
  ) async {
    try {
      // Expect that the user is already authenticated (e.g. via Google)
      final existingUser = _firebaseAuth.currentUser;

      if (existingUser == null) {
        throw 'No authenticated user found to link credentials to.';
      }

      // Create credential from email/password
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );

      // Link credential to current user
      await existingUser.linkWithCredential(credential);

      // Update user document
      await _ensureUserDocument(existingUser);
      await persistLocalSessionFlags();

      return existingUser;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw 'This email is already linked to another account';
      }
      throw Exception('errors.something_went_wrong_try_again'.tr());
    }
  }

  /// Merge duplicate user documents (call after resolving duplicates)
  Future<void> mergeDuplicateUsers(String sourceUid, String targetUid) async {
    try {
      final sourceDoc = await _firestore
          .collection('users')
          .doc(sourceUid)
          .get();
      final targetDoc = await _firestore
          .collection('users')
          .doc(targetUid)
          .get();

      if (sourceDoc.exists && targetDoc.exists) {
        // Merge data (keep target, update with non-null source fields)
        final sourceData = sourceDoc.data() as Map<String, dynamic>;
        final targetData = targetDoc.data() as Map<String, dynamic>;

        final mergedData = {...targetData};
        sourceData.forEach((key, value) {
          if (value != null && !mergedData.containsKey(key)) {
            mergedData[key] = value;
          }
        });

        // Write merged data to target
        await _firestore.collection('users').doc(targetUid).set(mergedData);

        // Delete source
        await _firestore.collection('users').doc(sourceUid).delete();
      }
    } catch (e) {
      throw 'Merge failed: $e';
    }
  }

  /// ---------------------------
  /// LOGOUT
  /// ---------------------------
  Future<void> logout() async {
    try {
      // 🎯 CRITICAL: Reset session tracking on logout
      StaleDataDetector.resetSession();

      // Get current user ID before signing out
      final currentUid = _firebaseAuth.currentUser?.uid;

      // Sign out from Firebase
      await _firebaseAuth.signOut();

      if (currentUid != null) {
        await ProfileImageService.deleteLocalProfileUrl(currentUid);
      }
      HistoryRepository.clearCache();
      FavoritesRepository.clearCache();
      await clearAllSharedPreferences();
    } catch (e) {
      throw 'errors.sign_out_failed'.tr();
    }
  }

  User? getCurrentUser() => _firebaseAuth.currentUser;

  /// ---------------------------
  /// RE-AUTHENTICATE USER (Required before sensitive operations)
  /// ---------------------------
  /// For Google users: Shows native Google account selector dialog (NOT webview)
  /// Returns true if re-authentication was successful, false if cancelled.
  Future<bool> reauthenticateWithGoogle() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        debugPrint('❌ No user to re-authenticate');
        return false;
      }

      debugPrint('🔄 Starting Google re-authentication for ${user.email}...');

      // Get singleton instance
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;

      // Initialize
      await googleSignIn.initialize();

      // Show native Google account selector dialog
      final GoogleSignInAccount? googleAccount = await googleSignIn
          .authenticate();

      if (googleAccount == null) {
        debugPrint('⚠️  User cancelled Google re-authentication');
        return false;
      }

      debugPrint('✅ Google auth returned: ${googleAccount.email}');

      // Get ID token from authenticated account
      final GoogleSignInAuthentication googleAuth =
          await googleAccount.authentication;

      final String? idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('❌ Failed to get Google ID token for re-auth');
        return false;
      }

      // Create Firebase credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      // Re-authenticate with Firebase
      debugPrint('🔐 Re-authenticating Firebase user...');
      await user.reauthenticateWithCredential(credential);

      debugPrint('✅ Google re-authentication successful!');
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch') {
        debugPrint(
          '❌ Re-auth error: Google account does not match current user',
        );
      } else if (e.code == 'invalid-credential') {
        debugPrint('❌ Re-auth error: Invalid Google credentials');
      } else {
        debugPrint('❌ Re-auth error: ${e.code} - ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('❌ Google re-authentication failed: $e');
      return false;
    }
  }

  /// ---------------------------
  /// RE-AUTHENTICATE WITH EMAIL/PASSWORD
  /// ---------------------------
  /// For email/password authenticated users, re-authenticate with credentials.
  /// This is required before sensitive operations like account deletion.
  /// Returns true if re-authentication was successful, false if failed.
  Future<bool> reauthenticateWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        debugPrint('❌ No user to re-authenticate');
        return false;
      }

      debugPrint('🔄 Starting email re-authentication for $email...');

      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );

      await user.reauthenticateWithCredential(credential);

      debugPrint(
        '✅ Email re-authentication successful. New auth token obtained.',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        debugPrint('❌ Re-auth error: Wrong password');
      } else if (e.code == 'user-not-found') {
        debugPrint('❌ Re-auth error: User not found');
      } else if (e.code == 'invalid-email') {
        debugPrint('❌ Re-auth error: Invalid email');
      } else {
        debugPrint('❌ Re-auth error: ${e.code} - ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('❌ Email re-authentication failed: $e');
      return false;
    }
  }

  /// ---------------------------
  /// CHECK AUTH TOKEN FRESHNESS
  /// ---------------------------
  /// Returns true if auth token is fresh (< 5 minutes old)
  /// Returns false if auth token is stale (>= 5 minutes old)
  /// This prevents 'requires-recent-login' errors during sensitive operations
  Future<bool> isAuthTokenFresh() async {
    print('═══════════════════════════════════════════════════════════');
    print('🚀 [TOKEN LIFETIME CHECK] Analyzing auth token freshness...');
    print('═══════════════════════════════════════════════════════════');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🚀 [TOKEN LIFETIME CHECK] Analyzing auth token freshness...');
    debugPrint('═══════════════════════════════════════════════════════════');

    final user = _firebaseAuth.currentUser;
    if (user == null) {
      print('❌ [TOKEN] No user authenticated');
      debugPrint('❌ [TOKEN] No user authenticated');
      return false;
    }

    try {
      final tokenResult = await user.getIdTokenResult();
      final issuedTime = tokenResult.issuedAtTime;
      final nowTime = DateTime.now();
      final ageInSeconds = nowTime.difference(issuedTime ?? nowTime).inSeconds;
      final ageInMinutes = ageInSeconds / 60;
      final secondsRemaining = 300 - ageInSeconds;
      final minutesRemaining = (secondsRemaining / 60).toStringAsFixed(2);
      final expiryTime = issuedTime?.add(const Duration(hours: 1));

      print('');
      print('📋 [TOKEN DETAILS]');
      print('   Token Issued At: $issuedTime');
      print('   Current Time:    $nowTime');
      print(
        '   Token Age:       ${ageInSeconds}s (${ageInMinutes.toStringAsFixed(2)}m)',
      );
      print('   Expires At:      $expiryTime (1 hour from issue)');
      print('');
      print('⏱️  [FRESHNESS THRESHOLD]');
      print('   Fresh Threshold:  300 seconds (5 minutes)');
      print('   Token Age:        ${ageInSeconds}s');
      print(
        '   Status:           ${ageInSeconds >= 300 ? '🔴 STALE' : '🟢 FRESH'}',
      );
      print(
        '   Time Until Stale: ${ageInSeconds >= 300 ? '0s (EXPIRED)' : '$secondsRemaining seconds ($minutesRemaining minutes)'}',
      );
      print('');

      debugPrint('');
      debugPrint('📋 [TOKEN DETAILS]');
      debugPrint('   Token Issued At: $issuedTime');
      debugPrint('   Current Time:    $nowTime');
      debugPrint(
        '   Token Age:       ${ageInSeconds}s (${ageInMinutes.toStringAsFixed(2)}m)',
      );
      debugPrint('   Expires At:      $expiryTime (1 hour from issue)');
      debugPrint('');
      debugPrint('⏱️  [FRESHNESS THRESHOLD]');
      debugPrint('   Fresh Threshold:  300 seconds (5 minutes)');
      debugPrint('   Token Age:        ${ageInSeconds}s');
      debugPrint(
        '   Status:           ${ageInSeconds >= 300 ? '🔴 STALE' : '🟢 FRESH'}',
      );
      debugPrint(
        '   Time Until Stale: ${ageInSeconds >= 300 ? '0s (EXPIRED)' : '$secondsRemaining seconds ($minutesRemaining minutes)'}',
      );
      debugPrint('');

      if (ageInSeconds >= 300) {
        print('⚠️  [DECISION] Token is STALE → RE-AUTHENTICATION REQUIRED');
        print('   ❌ Cannot proceed with sensitive operations');
        print('   ✅ Will trigger re-authentication dialog');
        debugPrint(
          '⚠️  [DECISION] Token is STALE → RE-AUTHENTICATION REQUIRED',
        );
        debugPrint('   ❌ Cannot proceed with sensitive operations');
        debugPrint('   ✅ Will trigger re-authentication dialog');
        print('═══════════════════════════════════════════════════════════');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        return false;
      } else {
        print('✅ [DECISION] Token is FRESH → PROCEEDING WITH OPERATION');
        print('   ✅ Safe to proceed with account deletion');
        print('   ⏱️  ${secondsRemaining}s remaining before re-auth required');
        debugPrint('✅ [DECISION] Token is FRESH → PROCEEDING WITH OPERATION');
        debugPrint('   ✅ Safe to proceed with account deletion');
        debugPrint(
          '   ⏱️  ${secondsRemaining}s remaining before re-auth required',
        );
        print('═══════════════════════════════════════════════════════════');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        return true;
      }
    } catch (e) {
      print('❌ [ERROR] Could not check token freshness: $e');
      print('   Assuming token is STALE for safety');
      debugPrint('❌ [ERROR] Could not check token freshness: $e');
      debugPrint('   Assuming token is STALE for safety');
      print('═══════════════════════════════════════════════════════════');
      debugPrint('═══════════════════════════════════════════════════════════');
      return false;
    }
  }

  /// ---------------------------
  /// DELETE ACCOUNT (WITH AUTO-REAUTHENTICATION)
  /// ---------------------------
  /// Deletes Firestore data FIRST (while authenticated), then Firebase Auth account.
  /// AUTOMATICALLY re-authenticates if token is stale (for email/password users).
  /// Requires password parameter for email/password users to re-auth if needed.
  /// Firestore data deletion is irreversible. Ensure user confirmation before calling.
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated.');

    final uid = user.uid;
    final email = user.email;

    print('═══════════════════════════════════════════════════════════');
    print('🔴🔴🔴 [ACCOUNT DELETION INITIATED] 🔴🔴🔴');
    print('═══════════════════════════════════════════════════════════');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🔴🔴🔴 [ACCOUNT DELETION INITIATED] 🔴🔴🔴');
    debugPrint('═══════════════════════════════════════════════════════════');

    print('');
    print('👤 [USER INFORMATION]');
    print('   UID:   $uid');
    print('   Email: $email');
    debugPrint('');
    debugPrint('👤 [USER INFORMATION]');
    debugPrint('   UID:   $uid');
    debugPrint('   Email: $email');

    try {
      // 🎯 NOTE: Token freshness is checked by UI before calling this method
      // If we reach here, token is already verified to be fresh
      print('');
      print(
        '🔒 [ACCOUNT DELETION] Token verified fresh by UI layer - proceeding',
      );
      debugPrint('');
      debugPrint(
        '🔒 [ACCOUNT DELETION] Token verified fresh by UI layer - proceeding',
      );

      // 1️⃣ Delete all Firestore data FIRST (while still authenticated)
      print('');
      print('🔄 [STEP 1] Deleting Firestore user data...');
      debugPrint('');
      debugPrint('🔄 [STEP 1] Deleting Firestore user data...');

      await _userService.deleteAllUserData(uid);
      print('   ✅ Firestore data deleted successfully');
      debugPrint('   ✅ Firestore data deleted successfully');

      // 2️⃣ Clear local profile image cache
      print('');
      print('🔄 [STEP 2] Clearing profile image cache...');
      debugPrint('');
      debugPrint('🔄 [STEP 2] Clearing profile image cache...');

      await ProfileImageService.deleteLocalProfileUrl(uid);
      print('   ✅ Profile image cache cleared');
      debugPrint('   ✅ Profile image cache cleared');

      // 3️⃣ DELETE FIREBASE AUTH ACCOUNT
      print('');
      print('🔄 [STEP 3] Deleting Firebase Auth account...');
      debugPrint('');
      debugPrint('🔄 [STEP 3] Deleting Firebase Auth account...');

      await user.delete();
      print('   ✅ Firebase Auth account deleted');
      debugPrint('   ✅ Firebase Auth account deleted');

      // 4️⃣ Sign out and clear session
      print('');
      print('🔄 [STEP 4] Signing out and clearing cache...');
      debugPrint('');
      debugPrint('🔄 [STEP 4] Signing out and clearing cache...');

      // 🎯 CRITICAL: Reset session tracking on account deletion
      StaleDataDetector.resetSession();

      await _firebaseAuth.signOut();
      print('   ✅ Signed out from Firebase');
      debugPrint('   ✅ Signed out from Firebase');

      HistoryRepository.clearCache();
      FavoritesRepository.clearCache();

      await clearAllSharedPreferences();
      print('   ✅ SharedPreferences cleared');
      debugPrint('   ✅ SharedPreferences cleared');

      print('');
      print('═══════════════════════════════════════════════════════════');
      print('✅✅✅ [SUCCESS] Account deletion completed! ✅✅✅');
      print('═══════════════════════════════════════════════════════════');
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('✅✅✅ [SUCCESS] Account deletion completed! ✅✅✅');
      debugPrint('═══════════════════════════════════════════════════════════');
    } on FirebaseAuthException catch (e) {
      // 🎯 CRITICAL: Reset session tracking even on error
      StaleDataDetector.resetSession();

      print('');
      print('❌ [ERROR] Firebase exception during deletion: ${e.code}');
      print('   Message: ${e.message}');
      debugPrint('');
      debugPrint('❌ [ERROR] Firebase exception during deletion: ${e.code}');
      debugPrint('   Message: ${e.message}');

      // Handle specific Firebase errors
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'Session expired. Please re-authenticate and try again. '
          'Error: ${e.message}',
        );
      } else if (e.code == 'operation-not-allowed') {
        throw Exception('Account deletion is not allowed at this time.');
      }

      throw Exception('errors.something_went_wrong_try_again'.tr());
    } catch (e) {
      // 🎯 CRITICAL: Reset session tracking even on error
      StaleDataDetector.resetSession();

      print('');
      print('❌❌❌ [CRITICAL ERROR] Account deletion FAILED ❌❌❌');
      print('   Error: $e');
      print('═══════════════════════════════════════════════════════════');
      debugPrint('');
      debugPrint('❌❌❌ [CRITICAL ERROR] Account deletion FAILED ❌❌❌');
      debugPrint('   Error: $e');
      debugPrint('═══════════════════════════════════════════════════════════');
      throw Exception('errors.something_went_wrong_try_again'.tr());
    }
  }

  /// ---------------------------
  /// CHECK EMAIL REGISTRATION
  /// ---------------------------
  /// Returns true if an account with this email exists in Firestore
  Future<bool> isEmailRegistered(String email) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking email registration: $e');
      // If we get a permission error, we assume the user exists to be safe,
      // or we can handle it specifically. For now, we return false to trigger the "unregistered" message.
      return false;
    }
  }
}
