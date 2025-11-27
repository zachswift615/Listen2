# Session Handoff: Word Highlighting Debug Session
**Date:** November 14, 2025
**Status:** 🔴 CRITICAL ISSUES REMAIN - Framework fixes applied but problems persist
**Next Session:** Deep investigation needed - framework may not be the root cause

---

## 🎯 What We Did This Session

### Task 1: Systematic Investigation ✅
Used the systematic-debugging skill to analyze 75k lines of logs and identify root causes:

**Bug #1: Stale Normalized Text**
- **Evidence:** Paragraphs getting "building applications with ai agents" repeatedly
- **Root Cause:** iOS framework built before commit 498f9071 (normalized text fix)
- **Fix Applied:** ✅ Rebuilt sherpa-onnx.xcframework with latest code

**Bug #2: Corrupt Phoneme Durations**
- **Evidence:** Durations showing -2147483648 (INT32_MIN) or 1073741824 samples (13.5 hours!)
- **Root Cause:** Uninitialized memory in old framework
- **Fix Applied:** ✅ Rebuilt framework with proper w_ceil extraction

**Bug #3: Stale Disk Cache**
- **Evidence:** Paragraphs loading corrupt alignment data from cache
- **Fix Applied:** ✅ Added `alignmentCache.clearAll()` on TTSService init

### Task 2: Framework Automation ✅
Created automated framework update system:
- **Script:** `scripts/update-frameworks.sh`
- **Modes:** Normal copy, rebuild+copy, force copy
- **Documentation:** `docs/FRAMEWORK_UPDATE_GUIDE.md`
- **Benefit:** Prevents future stale framework issues

---

## 🔴 CRITICAL: Problems Still Exist After Fixes

### Test Results After Clean Build

User tested with:
- ✅ Framework rebuilt from commit 498f9071
- ✅ Cache cleared on startup
- ✅ Clean Xcode build (⇧⌘K)

**Result:** 🔴 **Same issues persist!**

New logs location: `/Users/zachswift/listen-2-logs-2025-11-13.txt` (75,013 lines)

### Issues Observed

#### Issue #1: Phoneme Durations Still Corrupt
```
[SherpaOnnx] First phoneme duration: 0 samples = 0.0000s @ 22050Hz
[SherpaOnnx] First phoneme duration: -2147483648 samples = -97391.5487s
```

**Analysis:**
- Line 733: Duration = 0 (no w_ceil data extracted)
- Line 2671: Duration = INT32_MIN (uninitialized memory)
- Line 69203: Duration = INT32_MIN (still happening!)

**Implication:** Framework update didn't fix duration extraction OR w_ceil models don't have duration data

#### Issue #2: Normalized Text Still Stale
```
[SherpaOnnx] Extracted normalized text: 'building applications with ai agents...'
[SherpaOnnx] Extracted normalized text: 'data '
[SherpaOnnx] Extracted normalized text: 'it simplifies the complexities...'
```

**Analysis:**
- Line 736: First paragraph normalized text
- Lines 2674, 2712: DIFFERENT normalized text = some paragraphs work!
- Line 69206: Yet another different text

**Implication:** Normalized text extraction is working for SOME paragraphs but not all

#### Issue #3: Synthesis Failures
```
[TTSService] ⚠️ Piper synthesis failed: synthesisFailed(reason: "Synthesis returned nil")
```

**Analysis:**
- Lines 69185, 74995, 75008: Multiple synthesis failures
- Synthesis returning nil suggests deeper TTS provider issue

**Implication:** Something is causing synthesis to fail completely

#### Issue #4: Missing Phonemes
```
[PhonemeAlign] ⚠️ No phonemes found, using estimate
```

**Analysis:**
- 751-769: Many consecutive "no phonemes" warnings
- 2687: No per-phoneme durations, using estimate
- This happens DESPITE having phoneme data

**Implication:** Phoneme-to-word mapping logic is broken

#### Issue #5: Stuck Highlighting
```
⚠️ Highlight stuck on word 'Agents' for 2.16s, forcing next word
```

**Analysis:**
- Line 2735: Stuck detection triggered
- Forcing next word is a band-aid, not a fix

