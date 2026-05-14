import 'package:firebase_auth/firebase_auth.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/core/services/profile_image_service.dart';
import 'package:ideaboost/data/repository/history_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get userChanges => _auth.authStateChanges();

  // Helper to run after any successful sign-in
  Future<void> _handleUserSignIn(User? user) async {
    if (user != null) {
      // Check if user document already exists
      final userExists = await _userService.userDocumentExists(user.uid);

      if (!userExists) {
        // Only create new user document if it doesn't exist
        await _userService.createNewUser(
          user.uid,
          user.email ?? 'no-email@ideaboost.com',
        );
      }
      // If user exists, do nothing - let Firestore snapshot handle it
    }
  }

  // 1. Google Sign-In (Implemented in Sign-In/Sign-Up screens)
  Future<User?> signInWithGoogle() async {
    throw UnimplementedError(
      "Google Sign-In is handled in the Sign-In/Sign-Up screens.",
    );
  }

  // 2. Apple Sign-In (Still needs external implementation)
  Future<User?> signInWithApple() async {
    throw UnimplementedError(
      "Apple Sign-In needs external package implementation.",
    );
  }

  // 3. Email/Password Sign-up (Now Fully Implemented)
  Future<User?> signUpWithEmail(String email, String password) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _handleUserSignIn(userCredential.user); // Triggers Firestore creation
    return userCredential.user;
  }

  // 3. Email/Password Sign-in (Fully Implemented)
  Future<User?> signInWithEmail(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _handleUserSignIn(
      userCredential.user,
    ); // Ensures existing profile is verified
    return userCredential.user;
  }

  // Sign Out
  Future<void> signOut() async {
    // Clear cached profile image
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      try {
        await ProfileImageService.deleteLocalProfileUrl(currentUser.uid);
      } catch (_) {
        // Ignore cache clear errors
      }
    }
    HistoryRepository.clearCache();
    FavoritesRepository.clearCache();
    await _auth.signOut();
  }
}
