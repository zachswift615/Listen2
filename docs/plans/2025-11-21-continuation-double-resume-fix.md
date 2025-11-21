# Fix: Continuation Double-Resume Bug

**Date:** 2025-11-21
**Status:** IMPLEMENTED - Build successful

## Problem

Runtime crash: `SWIFT TASK CONTINUATION MISUSE: playSentenceWithChunks(sentence:isLast:) tried to resume its continuation more than once`

The app crashes after playing successfully for a while, when something triggers `stop()` or `stopAudioOnly()` during playback.

## Root Cause Analysis

### The Bug Pattern

Both `playSentenceWithChunks` (line 706) and `playBufferedChunks` (line 812) capture `continuation` directly in the `startStreaming` completion closure:

```swift
audioPlayer.startStreaming { [weak self] in
    self?.activeContinuation = nil
    continuation.resume()  // ← Captures continuation directly by value!
}
```

Setting `activeContinuation = nil` does NOT prevent the captured `continuation` from being called - it's a separate reference.

### The Race Condition

When `stop()` or `stopAudioOnly()` is called during playback:

1. `stop()` gets `activeContinuation` and calls `continuation.resume(throwing: CancellationError())`
2. `stop()` sets `activeContinuation = nil`
3. `stop()` calls `audioPlayer.stop()` **in a separate async Task** (line 527-528) - NOT awaited!
4. Before the audio player actually stops, `checkCompletion()` in StreamingAudioPlayer fires
5. `checkCompletion()` calls `onFinished()` callback
6. The callback's captured `continuation.resume()` executes - **CRASH: double resume!**

### Code Evidence

TTSService.swift `stop()` function (lines 521-532):
```swift
// Resume continuation first
if let continuation = activeContinuation {
    continuation.resume(throwing: CancellationError())
    activeContinuation = nil
}

// Audio player stop happens ASYNCHRONOUSLY - race condition!
Task {
    await audioPlayer.stop()
    ...
}
```

## Fix Strategy

Create a thread-safe `ContinuationResumer` wrapper that prevents double-resume by tracking whether the continuation has already been resumed.

## Implementation

### 1. Add `ContinuationResumer` Helper Class

Add to TTSService.swift (near the top, after imports):

```swift
/// Thread-safe wrapper to ensure continuation is only resumed once
/// Prevents crashes from race conditions between stop() and playback completion
private final class ContinuationResumer<T, E: Error>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, E>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    /// Resume with success value. Safe to call multiple times - only first call takes effect.
    func resume(returning value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()  // IMPORTANT: Unlock BEFORE calling resume to prevent deadlocks
        cont?.resume(returning: value)
    }

    /// Resume with error. Safe to call multiple times - only first call takes effect.
    func resume(throwing error: E) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()  // IMPORTANT: Unlock BEFORE calling resume to prevent deadlocks
        cont?.resume(throwing: error)
    }

    /// Check if already resumed
    var isResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation == nil
    }
}
```

**Note:** The lock is released BEFORE calling `resume()` to prevent potential priority inversion or deadlocks if the continuation's resume triggers work that needs the same lock.

### 2. Update Property Declaration (Line 66)

Change from:
```swift
private var activeContinuation: CheckedContinuation<Void, Error>?
```

To:
```swift
private var activeResumer: ContinuationResumer<Void, Error>?
```

### 3. Update `playSentenceWithChunks` (Lines 693-741)

```swift
private func playSentenceWithChunks(sentence: String, isLast: Bool) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        Task { @MainActor in
            // Wrap continuation in thread-safe resumer
            let resumer = ContinuationResumer(continuation)
            activeResumer = resumer

            do {
                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    print("[TTSService] 🏁 Sentence playback complete")
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                // Create delegate to receive chunks
                let chunkDelegate = ChunkStreamDelegate(audioPlayer: audioPlayer)

                // Start synthesis with streaming
                Task {
                    do {
                        _ = try await synthesisQueue?.streamSentence(sentence, delegate: chunkDelegate)
                        await MainActor.run {
                            audioPlayer.finishScheduling()
                        }
                    } catch {
                        print("[TTSService] ❌ Synthesis error: \(error)")
                        await MainActor.run {
                            self.activeResumer = nil
                            resumer.resume(throwing: error)  // Safe - won't double-resume
                        }
                    }
                }

                isPlaying = true
                shouldAutoAdvance = true

            } catch {
                activeResumer = nil
                resumer.resume(throwing: error)
            }
        }
    }
}
```

### 4. Update `playBufferedChunks` (Lines 795-833)

Same pattern - wrap continuation in `ContinuationResumer` and use `resumer.resume()` everywhere:

