import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/repository/ai_repository.dart';
import 'package:ideaboost/data/services/reward_token_manager.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

/// ViewModel for "Refine with AI" functionality on Idea Details screen
/// Handles: token retrieval, validation, AI generation, counter updates
class IdeaRefineViewModel extends ChangeNotifier {
  final UserRepository _userRepository;
  final AiRepository _aiRepository = AiRepository();
  final RewardTokenManager _tokenManager = RewardTokenManager();

  IdeaRefineViewModel(this._userRepository);

  bool _isRefining = false;
  bool get isRefining => _isRefining;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Execute full refinement flow with reward token management
  /// Returns refined idea data or throws error
  Future<Map<String, dynamic>> refineIdeaWithAI({
    required IdeaModel idea,
    required String userId,
    required String dailyAiLimit,
    String language = 'en',
    String length = 'short',
    String variation = 'default',
    String emotion = 'neutral',
    String platform = 'reels',
  }) async {
    // 📡 CHECK INTERNET CONNECTION FIRST
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      throw Exception('errors.no_internet'.tr());
    }

    _isRefining = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('🚀 IdeaRefineViewModel: Starting refinement flow');

      // STAGE 1: Validate Tier-3 daily limit
      debugPrint('📊 STAGE 1: Validating daily limit');
      final user = await _userRepository.getCurrentUser();

      if (user == null) {
        throw Exception('errors.user_data_not_found'.tr());
      }

      final aiNanoUsedToday = user.aiNanoUsedToday ?? 0;
      final dailyLimit = int.tryParse(dailyAiLimit) ?? 3;

      // 🔒 IMPORTANT: Do NOT block here based on daily limit!
      // Backend will check for trial FIRST, then daily limit
      // If we block here, trial users get error instead of using trial
      // Only throw if we can't even attempt generation

      // STAGE 2: Always fetch token as safety fallback (backend handles trial priority)
      debugPrint(
        '🎟️ STAGE 2: Fetching reward token (backend will use trial first if available)',
      );

