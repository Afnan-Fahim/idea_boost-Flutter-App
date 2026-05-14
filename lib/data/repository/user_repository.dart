// lib/data/repository/user_repository.dart

import 'package:flutter/material.dart';
import 'package:ideaboost/data/models/comments_model.dart';
import 'package:ideaboost/data/models/user_model.dart';
import 'package:ideaboost/core/services/user_service.dart';
import 'package:ideaboost/core/services/user_access_service.dart';
import 'package:ideaboost/core/services/admob_service.dart';

class UserRepository {
  final UserService _userService;
  final UserAccessService _accessService = UserAccessService();

  UserRepository(this._userService);

  // Save to favorites
  Future<void> saveCommentOutputToFavorites(CommentOutput output) async {
    await _userService.saveToFavorites(output);
  }

  // Save to history (generic) - keeps old comment flow separate
  Future<void> saveGenerationLog(CommentOutput output) async {
    // Preserve compatibility for callers that pass CommentOutput
    await _userService.saveMapToHistory(
      type: 'comment_generator',
      prompt: output.inputText,
      output: output.toJson(),
    );
  }

  Future<void> saveHistoryEntry({
    required String type,
    required String prompt,
    required Map<String, dynamic> output,
    Map<String, dynamic>? meta,
    DateTime? generatedAt,
  }) async {
    await _userService.saveMapToHistory(
      type: type,
      prompt: prompt,
      output: output,
      meta: meta,
      generatedAt: generatedAt,
    );
  }

  // Backwards-compatible alias expected by some callers
  Future<void> saveHistoryGeneric({
    required String type,
    String? prompt,
    String? input,
    required Map<String, dynamic> output,
    Map<String, dynamic>? meta,
    DateTime? generatedAt,
  }) async {
    // Accept either `prompt` or `input` as the caller might use either name.
    final resolvedPrompt = prompt ?? input ?? '';
    return await saveHistoryEntry(
      type: type,
      prompt: resolvedPrompt,
      output: output,
      meta: meta,
      generatedAt: generatedAt,
    );
  }

  // Stream user data in real-time
  // Stream<UserModel?> getUserStream() {
  //   return _accessService.getUserStream();
  // }

  // Get current user data
  Future<UserModel?> getCurrentUser() async {
    return await _accessService.getCurrentUser();
  }

  // Force reload current user data from Firestore (bypasses any cache)
  Future<UserModel?> reloadCurrentUser() async {
    return await _accessService.getCurrentUser();
  }

  // Get access status (trial, rewarded, blocked, etc.)
  Future<Map<String, dynamic>> getAccessStatus() async {
    return await _accessService.getAccessStatus();
  }

  // Check if limit exceeded
  Future<bool> checkDailyLimitExceeded() async {
    return await _accessService.checkDailyLimitExceeded();
  }

  // Deduct one normal generation (no-op - backend handles this)
  Future<void> deductUsage() async {
    // Backend automatically increments counters
    // This is a no-op for backwards compatibility
    return;
  }

  // Get recent history
  Future<List<Map<String, dynamic>>> getRecentHistory({int limit = 6}) async {
    return await _userService.getRecentHistory(limit: limit);
  }

  /// Centralized method: Check if user needs to watch ad before generation
  /// If ad required: shows ad, gets token from backend, returns token
  /// If no ad required: returns null (user can proceed immediately)
  /// If user cancels ad or ad fails: returns null
  Future<String?> ensureAdRequirementMetAndGetToken(
    BuildContext context,
    AdMobService adMobService,
  ) async {
    try {
      // Step 1: Get access status to see if ad is required
      final accessStatus = await getAccessStatus();
      final requiresAd = accessStatus['requiresAd'] as bool? ?? false;

      print('🎯 Ad requirement check: requiresAd=$requiresAd');

      if (!requiresAd) {
        // No ad required - user can proceed immediately
        print('✅ No ad required, user can proceed');
        return null;
      }

      // Step 2: Ad is required - show rewarded ad
      print('🎬 Ad required, showing rewarded ad...');

      final token = await adMobService.showRewardedAd(
        context: context,
        onRewarded: () {
          print('✅ User earned reward');
        },
      );

      if (token == null || token.isEmpty) {
        print('⚠️ No token received, user cannot proceed');
        return null;
      }

      print('✅ Token received: ${token.substring(0, 20)}...');
      return token;
    } catch (e) {
      print('❌ Error in ad requirement check: $e');
      return null;
    }
  }
}
