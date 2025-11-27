# Session Handoff: Phoneme Position Tracking - Diagnostic Phase

**Date:** 2025-11-13
**Status:** 🎉 Words are highlighting! But positions are corrupted - diagnostic logging deployed
**Next Step:** Interpret diagnostic logs to find where position data gets corrupted

---

## 🎉 Major Victories This Session

### We Got Phoneme Positions Flowing End-to-End!

**Three critical bugs fixed:**

1. **Missing phoneme events** ✅
   - **Bug:** espeak-ng wasn't generating phoneme events
   - **Root cause:** `espeakINITIALIZE_PHONEME_EVENTS` flag missing in initialization
   - **Fix:** Added flag in `sherpa-onnx/csrc/piper-phonemize-lexicon.cc:365`
   - **Result:** 11,583 phoneme events captured (was 0 before)

2. **Swift rejecting valid data** ✅
   - **Bug:** Swift required BOTH `phoneme_durations` AND position data
   - **Root cause:** Condition checked for durations pointer even though we only have positions
   - **Fix:** Made durations optional in `Listen2/Services/TTS/SherpaOnnx.swift:157-159`
   - **Result:** Swift now reads position data without requiring durations

3. **C API num_phonemes always 0** ✅
   - **Bug:** `num_phonemes` set based on empty `phoneme_durations` array
   - **Root cause:** Count was set in durations block, never updated for positions
   - **Fix:** Set `num_phonemes = audio.phonemes.size()` in `c-api.cc:1326`
   - **Result:** Swift sees `num_phonemes=332` instead of 0

**Evidence of success:**
```
[SHERPA_C_API] GeneratedAudio: samples=362496, phoneme_durations=0, phonemes=332
[SHERPA_C_API] Copying 332 phonemes to C API struct
[SherpaOnnx] C API returned: num_phonemes=332, symbols=✓, durations=✗, char_start=✓, char_length=✓
[SherpaOnnx] Extracting 332 phonemes from C API
```

**Words are now highlighting in the app!** 🎊

---

## 🔍 Current Problem: Position Data Corruption

### The Issue

**Symptom:** All phonemes show identical character positions instead of unique sequential positions.

**Expected:**
```
h[0..<1] ə[1..<2] l[2..<3] oʊ[3..<5] ...
```

**Actual (from logs):**
```
m[1..<1] ˈ[1..<1] a[1..<1] ɪ[1..<9] k[9..<9] ...
```

**Impact:**
- Word alignment fails because phonemes can't be mapped to words
- 177 "no phonemes found" warnings
- All word timings show `@ 0.000s for 0.000s`
- Highlighting works but is very inaccurate

### Root Cause Analysis (from subagent)

**Critical finding:** espeak only emits **39 position events** but piper generates **332 phonemes** (12% coverage)

**The corruption chain:**
1. espeak-ng emits sparse position events (only ~12-75% of phonemes)
2. piper-phonemize tries to fill gaps but produces duplicate positions
3. Position data gets corrupted somewhere between C++ → C API → Swift
4. Swift receives all phonemes with identical positions like `[3..<3]`

**Where we need to look:**
- Is corruption happening in C++ (before C API)?
- Or in Swift pointer reading (after C API)?
- Or in the position calculation logic itself?

---

## 🎯 Diagnostic Logging Deployed

### What We Added

We deployed comprehensive logging at **three critical points** in the pipeline:

#### 1. C API Layer (sherpa-onnx/c-api/c-api.cc)

**Lines 1363-1371:** Logs first 5 phonemes being copied to C API
```cpp
fprintf(stderr, "[SHERPA_C_API] First %zu phonemes' position data:\n", sample_count);
for (size_t i = 0; i < sample_count; ++i) {
  fprintf(stderr, "  [%zu]: symbol='%s', char_start=%d, char_length=%d -> [%d..<%d]\n",
          i, audio.phonemes[i].symbol.c_str(),
          audio.phonemes[i].char_start, audio.phonemes[i].char_length,
          audio.phonemes[i].char_start, audio.phonemes[i].char_start + audio.phonemes[i].char_length);
}
```

