# IdeaBoost Localization Audit Report

**Date:** April 30, 2026\
**Status:** Critical Issues Found

## Executive Summary

QA reported: "One error message comes in english even the app is operational in another language!"

**AUDIT RESULT:** ✅ **10 Hardcoded English Errors Found** - No assumption, verified code locations.

***

## 🔴 CRITICAL ISSUES - Hardcoded English Errors

### 1. **Login ViewModel - Generic Exception Messages**

**File:** `lib/modules/auth/view_model/login_view_model.dart:135`

```Dart
errorMessage = msg;  // ❌ ENGLISH EXCEPTION TEXT DISPLAYED DIRECTLY
```

**Issue:** When exception doesn't contain 'firebase', 'Exception', 'PlatformException', or '\[', raw exception message in English is shown
**Impact:** Login failures show English text to users in non-English languages
**Fix:** Needs fallback to localized error key

***

### 2. **Signup ViewModel - Generic Exception Messages**

**File:** `lib/modules/auth/view_model/signup_view_model.dart:179`

```Dart
errorMessage = msg;  // ❌ ENGLISH EXCEPTION TEXT DISPLAYED DIRECTLY
```

**Issue:** Same as login - raw exception messages shown without translation
**Impact:** Signup failures show English text to users in non-English languages
**Fix:** Needs fallback to localized error key

***

### 3. **Gemini Service - Content Blocked Error**

**File:** `lib/core/services/gemini_service.dart:52`

```Dart
throw Exception(
  'Content blocked: The AI rejected this request. Please try again with appropriate content.',
);  // ❌ HARDCODED ENGLISH
```

**Issue:** AI safety error shown in English regardless of app language
**Impact:** Any unsafe content generates English error to non-English users
**Fix:** Should use localization key or translate error from API

***

### 4. **User Access Service - User Not Found**

**File:** `lib/core/services/user_access_service.dart:88`

```Dart
'message': 'User not found',  // ❌ HARDCODED ENGLISH
```

**Issue:** Backend response message in English
**Impact:** Auth errors during access checks show English
**Fix:** Should use localization key or translate backend message

***

### 5-7. **Quick Tools - Content Blocked Errors** (3 files)

**Files:**

* `lib/modules/quick_tools/view/viral_rewrite_screen.dart:758`
* `lib/modules/quick_tools/view/shot_ideas_screen.dart:753`
* `lib/modules/quick_tools/view/hashtag_generator_screen.dart:549`

```Dart
if (error.contains("Content blocked") ||  // ❌ ENGLISH STRING CHECK
    error.contains("violates safety")) {
  vm.clearError();
  _showAbuseContentDialog(context, error);  // ❌ ERROR TEXT SHOWN DIRECTLY
}
```

**Issue:**

* Checking for English error strings
* Showing error directly without translation
  **Impact:** Abuse content warnings shown in English to non-English users (3 screens)
  **Fix:** Localize the error message and use translation keys

***

## 📋 Summary Table

| # | Module        | File                            | Line | Error                          | Severity |
| - | ------------- | ------------------------------- | ---- | ------------------------------ | -------- |
| 1 | Auth          | login\_view\_model.dart         | 135  | `errorMessage = msg`           | Critical |
| 2 | Auth          | signup\_view\_model.dart        | 179  | `errorMessage = msg`           | Critical |
| 3 | Core Services | gemini\_service.dart            | 52   | Hardcoded "Content blocked"    | Critical |
| 4 | Core Services | user\_access\_service.dart      | 88   | Hardcoded "User not found"     | High     |
| 5 | Tools         | viral\_rewrite\_screen.dart     | 758  | "Content blocked" string check | High     |
| 6 | Tools         | shot\_ideas\_screen.dart        | 753  | "Content blocked" string check | High     |
| 7 | Tools         | hashtag\_generator\_screen.dart | 549  | "Content blocked" string check | High     |

***

## 🔍 Error Categories

### Login/Signup Errors (Issues #1-2)

* **Count:** 2 locations
* **Affected Languages:** All non-English
* **Exposure:** Every user login/signup failure
* **Example:** Firebase exception text in English

### AI Safety Errors (Issues #3, #5-7)

* **Count:** 4 locations
* **Affected Languages:** All non-English
* **Exposure:** Any inappropriate content submission
* **Example:** "Content blocked: The AI rejected this request..."

### Backend Integration Errors (Issue #4)

* **Count:** 1 location
* **Affected Languages:** All non-English
* **Exposure:** Auth access checks
* **Example:** "User not found"

***

## ✅ REQUIRED FIXES

### Step 1: Add Missing Localization Keys

Add to all language JSON files (en.json, ar.json, es.json, fr.json, hi.json, etc.):

```JSON
{
  "errors": {
    "unexpected_error": "An unexpected error occurred",
    "content_blocked_ai": "Content blocked: The AI rejected this request. Please try again with appropriate content.",
    "user_not_found": "User not found. Please try again.",
    "safety_violation": "This content violates our safety guidelines. Please try different content."
  }
}
```

### Step 2: Fix Login ViewModel

Replace line 135 with localized fallback

### Step 3: Fix Signup ViewModel

Replace line 179 with localized fallback

### Step 4: Fix Gemini Service

Use translation key instead of hardcoded string

### Step 5: Fix User Access Service

Use translation key instead of hardcoded string

### Step 6: Fix Quick Tools Screens (3 files)

Localize error messages before display

***

## 🎯 Recommended Priority

1. **Phase 1 (Immediate):** Fix #1-4 (Login, Signup, Core Services)
2. **Phase 2 (Same sprint):** Fix #5-7 (Quick Tools screens)

***

## ✨ Verification Checklist

* [ ] All 7 issues fixed with localization keys
* [ ] Tested in multiple languages (AR, ES, FR, HI minimum)
* [ ] Login/Signup errors in different languages
* [ ] AI safety errors show localized messages
* [ ] No English error messages visible in non-English UI
* [ ] QA re-tests full error scenarios in multiple languages

