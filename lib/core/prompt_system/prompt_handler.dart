/// lib/core/prompt_system/prompt_handler.dart
///
/// Central Prompt Handler — 6-Rank priority-based prompt orchestration.
///
/// RANK HIERARCHY (assembled top → bottom in final prompt):
///   Rank 1: LANGUAGE          — Content language enforcement
///   Rank 2: PLATFORM IDENTITY — Reels / TikTok / Shorts
///   Rank 3: TONE STRENGTH     — Tone guidance & style
///   Rank 4: LOCALE BEHAVIOR   — Regional / cultural context
///   Rank 5: RELEVANCE         — Goal, length, domain, audience
///   Rank 6: JSON FORMATTING   — Unified strict JSON instructions
///
/// ARCHITECTURE:
/// ViewModels → PromptRequest → PromptHandler → PromptContext → PromptBuilder → PromptResult → AiRepository

import 'package:flutter/foundation.dart';
import 'prompt_template.dart';
import 'models/prompt_request.dart';
import 'models/prompt_context.dart';
import 'models/prompt_result.dart';
import 'validators/json_validator.dart';

class PromptHandler {
  /// Singleton instance
  static final PromptHandler _instance = PromptHandler._internal();

  factory PromptHandler() {
    return _instance;
  }

  PromptHandler._internal();

  /// The JSON validator for Rank 6 (JSON formatting & constraints)
  final JsonValidator _jsonValidator = JsonValidator();

  /// Safe cast to String - handles Map, List, String, or other types
  String? _safeStringCast(dynamic value) {
    if (value is String) return value;
    if (value is Map) return value.toString();
    if (value is List) return value.join(', ');
    if (value == null) return null;
    return value.toString();
  }

  /// ============ MAIN FLOW ============
  ///
  /// Process a prompt request from ViewModel through the 6-rank priority system.
  /// This is the main entry point for all generators.
  ///
  /// Flow:
  /// 1. Receive PromptRequest from ViewModel
  /// 2. Build PromptContext with all 6 ranks applied
  /// 3. Use PromptBuilder to assemble final prompt
  /// 4. Validate against JSON constraints (Rank 6)
  /// 5. Return PromptResult ready for AiRepository

  Future<PromptResult> handlePromptRequest({
    required String language,
    required String userPrompt,
    required PromptRequest request,
    required String locale,
    String? generatorType,
  }) async {
    try {
      debugPrint(
        '╔════════════════════════════════════════════════════════════════╗',
      );
      debugPrint(
        '║ 🎯 PROMPT HANDLER: Processing Request                         ║',
      );
      debugPrint(
        '╚════════════════════════════════════════════════════════════════╝',
      );

      // ✅ Step 1: Build PromptContext with all 6 ranks
      final context = _buildPromptContext(
        language: language,
        userPrompt: userPrompt,
        request: request,
        locale: locale,
        generatorType: generatorType,
      );

      debugPrint(context.debugPriorities());

      // ✅ Step 2: Select appropriate template based on generator type
      final template = _selectTemplate(generatorType);
      debugPrint(
        '📍 PromptHandler: Selected template: ${template.templateName}',
      );

      // ✅ Step 3: Build final prompt using PromptBuilder
      final promptBuilder = PromptBuilder();
      final finalPrompt = promptBuilder.buildPrompt(context, template, generatorType: generatorType);

      debugPrint('''
╔════════════════════════════════════════════════════════════════╗
║                  📝 FINAL ASSEMBLED PROMPT                    ║
╠════════════════════════════════════════════════════════════════╣
$finalPrompt
╚════════════════════════════════════════════════════════════════╝
''');

      // ✅ Step 4: Validate against JSON constraints (Rank 6)
      final validationResult = _validatePrompt(
        finalPrompt,
        context.jsonConstraints,
      );

      // ✅ Step 5: Create and return PromptResult
      final result = PromptResult(
        finalPrompt: finalPrompt,
        appliedContext: _contextToMap(context),
        isValid: validationResult['isValid'] as bool,
        validationErrors: List<String>.from(validationResult['errors'] as List),
        executionInstructions: _generateExecutionInstructions(
          context,
          generatorType,
        ),
      );

      debugPrint(result.toString());

      return result;
    } catch (e, stack) {
      debugPrint('❌ PromptHandler ERROR: $e');
      debugPrint('Stack: $stack');
      return PromptResult(
        finalPrompt: userPrompt,
        appliedContext: {'error': e.toString()},
        isValid: false,
        validationErrors: [e.toString()],
      );
    }
  }

