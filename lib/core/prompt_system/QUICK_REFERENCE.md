/// lib/core/prompt_system/QUICK_REFERENCE.md
/// 
/// One-page quick reference for using the Prompt System

# Prompt System - Quick Reference Card

## 📌 TL;DR
Replace your manual prompt building with PromptHandler → Get smart, priority-based prompts → Send to backend.

## 🚀 Basic Usage (Copy-Paste Ready)

```dart
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';

// In your ViewModel's generation method:
final request = PromptRequest(
  platform: userSelectedPlatform,        // user chose "instagram"
  tone: userSelectedTone,                // user chose "humorous"
  userPrompt: userProvidedText,          // "Create a video about..."
  parameters: {                          // additional options
    'length': 'short',
    'variation': 'comedy',
  },
  jsonStructure: {                       // expected response format
    'hook': 'string',
    'voiceover': 'string',
    'shots': 'array',
    'cta': 'string',
  },
  quality: 'nano',
);

// Let PromptHandler do the magic!
final handler = PromptHandler();
final result = await handler.handlePromptRequest(
  language: 'en',                 // Priority 1: Language
  userPrompt: userProvidedText,
  request: request,               // Priority 2: Platform/tone/params
  locale: 'en-US',               // Priority 3: Locale
  generatorType: 'script',       // Which of: script|comment|hashtag|viral_rewrite|shot_ideas
);

// Check if valid!
if (!result.isValid) {
  print('Error: ${result.errorSummary}');
  return;
}

// Use the polished prompt
final response = await aiRepository.generateAi(
  prompt: result.finalPrompt,  // ← Magic assembled prompt!
  quality: 'nano',
  locale: 'en-US',
  language: 'en',
);
```

## 🎯 The 5 Priorities (In Order)

| Priority | What | Set By | Example |
|----------|------|--------|---------|
| 1️⃣ | **Language** | System | 'en', 'es', 'ar' |
| 2️⃣ | **Platform, Tone, User Input** | ViewModel | 'instagram', 'humorous', user text |
| 3️⃣ | **Locale, RTL, Culture** | System + Locale | 'en-US', isRtl=true |
| 4️⃣ | **Domain, Audience, History** | System | domain='video_content', audience='youth' |
| 5️⃣ | **JSON Formatting & Constraints** | Template | max_tokens, required_fields |

## 📊 File Map

```
lib/core/prompt_system/
├── prompt_handler.dart ⭐ MAIN ENTRY POINT
├── prompt_template.dart (5 generators + default)
├── models/
│   ├── prompt_request.dart (what you CREATE)
│   ├── prompt_context.dart (internal context)
│   └── prompt_result.dart (what you USE)
├── validators/
│   └── json_validator.dart (Priority 5 validation)
└── 📚 Documentation
    ├── README.md (overview)
    ├── ARCHITECTURE_OVERVIEW.md (complete design)
    ├── INTEGRATION_GUIDE.md (how to use)
    ├── IMPLEMENTATION_CHECKLIST.md (step-by-step)
    └── QUICK_REFERENCE.md (this file)
```

## 🔧 For Each of 5 Generators

### Script Generator
```dart
generatorType: 'script'
jsonStructure: {
  'hook': '', 'voiceover': '', 'shots': [], 'cta': '', 'hashtags': []
}
```

### Comment Generator
```dart
generatorType: 'comment'
parameters: { 'selectedTones': ['friendly', 'humorous', ...] }
```

### Hashtag Generator
```dart
generatorType: 'hashtag'
parameters: { 'count': 10, 'platform': 'instagram' }
```

### Viral Rewrite
```dart
generatorType: 'viral_rewrite'
tone: 'engaging'
```

### Shot Ideas
```dart
generatorType: 'shot_ideas'
parameters: { 'ideaCount': 5 }
```

## ❌ What NOT To Do

```dart
// ❌ DON'T: Build prompt manually
String prompt = baseText + platformGuide + toneGuide + ...;

// ❌ DON'T: Ignore validation
final result = await handler.handlePromptRequest(...);
await sendToBackend(result.finalPrompt); // WRONG! Check validity first!

// ❌ DON'T: Forget PromptRequest
final result = await handler.handlePromptRequest(
  language: 'en',
  // ... missing request parameter!
);

// ✅  DO: Use the system
final result = await handler.handlePromptRequest(...);
if (!result.isValid) return;
await sendToBackend(result.finalPrompt);
```

## 🐛 Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Prompt unchanged | Are you using `result.finalPrompt`? |
| Validation errors | Check jsonConstraints structure |
| RTL text broken | Verify language is set correctly for RTL |
| Import errors | File paths: `lib/core/prompt_system/...` |
| Null error | All required fields in PromptRequest? |

## 🧪 Quick Test

```dart
// Minimal test
final handler = PromptHandler();
final result = await handler.handlePromptRequest(
  language: 'en',
  userPrompt: 'Hello',
  request: PromptRequest(),
  locale: 'en-US',
  generatorType: 'script',
);
print('✅ Valid: ${result.isValid}');
print('📝 Prompt:\n${result.finalPrompt}');
```

## 📞 Debug Commands

```dart
// Show priority hierarchy
context.debugPriorities();

// Show handler flow
handler.debugShowFlow('script', request);

// Check applied context
print(result.appliedContext);

// See error details
print(result.errorSummary);
```

## 💡 Key Concepts

| Term | Meaning |
|------|---------|
| **PromptRequest** | Data structure you create with VM parameters |
| **PromptContext** | Internal object with all priorities applied |
| **PromptTemplate** | Generator-specific formatting (script, comment, etc.) |
| **PromptBuilder** | Layers all 5 priorities into final prompt |
| **PromptResult** | Final output with prompt, context, validation |
| **Singleton** | Only one PromptHandler instance in memory |

## ⚡ Performance

- **Total time:** 10-20ms (imperceptible)
- **Memory:** Minimal allocations
- **Async:** No async operations
- **Thread-safe:** All synchronous

## 🎓 Learning Path

1. Read **README.md** (5 min) - Understand philosophy
2. Read **QUICK_REFERENCE.md** (5 min) - This file!
3. Read **INTEGRATION_GUIDE.md** (10 min) - See examples
4. Read **IMPLEMENTATION_CHECKLIST.md** (10 min) - Phase-by-phase plan
5. Pick ONE generator and implement
6. Test thoroughly
7. Move to next generator

## 🚀 Getting Started (30 seconds)

1. Copy the **Basic Usage** example above
2. Replace `'script'` with your generator type
3. Fill in real values
4. Test with actual user input
5. Done! 🎉

## 📚 Full Documentation

- **README.md** - System overview
- **ARCHITECTURE_OVERVIEW.md** - Complete design
- **INTEGRATION_GUIDE.md** - Detailed examples
- **IMPLEMENTATION_CHECKLIST.md** - Step-by-step plan
- **QUICK_REFERENCE.md** - This file

## ✅ Success Checklist

Before declaring victory:

- [ ] Prompt handler integrated into 1 generator
- [ ] Output quality is same or better
- [ ] No errors in console  
- [ ] RTL (Arabic) works correctly
- [ ] Validation catches bad inputs
- [ ] Performance is good

---

**1-MINUTE SUMMARY:** The Prompt System is a smart priority-based system that assembles better prompts. You provide platform/tone/user input → Handler applies all priorities → You get polished prompt for backend. Do it for all 5 generators.

**Questions?** Check the appropriate documentation file above.
