/// lib/core/prompt_system/IMPLEMENTATION_CHECKLIST.md
/// 
/// Step-by-step integration checklist for adding PromptHandler to all 5 generators.

# Implementation Checklist

## Overview
This document walks through integrating the PromptHandler into your 5 generators, one at a time.

**Start with ONE generator, test thoroughly, then rollout to others.**

---

## ✅ Phase 1: Script Generator

### 1.1 Update Imports
- [ ] Open `lib/modules/script_generator/view_model/script_generator_view_model.dart`
- [ ] Add imports:
```dart
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';
```

### 1.2 Create PromptRequest in _generateScriptWithAI()
Location: Around line 365-450 (in _generateScriptWithAI method)

Replace the current prompt building logic with:

```dart
// OLD: Manual prompt concatenation
String fullPrompt = basePrompt + lengthGuide + variationGuide + ...;

// NEW: Use PromptRequest
final request = PromptRequest(
  platform: _selectedPlatform,
  tone: _selectedEmotion,
  userPrompt: basePrompt,
  parameters: {
    'length': _selectedLength,
    'variation': _selectedVariation,
  },
  jsonStructure: {
    'hook': 'brief opening',
    'voiceover': 'main script',
    'shots': 'scenes',
    'cta': 'call to action',
    'hashtags': 'tags',
  },
  rewardGrantToken: _rewardGrantToken,
  quality: 'nano',
);
```

### 1.3 Call PromptHandler
Replace the direct generateAi call with:

```dart
// Create handler (singleton)
final promptHandler = PromptHandler();

// Get the assembled prompt
final promptResult = await promptHandler.handlePromptRequest(
  language: language,
  userPrompt: basePrompt,
  request: request,
  locale: locale,
  generatorType: 'script',
);

// Check validity
if (!promptResult.isValid) {
  throw Exception('Prompt validation failed: ${promptResult.errorSummary}');
}

// Use the polished prompt
final response = await _aiRepository.generateAi(
  prompt: promptResult.finalPrompt,
  quality: request.quality ?? 'nano',
  locale: locale,
  language: language,
  conversationHistory: request.conversationHistory,
  rewardGrantToken: request.rewardGrantToken,
);
```

### 1.4 Test Script Generator
- [ ] Run app and navigate to Script Generator
- [ ] Generate a script and verify output is correct
- [ ] Check console logs for "✅ PromptHandler" messages
- [ ] Verify priority hierarchy is shown in debug output

---

## ✅ Phase 2: Comment Generator

### 2.1 Update Imports
- [ ] Open `lib/modules/comment_generator/view_model/comment_generator_view_model.dart`
- [ ] Add imports (same as Script)

### 2.2 Find generateComments() Method
Location: Around line 143

### 2.3 Create PromptRequest
```dart
final request = PromptRequest(
  platform: 'instagram',  // or detect from context if available
  tone: _selectedTones.isNotEmpty ? _selectedTones.first : 'friendly',
  userPrompt: _input,
  parameters: {
    'selectedTones': _selectedTones,
  },
  quality: 'nano',
);
```

### 2.4 Call PromptHandler
Replace existing prompt building with PromptHandler call.

### 2.5 Test Comment Generator
- [ ] Navigate to Comment Generator
- [ ] Generate comments for sample text
- [ ] Verify all tones are applied correctly
- [ ] Check output quality

---

## ✅ Phase 3: Hashtag Generator

### 3.1 Update Imports
- [ ] Open `lib/modules/quick_tools/view_model/hashtag_generator_view_model.dart`

### 3.2 Find Generation Method
Likely `generateHashtags()` or similar

### 3.3 Create PromptRequest
```dart
final request = PromptRequest(
  platform: _selectedPlatform ?? 'instagram',
  userPrompt: _prompt,
  parameters: {
    'count': _count ?? 10,
    'platform': _selectedPlatform,
  },
  quality: 'nano',
);
```

### 3.4 Integrate PromptHandler

### 3.5 Test
- [ ] Generate hashtags
- [ ] Verify platform-specific optimization
- [ ] Check hashtag relevance

---

## ✅ Phase 4: Viral Rewrite

### 4.1 Update Imports
- [ ] Open `lib/modules/quick_tools/view_model/viral_rewrite_view_model.dart`

### 4.2 Create PromptRequest
```dart
final request = PromptRequest(
  platform: _selectedPlatform,
  tone: 'engaging',
  userPrompt: _originalContent,
  parameters: {
    'platform': _selectedPlatform,
  },
  quality: 'nano',
);
```

### 4.3 Integrate PromptHandler

### 4.4 Test
- [ ] Rewrite sample content
- [ ] Verify viral potential is increased
- [ ] Check platform optimization

---

