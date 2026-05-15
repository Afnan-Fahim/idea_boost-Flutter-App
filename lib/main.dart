// lib/main.dart
// NEW IMPORTS: Add the required localization packages
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'core/constants/locale_config.dart';
import 'core/services/language_service.dart';
import 'splash_screen.dart';
import 'modules/auth/view/login_screen.dart';
import 'modules/onboarding/view/onboarding_screen.dart';
import 'core/services/crashlytics_service.dart';
import 'modules/auth/view/signup_screen.dart';
import 'modules/home/view/home_screen.dart';
import 'modules/paywall/view/paywall_screen.dart';
import 'modules/auth/view/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'data/repository/auth_repository.dart';
import 'modules/auth/view_model/login_view_model.dart';
import 'modules/auth/view_model/signup_view_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/services/user_service.dart';
import 'data/repository/user_repository.dart';
import 'data/notifiers/user_notifier.dart';

// ADD THIS LINE — This is the ONLY change needed for language detection in ViewModels
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // 1. INITIALIZATION: Bindings must be initialized first
  WidgetsFlutterBinding.ensureInitialized();

  // 2. LOCALIZATION INIT: Initialize easy_localization (REQUIRED immediately)
  await EasyLocalization.ensureInitialized();

  // 3. FIREBASE INIT: Initialize Firebase (CRITICAL - needed for auth/Firestore immediately)
  // This MUST be synchronous before creating providers
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Lock app to portrait (vertical) mode only (FAST)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ⚡ OPTIMIZATION: Defer only NON-CRITICAL services to background
  // MobileAds and Crashlytics don't block auth, so defer them
  _initializeDeferredServices();

  runApp(
    // 3. EASY_LOCALIZATION WIDGET: Wrap the entire app
    EasyLocalization(
      supportedLocales: supportedAppLocales,
      path: 'assets/lang', // The folder with your JSON files
      // assetLoader: const JsonAssetLoader(), // Use the JSON loader
      fallbackLocale: const Locale('en'), // Fallback to English
      saveLocale: true,
      useOnlyLangCode: true, // Use only language code (en, ru, uz)

      child: MultiProvider(
        providers: [
          Provider<UserRepository>(
            create: (context) => UserRepository(UserService()),
          ),
          Provider<UserService>(create: (_) => UserService()),
          ChangeNotifierProvider<UserNotifier>(
            create: (context) => UserNotifier(context.read<UserService>()),
          ),
          // ... other providers ...
        ],
        child: const MyApp(),
      ),
    ),
  );
}

/// ⚡ OPTIMIZATION: Initialize non-critical services in background
/// These don't block auth/UI, so they can run after splash shows
void _initializeDeferredServices() {
  Future.microtask(() async {
    try {
      // Initialize MobileAds (ads load lazily anyway)
      await MobileAds.instance.initialize();
      debugPrint('✅ MobileAds initialized in background');

      // Initialize Crashlytics (error reporting can wait)
      await CrashlyticsService.initialize();
      debugPrint('✅ Crashlytics initialized in background');
    } catch (e) {
      debugPrint('⚠️ Error initializing deferred services: $e');
    }
  });
}

