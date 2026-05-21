// lib/modules/idea_details/view/idea_details_screen.dart
import 'dart:async';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/utils/idea_attribute_labels.dart';
import 'package:ideaboost/core/services/admob_service.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/modules/idea_details/view_model/idea_details_view_model.dart';
import 'package:ideaboost/modules/idea_details/view_model/idea_refine_view_model.dart';
import 'package:ideaboost/modules/script_generator/view/script_generator_screen.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';
import 'package:provider/provider.dart';

class IdeaDetailsScreen extends StatefulWidget {
  final IdeaModel idea;
  const IdeaDetailsScreen({Key? key, required this.idea}) : super(key: key);

  @override
  State<IdeaDetailsScreen> createState() => _IdeaDetailsScreenState();
}

class _IdeaDetailsScreenState extends State<IdeaDetailsScreen> {
  late List<IdeaModel> ideaHistory;
  late int currentIndex;
  late IdeaDetailsViewModel _viewModel;
  late IdeaRefineViewModel _refineViewModel;
  final AdMobService adMobService = AdMobService();
  String? _ideaAttrLocale;

  // ── Parameter selection state ──
  String _selectedLength = 'short';
  String _selectedVariation = 'default';
  String _selectedEmotion = 'neutral';
  String _selectedPlatform = 'reels';

  // ── Streaming animation state ──
  bool _isStreaming = false;
  bool _isActionLocked = false;
  bool _isTogglingFavorite = false;
  String _streamedTitle = '';
  String _streamedDescription = '';
  List<String> _streamedSteps = [];
  String _streamedCta = '';
  Timer? _streamTimer;
  int _streamPhase = 0; // 0=title, 1=desc, 2=steps, 3=cta, 4=done
  int _streamCharIndex = 0;
  int _streamStepIndex = 0;