  /// ============ STEP 1: Build PromptContext with ALL 6 RANKS ============

  PromptContext _buildPromptContext({
    required String language,
    required String userPrompt,
    required PromptRequest request,
    required String locale,
    String? generatorType,
  }) {
    // Detect RTL languages
    final isRtl = _isRtlLanguage(language);

    // Determine cultural context from locale
    final culturalContext = _determineCulturalContext(locale, language);

    // Build the context with all 6 ranks applied
    return PromptContext(
      // [Rank 1: LANGUAGE — Foundation]
      language: language,

      // [Rank 2: PLATFORM IDENTITY]
      platform: request.platform,

      // [Rank 3: TONE STRENGTH]
      tone: request.tone,
      parameters: request.parameters,

      // [Rank 4: LOCALE BEHAVIOR]
      locale: locale,
      isRtl: isRtl,
      culturalContext: culturalContext,

      // [Rank 5: RELEVANCE]
      userPrompt: userPrompt,
      conversationHistory: request.conversationHistory,
      domain: _extractDomain(generatorType),
      audienceType: _safeStringCast(request.parameters?['audienceType']),

      // [Rank 6: JSON FORMATTING & CONSTRAINTS]
      jsonStructure: request.jsonStructure,
      jsonConstraints: request.jsonStructure,
      enforceStrictJson: request.jsonStructure != null,

      // Backend fields
      rewardGrantToken: request.rewardGrantToken,
      quality: request.quality ?? 'nano',
    );
  }

  /// ============ STEP 2: Select Template Based on Generator Type ============

  PromptTemplate _selectTemplate(String? generatorType) {
    switch (generatorType?.toLowerCase()) {
      case 'script':
        return ScriptGeneratorTemplate();
      case 'comment':
        return CommentGeneratorTemplate();
      case 'hashtag':
        return HashtagGeneratorTemplate();
      case 'viral_rewrite':
        return ViralRewriteTemplate();
      case 'shot_ideas':
        return ShotIdeasTemplate();
      case 'refinement':
        return RefinementTemplate();
      default:
        return DefaultPromptTemplate();
    }
  }

  /// ============ STEP 3: Validate Prompt Against JSON Constraints ============

  Map<String, dynamic> _validatePrompt(
    String prompt,
    Map<String, dynamic>? constraints,
  ) {
    final errors = <String>[];
    bool isValid = true;

    if (constraints == null || constraints.isEmpty) {
      return {'isValid': true, 'errors': errors};
    }

    // Validate against constraints
    isValid = _jsonValidator.validatePrompt(prompt, constraints, errors);

    return {'isValid': isValid, 'errors': errors};
  }

  /// ============ HELPER METHODS ============

  bool _isRtlLanguage(String language) {
    // Common RTL languages: Arabic, Hebrew, Farsi, Urdu
    return ['ar', 'he', 'fa', 'ur'].contains(language.toLowerCase());
  }

  /// Extract country code from locale string
  /// Examples:
  ///   "en-PK" → "PK"
  ///   "ar-SA" → "SA"
  ///   "es-MX" → "MX"
  ///   "en" → "en" (fallback to full locale if no country code)
  String _extractCountryCode(String locale) {
    if (locale.contains('-')) {
      final parts = locale.split('-');
      if (parts.length >= 2) {
        return parts[1].toUpperCase();
      }
    }
    // Fallback: return full locale if no country code found
    return locale.toUpperCase();
  }