**Implication:** Timing data is wrong, causing incorrect word detection

---

## 🔬 Root Cause Analysis

### Why Did Framework Update Not Fix Issues?

**Three Possibilities:**

#### Possibility #1: Framework Not Actually Updated
**Check:**
```bash
cd ~/projects/Listen2/Frameworks/sherpa-onnx.xcframework
ls -lh Info.plist
# Should show Nov 14, 22:00 (when we rebuilt)
```

**Verify:**
```bash
./scripts/update-frameworks.sh
# Should show commit 498f9071
```

**If wrong:** Run `./scripts/update-frameworks.sh --force` and rebuild app

#### Possibility #2: w_ceil Models Don't Have Duration Data
**Evidence:**
- Log line 733: "First phoneme duration: 0 samples"
- This suggests w_ceil tensor is EMPTY or not being extracted

**Check Models:**
The models claim to have w_ceil (see WCEIL_VERIFICATION.md), but we need to verify:
1. Do the deployed models actually have w_ceil tensors?
2. Is sherpa-onnx extracting them correctly?
3. Is the Swift wrapper reading them properly?

**Next Steps:**
- Write test program to load models and verify w_ceil extraction
- Check if w_ceil tensor has actual data (not all zeros)
- Verify conversion from w_ceil values to sample durations

#### Possibility #3: Deeper Bug in Integration Chain
**The normalized text extraction works SOMETIMES:**
- Paragraph 0: "building applications..." ✅
- Paragraph 1: "data " ✅
- Paragraph N: "it simplifies..." ✅

**But phoneme durations are ALWAYS corrupt:**
- Paragraph 0: duration = 0
- Paragraph 1: duration = INT32_MIN
- Paragraph N: duration = INT32_MIN

**Hypothesis:**
The normalized text and phoneme duration extraction are separate code paths. Normalized text works, but duration extraction is broken.

**Investigate:**
1. Does sherpa-onnx C++ code actually extract phoneme_durations?
2. Does the C API expose them correctly?
3. Does the Swift wrapper read them?
4. Are they being passed to PhonemeAlignmentService?

---

## 📊 Key Log Evidence

### Cache Clear Working ✅
```
Line 1: [TTSService] 🗑️ Cleared corrupt alignment cache
```
Cache is being cleared on startup.

### Normalized Text Extraction Working (Partially) ⚠️
```
Line 736:   [SherpaOnnx] Extracted normalized text: 'building applications...'
Line 2674:  [SherpaOnnx] Extracted normalized text: 'data '
Line 69206: [SherpaOnnx] Extracted normalized text: 'it simplifies...'
```
Different paragraphs get different normalized text = extraction working.

### Phoneme Duration Extraction BROKEN 🔴
```
Line 733:   [SherpaOnnx] First phoneme duration: 0 samples
Line 2671:  [SherpaOnnx] First phoneme duration: -2147483648 samples
Line 69203: [SherpaOnnx] First phoneme duration: -2147483648 samples
```
Durations are corrupt across ALL paragraphs.

### Synthesis Failures 🔴
```
Line 69185: [TTSService] ⚠️ Piper synthesis failed: synthesisFailed(reason: "Synthesis returned nil")
Line 74995: [TTSService] ⚠️ Piper synthesis failed: synthesisFailed(reason: "Synthesis returned nil")
```
Some paragraphs fail to synthesize entirely.

### Phoneme Mapping Failures 🔴
```
Lines 751-769: [PhonemeAlign] ⚠️ No phonemes found, using estimate (×19)
Line 2687:     [PhonemeAlign] ⚠️ No per-phoneme durations, using estimate: 0.30s
```
Words can't find matching phonemes despite having phoneme data.

---

## 🎯 Next Session Priorities

### Priority 1: Verify w_ceil Extraction (CRITICAL)
**Goal:** Confirm w_ceil tensors exist and are being extracted

**Test Plan:**
1. **Check deployed models have w_ceil:**
   ```python
   import onnx
   model = onnx.load("Listen2/Resources/PiperModels/en_US-lessac-high.onnx")
   outputs = [o.name for o in model.graph.output]
   print(f"Outputs: {outputs}")
   # Should include "w_ceil"
   ```

