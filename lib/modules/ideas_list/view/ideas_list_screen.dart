// lib/modules/ideas_list/view/ideas_list_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:ideaboost/core/constants/colors.dart';
import 'package:ideaboost/core/constants/styles.dart';
import 'package:ideaboost/modules/ideas_list/view_model/ideas_list_view_model.dart';
import 'package:ideaboost/modules/idea_details/view/idea_details_screen.dart';
import 'package:ideaboost/data/notifiers/user_notifier.dart';
import '../../../core/services/admob_service.dart';
import '../../../core/utils/idea_attribute_labels.dart';

class IdeasListScreen extends StatefulWidget {
  final String dataset;

  const IdeasListScreen({super.key, this.dataset = 'ideas'});

  @override
  State<IdeasListScreen> createState() => _IdeasListScreenState();
}

class _IdeasListScreenState extends State<IdeasListScreen>
    with WidgetsBindingObserver {
  /// Sentinel for dropdown “all” option (must not be a real niche/format/level).
  static const String _kAllFilterValue = '__ALL__';

  final AdMobService adMobService = AdMobService();
  late IdeasListViewModel viewModel;
  String? lastLanguage;
  String? _ideaAttrLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    viewModel = IdeasListViewModel(dataset: widget.dataset);
    // Don't try to get language in initState - it will be set in build()
    lastLanguage = null;
    adMobService.loadBanner(onLoaded: () => mounted ? setState(() {}) : null);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // Reload ideas when system locale changes
    if (mounted) {
      viewModel.reloadIdeas();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    viewModel.dispose();
    adMobService.disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if locale changed and reload ideas with the new language
    final currentLocale = EasyLocalization.of(context)?.locale.languageCode;

    if (lastLanguage != currentLocale && currentLocale != null) {
      lastLanguage = currentLocale;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 🚀 FIX: Pass language directly to ensure correct translation loads
          viewModel.reloadIdeas(language: currentLocale);
        }
      });
    }

    return ChangeNotifierProvider.value(
      value: viewModel,
      child: Consumer<IdeasListViewModel>(
        builder: (context, vm, child) {
          if (viewModel.isLoading) {
            return _LoadingSplash(dataset: widget.dataset);
          }

          final filteredIdeas = viewModel.filteredIdeas;
          final screenWidth = MediaQuery.of(context).size.width;
          final isMobile = screenWidth < 600;
          final crossAxisCount = isMobile ? 2 : (screenWidth < 1000 ? 3 : 4);

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
                  'ideas_list.title'.tr(),
                  style: AppStyles.headingTextStyle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  minFontSize: 14,
                ),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.search_rounded,
                      color: AppColors.accent,
                      size: 24,
                    ),
                    onPressed: () => showSearch(
                      context: context,
                      delegate: IdeaSearchDelegate(viewModel),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFiltersLikeFavorites(viewModel),
                    const SizedBox(height: 10),
                    if (filteredIdeas.isEmpty)
                      _buildEmptyStateScrollable()
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio:
                                    0.85, // ← optimized height per card
                                crossAxisSpacing: isMobile ? 12 : 16,
                                mainAxisSpacing: isMobile ? 12 : 16,
                              ),
                          itemCount: filteredIdeas.length,
                          itemBuilder: (context, index) {
                            final idea = filteredIdeas[index];
                            return GestureDetector(
                              onTap: () {
                                if (mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          IdeaDetailsScreen(idea: idea),
                                    ),
                                  );
                                }
                              },
                              child: KeyedSubtree(
                                key: ValueKey(idea.id),
                                child: _IdeaCard(idea: idea),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              bottomNavigationBar:
                  (!context.watch<UserNotifier>().userModel.isPro &&
                      adMobService.isBannerLoaded)
                  ? SafeArea(
                      child: Container(
                        color: Colors.white,
                        child: SizedBox(
                          height: adMobService.bannerAd!.size.height.toDouble(),
                          child: AdWidget(ad: adMobService.bannerAd!),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  /// Same filter row structure as [FavoritesScreen] (padding, colors, dropdowns).
  /// Dropdown titles & items are forcibly constrained to prevent overflow on mobile.
  Widget _buildFiltersLikeFavorites(IdeasListViewModel vm) {
    String nicheValue() =>
        vm.selectedNiche != null && vm.niches.contains(vm.selectedNiche)
        ? vm.selectedNiche!
        : _kAllFilterValue;
    String formatValue() =>
        vm.selectedFormat != null && vm.formats.contains(vm.selectedFormat)
        ? vm.selectedFormat!
        : _kAllFilterValue;
    String levelValue() =>
        vm.selectedLevel != null && vm.levels.contains(vm.selectedLevel)
        ? vm.selectedLevel!
        : _kAllFilterValue;

    final sortedNiches = vm.niches.toList()..sort();
    final sortedFormats = vm.formats.toList()..sort();
    final sortedLevels = vm.levels.toList()..sort();

    // Helper to wrap dropdown items with forced width constraint
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (vm.niches.isNotEmpty)
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: false,
                value: nicheValue(),
                icon: Icon(
                  Icons.expand_more,
                  color: AppColors.accent,
                  size: 18,
                ),
                dropdownColor: AppColors.surface,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                underline: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    height: 1,
                    color: AppColors.accent.withOpacity(0.3),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  vm.updateNiche(value == _kAllFilterValue ? null : value);
                },
                items: [
                  DropdownMenuItem<String>(
                    value: _kAllFilterValue,
                    child: _buildConstrainedDropdownItem(
                      'favorites.all_niches'.tr(),
                    ),
                  ),
                  ...sortedNiches.map(
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
          if (vm.formats.isNotEmpty)
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: false,
                value: formatValue(),
                icon: Icon(
                  Icons.expand_more,
                  color: AppColors.accent,
                  size: 18,
                ),
                dropdownColor: AppColors.surface,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                underline: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    height: 1,
                    color: AppColors.accent.withOpacity(0.3),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  vm.updateFormat(value == _kAllFilterValue ? null : value);
                },
                items: [
                  DropdownMenuItem<String>(
                    value: _kAllFilterValue,
                    child: _buildConstrainedDropdownItem(
                      'favorites.all_formats'.tr(),
                    ),
                  ),
                  ...sortedFormats.map(
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
          if (vm.levels.isNotEmpty)
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: false,
                value: levelValue(),
                icon: Icon(
                  Icons.expand_more,
                  color: AppColors.accent,
                  size: 18,
                ),
                dropdownColor: AppColors.surface,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                underline: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    height: 1,
                    color: AppColors.accent.withOpacity(0.3),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  vm.updateLevel(value == _kAllFilterValue ? null : value);
                },
                items: [
                  DropdownMenuItem<String>(
                    value: _kAllFilterValue,
                    child: _buildConstrainedDropdownItem(
                      'favorites.all_levels'.tr(),
                    ),
                  ),
                  ...sortedLevels.map(
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

  Widget _buildEmptyStateScrollable() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 90,
            color: Colors.white24,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AutoSizeText(
              'ideas_list.empty_title'.tr(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              minFontSize: 14,
              overflow: TextOverflow.visible,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AutoSizeText(
              'ideas_list.empty_subtitle'.tr(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 6,
              minFontSize: 12,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}

class IdeaSearchDelegate extends SearchDelegate {
  final IdeasListViewModel viewModel;

  IdeaSearchDelegate(this.viewModel);

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Colors.black54),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 2),
        ),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => query.isNotEmpty
      ? [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              query = '';
              viewModel.searchIdeas('');
            },
          ),
        ]
      : null;

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    color: Colors.white,
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildResults();
  @override
  Widget buildSuggestions(BuildContext context) {
    // 🚀 PERF: Only filter when query actually changes (debounced)
    viewModel.searchIdeas(query);
    return _buildResults();
  }

  Widget _buildResults() {
    final results = viewModel.filteredIdeas;
    return results.isEmpty
        ? Center(
            child: Text(
              'ideas_list.search_no_results'.tr(),
              style: const TextStyle(color: Colors.white54, fontSize: 18),
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.87,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: results.length,
            itemBuilder: (context, i) => GestureDetector(
              onTap: () {
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IdeaDetailsScreen(idea: results[i]),
                    ),
                  );
                }
              },
              // 🚀 PERF: Use ValueKey for efficient search result updates
              child: KeyedSubtree(
                key: ValueKey(results[i].id),
                child: _IdeaCard(idea: results[i]),
              ),
            ),
          );
  }
}

// ─── REPLACE the entire _IdeaCard class with this ────────────────────────────

class _IdeaCard extends StatelessWidget {
  final dynamic idea;
  const _IdeaCard({required this.idea, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1000;

    // Responsive border radius
    final borderRadius = isMobile
        ? 18.0
        : isTablet
        ? 20.0
        : 22.0;

    // Responsive padding
    final cardPadding = isMobile
        ? const EdgeInsets.fromLTRB(10, 12, 10, 10)
        : isTablet
        ? const EdgeInsets.fromLTRB(12, 14, 12, 12)
        : const EdgeInsets.fromLTRB(14, 16, 14, 14);

    // Responsive spacing between title and tags
    final titleTagSpacing = isMobile ? 4.0 : 6.0;

    // Responsive title font size
    final titleFontSize = isMobile
        ? 13.0
        : isTablet
        ? 14.0
        : 15.0;
    final titleMinFontSize = isMobile ? 9.0 : 10.0;

    return Hero(
      tag: 'idea_${idea.id}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF2A3A50).withOpacity(0.9),
              const Color(0xFF1A2a3a).withOpacity(0.85),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
          boxShadow: [
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFF00D4FF).withOpacity(0.1),
              blurRadius: 25,
              spreadRadius: -8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title: fills remaining space, max 3 lines, auto-shrinks ──
                Expanded(
                  child: AutoSizeText(
                    idea.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 3,
                    minFontSize: titleMinFontSize,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),

                SizedBox(height: titleTagSpacing),

                // ── Tags section: never overflows, never cuts ──
                _buildTagsSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagsSection(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Responsive spacing
    final chipSpacing = isMobile ? 5.0 : 6.0;
    final chipRunSpacing = isMobile ? 4.0 : 5.0;
    final sectionSpacing = isMobile ? 2.0 : 3.0;

    final formatLabel = IdeaAttributeLabels.instance.labelFormat(
      idea.format ?? '',
    );
    final levelLabel = IdeaAttributeLabels.instance.labelLevel(
      idea.level ?? '',
    );
    final nicheLabel = IdeaAttributeLabels.instance.labelNiche(
      idea.niche ?? '',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Format + Level row: Wrap so long words stack, never clip ──
        Wrap(
          spacing: chipSpacing,
          runSpacing: chipRunSpacing,
          children: [
            _TagChip(
              label: formatLabel,
              color: const Color(0xFF00D4FF),
              bg: const Color(0xFF00D4FF),
            ),
            _TagChip(
              label: levelLabel,
              color: const Color(0xFFFFD700),
              bg: const Color(0xFFFFD700),
            ),
          ],
        ),

        SizedBox(height: sectionSpacing),

        // ── Niche: full width, wraps to 2 lines, auto-shrinks font ──
        _NicheChip(label: nicheLabel),
      ],
    );
  }
}

// ─── Inline tag chip (format / level) ────────────────────────────────────────
// Uses IntrinsicWidth so the chip hugs its text — but can grow up to the
// available width. AutoSizeText shrinks font before any word ever gets cut.

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _TagChip({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1000;

    // Responsive font size
    final fontSize = isMobile
        ? 10.0
        : isTablet
        ? 11.0
        : 12.0;
    final minFontSize = isMobile ? 7.0 : 8.0;

    // Responsive padding
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
        : isTablet
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 7);

    // Responsive border radius
    final borderRadius = isMobile ? 6.0 : 7.0;

    return Container(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.of(context).size.width / 2) - 32,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: bg.withOpacity(0.13),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: AutoSizeText(
        label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        maxLines: 2,
        minFontSize: minFontSize,
        overflow: TextOverflow.visible,
        softWrap: true,
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Full-width niche chip ────────────────────────────────────────────────────

class _NicheChip extends StatelessWidget {
  final String label;

  const _NicheChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1000;

    // Responsive font size
    final fontSize = isMobile
        ? 10.0
        : isTablet
        ? 11.0
        : 12.0;
    final minFontSize = isMobile ? 7.0 : 8.0;

    // Responsive padding
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
        : isTablet
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 7);

    // Responsive border radius
    final borderRadius = isMobile ? 6.0 : 7.0;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF00D4FF).withOpacity(0.10),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: AutoSizeText(
        label,
        style: TextStyle(
          color: const Color(0xFF00D4FF),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0.3,
        ),
        // Niche gets 3 lines max — Cyrillic/Arabic categories can be long
        maxLines: 3,
        minFontSize: minFontSize,
        overflow: TextOverflow.visible,
        softWrap: true,
        textAlign: TextAlign.start,
      ),
    );
  }
}

// 🚀 PERF: Optimized loading splash with smooth animation
class _LoadingSplash extends StatefulWidget {
  final String dataset;
  const _LoadingSplash({required this.dataset});

  @override
  State<_LoadingSplash> createState() => _LoadingSplashState();
}

class _LoadingSplashState extends State<_LoadingSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    // 🚀 PERF: Simple rotation animation - lightweight & smooth
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Container(
        // 🚀 PERF: Simple gradient - no complex effects
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🚀 PERF: Rotating icon using Transform
                RotationTransition(
                  turns: _animationController,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00D4FF),
                        width: 3,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        color: Color(0xFF00D4FF),
                        size: 45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Dataset-specific loading text
                AutoSizeText(
                  _getLoadingText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Subtle subtext
                AutoSizeText(
                  'Loading amazing ideas for you...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                // 🚀 PERF: Minimal dots animation using opacity fade
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildDotIndicator(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🚀 PERF: Ultra-light dot animation
  Widget _buildDotIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            // Simple opacity animation for dots
            final value = (_animationController.value * 3 - index).clamp(
              0.0,
              1.0,
            );
            return Transform.scale(
              scale: 0.6 + (value * 0.4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00D4FF).withOpacity(0.3 + (value * 0.7)),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  String _getLoadingText() {
    switch (widget.dataset) {
      case 'youth':
        return 'Loading Youth Ideas';
      case 'seasonal':
        return 'Loading Seasonal Ideas';
      default:
        return 'Loading Ideas';
    }
  }
}
