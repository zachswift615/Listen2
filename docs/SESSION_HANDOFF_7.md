# Session 7 Handoff - Word Highlighting Debugging

**Date:** November 13, 2025
**Status:** Word highlighting still not working after multiple bug fixes
**Latest logs:** `~/listen-2-logs-2025-11-13.txt`

---

## 🎯 Session Goal

Implement word-level highlighting for Piper TTS using phoneme position tracking from espeak-ng.

---

## ✅ What We Accomplished

### 1. Clarified Requirements
- **Goal:** Word-level highlighting (NOT character-level)
- **Approach:** Use espeak's word-level position data to identify which word to highlight
- **Implementation:** Option B (Full Word Mapping) - all phonemes in a word get the word's full character range

### 2. Fixed Multiple Bugs in piper-phonemize

#### Bug #1: Option B Code Not Committed/Pushed
- **Issue:** First subagent implemented Option B correctly, but it was never committed to git
- **Result:** sherpa-onnx was pulling old code from GitHub
- **Fix:** Committed and pushed Option B implementation (commit `ea63fed`)

#### Bug #2: `current_word` Pointer Reset Bug
- **Issue:** `current_word` was a local variable in `synth_callback`, reset to `nullptr` on each of 1,601 callback invocations
- **Symptom:** Words captured 0-1 phonemes instead of multiple (e.g., `Word #0: phonemes=[]`)
- **Root Cause:** espeak calls `synth_callback` 1000+ times during synthesis; local variables reset each time
- **Fix:** Moved `current_word` to `PhonemeEventCapture` struct so it persists across callbacks (commit `25b6816`)

### 3. Framework Rebuilds
- Rebuilt sherpa-onnx iOS framework 3 times with fixes
- Final build completed at ~21:55 with exit code 0
- Framework location: `/Users/zachswift/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework`

---

## 📊 Current State

### What's Working
✅ **WORD events captured** - logs show `"--> WORD event: text_pos=X, length=Y"`
✅ **New code is running** - diagnostic messages confirm latest code deployed
✅ **Data flows through pipeline** - C API → Swift bridge working

### What's NOT Working
❌ **Word highlighting doesn't happen**
❌ **Unknown why** - need log analysis to determine next bug

---

## 🔍 How to Interpret the Latest Logs

The logs in `~/listen-2-logs-2025-11-13.txt` contain diagnostic output at multiple levels:

### 1. Piper-Phonemize Debug Output

Look for `[PIPER_DEBUG]` messages:

```
[PIPER_DEBUG] synth_callback invoked, numsamples=1324
[PIPER_DEBUG]   Event #X: type=1, text_pos=Y, length=Z     ← WORD event
[PIPER_DEBUG]   --> WORD event: text_pos=Y, length=Z        ← WORD handler
[PIPER_DEBUG]   Event #X: type=7, text_pos=Y, length=0     ← PHONEME event
[PIPER_DEBUG]   --> PHONEME event: text_pos=Y (phoneme #N)  ← PHONEME handler
[PIPER_DEBUG]       -> Assigned to word at pos=Y, len=Z     ← Phoneme-to-word association
[PIPER_DEBUG]   Word #0: pos=1, len=5, phonemes=[0,1,2,3,4] ← Word grouping summary
```

