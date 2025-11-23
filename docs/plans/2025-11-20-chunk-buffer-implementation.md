# Implementation Plan: 1-Sentence Lookahead Buffer (Option B)

## Goal
Eliminate sentence gaps with minimal complexity using 1-sentence lookahead buffer with atomic operations and proper completion tracking.

## Architecture

**Single-sentence lookahead:**
- While sentence N plays, sentence N+1 pre-synthesizes into buffer
- When N finishes, N+1's chunks are atomically retrieved and flushed to player
- Chunks are removed from buffer as they're taken for playback

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

    /// Sentences that have completed synthesis
    private var completedSentences: Set<Int> = []

    /// Current buffer size in bytes
    private var currentSize: Int = 0

    /// Maximum buffer size (2MB - safety limit for long sentences)
    private let maxBufferSize: Int = 2 * 1024 * 1024

    // MARK: - Public Methods

    /// Add a chunk for a specific sentence
    func addChunk(_ chunk: Data, forSentence index: Int) {
        // Check buffer size limit
        guard currentSize + chunk.count <= maxBufferSize else {
            print("[ChunkBuffer] ⚠️ Buffer full (\(currentSize) bytes), dropping chunk for sentence \(index)")
            return
        }

        // Add chunk to buffer
        buffers[index, default: []].append(chunk)
        currentSize += chunk.count

        print("[ChunkBuffer] 📦 Added \(chunk.count) byte chunk for sentence \(index) (total: \(currentSize) bytes)")
    }

    /// Mark a sentence as complete (all chunks received)
    func markComplete(forSentence index: Int) {
        completedSentences.insert(index)
        let chunkCount = buffers[index]?.count ?? 0
        print("[ChunkBuffer] ✅ Sentence \(index) complete (\(chunkCount) chunks)")
    }

    /// Atomically take all chunks for a sentence (removes from buffer)
    /// Returns nil if synthesis not complete
    func takeChunks(forSentence index: Int) -> [Data]? {
        // Check if synthesis is complete
        guard completedSentences.contains(index) else {
            print("[ChunkBuffer] ⏳ Sentence \(index) not ready (synthesis incomplete)")
            return nil
        }

        // Remove chunks from buffer
        guard let chunks = buffers.removeValue(forKey: index) else {
            print("[ChunkBuffer] ⚠️ Sentence \(index) marked complete but has no chunks")
            return nil
        }

        // Update size and completion tracking
        let chunkSize = chunks.reduce(0) { $0 + $1.count }
        currentSize -= chunkSize
        completedSentences.remove(index)

        print("[ChunkBuffer] 🎯 Took \(chunks.count) chunks for sentence \(index) (freed \(chunkSize) bytes, remaining: \(currentSize) bytes)")

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

        print("[ChunkBuffer] 🗑️ Cleared all buffers (\(clearedSentences) sentences, \(clearedSize) bytes)")
    }

    /// Get debug info
    func getStatus() -> String {
        return "Buffered: \(buffers.count) sentences, \(currentSize) bytes, Completed: \(completedSentences.count)"
    }
}
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Services/TTS/ChunkBuffer.swift
git commit -m "feat: add ChunkBuffer actor for 1-sentence lookahead

Provides thread-safe storage for pre-synthesized audio chunks with:
- Atomic takeChunks() operation (removes as it retrieves)
- Completion tracking to prevent partial chunk retrieval
- Buffer size limits (2MB) to prevent memory issues
- Comprehensive logging for debugging

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Add BufferingChunkDelegate

**File:** `Listen2/Listen2/Listen2/Services/TTSService.swift` (add before ChunkStreamDelegate)

```swift
// MARK: - Buffering Chunk Delegate

/// Delegate that receives audio chunks and stores them in ChunkBuffer
/// Used for pre-synthesis of upcoming sentences
private class BufferingChunkDelegate: SynthesisStreamDelegate {
    private let buffer: ChunkBuffer
    private let sentenceIndex: Int

    init(buffer: ChunkBuffer, sentenceIndex: Int) {
        self.buffer = buffer
        self.sentenceIndex = sentenceIndex
    }

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        // Forward chunk to buffer asynchronously
        Task {
            await buffer.addChunk(chunk, forSentence: sentenceIndex)
        }
        return true // Continue synthesis
    }
}
```

**Also add ChunkBuffer property to TTSService:**

```swift
// Add after synthesisQueue property (around line 37):
private var chunkBuffer: ChunkBuffer?
```

**Initialize in init():**

```swift
// Add after audioPlayer initialization (around line 78):
self.chunkBuffer = ChunkBuffer()
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: add BufferingChunkDelegate for pre-synthesis

Forwards synthesis chunks to ChunkBuffer for upcoming sentences.
Uses nonisolated to prevent race conditions with async buffer access.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Modify speakParagraph for 1-Sentence Lookahead

**File:** `Listen2/Listen2/Listen2/Services/TTSService.swift`

Replace the sentence loop in `speakParagraph` (lines 576-591) with:

```swift
// Track pre-synthesis tasks for cancellation
var preSynthesisTask: Task<Void, Never>?

