# Listen2 ReadyQueue Pipeline - Handoff Document

## Original Task

Debug and fix issues in the ReadyQueue TTS pipeline for the Listen2 iOS app, specifically:
1. Word highlighting synchronization issues (highlight not matching audio)
2. Playback freezing/stopping and not continuing after pause
3. Memory crashes and audio system corruption
4. Sentence/paragraph skipping issues

## Work Completed

### Commits Made This Session

1. **fb2d7b1** - Memory leak fix and first word highlight
   - Fixed `slideWindowTo()` to evict `ready` and `skipped` sentences when window slides
   - Fixed `wordTiming(at:)` to return first word when time < startTime

2. **56904e7** - False sentence skipping fix
   - `processSentence()` was returning nil for both empty AND session-invalidated sentences
   - Now checks session validity BEFORE marking as skipped

3. **237e7a1** - Highlight paragraph mismatch fix
   - Stop highlight timer BEFORE setting new alignment in `playReadySentence()`
   - Added guard in `updateHighlightFromTime()` to verify alignment.paragraphIndex matches

4. **f372e54** - Audio system corruption prevention
   - Added `deinit` to `StreamingAudioPlayer` that stops/resets `AVAudioEngine`
   - Added `emergencyReset()` method for recovering from corrupted state

5. **cb2fa1a** - Pause not killing playback task
   - Removed `CancellationError` throwing from `pause()` - was killing the speakParagraph task
   - Now continuation stays active during pause and completes normally when audio resumes

6. **1626af3** - Clear alignment before paragraph transition
   - Stop highlight timer and clear `currentAlignment` in `handleParagraphComplete()` BEFORE advancing
   - Prevents old paragraph's wordRange from appearing on new paragraph

### Key Files Modified

- `Listen2/Listen2/Listen2/Services/TTSService.swift` - Main TTS coordination
- `Listen2/Listen2/Listen2/Services/TTS/ReadyQueue.swift` - Pipeline orchestration
- `Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift` - Word timing lookups
- `Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift` - AVAudioEngine management

### Issues Fixed

1. **Memory crash (EXC_RESOURCE)** - Evicting sentences from `ready` dictionary when window slides
2. **First word not highlighting** - Return first word when time < startTime
3. **False sentence skipping** - Don't mark session-invalidated sentences as "skipped"
4. **Highlight applying wrong paragraph's range** - Stop timer and clear alignment before transition
5. **Playback freeze after pause** - Don't throw CancellationError during pause
6. **Audio system corruption** - Proper cleanup in `deinit`

## Work Remaining

### HIGH PRIORITY: Short Word Skipping

**Problem**: Short words like "is" are being skipped in the highlight. Example from logs:
- `word[6]='food'` highlighted at time=2.005s
- `word[8]='healthy'` highlighted at time=2.411s
- `word[7]='is'` was SKIPPED

**Root Cause**: The 60fps timer (~16.7ms intervals) can miss short words if their entire duration falls between two timer ticks.

**Proposed Fix**: Track `lastHighlightedWordIndex` and ensure we don't skip indices. If `wordTiming(at:)` returns word[N] but `lastHighlightedWordIndex` is N-2, show word[N-1] first.

**Location**: `TTSService.swift:updateHighlightFromTime()` around line 1330

**Note**: I implemented this fix earlier (sequential word progression) but reverted it because the user said it was causing the highlight to lag behind audio. The correct approach is to show skipped words briefly (maybe 50-100ms minimum) rather than forcing sequential progression that delays the highlight.

### MEDIUM PRIORITY: Verify Pause/Resume Works

The pause fix (cb2fa1a) needs testing to confirm:
- Pause during playback pauses audio
- Resume continues from where it stopped
- No task cancellation or pipeline restart

### LOW PRIORITY: Code Cleanup

- Remove debug logging added for investigation (🎯 HIGHLIGHT logs)
- Clean up unused code paths
- Consider reducing CTC alignment timeout for faster pipeline