#### 2. Swift Layer (Listen2/Services/TTS/SherpaOnnx.swift)

**Lines 164-172:** Logs first 5 phonemes received from C API
```swift
let sampleCount = min(5, phonemeCount)
print("[SherpaOnnx] First \(sampleCount) phonemes' raw position data:")
for i in 0..<sampleCount {
    let start = startsPtr[i]
    let length = lengthsPtr[i]
    print("  [\(i)]: char_start=\(start), char_length=\(length) -> range[\(start)..<\(start+length)]")
}
```

#### 3. Existing Logs (already in place)

- `[SHERPA_DEBUG]` - sherpa-onnx C++ layer (piper-phonemize-lexicon.cc)
- `[PIPER_DEBUG]` - piper-phonemize callback events
- `[PhonemeAlign]` - Swift alignment results

---

## 📖 How to Interpret the Diagnostic Logs

### Step-by-Step Guide

When you run the app, look for this sequence in the logs:

#### Example 1: Corruption in C++ (Before C API)

**What you'd see:**
```
[SHERPA_DEBUG] Sentence 0: phonemes=332, positions=332
[SHERPA_C_API] First 5 phonemes' position data:
  [0]: symbol='h', char_start=3, char_length=0 -> [3..<3]
  [1]: symbol='ə', char_start=3, char_length=0 -> [3..<3]
  [2]: symbol='l', char_start=3, char_length=0 -> [3..<3]
  ^^^^ ALL IDENTICAL ^^^^
[SherpaOnnx] First 5 phonemes' raw position data:
  [0]: char_start=3, char_length=0 -> range[3..<3]
  [1]: char_start=3, char_length=0 -> range[3..<3]
```

**Interpretation:** Data is already corrupted BEFORE reaching C API
**Where to fix:** sherpa-onnx C++ code (piper-phonemize-lexicon.cc) or piper-phonemize position calculation

#### Example 2: Corruption in Swift (After C API)

**What you'd see:**
```
[SHERPA_C_API] First 5 phonemes' position data:
  [0]: symbol='h', char_start=0, char_length=1 -> [0..<1]
  [1]: symbol='ə', char_start=1, char_length=1 -> [1..<2]
  [2]: symbol='l', char_start=2, char_length=1 -> [2..<3]
  ^^^^ CORRECT ^^^^
[SherpaOnnx] First 5 phonemes' raw position data:
  [0]: char_start=3, char_length=0 -> range[3..<3]
  [1]: char_start=3, char_length=0 -> range[3..<3]
  ^^^^ WRONG ^^^^
```

**Interpretation:** C API has correct data, Swift is reading it wrong
**Where to fix:** Swift pointer dereferencing in SherpaOnnx.swift

#### Example 3: Data is Correct (Corruption is Downstream)

**What you'd see:**
```
[SHERPA_C_API] First 5 phonemes' position data:
  [0]: symbol='h', char_start=0, char_length=1 -> [0..<1]
  [1]: symbol='ə', char_start=1, char_length=1 -> [1..<2]
  ^^^^ CORRECT ^^^^
[SherpaOnnx] First 5 phonemes' raw position data:
  [0]: char_start=0, char_length=1 -> range[0..<1]
  [1]: char_start=1, char_length=1 -> range[1..<2]
  ^^^^ ALSO CORRECT ^^^^
```

**Interpretation:** Position data is flowing correctly! Problem is elsewhere
**Where to look:** PhonemeAlignmentService logic or downstream processing

### Log Search Commands

```bash
# Find the diagnostic output
grep "\[SHERPA_C_API\] First.*phonemes' position data" ~/listen-2-logs-2025-11-13.txt -A 6

grep "\[SherpaOnnx\] First.*phonemes' raw position data" ~/listen-2-logs-2025-11-13.txt -A 6

# Compare them side-by-side
grep -E "\[SHERPA_C_API\] First|char_start=" ~/listen-2-logs-2025-11-13.txt | head -20
grep -E "\[SherpaOnnx\] First|char_start=" ~/listen-2-logs-2025-11-13.txt | head -20

# Find first occurrence of each
grep "\[SHERPA_C_API\] First" ~/listen-2-logs-2025-11-13.txt -A 5 -m 1
grep "\[SherpaOnnx\] First" ~/listen-2-logs-2025-11-13.txt -A 5 -m 1
```

