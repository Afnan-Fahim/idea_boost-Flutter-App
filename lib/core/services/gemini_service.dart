import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

class GeminiService {
  // TODO: Move to Firebase Remote Config or secure environment variable
  static const String _apiKey = ""; 
  static const String _baseUrl =
      "https://api.groq.com/openai/v1/chat/completions";

  /// Send a prompt to Groq API and get the response
  /// Returns the generated text content
  /// Throws an exception with specific message for abuse/illegal content
  static Future<String> generateContent(String prompt) async {
    try {
      final url = Uri.parse(_baseUrl);

      final requestBody = {
        "model": "openai/gpt-oss-120b",
        "messages": [
          {"role": "user", "content": prompt},
        ],
      };

      print('🔵 Groq API Request: Sending prompt (${prompt.length} chars)');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
              "Groq API request timed out after 60 seconds",
            ),
          );

      print('🔵 Groq API Response: Status code ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        // Check if choices exist
        if (responseData['choices'] == null ||
            responseData['choices'].isEmpty) {
          throw Exception(
            'errors.content_blocked_ai'.tr(),
          );
        }

        final choice = responseData['choices'][0];

        if (choice['message'] != null && choice['message']['content'] != null) {
          final text = choice['message']['content'];
          print('✅ Groq API Success: Received ${text?.length ?? 0} chars');
          print(
            '✅ Response preview: ${text?.substring(0, min(100, text?.length ?? 0)) ?? "empty"}',
          );
          return text ?? '';
        }

        throw Exception('Invalid response format from Groq API');
      } else if (response.statusCode == 429) {
        throw Exception(
          'Groq API rate limit exceeded. Please try again later.',
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Invalid Groq API key. Please check your credentials.');
      } else {
        throw Exception(
          'Groq API error: ${response.statusCode} - ${response.body}',
        );
      }
    } on TimeoutException catch (e) {
      throw Exception('Request timeout: ${e.message}');
    } catch (e) {
      rethrow; // Re-throw to preserve the exception type
    }
  }

  /// Stream content generation (for future streaming implementation)
  /// Currently returns the full content at once
  static Future<Stream<String>> generateContentStream(String prompt) async {
    return Stream.value(await generateContent(prompt));
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
