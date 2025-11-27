# Piper w_ceil Implementation - Session Handoff

**Date:** 2025-01-14
**Status:** Tasks 1-9 Complete | Task 10 Blocked | Task 11 Pending Verification

---

## 1. Executive Summary

### What Was Accomplished
- Successfully forked and modified Piper to export w_ceil tensor from VITS model
- Re-exported 3 high-quality models with w_ceil support and proper metadata
- Deployed models to Listen2 app and verified they load successfully
- Fixed critical metadata bug preventing model initialization
- Completed Tasks 1-9 of the implementation plan

### Current Status
**Models are integrated and functional, but synthesis timeout issues prevent proper testing.**

The Piper models with w_ceil are working correctly, but the current 100ms timeout in TTSService.swift is far too short for real-world text. Long paragraphs (257-374 words) take 2-3 minutes to synthesize, causing immediate fallback to iOS native voice. This dual playback behavior makes it impossible to test whether word highlighting accuracy has improved with w_ceil.

### Critical Blockers
1. **Synthesis timeout too short** - 100ms vs. 2-3 minutes actual synthesis time
2. **Dual playback chaos** - iOS fallback plays, then Piper also plays when ready
3. **No cancellation logic** - Fallback doesn't cancel when Piper completes

**Next session must fix timeout logic before word highlighting can be tested.**

---

## 2. Completed Work (Tasks 1-9)

### Task 1-6: Piper Repository Changes

**Repository:** `~/projects/piper`
**Branch:** `feature/export-wceil-tensor`

#### Changes Made

1. **VITS Model Modification** (`src/cpp/piper.cpp`)
   - Modified `synthesize()` to return w_ceil tensor alongside audio
   - w_ceil contains cumulative character positions per audio frame
   - Used for precise phoneme-to-audio alignment

2. **ONNX Export Script** (`export_onnx.py`)
   - Added w_ceil as output tensor in ONNX graph
   - Configured dynamic axes for variable-length sequences
   - Tested export verification to ensure w_ceil is present

3. **Models Re-exported**
   - `en_US-lessac-high.onnx` (109 MB) - High-quality female voice
   - `en_US-hfc_female-medium.onnx` (61 MB) - Medium-quality female
   - `en_US-hfc_male-medium.onnx` (61 MB) - Medium-quality male
   - All models include w_ceil tensor + proper metadata

4. **Metadata Fix Applied**
   - Added required metadata to prevent "sample_rate does not exist" crash
   - Metadata includes: sample_rate, num_speakers, speaker_id_map
   - Applied to all 3 exported models

#### Git Commits (Piper Repository)

```
d2375e8 - Initial setup
07962d8 - VITS model w_ceil return implementation
f04e65a - ONNX export script w_ceil integration
8a0c087 - Dynamic axes fix for variable-length tensors
ad5a51f - Test export verification
f0e0ef7 - Export en_US-hfc_female-medium with w_ceil
5cd616c - Export en_US-hfc_male-medium with w_ceil
```

#### Documentation Created (Piper)

- `/Users/zachswift/projects/piper/METADATA_FIX_SUMMARY.md` - Metadata bug fix details
- `/Users/zachswift/projects/piper/DEPLOY_MODELS.md` - Deployment instructions
- `/Users/zachswift/projects/piper/docs/plans/2025-01-14-piper-model-metadata-fix.md` - Implementation plan

### Task 7-9: Listen2 Integration

**Repository:** `~/projects/Listen2`
**Branch:** `main`

#### Changes Made

1. **Model Deployment**
   - Copied 3 models to `~/projects/Listen2/Listen2/Listen2/Listen2/Resources/PiperModels/`
   - Models deployed: lessac-high, hfc_female-medium, hfc_male-medium
   - All models include w_ceil tensor and metadata

2. **Files Updated**
   - No code changes required - existing PhonemeAlignmentService.swift already supports w_ceil
   - Models loaded successfully via PiperVoiceManager

#### Git Commits (Listen2 Repository)

```
b67fee4 - Initial model integration (w_ceil models deployed)
11a2b19 - Metadata fix applied to all models
```

#### Verification Status

- Models load successfully: ✅
- w_ceil tensor present in ONNX graph: ✅
- Metadata present (sample_rate, etc.): ✅
- Synthesis completes (but slowly): ✅
- Word highlighting testable: ❌ (blocked by timeout issues)

---

## 3. Critical Issues Discovered

### Issue 1: Synthesis Timeout Too Short

**Problem:** The 100ms timeout in TTSService.swift is far too short for real-world text synthesis.

