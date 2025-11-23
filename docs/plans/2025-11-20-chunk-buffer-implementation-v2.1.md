# Implementation Plan: 1-Sentence Lookahead Buffer (v2.1 - Final Review Fixes)

## Changes from v2 → v2.1

**Critical fixes applied based on code review:**
1. ✅ Fixed BufferingChunkDelegate actor isolation (removed @MainActor from class, added to properties/methods)
2. ✅ Added Task.isCancelled checks in startPreSynthesis (3 checkpoints)
3. ✅ Added chunkBuffer.clearAll() to stopAudioOnly (fixes skip button memory leak)
4. ✅ Added empty sentence handling in playBufferedChunks (prevents audio player confusion)

**Status:** APPROVED FOR IMPLEMENTATION

---

## Goal
Eliminate sentence gaps with proper completion tracking to prevent race conditions and partial chunk retrieval.

## Critical Fix: Completion Tracking

The key insight from code review: `didReceiveAudioChunk()` uses fire-and-forget Tasks, so `streamSentence()` returning does NOT mean all chunks are buffered. We must wait for all delegate callbacks to complete.

## Architecture

**Single-sentence lookahead with guaranteed completion:**
- While sentence N plays, sentence N+1 pre-synthesizes into buffer
- Delegate tracks pending chunk additions with continuation
- Only mark complete AFTER all delegate Tasks finish
- When N finishes, N+1's chunks are atomically retrieved and flushed to player

---

## Task 1: Create ChunkBuffer Actor

**File:** `Listen2/Listen2/Listen2/Services/TTS/ChunkBuffer.swift` (new file)

```swift
//
//  ChunkBuffer.swift
//  Listen2
//
//  Thread-safe buffer for pre-synthesized audio chunks
//

import Foundation

actor ChunkBuffer {
    // MARK: - State

    /// Buffered chunks per sentence: sentenceIndex → chunks
    private var buffers: [Int: [Data]] = [:]

    /// Sentences that have completed synthesis AND all chunks buffered
    private var completedSentences: Set<Int> = []

    /// Current buffer size in bytes
    private var currentSize: Int = 0

    /// Maximum buffer size (2MB - safety limit for long sentences)
    private let maxBufferSize: Int = 2 * 1024 * 1024

    // Metrics
    private var hitCount: Int = 0
    private var missCount: Int = 0

    // MARK: - Public Methods

    /// Add a chunk for a specific sentence
    func addChunk(_ chunk: Data, forSentence index: Int) {
        // Validate chunk
        guard !chunk.isEmpty else {
            print("[ChunkBuffer] ⚠️ Ignoring empty chunk for sentence \(index)")
            return
        }

        guard chunk.count % MemoryLayout<Float>.size == 0 else {
            print("[ChunkBuffer] ⚠️ Invalid chunk size \(chunk.count) for sentence \(index)")
            return
        }

        // Check buffer size limit
        guard currentSize + chunk.count <= maxBufferSize else {
            print("[ChunkBuffer] ⚠️ Buffer full (\(currentSize) bytes), dropping chunk for sentence \(index)")
            return
        }

        // Add chunk to buffer
        buffers[index, default: []].append(chunk)
        currentSize += chunk.count

        #if DEBUG
        let chunkCount = buffers[index]?.count ?? 0
        if chunkCount % 10 == 0 || chunkCount == 1 {
            print("[ChunkBuffer] 📦 Added chunk #\(chunkCount) for sentence \(index) (buffer: \(currentSize) bytes)")
        }
        #endif
    }

    /// Mark a sentence as complete (all chunks received and buffered)
    /// CRITICAL: Only call this AFTER all delegate Tasks have completed!
    func markComplete(forSentence index: Int) {
        completedSentences.insert(index)
        let chunkCount = buffers[index]?.count ?? 0
        print("[ChunkBuffer] ✅ Sentence \(index) complete (\(chunkCount) chunks buffered)")
    }

    /// Atomically take all chunks for a sentence (removes from buffer)
    /// Returns nil if synthesis not marked complete
    func takeChunks(forSentence index: Int) -> [Data]? {
        // Check if synthesis is complete
        guard completedSentences.contains(index) else {
            print("[ChunkBuffer] ⏳ Sentence \(index) not ready (synthesis incomplete)")
            missCount += 1
            return nil
        }

        // Remove chunks from buffer (may be empty for empty sentences)
        let chunks = buffers.removeValue(forKey: index) ?? []

        // Update size and completion tracking
        let chunkSize = chunks.reduce(0) { $0 + $1.count }
        currentSize -= chunkSize
        completedSentences.remove(index)
        hitCount += 1

        if chunks.isEmpty {
            print("[ChunkBuffer] ℹ️ Sentence \(index) is empty (0 chunks)")
        } else {
            print("[ChunkBuffer] 🎯 Took \(chunks.count) chunks for sentence \(index) (freed \(chunkSize) bytes, remaining: \(currentSize) bytes)")
        }

        return chunks
    }

    /// Check if a sentence is ready (synthesis complete)
    func isReady(forSentence index: Int) -> Bool {
        return completedSentences.contains(index)
    }

    /// Clear all buffered data
    func clearAll() {
        let clearedSize = currentSize
        let clearedSentences = buffers.count

        buffers.removeAll()
        completedSentences.removeAll()
        currentSize = 0

        if clearedSentences > 0 {
            print("[ChunkBuffer] 🗑️ Cleared all buffers (\(clearedSentences) sentences, \(clearedSize) bytes)")
        }
    }

    /// Get buffer hit rate metric
    func getHitRate() -> Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }

    /// Get debug info
    func getStatus() -> String {
        let hitRate = getHitRate()
        return "Buffered: \(buffers.count) sentences, \(currentSize) bytes, Hit rate: \(String(format: "%.1f%%", hitRate * 100))"
    }
}
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Services/TTS/ChunkBuffer.swift
git commit -m "feat: add ChunkBuffer actor with completion tracking

Provides thread-safe storage for pre-synthesized audio chunks with:
- Atomic takeChunks() operation (removes as it retrieves)
- Explicit completion tracking (only ready after markComplete)
- Buffer size limits (2MB) to prevent memory issues
- Chunk validation (size and format checks)
- Hit rate metrics for performance monitoring
- Comprehensive debug logging

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Add BufferingChunkDelegate with Completion Tracking

**File:** `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift` (add before ChunkStreamDelegate)

```swift
// MARK: - Buffering Chunk Delegate with Completion Tracking

