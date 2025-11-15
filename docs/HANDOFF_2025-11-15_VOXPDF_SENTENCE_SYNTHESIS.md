# Session Handoff: VoxPDF Update & Sentence-Level Synthesis Progress

**Date:** 2025-11-15
**Session Focus:** Updated VoxPDF framework with hybrid paragraph detection, investigated sentence-level synthesis playback issue

---

## What Was Completed ✅

### 1. VoxPDF Framework Update
- **Updated VoxPDFCore.xcframework** to commit `2c219d6` with hybrid paragraph detection
  - 5 heuristics for better paragraph boundary detection
  - Font size tracking from MuPDF
  - Improved multi-column layout handling
- Framework rebuilt and copied to `Listen2/Frameworks/`
- Build verified successfully

### 2. Enhanced Framework Update Script
**File:** `scripts/update-frameworks.sh`

**New capabilities:**
```bash
# Update specific framework
./scripts/update-frameworks.sh --framework voxpdf
./scripts/update-frameworks.sh --framework sherpa

# Rebuild + update
./scripts/update-frameworks.sh --build --framework voxpdf

# Update both (default)
./scripts/update-frameworks.sh
```

**Features added:**
- VoxPDF build automation (runs `build-ios.sh` → `create-xcframework.sh`)
- Selective framework updates via `--framework` option
- Git commit tracking for both frameworks
- Timestamp-based skip logic for both frameworks

### 3. Documentation Updates
**File:** `docs/FRAMEWORK_UPDATE_GUIDE.md`

- Added VoxPDF framework locations and workflows
- Updated usage examples for both frameworks
- Added VoxPDF-specific troubleshooting
- Documented build times (sherpa: 5-6min, VoxPDF: 1-2min)

### 4. Git Commit & Push
**Commit:** `f975b14` - "feat: update VoxPDF framework with hybrid paragraph detection"
- All changes safely pushed to `origin/main`
- Framework binaries uploaded via Git LFS (136 MB)

---

## Current Issue: Sentence Playback Skipping 🐛

### Observed Behavior
**User Report:**
> "On the first paragraph with multiple sentences, it played the first sentence and then skipped to the next paragraph"

**CPU Performance:** ✅ IMPROVED
- CPU never spiked above 100% (previously was hitting 500%+)
- No more runaway CPU consumption

### Log Analysis

**From `/Users/zachswift/listen-2-logs-2025-11-13.txt`:**

1. **Multi-sentence paragraph detected:** 8 sentences in one paragraph
   ```
   [SynthesisQueue] ✅ Sentence 1/8 ready
   [SynthesisQueue] ✅ Sentence 2/8 ready
   [SynthesisQueue] ✅ Sentence 3/8 ready
   [SynthesisQueue] ✅ Sentence 4/8 ready
   [SynthesisQueue] ✅ Sentence 5/8 ready
   [SynthesisQueue] ✅ Sentence 6/8 ready
   [SynthesisQueue] ✅ Sentence 7/8 ready
   [SynthesisQueue] ✅ Sentence 8/8 ready
   ```

2. **All sentences synthesized successfully** ✅

3. **BUT: Sentences appear to arrive out of order:**
   ```
   [SynthesisQueue] ✅ Sentence 6/8 ready  (line 1538)
   [SynthesisQueue] ✅ Sentence 2/8 ready  (line 1539)
   [SynthesisQueue] ✅ Sentence 4/8 ready  (line 1540)
   [SynthesisQueue] ✅ Sentence 1/8 ready  (line 1879)
   [SynthesisQueue] ✅ Sentence 3/8 ready  (line 2218)
   [SynthesisQueue] ✅ Sentence 7/8 ready  (line 2557)
   [SynthesisQueue] ✅ Sentence 8/8 ready  (line 2897)
   [SynthesisQueue] ✅ Sentence 5/8 ready  (line 3236)
   ```

4. **Missing:** No logs for actual playback events
   - No "Playing sentence X" logs
   - No "Finished playing sentence X" logs
   - Suggests playback logic might not be hooked up correctly

### Hypothesis

**Likely cause:** Sentence-level playback queue is missing or broken

