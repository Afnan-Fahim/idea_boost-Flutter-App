import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/ai_repository.dart';
import 'package:ideaboost/data/services/reward_token_manager.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

class ShotIdeasViewModel extends ChangeNotifier {
  final UserRepository _userRepository;
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final AiRepository _aiRepository = AiRepository();

  // Store reward token for AI generation
  String? _rewardGrantToken;

  ShotIdeasViewModel(this._userRepository, {String? initialRewardToken}) {
    if (initialRewardToken != null && initialRewardToken.isNotEmpty) {
      _rewardGrantToken = initialRewardToken;
      print('🎟️ ShotIdeas initialized with reward token');
    }
  }

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
        return 'shot_ideas.tone_friendly'.tr();
      case 'engaging_question':
        return 'shot_ideas.tone_engaging_question'.tr();
      case 'humorous':
        return 'shot_ideas.tone_humorous'.tr();
      case 'supportive':
        return 'shot_ideas.tone_supportive'.tr();
      case 'thought_provoking':
        return 'shot_ideas.tone_thought_provoking'.tr();
      default:
        return tone;
    }
  }

  void updateInput(String value) {
    _input = value.trim();
    notifyListeners();
  }

  // 💡 NEW: Method for the UI to clear the error state after it's been handled
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> generateShotIdeas({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_input.isEmpty) return;

    _isLoading = true;
    _errorMessage = null; // Clear previous errors
    // Store last used tones for regeneration
    _lastGeneratedTones = List.from(_selectedTones);
    notifyListeners();

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }
      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print('🎟️ ShotIdeas: No token provided, attempting to retrieve...');
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ ShotIdeas: Token retrieved successfully');
            } else {
              print('⚠️ ShotIdeas: No available tokens, using quota system');
            }
          }
        } catch (e) {
          print(
            '⚠️ ShotIdeas: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // Reset favorite state for new generation
      _isFavorited = false;
      _lastSavedItemId = null;

      // Build tone descriptions from selected tones
      final toneDescriptions = {
        'friendly': 'warm and approachable',
        'engaging_question': 'question-driven to spark curiosity',
        'humorous': 'funny and entertaining',
        'supportive': 'encouraging and motivating',
        'thought_provoking': 'thought-provoking and reflective',
      };
      final selectedToneDescriptions = _lastGeneratedTones
          .map((t) => toneDescriptions[t] ?? t)
          .join(', ');

      // 3. Generate shot ideas using central PromptHandler
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: 'instagram',
        userPrompt: _input,
        parameters: {'selectedToneDescriptions': selectedToneDescriptions},
        jsonStructure: {
          'shot_ideas': [
            'shot idea 1 with **bold title** and description + timing',
            'shot idea 2 with **bold title** and description + timing',
            'shot idea 3 with **bold title** and description + timing',
            'shot idea 4 with **bold title** and description + timing',
            'shot idea 5 with **bold title** and description + timing',
            'shot idea 6 with **bold title** and description + timing',
            'shot idea 7 with **bold title** and description + timing',
            'shot idea 8 with **bold title** and description + timing',
            'shot idea 9 with **bold title** and description + timing',
            'shot idea 10 with **bold title** and description + timing',
          ],
        },
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: _input,
        request: request,
        locale: locale,
        generatorType: 'shot_ideas',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🔵 ShotIdeas: Sending request to Cloud Function generateAi...');
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken!.substring(0, 20)}...)" : "NO"}',
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

      _rewardGrantToken = null;
      print('🔵 ShotIdeas: Token cleared after use');

      final response = scriptOutput.script;
      var jsonStr = _extractJsonRobust(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      dynamic shotIdeasRaw =
          (data['shot_ideas'] ??
          data['output'] ??
          data['content'] ??
          data['ideas'] ??
          data['result']);

      // Handle both array and string responses from AI
      String shotIdeas;
      if (shotIdeasRaw is List) {
        // AI returned array - convert to numbered list string
        shotIdeas = shotIdeasRaw
            .asMap()
            .entries
            .map(
              (entry) =>
                  '${entry.key + 1}. ${_normalizeShotIdeaLine(entry.value.toString())}',
            )
            .join('\n');
      } else {
        shotIdeas = _normalizeShotIdeaLine(shotIdeasRaw?.toString() ?? '');
      }

      if (shotIdeas.isEmpty || shotIdeas.toLowerCase() == 'null') {
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Clean up any markdown formatting
      shotIdeas = shotIdeas
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .replaceAll('\\n', '\n')
          .trim();

      // 🔥 DEFENSIVE CLEANUP: Strip JSON brackets if AI added them (fallback)
      // Removes patterns like: {field: value, field2: value2} within numbered items
      shotIdeas = _cleanupShotIdeasBrackets(shotIdeas);
      shotIdeas = _normalizeShotIdeaBlock(shotIdeas);

      _output = shotIdeas;

      // Save to organized history
      try {
        await _userRepository.saveHistoryGeneric(
          type: 'shot_ideas',
          input: _input,
          output: {"content": _output ?? ""},
          meta: {
            'summary': _output?.substring(0, _output!.length.clamp(0, 120)),
          },
          // generatedAt omitted - uses server timestamp
        );
      } catch (_) {
        // ignore
      }
    } catch (e) {
      // 4. Handle errors and set the message
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      _errorMessage = msg.isNotEmpty ? msg : 'errors.unexpected_error'.tr();
      _output = null; // Clear output on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  /// 🔥 Defensive cleanup: Strip JSON object notation from shot ideas if present
  /// Converts: "1. {shot_title: ..., shot_description: ..., timing: ...}"
  /// To: "1. Shot title: description with timing details"
  String _cleanupShotIdeasBrackets(String input) {
    // Pattern: Remove JSON object notation like {field: value, field2: value2}
    // Replace with clean text extracted from the fields
    String cleaned = input;

    // Remove curly braces and 'shot_title:' prefixes, keeping the content
    cleaned = cleaned.replaceAll(RegExp(r'\{'), ''); // Remove opening braces
    cleaned = cleaned.replaceAll(RegExp(r'\}'), ''); // Remove closing braces

    // Clean up field markers like 'shot_title: ' and 'shot_description: '
    cleaned = cleaned.replaceAll(RegExp(r'shot_title:\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'shot_description:\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'timing:\s*'), 'Timing: ');
    cleaned = cleaned.replaceAll(RegExp(r'shot_style:\s*'), 'Style: ');
    cleaned = cleaned.replaceAll(RegExp(r'action:\s*'), 'Action: ');

    // Clean up extra commas and spaces
    cleaned = cleaned.replaceAll(RegExp(r',\s*,'), ','); // Remove double commas
    cleaned = cleaned.replaceAll(RegExp(r'^\s*,'), ''); // Remove leading commas
    cleaned = cleaned.replaceAll(
      RegExp(r',\s*$'),
      '',
    ); // Remove trailing commas

    return cleaned.trim();
  }

  String _normalizeShotIdeaLine(String input) {
    var cleaned = input.trim();

    if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    cleaned = cleaned.replaceAll(RegExp(r'^\*\*\s*\d+[\.\)]\s*'), '**');
    cleaned = cleaned.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\[\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^"|"$'), '');

    return cleaned.trim();
  }

  String _normalizeShotIdeaBlock(String input) {
    final normalizedBlock = input
        .replaceAll(RegExp(r'\],\s*'), ']\n')
        .replaceAll(RegExp(r',\s*(?=(?:\*\*|\d+[\.\)]))'), '\n');

    final lines = normalizedBlock
        .split('\n')
        .map((line) => _normalizeShotIdeaLine(line))
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  /// Stack-based JSON repair — delegates to shared utility.
  String _sanitizeJson(String json) => sanitizeJson(json);

  String _extractJsonRobust(String rawResponse) {
    // Remove markdown code blocks
    var cleaned = rawResponse
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Find JSON object boundaries properly
    final startIdx = cleaned.indexOf('{');
    if (startIdx == -1) {
      throw Exception('errors.parse_failed'.tr());
    }

    // Find matching closing brace, not the last one
    // CRITICAL: Must account for strings to avoid counting braces inside quoted text
    int braceCount = 0;
    int bracketCount = 0;
    int endIdx = -1;
    bool inString = false;
    bool isEscaped = false;

    for (int i = startIdx; i < cleaned.length; i++) {
      final char = cleaned[i];

      // Handle escape sequences in strings
      if (char == '\\' && inString && !isEscaped) {
        isEscaped = true;
        continue;
      }

      // Toggle string state on unescaped quotes
      if (char == '"' && !isEscaped) {
        inString = !inString;
        isEscaped = false;
        continue;
      }

      isEscaped = false;

      // Only count braces/brackets outside of strings
      if (!inString) {
        if (char == '{') {
          braceCount++;
        } else if (char == '}') {
          braceCount--;
          if (braceCount == 0 && bracketCount == 0) {
            endIdx = i;
            break;
          }
        } else if (char == '[') {
          bracketCount++;
        } else if (char == ']') {
          bracketCount--;
        }
      }
    }

    if (endIdx == -1) {
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

      final outcome = await _favoritesRepository.addShortIdeasToFavorites(
        itemId: itemId,
        title: title,
        content: {'prompt': _input, 'shot_ideas': _output!},
        input: _input, // Use input for duplicate detection
        groups: [
          {
            'type': 'shot_ideas',
            'prompt': _input,
            'shot_ideas': _output!,
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
        'shot_ideas',
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
    _input = '';
    _output = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Re-runs the generation logic using the last stored input.
  Future<void> regenerate({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_input.isEmpty || _output == null) return;

    final lastInput = _input;

    // Store last used tones for this regeneration
    _lastGeneratedTones = List.from(_selectedTones);

    // Check quota FIRST before clearing anything
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ ShotIdeas Regenerate: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ ShotIdeas Regenerate: Token retrieved successfully');
            } else {
              print(
                '⚠️ ShotIdeas Regenerate: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ ShotIdeas Regenerate: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // Reset favorite state for new generation
      _isFavorited = false;
      _lastSavedItemId = null;

      // Build tone descriptions from last used tones
      final toneDescriptions = {
        'friendly': 'warm and approachable',
        'engaging_question': 'question-driven to spark curiosity',
        'humorous': 'funny and entertaining',
        'supportive': 'encouraging and motivating',
        'thought_provoking': 'thought-provoking and reflective',
      };
      final selectedToneDescriptions = _lastGeneratedTones
          .map((t) => toneDescriptions[t] ?? t)
          .join(', ');

      // 3. Generate shot ideas via PromptHandler
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: 'instagram',
        userPrompt: lastInput,
        parameters: {'selectedToneDescriptions': selectedToneDescriptions},
        jsonStructure: {
          'shot_ideas': [
            'shot idea 1 with **bold title** and description + timing',
            'shot idea 2 with **bold title** and description + timing',
            'shot idea 3 with **bold title** and description + timing',
            'shot idea 4 with **bold title** and description + timing',
            'shot idea 5 with **bold title** and description + timing',
            'shot idea 6 with **bold title** and description + timing',
            'shot idea 7 with **bold title** and description + timing',
            'shot idea 8 with **bold title** and description + timing',
            'shot idea 9 with **bold title** and description + timing',
            'shot idea 10 with **bold title** and description + timing',
          ],
        },
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: lastInput,
        request: request,
        locale: locale,
        generatorType: 'shot_ideas',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🔵 ShotIdeas: Sending request to Cloud Function generateAi...');
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken!.substring(0, 20)}...)" : "NO"}',
      );
      // For PRO users: Phased model selection (same as generateShotIdeas)
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
      print('🔵 ShotIdeas: Token cleared after use');

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      final response = scriptOutput.script;
      var jsonStr2 = _extractJsonRobust(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr2 = _sanitizeJson(jsonStr2);
      final Map<String, dynamic> regenData = jsonDecode(jsonStr2);

      String shotIdeas =
          (regenData['shot_ideas'] ??
                  regenData['output'] ??
                  regenData['content'] ??
                  regenData['ideas'] ??
                  regenData['result'])
              ?.toString()
              .trim() ??
          '';

      if (shotIdeas.isEmpty || shotIdeas.toLowerCase() == 'null') {
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Clean up any markdown formatting
      shotIdeas = shotIdeas
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .replaceAll('\\n', '\n')
          .trim();

      shotIdeas = _cleanupShotIdeasBrackets(shotIdeas);
      shotIdeas = _normalizeShotIdeaBlock(shotIdeas);

      _output = shotIdeas;

      // 4. Log to History
      try {
        await _userRepository.saveHistoryGeneric(
          type: 'shot_ideas',
          input: lastInput,
          output: {"content": _output ?? ""},
          meta: {
            'summary': _output?.substring(0, _output!.length.clamp(0, 120)),
          },
        );
      } catch (_) {
        // ignore
      }
    } catch (e) {
      print('❌ ShotIdeas Regenerate Error: $e');
      // Set a clean error message for the UI
      _errorMessage = e.toString().contains('Exception:')
          ? e.toString().replaceFirst('Exception: ', '')
          : 'errors.unexpected_error'.tr();
      _output = null;
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
        '🔵 ShotIdeas Regenerate: Done - isLoading=$_isLoading, hasOutput=${_output != null}, error=$_errorMessage',
      );
    }
  }

  // NOTE: Prompt construction is handled by ShotIdeasTemplate in prompt_template.dart.
  // ViewModels only pass PromptRequest parameters to PromptHandler.
}
