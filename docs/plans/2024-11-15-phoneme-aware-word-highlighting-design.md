# Phoneme-Aware Word Highlighting Design

## Overview

This design implements reliable word-level highlighting for Piper TTS playback using a phoneme-aware streaming architecture. The key innovation is bundling phoneme timing data with each audio sentence chunk, using relative timing within sentences to eliminate synchronization issues.

## Problem Statement

The current word highlighting implementation suffers from:
- Random word highlighting and glitching between words
- Synchronization issues between audio playback and highlighting
- Difficulty handling the rolling cache architecture
- Complex mapping between normalized and original text

## Solution Architecture

### Core Concept

Each sentence in the rolling cache becomes a self-contained unit with:
1. Audio data (WAV format)
2. Phoneme timeline with relative timing
3. Mapping from phonemes → normalized text → original text → VoxPDF words
4. Word boundaries with timing information

### Key Benefits

- **Reliable Sync**: Relative timing per sentence eliminates drift
- **Clean Architecture**: Aligns with existing rolling cache design
- **Smooth Transitions**: Each sentence manages its own timeline
- **Pause/Resume Support**: Relative timing makes this trivial
- **Speed Changes**: Can be handled per sentence

## Data Structures

### PhonemeTimeline

Represents the timing information for a single sentence:

```swift
struct PhonemeTimeline: Codable {
    let sentenceText: String           // Original sentence text
    let normalizedText: String          // After espeak normalization
    let phonemes: [TimedPhoneme]       // Phonemes with relative times
    let wordBoundaries: [WordBoundary] // Word start/end times
    let duration: TimeInterval          // Total sentence duration

    struct TimedPhoneme: Codable {
        let phoneme: PhonemeInfo        // Original phoneme data
        let startTime: TimeInterval     // Relative to sentence start
        let endTime: TimeInterval       // startTime + duration
        let normalizedRange: Range<Int> // Position in normalized text
        let originalRange: Range<Int>?  // Position in original (via mapping)
    }

    struct WordBoundary: Codable {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let originalRange: Range<String.Index> // For highlighting
        let voxPDFWord: WordPosition?         // VoxPDF word data if available
    }

    /// Find the active word at a given time offset
    func findWord(at timeOffset: TimeInterval) -> WordBoundary? {
        // Binary search implementation
        return wordBoundaries.first {
            timeOffset >= $0.startTime && timeOffset < $0.endTime
        }
    }
}
```

### SentenceBundle

Combines audio with timing data:

```swift
struct SentenceBundle {
    let chunk: TextChunk              // Existing sentence data
    let audioData: Data               // WAV audio
    let timeline: PhonemeTimeline?   // Optional - may fail to generate
    let paragraphIndex: Int
    let sentenceIndex: Int
    let sentenceKey: String          // "paragraphIndex-sentenceIndex"
}
```

### EnhancedSynthesisResult

Extends the existing SynthesisResult:

```swift
extension SynthesisResult {
    /// Build a phoneme timeline from synthesis result
    func buildTimeline(
        for sentence: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> PhonemeTimeline? {
        // Implementation details below
    }
}
```

## Component Design

### 1. SynthesisQueue Modifications

The SynthesisQueue needs to build and cache sentence bundles:

```swift
extension SynthesisQueue {
    /// Stream sentence bundles with timing data
    func streamSentenceBundles(for index: Int) -> AsyncStream<SentenceBundle> {
        AsyncStream { continuation in
            Task {
                // Similar to existing streamAudio
                for sentenceIndex in 0..<chunks.count {
                    let bundle = try await synthesizeSentenceBundle(
                        paragraphIndex: index,
                        sentenceIndex: sentenceIndex
                    )
                    continuation.yield(bundle)
                }
                continuation.finish()
            }
        }
    }

    private func synthesizeSentenceBundle(
        paragraphIndex: Int,
        sentenceIndex: Int
    ) async throws -> SentenceBundle {
        // 1. Synthesize audio with phonemes
        let result = try await synthesizeSentence(
            paragraphIndex: paragraphIndex,
            sentenceIndex: sentenceIndex
        )

        // 2. Build timeline from phonemes
        let timeline = result.buildTimeline(
            for: chunk.text,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex
        )

        // 3. Create bundle
        return SentenceBundle(
            chunk: chunk,
            audioData: result.audioData,
            timeline: timeline,
            paragraphIndex: paragraphIndex,
            sentenceIndex: sentenceIndex
        )
    }
}
```

### 2. WordHighlighter Actor

Manages the highlighting state:

