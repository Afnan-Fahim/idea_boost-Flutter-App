/// Design Tokens for IdeaBoost
///
/// This file defines consistent spacing, typography, and visual tokens
/// used across the app to ensure UI consistency across all screens and locales.
///
/// Usage in widgets:
/// ```dart
/// Padding(
///   padding: AppSpacing.md,
///   child: Text(
///     'Hello',
///     style: AppTypography.bodyRegular,
///   ),
/// )
/// ```

import 'package:flutter/material.dart';

/// Consistent spacing scale used throughout the app
/// This ensures uniform padding and margins across all screens
abstract class AppSpacing {
  // Micro spacing
  static const double xs = 4.0; // Extra small gaps between tight elements
  static const double sm = 8.0; // Small gaps between related elements

  // Standard spacing
  static const double md = 16.0; // Standard padding/margin for most elements
  static const double lg = 24.0; // Large spacing between sections

  // Large spacing
  static const double xl = 32.0; // Extra large gaps between major sections
  static const double xxl = 48.0; // Maximum spacing for hero sections

  // Common EdgeInsets combinations
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);

  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(
    horizontal: md,
  );
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(
    vertical: md,
  );
  static const EdgeInsets paddingSymmetricMd = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );

  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(
    horizontal: lg,
  );
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(
    vertical: lg,
  );
  static const EdgeInsets paddingSymmetricLg = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

/// Typography scale for consistent text styling across locales
/// Uses AutoSizeText-friendly font sizes and weights
abstract class AppTypography {
  // Display/Hero text
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
  );

  // Heading styles
  static const TextStyle headingLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.33,
  );

  // Body text - primary content
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  static const TextStyle bodyRegular = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.2,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0.1,
  );

  // Labels and captions
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.43,
    letterSpacing: 0.3,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static const TextStyle captionSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.27,
    color: Colors.grey,
  );

  // Button text
  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.3,
  );
}

/// Border radius scale for consistency
abstract class AppBorders {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double circle = 50.0; // Used for CircleAvatar-like shapes

  // BorderRadius objects
  static final BorderRadius radiusSm = BorderRadius.circular(sm);
  static final BorderRadius radiusMd = BorderRadius.circular(md);
  static final BorderRadius radiusLg = BorderRadius.circular(lg);
  static final BorderRadius radiusXl = BorderRadius.circular(xl);
}

/// Component sizing standards
abstract class AppComponentSize {
  // Button heights - ensure text fits with translations
  static const double buttonHeightLarge = 56;
  static const double buttonHeightMedium = 48;
  static const double buttonHeightSmall = 40;
  static const double buttonHeightMinimum = 36;

  // Input field heights
  static const double textFieldHeight = 56;
  static const double textFieldHeightSmall = 48;

  // Icon sizes
  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // Card heights and widths (minimum)
  static const double cardMinHeight = 80;
  static const double chipHeight = 32;
}

/// Shadows for depth and elevation
abstract class AppShadows {
  static const List<BoxShadow> shadowSmall = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowLarge = [
    BoxShadow(color: Color(0x24000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> shadowExtraLarge = [
    BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// Animation durations for consistent motion
abstract class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration extraSlow = Duration(milliseconds: 800);
}

/// Opacity values for consistent transparency
abstract class AppOpacity {
  static const double disabled = 0.5;
  static const double hover = 0.8;
  static const double focus = 0.9;
  static const double active = 1.0;
  static const double subtle = 0.12;
  static const double divider = 0.12;
}