/// Delegate that receives audio chunks and stores them in ChunkBuffer
/// Tracks pending chunk additions to ensure all chunks are buffered before marking complete
/// NOT @MainActor on class - runs in background pre-synthesis tasks
private class BufferingChunkDelegate: SynthesisStreamDelegate {
    private let buffer: ChunkBuffer
    private let sentenceIndex: Int

    // Track pending async chunk additions (main-actor isolated)
    @MainActor private var pendingChunks: Int = 0
    @MainActor private var completion: CheckedContinuation<Void, Never>?

    init(buffer: ChunkBuffer, sentenceIndex: Int) {
        self.buffer = buffer
        self.sentenceIndex = sentenceIndex
    }

    /// Wait for all chunk additions to complete
    /// CRITICAL: Call this before markComplete() to prevent race conditions!
    @MainActor func waitForCompletion() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if pendingChunks == 0 {
                // All chunks already buffered
                continuation.resume()
            } else {
                // Store continuation, will resume when pendingChunks reaches 0
                self.completion = continuation
            }
        }
    }

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        Task { @MainActor in
            // Increment pending count
            self.pendingChunks += 1

            // Add chunk to buffer (async actor call)
            await self.buffer.addChunk(chunk, forSentence: self.sentenceIndex)

            // Decrement pending count
            self.pendingChunks -= 1

            // Check if all chunks are now buffered
            if self.pendingChunks == 0, let continuation = self.completion {
                self.completion = nil
                continuation.resume()
            }
        }
        return true // Continue synthesis
    }
}
```

**Also add ChunkBuffer property to TTSService:**

```swift
// Add after synthesisQueue property (around line 37):
private let chunkBuffer = ChunkBuffer()
```

**Remove initialization from init() - it's now a let constant**

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: add BufferingChunkDelegate with completion tracking

Tracks pending async chunk additions using continuation pattern.
Ensures all delegate callbacks complete before synthesis is marked done.
Prevents race condition where takeChunks() retrieves partial audio.

This fixes the audio distortion bug from commit e20d75a.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Modify speakParagraph for 1-Sentence Lookahead

**File:** `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

Replace the sentence loop in `speakParagraph` (lines 576-591) with:

