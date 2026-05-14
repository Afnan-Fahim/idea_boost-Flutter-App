/// lib/core/prompt_system/validators/json_validator.dart
///
/// Priority 5 Validator: Ensures strict JSON formatting and constraint compliance.
/// Validates that prompts include proper JSON formatting instructions and constraints.

import 'dart:convert';

class JsonValidator {
  /// Validate a prompt against JSON constraints
  ///
  /// Returns true if prompt satisfies all constraints, false otherwise.
  /// Accumulates errors in the provided [errors] list.

  bool validatePrompt(
    String prompt,
    Map<String, dynamic> constraints,
    List<String> errors,
  ) {
    bool isValid = true;

    // Constraint 1: Check max_tokens if specified
    if (constraints.containsKey('max_tokens')) {
      final maxTokens = constraints['max_tokens'] as int;
      // Rough estimate: 1 token ≈ 4 characters
      final estimatedTokens = prompt.length ~/ 4;
      if (estimatedTokens > maxTokens) {
        errors.add('Prompt exceeds max_tokens: $estimatedTokens > $maxTokens');
        isValid = false;
      }
    }

    // Constraint 2: Check response_format if specified
    if (constraints.containsKey('response_format')) {
      final formatValue = constraints['response_format'];
      final format = formatValue is String ? formatValue : null;
      if (format == 'json') {
        if (!_hasJsonFormatting(prompt)) {
          errors.add('Prompt missing JSON formatting instructions');
          isValid = false;
        }
      }
    }

    // Constraint 3: Validate required_fields if specified
    if (constraints.containsKey('required_fields')) {
      final fieldsValue = constraints['required_fields'];
      final fields = fieldsValue is List ? fieldsValue : null;
      if (fields != null) {
        final missingFields = _validateRequiredFields(prompt, fields);
        if (missingFields.isNotEmpty) {
          errors.add('Missing JSON fields: ${missingFields.join(", ")}');
          isValid = false;
        }
      }
    }

    // Constraint 4: Check array_length_limit if specified
    if (constraints.containsKey('array_length_limit')) {
      final limit = constraints['array_length_limit'] as int?;
      if (limit != null && !_validateArrayLimits(prompt, limit)) {
        errors.add('Prompt may violate array_length_limit: $limit');
        isValid = false;
      }
    }

    // Constraint 5: Check value_constraints if specified
    if (constraints.containsKey('value_constraints')) {
      final valueConstraints =
          constraints['value_constraints'] as Map<String, dynamic>?;
      if (valueConstraints != null) {
        final constraintErrors = _validateValueConstraints(
          prompt,
          valueConstraints,
        );
        if (constraintErrors.isNotEmpty) {
          errors.addAll(constraintErrors);
          isValid = false;
        }
      }
    }

    return isValid;
  }

  /// Check if prompt includes JSON formatting instructions
  bool _hasJsonFormatting(String prompt) {
    return prompt.contains('JSON') ||
        prompt.contains('json') ||
        prompt.contains('{') ||
        prompt.contains('[');
  }

  /// Validate required JSON fields are mentioned in prompt
  List<String> _validateRequiredFields(String prompt, List? fields) {
    final missingFields = <String>[];

    if (fields == null) return missingFields;

    for (final field in fields) {
      if (field is String) {
        // Check if field name appears in prompt
        if (!prompt.contains('"$field"') && !prompt.contains("'$field'")) {
          missingFields.add(field);
        }
      }
    }

    return missingFields;
  }

  /// Validate array length limits are reasonable
  bool _validateArrayLimits(String prompt, int limit) {
    // Simple heuristic: if prompt mentions array, check it's reasonable
    if (!prompt.contains('[') || !prompt.contains(']')) {
      return true; // No arrays mentioned
    }

    // If array is mentioned, ensure limit is reasonable (> 0)
    return limit > 0;
  }

  /// Validate value constraints
  List<String> _validateValueConstraints(
    String prompt,
    Map<String, dynamic> constraints,
  ) {
    final errors = <String>[];

    constraints.forEach((key, constraint) {
      if (constraint is Map<String, dynamic>) {
        // Check field length constraints
        if (constraint.containsKey('max_length')) {
          final maxLength = constraint['max_length'] as int?;
          if (maxLength != null && !_isReasonableLength(prompt, maxLength)) {
            errors.add('Field "$key" max_length constraint may be violated');
          }
        }

        // Check enum constraints
        if (constraint.containsKey('enum')) {
          final allowedValues = constraint['enum'] as List?;
          if (allowedValues != null) {
            final allMentioned = allowedValues.every(
              (val) => prompt.contains(val.toString()),
            );
            if (!allMentioned) {
              errors.add(
                'Field "$key" may not include all allowed enum values',
              );
            }
          }
        }
      }
    });

    return errors;
  }

  /// Check if max_length is reasonable for the prompt context
  bool _isReasonableLength(String prompt, int maxLength) {
    // If max_length is too small, it might be unreasonable
    return maxLength > 10; // Arbitrary minimum of 10 characters
  }

  /// Validate that a JSON string is properly formatted
  static bool isValidJson(String jsonString) {
    try {
      jsonDecode(jsonString);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Attempt to extract JSON from text (for robustness)
  static String? extractJsonFromText(String text) {
    // Try to find first { and last }
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');

    if (startIndex == -1 || endIndex == -1 || startIndex > endIndex) {
      return null;
    }

    final jsonString = text.substring(startIndex, endIndex + 1);
    return isValidJson(jsonString) ? jsonString : null;
  }

  /// Validate response structure matches expected JSON schema
  static bool validateResponseStructure(
    Map<String, dynamic> response,
    Map<String, dynamic> expectedStructure,
  ) {
    for (final key in expectedStructure.keys) {
      if (!response.containsKey(key)) {
        return false;
      }
    }
    return true;
  }
}