2. **Verify sherpa-onnx extracts w_ceil:**
   - Add logging in SherpaOnnx.swift to show raw w_ceil data
   - Check if `audio.pointee.phoneme_durations` is null or has data
   - Verify sample counts are reasonable (not 0, not INT32_MIN)

3. **Check Swift wrapper:**
   - Verify `GeneratedAudio.phonemes` has duration > 0
   - Check if durations are being passed to PhonemeAlignmentService
   - Confirm conversion from samples to seconds is correct

**Files to investigate:**
- `Services/TTS/SherpaOnnx.swift` (lines 190-204)
- `Services/TTS/PhonemeAlignmentService.swift` (duration usage)
- `sherpa-onnx/c-api/c-api.cc` (C API duration extraction)

### Priority 2: Debug Synthesis Failures
**Goal:** Understand why synthesis returns nil

**Investigation:**
1. Find what triggers "Synthesis returned nil"
2. Check PiperTTSProvider.swift for error handling
3. Look for ONNX inference errors
4. Check if models are loading correctly

**Evidence Needed:**
- What paragraphs fail? (get text of failed paragraphs)
- Does it correlate with text length?
- Does it happen on first synthesis or later?
- Are there ONNX errors in logs before "Synthesis returned nil"?

### Priority 3: Fix Phoneme Mapping Logic
**Goal:** Understand why "No phonemes found" despite having phonemes

**Investigation:**
1. Check PhonemeAlignmentService.swift mapping logic
2. Verify normalized text coordinates match phoneme textRange
3. Check for off-by-one errors in range calculations
4. Confirm mapToNormalized() is working correctly

**Test Case:**
- Take one failing word (logs show which ones)
- Log its original range, normalized range
- Log all phoneme ranges
- Manually verify if ranges overlap

### Priority 4: Consider Alternative Hypothesis
**What if w_ceil models DON'T have duration data?**

If w_ceil extraction is fundamentally broken:
1. **Option A:** Use estimation (defeat the purpose of w_ceil)
2. **Option B:** Re-export models with verified w_ceil
3. **Option C:** Use different model format that includes durations

**Decision point:** If Priority 1 investigation shows w_ceil is broken, decide whether to:
- Fix w_ceil extraction (requires C++ debugging)
- Use estimation with disclaimer (fast but inaccurate)
- Abandon w_ceil approach (major pivot)

---

## 📁 Files Modified This Session

### Code Changes
- `Services/TTSService.swift` - Added cache clear on init (lines 67-76)
- `Frameworks/sherpa-onnx.xcframework` - Rebuilt with commit 498f9071

### Scripts Added
- `scripts/update-frameworks.sh` - Framework update automation
- `.claude/CLAUDE.md` - Added framework update instructions

### Documentation Added
- `docs/FRAMEWORK_UPDATE_GUIDE.md` - Complete framework update guide
- `docs/HANDOFF_2025-11-14_NORMALIZED_TEXT.md` - Previous session handoff
- `docs/HANDOFF_2025-11-14_WORD_HIGHLIGHTING_DEBUG.md` - This document

### Git Commits
- `7661f28` - fix: rebuild sherpa-onnx framework with normalized text fixes and clear corrupt cache
- `d91280e` - build: add automated framework update script and documentation

---

## 🔧 Quick Debugging Commands

### Check Framework Version
```bash
cd ~/projects/Listen2
./scripts/update-frameworks.sh
# Should show commit 498f9071
```

### Re-verify Framework
```bash
cd ~/projects/sherpa-onnx
git log --oneline -1
# Should show: 498f9071 fix: capture normalized_text...

./build-ios.sh  # Rebuild
cd ~/projects/Listen2
./scripts/update-frameworks.sh --force
```

### Check Deployed Models
```bash
ls -lh Listen2/Listen2/Listen2/Resources/PiperModels/*.onnx
# Should show Nov 14 19:00 timestamps for w_ceil models
```