## ✅ Phase 5: Shot Ideas

### 5.1 Update Imports
- [ ] Open `lib/modules/quick_tools/view_model/shot_ideas_view_model.dart`

### 5.2 Create PromptRequest
```dart
final request = PromptRequest(
  userPrompt: _concept,
  parameters: {
    'ideaCount': _ideaCount ?? 5,
  },
  quality: 'nano',
);
```

### 5.3 Integrate PromptHandler

### 5.4 Test
- [ ] Generate shot ideas
- [ ] Verify practicality of ideas
- [ ] Check video production suitability

---

## 🧪 Testing Checklist (Do for Each Generator)

### Functional Testing
- [ ] Generates output without errors
- [ ] Output is sensible and relevant
- [ ] Handles empty input gracefully
- [ ] Works offline with error message

### Priority Testing
- [ ] Language changes affect output (test: 'en' vs 'es')
- [ ] Platform selection affects output (instagram vs tiktok)
- [ ] Tone is reflected in response
- [ ] RTL language handled correctly (test with 'ar')

### Validation Testing
- [ ] JSON validation works
- [ ] Invalid constraints caught
- [ ] Error messages are clear

### Performance Testing
- [ ] Prompt generation is fast (<100ms)
- [ ] No memory leaks
- [ ] No excessive allocations

---

## 🔍 Debugging Guide

If something doesn't work:

### Check 1: Are imports correct?
```dart
import 'package:ideaboost/core/prompt_system/prompt_handler.dart';
import 'package:ideaboost/core/prompt_system/models/prompt_request.dart';
```

### Check 2: Is PromptRequest built correctly?
```dart
// Add debug logging
print('Request: platform=${request.platform}, tone=${request.tone}');
```

### Check 3: Is PromptResult valid?
```dart
if (!promptResult.isValid) {
  print('Validation errors: ${promptResult.errorSummary}');
  // Don't proceed!
}
```

### Check 4: Check PromptContext priorities
```dart
// In PromptHandler, the context should show all priorities:
debugPrint(context.debugPriorities());
```

### Check 5: Test with minimal input
```dart
// Start with simplest case
final result = await handler.handlePromptRequest(
  language: 'en',
  userPrompt: 'Hello',
  request: PromptRequest(),  // Minimal request
  locale: 'en-US',
  generatorType: 'script',
);
print(result.finalPrompt);  // What was generated?
```

---

## 🚀 Rollout Strategy

### Day 1-2: Script Generator
- [ ] Implement
- [ ] Test thoroughly
- [ ] Get feedback

### Day 2-3: Comment Generator
- [ ] Implement
- [ ] Test thoroughly
- [ ] Fix any new issues discovered

### Day 3-4: Hashtag + Viral Rewrite
- [ ] Both implementation
- [ ] Test
- [ ] Minor fixes

### Day 4-5: Shot Ideas + Final Testing
- [ ] Implementation
- [ ] Full system test
- [ ] Performance testing
- [ ] RTL language testing

### Day 5: Deploy
- [ ] Build release version
- [ ] Test on devices
- [ ] Monitor for errors

---

## 📊 Success Criteria

All of the following should be true:

- [ ] All 5 generators work with PromptHandler
- [ ] No regressions in output quality
- [ ] RTL languages (Arabic) display correctly
- [ ] JSON responses are valid and properly formatted
- [ ] Language parameter affects all outputs
- [ ] Platform parameter affects output appropriately
- [ ] Performance is good (no slowdown)
- [ ] Error handling is robust
- [ ] Debug logs are helpful
- [ ] Code is maintainable and clear

---

## 🎓 Key Things to Remember

1. **PromptHandler is a singlet** - Only one instance
2. **PromptRequest is data** - Just contains the parameters
3. **Language is Priority 1** - Everything else flows from it
4. **Testing is critical** - Especially RTL and multilingual
5. **Error handling** - Always check promptResult.isValid
6. **Keep it minimal** - Don't add unnecessary complexity

---

## 📞 Troubleshooting

| Problem | Solution |
|---------|----------|
| Import errors | Check file paths are correct |
| Null pointer in handler | Ensure all required fields in PromptRequest |
| Output unchanged | Check if using promptResult.finalPrompt |
| Validation errors | Check jsonConstraints structure |
| RTL text broken | Verify isRtl is set correctly |
| Performance slow | Profile with DevTools, check validator |

---

## 🎉 Next Steps After Integration

1. Monitor quality metrics (user ratings, engagement)
2. Collect prompt examples for testing/training
3. Refine templates based on real-world results
4. Consider adding analytics/logging
5. Plan for future priority enhancements
6. Document generator-specific customizations

---

**You've got this! This is going to make your prompt system much smarter and more maintainable.** 🚀
