/// lib/core/prompt_system/INTEGRATION_GUIDE.md
/// 
/// How to integrate the PromptHandler into your 5 Generators
/// 
/// QUICK START:
/// 1. Import PromptHandler
/// 2. Create a PromptRequest with VM parameters
/// 3. Call PromptHandler.handlePromptRequest()
/// 4. Get back a PromptResult ready for AiRepository

# Prompt Handler Integration Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ VIEWMODEL LAYER                                             │
│ (ScriptGeneratorViewModel, CommentGeneratorViewModel, etc) │
│ Collects user input, options, parameters                   │
└────────────────┬────────────────────────────────────────────┘
                 │ PromptRequest
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ PROMPT HANDLER LAYER                                        │
│ PromptHandler + PromptBuilder + Validators                 │
│ Applies 5 priority levels systematically                   │
└────────────────┬────────────────────────────────────────────┘
                 │ PromptResult
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ BACKEND INTEGRATION LAYER                                   │
│ AiRepository → Cloud Functions (executeAiGeneration)       │
│ Final prompt sent with all context                         │
└─────────────────────────────────────────────────────────────┘
```

## Priority Hierarchy

1. **LANGUAGE** (Foundation) - All prompts built on this foundation
2. **PLATFORM, TONE, USER INPUT, JSON STRUCTURE** - From ViewModels
3. **LOCALE BEHAVIOR** - Regional/cultural adaptation
4. **RELEVANCE** - Domain, audience, conversation history
5. **JSON FORMATTING & CONSTRAINTS** - Strict validation rules

## Integration Steps

### Step 1: Import the PromptHandler

```dart
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_context.dart';
```

### Step 2: Create a PromptRequest in Your ViewModel

```dart
class ScriptGeneratorViewModel extends ChangeNotifier {
  