**Possible issues:**
1. ✅ Synthesis works (all 8 sentences generated)
2. ❌ Playback logic might only play first sentence
3. ❌ No queueing mechanism for subsequent sentences
4. ❌ Missing code to transition from sentence 1 → 2 → 3, etc.

**Evidence:**
- Out-of-order sentence completion suggests parallel synthesis (good!)
- But playback skips to next paragraph after first sentence (bad!)
- This indicates playback is NOT waiting for all sentences before moving to next paragraph

---

## Root Cause Investigation Needed 🔍

### Key Questions for Next Session

1. **Where is sentence playback triggered?**
   - Look for code that plays individual sentences
   - Check if there's a sentence queue or just paragraph queue

2. **How does playback know when a sentence finishes?**
   - Audio player completion callbacks?
   - Should queue next sentence when current finishes

3. **What triggers "move to next paragraph"?**
   - Currently might be triggered after first sentence completes
   - Should only trigger after ALL sentences in paragraph complete

### Files to Investigate

**Priority 1: Playback Logic**
- `Listen2/Services/AudioPlaybackService.swift` (if exists)
- `Listen2/Services/TTSService.swift` - playback triggering
- `Listen2/Services/TTS/SynthesisQueue.swift` - sentence queueing

**Priority 2: State Management**
- Look for `currentSentenceIndex` or similar
- Find where paragraph completion is determined
- Check sentence → sentence transition logic

**Priority 3: Audio Player**
- AVAudioPlayer completion delegate
- Sentence audio buffer management

### Debugging Strategy

1. **Add playback logs:**
   ```swift
   print("[Playback] 🔊 Playing sentence \(index)/\(total)")
   print("[Playback] ✅ Finished sentence \(index)/\(total)")
   print("[Playback] 🔄 Queueing next sentence: \(index + 1)")
   ```

2. **Verify sentence queue state:**
   ```swift
   print("[SynthesisQueue] Sentences ready: \(readySentences.count)/\(totalSentences)")
   print("[SynthesisQueue] Next sentence to play: \(currentPlaybackIndex)")
   ```

3. **Add paragraph transition guard:**
   ```swift
   guard currentSentenceIndex >= totalSentences else {
       print("[Playback] ⚠️ Not all sentences played, staying on paragraph")
       return
   }
   print("[Playback] ✅ All sentences complete, moving to next paragraph")
   ```

---

## Work Still Uncommitted 📝

**Modified but not committed:**
- `Listen2/Services/TTS/PiperTTSProvider.swift`
- `Listen2/Services/TTS/SynthesisQueue.swift`
- `Listen2/Services/TTS/TTSProvider.swift`
- `Listen2.xcodeproj/project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate`

**Action needed:** Review these changes before next commit
- Likely contain sentence synthesis work-in-progress
- May have partial fixes that need completion

---

## Recent Wins 🎉

### CPU Performance Fixed
- **Before:** CPU spiked to 500%+, MacBook thermal throttling
- **After:** CPU never exceeds 100%
- **Cause fixed:** Removed debug logging, fixed synthesis serialization, fixed word highlighting loop

### Framework Update Automation
- **Before:** Manual copy-paste, easy to forget, no version tracking
- **After:** One command updates either or both frameworks
- **Time saved:** ~5 minutes per update, prevents stale framework bugs

### VoxPDF Improvements
- Better paragraph detection = better reading experience
- Font size tracking enables future features (heading detection, etc.)
- Hybrid heuristics handle complex PDFs better

---

## Next Steps (Priority Order) 📋

### 1. **Fix Sentence Playback** (HIGH PRIORITY)
**Goal:** Play all sentences in a paragraph before moving to next paragraph

**Tasks:**
- [ ] Find sentence playback trigger code
- [ ] Add sentence completion callback
- [ ] Implement sentence-to-sentence transition logic
- [ ] Add guard to prevent premature paragraph transition
- [ ] Test with multi-sentence paragraphs

**Success criteria:**
- Paragraph with 8 sentences plays all 8 in order
- Only moves to next paragraph after last sentence finishes
- No skipping sentences

### 2. **Test Parallel Synthesis Performance**
**Goal:** Verify parallel sentence synthesis doesn't cause issues

