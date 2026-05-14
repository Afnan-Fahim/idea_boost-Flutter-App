import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/helpers.dart';
import '../../../core/utils/idea_attribute_labels.dart';
import '../../../core/widgets/skeleton_card_list.dart';

import '../view_model/history_view_model.dart';
import '../model/history_item_model.dart';
import '../../../core/constants/colors.dart' as AppColors;

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets (extracted so the card layout stays readable)
// ─────────────────────────────────────────────────────────────────────────────

/// Type badge chip — lives inside an [Expanded] in the card header row,
/// so it can NEVER overflow into the sibling action buttons regardless of
/// how long the Russian / Arabic / Uzbek label is.
///
/// [AutoSizeText] shrinks the font (down to 9sp) before ever wrapping to
/// a second line, and uses [TextOverflow.visible] — no ellipsis, ever.
class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final Color iconGradientEnd;

  const _TypeBadge({
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
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small gradient icon container
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
          // Flexible so it never pushes sibling buttons
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
              overflow: TextOverflow.visible, // NO "..." ever
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact square icon button used for copy / delete.
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color.withOpacity(0.75)),
      ),
    );
  }
}

/// Renders hashtags with structured layout: category badge + hashtag pills
class _HashtagDetailWidget extends StatelessWidget {
  final dynamic hashtagData;
  final List<String> directHashtags;

