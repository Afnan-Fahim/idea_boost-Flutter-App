import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/ai_repository.dart';
import 'package:ideaboost/data/services/reward_token_manager.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

class ViralRewriteViewModel extends ChangeNotifier {
  final UserRepository _userRepository;
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final AiRepository _aiRepository = AiRepository();

  // Store reward token for AI generation
  String? _rewardGrantToken;

  ViralRewriteViewModel(this._userRepository, {String? initialRewardToken}) {
    if (initialRewardToken != null && initialRewardToken.isNotEmpty) {
      _rewardGrantToken = initialRewardToken;
      print('🎟️ ViralRewrite initialized with reward token');
    }
  }

  // ---------------- STATE ----------------
  String _input = '';
  String get input => _input;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _output;
  String? get output => _output;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isFavorited = false;
  bool get isFavorited => _isFavorited;

  String? _lastSavedItemId;
  String? get lastSavedItemId => _lastSavedItemId;

  // ---------------- TONE SELECTION ----------------
  final List<String> availableTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
  ];

  List<String> _selectedTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
  ];
  List<String> get selectedTones => _selectedTones;

  List<String> _lastGeneratedTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
  ];
  List<String> get lastGeneratedTones => _lastGeneratedTones;

  void toggleTone(String tone) {
    if (_selectedTones.contains(tone)) {
      if (_selectedTones.length > 1) {
        _selectedTones.remove(tone);
      }
    } else {
      _selectedTones.add(tone);
    }
    notifyListeners();
  }

  bool isToneSelected(String tone) => _selectedTones.contains(tone);

  void restoreLastGeneratedTones() {
    _selectedTones = List.from(_lastGeneratedTones);
    notifyListeners();
  }

  String getToneLabel(String tone) {
    switch (tone) {
      case 'friendly':
        return 'viral_rewrite.tone_friendly'.tr();
      case 'engaging_question':
        return 'viral_rewrite.tone_engaging_question'.tr();
      case 'humorous':
        return 'viral_rewrite.tone_humorous'.tr();
      case 'supportive':
        return 'viral_rewrite.tone_supportive'.tr();
      case 'thought_provoking':
        return 'viral_rewrite.tone_thought_provoking'.tr();
      default:
        return tone;
    }
  }

  // ---------------- INPUT ----------------
  void updateInput(String value) {
    _input = value.trim();
    print('📝 Input updated: "$_input"');
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    print('🧹 Error cleared');
    notifyListeners();
  }

  void clearOutput() {
    _input = '';
    _output = null;
    _errorMessage = null;
    print('🧹 Input, output, and error cleared');
    notifyListeners();
  }

  // ---------------- MAIN LOGIC ----------------
  Future<void> generateViralRewrite({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_input.isEmpty) {
      print('⚠️ No input provided, aborting generation.');
      return;
    }

    _isLoading = true;
    _output = null;
    _isFavorited = false;
    _lastSavedItemId = null;
    _errorMessage = null;
    // Store last used tones for regeneration
    _lastGeneratedTones = List.from(_selectedTones);
    notifyListeners();
    print('🟡 ViralRewrite: Started generation for input: "$_input"');
    print('🌍 ViralRewrite: language=$language, locale=$locale');

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }

      final userInput = _input;

      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print('🎟️ ViralRewrite: No token provided, attempting to retrieve...');
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ ViralRewrite: Token retrieved successfully');
            } else {
              print('⚠️ ViralRewrite: No available tokens, using quota system');
            }
          }
        } catch (e) {
          print(
            '⚠️ ViralRewrite: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // Build richer tone guidance for the prompt (improves output quality)
      final toneDescriptions = {
        'friendly': 'warm and approachable',
        'engaging_question': 'question-driven to spark curiosity',
        'humorous': 'funny and entertaining',
        'supportive': 'encouraging and motivating',
        'thought_provoking': 'thought-provoking and reflective',
      };
      final selectedToneDescriptions = _lastGeneratedTones
          .map((tone) => toneDescriptions[tone] ?? tone)
          .join(', ');

      // 3️⃣ Build prompt via PromptHandler
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: 'instagram',
        userPrompt: userInput,
        parameters: {
          'selectedTones': _lastGeneratedTones,
          'selectedToneDescriptions': selectedToneDescriptions,
        },
        jsonStructure: {
          'text': 'main viral rewritten content (2-4 punchy sentences)',
          'emotional_hook': 'a short curiosity/emotion hook line',
          'hashtag': '3-6 relevant hashtags in one line',
          'call_to_action': 'a clear CTA sentence for engagement',
        },
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: userInput,
        request: request,
        locale: locale,
        generatorType: 'viral_rewrite',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🔵 ViralRewrite: Sending request to Cloud Function generateAi...');
      print(
        '   - Passing token: ${_rewardGrantToken != null && _rewardGrantToken!.isNotEmpty ? "YES" : "NO"}',
      );

      // For PRO users: Phased model selection
      // Phase 1: Mini (0-20) — premium model first
      // Phase 2: Nano (0-80) — after mini exhausted
      final user = await _userRepository.getCurrentUser();
      late final ScriptOutputModel scriptOutput;

      if (user?.isPro == true) {
        final nanoUsed = user?.aiNanoUsedToday ?? 0;
        final miniUsed = user?.aiMiniUsedToday ?? 0;
        const miniCap = 20;
        const nanoCap = 80;

        if (miniUsed < miniCap) {
          scriptOutput = await _aiRepository.generateMini(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else if (nanoUsed < nanoCap) {
          scriptOutput = await _aiRepository.generateNano(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else {
          throw Exception('errors.daily_limit_wait'.tr());
        }
      } else {
        scriptOutput = await _aiRepository.generateNano(
          prompt: aiPrompt,
          rewardGrantToken: _rewardGrantToken,
          locale: locale,
          language: language,
        );
      }

      // ⚠️ CRITICAL FIX: Clear token IMMEDIATELY after use (regardless of trial/rewarded)
      // This ensures token is not accidentally consumed when switching between trial and rewarded access
      _rewardGrantToken = null;
      print('🔵 ViralRewrite: Token cleared after use');

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      final response = scriptOutput.script;
      _logLongText(
        '🔵 ViralRewrite: Received response (${response.length} chars)',
        response,
      );

      // 3️⃣ Robust JSON extraction
      var jsonStr = _extractJsonRobust(response);
      _logLongText('🔹 Extracted JSON', jsonStr);

      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      print('🔹 Parsed JSON successfully');

      // 4️⃣ Flexible key lookup (Gemini sometimes uses different keys)
      String? rewritten =
          (data['rewritten'] ??
                  data['text'] ??
                  data['content'] ??
                  data['viral'] ??
                  data['output'] ??
                  data['result'])
              ?.toString()
              .trim();

      if (rewritten == null ||
          rewritten.isEmpty ||
          rewritten.toLowerCase() == 'null') {
        print('⚠️ ViralRewrite: AI returned empty or invalid content field');
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Clean up any accidental markdown or quotes for the primary rewrite text
      final cleanRewritten = _cleanResponseText(rewritten);

      // Build a richer display string so the UI shows the full structured response
      final formattedOutput = _formatViralRewriteOutput(data, cleanRewritten);
      _output = formattedOutput;
      print('✅ ViralRewrite: Final output: $_output');

      // 5️⃣ Save history (non-fatal) - server timestamp used
      try {
        await _userRepository.saveHistoryEntry(
          type: 'viral_rewrite',
          prompt: userInput,
          output: {
            'rewritten_content': cleanRewritten,
            'text': _getResolvedText(data, cleanRewritten),
            'hashtag': _getResolvedHashtag(data, cleanRewritten),
            'call_to_action': _getResolvedCallToAction(data, cleanRewritten),
            'emotional_hook': _getResolvedEmotionalHook(data, cleanRewritten),
            'formatted_output': formattedOutput,
          },
          // generatedAt omitted - uses server timestamp
        );
        print('✅ History saved successfully');
      } catch (e) {
        print('⚠️ History save failed (non-fatal): $e');
      }
    } catch (e) {
      print('❌ ViralRewrite Error: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', '').isNotEmpty
          ? e.toString().replaceFirst('Exception: ', '')
          : 'errors.unexpected_error'.tr();
      _output = null;
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
        '🔵 ViralRewrite: Finished - loading=$_isLoading, outputLength=${_output?.length ?? 0}, error=$_errorMessage',
      );
    }
  }

  // ---------------- REWARD ----------------
  // Future<void> increaseLimitByAdReward() async {
  //   try {
  //     await _userRepository.grantRewardedGeneration();
  //     print('✅ Rewarded generation granted');
  //     notifyListeners();
  //   } catch (e) {
  //     _errorMessage = "${'general.failed_grant_reward'.tr()}: ${e.toString()}";
  //     print('❌ Reward grant failed: $_errorMessage');
  //     notifyListeners();
  //   }
  // }

  // ---------------- FAVORITES ----------------
  Future<SaveFavoriteResult> saveToFavorites() async {
    if (_output == null || _input.isEmpty) {
      return SaveFavoriteResult.saved; // Fallback, won't save
    }

    try {
      final itemId = DateTime.now().millisecondsSinceEpoch.toString();
      final title = _input.length > 50
          ? '${_input.substring(0, 50)}...'
          : _input;

      final outcome = await _favoritesRepository.addViralRewriteToFavorites(
        itemId: itemId,
        title: title,
        content: {'original': _input, 'rewritten': _output!},
        input: _input, // Use input for duplicate detection
        groups: [
          {
            'type': 'viral_rewrite',
            'original': _input,
            'rewritten': _output!,
            'generatedAt': DateTime.now().toIso8601String(),
          },
        ],
        generatedAt: DateTime.now().toIso8601String(),
      );

      if (outcome.isSuccess) {
        _isFavorited = true;
        _lastSavedItemId = outcome.itemId;
      }
      notifyListeners();
      print('✅ Saved to favorites: ${outcome.itemId} (result: ${outcome.result})');
      return outcome.result;
    } catch (e) {
      _isFavorited = false;
      _errorMessage = 'errors.failed_save_favorites'.tr();
      print('❌ Save to favorites failed: $_errorMessage');
      notifyListeners();
      return SaveFavoriteResult.saved;
    }
  }

  Future<bool> removeFromFavorites() async {
    if (_lastSavedItemId == null) return false;

    // Optimistic update - change UI immediately
    final previousItemId = _lastSavedItemId;
    _isFavorited = false;
    _lastSavedItemId = null;
    notifyListeners();

    try {
      await _favoritesRepository.removeFromFavorites(
        'viral_rewrite',
        previousItemId!,
      );
      print('✅ Removed from favorites');
      return true;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = true;
      _lastSavedItemId = previousItemId;
      _errorMessage = 'errors.failed_remove_favorites'.tr();
      print('❌ Remove from favorites failed: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  /// Sanitize JSON to handle truncated/malformed AI responses
  /// Stack-based JSON repair — delegates to shared utility.
  String _sanitizeJson(String json) => sanitizeJson(json);

  void _logLongText(String header, String text, {int chunkSize = 700}) {
    print(header);
    if (text.isEmpty) {
      print('  (empty)');
      return;
    }

    for (int index = 0; index < text.length; index += chunkSize) {
      final end = (index + chunkSize).clamp(0, text.length);
      print(text.substring(index, end));
    }
  }

  String _cleanResponseText(String value) {
    var cleaned = value
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .replaceAll('"{', '{')
        .replaceAll('}"', '}')
        .trim();

    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    return _sanitizeUtf16(cleaned);
  }

  String _formatViralRewriteOutput(Map<String, dynamic> data, String fallback) {
    final text = _getResolvedText(data, fallback);
    final emotionalHook = _getResolvedEmotionalHook(data, fallback);
    final hashtag = _getResolvedHashtag(data, fallback);
    final callToAction = _getResolvedCallToAction(data, fallback);

    return _sanitizeUtf16(
      [
        '**${'viral_rewrite.text'.tr()}** \n$text',
        '**${'viral_rewrite.emotional_hook'.tr()}**\n$emotionalHook',
        '**${'viral_rewrite.hashtag'.tr()}**\n$hashtag',
        '**${'viral_rewrite.call_to_action'.tr()}**\n$callToAction',
      ].join('\n\n'),
    );
  }

  String _getResolvedText(Map<String, dynamic> data, String fallback) {
    final text = _extractBestText(data['text']);
    if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
      return _sanitizeUtf16(_cleanResponseText(text));
    }
    return _sanitizeUtf16(_cleanResponseText(fallback));
  }

  String _getResolvedEmotionalHook(Map<String, dynamic> data, String fallback) {
    final hook = _extractBestText(data['emotional_hook']);
    if (hook != null && hook.isNotEmpty && hook.toLowerCase() != 'null') {
      return _sanitizeUtf16(_cleanResponseText(hook));
    }

    final source = _getResolvedText(data, fallback);
    final sentenceEnd = source.indexOf(RegExp(r'[.!?]'));
    if (sentenceEnd > 0) {
      return _sanitizeUtf16(source.substring(0, sentenceEnd + 1).trim());
    }
    return _sanitizeUtf16(source);
  }

  String _getResolvedHashtag(Map<String, dynamic> data, String fallback) {
    final hashtag = _extractBestText(data['hashtag']);
    if (hashtag != null &&
        hashtag.isNotEmpty &&
        hashtag.toLowerCase() != 'null') {
      final tags = RegExp(
        r'#[\w_\-]+',
      ).allMatches(hashtag).map((m) => m.group(0)!).toList();
      if (tags.isNotEmpty) {
        return _sanitizeUtf16(tags.take(6).join(' '));
      }
      return _sanitizeUtf16(_cleanResponseText(hashtag));
    }

    final text = _getResolvedText(data, fallback);
    final matches = RegExp(
      r'#[\w_]+',
    ).allMatches(text).map((m) => m.group(0)!).toList();
    if (matches.isNotEmpty) {
      return _sanitizeUtf16(matches.take(6).join(' '));
    }
    return '#viral #trending #content #socialmedia';
  }

  String _getResolvedCallToAction(Map<String, dynamic> data, String fallback) {
    final cta =
        _extractBestText(data['call_to_action']) ??
        _extractBestText(data['cta']);
    if (cta != null && cta.isNotEmpty && cta.toLowerCase() != 'null') {
      return _sanitizeUtf16(_cleanResponseText(cta));
    }
    return _sanitizeUtf16(
      'Share this with your audience and tell us your take in the comments.',
    );
  }

  String? _extractBestText(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }

    if (value is List) {
      for (final item in value) {
        final extracted = _extractBestText(item);
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
      return null;
    }

    if (value is Map) {
      const preferredKeys = [
        'text',
        'message',
        'caption',
        'line',
        'hook',
        'cta',
        'call_to_action',
      ];
      for (final key in preferredKeys) {
        if (value.containsKey(key)) {
          final extracted = _extractBestText(value[key]);
          if (extracted != null && extracted.isNotEmpty) return extracted;
        }
      }

      const platforms = [
        'instagram',
        'tiktok',
        'twitter',
        'facebook',
        'youtube',
        'shorts',
        'reels',
      ];
      for (final platform in platforms) {
        if (value.containsKey(platform)) {
          final extracted = _extractBestText(value[platform]);
          if (extracted != null && extracted.isNotEmpty) return extracted;
        }
      }

      for (final entry in value.entries) {
        final extracted = _extractBestText(entry.value);
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
    }

    final fallback = value.toString().trim();
    return fallback.isEmpty ? null : fallback;
  }

  String _sanitizeUtf16(String input) {
    final units = input.codeUnits;
    final output = <int>[];

    for (int i = 0; i < units.length; i++) {
      final unit = units[i];
      final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
      final isLow = unit >= 0xDC00 && unit <= 0xDFFF;

      if (isHigh) {
        if (i + 1 < units.length) {
          final next = units[i + 1];
          final nextIsLow = next >= 0xDC00 && next <= 0xDFFF;
          if (nextIsLow) {
            output.add(unit);
            output.add(next);
            i++;
          }
        }
        continue;
      }

      if (isLow) {
        // Drop unpaired low surrogate.
        continue;
      }

      output.add(unit);
    }

    return String.fromCharCodes(output);
  }

  // ---------------- ROBUST JSON EXTRACTOR ----------------
  /// Safely extracts the first complete JSON object {} from the response
  /// Handles markdown wrappers, extra text, etc.
  String _extractJsonRobust(String response) {
    print('🔹 Extracting JSON from response...');
    // Method 1: Find by braces (most reliable)
    final int start = response.indexOf('{');
    final int end = response.lastIndexOf('}');

    if (start != -1 && end != -1 && end > start) {
      final candidate = response.substring(start, end + 1);
      try {
        jsonDecode(candidate);
        print('🔹 JSON extraction successful (method 1)');
        return candidate;
      } catch (_) {
        print('⚠️ Method 1 JSON parse failed');
      }
    }

    // Method 2: Regex with non-greedy match
    final regex = RegExp(r'\{[\s\S]*?\}', multiLine: true);
    final match = regex.firstMatch(response);
    if (match != null) {
      final candidate = match.group(0)!;
      try {
        jsonDecode(candidate);
        print('🔹 JSON extraction successful (method 2)');
        return candidate;
      } catch (_) {
        print('⚠️ Method 2 JSON parse failed');
      }
    }

    print('❌ Failed to extract valid JSON from response');
    throw Exception('errors.parse_failed'.tr());
  }

  // NOTE: Prompt construction is handled by ViralRewriteTemplate in prompt_template.dart.
  // ViewModels only pass PromptRequest parameters to PromptHandler.
}
