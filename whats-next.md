# What's Next - ReadyQueue Pipeline Debug Session

## Original Task

Implement the ReadyQueue pipeline from the comprehensive plan at `docs/plans/2025-11-22-ready-queue-pipeline.md`. This creates a unified synthesis + CTC alignment pipeline with 5-sentence lookahead buffer across paragraph boundaries, word highlighting toggle, and loading indicator.

## Work Completed

### Commits Made (from d64b77e baseline)

1. **226264f** - `feat: add Sendable conformance to AlignmentResult for concurrency safety`
   - Added `Sendable` to `AlignmentResult` and `WordTiming` structs

2. **494402e** - `feat: add ReadySentence model and ReadyQueueConstants`
   - Created `Listen2/Listen2/Listen2/Services/TTS/ReadySentence.swift`
   - Contains: `ReadySentence`, `SentenceKey`, `ReadyQueueConstants`

3. **2cddda3** - `feat: add ReadyQueue actor with sliding window and cross-paragraph lookahead`
   - Created `Listen2/Listen2/Listen2/Services/TTS/ReadyQueue.swift` (~535 lines)
   - Pipeline actor with session-based invalidation, sliding window

4. **e1170c4** - `feat: add word highlighting toggle to settings`
   - Modified `SettingsViewModel.swift` - added `@AppStorage("wordHighlightingEnabled")`
   - Modified `SettingsView.swift` - added Toggle UI

5. **2fa4217** - `feat: add isPreparing state and readyQueue to TTSService`
   - Added `isPreparing`, `wordHighlightingEnabled`, `readyQueue` properties
   - Initialized `readyQueue` in `initializePiperProvider()`

6. **227abfe** - `feat: integrate ReadyQueue into playback flow with buffer preservation`
   - Rewrote `speakParagraph(at:)` to use ReadyQueue
   - Updated `handleParagraphComplete()` (removed duplicate startFrom call)
   - Added `playReadySentence()` and `speakParagraphLegacy()` methods

7. **b896775** - `feat: clear readyQueue on stop/rate/voice/skip changes`
   - Added `readyQueue?.stopPipeline()` calls to `stop()`, `setPlaybackRate()`, `setVoice()`, `stopAudioOnly()`
   - Added `isPreparing = false` reset in `stop()`

8. **611bb9c** - `feat: add loading indicator for audio preparation`
   - Modified `ReaderView.swift` - added "Preparing audio..." overlay

9. **cabc374** - `fix: resolve race condition and empty alignment in ReadyQueue pipeline`
   - Merged two separate Tasks in `speakParagraph` into one sequential Task
   - Check `isReady()` before showing loading indicator
   - Added `createUniformWordTimings()` fallback in `CTCForcedAligner.swift`

10. **c288f2c** - `fix: use raw Float32 chunks for CTC alignment instead of WAV data`
    - Changed `ReadyQueue.processSentence()` to use chunks (raw Float32) instead of `combinedAudio` (WAV format)
    - This fixed the timing being half of actual duration

### Key Files Modified

- `Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift` - Sendable conformance
- `Listen2/Listen2/Listen2/Services/TTS/ReadySentence.swift` - NEW FILE
- `Listen2/Listen2/Listen2/Services/TTS/ReadyQueue.swift` - NEW FILE
- `Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift` - Added uniform fallback
- `Listen2/Listen2/Listen2/Services/TTSService.swift` - Major integration changes
- `Listen2/Listen2/Listen2/ViewModels/SettingsViewModel.swift` - Word highlighting setting
- `Listen2/Listen2/Listen2/Views/SettingsView.swift` - Word highlighting toggle
- `Listen2/Listen2/Listen2/Views/ReaderView.swift` - Loading indicator

## Work Remaining

### Fixes Applied (2025-11-22)

1. **MEMORY LEAK FIXED**: Added eviction of `ready` and `skipped` sentences in `slideWindowTo()`
   - Root cause: `slideWindowTo()` only evicted `paragraphWindow` and `paragraphSentences`, not the `ready` dictionary
   - Fix: Now evicts ready/skipped sentences for paragraphs being removed from window
   - Added logging to show freed memory when window slides

2. **FIRST WORD HIGHLIGHT FIXED**: Changed `wordTiming(at:)` to return first word when time < startTime
   - Root cause: Binary search returned `nil` when `currentTime=0.000s` and first word started at 0.021s
   - Fix: Now returns `wordTimings[0]` when time is before first word's start (audio is already playing)

3. **SESSION INVALIDATION LOGGING ADDED**: Added diagnostic logging throughout ReadyQueue
   - Added logs at all session check points in `runPipeline()` and `processSentence()`
   - Will help diagnose if sentence skipping is caused by session invalidation

4. **FALSE SENTENCE SKIPPING FIXED** (fb2d7b1 -> 56904e7):
   - Root cause: `processSentence()` returns nil for BOTH empty sentences AND session-invalidated sentences
   - When session invalidated during long alignment (4-5s), sentence was incorrectly marked "skipped"
   - Fix: Now checks session validity BEFORE marking as skipped - only truly empty sentences get skipped flag
   - Also reset `lastHighlightedWordIndex` when starting new sentence

