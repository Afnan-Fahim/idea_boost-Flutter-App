// lib/modules/auth/view/verification_bottom_sheet.dart
import 'dart:async';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerificationBottomSheet extends StatefulWidget {
  final String email;

  const VerificationBottomSheet({super.key, required this.email});

  static Future<bool?> show(BuildContext context, String email) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VerificationBottomSheet(email: email),
    );
  }

  @override
  State<VerificationBottomSheet> createState() => _VerificationBottomSheetState();
}

class _VerificationBottomSheetState extends State<VerificationBottomSheet> {
  Timer? _timer;
  bool _isResending = false;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        if (user.emailVerified && mounted) {
          timer.cancel();
          setState(() {
             _isVerified = true;
          });
          
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'emailVerified': true});
          } catch (_) {}

          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      }
    });
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('signup.verification_email_sent'.tr()),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isResending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const neonBlue = Color(0xFF00E5FF);
    const backgroundColor = Color(0xFF0D1B4C);
    const surfaceColor = Color(0xFF1A2A5A);
    const textColor = Colors.white;

    final bw = MediaQuery.of(context).size.width;
    final bh = MediaQuery.of(context).size.height;
    double bs(double v) => v * bw / 390;
    double bsv(double v) => v * bh / 844;
    double bfs(double v) => (v * bw / 390).clamp(v * 0.85, v * 1.4);

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, false);
        return false;
      },
      child: Wrap(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(bs(24))),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(bs(24), bsv(24), bs(24), bsv(40)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(bs(16)),
                    decoration: BoxDecoration(
                      color: neonBlue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isVerified ? Icons.check_circle_outline : Icons.mark_email_unread_outlined,
                      color: neonBlue,
                      size: bs(40),
                    ),
                  ),
                  SizedBox(height: bsv(20)),
                  AutoSizeText(
                    'signup.verify_email_title'.tr(),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: bfs(22),
                    ),
                    maxLines: 3,
                    minFontSize: 16,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: bsv(12)),
                  Text(
                    'signup.verify_email_subtitle'.tr().replaceAll('{0}', widget.email).replaceAll('{}', widget.email),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor.withOpacity(0.8),
                      fontSize: bfs(15),
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: bsv(6)),
                  Text(
                    'signup.check_spam_folder'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontSize: bfs(13),
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: bsv(32)),
                  _isVerified 
                      ? CircularProgressIndicator(color: neonBlue)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: bs(20),
                              width: bs(20),
                              child: CircularProgressIndicator(
                                color: neonBlue,
                                strokeWidth: 2.5,
                              ),
                            ),
                            SizedBox(width: bs(12)),
                            Text(
                              'signup.waiting_for_verification'.tr(),
                              style: TextStyle(
                                color: neonBlue,
                                fontWeight: FontWeight.w600,
                                fontSize: bfs(14),
                              ),
                            ),
                          ],
                        ),
                  if (!_isVerified) ...[
                    SizedBox(height: bsv(32)),
                    SizedBox(
                      width: double.infinity,
                      height: bsv(54),
                      child: TextButton(
                        onPressed: _isResending ? null : _resendEmail,
                        style: TextButton.styleFrom(
                          backgroundColor: surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(bs(12)),
                          ),
                        ),
                        child: _isResending
                            ? SizedBox(
                                height: bs(20),
                                width: bs(20),
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'signup.resend_verification'.tr(),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: bfs(16),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                  // Allow closing dialog if they want to use different email
                  SizedBox(height: bsv(16)),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'login.back'.tr(),
                      style: TextStyle(color: textColor.withOpacity(0.5)),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
