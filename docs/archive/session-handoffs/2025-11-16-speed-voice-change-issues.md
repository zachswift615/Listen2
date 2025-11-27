# Speed and Voice Change Issues - Handoff

**Date:** 2025-11-16
**Status:** Partially working, needs investigation

## Issues

### 1. Speed Changes Don't Take Effect Immediately
**Symptom:** Speed changes sometimes work on next sentence, sometimes only at next paragraph
**Expected:** Speed should change on the very next sentence after slider change

### 2. Voice Changes Cause Runaway Scrolling + No Playback
**Symptom:** After changing voice, playback won't restart and app scrolls to end of book
**Expected:** Voice change should stop cleanly, allow restart from same position

---

## What We've Tried

### Speed Change Attempts

#### Attempt 1: Apply rate to AudioPlayer ✅ Partial Success
**File:** `TTSService.swift:264`
```swift
audioPlayer.setRate(newRate)
```
**Result:** Applies to currently playing sentence, but cached sentences still use old speed

#### Attempt 2: Clear sentence caches ⚠️ Inconsistent
**File:** `SynthesisQueue.swift:194-200`
```swift
sentenceCache.removeAll()
synthesisCacheForTimeline.removeAll()
synthesizingSentences.removeAll()
isProcessingSentences = false
currentSentenceIndex = 0
currentParagraphIndex = 0
```
**Result:** Worked once, then stopped working

### Voice Change Attempts

#### Attempt 1: Catch CancellationError ❌ Didn't Work
**File:** `TTSService.swift:552-558`
```swift
} catch is CancellationError {
    print("[TTSService] ⏸️ Playback cancelled - not advancing")
    isPlaying = false
}
```
**Result:** Still getting runaway scrolling

#### Attempt 2: Resume continuation before stopping ❌ Didn't Work
**File:** `TTSService.swift:465-468`
```swift
if let continuation = activeContinuation {
    continuation.resume(throwing: CancellationError())
    activeContinuation = nil
}
```
**Result:** Prevents continuation leak but still causes runaway advance

---

## Debugging Next Steps

### For Speed Changes

#### Theory 1: Race Condition in Cache Clearing
**Hypothesis:** `setSpeed()` is called but synthesis has already started for next sentence

**Debug approach:**
1. Add logging to `streamSentenceBundles()` to see when sentences are fetched from cache
2. Log the speed value used for each sentence synthesis
3. Check if cache clearing happens AFTER sentence is already in the stream

**File to check:** `SynthesisQueue.swift:450-580` (streamSentenceBundles implementation)

**Key question:** Is the AsyncStream yielding cached sentences before `setSpeed()` completes?

#### Theory 2: AVAudioPlayer.rate Not Taking Effect
**Hypothesis:** Setting `.rate` on AVAudioPlayer doesn't affect already-initialized playback

**Debug approach:**
1. Check when `audioPlayer.setRate()` is called vs when audio starts playing
2. Try setting rate AFTER audio starts (in the play completion callback)
3. Check if AVAudioPlayer needs to be stopped/restarted for rate change

**File to check:** `AudioPlayer.swift:77` (where `player?.rate = rate` is set)

**Test:**
```swift
func setRate(_ rate: Float) {
    self.rate = rate
    player?.rate = rate  // Does this work mid-playback?
    print("[AudioPlayer] Set rate to \(rate), player.rate is now: \(player?.rate ?? 0)")
}
```

#### Theory 3: Multiple Concurrent setSpeed() Calls
**Hypothesis:** User drags slider → multiple rapid `setSpeed()` calls → race condition

**Debug approach:**
1. Add debouncing to speed change (only apply after 200ms of no changes)
2. Log every `setSpeed()` call with timestamp
3. Check if multiple calls are interfering with each other

**Implementation idea:**
```swift
private var speedChangeTask: Task<Void, Never>?

func setPlaybackRate(_ rate: Float) {
    speedChangeTask?.cancel()
    speedChangeTask = Task {
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        if !Task.isCancelled {
            await applySpeedChange(rate)
        }
    }
}
```

---

### For Voice Change Runaway Scrolling

