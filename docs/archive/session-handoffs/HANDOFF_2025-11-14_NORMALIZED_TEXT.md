# Session Handoff: Normalized Text Integration
**Date:** November 14, 2025
**Status:** Ready for Manual Testing (Critical Bugs Fixed)
**Next Session:** Manual testing and debugging on device

---

## 🎯 What Was Accomplished

### Tasks 1-8: Complete TTS Pipeline Implementation ✅

Successfully implemented the **espeak Normalized Text Integration** plan across the entire TTS stack:

1. ✅ **espeak-ng** (forked) - Captures normalized text ("Dr." → "Doctor", "123" → "one hundred twenty three")
2. ✅ **piper-phonemize** (modified) - Extracts normalized text from espeak-ng
3. ✅ **sherpa-onnx** (modified) - Threads normalized text through C API
4. ✅ **Swift wrapper** - Extracts from C API into GeneratedAudio struct
5. ✅ **PhonemeAlignmentService** - Maps VoxPDF words to normalized phoneme positions
6. ✅ **iOS Framework** - Rebuilt sherpa-onnx.xcframework with all changes

### Critical Bugs Fixed 🔧

#### Bug #1: Stale Normalized Text from C API
**Problem:** sherpa-onnx C API returned cached text from previous synthesis calls
**Symptoms:** Text "integration with sophisticated orchestration frameworks" appeared for unrelated paragraphs
**Root Cause:** Matcha, Kokoro, and Kitten TTS implementations weren't capturing normalized text
**Fix:** Updated all three implementations to extract data from PiperPhonemizeLexicon
**Commit:** sherpa-onnx `498f9071`

#### Bug #2: String.Index Out of Bounds Crash
**Problem:** Using String.Index from one string with a different string
**Symptoms:** Fatal error at AlignmentResult.swift:61 - "String index is out of bounds"
**Root Cause:** AlignmentResult used String.Index values with a dummy string
**Fix:** Changed to integer offsets throughout the codebase
**Commit:** Listen2 `0c36e3de`, `3cc0d3e`

---

## 📊 Current Status

### ✅ Working
- espeak-ng normalized text capture (tested with "u.s.a." → "usa")
- piper-phonemize normalized text extraction
- sherpa-onnx C API data flow
- Swift wrapper extraction
- PhonemeAlignmentService mapping algorithm (fixed critical ceiling division bug)
- No crashes on app launch or initial playback

### ⚠️ Needs Testing
- **End-to-end word highlighting with abbreviations** (not yet tested on device)
- Normalized text accuracy with real PDFs
- Multiple TTS models (Matcha, Kokoro, Kitten) with normalized text
- Character position mapping correctness
- Performance with long documents

### 🔴 Known Issues (from first test attempt)

**Issue #1: App froze after first line**
- Symptom: Word highlighting worked briefly, then app froze
- Audio continued playing after force-quit
- Logs: `/Users/zachswift/listen-2-logs-2025-11-14` (381,580 lines)
- Status: Both crash causes fixed, but untested if freeze is resolved

**Issue #2: Phoneme duration estimation**
- All 2193 phonemes had duration = 0
- Fallback: Estimated 109.65s duration
- Related to: w_ceil tensor issue (separate session working on this)
- Impact: May affect highlight timing accuracy

**Issue #3: Missing phonemes for words**
- Words 105-123 showed "⚠️ No phonemes found, using estimate"
- Could be related to normalized text mismatch (now fixed)
- Or could indicate phoneme text position mismatch

---

## 🔬 Testing Checklist

### Before Device Testing

1. **Build the app:**
   ```bash
   cd /Users/zachswift/projects/Listen2/Listen2/Listen2
   xcodebuild build -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)'
   ```

2. **Check for compilation errors**
   - Should build successfully
   - Only pre-existing warnings expected

3. **Run in Xcode:**
   - Select iPhone device
   - Press ⌘R
   - Watch for immediate crashes

### Device Testing Scenarios

#### Test 1: Simple Abbreviation
**PDF Text:** "Dr. Smith visited the clinic."

**Expected:**
- "Dr." highlights when "Doctor" is spoken
- Highlight duration matches full word "Doctor"
- No crashes or freezes

**Check:**
- Does highlighting appear?
- Does it stay lit for the full word?
- Any console errors?

#### Test 2: Multiple Abbreviations
**PDF Text:** "Dr. Smith's office is at 123 Main St."

**Expected:**
- "Dr." highlights during "Doctor"
- "123" highlights during "one hundred twenty three"
- "St." highlights during "Street"

**Check:**
- All three abbreviations handled correctly?
- Timing synchronized?
- App performance?

