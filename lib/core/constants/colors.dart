import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color lightGrey = Color(0xFFE0E0E0);

  static const Color backgroundTop = Color(0xFF0A0A0F);
  static const Color backgroundBottom = Color(0xFF000000);
  static const Color surface = Color(0xFF18181F);
  static const Color surfaceBright = Color(0xFF222229);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color accent = Color(0xFF6366F1);
  static const Color accentLight = Color(0xFF818CF8);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color deepPurple = Color(0xFF673AB7);

  // Additional colors for IdeaDetailsScreen
  static const Color cosmicTop = Color(
    0xFF1E1B4B,
  ); // Dark purple-blue for gradient top
  static const Color cosmicBottom = Color(
    0xFF0F0A1A,
  ); // Darker purple for gradient bottom
  static const Color amberGlow = Color(0xFFFFD700); // Bright amber for buttons
  static const Color goldPro = Color(0xFFFFD700); // Gold for pro elements
  static const Color glassBg = Color(
    0xFFFFFFFF,
  ); // White for glass effect backgrounds

  // Primary
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF818CF8);

  // Background & Surface
  static const Color background = Color(0xFF0F172A);

  // Text
  static const Color textMuted = Color(0xFF94A3B8);

  // Semantic
  static const Color info = Color(0xFF3B82F6);

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Type specific colors
  static const Color ideaColor = Color(0xFF6366F1);
  static const Color scriptColor = Color(0xFFEC4899);
  static const Color commentColor = Color(0xFF06B6D4);
  static const Color aiRefinedColor = Color(0xFFF59E0B);

  // ─── Refined Type Colors (Professional, Brand-Aligned) ───
  // Primary type — aligns with brand indigo
  static const Color typeIdeaDetails = Color(0xFF6366F1); // Indigo

  // Comment & Social
  static const Color typeComment = Color(0xFF0891B2); // Soft Cyan

  // Script & Viral — warm rose accent
  static const Color typeScript = Color(0xFFEC4899); // Rose
  static const Color typeViral = Color(0xFFEC4899); // Rose

  // AI Refined — warm professional amber
  static const Color typeAiRefined = Color(0xFFD97706); // Amber
  static const Color typeAiRefinedYouth = Color(0xFF14B8A6); // Teal
  static const Color typeAiRefinedSeasonal = Color(0xFFF43F5E); // Rose

  // Creative types
  static const Color typeYouthIdeas = Color(0xFF14B8A6); // Teal
  static const Color typeSeasonalIdeas = Color(0xFFF43F5E); // Rose
  static const Color typeHashtag = Color(0xFFA78BFA); // Purple
  static const Color typeShotIdeas = Color(0xFF06B6D4); // Cyan
}
