# Word-Level Alignment for Piper TTS Implementation Plan

## Goal
Enable accurate word-level highlighting during Piper TTS playback by using sherpa-onnx ASR to perform forced alignment on synthesized audio.

## Architecture Overview

```
Text (paragraph)
  ↓
Piper TTS Synthesis → Audio file (.wav)
  ↓
sherpa-onnx ASR (Offline Recognizer) → Token timestamps + durations
  ↓
Map tokens → VoxPDF words → String.Index ranges
  ↓
Cache alignment data with audio
  ↓
During playback: audioPlayer.currentTime → highlight current word
```

## Phase 1: ASR Model Selection & Integration

### 1.1 Choose ASR Model
**Recommended: Whisper-tiny or Zipformer-tiny**
- **Whisper-tiny**: ~40MB, multilingual, good accuracy
  - Model: `sherpa-onnx-whisper-tiny.en` or `sherpa-onnx-whisper-tiny`
  - Source: https://github.com/k2-fsa/sherpa-onnx/releases
- **Zipformer-tiny**: ~30MB, English-only, faster
  - Model: `sherpa-onnx-zipformer-en-2023-06-26`
  - Source: https://github.com/k2-fsa/sherpa-onnx/releases

**Decision Criteria:**
- Use Whisper-tiny if multilingual support needed
- Use Zipformer-tiny for faster alignment (English-only books)
- Both support character/word-level timestamps

### 1.2 Download & Bundle Model
```bash
# Download model
cd ~/Downloads
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-en-2023-06-26.tar.bz2
tar xvf sherpa-onnx-zipformer-en-2023-06-26.tar.bz2

# Add to project
# Option A: Bundle with app (increases app size by ~30-40MB)
cp -r sherpa-onnx-zipformer-en-2023-06-26 Listen2/Listen2/Resources/ASRModels/

# Option B: Download on first use (better for app size)
# Store models in app's Documents directory
```

## Phase 2: Create Alignment Service

### 2.1 New Files
```
Listen2/Services/TTS/
├── WordAlignmentService.swift       (NEW - main alignment logic)
├── AlignmentCache.swift              (NEW - caching aligned data)
└── Models/
    ├── AlignmentResult.swift         (NEW - timestamp data)
    └── CachedAlignment.swift         (NEW - cached alignment model)
```

### 2.2 WordAlignmentService Interface
```swift
final class WordAlignmentService {
    // Initialize ASR recognizer
    func initialize(modelPath: String) async throws

    // Align audio to text, return word timestamps
    func align(
        audioURL: URL,
        text: String,
        wordMap: DocumentWordMap,
        paragraphIndex: Int
    ) async throws -> AlignmentResult

    // Check if alignment exists in cache
    func getCachedAlignment(for audioURL: URL) -> AlignmentResult?
}

struct AlignmentResult: Codable {
    struct WordTiming: Codable {
        let wordIndex: Int              // Index in paragraph's word array
        let startTime: TimeInterval     // In seconds
        let duration: TimeInterval      // In seconds
        let text: String                // Word text (for validation)
        let stringRange: Range<String.Index>  // For highlighting
    }

    let paragraphIndex: Int
    let totalDuration: TimeInterval
    let wordTimings: [WordTiming]
}
```

### 2.3 Alignment Algorithm
```swift
func align(audioURL: URL, text: String, wordMap: DocumentWordMap, paragraphIndex: Int) async throws -> AlignmentResult {
    // 1. Load audio file
    let audioData = try Data(contentsOf: audioURL)

    // 2. Create offline stream
    let stream = SherpaOnnxCreateOfflineStream(recognizer)
    defer { SherpaOnnxDestroyOfflineStream(stream) }

    // 3. Feed audio samples
    SherpaOnnxAcceptWaveformOffline(stream, sampleRate, samples, numSamples)

    // 4. Decode
    SherpaOnnxDecodeOfflineStream(recognizer, stream)

    // 5. Get result with timestamps
    let result = SherpaOnnxGetOfflineStreamResult(stream)
    defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

    // 6. Extract timestamps and durations
    guard let timestamps = result.pointee.timestamps,
          let durations = result.pointee.durations else {
        throw AlignmentError.noTimestamps
    }

    let tokenCount = Int(result.pointee.count)

    // 7. Map ASR tokens to VoxPDF words
    // This is the tricky part - need to handle:
    // - ASR may split/merge words differently
    // - Need fuzzy matching (ASR: "don't" vs VoxPDF: "don", "'", "t")
    // - Use edit distance / dynamic programming

    let wordTimings = mapTokensToWords(
        asrTokens: result.pointee.tokens_arr,
        timestamps: timestamps,
        durations: durations,
        tokenCount: tokenCount,
        voxPDFWords: wordMap.wordsInParagraph(paragraphIndex),
        paragraphText: text
    )

    return AlignmentResult(
        paragraphIndex: paragraphIndex,
        totalDuration: wordTimings.last?.endTime ?? 0,
        wordTimings: wordTimings
    )
}
```