**Tasks:**
- [ ] Monitor memory usage during synthesis
- [ ] Check if out-of-order completion causes problems
- [ ] Ensure audio buffers are played in correct order (sentence 1, 2, 3... not 6, 2, 4...)
- [ ] Consider adding sentence ordering logic if needed

### 3. **Add Comprehensive Logging**
**Goal:** Never debug blindly again

**Tasks:**
- [ ] Add playback state logs (playing, paused, finished)
- [ ] Add sentence queue state logs
- [ ] Add paragraph transition logs with guards
- [ ] Log sentence ordering (synthesized order vs playback order)

### 4. **Clean Up Uncommitted Work**
**Goal:** Get to a clean commit state

**Tasks:**
- [ ] Review changes in TTS files
- [ ] Test thoroughly
- [ ] Commit with clear message describing sentence synthesis work
- [ ] Push to origin/main

### 5. **Performance Testing**
**Goal:** Verify all optimizations hold under load

**Tasks:**
- [ ] Test with long document (100+ paragraphs)
- [ ] Monitor CPU/memory over 10+ minutes
- [ ] Verify no memory leaks
- [ ] Check disk cache hit rate
- [ ] Ensure smooth UI during synthesis

---

## Context for Next Session 🧠

### Architecture Refresher

**Synthesis Flow:**
```
Paragraph → SentenceSplitter → N Sentences
                                    ↓
                            Parallel Synthesis
                                    ↓
                            SynthesisQueue (ready)
                                    ↓
                                 ??? → Playback
                                    ↓
                            AudioPlaybackService
```

**Gap identified:** The `??? → Playback` step doesn't handle multiple sentences

### Key Files Reference

**Synthesis:**
- `Listen2/Services/TTS/SynthesisQueue.swift` - Manages synthesis state
- `Listen2/Services/TTS/PiperTTSProvider.swift` - Does actual TTS
- `Listen2/Services/TTS/SentenceSplitter.swift` - Splits paragraphs

**Playback:**
- `Listen2/Services/TTSService.swift` - Main TTS coordinator
- (Need to find) AudioPlaybackService or similar

**Models:**
- `Listen2/Models/SentenceSynthesisResult.swift` - Sentence audio data

### Recent Commits for Context

```
f975b14 feat: update VoxPDF framework with hybrid paragraph detection
0a640f2 feat: add SentenceSynthesisResult models
34c7b61 fix: convert generateWithStreaming to async and fix safety issues
8a3e265 feat: bridge ONNX streaming callbacks to Swift
a9f5fe7 docs: Task 7 already complete - streaming callbacks exist
```

---

## Workshop Context 📝

**Use workshop CLI to query past decisions:**
```bash
workshop why "sentence synthesis"
workshop why "cpu performance"
workshop context
workshop recent
```

**Record decision after fixing:**
```bash
workshop decision "Fixed sentence playback by [solution]" -r "[reasoning]"
```

---

## Questions to Ask User 💬

Before starting next session:

1. **Can you describe the playback behavior more precisely?**
   - Did it play sentence 1 then immediately skip to paragraph 2?
   - Or did it play sentence 1, pause, then skip?
   - Any audio glitches during the transition?

2. **Did you see any UI indication of sentences?**
   - Did word highlighting work during the one sentence that played?
   - Any visual indication that paragraph had multiple sentences?

3. **Which paragraph was this on?**
   - First paragraph of the document?
   - Or later in the document?
   - Could help identify in logs

---

## Known Good State 🟢

**Commit:** `f975b14`
**Status:** Compiles ✅, Runs ✅, VoxPDF updated ✅, CPU fixed ✅
**Known issue:** Sentence playback skipping

**Safe to revert to if needed:**
```bash
git checkout f975b14
```

---

## End of Handoff

**Summary:** VoxPDF updated successfully, CPU performance excellent, but sentence playback logic is incomplete. Need to investigate playback triggering and add sentence-to-sentence transitions.

**Estimated time to fix:** 1-2 hours (find issue, implement fix, test)

**Blocker level:** Medium - basic playback works, but multi-sentence paragraphs broken