  /// PATTERN FROM BACKEND (executed in executeAi.js):
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// The LANGUAGE parameter is the authoritative source for:
  ///   • What language to generate content in
  ///   • What language-specific tone/voice to use
  ///   • Examples: "en", "ru", "hi", "ar", etc.
  ///
  /// The LOCALE parameter is the full OS locale and is used for:
  ///   • EXTRACT country code ONLY for cultural tone adaptation
  ///   • Respecting cultural context (e.g., "en-PK" → extract "PK" for Pakistan cultural tone)
  ///   • Examples: "en-US", "en-PK", "ru-RU", "ar-SA", etc.
  ///
  /// KEY INSIGHT: Language vs Cultural Tone
  ///   Device locale: en-PK  (English from Pakistan)
  ///   App language:  en     (English)
  ///   → Generate in English (from language param)
  ///   → Apply Pakistan's cultural tone/etiquette (extracted from locale)
  ///
  /// CHANGE (Apr 2026): We now extract ONLY country code ("PK") from locale,
  /// not the full locale format, allowing country-neutral cultural adaptation.
  String _determineCulturalContext(String locale, String language) {
    // Extract country code from locale (e.g., "en-PK" → "PK")
    final countryCode = _extractCountryCode(locale);
    debugPrint(
      '🌍 Cultural Context: locale="$locale" → countryCode="$countryCode"',
    );
    return countryCode;
  }

  String _extractDomain(String? generatorType) {
    switch (generatorType?.toLowerCase()) {
      case 'script':
        return 'video_content';
      case 'comment':
        return 'social_engagement';
      case 'hashtag':
        return 'social_discovery';
      case 'viral_rewrite':
        return 'content_optimization';
      case 'shot_ideas':
        return 'creative_ideation';
      case 'refinement':
        return 'idea_enhancement';
      default:
        return 'general_content';
    }
  }

  Map<String, dynamic> _contextToMap(PromptContext context) {
    return {
      'language': context.language,
      'platform': context.platform,
      'tone': context.tone,
      'locale': context.locale,
      'isRtl': context.isRtl,
      'culturalContext': context.culturalContext,
      'domain': context.domain,
      'quality': context.quality,
    };
  }

  String _generateExecutionInstructions(
    PromptContext context,
    String? generatorType,
  ) {
    final instructions = <String>[];

    // Rank 1: Language
    instructions.add('Generate response in ${context.language}.');

    // Rank 2: Platform
    if (context.platform != null) {
      instructions.add('Optimize for ${context.platform} platform.');
    }

    // Rank 3: Tone
    if (context.tone != null) {
      instructions.add('Use a ${context.tone} tone.');
    }

    // Rank 4: Locale / RTL
    if (context.isRtl) {
      instructions.add('Format for RTL (right-to-left) language display.');
    }

    // Rank 5: Relevance / Audience
    if (context.audienceType != null) {
      instructions.add('Target audience: ${context.audienceType}.');
    }

    // Rank 6: JSON
    if (context.enforceStrictJson && context.jsonStructure != null) {
      instructions.add(
        'Return valid JSON with fields: ${(context.jsonStructure!.keys.toList()).join(", ")}',
      );
    }

    return instructions.join('\n');
  }

  /// Debug method to show execution flow
  void debugShowFlow(String generatorType, PromptRequest request) {
    print('''
╔════════════════════════════════════════════════════════════════╗
║                 📊 PROMPT HANDLER FLOW                         ║
╠════════════════════════════════════════════════════════════════╣
║ Generator Type: $generatorType
║ Platform: ${request.platform ?? "—"}
║ Tone: ${request.tone ?? "—"}
║ Quality: ${request.quality ?? "nano"}
║ Has Reward Token: ${request.rewardGrantToken != null}
║ Has JSON Structure: ${request.jsonStructure != null}
║ Has Parameters: ${request.parameters != null}
╚════════════════════════════════════════════════════════════════╝
''');
  }
}

/// ============ PROMPT BUILDER ============
///
/// Constructs the final prompt string using the PromptContext and Template.
/// Applies enhancements in strict 6-rank order.
///
/// Assembly order:
///   1. Template base prompt (generator-specific content)
///   2. Rank 2: Platform identity
///   4. Rank 3: Tone strength
///   5. Rank 4: Locale / cultural behavior
///   6. Rank 5: Relevance (domain, audience, conversation)
///   7. Rank 6: JSON formatting (single source of truth)

