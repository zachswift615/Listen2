# Session Handoff: Systematic Debugging - Framework Deployment Issues

**Date:** 2025-11-12
**Status:** 95% Complete - Awaiting DerivedData cache clear test
**Next Step:** Clear Xcode cache and test, then add diagnostic logging if needed

---

## What We Fixed This Session

### Issue 1: CMake FetchContent Conflict (FIXED ✅)

**Problem:** Build failed with CMake error:
```
The binary directory ... is already used to build a source directory
```

**Root Cause:** Previous session used `FetchContent_MakeAvailable()` which automatically calls `add_subdirectory()`, but the script also manually called `add_subdirectory()` again.

**Fix:** Changed `cmake/piper-phonemize.cmake` to use the `FetchContent_GetProperties + FetchContent_Populate` pattern instead:

```cmake
# BEFORE (broken):
FetchContent_MakeAvailable(piper_phonemize)  # This calls add_subdirectory
add_subdirectory(${piper_phonemize_SOURCE_DIR} ...)  # Duplicate!

# AFTER (working):
FetchContent_GetProperties(piper_phonemize)
if(NOT piper_phonemize_POPULATED)
  FetchContent_Populate(piper_phonemize)
endif()
add_subdirectory(${piper_phonemize_SOURCE_DIR} ...)  # Only one call
```

**Commit:** Modified `cmake/piper-phonemize.cmake` (uncommitted change)

---

### Issue 2: Ruby Script Failed to Copy Framework (FIXED ✅)

**Problem:** Zero phonemes still returned after rebuild.

**Systematic Debugging Process:**
1. ✅ Verified correct fork downloaded: `zachswift615/piper-phonemize.git`
2. ✅ Verified fork contains `phonemize_eSpeak_with_positions` function
3. ✅ Verified sherpa-onnx C++ calls position function
4. ✅ Verified C++ populates `GeneratedAudio.phonemes`
5. ❌ **Framework in Listen2 had no `WithPositions` symbols!**

**Discovery:**
```bash
# New framework (just built): HAS symbols ✅
nm build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep WithPositions
# Output: CallPhonemizeEspeakWithPositions symbols found

# Old framework (in Listen2): NO symbols ❌
nm Listen2/Frameworks/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep WithPositions
# Output: (empty)

# Timestamp proof:
stat Listen2/Frameworks/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a
# 2025-11-09 16:31:33 (3 days old!)

stat build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a
# 2025-11-12 21:52:39 (just built)
```

**Root Cause:** The Ruby script `update_sherpa_phoneme_durations.rb` reported success but didn't actually copy the new framework.

**Fix:** Manually copied framework:
```bash
rm -rf /Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework
cp -R /Users/zachswift/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework \
      /Users/zachswift/projects/Listen2/Frameworks/
```

**Verification:** All symbols now present:
- ✅ `CallPhonemizeEspeakWithPositions`
- ✅ `piper::phonemize_eSpeak_with_positions`
- ✅ `piper::g_phoneme_capture`
- ✅ `piper::synth_callback`

---

### Issue 3: Xcode DerivedData Cache (TESTING ⏳)

**Problem:** Even with correct framework, still getting zero phonemes.

**Hypothesis:** Xcode caches frameworks in DerivedData. Product → Clean Build Folder only cleans YOUR build products, not cached third-party frameworks.

**Fix:** Clear DerivedData cache:
1. Close Xcode (⌘Q)
2. Delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*
   ```
3. Reopen Xcode
4. Clean Build Folder (⌘⇧K)
5. Build (⌘B)
6. Run on device (⌘R)

**Status:** Awaiting user test

---

## Complete Build & Deployment Process

### Prerequisites
- sherpa-onnx fork: `https://github.com/zachswift615/sherpa-onnx.git`
  - Branch: `feature/piper-phoneme-durations`
- piper-phonemize fork: `https://github.com/zachswift615/piper-phonemize.git`
  - Branch: `feature/espeak-position-tracking`

### Step 1: Verify sherpa-onnx Changes

**Location:** `/Users/zachswift/projects/sherpa-onnx`

