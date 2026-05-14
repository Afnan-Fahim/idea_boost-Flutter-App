// lib/modules/idea_details/view_model/idea_details_view_model.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ideaboost/data/models/idea_model.dart';
import 'package:ideaboost/data/repository/favorites_repository.dart';
import 'package:ideaboost/data/repository/user_repository.dart';
import 'package:ideaboost/core/services/user_service.dart';

class IdeaDetailsViewModel extends ChangeNotifier {
  final IdeaModel idea;

  final UserRepository _userRepository = UserRepository(UserService());
  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  bool _isFavorited = false;
  bool get isFavorited => _isFavorited;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  IdeaDetailsViewModel(this.idea);

  // Expose a safe setter for UI to update the flag without touching private state
  void setFavorited(bool value) {
    _isFavorited = value;
    notifyListeners();
  }

  /// ============================
  /// Methods needed by old screen
  /// ============================
  Future<bool> checkIfFavorited(String itemId) async {
    // Key is not used here because favorites are stored by idea.id
    return await isIdeaFavorited(itemId);
  }

  Future<bool> checkIfFavoritedWithType(
    String itemId, {
    bool isRefined = false,
    IdeaModel? originalIdea,
  }) async {
    if (isRefined && originalIdea != null) {
      // For refined ideas, check using the derived ID and proper type
      String refinedType = 'ai_refined';
      if (originalIdea.dataset == 'youth') {
        refinedType = 'ai_refined_youth';
      } else if (originalIdea.dataset == 'seasonal') {
        refinedType = 'ai_refined_seasonal';
      }
      final refinedItemId = '${originalIdea.id}_refined';
      final item = await _favoritesRepository.getFavoriteItem(
        refinedType,
        refinedItemId,
      );
      return item != null;
    } else {
      // For normal ideas, check the standard idea_details types
      return await isIdeaFavorited(itemId);
    }
  }

  Future<SaveFavoriteResult> addToFavorites(IdeaModel ideaModel) async {
    // Optimistic update - change UI immediately
    _isFavorited = true;
    notifyListeners();

    try {
      // Determine type based on dataset
      String favoriteType = 'idea_details';
      if (ideaModel.dataset == 'youth') {
        favoriteType = 'youth_ideas';
      } else if (ideaModel.dataset == 'seasonal') {
        favoriteType = 'seasonal_ideas';
      }

      final result = await _favoritesRepository.addIdeaDetailsToFavorites(
        id: ideaModel.id,
        title: ideaModel.title,
        description: ideaModel.description,
        niche: ideaModel.niche,
        format: ideaModel.format,
        level: ideaModel.level,
        steps: ideaModel.steps,
        cta: ideaModel.cta,
        timestamp:
            ideaModel.timestamp?.toIso8601String() ??
            DateTime.now().toIso8601String(),
        dataset: ideaModel.dataset,
        favoriteType: favoriteType,
      );
      notifyListeners();
      return result;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = false;
      _errorMessage = 'general.failed_save_favorite'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved;
    }
  }

  Future<SaveFavoriteResult> addRefinedToFavorites({
    required IdeaModel originalIdea,
    required IdeaModel refinedIdea,
  }) async {
    // Optimistic update - change UI immediately
    _isFavorited = true;
    notifyListeners();

    try {
      // Determine type based on original idea's dataset
      String refinedType = 'ai_refined';
      if (originalIdea.dataset == 'youth') {
        refinedType = 'ai_refined_youth';
      } else if (originalIdea.dataset == 'seasonal') {
        refinedType = 'ai_refined_seasonal';
      }

      // Use original idea ID as basis for refined idea ID to avoid duplicates on re-adding
      final refinedItemId = '${originalIdea.id}_refined';

      final result = await _favoritesRepository.addAiRefinedScriptToFavorites(
        itemId: refinedItemId,
        title: refinedIdea.title,
        originalScript: originalIdea.description,
        refinedScript: refinedIdea.description,
        dataset: refinedIdea.dataset,
        favoriteType: refinedType,
        groups: [
          {
            'type': refinedType,
            'originalTitle': originalIdea.title,
            'refinedTitle': refinedIdea.title,
            'originalDescription': originalIdea.description,
            'refinedDescription': refinedIdea.description,
            'refinedSteps': refinedIdea.steps,
            'refinedCta': refinedIdea.cta,
            'refinedLevel': refinedIdea.level,
            'generatedAt': DateTime.now().toIso8601String(),
          },
        ],
      );
      notifyListeners();
      return result;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = false;
      _errorMessage = 'errors.failed_to_save'.tr();
      notifyListeners();
      return SaveFavoriteResult.saved;
    }
  }

  Future<bool> removeFromFavorites(String type, String itemId) async {
    // Optimistic update - change UI immediately
    _isFavorited = false;
    notifyListeners();

    try {
      await _favoritesRepository.removeFromFavorites(type, itemId);
      return true;
    } catch (e) {
      // Revert optimistic update on failure
      _isFavorited = true;
      _errorMessage = 'errors.failed_to_remove'.tr();
      notifyListeners();
      return false;
    }
  }

  Future<bool> isIdeaFavorited(String itemId) async {
    // Check all three idea types: idea_details, youth_ideas, seasonal_ideas
    final ideaDetailsItem = await _favoritesRepository.getFavoriteItem(
      'idea_details',
      itemId,
    );
    if (ideaDetailsItem != null) return true;

    final youthIdeasItem = await _favoritesRepository.getFavoriteItem(
      'youth_ideas',
      itemId,
    );
    if (youthIdeasItem != null) return true;

    final seasonalIdeasItem = await _favoritesRepository.getFavoriteItem(
      'seasonal_ideas',
      itemId,
    );
    return seasonalIdeasItem != null;
  }

  /// ============================
  /// Daily action quota
  /// ============================
  Future<bool> consumeDailyAction() async {
    _errorMessage = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _errorMessage = 'errors.please_log_in'.tr();
      notifyListeners();
      return false;
    }
    // 🔒 Backend handles ALL quota check + deduction + rollback on failure
    // Client NEVER deducts or gates — server is the single source of truth
    return true;
  }

  // Future<void> grantRewardedGeneration() async {
  //   try {
  //     //await _userRepository.grantRewardedGeneration();
  //     notifyListeners();
  //   } catch (e) {
  //     _errorMessage = "${'general.failed_grant_reward'.tr()}: ${e.toString()}";
  //     notifyListeners();
  //   }
  // }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

/// Extension for timestamp compatibility
extension IdeaModelTimestampExtension on IdeaModel {
  DateTime? get timestamp {
    try {
      final dynamic value =
          (this as dynamic).createdAt ?? (this as dynamic).date;
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value);
    } catch (_) {}
    return null;
  }
}
