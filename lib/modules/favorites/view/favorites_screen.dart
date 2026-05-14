import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/constants/styles.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/core/utils/idea_attribute_labels.dart';
import 'package:ideaboost/core/widgets/skeleton_card_list.dart';
import 'package:ideaboost/modules/favorites/view_model/favorites_view_model.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';

// ─── Private helper widgets ───────────────────────────────────────────────────

class _FavTypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final Color iconGradientEnd;
  const _FavTypeBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.iconGradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.28), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  iconColor.withOpacity(0.22),
                  iconGradientEnd.withOpacity(0.16),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 13),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AutoSizeText(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              minFontSize: 9,
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _DeleteButton({this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.close, size: 16, color: Colors.red.withOpacity(0.72)),
    ),
  );
}

class _FavMiniTag extends StatelessWidget {
  final String label;
  final Color color;
  const _FavMiniTag({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: AutoSizeText(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      maxLines: 2,
      minFontSize: 8,
      overflow: TextOverflow.visible,
      softWrap: true,
    ),
  );
}

class _FavPreviewContainer extends StatelessWidget {
  final Color color;
  final String label;
  final String text;
  const _FavPreviewContainer({
    required this.color,
    required this.label,
    required this.text,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.2), width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AutoSizeText(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        AutoSizeText(
          text,
          maxLines: 2,
          minFontSize: 10,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// Renders hashtags with structured layout: category badge + hashtag pills
class _FavHashtagDetailWidget extends StatelessWidget {
  final dynamic hashtagData;
  final List<String> directHashtags;

  const _FavHashtagDetailWidget({
    required this.hashtagData,
    required this.directHashtags,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Handle structured hashtag maps (with category)
    if (hashtagData is List) {
      for (final item in hashtagData) {
        if (item is Map<String, dynamic>) {
          final category = (item['category'] ?? '').toString().trim();
          final tags = item['tags'] ?? item['hashtags'] ?? [];
          
          if (category.isNotEmpty || (tags is List && tags.isNotEmpty)) {
            if (children.isNotEmpty) {
              children.add(const SizedBox(height: 12));
            }

            if (category.isNotEmpty) {
              children.add(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    category,
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }

            if (tags is List && tags.isNotEmpty) {
              final tagStrings = tags
                  .map((t) {
                    final str = t.toString().trim();
                    return str.startsWith('#') ? str : '#$str';
                  })
                  .where((t) => t.isNotEmpty)
                  .toList();

              if (tagStrings.isNotEmpty) {
                children.add(const SizedBox(height: 8));
                children.add(
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tagStrings
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.typeHashtag.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.typeHashtag.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: AutoSizeText(
                              tag,
                              style: TextStyle(
                                color: AppColors.typeHashtag,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              }
            }
          }
        }
      }
    }

    // Handle direct hashtags as pills
    if (directHashtags.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: directHashtags
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.typeHashtag.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.typeHashtag.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    tag,
                    style: TextStyle(
                      color: AppColors.typeHashtag,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    return children.isEmpty
        ? AutoSizeText(
            'history.detail.not_available'.tr(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  static const String _kAllFilterValue = '__ALL__';
  late FavoritesViewModel _viewModel;
  String _selectedType = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedNiche = _kAllFilterValue;
  String _selectedFormat = _kAllFilterValue;
  String _selectedLevel = _kAllFilterValue;
  Set<String> _availableNiches = {};
  Set<String> _availableFormats = {};
  Set<String> _availableLevels = {};
  String? _ideaAttrLocale;
  Timer? _searchDebounceTimer;
  Timer? _filterUpdateTimer;

  @override
  void initState() {
    super.initState();
    _viewModel = FavoritesViewModel(FavoritesRepository());
    _loadFavorites();
    _viewModel.addListener(_onVMChange);
    _searchController.addListener(_onSearchChange);
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
    _viewModel.removeListener(_onVMChange);
    _searchDebounceTimer?.cancel();
    _filterUpdateTimer?.cancel();
    _searchController.removeListener(_onSearchChange);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChange() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: 400),
      () => setState(() => _searchQuery = _searchController.text),
    );
  }

  void _onVMChange() {
    _filterUpdateTimer?.cancel();
    _filterUpdateTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _updateAvailableFilters();
    });
  }

  void _loadFavorites() {
    final types = _selectedType == 'All'
        ? [
            'idea_details',
            'youth_ideas',
            'seasonal_ideas',
            'ai_refined',
            'ai_refined_youth',
            'ai_refined_seasonal',
            'comments',
            'script',
            'viral_rewrite',
            'hashtag',
            'shot_ideas',
          ]
        : [_selectedType];
    _viewModel.loadFavorites(types: types);
  }

  void _updateAvailableFilters() {
    final filters = _viewModel.getAvailableFilters();
    setState(() {
      _availableNiches = filters['niches'] ?? {};
      _availableFormats = filters['formats'] ?? {};
      _availableLevels = filters['levels'] ?? {};
      if (_selectedNiche != _kAllFilterValue &&
          !_availableNiches.contains(_selectedNiche))
        _selectedNiche = _kAllFilterValue;
      if (_selectedFormat != _kAllFilterValue &&
          !_availableFormats.contains(_selectedFormat))
        _selectedFormat = _kAllFilterValue;
      if (_selectedLevel != _kAllFilterValue &&
          !_availableLevels.contains(_selectedLevel))
        _selectedLevel = _kAllFilterValue;
    });
  }

  String? get _nicheFilterArg =>
      _selectedNiche == _kAllFilterValue ? null : _selectedNiche;
  String? get _formatFilterArg =>
      _selectedFormat == _kAllFilterValue ? null : _selectedFormat;
  String? get _levelFilterArg =>
      _selectedLevel == _kAllFilterValue ? null : _selectedLevel;

  // ── Type helpers (all unchanged) ──────────────────────────────────────────
  String _getTypeLabel(String type) {
    switch (type) {
      case 'idea_details':
        return 'favorites.type.idea_details'.tr();
      case 'youth_ideas':
        return 'favorites.type.youth_ideas'.tr();
      case 'seasonal_ideas':
        return 'favorites.type.seasonal_ideas'.tr();
      case 'script':
        return 'favorites.type.script'.tr();
      case 'comments':
        return 'favorites.type.comments'.tr();
      case 'ai_refined':
        return 'favorites.type.ai_refined'.tr();
      case 'ai_refined_youth':
        return 'favorites.type.ai_refined_youth'.tr();
      case 'ai_refined_seasonal':
        return 'favorites.type.ai_refined_seasonal'.tr();
      case 'viral_rewrite':
        return 'favorites.type.viral_rewrite'.tr();
      case 'hashtag':
        return 'favorites.type.hashtag'.tr();
      case 'shot_ideas':
        return 'favorites.type.shot_ideas'.tr();
      default:
        return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'idea_details':
        return AppColors.typeIdeaDetails;
      case 'youth_ideas':
        return AppColors.typeYouthIdeas;
      case 'seasonal_ideas':
        return AppColors.typeSeasonalIdeas;
      case 'script':
        return AppColors.typeScript;
      case 'comments':
        return AppColors.typeComment;
      case 'ai_refined':
        return AppColors.typeAiRefined;
      case 'ai_refined_youth':
        return AppColors.typeAiRefinedYouth;
      case 'ai_refined_seasonal':
        return AppColors.typeAiRefinedSeasonal;
      case 'viral_rewrite':
        return AppColors.typeViral;
      case 'hashtag':
        return AppColors.typeHashtag;
      case 'shot_ideas':
        return AppColors.typeShotIdeas;
      default:
        return AppColors.accent;
    }
  }

  String _normalizeCommentToneCode(String tone) {
    switch (tone.trim()) {
      // Backward compatibility for older saved favorites.
      case 'Friendly':
        return 'friendly';
      case 'Engaging Comment':
      case 'Engaging':
        return 'engaging_question';
      case 'Humorous':
        return 'humorous';
      case 'Supportive':
        return 'supportive';
      case 'Thought-Provoking':
        return 'thought_provoking';
      case 'Transform to Art':
        return 'hate_to_art';
      default:
        return tone.trim();
    }
  }

  String _localizeCommentTone(String tone, {required String unknownKey}) {
    final normalized = tone.trim();
    if (normalized.isEmpty || normalized == 'Unknown') return unknownKey.tr();

    final code = _normalizeCommentToneCode(normalized);
    const supportedCodes = {
      'friendly',
      'engaging_question',
      'humorous',
      'supportive',
      'thought_provoking',
      'hate_to_art',
    };

    if (supportedCodes.contains(code)) {
      return 'comment_generator.tone_$code'.tr();
    }

    return normalized;
  }

  List<String> _extractHashtags(dynamic source) {
    final tags = <String>[];

    void addTag(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return;
      final normalized = text.startsWith('#') ? text : '#$text';
      if (!tags.contains(normalized)) tags.add(normalized);
    }

    void walk(dynamic value) {
      if (value == null) return;
      if (value is String) {
        final matches = RegExp(r'#[\p{L}\p{N}_]+', unicode: true).allMatches(
          value,
        );
        if (matches.isNotEmpty) {
          for (final match in matches) {
            addTag(match.group(0));
          }
        } else {
          for (final part in value.split(RegExp(r'[\s,]+'))) {
            if (part.trim().isNotEmpty) addTag(part);
          }
        }
        return;
      }

      if (value is Iterable) {
        for (final entry in value) {
          walk(entry);
        }
        return;
      }

      if (value is Map) {
        walk(value['hashtags']);
        walk(value['content']);
        walk(value['items']);
        walk(value['tags']);
        final category = value['category'];
        if (category is String && category.trim().isNotEmpty) {
          final categoryText = category.trim();
          if (categoryText.contains('#')) walk(categoryText);
        }
        return;
      }

      addTag(value);
    }

    walk(source);
    return tags;
  }

  /// Parse a hashtag string (e.g., "#tag1 #tag2" or "tag1, tag2") into individual tags
  void _parseHashtagString(String input, List<String> tags) {
    if (input.isEmpty) return;
    
    // Try to match individual hashtags with regex
    final matches = RegExp(r'#[\p{L}\p{N}_]+', unicode: true).allMatches(input);
    if (matches.isNotEmpty) {
      for (final match in matches) {
        final tag = match.group(0)!;
        if (!tags.contains(tag)) tags.add(tag);
      }
    } else {
      // Fall back to splitting by spaces or commas
      for (final part in input.split(RegExp(r'[\s,]+'))) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) {
          final tag = trimmed.startsWith('#') ? trimmed : '#$trimmed';
          if (!tags.contains(tag)) tags.add(tag);
        }
      }
    }
  }

  Color _getIconColor(String type) {
    if (type.contains('comment')) return AppColors.typeComment;
    if (type.contains('viral')) return AppColors.typeViral;
    if (type.contains('hashtag')) return AppColors.typeHashtag;
    if (type.contains('shot') || type.contains('short'))
      return AppColors.typeShotIdeas;
    if (type.contains('ai_refined_youth')) return AppColors.typeAiRefinedYouth;
    if (type.contains('ai_refined_seasonal'))
      return AppColors.typeAiRefinedSeasonal;
    if (type.contains('ai_refined')) return AppColors.typeAiRefined;
    if (type.contains('script')) return AppColors.typeScript;
    if (type.contains('youth_ideas')) return AppColors.typeYouthIdeas;
    if (type.contains('seasonal_ideas')) return AppColors.typeSeasonalIdeas;
    if (type.contains('idea_details')) return AppColors.typeIdeaDetails;
    return AppColors.accent;
  }

  Color _getIconGradientEnd(String type) {
    // Slightly darker/richer shade of the icon color for gradient depth
    if (type.contains('comment')) return AppColors.typeComment.withOpacity(0.7);
    if (type.contains('viral')) return AppColors.typeViral.withOpacity(0.7);
    if (type.contains('hashtag')) return AppColors.typeHashtag.withOpacity(0.7);
    if (type.contains('shot') || type.contains('short'))
      return AppColors.typeShotIdeas.withOpacity(0.7);
    if (type.contains('ai_refined_youth'))
      return AppColors.typeAiRefinedYouth.withOpacity(0.7);
    if (type.contains('ai_refined_seasonal'))
      return AppColors.typeAiRefinedSeasonal.withOpacity(0.7);
    if (type.contains('ai_refined'))
      return AppColors.typeAiRefined.withOpacity(0.7);
    if (type.contains('script')) return AppColors.typeScript.withOpacity(0.7);
    if (type.contains('youth_ideas'))
      return AppColors.typeYouthIdeas.withOpacity(0.7);
    if (type.contains('seasonal_ideas'))
      return AppColors.typeSeasonalIdeas.withOpacity(0.7);
    if (type.contains('idea_details'))
      return AppColors.typeIdeaDetails.withOpacity(0.7);
    return AppColors.accent.withOpacity(0.7);
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'idea_details':
        return Icons.emoji_objects;
      case 'youth_ideas':
        return Icons.lightbulb;
      case 'seasonal_ideas':
        return Icons.wb_sunny;
      case 'script':
        return Icons.menu_book;
      case 'comments':
        return Icons.chat_bubble_outline;
      case 'ai_refined':
        return Icons.auto_awesome;
      case 'ai_refined_youth':
        return Icons.person;
      case 'ai_refined_seasonal':
        return Icons.calendar_month;
      case 'viral_rewrite':
        return Icons.trending_up;
      case 'hashtag':
        return Icons.tag;
      case 'shot_ideas':
        return Icons.video_camera_back;
      default:
        return Icons.category;
    }
  }

  Future<void> _deleteFavorite(String type, String itemId) async {
    _viewModel.removeFromFavoritesWithUndo(
      type,
      itemId,
      () => debugPrint('Item deleted'),
    );
    if (!mounted) return;
    showSnackBarSafe(
      context,
      SnackBar(
        content: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E1B4B).withOpacity(0.95),
                const Color(0xFF312E81).withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.red[400]!, Colors.red[600]!],
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AutoSizeText(
                      'favorites.snack_removed'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                    const SizedBox(height: 2),
                    AutoSizeText(
                      'Tap undo to restore',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _viewModel.restoreFromFavorites(itemId);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  backgroundColor: AppColors.accent.withOpacity(0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppColors.accent.withOpacity(0.5)),
                  ),
                ),
                child: Text(
                  'general.undo'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ),
    );
  }

  Widget _buildConstrainedDropdownItem(String text) => Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.25,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AutoSizeText(
        text,
        overflow: TextOverflow.visible,
        maxLines: 2,
        minFontSize: 8,
        softWrap: true,
      ),
    ),
  );

  Widget _buildAttributeFilters() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        if (_availableNiches.isNotEmpty)
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedNiche,
              icon: Icon(Icons.expand_more, color: AppColors.accent, size: 18),
              dropdownColor: AppColors.surface,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (v) => setState(() {
                _selectedNiche = v ?? _kAllFilterValue;
                _updateAvailableFilters();
              }),
              items: [
                DropdownMenuItem(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'favorites.all_niches'.tr(),
                  ),
                ),
                ..._availableNiches.map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelNiche(n),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        if (_availableFormats.isNotEmpty)
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedFormat,
              icon: Icon(Icons.expand_more, color: AppColors.accent, size: 18),
              dropdownColor: AppColors.surface,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (v) => setState(() {
                _selectedFormat = v ?? _kAllFilterValue;
                _updateAvailableFilters();
              }),
              items: [
                DropdownMenuItem(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'favorites.all_formats'.tr(),
                  ),
                ),
                ..._availableFormats.map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelFormat(f),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        if (_availableLevels.isNotEmpty)
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedLevel,
              icon: Icon(Icons.expand_more, color: AppColors.accent, size: 18),
              dropdownColor: AppColors.surface,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (v) => setState(() {
                _selectedLevel = v ?? _kAllFilterValue;
                _updateAvailableFilters();
              }),
              items: [
                DropdownMenuItem(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'favorites.all_levels'.tr(),
                  ),
                ),
                ..._availableLevels.map(
                  (l) => DropdownMenuItem(
                    value: l,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelLevel(l),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  String _formatDate(dynamic date) {
    try {
      DateTime dt;
      if (date is String)
        dt = DateTime.tryParse(date) ?? DateTime.now();
      else if (date.runtimeType.toString().contains('Timestamp'))
        dt = date.toDate();
      else if (date is DateTime)
        dt = date;
      else
        return 'Unknown';
      // 📅 Issue #4 fix: Always show absolute date — never "X hours ago".
      final locale = context.locale.languageCode;
      return DateFormat.yMMMd(locale).format(dt);
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF1E1B4B).withOpacity(0.8),
            const Color(0xFF0F0A1A),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.accent,
              size: 22,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: AutoSizeText(
            'favorites.screen_title'.tr(),
            style: AppStyles.headingTextStyle.copyWith(
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            minFontSize: 14,
          ),
          centerTitle: true,
        ),
        body: ChangeNotifierProvider.value(
          value: _viewModel,
          child: Consumer<FavoritesViewModel>(
            builder: (context, vm, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      _buildFilterChip('All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('idea_details'),
                      const SizedBox(width: 8),
                      _buildFilterChip('youth_ideas'),
                      const SizedBox(width: 8),
                      _buildFilterChip('seasonal_ideas'),
                      const SizedBox(width: 8),
                      _buildFilterChip('script'),
                      const SizedBox(width: 8),
                      _buildFilterChip('comments'),
                      const SizedBox(width: 8),
                      _buildFilterChip('ai_refined'),
                      const SizedBox(width: 8),
                      _buildFilterChip('ai_refined_youth'),
                      const SizedBox(width: 8),
                      _buildFilterChip('ai_refined_seasonal'),
                      const SizedBox(width: 8),
                      _buildFilterChip('viral_rewrite'),
                      const SizedBox(width: 8),
                      _buildFilterChip('hashtag'),
                      const SizedBox(width: 8),
                      _buildFilterChip('shot_ideas'),
                    ],
                  ),
                ),
                if (_selectedType == 'script' ||
                    _selectedType == 'ai_refined' ||
                    _selectedType == 'ai_refined_youth' ||
                    _selectedType == 'ai_refined_seasonal' ||
                    _selectedType == 'idea_details' ||
                    _selectedType == 'youth_ideas' ||
                    _selectedType == 'seasonal_ideas' ||
                    _selectedType == 'All')
                  _buildAttributeFilters(),
                const SizedBox(height: 4),
                // Content — skeleton | error | empty | list
                Expanded(child: _buildBody(vm)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(FavoritesViewModel vm) {
    // 1. Loading → skeleton
    if (vm.isLoading) return const SkeletonCardList(cardCount: 4);

    // 2. Error
    if (vm.error.isNotEmpty)
      return ErrorStateWidget(message: vm.error, onRetry: _loadFavorites);

    // 3. Empty data
    if (vm.favorites.isEmpty)
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        title: 'favorites.empty_title'.tr(),
        subtitle: 'favorites.empty_subtitle'.tr(),
      );

    // 4. Filtered list
    final filtered = _viewModel.getFullyFilteredFavorites(
      selectedType: _selectedType,
      searchQuery: _searchQuery,
      selectedNiche: _nicheFilterArg,
      selectedFormat: _formatFilterArg,
      selectedLevel: _levelFilterArg,
    );

    if (filtered.isEmpty)
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        subtitle: 'Try adjusting your filters or search terms.',
      );

    return ListView.builder(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 40,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final item = filtered[i];
        final type = item['type'] as String;
        final itemId = item['id'] as String?;
        return Padding(
          key: ValueKey(itemId),
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildFavoriteCard(item, type, itemId),
        );
      },
    );
  }

  Widget _buildFilterChip(String type) {
    final isSelected = _selectedType == type;
    final label = type == 'All'
        ? 'favorites.filter_all'.tr()
        : _getTypeLabel(type);
    final color = _getTypeColor(type);
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
          _updateAvailableFilters();
        });
        _loadFavorites();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.12),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: AutoSizeText(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white.withOpacity(0.6),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
          minFontSize: 10,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    Map<String, dynamic> item,
    String type,
    String? itemId,
  ) {
    final typeColor = _getTypeColor(type);
    final title = (item['title'] as String? ?? 'Untitled').trim();
    final content = (item['content'] as Map<String, dynamic>?) ?? {};
    final groups = (item['groups'] as List<dynamic>?) ?? [];
    final savedAt = item['savedAt'];
    final generatedAt = item['generatedAt'] as String?;

    return GestureDetector(
      onTap: () => _showDetailModal(context, type, item),
      onLongPress: itemId != null ? () => _deleteFavorite(type, itemId) : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          boxShadow: [
            BoxShadow(
              color: typeColor.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _FavTypeBadge(
                      label: _getTypeLabel(type),
                      color: typeColor,
                      icon: _getTypeIcon(type),
                      iconColor: _getIconColor(type),
                      iconGradientEnd: _getIconGradientEnd(type),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DeleteButton(
                    onTap: itemId != null
                        ? () => _deleteFavorite(type, itemId)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AutoSizeText(
                title,
                maxLines: 3,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              _buildFavContentPreview(type, content, groups),
              const SizedBox(height: 12),
              AutoSizeText(
                _formatDate(savedAt ?? generatedAt),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavContentPreview(
    String type,
    Map<String, dynamic> content,
    List<dynamic> groups,
  ) {
    final c = _getTypeColor(type);
    if (type.contains('comment')) {
      final cg = (content['groups'] as List<dynamic>?) ?? groups;
      String pt = '', tl = '';
      if (cg.isNotEmpty) {
        final fg = cg[0] as Map<String, dynamic>;
        final rawTone = fg['tone'] as String? ?? '';
        tl = rawTone.isEmpty
            ? ''
            : _localizeCommentTone(
                rawTone,
                unknownKey: 'history.detail.unknown_tone',
              );
        final cm = (fg['comments'] as List<dynamic>?) ?? [];
        if (cm.isNotEmpty) pt = cm[0].toString();
      }
      return _FavPreviewContainer(
        color: c,
        label: tl.isNotEmpty
            ? '$tl ${"history.type_comment".tr()}'
            : 'history.type_comment'.tr(),
        text: pt.isEmpty ? 'history.preview_no_content'.tr() : pt,
      );
    }
    if (type.contains('viral')) {
      final r =
          content['rewritten_content'] as String? ??
          content['rewritten'] as String? ??
          '';
      return _FavPreviewContainer(
        color: c,
        label: 'history.type_viral'.tr(),
        text: r.isEmpty ? 'history.preview_no_content'.tr() : r,
      );
    }
    if (type.contains('hashtag')) {
      final cf = content['content'];
      final ht = _extractHashtags([
        cf,
        content['hashtags'],
      ]);
      final pt = ht.isNotEmpty
          ? ht.take(3).join(' ')
          : (cf is String && cf.isNotEmpty)
          ? (cf.length > 50 ? '${cf.substring(0, 50)}...' : cf)
          : '';
      return _FavPreviewContainer(
        color: c,
        label: 'history.type_hashtag'.tr(),
        text: pt.isEmpty ? 'history.preview_no_content'.tr() : pt,
      );
    }
    if (type.contains('shot') || type.contains('short')) {
      final group0 = groups.isNotEmpty && groups.first is Map<String, dynamic>
          ? groups.first as Map<String, dynamic>
          : <String, dynamic>{};

      dynamic ideasField = content['shot_ideas'];
      ideasField ??= content['content'];
      ideasField ??= content['ideas'];
      ideasField ??= content['shotIdeas'];
      ideasField ??= group0['shot_ideas'];
      ideasField ??= group0['content'];
      ideasField ??= group0['ideas'];

      List<dynamic> ideas = [];
      if (ideasField is List) {
        ideas = ideasField;
      } else if (ideasField is String && ideasField.isNotEmpty) {
        ideas = ideasField
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
      }

      final previewText = ideas.isNotEmpty
          ? ideas.first.toString()
          : 'history.preview_no_ideas'.tr();

      return _FavPreviewContainer(
        color: c,
        label: 'history.type_shot'.tr(),
        text: previewText,
      );
    }
    if (type.contains('script')) {
      final sc = (content['shots'] as List?)?.length ?? 0;
      final hv = ((content['voiceover'] as List?)?.isNotEmpty) ?? false;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.2), width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AutoSizeText(
                      'history.type_shot'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                    const SizedBox(height: 6),
                    AutoSizeText(
                      '$sc ${"general.scenes".tr().toLowerCase()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.white.withOpacity(0.1),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AutoSizeText(
                      'general.voiceover'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                    const SizedBox(height: 6),
                    AutoSizeText(
                      hv ? 'general.yes'.tr() : 'general.no'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hv ? c : Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (type.contains('ai_refined')) {
      final group0 = groups.isNotEmpty && groups.first is Map<String, dynamic>
          ? groups.first as Map<String, dynamic>
          : <String, dynamic>{};
      final refinedDescription =
          content['refined_description'] as String? ??
          group0['refinedDescription'] as String? ??
          '';
      final refinedIdea =
          content['refined_idea'] as String? ??
          content['refined'] as String? ??
          '';
      final refinedTitle =
          content['refined_title'] as String? ??
          group0['refinedTitle'] as String? ??
          '';
      final previewText = refinedDescription.isNotEmpty
          ? refinedDescription
          : refinedIdea.isNotEmpty
          ? refinedIdea
          : refinedTitle;
      return _FavPreviewContainer(
        color: c,
        label: 'history.type_refined'.tr(),
        text: previewText.isEmpty ? 'history.preview_no_content'.tr() : previewText,
      );
    }
    if (type.contains('idea_details') ||
        type.contains('youth_ideas') ||
        type.contains('seasonal_ideas')) {
      final desc = content['description'] as String? ?? '';
      final niche = content['niche'] as String? ?? '';
      final fmt = content['format'] as String? ?? '';
      String tc(String s) => s
          .split('_')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (niche.isNotEmpty || fmt.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (niche.isNotEmpty) _FavMiniTag(label: tc(niche), color: c),
                  if (fmt.isNotEmpty) _FavMiniTag(label: tc(fmt), color: c),
                ],
              ),
            if (niche.isNotEmpty || fmt.isNotEmpty) const SizedBox(height: 6),
            AutoSizeText(
              desc.isEmpty ? 'history.preview_no_description'.tr() : desc,
              maxLines: 2,
              minFontSize: 10,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.2), width: 1),
      ),
      child: AutoSizeText(
        'Content available',
        style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600),
        maxLines: 2,
        minFontSize: 11,
        overflow: TextOverflow.visible,
      ),
    );
  }

  void _showDetailModal(
    BuildContext context,
    String type,
    Map<String, dynamic> item,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, sc) => SingleChildScrollView(
          controller: sc,
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subtle drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                AutoSizeText(
                  item['title'] ?? 'Details',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  minFontSize: 14,
                ),
                const SizedBox(height: 8),
                // Subtitle label with locale-aware date formatting
                AutoSizeText(
                  'favorites.saved_on'.tr(
                    namedArgs: {
                      'date': (item['savedAt'] as Timestamp?)?.toDate() != null
                          ? DateFormat(
                              'd MMMM yyyy',
                              context.locale.languageCode == 'hi'
                                  ? 'en'
                                  : context.locale.languageCode,
                            ).format((item['savedAt'] as Timestamp).toDate())
                          : 'Unknown',
                    },
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  minFontSize: 10,
                ),
                const SizedBox(height: 24),
                // Simple divider
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 24),
                // Content section
                _buildDetailContent(type, item),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced implementation that displays saved favorite data
  Widget _buildDetailContent(String type, Map<String, dynamic> item) {
    final content = item['content'] as Map<String, dynamic>? ?? {};
    final groups = (item['groups'] as List<dynamic>?) ?? [];

    // Comments
    if (type.contains('comment')) {
      final groups = (content['groups'] as List<dynamic>?) ?? [];
      final inputText = item['input'] as String? ?? item['title'] ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('favorites.original_prompt'.tr(), inputText),
          const SizedBox(height: 20),
          ...groups.asMap().entries.map((e) {
            final groupMap = e.value as Map<String, dynamic>;
            final rawTone = groupMap['tone'] as String? ?? '';
            final tone = _localizeCommentTone(
              rawTone,
              unknownKey: 'history.detail.unknown_tone',
            );
            final comments = (groupMap['comments'] as List<dynamic>?) ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00D4FF).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    tone,
                    style: const TextStyle(
                      color: Color(0xFF00D4FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    minFontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                ...comments.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBright,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: AutoSizeText(
                        '${entry.key + 1}. ${entry.value}',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        maxLines: 12,
                        minFontSize: 11,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      );
    }

    // Viral Rewrite
    if (type.contains('viral')) {
      final inputText = item['input'] as String? ?? item['title'] ?? '';
      final rewritten =
          content['rewritten_content'] as String? ??
          content['rewritten'] as String? ??
          '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('favorites.original_prompt'.tr(), inputText),
          const SizedBox(height: 20),
          _detailSection('favorites.viral_rewrite'.tr(), rewritten),
        ],
      );
    }

    // Hashtags
    if (type.contains('hashtag')) {
      final inputText = item['input'] as String? ?? item['title'] ?? '';
      List<String> directTags = [];
      List<Map<String, dynamic>> structuredHashtags = [];
      
      // Try to get hashtags from different possible locations
      dynamic hashtagsRaw = content['hashtags'] ?? content['content'];
      
      // Normalize hashtags: could be List, String, or null
      if (hashtagsRaw is List) {
        for (final ht in hashtagsRaw) {
          if (ht is Map<String, dynamic>) {
            // Structured hashtag with category
            structuredHashtags.add(ht);
          } else if (ht is String && ht.isNotEmpty) {
            // Parse string for individual hashtags (#tag1 #tag2 or comma-separated)
            _parseHashtagString(ht, directTags);
          }
        }
      } else if (hashtagsRaw is String && hashtagsRaw.isNotEmpty) {
        // Single hashtag string: parse it for individual tags
        _parseHashtagString(hashtagsRaw, directTags);
      }
      
      // If no structured or direct tags found, use extraction fallback
      if (structuredHashtags.isEmpty && directTags.isEmpty) {
        final extracted = _extractHashtags([
          content['content'],
          content['hashtags'],
        ]);
        directTags = extracted;
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('favorites.original_prompt'.tr(), inputText),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  'favorites.hashtags_generated'.tr(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _FavHashtagDetailWidget(
                    hashtagData: structuredHashtags.isNotEmpty
                        ? structuredHashtags
                        : [],
                    directHashtags: directTags,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Shot / Short Ideas
    if (type.contains('shot') || type.contains('short')) {
      final inputText = item['input'] as String? ?? item['title'] ?? '';
      final groups = (item['groups'] as List<dynamic>?) ?? [];
      final group0 = groups.isNotEmpty && groups.first is Map<String, dynamic>
          ? groups.first as Map<String, dynamic>
          : <String, dynamic>{};

      dynamic cf = content['shot_ideas'];
      cf ??= content['content'];
      cf ??= content['ideas'];
      cf ??= content['shotIdeas'];
      cf ??= group0['shot_ideas'];
      cf ??= group0['content'];
      cf ??= group0['ideas'];

      List<dynamic> ideas = [];
      if (cf is List) {
        ideas = cf;
      } else if (cf is String && cf.isNotEmpty) {
        ideas = cf.split('\n').where((l) => l.trim().isNotEmpty).toList();
      } else {
        // Safely handle content['ideas'] which could be List, String, or null
        final ideasField = content['ideas'];
        if (ideasField is List) {
          ideas = ideasField;
        } else if (ideasField is String && ideasField.isNotEmpty) {
          ideas = ideasField
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
        } else {
          ideas = [];
        }
      }
      final ideasText = ideas
          .asMap()
          .entries
          .map(
            (e) =>
                '${e.key + 1}. ${_stripLeadingListMarker(e.value.toString())}',
          )
          .join('\n');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('favorites.original_prompt'.tr(), inputText),
          const SizedBox(height: 20),
          _detailSection(
            'favorites.ideas_count'.tr(namedArgs: {'count': '${ideas.length}'}),
            ideasText.isEmpty ? 'history.preview_no_ideas'.tr() : ideasText,
          ),
        ],
      );
    }

    // Script / Video
    if (type.contains('script')) {
      final inputText = item['input'] as String? ?? item['title'] ?? '';
      final hook = content['hook'] as String? ?? '';
      final cta = content['cta'] as String? ?? '';

      // Safely handle shots which could be List, String, or null
      List<dynamic> shots = [];
      final shotsField = content['shots'];
      if (shotsField is List) {
        shots = shotsField;
      } else if (shotsField is String && shotsField.isNotEmpty) {
        shots = [shotsField];
      }

      // Safely handle hashtags which could be List, String, or null
      List<dynamic> hashtags = [];
      final hashtagsField = content['hashtags'];
      if (hashtagsField is List) {
        hashtags = hashtagsField;
      } else if (hashtagsField is String && hashtagsField.isNotEmpty) {
        hashtags = [hashtagsField];
      }

      final shotsText = shots.isNotEmpty
          ? shots
                .asMap()
                .entries
                .map((e) {
                  final shot = e.value;
                  if (shot is Map<String, dynamic>) {
                    return '${e.key + 1}. [${shot['duration'] ?? ''}]\n${shot['description'] ?? ''}';
                  }
                  return '${e.key + 1}. ${shot.toString()}';
                })
                .join('\n\n')
          : '';
      final hashtagsText = hashtags.isNotEmpty ? hashtags.join(' ') : '';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('favorites.original_prompt'.tr(), inputText),
          const SizedBox(height: 16),
          if (hook.isNotEmpty) ...[
            _detailSection('favorites.hook'.tr(), hook),
            const SizedBox(height: 16),
          ],
          if (shotsText.isNotEmpty) ...[
            _detailSection(
              'favorites.scenes'.tr(namedArgs: {'count': '${shots.length}'}),
              shotsText,
            ),
            const SizedBox(height: 16),
          ],
          if (cta.isNotEmpty) ...[
            _detailSection('favorites.cta'.tr(), cta),
            const SizedBox(height: 16),
          ],
          if (hashtagsText.isNotEmpty) ...[
            _detailSection('favorites.hashtags_generated'.tr(), hashtagsText),
          ],
        ],
      );
    }

    // Ideas / Seasonal Ideas
    if (type.contains('youth_ideas') ||
        type.contains('seasonal_ideas') ||
        type.contains('idea')) {
      final title = content['title'] as String? ?? item['title'] ?? '';
      final description = content['description'] as String? ?? '';
      final niche = content['niche'] as String? ?? '';
      final format = content['format'] as String? ?? '';
      final level = content['level'] as String? ?? '';

      // Safely handle steps which could be List, String, or null
      List<dynamic> steps = [];
      final stepsField = content['steps'];
      if (stepsField is List) {
        steps = stepsField;
      } else if (stepsField is String && stepsField.isNotEmpty) {
        steps = stepsField
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
      }

      final stepsText = steps.isNotEmpty
          ? steps
                .asMap()
                .entries
                .map(
                  (e) =>
                      '${e.key + 1}. ${_stripLeadingListMarker(e.value.toString())}',
                )
                .join('\n')
          : '';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            _detailSection('favorites.title'.tr(), title),
            const SizedBox(height: 16),
          ],
          if (description.isNotEmpty) ...[
            _detailSection('favorites.description'.tr(), description),
            const SizedBox(height: 16),
          ],
          if (niche.isNotEmpty || format.isNotEmpty || level.isNotEmpty)
            Row(
              children: [
                if (niche.isNotEmpty)
                  Expanded(
                    child: _detailSection('favorites.niche'.tr(), niche),
                  ),
                if (format.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _detailSection('favorites.format'.tr(), format),
                  ),
                ],
                if (level.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _detailSection('favorites.level'.tr(), level),
                  ),
                ],
              ],
            ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('favorites.steps'.tr(), stepsText),
          ],
        ],
      );
    }

    // AI Refined Ideas
    if (type.contains('ai_refined')) {
      final group0 = groups.isNotEmpty && groups.first is Map<String, dynamic>
          ? groups.first as Map<String, dynamic>
          : <String, dynamic>{};

      final originalIdea =
          item['input'] as String? ??
          content['original_idea'] as String? ??
          content['original'] as String? ??
          group0['originalDescription'] as String? ??
          item['title'] ??
          '';
      final refinedTitle =
          content['refined_title'] as String? ??
          group0['refinedTitle'] as String? ??
          '';
      final refinedDescription =
          content['refined_description'] as String? ??
          content['refined_idea'] as String? ??
          content['refined'] as String? ??
          group0['refinedDescription'] as String? ??
          '';

      List<dynamic> refinedSteps = [];
      final refinedStepsField = content['refined_steps'];
      if (refinedStepsField is List) {
        refinedSteps = refinedStepsField;
      } else if (refinedStepsField is String && refinedStepsField.isNotEmpty) {
        refinedSteps = refinedStepsField
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
      } else {
        final groupSteps = group0['refinedSteps'];
        if (groupSteps is List) {
          refinedSteps = groupSteps;
        } else if (groupSteps is String && groupSteps.isNotEmpty) {
          refinedSteps = groupSteps
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
        }
      }

      final refinedCta =
          content['refined_cta'] as String? ??
          group0['refinedCta'] as String? ??
          '';
      final refinedLevel =
          content['refined_level'] as String? ??
          group0['refinedLevel'] as String? ??
          '';

      final stepsText = refinedSteps
          .map((e) => e.toString())
          .toList()
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${_stripLeadingListMarker(e.value)}')
          .join('\n');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (originalIdea.isNotEmpty) ...[
            _detailSection('history.detail.original_idea'.tr(), originalIdea),
            const SizedBox(height: 16),
          ],
          if (refinedTitle.isNotEmpty) ...[
            _detailSection('history.detail.refined_title'.tr(), refinedTitle),
            const SizedBox(height: 16),
          ],
          if (refinedDescription.isNotEmpty) ...[
            _detailSection(
              'history.detail.refined_description'.tr(),
              refinedDescription,
            ),
            const SizedBox(height: 16),
          ],
          if (stepsText.isNotEmpty) ...[
            _detailSection('history.detail.refined_steps'.tr(), stepsText),
            const SizedBox(height: 16),
          ],
          if (refinedCta.isNotEmpty) ...[
            _detailSection('history.detail.refined_cta'.tr(), refinedCta),
            const SizedBox(height: 16),
          ],
          if (refinedLevel.isNotEmpty) ...[
            _detailSection('history.detail.refined_level'.tr(), refinedLevel),
          ],
          if (originalIdea.isEmpty &&
              refinedTitle.isEmpty &&
              refinedDescription.isEmpty &&
              stepsText.isEmpty &&
              refinedCta.isEmpty &&
              refinedLevel.isEmpty)
            _detailSection(
              'favorites.content'.tr(),
              content['refined'] as String? ?? item['title'] ?? 'history.preview_no_content'.tr(),
            ),
        ],
      );
    }

    // Default fallback
    return _detailSection(
      'favorites.content'.tr(),
      item['title'] ?? 'history.preview_no_content'.tr(),
    );
  }

  Widget _detailSection(String label, String value) {
    final displayValue = value.isEmpty ? 'N/A' : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoSizeText(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          maxLines: 2,
          minFontSize: 10,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.6,
              ),
              children: _buildStyledDetailSpans(displayValue),
            ),
          ),
        ),
      ],
    );
  }

  String _stripLeadingListMarker(String text) {
    return text.replaceFirst(RegExp(r'^\s*\d+[\.)]\s+'), '').trim();
  }

  List<InlineSpan> _buildStyledDetailSpans(String value) {
    final spans = <InlineSpan>[];
    final normalized = value
        .split('\n')
        .map(
          (line) => line.replaceFirst(RegExp(r'^(\s*\d+\.\s*)\d+\.\s+'), r'$1'),
        )
        .join('\n');
    // Updated regex to support Unicode letters (Cyrillic, Arabic, etc.)
    final exp = RegExp(
      r'\*\*(.*?)\*\*|(#[\p{L}\p{N}_]+)',
      dotAll: false,
      unicode: true,
    );
    int start = 0;

    for (final match in exp.allMatches(normalized)) {
      if (match.start > start) {
        spans.add(TextSpan(text: normalized.substring(start, match.start)));
      }

      if (match.group(1) != null) {
        // Bold Markdown
        spans.add(
          TextSpan(
            text: match.group(1) ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF00D4FF),
            ),
          ),
        );
      } else if (match.group(2) != null) {
        // Hashtag match
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.only(right: 4, bottom: 4, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                ),
              ),
              child: Text(
                match.group(2)!,
                style: const TextStyle(
                  color: Color(0xFF00D4FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        );
      }
      start = match.end;
    }

    if (start < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(start)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: normalized));
    }

    return spans;
  }
}
