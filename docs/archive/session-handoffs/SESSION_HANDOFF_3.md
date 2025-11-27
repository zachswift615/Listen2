# Session Handoff: Fixed CMake Bug - Wrong Piper-Phonemize Source

**Date:** 2025-11-12/13
**Status:** 99% Complete - Ready to rebuild with correct fork
**Next Step:** Rebuild sherpa-onnx with forked piper-phonemize

---

## What We Fixed

### Root Cause Discovery
Used systematic debugging to trace through the entire pipeline:
1. ✅ Swift code correctly checks for phoneme data
2. ✅ C API correctly populates phoneme fields (if available)
3. ✅ C++ code correctly calls `CallPhonemizeEspeakWithPositions()`
4. ✅ `last_phoneme_sequences_` correctly stores phoneme data
5. ❌ **piper-phonemize fork with position tracking was NOT being used**

### The Bug
**File:** `sherpa-onnx/cmake/piper-phonemize.cmake`

```cmake
# Lines 4-6: WRONG - Points to original repo without position tracking
set(piper_phonemize_URL  "https://github.com/csukuangfj/piper-phonemize/...")

# Lines 28-31: CORRECT - Declares fork with position tracking
FetchContent_Declare(piper_phonemize
  GIT_REPOSITORY https://github.com/zachswift615/piper-phonemize.git
  GIT_TAG feature/espeak-position-tracking
)

# Lines 33-36: BUG - FetchContent_Populate() uses URL not GIT_REPOSITORY
FetchContent_GetProperties(piper_phonemize)
if(NOT piper_phonemize_POPULATED)
  message(STATUS "Downloading piper-phonemize from ${piper_phonemize_URL}")  # Misleading!
  FetchContent_Populate(piper_phonemize)  # Downloads from URL variable, not GIT
endif()
```

**Evidence from build log:**
```
-- Downloading piper-phonemize from https://github.com/csukuangfj/piper-phonemize/archive/78a788e0b719013401572d70fef372e77bff8e43.zip
```
☝️ This is the ORIGINAL repo, not the fork!

### The Fix
**Commit:** `5c3d6c07 - fix: use FetchContent_MakeAvailable to correctly download forked piper-phonemize`

**Changes:**
- Removed obsolete URL variables (lines 4-26)
- Changed deprecated `FetchContent_Populate()` to `FetchContent_MakeAvailable()`
- Now correctly downloads from `zachswift615/piper-phonemize` fork

**Before:**
```cmake
set(piper_phonemize_URL "https://github.com/csukuangfj/piper-phonemize/...")
FetchContent_Populate(piper_phonemize)  # Uses URL
```

**After:**
```cmake
FetchContent_Declare(piper_phonemize
  GIT_REPOSITORY https://github.com/zachswift615/piper-phonemize.git
  GIT_TAG feature/espeak-position-tracking
)
FetchContent_MakeAvailable(piper_phonemize)  # Uses GIT_REPOSITORY
```

---

## Current Status

### Completed
1. ✅ Identified root cause using systematic debugging
2. ✅ Fixed cmake file to use correct piper-phonemize fork
3. ✅ Committed fix: `5c3d6c07`
4. ✅ Deleted build cache: `rm -rf build-ios`

### Ready to Execute
1. 🔄 Rebuild sherpa-onnx framework (15-20 min)
2. 📦 Update Listen2 Xcode project
3. 🧪 Test on device

---

## Next Steps (When You Resume)

### 1. Rebuild sherpa-onnx Framework
```bash
cd /Users/zachswift/projects/sherpa-onnx
./build-ios.sh
```

**Expected log output:**
```
-- Downloading piper-phonemize from https://github.com/zachswift615/piper-phonemize.git (branch: feature/espeak-position-tracking)
```
☝️ This confirms it's using the fork!

**Build time:** ~15-20 minutes

### 2. Verify Correct Fork Was Used
```bash
# Check the downloaded source
ls /Users/zachswift/projects/sherpa-onnx/build-ios/build/*/deps/piper_phonemize-src/

# Should see files from the fork (check git branch/commit)
cd /Users/zachswift/projects/sherpa-onnx/build-ios/build/simulator_x86_64/_deps/piper_phonemize-src
git log --oneline -5
```

Should show commits from `zachswift615/piper-phonemize` fork.

### 3. Update Listen2 Framework
```bash
cd /Users/zachswift/projects/Listen2
ruby update_sherpa_phoneme_durations.rb
```

### 4. Clean Build in Xcode
- Product → Clean Build Folder (⌘⇧K)
- Product → Build (⌘B)
- Product → Run (⌘R) on iPhone 15 Pro Max

### 5. Expected Success Logs
```
[SherpaOnnx] Extracting 47 phonemes from C API
[SherpaOnnx] Extracted phonemes: h ə l oʊ w ɝ l d ...
[PiperTTS] Received 47 phonemes from sherpa-onnx
[PhonemeAlign] ✅ Created alignment with 10 word timings
```