---

## 🔧 What to Do Based on Log Analysis

### Scenario A: Corruption in C++ (piper-phonemize)

**If C API logs show identical positions like `[3..<3]` for all phonemes:**

**Problem:** piper-phonemize position calculation is wrong

**File to investigate:** `~/projects/piper-phonemize/src/phonemize.cpp`

**Specific issues to check:**

1. **Lines 291-304:** Position calculation when `keepLanguageFlags = true`
   ```cpp
   if (posIdx + 1 < g_phoneme_capture.positions.size()) {
     pos.length = g_phoneme_capture.positions[posIdx + 1] - pos.text_position;
   } else {
     pos.length = 1;
   }
   ```

   **Issue:** When espeak emits duplicate positions (e.g., `[3, 3, 3]`), this calculates:
   - `pos.length = 3 - 3 = 0` → creates `[3..<3]`

2. **Lines 327-339:** Same issue in the language flag filtering branch

**Root cause:** espeak's sparse position events (only 12-75% coverage) get duplicated to fill gaps, resulting in many phonemes with the same position.

**Possible fixes:**
- Don't rely on `nextPos - currentPos` when positions are duplicate
- Use a default length of 1 when positions don't increase
- Track the actual source text and calculate lengths properly
- Use a different approach entirely (forced alignment, duration models, etc.)

### Scenario B: Corruption in Swift Pointer Reading

**If C API logs show CORRECT positions but Swift logs show wrong positions:**

**Problem:** Swift pointer dereferencing issue

**File to investigate:** `Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

**Check lines 168-170:**
```swift
let start = startsPtr[i]
let length = lengthsPtr[i]
```

**Possible issues:**
- Wrong pointer type/casting
- Array indexing issue
- Memory alignment problem
- UnsafePointer vs UnsafeMutablePointer confusion

### Scenario C: Data is Flowing Correctly

**If both C API and Swift show CORRECT positions:**

**Problem is downstream in:**
- `PhonemeAlignmentService.swift` - alignment algorithm
- `PhonemeInfo` processing
- Word timing calculation

**Look for:**
- Incorrect range manipulation
- Off-by-one errors
- Character encoding issues (UTF-8 vs UTF-16)

---

## 📊 Known Issues from Log Analysis

### Issue 1: espeak Event Sparsity (CRITICAL)

**Evidence:**
- espeak captures only 39 positions for 332 phonemes (12% coverage)
- Other examples: 70/93 (75%), 126/211 (60%), 83/1223 (7%)

**Why this matters:**
- When 88% of phonemes have NO position data from espeak, gaps must be filled
- Filling strategy is duplicating the last known position
- This creates many phonemes with identical positions

**Underlying cause:**
- espeak may only emit position events at word boundaries, not per-phoneme
- OR espeak events are being dropped during callback
- OR callback is not being invoked for all synthesis chunks

**What to check:**
```bash
# Count how many position events espeak is actually emitting
grep "PHONEME event: pos=" ~/listen-2-logs-2025-11-13.txt | wc -l

# Count how many phonemes are generated
grep "Sentence.*phonemes=" ~/listen-2-logs-2025-11-13.txt

# Calculate coverage ratio
```

### Issue 2: No Duration Data

**All logs show:**
```
phoneme_durations=0, phonemes=332
```

**Impact:**
- Even if positions are fixed, timing will still be wrong
- Can't calculate when to advance highlighting without durations

**Why durations are missing:**
- Piper TTS model doesn't expose phoneme durations
- sherpa-onnx Generate() doesn't populate `phoneme_durations` field
- We're only getting position data, not timing data

**Possible solutions:**
1. Extract durations from Piper's internal w_ceil tensor
2. Use forced alignment (Montreal Forced Aligner)
3. Estimate durations from audio length / phoneme count
4. Use attention weights from TTS model

---

## 🗺️ The Complete Data Flow

```
Text: "Hello world"
   ↓
