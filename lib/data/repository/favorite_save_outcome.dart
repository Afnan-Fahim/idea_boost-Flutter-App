import 'package:ideaboost/data/repository/favorites_repository.dart';

/// Result of a favorites save operation, including the Firestore document id.
class FavoriteSaveOutcome {
  const FavoriteSaveOutcome({
    required this.result,
    required this.itemId,
  });

  final SaveFavoriteResult result;
  final String itemId;

  bool get isSuccess =>
      result == SaveFavoriteResult.saved ||
      result == SaveFavoriteResult.updated;
}
