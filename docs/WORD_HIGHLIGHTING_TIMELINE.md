# Word Highlighting Implementation Timeline
**Project:** Listen2 TTS App
**Goal:** Implement accurate word-level highlighting synchronized with Piper TTS audio
**Timeline:** November 12-16, 2025 (3-4 days of investigation)
**Status:** Feature completely unusable - never worked for more than 25% of words

---

## Overview

This document tracks all attempts to implement word highlighting for Piper TTS in the Listen2 app. Despite fixing 10+ individual bugs across multiple layers (espeak-ng, piper-phonemize, sherpa-onnx, Swift), the feature remains broken. Highlighting either doesn't appear, appears on wrong words, or jumps randomly.

---

## 📅 November 12, 2025 - Initial Implementation

### Session 1: Phoneme Alignment Infrastructure
**Files:** `docs/plans/2025-11-12-phoneme-alignment-complete.md`

**Problem being addressed:**
Need phoneme position data to map phonemes to words for highlighting.

**Changes made:**
- Forked piper-phonemize (`github.com/zachswift615/piper-phonemize`)
  - `src/phonemize.cpp` - Added espeak position tracking callbacks
- Modified sherpa-onnx C++ layer
  - `csrc/piper-phonemize-lexicon.cc` - Integration layer for position data
  - `csrc/phoneme-info.h` - PhonemeInfo struct definition
  - `c-api/c-api.h` - C API struct with phoneme fields
  - `c-api/c-api.cc` - Populate phoneme fields from C++
- Created Listen2 Swift services
  - `Services/TTS/PhonemeAlignmentService.swift` - Alignment logic

**Result:**
Infrastructure built but not tested. 10 of 16 tasks completed.

---

### Session 2: Function Call Wiring Bug
**Files:** `docs/SESSION_HANDOFF_2.md`

**Bug addressed:**
Position tracking infrastructure existed but was never invoked. All `ConvertTextToTokenIds*()` methods calling old `CallPhonemizeEspeak()` without position tracking.

**Changes made:**
- **sherpa-onnx** `csrc/piper-phonemize-lexicon.cc`
  - Lines 569-606: Changed `CallPhonemizeEspeak()` → `CallPhonemizeEspeakWithPositions()` (VITS)
  - Lines 506-530: Same change for Matcha model
  - Added `GetLastPhonemeSequences()` method

**Result:**
Fixed call chain. 0 phonemes still being extracted on device - revealed next bug.

---

### Session 3: CMake Download Wrong Repository
**Files:** `docs/SESSION_HANDOFF_3.md`

**Bug addressed:**
CMake downloading original piper-phonemize instead of fork with position tracking.

**Changes made:**
- **sherpa-onnx** `cmake/piper-phonemize.cmake`
  - Removed obsolete URL variables pointing to original repo
  - Changed `FetchContent_MakeAvailable()` to proper `FetchContent_GetProperties + FetchContent_Populate` pattern
  - Fixed to download from `github.com/zachswift615/piper-phonemize` fork

**Result:**
Framework now using correct source. Still 0 phonemes on device - revealed next bug.

---

### Session 4: Framework Deployment Failure
**Files:** `docs/SESSION_HANDOFF_4.md`

**Bug addressed:**
Ruby script claimed success but never copied new framework. Listen2 using stale framework from November 9.

**Changes made:**
- Added diagnostic logging
  - **sherpa-onnx** `c-api/c-api.cc:1363-1371` - Log first 5 phonemes
  - **Listen2** `Services/TTS/SherpaOnnx.swift:164-172` - Log raw position data
- Manual framework copy to replace failed script
  ```bash
  rm -rf Listen2/Frameworks/sherpa-onnx.xcframework
  cp -R sherpa-onnx/build-ios/sherpa-onnx.xcframework Listen2/Frameworks/
  ```

**Result:**
Framework updated. Symbol verification passed. Still 0 phonemes - revealed next bug.

---

## 📅 November 13, 2025 - Pipeline Issues