```swift
// Track pre-synthesis task for cancellation
var preSynthesisTask: Task<Void, Never>?

// Cleanup function to cancel and clear
func cleanup() async {
    preSynthesisTask?.cancel()
    await chunkBuffer.clearAll()
}

// Start pre-synthesis for first sentence (N+1 when N=0)
if sentences.count > 1 {
    preSynthesisTask = startPreSynthesis(
        sentence: sentences[1].text,
        index: 1
    )
}

// Play each sentence with lookahead buffering
for (sentenceIndex, chunk) in sentences.enumerated() {
    // Check cancellation
    guard !Task.isCancelled else {
        print("[TTSService] 🛑 Task cancelled - breaking loop")
        await cleanup()
        throw CancellationError()
    }

    print("[TTSService] 🎤 Starting sentence \(sentenceIndex+1)/\(sentences.count)")

    // Try to use buffered chunks if available
    if let bufferedChunks = await chunkBuffer.takeChunks(forSentence: sentenceIndex),
       !bufferedChunks.isEmpty {
        print("[TTSService] ⚡️ Playing from buffer (\(bufferedChunks.count) chunks)")
        try await playBufferedChunks(bufferedChunks)
    } else {
        // Buffer miss - synthesize on-demand
        print("[TTSService] 🔄 Buffer miss, synthesizing on-demand")
        try await playSentenceWithChunks(
            sentence: chunk.text,
            isLast: sentenceIndex == sentences.count - 1
        )
    }

    // Start pre-synthesis for next sentence (N+1)
    let nextIndex = sentenceIndex + 1
    if nextIndex < sentences.count {
        preSynthesisTask?.cancel() // Cancel previous if still running
        preSynthesisTask = startPreSynthesis(
            sentence: sentences[nextIndex].text,
            index: nextIndex
        )
    }
}

// Final cleanup
await cleanup()

// Log buffer performance
let status = await chunkBuffer.getStatus()
let hitRate = await chunkBuffer.getHitRate()
print("[TTSService] 📊 Buffer performance: \(status)")
if hitRate < 0.9 {
    print("[TTSService] ⚠️ Low buffer hit rate (\(String(format: "%.1f%%", hitRate * 100))), synthesis may be slower than playback")
}
```

**Add helper methods after playSentenceWithChunks:**

```swift
/// Start pre-synthesis for a sentence in the background
/// Returns Task that can be cancelled
private func startPreSynthesis(sentence: String, index: Int) -> Task<Void, Never> {
    return Task {
        // Check cancellation before expensive work
        guard !Task.isCancelled else {
            print("[TTSService] 🛑 Pre-synthesis cancelled before starting for sentence \(index)")
            return
        }

        guard let queue = await self.synthesisQueue else {
            return
        }

        print("[TTSService] 🔮 Pre-synthesizing sentence \(index): '\(sentence.prefix(50))...'")

        do {
            let delegate = await BufferingChunkDelegate(
                buffer: chunkBuffer,
                sentenceIndex: index
            )

            // Check again after delegate creation
            guard !Task.isCancelled else {
                print("[TTSService] 🛑 Pre-synthesis cancelled during setup for sentence \(index)")
                return
            }

            // Synthesize with streaming delegate
            _ = try await queue.streamSentence(sentence, delegate: delegate)

            // Check before waiting for completion
            guard !Task.isCancelled else {
                print("[TTSService] 🛑 Pre-synthesis cancelled after synthesis for sentence \(index)")
                return
            }

            // CRITICAL: Wait for all chunk additions to complete!
            await delegate.waitForCompletion()

            // Now it's safe to mark complete
            await chunkBuffer.markComplete(forSentence: index)

            print("[TTSService] ✅ Pre-synthesis complete for sentence \(index)")
        } catch is CancellationError {
            print("[TTSService] 🛑 Pre-synthesis cancelled for sentence \(index)")
        } catch {
            print("[TTSService] ⚠️ Pre-synthesis failed for sentence \(index): \(error)")
        }
    }
}

/// Play buffered chunks that were pre-synthesized
private func playBufferedChunks(_ chunks: [Data]) async throws {
    // Handle empty sentences (e.g., only punctuation)
    guard !chunks.isEmpty else {
        print("[TTSService] ⏭️ Skipping empty buffered sentence")
        return
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        Task { @MainActor in
            activeContinuation = continuation

            do {
                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    print("[TTSService] 🏁 Buffered playback complete")
                    self?.activeContinuation = nil
                    continuation.resume()
                }

                // Schedule all buffered chunks immediately
                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // Update playback state
                isPlaying = true
                shouldAutoAdvance = true

            } catch {
                activeContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: implement 1-sentence lookahead with proper completion tracking

While sentence N plays, sentence N+1 pre-synthesizes into buffer.
Delegate.waitForCompletion() ensures all chunks buffered before markComplete().
When N finishes, N+1 chunks atomically retrieved and played.
Falls back to on-demand synthesis on buffer miss.

Eliminates sentence gaps with zero audio distortion.
Tracks buffer hit rate for performance monitoring.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Integrate Buffer Clearing (Correct Order)

**File:** `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**4a. Speed change (around line 282):**