```swift
private func playBufferedChunks(_ chunks: [Data]) async throws {
    guard !chunks.isEmpty else {
        print("[TTSService] ⏭️ Skipping empty buffered sentence")
        return
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        Task { @MainActor in
            // Wrap continuation in thread-safe resumer
            let resumer = ContinuationResumer(continuation)
            activeResumer = resumer

            do {
                audioPlayer.startStreaming { [weak self] in
                    print("[TTSService] 🏁 Buffered playback complete")
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }
                audioPlayer.finishScheduling()

                isPlaying = true
                shouldAutoAdvance = true

            } catch {
                activeResumer = nil
                resumer.resume(throwing: error)
            }
        }
    }
}
```

### 5. Update `stop()` (Lines 511-549)

```swift
func stop() {
    if let task = activeSpeakTask {
        print("[TTSService] 🛑 Cancelling active speak task during stop()")
        task.cancel()
        activeSpeakTask = nil
    }

    // Resume any active continuation (safe - resumer prevents double-resume)
    if let resumer = activeResumer {
        print("[TTSService] ⚠️ Resuming active continuation during stop()")
        resumer.resume(throwing: CancellationError())
        activeResumer = nil
    }

    Task {
        await audioPlayer.stop()
        await synthesisQueue?.clearAll()
        wordHighlighter.stop()
    }
    // ... rest of stop()
}
```

### 6. Update `stopAudioOnly()` (Lines 478-509) - CRITICAL ADDITION

**This was missing from v1!** `stopAudioOnly()` is called by `skipToNext()` and `skipToPrevious()` but did NOT handle the continuation, causing the same race condition.

```swift
private func stopAudioOnly() {
    if let task = activeSpeakTask {
        task.cancel()
        activeSpeakTask = nil
    }

    // CRITICAL: Resume any active continuation to prevent double-resume crash
    if let resumer = activeResumer {
        print("[TTSService] ⚠️ Resuming active continuation during stopAudioOnly()")
        resumer.resume(throwing: CancellationError())
        activeResumer = nil
    }

    Task {
        await audioPlayer.stop()
        // ... rest
    }
    // ...
}
```

### 7. Update All Other Continuation Access Points

Complete list of locations that need updating:

| Line(s) | Location | Change |
|---------|----------|--------|
| 66 | Property declaration | `activeContinuation` → `activeResumer` |
| 291-294 | `setPlaybackRate()` | Use `activeResumer` |
| 432-435 | `pause()` | Use `activeResumer` |
| 478-509 | `stopAudioOnly()` | **ADD** resumer handling (was missing!) |
| 521-524 | `stop()` | Use `activeResumer` |
| 698, 705, 725, 736 | `playSentenceWithChunks()` | Use resumer pattern |
| 805, 811, 828 | `playBufferedChunks()` | Use resumer pattern |

## Files Modified

1. `Listen2/Services/TTSService.swift`
   - Add `ContinuationResumer` class (new code near top)
   - Change `activeContinuation` property to `activeResumer` (line 66)
   - Update `setPlaybackRate()` (lines 291-294)
   - Update `pause()` (lines 432-435)
   - Update `stopAudioOnly()` (lines 478-509) - **ADD continuation handling**
   - Update `stop()` (lines 521-524)
   - Update `playSentenceWithChunks()` (lines 693-741)
   - Update `playBufferedChunks()` (lines 795-833)

## Testing

### Basic Tests
1. Start reading a document
2. While audio is playing, trigger stop (pause button)
3. Verify no crash occurs
4. Verify playback stops cleanly
5. Verify can resume/restart playback

### Skip Tests (exercises `stopAudioOnly()`)
6. While audio is playing, tap skip forward rapidly
7. While audio is playing, tap skip backward rapidly
8. Alternate skip forward/backward quickly
9. Verify no crashes during any skip operation

### Edge Case Tests
10. Stop during sentence boundary transition
11. Stop when synthesis is in progress but no audio scheduled yet
12. Voice change during playback (triggers stop)
13. Speed change during playback (triggers stop)

## Risks

- **Low risk:** The `ContinuationResumer` is a simple, focused helper class
- **Thread safety:** Uses `NSLock` with proper unlock-before-resume pattern
- **No behavior change:** Only prevents the crash, doesn't change normal operation

## Alternatives Considered

1. **Make `stop()` await `audioPlayer.stop()`** - Would work but changes the async behavior of stop() and could cause UI delays
2. **Use `withTaskCancellationHandler`** - More complex and doesn't handle all the race conditions (completion callback race not addressed)
3. **Nil out `onFinished` before resuming** - Doesn't work because the closure captures continuation directly by value
4. **Simple Bool flag without lock** - Would work since all access is on MainActor, but NSLock is more defensive

## Review History

- **v1 (2025-11-21):** Initial draft
- **v2 (2025-11-21):** Revised after code review
  - Fixed: Lock ordering in `ContinuationResumer` (unlock before resume)
  - Added: `stopAudioOnly()` handling (was completely missing!)
  - Added: Complete line number reference table
  - Added: More comprehensive test cases for skip operations