      String? rewardToken;
      try {
        rewardToken = await _tokenManager.getFirstUnconsumedToken(userId);
        if (rewardToken != null) {
          debugPrint('✅ Reward token found');
        } else {
          debugPrint(
            '⚠️ No reward tokens available, will attempt with daily limit',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Token retrieval failed: $e, continuing without token');
      }

      // STAGE 3: Call backend API (with optional token)
      debugPrint('🤖 STAGE 3: Building refinement prompt with PromptHandler');

      // 🎯 BUILD PROMPT WITH PROMPTHANDLER (Smart priority-based approach)
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: platform, // Priority 2: Platform
        tone: emotion, // Priority 2: Tone (emotion)
        userPrompt:
            '${idea.title}\n${idea.description}', // Priority 2: User Input
        parameters: {
          'length': length, // ← ADDED: length parameter
          'variation': variation,
          'emotion': emotion,
          'platform': platform,
          'steps': idea.steps,
          'cta': idea.cta,
        },
        jsonStructure: {
          'refined_title': 'string',
          'refined_description': 'string',
          'refined_steps': [
            'specific actionable step 1',
            'specific actionable step 2',
            'specific actionable step 3',
            'specific actionable step 4',
            'specific actionable step 5',
          ],
          'refined_cta': 'string',
          'refined_level': 'string',
        },
        rewardGrantToken: rewardToken,
        quality: user?.isPro == true ? 'mini' : 'nano',
      );

      final promptResult = await handler.handlePromptRequest(
        language: language, // Priority 1: Language
        userPrompt: '${idea.title}\n${idea.description}',
        request: request, // Priority 2: Platform, tone, params
        locale: Platform.localeName.replaceAll(
          '_',
          '-',
        ), // Priority 3: Locale/RTL
        generatorType: 'refinement',
      );

      // Validate prompt result
      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final refinementPrompt = promptResult.finalPrompt;
      debugPrint(
        '🤖 STAGE 3: Calling backend API (with PromptHandler-assembled prompt)',
      );

      // For PRO users: Phased model selection
      // Phase 1: Mini (0-20) — premium model first
      // Phase 2: Nano (0-80) — after mini exhausted
      late final ScriptOutputModel scriptOutput;

      if (user?.isPro == true) {
        final nanoUsed = user?.aiNanoUsedToday ?? 0;
        final miniUsed = user?.aiMiniUsedToday ?? 0;
        const miniCap = 20;
        const nanoCap = 80;

        if (miniUsed < miniCap) {
          scriptOutput = await _aiRepository.generateMini(
            prompt: refinementPrompt,
            rewardGrantToken: rewardToken,
            locale: Platform.localeName.replaceAll('_', '-'),
            language: language,
          );
        } else if (nanoUsed < nanoCap) {
          scriptOutput = await _aiRepository.generateNano(
            prompt: refinementPrompt,
            rewardGrantToken: rewardToken,
            locale: Platform.localeName.replaceAll('_', '-'),
            language: language,
          );
        } else {
          throw Exception('errors.daily_limit_wait'.tr());
        }
      } else {
        scriptOutput = await _aiRepository.generateNano(
          prompt: refinementPrompt,
          rewardGrantToken: rewardToken,
          locale: Platform.localeName.replaceAll('_', '-'),
          language: language,
        );
      }

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      // STAGE 4: Parse and return refined data
      debugPrint('📋 STAGE 4: Parsing refined data');
      final response = scriptOutput.script;

      debugPrint('🔍 STAGE 4 DEBUG: Script output from API');
      debugPrint('   - Length: ${response.length}');
      debugPrint('   - Full response preview:');
      debugPrint('   $response');

      if (response.isEmpty) {
        debugPrint('❌ CRITICAL: Script response is EMPTY!');
        debugPrint('   Full scriptOutput object: $scriptOutput');
      }

      final refinedData = _parseRefinedIdea(response);

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('✅ [REFINED IDEA - FULL RESPONSE] Complete JSON Structure:');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('📦 Refined Idea Response:');
      refinedData.forEach((key, value) {
        if (value is String) {
          final preview = value.length > 80
              ? '${value.substring(0, 80)}...'
              : value;
          debugPrint('   • "$key": "$preview"');
        } else if (value is List) {
          debugPrint('   • "$key": [${(value as List).length} items]');
          final items = value as List;
          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is String) {
              final itemPreview = item.length > 80
                  ? '${item.substring(0, 80)}...'
                  : item;
              debugPrint('       [$i] "$itemPreview"');
            }
          }
        } else {
          debugPrint('   • "$key": $value');
        }
      });
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('✅ Refinement completed successfully');
      return refinedData;
    } catch (e) {
      debugPrint('❌ Refinement error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      final isUserFriendly =
          !msg.contains('PlatformException') &&
          !msg.contains('firebase') &&
          !msg.contains('DioException') &&
          !msg.contains('SocketException') &&
          msg.length < 200;
      _errorMessage = isUserFriendly ? msg : 'errors.refinement_failed'.tr();
      rethrow;
    } finally {
      _isRefining = false;
      notifyListeners();
    }
  }

  /// Parse refined idea from AI response
  Map<String, dynamic> _parseRefinedIdea(String response) {
    try {
      var jsonStr = _extractJson(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // FALLBACK: Convert old object-based refined_steps to array of strings
      if (data['refined_steps'] is List) {
        final stepsRaw = data['refined_steps'] as List;
        if (stepsRaw.isNotEmpty && stepsRaw.first is Map) {
          // Old format: [{step: "...", description: "..."}, ...]
          // Convert to: ["...", "...", ...]
          data['refined_steps'] = stepsRaw.map((item) {
            if (item is Map) {
              final step = item['step'] ?? '';
              final desc = item['description'] ?? '';
              return desc.isNotEmpty ? desc : step;
            }
            return item.toString();
          }).toList();
          debugPrint(
            'ℹ️ Converted refined_steps from object format to string array',
          );
        }
      }

      return data;
    } catch (e) {
      debugPrint('Error parsing refined idea: $e');
      throw Exception('errors.parse_failed'.tr());
    }
  }

  /// Stack-based JSON repair — delegates to shared utility.
  String _sanitizeJson(String json) => sanitizeJson(json);

  /// Map language code to language name for AI prompt
  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'ru':
        return 'Russian';
      case 'uz':
        return 'Uzbek';
      case 'ar':
        return 'Arabic';
      case 'de':
        return 'German';
      case 'es':
        return 'Spanish';
      case 'fr':
        return 'French';
      case 'hi':
        return 'Hindi';
      case 'id':
        return 'Indonesian';
      case 'ms':
        return 'Malay';
      case 'pt':
        return 'Portuguese';
      case 'vi':
        return 'Vietnamese';
      default:
        return 'English';
    }
  }

  /// Extract JSON from response (handles markdown code blocks)
  String _extractJson(String response) {
    String jsonStr = response.trim();

    // Remove markdown code blocks if present
    if (jsonStr.contains('```')) {
      jsonStr = jsonStr.replaceAll('```json', '').replaceAll('```', '').trim();
    }

    // Try to find JSON object
    final startIdx = jsonStr.indexOf('{');
    final endIdx = jsonStr.lastIndexOf('}');

    if (startIdx == -1 || endIdx == -1 || startIdx > endIdx) {
      throw Exception('errors.parse_failed'.tr());
    }

    return jsonStr.substring(startIdx, endIdx + 1);
  }
}
