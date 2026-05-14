import 'package:shared_preferences/shared_preferences.dart';
import '../../data/network/api_client.dart';

/// Service to handle reward claiming and token management
class RewardService {
  static const String _tokenStorageKey = 'reward_tokens';
  final ApiClient _apiClient = ApiClient();

  /// Claim reward from backend after user watches ad
  /// Returns the grant token if successful, null if failed
  Future<String?> claimReward({
    required String rewardId,
    required String rewardToken,
  }) async {
    try {
      final requestTime = DateTime.now();
      print('═══════════════════════════════════════════════════════════');
      print('🔐 [RewardService] CLAIM REWARD REQUEST');
      print('   ├─ Timestamp: ${requestTime.toIso8601String()}');
      print('   ├─ RewardId: $rewardId');
      print('   └─ RewardToken: ${rewardToken.substring(0, 10)}...');

      // Call backend endpoint using ApiClient
      final response = await _apiClient.claimReward(
        rewardId: rewardId,
        rewardToken: rewardToken,
      );

      final responseTime = DateTime.now();
      final duration = responseTime.difference(requestTime);

      print('✅ [RewardService] API RESPONSE RECEIVED');
      print('   ├─ Duration: ${duration.inMilliseconds}ms');
      print('   ├─ Full Response: $response');
      print('   └─ Response type: ${response.runtimeType}');

      final grantToken = response['rewardGrantToken'] as String?;

      if (grantToken != null && grantToken.isNotEmpty) {
        print('✅ [RewardService] GRANT TOKEN EXTRACTED');
        print('   ├─ Token: ${grantToken.substring(0, 10)}...');
        print('   └─ Token Length: ${grantToken.length}');
        print('═══════════════════════════════════════════════════════════');
        return grantToken;
      } else {
        print('❌ [RewardService] NO GRANT TOKEN IN RESPONSE');
        print('   ├─ Response keys: ${response.keys.toList()}');
        print('   └─ rewardGrantToken value: $grantToken');
        print('═══════════════════════════════════════════════════════════');
        return null;
      }
    } catch (e) {
      print('❌ [RewardService] ERROR CLAIMING REWARD');
      print('   ├─ Error: $e');
      print('   ├─ Error Type: ${e.runtimeType}');
      print('   └─ Stack Trace: ${StackTrace.current}');
      print('═══════════════════════════════════════════════════════════');
      return null;
    }
  }

  /// Store reward token in SharedPreferences
  Future<bool> storeRewardToken(String token) async {
    try {
      print('💾 [RewardService] STORING TOKEN TO SHARED PREFERENCES');
      print('   └─ Token to store: $token');

      final prefs = await SharedPreferences.getInstance();
      List<String> tokens = prefs.getStringList(_tokenStorageKey) ?? [];

      print('   ├─ Existing tokens BEFORE add: ${tokens.length}');
      for (int i = 0; i < tokens.length; i++) {
        print('   │  $i. ${tokens[i]}');
      }

      if (!tokens.contains(token)) {
        tokens.add(token);
        print('   ├─ Token to add: $token (NEW)');
        print('   ├─ Tokens list AFTER add (before save): ${tokens.length}');
        for (int i = 0; i < tokens.length; i++) {
          print('   │  $i. ${tokens[i]}');
        }

        // Save to SharedPreferences
        final saveResult = await prefs.setStringList(_tokenStorageKey, tokens);
        print('   ├─ Save result: $saveResult');

        // Verify save by reading back immediately
        final verifyTokens = prefs.getStringList(_tokenStorageKey) ?? [];
        print(
          '   ├─ Verification - tokens in prefs NOW: ${verifyTokens.length}',
        );
        for (int i = 0; i < verifyTokens.length; i++) {
          print('   │  $i. ${verifyTokens[i]}');
        }

        print('   ├─ Total tokens now: ${tokens.length}');
        print('   └─ ✅ Token stored successfully');
        return true;
      } else {
        print('   ├─ Token already exists in storage: $token');
        print('   └─ ✅ No duplicate added');
        return true;
      }
    } catch (e) {
      print('❌ [RewardService] ERROR STORING TOKEN');
      print('   ├─ Error: $e');
      print('   └─ Error Type: ${e.runtimeType}');
      return false;
    }
  }

  /// Get all stored reward tokens
  Future<List<String>> getStoredTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      print('═══════════════════════════════════════════════════════════');
      print('📋 [RewardService] FETCHING ALL SAVED TOKENS');

      // Get the key info
      final allKeys = prefs.getKeys();
      print('   ├─ All SharedPreferences keys: $allKeys');

      // Get the token list
      final tokens = prefs.getStringList(_tokenStorageKey) ?? [];

      print('   ├─ Storage key being used: $_tokenStorageKey');
      print('   ├─ Total tokens stored: ${tokens.length}');

      if (tokens.isNotEmpty) {
        print('   ├─ Saved tokens:');
        for (int i = 0; i < tokens.length; i++) {
          print('   │  $i. ${tokens[i]}');
        }
      } else {
        print('   ├─ No tokens stored yet');
      }
      print('   └─ ✅ Fetch complete');
      print('═══════════════════════════════════════════════════════════');

      return tokens;
    } catch (e) {
      print('❌ Error getting tokens: $e');
      return [];
    }
  }

  /// Get first available token (for AI generation)
  Future<String?> getFirstToken() async {
    try {
      final tokens = await getStoredTokens();
      return tokens.isNotEmpty ? tokens.first : null;
    } catch (e) {
      print('❌ Error getting first token: $e');
      return null;
    }
  }

  /// Remove token from storage after use
  Future<bool> removeToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> tokens = prefs.getStringList(_tokenStorageKey) ?? [];
      tokens.remove(token);
      await prefs.setStringList(_tokenStorageKey, tokens);
      print('✅ Token removed from SharedPreferences');
      return true;
    } catch (e) {
      print('❌ Error removing token: $e');
      return false;
    }
  }

  /// Clear all tokens
  Future<bool> clearAllTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenStorageKey);
      print('✅ All tokens cleared from SharedPreferences');
      return true;
    } catch (e) {
      print('❌ Error clearing tokens: $e');
      return false;
    }
  }
}

final rewardService = RewardService();