## Phase 3: Token-to-Word Mapping

### 3.1 Challenge
ASR tokens ≠ VoxPDF words due to:
- Different tokenization (ASR may use BPE, subword units)
- Punctuation handling differences
- Contractions ("don't" vs "do" + "n't")

### 3.2 Solution: Dynamic Time Warping (DTW) with Edit Distance
```swift
func mapTokensToWords(
    asrTokens: UnsafePointer<UnsafePointer<CChar>?>,
    timestamps: UnsafePointer<Float>,
    durations: UnsafePointer<Float>,
    tokenCount: Int,
    voxPDFWords: [WordPosition],
    paragraphText: String
) -> [AlignmentResult.WordTiming] {

    // 1. Convert ASR tokens to strings
    var asrTokenStrings: [String] = []
    for i in 0..<tokenCount {
        if let tokenPtr = asrTokens[i] {
            asrTokenStrings.append(String(cString: tokenPtr))
        }
    }

    // 2. Normalize both sequences (lowercase, remove punctuation)
    let normalizedASR = normalize(asrTokenStrings)
    let normalizedWords = voxPDFWords.map { normalize($0.text) }

    // 3. Use DTW to find best alignment
    let alignment = alignSequences(normalizedASR, normalizedWords)

    // 4. Build WordTiming array
    var wordTimings: [AlignmentResult.WordTiming] = []

    for (wordIndex, tokenIndices) in alignment {
        let voxWord = voxPDFWords[wordIndex]

        // Word span across multiple ASR tokens - use first token's start, last token's end
        let startTime = Double(timestamps[tokenIndices.first!])
        let endTime = Double(timestamps[tokenIndices.last!] + durations[tokenIndices.last!])

        // Get String.Index range from VoxPDF word position
        let stringRange = getStringRange(
            for: voxWord,
            in: paragraphText
        )

        wordTimings.append(.init(
            wordIndex: wordIndex,
            startTime: startTime,
            duration: endTime - startTime,
            text: voxWord.text,
            stringRange: stringRange
        ))
    }

    return wordTimings
}
```

## Phase 4: Caching Strategy

### 4.1 Cache Structure
```swift
// Store in app's Caches directory
// Structure: Caches/WordAlignments/{documentID}/{paragraphIndex}.json

class AlignmentCache {
    func save(_ alignment: AlignmentResult, for documentID: UUID, paragraph: Int)
    func load(for documentID: UUID, paragraph: Int) -> AlignmentResult?
    func clear(for documentID: UUID)  // When document deleted
}
```

### 4.2 When to Align
```
- First playback of paragraph: Align + cache
- Subsequent playback: Load from cache
- Voice change: Re-align (different timing)
- Text change: Re-align (invalidate cache)
```

## Phase 5: Integration with SynthesisQueue

### 5.1 Modify SynthesisQueue.synthesize()
```swift
func synthesize(text: String, for paragraphIndex: Int) async throws -> URL {
    // 1. Generate audio with Piper (existing code)
    let audioURL = try await piperProvider.synthesize(text)

    // 2. Perform alignment (NEW)
    if let wordMap = currentWordMap {
        let alignment = try await wordAlignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex
        )

        // 3. Cache alignment
        alignmentCache.save(alignment, for: documentID, paragraph: paragraphIndex)

        // 4. Return both audio + alignment
        return (audioURL, alignment)
    }

    return (audioURL, nil)
}
```

### 5.2 Store Alignment with Audio
```swift
// Modify SynthesisQueue to track alignments
private var alignments: [Int: AlignmentResult] = [:]  // paragraphIndex -> alignment

func getAlignment(for paragraphIndex: Int) -> AlignmentResult? {
    return alignments[paragraphIndex]
}
```

## Phase 6: Playback with Word Highlighting

### 6.1 Modify AudioPlayer
```swift
class AudioPlayer: ObservableObject {
    @Published var currentTime: TimeInterval = 0

    private var displayLink: CADisplayLink?

    func play(url: URL, alignment: AlignmentResult?) {
        // Start display link for smooth updates (60 FPS)
        displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
        displayLink?.add(to: .main, forMode: .common)

        // Play audio
        audioEngine.play(url)
    }

    @objc private func updateTime() {
        currentTime = audioEngine.currentTime
    }
}
```