```swift
// CORRECT ORDER: Cancel → Clear → Update
if let task = activeSpeakTask {
    print("[TTSService] 🛑 Cancelling active speak task for speed change")
    task.cancel()
}
await chunkBuffer.clearAll()  // Clear BEFORE speed change
await synthesisQueue?.setSpeed(newRate)
await audioPlayer.stop()
```

**4b. Voice change (around line 362):**

```swift
// CORRECT ORDER: Cancel → Clear → Update
if let task = activeSpeakTask {
    task.cancel()
}
await chunkBuffer.clearAll()  // Clear BEFORE voice change
self.synthesisQueue = SynthesisQueue(provider: piperProvider)
await synthesisQueue?.setContent(/* ... */)
```

**4c. Stop (around line 474):**

```swift
// In stopAudioOnly():
if let task = activeSpeakTask {
    task.cancel()
}
await chunkBuffer.clearAll()  // Clear before stop
await synthesisQueue?.clearAll()
```

**4d. Skip buttons (stopAudioOnly around line 470):**

```swift
// In stopAudioOnly():
private func stopAudioOnly() {
    Task {
        await audioPlayer.stop()
        await chunkBuffer.clearAll()  // ← ADD THIS (clear before synthesis queue)
        await synthesisQueue?.clearAll()
        await MainActor.run {
            wordHighlighter.stop()
        }
    }
    // ... rest of method
}
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "fix: clear chunk buffer in correct order on state changes

Buffer contents are speed/voice-dependent and must be cleared AFTER
cancelling tasks but BEFORE updating speed/voice. This prevents:
- Playing cached audio at wrong speed
- Playing cached audio with wrong voice
- Race conditions with pre-synthesis tasks

Order: Cancel tasks → Clear buffer → Update state

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Add ChunkBuffer to Xcode Project

Since the project uses explicit file references (not PBXFileSystemSynchronizedRootGroup), must manually add:

```bash
open Listen2/Listen2/Listen2.xcodeproj
# In Xcode:
# 1. Right-click on Services/TTS folder
# 2. Add Files to "Listen2"
# 3. Select ChunkBuffer.swift
# 4. Ensure target "Listen2" is checked
# 5. Click Add
```

Then commit the project file:

```bash
git add Listen2/Listen2/Listen2.xcodeproj/project.pbxproj
git commit -m "build: add ChunkBuffer.swift to Xcode project

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Build and Test

**Build verification:**
```bash
cd Listen2/Listen2
xcodebuild clean -project Listen2.xcodeproj -scheme Listen2
xcodebuild build -project Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: BUILD SUCCEEDED with 0 errors

**Testing Checklist:**

- [ ] **Gap eliminated:** Play multi-sentence paragraph, listen for smooth transitions
- [ ] **Buffer hit rate:** Check logs for hit rate > 90%
- [ ] **Speed change:** Change speed mid-paragraph, verify buffer clears and new speed works
- [ ] **Voice change:** Change voice, verify buffer clears
- [ ] **Stop mid-paragraph:** Stop during playback, verify no crashes
- [ ] **Skip forward:** Skip to next paragraph, verify pre-synthesis cancels
- [ ] **Race condition test:** Start playback, immediately skip (tests cancellation)
- [ ] **Memory usage:** Check Xcode memory gauge stays < 50MB
- [ ] **Very short sentences:** Test 1-2 word sentences work smoothly
- [ ] **Very long sentences:** Test 100+ word sentences don't blow up buffer
- [ ] **Empty sentences:** Test sentences with only punctuation

**Performance validation:**
```swift
// Add to speakParagraph after loop:
let hitRate = await chunkBuffer.getHitRate()
print("[TTSService] Final buffer hit rate: \(String(format: "%.1f%%", hitRate * 100))")
```

Target: > 90% hit rate (90% of sentences play from buffer)

---

## Success Criteria

- ✅ No perceivable gap between sentences
- ✅ Buffer hit rate > 90% (logged at end of paragraph)
- ✅ Memory stays < 50MB during playback
- ✅ No audio distortion or garbled audio
- ✅ All edge cases handled gracefully (speed, voice, stop, skip)
- ✅ Clean logs showing pre-synthesis and buffer hits

---

## Rollback Plan

If this causes issues:

```bash
git log --oneline -6  # Find commits
git revert HEAD~5..HEAD  # Revert all buffer commits
```

The direct-streaming code will still work.

---

## Workshop Documentation

After successful implementation:

```bash
workshop decision "1-sentence lookahead buffer eliminates gaps with proper completion tracking" -r "BufferingChunkDelegate tracks pending chunk additions using continuation pattern. Only marks sentence complete after waitForCompletion() ensures all delegate Tasks finished. This prevents race condition that caused audio distortion in e20d75a. Buffer hit rate >90% means synthesis is faster than playback."
```
