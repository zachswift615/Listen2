# Word-Level Alignment Architecture Flow

This document provides visual diagrams of the word-level alignment feature architecture for Listen2's Piper TTS integration.

---

## System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            USER INTERFACE                                 │
│  • ReaderView displays PDF with word highlighting                        │
│  • ReadingProgress.wordRange determines highlighted text                 │
│  • 60 FPS updates for smooth visual feedback                             │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             │ ReadingProgress updates
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                            TTSService                                     │
│  • Main orchestrator (@MainActor)                                        │
│  • Manages playback state and coordination                               │
│  • Runs 60 FPS timer for word highlighting                               │
│                                                                            │
│  Key responsibilities:                                                    │
│  ✓ Initialize alignment service on app launch                           │
│  ✓ Start/stop playback with word highlighting                           │
│  ✓ Update currentProgress based on audio time                           │
│  ✓ Handle voice/speed changes (triggers re-alignment)                   │
└────┬────────────────────────┬────────────────────────┬───────────────────┘
     │                        │                        │
     │ Manages                │ Coordinates            │ Uses
     │                        │                        │
     ▼                        ▼                        ▼
┌──────────────┐    ┌──────────────────┐    ┌───────────────────────┐
│ AudioPlayer  │    │ SynthesisQueue   │    │ WordAlignmentService  │
│ (@MainActor) │    │ (@MainActor)     │    │ (Actor)               │
└──────────────┘    └──────────────────┘    └───────────────────────┘
```

---

## Component Interaction Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                         Component Interactions                          │
└────────────────────────────────────────────────────────────────────────┘

    TTSService                SynthesisQueue           WordAlignmentService
        │                           │                           │
        │ setContent()              │                           │
        ├──────────────────────────>│                           │
        │                           │ initialize()              │
        │                           ├──────────────────────────>│
        │                           │                           │
        │ getAudio(index: 0)        │                           │
        ├──────────────────────────>│                           │
        │                           │                           │
        │                           │ synthesize()              │
        │                           ├───────────────┐           │
        │                           │               │           │
        │                           │<──────────────┘           │
        │                           │ WAV data                  │
        │                           │                           │
        │                           │ align()                   │
        │                           ├──────────────────────────>│
        │                           │                           │
        │                           │                  ┌────────┴────────┐
        │                           │                  │ Load audio      │
        │                           │                  │ Run ASR         │
        │                           │                  │ Map tokens      │
        │                           │                  └────────┬────────┘
        │                           │                           │
        │                           │<──────────────────────────┤
        │                           │ AlignmentResult           │
        │                           │                           │
        │<──────────────────────────┤                           │
        │ Audio + Alignment         │                           │
        │                           │                           │
        │ play()                    │                           │
        ├──────────┐                │                           │
        │          │                │                           │
        │          │ Timer (60 FPS) │                           │
        │          │                │                           │
        │          │ wordTiming(at: currentTime)                │
        │<─────────┘                │                           │
        │                           │                           │
        │ Update UI                 │                           │
        └───────────────────────────┴───────────────────────────┘
```

---

## Data Flow: VoxPDF → TTS → ASR → Highlighting