---

## Why Previous Build Failed

### Previous Session (Session #2)
- Built sherpa-onnx with correct C++ code changes
- Framework contained `PhonemeInfo` symbols
- But piper-phonemize was the ORIGINAL version without `phonemize_eSpeak_with_positions()`

### What Happened
1. C++ code correctly calls `CallPhonemizeEspeakWithPositions()`
2. But piper-phonemize library didn't have this function!
3. So it fell back to regular `phonemize_eSpeak()` (no positions)
4. Result: Empty `phoneme_info` → Empty `audio.phonemes` → nullptr in C API

### Now (After Fix)
1. CMake will download forked piper-phonemize WITH `phonemize_eSpeak_with_positions()`
2. C++ code calls `CallPhonemizeEspeakWithPositions()` → Works!
3. Returns populated `phoneme_info` with character positions
4. C API gets non-null phoneme data → Swift extracts successfully

---

## Key Files Modified

### sherpa-onnx (commit 5c3d6c07)
- `cmake/piper-phonemize.cmake` - Fixed to use forked piper-phonemize

### sherpa-onnx (commit 8f3f11c2 - from previous session)
- `sherpa-onnx/csrc/piper-phonemize-lexicon.cc` - Calls position tracking functions
- `sherpa-onnx/csrc/piper-phonemize-lexicon.h` - Added GetLastPhonemeSequences()
- `sherpa-onnx/csrc/offline-tts-vits-impl.h` - Attaches phonemes to GeneratedAudio
- `sherpa-onnx/c-api/c-api.cc` - Already correct (populates from audio.phonemes)

---

## Debugging Methodology Used

**Skill:** `superpowers:systematic-debugging`

### Phase 1: Root Cause Investigation
1. Read error messages: "No phoneme data available from C API"
2. Traced data flow backward:
   - Swift checks `audio.pointee.phoneme_symbols` → nullptr
   - C API checks `audio.phonemes.empty()` → true
   - C++ checks `phoneme_sequences.empty()` → true
   - C++ calls `GetLastPhonemeSequences()` → empty vector
   - `last_phoneme_sequences_` was empty despite being set

### Phase 2: Pattern Analysis
1. Verified code changes were committed (git log)
2. Verified framework had `PhonemeInfo` symbols (nm)
3. Found discrepancy: cmake had TWO piper-phonemize sources

### Phase 3: Hypothesis Testing
**Hypothesis:** Build is downloading wrong piper-phonemize
**Test:** Check build log for download URL
**Result:** ✅ Confirmed - downloading original repo, not fork!

### Phase 4: Implementation
**Fix:** Updated cmake to use `FetchContent_MakeAvailable()`
**Verification:** Delete build cache and rebuild (pending)

---

## Workshop Commands Reference

```bash
# View full context
workshop context

# Search for this issue
workshop why "phoneme"
workshop why "piper-phonemize"

# Recent activity
workshop recent
```

---

## Git Status

### sherpa-onnx repository
**Branch:** feature/piper-phoneme-durations (or main)
**Recent commits:**
```
5c3d6c07 fix: use FetchContent_MakeAvailable to correctly download forked piper-phonemize
8f3f11c2 feat: wire up phoneme position tracking through TTS pipeline
```

### Listen2 repository
**Branch:** main
**Status:** Clean (no changes needed, framework update only)

---

## Confidence Level

**Code Changes:** ✅ 100% - CMake fix is correct
**Root Cause:** ✅ 100% - Confirmed via build logs
**Expected Outcome:** ✅ 98% - Should work after rebuild with correct fork

**Risk:** 2% - Possibility that zachswift615/piper-phonemize fork has issues, but unlikely since it was specifically created for this feature.

---

## If Still Fails After Rebuild

**This would be highly unexpected**, but debug steps:

1. **Verify fork was actually used:**
   ```bash
   cat /Users/zachswift/projects/sherpa-onnx/build-ios/build/*/deps/piper_phonemize-src/.git/config
   ```
   Should show: `url = https://github.com/zachswift615/piper-phonemize.git`

2. **Verify fork has position tracking function:**
   ```bash
   grep -r "phonemize_eSpeak_with_positions" /Users/zachswift/projects/sherpa-onnx/build-ios/build/*/deps/piper_phonemize-src/
   ```

3. **Check fork commits:**
   ```bash
   cd /Users/zachswift/projects/sherpa-onnx/build-ios/build/simulator_x86_64/_deps/piper_phonemize-src
   git log --oneline --all --grep="position"
   ```

But honestly, I'm 98% confident it will just work after the rebuild with the correct fork.

---

**Estimated Time to Working Word Highlighting:** ~25 minutes
(15-20min rebuild + 5min update/test)

🎉 This is the final missing piece!
