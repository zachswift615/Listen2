# Plan: Eliminate Sentence Gaps with Chunk Buffering

## Goal
Remove the small gaps between sentences by pre-synthesizing upcoming sentences and buffering their chunks while the current sentence plays.

## Architecture

**Two-sentence lookahead buffer:**
- While sentence N plays, sentences N+1 and N+2 are pre-synthesizing into a buffer
- When N finishes, N+1's chunks are immediately available to flush to the player
- This creates a safety margin if synthesis is occasionally slower than expected

## Components to Create

### 1. ChunkBuffer Actor
Thread-safe storage for buffered chunks from multiple sentences.

```swift
actor ChunkBuffer {
    private var buffers: [Int: [Data]] = [:]  // sentenceIndex → chunks

    func addChunk(_ chunk: Data, forSentence index: Int)
    func getChunks(forSentence index: Int) -> [Data]
    func hasChunks(forSentence index: Int) -> Bool
    func clear(forSentence index: Int)
    func clearAll()
}
```

### 2. BufferingChunkDelegate
Forwards chunks to ChunkBuffer instead of directly to StreamingAudioPlayer.

```swift
class BufferingChunkDelegate: SynthesisStreamDelegate {
    private let buffer: ChunkBuffer
    private let sentenceIndex: Int

    func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        Task {
            await buffer.addChunk(chunk, forSentence: sentenceIndex)
        }
        return true
    }
}
```

### 3. Modified speakParagraph Flow

```
1. Start pre-synthesis tasks for first 2 sentences (N=0, N=1)
2. For each sentence N:
   a. If buffer has chunks for N:
      - Start streaming session
      - Flush all buffered chunks to player
      - Call finishScheduling()
   b. Else (buffer miss):
      - Synthesize on-demand with direct delegate
   c. Start pre-synthesis for N+2 (if exists)
   d. Wait for playback to complete
3. Cleanup: cancel pending synthesis tasks, clear buffer
```

## Key Benefits

- **Zero-gap playback:** Next sentence's chunks are pre-buffered and ready
- **Memory safe:** Only 2 sentences buffered at a time (~400KB typical)
- **Robust:** 2-sentence buffer handles synthesis speed variations
- **Streaming preserved:** Still using chunk-level streaming during playback

## Edge Cases

1. **Very fast user skip:** Cancel pending synthesis tasks, clear buffer
2. **Speed change:** Clear buffer (audio is speed-dependent)
3. **Synthesis failure:** Fall back to on-demand synthesis
4. **Last sentence:** Don't start pre-synthesis for non-existent sentences

## Files to Modify

1. Create `ChunkBuffer.swift` (~60 lines)
2. Modify `TTSService.swift` speakParagraph method (~80 lines changed)
3. Add BufferingChunkDelegate class to TTSService.swift (~20 lines)

## Estimated Complexity

- **Lines added:** ~160
- **Complexity:** Medium (actor synchronization, task lifecycle management)
- **Risk:** Low (fallback to on-demand synthesis if buffer empty)
