/// lib/core/prompt_system/ARCHITECTURE_OVERVIEW.md
/// 
/// Complete system architecture and design patterns

# Prompt System - Complete Architecture Overview

## System Purpose

The Prompt System is a **centralized, priority-based framework** that sits between ViewModels and the AI backend. It treats prompt generation as a systematic process where each priority level builds upon the previous one, ensuring consistent, high-quality prompts across all 5 generators.

## Design Principles

### 1. **Smart & Minimal**
- Single entry point: `promptHandler.handlePromptRequest()`
- No boilerplate or configuration
- Self-documenting through clear naming
- Singleton pattern = one instance across app

### 2. **Priority-Based**
- 5 well-defined priority levels
- Each level has clear ownership (system vs ViewModel vs backend)
- Easy to understand and debug
- Can be extended without breaking existing code

### 3. **Separation of Concerns**
- **ViewModels:** Collect user input, create PromptRequest
- **PromptHandler:** Orchestrate the system, apply priorities
- **PromptBuilder:** Assemble final prompt string
- **Validators:** Check constraints
- **Backend:** Execute the generation

### 4. **Zero Runtime Configuration**
- No setup required
- No dependency injection needed
- Works immediately after import
- All configuration in code at compile time

## File Structure & Responsibilities

```
lib/core/prompt_system/
│
├── 📋 README.md
│   └── System overview and philosophy
│
├── 📥 INTEGRATION_GUIDE.md
│   └── How to integrate into ViewModels
│
├── ✅ IMPLEMENTATION_CHECKLIST.md
│   └── Step-by-step integration for 5 generators
│
├── 🏗️ ARCHITECTURE_OVERVIEW.md
│   └── This file - complete design documentation
│
├── 📍 prompt_handler.dart (CORE)
│   ├── PromptHandler (singleton) - Main orchestrator
│   │   └── handlePromptRequest() - Main entry point
│   │   └── _buildPromptContext() - Apply all priorities
│   │   └── _selectTemplate() - Choose generator template
│   │   └── _validatePrompt() - Run Priority 5 validation
│   │
│   ├── PromptBuilder - Assemble final prompt
│   │   └── buildPrompt() - Layer all 5 priorities
│   │   └── _addPriority2/3/4/5Enhancements() - Layer methods
│   │
│   └── Utilities
│       └── _contextToMap() - For debugging
│
├── 📑 prompt_template.dart (TEMPLATES)
│   ├── Abstract PromptTemplate
│   ├── ScriptGeneratorTemplate
│   ├── CommentGeneratorTemplate
│   ├── HashtagGeneratorTemplate
│   ├── ViralRewriteTemplate
│   ├── ShotIdeasTemplate
│   ├── DefaultPromptTemplate (fallback)
│   └── PromptTemplateFactory
│
├── 📊 models/
│   │
│   ├── prompt_request.dart
│   │   └── PromptRequest (data from ViewModels)
│   │       ├── platform, tone, userPrompt (Priority 2)
│   │       ├── parameters, jsonStructure (Priority 2)
│   │       ├── conversationHistory, rewardGrantToken
│   │       └── copyWith() for immutability
│   │
│   ├── prompt_context.dart
│   │   └── PromptContext (all context with priorities)
│   │       ├── language (Priority 1)
│   │       ├── platform, tone, userPrompt (Priority 2)
│   │       ├── locale, isRtl, culturalContext (Priority 3)
│   │       ├── domain, audienceType, history (Priority 4)
│   │       ├── jsonConstraints, enforceStrictJson (Priority 5)
│   │       ├── debugPriorities() - Show hierarchy
│   │       └── copyWith() for immutability
│   │
│   └── prompt_result.dart
│       └── PromptResult (final output)
│           ├── finalPrompt - Ready for backend
│           ├── appliedContext - What was applied
│           ├── executionInstructions - For backend
│           ├── isValid, validationErrors - Validation status
│           └── hasErrors, errorSummary - Error handling
│
└── ✔️ validators/
    │
    └── json_validator.dart
        └── JsonValidator (Priority 5 validator)
            ├── validatePrompt() - Main validation
            ├── _hasJsonFormatting() - Check JSON format
            ├── _validateRequiredFields() - Check fields
            ├── _validateArrayLimits() - Check arrays
            ├── _validateValueConstraints() - Check values
            └── Static utilities
                ├── isValidJson()
                ├── extractJsonFromText()
                └── validateResponseStructure()
```

## Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                        USER PROVIDES INPUT                                ║
║                      (ViewModel perspective)                              ║
╚═══════════════════════════════════════════════════════════════════════════╝
                              ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ VIEWMODEL LAYER                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ • Collect user selections (platform, tone, length, variation)              │
