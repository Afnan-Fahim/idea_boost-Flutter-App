// lib/modules/auth/view/signup_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_model/signup_view_model.dart';
import '../../../data/repository/auth_repository.dart';
import '../../../core/services/user_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/utils/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verification_bottom_sheet.dart';
import '../../home/view/home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _fades;
  late final List<Animation<Offset>> _slides;
  static const _n = 9;

  @override
  void initState() {
    super.initState();

    // 🌍 Restore device language when returning to signup screen (e.g., after logout)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final deviceLang = LanguageService.getDeviceLanguageCode();
        if (context.locale.languageCode != deviceLang) {
          context.setLocale(Locale(deviceLang));
          debugPrint(
            '🌍 SignupScreen: Restored device language after logout: $deviceLang',
          );
        }
      } catch (e) {
        debugPrint('⚠️ SignupScreen: Error restoring device language: $e');
      }
    });

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fades = List.generate(_n, (i) {
      final begin = (i * 0.06).clamp(0.0, 0.55);
      final end = (begin + 0.45).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );
    });
    _slides = List.generate(_n, (i) {
      final begin = (i * 0.06).clamp(0.0, 0.55);
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
    double s(double v) => v * w / 390;
    double sv(double v) => v * h / 844;
    double fs(double v) => (v * w / 390).clamp(v * 0.85, v * 1.4);

    return ChangeNotifierProvider(
      create: (_) => SignupViewModel(AuthRepository(UserService())),
      child: Consumer<SignupViewModel>(
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
                  physics: const AlwaysScrollableScrollPhysics(),
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
                      SizedBox(height: sv(16)),

                      // 1 — Title + Subtitle
                      _anim(
                        1,
                        Center(
                          child: Column(
                            children: [
                              AutoSizeText(
                                'signup.create_account'.tr(),
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
                                'signup.subtitle'.tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: fs(14),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.visible,
                                minFontSize: 11,
                                //textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: sv(32)),

                      // 2 — Full Name
                      _anim(
                        2,
                        _buildInputField(
                          label: 'signup.full_name_label'.tr(),
                          hint: 'signup.full_name_hint'.tr(),
                          icon: Icons.person_outline_rounded,
                          onChanged: (v) => vm.name = v,
                          neonBlue: neonBlue,
                          surfaceColor: surfaceColor,
                          textColor: textColor,
                          s: s,
                          sv: sv,
                          fs: fs,
                        ),
                      ),
                      SizedBox(height: sv(18)),

                      // 3 — Email
                      _anim(
                        3,
                        _buildInputField(
                          label: 'signup.email_label'.tr(),
                          hint: 'signup.email_hint'.tr(),
                          icon: Icons.mail_outline_rounded,
                          onChanged: (v) => vm.email = v,
                          error: vm.email.isNotEmpty && !vm.isEmailValid
                              ? 'signup.invalid_email'.tr()
                              : null,
                          neonBlue: neonBlue,
                          surfaceColor: surfaceColor,
                          textColor: textColor,
                          s: s,
                          sv: sv,
                          fs: fs,
                        ),
                      ),
                      SizedBox(height: sv(18)),

                      // 4 — Password
                      _anim(
                        4,
                        _buildPasswordField(
                          label: 'signup.password_label'.tr(),
                          hint: 'signup.password_hint'.tr(),
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
                      ),
                      SizedBox(height: sv(18)),

                      // 5 — Confirm Password
                      _anim(
                        5,
                        _buildPasswordField(
                          label: 'signup.confirm_password_label'.tr(),
                          hint: 'signup.confirm_password_hint'.tr(),
                          obscure: vm.obscureConfirmPassword,
                          onChanged: (v) => vm.confirmPassword = v,
                          onToggle: vm.toggleConfirmPasswordVisibility,
                          neonBlue: neonBlue,
                          surfaceColor: surfaceColor,
                          textColor: textColor,
                          s: s,
                          sv: sv,
                          fs: fs,
                        ),
                      ),
                      SizedBox(height: sv(18)),

                      // 6 — Error + Create Account Button
                      _anim(
                        6,
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
                              SizedBox(height: sv(18)),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: sv(54),
                              child: ElevatedButton(
                                onPressed: vm.isLoading
                                    ? null
                                    : () async {
                                        final success = await vm.signup();
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
                                                await vm.sendCustomVerificationEmail(
                                                  user.email ?? '',
                                                );
                                              } catch (_) {}
                                              if (context.mounted) {
                                                final sheetResult =
                                                    await VerificationBottomSheet.show(
                                                      context,
                                                      user.email ?? '',
                                                    );
                                                if (sheetResult == true &&
                                                    context.mounted) {
                                                  // 🌍 PHASE 1.1: Set device language for new user after signup
                                                  await LanguageService.setAppLocale(
                                                    context,
                                                    LanguageService.getDeviceLanguageCode(),
                                                  );
                                                  Navigator.pushAndRemoveUntil(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const HomeScreen(),
                                                    ),
                                                    (route) => false,
                                                  );
                                                }
                                              }
                                            } else {
                                              if (context.mounted) {
                                                // 🌍 PHASE 1.1: Set device language for new user after signup
                                                await LanguageService.setAppLocale(
                                                  context,
                                                  LanguageService.getDeviceLanguageCode(),
                                                );
                                                Navigator.pushAndRemoveUntil(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const HomeScreen(),
                                                  ),
                                                  (route) => false,
                                                );
                                              }
                                            }
                                          } else {
                                            if (context.mounted)
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
                                                    'signup.failed'.tr(),
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
                                        'signup.create_account_button'.tr(),
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
                      SizedBox(height: sv(14)),

                      // 6 — Divider
                      _anim(
                        6,
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
                                  'signup.or_continue_with'.tr(),
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
                      SizedBox(height: sv(14)),

                      // 7 — Social Buttons (No Fade - Full Opacity)
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

                                final success = await vm.signupWithGoogle();
                                if (success && context.mounted) {
                                  // 🌍 PHASE 1.1: Set device language for new user after Google signup
                                  await LanguageService.setAppLocale(
                                    context,
                                    LanguageService.getDeviceLanguageCode(),
                                  );
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const HomeScreen(),
                                    ),
                                    (route) => false,
                                  );
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
                              color: Colors.white,
                              isLoading: vm.isLoading,
                              onPressed: () async {
                                final success = await vm.signupWithApple();
                                if (success && context.mounted) {
                                  // 🌍 PHASE 1.1: Set device language for new user after Apple signup
                                  await LanguageService.setAppLocale(
                                    context,
                                    LanguageService.getDeviceLanguageCode(),
                                  );
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const HomeScreen(),
                                    ),
                                    (route) => false,
                                  );
                                }
                              },
                              s: s,
                              sv: sv,
                              fs: fs,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: sv(18)),

                      // 8 — Login Link
                      _anim(
                        8,
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              AutoSizeText(
                                'signup.have_account'.tr(),
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: fs(14),
                                ),
                                maxLines: 1,
                                minFontSize: 11,
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: AutoSizeText(
                                  'signup.login'.tr(),
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
                    'signup.google_auth_dialog_hint'.tr(),
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
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: neonBlue,
                size: s(20),
              ),
              onPressed: onToggle,
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

  static Widget _buildSocialButton({
    required String icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    required double Function(double) s,
    required double Function(double) sv,
    required double Function(double) fs,
    Color? color,
  }) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: Image.asset(icon, height: s(20), width: s(20), color: color),
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
