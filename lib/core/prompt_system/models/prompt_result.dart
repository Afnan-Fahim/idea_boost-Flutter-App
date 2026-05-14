/// lib/core/prompt_system/models/prompt_result.dart
///
/// The final assembled prompt result ready to send to the backend.

class PromptResult {
  /// The finalized prompt string to send to backend
  final String finalPrompt;

  /// The context that was used to generate this prompt
  final Map<String, dynamic> appliedContext;

  /// Instructions for backend execution
  final String? executionInstructions;

  /// Timestamp of generation
  final DateTime generatedAt;

  /// Whether this prompt passed validation
  final bool isValid;

  /// Validation errors if any
  final List<String> validationErrors;

  PromptResult({
    required this.finalPrompt,
    required this.appliedContext,
    this.executionInstructions,
    DateTime? generatedAt,
    this.isValid = true,
    this.validationErrors = const [],
  }) : generatedAt = generatedAt ?? DateTime.now();

  /// Check if prompt has any validation errors
  bool get hasErrors => validationErrors.isNotEmpty;

  /// Get all validation error messages
  String get errorSummary => validationErrors.join('\n');

  @override
  String toString() {
    return '''
═══════════════════════════════════════════════════════════════
🎯 PROMPT RESULT
═══════════════════════════════════════════════════════════════
✅ Valid: $isValid
⏰ Generated: $generatedAt
📝 Prompt Length: ${finalPrompt.length} chars
${executionInstructions != null ? '📋 Instructions: $executionInstructions' : ''}
${hasErrors ? '❌ Errors: $errorSummary' : ''}
═══════════════════════════════════════════════════════════════
''';
  }
}