[espeak-ng] → Emits 39 position events (12% of phonemes)
   ↓
[piper-phonemize synth_callback] → Captures positions
   g_phoneme_capture.positions = [0, 0, 0, 6, 6, 6, ...]
   ↓
[piper-phonemize phonemize.cpp:291-304] → Calculates lengths
   PhonemePosition{text_position=0, length=0}  ← Bug: 0-0=0
   PhonemePosition{text_position=0, length=0}
   PhonemePosition{text_position=0, length=6}
   PhonemePosition{text_position=6, length=0}
   ↓
[sherpa-onnx C++ piper-phonemize-lexicon.cc] → Converts to PhonemeInfo
   PhonemeInfo{symbol="h", char_start=0, char_length=0}
   PhonemeInfo{symbol="ə", char_start=0, char_length=0}
   ↓
[sherpa-onnx C API c-api.cc] → Copies to C arrays
   char_start[] = [0, 0, 0, 6, 6, ...]
   char_length[] = [0, 0, 6, 0, 0, ...]
   ↓
[Swift SherpaOnnx.swift] → Reads C arrays
   PhonemeInfo(symbol: "h", textRange: 0..<0)
   PhonemeInfo(symbol: "ə", textRange: 0..<0)
   ↓
[Swift PhonemeAlignmentService] → Tries to align
   ❌ Fails because all positions are 0
