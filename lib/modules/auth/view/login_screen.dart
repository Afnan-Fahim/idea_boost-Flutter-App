// lib/modules/auth/view/login_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/core/services/language_service.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../view_model/login_view_model.dart';
import '../../../data/repository/auth_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verification_bottom_sheet.dart';
import '../../home/view/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Future milestone: set to `true` to enable "Forgot Password" feature.
  static const bool enableForgotPassword = true;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _fades;
  late final List<Animation<Offset>> _slides;
  static const _n = 8;

  @override
  void initState() {
    super.initState();

    // 🌍 Restore device language when returning to login screen (e.g., after logout)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final deviceLang = LanguageService.getDeviceLanguageCode();
        if (context.locale.languageCode != deviceLang) {
          context.setLocale(Locale(deviceLang));
          debugPrint(
            '🌍 LoginScreen: Restored device language after logout: $deviceLang',
          );
        }
      } catch (e) {
        debugPrint('⚠️ LoginScreen: Error restoring device language: $e');
      }
    });

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fades = List.generate(_n, (i) {
      final begin = (i * 0.07).clamp(0.0, 0.55);
      final end = (begin + 0.45).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );
    });
    _slides = List.generate(_n, (i) {
      final begin = (i * 0.07).clamp(0.0, 0.55);
      final end = (begin + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(begin, end, curve: Curves.easeOutCubic),
        ),
      );
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _anim(int i, Widget child) => FadeTransition(
    opacity: _fades[i],
    child: SlideTransition(position: _slides[i], child: child),
  );

  @override
  Widget build(BuildContext context) {
    const neonBlue = Color(0xFF00E5FF);
    const primaryColor = Color(0xFF2196F3);
    const backgroundColor = Color(0xFF0D1B4C);
    const surfaceColor = Color(0xFF1A2A5A);
    const accentColor = Color(0xFFFF6B6B);
    const textColor = Colors.white;
    const subTextColor = Color(0xFFB0BEC5);

    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    // Responsive helpers — scale relative to iPhone 14 (390 x 844)
    double s(double v) => v * w / 390;
    double sv(double v) => v * h / 844;
    double fs(double v) => (v * w / 390).clamp(v * 0.85, v * 1.4);

    return ChangeNotifierProvider(
      create: (_) => LoginViewModel(AuthRepository(UserService())),
      child: Consumer<LoginViewModel>(
        builder: (context, vm, _) {
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              // Do nothing → completely block back navigation
            },
            child: Scaffold(
              backgroundColor: backgroundColor,
              body: SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: s(24),
                    vertical: sv(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 0 — Logo
                      _anim(
                        0,
                        Center(
                          child: Container(
                            height: s(90),
                            width: s(90),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [neonBlue, primaryColor],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(s(22)),
                              boxShadow: [
                                BoxShadow(
                                  color: neonBlue.withOpacity(0.3),
                                  blurRadius: s(20),
                                  offset: Offset(0, s(8)),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(s(22)),
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sv(24)),

                      // 1 — Title + Subtitle
                      _anim(
                        1,
                        Center(
                          child: Column(
                            children: [
                              AutoSizeText(
                                'login.welcome_back'.tr(),
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: fs(30),
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.visible,
                                minFontSize: 24,
                              ),
                              SizedBox(height: sv(6)),
                              AutoSizeText(
                                'login.subtitle'.tr(),
                                textAlign: TextAlign.center, // 👈 add this

                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: fs(14),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.visible,
                                minFontSize: 11,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: sv(40)),

                      // 2 — Email
                      _anim(
                        2,
                        _buildInputField(
                          label: 'login.email_label'.tr(),
                          hint: 'login.email_hint'.tr(),
                          icon: Icons.mail_outline_rounded,
                          onChanged: (v) => vm.email = v,
                          error: vm.email.isNotEmpty && !vm.isEmailValid
                              ? 'login.invalid_email'.tr()
                              : null,
                          neonBlue: neonBlue,
                          surfaceColor: surfaceColor,
                          textColor: textColor,
                          s: s,
                          sv: sv,
                          fs: fs,
                        ),
                      ),
                      SizedBox(height: sv(20)),

                      // 3 — Password + Forgot
                      _anim(
                        3,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPasswordField(
                              label: 'login.password_label'.tr(),
                              hint: 'login.password_hint'.tr(),
                              obscure: vm.obscurePassword,
                              onChanged: (v) => vm.password = v,
                              onToggle: vm.togglePasswordVisibility,
                              neonBlue: neonBlue,
                              surfaceColor: surfaceColor,
                              textColor: textColor,
                              s: s,
                              sv: sv,
                              fs: fs,
                            ),
                            if (LoginScreen.enableForgotPassword) ...[
                              SizedBox(height: sv(10)),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: GestureDetector(
                                  onTap: () => _showForgotPasswordSheet(
                                    context,
                                    neonBlue,
                                    surfaceColor,
                                    textColor,
                                    backgroundColor,
                                  ),
                                  child: AutoSizeText(
                                    'login.forgot_password'.tr(),
                                    style: TextStyle(
                                      color: neonBlue,
                                      fontSize: fs(13),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    minFontSize: 10,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: sv(20)),

                      // 4 — Error + Sign In
                      _anim(
                        4,
                        Column(
                          children: [
                            if (vm.errorMessage != null) ...[
                              Container(
                                padding: EdgeInsets.all(s(12)),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(s(8)),
                                  border: Border.all(
                                    color: accentColor.withOpacity(0.5),
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: accentColor,
                                        size: s(20),
                                      ),
                                      SizedBox(width: s(8)),
                                      Flexible(
                                        child: AutoSizeText(
                                          vm.errorMessage!,
                                          style: TextStyle(
                                            color: accentColor,
                                            fontSize: fs(13),
                                          ),
                                          maxLines: 2,
                                          minFontSize: 10,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: sv(20)),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: sv(54),
                              child: ElevatedButton(
                                onPressed: vm.isLoading
                                    ? null
                                    : () async {
                                        final success = await vm.login();
                                        if (success && context.mounted) {
                                          final user =
                                              FirebaseAuth.instance.currentUser;
                                          if (user != null) {
                                            bool isVerified =
                                                user.emailVerified;
                                            if (!isVerified) {
                                              await user.reload();
                                              isVerified =
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.emailVerified ??
                                                  false;
                                            }
                                            if (!isVerified) {
                                              try {
                                                final userDoc =
                                                    await FirebaseFirestore
                                                        .instance
                                                        .collection('users')
                                                        .doc(user.uid)
                                                        .get();
                                                if (userDoc.exists &&
                                                    userDoc.data()?['emailVerified'] ==
                                                        true) {
                                                  isVerified = true;
                                                }
                                              } catch (_) {}
                                            }

                                            if (!isVerified) {
                                              try {
                                                await user
                                                    .sendEmailVerification();
                                              } catch (_) {}
                                              if (context.mounted) {
                                                final sheetResult =
                                                    await VerificationBottomSheet.show(
                                                      context,
                                                      user.email ?? '',
                                                    );
                                                if (sheetResult != true) return;
                                              }
                                            }
                                          }

                                          // Standard Login Locale setup
                                          final finalUser =
                                              FirebaseAuth.instance.currentUser;
                                          if (finalUser != null &&
                                              context.mounted) {
                                            try {
                                              final userDoc =
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('users')
                                                      .doc(finalUser.uid)
                                                      .get();
                                              if (userDoc.exists &&
                                                  context.mounted) {
                                                final data = userDoc.data();
                                                final savedLanguage =
                                                    data?['language']
                                                        as String?;
                                                if (savedLanguage != null &&
                                                    savedLanguage.isNotEmpty) {
                                                  await context.setLocale(
                                                    Locale(savedLanguage),
                                                  );
                                                }
                                              }
                                            } catch (e) {}
                                          }
                                          if (context.mounted) {
                                            Navigator.pushAndRemoveUntil(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const HomeScreen(),
                                              ),
                                              (route) => false,
                                            );
                                          }
                                        } else if (context.mounted) {
                                          showSnackBarSafe(
                                            context,
                                            SnackBar(
                                              content: AutoSizeText(
                                                vm.errorMessage ??
                                                    'login.failed'.tr(),
                                                maxLines: 2,
                                                minFontSize: 10,
                                                textAlign: TextAlign.center,
                                              ),
                                              backgroundColor: accentColor,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: neonBlue,
                                  disabledBackgroundColor: neonBlue.withOpacity(
                                    0.5,
                                  ),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(s(12)),
                                  ),
                                ),
                                child: vm.isLoading
                                    ? SizedBox(
                                        height: s(24),
                                        width: s(24),
                                        child: CircularProgressIndicator(
                                          color: backgroundColor,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : AutoSizeText(
                                        'login.sign_in'.tr(),
                                        style: TextStyle(
                                          color: backgroundColor,
                                          fontSize: fs(16),
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 12,
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: sv(22)),

                      // 5 — Divider
                      _anim(
                        5,
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.grey[700],
                                thickness: 0.8,
                              ),
                            ),
                            Flexible(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: s(16),
                                ),
                                child: AutoSizeText(
                                  'login.or_continue_with'.tr(),
                                  style: TextStyle(
                                    color: subTextColor,
                                    fontSize: fs(13),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  minFontSize: 10,
                                  softWrap: true,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.grey[700],
                                thickness: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: sv(18)),

                      // 6 — Social Buttons (No Fade - Full Opacity)
                      Row(
                        children: [
                          Expanded(
                            child: _buildSocialButton(
                              icon: 'assets/google.png',
                              label: 'Google',
                              isLoading: vm.isLoading,
                              onPressed: () async {
                                // Show the dialog hint message
                                if (context.mounted) {
                                  _showGoogleAuthDialog(
                                    context,
                                    neonBlue,
                                    backgroundColor,
                                    textColor,
                                    s,
                                    fs,
                                  );
                                }

                                final success = await vm.loginWithGoogle();
                                if (success && context.mounted) {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  if (user != null) {
                                    try {
                                      final userDoc = await FirebaseFirestore
                                          .instance
                                          .collection('users')
                                          .doc(user.uid)
                                          .get();
                                      if (userDoc.exists && context.mounted) {
                                        final data = userDoc.data();
                                        final savedLanguage =
                                            data?['language'] as String?;
                                        if (savedLanguage != null &&
                                            savedLanguage.isNotEmpty) {
                                          await context.setLocale(
                                            Locale(savedLanguage),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      // Continue with default language
                                    }
                                  }
                                  if (context.mounted) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const HomeScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                }
                              },
                              s: s,
                              sv: sv,
                              fs: fs,
                            ),
                          ),
                          SizedBox(width: s(12)),
                          Expanded(
                            child: _buildSocialButton(
                              icon: 'assets/apple.png',
                              label: 'Apple',
                              isLoading: vm.isLoading,
                              onPressed: () async {
                                final success = await vm.loginWithApple();
                                if (success && context.mounted) {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  if (user != null) {
                                    try {
                                      final userDoc = await FirebaseFirestore
                                          .instance
                                          .collection('users')
                                          .doc(user.uid)
                                          .get();
                                      if (userDoc.exists && context.mounted) {
                                        final data = userDoc.data();
                                        final savedLanguage =
                                            data?['language'] as String?;
                                        if (savedLanguage != null &&
                                            savedLanguage.isNotEmpty) {
                                          await context.setLocale(
                                            Locale(savedLanguage),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      // Continue with default language
                                    }
                                  }
                                  if (context.mounted) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const HomeScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                }
                              },
                              s: s,
                              sv: sv,
                              fs: fs,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: sv(22)),

                      // 7 — Sign Up Link
                      _anim(
                        7,
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              AutoSizeText(
                                'login.no_account'.tr(),
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: fs(14),
                                ),
                                maxLines: 1,
                                minFontSize: 11,
                              ),
                              GestureDetector(
                                onTap: () =>
                                    Navigator.pushNamed(context, "/signup"),
                                child: AutoSizeText(
                                  'login.sign_up'.tr(),
                                  style: TextStyle(
                                    color: neonBlue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: fs(14),
                                  ),
                                  maxLines: 1,
                                  minFontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: sv(20)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────── Forgot Password Bottom Sheet ────────────
  static void _showForgotPasswordSheet(
    BuildContext context,
    Color neonBlue,
    Color surfaceColor,
    Color textColor,
    Color backgroundColor,
  ) {
    final emailController = TextEditingController();
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bw = MediaQuery.of(ctx).size.width;
        final bh = MediaQuery.of(ctx).size.height;
        double bs(double v) => v * bw / 390;
        double bsv(double v) => v * bh / 844;
        double bfs(double v) => (v * bw / 390).clamp(v * 0.85, v * 1.4);

        return StatefulBuilder(
          builder: (ctx, setState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Wrap(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(bs(24)),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      bs(24),
                      bsv(12),
                      bs(24),
                      bsv(32),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: bs(40),
                          height: bsv(4),
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        SizedBox(height: bsv(24)),
                        // Icon
                        Container(
                          padding: EdgeInsets.all(bs(16)),
                          decoration: BoxDecoration(
                            color: neonBlue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lock_reset_rounded,
                            color: neonBlue,
                            size: bs(32),
                          ),
                        ),
                        SizedBox(height: bsv(20)),
                        AutoSizeText(
                          'login.forgot_password'.tr(),
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: bfs(20),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                          minFontSize: 16,
                        ),
                        SizedBox(height: bsv(8)),
                        AutoSizeText(
                          'login.forgot_password_desc'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor.withOpacity(0.6),
                            fontSize: bfs(14),
                            height: 1.4,
                          ),
                          maxLines: 2,
                          minFontSize: 11,
                        ),
                        SizedBox(height: bsv(24)),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: textColor, fontSize: bfs(15)),
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'login.email_hint'.tr(),
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: bfs(14),
                            ),
                            prefixIcon: Icon(
                              Icons.mail_outline_rounded,
                              color: neonBlue,
                              size: bs(20),
                            ),
                            filled: true,
                            fillColor: surfaceColor,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: bsv(16),
                              horizontal: bs(12),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(bs(12)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(bs(12)),
                              borderSide: BorderSide(color: neonBlue, width: 2),
                            ),
                          ),
                        ),
                        SizedBox(height: bsv(20)),
                        SizedBox(
                          width: double.infinity,
                          height: bsv(52),
                          child: ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    final email = emailController.text.trim();
                                    if (email.isEmpty) return;
                                    setState(() => isLoading = true);
                                    try {
                                      await FirebaseAuth.instance
                                          .sendPasswordResetEmail(email: email);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (context.mounted) {
                                        showSnackBarSafe(
                                          context,
                                          SnackBar(
                                            content: AutoSizeText(
                                              'login.reset_email_sent'.tr(),
                                              maxLines: 2,
                                              minFontSize: 10,
                                              textAlign: TextAlign.center,
                                            ),
                                            backgroundColor: Colors.green,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } on FirebaseAuthException catch (e) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (context.mounted) {
                                        // Map specific Firebase error codes to user-friendly messages; use generic for others
                                        final message = () {
                                          switch (e.code) {
                                            case 'invalid-email':
                                              return 'errors.invalid_email_format'
                                                  .tr();
                                            case 'user-not-found':
                                              return 'errors.account_not_found'
                                                  .tr();
                                            case 'network-request-failed':
                                              return 'errors.no_internet'.tr();
                                            default:
                                              return 'errors.something_went_wrong_try_again'
                                                  .tr();
                                          }
                                        }();
                                        showSnackBarSafe(
                                          context,
                                          SnackBar(
                                            content: AutoSizeText(
                                              message,
                                              maxLines: 2,
                                              minFontSize: 10,
                                              textAlign: TextAlign.center,
                                            ),
                                            backgroundColor: const Color(
                                              0xFFFF6B6B,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (ctx.mounted) {
                                        setState(() => isLoading = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonBlue,
                              disabledBackgroundColor: neonBlue.withOpacity(
                                0.5,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(bs(12)),
                              ),
                            ),
                            child: isLoading
                                ? SizedBox(
                                    height: bs(22),
                                    width: bs(22),
                                    child: CircularProgressIndicator(
                                      color: backgroundColor,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : AutoSizeText(
                                    'login.send_reset_link'.tr(),
                                    style: TextStyle(
                                      fontSize: bfs(16),
                                      fontWeight: FontWeight.w600,
                                      color: backgroundColor,
                                    ),
                                    maxLines: 1,
                                    minFontSize: 12,
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────── Helper Widgets ────────────
  static Widget _buildInputField({
    required String label,
    required String hint,
    required IconData icon,
    required Function(String) onChanged,
    String? error,
    required Color neonBlue,
    required Color surfaceColor,
    required Color textColor,
    required double Function(double) s,
    required double Function(double) sv,
    required double Function(double) fs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoSizeText(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: fs(14),
            letterSpacing: 0.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.visible,
          minFontSize: 11,
        ),
        SizedBox(height: sv(8)),
        TextField(
          onChanged: onChanged,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: textColor, fontSize: fs(15)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: fs(14)),
            prefixIcon: Icon(icon, color: neonBlue, size: s(20)),
            filled: true,
            fillColor: surfaceColor,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              vertical: sv(16),
              horizontal: s(12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s(12)),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s(12)),
              borderSide: BorderSide(color: neonBlue, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s(12)),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 2),
            ),
            errorText: error,
          ),
        ),
      ],
    );
  }

  static Widget _buildPasswordField({
    required String label,
    required String hint,
    required bool obscure,
    required Function(String) onChanged,
    required VoidCallback onToggle,
    required Color neonBlue,
    required Color surfaceColor,
    required Color textColor,
    required double Function(double) s,
    required double Function(double) sv,
    required double Function(double) fs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoSizeText(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: fs(14),
            letterSpacing: 0.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.visible,
          minFontSize: 11,
        ),
        SizedBox(height: sv(8)),
        TextField(
          onChanged: onChanged,
          obscureText: obscure,
          style: TextStyle(color: textColor, fontSize: fs(15)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: fs(14)),
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: neonBlue,
              size: s(20),
            ),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: neonBlue,
                size: s(20),
              ),
            ),
            filled: true,
            fillColor: surfaceColor,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              vertical: sv(16),
              horizontal: s(12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s(12)),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(s(12)),
              borderSide: BorderSide(color: neonBlue, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  static void _showGoogleAuthDialog(
    BuildContext context,
    Color neonBlue,
    Color backgroundColor,
    Color textColor,
    double Function(double) s,
    double Function(double) fs,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black45,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(20)),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(s(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: s(20),
                    offset: Offset(0, s(8)),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AutoSizeText(
                    'login.google_auth_dialog_hint'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: fs(14),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    minFontSize: 11,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  static Widget _buildSocialButton({
    required String icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    required double Function(double) s,
    required double Function(double) sv,
    required double Function(double) fs,
  }) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: Image.asset(icon, height: s(20), width: s(20)),
      label: AutoSizeText(
        label,
        style: TextStyle(fontSize: fs(14), fontWeight: FontWeight.w600),
        maxLines: 1,
        minFontSize: 11,
        textAlign: TextAlign.center,
      ),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: sv(14)),
        side: BorderSide(color: Colors.grey[700]!, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s(12)),
        ),
        foregroundColor: Colors.white,
      ),
    );
  }
}