│ • Get user input (text prompt, idea, content)                              │
│ • Prepare parameters (as Map<String, dynamic>)                             │
│ • Create PromptRequest with all this data                                  │
└──────────────┬────────────────────────────────────────────────────────────┘
               │ PromptRequest object
               │ {
               │   platform: 'instagram',
               │   tone: 'humorous',
               │   userPrompt: 'Create...',
               │   parameters: {...},
               │   jsonStructure: {...},
               │   rewardGrantToken: 'xyz',
               │   quality: 'nano'
               │ }
               ↓
╔════════════════════════════════════════════════════════════════════════════╗
║                    CALL: promptHandler.handlePromptRequest()               ║
║ Args: language, userPrompt, request, locale, generatorType               ║
╚════════════════════════════════════════════════════════════════════════════╝
                              ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: BUILD PROMPTCONTEXT                                               │
├────────────────────────────────────────────────────────────────────────────┤
│ Apply all 5 priorities:                                                   │
│ • Priority 1: LANGUAGE (foundation) ← from 'language' parameter           │
│ • Priority 2: Platform, Tone, UserPrompt ← from PromptRequest             │
│ • Priority 3: Locale, RTL, Cultural Context ← from 'locale' + system     │
│ • Priority 4: Domain, Audience, History ← derived from context            │
│ • Priority 5: JSON Constraints ← from jsonStructure                       │
│                                                                            │
│ Result: PromptContext with all layers ready                               │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ PromptContext object
               ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: SELECT TEMPLATE                                                   │
├────────────────────────────────────────────────────────────────────────────┤
│ Choose correct template based on generatorType:                           │
│ • 'script' → ScriptGeneratorTemplate                                      │
│ • 'comment' → CommentGeneratorTemplate                                    │
│ • 'hashtag' → HashtagGeneratorTemplate                                    │
│ • 'viral_rewrite' → ViralRewriteTemplate                                  │
│ • 'shot_ideas' → ShotIdeasTemplate                                        │
│ • default → DefaultPromptTemplate                                         │
│                                                                            │
│ Template knows how to format prompts for its specific generator           │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ PromptTemplate instance
               ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: BUILD FINAL PROMPT                                                │
├────────────────────────────────────────────────────────────────────────────┤
│ PromptBuilder.buildPrompt(context, template)                              │
│ ├─ Get template base prompt (generator-specific format)                   │
│ ├─ Add Priority 2 enhancements (platform, tone, parameters)               │
│ ├─ Add Priority 3 enhancements (locale, RTL, cultural)                    │
│ ├─ Add Priority 4 enhancements (domain, audience, history)                │
│ └─ Add Priority 5 enhancements (JSON format instructions)                 │
│                                                                            │
│ Result: String finalPrompt (ready to send to backend)                     │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ String (the assembled prompt)
               ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: VALIDATE (PRIORITY 5)                                             │
├────────────────────────────────────────────────────────────────────────────┤
│ JsonValidator.validatePrompt(finalPrompt, constraints, errors)             │
│ ├─ Check max_tokens                                                       │
│ ├─ Check response_format (JSON)                                           │
│ ├─ Check required_fields presence                                         │
│ ├─ Check array_length_limits                                              │
│ └─ Check value_constraints                                                │
│                                                                            │
│ Result: {isValid: bool, errors: [String]}                                 │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ Validation result
               ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: CREATE PROMPTRESULT                                               │
├────────────────────────────────────────────────────────────────────────────┤
│ Package everything into PromptResult:                                     │
│ • finalPrompt: String (the actual prompt to send)                         │
│ • appliedContext: Map (what priorities were applied)                      │
│ • executionInstructions: String (for backend guidance)                    │
│ • isValid: bool (passed validation?)                                      │
│ • validationErrors: List<String> (any errors)                             │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ PromptResult object
               ↓
╔════════════════════════════════════════════════════════════════════════════╗
║                    RETURN TO VIEWMODEL                                    ║
║                                                                            ║
║ promptResult.finalPrompt ← USE THIS!                                      ║
║ promptResult.isValid ← CHECK THIS!                                        ║
║ promptResult.validationErrors ← IF ERRORS!                                ║
╚════════════════════════════════════════════════════════════════════════════╝
                              ↓
┌────────────────────────────────────────────────────────────────────────────┐
│ VIEWMODEL: USE THE RESULT                                                 │
├────────────────────────────────────────────────────────────────────────────┤
│ if (!promptResult.isValid) {                                              │
│   _errorMessage = promptResult.errorSummary;                              │
│   notifyListeners();                                                      │
│   return;                                                                 │
│ }                                                                         │
│                                                                            │
│ // Send polished prompt to backend!                                       │
│ final response = await _aiRepository.generateAi(                          │
│   prompt: promptResult.finalPrompt,  ← ✨ THE MAGIC PROMPT ✨             │
│   quality: request.quality ?? 'nano',                                     │
│   locale: locale,                                                         │
│   language: language,                                                     │
│   conversationHistory: request.conversationHistory,                       │
│   rewardGrantToken: request.rewardGrantToken,                             │
│ );                                                                        │
└────────────────┬───────────────────────────────────────────────────────────┘
                 │
                 ↓
        🚀 BACKEND RECEIVES POLISHED PROMPT
        📝 WITH ALL PRIORITIES PROPERLY APPLIED
        ✨ GENERATES BETTER RESPONSE