### Session 5: Diagnostic Logging Added
**Files:** `docs/SESSION_HANDOFF_5.md`

**Bug being investigated:**
Still getting 0 phonemes despite correct code and correct framework.

**Changes made:**
- **piper-phonemize** `src/phonemize.cpp` - Added 6 diagnostic logging points
  - Line ~197: Callback registration
  - Line ~213: Capture enabled
  - Line ~155: Callback invocation
  - Line ~160: Phoneme event
  - Line ~224: Positions captured count
  - Line ~376: Final return count

**Result:**
Logging deployed. Awaiting log analysis to find root cause.

---

### Session 6: Three Initialization Bugs
**Files:** `docs/SESSION_HANDOFF_6.md`

**Bugs addressed:**

1. **Missing espeak-ng flag**
   - espeak-ng wasn't generating phoneme events at all
   - **sherpa-onnx** `csrc/piper-phonemize-lexicon.cc:365` - Added `espeakINITIALIZE_PHONEME_EVENTS` flag

2. **Swift rejecting valid data**
   - Swift required BOTH durations AND positions
   - **Listen2** `Services/TTS/SherpaOnnx.swift:157-159` - Made durations optional

3. **C API counter always 0**
   - Counter set from empty durations array instead of phonemes array
   - **sherpa-onnx** `c-api/c-api.cc:1326` - Changed to `num_phonemes = audio.phonemes.size()`

**Result:**
Phoneme data now flowing (0 → 332 phonemes per synthesis). Highlighting appears but completely wrong - positions corrupted. All phonemes showing identical positions like `[3..<3]` instead of sequential `[0..<1] [1..<2]`.

---

### Session 7: Position Data Corruption
**Files:** `docs/SESSION_HANDOFF_7.md`

**Bug addressed:**
All phonemes showing duplicate positions. espeak only emitting 39 position events for 332 phonemes (12% coverage). Gap-filling logic creating duplicates.

