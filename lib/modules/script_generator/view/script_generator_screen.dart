// lib/modules/script_generator/view/script_generator_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ideaboost/core/constants/colors.dart';

import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import 'package:provider/provider.dart';
import '../view_model/script_generator_view_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';

class ScriptGeneratorScreen extends StatelessWidget {
  final IdeaModel? idea;
  final String? initialPrompt;
  final String? initialRewardToken;
  final String? initialLength;
  final String? initialVariation;
  final String? initialEmotion;
  final String? initialPlatform;
  const ScriptGeneratorScreen({
    Key? key,
    this.idea,
    this.initialPrompt,
    this.initialRewardToken,
    this.initialLength,
    this.initialVariation,
    this.initialEmotion,
    this.initialPlatform,
  }) : super(key: key);

  // ======================== LIMIT DIALOG (unchanged logic) ========================
  void _showLimitExceededDialog(BuildContext context, {bool isPro = false}) {
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
                      'script_generator.limit_dialog_title'.tr(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AutoSizeText(
                      'script_generator.limit_dialog_subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              final vm = Provider.of<ScriptGeneratorViewModel>(
                                context,
                                listen: false,
                              );
                              print(
                                '🎬 OLD Dialog: Regenerating with token system',
                              );
                              if (vm.isComplete) {
                                await vm.regenerate(
                                  language: getAppLanguageCode(context),
                                  locale: getValidOsLocale(),
                                );
                              } else {
                                await vm.startGeneration(
                                  language: getAppLanguageCode(context),
                                  locale: getValidOsLocale(),
                                );
                              }
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
                                    'script_generator.reward_button'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.visible,
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
                                  content: Center(
                                    child: Text(
                                      'script_generator.snack_pro_navigating'
                                          .tr(),
                                      textAlign: TextAlign.center,
                                    ),
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
                              'script_generator.go_pro_button'.tr(),
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
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBright,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.textSecondary,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ======================== PARAMETER BOTTOM SHEET ========================
  void _showParameterSheet(BuildContext context, ScriptGeneratorViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ChangeNotifierProvider.value(
          value: vm,
          child: Consumer<ScriptGeneratorViewModel>(
            builder: (ctx, vm, _) {
              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
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
                            Icons.tune,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'script_generator.parameters_title'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.visible,
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
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sheetSectionLabel(
                              'script_generator.param_length'.tr(),
                            ),
                            const SizedBox(height: 10),
                            _buildChipRow(vm, [
                              _ChipData(
                                'script_generator.length_super_short'.tr(),
                                'super_short',
                                icon: Icons.flash_on,
                                iconColor: const Color(0xFFFFB800),
                              ),
                              _ChipData(
                                'script_generator.length_short'.tr(),
                                'short',
                                icon: Icons.trending_up,
                                iconColor: const Color(0xFF00C853),
                              ),
                              _ChipData(
                                'script_generator.length_full'.tr(),
                                'full',
                                icon: Icons.schedule,
                                iconColor: const Color(0xFF2196F3),
                              ),
                            ], 'length'),
                            const SizedBox(height: 20),
                            _sheetSectionLabel(
                              'script_generator.param_variation'.tr(),
                            ),
                            const SizedBox(height: 10),
                            _buildChipRow(vm, [
                              _ChipData(
                                'script_generator.variation_default'.tr(),
                                'default',
                                icon: Icons.adjust,
                                iconColor: const Color(0xFF757575),
                              ),
                              _ChipData(
                                'script_generator.variation_comedy'.tr(),
                                'comedy',
                                icon: Icons.emoji_emotions,
                                iconColor: const Color(0xFFFFC107),
                              ),
                              _ChipData(
                                'script_generator.variation_dramatic'.tr(),
                                'dramatic',
                                icon: Icons.theaters,
                                iconColor: const Color(0xFF9C27B0),
                              ),
                              _ChipData(
                                'script_generator.variation_romantic'.tr(),
                                'romantic',
                                icon: Icons.favorite,
                                iconColor: const Color(0xFFE91E63),
                              ),
                              _ChipData(
                                'script_generator.variation_school'.tr(),
                                'school',
                                icon: Icons.school,
                                iconColor: const Color(0xFF1976D2),
                              ),
                              _ChipData(
                                'script_generator.variation_npc'.tr(),
                                'npc',
                                icon: Icons.smart_toy,
                                iconColor: const Color(0xFF00BCD4),
                              ),
                            ], 'variation'),
                            const SizedBox(height: 20),
                            _sheetSectionLabel(
                              'script_generator.param_emotion'.tr(),
                            ),
                            const SizedBox(height: 10),
                            _buildChipRow(vm, [
                              _ChipData(
                                'script_generator.emotion_neutral'.tr(),
                                'neutral',
                                icon: Icons.face,
                                iconColor: const Color(0xFF757575),
                              ),
                              _ChipData(
                                'script_generator.emotion_funny'.tr(),
                                'funny',
                                icon: Icons.sentiment_very_satisfied,
                                iconColor: const Color(0xFFFFD54F),
                              ),
                              _ChipData(
                                'script_generator.emotion_panic'.tr(),
                                'panic',
                                icon: Icons.warning,
                                iconColor: const Color(0xFFFF6F00),
                              ),
                              _ChipData(
                                'script_generator.emotion_calm'.tr(),
                                'calm',
                                icon: Icons.self_improvement,
                                iconColor: const Color(0xFF0097A7),
                              ),
                              _ChipData(
                                'script_generator.emotion_cinematic'.tr(),
                                'cinematic',
                                icon: Icons.movie,
                                iconColor: const Color(0xFF7B1FA2),
                              ),
                            ], 'emotion'),
                            const SizedBox(height: 20),
                            _sheetSectionLabel(
                              'script_generator.param_platform'.tr(),
                            ),
                            const SizedBox(height: 10),
                            _buildChipRow(vm, [
                              _ChipData(
                                'script_generator.platform_tiktok'.tr(),
                                'tiktok',
                                svgAsset: 'assets/icons/tiktok.svg',
                              ),
                              _ChipData(
                                'script_generator.platform_reels'.tr(),
                                'reels',
                                svgAsset: 'assets/icons/instagram.svg',
                              ),
                              _ChipData(
                                'script_generator.platform_shorts'.tr(),
                                'shorts',
                                svgAsset: 'assets/icons/youtube-shorts.svg',
                              ),
                            ], 'platform'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _sheetSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white.withOpacity(0.35),
        letterSpacing: 1.2,
      ),
    );
  }

  /// Helper to get SVG widget for platform icon - preserves native SVG colors
  Widget _getPlatformSvg(String platform, {double? size}) {
    final iconSize = size ?? 16;

    switch (platform) {
      case 'tiktok':
        return SvgPicture.asset(
          'assets/icons/tiktok.svg',
          width: iconSize,
          height: iconSize,
        );
      case 'reels':
        return SvgPicture.asset(
          'assets/icons/instagram.svg',
          width: iconSize,
          height: iconSize,
        );
      case 'shorts':
        return SvgPicture.asset(
          'assets/icons/youtube-shorts.svg',
          width: iconSize,
          height: iconSize,
        );
      default:
        return SizedBox(width: iconSize, height: iconSize);
    }
  }

  Widget _buildChipRow(
    ScriptGeneratorViewModel vm,
    List<_ChipData> chips,
    String type,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((chip) {
        bool selected;
        switch (type) {
          case 'length':
            selected = vm.selectedLength == chip.value;
            break;
          case 'variation':
            selected = vm.selectedVariation == chip.value;
            break;
          case 'emotion':
            selected = vm.selectedEmotion == chip.value;
            break;
          case 'platform':
            selected = vm.selectedPlatform == chip.value;
            break;
          default:
            selected = false;
        }
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            switch (type) {
              case 'length':
                vm.selectedLength = chip.value;
                break;
              case 'variation':
                vm.selectedVariation = chip.value;
                break;
              case 'emotion':
                vm.selectedEmotion = chip.value;
                break;
              case 'platform':
                vm.selectedPlatform = chip.value;
                break;
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withOpacity(0.18)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withOpacity(0.5)
                    : Colors.white.withOpacity(0.08),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show SVG icon for platforms, material icon for others
                if (type == 'platform' && chip.svgAsset != null) ...[
                  _getPlatformSvg(chip.value, size: 15),
                  const SizedBox(width: 6),
                ] else if (chip.icon != null) ...[
                  Icon(
                    chip.icon,
                    size: 15,
                    color:
                        chip.iconColor ??
                        (selected ? Colors.white : AppColors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  chip.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.accentLight : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ======================== SECTION BUILDERS ========================
  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }

  Widget _modernCard({required Widget child, Color? glowColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor.withOpacity(0.15),
                  blurRadius: 24,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  // ======================== BUILD ========================
  @override
  Widget build(BuildContext context) {
    final userRepository = context.read<UserRepository>();

    return ChangeNotifierProvider(
      create: (_) => ScriptGeneratorViewModel(
        idea,
        userRepository,
        initialPrompt: initialPrompt,
        initialRewardToken: initialRewardToken,
        initialLength: initialLength,
        initialVariation: initialVariation,
        initialEmotion: initialEmotion,
        initialPlatform: initialPlatform,
        initialLanguage: context.locale.languageCode,
      ),
      child: Consumer<ScriptGeneratorViewModel>(
        builder: (context, vm, _) {
          // Error handling — completely unchanged logic
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final error = vm.errorMessage;
            if (error != null) {
              showSnackBarSafe(
                context,
                SnackBar(
                  content: Center(
                    child: Text(error, textAlign: TextAlign.center),
                  ),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              vm.clearError();
            }

            // 🔄 Issue #3 fix: Refresh user limits from server after generation.
            if (vm.isComplete && !vm.isReloadScheduled) {
              vm.isReloadScheduled = true;
              Future.delayed(const Duration(seconds: 2), () {
                if (!context.mounted) return;
                try {
                  context.read<UserNotifier>().reload(forceServer: true);
                } catch (_) {}
              });
            }
          });

          final bool hasContent =
              vm.hook.isNotEmpty ||
              vm.voiceover.isNotEmpty ||
              vm.shots.isNotEmpty ||
              vm.cta.isNotEmpty ||
              vm.hashtags.isNotEmpty;

          return PopScope(
            canPop: !vm.isStreaming,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && vm.isStreaming) {
                // Generation in progress - prevent navigation
                return;
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF1A1A1F),
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A1A1F), Color(0xFF111114)],
                  ),
                ),
                child: AbsorbPointer(
                  absorbing: vm.isStreaming,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // ─── Top Bar ───
                        _buildTopBar(context, vm),

                        // ─── Main Content ───
                        Expanded(
                          child: hasContent || vm.isStreaming
                              ? _buildResultsView(context, vm)
                              : _buildWelcomeView(context, vm),
                        ),

                        // ─── Input Bar (only when input mode & not complete) ───
                        if (vm.showInputField && !vm.isComplete)
                          _buildInputBar(context, vm),

                        // ─── Bottom Bar (when generation is done) ───
                        if (vm.isComplete) _buildBottomBar(context, vm),
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
  Widget _buildTopBar(BuildContext context, ScriptGeneratorViewModel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: vm.isStreaming ? null : () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
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
                  vm.idea != null
                      ? 'script_generator.title_with_idea'.tr()
                      : 'script_generator.title'.tr(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  minFontSize: 13,
                ),
                if (vm.isStreaming)
                  AutoSizeText(
                    'script_generator.generating'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
              ],
            ),
          ),
          if (vm.isComplete) ...[
            _barIcon(
              icon: vm.isFavorited ? Icons.favorite : Icons.favorite_outline,
              color: vm.isFavorited ? AppColors.error : Colors.white60,
              onTap: () async {
                HapticFeedback.mediumImpact();
                if (!vm.isFavorited) {
                  await vm.saveToFavorites();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Center(
                          child: Text(
                            'script_generator.snack_saved'.tr(),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                } else {
                  final removed = await vm.removeFromFavorites();
                  if (removed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Center(
                          child: Text(
                            'script_generator.snack_removed'.tr(),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            _barIcon(
              icon: Icons.content_copy,
              color: Colors.white60,
              onTap: () => vm.copyAll(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  // ======================== WELCOME VIEW ========================
  Widget _buildWelcomeView(BuildContext context, ScriptGeneratorViewModel vm) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sparkle icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.3),
                    AppColors.accentLight.withOpacity(0.15),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppColors.accentLight,
                size: 28,
              ),
            ),
            const SizedBox(height: 28),
            AutoSizeText(
              'script_generator.input_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.35,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 14),
            AutoSizeText(
              'script_generator.input_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.38),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _suggestionChip('script_generator.suggestion_write'.tr()),
                _suggestionChip('script_generator.suggestion_learn'.tr()),
                _suggestionChip('script_generator.suggestion_code'.tr()),
                _suggestionChip('script_generator.suggestion_script'.tr()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withOpacity(0.55),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ======================== INPUT BAR ========================
  Widget _buildInputBar(BuildContext context, ScriptGeneratorViewModel vm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text field
            IgnorePointer(
              ignoring: vm.isStreaming,
              child: TextField(
                controller: vm.promptController,
                onChanged: (v) => vm.userPrompt = v,
                maxLines: 5,
                minLines: 1,
                readOnly: vm.isStreaming || vm.isComplete,
                enableInteractiveSelection: !vm.isStreaming,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'script_generator.input_hint'.tr(),
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.28),
                    fontSize: 15,
                  ),
                  hintMaxLines: 1,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                ),
              ),
            ),
            // Bottom controls row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 10, 10),
              child: Row(
                children: [
                  const Spacer(),
                  // Tune / Parameter icon
                  _inputBarCircle(
                    icon: Icons.tune,
                    onTap: vm.isStreaming
                        ? null
                        : () => _showParameterSheet(context, vm),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  _buildSendButton(context, vm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBarCircle({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white.withOpacity(0.45)),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context, ScriptGeneratorViewModel vm) {
    final bool canSend = !vm.isStreaming && vm.userPrompt.trim().isNotEmpty;

    return GestureDetector(
      onTap: canSend
          ? () async {
              HapticFeedback.mediumImpact();
              if (vm.isComplete) {
                await vm.regenerate(
                  language: getAppLanguageCode(context),
                  locale: getValidOsLocale(),
                );
              } else {
                await vm.startGeneration(
                  language: getAppLanguageCode(context),
                  locale: getValidOsLocale(),
                );
              }
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: vm.isStreaming
              ? Colors.white.withOpacity(0.08)
              : canSend
              ? AppColors.accent
              : Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: vm.isStreaming
            ? Padding(
                padding: const EdgeInsets.all(9),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withOpacity(0.5),
                ),
              )
            : Icon(
                Icons.arrow_upward,
                size: 18,
                color: canSend ? Colors.white : Colors.white.withOpacity(0.2),
              ),
      ),
    );
  }

  // ======================== RESULTS VIEW ========================
  Widget _buildResultsView(BuildContext context, ScriptGeneratorViewModel vm) {
    return ListView(
      controller: vm.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // User prompt bubble
        if (vm.userPrompt.isNotEmpty || vm.idea != null) ...[
          _buildUserBubble(vm),
          const SizedBox(height: 24),
        ],

        // Streaming indicator (when no content yet)
        if (vm.isStreaming && !_hasAnyContent(vm)) _buildStreamingIndicator(),

        // ─── Hook ───
        if (vm.hook.isNotEmpty)
          _buildAISection(
            child: _modernCard(
              glowColor: AppColors.error,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      'script_generator.hook_title'.tr(),
                      Icons.flash_on,
                      AppColors.error,
                    ),
                    const SizedBox(height: 20),
                    SelectableText(
                      vm.hook,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ─── Voiceover ───
        if (vm.voiceover.isNotEmpty)
          _buildAISection(
            child: _modernCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      'script_generator.voiceover_title'.tr(),
                      Icons.record_voice_over,
                      AppColors.accent,
                    ),
                    const SizedBox(height: 20),
                    ...vm.voiceover.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SelectableText(
                          line,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ─── Shots ───
        if (vm.shots.isNotEmpty)
          _buildAISection(
            child: _modernCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      'script_generator.shots_title'.tr(),
                      Icons.videocam,
                      AppColors.success,
                    ),
                    const SizedBox(height: 20),
                    ...vm.shots.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.success,
                                    AppColors.success.withOpacity(0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  "${e.key + 1}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SelectableText(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                  height: 1.5,
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
            ),
          ),

        // ─── CTA ───
        if (vm.cta.isNotEmpty)
          _buildAISection(
            child: _modernCard(
              glowColor: AppColors.warning,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _sectionHeader(
                      'script_generator.cta_title'.tr(),
                      Icons.campaign,
                      AppColors.warning,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.warning.withOpacity(0.15),
                            AppColors.warning.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: SelectableText(
                        vm.cta,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.4,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ─── Hashtags ───
        if (vm.hashtags.isNotEmpty)
          _buildAISection(
            child: _modernCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      'script_generator.hashtags_title'.tr(),
                      Icons.tag,
                      AppColors.accentLight,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: vm.hashtags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentLight.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.accentLight.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  color: AppColors.accentLight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Streaming indicator at bottom when content is partially loaded
        if (vm.isStreaming && _hasAnyContent(vm)) _buildStreamingIndicator(),
      ],
    );
  }

  bool _hasAnyContent(ScriptGeneratorViewModel vm) {
    return vm.hook.isNotEmpty ||
        vm.voiceover.isNotEmpty ||
        vm.shots.isNotEmpty ||
        vm.cta.isNotEmpty ||
        vm.hashtags.isNotEmpty;
  }

  // ======================== USER BUBBLE ========================
  Widget _buildUserBubble(ScriptGeneratorViewModel vm) {
    final text = vm.idea != null
        ? '${vm.idea!.title}\n${vm.idea!.description}'
        : vm.userPrompt;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
          border: Border.all(color: AppColors.accent.withOpacity(0.12)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  // ======================== AI SECTION WRAPPER ========================
  Widget _buildAISection({required Widget child}) {
    return TweenAnimationBuilder<double>(
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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI avatar
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.35),
                    AppColors.accentLight.withOpacity(0.15),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppColors.accentLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  // ======================== STREAMING INDICATOR ========================
  Widget _buildStreamingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withOpacity(0.35),
                  AppColors.accentLight.withOpacity(0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 14,
              color: AppColors.accentLight,
            ),
          ),
          const SizedBox(width: 12),
          const _TypingDots(),
        ],
      ),
    );
  }

  // ======================== BOTTOM BAR ========================
  Widget _buildBottomBar(BuildContext context, ScriptGeneratorViewModel vm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F).withOpacity(0.95),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Tune / Change params icon
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showParameterSheet(context, vm);
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
                  Icons.tune_rounded,
                  size: 20,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Regenerate
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final needsAd = await vm.needsRewardedAd();
                    if (needsAd) {
                      await vm.regenerate(
                        language: getAppLanguageCode(context),
                        locale: getValidOsLocale(),
                      );
                    } else {
                      await vm.regenerate(
                        language: getAppLanguageCode(context),
                        locale: getValidOsLocale(),
                      );
                    }
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
                    children: [const Icon(Icons.refresh, size: 18)],
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
                  onPressed: () => vm.copyAll(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [const Icon(Icons.content_copy, size: 16)],
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

// ======================== TYPING DOTS WIDGET ========================
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
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
                    color: AppColors.accentLight.withOpacity(
                      0.35 + 0.45 * bounce,
                    ),
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

  double _sinApprox(double x) =>
      x - (x * x * x) / 6.0 + (x * x * x * x * x) / 120.0;
}

// ======================== CHIP DATA ========================
class _ChipData {
  final String label;
  final String value;
  final IconData? icon;
  final String? svgAsset;
  final Color? iconColor;
  const _ChipData(
    this.label,
    this.value, {
    this.icon,
    this.svgAsset,
    this.iconColor,
  });
}