```

## Priority Layer Details

### Layer 1: Language (Foundation)
```
Input: 'en', 'es', 'ar', etc.
Effect: Affects all subsequent layers
Example: 'ar' → isRtl=true, RTL formatting applied
```

### Layer 2: Platform, Tone, User Input, JSON Structure
```
Input: From PromptRequest
Examples:
  platform: 'instagram' → add Instagram-specific guidance
  tone: 'humorous' → add humor instructions
  userPrompt: 'Create...' → base of prompt
  jsonStructure: {...} → define response format
```

### Layer 3: Locale & Cultural Behavior
```
Input: Full locale like 'en-US', 'ar-SA', 'es-MX'
Effects:
  - Cultural appropriateness
  - Regional variations
  - RTL handling for Arabic, Hebrew, Farsi, Urdu
```

### Layer 4: Relevance
```
Input: Domain, audience type, conversation history
Effects:
  - Better context matching
  - Audience-appropriate language
  - Continuity in conversations
```

### Layer 5: JSON Formatting & Constraints
```
Input: JSON structure requirements, constraints
Effects:
  - Ensure response can be parsed
  - Validate format before sending
  - Provide clear formatting instructions to backend
```

## Integration Pattern

### For Each Generator:

```dart
// 1. Create PromptRequest
final request = PromptRequest(
  platform: userSelectedPlatform,
  tone: userSelectedTone,
  userPrompt: userInputText,
  parameters: {...}
  jsonStructure: expectedResponseFormat,
  quality: 'nano',
);

// 2. Call PromptHandler
final handler = PromptHandler();
final result = await handler.handlePromptRequest(
  language: systemLanguage,
  userPrompt: userInputText,
  request: request,
  locale: systemLocale,
  generatorType: 'script', // or 'comment', 'hashtag', etc.
);

// 3. Check validity
if (!result.isValid) {
  handleError(result.errorSummary);
  return;
}

// 4. Use the polished prompt
await callBackend(result.finalPrompt);
```

## Testing Strategy

### Unit Tests
```dart
test('applies all 5 priorities correctly', () async {
  // Build minimal context
  // Call handler
  // Verify all priorities appear in output
});

test('validates JSON constraints', () async {
  // Build request with constraints
  // Call handler
  // Check isValid matches expectations
});

test('handles RTL languages', () async {
  // Use language: 'ar'
  // Verify isRtl is true
  // Check formatting
});
```

### Integration Tests
```dart
test('script generator full flow', () async {
  // Create realistic input
  // Call handler
  // Send to mock backend
  // Verify response parsing
});
```

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| PromptRequest creation | <1ms | Simple data structure |
| PromptContext creation | <2ms | Minimal computation |
| Template selection | <1ms | Simple switch statement |
| Prompt building | 5-10ms | String concatenation |
| Validation | 2-5ms | Only if constraints provided |
| Total flow | 10-20ms | Should be imperceptible |

## Extension Points

### Add a New Generator

1. Create new template:
```dart
class MyGeneratorTemplate implements PromptTemplate {
  @override
  String buildBasePrompt(PromptContext context) => '...';
}
```

2. Register in factory:
```dart
case 'my_generator':
  return MyGeneratorTemplate();
```

### Add a New Priority

1. Add field to PromptContext
2. Add layer method in PromptBuilder
3. Add validation if needed
4. Document the priority

### Add Custom Validator

1. Create validator class
2. Implement validation logic
3. Call from handlePromptRequest()

## Security Considerations

- **No API keys in prompts** - Keep separate from content
- **User input escaping** - Be careful with user text
- **Token safety** - Reward tokens handled securely
- **No sensitive data** - Avoid PII in prompts
- **Validation on client** - But trust backend validation too

## Maintainability

### Code Organization
- Clear separation of concerns
- Single responsibility per class
- No cyclic dependencies
- Minimal coupling

### Documentation
- 4 markdown files (README, Integration, Checklist, Architecture)
- Inline code comments
- Self-documenting method names
- Examples in integration guide

### Debuggability
- Debug methods: `debugPriorities()`, `debugShowFlow()`
- Clear console output
- Full context available
- Validation error messages

## Future Enhancements

1. **Prompt Caching** - Cache successful prompts
2. **Analytics** - Track quality metrics per priority
3. **Learning** - Optimize priorities based on results
4. **Custom Rules** - App-defined priority rules
5. **A/B Testing** - Test different priority orders
6. **Multilingual Switching** - Handle code-switching

---

**This system is designed to scale with your needs while remaining simple and understandable.** 🚀