  @override
  void initState() {
    super.initState();
    ideaHistory = [widget.idea];
    currentIndex = 0;
    _viewModel = IdeaDetailsViewModel(widget.idea);
    _refineViewModel = IdeaRefineViewModel(UserRepository(UserService()));
    // ⚡ Check immediately if this idea was previously favorited
    _checkIfFavorited();
    // 📝 Save initial idea to history
    _saveInitialIdeaToHistory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = context.locale.languageCode;
    if (_ideaAttrLocale != lang) {
      _ideaAttrLocale = lang;
      IdeaAttributeLabels.instance.setDisplayLocale(lang).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    adMobService.disposeBanner();
    super.dispose();
  }

  Future<void> _saveInitialIdeaToHistory() async {
    try {
      final idea = widget.idea;
      final userRepository = UserRepository(UserService());

      // Determine history type based on dataset
      String historyType = 'idea_details';
      if (idea.dataset == 'youth') {
        historyType = 'youth_ideas';
      } else if (idea.dataset == 'seasonal') {
        historyType = 'seasonal_ideas';
      }

      // Fire-and-forget: don't await
      userRepository.saveHistoryEntry(
        type: historyType,
        prompt: idea.title,
        output: {
          'title': idea.title,
          'description': idea.description,
          'steps': idea.steps,
          'cta': idea.cta,
          'niche': idea.niche,
          'format': idea.format,
          'level': idea.level,
          'dataset': idea.dataset,
        },
        meta: {
          'idea': {...idea.toMap(), 'dataset': idea.dataset},
        },
      );
      debugPrint('✅ Initial idea saved to history: $historyType');
    } catch (e) {
      debugPrint('⚠️ Failed to save initial idea to history: $e');
      // Non-fatal, don't show error to user
    }
  }

  Future<void> _checkIfFavorited() async {
    final currentIdea = ideaHistory[currentIndex];
    final isRefined = currentIndex > 0;
    try {
      // ⚡ CRITICAL: Check with proper type based on whether it's refined
      final isFav = await _viewModel.checkIfFavoritedWithType(
        currentIdea.id.toString(),
        isRefined: isRefined,
        originalIdea: isRefined ? ideaHistory[0] : null,
      );
      // Update ViewModel with actual favorite status
      _viewModel.setFavorited(isFav);
      // Trigger UI rebuild
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ Error checking favorite status: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isTogglingFavorite) return;
    _isTogglingFavorite = true;
    final currentIdea = ideaHistory[currentIndex];
    final isRefined = currentIndex > 0;

    try {
      if (_viewModel.isFavorited) {
        // Update UI immediately (optimistic) - ViewModel's notifyListeners() will trigger rebuild
        _viewModel.setFavorited(false);

        if (isRefined) {
          final originalIdea = ideaHistory[0];
          String refinedType = 'ai_refined';
          if (originalIdea.dataset == 'youth') {
            refinedType = 'ai_refined_youth';
          } else if (originalIdea.dataset == 'seasonal') {
            refinedType = 'ai_refined_seasonal';
          }
          final refinedItemId = '${originalIdea.id}_refined';
          await _viewModel.removeFromFavorites(refinedType, refinedItemId);
        } else {
          String favoriteType = 'idea_details';
          if (currentIdea.dataset == 'youth') {
            favoriteType = 'youth_ideas';
          } else if (currentIdea.dataset == 'seasonal') {
            favoriteType = 'seasonal_ideas';
          }
          await _viewModel.removeFromFavorites(
            favoriteType,
            currentIdea.id.toString(),
          );
        }
        _showSnackBar('idea_details.removed_favorite'.tr(), Colors.grey);
      } else {
        // Update UI immediately (optimistic) - ViewModel's notifyListeners() will trigger rebuild
        _viewModel.setFavorited(true);

        SaveFavoriteResult result;
        if (isRefined) {
          result = await _viewModel.addRefinedToFavorites(
            originalIdea: ideaHistory[0],
            refinedIdea: currentIdea,
          );
        } else {
          result = await _viewModel.addToFavorites(currentIdea);
        }
        // Only show message for successful adds, not for already exists
        if ((result == SaveFavoriteResult.saved ||
                result == SaveFavoriteResult.updated) &&
            context.mounted) {
          _showSnackBar('idea_details.added_favorite'.tr(), Colors.red);
        }
      }
    } catch (_) {
      // Revert UI on error
      _viewModel.setFavorited(!_viewModel.isFavorited);
      _showSnackBar('idea_details.error_favorite'.tr(), Colors.red);
    } finally {
      _isTogglingFavorite = false;
    }
  }

  void _showLimitExceededDialog(BuildContext context, {bool isPro = false}) {
    if (isPro) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => Dialog(
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
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: AutoSizeText(
                      'general.ok'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      minFontSize: 14,
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
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                  color: AppColors.warning.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: AppColors.warning,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              AutoSizeText(
                'script_generator.limit_dialog_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                maxLines: 3,
                minFontSize: 16,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              AutoSizeText(
                'script_generator.limit_dialog_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                maxLines: 6,
                minFontSize: 12,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await adMobService.showRewardedAd(
                          context: dialogCtx,
                          onRewarded: () async {
                            Navigator.of(dialogCtx).pop();
                            if (mounted) {
                              _showSnackBar(
                                'general.extra_generation_granted'.tr(),
                                AppColors.success,
                              );
                            }
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: AutoSizeText(
                        'general.watch_ad'.tr(),
                        maxLines: 2,
                        minFontSize: 11,
                        style: const TextStyle(color: Colors.black),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.warning),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: AutoSizeText(
                        'script_generator.go_pro_button'.tr(),
                        maxLines: 2,
                        minFontSize: 11,
                        style: const TextStyle(color: AppColors.warning),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REFINE WITH AI
  // ═══════════════════════════════════════════════════════

  void _onRefineWithAI() async {
    if (_isStreaming || _isActionLocked) return;

    _isActionLocked = true;
    try {
      final userRepository = UserRepository(UserService());
      final user = await userRepository.getCurrentUser();
      if (user == null) {
        _showSnackBar('errors.user_not_found'.tr(), Colors.red);
        return;
      }

      // Start streaming state — show loading inline
      if (!mounted) return;
      setState(() {
        _isStreaming = true;
        _streamedTitle = '';
        _streamedDescription = '';
        _streamedSteps = [];
        _streamedCta = '';
        _streamPhase = 0;
        _streamCharIndex = 0;
        _streamStepIndex = 0;
      });

      final refinedData = await _refineViewModel.refineIdeaWithAI(
        idea: ideaHistory[currentIndex],
        userId: user.id,
        dailyAiLimit: user.dailyAiLimit.toString(),
        language: context.locale.languageCode,
        length: _selectedLength,
        variation: _selectedVariation,
        emotion: _selectedEmotion,
        platform: _selectedPlatform,
      );

      final newIdea = IdeaModel(
        id: DateTime.now().millisecondsSinceEpoch,
        title:
            refinedData['refined_title'] ??
            '${ideaHistory[currentIndex].title} (${'idea_details.refine_button'.tr()})',
        description:
            refinedData['refined_description'] ??
            ideaHistory[currentIndex].description,
        steps: List<String>.from(
          refinedData['refined_steps'] as List? ??
              ideaHistory[currentIndex].steps,
        ),
        cta: refinedData['refined_cta'] ?? ideaHistory[currentIndex].cta,
        niche: ideaHistory[currentIndex].niche,
        format: ideaHistory[currentIndex].format,
        level:
            refinedData['refined_level'] ?? 'idea_details.pro_ai_enhanced'.tr(),
        dataset: ideaHistory[0].dataset,
      );

      if (!mounted) return;

      // Add to history immediately
      ideaHistory.add(newIdea);
      currentIndex = ideaHistory.length - 1;

      // ⚡ CRITICAL: Reset favorite status for refined idea (it's a NEW idea)
      // Don't auto-check - just keep it false. User can favorite if they want.
      _viewModel.setFavorited(false);

      // 📝 Save refined idea to history (fire-and-forget)
      try {
        String historyType = 'ai_refined';
        final originalDataset = ideaHistory[0].dataset;
        if (originalDataset == 'youth') historyType = 'ai_refined_youth';
        if (originalDataset == 'seasonal') historyType = 'ai_refined_seasonal';

        final userRepository = UserRepository(UserService());
        userRepository.saveHistoryEntry(
          type: historyType,
          prompt: ideaHistory[currentIndex - 1].description,
          output: {
            'refined_title': newIdea.title,
            'refined_description': newIdea.description,
            'refined_steps': newIdea.steps,
            'refined_cta': newIdea.cta,
            'refined_level': newIdea.level,
            'dataset': originalDataset,
          },
          meta: {
            'idea': {...newIdea.toMap(), 'dataset': originalDataset},
          },
        );
      } catch (e) {
        debugPrint('⚠️ Failed to save refined idea to history: $e');
      }

      // Start generative streaming animation
      _startStreamingAnimation(newIdea);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isStreaming = false);
      debugPrint('❌ Refine error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      final isUserFriendly =
          !msg.contains('PlatformException') &&
          !msg.contains('firebase') &&
          !msg.contains('DioException') &&
          !msg.contains('SocketException') &&
          msg.length < 200;
      _showSnackBar(
        isUserFriendly ? msg : 'general.refine_failed'.tr(),
        Colors.red,
      );
    } finally {
      _isActionLocked = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // STREAMING ANIMATION
  // ═══════════════════════════════════════════════════════

  void _startStreamingAnimation(IdeaModel idea) {
    _streamTimer?.cancel();
    _streamPhase = 0;
    _streamCharIndex = 0;
    _streamStepIndex = 0;
    _streamedTitle = '';
    _streamedDescription = '';
    _streamedSteps = [];
    _streamedCta = '';

    const speed = Duration(milliseconds: 18);

    _streamTimer = Timer.periodic(speed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        switch (_streamPhase) {
          case 0: // Stream title
            if (_streamCharIndex < idea.title.length) {
              _streamedTitle = idea.title.substring(0, _streamCharIndex + 1);
              _streamCharIndex++;
            } else {
              _streamPhase = 1;
              _streamCharIndex = 0;
            }
            break;
          case 1: // Stream description
            if (_streamCharIndex < idea.description.length) {
              // Stream 3 chars at a time for description (it's longer)
              final end = (_streamCharIndex + 3).clamp(
                0,
                idea.description.length,
              );
              _streamedDescription = idea.description.substring(0, end);
              _streamCharIndex = end;
            } else {
              _streamPhase = 2;
              _streamCharIndex = 0;
            }
            break;
          case 2: // Stream steps one by one
            if (_streamStepIndex < idea.steps.length) {
              final currentStep = idea.steps[_streamStepIndex];
              if (_streamCharIndex < currentStep.length) {
                final end = (_streamCharIndex + 2).clamp(0, currentStep.length);
                // Build steps list progressively
                if (_streamedSteps.length <= _streamStepIndex) {
                  _streamedSteps.add(currentStep.substring(0, end));
                } else {
                  _streamedSteps[_streamStepIndex] = currentStep.substring(
                    0,
                    end,
                  );
                }
                _streamCharIndex = end;
              } else {
                _streamStepIndex++;
                _streamCharIndex = 0;
              }
            } else {
              _streamPhase = 3;
              _streamCharIndex = 0;
            }
            break;
          case 3: // Stream CTA
            if (_streamCharIndex < idea.cta.length) {
              _streamedCta = idea.cta.substring(0, _streamCharIndex + 1);
              _streamCharIndex++;
            } else {
              _streamPhase = 4;
              timer.cancel();
              _isStreaming = false;
              _showSnackBar(
                'idea_details.snack_refined'.tr(),
                AppColors.success,
              );
              // 🔄 Issue #3 fix: Refresh user limits from server after generation.
              // The backend function takes ~1-2s to write the updated limit.
              // We reload with a 2s delay to show the correct count on home screen.
              Future.delayed(const Duration(seconds: 2), () {
                if (!mounted) return;
                try {
                  final notifier = context.read<UserNotifier>();
                  notifier.reload(forceServer: true);
                } catch (_) {}
              });
            }
            break;
        }
      });
    });
  }

  // ═══════════════════════════════════════════════════════
  // AI SCRIPT NAVIGATION
  // ═══════════════════════════════════════════════════════

  Future<void> _onGenerateScript() async {
    if (_isActionLocked) return;

    _isActionLocked = true;
    try {
      final allowed = await _viewModel.consumeDailyAction();
      if (!allowed) {
        final userRepo = Provider.of<UserRepository>(context, listen: false);
        final user = await userRepo.getCurrentUser();
        _showLimitExceededDialog(context, isPro: user?.isPro == true);
        return;
      }

      if (!context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScriptGeneratorScreen(
            idea: ideaHistory[currentIndex],
            initialLength: _selectedLength,
            initialVariation: _selectedVariation,
            initialEmotion: _selectedEmotion,
            initialPlatform: _selectedPlatform,
          ),
        ),
      );

      if (mounted) {
        setState(() {});
        // 🔄 Issue #3 fix: Refresh user limits after returning from script gen.
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          try {
            context.read<UserNotifier>().reload(forceServer: true);
          } catch (_) {}
        });
      }
    } finally {
      _isActionLocked = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  void _showSnackBar(String message, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Center(
            child: AutoSizeText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 4,
              minFontSize: 12,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          elevation: 8,
        ),
      );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM SHEET — PARAMETER SELECTOR
  // ═══════════════════════════════════════════════════════

  void _showParameterSheet(String mode) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ParameterBottomSheet(
        mode: mode,
        selectedLength: _selectedLength,
        selectedVariation: _selectedVariation,
        selectedEmotion: _selectedEmotion,
        selectedPlatform: _selectedPlatform,
        isRefining: _refineViewModel.isRefining,
        onParamsChanged: (length, variation, emotion, platform) {
          setState(() {
            _selectedLength = length;
            _selectedVariation = variation;
            _selectedEmotion = emotion;
            _selectedPlatform = platform;
          });
        },
        onAction: () {
          Navigator.pop(context);
          if (mode == 'refine') {
            _onRefineWithAI();
          } else {
            _onGenerateScript();
          }
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // CONTENT CARDS
  // ═══════════════════════════════════════════════════════

  Widget _buildContentCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: AutoSizeText(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 3,
                  minFontSize: 13,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  Widget _buildTag(String label, Color color, {bool isPro = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPro
            ? AppColors.warning.withOpacity(0.15)
            : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPro
              ? AppColors.warning.withOpacity(0.4)
              : color.withOpacity(0.3),
        ),
      ),
      child: AutoSizeText(
        label,
        style: TextStyle(
          fontSize: 13,
          color: isPro ? AppColors.warning : color,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        minFontSize: 10,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color foregroundColor,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color : color.withOpacity(0.3),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isActive ? foregroundColor : color),
            const SizedBox(width: 8),
            Flexible(
              child: AutoSizeText(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? foregroundColor : color,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
                minFontSize: 10,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // STREAMING CONTENT BUILDERS
  // ═══════════════════════════════════════════════════════

  /// Returns display title — streaming text or final idea title
  String get _displayTitle {
    if (_isStreaming || _streamPhase > 0) return _streamedTitle;
    return ideaHistory[currentIndex].title;
  }

  String get _displayDescription {
    if (_isStreaming || _streamPhase > 1) return _streamedDescription;
    return ideaHistory[currentIndex].description;
  }

  List<String> get _displaySteps {
    if (_isStreaming || _streamPhase > 2) return _streamedSteps;
    return ideaHistory[currentIndex].steps;
  }

  String get _displayCta {
    if (_isStreaming || _streamPhase > 3) return _streamedCta;
    return ideaHistory[currentIndex].cta;
  }

  bool get _showCursor => _isStreaming && _streamPhase < 4;

  @override
  Widget build(BuildContext context) {
    final currentIdea = ideaHistory[currentIndex];
    final isBoosted =
        currentIdea.level.contains('Boosted') ||
        currentIdea.level.contains('Pro');
    // Use streaming text when streaming, otherwise real idea
    final displayTitle = _displayTitle;
    final displayDesc = _displayDescription;
    final displaySteps = _displaySteps;
    final displayCta = _displayCta;

    return PopScope(
      canPop: !_isStreaming && !_isActionLocked,
      child: Scaffold(
        backgroundColor: AppColors.backgroundTop,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: AutoSizeText(
            'idea_details.title'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            maxLines: 1,
            minFontSize: 14,
            overflow: TextOverflow.ellipsis,
          ),
          foregroundColor: AppColors.textPrimary,
          actions: [
            ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) {
                return IconButton(
                  icon: Icon(
                    _viewModel.isFavorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _viewModel.isFavorited
                        ? Colors.red
                        : AppColors.textSecondary,
                  ),
                  onPressed: _toggleFavorite,
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Scrollable content ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AutoSizeText(
                              displayTitle,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.25,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 5,
                              minFontSize: 18,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_showCursor && _streamPhase == 0)
                            const Text(
                              '▌',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w300,
                                fontSize: 26,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Tags (localized labels) ──
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildTag(
                            IdeaAttributeLabels.instance.labelNiche(
                              currentIdea.niche,
                            ),
                            AppColors.accent,
                          ),
                          _buildTag(
                            IdeaAttributeLabels.instance.labelFormat(
                              currentIdea.format,
                            ),
                            AppColors.success,
                          ),
                          _buildTag(
                            IdeaAttributeLabels.instance.labelLevel(
                              currentIdea.level,
                            ),
                            isBoosted
                                ? AppColors.warning
                                : AppColors.textSecondary,
                            isPro: isBoosted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ── Inline loading indicator (while waiting for API) ──
                      if (_isStreaming &&
                          _streamPhase == 0 &&
                          _streamedTitle.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              AutoSizeText(
                                'idea_details.generating_enhanced'.tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 3,
                                minFontSize: 12,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // ── Core Idea ──
                        _buildContentCard(
                          icon: Icons.lightbulb_outline,
                          iconColor: AppColors.warning,
                          title: 'idea_details.core_idea'.tr(),
                          content: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: AutoSizeText(
                                  displayDesc,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.65,
                                    color: AppColors.textSecondary,
                                  ),
                                  minFontSize: 12,
                                  maxLines: 120,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_showCursor && _streamPhase == 1)
                                const Text(
                                  '▌',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w300,
                                    fontSize: 15,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // ── Action Steps ──
                        if (displaySteps.isNotEmpty)
                          _buildContentCard(
                            icon: Icons.checklist_rounded,
                            iconColor: AppColors.success,
                            title: 'idea_details.action_steps'.tr(),
                            content: Column(
                              children: displaySteps.asMap().entries.map((e) {
                                final isLastStreaming =
                                    _showCursor &&
                                    _streamPhase == 2 &&
                                    e.key == displaySteps.length - 1;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 26,
                                        height: 26,
                                        margin: const EdgeInsets.only(top: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withOpacity(
                                            0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                        ),
                                        child: Center(
                                          child: AutoSizeText(
                                            '${e.key + 1}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.accent,
                                            ),
                                            maxLines: 1,
                                            minFontSize: 9,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: AutoSizeText(
                                                e.value,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color:
                                                      AppColors.textSecondary,
                                                  height: 1.55,
                                                ),
                                                minFontSize: 12,
                                                maxLines: 40,
                                                softWrap: true,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isLastStreaming)
                                              const Text(
                                                '▌',
                                                style: TextStyle(
                                                  color: AppColors.accent,
                                                  fontWeight: FontWeight.w300,
                                                  fontSize: 15,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        // ── CTA ──
                        if (displayCta.isNotEmpty)
                          _buildContentCard(
                            icon: Icons.campaign_rounded,
                            iconColor: AppColors.error,
                            title: 'idea_details.cta_title'.tr(),
                            content: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.accent.withOpacity(0.15),
                                    AppColors.accent.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.accent.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: AutoSizeText(
                                      displayCta,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      textAlign: TextAlign.center,
                                      minFontSize: 12,
                                      maxLines: 20,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_showCursor && _streamPhase == 3)
                                    const Text(
                                      '▌',
                                      style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w300,
                                        fontSize: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // ── Bottom action buttons (pinned) ──
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).padding.bottom + 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundTop,
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: _isStreaming
                              ? 'idea_details.refining'.tr()
                              : 'idea_details.refine_button'.tr(),
                          icon: Icons.auto_fix_high,
                          color: AppColors.warning,
                          foregroundColor: Colors.black,
                          isActive: _isStreaming,
                          onTap: _isStreaming
                              ? () {}
                              : () => _showParameterSheet('refine'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          label: 'idea_details.generate_script'.tr(),
                          icon: Icons.movie_creation_outlined,
                          color: AppColors.accent,
                          foregroundColor: Colors.white,
                          isActive: false,
                          onTap: _isStreaming
                              ? () {}
                              : () => _showParameterSheet('script'),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SEPARATE STATEFUL BOTTOM SHEET WIDGET
// ═══════════════════════════════════════════════════════════

class _ParameterBottomSheet extends StatefulWidget {
  final String mode; // 'refine' or 'script'
  final String selectedLength;
  final String selectedVariation;
  final String selectedEmotion;
  final String selectedPlatform;
  final bool isRefining;
  final void Function(String, String, String, String) onParamsChanged;
  final VoidCallback onAction;

  const _ParameterBottomSheet({
    required this.mode,
    required this.selectedLength,
    required this.selectedVariation,
    required this.selectedEmotion,
    required this.selectedPlatform,
    required this.isRefining,
    required this.onParamsChanged,
    required this.onAction,
  });

  @override
  State<_ParameterBottomSheet> createState() => _ParameterBottomSheetState();
}

class _ParameterBottomSheetState extends State<_ParameterBottomSheet> {
  late String _length;
  late String _variation;
  late String _emotion;
  late String _platform;

  @override
  void initState() {
    super.initState();
    _length = widget.selectedLength;
    _variation = widget.selectedVariation;
    _emotion = widget.selectedEmotion;
    _platform = widget.selectedPlatform;
  }

  void _updateAndNotify() {
    widget.onParamsChanged(_length, _variation, _emotion, _platform);
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    String? svgAsset,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                )
              : null,
          color: isSelected ? null : AppColors.surfaceBright,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withOpacity(0.5)
                : Colors.white.withOpacity(0.06),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (svgAsset != null) ...[
              SvgPicture.asset(svgAsset, width: 15, height: 15),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color:
                    iconColor ??
                    (isSelected ? Colors.white : AppColors.textSecondary),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: AutoSizeText(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
                maxLines: 3,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: AutoSizeText(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
        maxLines: 3,
        minFontSize: 10,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRefine = widget.mode == 'refine';
    final accentColor = isRefine ? AppColors.warning : AppColors.accent;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 20, color: accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AutoSizeText(
                      isRefine
                          ? 'idea_details.customize_refinement'.tr()
                          : 'idea_details.customize_script'.tr(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 3,
                      minFontSize: 14,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.06), height: 1),
            // Scrollable chips
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                children: [
                  // LENGTH
                  _buildSectionLabel('script_generator.param_length'.tr()),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'script_generator.length_super_short'.tr(),
                        isSelected: _length == 'super_short',
                        onTap: () {
                          setState(() => _length = 'super_short');
                          _updateAndNotify();
                        },
                        icon: Icons.flash_on,
                        iconColor: const Color(0xFFFFB800),
                      ),
                      _buildChip(
                        label: 'script_generator.length_short'.tr(),
                        isSelected: _length == 'short',
                        onTap: () {
                          setState(() => _length = 'short');
                          _updateAndNotify();
                        },
                        icon: Icons.trending_up,
                        iconColor: const Color(0xFF00C853),
                      ),
                      _buildChip(
                        label: 'script_generator.length_full'.tr(),
                        isSelected: _length == 'full',
                        onTap: () {
                          setState(() => _length = 'full');
                          _updateAndNotify();
                        },
                        icon: Icons.schedule,
                        iconColor: const Color(0xFF2196F3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // VARIATION
                  _buildSectionLabel('script_generator.param_variation'.tr()),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'script_generator.variation_default'.tr(),
                        isSelected: _variation == 'default',
                        onTap: () {
                          setState(() => _variation = 'default');
                          _updateAndNotify();
                        },
                        icon: Icons.adjust,
                        iconColor: const Color(0xFF757575),
                      ),
                      _buildChip(
                        label: 'script_generator.variation_comedy'.tr(),
                        isSelected: _variation == 'comedy',
                        onTap: () {
                          setState(() => _variation = 'comedy');
                          _updateAndNotify();
                        },
                        icon: Icons.emoji_emotions,
                        iconColor: const Color(0xFFFFC107),
                      ),
                      _buildChip(
                        label: 'script_generator.variation_dramatic'.tr(),
                        isSelected: _variation == 'dramatic',
                        onTap: () {
                          setState(() => _variation = 'dramatic');
                          _updateAndNotify();
                        },
                        icon: Icons.theaters,
                        iconColor: const Color(0xFF9C27B0),
                      ),
                      _buildChip(
                        label: 'script_generator.variation_romantic'.tr(),
                        isSelected: _variation == 'romantic',
                        onTap: () {
                          setState(() => _variation = 'romantic');
                          _updateAndNotify();
                        },
                        icon: Icons.favorite,
                        iconColor: const Color(0xFFE91E63),
                      ),
                      _buildChip(
                        label: 'script_generator.variation_school'.tr(),
                        isSelected: _variation == 'school',
                        onTap: () {
                          setState(() => _variation = 'school');
                          _updateAndNotify();
                        },
                        icon: Icons.school,
                        iconColor: const Color(0xFF1976D2),
                      ),
                      _buildChip(
                        label: 'script_generator.variation_npc'.tr(),
                        isSelected: _variation == 'npc',
                        onTap: () {
                          setState(() => _variation = 'npc');
                          _updateAndNotify();
                        },
                        icon: Icons.smart_toy,
                        iconColor: const Color(0xFF00BCD4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // EMOTION
                  _buildSectionLabel('script_generator.param_emotion'.tr()),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'script_generator.emotion_neutral'.tr(),
                        isSelected: _emotion == 'neutral',
                        onTap: () {
                          setState(() => _emotion = 'neutral');
                          _updateAndNotify();
                        },
                        icon: Icons.face,
                        iconColor: const Color(0xFF757575),
                      ),
                      _buildChip(
                        label: 'script_generator.emotion_funny'.tr(),
                        isSelected: _emotion == 'funny',
                        onTap: () {
                          setState(() => _emotion = 'funny');
                          _updateAndNotify();
                        },
                        icon: Icons.sentiment_very_satisfied,
                        iconColor: const Color(0xFFFFD54F),
                      ),
                      _buildChip(
                        label: 'script_generator.emotion_panic'.tr(),
                        isSelected: _emotion == 'panic',
                        onTap: () {
                          setState(() => _emotion = 'panic');
                          _updateAndNotify();
                        },
                        icon: Icons.warning,
                        iconColor: const Color(0xFFFF6F00),
                      ),
                      _buildChip(
                        label: 'script_generator.emotion_calm'.tr(),
                        isSelected: _emotion == 'calm',
                        onTap: () {
                          setState(() => _emotion = 'calm');
                          _updateAndNotify();
                        },
                        icon: Icons.self_improvement,
                        iconColor: const Color(0xFF0097A7),
                      ),
                      _buildChip(
                        label: 'script_generator.emotion_cinematic'.tr(),
                        isSelected: _emotion == 'cinematic',
                        onTap: () {
                          setState(() => _emotion = 'cinematic');
                          _updateAndNotify();
                        },
                        icon: Icons.movie,
                        iconColor: const Color(0xFF7B1FA2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // PLATFORM
                  _buildSectionLabel('script_generator.param_platform'.tr()),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'script_generator.platform_tiktok'.tr(),
                        isSelected: _platform == 'tiktok',
                        onTap: () {
                          setState(() => _platform = 'tiktok');
                          _updateAndNotify();
                        },
                        svgAsset: 'assets/icons/tiktok.svg',
                      ),
                      _buildChip(
                        label: 'script_generator.platform_reels'.tr(),
                        isSelected: _platform == 'reels',
                        onTap: () {
                          setState(() => _platform = 'reels');
                          _updateAndNotify();
                        },
                        svgAsset: 'assets/icons/instagram.svg',
                      ),
                      _buildChip(
                        label: 'script_generator.platform_shorts'.tr(),
                        isSelected: _platform == 'shorts',
                        onTap: () {
                          setState(() => _platform = 'shorts');
                          _updateAndNotify();
                        },
                        svgAsset: 'assets/icons/youtube-shorts.svg',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // Action button pinned at bottom
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                4 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: Icon(
                    isRefine
                        ? Icons.auto_fix_high
                        : Icons.movie_creation_outlined,
                    size: 18,
                  ),
                  label: AutoSizeText(
                    isRefine
                        ? 'idea_details.refine_with_ai_button'.tr()
                        : 'idea_details.generate_script_button'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    minFontSize: 12,
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: isRefine ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    // ⚡ CRITICAL: Sync parameters to parent BEFORE executing action
                    _updateAndNotify();
                    widget.onAction();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