// Start pre-synthesis for first sentence (N+1 when N=0)
if sentences.count > 1 {
    preSynthesisTask = startPreSynthesis(
        sentence: sentences[1].text,
        index: 1,
        buffer: chunkBuffer
    )
}

// Play each sentence with lookahead buffering
for (sentenceIndex, chunk) in sentences.enumerated() {
    // Check cancellation
    guard !Task.isCancelled else {
        print("[TTSService] 🛑 Task cancelled - breaking loop")
        preSynthesisTask?.cancel()
        await chunkBuffer?.clearAll()
        throw CancellationError()
    }

    print("[TTSService] 🎤 Starting sentence \(sentenceIndex+1)/\(sentences.count)")

    // Try to use buffered chunks if available
    if let buffer = chunkBuffer,
       let bufferedChunks = await buffer.takeChunks(forSentence: sentenceIndex),
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
        preSynthesisTask?.cancel() // Cancel previous task if still running
        preSynthesisTask = startPreSynthesis(
            sentence: sentences[nextIndex].text,
            index: nextIndex,
            buffer: chunkBuffer
        )
    }
}

// Cleanup
preSynthesisTask?.cancel()
await chunkBuffer?.clearAll()
```

**Add helper methods after playSentenceWithChunks:**

```swift
/// Start pre-synthesis for a sentence in the background
private func startPreSynthesis(sentence: String, index: Int, buffer: ChunkBuffer?) -> Task<Void, Never> {
    return Task {
        guard let buffer = buffer, let queue = await self.synthesisQueue else {
            return
        }

        print("[TTSService] 🔮 Pre-synthesizing sentence \(index): '\(sentence.prefix(50))...'")

        do {
            let delegate = BufferingChunkDelegate(buffer: buffer, sentenceIndex: index)
            _ = try await queue.streamSentence(sentence, delegate: delegate)
            await buffer.markComplete(forSentence: index)
            print("[TTSService] ✅ Pre-synthesis complete for sentence \(index)")
        } catch {
            print("[TTSService] ⚠️ Pre-synthesis failed for sentence \(index): \(error)")
        }
    }
}

/// Play buffered chunks that were pre-synthesized
private func playBufferedChunks(_ chunks: [Data]) async throws {
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
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: implement 1-sentence lookahead buffering

While sentence N plays, sentence N+1 pre-synthesizes into buffer.
When N finishes, N+1 chunks are atomically retrieved and played.
Falls back to on-demand synthesis on buffer miss.

Eliminates ~100-200ms gaps between sentences.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Integrate Buffer Clearing

**File:** `Listen2/Listen2/Listen2/Services/TTSService.swift`

**4a. Speed change (line 282):**

```swift
// After setSpeed, before stop:
await synthesisQueue?.setSpeed(newRate)
await chunkBuffer?.clearAll()  // ← ADD THIS
await audioPlayer.stop()
```

**4b. Voice change (line 362):**

```swift
// After creating new synthesis queue, before clearing:
self.synthesisQueue = SynthesisQueue(provider: piperProvider)
await chunkBuffer?.clearAll()  // ← ADD THIS
await synthesisQueue?.setContent(/* ... */)
```

**4c. Stop (line 474):**

```swift
// Add to stopAudioOnly():
await synthesisQueue?.clearAll()
await chunkBuffer?.clearAll()  // ← ADD THIS
```

**Commit:**
```bash
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "fix: clear chunk buffer on speed/voice change and stop

Buffer contents are speed/voice-dependent, must be cleared on changes.
Prevents playing cached audio at wrong speed or with wrong voice.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Add ChunkBuffer to Xcode Project

Open Xcode and add the new file (or it will auto-discover via PBXFileSystemSynchronizedRootGroup).

Build and verify no errors.

---

## Testing Checklist

- [ ] **Gap eliminated:** Play multi-sentence paragraph, listen for smooth transitions
- [ ] **Buffer hit rate:** Check logs for "Playing from buffer" vs "Buffer miss"
- [ ] **Speed change:** Change speed mid-paragraph, verify buffer clears and new speed works
- [ ] **Voice change:** Change voice, verify buffer clears
- [ ] **Stop mid-paragraph:** Stop during playback, verify no crashes
- [ ] **Skip forward:** Skip to next paragraph, verify pre-synthesis cancels
- [ ] **Memory usage:** Check Xcode memory gauge stays low
- [ ] **Very short sentences:** Test 1-2 word sentences work smoothly
- [ ] **Very long sentences:** Test 100+ word sentences don't blow up buffer

---

## Success Criteria

- ✅ No perceivable gap between sentences
- ✅ Buffer hit rate > 90% (most sentences play from buffer)
- ✅ Memory stays < 50MB during playback
- ✅ All edge cases handled gracefully
- ✅ Clean logs showing pre-synthesis working

---

## Rollback Plan

If this causes issues:

```bash
git log --oneline -5  # Find commits
git revert HEAD~4..HEAD  # Revert all buffer commits
```

The old direct-streaming code will still work.