```swift
actor WordHighlighter {
    private var currentTimeline: PhonemeTimeline?
    private var sentenceStartTime: Date?
    private var displayLink: CADisplayLink?
    private var isPaused = false
    private var pausedTime: TimeInterval = 0

    // Callback for UI updates
    private var onHighlight: ((WordPosition?) -> Void)?

    /// Start highlighting for a new sentence
    func startSentence(_ bundle: SentenceBundle) {
        currentTimeline = bundle.timeline
        sentenceStartTime = Date()
        pausedTime = 0
        isPaused = false
        startDisplayLink()
    }

    /// Pause highlighting
    func pause() {
        guard !isPaused, let startTime = sentenceStartTime else { return }
        pausedTime = Date().timeIntervalSince(startTime)
        isPaused = true
        stopDisplayLink()
    }

    /// Resume highlighting
    func resume() {
        guard isPaused else { return }
        sentenceStartTime = Date().addingTimeInterval(-pausedTime)
        isPaused = false
        startDisplayLink()
    }

    /// Stop highlighting
    func stop() {
        currentTimeline = nil
        sentenceStartTime = nil
        pausedTime = 0
        isPaused = false
        stopDisplayLink()
    }

    @objc private func updateHighlight() {
        guard !isPaused,
              let timeline = currentTimeline,
              let startTime = sentenceStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)

        // Find current word using binary search
        if let word = timeline.findWord(at: elapsed) {
            Task { @MainActor in
                onHighlight?(word.voxPDFWord)
            }
        }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updateHighlight))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
```

### 3. PhonemeTimeline Builder

Creates timeline from synthesis results:

```swift
extension SynthesisResult {
    func buildTimeline(
        for sentence: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> PhonemeTimeline? {
        // Guard against empty phonemes
        guard !phonemes.isEmpty else { return nil }

        // 1. Build timed phonemes with accumulated timing
        var timedPhonemes: [PhonemeTimeline.TimedPhoneme] = []
        var currentTime: TimeInterval = 0

        for phoneme in phonemes {
            let timed = PhonemeTimeline.TimedPhoneme(
                phoneme: phoneme,
                startTime: currentTime,
                endTime: currentTime + phoneme.duration,
                normalizedRange: phoneme.textRange,
                originalRange: mapToOriginal(phoneme.textRange)
            )
            timedPhonemes.append(timed)
            currentTime += phoneme.duration
        }

        // 2. Find word boundaries using phoneme positions
        let wordBoundaries = findWordBoundaries(
            timedPhonemes: timedPhonemes,
            originalText: sentence,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex
        )

        // 3. Create timeline
        return PhonemeTimeline(
            sentenceText: sentence,
            normalizedText: normalizedText,
            phonemes: timedPhonemes,
            wordBoundaries: wordBoundaries,
            duration: currentTime
        )
    }

    private func mapToOriginal(_ normalizedRange: Range<Int>) -> Range<Int>? {
        // Use charMapping to convert normalized position to original
        guard let firstMapping = charMapping.first(where: {
            $0.normalizedPos == normalizedRange.lowerBound
        }) else { return nil }

        guard let lastMapping = charMapping.first(where: {
            $0.normalizedPos == normalizedRange.upperBound - 1
        }) else { return nil }

        return firstMapping.originalPos..<(lastMapping.originalPos + 1)
    }

    private func findWordBoundaries(
        timedPhonemes: [PhonemeTimeline.TimedPhoneme],
        originalText: String,
        normalizedText: String,
        charMapping: [(originalPos: Int, normalizedPos: Int)],
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> [PhonemeTimeline.WordBoundary] {
        var boundaries: [PhonemeTimeline.WordBoundary] = []

        // Split original text into words
        let words = originalText.split(separator: " ", omittingEmptySubsequences: true)
        var currentOffset = 0

        for word in words {
            let wordString = String(word)
            let wordRange = currentOffset..<(currentOffset + wordString.count)

            // Find phonemes that overlap this word
            let wordPhonemes = timedPhonemes.filter { phoneme in
                if let originalRange = phoneme.originalRange {
                    return originalRange.overlaps(wordRange)
                }
                return false
            }

            guard !wordPhonemes.isEmpty else {
                currentOffset += wordString.count + 1 // +1 for space
                continue
            }

            // Get timing from first and last phoneme
            let startTime = wordPhonemes.first!.startTime
            let endTime = wordPhonemes.last!.endTime

            // Convert to String.Index range
            let startIndex = originalText.index(
                originalText.startIndex,
                offsetBy: currentOffset
            )
            let endIndex = originalText.index(
                startIndex,
                offsetBy: wordString.count
            )

            // Find VoxPDF word if available
            let voxWord = wordMap?.word(at: currentOffset, in: paragraphIndex)

            boundaries.append(PhonemeTimeline.WordBoundary(
                word: wordString,
                startTime: startTime,
                endTime: endTime,
                originalRange: startIndex..<endIndex,
                voxPDFWord: voxWord
            ))

            currentOffset += wordString.count + 1 // +1 for space
        }

        return boundaries
    }
}
```

