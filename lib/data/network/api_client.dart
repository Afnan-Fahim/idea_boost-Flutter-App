import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Custom exception that includes HTTP status code for retry logic
class HttpStatusException implements Exception {
  final int? statusCode;
  final String userMessage;

  HttpStatusException(this.statusCode, this.userMessage);

  @override
  String toString() => userMessage;
}

/// Cloud Functions API Client
/// Handles all HTTP communication with Firebase Cloud Functions
class ApiClient {
  static const String _baseUrl =
      'https://us-central1-ideaboost-e89fc.cloudfunctions.net';

  final Dio _dio;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  ApiClient({Dio? dio}) : _dio = dio ?? Dio(_buildBaseOptions());

  /// Fetch current server time from the Cloud Function health endpoint.
  /// This acts as a "time API" without relying on third-party services.
  Future<DateTime?> fetchServerNow() async {
    try {
      debugPrint('[TimeAPI] GET /health (server time)');
      final response = await _dio.get('/health');
      final data = response.data;
      if (data is Map && data['timestamp'] is String) {
        final ts = data['timestamp'] as String;
        final parsed = DateTime.tryParse(ts);
        debugPrint('[TimeAPI] /health timestamp=$ts parsed=$parsed');
        return parsed;
      }

      debugPrint('[TimeAPI] /health response missing timestamp: $data');
      return null;
    } catch (e) {
      debugPrint('[TimeAPI] fetchServerNow failed - $e');
      return null;
    }
  }

