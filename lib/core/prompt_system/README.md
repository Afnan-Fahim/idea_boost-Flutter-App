/// lib/core/prompt_system/README.md
/// 
/// Prompt System Documentation - Smart, Minimal Approach to Prompt Generation

# Prompt System Architecture

## Overview

The Prompt System is a centralized, priority-based framework for generating AI prompts across IdeaBoost's 5 generators. It treats prompt construction as a systematic, layered process where each priority level builds upon the previous one.

**Design Philosophy:** Smart and minimal - no bloat, maximum clarity.

## The 5 Priority Levels

### Priority 1️⃣: LANGUAGE (Foundation)

**Status:** Foundation/Core
**Set by:** System (device locale, user preferences)
**Purpose:** Language is the base upon which everything sits

Every prompt is built in a specific language. This affects:
- How instructions are written
- Cultural assumptions
- Format conventions
- Localization behavior

**Examples:**
- 'en' (English)
- 'es' (Spanish)
- 'ar' (Arabic - RTL)
- 'fr' (French)
- 'ru' (Russian)
- 'hi' (Hindi)

### Priority 2️⃣: PLATFORM, TONE, USER INPUT, JSON STRUCTURE

**Status:** Highest user-controlled priority
**Set by:** ViewModels (from user selections + UI input)
**Purpose:** Direct requirements from user choices

These are the concrete specifications that come from what the user selected:

- **Platform:** Where content will be distributed (instagram, tiktok, youtube, twitter, facebook)
- **Tone:** Style preference (friendly, humorous, dramatic, sophisticated, engaging_question)
- **User Prompt:** The actual user input/idea/request
- **JSON Structure:** How the response should be formatted

**Example from ScriptGeneratorViewModel:**
```dart
platform: 'instagram'
tone: 'humorous'
userPrompt: 'A video about learning to code'
jsonStructure: {
  'hook': 'opening that grabs attention',
  'voiceover': 'main script',
  'shots': 'list of scenes',
  'cta': 'call to action',
  'hashtags': 'relevant tags'
}
```

**Example from CommentGeneratorViewModel:**
```dart
tone: 'engaging_question'
platform: 'instagram'
userPrompt: 'React to this cooking video'
parameters: {
  'selectedTones': ['friendly', 'humorous'],
  'platform': 'instagram'
}
```

### Priority 3️⃣: LOCALE BEHAVIOR

**Status:** Regional/cultural adaptation
**Set by:** System + context
**Purpose:** Adapt to user's region and culture

Handles regional variations and cultural appropriateness:

- **Locale:** Full locale tag with region ('en-US', 'en-GB', 'es-ES', 'es-MX', 'ar-SA', 'ru-RU')
- **RTL Support:** Right-to-left formatting for Arabic, Hebrew, Farsi, Urdu
- **Cultural Context:** Region-specific preferences and conventions

**Currently:** Handled by backend's executeAiGeneration()
**Future:** Will be fully managed in this handler

**Examples:**
```
locale: 'en-US'      → American English, date format MM/DD/YYYY
locale: 'en-GB'      → British English, date format DD/MM/YYYY
locale: 'ar-SA'      → Arabic (Saudi Arabia), RTL direction
locale: 'es-MX'      → Mexican Spanish, cultural nuances
locale: 'ru-RU'      → Russian, Cyrillic, cultural context
locale: 'hi-IN'      → Hindi (India), specific cultural norms
```

### Priority 4️⃣: RELEVANCE

**Status:** Context for better matching
**Set by:** System + conversation history
**Purpose:** Make output more relevant to user's domain/audience

- **Domain:** What category is this content for? (video_content, social_engagement, content_optimization, creative_ideation)
- **Audience Type:** Who is this for? (youth, general_audience, professionals, students)
- **Conversation History:** Previous exchanges/context for continuation

**Examples:**
```
domain: 'video_content' + audience: 'youth' 
  → Language, examples, tone matches TikTok/YouTube shorts audience

domain: 'content_optimization' + audience: 'professionals'
  → Sophisticated language, business-focused examples

domain: 'creative_ideation' + audience: 'students'
  → Accessible, educational tone
```

### Priority 5️⃣: JSON FORMATTING & CONSTRAINTS

**Status:** Technical requirements
**Set by:** Generator template + system
**Purpose:** Enforce strict output validation

Ensures responses are well-formatted and meet requirements:

- **Response Format:** Must be valid JSON
- **Required Fields:** Which keys must be present
- **Array Length Limits:** Max items in arrays
- **Value Constraints:** Max lengths, enum values, patterns
- **Token Limits:** Max tokens for response

**Example:**
```dart
jsonConstraints: {
  'max_tokens': 500,
  'response_format': 'json',
  'required_fields': ['hook', 'voiceover', 'shots', 'cta'],
  'array_length_limit': 5,
  'value_constraints': {
    'hook': {'max_length': 100},
    'cta': {'max_length': 50},
  }
}
```

## File Structure