#### Test 3: Long Document
**Test with:** Actual book/article with many abbreviations

**Watch for:**
- Memory issues
- Freezing after N paragraphs
- Audio playback continuing after freeze/crash

### Log Collection

**Enable detailed logging:**
```swift
// Check these print statements are active:
[SherpaOnnx] Extracted normalized text
[PhonemeAlign] Normalized text length
[PhonemeAlign] Character mapping entries
```

**Collect logs:**
1. Connect iPhone via cable
2. Window → Devices and Simulators → Console
3. Filter: "SherpaOnnx" OR "PhonemeAlign"
4. Save to file for analysis

---

## 🗂️ Key Files Modified

### espeak-ng
- `src/libespeak-ng/translate.c` - Normalized text buffer and capture logic
- `src/include/espeak-ng/speak_lib.h` - API declarations
- `src/libespeak-ng/espeak_api.c` - API implementations
- `tests/normalized_text_test.c` - Test suite

**Repository:** `/Users/zachswift/projects/espeak-ng`
**Branch:** `feature/expose-normalized-text`
**Key Commits:** `c1383028`, `fc13d177`, `f1e8ec93`

### piper-phonemize
- `src/phonemize.hpp` - PhonemeResult struct with normalized_text
- `src/phonemize.cpp` - phonemize_eSpeak_with_normalized() implementation
- `CMakeLists.txt` - Uses local espeak-ng (relative path)
- `test_normalized_text.cpp` - Test suite

**Repository:** `/Users/zachswift/projects/piper-phonemize`
**Branch:** `feature/espeak-position-tracking`
**Key Commits:** `55b0ac10`, `0efefc6`