## Attempted Approaches

### What Worked

1. **Stopping highlight timer BEFORE changing alignment** - Prevents stale range application
2. **Guard checking alignment.paragraphIndex == currentProgress.paragraphIndex** - Extra safety
3. **Not throwing CancellationError during pause()** - Allows continuation to stay active
4. **Adding deinit to StreamingAudioPlayer** - Prevents system audio corruption

### What Didn't Work / Issues Found

1. **Sequential word progression fix** - User reported it made highlight lag behind audio. The fix forced showing word[N] before word[N+1], but if audio is at word[4], forcing display of word[3] first makes highlight appear behind.

2. **Forcing last word highlight at sentence end** - User rejected this approach. "The highlight should always be on the currently audible word. We should fix the sync issue, not pause playback."

### Dead Ends to Avoid

- Don't artificially delay or pause to let highlight catch up
- Don't force sequential word display that causes highlight to lag
- Don't throw CancellationError in pause() - it kills the playback task

## Critical Context

### Architecture

- `ReadyQueue` orchestrates synthesis + alignment pipeline
- `TTSService` coordinates playback and highlight updates
- `StreamingAudioPlayer` uses AVAudioEngine for chunk streaming
- `CTCForcedAligner` performs CTC forced alignment for word timings
- Highlight timer runs at 60fps via CADisplayLink

### Key Variables

- `currentAlignment: AlignmentResult?` - Word timings for current sentence
- `currentProgress: ReadingProgress` - Published for UI (paragraphIndex, wordRange)
- `lastHighlightedWordIndex: Int?` - Tracks last shown word to detect changes
- `activeResumer: ContinuationResumer` - Manages async continuation for playback

### Gotchas (Recorded in Workshop)

1. **AVAudioEngine must be explicitly stopped and reset in deinit** - Otherwise causes system-wide audio corruption requiring hard restart

2. **CTC word highlighting has 3 root causes**:
   - Sentence-relative char offsets used as paragraph offsets
   - Wall-clock time instead of AVAudioPlayerNode.playerTime
   - Space token mapping assumes 1 space = 1 span

3. **Session invalidation during long alignment** - 4-5 second alignments can be invalidated mid-processing, causing false "skipped" marking

### Workshop Decisions Recorded

- Fixed pause() killing playback task by not throwing CancellationError
- Fixed highlight offset by verifying alignment belongs to current paragraph
- Fixed false sentence skipping caused by session invalidation
- Fixed CTC alignment sample extraction - streaming chunks are Float32, not WAV Int16

## Current State

### Commits

All fixes committed to local `main` branch:
- 6 commits ahead of origin/main
- All builds successfully
- No uncommitted changes

### Testing Status

- Memory crash: FIXED (needs long-term verification)
- Audio corruption: FIXED (added deinit cleanup)
- Pause/resume freeze: FIXED (needs testing)
- First word of paragraph highlight: FIXED (1626af3)
- Short word skipping ("is"): NOT FIXED - still occurs

### Latest Logs

Location: `/Users/zachswift/listen-2-logs-2025-11-14`

Key observations from logs:
- Word highlighting is generally working (most words highlighted correctly)
- Paragraph transitions now clear alignment properly
- Short words (1-2 characters) occasionally skipped
- Timer running at ~60fps as expected

### Next Steps for New Session

1. **Fix short word skipping** - Implement minimum word display time or ensure sequential coverage without lagging behind audio. Key insight: the timer might need to track "last displayed word index" and ensure all intermediate words get at least one frame of display.

2. **Test pause/resume thoroughly** - Verify the CancellationError removal works correctly

3. **Consider higher timer frequency** - 120fps might catch more short words (but increases CPU)

### Command to Resume

```
Continue debugging word highlight sync in Listen2. The main remaining issue is short words like "is" being skipped during highlighting. The 60fps timer misses words whose entire duration falls between timer ticks. See whats-next.md for full context. Logs at /Users/zachswift/listen-2-logs-2025-11-14
```