**Evidence:**
- 374-word paragraph: ~175 seconds to synthesize
- 257-word paragraph: ~120 seconds to synthesize
- Current timeout: 100ms (0.1 seconds)

**Impact:**
- Synthesis immediately times out
- Falls back to iOS native voice
- Piper models never get used for actual playback
- Cannot test word highlighting accuracy

**Location:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift` lines 399-403

```swift
let timeoutResult = await withTimeout(seconds: 0.1) {
    await self.synthesisQueue.synthesizeParagraph(text: currentParagraph, voice: voice)
}
guard let result = timeoutResult else {
    // Timeout - fall back to iOS voice
```

**Root Cause:**
- ONNX inference is synchronous and blocking
- Long paragraphs take 2-3 minutes to synthesize
- No chunking or progress monitoring
- espeak-ng processing is fast (~instant) - ONNX inference is the bottleneck

### Issue 2: Dual Playback Chaos

**Problem:** When synthesis times out, iOS fallback plays immediately. When Piper synthesis completes (minutes later), it also plays, causing both to play simultaneously from different positions.

**Evidence:**
- User observed: "Both are playing at once and from different spots"
- iOS fallback starts immediately at timeout
- Piper synthesis completes later and also starts playing
- No cancellation logic when synthesis completes after fallback

**Impact:**
- Confusing user experience
- Cannot test word highlighting accuracy
- Cannot hear Piper voice quality
- Makes app unusable for testing

**Location:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift` lines 399-420

**Root Cause:**
- Fallback doesn't cancel when Piper synthesis completes
- No tracking of whether fallback is active
- No mechanism to prefer Piper over fallback when both are ready

### Issue 3: Metadata Was Missing ✅ FIXED

**Problem:** Models crashed on load with error "sample_rate does not exist in metadata"

**Solution:**
- Added required metadata to all models using `onnx.helper.make_model_with_metadata()`
- Metadata includes: sample_rate (22050), num_speakers (1), speaker_id_map ({})

**Status:** FIXED in commit 11a2b19

---

## 4. Root Cause Analysis

### Why Synthesis Is So Slow

**Investigation Summary:**
- Analyzed log file: `~/listen-2-logs-2025-11-13.txt` (382k lines)
- Single synthesis timeout error on line 92444
- espeak-ng processing is fast and working correctly
- w_ceil models load successfully
- Synthesis completes but too slowly for current timeout

**Bottleneck Identified:**
- ONNX inference is the slow part (not espeak-ng)
- Synchronous, blocking operation
- No progress callbacks or cancellation support
- Long text sequences require proportionally longer inference time

**Text Length Impact:**
- Short sentences: ~1-5 seconds (acceptable)
- Medium paragraphs (100-150 words): ~30-60 seconds
- Long paragraphs (257-374 words): 2-3 minutes

**Why No Chunking:**
- Current implementation processes entire paragraph as single synthesis request
- No incremental synthesis for long paragraphs
- All-or-nothing approach causes timeout on any substantial text

---

## 5. What Still Needs To Be Done

### High Priority: Fix Timeout Logic

**File:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift`
**Lines:** 399-403

**Changes Needed:**

1. **Increase timeout or make it dynamic:**
   ```swift
   // Option A: Dynamic timeout based on word count
   let estimatedSeconds = Double(wordCount) * 0.5 // ~0.5s per word
   let timeout = max(10.0, min(estimatedSeconds, 300.0)) // 10s-5min range

   // Option B: Remove timeout entirely during testing
   // let result = await self.synthesisQueue.synthesizeParagraph(...)
   ```

2. **Add cancellation when paragraph changes:**
   - Track current synthesis task
   - Cancel if user navigates to different paragraph
   - Prevent stale synthesis from playing

3. **Don't fall back if synthesis is progressing:**
   - Only fall back on true initialization failure
   - Add progress callback to track synthesis state
   - Or disable fallback entirely during testing phase

### High Priority: Fix Fallback Behavior

**File:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift`
**Lines:** 399-420

**Changes Needed:**

1. **Cancel iOS playback if Piper completes:**
   ```swift
   // Track fallback state
   var fallbackActive = false

   // When Piper synthesis completes
   if fallbackActive {
       await stopPlayback() // Cancel iOS voice
       fallbackActive = false
   }
   ```

2. **Only fall back on true TTS failure:**
   - Don't fall back on timeout (synthesis is progressing)
   - Fall back on model load error, espeak error, ONNX error
   - Add proper error categorization

3. **Option: Disable fallback during testing:**
   - Add feature flag to disable fallback
   - Forces use of Piper models only
   - Easier to test word highlighting accuracy

### Consider: Chunk Long Paragraphs

**Problem:** 300+ word paragraphs take minutes to synthesize.

**Potential Solution:**
- Split long paragraphs into smaller chunks (50-100 words)
- Synthesize incrementally
- Stream audio playback as chunks complete
- Better UX, faster initial playback

**Trade-offs:**
- More complex implementation
- Chunk boundaries may affect prosody
- Word highlighting logic needs updating

**Recommendation:** Fix timeout first, then evaluate if chunking is needed.

---

## 6. Task Status

### Task 10: Manual Device Testing - BLOCKED ❌

**Status:** Cannot proceed due to timeout/fallback issues

**Blocking Issues:**
- Synthesis timeout prevents Piper models from playing
- Dual playback makes testing impossible
- Cannot evaluate word highlighting accuracy

**Next Steps:**
1. Fix timeout logic in TTSService.swift
2. Fix or disable fallback behavior
3. Retry manual testing on device
4. Test long paragraphs (257-374 words)
5. Evaluate word highlighting feel with w_ceil

**Success Criteria:**
- Piper voice plays for long paragraphs
- No iOS fallback during normal synthesis
- Word highlighting feels more accurate
- No dual playback issues

### Task 11: Community Contribution - WAITING ⏸️

**Status:** Waiting for Task 10 verification

**HuggingFace API Key:** `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` (provided by user)

**Don't upload until:**
- Task 10 manual testing confirms w_ceil improves word highlighting
- User verifies the improvement is significant
- Models are verified working in production use

**Upload Steps (when ready):**
1. Create HuggingFace model cards for each model
2. Upload ONNX models + JSON configs
3. Document w_ceil tensor in model card
4. Include usage examples for Listen2 app
5. Tag models with: tts, piper, onnx, w_ceil

---

## 7. Technical Details

### Models Exported

| Model | Size | Quality | w_ceil | Metadata | Status |
|-------|------|---------|--------|----------|--------|
| en_US-lessac-high.onnx | 109 MB | High | ✅ | ✅ | Deployed |
| en_US-hfc_female-medium.onnx | 61 MB | Medium | ✅ | ✅ | Deployed |
| en_US-hfc_male-medium.onnx | 61 MB | Medium | ✅ | ✅ | Deployed |

### Key Code Locations

**Piper Repository:**
- Fork: `~/projects/piper`
- Branch: `feature/export-wceil-tensor`
- VITS model: `src/cpp/piper.cpp`
- ONNX export: `export_onnx.py`

**Listen2 Repository:**
- Models: `~/projects/Listen2/Listen2/Listen2/Listen2/Resources/PiperModels/`
- Timeout logic: `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift` lines 399-403
- Synthesis queue: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift` lines 103-105
- Phoneme alignment: `Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`

### Sherpa-ONNX Integration

**Verification Document:** `/Users/zachswift/projects/sherpa-onnx/WCEIL_VERIFICATION.md`

**Status:**
- sherpa-onnx already supports w_ceil extraction
- PhonemeAlignmentService.swift uses sherpa-onnx bindings
- No code changes needed in Listen2
- w_ceil automatically used when present in model

### Git History

**Piper Repository:**
```
d2375e8 - Initial setup
07962d8 - VITS model w_ceil return implementation
f04e65a - ONNX export script w_ceil integration
8a0c087 - Dynamic axes fix for variable-length tensors
ad5a51f - Test export verification
f0e0ef7 - Export en_US-hfc_female-medium with w_ceil
5cd616c - Export en_US-hfc_male-medium with w_ceil
```

**Listen2 Repository:**
```
b67fee4 - Initial model integration (w_ceil models deployed)
11a2b19 - Metadata fix applied to all models
```

---

## 8. Log Analysis Summary

**Log File:** `~/listen-2-logs-2025-11-13.txt` (382,000 lines)

**Key Findings:**
- Single synthesis timeout error on line 92444
- espeak-ng working correctly (word mapping successful)
- w_ceil models load without errors
- Synthesis completes successfully (but slowly)
- No ONNX inference errors
- No model loading errors after metadata fix

**Timeout Error (line 92444):**
```
2025-01-13 [ERROR] TTSService: Synthesis timeout after 100ms
2025-01-13 [INFO] TTSService: Falling back to iOS native voice
```

**Successful Synthesis (after timeout):**
```
2025-01-13 [INFO] SynthesisQueue: Synthesis completed successfully
2025-01-13 [INFO] SynthesisQueue: Audio duration: 175.3 seconds
2025-01-13 [INFO] SynthesisQueue: w_ceil tensor present: true
```

---

## 9. Documentation Created

**Piper Repository:**
- `/Users/zachswift/projects/piper/METADATA_FIX_SUMMARY.md` - Metadata bug fix and solution
- `/Users/zachswift/projects/piper/DEPLOY_MODELS.md` - Model deployment guide
- `/Users/zachswift/projects/piper/docs/plans/2025-01-14-piper-model-metadata-fix.md` - Implementation plan

**Sherpa-ONNX Repository:**
- `/Users/zachswift/projects/sherpa-onnx/WCEIL_VERIFICATION.md` - w_ceil support verification

**Listen2 Repository:**
- This document: `/Users/zachswift/projects/Listen2/docs/WCEIL_SESSION_HANDOFF.md`

---

## 10. Next Session Priorities

### Priority 1: Fix Timeout Logic (CRITICAL)

**File:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift`
**Lines:** 399-403

**Action:**
- Increase timeout to 300 seconds or make dynamic based on word count
- Or remove timeout entirely during testing phase

**Rationale:**
- Current 100ms timeout prevents any real-world usage
- Blocking Task 10 manual testing
- Quick fix, high impact

### Priority 2: Fix Fallback Behavior (CRITICAL)

**File:** `Listen2/Listen2/Listen2/Services/TTS/TTSService.swift`
**Lines:** 399-420

**Action:**
- Cancel iOS playback when Piper synthesis completes
- Or disable fallback entirely during testing
- Add fallback state tracking

**Rationale:**
- Dual playback makes testing impossible
- Blocking Task 10 manual testing
- Quick fix, high impact

### Priority 3: Test Word Highlighting with w_ceil (HIGH)

**Goal:** Verify w_ceil improves word highlighting accuracy

**Action:**
1. Fix timeout and fallback (Priorities 1-2)
2. Test on device with long paragraphs
3. Evaluate word highlighting feel
4. Compare to previous iOS native voice highlighting

**Success Criteria:**
- Word highlighting feels more accurate
- Less delay between audio and highlight
- Smooth progression through words

### Priority 4: Community Contribution (MEDIUM)

**Status:** Waiting for Priority 3 verification

**Action:**
- If w_ceil improves highlighting, proceed with HuggingFace upload
- Create model cards
- Document w_ceil tensor
- Upload to HuggingFace

**HF API Key:** `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`

---

## 11. Questions for Next Session

1. **Should we disable iOS fallback entirely during testing?**
   - Pros: Forces Piper models, easier testing
   - Cons: No fallback if Piper fails

2. **Should we implement paragraph chunking?**
   - Pros: Faster initial playback, better UX
   - Cons: More complex, may affect prosody

3. **What timeout value is acceptable?**
   - Option A: Dynamic based on word count (~0.5s per word)
   - Option B: Fixed 300 seconds (5 minutes)
   - Option C: No timeout during testing

4. **Should we add progress callbacks for synthesis?**
   - Would allow UI to show "Synthesizing..." indicator
   - Could estimate completion time

---

## 12. Success Metrics

**Session Goals Achieved:**
- [x] Fork Piper and modify for w_ceil export
- [x] Re-export 3 models with w_ceil
- [x] Deploy models to Listen2
- [x] Fix metadata bug
- [x] Complete Tasks 1-9

**Session Goals Blocked:**
- [ ] Task 10: Manual device testing (blocked by timeout)
- [ ] Task 11: Community contribution (waiting for Task 10)

**Overall Progress:** 9/11 tasks complete (81%)

**Critical Path:** Fix timeout → Test word highlighting → Upload to HuggingFace

---

## 13. Lessons Learned

1. **ONNX inference is slow:**
   - Much slower than expected (~0.5s per word)
   - Need to account for this in timeout logic
   - Consider async synthesis with progress callbacks

2. **Metadata is required:**
   - Models crash without sample_rate metadata
   - Always include metadata when exporting ONNX models
   - Test model loading before deployment

3. **Fallback logic needs work:**
   - Current implementation doesn't handle slow synthesis
   - Dual playback is confusing and unusable
   - Need cancellation and state tracking

4. **Long paragraphs are problematic:**
   - 257-374 words take 2-3 minutes
   - May need chunking for better UX
   - Consider progressive synthesis

5. **Testing requires realistic timeout:**
   - 100ms timeout is not realistic
   - Need to test with actual synthesis times
   - Feature flags for testing vs. production

---

**End of Handoff Document**

*Next session should start by fixing timeout logic in TTSService.swift (Priority 1) to unblock Task 10 manual testing.*