  const _HashtagDetailWidget({
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
                    color: AppColors.AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.AppColors.accent.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    category,
                    style: TextStyle(
                      color: AppColors.AppColors.accent,
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
                              color: AppColors.AppColors.typeHashtag.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.AppColors.typeHashtag.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: AutoSizeText(
                              tag,
                              style: TextStyle(
                                color: AppColors.AppColors.typeHashtag,
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
                    color: AppColors.AppColors.typeHashtag.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.AppColors.typeHashtag.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: AutoSizeText(
                    tag,
                    style: TextStyle(
                      color: AppColors.AppColors.typeHashtag,
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

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// Sentinel value so the dropdown always has a matching [DropdownMenuItem].
  static const String _kAllFilterValue = '__ALL__';

  late HistoryViewModel vm;
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

  @override
  void initState() {
    super.initState();
    vm = HistoryViewModel();
    vm.init();
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
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChange);
    _searchController.dispose();
    vm.disposeViewModel();
    super.dispose();
  }

  void _onSearchChange() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
        _updateAvailableFilters();
      }
    });
  }

  // ── Type helpers (unchanged) ──────────────────────────────────────────────

  String _getTypeLabel(String type) {
    if (type.contains('comment')) return 'history.type_comment'.tr();
    if (type.contains('viral')) return 'history.type_viral'.tr();
    if (type.contains('hashtag')) return 'history.type_hashtag'.tr();
    if (type.contains('shot') ||
        type.contains('short') ||
        type.contains('shot_ideas'))
      return 'history.type_shot'.tr();
    if (type.contains('ai_refined_youth'))
      return 'history.type_refined_youth'.tr();
    if (type.contains('ai_refined_seasonal'))
      return 'history.type_refined_seasonal'.tr();
    if (type.contains('ai_refined')) return 'history.type_refined'.tr();
    if (type.contains('script')) return 'history.type_script'.tr();
    if (type.contains('youth_ideas')) return 'history.type_youth_ideas'.tr();
    if (type.contains('seasonal_ideas'))
      return 'history.type_seasonal_ideas'.tr();
    if (type.contains('idea_details')) return 'history.type_idea'.tr();
    return 'history.type_item'.tr();
  }

  Color _getTypeColor(String type) {
    if (type.contains('comment')) return AppColors.AppColors.typeComment;
    if (type.contains('viral')) return AppColors.AppColors.typeViral;
    if (type.contains('hashtag')) return AppColors.AppColors.typeHashtag;
    if (type.contains('shot') || type.contains('short'))
      return AppColors.AppColors.typeShotIdeas;
    if (type.contains('ai_refined_youth'))
      return AppColors.AppColors.typeAiRefinedYouth;
    if (type.contains('ai_refined_seasonal'))
      return AppColors.AppColors.typeAiRefinedSeasonal;
    if (type.contains('ai_refined')) return AppColors.AppColors.typeAiRefined;
    if (type.contains('script')) return AppColors.AppColors.typeScript;
    if (type.contains('youth_ideas')) return AppColors.AppColors.typeYouthIdeas;
    if (type.contains('seasonal_ideas'))
      return AppColors.AppColors.typeSeasonalIdeas;
    if (type.contains('idea_details'))
      return AppColors.AppColors.typeIdeaDetails;
    return AppColors.AppColors.accent;
  }

  String _normalizeCommentToneCode(String tone) {
    switch (tone.trim()) {
      // Backward compatibility for older saved history items.
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
        final matches = RegExp(
          r'#[\p{L}\p{N}_]+',
          unicode: true,
        ).allMatches(value);
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


  IconData _getTypeIcon(String type) {
    if (type.contains('comment')) return Icons.chat_bubble_outline;
    if (type.contains('viral')) return Icons.trending_up;
    if (type.contains('hashtag')) return Icons.tag;
    if (type.contains('shot') || type.contains('short'))
      return Icons.video_camera_back;
    if (type.contains('ai_refined_youth')) return Icons.person;
    if (type.contains('ai_refined_seasonal')) return Icons.calendar_month;
    if (type.contains('ai_refined')) return Icons.auto_awesome;
    if (type.contains('script')) return Icons.menu_book;
    if (type.contains('youth_ideas')) return Icons.lightbulb;
    if (type.contains('seasonal_ideas')) return Icons.wb_sunny;
    if (type.contains('idea_details')) return Icons.emoji_objects;
    return Icons.category;
  }

  Color _getIconColor(String type) {
    if (type.contains('comment')) return AppColors.AppColors.typeComment;
    if (type.contains('viral')) return AppColors.AppColors.typeViral;
    if (type.contains('hashtag')) return AppColors.AppColors.typeHashtag;
    if (type.contains('shot') || type.contains('short'))
      return AppColors.AppColors.typeShotIdeas;
    if (type.contains('ai_refined_youth'))
      return AppColors.AppColors.typeAiRefinedYouth;
    if (type.contains('ai_refined_seasonal'))
      return AppColors.AppColors.typeAiRefinedSeasonal;
    if (type.contains('ai_refined')) return AppColors.AppColors.typeAiRefined;
    if (type.contains('script')) return AppColors.AppColors.typeScript;
    if (type.contains('youth_ideas')) return AppColors.AppColors.typeYouthIdeas;
    if (type.contains('seasonal_ideas'))
      return AppColors.AppColors.typeSeasonalIdeas;
    if (type.contains('idea_details'))
      return AppColors.AppColors.typeIdeaDetails;
    return AppColors.AppColors.accent;
  }

  Color _getIconGradientEnd(String type) {
    // Slightly darker/richer shade of the icon color for gradient depth
    if (type.contains('comment'))
      return AppColors.AppColors.typeComment.withOpacity(0.7);
    if (type.contains('viral'))
      return AppColors.AppColors.typeViral.withOpacity(0.7);
    if (type.contains('hashtag'))
      return AppColors.AppColors.typeHashtag.withOpacity(0.7);
    if (type.contains('shot') || type.contains('short'))
      return AppColors.AppColors.typeShotIdeas.withOpacity(0.7);
    if (type.contains('ai_refined_youth'))
      return AppColors.AppColors.typeAiRefinedYouth.withOpacity(0.7);
    if (type.contains('ai_refined_seasonal'))
      return AppColors.AppColors.typeAiRefinedSeasonal.withOpacity(0.7);
    if (type.contains('ai_refined'))
      return AppColors.AppColors.typeAiRefined.withOpacity(0.7);
    if (type.contains('script'))
      return AppColors.AppColors.typeScript.withOpacity(0.7);
    if (type.contains('youth_ideas'))
      return AppColors.AppColors.typeYouthIdeas.withOpacity(0.7);
    if (type.contains('seasonal_ideas'))
      return AppColors.AppColors.typeSeasonalIdeas.withOpacity(0.7);
    if (type.contains('idea_details'))
      return AppColors.AppColors.typeIdeaDetails.withOpacity(0.7);
    return AppColors.AppColors.accent.withOpacity(0.7);
  }

  // ── Dropdown helpers (unchanged) ──────────────────────────────────────────

  Widget _buildConstrainedDropdownItem(String text) {
    return Container(
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
  }

  Widget _buildAttributeFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedNiche,
              icon: Icon(
                Icons.expand_more,
                color: AppColors.AppColors.accent,
                size: 18,
              ),
              dropdownColor: AppColors.AppColors.surface,
              style: TextStyle(
                color: AppColors.AppColors.textPrimary,
                fontSize: 12,
              ),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedNiche = value ?? _kAllFilterValue;
                  _updateAvailableFilters();
                });
              },
              items: [
                DropdownMenuItem<String>(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'history.all_niches'.tr(),
                  ),
                ),
                ..._availableNiches.map(
                  (niche) => DropdownMenuItem<String>(
                    value: niche,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelNiche(niche),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedFormat,
              icon: Icon(
                Icons.expand_more,
                color: AppColors.AppColors.accent,
                size: 18,
              ),
              dropdownColor: AppColors.AppColors.surface,
              style: TextStyle(
                color: AppColors.AppColors.textPrimary,
                fontSize: 12,
              ),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedFormat = value ?? _kAllFilterValue;
                  _updateAvailableFilters();
                });
              },
              items: [
                DropdownMenuItem<String>(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'history.all_formats'.tr(),
                  ),
                ),
                ..._availableFormats.map(
                  (format) => DropdownMenuItem<String>(
                    value: format,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelFormat(format),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: false,
              value: _selectedLevel,
              icon: Icon(
                Icons.expand_more,
                color: AppColors.AppColors.accent,
                size: 18,
              ),
              dropdownColor: AppColors.AppColors.surface,
              style: TextStyle(
                color: AppColors.AppColors.textPrimary,
                fontSize: 12,
              ),
              underline: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  height: 1,
                  color: AppColors.AppColors.accent.withOpacity(0.3),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedLevel = value ?? _kAllFilterValue;
                  _updateAvailableFilters();
                });
              },
              items: [
                DropdownMenuItem<String>(
                  value: _kAllFilterValue,
                  child: _buildConstrainedDropdownItem(
                    'history.all_levels'.tr(),
                  ),
                ),
                ..._availableLevels.map(
                  (level) => DropdownMenuItem<String>(
                    value: level,
                    child: _buildConstrainedDropdownItem(
                      IdeaAttributeLabels.instance.labelLevel(level),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Date / title helpers (unchanged) ─────────────────────────────────────

  String _formatDate(DateTime dateTime) {
    final locale = context.locale.languageCode;
    // 📅 Issue #4 fix: Always show absolute date — never "X hours ago".
    return DateFormat.yMMMd(locale).format(dateTime);
  }

  String _getDisplayTitle(HistoryItem item) {
    if (item.type.contains('script') && item.meta.containsKey('idea')) {
      try {
        final ideaMap = item.meta['idea'] as Map<String, dynamic>;
        final title = ideaMap['title'] as String?;
        if (title != null && title.trim().isNotEmpty) return title;
      } catch (_) {}
    }
    return item.prompt;
  }

  void _updateAvailableFilters() {
    final filters = vm.getAvailableFilters();
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

  // ── Delete (unchanged) ────────────────────────────────────────────────────

  Future<void> _deleteItem(String itemId) async {
    vm.deleteOneWithUndo(itemId, () {
      debugPrint('Item permanently deleted from backend');
    });

    if (mounted) {
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.AppColors.primaryDark.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
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
                        'history.deleted'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(height: 2),
                      AutoSizeText(
                        'general.tap_undo_to_restore'.tr(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        minFontSize: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    vm.restoreFromDelete(itemId);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: AppColors.AppColors.accent.withOpacity(
                      0.25,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: AppColors.AppColors.accent.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: AutoSizeText(
                    'general.undo'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    minFontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        ),
      );
    }
  }

  // ── Content preview (unchanged) ───────────────────────────────────────────

  Widget _buildContentPreview(HistoryItem item) {
    final output = item.output;
    final typeColor = _getTypeColor(item.type);

    if (item.type.contains('comment')) {
      final groups = (output['groups'] as List<dynamic>?) ?? [];
      String previewText = '';
      String toneLabel = '';
      if (groups.isNotEmpty) {
        final firstGroup = groups[0] as Map<String, dynamic>;
        final comments = (firstGroup['comments'] as List<dynamic>?) ?? [];
        final rawTone = firstGroup['tone'] as String? ?? '';
        toneLabel = rawTone.isEmpty
            ? ''
            : _localizeCommentTone(
                rawTone,
                unknownKey: 'history.detail.unknown_tone',
              );
        if (comments.isNotEmpty) previewText = comments[0].toString();
      }
      return _PreviewContainer(
        color: typeColor,
        label: toneLabel.isNotEmpty
            ? '$toneLabel ${"history.type_comment".tr()}'
            : 'history.type_comment'.tr(),
        text: previewText.isEmpty
            ? 'history.preview_no_content'.tr()
            : previewText,
      );
    }

    if (item.type.contains('viral')) {
      final rewritten =
          output['rewritten_content'] as String? ??
          output['rewritten'] as String? ??
          '';
      return _PreviewContainer(
        color: typeColor,
        label: 'history.type_viral'.tr(),
        text: rewritten.isEmpty ? 'history.preview_no_content'.tr() : rewritten,
      );
    }

    if (item.type.contains('hashtag')) {
      final content = output['content'];
      final hashtags = _extractHashtags([content, output['hashtags']]);
      final previewText = hashtags.isNotEmpty
          ? hashtags.take(3).join(' ')
          : (content is String && content.isNotEmpty)
          ? (content.length > 50 ? '${content.substring(0, 50)}...' : content)
          : '';
      return _PreviewContainer(
        color: typeColor,
        label: 'history.type_hashtag'.tr(),
        text: previewText.isEmpty
            ? 'history.preview_no_content'.tr()
            : previewText,
      );
    }

    if (item.type.contains('shot') || item.type.contains('short')) {
      final content = output['content'];
      List<dynamic> ideas = [];
      if (content is List) {
        ideas = content;
      } else if (content is String && content.isNotEmpty) {
        ideas = content
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(2)
            .toList();
      } else {
        final i = output['ideas'];
        if (i is List)
          ideas = i;
        else if (i is String)
          ideas = [i.trim()];
      }
      return _PreviewContainer(
        color: typeColor,
        label: 'history.type_shot'.tr(),
        text: ideas.isNotEmpty
            ? ideas.first.toString()
            : 'history.preview_no_ideas'.tr(),
      );
    }

    if (item.type.contains('script')) {
      final shotCount = (output['shots'] as List?)?.length ?? 0;
      final hasVoiceover =
          ((output['voiceover'] as List?)?.isNotEmpty) ?? false;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: typeColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: typeColor.withOpacity(0.2), width: 1),
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
                    ),
                    const SizedBox(height: 6),
                    AutoSizeText(
                      'history.scenes_count_line'.tr(
                        namedArgs: {'n': '$shotCount'},
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      minFontSize: 11,
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
                    ),
                    const SizedBox(height: 6),
                    AutoSizeText(
                      hasVoiceover ? 'general.yes'.tr() : 'general.no'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hasVoiceover
                            ? typeColor
                            : Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      minFontSize: 11,
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

    if (item.type.contains('ai_refined')) {
      final refinedDescription = output['refined_description'] as String? ?? '';
      final refinedIdea = output['refined_idea'] as String? ?? output['refined'] as String? ?? '';
      final refinedTitle = output['refined_title'] as String? ?? '';
      
      final previewText = refinedDescription.isNotEmpty
          ? refinedDescription
          : refinedIdea.isNotEmpty
          ? refinedIdea
          : refinedTitle;
          
      return _PreviewContainer(
        color: typeColor,
        label: 'history.type_refined'.tr(),
        text: previewText.isEmpty
            ? 'history.preview_no_content'.tr()
            : previewText,
      );
    }

    // idea_details / youth_ideas / seasonal_ideas — tag + description
    if (item.type.contains('idea_details') ||
        item.type.contains('youth_ideas') ||
        item.type.contains('seasonal_ideas')) {
      final description = output['description'] as String? ?? '';
      final niche = output['niche'] as String? ?? '';
      final format = output['format'] as String? ?? '';
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: typeColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: typeColor.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (niche.isNotEmpty || format.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (niche.isNotEmpty)
                    _MiniTag(
                      label: niche
                          .split('_')
                          .map(
                            (w) => w.isNotEmpty
                                ? '${w[0].toUpperCase()}${w.substring(1)}'
                                : '',
                          )
                          .join(' '),
                      color: typeColor,
                    ),
                  if (format.isNotEmpty)
                    _MiniTag(
                      label: format
                          .split('_')
                          .map(
                            (w) => w.isNotEmpty
                                ? '${w[0].toUpperCase()}${w.substring(1)}'
                                : '',
                          )
                          .join(' '),
                      color: typeColor,
                    ),
                ],
              ),
            if (niche.isNotEmpty || format.isNotEmpty)
              const SizedBox(height: 6),
            AutoSizeText(
              description.isEmpty
                  ? 'history.preview_no_description'.tr()
                  : description,
              maxLines: 2,
              minFontSize: 10,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: typeColor,
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
        color: typeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: typeColor.withOpacity(0.2), width: 1),
      ),
      child: AutoSizeText(
        'history.preview_content_available'.tr(),
        style: TextStyle(
          color: typeColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 3,
        minFontSize: 11,
        overflow: TextOverflow.visible,
      ),
    );
  }

  // ── History card — FIXED ──────────────────────────────────────────────────
  //
  // Root cause of screenshot bugs:
  //   OLD: Stack with badge as Flexible child and action buttons at top:16,end:16
  //        → long Russian badge text could grow past the buttons' x position
  //   NEW: proper Row(badge Expanded | copy button | delete button)
  //        → Expanded consumes all remaining space; buttons are always visible
  //
  Widget _buildHistoryCard(HistoryItem item) {
    final typeColor = _getTypeColor(item.type);
    final typeLabel = _getTypeLabel(item.type);

    return GestureDetector(
      onTap: () => _showDetailModal(context, item),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.AppColors.surface,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: badge (Expanded) + copy + delete ──────────────
              // KEY FIX: No Stack. Badge is inside Expanded so it can NEVER
              // push the action buttons off-screen regardless of text length.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Badge — absorbs all available width
                  Expanded(
                    child: _TypeBadge(
                      label: typeLabel,
                      color: typeColor,
                      icon: _getTypeIcon(item.type),
                      iconColor: _getIconColor(item.type),
                      iconGradientEnd: _getIconGradientEnd(item.type),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Copy button — always visible, fixed 34×34
                  _ActionIconButton(
                    icon: Icons.copy,
                    color: Colors.blue,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.prompt));
                      showSnackBarSafe(
                        context,
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AutoSizeText(
                                  'history.copied'.tr(),
                                  maxLines: 2,
                                  minFontSize: 11,
                                  overflow: TextOverflow.visible,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 6),

                  // Delete button — always visible, fixed 34×34
                  _ActionIconButton(
                    icon: Icons.close,
                    color: Colors.red,
                    onTap: () => _deleteItem(item.id),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Title — full available width, no overlap risk ─────────────
              AutoSizeText(
                _getDisplayTitle(item),
                maxLines: 3,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 10),

              // ── Content preview ───────────────────────────────────────────
              _buildContentPreview(item),

              const SizedBox(height: 12),

              // ── Footer: date + details button ─────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: AutoSizeText(
                      _formatDate(item.generatedAt),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      minFontSize: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showDetailModal(context, item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 4),
                          AutoSizeText(
                            'history.details'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            minFontSize: 9,
                            overflow: TextOverflow.visible,
                          ),
                        ],
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

  // ── Filter chip — no ellipsis, chip scrolls horizontally ─────────────────
  Widget _buildFilterChip(String type) {
    final isSelected = _selectedType == type;
    final typeColor = _getTypeColor(type);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
          _updateAvailableFilters();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? typeColor.withOpacity(0.18)
              : AppColors.AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? typeColor : Colors.white.withOpacity(0.12),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        // Chips are inside a horizontal scroll — width is unconstrained,
        // so we let AutoSizeText flow naturally (no ellipsis).
        child: AutoSizeText(
          type == 'All' ? 'history.filter_all'.tr() : _getTypeLabel(type),
          style: TextStyle(
            color: isSelected ? typeColor : Colors.white.withOpacity(0.6),
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

  // ── Detail modal (unchanged) ───────────────────────────────────────────────

  void _showDetailModal(BuildContext context, HistoryItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Subtle drag handle ──
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
                  // ── Title ──
                  AutoSizeText(
                    _getDisplayTitle(item),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    minFontSize: 14,
                  ),
                  const SizedBox(height: 8),
                  // ── Subtitle with generated date (locale-aware formatting) ──
                  AutoSizeText(
                    'history.generated_on'.tr(
                      namedArgs: {
                        'date': DateFormat(
                          'd MMMM yyyy',
                          context.locale.languageCode == 'hi'
                              ? 'en'
                              : context.locale.languageCode,
                        ).format(item.generatedAt),
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
                  // ── Simple divider ──
                  Container(height: 1, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 24),
                  _buildDetailContent(item),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Detail content (unchanged) ────────────────────────────────────────────

  Widget _buildDetailContent(HistoryItem item) {
    final output = item.output;

    if (item.type.contains('comment')) {
      final groups = (output['groups'] as List<dynamic>?) ?? [];
      final inputText = output['inputText'] as String? ?? item.prompt;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('history.detail.original_prompt'.tr(), inputText),
          const SizedBox(height: 20),
          ...groups.map((group) {
            final groupMap = group as Map<String, dynamic>;
            final rawTone = groupMap['tone'] as String? ?? '';
            final toneDisplay = _localizeCommentTone(
              rawTone,
              unknownKey: 'history.detail.unknown_tone',
            );
            final comments = (groupMap['comments'] as List<dynamic>?) ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  toneDisplay,
                  style: TextStyle(
                    color: AppColors.AppColors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 3,
                  minFontSize: 12,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                ...comments.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.AppColors.surfaceBright,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: AutoSizeText(
                        '${entry.key + 1}. ${entry.value}',
                        style: TextStyle(
                          color: AppColors.AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.4,
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

    if (item.type.contains('viral')) {
      final rewritten =
          output['rewritten_content'] as String? ??
          output['rewritten'] as String? ??
          '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('history.detail.original_prompt'.tr(), item.prompt),
          const SizedBox(height: 16),
          _detailSection('history.detail.viral_rewrite'.tr(), rewritten),
        ],
      );
    }

    if (item.type.contains('hashtag')) {
      final content = output['content'];
      final hashtagsRaw = output['hashtags'];
      
      // Separate structured hashtags (maps) from direct tags (strings)
      List<Map<String, dynamic>> structuredHashtags = [];
      List<String> directTags = [];
      
      if (hashtagsRaw is List) {
        for (final item in hashtagsRaw) {
          if (item is Map<String, dynamic>) {
            structuredHashtags.add(item);
          } else if (item is String && item.isNotEmpty) {
            // Parse string for individual hashtags (#tag1 #tag2 or comma-separated)
            _parseHashtagString(item, directTags);
          }
        }
      } else if (hashtagsRaw is String && hashtagsRaw.isNotEmpty) {
        // hashtagsRaw is a single string: parse it for individual tags
        _parseHashtagString(hashtagsRaw, directTags);
      }
      
      // Add any extracted hashtags that aren't already in direct tags
      if (structuredHashtags.isEmpty && directTags.isEmpty) {
        final extracted = _extractHashtags([content, hashtagsRaw]);
        directTags = extracted;
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('history.detail.original_prompt'.tr(), item.prompt),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  'history.detail.hashtags'.tr(),
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
                    color: AppColors.AppColors.background,
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
                  child: _HashtagDetailWidget(
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

    if (item.type.contains('shot') || item.type.contains('short')) {
      final content = output['content'];
      List<dynamic> ideas = [];
      if (content is List) {
        ideas = content;
      } else if (content is String && content.isNotEmpty) {
        ideas = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
      } else {
        ideas = (output['ideas'] as List<dynamic>?) ?? [];
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
          _detailSection('history.detail.original_prompt'.tr(), item.prompt),
          const SizedBox(height: 16),
          _detailSection(
            'history.detail.ideas_created'.tr(),
            'history.detail.ideas_count'.tr(
              namedArgs: {'n': '${ideas.length}'},
            ),
          ),
          const SizedBox(height: 16),
          _detailSection('history.detail.content'.tr(), ideasText),
        ],
      );
    }

    if (item.type.contains('script')) {
      return _buildScriptDetail(item, output);
    }

    if (item.type.contains('youth_ideas') ||
        item.type.contains('seasonal_ideas')) {
      return _buildSimpleIdeaDetail(item, output);
    }

    if (item.type.contains('idea_details')) {
      final hook = output['hook'] as String? ?? '';
      return hook.isNotEmpty
          ? _buildScriptDetail(item, output)
          : _buildSimpleIdeaDetail(item, output);
    }

    if (item.type.contains('ai_refined')) {
      final refinedTitle = output['refined_title'] as String? ?? '';
      final refinedDescription = output['refined_description'] as String? ?? '';
      final refinedSteps = output['refined_steps'] as List? ?? [];
      final refinedCta = output['refined_cta'] as String? ?? '';
      final refinedLevel = output['refined_level'] as String? ?? '';
      final stepsText = refinedSteps.isNotEmpty
          ? refinedSteps
                .asMap()
                .entries
                .map(
                  (e) =>
                      '${e.key + 1}. ${_stripLeadingListMarker(e.value.toString())}',
                )
                .join('\n')
          : 'history.detail.no_steps'.tr();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailSection('history.detail.original_idea'.tr(), item.prompt),
          if (refinedTitle.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('history.detail.refined_title'.tr(), refinedTitle),
          ],
          if (refinedDescription.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection(
              'history.detail.refined_description'.tr(),
              refinedDescription,
            ),
          ],
          if (refinedSteps.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('history.detail.refined_steps'.tr(), stepsText),
          ],
          if (refinedCta.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('history.detail.refined_cta'.tr(), refinedCta),
          ],
          if (refinedLevel.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailSection('history.detail.refined_level'.tr(), refinedLevel),
          ],
        ],
      );
    }

    return _detailSection('history.detail.content'.tr(), item.prompt);
  }

  Widget _buildScriptDetail(HistoryItem item, Map<String, dynamic> output) {
    final hook = output['hook'] as String? ?? '';
    final cta = output['cta'] as String? ?? '';
    final hashtags = output['hashtags'] as List? ?? [];
    final shots = (output['shots'] as List?) ?? [];
    final voiceovers = (output['voiceover'] as List?) ?? [];
    String? ideaTitle;
    String? ideaDescription;
    if (item.meta.containsKey('idea')) {
      try {
        final ideaMap = item.meta['idea'] as Map<String, dynamic>;
        ideaTitle = ideaMap['title'] as String?;
        ideaDescription = ideaMap['description'] as String?;
      } catch (_) {}
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
    final voiceoverText = voiceovers.isNotEmpty
        ? voiceovers
              .asMap()
              .entries
              .map(
                (e) =>
                    '${e.key + 1}. ${_stripLeadingListMarker(e.value.toString())}',
              )
              .join('\n\n')
        : '';
    final hashtagsText = _extractHashtags([
      hashtags,
      output['content'],
    ]).join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ideaTitle != null && ideaTitle.isNotEmpty) ...[
          _detailSection('history.detail.idea_title'.tr(), ideaTitle),
          const SizedBox(height: 16),
        ],
        if (ideaDescription != null && ideaDescription.isNotEmpty) ...[
          _detailSection(
            'history.detail.idea_description'.tr(),
            ideaDescription,
          ),
          const SizedBox(height: 16),
        ],
        if (hook.isNotEmpty) ...[
          _detailSection('history.detail.hook'.tr(), hook),
          const SizedBox(height: 16),
        ],
        if (shotsText.isNotEmpty) ...[
          _detailSection(
            '${"general.scenes".tr()} (${shots.length})',
            shotsText,
          ),
          const SizedBox(height: 16),
        ],
        if (voiceoverText.isNotEmpty) ...[
          _detailSection(
            '${"general.voiceover".tr()} (${voiceovers.length})',
            voiceoverText,
          ),
          const SizedBox(height: 16),
        ],
        if (cta.isNotEmpty) ...[
          _detailSection('history.detail.cta'.tr(), cta),
          const SizedBox(height: 16),
        ],
        _detailSection(
          'history.type_hashtag'.tr(),
          hashtagsText.isEmpty
              ? 'history.detail.no_hashtags'.tr()
              : hashtagsText,
        ),
      ],
    );
  }

  Widget _buildSimpleIdeaDetail(HistoryItem item, Map<String, dynamic> output) {
    final title = output['title'] as String? ?? '';
    final description = output['description'] as String? ?? '';
    final niche = output['niche'] as String? ?? '';
    final format = output['format'] as String? ?? '';
    final level = output['level'] as String? ?? '';
    final steps = output['steps'] as List? ?? [];
    final cta = output['cta'] as String? ?? '';
    final stepsText = steps.isNotEmpty
        ? steps
              .asMap()
              .entries
              .map(
                (e) =>
                    '${e.key + 1}. ${_stripLeadingListMarker(e.value.toString())}',
              )
              .join('\n')
        : 'history.detail.no_steps'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          _detailSection('history.detail.idea_title'.tr(), title),
          const SizedBox(height: 16),
        ],
        if (description.isNotEmpty) ...[
          _detailSection('history.detail.description'.tr(), description),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            if (niche.isNotEmpty)
              Expanded(
                child: _detailSection('history.filter_niche'.tr(), niche),
              ),
            if (format.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _detailSection('history.filter_format'.tr(), format),
              ),
            ],
            if (level.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _detailSection('history.filter_level'.tr(), level),
              ),
            ],
          ],
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailSection('history.detail.steps'.tr(), stepsText),
        ],
        if (cta.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailSection('history.detail.cta'.tr(), cta),
        ],
      ],
    );
  }

  Widget _detailSection(String label, String value) {
    final displayValue = value.isEmpty
        ? 'history.detail.not_available'.tr()
        : value;

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
            color: AppColors.AppColors.background,
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
                color: AppColors.AppColors.textPrimary,
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

  // ── Build history content (separated to prevent full list rebuild) ───────
  Widget _buildHistoryContent(HistoryViewModel vm, List<HistoryItem> items) {
    if (vm.isLoading) {
      return SkeletonCardList(cardCount: 5);
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            AutoSizeText(
              'history.empty_title'.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            AutoSizeText(
              'history.empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      cacheExtent: 500,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom + 32,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          key: ValueKey(items[index].id),
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildHistoryCard(items[index]),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: vm,
      child: Consumer<HistoryViewModel>(
        builder: (context, vm, child) {
          final items = vm.getFullyFilteredItems(
            selectedType: _selectedType,
            searchQuery: _searchQuery,
            selectedNiche: _nicheFilterArg,
            selectedFormat: _formatFilterArg,
            selectedLevel: _levelFilterArg,
          );
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
                    color: AppColors.AppColors.accent,
                    size: 22,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                title: AutoSizeText(
                  'history.title'.tr(),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  minFontSize: 16,
                  overflow: TextOverflow.ellipsis,
                ),
                centerTitle: true,
                actions: [
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'all') vm.setDateFilter(DateFilter.all);
                      if (v == 'today') vm.setDateFilter(DateFilter.today);
                      if (v == 'week') vm.setDateFilter(DateFilter.week);
                      if (v == 'month') vm.setDateFilter(DateFilter.month);
                      if (v == 'clear_all') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: AutoSizeText(
                              'history.confirm_clear_all'.tr(),
                              maxLines: 3,
                              minFontSize: 14,
                              overflow: TextOverflow.ellipsis,
                            ),
                            content: AutoSizeText(
                              'history.confirm_clear_message'.tr(),
                              maxLines: 8,
                              minFontSize: 12,
                              overflow: TextOverflow.ellipsis,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: AutoSizeText(
                                  'history.action_cancel'.tr(),
                                  maxLines: 1,
                                  minFontSize: 12,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: AutoSizeText(
                                  'history.action_clear'.tr(),
                                  maxLines: 2,
                                  minFontSize: 11,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await vm.clearAll();
                          setState(() {});
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'all',
                        child: AutoSizeText(
                          'history.filter_all'.tr(),
                          maxLines: 2,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'today',
                        child: AutoSizeText(
                          'history.filter_today'.tr(),
                          maxLines: 2,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'week',
                        child: AutoSizeText(
                          'history.filter_week'.tr(),
                          maxLines: 2,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'month',
                        child: AutoSizeText(
                          'history.filter_month'.tr(),
                          maxLines: 2,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'clear_all',
                        child: AutoSizeText(
                          'history.clear_all'.tr(),
                          maxLines: 2,
                          minFontSize: 11,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              body: Directionality(
                textDirection: Directionality.of(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Type filter chips (horizontal scroll) ──────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
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
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),

                    // ── Attribute filters ──────────────────────────────────
                    if (_selectedType == 'script' ||
                        _selectedType == 'ai_refined' ||
                        _selectedType == 'ai_refined_youth' ||
                        _selectedType == 'ai_refined_seasonal' ||
                        _selectedType == 'idea_details' ||
                        _selectedType == 'youth_ideas' ||
                        _selectedType == 'seasonal_ideas' ||
                        _selectedType == 'All')
                      _buildAttributeFilters(),

                    // ── Content area ───────────────────────────────────────
                    Expanded(child: _buildHistoryContent(vm, items)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny reusable private widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Simple two-line preview container shared by most content types.
class _PreviewContainer extends StatelessWidget {
  final Color color;
  final String label;
  final String text;

  const _PreviewContainer({
    required this.color,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

/// Tiny pill tag used in idea_details / youth / seasonal preview cards.
class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: AutoSizeText(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        minFontSize: 8,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