### sherpa-onnx
- `sherpa-onnx/c-api/c-api.h` - Added normalized_text, char_mapping to struct
- `sherpa-onnx/c-api/c-api.cc` - C API bridge implementation
- `sherpa-onnx/csrc/offline-tts.h` - C++ struct updates
- `sherpa-onnx/csrc/offline-tts-vits-impl.h` - VITS normalized text capture
- `sherpa-onnx/csrc/offline-tts-matcha-impl.h` - Matcha fix (Bug #1)
- `sherpa-onnx/csrc/offline-tts-kokoro-impl.h` - Kokoro fix (Bug #1)
- `sherpa-onnx/csrc/offline-tts-kitten-impl.h` - Kitten fix (Bug #1)
- `sherpa-onnx/csrc/piper-phonemize-lexicon.h/.cc` - Integration layer
- `cmake/piper-phonemize.cmake` - Uses local piper-phonemize
- `cmake/espeak-ng-for-piper.cmake` - Uses local espeak-ng

**Repository:** `/Users/zachswift/projects/sherpa-onnx`
**Branch:** `feature/piper-phoneme-durations`
**Key Commits:** `4dd3f5fe`, `44bb9bf3`, `8a24b438`, `498f9071`

### Listen2
- `Services/TTS/SherpaOnnx.swift` - Extract normalized_text from C API
- `Services/TTS/PiperTTSProvider.swift` - SynthesisResult with normalized_text
- `Services/TTS/PhonemeAlignmentService.swift` - Critical mapping logic
- `Services/TTS/AlignmentResult.swift` - Fixed String.Index bug
- `Services/TTS/WordAlignmentService.swift` - Updated for integer offsets
- `Services/TTS/SynthesisQueue.swift` - Pass normalized_text to alignment
- `Tests/Services/TTS/PhonemeAlignmentAbbreviationTests.swift` - Test suite
- `Frameworks/sherpa-onnx.xcframework` - Rebuilt with all fixes

**Repository:** `/Users/zachswift/projects/Listen2`
**Branch:** `main`
**Key Commits:** `0769d79`, `20ead81`, `3a8cab5`, `30b7ccc`, `6823602`, `0c36e3de`, `3cc0d3e`

---

## 🐛 Debugging Guide

### If App Freezes

1. **Check console for:**
   ```
   [PhonemeAlign] ⚠️ No phonemes found
   Thread 24: Fatal error
   String index is out of bounds
   ```

2. **Look for infinite loops in:**
   - PhonemeAlignmentService.alignWithNormalizedMapping
   - mapToNormalized function

3. **Verify normalized text:**
   ```
   [SherpaOnnx] Extracted normalized text: '...'
   ```
   Should match the length of original text (±50%)

### If Highlighting is Wrong

1. **Check character mapping:**
   ```
   [PhonemeAlign] Character mapping entries: N
   ```
   Should have entries proportional to text length

2. **Verify phoneme positions:**
   - Phonemes should have textRange in normalized text coordinates
   - Use logs to see what ranges are being matched

3. **Check mapToNormalized output:**
   - Add logging in PhonemeAlignmentService.swift:560
   - Verify mapped positions are reasonable

### If Audio Plays But No Highlighting

1. **Check alignment results:**
   ```
   [PhonemeAlign] ✅ Aligned N words
   ```
   Should match word count in paragraph

2. **Verify word timings have duration > 0**

3. **Check if AlignmentResult.WordTiming is being created with valid data**

---

## 📈 Performance Considerations

### Build Times
- espeak-ng: ~30 seconds
- piper-phonemize: ~20 seconds
- sherpa-onnx iOS framework: ~5 minutes (3 architectures)
- Total rebuild time: ~6 minutes

### Framework Size
- sherpa-onnx.xcframework: 46 MB
- Includes espeak-ng language data for all languages
- Could be optimized by removing unused languages

### Runtime Performance
- Normalized text extraction: Negligible overhead
- Character mapping: O(n) where n = text length
- PhonemeAlignmentService mapping: O(w*p) where w = words, p = phonemes per word
- Expected impact: < 50ms per paragraph

---

## 🔗 Related Issues

### w_ceil Tensor Issue
**Separate session working on this**
**Impact:** Phoneme durations are all 0, requiring estimation
**Workaround:** PhonemeAlignmentService estimates duration
**Status:** Models being re-exported with proper w_ceil tensor

### Native iOS Voice Fallback
**Observed:** App fell back to system voice during crash
**Potential cause:** Sherpa-onnx error triggered AVFoundation fallback
**Action:** Watch for this in next test

### Audio Continues After Force-Quit
**Observed:** TTS audio kept playing after app was killed
**Potential cause:** Audio session not properly released
**Action:** Verify AVAudioSession cleanup on crash

---

## 📝 Workshop Notes

Use these commands to query project context:

```bash
# View all normalized text related decisions
workshop why "normalized text"

# Search for alignment issues
workshop search "alignment"

# Add notes from this test session
workshop note "Testing normalized text integration - [results here]"

# Record any new gotchas
workshop gotcha "Specific issue found during testing" -t normalized-text -t word-highlighting
```

---

## 🎯 Next Session Goals

### Priority 1: Manual Testing
1. Run app on iPhone with both bug fixes
2. Test with simple abbreviation PDF
3. Verify no crashes or freezes
4. Check highlighting accuracy

### Priority 2: Debug Any Issues
1. Collect detailed logs
2. Analyze timing/synchronization
3. Fix any remaining edge cases

### Priority 3: If Testing Succeeds
1. Test with multiple TTS models (Matcha, Kokoro, Kitten)
2. Performance testing with long documents
3. Prepare for Task 10: Contribute to open source

---

## ⚡ Quick Start Commands

```bash
# Build and run on device
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)'

# Rebuild sherpa-onnx framework (if needed)
cd /Users/zachswift/projects/sherpa-onnx
./build-ios.sh
cp -R build-ios/sherpa-onnx.xcframework /Users/zachswift/projects/Listen2/Frameworks/

# View recent commits
cd /Users/zachswift/projects/Listen2
git log --oneline -10

# Check git status across all repos
cd /Users/zachswift/projects/espeak-ng && git status
cd /Users/zachswift/projects/piper-phonemize && git status
cd /Users/zachswift/projects/sherpa-onnx && git status
cd /Users/zachswift/projects/Listen2 && git status
```

---

## 📞 Contact Points

If issues arise, check these resources:

1. **Plan document:** `/Users/zachswift/projects/Listen2/docs/plans/2025-01-14-espeak-normalized-text-integration.md`
2. **Crash logs:** `/Users/zachswift/listen-2-logs-2025-11-14/`
3. **Bug fix summary:** `/Users/zachswift/projects/Listen2/docs/CHARACTER_MAPPING_FIX_SUMMARY.md`
4. **Workshop context:** `workshop context`

---

## ✨ Summary

**What's Done:**
- ✅ Complete normalized text pipeline (espeak → piper → sherpa → Swift)
- ✅ Fixed String.Index crash
- ✅ Fixed stale normalized text bug
- ✅ Algorithm for mapping VoxPDF words to normalized phonemes
- ✅ iOS framework rebuilt with all changes

**What's Next:**
- 🧪 Manual testing on device
- 🐛 Debug any issues that arise
- 🎯 Verify abbreviation highlighting works correctly

**The Goal:**
Make "Dr." highlight when "Doctor" is spoken, "St." when "Street" is spoken, and all abbreviations/numbers work perfectly with word-level highlighting.

**We're at the finish line - just needs real-world testing! 🚀**