```
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 1: Document Import                                                 │
└─────────────────────────────────────────────────────────────────────────┘

    VoxPDF Document
         │
         │ Extract text + word positions
         │
         ▼
    DocumentWordMap
         │
         │ Contains:
         │ • Paragraph text
         │ • WordPosition[] per paragraph
         │   - text: "Hello"
         │   - characterOffset: 0
         │   - length: 5
         │   - paragraphIndex: 0
         │
         └──> Stored in ReaderDocument


┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 2: User Starts Reading (Paragraph 0)                              │
└─────────────────────────────────────────────────────────────────────────┘

    TTSService.startReading(
        paragraphs: ["Hello world", ...],
        wordMap: DocumentWordMap,
        documentID: UUID
    )
         │
         ▼
    SynthesisQueue.setContent()
         │
         ├─> Cache current content
         ├─> Store wordMap reference
         └─> Store documentID for caching


┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 3: TTS Synthesis                                                   │
└─────────────────────────────────────────────────────────────────────────┘

    SynthesisQueue.getAudio(index: 0)
         │
         ▼
    PiperTTSProvider.synthesize("Hello world", speed: 1.0)
         │
         │ Piper TTS engine
         │
         ▼
    WAV Audio Data (16kHz mono)
         │
         ├─> Cache in memory
         └─> Write to temp file for ASR


┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 4: ASR Alignment                                                   │
└─────────────────────────────────────────────────────────────────────────┘

    SynthesisQueue.performAlignment()
         │
         │ Check disk cache first
         │
         ▼
    AlignmentCache.load(documentID, paragraph: 0)
         │
         ├─> Cache HIT: Return AlignmentResult ✓
         │
         └─> Cache MISS: Continue to ASR
              │
              ▼
         WordAlignmentService.align(
             audioURL: temp.wav,
             text: "Hello world",
             wordMap: DocumentWordMap,
             paragraphIndex: 0
         )
              │
              ├─> Load WAV file
              ├─> Resample to 16kHz if needed
              ├─> Feed to sherpa-onnx ASR
              ├─> Get tokens + timestamps
              │
              ▼
         ASR Output:
         ┌────────────────────────────────────┐
         │ Token 0: "Hello"                   │
         │   timestamp: 0.0s                  │
         │   duration: 0.5s                   │
         │                                    │
         │ Token 1: "world"                   │
         │   timestamp: 0.5s                  │
         │   duration: 0.5s                   │
         └────────────────────────────────────┘
              │
              ▼
         Token-to-Word Mapping (DTW)
              │
              │ Normalize: "hello" ↔ "Hello"
              │ Compute edit distances
              │ Find optimal alignment path
              │
              ▼
         AlignmentResult
         ┌────────────────────────────────────┐
         │ paragraphIndex: 0                  │
         │ totalDuration: 1.0s                │
         │                                    │
         │ wordTimings: [                     │
         │   WordTiming(                      │
         │     wordIndex: 0,                  │
         │     startTime: 0.0,                │
         │     duration: 0.5,                 │
         │     text: "Hello",                 │
         │     stringRange: 0..<5             │
         │   ),                               │
         │   WordTiming(                      │
         │     wordIndex: 1,                  │
         │     startTime: 0.5,                │
         │     duration: 0.5,                 │
         │     text: "world",                 │
         │     stringRange: 6..<11            │
         │   )                                │
         │ ]                                  │
         └────────────────────────────────────┘
              │
              ├─> Save to disk cache
              └─> Save to memory cache


┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 5: Playback with Highlighting                                      │
└─────────────────────────────────────────────────────────────────────────┘

    TTSService.playAudio(data)
         │
         ├─> Get alignment from SynthesisQueue
         ├─> Start AudioPlayer
         └─> Start 60 FPS highlight timer
              │
              │ Timer fires every ~16ms
              │
              ▼
         updateHighlightFromTime()
              │
              │ Get currentTime from AudioPlayer
              │
              ▼
         AlignmentResult.wordTiming(at: 0.25s)
              │
              │ Binary search in wordTimings array
              │
              ▼
         Found: WordTiming(wordIndex: 0, startTime: 0.0, duration: 0.5)
              │
              ├─> Get stringRange: 0..<5
              └─> Update ReadingProgress
                   │
                   ▼
              UI highlights "Hello" in yellow
```

---

## Cache Strategy Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Multi-Level Caching                              │
└─────────────────────────────────────────────────────────────────────────┘

User requests paragraph 0
         │
         ▼
┌─────────────────────────┐
│ Level 1: Memory Cache   │  ◄── Fastest (hash lookup)
│ (SynthesisQueue)        │      <10ms access time
└────────┬────────────────┘
         │
         │ Cache MISS
         │
         ▼