### 6.2 Modify TTSService
```swift
// Add timer-based highlighting
private var highlightTimer: Timer?
private var currentAlignment: AlignmentResult?

func speakParagraph(at index: Int) {
    // Get alignment from synthesis queue
    currentAlignment = synthesisQueue?.getAlignment(for: index)

    // Start playback
    audioPlayer.play(url: audioURL, alignment: currentAlignment)

    // Start highlight timer
    startHighlightTimer()
}

private func startHighlightTimer() {
    highlightTimer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { [weak self] _ in
        self?.updateHighlightFromTime()
    }
}

private func updateHighlightFromTime() {
    guard let alignment = currentAlignment else { return }

    let currentTime = audioPlayer.currentTime

    // Binary search for current word
    if let wordTiming = alignment.wordTimings.first(where: {
        currentTime >= $0.startTime && currentTime < $0.startTime + $0.duration
    }) {
        currentProgress = ReadingProgress(
            paragraphIndex: currentProgress.paragraphIndex,
            wordRange: wordTiming.stringRange,
            isPlaying: true
        )
    }
}
```

## Phase 7: Performance Optimizations

### 7.1 Background Processing
- Run alignment on background queue
- Show "Preparing audio..." indicator during first alignment
- Prefetch & align next paragraph while current one plays

### 7.2 Model Loading
- Load ASR model once at app launch
- Keep in memory (40MB is acceptable)
- Alternative: Lazy load on first alignment

### 7.3 Alignment Speed
- Target: <2 seconds per paragraph
- Whisper-tiny: ~1-2 seconds for 30-second audio on iPhone
- Zipformer: ~0.5-1 seconds (faster)

## Phase 8: Testing & Validation

### 8.1 Unit Tests
```swift
- testASRModelLoading()
- testAudioAlignment()
- testTokenToWordMapping()
- testAlignmentCaching()
- testTimestampAccuracy()
```

### 8.2 Integration Tests
```swift
- testEndToEndAlignment()  // Synthesize → Align → Highlight
- testCacheHitRate()
- testAlignmentPerformance()
```

### 8.3 Manual Testing Checklist
- [ ] Word highlighting syncs accurately with audio
- [ ] No visible drift over long paragraphs
- [ ] Cache survives app restart
- [ ] Works with different voices
- [ ] Handles contractions correctly ("don't", "I'll", etc.)
- [ ] Handles punctuation correctly
- [ ] Performance acceptable (<2s alignment time)

## Estimated Timeline

### Week 1: Setup & Core Alignment
- Day 1-2: Download models, integrate ASR, basic alignment working
- Day 3-4: Token-to-word mapping algorithm
- Day 5: Caching implementation

### Week 2: Integration & Polish
- Day 6-7: SynthesisQueue integration
- Day 8-9: AudioPlayer time tracking & highlighting
- Day 10: Performance optimization & testing

### Week 3: Testing & Refinement
- Day 11-13: Comprehensive testing
- Day 14: Bug fixes & edge cases
- Day 15: Documentation & release

## Dependencies

### Required
- sherpa-onnx framework (already integrated ✅)
- ASR model files (~30-40MB)
- VoxPDF word positions (already implemented ✅)

### Optional
- Progress indicators for first-time alignment
- Settings to disable alignment (fallback to no highlighting)
- Model download UI (if not bundling model)

## Risks & Mitigations

### Risk 1: Alignment Accuracy
**Mitigation:** Use edit distance + DTW for robust token mapping

### Risk 2: Performance
**Mitigation:** Cache aggressively, prefetch next paragraph

### Risk 3: ASR Model Size
**Mitigation:** Download on first use instead of bundling

### Risk 4: Different Tokenization
**Mitigation:** Normalize text before alignment, fuzzy matching

## Future Enhancements

1. **Multiple Language Support**: Use multilingual Whisper model
2. **Phoneme-Level Alignment**: Even finer granularity
3. **Cloud Alignment**: Offload to server for faster processing
4. **Model Quantization**: Reduce model size further

## Success Metrics

- ✅ Word highlighting drift < 100ms over 5-minute paragraph
- ✅ Alignment time < 2 seconds per paragraph
- ✅ Cache hit rate > 95% on re-reads
- ✅ User satisfaction: "Highlighting feels natural"

---

**Next Steps:**
1. Choose ASR model (Whisper-tiny vs Zipformer)
2. Download & test model locally
3. Implement WordAlignmentService.swift
4. Build & test alignment on sample paragraph