#### Theory 1: CancellationError Not Being Caught
**Hypothesis:** The error type might not match `is CancellationError`

**Debug approach:**
1. Print the actual error type in catch block:
```swift
} catch {
    print("[TTSService] ❌ Error type: \(type(of: error))")
    print("[TTSService] ❌ Error description: \(error)")
    if error is CancellationError {
        print("[TTSService] ✅ IS CancellationError")
    } else {
        print("[TTSService] ⚠️ NOT CancellationError")
    }
}
```

2. Check if it's a different cancellation type (Task.CancellationError, etc.)

**File to check:** `TTSService.swift:552-573`

#### Theory 2: Multiple Tasks Running After Voice Change
**Hypothesis:** Old `speakParagraph()` Task keeps running after new voice initializes

**Debug approach:**
1. Store Task reference when starting `speakParagraph()`
2. Cancel old Task before creating new one
3. Add Task ID logging to see if multiple tasks are racing

**Implementation idea:**
```swift
private var speakParagraphTask: Task<Void, Never>?

private func speakParagraph(at index: Int) {
    // Cancel any existing task
    speakParagraphTask?.cancel()

    speakParagraphTask = Task {
        let taskID = UUID()
        print("[TTSService] Starting speakParagraph task \(taskID)")
        defer { print("[TTSService] Ending speakParagraph task \(taskID)") }

        if let queue = synthesisQueue {
            // ... existing code
        }
    }
}
```

#### Theory 3: handleParagraphComplete() Called from Somewhere Else
**Hypothesis:** Auto-advance might be triggered outside the error path

**Debug approach:**
1. Add stack trace logging to `handleParagraphComplete()`:
```swift
func handleParagraphComplete() {
    print("[TTSService] ⚠️ handleParagraphComplete() called")
    print("[TTSService] Stack trace: \(Thread.callStackSymbols)")
    // ... existing code
}
```

2. Search for all calls to `handleParagraphComplete()` in codebase
3. Check if it's being called from multiple places

**File to check:** `TTSService.swift` - search for `handleParagraphComplete()`

#### Theory 4: AsyncStream Not Being Cancelled
**Hypothesis:** `streamSentenceBundles()` continues yielding even after stop()

**Debug approach:**
1. Check if AsyncStream respects Task cancellation
2. Add explicit cancellation check in stream:
```swift
for await bundle in await queue.streamSentenceBundles(for: index) {
    if Task.isCancelled {
        print("[TTSService] Task cancelled, breaking stream")
        break
    }
    try await playSentenceAudio(bundle, ...)
}
```

**File to check:** `SynthesisQueue.swift:450+` (streamSentenceBundles)

---

## Critical Files to Review

### For Speed Changes
1. `SynthesisQueue.swift:175-202` - setSpeed() implementation
2. `SynthesisQueue.swift:450-580` - streamSentenceBundles() (AsyncStream generation)
3. `AudioPlayer.swift:77` - rate application
4. `TTSService.swift:245-300` - setPlaybackRate() implementation

### For Voice Changes
1. `TTSService.swift:302-362` - setVoice() implementation
2. `TTSService.swift:536-574` - speakParagraph() error handling
3. `TTSService.swift:462-493` - stop() implementation
4. `SynthesisQueue.swift:450+` - Check if AsyncStream continues after cancellation

---

## Recommended Next Steps

### Immediate Actions (30 mins each)

1. **Add comprehensive logging** to understand what's actually happening:
   - Log every cache access (hit/miss)
   - Log every speed value used in synthesis
   - Log every error with its actual type
   - Log Task lifecycle (start/end/cancel)

2. **Test with minimal reproducer**:
   - Single paragraph document
   - Change speed mid-sentence
   - Change voice mid-playback
   - Look at logs to see exact sequence

3. **Verify assumptions**:
   - Does `CancellationError()` match `is CancellationError`?
   - Does `audioPlayer.setRate()` work mid-playback?
   - Is `setSpeed()` actually being awaited before playback restarts?

### Deeper Investigation (1-2 hours each)

4. **AsyncStream cancellation behavior**:
   - Test if `for await` loop breaks when Task is cancelled
   - Test if `streamSentenceBundles()` stops yielding after `stop()`
   - Consider using `Task.isCancelled` checks

