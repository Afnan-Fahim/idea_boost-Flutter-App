import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../main.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _pulseController;

  final List<OnboardingData> _onboardingData = [
    OnboardingData(
      title: "Generate Viral Ideas",
      subtitle: "Discover hundreds of trending content ideas tailored for your niche — powered by cutting-edge AI technology.",
      badge: "AI-Powered",
      icon: Icons.lightbulb,
      color: const Color(0xFFFFB300), // Amber/Yellow
    ),
    OnboardingData(
      title: "Scripts & Comments",
      subtitle: "Write full video scripts and engaging comments in seconds — available in English, Russian, and Uzbek.",
      badge: "3 Languages",
      icon: Icons.auto_awesome,
      color: const Color(0xFF6366F1), // Indigo/Purple
    ),
    OnboardingData(
      title: "Grow Your Audience",
      subtitle: "Viral rewrites, hashtag generators, shot ideas — every tool you need to grow your audience, in one place.",
      badge: "All-in-One",
      icon: Icons.rocket_launch,
      color: const Color(0xFF10B981), // Emerald/Green
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeData = _onboardingData[_currentPage];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: Stack(
        children: [
          // Dynamic Background Glow
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Positioned(
                top: size.height * 0.1,
                left: -size.width * 0.2,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 1000),
                    width: size.width * 1.2,
                    height: size.width * 1.2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeData.color.withOpacity(0.08 + (_pulseController.value * 0.04)),
                    ),
                  ),
                ),
              );
            },
          ),

          SafeArea(
            child: Stack(
              children: [
                // Top Bar
                _AnimatedFadeIn(
                  delay: 200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${_currentPage + 1} of ${_onboardingData.length}",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton(
                          onPressed: _completeOnboarding,
                          child: const Text(
                            "Skip",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Content
                PageView.builder(
                  controller: _pageController,
                  itemCount: _onboardingData.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final data = _onboardingData[index];
                    return _OnboardingContent(
                      data: data,
                      pulseAnimation: _pulseController,
                      isActive: _currentPage == index,
                    );
                  },
                ),

                // Bottom Controls
                Positioned(
                  bottom: 40,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      // Indicators
                      _AnimatedFadeIn(
                        delay: 600,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _onboardingData.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 4,
                              width: _currentPage == index ? 24 : 8,
                              decoration: BoxDecoration(
                                color: _currentPage == index
                                    ? activeData.color
                                    : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Animated Glowing Button
                      _AnimatedFadeIn(
                        delay: 800,
                        child: _GlowingActionButton(
                          color: activeData.color,
                          text: _currentPage == _onboardingData.length - 1
                              ? "Get Started 🚀"
                              : "Next",
                          pulseAnimation: _pulseController,
                          onPressed: () {
                            if (_currentPage < _onboardingData.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOutQuart,
                              );
                            } else {
                              _completeOnboarding();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  final OnboardingData data;
  final Animation<double> pulseAnimation;
  final bool isActive;

  const _OnboardingContent({
    required this.data,
    required this.pulseAnimation,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated Pulse Icon
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (pulseAnimation.value * 0.02),
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.color,
                    boxShadow: [
                      BoxShadow(
                        color: data.color.withOpacity(0.2 * (1 - pulseAnimation.value)),
                        blurRadius: 60 * pulseAnimation.value,
                        spreadRadius: 20 * pulseAnimation.value,
                      ),
                      BoxShadow(
                        color: data.color.withOpacity(0.3),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    data.icon,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 56),

          // Badge
          _AnimatedFadeIn(
            delay: 300,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: data.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: data.color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                data.badge.toUpperCase(),
                style: TextStyle(
                  color: data.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          _AnimatedFadeIn(
            delay: 400,
            child: Text(
              data.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Subtitle
          _AnimatedFadeIn(
            delay: 500,
            child: Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
                height: 1.6,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 120), // Space for bottom controls
        ],
      ),
    );
  }
}

class _GlowingActionButton extends StatefulWidget {
  final Color color;
  final String text;
  final Animation<double> pulseAnimation;
  final VoidCallback onPressed;

  const _GlowingActionButton({
    required this.color,
    required this.text,
    required this.pulseAnimation,
    required this.onPressed,
  });

  @override
  State<_GlowingActionButton> createState() => _GlowingActionButtonState();
}

class _GlowingActionButtonState extends State<_GlowingActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedBuilder(
          animation: widget.pulseAnimation,
          builder: (context, child) {
            return Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  // Outer Pulsing Glow
                  BoxShadow(
                    color: widget.color.withOpacity(0.3 * widget.pulseAnimation.value),
                    blurRadius: 25 * widget.pulseAnimation.value,
                    spreadRadius: 5 * widget.pulseAnimation.value,
                    offset: const Offset(0, 4),
                  ),
                  // Solid shadow for depth
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.text.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedFadeIn extends StatelessWidget {
  final Widget child;
  final int delay;

  const _AnimatedFadeIn({required this.child, required this.delay});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class OnboardingData {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color color;

  OnboardingData({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.color,
  });
}