**Key commits:**
```
5c3d6c07 fix: use FetchContent_MakeAvailable to correctly download forked piper-phonemize
8f3f11c2 feat: wire up phoneme position tracking through TTS pipeline
```

**Critical files modified:**
1. `cmake/piper-phonemize.cmake` - Downloads forked piper-phonemize
2. `sherpa-onnx/csrc/piper-phonemize-lexicon.cc` - Calls position tracking function
3. `sherpa-onnx/csrc/offline-tts-vits-impl.h` - Attaches phonemes to GeneratedAudio
4. `sherpa-onnx/c-api/c-api.cc` - Exposes phonemes through C API

**Uncommitted changes:**
- `cmake/piper-phonemize.cmake` - FetchContent fix (needs to be committed)

### Step 2: Build sherpa-onnx iOS Framework

**Time:** ~15-20 minutes

**Commands:**
```bash
cd /Users/zachswift/projects/sherpa-onnx

# IMPORTANT: Clean build to force re-download of piper-phonemize
rm -rf build-ios

# Build iOS framework
./build-ios.sh 2>&1 | tee /tmp/sherpa-build.log
```

**Verification - Check build log:**
```bash
grep "Downloading piper-phonemize" /tmp/sherpa-build.log
```

**Expected output:**
```
-- Downloading piper-phonemize from https://github.com/zachswift615/piper-phonemize.git (branch: feature/espeak-position-tracking)
```

❌ **DO NOT proceed if you see:**
```
-- Downloading piper-phonemize from https://github.com/csukuangfj/piper-phonemize/...
```

**Verification - Check symbols:**
```bash
# Verify WithPositions symbols exist
nm build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep WithPositions

# Should output 3 lines with CallPhonemizeEspeakWithPositions
```

**Verification - Check xcframework created:**
```bash
ls -la build-ios/sherpa-onnx.xcframework/
# Should show:
# - ios-arm64/ (device)
# - ios-arm64_x86_64-simulator/ (simulator)
```

### Step 3: Deploy to Listen2 Project

**CRITICAL:** The Ruby script may report success but fail to copy. Always verify manually!

**Attempt automatic update:**
```bash
cd /Users/zachswift/projects/Listen2
ruby update_sherpa_phoneme_durations.rb
```

**REQUIRED: Manual verification:**
```bash
# Check timestamp - should be recent (within minutes)
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" Frameworks/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a

# Check symbols
nm Frameworks/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep WithPositions
```

**If timestamp is old OR symbols are missing:**
```bash
# MANUAL COPY (guaranteed to work):
rm -rf /Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework
cp -R /Users/zachswift/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework \
      /Users/zachswift/projects/Listen2/Frameworks/

# Verify again
nm Frameworks/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep WithPositions
# MUST show CallPhonemizeEspeakWithPositions symbols!
```

### Step 4: Clear Xcode Cache

**CRITICAL:** Xcode caches frameworks even after Clean Build Folder!