class PromptBuilder {
  String buildPrompt(PromptContext context, PromptTemplate template, {String? generatorType}) {
    debugPrint(
      '📝 PromptBuilder: Assembling prompt with ${template.runtimeType}',
    );

    // ── Base prompt from the template (generator-specific logic) ──
    String prompt = template.buildBasePrompt(context);

    // ── Rank 2: Platform identity ──
    prompt = _addRank2PlatformEnhancements(prompt, context);

    // ── Rank 3: Tone strength ──
    prompt = _addRank3ToneEnhancements(prompt, context);

    // ── Rank 4: Locale / cultural behavior ──
    prompt = _addRank4LocaleEnhancements(prompt, context);

    // ── Rank 5: Relevance (audience only) ──
    prompt = _addRank5RelevanceEnhancements(prompt, context);

    // ── Rank 6: JSON formatting (single source of truth) ──
    prompt = _addRank6JsonEnhancements(prompt, context, generatorType);

    // ── Rank 1: Language enforcement (LAST = strongest due to recency bias) ──
    prompt = _addRank1LanguageEnforcement(prompt, context);

    debugPrint('✅ PromptBuilder: Final prompt assembled (${prompt.length} chars) for ${template.templateName}');

    return prompt;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANK 1: LANGUAGE ENFORCEMENT (appended LAST for maximum recency bias)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Appended ONCE at the very end of the prompt — after JSON rules —
  /// so the LLM sees "RESPOND IN X LANGUAGE" as the final instruction.
  String _addRank1LanguageEnforcement(String prompt, PromptContext context) {
    return prompt + _getLanguageEnforcementInstruction(context.language);
  }

  /// Per-language enforcement instructions. Each block uses the target language
  /// itself so the LLM is already "thinking" in that language when it starts.
  String _getLanguageEnforcementInstruction(String language) {
    switch (language) {
      case 'hi':
        return '\n\n🔒 LANGUAGE: HINGLISH ONLY\n'
            '⚠️ Yeh MANDATORY hai — koi compromise nahi!\n'
            'Saara output sirf Hinglish mein hona chahiye (Hindi-English mix jaise log bolte hain).\n'
            '- Pure English sentences BILKUL mat likho\n'
            '- Natural Hinglish use karo jaise: "viral content banao", "engagement badhao"\n'
            '⛔ Pure English sentence likhna = COMPLETE FAILURE.';
      case 'ar':
        return '\n\n🔒 اللغة: العربية فقط\n'
            '⚠️ هذا إجباري — بدون مساومة!\n'
            'جميع المخرجات يجب أن تكون باللغة العربية فقط.\n'
            '⛔ حتى كلمة واحدة بالإنجليزية = فشل كامل.';
      case 'ru':
        return '\n\n🔒 ЯЗЫК: ТОЛЬКО РУССКИЙ\n'
            '⚠️ Это обязательно — без компромиссов!\n'
            'Вся информация должна быть только на русском языке.\n'
            '⛔ ДАЖЕ ОДНО английское слово = ПОЛНЫЙ ОТКАЗ.';
      case 'fr':
        return '\n\n🔒 LANGUE: FRANÇAIS UNIQUEMENT\n'
            '⚠️ C\'est obligatoire — pas de compromis!\n'
            'Tout doit être en français uniquement.\n'
            '⛔ MÊME UN SEUL mot anglais = ÉCHEC COMPLET.';
      case 'es':
        return '\n\n🔒 IDIOMA: SOLO ESPAÑOL\n'
            '⚠️ ¡Esto es obligatorio — sin compromisos!\n'
            '¡Todo debe estar en español únicamente!\n'
            '⛔ ¡INCLUSO UNA palabra en inglés = FRACASO TOTAL!';
      case 'de':
        return '\n\n🔒 SPRACHE: NUR DEUTSCH\n'
            '⚠️ Das ist obligatorisch — kein Kompromiss!\n'
            'Alles muss ausschließlich auf Deutsch sein.\n'
            '⛔ AUCH NUR EIN englisches Wort = VÖLLIGER FEHLER.';
      case 'pt':
        return '\n\n🔒 IDIOMA: APENAS PORTUGUÊS\n'
            '⚠️ Isto é obrigatório — sem compromissos!\n'
            'Tudo deve estar em português apenas.\n'
            '⛔ MESMO UMA PALAVRA em inglês = FALHA COMPLETA.';
      case 'id':
        return '\n\n🔒 BAHASA: HANYA BAHASA INDONESIA\n'
            '⚠️ Ini wajib — tanpa kompromi!\n'
            'Semuanya harus dalam bahasa Indonesia saja.\n'
            '⛔ BAHKAN SATU kata Inggris = KEGAGALAN TOTAL.';
      case 'vi':
        return '\n\n🔒 NGÔN NGỮ: CHỈ TIẾNG VIỆT\n'
            '⚠️ Đây là bắt buộc — không thương lượng!\n'
            'Tất cả phải bằng tiếng Việt.\n'
            '⛔ NGAY CẢ MỘT từ tiếng Anh = THẤT BẠI HOÀN TOÀN.';
      case 'uz':
        return '\n\n🔒 TIL: FAQAT O\'ZBEK TILIDA\n'
            '⚠️ Bu majburiy — kompromiss yo\'q!\n'
            'Hamasi faqat o\'zbek tilida bo\'lishi kerak.\n'
            '⛔ HECH BIR Ingliz so\'zi = TO\'LIQ MUVAFFAQIYATSIZLIK.';
      case 'ms':
        return '\n\n🔒 BAHASA: HANYA BAHASA MELAYU\n'
            '⚠️ Ini wajib — tanpa kompromi!\n'
            'Semuanya mesti dalam bahasa Melayu sahaja.\n'
            '⛔ WALAUPUN SATU perkataan Inggeris = KEGAGALAN TOTAL.';
      default: // 'en'
        return '\n\n🔒 LANGUAGE: ENGLISH ONLY\n'
            '⚠️ This is mandatory — no compromises!\n'
            'Everything MUST be in English ONLY.\n'
            '⛔ EVEN ONE non-English word = COMPLETE FAILURE.';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANK 2: PLATFORM IDENTITY
  // ═══════════════════════════════════════════════════════════════════════════
  String _addRank2PlatformEnhancements(String prompt, PromptContext context) {
    if (context.platform != null) {
      prompt +=
          '\n\n📱 Platform: Optimize specifically for ${context.platform}.';
    }
    return prompt;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANK 3: TONE STRENGTH
  // ═══════════════════════════════════════════════════════════════════════════
  String _addRank3ToneEnhancements(String prompt, PromptContext context) {
    if (context.tone != null) {
      prompt += '\n🎭 Tone: Use a ${context.tone} tone throughout.';
    }
    return prompt;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANK 4: LOCALE BEHAVIOR
  // ═══════════════════════════════════════════════════════════════════════════
  String _addRank4LocaleEnhancements(String prompt, PromptContext context) {
    // [Rank 4: LOCALE BEHAVIOR — Cultural & Tonal Adaptation]
    // Extract country code from locale for cultural adaptation
    // Language enforcement is handled by Rank 1 (separate concern)
    final locale = context.locale;
    final language = context.language;

    if (locale != null) {
      // Extract country code from locale (e.g., "en-PK" → "PK")
      final countryCode = _extractCountryCode(locale);
      final instruction = _getCulturalInstruction(countryCode, language);
      if (instruction.isNotEmpty) {
        prompt += instruction;
      }
    }

    // Add RTL guidance if needed
    if (context.isRtl) {
      prompt +=
          '\n⚠️ RTL Language: Use appropriate RTL formatting and conventions.';
    }

    return prompt;
  }

  String _getCulturalInstruction(String countryCode, String language) {
    final code = countryCode.toUpperCase();

    // ─────────────────────────────────────────────────────────
    // COUNTRY + LANGUAGE ADAPTIVE INSTRUCTIONS (Rank 4 Enhanced)
    // ─────────────────────────────────────────────────────────
    final countryCodeInstructions = <String, String>{
      'US':
          '\nLANGUAGE: English — Respond ONLY in English.\n'
          'TONE: Confident, direct, and results-oriented. Get to the point fast. '
          'Use active voice. Avoid fluff and corporate jargon.',

      'GB':
          '\nLANGUAGE: English (UK) — Respond ONLY in British English.\n'
          'TONE: Precise, measured, and understated. Use British spelling. '
          'Dry wit is acceptable. Let substance speak — avoid exaggeration.',

      'AU':
          '\nLANGUAGE: English — Respond ONLY in English.\n'
          'TONE: Direct, practical, and no-nonsense. Friendly but not over-eager. '
          'Be grounded and genuine.',

      // 🔥 Hinglish override (IMPORTANT)
      'IN':
          '\nLANGUAGE: Hinglish — Use a natural mix of Hindi + English.\n'
          'TONE: Warm, relatable, and respectful. Use "aap". '
          'Sound like a real Indian conversation — not formal, not slangy. '
          'Keep it natural and clear.',

      'PK':
          '\nLANGUAGE: Hinglish — Use a natural mix of Urdu + English.\n'
          'TONE: Respectful and slightly formal. Use "aap". '
          'Maintain dignity and structure, but keep it human and relatable.',

      'NG':
          '\nLANGUAGE: English — Respond ONLY in English.\n'
          'TONE: Confident, energetic, and respectful. Professional yet vibrant.',

      'ZA':
          '\nLANGUAGE: English — Respond ONLY in English.\n'
          'TONE: Inclusive, respectful, and clear. Avoid assumptions.',

      'RU':
          '\nЯЗЫК: Русский — Отвечай ТОЛЬКО на русском языке.\n'
          'ТОН: Чёткий, структурированный и профессиональный. Без лишней вежливости. '
          'Логика и точность = уважение.',

      'UZ':
          '\nTIL: O‘zbek — Faqat o‘zbek tilida yoz.\n'
          'OHANG: Samimiy, hurmatli va sodda. "Siz" bilan murojaat qil.',

      'ES':
          '\nIDIOMA: Español — Responde SOLO en español.\n'
          'TONO: Directo, sofisticado y claro.',

      'MX':
          '\nIDIOMA: Español — Responde SOLO en español.\n'
          'TONO: Cálido, respetuoso y accesible.',

      'AR':
          '\nIDIOMA: Español — Responde SOLO en español.\n'
          'TONO: Directo, apasionado y auténtico.',

      'CO':
          '\nIDIOMA: Español — Responde SOLO en español.\n'
          'TONO: Muy cortés, cálido y profesional.',

      'BR':
          '\nIDIOMA: Português (Brasil) — Responda SOMENTE em português.\n'
          'TOM: Caloroso, próximo e natural.',

      'PT':
          '\nIDIOMA: Português (Portugal) — Responda SOMENTE em português.\n'
          'TOM: Formal, preciso e estruturado.',

      'FR':
          '\nLANGUE: Français — Répondre UNIQUEMENT en français.\n'
          'TON: Nuancé, intellectuel et précis.',

      'CA':
          '\nLANGUAGE: English/French — Respond in the user’s language.\n'
          'TONE: Warm, clear, and accessible.',

      'SA':
          '\nاللغة: العربية — أجب فقط بالعربية.\n'
          'الأسلوب: رسمي جداً ومحترم.',

      'EG':
          '\nاللغة: العربية — أجب فقط بالعربية.\n'
          'الأسلوب: رسمي مع مرونة ودفء.',

      'AE':
          '\nاللغة: العربية — أجب فقط بالعربية.\n'
          'الأسلوب: احترافي ومحترم ومتعدد الثقافات.',

      'DE':
          '\nSPRACHE: Deutsch — Antworte NUR auf Deutsch.\n'
          'TON: Präzise, sachlich und direkt.',

      'AT':
          '\nSPRACHE: Deutsch — Antworte NUR auf Deutsch.\n'
          'TON: Höflich, strukturiert und etwas wärmer.',

      'CH':
          '\nSPRACHE: Deutsch — Antworte NUR auf Deutsch.\n'
          'TON: Sehr direkt, effizient und präzise.',

      'VN':
          '\nNGÔN NGỮ: Tiếng Việt — Chỉ dùng tiếng Việt.\n'
          'GIỌNG: Lịch sự, tôn trọng và phù hợp ngữ cảnh.',

      'ID':
          '\nBAHASA: Bahasa Indonesia — Gunakan hanya Bahasa Indonesia.\n'
          'NADA: Sopan, hangat dan harmonis.',

      'MY':
          '\nBAHASA: Bahasa Melayu — Gunakan hanya Bahasa Melayu.\n'
          'NADA: Sopan, mesra dan penuh hormat.',

      'BN':
          '\nBAHASA: Bahasa Melayu — Gunakan hanya Bahasa Melayu.\n'
          'NADA: Sangat sopan, profesional dan sensitif budaya.',
    };

    // ─────────────────────────────────────────────────────────
    // LOOKUP (NO CHANGE IN LOGIC)
    // ─────────────────────────────────────────────────────────
    if (countryCodeInstructions.containsKey(code)) {
      debugPrint('🌍 Rank 4 Culture [country-code]: $code');
      return countryCodeInstructions[code]!;
    } else if (countryCodeInstructions.containsKey(countryCode)) {
      debugPrint('🌍 Rank 4 Culture [fallback-full-locale]: $countryCode');
      return countryCodeInstructions[countryCode]!;
    } else {
      debugPrint('🌍 Rank 4 Culture [unmatched]: $code');
      return '\n\n📍 CULTURAL TONE ($code): Adapt tone naturally to local culture. '
          'Respect communication norms, hierarchy, and social expectations.';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  String _extractCountryCode(String locale) {
    if (locale.contains('-')) {
      final parts = locale.split('-');
      if (parts.length >= 2) return parts[1].toUpperCase();
    }
    return locale.toUpperCase();
  }

    // ═══════════════════════════════════════════════════════════════════════════
  // RANK 5: RELEVANCE
  // ═══════════════════════════════════════════════════════════════════════════
  String _addRank5RelevanceEnhancements(String prompt, PromptContext context) {
    // Domain label removed — generic strings like "social_discovery" add no signal.
    if (context.audienceType != null) {
      prompt += '\n👥 Target Audience: ${context.audienceType}';
    }
    return prompt;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANK 6: JSON FORMATTING (SINGLE SOURCE OF TRUTH)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Emits strict JSON rules + a generator-specific exact example matching
  /// what each ViewModel actually parses. Templates must NOT include JSON blocks.
  String _addRank6JsonEnhancements(
    String prompt,
    PromptContext context,
    String? generatorType,
  ) {
    if (!context.enforceStrictJson || context.jsonStructure == null) {
      return prompt;
    }

    final langName = _languageName(context.language);

    prompt += '\n\n🚨 OUTPUT: Respond with ONLY a valid JSON object.';
    prompt += '\n- First char: {   Last char: }';
    prompt += '\n- No markdown, no ``` blocks, no text before or after the JSON';
    prompt += '\n- JSON keys stay in English; ALL string VALUES must be written in $langName';
    prompt += '\n- All string values in double quotes';
    prompt += '\n- If truncated, close all open arrays/objects to keep JSON valid';
    prompt += '\n\n✅ EXACT FORMAT — copy this shape and fill with real $langName content:';
    prompt += '\n${_exactExampleForGenerator(generatorType, context.jsonStructure!, context.language)}';
    prompt += '\n\n⚠️ CRITICAL: The example above shows STRUCTURE only. Every string value you write MUST be in $langName. Do NOT copy the English example text — translate/rewrite everything into $langName.';
    prompt += '\n⚡ Your entire response = only the JSON above. Nothing else.';

    return prompt;
  }

  /// Human-readable language name used in Rank 6 to make the LLM aware.
  String _languageName(String code) {
    switch (code) {
      case 'hi': return 'Hindi/Hinglish';
      case 'ar': return 'Arabic (العربية)';
      case 'ru': return 'Russian (Русский)';
      case 'fr': return 'French (Français)';
      case 'es': return 'Spanish (Español)';
      case 'de': return 'German (Deutsch)';
      case 'pt': return 'Portuguese (Português)';
      case 'id': return 'Bahasa Indonesia';
      case 'vi': return 'Vietnamese (Tiếng Việt)';
      case 'uz': return 'Uzbek (O\'zbek)';
      case 'ms': return 'Bahasa Melayu';
      default:  return 'English';
    }
  }

  String _exactExampleForGenerator(
    String? generatorType,
    Map<String, dynamic> structure,
    String language,
  ) {
    switch (generatorType?.toLowerCase()) {
      case 'script':
        // VM: hook(String), voiceover(List<String>), shots(List<String>),
        //     cta(String), hashtags(List<String>)
        return '{\n'
            '  "hook": "Stop everything — you need to see this.",\n'
            '  "voiceover": ["Opening line that sets the scene.", "Second line building tension.", "Third line with the punchline.", "Final wrap-up line."],\n'
            '  "shots": ["Close-up of host face reacting.", "Wide shot of the environment.", "Cut to subject detail."],\n'
            '  "cta": "Follow for more content like this.",\n'
            '  "hashtags": ["#viral", "#trending", "#contentcreator"]\n'
            '}';

      case 'comment':
        // VM: commentData[tone] → List<String> of exactly 5 strings per tone
        final toneLines = structure.keys
            .map((t) =>
                '  "$t": ["Authentic $t comment 1.", "Authentic $t comment 2.", "Authentic $t comment 3.", "Authentic $t comment 4.", "Authentic $t comment 5."]')
            .join(',\n');
        return '{\n$toneLines\n}';

      case 'hashtag':
        // VM: data['hashtags'] → String (space-separated) or List<String>
        return '{\n'
            '  "hashtags": "#viral #trending #contentcreator #socialmedia #reels #fyp #explore #growth"\n'
            '}';

      case 'viral_rewrite':
        // VM: data['text'], data['emotional_hook'], data['hashtag'], data['call_to_action']
        return '{\n'
            '  "text": "Rewritten viral caption in 2-4 punchy sentences that hooks instantly.",\n'
            '  "emotional_hook": "One short hook line that triggers emotion or curiosity.",\n'
            '  "hashtag": "#viral #trending #content #reels #fyp",\n'
            '  "call_to_action": "Drop a comment — what do you think?"\n'
            '}';

      case 'shot_ideas':
        // VM: data['shot_ideas'] → List<String>, each item is one plain string
        return '{\n'
            '  "shot_ideas": [\n'
            '    "**1. Hook**: Close-up of host looking surprised. Timing: 0-3s. Shot style: soft focus.",\n'
            '    "**2. Build**: Wide shot of the setup. Timing: 3-7s. Shot style: natural light.",\n'
            '    "**3. Reveal**: Subject detail cut. Timing: 7-10s. Shot style: macro.",\n'
            '    "**4. Reaction**: Over-the-shoulder view. Timing: 10-13s. Shot style: handheld.",\n'
            '    "**5. Energy**: Fast B-roll montage. Timing: 13-16s. Shot style: dynamic cuts.",\n'
            '    "**6. Tension**: Slow zoom on key element. Timing: 16-19s. Shot style: telephoto.",\n'
            '    "**7. Contrast**: Split-screen before/after. Timing: 19-22s. Shot style: static.",\n'
            '    "**8. CTA**: Host addresses camera directly. Timing: 22-25s. Shot style: medium shot."\n'
            '  ]\n'
            '}';

      case 'refinement':
        // VM: refined_title(String), refined_description(String),
        //     refined_steps(List<String>), refined_cta(String), refined_level(String)
        return '{\n'
            '  "refined_title": "A compelling improved title that maximises curiosity.",\n'
            '  "refined_description": "An enhanced description that boosts virality and drives engagement.",\n'
            '  "refined_steps": [\n'
            '    "Step 1: Specific actionable instruction with a clear measurable outcome.",\n'
            '    "Step 2: Second step the creator can execute immediately.",\n'
            '    "Step 3: Mid-point step that builds momentum toward the goal.",\n'
            '    "Step 4: Near-completion step with a tangible result.",\n'
            '    "Step 5: Final step that delivers the payoff and closes the loop."\n'
            '  ],\n'
            '  "refined_cta": "A strong call-to-action that drives immediate engagement.",\n'
            '  "refined_level": "${_localizedRefinedLevel(language)}"\n'
            '}';

      default:
        final lines = structure.keys.map((k) => '  "$k": "value for $k"').join(',\n');
        return '{\n$lines\n}';
    }
  }

  /// Localized value for the `refined_level` JSON field in refinement example.
  String _localizedRefinedLevel(String language) {
    switch (language) {
      case 'hi': return 'Expert (AI se Enhanced)';
      case 'ar': return 'خبير (محسّن بالذكاء الاصطناعي)';
      case 'ru': return 'Эксперт (Улучшено ИИ)';
      case 'fr': return 'Expert (Amélioré par IA)';
      case 'es': return 'Experto (Mejorado por IA)';
      case 'de': return 'Experte (KI-verbessert)';
      case 'pt': return 'Especialista (Aprimorado por IA)';
      case 'id': return 'Ahli (Ditingkatkan AI)';
      case 'vi': return 'Chuyên gia (AI Nâng cấp)';
      case 'uz': return 'Ekspert (AI yaxshilangan)';
      case 'ms': return 'Pakar (Dipertingkat AI)';
      default:  return 'Expert (AI Enhanced)';
    }
  }
}
