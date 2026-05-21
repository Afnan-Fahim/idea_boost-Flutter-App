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

class HashtagGeneratorViewModel extends ChangeNotifier {
  final UserRepository _userRepository;
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final AiRepository _aiRepository = AiRepository();

  // Store reward token for AI generation
  String? _rewardGrantToken;

  final StreamSubscription<FavoritesChangeEvent>? _changeSubscription;

  HashtagGeneratorViewModel(
    this._userRepository, {
    String? initialRewardToken,
  }) {
    if (initialRewardToken != null && initialRewardToken.isNotEmpty) {
      _rewardGrantToken = initialRewardToken;
      print('🎟️ HashtagGenerator initialized with reward token');
    }
    // Subscribe to Favorites changes
    _changeSubscription = FavoritesRepository.onChange.listen(_handleFavoritesChange);
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _input = '';
  String get input => _input;

  String? _output;
  String? get output => _output;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isFavorited = false;
  bool get isFavorited => _isFavorited;

  String? _lastSavedItemId;
  String? get lastSavedItemId => _lastSavedItemId;

  void updateInput(String value) {
    _input = value.trim();
    notifyListeners();
  }

  // ---------------------------
  // NEW: Clear error function for UI listener
  // ---------------------------
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Future<void> increaseLimitByAdReward() async {
  //   try {
  //     // Calls the repository method to increase the daily limit count
  //     await _userRepository.grantRewardedGeneration();
  //     // Notify listeners to update any displayed limit counter in the UI
  //     notifyListeners();
  //   } catch (e) {
  //     _errorMessage = "${'general.failed_grant_reward'.tr()}: ${e.toString()}";
  //     notifyListeners();
  //   }
  // }

  // ---------------------------
  // CORRECTED GENERATION LOGIC
  // ---------------------------
  Future<void> generateHashtags({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_input.isEmpty) return;

    _isLoading = true;
    _errorMessage = null; // Clear previous errors
    notifyListeners();

    try {
      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ HashtagGenerator: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ HashtagGenerator: Token retrieved successfully');
            } else {
              print(
                '⚠️ HashtagGenerator: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ HashtagGenerator: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // 3. Generate hashtags using Gemini AI via PromptHandler
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: 'instagram',
        userPrompt: _input,
        parameters: {'isDifferent': false},
        jsonStructure: {
          'hashtags': 'string containing all hashtags separated by spaces',
        },
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: _input,
        request: request,
        locale: locale,
        generatorType: 'hashtag',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print(
        '🔵 HashtagGenerator: Sending request to Cloud Function generateAi...',
      );
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken?.substring(0, 20) ?? 'null'}...)" : "NO"}',
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
      print('🔵 HashtagGenerator: Token cleared after use');

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      final response = scriptOutput.script;
      var jsonStr = _extractJsonRobust(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      dynamic hashtagsRaw =
          (data['hashtags'] ??
          data['output'] ??
          data['content'] ??
          data['result']);

      // Handle both array and string responses from AI
      String? hashtags;
      if (hashtagsRaw is List) {
        // AI returned array - convert to space-separated string
        hashtags = hashtagsRaw
            .map((item) {
              final str = item.toString().trim();
              // Ensure hashtags start with #
              return str.startsWith('#') ? str : '#$str';
            })
            .join(' ');
      } else {
        hashtags = hashtagsRaw?.toString().trim();
      }

      if (hashtags == null ||
          hashtags.isEmpty ||
          hashtags.toLowerCase() == 'null') {
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Clean up any markdown formatting
      hashtags = hashtags
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .replaceAll('\\n', '\n')
          .trim();

      _output = hashtags;

      // 4. Log to History (organized)
      try {
        await _userRepository.saveHistoryGeneric(
          type: 'hashtag',
          input: _input,
          output: {"content": _output ?? ""},
          meta: {
            'summary': _output?.substring(0, _output!.length.clamp(0, 120)),
          },
          // generatedAt omitted - uses server timestamp
        );
      } catch (_) {
        // ignore non-fatal
      }
    } catch (e) {
      // 5. Capture any error (limit exceeded, not logged in, database error)
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      _errorMessage = msg.isNotEmpty ? msg : 'errors.unexpected_error'.tr();
      _output = null; // Clear output on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stack-based JSON repair — delegates to shared utility.
  String _sanitizeJson(String json) => sanitizeJson(json);

  String _extractJsonRobust(String rawResponse) {
    // Remove markdown code blocks
    var cleaned = rawResponse
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Find JSON object boundaries
    final startIdx = cleaned.indexOf('{');
    final endIdx = cleaned.lastIndexOf('}');

    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) {
      throw Exception('errors.parse_failed'.tr());
    }

    return cleaned.substring(startIdx, endIdx + 1);
  }

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

      final outcome = await _favoritesRepository.addHashtagToFavorites(
        itemId: itemId,
        title: title,
        content: {'prompt': _input, 'hashtags': _output!},
        input: _input, // Use input for duplicate detection
        groups: [
          {
            'type': 'hashtag',
            'prompt': _input,
            'hashtags': _output!,
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
      return outcome.result;
    } catch (e) {
      _isFavorited = false;
      _errorMessage = 'errors.failed_save_favorites'.tr();
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
        'hashtag',
        previousItemId!,
      );
      return true;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = true;
      _lastSavedItemId = previousItemId;
      _errorMessage = 'errors.failed_remove_favorites'.tr();
      notifyListeners();
      return false;
    }
  }

  void clearOutput() {
    _output = null;
    notifyListeners();
  }

  /// Re-runs the generation logic using the last stored input and styles.
  Future<void> regenerate({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_output == null) return;

    final lastInput = _input;

    // Check quota FIRST before clearing anything
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ HashtagGenerator Regenerate: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print(
                '✅ HashtagGenerator Regenerate: Token retrieved successfully',
              );
            } else {
              print(
                '⚠️ HashtagGenerator Regenerate: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ HashtagGenerator Regenerate: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // 3. Only NOW clear old output and reset state
      _output = null;
      _isFavorited = false;
      _lastSavedItemId = null;
      // 💾 IMPORTANT: Keep using the last generated styles, don't reset them
      notifyListeners();

      // 4. Generate hashtags using Gemini AI via PromptHandler (isDifferent = true)
      final handler = PromptHandler();
      final regenRequest = PromptRequest(
        platform: 'instagram',
        userPrompt: lastInput,
        parameters: {'isDifferent': true},
        jsonStructure: {
          'hashtags': 'string containing all hashtags separated by spaces',
        },
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: lastInput,
        request: regenRequest,
        locale: locale,
        generatorType: 'hashtag',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🟡 HashtagGenerator: Regenerating hashtags...');
      print(
        '🔵 HashtagGenerator: Sending request to Cloud Function generateAi...',
      );
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken?.substring(0, 20) ?? 'null'}...)" : "NO"}',
      );
      // For PRO users: Phased model selection (same as generateHashtags)
      final regenUser = await _userRepository.getCurrentUser();
      late final ScriptOutputModel scriptOutput;

      if (regenUser?.isPro == true) {
        final nanoUsed = regenUser?.aiNanoUsedToday ?? 0;
        final miniUsed = regenUser?.aiMiniUsedToday ?? 0;
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
      print('🔵 HashtagGenerator: Token cleared after use');

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      final response = scriptOutput.script;
      var jsonStr2 = _extractJsonRobust(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr2 = _sanitizeJson(jsonStr2);
      final Map<String, dynamic> regenData = jsonDecode(jsonStr2);

      String? hashtags =
          (regenData['hashtags'] ??
                  regenData['output'] ??
                  regenData['content'] ??
                  regenData['result'])
              ?.toString()
              .trim();

      if (hashtags == null ||
          hashtags.isEmpty ||
          hashtags.toLowerCase() == 'null') {
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Clean up any markdown formatting
      hashtags = hashtags
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .replaceAll('\\n', '\n')
          .trim();

      _output = hashtags;

      // 5. Log to History
      try {
        await _userRepository.saveHistoryGeneric(
          type: 'hashtag',
          input: lastInput,
          output: {"content": _output ?? ""},
          meta: {
            'summary': _output?.substring(0, _output!.length.clamp(0, 120)),
          },
        );
      } catch (_) {
        // ignore non-fatal
      }
    } catch (e) {
      print('❌ HashtagGenerator Regenerate Error: $e');
      // Set a clean error message for the UI
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      _errorMessage = msg.isNotEmpty ? msg : 'errors.unexpected_error'.tr();
      _output = null;
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
        '🔵 HashtagGenerator Regenerate: Done - isLoading=$_isLoading, hasOutput=${_output != null}, error=$_errorMessage',
      );
    }
  }

  // NOTE: Prompt construction is handled by HashtagGeneratorTemplate in prompt_template.dart.
  // ViewModels only pass PromptRequest parameters to PromptHandler.
}