**Key metrics to check:**
- **synth_callback invocations:** Should be 1000+ (proves callbacks working)
- **Word groupings:** Should show multiple phonemes per word (e.g., `phonemes=[0,1,2,3,4]`)
- **NOT:** Empty word groups like `phonemes=[]` (indicates bug #2 still present)

### 2. Sherpa C API Output

Look for `[SHERPA_C_API]` messages:

```
[SHERPA_C_API] First 5 phonemes' position data:
  [0]: symbol='k', char_start=1, char_length=5 -> [1..<6]
  [1]: symbol='ˈ', char_start=1, char_length=5 -> [1..<6]  ← SAME range (correct!)
  [2]: symbol='ʌ', char_start=1, char_length=5 -> [1..<6]  ← SAME range (correct!)
```

**Expected (Option B working):** All phonemes in the same word have **identical** `char_start` and `char_length`.

**Bad signs:**
- `char_start=-1, char_length=0 -> [-1..<-1]` (no position assigned)
- Different ranges for phonemes in same word (word grouping failed)
- `[0..<0]`, `[2..<2]` empty ranges (old bug still present)

### 3. Swift Side Output

Look for `[SherpaOnnx]` messages:

```
[SherpaOnnx] First 5 phonemes' raw position data:
  [0]: char_start=1, char_length=5 -> range[1..<6]
  [1]: char_start=1, char_length=5 -> range[1..<6]
```

Should match the C API output. If different, indicates Swift pointer/conversion issue.

### 4. Alignment/Highlighting Logs

Look for:
- `[SynthesisQueue]` messages about word maps
- `[PhonemeAlignmentService]` messages about DTW alignment
- `[TTSService]` messages about highlighting

**Key error:** `"No word map available for alignment"` indicates VoxPDF word extraction issue.

---

## 🐛 Known Issues After This Session

### Issue #1: Words Still Have Missing Phonemes
From the latest logs (need to verify):
- Some words may still show `phonemes=[]` or only 1-2 phonemes
- If true, the `current_word` persistence fix didn't fully work

### Issue #2: Many Phonemes Show `[-1..<-1]`
From earlier in this session:
- 50 phonemes had `char_start=-1` (no position)
- 34 phonemes had valid positions
- This suggests ~60% of phonemes aren't being assigned to words

### Issue #3: Unknown Blocker for Highlighting
Even if positions are correct, words might not highlight due to:
- Word map generation issue in Swift
- DTW alignment failure
- VoxPDF word extraction problem
- Timing/threading issue

---

## 🚀 Next Session Action Plan

### Step 1: Analyze Latest Logs

Run these greps on `~/listen-2-logs-2025-11-13.txt`:

```bash
# Check word groupings - should show multiple phonemes per word
grep "Word #" ~/listen-2-logs-2025-11-13.txt | head -20

# Count phonemes with valid positions vs [-1..<-1]
grep "char_start=" ~/listen-2-logs-2025-11-13.txt | grep "char_start=-1" | wc -l
grep "char_start=" ~/listen-2-logs-2025-11-13.txt | grep -v "char_start=-1" | wc -l

# Check first 5 phonemes diagnostic
grep "\[SHERPA_C_API\] First" ~/listen-2-logs-2025-11-13.txt -A 5 | tail -15

# Look for alignment errors
grep -i "no word map\|alignment\|phoneme.*not found" ~/listen-2-logs-2025-11-13.txt | head -20
```

### Step 2: Determine Root Cause

Based on log analysis, the issue is likely ONE of:

**A) Word Grouping Still Broken**
- Symptom: `Word #X: phonemes=[]` or `phonemes=[0]` (only 1 phoneme)
- Cause: `current_word` persistence fix didn't work
- Solution: Debug why phonemes aren't being added to `current_word->phoneme_indices`

**B) Position Distribution Logic Error**
- Symptom: Valid word groupings BUT phonemes still have `[-1..<-1]` or wrong positions
- Cause: The position_map isn't being applied correctly in lines 340-406 of phonemize.cpp
- Solution: Check the position distribution code that maps words to phonemes

**C) Swift-Side Issue**
- Symptom: C API shows correct positions BUT Swift shows different or highlighting doesn't work
- Cause: Word map generation, DTW alignment, or highlighting logic broken
- Solution: Debug Swift code in PhonemeAlignmentService or TTSService

**D) Text-Position Mismatch**
- Symptom: Positions are correct BUT don't match VoxPDF word positions
- Cause: espeak positions are character offsets in normalized text, VoxPDF has different character offsets
- Solution: May need text normalization or position mapping layer