┌─────────────────────────┐
│ Level 2: Disk Cache     │  ◄── Fast (file I/O)
│ (AlignmentCache)        │      ~50-100ms access time
└────────┬────────────────┘
         │
         │ Cache MISS
         │
         ▼
┌─────────────────────────┐
│ Level 3: ASR Alignment  │  ◄── Slow (computation)
│ (WordAlignmentService)  │      1-2 seconds
└────────┬────────────────┘
         │
         │ Save to all caches
         │
         ▼
    AlignmentResult
         │
         ├──> Memory cache (for current session)
         └──> Disk cache (for future sessions)


Cache Invalidation Events:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Voice Changed      →  Clear all caches (new speaker)              │
│  Speed Changed      →  Clear all caches (new duration)             │
│  Text Edited        →  Clear paragraph cache (content changed)     │
│  Document Deleted   →  Clear document directory (cleanup)          │
│  App Settings       →  User can manually clear cache               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Background Prefetching Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Prefetch Strategy (Lookahead = 3)                   │
└─────────────────────────────────────────────────────────────────────────┘

User playing paragraph 0
         │
         ▼
    getAudio(index: 0) returns
         │
         │ Trigger prefetch
         │
         ▼
    preSynthesizeAhead(from: 0)
         │
         ├─────────────────┬─────────────────┬─────────────────┐
         │                 │                 │                 │
         ▼                 ▼                 ▼                 ▼
    Task {            Task {            Task {            (lookahead = 3)
      Paragraph 1       Paragraph 2       Paragraph 3
         │                 │                 │
         │                 │                 │
    Synthesize        Synthesize        Synthesize
         │                 │                 │
         │                 │                 │
    Align             Align             Align
         │                 │                 │
         │                 │                 │
    Cache             Cache             Cache
    }                 }                 }
         │                 │                 │
         └─────────────────┴─────────────────┘
                           │
                           │ All tasks run in parallel
                           │ Non-blocking (async/await)
                           │
                           ▼
    Paragraphs 1-3 ready in cache

User navigates to paragraph 1
         │
         ▼
    getAudio(index: 1)
         │
         │ Cache HIT (instant!)
         │
         ▼
    Return cached audio + alignment
         │
         │ Trigger new prefetch
         │
         ▼
    preSynthesizeAhead(from: 1)
         │
         ├─> Paragraph 2: Already cached ✓
         ├─> Paragraph 3: Already cached ✓
         └─> Paragraph 4: Start synthesis (NEW)

Result: Smooth, uninterrupted playback
```

---

## Token-to-Word Mapping Algorithm

```
┌─────────────────────────────────────────────────────────────────────────┐
│              Dynamic Time Warping (DTW) Alignment                        │
└─────────────────────────────────────────────────────────────────────────┘

Input:
  ASR tokens:   ["hello", "world"]
  VoxPDF words: ["Hello", "world"]

Step 1: Normalize both sequences
  ASR (normalized):   ["hello", "world"]
  Words (normalized): ["hello", "world"]

Step 2: Compute DTW cost matrix

         ε      "hello"   "world"
    ┌─────────────────────────────┐
  ε │  0         ∞         ∞       │
    │                              │
"hello" │  ∞      0         2       │  ← Edit distances
    │                              │
"world" │  ∞      2         2       │
    └─────────────────────────────┘

Step 3: Fill DTW table (allows many-to-one mappings)

cost[i][j] = editDistance(token[i], word[j]) +
             min(cost[i-1][j-1],  // diagonal: align
                 cost[i-1][j],    // vertical: multi-token word
                 cost[i][j-1])    // horizontal: skip word

Step 4: Backtrack to find alignment path

Path: (1,1) → (0,0)
  Token 0 "hello" → Word 0 "Hello"
  Token 1 "world" → Word 1 "world"

Step 5: Generate WordTiming array

  WordTiming(
    wordIndex: 0,
    startTime: timestamps[0] = 0.0,
    duration: durations[0] = 0.5,
    text: "Hello",
    stringRange: 0..<5
  )

  WordTiming(
    wordIndex: 1,
    startTime: timestamps[1] = 0.5,
    duration: durations[1] = 0.5,
    text: "world",
    stringRange: 6..<11
  )


