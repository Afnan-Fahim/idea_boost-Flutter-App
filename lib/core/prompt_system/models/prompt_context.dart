/// lib/core/prompt_system/models/prompt_context.dart
///
/// Carries all contextual information for prompt generation with defined priorities.
/// This is the core data structure that flows through the prompt handler.
///
/// PRIORITY HIERARCHY (Rank 1 → 6):
///   Rank 1: LANGUAGE          — Must generate content in this language
///   Rank 2: PLATFORM IDENTITY — Reels / TikTok / Shorts
///   Rank 3: TONE STRENGTH     — Tone guidance & style parameters
///   Rank 4: LOCALE BEHAVIOR   — Regional / cultural context
///   Rank 5: RELEVANCE         — Goal, length, domain, audience
///   Rank 6: JSON FORMATTING   — Strict JSON output structure

class PromptContext {
  // ============ RANK 1: LANGUAGE (FOUNDATION) ============
  /// The language in which the prompt will be generated
  /// Required and foundational - affects all other priorities
  /// Examples: 'en', 'es', 'fr', 'ru', 'ar' (RTL), 'hi'
  final String language;

  // ============ RANK 2: PLATFORM IDENTITY ============
  /// Platform where the content will be used
  /// Examples: 'reels', 'tiktok', 'shorts'
  final String? platform;

  // ============ RANK 3: TONE STRENGTH ============
  /// Tone/style of the content
  /// Examples: 'friendly', 'humorous', 'dramatic', 'sophisticated', 'engaging_question'
  final String? tone;

  /// Additional parameters from ViewModels (includes tone-related data)
  /// Examples: {
  ///   'selectedTones': ['friendly', 'humorous'],
  ///   'selectedToneDescriptions': 'warm and approachable',
  ///   'variation': 'comedy',
  ///   'emotion': 'happy',
  /// }
  final Map<String, dynamic>? parameters;

  // ============ RANK 4: LOCALE BEHAVIOR ============
  /// Full locale tag with region for cultural adaptation
  /// Examples: 'en-US', 'en-GB', 'es-ES', 'es-MX', 'ar-SA', 'ru-RU'
  final String? locale;

  /// Whether to apply RTL-specific formatting (for Arabic, Hebrew, etc.)
  final bool isRtl;

  /// Cultural context or regional preferences
  final String? culturalContext;

  // ============ RANK 5: RELEVANCE ============
  /// User's direct input or base prompt
  /// The raw user-provided content or idea
  final String userPrompt;

  /// Domain or category for relevance (e.g., 'video_content', 'social_engagement')
  final String? domain;

  /// Audience type for targeted relevance
  /// Examples: 'youth', 'general_audience', 'professionals'
  final String? audienceType;

  /// Context about the user's content history (for relevance)
  /// Examples: previous topics, favorite styles, audience type
  final List<Map<String, dynamic>>? conversationHistory;

  // ============ RANK 6: JSON FORMATTING & CONSTRAINTS ============
  /// JSON structure requirements
  /// Defines how the response should be formatted
  final Map<String, dynamic>? jsonStructure;

  /// Strict JSON formatting rules
  /// Examples: max_tokens, response_format, array_length_limit
  final Map<String, dynamic>? jsonConstraints;

  /// Whether to enforce strict JSON validation
  final bool enforceStrictJson;

  // ============ BACKEND & SYSTEM FIELDS ============
  /// Reward token if user has claimed free reward
  final String? rewardGrantToken;

  /// Quality tier for backend routing: 'nano', 'mini', 'gpt'
  final String quality;

  /// Timestamp for auditing and logging
  final DateTime createdAt;