### Step 3: Fix the Right Bug

Don't guess - use the logs to determine which bug it is, THEN fix it.

---

## 📁 Key Files & Locations

### Modified Code
- **piper-phonemize:** `/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp`
  - Lines 136-157: WordInfo struct and PhonemeEventCapture
  - Lines 159-232: synth_callback with WORD/PHONEME handling
  - Lines 340-406: Position distribution logic

- **Git commits:**
  - `ea63fed`: Initial Option B implementation
  - `25b6816`: Fixed current_word persistence bug

### Framework
- **sherpa-onnx:** `/Users/zachswift/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework`
- **Listen2 links to:** `../../../sherpa-onnx/build-ios/sherpa-onnx.xcframework` (NOT the Frameworks/ copy)

### Logs
- **Current session:** `~/listen-2-logs-2025-11-13.txt` (contains multiple test runs)
- **Previous session:** `~/listen-2-logs-2025-11-13.txt` (same file, appended)

### Documentation
- **Swift architecture:** `/Users/zachswift/projects/Listen2/docs/WORD_HIGHLIGHTING_*.md` (4 files, created by subagent)
- **Previous handoff:** `/Users/zachswift/projects/Listen2/docs/SESSION_HANDOFF_6.md`

---

## 🎓 Key Learnings

### 1. espeak-ng Event Model
- espeak provides **word-level** position tracking, not phoneme-level
- All phonemes in a word get the same `text_position` (the word's start position)
- WORD events (type=1) provide position + length
- PHONEME events (type=7) provide phoneme + word's position

### 2. Callback Persistence Issue
- espeak calls `synth_callback` 1000+ times during synthesis
- Local variables reset on each call
- Must use static/global storage or struct fields for data that persists across calls

### 3. GitHub-Based Build
- sherpa-onnx's CMake clones piper-phonemize from GitHub
- Local uncommitted changes are NOT included in the build
- Must commit AND push to GitHub before rebuilding sherpa-onnx

### 4. Word-Level vs Character-Level
- User wants WORD-level highlighting (highlight entire words)
- Swift code uses character ranges to identify WHICH word to highlight
- Then highlights the whole word (not individual characters)

---

## 🆘 Emergency Recovery

If you need to rollback to a known state:

### Revert piper-phonemize Changes
```bash
cd /Users/zachswift/projects/piper-phonemize
git log --oneline -5  # Find commit before Option B
git revert 25b6816 ea63fed  # Revert both commits
git push origin feature/espeak-position-tracking
```

### Rebuild sherpa-onnx
```bash
cd /Users/zachswift/projects/sherpa-onnx
rm -rf build-ios
./build-ios.sh
```

### Test Without Position Tracking
To verify highlighting works WITHOUT position tracking:
- Comment out position assignment code in Swift
- Hardcode test ranges for debugging
- Verify UI highlighting works in isolation

---

## 💬 Context for Next Session

The user has been patient through multiple debugging sessions. They understand:
- This is complex TTS integration work
- We're working at multiple layers (espeak → piper → sherpa → Swift)
- Word-level highlighting is the goal (NOT character-level)

**Communication style:**
- Be direct and honest about what's broken
- Use subagents for heavy lifting (log analysis, builds)
- Focus on systematic debugging, not guessing
- Show evidence from logs before proposing fixes

**Key phrases to avoid:**
- "Should work now" (without testing)
- "Try rebuilding" (without diagnosing first)
- Character-level highlighting (that's not the goal)

---

## 📝 Session Summary

**Time invested:** ~2 hours
**Bugs fixed:** 2 major bugs in piper-phonemize
**Framework rebuilds:** 3
**Code commits:** 2
**Status:** Implementation appears correct, but highlighting still doesn't work - need log analysis to find next bug

**Next session should start with:** Analyze the latest logs to determine the ACTUAL blocker, then fix it systematically.

---

Good luck! 🚀