Example: Multi-token word alignment

Input:
  ASR tokens:   ["don", "'", "t", "worry"]
  VoxPDF words: ["don't", "worry"]

DTW alignment:
  Tokens [0,1,2] → Word 0 "don't"
    startTime: min(timestamps[0], timestamps[1], timestamps[2]) = 0.0
    endTime: max(timestamps[2] + durations[2]) = 0.6
    duration: 0.6

  Token [3] → Word 1 "worry"
    startTime: timestamps[3] = 0.6
    duration: durations[3] = 0.4

Result: Accurate timing even with tokenization mismatch
```

---

## Error Handling and Graceful Degradation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Error Handling Flow                               │
└─────────────────────────────────────────────────────────────────────────┘

    App Launch
         │
         ▼
    Initialize AlignmentService
         │
         ├─> SUCCESS: Ready for alignment ✓
         │
         └─> FAILURE: Model not found
              │
              └─> Log error
                  Continue without alignment
                  Fallback: No word highlighting


    Playback Starts
         │
         ▼
    Synthesize Audio
         │
         ├─> SUCCESS: WAV data ✓
         │    │
         │    ▼
         │ Perform Alignment
         │    │
         │    ├─> SUCCESS: AlignmentResult ✓
         │    │    │
         │    │    └─> Enable word highlighting
         │    │
         │    └─> FAILURE: ASR error
         │         │
         │         └─> Log error
         │             Play audio without highlighting
         │
         └─> FAILURE: Synthesis error
              │
              └─> Fallback to AVSpeech
                  Use AVSpeech word ranges


    Cache Operations
         │
         ▼
    Save Alignment
         │
         ├─> SUCCESS: Saved to disk ✓
         │
         └─> FAILURE: Disk write error
              │
              └─> Log error
                  Continue (alignment still in memory)


    Result: Playback NEVER fails due to alignment
            User may not notice alignment failures
            Graceful degradation to no highlighting
```

---

## Performance Optimization Points

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Performance Critical Paths                           │
└─────────────────────────────────────────────────────────────────────────┘

1. Word Lookup (60 FPS requirement)
   ────────────────────────────────────

   BEFORE: Linear search O(n)
   for word in wordTimings {
       if time >= word.startTime && time < word.endTime {
           return word
       }
   }
   Performance: ~50μs for 100 words

   AFTER: Binary search O(log n)
   var left = 0, right = wordTimings.count - 1
   while left <= right {
       let mid = (left + right) / 2
       // ... binary search logic
   }
   Performance: <1μs for 100 words

   Impact: 50x speedup ✓


2. Edit Distance Calculation (DTW bottleneck)
   ───────────────────────────────────────────

   BEFORE: Recompute for every token-word pair
   for i in tokens {
       for j in words {
           cost = editDistance(tokens[i], words[j])  // O(m×n) each time
       }
   }
   Performance: ~100ms for 100 words

   AFTER: Memoization cache
   var cache: [String: Int] = [:]
   func getCachedEditDistance(_ s1: String, _ s2: String) -> Int {
       let key = "\(s1)|\(s2)"
       if let cached = cache[key] { return cached }
       let distance = editDistance(s1, s2)
       cache[key] = distance
       return distance
   }
   Performance: ~50ms for 100 words

   Impact: 2x speedup ✓


3. Audio Resampling (16kHz requirement)
   ──────────────────────────────────────

   Linear interpolation (current):
   for i in 0..<newLength {
       let srcIndex = Double(i) * ratio
       let fraction = srcIndex - floor(srcIndex)
       sample = lerp(samples[floor], samples[ceil], fraction)
   }
   Performance: ~20ms for 1-second audio

   Could use vDSP (not implemented):
   vDSP_vgenp(samples, stride, &ratio, output, 1, newLength, 1)
   Performance: ~5ms for 1-second audio

   Decision: Linear interpolation sufficient for quality
             Not worth added complexity


