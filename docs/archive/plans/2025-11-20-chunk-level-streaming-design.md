# Chunk-Level Audio Streaming Design

**Date:** 2025-11-20
**Status:** Approved for implementation
**Goal:** Replace sentence-level caching with true audio chunk streaming from sherpa-onnx

## Problem Statement

Current implementation buffers complete sentences before playback:
- High memory usage (~100-200MB for sentence cache)
- Latency from waiting for complete sentence synthesis
- Complex producer-consumer caching logic (~600 lines)
- sherpa-onnx streaming API available but audio chunks discarded

## Goals

1. **Lower latency:** Start playback as first chunks arrive
2. **Smoother playback:** Continuous audio feed to player
3. **Better memory efficiency:** Process and release chunks immediately
4. **Simpler architecture:** Remove caching complexity

## Design

### Architecture Overview

**Current (sentence-level caching):**
```
SynthesisQueue (producer-consumer)
  → Pre-synthesize sentences → sentenceCache
  → TTSService requests complete sentence
  → AVAudioPlayer plays
```

**New (chunk-level streaming):**
```
TTSService requests sentence
  → synthesizeWithStreaming()
  → chunks flow via callback
  → schedule on AVAudioPlayerNode immediately
```

### Data Flow

1. **Playback initiation:** `TTSService.startReading(paragraph)`
2. **Sentence splitting:** Use existing `SentenceSplitter` to break paragraph
3. **Just-in-time synthesis:** For each sentence:
   - Call `provider.synthesizeWithStreaming(sentence, delegate: self)`
   - sherpa-onnx invokes `didReceiveAudioChunk()` every ~50-200ms
   - Convert chunk (`Data`) to `AVAudioPCMBuffer`
   - Schedule buffer immediately with `AVAudioPlayerNode.scheduleBuffer()`
4. **Sequential sentences:** Wait for current sentence to complete before starting next

### Component Changes

| Component | Change |
|-----------|--------|
| **SynthesisQueue.swift** | Delete or reduce to minimal sentence splitter |
| **TTSService.swift** | Add AVAudioEngine chunk scheduling logic |
| **PiperTTSProvider.swift** | No changes (already has streaming) |
| **SherpaOnnx.swift** | No changes (streaming callback exists) |

### Word Highlighting

**Phase 1:** Disable highlighting temporarily
- Return `nil` or empty timeline from streaming methods
- Focus on getting audio streaming stable first

**Phase 2:** (Future) Revisit highlighting approaches
- Current phoneme duration scaling approach has issues (skips words, gets stuck)
- Will brainstorm more bulletproof approaches after streaming works

### Error Handling

| Scenario | Strategy |
|----------|----------|
| Synthesis fails mid-sentence | Finish current chunk, log error, skip to next sentence |
| Synthesis slower than playback | Audio gaps expected (direct passthrough). Measure in testing. Add buffer if needed. |
| User skips during synthesis | Cancel task, stop scheduling chunks, start fresh at new position |
| Speed change mid-playback | Cancel synthesis, clear queued buffers, restart with new speed |

### Memory Management

- **No caching:** Chunks scheduled then released
- **Expected usage:** ~10-20MB (vs current ~100-200MB)
- **No pre-synthesis:** No lookahead, no producer-consumer overhead

### State Tracking

**Keep:**
- Current paragraph index
- Current sentence index
- Current synthesis task (for cancellation)

**Remove:**
- sentenceCache
- synthesizingSentences
- producer-consumer state (isProcessingSentences, currentSentenceIndex, etc.)
- Pre-synthesis progress tracking

## Implementation Strategy

### Phase 1: Direct Passthrough (Start here)
- Just-in-time synthesis only
- No buffering, no lookahead
- Test for acceptability

### Phase 2: If gaps are unacceptable
- Add minimal chunk buffer (3-5 chunks ~100-200ms)
- Or reintroduce lookahead synthesis

### Phase 3: After streaming stable
- Revisit word highlighting with new approach
- Consider alternatives to phoneme duration scaling

## Success Criteria

1. Audio playback starts within 100-200ms of sentence request
2. No gaps within sentences (or acceptable gaps < 50ms)
3. Memory usage reduced to < 50MB during playback
4. Clean cancellation on skip/speed change
5. Code reduction: Remove ~400-500 lines of caching logic

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Synthesis slower than playback | Measure in testing. Add buffer or lookahead if needed. |
| Gaps between sentences | Expected initially. Can add sentence boundary buffering. |
| Loss of highlighting | Temporary. Will revisit with better approach. |
| AVAudioEngine complexity | Use existing examples, test thoroughly. |

## Testing Plan

1. Test single sentence playback with streaming
2. Test paragraph with multiple sentences
3. Test skip forward/backward during streaming
4. Test speed changes during playback
5. Measure latency to first audio
6. Measure memory usage vs old implementation
7. Listen for gaps/stutters subjectively

## Rollback Plan

Current implementation is committed to git. If chunk-level streaming is unacceptable:
- `git revert` to previous commit
- Or keep both implementations with feature flag (decide later)

## References

- sherpa-onnx streaming API: `SherpaOnnxOfflineTtsGenerateWithProgressCallbackWithArg`
- Current streaming callback: `SynthesisQueue.swift:992` (currently only updates progress)
- AVAudioEngine scheduling: Apple's AVAudioEngine documentation