5. **DEBUG LOGGING FOR HIGHLIGHT RANGE**: Added logging to show exact range being applied
   - Will show `[TTSService] 🎯 HIGHLIGHT: applying range X..<Y = 'text' to P#`
   - Helps diagnose highlight offset issues

### Remaining Plan Tasks

- **Task 8** (Optional): Clean up old code - defer until bugs fixed
- **Task 9**: Integration testing - needs re-test after fixes
- **Highlight offset issue**: Still investigating - new debug logging will help

## Attempted Approaches

### What Worked

1. **Subagent-driven development with code review gates** - Effective for systematic implementation
2. **Merging fire-and-forget Task into sequential flow** - Fixed race condition where buffer was cleared
3. **Using raw Float32 chunks for alignment** - Fixed timing being half of actual duration

### What Didn't Work / Issues Found

1. **Fire-and-forget Task for pipeline setup** - Caused race condition with playback Task
2. **Using `combinedAudio` from `synthesisQueue.streamSentence()`** - It's WAV format (Int16 PCM), not raw Float32
3. **Duplicate `startFrom` calls** - `handleParagraphComplete` was calling `startFrom` before `speakParagraph`, both cleared buffer

### Dead Ends to Avoid

- Don't interpret WAV data as Float32 samples - `synthesisQueue.streamSentence()` returns WAV!
- Don't have separate Tasks for pipeline setup and consumption - causes race
- Don't call `startFrom` from `handleParagraphComplete` - `speakParagraph` handles it

## Critical Context

### Architecture Understanding

1. **Audio Data Flow**:
   - `SynthesisQueue.streamSentence()` returns **WAV format** Data (Int16 PCM with 44-byte header)
   - `PipelineChunkDelegate` collects **raw Float32** chunks from streaming callbacks
   - `ReadySentence.chunks` are raw Float32 - use these for alignment!

2. **Sample Rate Constants**:
   - Piper TTS: 22050 Hz (stored in `ReadyQueueConstants.sampleRate`)
   - CTC Model (MMS-FA): 16000 Hz (resamples internally in CTCForcedAligner)
   - Frame rate: ~49 fps (varies slightly)

3. **Session ID Pattern** (Important for debugging sentence skipping):
   - `ReadyQueue.sessionID` increments on `startFrom()` and `stopPipeline()`
   - All pipeline operations check `session == sessionID` before/after async work
   - If session changes mid-operation, operation returns nil/skips

4. **Buffer Management**:
   - Max 5 sentences lookahead (`maxSentenceLookahead`)
   - Max 5 paragraphs in window (`maxParagraphWindow`)
   - Max 10MB buffer (`maxBufferBytes`)
   - **NOTE**: Check if these limits are being enforced!

### Important Files to Debug

- **ReadyQueue.swift** (lines ~430-515): `processSentence()` - memory accumulation here?
- **ReadyQueue.swift** (lines ~248-288): `slideWindowTo()` - eviction working?
- **TTSService.swift** (lines ~1310-1380): `updateHighlightFromTime()` - first word handling
- **TTSService.swift** (lines ~690-760): `speakParagraph()` - sentence loop and session handling

### Latest Log Analysis (from `/Users/zachswift/listen-2-logs-2025-11-14`)

**Good news - CTC alignment IS working**:
```
[CTCForcedAligner] 🔗 Created 2 word timings:
[CTCForcedAligner]   [0] 'The' @ 0.021-0.124s, range=0...3
[CTCForcedAligner]   [1] 'Knowledge' @ 0.124-0.766s, range=4...13
```

**But first word doesn't start at 0**:
```
[TTSService] 🎬 Starting CTC word highlighting timer at audioPlayer.currentTime = 0.000s
[TTSService] 🎬 DEBUG: First word starts at 0.021s
```
This 21ms gap causes the "starts on 2nd word" issue.

### Known Gotchas

- CTC backtrack can return empty `tokenSpans` for short sentences - uniform fallback handles this
- `Publishing changes from within view updates` warnings are pre-existing, unrelated
- `[StreamingAudioPlayer] setRate not yet implemented` - playback rate for streaming is TODO

## Current State

### Status

- **Tasks 0-7**: Complete, code reviewed, committed
- **Task 8 (cleanup)**: Not started (waiting for bugs to be fixed)
- **Task 9 (testing)**: In progress, bugs found

### Git State

- All changes committed to `main` branch
- 10 new commits since baseline `d64b77e`
- HEAD is `c288f2c`

### Next Steps for New Session

1. **TEST FIXES** - Run app and verify:
   - Memory stays bounded (monitor in Xcode Instruments or Debug Navigator)
   - First word highlights immediately at playback start
   - Check console logs for session invalidation warnings (⚠️ messages)

2. **If sentence skipping persists**, check logs for:
   - `[ReadyQueue] ⚠️ Session invalidated...` messages
   - Whether it's session mismatch, timeout, or Task cancellation

3. **Consider Task 8 cleanup** only after all bugs confirmed fixed

### Command to Resume

```
Test the ReadyQueue pipeline fixes:
1. Memory leak fix in slideWindowTo()
2. First word highlight fix in wordTiming(at:)
3. Session invalidation logging for debugging skips
```