4. Background Prefetch (hide alignment latency)
   ─────────────────────────────────────────────

   WITHOUT prefetch:
   User plays paragraph → Wait 1-2s for alignment → Start playback

   WITH prefetch (lookahead = 3):
   User plays paragraph 0 → Instant playback (first paragraph)
                          → Background: Align paragraphs 1-3
   User navigates to paragraph 1 → Instant playback (already aligned)

   Impact: Eliminates perceived latency after first paragraph ✓
```

---

## Memory Management

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Memory Footprint                                 │
└─────────────────────────────────────────────────────────────────────────┘

ASR Model (Whisper-tiny INT8)
├─ tiny-encoder.int8.onnx     15 MB
├─ tiny-decoder.int8.onnx     25 MB
└─ tiny-tokens.txt             1 MB
                        Total: ~40 MB (persistent, loaded once)

Alignment Data (per paragraph)
├─ AlignmentResult struct     ~1 KB
├─ WordTiming[] array         ~100 bytes per word
└─ Example: 100-word para     ~10 KB

Memory Caches
├─ WordAlignmentService       ~50 KB (in-memory alignment cache)
├─ SynthesisQueue             ~500 KB (3 paragraphs × audio + alignment)
└─ AlignmentCache             0 KB (disk-only, no memory cache)

Total memory usage:            ~40 MB (model) + ~1 MB (caches)

Cleanup on deinit:
- WordAlignmentService.deinit() → Destroy ASR recognizer
- SynthesisQueue.clearAll()     → Clear all caches
- AlignmentCache                → No cleanup needed (actor deinit)
```

---

## Thread Safety Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Concurrency & Thread Safety                          │
└─────────────────────────────────────────────────────────────────────────┘

@MainActor Components (UI-safe, serial execution)
────────────────────────────────────────────────
├─ TTSService
├─ SynthesisQueue
├─ AudioPlayer
└─ All SwiftUI views

Actor Components (thread-safe, concurrent access)
──────────────────────────────────────────────────
├─ WordAlignmentService
│   • Isolates sherpa-onnx C API calls
│   • Prevents data races on recognizer pointer
│   • Serializes alignment operations
│
└─ AlignmentCache
    • Isolates file I/O operations
    • Prevents concurrent writes to same file
    • Atomic read/write operations


Async/Await Flow
────────────────

TTSService (@MainActor)
    │
    │ await
    ▼
SynthesisQueue (@MainActor)
    │
    │ await  (crosses actor boundary)
    ▼
WordAlignmentService (Actor)
    │
    │ Alignment happens on background thread
    │ Isolated from main thread
    │
    └─> Returns AlignmentResult
         │
         │ (crosses actor boundary back)
         ▼
SynthesisQueue (@MainActor)
    │
    │ Caches result
    │
    └─> Returns to TTSService


Data Race Prevention
────────────────────

❌ WITHOUT Actor:
Thread 1: recognizer.decode(stream)
Thread 2: recognizer.decode(stream)  // CRASH: concurrent access

✓ WITH Actor:
Thread 1: await service.align(...)  // Queued
Thread 2: await service.align(...)  // Waits for Thread 1
Result: Serial execution, no data races


Cancellation Support
────────────────────

Task.isCancelled checks in long operations:

func align(...) async throws -> AlignmentResult {
    guard !Task.isCancelled else { throw CancellationError() }

    // Long operation 1
    let samples = try await loadAudioSamples(...)

    guard !Task.isCancelled else { throw CancellationError() }

    // Long operation 2
    let result = performASR(...)

    return result
}

Impact: Responsive to speed/voice changes
        Tasks cancelled immediately, no wasted work
```

---

## End of Architecture Flow Documentation

For implementation details, see:
- Implementation summary: `docs/word-alignment-implementation-summary.md`
- Implementation plan: `docs/plans/2025-11-09-word-alignment-implementation-plan.md`
- Test suite: `Listen2Tests/Services/WordAlignmentServiceTests.swift`