### Grep Useful Log Patterns
```bash
# Check cache clear
grep "Cleared corrupt" listen-2-logs-2025-11-13.txt

# Check normalized text
grep "Extracted normalized text:" listen-2-logs-2025-11-13.txt

# Check phoneme durations
grep "First phoneme duration:" listen-2-logs-2025-11-13.txt

# Check synthesis failures
grep "Synthesis returned nil" listen-2-logs-2025-11-13.txt

# Check phoneme mapping failures
grep "No phonemes found" listen-2-logs-2025-11-13.txt | wc -l
```

---

## 💡 Lessons Learned

### What Worked
✅ Systematic debugging approach identified specific issues
✅ Framework automation prevents future manual errors
✅ Cache clear ensures fresh data
✅ Detailed logging helps trace data flow

### What Didn't Work
❌ Framework rebuild didn't fix duration extraction
❌ Assumption that w_ceil models have valid data
❌ Assumption that framework was the only problem

### Key Insight
**Normalized text extraction works, but phoneme duration extraction is completely broken.**

This suggests:
1. These are separate code paths in sherpa-onnx
2. The C API might not expose durations correctly
3. The Swift wrapper might not read durations
4. The w_ceil tensor might be empty/corrupt

**Next session must focus on the duration extraction chain, not the framework.**

---

## 🎯 Success Criteria for Next Session

### Minimum Viable Fix
- [ ] Phoneme durations are non-zero and reasonable (0.01s - 1.0s range)
- [ ] No "First phoneme duration: -2147483648" errors
- [ ] No "Synthesis returned nil" errors
- [ ] Word highlighting doesn't get stuck

### Ideal Fix
- [ ] All words find matching phonemes (minimal "No phonemes found")
- [ ] Durations match audio reality (not estimates)
- [ ] Smooth word highlighting with no glitching
- [ ] All paragraphs synthesize successfully

### Acceptable Fallback
If w_ceil is fundamentally broken:
- [ ] Document why w_ceil doesn't work
- [ ] Switch to estimation with clear logging
- [ ] Set expectations: "using estimation, not w_ceil"
- [ ] Plan alternative approach (different models? different framework?)

---

## 📞 Resources for Next Session

### Log Files
- **Latest test:** `/Users/zachswift/listen-2-logs-2025-11-13.txt` (75,013 lines)
- **Previous test:** Referenced in HANDOFF_2025-11-14_NORMALIZED_TEXT.md

### Documentation
- **Framework guide:** `docs/FRAMEWORK_UPDATE_GUIDE.md`
- **w_ceil verification:** `~/projects/sherpa-onnx/WCEIL_VERIFICATION.md`
- **Normalized text:** `docs/HANDOFF_2025-11-14_NORMALIZED_TEXT.md`
- **w_ceil handoff:** `docs/WCEIL_SESSION_HANDOFF.md`

### Key Code Locations
- **Duration extraction:** `Services/TTS/SherpaOnnx.swift:190-204`
- **Phoneme alignment:** `Services/TTS/PhonemeAlignmentService.swift:500-556`
- **Synthesis:** `Services/TTS/PiperTTSProvider.swift`
- **C API:** `sherpa-onnx/c-api/c-api.cc`

### Verification Points
```bash
# Framework commit
cd ~/projects/sherpa-onnx && git log --oneline -1

# Model timestamps
ls -lh ~/projects/Listen2/Listen2/Listen2/Listen2/Resources/PiperModels/*.onnx

# Test framework update
cd ~/projects/Listen2 && ./scripts/update-frameworks.sh
```

---

## 🚨 Critical Question for Next Session

**Is w_ceil extraction fundamentally broken, or is it a configuration issue?**

This is the KEY question that determines the path forward:

- **If config issue:** Fix extraction, verify durations, celebrate w_ceil working
- **If fundamentally broken:** Pivot to estimation or alternative approach

**How to answer:**
1. Write minimal test program that loads model and extracts w_ceil
2. Verify w_ceil tensor has non-zero data
3. Verify sherpa-onnx C++ extracts it
4. Verify C API exposes it
5. Verify Swift reads it

**If ALL steps work in isolation but fail in app:** Integration bug
**If ANY step fails:** Fundamental issue with w_ceil approach

---

**End of Handoff**

*Next session should start with Priority 1: Verify w_ceil Extraction*
