// lib/modules/quick_tools/view/viral_rewrite_screen.dart
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/services/admob_service.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/core/utils/hashtag_parser.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/modules/quick_tools/view_model/viral_rewrite_view_model.dart';
import 'package:provider/provider.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';

// ─── Accent color for Make Viral ───
const _kViralAccent = Color(0xFFF59E0B); // Warm amber/orange

class ViralRewriteScreen extends StatefulWidget {
  final String? initialInput;
  final String? initialRewardToken;
  const ViralRewriteScreen({
    Key? key,
    this.initialInput,
    this.initialRewardToken,
  }) : super(key: key);

  @override
  State<ViralRewriteScreen> createState() => _ViralRewriteScreenState();
}

class _ViralRewriteScreenState extends State<ViralRewriteScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isButtonDebouncing = false;

  // Streaming
  bool _isOutputStreaming = false;
  String _displayedOutput = '';
  Timer? _streamTimer;
  String? _lastStreamedOutput;

  // Shimmer
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialInput != null && widget.initialInput!.isNotEmpty) {
        _textController.text = widget.initialInput!;
        final vm = Provider.of<ViralRewriteViewModel>(context, listen: false);
        vm.updateInput(widget.initialInput!);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _shimmerCtrl.dispose();
    _streamTimer?.cancel();
    super.dispose();
  }

  // ======================== STREAMING ========================
  void _startStreamingText(String output) {
    if (_lastStreamedOutput == output) return;
    _lastStreamedOutput = output;
    _streamTimer?.cancel();
    _displayedOutput = '';
    setState(() {
      _isOutputStreaming = true;
    });
    int charIdx = 0;
    _streamTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (charIdx >= output.length) {
        setState(() {
          _isOutputStreaming = false;
        });
        timer.cancel();
        // 🔄 Issue #3 fix: Refresh user limits from server after generation.
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          try {
            final notifier = context.read<UserNotifier>();
            notifier.reload(forceServer: true);
          } catch (_) {}
        });
        return;
      }
      final end = (charIdx + 5).clamp(0, output.length);
      setState(() {
        _displayedOutput = output.substring(0, end);
      });
      charIdx = end;
    });
  }

  // ======================== DIALOGS (logic preserved) ========================
  void _showLimitExceededDialog(
    BuildContext context,
    ViralRewriteViewModel vm, {
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
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
      builder: (dialogContext) {
        return Dialog(
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
                  'viral_rewrite.limit_dialog_title'.tr(),
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
                  'viral_rewrite.limit_dialog_subtitle'.tr(),
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
                            onRewarded: () {
                              showSnackBarSafe(
                                context,
                                SnackBar(
                                  content: Text(
                                    'viral_rewrite.snack_reward'.tr(),
                                  ),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
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
                                'viral_rewrite.reward_button'.tr(),
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
                                'viral_rewrite.snack_pro_navigating'.tr(),
                              ),
                              backgroundColor: AppColors.accent,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
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
                          'viral_rewrite.go_pro_button'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAbuseContentDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
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
                        AppColors.error,
                        AppColors.error.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                AutoSizeText(
                  'general.content_blocked'.tr(),
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
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  minFontSize: 12,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'general.understood'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
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

  void _showFeedback(BuildContext context, String message, {Color? color}) {
    showSnackBarSafe(
      context,
      SnackBar(
        content: Center(child: Text(message, textAlign: TextAlign.center)),
        backgroundColor: color ?? _kViralAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      _showFeedback(
        context,
        'viral_rewrite.snack_copy'.tr(),
        color: AppColors.success,
      );
    });
  }

  // ======================== TONE BOTTOM SHEET ========================
  void _showToneSheet(
    BuildContext context,
    ViralRewriteViewModel vm, {
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
                          Icons.local_fire_department_rounded,
                          color: _kViralAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AutoSizeText(
                            isRegeneration
                                ? 'viral_rewrite.regenerate_title'.tr()
                                : 'viral_rewrite.tone_selection_title'.tr(),
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
                      'viral_rewrite.tone_selection_subtitle'.tr(),
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
                                        ? _kViralAccent.withOpacity(0.15)
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? _kViralAccent.withOpacity(0.5)
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
                                          ? _kViralAccent
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
                            'viral_rewrite.tone_selection_min'.tr(),
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
                          onPressed: () {
                            Navigator.pop(ctx);
                            HapticFeedback.mediumImpact();
                            _lastStreamedOutput = null;
                            _displayedOutput = '';
                            vm.generateViralRewrite(
                              language: getAppLanguageCode(context),
                              locale: getValidOsLocale(),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kViralAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Regenerate',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
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

  // ======================== FORMAT PARSER ========================
  List<InlineSpan> _parseFormattedText(String text, Color accentColor) {
    final spans = <InlineSpan>[];
    // Matches **bold text** or #hashtags
    final regex = HashtagParser.inlineFormatPattern;
    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        // Bold match
        spans.add(
          TextSpan(
            text: match.group(1),
            style: TextStyle(fontWeight: FontWeight.w700, color: accentColor),
          ),
        );
      } else if (match.group(2) != null) {
        // Hashtag match -> Render as a beautiful pill
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.only(right: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Text(
                HashtagParser.cleanToken(match.group(2)!),
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        );
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  // ======================== BUILD ========================
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ViralRewriteViewModel>(
      create: (_) => ViralRewriteViewModel(
        Provider.of<UserRepository>(context, listen: false),
        initialRewardToken: widget.initialRewardToken,
      ),
      child: Consumer<ViralRewriteViewModel>(
        builder: (context, vm, child) {
          // Shimmer control
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

            if (widget.initialInput != null &&
                widget.initialInput!.isNotEmpty &&
                _textController.text.isEmpty) {
              _textController.text = widget.initialInput!;
              vm.updateInput(widget.initialInput!);
            }

            final error = vm.errorMessage;
            if (error != null) {
              if (error.contains('errors.content_blocked_ai') ||
                  error.contains('errors.content_violates_safety')) {
                vm.clearError();
                _showAbuseContentDialog(context, error.tr());
              } else {
                _showFeedback(context, error.tr(), color: AppColors.error);
                vm.clearError();
              }
            }

            if (vm.output != null && !vm.isLoading) {
              _startStreamingText(vm.output!);
            }
          });

          final isLocked = vm.isLoading || _isOutputStreaming;

          return PopScope(
            canPop: !isLocked,
            onPopInvoked: (didPop) {
              if (isLocked) return;
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF121215),
              resizeToAvoidBottomInset: true,
              body: AbsorbPointer(
                absorbing: isLocked,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF151518), Color(0xFF0E0E11)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        _buildTopBar(context, vm),
                        Expanded(
                          child: vm.isLoading && vm.output == null
                              ? _buildSkeletonLoader()
                              : vm.output == null
                              ? _buildEmptyState()
                              : _buildResultsView(context, vm),
                        ),
                        if (vm.output == null) _buildInputBar(context, vm),
                        if (vm.output != null && !vm.isLoading)
                          _buildBottomBar(context, vm),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ======================== TOP BAR ========================
  Widget _buildTopBar(BuildContext context, ViralRewriteViewModel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (vm.isLoading) return;
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  'viral_rewrite.title'.tr(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  minFontSize: 11,
                ),
                if (vm.isLoading)
                  AutoSizeText(
                    'viral_rewrite.generating'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _kViralAccent,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    minFontSize: 10,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (vm.output != null && !vm.isLoading) ...[
            _topBarIcon(
              icon: Icons.copy_all_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                _copyToClipboard(context, vm.output!);
              },
            ),
            const SizedBox(width: 8),
            _topBarIcon(
              icon: vm.isFavorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: vm.isFavorited ? AppColors.error : Colors.white60,
              onTap: () async {
                HapticFeedback.mediumImpact();
                if (vm.isFavorited) {
                  await vm.removeFromFavorites();
                  if (mounted) {
                    _showFeedback(
                      context,
                      'general.removed_from_favorites'.tr(),
                      color: Colors.grey,
                    );
                  }
                } else {
                  final result = await vm.saveToFavorites();
                  if (mounted) {
                    final saved = result == SaveFavoriteResult.saved ||
                        result == SaveFavoriteResult.updated;
                    final message = saved
                        ? 'general.snack_saved'.tr()
                        : 'general.snack_already_saved'.tr();
                    final color =
                        saved ? AppColors.success : AppColors.warning;
                    _showFeedback(context, message, color: color);
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBarIcon({
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, size: 18, color: color ?? Colors.white60),
      ),
    );
  }

  // ======================== EMPTY STATE ========================
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _kViralAccent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: _kViralAccent,
                size: 30,
              ),
            ),
            const SizedBox(height: 24),
            AutoSizeText(
              'viral_rewrite.input_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.35,
                letterSpacing: -0.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              minFontSize: 18,
            ),
            const SizedBox(height: 12),
            AutoSizeText(
              'viral_rewrite.input_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.35),
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              minFontSize: 11,
            ),
          ],
        ),
      ),
    );
  }

  // ======================== SKELETON LOADER ========================
  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _kViralAccent.withOpacity(0.4),
                        _kViralAccent.withOpacity(0.12),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    size: 14,
                    color: _kViralAccent,
                  ),
                ),
                const SizedBox(width: 12),
                _ViralTypingDots(),
              ],
            ),
            const SizedBox(height: 24),
            _shimmerBar(double.infinity, 14),
            const SizedBox(height: 12),
            _shimmerBar(290, 14),
            const SizedBox(height: 12),
            _shimmerBar(230, 14),
            const SizedBox(height: 12),
            _shimmerBar(310, 14),
            const SizedBox(height: 12),
            _shimmerBar(200, 14),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBar(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(
          begin: Alignment(_shimmerAnim.value - 1, 0),
          end: Alignment(_shimmerAnim.value, 0),
          colors: [
            Colors.white.withOpacity(0.04),
            Colors.white.withOpacity(0.09),
            Colors.white.withOpacity(0.04),
          ],
        ),
      ),
    );
  }

  // ======================== RESULTS VIEW ========================
  Widget _buildResultsView(BuildContext context, ViralRewriteViewModel vm) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // User prompt bubble
        if (vm.input.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _kViralAccent.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
                border: Border.all(color: _kViralAccent.withOpacity(0.08)),
              ),
              child: Text(
                vm.input,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // AI Response
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, value, ch) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)),
                child: ch,
              ),
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kViralAccent.withOpacity(0.4),
                      _kViralAccent.withOpacity(0.12),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: _kViralAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tone badges
                      if (vm.lastGeneratedTones.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: vm.lastGeneratedTones.map((tone) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _kViralAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _kViralAccent.withOpacity(0.25),
                                ),
                              ),
                              child: AutoSizeText(
                                vm.getToneLabel(tone),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: _kViralAccent,
                                ),
                                maxLines: 1,
                                minFontSize: 8,
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      SelectableText.rich(
                        TextSpan(
                          children: _parseFormattedText(
                            _displayedOutput.isNotEmpty
                                ? _displayedOutput
                                : vm.output ?? '',
                            _kViralAccent,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ======================== INPUT BAR ========================
  Widget _buildInputBar(BuildContext context, ViralRewriteViewModel vm) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: IgnorePointer(
                  ignoring: vm.isLoading,
                  child: TextField(
                    controller: _textController,
                    onChanged: vm.updateInput,
                    maxLines: 4,
                    minLines: 1,
                    readOnly: vm.isLoading,
                    enableInteractiveSelection: !vm.isLoading,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'viral_rewrite.input_hint'.tr(),
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.28),
                        fontSize: 14,
                      ),
                      hintMaxLines: 1,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 10, 10),
                child: Row(
                  children: [
                    const Spacer(),
                    // Tune icon — also opens tone sheet
                    GestureDetector(
                      onTap: vm.isLoading
                          ? null
                          : () => _showToneSheet(context, vm),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.tune,
                          size: 18,
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button
                    GestureDetector(
                      onTap:
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
                              await vm.generateViralRewrite(
                                language: getAppLanguageCode(context),
                                locale: getValidOsLocale(),
                              );
                              if (mounted) {
                                setState(() => _isButtonDebouncing = false);
                              }
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: vm.input.isNotEmpty && !vm.isLoading
                              ? _kViralAccent
                              : Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: vm.isLoading
                            ? Padding(
                                padding: const EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                                color: vm.input.isNotEmpty
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.2),
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
    );
  }

  // ======================== BOTTOM BAR ========================
  Widget _buildBottomBar(BuildContext context, ViralRewriteViewModel vm) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF121215).withOpacity(0.95),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: Row(
          children: [
            // New input
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _lastStreamedOutput = null;
                _displayedOutput = '';
                _textController.clear();
                vm.clearOutput();
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: 22,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Tone / Change tones icon
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showToneSheet(context, vm, isRegeneration: true);
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Icon(
                  Icons.tune,
                  size: 20,
                  color: _kViralAccent.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Regenerate
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _lastStreamedOutput = null;
                    _displayedOutput = '';
                    vm.generateViralRewrite(
                      language: getAppLanguageCode(context),
                      locale: getValidOsLocale(),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [const Icon(Icons.refresh_rounded, size: 18)],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Copy All
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _copyToClipboard(context, vm.output!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kViralAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.content_copy_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================== TYPING DOTS ========================
class _ViralTypingDots extends StatefulWidget {
  @override
  State<_ViralTypingDots> createState() => _ViralTypingDotsState();
}

class _ViralTypingDotsState extends State<_ViralTypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _sinApprox(double x) =>
      x - (x * x * x) / 6.0 + (x * x * x * x * x) / 120.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final bounce = _sinApprox(t * 3.14159);
            return Container(
              margin: EdgeInsetsDirectional.only(end: index < 2 ? 5 : 0),
              child: Transform.translate(
                offset: Offset(0, -3.5 * bounce),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _kViralAccent.withOpacity(0.35 + 0.45 * bounce),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