  static BaseOptions _buildBaseOptions() {
    return BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
    );
  }

  /// Get Firebase Auth token for current user
  Future<String?> _getAuthToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ ApiClient: No authenticated user');
        throw Exception('errors.not_authenticated'.tr());
      }

      // Force token refresh to avoid expired tokens
      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        debugPrint('❌ ApiClient: Empty token received');
        throw Exception('errors.auth_token_failed'.tr());
      }

      debugPrint('✅ ApiClient: Auth token obtained (${token.length} chars)');
      return token;
    } catch (e) {
      debugPrint('❌ ApiClient: Failed to get auth token - $e');
      // 📡 Check if error is a network error from Firebase Auth
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('network-request-failed') ||
          errorStr.contains('network error') ||
          errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('unreachable')) {
        debugPrint('🌐 ApiClient: Network error detected in auth token fetch');
        throw Exception('errors.no_internet'.tr());
      }
      rethrow;
    }
  }

  /// Call generateAi Cloud Function
  /// [prompt] - The user's prompt for idea generation
  /// [quality] - 'nano' (free), 'mini' (trial/pro), 'gpt' (pro only)
  /// [conversationHistory] - Previous context messages (optional)
  /// [locale] - Full locale tag for cultural adaptation (e.g. 'en-US', 'ru-RU')
  /// Returns: Generated idea response
  Future<Map<String, dynamic>> generateAi({
    required String prompt,
    required String quality,
    required String locale,
    String? language,
    List<Map<String, dynamic>>? conversationHistory,
    String? rewardGrantToken,
  }) async {
    try {
      debugPrint('📨 ApiClient: Calling generateAi endpoint');
      debugPrint('   Prompt length: ${prompt.length} chars');
      debugPrint('   Quality: $quality');
      debugPrint('   🌍 Locale: $locale');
      debugPrint('   🗣️ Language: ${language ?? "not provided"}');
      debugPrint('   Has rewardGrantToken: ${rewardGrantToken != null}');
      if (rewardGrantToken != null) {
        debugPrint(
          '   Token preview: ${rewardGrantToken.substring(0, rewardGrantToken.length > 20 ? 20 : rewardGrantToken.length)}...',
        );
      }

      final token = await _getAuthToken();

      // Use explicitly provided language code, fallback to extracting from locale
      final effectiveLanguage = language ?? locale.split('-')[0].toLowerCase();

      final response = await _dio.post(
        '/generateAi',
        data: {
          'prompt': prompt,
          'quality': quality,
          'locale': locale,
          'language': effectiveLanguage,
          'conversationHistory': conversationHistory ?? [],
          if (rewardGrantToken != null) 'rewardGrantToken': rewardGrantToken,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      debugPrint('✅ ApiClient: generateAi success');
      final responseData = response.data as Map<String, dynamic>;

      // 🔍 DEBUG LOG: Show FULL response format being returned to UI
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('📦 [RESPONSE FORMAT] generateAi full response structure:');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('Response Keys: ${responseData.keys.toList()}');
      debugPrint('Response Type: ${response.data.runtimeType}');

      // Show each field
      responseData.forEach((key, value) {
        if (value is String) {
          final preview = value.length > 150
              ? '${value.substring(0, 150)}...'
              : value;
          debugPrint('   ✓ "$key" (String): $preview');
        } else if (value is List) {
          debugPrint('   ✓ "$key" (List): ${value.length} items');
        } else if (value is Map) {
          debugPrint('   ✓ "$key" (Map): ${value.keys.toList()}');
        } else if (value is int) {
          debugPrint('   ✓ "$key" (int): $value');
        } else if (value is double) {
          debugPrint('   ✓ "$key" (double): $value');
        } else if (value is bool) {
          debugPrint('   ✓ "$key" (bool): $value');
        } else {
          debugPrint('   ✓ "$key" (${value.runtimeType}): $value');
        }
      });

      // Show specific fields used by app
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('📊 [FIELDS USED BY UI]');
      debugPrint('═══════════════════════════════════════════════════════════');

      final scriptField =
          responseData['response'] ??
          responseData['script'] ??
          responseData['output'] ??
          '';
      final scriptStr = scriptField.toString();
      debugPrint('Script Content:');
      debugPrint(
        '   From "response": ${responseData['response'] != null ? "YES" : "NO"}',
      );
      debugPrint(
        '   From "script": ${responseData['script'] != null ? "YES" : "NO"}',
      );
      debugPrint(
        '   From "output": ${responseData['output'] != null ? "YES" : "NO"}',
      );
      debugPrint('   Final selection length: ${scriptStr.length} chars');
      if (scriptStr.isNotEmpty) {
        debugPrint(
          '   Preview: ${scriptStr.substring(0, scriptStr.length > 100 ? 100 : scriptStr.length)}...',
        );
      }

      debugPrint('Model: ${responseData['model']}');
      debugPrint('Tokens Used: ${responseData['tokensUsed']}');
      debugPrint('Execution Time: ${responseData['executionTime']}ms');
      debugPrint('═══════════════════════════════════════════════════════════');

      return responseData;
    } on DioException catch (e) {
      debugPrint(
        '❌ ApiClient: generateAi DioException | Status: ${e.response?.statusCode}',
      );
      debugPrint('   Response: ${e.response?.data}');
      throw _friendlyError(e);
    } catch (e) {
      debugPrint('❌ ApiClient: generateAi Exception - $e');
      // 📡 Check if this is a Firebase Auth network error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('network-request-failed') ||
          errorStr.contains('network error') ||
          errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('unreachable')) {
        debugPrint('🌐 ApiClient: Network error detected');
        throw Exception('errors.no_internet'.tr());
      }
      // Re-throw only if it's already a user-friendly Exception
      if (e is Exception) rethrow;
      throw Exception('errors.something_went_wrong'.tr());
    }
  }

  /// Call claimReward Cloud Function
  /// [rewardId] - Reward identifier from AdMob
  /// [rewardToken] - Reward token from AdMob callback
  /// Returns: { rewardGrantToken: string, ... }
  Future<Map<String, dynamic>> claimReward({
    required String rewardId,
    required String rewardToken,
  }) async {
    try {
      final requestTime = DateTime.now();
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('📨 [ApiClient] CLAIM REWARD HTTP REQUEST');
      debugPrint('   ├─ Endpoint: POST /claimReward');
      debugPrint('   ├─ Timestamp: ${requestTime.toIso8601String()}');
      debugPrint('   ├─ RewardId: $rewardId');
      debugPrint('   └─ Token: ${rewardToken.substring(0, 10)}...');

      final token = await _getAuthToken();
      debugPrint('   ├─ Auth Token: ${token?.substring(0, 10) ?? 'NULL'}...');

      debugPrint('   └─ Sending HTTP request...');
      final response = await _dio.post(
        '/claimReward',
        data: {'rewardId': rewardId, 'rewardToken': rewardToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final responseTime = DateTime.now();
      final duration = responseTime.difference(requestTime);

      debugPrint('✅ [ApiClient] CLAIM REWARD HTTP RESPONSE');
      debugPrint('   ├─ Status Code: ${response.statusCode}');
      debugPrint('   ├─ Duration: ${duration.inMilliseconds}ms');
      debugPrint('   ├─ Response Data: ${response.data}');
      debugPrint('   ├─ Response Type: ${response.data.runtimeType}');

      // Extract and log grant token
      final data = response.data as Map<String, dynamic>;
      final grantToken = data['rewardGrantToken'] as String?;
      debugPrint(
        '   ├─ Grant Token: ${grantToken != null ? '${grantToken.substring(0, 10)}...' : 'NULL'}',
      );

      // 🔍 DEBUG: Show full response structure
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('📦 [RESPONSE FORMAT] claimReward full response structure:');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('Response Keys: ${data.keys.toList()}');
      data.forEach((key, value) {
        if (value is String) {
          final preview = value.length > 100
              ? '${value.substring(0, 100)}...'
              : value;
          debugPrint('   ✓ "$key": "$preview"');
        } else {
          debugPrint('   ✓ "$key": $value (${value.runtimeType})');
        }
      });
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('   └─ Response Timestamp: ${responseTime.toIso8601String()}');
      debugPrint('═══════════════════════════════════════════════════════════');

      return data;
    } on DioException catch (e) {
      debugPrint(
        '❌ [ApiClient] CLAIM REWARD FAILED | Status: ${e.response?.statusCode} | Data: ${e.response?.data}',
      );
      throw _friendlyError(e);
    } catch (e) {
      debugPrint('❌ [ApiClient] CLAIM REWARD EXCEPTION: $e');
      // 📡 Check if this is a Firebase Auth network error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('network-request-failed') ||
          errorStr.contains('network error') ||
          errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('unreachable')) {
        debugPrint('🌐 ApiClient: Network error detected in claimReward');
        throw Exception('errors.no_internet'.tr());
      }
      if (e is Exception) rethrow;
      throw Exception('errors.failed_process_reward'.tr());
    }
  }

  /// Maps a DioException to a user-friendly error message.
  /// Returns HttpStatusException which includes the status code for retry logic.
  /// Backend `error` field is user-readable; `message` field is internal — ignore it.
  Exception _friendlyError(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    // Backend sends an `error` field with a user-readable message
    final backendError = (data is Map) ? data['error'] as String? : null;

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return HttpStatusException(null, 'errors.request_timeout'.tr());
    }
    if (e.type == DioExceptionType.connectionError) {
      return HttpStatusException(null, 'errors.no_internet'.tr());
    }

    switch (status) {
      case 400:
        return HttpStatusException(status, 'errors.invalid_request'.tr());
      case 401:
        return HttpStatusException(status, 'errors.session_expired'.tr());
      case 403:
        // 403s carry backend business-logic messages — map known patterns to
        // localized strings so they display correctly in all languages.
        if (backendError != null &&
            backendError.toLowerCase().contains('reward grant token')) {
          return HttpStatusException(
            status,
            'errors.missing_reward_token'.tr(),
          );
        }
        if (backendError != null &&
            (backendError.toLowerCase().contains('daily limit') ||
                backendError.toLowerCase().contains('limit reached'))) {
          return HttpStatusException(status, 'errors.daily_limit_wait'.tr());
        }
        return HttpStatusException(status, 'errors.access_denied'.tr());
      case 404:
        return HttpStatusException(status, 'errors.service_unavailable'.tr());
      case 429:
        return HttpStatusException(status, 'errors.limited_exhusted'.tr());
      case 500:
      case 502:
      case 503:
        return HttpStatusException(status, 'errors.server_error'.tr());
      default:
        return HttpStatusException(status, 'errors.something_went_wrong'.tr());
    }
  }

  /// Health check endpoint
  /// Returns: Server status
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      debugPrint('📨 ApiClient: Health check');

      final response = await _dio.get('/health');

      debugPrint('✅ ApiClient: Health check OK');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ ApiClient: Health check failed - $e');
      rethrow;
    }
  }
}