5. **Audio player rate timing**:
   - Test setting rate before vs after audio starts
   - Test if rate needs to be set per-sentence vs once globally
   - Consider rebuilding audio player when rate changes

6. **Task lifecycle management**:
   - Track all active Tasks
   - Cancel old tasks before starting new ones
   - Add Task IDs for debugging

---

## Potential Solutions to Try

### For Speed Changes

#### Option A: Restart Current Sentence (Most Reliable)
```swift
func setPlaybackRate(_ rate: Float) {
    // ... existing setup ...

    if wasPlaying {
        Task {
            await synthesisQueue?.setSpeed(newRate)

            // Resume continuation to cancel current sentence
            if let continuation = activeContinuation {
                continuation.resume(throwing: CancellationError())
                activeContinuation = nil
            }

            await audioPlayer.stop()

            // Restart from CURRENT SENTENCE, not paragraph
            let currentSentenceIndex = wordHighlighter.currentSentenceIndex
            speakParagraph(at: currentIndex, startingSentence: currentSentenceIndex)
        }
    }
}
```

#### Option B: Debounce Speed Changes
```swift
private var speedChangeTask: Task<Void, Never>?

func setPlaybackRate(_ rate: Float) {
    speedChangeTask?.cancel()
    speedChangeTask = Task {
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        await applySpeedChangeImmediately(rate)
    }
}
```

### For Voice Changes

#### Option A: Use Task.isCancelled Checks
```swift
for await bundle in await queue.streamSentenceBundles(for: index) {
    guard !Task.isCancelled else {
        print("[TTSService] Task cancelled, stopping stream")
        break
    }
    try await playSentenceAudio(bundle, ...)
}

// Don't call handleParagraphComplete() if cancelled
if !Task.isCancelled {
    handleParagraphComplete()
}
```

#### Option B: Store and Cancel Tasks
```swift
private var activeSpeakTask: Task<Void, Never>?

private func speakParagraph(at index: Int) {
    activeSpeakTask?.cancel()
    activeSpeakTask = Task {
        defer { activeSpeakTask = nil }
        // ... existing code
    }
}

func stop() {
    activeSpeakTask?.cancel()
    activeSpeakTask = nil
    // ... existing code
}
```

---

## Questions to Answer

1. **When exactly is the sentence cache accessed?**
   - Before or after `setSpeed()`?
   - Does the AsyncStream hold references to cached sentences?

2. **What error type is actually thrown?**
   - Is it `CancellationError`?
   - Or `Task.CancellationError`?
   - Or something else?

3. **Is the Task actually being cancelled?**
   - Check `Task.isCancelled` in the loop
   - Add logging to see if loop continues after cancellation

4. **How many Tasks are running?**
   - Are old tasks still running after new ones start?
   - Are we creating Task leaks?

---

## Log Strings to Search For

When testing, grep for these in the logs:

**Speed change diagnostics:**
```
"🎚️ Changing speed from"
"🗑️ Clearing ALL caches"
"🎵 Synthesizing sentence"
"🔊 Applied playback rate"
```

**Voice change diagnostics:**
```
"🎤 Switching to voice"
"⏸️ Playback cancelled"
"⚠️ Resuming active continuation"
"handleParagraphComplete"
```

**Error diagnostics:**
```
"Error type:"
"CancellationError"
"Task cancelled"
```

---

## Contact Points

If you need to dive deeper, these are the key integration points:

1. **Speed application**: `AudioPlayer.swift:77` - where `player?.rate = rate` happens
2. **Cache lookup**: `SynthesisQueue.swift:490+` - where sentence cache is checked
3. **Stream generation**: `SynthesisQueue.swift:450+` - where AsyncStream yields sentences
4. **Error handling**: `TTSService.swift:552` - where CancellationError should be caught
5. **Auto-advance**: Search for `handleParagraphComplete()` calls

---

## Success Criteria

**Speed Changes:** User drags slider → next sentence plays at new speed (< 2 seconds delay)

**Voice Changes:** User selects new voice → playback stops → can restart from same position → no scrolling

Good luck! 🚀
