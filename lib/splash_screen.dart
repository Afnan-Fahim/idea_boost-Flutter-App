// lib/splash_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repository/auth_repository.dart';
import '../main.dart';
import 'core/services/language_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize scale animation: starts small, grows to fill screen
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // Start animation immediately - splash is now visible
    _scaleController.forward();

    // 🎯 SMART APPROACH: Wait for widget to render, THEN start heavy work
    // This ensures splash is visible and animating before we do initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndNavigateWhenReady();
    });
  }

  Future<void> _initializeAndNavigateWhenReady() async {
    if (!mounted) return;

    // ✅ At this point splash is definitely visible on screen
    debugPrint('🎬 Splash visible, starting initialization...');

    // Add minimum 500ms delay to guarantee splash renders/paints on screen
    // This is not arbitrary - it gives the OS time to actually display pixels
    await Future.delayed(const Duration(milliseconds: 500));

    // Now start the real initialization while user watches splash
    if (!mounted) return;
    await _initializeAndNavigate();
  }

  Future<bool> _initializeAndNavigate() async {
    if (!mounted) return false;

    final authRepo = Provider.of<AuthRepository>(context, listen: false);
    User? user = authRepo.getCurrentUser();

    // Refresh cached user (emailVerified, etc.) from server when online
    try {
      await user?.reload();
    } catch (_) {}
    user = authRepo.getCurrentUser();

    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      final hadSession =
          prefs.getBool(AuthRepository.prefKeySessionActive) ?? false;
      if (hadSession) {
        await prefs.remove(AuthRepository.prefKeySessionActive);
        await prefs.remove(AuthRepository.prefKeySessionUid);
      }
    } else {
      await authRepo.persistLocalSessionFlags();

      // 🌍 PHASE 1.2: Auto-login language restoration
      // When returning user auto-logs in, restore their saved language preference
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && mounted) {
          final savedLanguage = userDoc.data()?['language'] as String?;
          if (savedLanguage != null && savedLanguage.isNotEmpty) {
            await LanguageService.setAppLocale(context, savedLanguage);
            debugPrint('🌍 Language restored on auto-login: $savedLanguage');
          }
        }
      } catch (e) {
        debugPrint('Error restoring language on auto-login: $e');
        // Continue without language restoration if Firestore fails
      }
    }

    final bool allowHome = await _shouldOpenHomeForUser(user);

    if (!mounted) return allowHome;

    // 🚀 NEW: Check if onboarding is completed
    final bool onboardingCompleted =
        prefs.getBool('onboarding_completed') ?? false;

    // Navigate to appropriate screen
    if (!onboardingCompleted && user == null) {
      Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
    } else {
      Navigator.pushReplacementNamed(
        context,
        allowHome ? AppRoutes.home : AppRoutes.login,
      );
    }

    return true;
  }

  /// Mirrors login_screen: social / verified email / Firestore emailVerified flag.
  Future<bool> _shouldOpenHomeForUser(User? user) async {
    if (user == null) return false;

    if (user.emailVerified) return true;

    final isSocial = user.providerData.any(
      (fi) => fi.providerId == 'google.com' || fi.providerId == 'apple.com',
    );
    if (isSocial) return true;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) {
        // Session valid but doc not created yet (rare); don't block the user
        return true;
      }
      if (doc.data()?['emailVerified'] == true) return true;
      return false;
    } catch (_) {
      // Offline / Firestore error — prefer keeping session over forcing re-login
      return true;
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final displaySize = screenSize.shortestSide;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Image.asset(
                'assets/LookSplash.png',
                fit: BoxFit.contain,
                width: displaySize,
                height: displaySize,
              ),
            );
          },
        ),
      ),
    );
  }
}
