// lib/modules/comment_generator/view/comment_generator_screen.dart
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/data/models/comments_model.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/modules/comment_generator/view_model/comment_generator_view_model.dart';
import 'package:provider/provider.dart';
import 'package:ideaboost/core/services/admob_service.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/data/repository/user_repository.dart';

class CommentGeneratorScreen extends StatelessWidget {
  final String? initialInput;
  final String? initialRewardToken;
  const CommentGeneratorScreen({
    Key? key,
    this.initialInput,
    this.initialRewardToken,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CommentGeneratorViewModel(
        UserRepository(UserService()),
        initialRewardToken: initialRewardToken,
      ),
      child: CommentGeneratorScreenBody(initialInput: initialInput),
    );
  }
}

class CommentGeneratorScreenBody extends StatefulWidget {
  final String? initialInput;
  const CommentGeneratorScreenBody({Key? key, this.initialInput})
    : super(key: key);

  @override
  State<CommentGeneratorScreenBody> createState() =>
      _CommentGeneratorScreenBodyState();
}

class _CommentGeneratorScreenBodyState extends State<CommentGeneratorScreenBody>
    with SingleTickerProviderStateMixin {
  // ╔══════════════════════════════════════════════════════════════╗
  // ║  TOGGLE: set to false to revert to original UI              ║
  // ╚══════════════════════════════════════════════════════════════╝
  static const bool useNewUI = true;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isButtonDebouncing = false;

  // Streaming text animation state
  final Map<String, Map<int, String>> _displayedTexts = {};
  final Map<String, Map<int, Timer?>> _streamTimers = {};
  CommentOutput? _lastStreamedOutput;

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;
  bool _shimmerRunning = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerAnim = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = Provider.of<CommentGeneratorViewModel>(context, listen: false);
      await vm.checkDailyLimitAndShowDialogIfNeeded(context);
      if (widget.initialInput != null && widget.initialInput!.isNotEmpty) {
        _textController.text = widget.initialInput!;
        vm.updateInput(widget.initialInput!);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _shimmerCtrl.dispose();
    for (final group in _streamTimers.values) {
      for (final timer in group.values) {
        timer?.cancel();
      }
    }
    super.dispose();
  }

  void _showLimitExceededDialog(
    BuildContext context,
    CommentGeneratorViewModel vm, {
    bool isPro = false,
  }) {
    if (isPro) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent,
                        AppColors.accent.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                AutoSizeText(
                  'errors.pro_daily_limit_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  minFontSize: 16,
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'errors.pro_daily_limit_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  minFontSize: 12,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'general.ok'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.surface,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.warning,
                            AppColors.warning.withOpacity(0.7),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AutoSizeText(
                      'comment_generator.limit_dialog_title'.tr(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      minFontSize: 18,
                    ),
                    const SizedBox(height: 12),
                    AutoSizeText(
                      'comment_generator.limit_dialog_subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      minFontSize: 12,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await adMobService.showRewardedAd(
                                context: context,
                                onRewarded: () async {
                                  //await vm.increaseLimitByAdReward();

                                  showSnackBarSafe(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        'comment_generator.snack_reward'.tr(),
                                        textAlign: TextAlign.center,
                                      ),
                                      backgroundColor: AppColors.success,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                  // Auto-retry generation after ad reward
                                  if (vm.output != null) {
                                    await vm.regenerate(
                                      language: getAppLanguageCode(context),
                                      locale: getValidOsLocale(),
                                    );
                                  } else {
                                    await vm.generateComments(
                                      language: getAppLanguageCode(context),
                                      locale: getValidOsLocale(),
                                    );
                                  }
                                },
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.success,
                              side: BorderSide(
                                color: AppColors.success.withOpacity(0.3),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_circle_outline, size: 20),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'comment_generator.reward_button'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              showSnackBarSafe(
                                context,
                                SnackBar(
                                  content: Text(
                                    'comment_generator.snack_pro_navigating'
                                        .tr(),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                              // TODO: Navigate to PRO screen
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'comment_generator.go_pro_button'.tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message, {Color? color}) {
    showSnackBarSafe(
      context,
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color ?? AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show style selection modal for re-generation
  /// Show tone selection bottom sheet (matches shot_ideas / make_viral UI)
  void _showToneSheet(
    BuildContext context,
    CommentGeneratorViewModel vm, {
    bool isRegeneration = false,
  }) {
    if (isRegeneration) {
      vm.restoreLastGeneratedTones();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E24),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          color: Color(0xFF06B6D4),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AutoSizeText(
                            isRegeneration
                                ? 'comment_generator.regenerate_title'.tr()
                                : 'comment_generator.tone_selection_title'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            minFontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'comment_generator.tone_selection_subtitle'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: vm.availableTones.map((tone) {
                              final isSelected = vm.isToneSelected(tone);
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  vm.toggleTone(tone);
                                  setSheetState(() {});
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(
                                            0xFF06B6D4,
                                          ).withOpacity(0.15)
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(
                                              0xFF06B6D4,
                                            ).withOpacity(0.5)
                                          : Colors.white.withOpacity(0.08),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: AutoSizeText(
                                    vm.getToneLabel(tone),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? const Color(0xFF06B6D4)
                                          : Colors.white70,
                                    ),
                                    maxLines: 1,
                                    minFontSize: 10,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          AutoSizeText(
                            'comment_generator.tone_selection_min'.tr(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            minFontSize: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isRegeneration)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: vm.isLoading
                              ? null
                              : () async {
                                  if (_isButtonDebouncing) return;
                                  _isButtonDebouncing = true;

                                  vm.commitSelectedTones();
                                  Navigator.pop(ctx);
                                  HapticFeedback.mediumImpact();

                                  await vm.regenerate(
                                    language: context.locale.languageCode,
                                    locale: getValidOsLocale(),
                                  );

                                  if (mounted) {
                                    _isButtonDebouncing = false;
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF06B6D4),
                            disabledBackgroundColor: Colors.white.withOpacity(
                              0.08,
                            ),
                            disabledForegroundColor: Colors.white.withOpacity(
                              0.35,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: vm.isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'comment_generator.generating'.tr(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'comment_generator.regenerate_button'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ▶ NEW GLASSMORPHISM UI — Replaces old build + _buildInputSection +
  // ══════════════════════════════════════════════════════════════════════
  // ▶ NEW GLASSMORPHISM UI — Replaces old build + _buildInputSection +
  //   _buildResultsSection below. Old code is commented out at the
  //   very bottom of this file for reference.
  // ══════════════════════════════════════════════════════════════════════

  void _copyComment(BuildContext context, String comment) {
    Clipboard.setData(ClipboardData(text: comment)).then((_) {
      _showFeedback(context, 'comment_generator.snack_copy_single'.tr());
    });
  }

  void _copyAllComments(
    BuildContext context,
    CommentOutput output,
    CommentGeneratorViewModel vm,
  ) {
    final combinedText = output.groups
        .map(
          (group) =>
              "--- ${vm.getToneLabel(group.tone)} ---\n${group.comments.join('\n')}",
        )
        .join('\n\n');
    Clipboard.setData(ClipboardData(text: combinedText)).then((_) {
      _showFeedback(
        context,
        'comment_generator.snack_copy_all'.tr(),
        color: AppColors.success,
      );
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // ▶ NEW GLASSMORPHISM UI — Replaces old build + _buildInputSection +
  //   _buildResultsSection below. Old code is commented out at the
  //   very bottom of this file for reference.
  // ══════════════════════════════════════════════════════════════════════

  void _startStreamingText(CommentOutput output) {
    if (_lastStreamedOutput == output) return;
    _lastStreamedOutput = output;
    for (final group in _streamTimers.values) {
      for (final timer in group.values) {
        timer?.cancel();
      }
    }
    _streamTimers.clear();
    _displayedTexts.clear();

    for (final group in output.groups) {
      _displayedTexts[group.tone] = {};
      _streamTimers[group.tone] = {};
      for (int i = 0; i < group.comments.length; i++) {
        final full = group.comments[i];
        _displayedTexts[group.tone]![i] = '';
        int charIdx = 0;
        _streamTimers[group.tone]![i] = Timer.periodic(
          const Duration(milliseconds: 35),
          (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            if (charIdx >= full.length) {
              timer.cancel();
              return;
            }
            // Add 8 chars per tick — smooth but lightweight
            final end = (charIdx + 8).clamp(0, full.length);
            setState(() {
              _displayedTexts[group.tone]![i] = full.substring(0, end);
            });
            charIdx = end;
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CommentGeneratorViewModel>(
      builder: (context, vm, child) {
        // Start/stop shimmer only when loading state actually changes
        if (vm.isLoading && vm.output == null) {
          if (!_shimmerRunning) {
            _shimmerCtrl.repeat();
            _shimmerRunning = true;
          }
        } else if (_shimmerRunning) {
          _shimmerCtrl.stop();
          _shimmerRunning = false;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final error = vm.errorMessage;
          if (error != null) {
            if (error.contains("Daily limit exceeded") ||
                error.contains("daily limit")) {
              vm.clearError();
              final userRepo = Provider.of<UserRepository>(
                context,
                listen: false,
              );
              final user = await userRepo.getCurrentUser();
              _showLimitExceededDialog(context, vm, isPro: user?.isPro == true);
            } else {
              _showFeedback(context, error, color: AppColors.error);
              vm.clearError();
            }
          }
          // Start streaming when output arrives
          if (vm.output != null && !vm.isLoading) {
            _startStreamingText(vm.output!);
          }
        });

        // ── TOGGLE: New glassmorphism UI vs Original UI ──
        return PopScope(
          canPop: !vm.isLoading,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && vm.isLoading) {
              // Generation in progress - prevent navigation
              return;
            }
          },
          child: AbsorbPointer(
            absorbing: vm.isLoading,
            child: useNewUI
                ? _buildNewUI(context, vm)
                : _buildOldUI(context, vm),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ▶ NEW GLASSMORPHISM UI
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildNewUI(BuildContext context, CommentGeneratorViewModel vm) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    double s(double v) => v * w / 390;
    double sv(double v) => v * h / 844;
    double fs(double v) => (v * w / 390).clamp(v * 0.85, v * 1.35);

    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ─── App Bar ───
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: s(16),
                  vertical: sv(10),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (vm.isLoading) return;
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: s(34),
                        height: s(34),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(s(8)),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: s(14),
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: s(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(
                            'comment_generator.title'.tr(),
                            style: TextStyle(
                              fontSize: fs(18),
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 2,
                            minFontSize: 11,
                          ),
                          if (vm.isLoading)
                            AutoSizeText(
                              'comment_generator.generating'.tr(),
                              style: TextStyle(
                                fontSize: fs(12),
                                color: AppColors.accent,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              minFontSize: 10,
                            ),
                        ],
                      ),
                    ),
                    if (vm.output != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.refresh_rounded,
                              size: s(19),
                              color: AppColors.textPrimary,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: BoxConstraints(
                              minWidth: s(28),
                              minHeight: s(28),
                            ),
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              _showToneSheet(context, vm, isRegeneration: true);
                            },
                          ),
                          SizedBox(width: s(4)),
                          IconButton(
                            icon: Icon(
                              Icons.copy_all_rounded,
                              size: s(19),
                              color: AppColors.textPrimary,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: BoxConstraints(
                              minWidth: s(28),
                              minHeight: s(28),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _copyAllComments(context, vm.output!, vm);
                            },
                          ),
                          SizedBox(width: s(4)),
                          IconButton(
                            icon: Icon(
                              vm.isFavorited
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: s(19),
                              color: vm.isFavorited
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: BoxConstraints(
                              minWidth: s(28),
                              minHeight: s(28),
                            ),
                            onPressed: () async {
                              if (vm.isLoading) return;
                              HapticFeedback.mediumImpact();
                              if (!vm.isFavorited) {
                                final result = await vm
                                    .saveCurrentOutputToFavorites();
                                if (vm.errorMessage == null &&
                                    context.mounted) {
                                  final isAlready =
                                      result ==
                                      SaveFavoriteResult.alreadyExists;
                                  showSnackBarSafe(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        isAlready
                                            ? 'snack_already_saved'.tr()
                                            : 'snack_saved'.tr(),
                                        textAlign: TextAlign.center,
                                      ),
                                      backgroundColor: isAlready
                                          ? AppColors.warning
                                          : AppColors.success,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          s(12),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                final removed = await vm.removeFromFavorites();
                                if (removed && context.mounted) {
                                  showSnackBarSafe(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        'general.removed_from_favorites'.tr(),
                                        textAlign: TextAlign.center,
                                      ),
                                      backgroundColor: AppColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          s(12),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // ─── Content Area ───
              Expanded(
                child: vm.isLoading && vm.output == null
                    ? _buildSkeletonLoader(s, sv, fs)
                    : vm.output == null
                    ? _buildEmptyState(s, sv, fs)
                    : _buildNewResultsSection(context, vm, s, sv, fs),
              ),

              // ─── ChatGPT-style Input Bar ───
              if (vm.output == null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(s(16), sv(12), s(16), sv(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBright,
                        borderRadius: BorderRadius.circular(s(24)),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Text field — grows up to 4 lines
                          IgnorePointer(
                            ignoring: vm.isLoading,
                            child: TextField(
                              controller: _textController,
                              onChanged: vm.updateInput,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.newline,
                              readOnly: vm.isLoading,
                              enableInteractiveSelection: !vm.isLoading,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: fs(15),
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                hintText: 'comment_generator.input_hint'.tr(),
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: fs(14),
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: s(12),
                                  vertical: sv(8),
                                ),
                              ),
                            ),
                          ),
                          // Controls row with tone icon and send button
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              s(8),
                              sv(2),
                              s(8),
                              sv(8),
                            ),
                            child: Row(
                              children: [
                                const Spacer(),
                                // Tone selection icon
                                GestureDetector(
                                  onTap: vm.isLoading
                                      ? null
                                      : () => _showToneSheet(context, vm),
                                  child: Container(
                                    width: s(36),
                                    height: s(36),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.tune,
                                      size: s(18),
                                      color: Colors.white.withOpacity(0.45),
                                    ),
                                  ),
                                ),
                                SizedBox(width: s(6)),
                                // Send button
                                GestureDetector(
                                  onTap:
                                      (vm.input.isEmpty ||
                                          vm.isLoading ||
                                          _isButtonDebouncing)
                                      ? null
                                      : () async {
                                          if (_isButtonDebouncing) return;
                                          setState(
                                            () => _isButtonDebouncing = true,
                                          );
                                          FocusScope.of(context).unfocus();
                                          await Future.delayed(
                                            const Duration(milliseconds: 300),
                                          );
                                          await vm.generateComments(
                                            language: getAppLanguageCode(
                                              context,
                                            ),
                                            locale: getValidOsLocale(),
                                          );
                                          if (mounted) {
                                            setState(
                                              () => _isButtonDebouncing = false,
                                            );
                                          }
                                        },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: s(36),
                                    height: s(36),
                                    decoration: BoxDecoration(
                                      color:
                                          vm.input.isNotEmpty && !vm.isLoading
                                          ? AppColors.accent
                                          : Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: vm.isLoading
                                        ? Padding(
                                            padding: EdgeInsets.all(s(9)),
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            Icons.arrow_upward_rounded,
                                            color: vm.input.isNotEmpty
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            size: s(20),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Skeleton Loader ───
  Widget _buildSkeletonLoader(
    double Function(double) s,
    double Function(double) sv,
    double Function(double) fs,
  ) {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, __) => ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: s(16), vertical: sv(8)),
        itemCount: 3,
        itemBuilder: (_, groupIdx) => Container(
          margin: EdgeInsets.only(bottom: sv(16)),
          padding: EdgeInsets.all(s(16)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(s(16)),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tone badge skeleton
              _shimmerBar(s(90), sv(28), s, _shimmerAnim.value),
              SizedBox(height: sv(14)),
              // Comment skeletons
              for (int i = 0; i < 3; i++) ...[
                Container(
                  padding: EdgeInsets.all(s(14)),
                  margin: EdgeInsets.only(bottom: sv(8)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(s(12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shimmerBar(
                        double.infinity,
                        sv(12),
                        s,
                        _shimmerAnim.value,
                      ),
                      SizedBox(height: sv(8)),
                      _shimmerBar(
                        s(200 - i * 40),
                        sv(12),
                        s,
                        _shimmerAnim.value,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBar(
    double width,
    double height,
    double Function(double) s,
    double animVal,
  ) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s(6)),
        gradient: LinearGradient(
          begin: Alignment(animVal - 1, 0),
          end: Alignment(animVal, 0),
          colors: [
            Colors.white.withOpacity(0.04),
            Colors.white.withOpacity(0.09),
            Colors.white.withOpacity(0.04),
          ],
        ),
      ),
    );
  }

  // ─── Empty State ───
  Widget _buildEmptyState(
    double Function(double) s,
    double Function(double) sv,
    double Function(double) fs,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: s(40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: s(64),
              height: s(64),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.accent,
                size: s(28),
              ),
            ),
            SizedBox(height: sv(16)),
            AutoSizeText(
              'comment_generator.input_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fs(17),
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              minFontSize: 14,
            ),
            SizedBox(height: sv(6)),
            AutoSizeText(
              'comment_generator.input_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fs(13),
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              minFontSize: 11,
            ),
            SizedBox(height: sv(10)),
            AutoSizeText(
              'comment_generator.supports'.tr(),
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.6),
                fontSize: fs(11),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              minFontSize: 9,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Results Section (glassmorphism cards with streaming) ───
  Widget _buildNewResultsSection(
    BuildContext context,
    CommentGeneratorViewModel vm,
    double Function(double) s,
    double Function(double) sv,
    double Function(double) fs,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(s(16), sv(4), s(16), sv(100)),
      itemCount: vm.output!.groups.length,
      itemBuilder: (_, groupIdx) {
        final group = vm.output!.groups[groupIdx];
        return Container(
          margin: EdgeInsets.only(bottom: sv(14)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(s(18)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Padding(
            padding: EdgeInsets.all(s(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tone badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: s(14),
                    vertical: sv(7),
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withOpacity(0.2),
                        AppColors.accent.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(s(10)),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    vm.getToneLabel(group.tone),
                    style: TextStyle(
                      fontSize: fs(14),
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                SizedBox(height: sv(12)),
                // Comments
                ...List.generate(group.comments.length, (cIdx) {
                  final displayText =
                      _displayedTexts[group.tone]?[cIdx] ??
                      group.comments[cIdx];
                  return Container(
                    margin: EdgeInsets.only(bottom: sv(8)),
                    padding: EdgeInsets.all(s(14)),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(s(12)),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _copyComment(context, group.comments[cIdx]);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayText,
                              style: TextStyle(
                                fontSize: fs(14),
                                color: AppColors.textPrimary,
                                height: 1.5,
                              ),
                            ),
                          ),
                          SizedBox(width: s(10)),
                          Icon(
                            Icons.copy_rounded,
                            size: s(16),
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ▼ ORIGINAL UI (activated when useNewUI = false)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildOldUI(BuildContext context, CommentGeneratorViewModel vm) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.backgroundTop,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, size: 20),
                          color: AppColors.textPrimary,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(
                              'comment_generator.title'.tr(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              minFontSize: 11,
                            ),
                            if (vm.isLoading)
                              AutoSizeText(
                                'comment_generator.generating'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                minFontSize: 11,
                              ),
                          ],
                        ),
                      ),
                      if (vm.output != null)
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            color: AppColors.textPrimary,
                            onPressed: () => _showToneSheet(
                              context,
                              vm,
                              isRegeneration: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: vm.isLoading && vm.output == null
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        )
                      : vm.output == null
                      ? _buildOldInputSection(context, vm)
                      : _buildOldResultsSection(context, vm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOldInputSection(
    BuildContext context,
    CommentGeneratorViewModel vm,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.15),
                blurRadius: 24,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.accent, AppColors.accentLight],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(
                            'comment_generator.input_title'.tr(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            minFontSize: 14,
                          ),
                          const SizedBox(height: 2),
                          AutoSizeText(
                            'comment_generator.input_subtitle'.tr(),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            minFontSize: 11,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AutoSizeText(
                  'comment_generator.tone_selection_title'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  minFontSize: 12,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: vm.availableTones.map((tone) {
                    final isSelected = vm.isToneSelected(tone);
                    return FilterChip(
                      label: AutoSizeText(
                        vm.getToneLabel(tone),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        minFontSize: 9,
                      ),
                      selected: isSelected,
                      onSelected: (_) => vm.toggleTone(tone),
                      backgroundColor: AppColors.surfaceBright,
                      selectedColor: AppColors.accent,
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.accent
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                AutoSizeText(
                  'comment_generator.tone_selection_min'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  minFontSize: 10,
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBright,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: TextField(
                    controller: _textController,
                    onChanged: vm.updateInput,
                    maxLines: 6,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'comment_generator.input_hint'.tr(),
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed:
                        (vm.input.isEmpty ||
                            vm.isLoading ||
                            _isButtonDebouncing)
                        ? null
                        : () async {
                            if (_isButtonDebouncing) return;
                            setState(() => _isButtonDebouncing = true);
                            FocusScope.of(context).unfocus();
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                            HapticFeedback.mediumImpact();
                            await vm.generateComments(
                              language: getAppLanguageCode(context),
                              locale: getValidOsLocale(),
                            );

                            // Reset debounce after generation completes
                            if (mounted) {
                              setState(() => _isButtonDebouncing = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      disabledBackgroundColor: AppColors.surface,
                      disabledForegroundColor: AppColors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: vm.isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'comment_generator.generating'.tr(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'comment_generator.generate_button'.tr(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'comment_generator.supports'.tr(),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOldResultsSection(
    BuildContext context,
    CommentGeneratorViewModel vm,
  ) {
    final allComments = vm.output!.groups.expand((g) => g.comments).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.95),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "$allComments ${'general.copied'.tr().toLowerCase()}",
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.copy_all, size: 20),
                  color: AppColors.textPrimary,
                  padding: const EdgeInsets.all(8),
                  onPressed: () => _copyAllComments(context, vm.output!, vm),
                  tooltip: 'general.copy'.tr(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright,
                  borderRadius: BorderRadius.circular(10),
                  border: vm.isFavorited
                      ? Border.all(
                          color: AppColors.error.withOpacity(0.5),
                          width: 1.5,
                        )
                      : null,
                  boxShadow: vm.isFavorited
                      ? [
                          BoxShadow(
                            color: AppColors.error.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  icon: Icon(
                    vm.isFavorited ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: vm.isFavorited
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                  padding: const EdgeInsets.all(8),
                  onPressed: () async {
                    if (vm.isLoading) return;
                    HapticFeedback.mediumImpact();
                    if (!vm.isFavorited) {
                      final result = await vm.saveCurrentOutputToFavorites();
                      if (vm.errorMessage == null && context.mounted) {
                        final isAlreadySaved =
                            result == SaveFavoriteResult.alreadyExists;
                        showSnackBarSafe(
                          context,
                          SnackBar(
                            content: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isAlreadySaved
                                      ? Icons.info_outline
                                      : Icons.check_circle,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isAlreadySaved
                                        ? 'snack_already_saved'.tr()
                                        : 'snack_saved'.tr(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: isAlreadySaved
                                ? AppColors.warning
                                : AppColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else if (vm.errorMessage != null && context.mounted) {
                        showSnackBarSafe(
                          context,
                          SnackBar(
                            content: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    vm.errorMessage ??
                                        'general.error_while_saving'.tr(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        vm.clearError();
                      }
                    } else {
                      final removed = await vm.removeFromFavorites();
                      if (removed && context.mounted) {
                        showSnackBarSafe(
                          context,
                          SnackBar(
                            content: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'general.removed_from_favorites'.tr(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else if (vm.errorMessage != null && context.mounted) {
                        showSnackBarSafe(
                          context,
                          SnackBar(
                            content: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    vm.errorMessage ??
                                        'general.error_while_removing'.tr(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        vm.clearError();
                      }
                    }
                  },
                  tooltip: vm.isFavorited
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: vm.output!.groups
                .map(
                  (group) => Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.accent.withOpacity(0.2),
                                  AppColors.accent.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.accent.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              vm.getToneLabel(group.tone),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...group.comments.map(
                            (comment) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceBright,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.05),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _copyComment(context, comment),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SelectableText(
                                        comment,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: AppColors.textPrimary,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.copy,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