class AppRoutes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/home';
  static const paywall = '/paywall';

  static Map<String, WidgetBuilder> routes = {
    splash: (_) => const SplashScreen(),
    onboarding: (_) => const OnboardingScreen(),
    login: (_) => const LoginScreen(),
    signup: (_) => const SignupScreen(),
    home: (_) => const HomeScreen(),
    paywall: (_) => const PaywallScreen(),
    // The reset password screen will be shown when the deep link is triggered
  };
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();

    // ⚡ OPTIMIZATION: Defer all non-critical initialization to background
    // This keeps the app responsive and splash screen appears immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initializeDeferredServices();
      _initDeepLinks();
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    // Handle link when app is started from cold boot
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 Incoming Deep Link: $uri');

    // 1. Handle standard Firebase HTTPS links
    if (uri.queryParameters.containsKey('oobCode') &&
        (uri.queryParameters['mode'] == 'resetPassword' || 
         uri.path.contains('/auth/action'))) {
      final oobCode = uri.queryParameters['oobCode']!;
      _navigateToReset(oobCode);
    } 
    // 2. Handle our custom Magic Scheme: ideaboost://reset-password?oobCode=...
    else if (uri.scheme == 'ideaboost' && uri.host == 'reset-password') {
      final oobCode = uri.queryParameters['oobCode'];
      if (oobCode != null) _navigateToReset(oobCode);
    }
  }

  void _navigateToReset(String oobCode) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(oobCode: oobCode),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// Initialize services that don't need to block app startup
  /// These run in the background after splash screen is shown
  Future<void> _initializeDeferredServices() async {
    try {
      debugPrint('⏳ Starting deferred initialization...');

      // Initialize MobileAds (ads won't show immediately anyway)
      await MobileAds.instance.initialize();
      debugPrint('✅ MobileAds initialized');

      // Initialize Crashlytics (error reporting can be deferred)
      await CrashlyticsService.initialize();
      debugPrint('✅ Crashlytics initialized');

      // Initialize device language
      _initializeDeviceLanguage();

      debugPrint('✅ All deferred services initialized');
    } catch (e) {
      debugPrint('⚠️ Error in deferred initialization: $e');
    }
  }

  /// Initialize device language for new/unauthenticated users only
  ///
  /// ⚠️ IMPORTANT: Skip device language initialization if user is already authenticated,
  /// since the splash screen or login screen will handle language restoration from Firestore.
  /// Only set device language for first-time app launch (no user logged in).
  void _initializeDeviceLanguage() {
    try {
      final authRepo = AuthRepository(UserService());
      final currentUser = authRepo.getCurrentUser();

      // Only initialize device language if NO USER is logged in
      // (splash screen will restore user's saved language after auth check)
      if (currentUser == null) {
        final currentLocale = context.locale;
        final deviceLangCode = LanguageService.getDeviceLanguageCode();

        if (currentLocale.languageCode != deviceLangCode) {
          context.setLocale(Locale(deviceLangCode));
          debugPrint('🌍 App launched with device language: $deviceLangCode');
        }
      } else {
        debugPrint(
          '🔐 User already logged in - skipping device language initialization. User language will be restored by splash screen.',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error initializing device language: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository(UserService());

    return MultiProvider(
      providers: [
        Provider<UserRepository>(
          create: (context) => UserRepository(UserService()),
        ),
        Provider<AuthRepository>.value(value: authRepo),
        ChangeNotifierProvider<LoginViewModel>(
          create: (_) => LoginViewModel(authRepo),
        ),
        ChangeNotifierProvider<SignupViewModel>(
          create: (_) => SignupViewModel(authRepo),
        ),
        // ChangeNotifierProvider<ProfileViewModel>(
        //   create: (_) => ProfileViewModel()..loadUserData(),
        // ),
      ],
      child: MaterialApp(
        // ADD navigatorKey HERE — This is the second (and final) required change
        navigatorKey: navigatorKey,

        // 4. LOCALIZATION SETUP: Pass delegates and locale to MaterialApp
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,

        // 5. EXAMPLE USAGE: Use a translation key and .tr()
        title:
            'IdeaBoost', // Static — avoids 'key not found' warning before locale JSON loads
        debugShowCheckedModeBanner: false,
        color: const Color(0xFF1A1A2E), // Window background color
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: const Color(0xFF1A1A2E),
          canvasColor: const Color(0xFF1A1A2E),
          dialogBackgroundColor: const Color(0xFF1A1A2E),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00D4FF),
            brightness: Brightness.dark,
            background: const Color(0xFF1A1A2E),
            surface: const Color(0xFF1A1A2E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1A1A2E),
            elevation: 0,
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.routes,
      ),
    );
  }
}
