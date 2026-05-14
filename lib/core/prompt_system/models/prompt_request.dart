/// lib/core/prompt_system/models/prompt_request.dart
///
/// Represents the request data sent from ViewModels to the Prompt Handler.
/// This is Priority 2: Platform, tone, user prompt, JSON structure from local models.

class PromptRequest {
  /// 📌 PRIORITY 2: Platform where content will be used
  /// Examples: 'instagram', 'tiktok', 'youtube', 'twitter', 'facebook'
  final String? platform;

  /// 📌 PRIORITY 2: Tone/style of content
  /// Examples: 'friendly', 'humorous', 'dramatic', 'sophisticated'
  final String? tone;

  /// 📌 PRIORITY 2: User's direct input/prompt
  final String? userPrompt;

  /// 📌 PRIORITY 2: Additional contextual parameters
  /// Examples: length, variation, emotion, style preferences
  final Map<String, dynamic>? parameters;

  /// 📌 PRIORITY 2: JSON-formatted request structure
  /// Used when the request itself needs strict JSON formatting
  final Map<String, dynamic>? jsonStructure;

  /// Conversation history for context awareness (optional)
  final List<Map<String, dynamic>>? conversationHistory;

  /// Reward token if user has claimed a free reward
  final String? rewardGrantToken;

  /// Quality tier for backend routing
  final String? quality;

  PromptRequest({
    this.platform,
    this.tone,
    this.userPrompt,
    this.parameters,
    this.jsonStructure,
    this.conversationHistory,
    this.rewardGrantToken,
    this.quality,
  });

  /// Creates a copy with some fields replaced
  PromptRequest copyWith({
    String? platform,
    String? tone,
    String? userPrompt,
    Map<String, dynamic>? parameters,
    Map<String, dynamic>? jsonStructure,
    List<Map<String, dynamic>>? conversationHistory,
    String? rewardGrantToken,
    String? quality,
  }) {
    return PromptRequest(
      platform: platform ?? this.platform,
      tone: tone ?? this.tone,
      userPrompt: userPrompt ?? this.userPrompt,
      parameters: parameters ?? this.parameters,
      jsonStructure: jsonStructure ?? this.jsonStructure,
      conversationHistory: conversationHistory ?? this.conversationHistory,
      rewardGrantToken: rewardGrantToken ?? this.rewardGrantToken,
      quality: quality ?? this.quality,
    );
  }

  @override
  String toString() {
    return 'PromptRequest('
        'platform: $platform, '
        'tone: $tone, '
        'userPrompt: ${userPrompt?.substring(0, 50) ?? "null"}..., '
        'platform: $platform'
        ')';
  }
}
