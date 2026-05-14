// lib/core/widgets/skeleton_card_list.dart
//
// Drop-in glassmorphic skeleton loader that exactly mirrors the
// favorites / history card structure:
//   Row( icon_box | badge_label | delete_box )
//   title line 1
//   title line 2
//   preview block
//   date line
//
// Also provides [EmptyStateWidget] and [ErrorStateWidget]
// so both screens can remove their inline states.
//
// Performance notes
// ─────────────────
// • Single [AnimationController] drives ALL shimmer boxes via one
//   [AnimatedBuilder] — no per-box controllers, no rebuild storms.
// • Shimmer is a [LinearGradient] sweep on a clip rect — GPU-composited,
//   zero layout cost per frame.
// • [RepaintBoundary] around each card isolates repaints.
// • Respects [MediaQuery.disableAnimations] for reduced-motion users.

import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:easy_localization/easy_localization.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton card list
// ─────────────────────────────────────────────────────────────────────────────

class SkeletonCardList extends StatefulWidget {
  /// How many placeholder cards to show.
  final int cardCount;

  const SkeletonCardList({Key? key, this.cardCount = 4}) : super(key: key);

  @override
  State<SkeletonCardList> createState() => _SkeletonCardListState();
}

class _SkeletonCardListState extends State<SkeletonCardList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(
      begin: -1.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect system reduce-motion preference
    if (!MediaQuery.of(context).disableAnimations) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: widget.cardCount,
          itemBuilder: (_, i) => RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SkeletonCard(
                shimmerOffset: _anim.value,
                // Stagger opacity so cards fade in depth
                opacity: 1.0 - (i * 0.12).clamp(0.0, 0.45),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single skeleton card — mirrors real card layout precisely
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonCard extends StatelessWidget {
  final double shimmerOffset;
  final double opacity;

  const _SkeletonCard({required this.shimmerOffset, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          // Glassmorphic card: strong frosted surface
          color: const Color(0xFF1E2A3A).withOpacity(0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
          // Subtle inner glow — no external shadow to keep GPU load low
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4FF).withOpacity(0.04),
              blurRadius: 20,
              spreadRadius: -4,
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row: icon | badge text | delete ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon box
                _Bone(
                  shimmerOffset: shimmerOffset,
                  width: 22,
                  height: 22,
                  radius: 6,
                ),
                const SizedBox(width: 8),
                // Badge label — takes all available space
                Expanded(
                  child: _Bone(
                    shimmerOffset: shimmerOffset,
                    height: 22,
                    radius: 8,
                    // Vary widths across cards via parent opacity proxy
                    widthFraction: opacity > 0.85 ? 0.7 : 0.55,
                  ),
                ),
                const SizedBox(width: 8),
                // Delete button placeholder
                _Bone(
                  shimmerOffset: shimmerOffset,
                  width: 34,
                  height: 34,
                  radius: 8,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Title line 1 ────────────────────────────────────────────────
            _Bone(
              shimmerOffset: shimmerOffset,
              height: 14,
              radius: 6,
              widthFraction: opacity > 0.85 ? 0.88 : 0.78,
            ),
            const SizedBox(height: 7),
            // Title line 2
            _Bone(
              shimmerOffset: shimmerOffset,
              height: 14,
              radius: 6,
              widthFraction: opacity > 0.85 ? 0.60 : 0.50,
            ),

            const SizedBox(height: 12),

            // ── Content preview block ───────────────────────────────────────
            _Bone(
              shimmerOffset: shimmerOffset,
              height: 58,
              radius: 10,
              widthFraction: 1.0,
            ),

            const SizedBox(height: 12),

            // ── Date line ───────────────────────────────────────────────────
            _Bone(
              shimmerOffset: shimmerOffset,
              height: 11,
              radius: 5,
              widthFraction: 0.28,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bone (single shimmer rectangle)
// ─────────────────────────────────────────────────────────────────────────────

class _Bone extends StatelessWidget {
  final double shimmerOffset;
  final double? width;
  final double height;
  final double radius;

  /// Fraction of available width (0–1). Ignored when [width] is set.
  final double widthFraction;

  const _Bone({
    required this.shimmerOffset,
    required this.height,
    required this.radius,
    this.width,
    this.widthFraction = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(shimmerOffset - 0.8, 0),
            end: Alignment(shimmerOffset + 0.8, 0),
            colors: const [
              Color(0x12FFFFFF), // 7% white
              Color(0x22FFFFFF), // 13% white — highlight pass
              Color(0x12FFFFFF), // 7% white
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          color: const Color(0x1AFFFFFF), // base 10% white fill
        ),
      ),
    );

    if (width != null) return child;

    return FractionallySizedBox(
      widthFactor: widthFraction,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyStateWidget({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white.withOpacity(0.18)),
            const SizedBox(height: 18),
            AutoSizeText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              maxLines: 3,
              minFontSize: 14,
            ),
            const SizedBox(height: 8),
            AutoSizeText(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 14,
                height: 1.5,
              ),
              maxLines: 4,
              minFontSize: 12,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error / retry state
// ─────────────────────────────────────────────────────────────────────────────

class ErrorStateWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorStateWidget({
    Key? key,
    required this.message,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withOpacity(0.22),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 26,
                color: Colors.red.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 18),
            AutoSizeText(
              'errors.could_not_load_data'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              minFontSize: 14,
            ),
            const SizedBox(height: 6),
            AutoSizeText(
              message.isNotEmpty
                  ? message
                  : 'errors.something_went_wrong_try_again'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
                height: 1.5,
              ),
              maxLines: 4,
              minFontSize: 11,
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00D4FF).withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: const Color(0xFF00D4FF).withOpacity(0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'general.try_again'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF00D4FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