**Process:**
1. **Close Xcode completely** (⌘Q, don't just hide)
2. **Delete DerivedData:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*
   ```
3. **Reopen Xcode**
4. **Clean Build Folder** (⌘⇧K)
5. **Build** (⌘B)
6. **Run on device** (⌘R)

### Step 5: Expected Success Logs

When working, you should see:
```
[SherpaOnnx] Extracting 47 phonemes from C API
[SherpaOnnx] Extracted phonemes: h ə l oʊ w ɝ l d ...
[PiperTTS] Received 47 phonemes from sherpa-onnx
[PhonemeAlign] ✅ Created alignment with 10 word timings
```

If still seeing:
```
⚠️  [SherpaOnnx] No phoneme data available from C API
[PiperTTS] Received 0 phonemes from sherpa-onnx
```

→ Proceed to diagnostic logging (see next section)

---

## If Still Failing: Add Diagnostic Logging

### Hypothesis to Test

The position tracking code path may not be executing. We need to verify:
1. Is `CallPhonemizeEspeakWithPositions` actually being called?
2. Is `phonemize_eSpeak_with_positions` returning positions?
3. Is espeak callback `synth_callback` being triggered?
4. Is `g_phoneme_capture.positions` being populated?

### Location: piper-phonemize Fork

**Repository:** `https://github.com/zachswift615/piper-phonemize.git`
**Branch:** `feature/espeak-position-tracking`
**File:** `src/phonemize.cpp`

### Add Logging to phonemize_eSpeak_with_positions

**Line ~188:** Add logging when callback is registered:
```cpp
// Set up synthesis callback to capture events
espeak_SetSynthCallback(synth_callback);

// DIAGNOSTIC: Confirm callback registration
fprintf(stderr, "[PIPER_DEBUG] Registered synth_callback for position tracking\n");
```

**Line ~201:** Add logging when capturing positions:
```cpp
// Clear and enable capture for this clause
g_phoneme_capture.positions.clear();
g_phoneme_capture.capturing = true;

// DIAGNOSTIC: Confirm capture enabled
fprintf(stderr, "[PIPER_DEBUG] Enabled phoneme capture for clause\n");
```

**Line ~209:** Add logging after espeak_Synchronize:
```cpp
espeak_Synchronize();

g_phoneme_capture.capturing = false;

// DIAGNOSTIC: Show captured positions
fprintf(stderr, "[PIPER_DEBUG] Captured %zu positions from espeak\n",
        g_phoneme_capture.positions.size());
```

**Before return (~360):** Add final summary:
```cpp
// DIAGNOSTIC: Final phoneme count
fprintf(stderr, "[PIPER_DEBUG] Returning %zu phoneme sequences with positions\n",
        positions.size());

} /* phonemize_eSpeak_with_positions */
```

### Add Logging to synth_callback

**File:** `src/phonemize.cpp`
**Location:** Inside `synth_callback` function (~line 140-160)

**At start of function:**
```cpp
static int synth_callback(short *wav, int numsamples, espeak_EVENT *events) {
  if (!g_phoneme_capture.capturing) return 0;

  // DIAGNOSTIC: Callback invoked
  fprintf(stderr, "[PIPER_DEBUG] synth_callback invoked, numsamples=%d\n", numsamples);
```

**When capturing phoneme:**
```cpp
case espeakEVENT_PHONEME:
  // DIAGNOSTIC: Phoneme event received
  fprintf(stderr, "[PIPER_DEBUG]   Phoneme event: pos=%d len=%d\n",
          events[i].text_position, events[i].length);

  g_phoneme_capture.positions.push_back({
    events[i].text_position,
    events[i].length
  });
  break;
```

### Rebuild Process After Adding Logging

```bash
# 1. Make changes in piper-phonemize fork (local clone or GitHub)

# 2. Commit changes to piper-phonemize
cd /path/to/piper-phonemize
git add src/phonemize.cpp
git commit -m "debug: add diagnostic logging for position tracking"
git push origin feature/espeak-position-tracking

# 3. Force rebuild of sherpa-onnx to fetch latest piper-phonemize
cd /Users/zachswift/projects/sherpa-onnx
rm -rf build-ios
./build-ios.sh 2>&1 | tee /tmp/sherpa-build-debug.log

# 4. Verify new framework has updated code
# Check build timestamp of piper_phonemize sources
ls -la build-ios/build/os64/_deps/piper_phonemize-src/src/phonemize.cpp

# 5. Copy framework to Listen2
rm -rf /Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework
cp -R build-ios/sherpa-onnx.xcframework \
      /Users/zachswift/projects/Listen2/Frameworks/

# 6. Clear Xcode cache
rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*

# 7. Build and run in Xcode
# Look for [PIPER_DEBUG] messages in Xcode console
```

### Expected Diagnostic Output

**If working correctly:**
```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] synth_callback invoked, numsamples=...
[PIPER_DEBUG]   Phoneme event: pos=0 len=1
[PIPER_DEBUG]   Phoneme event: pos=1 len=1
... (many more) ...
[PIPER_DEBUG] Captured 47 positions from espeak
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**If NOT working:**
```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] Captured 0 positions from espeak  ← ❌ Problem!
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