  // ============ CONSTRUCTOR ============
  PromptContext({
    required this.language,
    required this.userPrompt,
    this.platform,
    this.tone,
    this.parameters,
    this.jsonStructure,
    this.locale,
    this.isRtl = false,
    this.culturalContext,
    this.conversationHistory,
    this.domain,
    this.audienceType,
    this.jsonConstraints,
    this.enforceStrictJson = false,
    this.rewardGrantToken,
    this.quality = 'nano',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // ============ UTILITY METHODS ============

  /// Creates a copy with some fields replaced
  PromptContext copyWith({
    String? language,
    String? userPrompt,
    String? platform,
    String? tone,
    Map<String, dynamic>? parameters,
    Map<String, dynamic>? jsonStructure,
    String? locale,
    bool? isRtl,
    String? culturalContext,
    List<Map<String, dynamic>>? conversationHistory,
    String? domain,
    String? audienceType,
    Map<String, dynamic>? jsonConstraints,
    bool? enforceStrictJson,
    String? rewardGrantToken,
    String? quality,
  }) {
    return PromptContext(
      language: language ?? this.language,
      userPrompt: userPrompt ?? this.userPrompt,
      platform: platform ?? this.platform,
      tone: tone ?? this.tone,
      parameters: parameters ?? this.parameters,
      jsonStructure: jsonStructure ?? this.jsonStructure,
      locale: locale ?? this.locale,
      isRtl: isRtl ?? this.isRtl,
      culturalContext: culturalContext ?? this.culturalContext,
      conversationHistory: conversationHistory ?? this.conversationHistory,
      domain: domain ?? this.domain,
      audienceType: audienceType ?? this.audienceType,
      jsonConstraints: jsonConstraints ?? this.jsonConstraints,
      enforceStrictJson: enforceStrictJson ?? this.enforceStrictJson,
      rewardGrantToken: rewardGrantToken ?? this.rewardGrantToken,
      quality: quality ?? this.quality,
      createdAt: createdAt,
    );
  }

  /// Returns a debug summary of all priorities
  String debugPriorities() {
    // Extract key parameters if they exist
    final length = parameters?['length'] ?? 'not set';
    final variation = parameters?['variation'] ?? 'not set';
    final emotion = parameters?['emotion'] ?? 'not set';

    // Build remaining parameters output (excluding length, variation, emotion)
    String paramDetails = "none";
    if (parameters != null && parameters!.isNotEmpty) {
      final remaining = Map<String, dynamic>.from(parameters!)
        ..removeWhere((k, v) => ['length', 'variation', 'emotion'].contains(k));

      if (remaining.isNotEmpty) {
        final paramLines = <String>[];
        remaining.forEach((key, value) {
          final displayValue = value is List
              ? '[${(value as List).take(2).join(", ")}...]'
              : value.toString();
          final shortValue = displayValue.length > 30
              ? displayValue.substring(0, 30) + '...'
              : displayValue;
          paramLines.add('$key=$shortValue');
        });
        paramDetails = paramLines.join(', ');
      }
    }

    return '''
╔════════════════════════════════════════════════════════════════╗
║           PROMPT CONTEXT — 6-RANK PRIORITY HIERARCHY           ║
╠════════════════════════════════════════════════════════════════╣
║ [Rank 1: LANGUAGE]
║     🗣️  Language: $language
║ [Rank 2: PLATFORM IDENTITY]
║     📱 Platform: ${platform ?? "not set"}
║ [Rank 3: TONE STRENGTH]
║     🎭 Tone: ${tone ?? "not set"}
║     • Variation: $variation
║     • Emotion: $emotion
║     ⚙️  Parameters: $paramDetails
║ [Rank 4: LOCALE BEHAVIOR]
║     🌍 Locale: ${locale ?? "not set"}
║     🔄 RTL Mode: ${isRtl ? "YES" : "NO"}
║     🏛️  Cultural Context: ${culturalContext ?? "not set"}
║ [Rank 5: RELEVANCE]
║     💬 User Prompt: ${userPrompt.length > 50 ? userPrompt.substring(0, 50) + '...' : userPrompt}
║     💼 Domain: ${domain ?? "not set"}
║     • Length: $length
║ [Rank 6: JSON FORMATTING]
║     🔒 Strict JSON: ${enforceStrictJson ? "YES" : "NO"}
║     📋 JSON Structure: ${jsonStructure?.keys.join(', ') ?? "none"}
║     📐 Constraints: ${jsonConstraints?.keys.join(', ') ?? "none"}
║ [⚙️  BACKEND]
║     🎟️  Quality: $quality
║     🎁 Token: ${rewardGrantToken != null ? "PRESENT" : "NONE"}
║     ⏰ Created: $createdAt
╚════════════════════════════════════════════════════════════════╝
''';
  }

  @override
  String toString() {
    return 'PromptContext(language: $language, platform: $platform, tone: $tone)';
  }
}