**Changes made:**
- **piper-phonemize** `src/phonemize.cpp`
  - Lines 136-157: Added WordInfo struct and PhonemeEventCapture
  - Lines 159-232: Implemented synth_callback with WORD/PHONEME handling
  - Lines 340-406: Position distribution logic (Option B - all phonemes in word get word's full range)
  - Fixed `current_word` pointer reset bug (was local variable, moved to PhonemeEventCapture struct)

**Result:**
Word grouping fixed. Still many phonemes showing `[-1..<-1]` (no position assigned). Highlighting appears but jumps randomly between words.

---

### Session 8: Position Mapping Attempts
**Files:** `docs/SESSION_HANDOFF_8.md`

**Bug addressed:**
VoxPDF word positions don't match espeak's normalized text positions. PDF: "Dr. Smith's couldn't" vs espeak: "Doctor Smith s could not". Position mismatch causing crashes and wrong words highlighted.

**Approaches tried:**

1. **VoxPDF + espeak position mapping** - Overlap detection failed, gibberish words
2. **Pure espeak word extraction** - Same normalization issue
3. **Hybrid VoxPDF words + espeak timing** - String index out of bounds crash
4. **Text splitting + espeak timing** - Current approach, no crashes but wrong mappings

**Changes made:**
- **Listen2** `Services/TTS/PhonemeAlignmentService.swift`
  - Made wordMap optional
  - Removed VoxPDF alignment path
  - Added `extractWordsFromText()` - whitespace splitting
  - Added `groupPhonemesByWord()` - group by textRange
- **Listen2** `Services/TTS/SynthesisQueue.swift`
  - Removed `guard let wordMap` that blocked EPUB alignment

**Result:**
No crashes. Highlighting works for all document types but mappings wrong. Word count mismatch: 28 text words vs 39 espeak groups. Highlighting glitchy - jumps randomly.

---

## 📅 November 14, 2025 - Normalization Issues

### Normalized Text Pipeline
**Files:** `docs/HANDOFF_2025-11-14_NORMALIZED_TEXT.md`

**Bug addressed:**
Need normalized text to properly map espeak positions to actual text. espeak normalizes "Dr." → "Doctor", "123" → "one hundred twenty three".

**Changes made:**
- **espeak-ng fork** `src/libespeak-ng/translate.c` - Normalized text buffer and capture
- **piper-phonemize** `src/phonemize.cpp` - Added phonemize_eSpeak_with_normalized()
- **sherpa-onnx** `csrc/offline-tts-vits-impl.h` - VITS normalized text capture
- **sherpa-onnx** `csrc/offline-tts-matcha-impl.h` - Matcha normalized text (Bug #1 fix)
- **Listen2** `Services/TTS/AlignmentResult.swift` - Changed to integer offsets

**Result:**
Normalized text pipeline working. App froze after first line during testing. All 2193 phonemes had duration = 0.

---

### Framework Cache and Stale Data
**Files:** `docs/HANDOFF_2025-11-14_WORD_HIGHLIGHTING_DEBUG.md`

**Bugs addressed:**
1. Stale normalized text from previous synthesis calls
2. Framework cache preventing code updates from taking effect
3. Corrupt alignment cache

**Changes made:**
- **Listen2** `Services/TTSService.swift:67-76` - Added cache clear on init
- **sherpa-onnx framework** - Rebuilt with commit 498f9071
- Framework deployment via update script

**Result:**
Same issues persist after clean build. Phoneme durations still 0 or corrupt (INT32_MIN). Normalized text still stale for some paragraphs. Synthesis failures (returned nil).

---

### w_ceil Tensor Data Type Mismatch
**Files:** `docs/HANDOFF_2025-11-14_WCEIL_DTYPE_FIX.md`

**Bug addressed:**
Phoneme durations showing garbage values (-2,147,483,648 samples = 13 hours). Model exported w_ceil as float32, sherpa-onnx reading as int64.

**Changes made:**
- **Piper** `src/python/piper_train/export_onnx.py:69`
  - Added `.squeeze()` to remove batch/channel dimensions (3D → 1D)
  - Added `.long()` to cast float32 → int64
- **Piper** Lines 106-126: Added automatic metadata generation
- **Listen2** `scripts/export-and-update-model.sh` - Automation script

**Result:**
w_ceil corruption fixed. Durations now plausible (0.023s instead of 222 hours). Synthesis performance slow (476% CPU). Word highlighting still wrong - only ~50% accuracy. Stuck on last word issue.

---

## 📅 November 15, 2025 - Text Truncation

### Normalized Text Truncation
**Files:** `docs/handoff-normalized-text-truncation-bug.md`

**Bug addressed:**
Long sentences only captured last clause. espeak splits long sentences into multiple clauses, but `espeak_GetNormalizedText()` called once after loop.

**Example:**
- Input: "They start with a messy problem..."
- Output: "and a rough idea of what might help" (only last clause)

**Changes made:**
- **piper-phonemize** `src/phonemize.cpp:577-580`
  - Moved normalized text capture INSIDE the sentence loop
  - Changed from single call to accumulated across all sentences

**Result:**
Truncation fixed. Complete normalized text now captured. Framework rebuild needed to test.

---

### Simplification Plan and Implementation
**Files:** `docs/plans/2024-11-15-phoneme-aware-word-highlighting-design.md`, `docs/word-highlighting-handoff-2024-11-15.md`

**Problem being addressed:**
Random word highlighting, glitching, synchronization issues. Over-complication with character-level precision for word-level problem.

**Simplification plan proposed:**
- Abandon character mapping, use word-level only
- PhonemeTimeline with relative timing per sentence
- SentenceBundle - audio + timeline combined
- WordHighlighter with CADisplayLink at 60 FPS
- Simple word matching between original/normalized text

**Changes made:**
- **Listen2 Swift:**
  - `PhonemeTimeline.swift` - Core data structures
  - `PhonemeTimelineBuilder.swift` - Builds timelines from synthesis
  - `WordHighlighter.swift` - CADisplayLink at 60 FPS
  - `SynthesisQueue.swift` - Streams sentence bundles
  - `TTSService.swift` - Integrated highlighting with playback

**Result:**
Simplification plan implemented. Word detection completely broken. Character mapping wrong: "CHAPTER 2" → "APTER 2" (missing first 2 chars). Positions start at 2 instead of 0. Sparse mapping (4 entries for 9 chars). Implementation revealed character position offset bug from espeak-ng.

---

## 📅 November 16, 2025 - Position Offset

### espeak Character Position Offset
**Files:** `docs/word-highlighting-session-2024-11-16.md`

**Bug addressed:**
All character positions systematically off by 2. "CHAPTER" highlighted as "APTER". espeak initializes `count_characters` to -1, increments happen before text processing starts.

**Changes made:**
- **piper-phonemize** `src/phonemize.cpp:197`
  - Added offset compensation: `word.text_position = events->text_position > 0 ? events->text_position - 1 : 0;`
- **sherpa-onnx framework** - Rebuilt with fix

**Result:**
Position offset fix applied. Needs testing on device. May need -2 offset instead of -1.

---

### Additional Simplification Analysis
**Files:** `docs/plan-for-word-highlighting-fix-simplification.md`

**Problem identified:**
After implementing Nov 15 redesign, still broken. Analysis identified remaining over-complication: Three text representations causing cascading bugs:
- Original: "Dr. Smith's"
- Normalized: "doctor smith s"
- Phoneme positions: word-level groupings

**Further simplification proposed:**
Abandon character mapping entirely. Use word-level only: split/match/assign durations. Stop trying to track character-level positions.

**Result:**
Plan documented. Nov 16 sessions continued with bug fixes to character-mapping approach instead.

---

### State Contamination Bug
**Files:** `docs/2025-11-16-16-43-54-session-handoff.md`

**Bug addressed:**
Race condition in shared mutable state. Thread A's normalized text overwritten by Thread B (lookahead synthesis). Wrong sentences' normalized text appearing.

**Changes made:**
- **piper-phonemize** `src/phonemize.cpp:260` - Added `espeak_Cancel()` before synthesis
- **sherpa-onnx** `csrc/offline-tts-frontend.h` - Extended TokenIDs struct with phoneme data fields
- **sherpa-onnx** `csrc/piper-phonemize-lexicon.cc:628-636, 717-725` - Populate TokenIDs atomically
- **sherpa-onnx** `csrc/offline-tts-vits-impl.h:218-237` - Extract from TokenIDs instead of Get methods

**Result:**
State contamination fixed. NEW BUG INTRODUCED: Phoneme duration corruption. Only first word highlights. Durations huge/negative (-122716s). Fix broke duration extraction from w_ceil tensor.

---

## 📅 January 14, 2025 - w_ceil Tensor Work

### Piper Model Re-export
**Files:** `docs/WCEIL_SESSION_HANDOFF.md`

**Problem being addressed:**
Need actual phoneme durations for accurate timing. Estimating durations (50ms per phoneme) not accurate enough.

**Changes made:**
- **Piper fork** `src/cpp/piper.cpp` - Modified synthesize() to return w_ceil
- **Piper** `export_onnx.py` - Added w_ceil as output tensor
- Re-exported 3 models: en_US-lessac-high.onnx (109 MB), hfc_female/male-medium (61 MB each)
- Fixed metadata bug (added sample_rate, num_speakers, speaker_id_map)

**Result:**
Models exported with w_ceil and metadata. Models load successfully. BLOCKED: Synthesis timeout (100ms vs 2-3 minutes actual synthesis time). Dual playback chaos (iOS fallback plays, then Piper also plays). Cannot test if w_ceil improves highlighting.

---

## Current State

### What Data Is Flowing
- Phoneme symbols: Yes (332 per synthesis)
- Phoneme positions: Partially (12-75% have espeak positions, rest are duplicates or -1)
- Phoneme durations: Broken (corrupted by TokenIDs changes) OR unavailable (depending on session)
- Normalized text: Yes but may be stale/truncated depending on session

### What's Broken
- Highlighting accuracy: ~0-25% of words highlight correctly
- Position mapping: Misaligned due to normalization mismatch
- Word detection: Character ranges often wrong or off by 1-2 characters
- Timing: Either using estimates or corrupted durations
- Synthesis timeout: 100ms prevents real-world testing
- State contamination: Fixed but broke duration extraction

---

## Files Modified Across All Sessions

### Forks Created
- `github.com/zachswift615/piper-phonemize` - Position tracking
- `github.com/zachswift615/piper` - w_ceil tensor export
- espeak-ng fork (path unknown) - Normalized text capture

### sherpa-onnx Repository
- `cmake/piper-phonemize.cmake` - Downloads forked piper-phonemize
- `csrc/piper-phonemize-lexicon.h` - Declares position tracking functions
- `csrc/piper-phonemize-lexicon.cc` - Implementation, espeak initialization
- `csrc/offline-tts-vits-impl.h` - Calls frontend, attaches phonemes
- `csrc/offline-tts-matcha-impl.h` - Normalized text fix
- `csrc/offline-tts-frontend.h` - Extended TokenIDs struct
- `csrc/phoneme-info.h` - PhonemeInfo struct definition
- `c-api/c-api.h` - C API struct with phoneme fields
- `c-api/c-api.cc` - Populates phoneme fields, diagnostic logging

### piper-phonemize Repository
- `src/phonemize.hpp` - Function declarations
- `src/phonemize.cpp` - Position capture, word grouping, normalization

### Piper Repository
- `src/cpp/piper.cpp` - w_ceil return implementation
- `export_onnx.py` - w_ceil tensor export, metadata fix

### Listen2 Repository
- `Services/TTS/SherpaOnnx.swift` - Swift C API interface, diagnostic logging
- `Services/TTS/PhonemeAlignmentService.swift` - Alignment logic (multiple rewrites)
- `Services/TTS/SynthesisQueue.swift` - Removed wordMap guard
- `Services/TTS/TTSService.swift` - Cache clear on init, timeout logic
- `Services/TTS/PhonemeTimeline.swift` - Data structures (Nov 15 redesign)
- `Services/TTS/PhonemeTimelineBuilder.swift` - Timeline builder (Nov 15 redesign)
- `Services/TTS/WordHighlighter.swift` - CADisplayLink highlighting (Nov 15 redesign)
- `Services/TTS/AlignmentResult.swift` - Integer offsets (normalized text support)
- `Frameworks/sherpa-onnx.xcframework/` - iOS framework (rebuilt 8+ times)

---

## Bugs Fixed vs Bugs Remaining

### Fixed
1. Missing function calls to position tracking - Session 2
2. CMake downloading wrong repository - Session 3
3. Framework deployment script failing - Session 4
4. espeak phoneme events not enabled - Session 6
5. Swift rejecting valid data (required durations) - Session 6
6. C API counter using wrong array - Session 6
7. current_word pointer reset bug - Session 7
8. w_ceil tensor data type mismatch - Nov 14
9. Normalized text truncation - Nov 15
10. State contamination race condition - Nov 16

### Remaining (Partial List)
1. espeak sparse position events (12-75% coverage)
2. Position offset (off by 1-2 characters)
3. Text normalization mismatch (VoxPDF vs espeak)
4. Word count mismatch (28 vs 39 groups)
5. Duration extraction broken by TokenIDs changes
6. Character mapping sparse/incomplete
7. Synthesis timeout too short (100ms)
8. Dual playback with fallback
9. Unknown additional bugs preventing accurate highlighting

---

## Statistics

**Sessions documented:** 15+
**Time invested:** 3-4 days (Nov 12-16)
**Lines of logs analyzed:** 382,000+
**Bugs identified and fixed:** 10
**Framework rebuilds:** 8+
**Architectural rewrites:** 4
**Current highlighting accuracy:** 0-25%
**Feature status:** Completely unusable

---

**Last Updated:** Based on 19 session handoff documents
**Purpose:** Clinical record of what was tried, what was changed, and what bugs remain