```
lib/core/prompt_system/
├── prompt_handler.dart              # Main orchestrator
├── prompt_template.dart             # Templates for 5 generators
├── models/
│   ├── prompt_request.dart         # Input from ViewModels
│   ├── prompt_context.dart         # All context with priorities
│   └── prompt_result.dart          # Final output
├── validators/
│   └── json_validator.dart         # Priority 5 validation
├── INTEGRATION_GUIDE.md             # How to use
└── README.md                        # This file
```

## Flow Diagram

```
User Input (ViewModel)
        ↓
   (Platform, Tone, User Prompt)
        ↓
CREATE PromptRequest ← Priority 2 data
        ↓
CALL promptHandler.handlePromptRequest()
        ↓
BUILD PromptContext
├─ Priority 1: Language ← Set by system
├─ Priority 2: Platform, tone, user input
├─ Priority 3: Locale, RTL, cultural context
├─ Priority 4: Domain, audience, history
└─ Priority 5: JSON constraints
        ↓
SELECT PromptTemplate ← Based on generator type
        ↓
BUILD PromptBuilder ← Assembles all 5 priorities
        ↓
VALIDATE JsonValidator ← Checks Priority 5 constraints
        ↓
CREATE PromptResult
├─ finalPrompt ← Ready for backend
├─ appliedContext ← What was applied
└─ validationErrors ← Any issues?
        ↓
Send to AiRepository → generateAi()
```

## Integration Example: Script Generator

```dart
class ScriptGeneratorViewModel extends ChangeNotifier {
  
  Future<void> generateScript(String idea) async {
    // Step 1: Create PromptRequest with Priority 2 data
    final request = PromptRequest(
      platform: 'instagram',           // Priority 2
      tone: 'humorous',                // Priority 2
      userPrompt: idea,                // Priority 2
      parameters: {
        'length': 'short',
        'variation': 'comedy',
      },
      jsonStructure: {                 // Priority 2
        'hook': '',
        'voiceover': '',
        'shots': [],
        'cta': '',
        'hashtags': []
      },
      quality: 'nano',
    );

    // Step 2: Let PromptHandler do the heavy lifting!
    final handler = PromptHandler();
    final result = await handler.handlePromptRequest(
      language: 'en',                  // Priority 1
      userPrompt: idea,
      request: request,
      locale: 'en-US',                 // Priority 3
      generatorType: 'script',
    );

    // Step 3: Check if valid
    if (!result.isValid) {
      _errorMessage = result.errorSummary;
      notifyListeners();
      return;
    }

    // Step 4: Use the polished prompt!
    final response = await _aiRepository.generateAi(
      prompt: result.finalPrompt,  // ← Magic assembled prompt
      quality: 'nano',
      locale: 'en-US',
      language: 'en',
    );

    // Parse and display response...
  }
}
```

## Key Features

### ✨ Smart
- Automatically handles complex priority interactions
- Detects RTL languages and applies proper formatting
- Extracts domain from generator type
- Validates JSON structure before sending

### 🎯 Minimal
- Single file integration (PromptRequest → handlePromptRequest())
- No configuration overhead
- No template boilerplate
- Singleton pattern (one instance)

### 🔧 Extensible
- Easy to add new generators (just extend PromptTemplate)
- New priority levels can be added without breaking existing code
- Validators can be extended for new constraints
- Plugin architecture for custom templates

### 📊 Debuggable
- Print priority hierarchy with `context.debugPriorities()`
- Show flow with `handler.debugShowFlow()`
- Detailed error messages
- Full context available in PromptResult

## Testing

```dart
test('Script generator applies all 5 priorities', () async {
  final handler = PromptHandler();
  
  final request = PromptRequest(
    platform: 'instagram',
    tone: 'humorous',
    userPrompt: 'Create a funny video about coding',
  );

  final result = await handler.handlePromptRequest(
    language: 'en',
    userPrompt: 'Create a funny video about coding',
    request: request,
    locale: 'en-US',
    generatorType: 'script',
  );

  // Verify all priorities were applied
  expect(result.finalPrompt, contains('english')); // Priority 1
  expect(result.finalPrompt, contains('instagram')); // Priority 2
  expect(result.finalPrompt, contains('humorous')); // Priority 2
  expect(result.finalPrompt, contains('en-US')); // Priority 3
  expect(result.isValid, true); // Priority 5
});
```

## Performance

- **No async operations** - Everything is synchronous/fast
- **Minimal allocations** - Only creates necessary objects
- **Singleton pattern** - One instance across app
- **Lazy validation** - Only validates if constraints exist

## Future Enhancements

1. **Prompt Caching** - Cache successfully generated prompts
2. **A/B Testing** - Compare different priority orderings
3. **Learning** - Track which prompts generate best responses
4. **Custom Rules** - Allow app to define custom priority rules
5. **Multilingual** - Better support for code-switching scenarios
6. **Analytics** - Track what priorities most affect quality

## Summary

The Prompt System is a foundation for smart, systematic prompt generation. By understanding the 5 priorities and how they layer together, you can generate better prompts, debug issues faster, and extend the system for future needs.

**Remember:** Language first, user choices second, then context, relevance, and technical constraints.
