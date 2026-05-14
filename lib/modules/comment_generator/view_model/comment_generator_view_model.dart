import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ideaboost/data/models/comments_model.dart';
import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/ai_repository.dart';
import 'package:ideaboost/data/services/reward_token_manager.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

class CommentGeneratorViewModel extends ChangeNotifier {
  // Dependency: Inject the UserRepository
  final UserRepository _userRepository;
  final AiRepository _aiRepository = AiRepository();

  // Store reward token for AI generation
  String? _rewardGrantToken;

  CommentGeneratorViewModel(
    this._userRepository, {
    String? initialRewardToken,
  }) {
    if (initialRewardToken != null && initialRewardToken.isNotEmpty) {
      _rewardGrantToken = initialRewardToken;
      print('🎟️ CommentGenerator initialized with reward token');
    }
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _input = '';
  String get input => _input;

  CommentOutput? _output;
  CommentOutput? get output => _output;

  // Available tones
  final List<String> availableTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
    'hate_to_art',
  ];

  // Selected tones (default: all selected)
  List<String> _selectedTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
    'hate_to_art',
  ];

  List<String> get selectedTones => _selectedTones;

  // Store the last used tones for regeneration
  List<String> _lastGeneratedTones = [
    'friendly',
    'engaging_question',
    'humorous',
    'supportive',
    'thought_provoking',
    'hate_to_art',
  ];

  List<String> get lastGeneratedTones => _lastGeneratedTones;

  void toggleTone(String tone) {
    if (_selectedTones.contains(tone)) {
      if (_selectedTones.length > 1) {
        // Don't allow deselecting all tones
        _selectedTones.remove(tone);
      }
    } else {
      _selectedTones.add(tone);
    }
    notifyListeners();
  }

  bool isToneSelected(String tone) => _selectedTones.contains(tone);

  /// ⚡ CRITICAL: Commit selected tones to be used for next regeneration
  /// Call this BEFORE regenerate() to ensure new selections are used
  void commitSelectedTones() {
    _lastGeneratedTones = List.from(_selectedTones);
    notifyListeners();
  }

  /// Restore the last used tones for re-generation modal
  void restoreLastGeneratedTones() {
    _selectedTones = List.from(_lastGeneratedTones);
    notifyListeners();
  }

  String getToneLabel(String tone) {
    switch (tone) {
      case 'friendly':
        return 'comment_generator.tone_friendly'.tr();
      case 'engaging_question':
        return 'comment_generator.tone_engaging_question'.tr();
      case 'humorous':
        return 'comment_generator.tone_humorous'.tr();
      case 'supportive':
        return 'comment_generator.tone_supportive'.tr();
      case 'thought_provoking':
        return 'comment_generator.tone_thought_provoking'.tr();
      case 'hate_to_art':
        return 'comment_generator.tone_hate_to_art'.tr();
      default:
        return tone;
    }
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isFavorited = false;
  bool get isFavorited => _isFavorited;

  // Track last saved favorite itemId for safe removal
  String? _lastSavedItemId;

  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  void updateInput(String value) {
    _input = value.trim();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// The main function for AI generation.
  /// It first checks the limit, and only proceeds if the limit is available.
  Future<void> generateComments({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_input.isEmpty) {
      _errorMessage = 'comment_ext.enter_text_prompt'.tr();
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _output = null;
    notifyListeners();

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }

      print('🟡 CommentGenerator: Starting generation for input: "$_input"');

      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ CommentGenerator: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ CommentGenerator: Token retrieved successfully');
            } else {
              print(
                '⚠️ CommentGenerator: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ CommentGenerator: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure
      // Client NEVER deducts or gates — server is the single source of truth

      // 3. Generate comments using Gemini AI via PromptHandler
      final handler = PromptHandler();
      final jsonStructure = <String, dynamic>{
        for (final tone in _selectedTones)
          tone: [
            'comment 1',
            'comment 2',
            'comment 3',
            'comment 4',
            'comment 5',
          ],
      };
      final request = PromptRequest(
        platform: 'instagram',
        userPrompt: _input,
        parameters: {
          'selectedTones': _selectedTones,
        },
        jsonStructure: jsonStructure,
        rewardGrantToken: _rewardGrantToken,
        quality: '',
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: _input,
        request: request,
        locale: locale,
        generatorType: 'comment',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🔵 CommentGenerator: Calling Cloud Function generateAi...');
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken?.substring(0, 20) ?? 'null'}...)" : "NO"}',
      );

      // For PRO users: Phased model selection
      // Phase 1: Mini (0-20) — premium model first
      // Phase 2: Nano (0-80) — after mini exhausted
      final user = await _userRepository.getCurrentUser();
      late final ScriptOutputModel output;

      if (user?.isPro == true) {
        final nanoUsed = user?.aiNanoUsedToday ?? 0;
        final miniUsed = user?.aiMiniUsedToday ?? 0;
        const miniCap = 20;
        const nanoCap = 80;

        if (miniUsed < miniCap) {
          print('✅ PRO mini phase ($miniUsed/$miniCap)');
          output = await _aiRepository.generateMini(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else if (nanoUsed < nanoCap) {
          print('✅ PRO nano phase ($nanoUsed/$nanoCap)');
          output = await _aiRepository.generateNano(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else {
          throw Exception('errors.daily_limit_wait'.tr());
        }
      } else {
        output = await _aiRepository.generateNano(
          prompt: aiPrompt,
          rewardGrantToken: _rewardGrantToken,
          locale: locale,
          language: language,
        );
      }

      // 🔐 NOTE: Token is consumed SERVER-SIDE after AI generation succeeds
      // The server has permission to write to activeRewardTokens field
      // Client-side marking would fail due to Firestore security rules

      // Clear token after use
      _rewardGrantToken = null;
      print('🔵 CommentGenerator: Token cleared after use');

      final response = output.script;
      print('🟢 CommentGenerator: Got response (${response.length} chars)');
      print('🔵 CommentGenerator: Raw response: $response');

      var jsonStr = _extractJson(response);
      print('🔵 CommentGenerator: Extracted JSON: $jsonStr');

      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> commentData = jsonDecode(jsonStr);
      print('🔵 CommentGenerator: Parsed JSON successfully');

      // Validate we got actual data from selected tones
      bool hasData = false;
      for (final tone in _selectedTones) {
        final comments = _normalizeComments(commentData[tone]);
        if (comments.isNotEmpty) {
          hasData = true;
          break;
        }
      }
      if (!hasData) {
        throw Exception('errors.ai_empty_content'.tr());
      }

      // Build CommentOutput from AI response - only for selected tones
      final groups = <CommentGroup>[];

      for (final tone in _selectedTones) {
        final comments = _normalizeComments(commentData[tone]);
        if (comments.isNotEmpty) {
          groups.add(
            CommentGroup(
              // Store canonical tone code (localized at render time).
              tone: tone,
              comments: comments,
            ),
          );
        }
      }

      _output = CommentOutput(
        inputText: _input,
        generatedAt: DateTime.now(), // UI display only
        groups: groups,
      );
      // 💾 Save the tones that were used for this generation
      _lastGeneratedTones = List.from(_selectedTones);
      print('✅ CommentGenerator: Output created successfully');
      print(
        '💾 CommentGenerator: Saved tones for regeneration: $_lastGeneratedTones',
      );

      // 3. Log to History
      try {
        if (_output != null) {
          await _userRepository.saveGenerationLog(_output!);
          print('✅ CommentGenerator: History saved');
        }
      } catch (e) {
        print('⚠️ CommentGenerator: History save failed (non-fatal): $e');
      }
    } catch (e) {
      print('❌ CommentGenerator Error: $e');
      // Set a clean error message for the UI
      final msg = e.toString().replaceFirst('Exception: ', '');
      _errorMessage = msg.isEmpty ? 'errors.unexpected_error'.tr() : msg;
      _output = null;

      // 🔄 FORCE RELOAD user data after any error to ensure frontend has fresh quote info
      // This handles the edge case where backend rollback may have failed or been delayed
      try {
        print('🔄 CommentGenerator: Force-reloading user data after error...');
        await _userRepository.reloadCurrentUser();
        print('✅ CommentGenerator: User data reloaded successfully');
      } catch (reloadError) {
        print(
          '⚠️ CommentGenerator: User reload failed (non-critical): $reloadError',
        );
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
        '🔵 CommentGenerator: Done - isLoading=$_isLoading, hasOutput=${_output != null}, error=$_errorMessage',
      );
    }
  }

  /// Re-runs the generation logic using the last stored input and tones.
  Future<void> regenerate({
    String language = 'en',
    required String locale,
  }) async {
    if (_isLoading) return;

    if (_output == null) return;

    final lastInput = _output!.inputText;

    // Check quota FIRST before clearing anything
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }
      print(
        '🟡 CommentGenerator: Starting regeneration for input: "$lastInput"',
      );

      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ CommentGenerator: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ CommentGenerator: Token retrieved successfully');
            } else {
              print(
                '⚠️ CommentGenerator: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ CommentGenerator: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // 3. Only NOW clear old output and reset state
      _output = null;
      _input = lastInput;
      _isFavorited = false;
      _lastSavedItemId = null;
      // 💾 IMPORTANT: Keep using the last generated tones, don't reset them
      notifyListeners();

      // 4. Generate comments using Gemini AI with LAST USED TONES via PromptHandler
      final handler = PromptHandler();
      final jsonStructure = <String, dynamic>{
        for (final tone in _lastGeneratedTones)
          tone: [
            'comment 1',
            'comment 2',
            'comment 3',
            'comment 4',
            'comment 5',
          ],
      };
      final regenRequest = PromptRequest(
        platform: 'instagram',
        userPrompt: lastInput,
        parameters: {
          'selectedTones': _lastGeneratedTones,
        },
        jsonStructure: jsonStructure,
        rewardGrantToken: _rewardGrantToken,
      );

      final promptResult = await handler.handlePromptRequest(
        language: language,
        userPrompt: lastInput,
        request: regenRequest,
        locale: locale,
        generatorType: 'comment',
      );

      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print(
        '🔵 CommentGenerator: Regenerating with tones: $_lastGeneratedTones using Cloud Function',
      );
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken?.substring(0, 20) ?? 'null'}...)" : "NO"}',
      );
      // For PRO users: Phased model selection (same as generateComments)
      final regenUser = await _userRepository.getCurrentUser();
      late final ScriptOutputModel output;

      if (regenUser?.isPro == true) {
        final nanoUsed = regenUser?.aiNanoUsedToday ?? 0;
        final miniUsed = regenUser?.aiMiniUsedToday ?? 0;
        const miniCap = 20;
        const nanoCap = 80;

        if (miniUsed < miniCap) {
          output = await _aiRepository.generateMini(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else if (nanoUsed < nanoCap) {
          output = await _aiRepository.generateNano(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else {
          throw Exception('errors.daily_limit_wait'.tr());
        }
      } else {
        output = await _aiRepository.generateNano(
          prompt: aiPrompt,
          rewardGrantToken: _rewardGrantToken,
          locale: locale,
          language: language,
        );
      }

      // 🔐 NOTE: Token is consumed SERVER-SIDE after AI generation succeeds
      // The server has permission to write to activeRewardTokens field
      // Client-side marking would fail due to Firestore security rules

      // Clear token after use
      _rewardGrantToken = null;
      print('🔵 CommentGenerator: Token cleared after use');

      final response = output.script;
      var jsonStr = _extractJson(response);
      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> commentData = jsonDecode(jsonStr);

      // Build CommentOutput from AI response - only for last generated tones
      final groups = <CommentGroup>[];

      for (final tone in _lastGeneratedTones) {
        final comments = _normalizeComments(commentData[tone]);
        if (comments.isNotEmpty) {
          groups.add(
            CommentGroup(
              // Store canonical tone code (localized at render time).
              tone: tone,
              comments: comments,
            ),
          );
        }
      }

      _output = CommentOutput(
        inputText: lastInput,
        generatedAt: DateTime.now(), // UI display only
        groups: groups,
      );

      // 5. Log to History (save full output map) - server timestamp used
      if (_output != null) {
        await _userRepository.saveGenerationLog(_output!);
      }
    } catch (e) {
      print('❌ CommentGenerator Regenerate Error: $e');
      // Set a clean error message for the UI
      final msg = e.toString().replaceFirst('Exception: ', '');
      _errorMessage = msg.isEmpty ? 'errors.unexpected_error'.tr() : msg;
      _output = null;
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
        '🔵 CommentGenerator Regenerate: Done - isLoading=$_isLoading, hasOutput=${_output != null}, error=$_errorMessage',
      );
    }
  }

  /// Saves the current generated output to the user's favorites list.
  /// Returns SaveFavoriteResult to indicate if saved or already exists.
  Future<SaveFavoriteResult> saveCurrentOutputToFavorites() async {
    if (_output == null || _input.isEmpty) {
      _errorMessage = 'comment_ext.no_output_yet'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved; // Fallback, won't actually save
    }

    // Optimistic update - change UI immediately
    _isFavorited = true;
    notifyListeners();

    try {
      final generatedAt = DateTime.now().toIso8601String();

      // Create the groups structure matching the Firestore format
      final groups = _output!.groups.map((group) {
        return {
          'type': 'comment_set',
          'tone': group.tone,
          'comments': group.comments,
          'originalInput': _input,
          'inputText': _input,
          'generatedAt': generatedAt,
        };
      }).toList();

      // Full content for storage
      final content = {'groups': groups, 'generatedAt': generatedAt};

      // Generate item ID
      final itemId = DateTime.now().millisecondsSinceEpoch.toString();

      // Save to Firestore - duplicate detection based on input + tones
      // This allows saving same input with different tones as separate favorites
      final result = await _favoritesRepository.addToFavorites(
        type: 'comments',
        itemId: itemId,
        title: _input.length > 50 ? '${_input.substring(0, 50)}...' : _input,
        content: content,
        groups: groups,
        generatedAt: generatedAt,
        input: _input,
        tones: _output!.groups
            .map((g) => g.tone)
            .toList(), // Include tones in duplicate detection
      );

      // Track saved id
      if (result == SaveFavoriteResult.saved) {
        _lastSavedItemId = itemId;
      }
      _errorMessage = null;
      notifyListeners();
      return result;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = false;
      _errorMessage = 'errors.failed_save_favorites'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved;
    }
  }

  /// Removes the last saved favorite safely.
  Future<bool> removeFromFavorites() async {
    if (_lastSavedItemId == null) {
      _errorMessage = 'comment_ext.nothing_saved'.tr();
      notifyListeners();
      return false;
    }

    // Optimistic update - change UI immediately
    final previousItemId = _lastSavedItemId;
    _isFavorited = false;
    _lastSavedItemId = null;
    notifyListeners();

    try {
      await _favoritesRepository.removeFromFavorites(
        'comments',
        previousItemId!,
      );
      _errorMessage = null;
      notifyListeners();
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

  /// Sanitize extracted JSON to handle common AI response issues:
  /// - Trailing commas before } or ]
  /// - Truncated keys without values (e.g. "key"} )
  /// - Unclosed strings or arrays
  /// Stack-based JSON repair — delegates to shared utility.
  String _sanitizeJson(String json) => sanitizeJson(json);

  /// Extract JSON from response text (handles cases where AI wraps JSON in markdown)
  String _extractJson(String response) {
    // Clean up the response first
    var cleanedResponse = response.trim();

    // Try to find JSON object more carefully
    int startIndex = cleanedResponse.indexOf('{');
    if (startIndex == -1) {
      throw Exception('errors.parse_failed'.tr());
    }

    // Find matching closing brace, accounting for strings
    // This is critical: if a comment contains "text with } character", we must not count that brace
    int braceCount = 0;
    int bracketCount = 0;
    int endIndex = -1;
    bool inString = false;
    bool isEscaped = false;

    for (int i = startIndex; i < cleanedResponse.length; i++) {
      final char = cleanedResponse[i];

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
            endIndex = i;
            break;
          }
        } else if (char == '[') {
          bracketCount++;
        } else if (char == ']') {
          bracketCount--;
        }
      }
    }

    if (endIndex == -1) {
      print('❌ Malformed JSON: Unclosed braces');
      print(
        'Response: ${cleanedResponse.substring(0, cleanedResponse.length > 200 ? 200 : cleanedResponse.length)}...',
      );
      throw Exception('errors.parse_failed'.tr());
    }

    return cleanedResponse.substring(startIndex, endIndex + 1);
  }

  /// Called from screen initState → checks limit and shows dialog if exceeded
  Future<void> checkDailyLimitOnOpen(BuildContext context) async {
    final exceeded = await _userRepository.checkDailyLimitExceeded();
    if (exceeded && context.mounted) {
      // Show the same dialog you already have
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          // Reuse the same dialog logic from screen
          // You can call a method from screen or duplicate small part
          // But easiest: just trigger the same flow
          _errorMessage = 'errors.daily_limit_exceeded'
              .tr(); // This triggers your existing dialog
          notifyListeners();
        }
      });
    }
  }

  Future<bool> isDailyLimitExceeded() async {
    return await _userRepository.checkDailyLimitExceeded();
  }

  Future<bool> checkDailyLimitAndShowDialogIfNeeded(
    BuildContext context,
  ) async {
    final exceeded = await _userRepository.checkDailyLimitExceeded();
    if (exceeded && context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _errorMessage = 'errors.daily_limit_exceeded'.tr();
          notifyListeners();
        }
      });
    }
    return exceeded;
  }


  // NOTE: Prompt construction is handled by CommentGeneratorTemplate in prompt_template.dart.
  // ViewModels only pass PromptRequest parameters to PromptHandler.

  List<String> _normalizeComments(dynamic raw) {
    if (raw == null) return const [];

    // Common case: list of strings
    if (raw is List) {
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty && s.toLowerCase() != 'null')
          .toList(growable: false);
    }

    // Sometimes the model returns a single string blob instead of an array
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return const [];

      // Split by newlines or numbered bullets, keep non-empty lines
      final lines = s
          .split(RegExp(r'\n+'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceFirst(RegExp(r'^\s*\d+[\).\-\:]\s*'), ''))
          .where((l) => l.isNotEmpty)
          .toList();
      return lines.isEmpty ? [s] : lines;
    }

    // Fallback: stringify any object into a single-item list
    final s = raw.toString().trim();
    return (s.isEmpty || s.toLowerCase() == 'null') ? const [] : [s];
  }

}