  Future<void> _generateScriptWithAI(
    String basePrompt, {
    String language = 'en',
    required String locale,
  }) async {
    try {
      // Build PromptRequest with all Priority 2 data
      final request = PromptRequest(
        platform: _selectedPlatform,    // Priority 2
        tone: _selectedEmotion,          // Priority 2
        userPrompt: basePrompt,          // Priority 2
        parameters: {                    // Priority 2
          'length': _selectedLength,
          'variation': _selectedVariation,
          'audienceType': 'general_audience',
        },
        jsonStructure: {                 // Priority 2
          'hook': 'string',
          'voiceover': 'string',
          'shots': 'array',
          'cta': 'string',
          'hashtags': 'array',
        },
        rewardGrantToken: _rewardGrantToken,
        quality: 'nano',
      );

      // ✨ MAGIC: Let PromptHandler handle everything!
      final promptHandler = PromptHandler();
      final promptResult = await promptHandler.handlePromptRequest(
        language: language,
        userPrompt: basePrompt,
        request: request,
        locale: locale,
        generatorType: 'script',  // Which of the 5 generators
      );

      // Validation check
      if (!promptResult.isValid) {
        throw Exception('Prompt validation failed: ${promptResult.errorSummary}');
      }

      // Now send the polished prompt to backend!
      final response = await _aiRepository.generateAi(
        prompt: promptResult.finalPrompt,  // Use the assembled prompt
        quality: request.quality ?? 'nano',
        locale: locale,
        language: language,
        conversationHistory: request.conversationHistory,
        rewardGrantToken: request.rewardGrantToken,
      );
      
      // Parse response...
      
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}
```

### Step 3: Use in Other Generators

Same pattern for all 5 generators! Just change the generator type:

```dart
// In CommentGeneratorViewModel
final promptResult = await promptHandler.handlePromptRequest(
  language: language,
  userPrompt: userPromptText,
  request: PromptRequest(
    tone: selectedTone,
    platform: 'instagram',
    // ... other fields
  ),
  locale: locale,
  generatorType: 'comment',  // ← Change this
);

// In HashtagGeneratorViewModel
final promptResult = await promptHandler.handlePromptRequest(
  // ...
  generatorType: 'hashtag',  // ← Change this
);

// In ViralRewriteViewModel
final promptResult = await promptHandler.handlePromptRequest(
  // ...
  generatorType: 'viral_rewrite',  // ← Change this
);

// In ShotIdeasViewModel
final promptResult = await promptHandler.handlePromptRequest(
  // ...
  generatorType: 'shot_ideas',  // ← Change this
);
```

## What Happens Inside PromptHandler

### 1. Build PromptContext
- Applies Priority 1 (Language)
- Applies Priority 2 (Platform, tone, user input)
- Applies Priority 3 (Locale, RTL)
- Applies Priority 4 (Domain, audience)
- Applies Priority 5 (JSON constraints)

### 2. Select Template
Based on generator type (script, comment, hashtag, viral_rewrite, shot_ideas), the appropriate template formats the base prompt with generator-specific logic.

### 3. Build Final Prompt
PromptBuilder layers all 5 priorities into the final prompt string in the correct order.

### 4. Validate Against Constraints
JsonValidator checks:
- Max tokens
- Response format (JSON)
- Required fields
- Array length limits
- Value constraints

### 5. Return PromptResult
```dart
class PromptResult {
  String finalPrompt;                    // Final assembled prompt
  Map<String, dynamic> appliedContext;  // What was applied
  String? executionInstructions;        // Backend instructions
  bool isValid;                         // Passed validation?
  List<String> validationErrors;        // Any errors?
}
```

## Error Handling

```dart
final promptResult = await promptHandler.handlePromptRequest(...);

if (promptResult.hasErrors) {
  print('Validation errors:');
  print(promptResult.errorSummary);
  return;
}

// Safe to use
_usePrompt(promptResult.finalPrompt);
```

## Advanced: Custom Constraints

### Adding JSON Constraints to PromptRequest

```dart
final request = PromptRequest(
  jsonStructure: {
    'hook': 'brief attention-grabbing opening',
    'voiceover': 'main script dialogue',
    'shots': 'list of scene descriptions',
    'cta': 'call to action',
    'hashtags': 'relevant hashtags',
  },
  jsonConstraints: {
    'max_tokens': 500,
    'response_format': 'json',
    'required_fields': ['hook', 'voiceover', 'shots', 'cta'],
    'array_length_limit': 5,
    'value_constraints': {
      'hook': {'max_length': 100},
      'cta': {'max_length': 50},
    },
  },
  // ... other fields
);
```

## Debugging

### View All Priorities Being Applied

```dart
debugPrint(promptResult.appliedContext.toString());
// or in PromptContext:
final context = buildPromptContext(...);
print(context.debugPriorities());
```

### Monitor Handler Flow

```dart
promptHandler.debugShowFlow('script', request);
// Output: Shows RequestType, Platform, Tone, Quality, etc.
```

## Performance Considerations

- **PromptHandler is a singleton** - Only one instance in memory
- **No async operations** - Fast, synchronous prompt assembly
- **Minimal allocations** - Only creates PromptContext, PromptResult, strings
- **Validator is lazy** - Only validates if constraints are provided

## Testing PromptHandler

```dart
// Example unit test
void main() {
  group('PromptHandler', () {
    test('builds prompt with all priorities', () async {
      final handler = PromptHandler();
      final request = PromptRequest(
        platform: 'instagram',
        tone: 'friendly',
        userPrompt: 'Create content about cooking',
      );

      final result = await handler.handlePromptRequest(
        language: 'en',
        userPrompt: 'Create content about cooking',
        request: request,
        locale: 'en-US',
        generatorType: 'script',
      );

      expect(result.isValid, true);
      expect(result.finalPrompt, contains('instagram'));
      expect(result.finalPrompt, contains('friendly'));
    });
  });
}
```

## Migration Checklist

- [ ] Create PromptRequest in all 5 ViewModels
- [ ] Replace direct prompt building with handlePromptRequest()
- [ ] Update AiRepository calls to use promptResult.finalPrompt
- [ ] Test each generator (script, comment, hashtag, viral, shots)
- [ ] Verify no regression in output quality
- [ ] Check with RTL languages (Arabic, Hebrew)
- [ ] Validate JSON structure in responses

## Support for Future Generators

The system is designed to easily extend to new generators:

1. Create a new template class extending `PromptTemplate`
2. Add case to `PromptTemplateFactory.createTemplate()`
3. Update generator list in factory
4. Use same `handlePromptRequest()` flow

```dart
class NewGeneratorTemplate implements PromptTemplate {
  @override
  String get templateName => 'NewGenerator';
  
  @override
  String buildBasePrompt(PromptContext context) {
    return 'Your specific prompt structure...';
  }
}
```

---

**This system ensures consistent, priority-based prompt generation across all 5 generators while remaining minimal, smart, and maintainable.**