### 4. TTSService Integration

Connect the word highlighter to playback:

```swift
extension TTSService {
    private let wordHighlighter = WordHighlighter()

    private func playPiperSentences(at index: Int) {
        Task {
            let bundleStream = synthesisQueue.streamSentenceBundles(for: index)

            for await bundle in bundleStream {
                // Start highlighting for this sentence
                await wordHighlighter.startSentence(bundle)

                // Play audio (existing code)
                await audioPlayer.play(bundle.audioData)

                // Notify completion
                synthesisQueue.onSentenceFinished(
                    paragraphIndex: bundle.paragraphIndex,
                    sentenceIndex: bundle.sentenceIndex
                )
            }

            // Stop highlighting when done
            await wordHighlighter.stop()
        }
    }

    func pause() {
        audioPlayer.pause()
        Task {
            await wordHighlighter.pause()
        }
    }

    func resume() {
        audioPlayer.resume()
        Task {
            await wordHighlighter.resume()
        }
    }
}
```

## Implementation Steps

1. **Create Core Data Structures** (30 min)
   - PhonemeTimeline struct
   - SentenceBundle struct
   - TimedPhoneme and WordBoundary

2. **Implement PhonemeTimeline Builder** (1 hour)
   - Map phonemes to normalized text
   - Use charMapping for original positions
   - Find word boundaries
   - Handle edge cases (punctuation, contractions)

3. **Modify SynthesisQueue** (45 min)
   - Add streamSentenceBundles method
   - Update cache to store bundles
   - Maintain backward compatibility

4. **Create WordHighlighter Actor** (45 min)
   - CADisplayLink management
   - Binary search for current word
   - Pause/resume support
   - Thread-safe state management

5. **Integrate with TTSService** (30 min)
   - Connect highlighter to playback
   - Handle sentence transitions
   - Update pause/resume methods

6. **Update UI Bindings** (30 min)
   - Connect highlighter callbacks to ReaderView
   - Ensure smooth UI updates
   - Handle nil timelines gracefully

7. **Testing & Debugging** (2 hours)
   - Test with various text types
   - Verify normalized text mapping
   - Check sentence transitions
   - Validate pause/resume behavior

8. **Performance Optimization** (30 min)
   - Profile binary search
   - Optimize memory usage
   - Cache timeline calculations

## Testing Strategy

### Unit Tests
- PhonemeTimeline construction
- Word boundary detection
- Normalized text mapping
- Binary search correctness

### Integration Tests
- Sentence bundle streaming
- Highlighter state transitions
- Pause/resume timing accuracy
- Speed change handling

### Manual Testing Checklist
- [ ] Numbers normalize correctly ("123" → "one hundred twenty-three")
- [ ] Abbreviations work ("Dr. Smith" → "Doctor Smith")
- [ ] Contractions highlight properly ("don't" → "do not")
- [ ] Punctuation doesn't break highlighting
- [ ] Sentence transitions are smooth
- [ ] Pause/resume maintains correct position
- [ ] No glitching or random word jumping
- [ ] Performance is smooth at 60 FPS

## Known Challenges & Solutions

### Challenge 1: Normalized Text Mapping
**Issue**: "Dr." becomes "Doctor" but we need to highlight "Dr." in the original
**Solution**: Use charMapping array to map positions bidirectionally

### Challenge 2: Word Boundary Detection
**Issue**: Phonemes don't align perfectly with word boundaries
**Solution**: Find overlapping phonemes and use their combined duration

### Challenge 3: Sentence Transitions
**Issue**: Gap between sentences could lose highlighting
**Solution**: Maintain last word highlighted until new sentence starts

### Challenge 4: Speed Changes
**Issue**: User changes speed mid-playback
**Solution**: Each sentence uses its own speed, no retroactive changes

## Performance Considerations

- Binary search for word lookup: O(log n) per frame
- Memory overhead: ~2KB per sentence for timeline data
- CADisplayLink runs at 60 FPS (16.67ms per update)
- Timeline building happens during synthesis (off main thread)

## Migration Path

1. Implement new system alongside existing code
2. Add feature flag to toggle between old and new
3. Test thoroughly with subset of users
4. Remove old implementation once stable

## Success Criteria

- Word highlighting is accurate and synchronized
- No glitching or random word jumping
- Smooth transitions between sentences
- Pause/resume works correctly
- Performance impact < 5% CPU usage
- Works with all text normalization cases

## Future Enhancements

- Syllable-level highlighting for language learning
- Karaoke-style upcoming word preview
- Speed-adjusted highlighting animation
- Word-level progress bar
- Tap-to-seek to specific word