```

---

## 🚀 Next Session Action Plan

### Step 1: Run the App with New Diagnostics (5 min)

1. Open Listen2 in Xcode
2. Build and run
3. Trigger TTS synthesis
4. Capture the console output

### Step 2: Find First Diagnostic Output (2 min)

```bash
# Save logs to file
# Then run:
grep "\[SHERPA_C_API\] First" ~/new-logs.txt -A 5 -m 1
grep "\[SherpaOnnx\] First" ~/new-logs.txt -A 5 -m 1
```

### Step 3: Compare the Two Outputs (2 min)

Look at the `char_start` and `char_length` values:
- Are they the same in both outputs?
- Are they all identical (e.g., all `char_start=3`)?
- Or are they properly sequential (e.g., `0, 1, 2, 3, 4`)?

### Step 4: Apply the Fix (varies)

**If corruption is in C++ (Scenario A):**
- Fix piper-phonemize position calculation
- Handle duplicate espeak positions better
- May need to rebuild framework (15-20 min)

**If corruption is in Swift (Scenario B):**
- Fix pointer dereferencing
- Quick Swift-only change

**If data is correct (Scenario C):**
- Fix alignment algorithm
- Or investigate espeak event sparsity

### Step 5: Investigate espeak Event Sparsity

**Even after fixing position corruption, you'll need to address:**

Why is espeak only emitting 12-75% position events?

**Check:**
1. Is `espeakINITIALIZE_PHONEME_EVENTS` flag actually working?
2. Are phoneme events being filtered somewhere?
3. Does espeak configuration need adjustment?

**Commands to investigate:**
```bash
# Count espeak events vs phonemes
grep -c "PHONEME event:" ~/logs.txt
grep "phonemes=" ~/logs.txt | head -1
```

---

## 📁 Files Modified This Session

### piper-phonemize (zachswift615/piper-phonemize)

**Branch:** `feature/espeak-position-tracking`

**Commits:**
- `356f629` - debug: add detailed event logging to diagnose missing phoneme events
- Earlier: Added `synth_callback` and position capture

**Key files:**
- `src/phonemize.cpp` - Position capture and calculation

### sherpa-onnx (zachswift615/sherpa-onnx)

**Branch:** `feature/piper-phoneme-durations`

**Commits:**
- `2955dcad` - debug: log first 5 phonemes' position data in C API
- `a7e84ac9` - fix: set num_phonemes based on phonemes array, not durations
- `eb972b31` - debug: add comprehensive diagnostics for phoneme position data flow
- `0ef460d3` - fix: enable phoneme events in espeak-ng initialization

**Key files:**
- `sherpa-onnx/csrc/piper-phonemize-lexicon.cc` - espeak initialization, position conversion
- `sherpa-onnx/c-api/c-api.cc` - C API boundary, diagnostic logging

### Listen2

**Branch:** `main`

**Commits:**
- `9c72cd7` - debug: add logging for first 5 phonemes' raw position data
- `06010ba` - fix: prevent crash from invalid phoneme text ranges
- `b7ac491` - fix: make phoneme_durations optional in Swift bridge

**Key files:**
- `Listen2/Services/TTS/SherpaOnnx.swift` - Swift C API interface

---

## 🎓 Technical Context

### Why Position Tracking is Hard

**The challenge:** Phonemes don't map 1:1 to characters

**Examples:**
- One character → multiple phonemes: "x" → [k s]
- Multiple characters → one phoneme: "sh" → [ʃ]
- IPA stress markers: "ˈ" has no character position
- Diacritics and decomposed characters

**espeak's approach:**
- Emits position events at certain boundaries (words? syllables?)
- Not documented what triggers a position event
- Position is UTF-8 byte offset, not character index

**Current gap-filling strategy:**
- When phoneme N has no espeak event, use position from phoneme N-1
- Calculates length as: `next_position - current_position`
- This fails when positions are duplicate: `3 - 3 = 0` → `[3..<3]`

### Why Duration Tracking is Missing

**The TTS pipeline:**
```
Text → Phonemes → Duration Prediction → Mel Spectrogram → Audio
```

Piper TTS DOES predict durations internally (w_ceil tensor), but:
- sherpa-onnx doesn't expose them
- Would need to modify Piper integration to extract durations
- Or use post-hoc forced alignment instead

---

## 🆘 Emergency Recovery

If you get completely stuck:

### Fallback 1: Disable Position Validation

In `SherpaOnnx.swift`, comment out the position data and use placeholders:

```swift
// TEMPORARY: Use placeholder positions until corruption is fixed
let textRange = i..<(i+1)  // Each phoneme = 1 char
```

This won't be accurate but will prevent crashes and let you test other parts.

### Fallback 2: Use Simple Duration Estimation

```swift
// Estimate duration = audio length / phoneme count
let estimatedDuration = TimeInterval(audio.pointee.n) / TimeInterval(audio.pointee.sample_rate) / Double(phonemeCount)
```

Won't be perfect but better than 0.

### Fallback 3: Contact Me

If logs show something completely unexpected:
1. Capture full diagnostic output (both C API and Swift logs)
2. Share the pattern you're seeing
3. I can help interpret what's happening

---

## 📈 Success Metrics

**Session 6 was successful because:**
- ✅ Phoneme events: 0 → 11,583 (infinite improvement!)
- ✅ Phonemes reaching Swift: 0 → 332 per synthesis
- ✅ Word highlighting: Not working → Working (but inaccurate)
- ✅ End-to-end data flow: Broken → Connected

**Session 7 will be successful when:**
- ✅ Position data shows sequential values: `[0..<1] [1..<2] [2..<3]` not `[3..<3] [3..<3]`
- ✅ Alignment produces reasonable phoneme→word mappings
- ✅ Word highlighting timing is roughly correct
- 🎯 STRETCH: Duration data flows through (may need separate session)

---

## 🔗 Related Documentation

- **SESSION_HANDOFF_3.md** - Framework deployment debugging
- **SESSION_HANDOFF_5.md** - Diagnostic logging implementation
- **espeak-ng docs:** `/Users/zachswift/projects/sherpa-onnx/build-ios/_deps/espeak_ng-src/src/include/espeak/speak_lib.h`

---

**Prepared by:** Claude (Session 6)
**Ready for:** Position corruption diagnosis via diagnostic logs
**Confidence:** 95% that diagnostic logs will reveal exact corruption point
**Estimated time to fix:** 1-3 hours depending on where corruption is found

🎯 **Next session starts with:** Run app, capture diagnostic logs, compare C API vs Swift output!
