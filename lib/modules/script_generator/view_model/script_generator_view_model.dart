// lib/modules/script_generator/view_model/script_generator_view_model.dart

import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ideaboost/core/utils/helpers.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/ai_repository.dart';
import 'package:ideaboost/data/services/reward_token_manager.dart';
import 'package:ideaboost/core/utils/json_sanitizer.dart';
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

class ScriptGeneratorViewModel extends ChangeNotifier {
  final IdeaModel? idea;
  final UserRepository _userRepository;
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final AiRepository _aiRepository = AiRepository();

  /// If true, quota was already deducted before VM creation
  final bool externalQuotaConsumed;

  // Store reward token for AI generation
  String? _rewardGrantToken;

  ScriptGeneratorViewModel(
    this.idea,
    this._userRepository, {
    this.externalQuotaConsumed = false,
    String? initialPrompt,
    String? initialRewardToken,
    String? initialLength,
    String? initialVariation,
    String? initialEmotion,
    String? initialPlatform,
    String initialLanguage = 'en',
  }) {
    showInputField = idea == null;
    _consumedQuota = externalQuotaConsumed;

    // Apply initial parameters if passed (e.g. from IdeaDetailsScreen bottom sheet)
    if (initialLength != null) _selectedLength = initialLength;
    if (initialVariation != null) _selectedVariation = initialVariation;
    if (initialEmotion != null) _selectedEmotion = initialEmotion;
    if (initialPlatform != null) _selectedPlatform = initialPlatform;

    // Store initial reward token if provided
    if (initialRewardToken != null && initialRewardToken.isNotEmpty) {
      _rewardGrantToken = initialRewardToken;
      print('🎟️  ViewModel initialized with reward token');
    }

    // If an initial prompt was provided (e.g. from History regenerate), prefill the prompt
    if (initialPrompt != null && initialPrompt.isNotEmpty) {
      _userPrompt = initialPrompt;
      promptController.text = initialPrompt;
      // ensure input field is shown when initial prompt exists
      showInputField = true;
    }

    if (!showInputField) {
      isStreaming = true;
      _generateScriptWithAI(
        '${idea!.title}\n${idea!.description}',
        language: initialLanguage,
        locale: Platform.localeName.replaceAll('_', '-'),
      );
    }
  }

  // ===================== STATE =====================

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _userPrompt = '';
  String get userPrompt => _userPrompt;
  set userPrompt(String value) {
    if (_userPrompt != value) {
      _userPrompt = value;
      notifyListeners();
    }
  }

  bool isStreaming = false;
  bool isComplete = false;
  bool isReloadScheduled = false;
  bool showInputField = false;

  bool _consumedQuota = false;

  bool _isFavorited = false;
  bool get isFavorited => _isFavorited;

  String? _lastSavedItemId; // track last saved favorite id

  final ScrollController scrollController = ScrollController();
  final TextEditingController promptController = TextEditingController();

  // ===================== GENERATION OPTIONS =====================

  String _selectedLength = 'short';
  String get selectedLength => _selectedLength;
  set selectedLength(String value) {
    if (_selectedLength != value) {
      _selectedLength = value;
      notifyListeners();
    }
  }

  String _selectedVariation = 'default';
  String get selectedVariation => _selectedVariation;
  set selectedVariation(String value) {
    if (_selectedVariation != value) {
      _selectedVariation = value;
      notifyListeners();
    }
  }

  String _selectedEmotion = 'neutral';
  String get selectedEmotion => _selectedEmotion;
  set selectedEmotion(String value) {
    if (_selectedEmotion != value) {
      _selectedEmotion = value;
      notifyListeners();
    }
  }

  String _selectedPlatform = 'reels';
  String get selectedPlatform => _selectedPlatform;
  set selectedPlatform(String value) {
    if (_selectedPlatform != value) {
      _selectedPlatform = value;
      notifyListeners();
    }
  }

  // ===================== SCRIPT DATA =====================

  String hook = '';
  List<String> voiceover = [];
  List<String> shots = [];
  String cta = '';
  List<String> hashtags = [];

  // ===================== ERROR =====================

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ===================== QUOTA =====================

  /// Check if user needs to watch ad before generation
  Future<bool> needsRewardedAd() async {
    final accessStatus = await _userRepository.getAccessStatus();
    return accessStatus['requiresAd'] as bool? ?? false;
  }

  // Future<void> increaseLimitByAdReward() async {
  //   try {
  //     //await _userRepository.grantRewardedGeneration();
  //     notifyListeners();
  //   } catch (e) {
  //     _errorMessage = 'general.failed_grant_reward'.tr();
  //     notifyListeners();
  //   }
  // }

  // ===================== GENERATION =====================

  Future<void> startGeneration({
    String language = 'en',
    required String locale,
  }) async {
    if (isStreaming) return;

    final prompt = idea != null
        ? '${idea!.title}\n${idea!.description}'
        : userPrompt;

    if (prompt.trim().isEmpty) return;

    isStreaming = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }

      // Check access status
      final accessStatus = await _userRepository.getAccessStatus();
      final accessMethodValue = accessStatus['accessMethod'];
      final accessMethod = accessMethodValue is String
          ? accessMethodValue
          : 'unknown';

      print('🔐 Access method: $accessMethod');

      if (accessMethod == 'blocked') {
        throw Exception('errors.daily_limit_wait'.tr());
      }

      // If not consumed yet, consume quota
      if (!_consumedQuota) {
        _consumedQuota = true;
      }

