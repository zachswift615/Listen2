# Word Highlighting - Normalized Text Truncation Bug

## Current Status: NEW BUG DISCOVERED

**State Bug**: ✅ FIXED - Normalized text no longer persists across syntheses
**New Bug**: ❌ TRUNCATION - Long sentences only capture the last clause in normalized text

## What We Fixed

Successfully fixed the state bug where `last_normalized_text_` was being overwritten by lookahead synthesis. The fix captures normalized text immediately after tokenization in all 4 TTS implementation files:

- ✅ `offline-tts-vits-impl.h` (lines 218-228, 269-271, 365-366)
- ✅ `offline-tts-matcha-impl.h` (lines 270-281, 313-314, 389-390)
- ✅ `offline-tts-kokoro-impl.h` (lines 223-235, 339-340)
- ✅ `offline-tts-kitten-impl.h` (lines 222-233, 337-338)

Framework rebuilt successfully.

## New Bug: Normalized Text Truncation

### Symptoms

For long sentences, `phonemize_eSpeak_with_normalized` only returns the **last sentence/clause** instead of the complete normalized text:

**Examples from logs** (`/Users/zachswift/listen-2-logs-2025-11-13.txt`):

1. **Lines 595, 678**:
   - Input: "They start with a messy problem, a foundation model API key, and a rough idea of what might help. "
   - Output: "and a rough idea of what might help " ❌ (only last clause)

2. **Lines 876, 1134**:
   - Input: "We'll cover each of the following topics in more depth through the rest of the book, and many will get their own chapter, but this chapter will give you an overview of how to design an agentic system, all grounded in a specific example of managing customer support for an ecommerce platform."
   - Output: "all grounded in a specific example of managing customer support for ecommerce platform " ❌ (only last clause)

3. **Lines 1415, 1549**:
   - Input: "Every day, your customer-support team fields dozens or hundreds of emails asking to refund a broken mug, cancel an unshipped order, or change a delivery address. "
   - Output: "or change a delivery address " ❌ (only last clause)

**Short sentences work fine**:
- "Building" → "building " ✅
- "CHAPTER 2" → "chapter 2 " ✅
- "Designing Agent Systems" → "designing agent systems " ✅

### Root Cause

Located in **`/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp.backup:577-580`**:

```cpp
// NEW: Get normalized text after phonemization
const char* normalized = espeak_GetNormalizedText();
if (normalized) {
  result.normalized_text = std::string(normalized);
}
```

**Problem**: `espeak_GetNormalizedText()` is called ONCE after the entire phonemization loop completes. When espeak-ng splits long text into multiple sentences internally, it processes them one at a time, and `GetNormalizedText()` only returns the normalized text from the **last sentence processed**.

### The Fix Needed

The normalized text must be **accumulated across all sentences** during phonemization, not captured once at the end.

**File to modify**: `/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp.backup`

**Location**: Inside the `phonemize_eSpeak_with_normalized` function (around line 460)

**Current problematic code**:
```cpp
} // while inputTextPointer != NULL

// NEW: Get normalized text after phonemization  <-- WRONG: Only gets last sentence
const char* normalized = espeak_GetNormalizedText();
if (normalized) {
  result.normalized_text = std::string(normalized);
}
```

**Needed change**: Move normalized text capture INSIDE the loop and accumulate:

```cpp
// Inside the while loop, after each sentence is processed:
while (inputTextPointer != NULL) {
  // ... existing code ...

  // Capture normalized text for THIS sentence
  const char* normalized = espeak_GetNormalizedText();
  if (normalized) {
    result.normalized_text += std::string(normalized);  // Accumulate!
  }

  // ... rest of loop ...
}
```

**OR** investigate if there's an espeak-ng API that returns normalized text for ALL sentences at once.

## Files Involved

### C++ (sherpa-onnx)
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h` (FIXED)
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-matcha-impl.h` (FIXED)
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-kokoro-impl.h` (FIXED)
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-kitten-impl.h` (FIXED)
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/piper-phonemize-lexicon.cc` (calls piper-phonemize)

### C++ (piper-phonemize) - NEEDS FIX
- **`/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp.backup`** ← BUG HERE
- `/Users/zachswift/projects/piper-phonemize/src/phonemize.hpp`

### Swift (Listen2)
- `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

## Next Steps

1. **Fix the truncation bug in piper-phonemize**:
   - Modify `phonemize_eSpeak_with_normalized()` in `phonemize.cpp.backup`
   - Accumulate normalized text across all sentences instead of capturing only the last one
   - Rebuild piper-phonemize library

2. **Rebuild framework**:
   ```bash
   cd /Users/zachswift/projects/Listen2
   ./scripts/update-frameworks.sh --build
   ```

3. **Test with long sentences** to verify complete normalized text is captured

## Debug Logging

The C++ code has debug logging enabled (lines 606-612 in `piper-phonemize-lexicon.cc`):
```cpp
fprintf(stderr, "[DEBUG] About to phonemize text: '%s'\n", text.c_str());
fprintf(stderr, "[DEBUG] Previous normalized text was: '%s'\n", last_normalized_text_.c_str());
// ... phonemization ...
fprintf(stderr, "[DEBUG] New normalized text is: '%s'\n", last_normalized_text_.c_str());
```

These logs show the truncation happening at the piper-phonemize level.

## Testing

After fixing, test with these samples from the logs:
1. Short: "Building" should → "building "
2. Medium: "Most practitioners don't begin with a grand design document when building agent systems." should → "most practitioners don't begin with a grand design document when building agent systems "
3. Long: "We'll cover each of the following topics in more depth..." should → complete normalized text (not just "all grounded...")

## References

- Original plan: `/Users/zachswift/projects/Listen2/docs/plan-for-word-highlighting-fix-simplification.md`
- Pipeline doc: `/Users/zachswift/projects/Listen2/docs/word-highlighting-pipeline`
- Test logs: `/Users/zachswift/listen-2-logs-2025-11-13.txt`