This would indicate espeak is NOT calling the callback, meaning:
- espeak-ng may not be built with callback support
- espeak library linkage issue
- Need to investigate espeak-ng fork/build

---

## Key Files Reference

### sherpa-onnx Repository
- `cmake/piper-phonemize.cmake` - Downloads piper-phonemize fork
- `sherpa-onnx/csrc/piper-phonemize-lexicon.h` - Declares `CallPhonemizeEspeakWithPositions`
- `sherpa-onnx/csrc/piper-phonemize-lexicon.cc` - Implements position tracking wrapper
- `sherpa-onnx/csrc/offline-tts-vits-impl.h` - Calls frontend and attaches phonemes
- `sherpa-onnx/csrc/phoneme-info.h` - PhonemeInfo struct definition
- `sherpa-onnx/c-api/c-api.h` - C API struct with phoneme fields
- `sherpa-onnx/c-api/c-api.cc` - Populates phoneme fields from C++

### Listen2 Project
- `Listen2/Listen2/SherpaOnnxBridge.swift` - C API → Swift bridge, extracts phonemes
- `Frameworks/sherpa-onnx.xcframework/` - iOS framework (must have WithPositions symbols!)

### Build Artifacts (Verification)
- `build-ios/sherpa-onnx.xcframework/` - Freshly built framework
- `build-ios/build/os64/_deps/piper_phonemize-src/` - Downloaded piper-phonemize source
- `build-ios/build/os64/libsherpa-onnx.a` - Combined static library

---

## Debugging Checklist

Before starting next session, verify:

- [ ] sherpa-onnx repo on correct branch: `feature/piper-phoneme-durations`
- [ ] Uncommitted cmake changes are NOT lost (back them up!)
- [ ] piper-phonemize fork has position tracking code (commit 71f9ebd)
- [ ] Build log confirms downloading from zachswift615/piper-phonemize
- [ ] Built framework has WithPositions symbols (nm check)
- [ ] Framework copied to Listen2/Frameworks/ (timestamp + symbols)
- [ ] Xcode DerivedData cleared
- [ ] Clean + Build + Run performed after cache clear

If still failing after all checks:
- [ ] Add diagnostic logging to piper-phonemize
- [ ] Rebuild sherpa-onnx to fetch updated fork
- [ ] Check console for [PIPER_DEBUG] messages
- [ ] Analyze where phoneme capture is failing

---

## Workshop Commands for Context

```bash
# View current session context
workshop context

# Search for phoneme-related decisions
workshop why "phoneme"

# Search for build-related issues
workshop search "build"

# Recent activity
workshop recent
```

---

## Critical Gotchas

⚠️ **Ruby script lies:** Reports success but doesn't copy framework. ALWAYS verify with nm + timestamp!

⚠️ **Xcode caches frameworks:** Product → Clean doesn't clear DerivedData. Must manually delete!

⚠️ **FetchContent_MakeAvailable:** Calls add_subdirectory internally. Don't call it twice!

⚠️ **CMake caches aggressively:** If piper-phonemize changes don't take effect, `rm -rf build-ios`

⚠️ **Symbol verification is critical:** Framework can have old code even if it "builds successfully"

---

## Success Criteria

✅ Build log shows: `Downloading piper-phonemize from https://github.com/zachswift615/piper-phonemize.git`

✅ Framework has symbols: `nm ... | grep WithPositions` returns results

✅ Timestamp recent: Framework modified within last hour

✅ Xcode logs show: `[SherpaOnnx] Extracting N phonemes from C API` (N > 0)

✅ Alignment succeeds: `[PhonemeAlign] ✅ Created alignment with N word timings`

---

**Estimated Time to Working (if DerivedData clear works):** 5 minutes

**Estimated Time to Working (if diagnostic logging needed):** 30-45 minutes
- 10 min: Add logging to piper-phonemize fork
- 20 min: Rebuild sherpa-onnx
- 5 min: Deploy + test
- 10 min: Analyze diagnostic output

🎯 **Confidence:** 85% that DerivedData clear will fix it. 95% that diagnostic logging will reveal the issue if not.
