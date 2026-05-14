import 'package:ideaboost/data/models/script_output_model.dart';
import 'package:ideaboost/data/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:ideaboost/core/services/crashlytics_service.dart';

/// AI Generation Repository
/// Handles communication with generateAi Cloud Function
class AiRepository {
  final ApiClient _apiClient = ApiClient();

  /// Generate AI idea/script with automatic retry on 500 errors (max 3 retries)
  /// [prompt] - User's input prompt
  /// [quality] - 'nano' (free), 'mini' (trial/pro), 'gpt' (pro only)
  /// [conversationHistory] - Previous context (optional)
  /// [rewardGrantToken] - Token from claimed reward (optional, for free users)
  /// [locale] - Full locale tag for cultural adaptation (e.g. 'en-US', 'ru-RU')

  Future<ScriptOutputModel> generateAi({
    required String prompt,
    required String quality,
    required String locale,
    String? language,
    List<Map<String, dynamic>>? conversationHistory,
    String? rewardGrantToken,
  }) async {
    const int maxRetries = 3;
    int retryCount = 0;
    Exception? lastError;

    while (retryCount <= maxRetries) {
      try {
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint(
          '🔵 AiRepository: Request attempt ${retryCount + 1}/$maxRetries',
        );
        debugPrint('   Quality: $quality');
        debugPrint('   🌍 Locale: $locale');
        debugPrint('   🗣️ Language: ${language ?? "not provided"}');
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );

        final response = await _apiClient.generateAi(
          prompt: prompt,
          quality: quality,
          conversationHistory: conversationHistory,
          rewardGrantToken: rewardGrantToken,
          locale: locale,
          language: language,
        );

        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint(
          '✅ AiRepository: Response received (attempt ${retryCount + 1})',
        );
        debugPrint('   Keys: ${response.keys.toList()}');
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );

        // Parse response into ScriptOutputModel
        final scriptContent =
            response['response'] ??
            response['script'] ??
            response['output'] ??
            '';

        debugPrint('🔍 AiRepository: Script field extraction');
        final respStr = response['response']?.toString() ?? 'NULL';
        final scriptStr = response['script']?.toString() ?? 'NULL';
        final outputStr = response['output']?.toString() ?? 'NULL';

        debugPrint(
          '   - response[\'response\']: ${respStr.length > 100 ? respStr.substring(0, 100) : respStr}',
        );
        debugPrint(
          '   - response[\'script\']: ${scriptStr.length > 100 ? scriptStr.substring(0, 100) : scriptStr}',
        );
        debugPrint(
          '   - response[\'output\']: ${outputStr.length > 100 ? outputStr.substring(0, 100) : outputStr}',
        );
        debugPrint('   - Final scriptContent length: ${scriptContent.length}');

        if (scriptContent.isEmpty) {
          debugPrint('❌ CRITICAL: Script content is EMPTY!');
          debugPrint('   Response object: $response');
        }

        // 🎬 Create the model that will be shown on UI
        final output = ScriptOutputModel(
          id:
              response['id'] ??
              'generated-${DateTime.now().millisecondsSinceEpoch}',
          script:
              response['response'] ??
              response['script'] ??
              response['output'] ??
              '',
          model: response['model'] ?? quality,
          tokensUsed: response['tokensUsed'] ?? 0,
          executionTime: response['executionTime'] ?? 0,
          timestamp: DateTime.now(),
        );

        // 🎨 DEBUG: Show what model looks like when displayed on UI
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint('🎬 [PARSED MODEL - SHOWN ON UI] ScriptOutputModel:');
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint('• id: ${output.id}');
        debugPrint('• model: ${output.model}');
        debugPrint('• tokensUsed: ${output.tokensUsed}');
        debugPrint('• executionTime: ${output.executionTime}ms');
        debugPrint('• timestamp: ${output.timestamp.toIso8601String()}');
        debugPrint('• script length: ${output.script.length} chars');
        debugPrint('• script preview:');
        final scriptLines = output.script.split('\n');
        for (
          int i = 0;
          i < (scriptLines.length > 5 ? 5 : scriptLines.length);
          i++
        ) {
          debugPrint('  ${i + 1}. ${scriptLines[i]}');
        }
        if (scriptLines.length > 5) {
          debugPrint('  ... and ${scriptLines.length - 5} more lines');
        }
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint(
          '✅ AiRepository: Generation SUCCEEDED (attempt ${retryCount + 1})',
        );
        debugPrint('   Parsed into ScriptOutputModel');
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        return output;
      } catch (e, stackTrace) {
        lastError = e as Exception;

        // Check if it's an HttpStatusException with 500/502/503 status code
        int? statusCode;
        if (e is HttpStatusException) {
          statusCode = e.statusCode;
        }

        final is500Error =
            statusCode == 500 || statusCode == 502 || statusCode == 503;

        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );
        debugPrint(
          '❌ AiRepository: Error on attempt ${retryCount + 1}/$maxRetries',
        );
        debugPrint('   Error: $e');
        debugPrint('   Status Code: ${statusCode ?? "unknown"}');
        debugPrint('   Is 500/502/503: $is500Error');
        debugPrint(
          '═══════════════════════════════════════════════════════════════',
        );

