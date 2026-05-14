/// Utility for reporting JSON parse failures back to server
/// This allows the backend to rollback token consumption when client can't parse response

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ParseFailureReporter {
  static const String _baseUrl =
      'https://us-central1-ideaboost-e89fc.cloudfunctions.net';

  /// Report a JSON parsing failure to the backend
  /// The backend will then rollback the consumption counter
  ///
  /// This is called when:
  /// - Client receives a 200 response but can't parse the JSON
  /// - JSON repair utilities (ensureValidJson) failed to produce valid JSON
  /// - The response is beyond recovery
  static Future<bool> reportParseFailure({
    required String parseErrorMessage,
    required String responsePreview,
    int? responseLength,
    String? requestId,
  }) async {
    try {
      debugPrint(
        '📛 Reporting JSON parse failure to backend: $parseErrorMessage',
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ Cannot report parse failure: User not authenticated');
        return false;
      }

      final token = await user.getIdToken(true);
      final dio = Dio(
        BaseOptions(baseUrl: _baseUrl, contentType: 'application/json'),
      );

      final response = await dio.post(
        '/reportParseFailure',
        data: {
          'parseErrorMessage': parseErrorMessage,
          'responsePreview': responsePreview,
          'responseLength': responseLength ?? 0,
          'requestId': requestId,
          'reportedAt': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        debugPrint(
          '✅ Parse failure reported successfully | Method: ${data['method']}',
        );
        return true;
      }

      debugPrint('⚠️ Parse failure report returned non-success response');
      return false;
    } catch (e) {
      debugPrint('❌ Failed to report parse failure: $e');
      // Don't throw - this is a best-effort operation
      // If reporting fails, the user has lost a generation but at least we tried
      return false;
    }
  }
}