      await _generateScriptWithAI(prompt, language: language, locale: locale);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      final isUserFriendly =
          !msg.contains('PlatformException') &&
          !msg.contains('firebase') &&
          !msg.contains('DioException') &&
          !msg.contains('SocketException') &&
          msg.length < 200;
      _errorMessage = isUserFriendly ? msg : 'errors.generation_failed'.tr();
      isStreaming = false;
      isComplete = false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> regenerate({
    String language = 'en',
    required String locale,
  }) async {
    if (isStreaming) return;

    // Check access status first before clearing anything
    _errorMessage = null;
    notifyListeners();

    try {
      final accessStatus = await _userRepository.getAccessStatus();
      final accessMethodValue = accessStatus['accessMethod'];
      final accessMethod = accessMethodValue is String
          ? accessMethodValue
          : 'unknown';

      if (accessMethod == 'blocked') {
        throw Exception('errors.daily_limit_wait'.tr());
      }

      // Only clear data after access check passes
      _isFavorited = false;
      _lastSavedItemId = null;
      isComplete = false;
      isStreaming = false;
      isReloadScheduled = false;
      _consumedQuota =
          false; // Reset quota flag so regeneration will deduct usage

      // Clear previous data
      hook = '';
      voiceover.clear();
      shots.clear();
      cta = '';
      hashtags.clear();

      notifyListeners();
      await startGeneration(language: language, locale: locale);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  // ===================== FAVORITES =====================
  /// Returns SaveFavoriteResult to indicate if saved, already exists, or updated
  Future<SaveFavoriteResult> saveToFavorites() async {
    if (!isComplete) {
      _errorMessage = 'general.generate_script_first'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved; // Fallback, won't actually save
    }

    final itemId = DateTime.now().millisecondsSinceEpoch.toString();
    final generatedAt = DateTime.now().toIso8601String();
    final title = (idea?.title != null && idea!.title.trim().isNotEmpty)
        ? idea!.title
        : (_userPrompt.trim().isNotEmpty ? _userPrompt.trim() : 'Script');

    // Input for duplicate detection: use idea description or user prompt
    final inputForHash = idea?.description ?? _userPrompt;

    final content = {
      'hook': hook,
      'voiceover': voiceover,
      'shots': shots,
      'cta': cta,
      'hashtags': hashtags,
    };

    final groups = <Map<String, dynamic>>[
      {
        'type': 'script',
        'originalInput': idea?.description ?? '',
        'inputText': _userPrompt,
        'generatedAt': generatedAt,
      },
    ];

    try {
      final outcome = await _favoritesRepository.addScriptToFavorites(
        itemId: itemId,
        title: title,
        content: content,
        groups: groups,
        generatedAt: generatedAt,
        input: inputForHash, // Use input for duplicate detection
      );

      if (outcome.isSuccess) {
        _isFavorited = true;
        _lastSavedItemId = outcome.itemId;
      }
      _errorMessage = null;
      notifyListeners();
      return outcome.result;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = false;
      _errorMessage = 'general.failed_save_favorite'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved; // Fallback on error
    }
  }

  Future<bool> removeFromFavorites() async {
    if (_lastSavedItemId == null) {
      // nothing to remove (not saved yet)
      return false;
    }

    // Optimistic update - change UI immediately
    final previousItemId = _lastSavedItemId;
    _isFavorited = false;
    _lastSavedItemId = null;
    notifyListeners();

    try {
      await _favoritesRepository.removeFromFavorites('script', previousItemId!);
      return true;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = true;
      _lastSavedItemId = previousItemId;
      _errorMessage = 'general.failed_remove_favorite'.tr();
      notifyListeners();
      return false;
    }
  }

  // ===================== STREAMING =====================

  Future<void> _generateScriptWithAI(
    String basePrompt, {
    String language = 'en',
    required String locale,
  }) async {
    hook = '';
    voiceover.clear();
    shots.clear();
    cta = '';
    hashtags.clear();
    isComplete = false;
    notifyListeners();

    try {
      // 📡 CHECK INTERNET CONNECTION FIRST
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('errors.no_internet'.tr());
      }
      print('🟡 ScriptGenerator: Starting generation for: "$basePrompt"');
      print('🌍 ScriptGenerator: language=$language, locale=$locale');

      // 0️⃣ Always fetch a token as safety fallback (backend handles trial priority)
      if (_rewardGrantToken == null || _rewardGrantToken!.isEmpty) {
        print(
          '🎟️ ScriptGenerator: No token provided, attempting to retrieve...',
        );
        try {
          final tokenManager = RewardTokenManager();
          final userId = tokenManager.getCurrentUserId();
          if (userId != null) {
            final token = await tokenManager.getFirstUnconsumedToken(userId);
            if (token != null) {
              _rewardGrantToken = token;
              print('✅ ScriptGenerator: Token retrieved successfully');
            } else {
              print(
                '⚠️ ScriptGenerator: No available tokens, using quota system',
              );
            }
          }
        } catch (e) {
          print(
            '⚠️ ScriptGenerator: Token retrieval failed: $e, falling back to quota',
          );
        }
      }

      // 🔒 Backend handles ALL quota check + deduction + rollback on failure

      // 🎯 BUILD PROMPT WITH PROMPTHANDLER (Smart priority-based approach)
      print(
        '🎯 ScriptGenerator: Using PromptHandler for smart prompt assembly',
      );
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: _platformToBackend(_selectedPlatform), // Priority 2: Platform
        tone: _selectedEmotion, // Priority 2: Tone
        userPrompt: basePrompt, // Priority 2: User Input
        parameters: {
          'length': _selectedLength,
          'variation': _selectedVariation,
        },
        jsonStructure: {
          'hook': 'brief opening that grabs attention',
          'voiceover': [
            'dialogue/narration line 1',
            'dialogue/narration line 2',
          ],
          'shots': ['scene description 1', 'scene description 2'],
          'cta': 'call to action',
          'hashtags': ['hashtag1', 'hashtag2'],
        },
        rewardGrantToken: _rewardGrantToken,
        quality: 'nano',
      );

      final promptResult = await handler.handlePromptRequest(
        language: language, // Priority 1: Language (foundation)
        userPrompt: basePrompt,
        request: request, // Priority 2: Platform, tone, params
        locale: locale, // Priority 3: Locale/RTL
        generatorType: 'script',
      );

      // Validate prompt result
      if (!promptResult.isValid) {
        throw Exception(
          'Prompt validation failed: ${promptResult.errorSummary}',
        );
      }

      final aiPrompt = promptResult.finalPrompt;

      print('🔵 ScriptGenerator: Calling Cloud Function generateAi...');
      print(
        '   - Passing token: ${_rewardGrantToken != null ? "YES (${_rewardGrantToken!.substring(0, 20)}...)" : "NO"}',
      );
      print('   - Prompt assembled with PromptHandler (5 priorities applied)');

      // For PRO users: Phased model selection
      // Phase 1: Mini (0-20) — premium model first
      // Phase 2: Nano (0-80) — after mini exhausted
      // Total: 100 AI generations/day
      final user = await _userRepository.getCurrentUser();
      late final ScriptOutputModel scriptOutput;

      if (user?.isPro == true) {
        final nanoUsed = user?.aiNanoUsedToday ?? 0;
        final miniUsed = user?.aiMiniUsedToday ?? 0;
        const miniCap = 20;
        const nanoCap = 80;

        if (miniUsed < miniCap) {
          print('✅ PRO mini phase ($miniUsed/$miniCap)');
          scriptOutput = await _aiRepository.generateMini(
            prompt: aiPrompt,
            rewardGrantToken: _rewardGrantToken,
            locale: locale,
            language: language,
          );
        } else if (nanoUsed < nanoCap) {
          print('✅ PRO nano phase ($nanoUsed/$nanoCap)');
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
        // Non-PRO: Always use Nano
        scriptOutput = await _aiRepository.generateNano(
          prompt: aiPrompt,
          rewardGrantToken: _rewardGrantToken,
          locale: locale,
          language: language,
        );
      }

      // ⚠️ IMPORTANT: Do NOT mark token as consumed here!
      // The backend marks tokens as consumed after AI generation
      // Let backend handle token consumption - it knows the access method used

      // Clear token after use
      _rewardGrantToken = null;
      print('🔵 ScriptGenerator: Token cleared after use');

      final response = scriptOutput.script;
      print('🟢 ScriptGenerator: Got response (${response.length} chars)');
      print('🔵 ScriptGenerator: Raw response: $response');

      // Parse the JSON response
      var jsonStr = _extractJson(response);
      print('🔵 ScriptGenerator: Extracted JSON: $jsonStr');

      // Always sanitize — safe on valid JSON, fixes control chars + truncation
      jsonStr = _sanitizeJson(jsonStr);
      final Map<String, dynamic> scriptData = jsonDecode(jsonStr);
      print('🔵 ScriptGenerator: Parsed JSON successfully');

      // Support both flat schema and nested schema:
      // flat: {hook, voiceover, shots, cta, hashtags}
      // nested: {script: {sections: {hook, voiceover, shots, cta}, hashtags}}
      Map<String, dynamic> parsedScript = scriptData;
      if (scriptData['script'] is Map) {
        final scriptRoot = Map<String, dynamic>.from(
          scriptData['script'] as Map,
        );
        final sectionsRaw = scriptRoot['sections'];
        if (sectionsRaw is Map) {
          final sections = Map<String, dynamic>.from(sectionsRaw);
          parsedScript = {
            'hook': sections['hook'],
            'voiceover': sections['voiceover'],
            'shots':
                sections['shots'] ??
                ((sections['hook'] is Map)
                    ? (sections['hook'] as Map)['shots']
                    : null),
            'cta': sections['cta'],
            'hashtags':
                scriptRoot['hashtags'] ??
                scriptData['hashtags'] ??
                sections['hashtags'],
          };
          print('🔵 ScriptGenerator: Detected nested schema script.sections');
        } else {
          parsedScript = scriptRoot;
          print('🔵 ScriptGenerator: Detected nested schema script.*');
        }
      } else if (scriptData['sections'] is Map) {
        // Handle shape: {sections: {...}, hashtags: [...]}
        final sections = Map<String, dynamic>.from(
          scriptData['sections'] as Map,
        );
        parsedScript = {
          'hook': sections['hook'],
          'voiceover': sections['voiceover'],
          'shots':
              sections['shots'] ??
              ((sections['hook'] is Map)
                  ? (sections['hook'] as Map)['shots']
                  : null),
          'cta': sections['cta'],
          'hashtags': scriptData['hashtags'] ?? sections['hashtags'],
        };
        print('🔵 ScriptGenerator: Detected nested schema sections.*');
      }

      // Simulate streaming effect for UI consistency
      // Extract hook - handle nested structure {description: "...", duration: 3, ...}
      final hookData = parsedScript['hook'];
      late final String hookValue;
      if (hookData is String) {
        hookValue = hookData;
      } else if (hookData is Map) {
        // Extract description from nested object
        hookValue =
            (hookData['description'] ??
                    hookData['text'] ??
                    hookData['title'] ??
                    hookData.toString())
                .toString();
      } else {
        hookValue = 'Hook';
      }

      final steps = <void Function()>[() => hook = hookValue];

      // Add voiceover lines one by one (handle nested structure {line: "...", speaker: "...", start: 5, end: 8})
      final voiceoverData =
          parsedScript['voiceover'] ?? parsedScript['voice_over'];
      final voiceoverList = <String>[];
      if (voiceoverData is List) {
        for (final item in voiceoverData) {
          if (item is String) {
            voiceoverList.add(item);
          } else if (item is Map) {
            // Extract the actual dialogue line from nested object
            final line =
                (item['line'] ??
                        item['text'] ??
                        item['dialogue'] ??
                        item.toString())
                    .toString();
            voiceoverList.add(line);
          }
        }
      } else if (voiceoverData is Map) {
        // Handle shape: {lines: ["...", "..."]}
        final linesData = voiceoverData['lines'];
        if (linesData is List) {
          for (final item in linesData) {
            if (item is String) {
              voiceoverList.add(item);
            } else if (item is Map) {
              final line =
                  (item['line'] ??
                          item['text'] ??
                          item['dialogue'] ??
                          item.toString())
                      .toString();
              voiceoverList.add(line);
            }
          }
        } else if (linesData is String && linesData.isNotEmpty) {
          voiceoverList.add(linesData.trim());
        }
      } else if (voiceoverData is String && voiceoverData.isNotEmpty) {
        // Fallback: AI returned string instead of array
        // Split by common delimiters (periods, newlines, "Line X:")
        final lines = voiceoverData
            .replaceAll(RegExp(r'^\d+\.\s+'), '') // Remove "1. " prefix
            .split(RegExp(r'(?:^|\n|\. )\s*(?:\d+\.\s+)?'))
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList();
        voiceoverList.addAll(lines);
      }
      for (final line in voiceoverList) {
        steps.add(() => voiceover.add(line));
      }

      // Add shots one by one (handle nested structure {description: "...", duration: 3, ...})
      final shotsData =
          parsedScript['shots'] ??
          parsedScript['shot_list'] ??
          parsedScript['scenes'];
      final shotsList = <String>[];
      if (shotsData is List) {
        for (final item in shotsData) {
          if (item is String) {
            shotsList.add(item);
          } else if (item is Map) {
            // Extract description from nested object and keep useful metadata if present
            final desc =
                (item['description'] ??
                        item['scene'] ??
                        item['frame'] ??
                        item['text'] ??
                        item['image'] ??
                        '')
                    .toString()
                    .trim();
            final duration = item['duration'];
            if (desc.isNotEmpty && duration != null) {
              shotsList.add('$desc (${duration}s)');
            } else if (desc.isNotEmpty) {
              shotsList.add(desc);
            } else {
              shotsList.add(item.toString());
            }
          }
        }
      } else if (shotsData is String && shotsData.isNotEmpty) {
        // Fallback: AI returned string instead of array
        // Split by "Scene", numbers, or common punctuation
        final shots_list = shotsData
            .split(RegExp(r'(?:^|\n|,)\s*(?:Scene\s+\d+:|\d+\.)\s*'))
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList();
        shotsList.addAll(shots_list);
      }
      for (final shot in shotsList) {
        steps.add(() => shots.add(shot));
      }

      // Extract CTA - handle nested structure {text: "...", ...}
      final ctaData =
          parsedScript['cta'] ??
          parsedScript['call_to_action'] ??
          parsedScript['callToAction'];
      late final String ctaValue;
      if (ctaData is String) {
        ctaValue = ctaData;
      } else if (ctaData is Map) {
        // Extract text from nested object
        ctaValue = (ctaData['text'] ?? ctaData['message'] ?? ctaData.toString())
            .toString();
      } else {
        ctaValue = 'CTA';
      }
      steps.add(() => cta = ctaValue);

      // Handle hashtags (array of strings or tag objects)
      final hashtagsData =
          parsedScript['hashtags'] ??
          parsedScript['tags'] ??
          parsedScript['hash_tags'];
      final hashtagsList = <String>[];
      if (hashtagsData is List) {
        for (final item in hashtagsData) {
          if (item is String) {
            hashtagsList.add(item);
          } else if (item is Map) {
            // Extract tag from nested object if needed
            final tag =
                (item['tag'] ??
                        item['hashtag'] ??
                        item['text'] ??
                        item.toString())
                    .toString();
            hashtagsList.add(tag);
          }
        }
      } else if (hashtagsData is String && hashtagsData.isNotEmpty) {
        // Fallback: AI returned string instead of array
        // Split by spaces or commas
        final tags = hashtagsData
            .split(RegExp(r'[\s,]+'))
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList();
        hashtagsList.addAll(tags);
      }
      steps.add(() => hashtags = hashtagsList);

      // Execute steps with streaming effect
      for (final step in steps) {
        await Future.delayed(const Duration(milliseconds: 300));
        step();
        notifyListeners();
        _scrollToBottom();
      }

      isStreaming = false;
      isComplete = true;
      notifyListeners();
      print('✅ ScriptGenerator: Generation complete');

      // Save script generation to history (structured output)
      try {
        final prompt = idea != null
            ? '${idea!.title}\n${idea!.description}'
            : _userPrompt;
        final outputMap = {
          'hook': hook,
          'voiceover': voiceover,
          'shots': shots,
          'cta': cta,
          'hashtags': hashtags,
        };
        // Always save as 'script' when a script is generated
        final historyType = 'script';
        await _userRepository.saveHistoryEntry(
          type: historyType,
          prompt: prompt,
          output: outputMap,
          meta: idea != null ? {'idea': idea!.toMap()} : {},
          // generatedAt omitted - uses server timestamp
        );
        print('✅ ScriptGenerator: History saved as $historyType');
      } catch (e) {
        print('⚠️ ScriptGenerator: History save failed (non-fatal): $e');
      }
    } catch (e) {
      print('❌ ScriptGenerator Error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      final isUserFriendly =
          !msg.contains('PlatformException') &&
          !msg.contains('firebase') &&
          !msg.contains('DioException') &&
          !msg.contains('SocketException') &&
          msg.length < 200;
      _errorMessage = isUserFriendly ? msg : 'errors.generation_failed'.tr();
      isStreaming = false;
      isComplete = false;
      notifyListeners();
    }
  }

  /// Sanitize JSON to handle truncated/malformed AI responses
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
    // CRITICAL: if a string contains "text with } character", we must not count that brace
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

    var jsonStr = cleanedResponse.substring(startIndex, endIndex + 1);

    // Fix unescaped newlines inside JSON strings
    // This handles newlines that appear in the middle of string values
    jsonStr = _fixUnescapedNewlines(jsonStr);

    return jsonStr;
  }

  /// Fix unescaped newlines in JSON strings
  /// Newlines inside string values need to be escaped as \\n
  String _fixUnescapedNewlines(String jsonStr) {
    final buffer = StringBuffer();
    bool inString = false;
    bool isEscaped = false;

    for (int i = 0; i < jsonStr.length; i++) {
      final char = jsonStr[i];

      if (char == '"' && !isEscaped) {
        inString = !inString;
        buffer.write(char);
      } else if (char == '\\' && !isEscaped) {
        isEscaped = true;
        buffer.write(char);
      } else if (inString && (char == '\n' || char == '\r') && !isEscaped) {
        // Unescaped newline inside string - escape it
        if (char == '\n') {
          buffer.write('\\n');
        } else if (char == '\r') {
          buffer.write('\\r');
        }
        isEscaped = false;
      } else {
        buffer.write(char);
        isEscaped = false;
      }
    }

    return buffer.toString();
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent + 300,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Map internal platform names to backend names
  /// Internal: 'tiktok', 'reels', 'shorts'
  /// Backend: 'tiktok', 'instagram', 'youtube'
  String _platformToBackend(String platform) {
    switch (platform) {
      case 'reels':
        return 'instagram';
      case 'shorts':
        return 'youtube';
      case 'tiktok':
      default:
        return platform;
    }
  }

  /// Build AI prompt for script generation with language-specific instructions
  /// Routes to individual language-specific prompt methods
  String _buildScriptPrompt(
    String basePrompt, {
    required String language,
    required String lengthGuide,
    required String variationGuide,
    required String emotionGuide,
    required String platformGuide,
  }) {
    debugPrint('🌍 Building script prompt for language: $language');

    switch (language) {
      case 'ru':
        return _promptRussian(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'uz':
        return _promptUzbek(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'ar':
        return _promptArabic(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'de':
        return _promptGerman(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'es':
        return _promptSpanish(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'fr':
        return _promptFrench(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'hi':
        return _promptHinglish(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'id':
        return _promptIndonesian(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'ms':
        return _promptMalay(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'pt':
        return _promptPortuguese(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'vi':
        return _promptVietnamese(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
      case 'en':
      default:
        return _promptEnglish(
          basePrompt,
          lengthGuide,
          variationGuide,
          emotionGuide,
          platformGuide,
        );
    }
  }

  /// English script prompt
  String _promptEnglish(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Generate a viral short-form video script for this topic: "$basePrompt"

🚨 MUST GENERATE IN ENGLISH!!! 🚨
Every single word, hook, voiceover line, CTA, and hashtag MUST be in English ONLY.

Style Guidelines:
- Length: $lengthGuide
- Variation: $variationGuide
- Emotion: $emotionGuide
- Platform: $platformGuide

Return ONLY a valid JSON object with this exact structure (no markdown, no code blocks, no extra text):
{
  "hook": "A compelling opening hook line in English that grabs attention",
  "voiceover": ["Line 1 in English", "Line 2 in English", "Line 3 in English"],
  "shots": ["Shot description 1", "Shot description 2", "Shot description 3"],
  "cta": "A call-to-action statement in English",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Requirements:
- Make it viral, engaging, and suitable for Instagram Reels, TikTok, or YouTube Shorts
- The content MUST be relevant to: "$basePrompt"
- Hook should grab attention immediately in English
- Voiceover should be conversational and engaging in English
- Shots should be visual and dynamic
- ALL text content MUST be in English language only

CRITICAL OUTPUT RULES (MUST FOLLOW STRICTLY):
- Return ONLY a valid JSON object
- DO NOT include markdown (no ```), explanations, or extra text
- DO NOT include comments or trailing commas
- DO NOT break JSON format under any condition
- ALWAYS return a response (never empty)
- Ensure and doublecheck the JSON is parseable and error-free
- Escape quotes properly inside strings

FAIL-SAFE INSTRUCTION:
If unsure, still return best possible structured output in valid JSON. Never return anything outside the JSON object.''';
  }

  /// Russian script prompt
  String _promptRussian(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Создайте вирусный скрипт для короткого видео по этой теме: "$basePrompt"

🚨 ДОЛЖНО БЫТЬ ТОЛЬКО НА РУССКОМ!!! 🚨
Каждое слово, крючок, текст закадрового голоса, CTA и хештег ДОЛЖНЫ быть ТОЛЬКО на русском языке.

Руководство по стилю:
- Длина: $lengthGuide
- Вариация: $variationGuide
- Эмоция: $emotionGuide
- Платформа: $platformGuide

Вернуть ТОЛЬКО валидный JSON объект с этой точной структурой (без markdown, без блоков кода, без лишнего текста):
{
  "hook": "Привлекающая внимание открывающая фраза на русском",
  "voiceover": ["Строка 1 на русском", "Строка 2 на русском", "Строка 3 на русском"],
  "shots": ["Описание кадра 1", "Описание кадра 2", "Описание кадра 3"],
  "cta": "Призыв к действию на русском",
  "hashtags": ["#Хештег1", "#Хештег2", "#Хештег3", "#Хештег4"]
}

Требования:
- Сделайте его вирусным, интересным и подходящим для Instagram Reels, TikTok или YouTube Shorts
- Контент ДОЛЖЕН быть релевантен: "$basePrompt"
- Крючок должен привлечь внимание сразу на русском
- Закадровый текст должен быть разговорным и интересным на русском
- Кадры должны быть визуально динамичными
- ВСЕ текстовое содержание ДОЛЖНО быть ТОЛЬКО на русском языке

КРИТИЧЕСКИЕ ПРАВИЛА ВЫВОДА (СЛЕДУЙТЕ СТРОГО):
- Возвращайте ТОЛЬКО валидный JSON объект
- НЕ включайте markdown (никаких ```), объяснений или лишнего текста
- НЕ включайте комментарии или последующие запятые
- НЕ нарушайте формат JSON ни при каких условиях
- ВСЕГДА возвращайте ответ (никогда не пустой)
- Убедитесь и проверьте, что JSON разбирается без ошибок
- Правильно экранируйте кавычки внутри строк

ИНСТРУКЦИЯ ПОДСТРАХОВКИ:
Если не уверены, все равно верните лучший возможный структурированный вывод в валидном JSON. Никогда не возвращайте ничего, что не входит в объект JSON.''';
  }

  /// Uzbek script prompt
  String _promptUzbek(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Ushbu mavzu bo'yicha viral videoskript yozing: "$basePrompt"

🚨 FAQAT O'ZBEKCHADA BO'LISHI KERAK!!! 🚨
Har bir so'z, crook, ovozli tekst, CTA va heshteq FAQAT o'zbek tilida bo'LISHI KERAK.

Uslub bo'yicha ko'rsatmalar:
- Uzunligi: $lengthGuide
- Variatsiya: $variationGuide
- Emosiya: $emotionGuide
- Platforma: $platformGuide

FAQAT bu aniq tuzulishda haqiqiy JSON ob'ektini qaytaring (markdown yo'q, kod bloklari yo'q, ekstra matn yo'q):
{
  "hook": "O'zbekchada e'tiborni o'ziga tortadigan ochuvchi qator",
  "voiceover": ["O'zbekchada 1-qator", "O'zbekchada 2-qator", "O'zbekchada 3-qator"],
  "shots": ["Kadriframe tavsifi 1", "Kadriframe tavsifi 2", "Kadriframe tavsifi 3"],
  "cta": "O'zbekchada harakat chaqiruvi",
  "hashtags": ["#Heshteg1", "#Heshteg2", "#Heshteg3", "#Heshteg4"]
}

Talablar:
- Instagram Reels, TikTok yoki YouTube Shorts uchun viral, qiziqarli va mos bo'lsin
- Kontent MUTLAQO: "$basePrompt" bilan bog'liq bo'lishi kerak
- Crook o'zbekchada darhol e'tiborni tortishi kerak
- Ovozli tekst o'zbekchada gaplashuvchi va qiziqarli bo'lishi kerak
- Kadrlar vizual va dinamik bo'lishi kerak
- BARCHA matn "$basePrompt" FAQAT o'zbek tilida bo'lishi kerak

KRITIK CHIQIsh QO'YLLARI (QATIY RIOYA QILING):
- FAQAT haqiqiy JSON ob'ektini qaytaring
- Markdown (hech qanday ```), izohlar yoki ekstra matn qo'SH MA
- Izohlar yoki tugallash vergullarini o'Z MA
- JSON formatini hech qanday sharoitda buzma
- DOIM javob qaytaring (hech qachon bo'sh emas)
- JSON xatasiz tahlil qilinishiga ishonch hosil qiling
- Satrlar ichida kavychkalarni to'g'ri ekranirlang

ZAXIRA KO'RSATMA:
Agarda ishonch hosil bo'lmasa, hali ham eng yaxshi mumkin bo'lgan tuzilgan chiqarish haqiqiy JSON da qaytaring. Hech qachon JSON ob'ektidan tashqarida hech narsani qaytarmang.''';
  }

  /// Arabic script prompt
  String _promptArabic(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''أنشئ سيناريو فيديو فيروسي قصير المدى حول هذا الموضوع: "$basePrompt"

🚨 يجب أن يكون باللغة العربية فقط!!! 🚨
كل كلمة والخطاف والنص الصوتي والدعوة والهاشتاج يجب أن تكون باللغة العربية فقط.

إرشادات الأسلوب:
- الطول: $lengthGuide
- التنويع: $variationGuide
- العاطفة: $emotionGuide
- المنصة: $platformGuide

أعد فقط كائن JSON صحيح بهذا الهيكل الدقيق (بدون markdown، بدون كتل أكواد، بدون نصوص إضافية):
{
  "hook": "سطر افتتاحي جذاب باللغة العربية",
  "voiceover": ["السطر 1 باللغة العربية", "السطر 2 باللغة العربية", "السطر 3 باللغة العربية"],
  "shots": ["وصف اللقطة 1", "وصف اللقطة 2", "وصف اللقطة 3"],
  "cta": "دعوة للعمل باللغة العربية",
  "hashtags": ["#هاشتاج1", "#هاشتاج2", "#هاشتاج3", "#هاشتاج4"]
}

المتطلبات:
- اجعله فيروسياً وجذاباً ومناسباً لـ Instagram Reels أو TikTok أو YouTube Shorts
- يجب أن يكون المحتوى ذا صلة بـ: "$basePrompt"
- يجب أن يجذب الخطاف الانتباه على الفور باللغة العربية
- يجب أن يكون النص الصوتي محادثة قيمة ممتعة باللغة العربية
- يجب أن تكون اللقطات بصرية وديناميكية
- جميع محتويات النصوص يجب أن تكون باللغة العربية فقط

قواعد الإخراج الحرجة (الامتثال الصارم):
- أعد فقط كائن JSON صحيح
- لا تضمن markdown (بدون ```)، تفسيرات، أو نصوص إضافية
- لا تضمن تعليقات أو فواصل زائدة
- لا تنتهك تنسيق JSON تحت أي ظرف
- أعد دائماً استجابة (لا تكن فارغة أبداً)
- تأكد وتحقق من أن JSON جاهز للتح حيل بدون أخطاء
- اهرب من علامات الاقتباس بشكل صحيح داخل السلاسل

تعليمات الملاذ الآخير:
إذا كنت غير متأكد، فلا تزال تعيد أفضل ناتج منظم ممكن في JSON صحيح. لا تعد أبداً أي شيء خارج كائن JSON.''';
  }

  /// German script prompt
  String _promptGerman(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Erstellen Sie ein virales Kurzform-Videoskript für dieses Thema: "$basePrompt"

🚨 MUSS NUR AUF DEUTSCH SEIN!!! 🚨
Jedes Wort, der Hook, der Voice-Over-Text, der CTA und die Hashtags MÜSSEN nur auf Deutsch sein.

Stilrichtlinien:
- Länge: $lengthGuide
- Variation: $variationGuide
- Emotion: $emotionGuide
- Plattform: $platformGuide

Geben Sie nur ein gültiges JSON-Objekt mit dieser genauen Struktur zurück (kein Markdown, keine Codeblöcke, kein zusätzlicher Text):
{
  "hook": "Eine aufmerksamkeitserregende Eröffnungszeile auf Deutsch",
  "voiceover": ["Zeile 1 auf Deutsch", "Zeile 2 auf Deutsch", "Zeile 3 auf Deutsch"],
  "shots": ["Aufnahmebeschreibung 1", "Aufnahmebeschreibung 2", "Aufnahmebeschreibung 3"],
  "cta": "Call-to-Action auf Deutsch",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Anforderungen:
- Machen Sie es virenverbreitet, fesselnd und geeignet für Instagram Reels, TikTok oder YouTube Shorts
- Der Inhalt MUSS relevant sein für: "$basePrompt"
- Der Hook sollte sofort auf Deutsch Aufmerksamkeit erregen
- Der Voice-Over sollte auf Deutsch gesprächig und fesselnd sein
- Die Aufnahmen sollten visuell und dynamisch sein
- ALLE Textinhalte MÜSSEN nur auf Deutsch sein

KRITISCHE AUSGANGSREGELN (STRENG EINHALTEN):
- Geben Sie nur ein gültiges JSON-Objekt zurück
- Kein Markdown (keine ```), Erklärungen oder zusätzlicher Text
- Keine Kommentare oder nachfolgende Kommas
- Verletzen Sie das JSON-Format unter keinen Umständen
- Geben Sie IMMER eine Antwort zurück (nie leer)
- Stellen Sie sicher und überprüfen Sie, dass die JSON fehlerfrei analysierbar ist
- Maskieren Sie Anführungszeichen korrekt in Zeichenketten

NOTFALLANWEISUNG:
Wenn unsicher, geben Sie trotzdem die bestmögliche strukturierte Ausgabe in gültigem JSON zurück. Geben Sie nie etwas außerhalb des JSON-Objekts zurück.''';
  }

  /// Spanish script prompt
  String _promptSpanish(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Crea un guion viral de video de corta duración sobre este tema: "$basePrompt"

🚨 ¡DEBE SER SOLO EN ESPAÑOL!!! 🚨
Cada palabra, el gancho, el texto de voz en off, el CTA y los hashtags DEBEN ser solo en español.

Directrices de estilo:
- Largo: $lengthGuide
- Variación: $variationGuide
- Emoción: $emotionGuide
- Plataforma: $platformGuide

Devuelve SOLO un objeto JSON válido con esta estructura exacta (sin markdown, sin bloques de código, sin texto extra):
{
  "hook": "Una línea de apertura que capture la atención en español",
  "voiceover": ["Línea 1 en español", "Línea 2 en español", "Línea 3 en español"],
  "shots": ["Descripción de toma 1", "Descripción de toma 2", "Descripción de toma 3"],
  "cta": "Llamada a la acción en español",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Requisitos:
- Hazlo viral, atractivo y adecuado para Instagram Reels, TikTok o YouTube Shorts
- El contenido DEBE ser relevante para: "$basePrompt"
- El gancho debe captar la atención de inmediato en español
- La voz en off debe ser conversacional y atractiva en español
- Los planos deben ser visuales y dinámicos
- TODO el contenido de texto DEBE ser SOLO en español

REGLAS CRÍTICAS DE SALIDA (CUMPLIR ESTRICTAMENTE):
- Devuelve SOLO un objeto JSON válido
- NO incluyas markdown (sin ```), explicaciones o texto extra
- NO incluyas comentarios o comas finales
- NO rompas el formato JSON bajo ninguna circunstancia
- SIEMPRE devuelve una respuesta (nunca vacía)
- Asegúrate y comprueba que el JSON es analizable sin errores
- Escapa correctamente las comillas dentro de las cadenas

INSTRUCCIÓN DE ÚLTIMO RECURSO:
Si no estás seguro, aún devuelve la mejor salida estructurada posible en JSON válido. Nunca devuelvas nada fuera del objeto JSON.''';
  }

  /// French script prompt
  String _promptFrench(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Créez un scénario vidéo viral de courte durée sur ce sujet : "$basePrompt"

🚨 DOIT ÊTRE EN FRANÇAIS UNIQUEMENT !!! 🚨
Chaque mot, l'accroche, le texte de la voix-off, l'appel à l'action et les hashtags DOIVENT être en français uniquement.

Directrices de style :
- Longueur : $lengthGuide
- Variation : $variationGuide
- Émotion : $emotionGuide
- Plateforme : $platformGuide

Retournez UNIQUEMENT un objet JSON valide avec cette structure exacte (pas markdown, pas de blocs de code, pas de texte supplémentaire) :
{
  "hook": "Une ligne d'ouverture captivante en français",
  "voiceover": ["Ligne 1 en français", "Ligne 2 en français", "Ligne 3 en français"],
  "shots": ["Description du plan 1", "Description du plan 2", "Description du plan 3"],
  "cta": "Appel à l'action en français",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Exigences :
- Rendez-le viral, engageant et adapté à Instagram Reels, TikTok ou YouTube Shorts
- Le contenu DOIT être pertinent pour : "$basePrompt"
- L'accroche doit attirer l'attention immédiatement en français
- La narration doit être conversationnelle et engageante en français
- Les plans doivent être visuels et dynamiques
- TOUT le contenu textuel DOIT être EN FRANÇAIS UNIQUEMENT

RÈGLES CRITIQUES DE SORTIE (RESPECTER STRICTEMENT) :
- Retournez UNIQUEMENT un objet JSON valide
- N'incluez PAS de markdown (pas de ```), explications ou texte supplémentaire
- N'incluez PAS de commentaires ou virgules finales
- NE MODIFIEZ PAS le format JSON sous aucune circonstance
- RETOURNEZ TOUJOURS une réponse (ne jamais vide)
- Assurez-vous et vérifiez que le JSON est analysable sans erreurs
- Échappez correctement les guillemets à l'intérieur des chaînes

INSTRUCTION DE DERNIER RECOURS :
Si vous n'êtes pas sûr, retournez quand même la meilleure sortie structurée possible en JSON valide. Ne retournez jamais rien en dehors de l'objet JSON.''';
  }

  /// Hinglish (Hindi Roman) script prompt
  String _promptHinglish(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Iss topic par ek viral short-form video script banaayen: "$basePrompt"

🚨 SIRF HINDI/HINGLISH MEIN HONA CHAHIYE!!! 🚨
Har ek word, hook, voiceover text, CTA aur hashtag sirf Hindi/Hinglish mein hona chahiye.

Nirdesh:
- Lambai: $lengthGuide
- Badlav: $variationGuide
- Bhavna: $emotionGuide
- Manch: $platformGuide

Sirf ek valid JSON object return karien is exact structure ke saath (koi markdown nahi, koi code blocks nahi, koi extra text nahi):
{
  "hook": "Ek attractive opening line jo attention grab kare Hindi/Hinglish mein",
  "voiceover": ["Line 1 Hindi/Hinglish mein", "Line 2 Hindi/Hinglish mein", "Line 3 Hindi/Hinglish mein"],
  "shots": ["Shot description 1", "Shot description 2", "Shot description 3"],
  "cta": "Call-to-action Hindi/Hinglish mein",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Zarurat:
- Isse viral, engaging, aur Instagram Reels, TikTok ya YouTube Shorts ke liye perfect banaayen
- Content "$basePrompt" ke liye relevant hona chahiye
- Hook turant hi attention grab kare Hindi/Hinglish mein
- Voiceover conversational aur engaging ho Hindi/Hinglish mein
- Shots visually dynamic hone chahiye
- SAB text content SIRF Hindi/Hinglish mein hona chahiye

ZAROORI OUTPUT RULE (STRICTLY FOLLOW KARIEN):
- Sirf valid JSON object return karien
- Koi markdown (``` nahi), explanations ya extra text nahi
- Koi comments ya trailing commas nahi
- JSON format ko kisi bhi condition mein break na karien
- HAMESHA ek response return karien (kabhi empty nahi)
- Ensure karien ke JSON properly parse ho sake
- Quotes ko properly escape karien strings ke andar

AAKHRI INSTRUCTION:
Agar unsure ho to bhi best possible structured output return karien valid JSON mein. JSON object ke bahar kuch bhi return na karien.''';
  }

  /// Indonesian script prompt
  String _promptIndonesian(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Buat skenario video bentuk pendek yang viral untuk topik ini: "$basePrompt"

🚨 HARUS HANYA DALAM BAHASA INDONESIA!!! 🚨
Setiap kata, hook, teks voice-over, CTA, dan hashtag HARUS hanya dalam bahasa Indonesia.

Panduan Gaya:
- Panjang: $lengthGuide
- Variasi: $variationGuide
- Emosi: $emotionGuide
- Platform: $platformGuide

Hanya kembalikan objek JSON yang valid dengan struktur yang tepat ini (tanpa markdown, tanpa blok kode, tanpa teks tambahan):
{
  "hook": "Garis pembukaan yang menarik dalam bahasa Indonesia",
  "voiceover": ["Baris 1 dalam bahasa Indonesia", "Baris 2 dalam bahasa Indonesia", "Baris 3 dalam bahasa Indonesia"],
  "shots": ["Deskripsi shot 1", "Deskripsi shot 2", "Deskripsi shot 3"],
  "cta": "Call-to-action dalam bahasa Indonesia",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Persyaratan:
- Buat viral, menarik, dan cocok untuk Instagram Reels, TikTok, atau YouTube Shorts
- Konten HARUS relevan dengan: "$basePrompt"
- Hook harus menarik perhatian secara langsung dalam bahasa Indonesia
- Voice-over harus percakapan dan menarik dalam bahasa Indonesia
- Shot harus visual dan dinamis
- SEMUA konten teks HARUS hanya dalam bahasa Indonesia

PERATURAN OUTPUT KRITIS (IKUTI DENGAN KETAT):
- Hanya kembalikan objek JSON yang valid
- JANGAN sertakan markdown (tanpa ```), penjelasan, atau teks tambahan
- JANGAN sertakan komentar atau koma tertinggal
- JANGAN rusak format JSON dalam kondisi apa pun
- SELALU kembalikan respons (tidak pernah kosong)
- Pastikan dan periksa bahwa JSON dapat diuraikan tanpa kesalahan
- Escape kutipan dengan benar di dalam string

INSTRUKSI PENGAMAN:
Jika tidak yakin, tetap kembalikan output terstruktur terbaik yang mungkin dalam JSON yang valid. Jangan pernah mengembalikan apa pun di luar objek JSON.''';
  }

  /// Malay script prompt
  String _promptMalay(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Buat skenario video pendek berbentuk viral untuk topik ini: "$basePrompt"

🚨 MESTI HANYA DALAM BAHASA MELAYU!!! 🚨
Setiap perkataan, hook, teks suara latar belakang, CTA, dan hashtag MESTI hanya dalam bahasa Melayu.

Panduan Gaya:
- Panjang: $lengthGuide
- Variasi: $variationGuide
- Emosi: $emotionGuide
- Platform: $platformGuide

Hanya pulang objek JSON yang sah dengan struktur yang tepat ini (tiada markdown, tiada blok kod, tiada teks tambahan):
{
  "hook": "Baris pembuka yang menarik dalam bahasa Melayu",
  "voiceover": ["Baris 1 dalam bahasa Melayu", "Baris 2 dalam bahasa Melayu", "Baris 3 dalam bahasa Melayu"],
  "shots": ["Penerangandeskripsi shot 1", "Penerangan deskripsi shot 2", "Penerangan deskripsi shot 3"],
  "cta": "Seruan bertindak dalam bahasa Melayu",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Keperluan:
- Buat viral, menarik, dan sesuai untuk Instagram Reels, TikTok, atau YouTube Shorts
- Kandungan MESTI berkaitan dengan: "$basePrompt"
- Hook mesti menarik perhatian serta merta dalam bahasa Melayu
- Suara latar belakang mesti perbualan dan menarik dalam bahasa Melayu
- Shot mesti visual dan dinamis
- SEMUA kandungan teks MESTI hanya dalam bahasa Melayu

PERATURAN KELUARAN KRITIKAL (IKUTI DENGAN KETAT):
- Hanya pulang objek JSON yang sah
- JANGAN sertakan markdown (tiada ```), penjelasan, atau teks tambahan
- JANGAN sertakan ulasan atau koma berakhir
- JANGAN rosak format JSON dalam sebarang keadaan
- SENTIASA pulang respons (tidak pernah kosong)
- Pastikan dan semak bahawa JSON boleh diuraikan tanpa ralat
- Elak tanda petik dengan betul dalam rentetan

ARAN KESELAMATAN:
Jika tidak pasti, tetap pulang keluaran berstruktur terbaik yang mungkin dalam JSON yang sah. Jangan sekali-kali pulang apa-apa di luar objek JSON.''';
  }

  /// Portuguese script prompt
  String _promptPortuguese(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Crie um roteiro de vídeo viral de curta duração para este tópico: "$basePrompt"

🚨 DEVE SER APENAS EM PORTUGUÊS!!! 🚨
Cada palavra, gancho, texto da voz em off, CTA e hashtags DEVEM ser apenas em português.

Directrizes de Estilo:
- Comprimento: $lengthGuide
- Variação: $variationGuide
- Emoção: $emotionGuide
- Plataforma: $platformGuide

Retorne APENAS um objeto JSON válido com esta estrutura exata (sem markdown, sem blocos de código, sem texto extra):
{
  "hook": "Uma linha de abertura atraente em português",
  "voiceover": ["Linha 1 em português", "Linha 2 em português", "Linha 3 em português"],
  "shots": ["Descrição do plano 1", "Descrição do plano 2", "Descrição do plano 3"],
  "cta": "Chamada para ação em português",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Requisitos:
- Faça viral, envolvente e adequado para Instagram Reels, TikTok ou YouTube Shorts
- O conteúdo DEVE ser relevante para: "$basePrompt"
- O gancho deve chamar atenção imediatamente em português
- O voice-over deve ser conversacional e envolvente em português
- Os planos devem ser visuais e dinâmicos
- TODO o conteúdo de texto DEVE ser APENAS em português

REGRAS DE SAÍDA CRÍTICAS (CUMPRIR ESTRITAMENTE):
- Retorne APENAS um objeto JSON válido
- NÃO inclua markdown (sem ```), explicações ou texto extra
- NÃO inclua comentários ou vírgulas finais
- NÃO quebre o formato JSON sob nenhuma circunstância
- SEMPRE retorne uma resposta (nunca vazia)
- Certifique-se e verifique se o JSON é analisável sem erros
- Escape aspas corretamente dentro de strings

INSTRUÇÃO DE ÚLTIMO RECURSO:
Se não tiver certeza, retorne a melhor saída estruturada possível em JSON válido. Nunca retorne nada fora do objeto JSON.''';
  }

  /// Vietnamese script prompt
  String _promptVietnamese(
    String basePrompt,
    String lengthGuide,
    String variationGuide,
    String emotionGuide,
    String platformGuide,
  ) {
    return '''Tạo kịch bản video ngắn hạn viral cho chủ đề này: "$basePrompt"

🚨 PHẢI CHỈ BẰNG TIẾNG VIỆT!!! 🚨
Mỗi từ, móc, văn bản voiceover, CTA và hashtag PHẢI chỉ bằng tiếng Việt.

Hướng Dẫn Về Phong Cách:
- Chiều dài: $lengthGuide
- Biến thể: $variationGuide
- Cảm xúc: $emotionGuide
- Nền tảng: $platformGuide

Chỉ trả về một đối tượng JSON hợp lệ với cấu trúc chính xác này (không markdown, không khối mã, không văn bản bổ sung):
{
  "hook": "Dòng mở đầu hấp dẫn bằng tiếng Việt",
  "voiceover": ["Dòng 1 bằng tiếng Việt", "Dòng 2 bằng tiếng Việt", "Dòng 3 bằng tiếng Việt"],
  "shots": ["Mô tả cảnh quay 1", "Mô tả cảnh quay 2", "Mô tả cảnh quay 3"],
  "cta": "Lời kêu gọi hành động bằng tiếng Việt",
  "hashtags": ["#Hashtag1", "#Hashtag2", "#Hashtag3", "#Hashtag4"]
}

Yêu Cầu:
- Làm có tính lan truyền, hấp dẫn và phù hợp cho Instagram Reels, TikTok hoặc YouTube Shorts
- Nội dung PHẢI liên quan đến: "$basePrompt"
- Móc phải thu hút sự chú ý ngay lập tức bằng tiếng Việt
- Voiceover phải hội thoại và hấp dẫn bằng tiếng Việt
- Cảnh quay phải trực quan và năng động
- TẤT CẢ nội dung văn bản PHẢI chỉ bằng tiếng Việt

QUY TẮC ĐẦU RA TỚI HẠN (TUÂN THỦ HOÀN TOÀN):
- Chỉ trả về một đối tượng JSON hợp lệ
- KHÔNG bao gồm markdown (không ```), giải thích hoặc văn bản bổ sung
- KHÔNG bao gồm nhận xét hoặc dấu phẩy ở cuối
- KHÔNG phá vỡ định dạng JSON dưới bất kỳ hoàn cảnh nào
- LUÔN trả về phản hồi (không bao giờ trống)
- Đảm bảo và kiểm tra rằng JSON có thể phân tích cú pháp mà không có lỗi
- Thoát khỏi dấu ngoặc kép một cách chính xác bên trong chuỗi

HƯỚNG DẪN PHƯƠNG ÁN CUỐI CÙNG:
Nếu không chắc chắn, vẫn trả về kết quả được cấu trúc tốt nhất có thể ở dạng JSON hợp lệ. Không bao giờ trả về bất cứ điều gì ngoài đối tượng JSON.''';
  }

  // ===================== COPY =====================

  Future<void> copyAll(BuildContext context) async {
    final text =
        '''
HOOK:
$hook

VOICEOVER:
${voiceover.join('\n')}

SHOTS:
${shots.join('\n')}

CTA:
$cta

HASHTAGS:
${hashtags.join(' ')}
''';

    await Clipboard.setData(ClipboardData(text: text));

    if (context.mounted) {
      showSnackBarSafe(
        context,
        SnackBar(content: Text('general.copied_to_clipboard'.tr())),
      );
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    promptController.dispose();
    super.dispose();
  }
}