        // If it's a 500 error AND we haven't exhausted retries, retry
        if (is500Error && retryCount < maxRetries) {
          retryCount++;
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );
          debugPrint('🔄 Retrying API call... ($retryCount/$maxRetries)');
          debugPrint('   Will attempt again in 1 second...');
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );

          // Wait 1 second before retry
          await Future.delayed(const Duration(seconds: 1));
          continue; // Try again
        } else if (is500Error && retryCount >= maxRetries) {
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );
          debugPrint('❌ AiRepository: Max retries ($maxRetries) exhausted');
          debugPrint('   No more retries available');
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );

          await CrashlyticsService.recordError(
            e,
            stackTrace,
            reason:
                'AI generation failed after $maxRetries retries for quality: $quality',
          );
          rethrow;
        } else {
          // Not a 500 error, don't retry (it's a validation/auth error, etc.)
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );
          debugPrint('❌ AiRepository: Non-retryable error detected');
          debugPrint('   Error type: ${e.runtimeType}');
          debugPrint(
            '═══════════════════════════════════════════════════════════════',
          );

          await CrashlyticsService.recordError(
            e,
            stackTrace,
            reason: 'Non-retryable AI generation error for quality: $quality',
          );
          rethrow;
        }
      }
    }

    // Fallback - should never reach here
    debugPrint('❌ AiRepository: Unexpected state - throwing lastError');
    if (lastError != null) {
      throw lastError;
    }
    throw Exception('AI generation failed - unknown error');
  }

  /// Generate with nano quality (free tier)
  Future<ScriptOutputModel> generateNano({
    required String prompt,
    required String locale,
    String? language,
    String? rewardGrantToken,
  }) async {
    debugPrint('🔵 AiRepository.generateNano called');
    debugPrint('   - Has token: ${rewardGrantToken != null}');
    debugPrint('   - 🌍 Locale: $locale');
    if (rewardGrantToken != null) {
      debugPrint('   - Token length: ${rewardGrantToken.length}');
      debugPrint(
        '   - Token preview: ${rewardGrantToken.substring(0, rewardGrantToken.length > 20 ? 20 : rewardGrantToken.length)}...',
      );
    }

    return generateAi(
      prompt: prompt,
      quality: 'nano',
      rewardGrantToken: rewardGrantToken,
      locale: locale,
      language: language,
    );
  }

  /// Generate with mini quality (trial/limited pro)
  Future<ScriptOutputModel> generateMini({
    required String prompt,
    required String locale,
    String? language,
    String? rewardGrantToken,
  }) async {
    return generateAi(
      prompt: prompt,
      quality: 'mini',
      rewardGrantToken: rewardGrantToken,
      locale: locale,
      language: language,
    );
  }

  /// Generate with full GPT quality (pro tier)
  Future<ScriptOutputModel> generateGpt({
    required String prompt,
    required String locale,
    String? language,
    List<Map<String, dynamic>>? conversationHistory,
  }) async {
    return generateAi(
      prompt: prompt,
      quality: 'gpt',
      conversationHistory: conversationHistory,
      locale: locale,
      language: language,
    );
  }
}
