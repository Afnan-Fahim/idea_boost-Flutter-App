import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  int _selectedPlan = 1; // 0 = monthly, 1 = yearly (default)

  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.all_inclusive_rounded,
      'title': 'profile.feature_unlimited',
      'subtitle': 'paywall.feature_unlimited_desc',
    },
    {
      'icon': Icons.bolt_rounded,
      'title': 'profile.feature_priority',
      'subtitle': 'paywall.feature_priority_desc',
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'profile.feature_templates',
      'subtitle': 'paywall.feature_templates_desc',
    },
    {
      'icon': Icons.block_rounded,
      'title': 'profile.feature_no_ads',
      'subtitle': 'paywall.feature_no_ads_desc',
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideUp = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        body: Stack(
          children: [
            // Background gradient orbs
            _buildBackgroundEffects(),

            // Main content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(bottom: bottomPadding + 120),
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _fadeIn.value,
                            child: Transform.translate(
                              offset: Offset(0, _slideUp.value),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 20 : 32,
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 8),

                              // Crown icon with glow
                              _buildPremiumBadge(isMobile),

                              const SizedBox(height: 24),

                              // Title
                              AutoSizeText(
                                'paywall.title'.tr(),
                                style: TextStyle(
                                  fontSize: isMobile ? 28 : 34,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                  height: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 10),

                              // Subtitle
                              AutoSizeText(
                                'paywall.subtitle'.tr(),
                                style: TextStyle(
                                  fontSize: isMobile ? 14 : 16,
                                  color: Colors.white.withOpacity(0.6),
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 32),

                              // Features list
                              _buildFeaturesList(isMobile),

                              const SizedBox(height: 32),

                              // Pricing plans
                              _buildPricingPlans(isMobile),

                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom CTA
            _buildBottomCTA(context, isMobile, bottomPadding),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundEffects() {
    return Stack(
      children: [
        // Top-right golden orb
        Positioned(
          top: -100,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withOpacity(0.15),
                  const Color(0xFFFFD700).withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Bottom-left cyan orb
        Positioned(
          bottom: 100,
          left: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00D4FF).withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumBadge(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.2),
            const Color(0xFFFAD94D).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.25),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFED4B), Color(0xFFFAD94D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          Icons.workspace_premium_rounded,
          size: isMobile ? 36 : 44,
          color: const Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  Widget _buildFeaturesList(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: _features.asMap().entries.map((entry) {
          final index = entry.key;
          final feature = entry.value;
          return Column(
            children: [
              _buildFeatureRow(
                icon: feature['icon'] as IconData,
                title: (feature['title'] as String).tr(),
                subtitle: (feature['subtitle'] as String).tr(),
                isMobile: isMobile,
              ),
              if (index < _features.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    color: Colors.white.withOpacity(0.06),
                    height: 1,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isMobile,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: isMobile ? 20 : 22,
            color: const Color(0xFFFFED4B),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoSizeText(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.visible,
              ),
              const SizedBox(height: 2),
              AutoSizeText(
                subtitle,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: Colors.white.withOpacity(0.5),
                ),
                maxLines: 2,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_circle_rounded,
          size: 20,
          color: const Color(0xFF00D4FF).withOpacity(0.8),
        ),
      ],
    );
  }

  Widget _buildPricingPlans(bool isMobile) {
    return Column(
      children: [
        // Yearly plan (recommended)
        _buildPlanCard(
          planIndex: 1,
          title: 'paywall.yearly_plan'.tr(),
          price: '\$29.99',
          period: 'paywall.per_year'.tr(),
          savings: 'paywall.save_50'.tr(),
          isPopular: true,
          isMobile: isMobile,
        ),

        const SizedBox(height: 12),

        // Monthly plan
        _buildPlanCard(
          planIndex: 0,
          title: 'paywall.monthly_plan'.tr(),
          price: '\$4.99',
          period: 'paywall.per_month'.tr(),
          savings: null,
          isPopular: false,
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required int planIndex,
    required String title,
    required String price,
    required String period,
    required String? savings,
    required bool isPopular,
    required bool isMobile,
  }) {
    final isSelected = _selectedPlan == planIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = planIndex;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    const Color(0xFFFFD700).withOpacity(0.12),
                    const Color(0xFFFFD700).withOpacity(0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700).withOpacity(0.5)
                : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFFD700)
                      : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFED4B)],
                          ),
                        ),
                      ),
                    )
                  : null,
            ),

            const SizedBox(width: 14),

            // Plan details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFED4B)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'paywall.best_value'.tr(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (savings != null) ...[
                    const SizedBox(height: 4),
                    AutoSizeText(
                      savings,
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF00D4FF).withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ],
              ),
            ),

            // Price
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AutoSizeText(
                    price,
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? const Color(0xFFFFED4B)
                          : Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
                  AutoSizeText(
                    period,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCTA(
    BuildContext context,
    bool isMobile,
    double bottomPadding,
  ) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          bottomPadding > 0 ? bottomPadding + 8 : 20,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF0D0D1A).withOpacity(0.0),
              const Color(0xFF0D0D1A).withOpacity(0.9),
              const Color(0xFF0D0D1A),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subscribe button
            GestureDetector(
              onTap: () {
                // 🧪 CHEAT: Check for 8 quick clicks
                // _cheatCheckProEnable();

                // Handle subscription
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('profile.upgrade_launching_soon'.tr()),
                    backgroundColor: const Color(0xFFFFD700),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFFED4B),
                      Color(0xFFFAD94D),
                    ],
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.rocket_launch_rounded,
                      size: 20,
                      color: Color(0xFF1A1A2E),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'paywall.subscribe_button'.tr(),
                        style: TextStyle(
                          color: const Color(0xFF1A1A2E),
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Terms text
            AutoSizeText(
              'paywall.terms_text'.tr(),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.4),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
