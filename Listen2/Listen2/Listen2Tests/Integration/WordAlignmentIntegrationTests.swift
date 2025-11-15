//
//  WordAlignmentIntegrationTests.swift
//  Listen2Tests
//
//  End-to-end integration tests for word-level alignment feature
//  Tests complete flow: Text → TTS → ASR Alignment → Word Highlighting
//

import XCTest
import AVFoundation
@testable import Listen2

/// End-to-end integration tests for word-level alignment feature
/// Verifies the complete pipeline from text synthesis through alignment to playback highlighting
final class WordAlignmentIntegrationTests: XCTestCase {

    var voiceManager: VoiceManager!
    var ttsProvider: PiperTTSProvider!
    var alignmentService: WordAlignmentService!
    var alignmentCache: AlignmentCache!
    var testDocumentID: UUID!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Initialize components
        voiceManager = VoiceManager()
        testDocumentID = UUID()

        // Get bundled voice
        let bundledVoice = voiceManager.bundledVoice()

        // Initialize TTS provider
        ttsProvider = PiperTTSProvider(
            voiceID: bundledVoice.id,
            voiceManager: voiceManager
        )

        // Initialize alignment service
        alignmentService = WordAlignmentService()

        // Get ASR model path
        guard let modelDir = Bundle.main.path(forResource: "tiny-encoder.int8", ofType: "onnx", inDirectory: "ASRModels/whisper-tiny") else {
            throw XCTSkip("ASR model files not found in bundle")
        }

        let modelPath = (modelDir as NSString).deletingLastPathComponent

        // Initialize cache
        alignmentCache = AlignmentCache()
        try await alignmentCache.clear(for: testDocumentID)

        // Initialize services
        try await ttsProvider.initialize()
        try await alignmentService.initialize(modelPath: modelPath)
    }

    override func tearDown() async throws {
        // Clean up
        try await alignmentCache.clear(for: testDocumentID)
        await alignmentService.deinitialize()

        alignmentService = nil
        ttsProvider = nil
        alignmentCache = nil
        voiceManager = nil
        testDocumentID = nil

        try await super.tearDown()
    }

    // MARK: - End-to-End Integration Tests

    /// Test complete alignment pipeline: Text → Synthesis → ASR Alignment → Word Timings
    /// This is the primary integration test verifying all components work together
    func testEndToEndAlignmentPipeline() async throws {
        // Given: A paragraph of text with known word positions
        let text = "The quick brown fox jumps over the lazy dog."
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Step 1: Synthesize audio with Piper TTS
        print("Step 1: Synthesizing audio...")
        let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData

        XCTAssertGreaterThan(audioData.count, 0, "TTS should produce audio data")

        // Save audio to file
        let audioURL = try createTempAudioFile(from: audioData)
        print("Audio saved to: \(audioURL.path)")

        // Step 2: Perform ASR alignment
        print("Step 2: Performing ASR alignment...")
        let alignment = try await alignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify alignment result structure
        XCTAssertEqual(alignment.paragraphIndex, 0, "Alignment should be for paragraph 0")
        XCTAssertGreaterThan(alignment.totalDuration, 0, "Alignment should have positive duration")
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Alignment should produce word timings")

        print("Alignment complete: \(alignment.wordTimings.count) words aligned")
        print("Total duration: \(alignment.totalDuration)s")

        // Step 3: Verify word timings are sequential and valid
        print("Step 3: Verifying word timings...")
        for (index, wordTiming) in alignment.wordTimings.enumerated() {
            // Each word should have positive duration
            XCTAssertGreaterThan(
                wordTiming.duration,
                0,
                "Word '\(wordTiming.text)' should have positive duration"
            )

            // Each word's start time should be within the total duration
            XCTAssertLessThanOrEqual(
                wordTiming.startTime,
                alignment.totalDuration,
                "Word '\(wordTiming.text)' start time should be within total duration"
            )

            // Words should be in chronological order
            if index > 0 {
                let previousTiming = alignment.wordTimings[index - 1]
                XCTAssertGreaterThanOrEqual(
                    wordTiming.startTime,
                    previousTiming.startTime,
                    "Words should be in chronological order"
                )
            }

            // Verify string range can extract the word from text
            if let extractedRange = wordTiming.stringRange(in: text) {
                let extractedText = String(text[extractedRange])
                print("  Word \(index): '\(wordTiming.text)' at \(wordTiming.startTime)s, extracted: '\(extractedText)'")
            }
        }

        // Step 4: Simulate playback and verify highlighting lookup
        print("Step 4: Simulating playback highlighting...")

        // Test word lookup at various playback positions
        let testTimes: [TimeInterval] = [0.0, alignment.totalDuration / 2, alignment.totalDuration - 0.1]

        for time in testTimes {
            if let wordTiming = alignment.wordTiming(at: time) {
                print("  At t=\(time)s: '\(wordTiming.text)' (index \(wordTiming.wordIndex))")
                XCTAssertTrue(
                    time >= wordTiming.startTime && time < wordTiming.startTime + wordTiming.duration,
                    "Word lookup should return correct word for playback time"
                )
            }
        }

        print("✅ End-to-end alignment pipeline test passed")
    }

    /// Test that alignment results are correctly cached and can be retrieved
    func testAlignmentCaching() async throws {
        // Given: A synthesized audio file and alignment
        let text = "Hello world this is a test."
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData
        let audioURL = try createTempAudioFile(from: audioData)

        // Step 1: Perform alignment (should not be cached)
        let startTime1 = CFAbsoluteTimeGetCurrent()
        let alignment1 = try await alignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )
        let time1 = CFAbsoluteTimeGetCurrent() - startTime1

        // Step 2: Save to persistent cache
        try await alignmentCache.save(alignment1, for: testDocumentID, paragraph: 0, speed: 1.0)

        // Step 3: Load from persistent cache
        let cachedAlignment = try await alignmentCache.load(for: testDocumentID, paragraph: 0, speed: 1.0)

        XCTAssertNotNil(cachedAlignment, "Alignment should be cached")
        XCTAssertEqual(cachedAlignment?.paragraphIndex, alignment1.paragraphIndex)
        XCTAssertEqual(cachedAlignment?.wordTimings.count, alignment1.wordTimings.count)
        XCTAssertEqual(cachedAlignment?.totalDuration, alignment1.totalDuration)

        // Step 4: Verify memory cache hit (should be much faster)
        let startTime2 = CFAbsoluteTimeGetCurrent()
        _ = await alignmentService.getCachedAlignment(for: audioURL)
        let time2 = CFAbsoluteTimeGetCurrent() - startTime2

        XCTAssertLessThan(time2, time1, "Memory cache hit should be faster than initial alignment")
        XCTAssertLessThan(time2, 0.010, "Memory cache hit should be < 10ms")

        print("Cache performance: First alignment: \(time1)s, Cache hit: \(time2 * 1000)ms")
        print("✅ Alignment caching test passed")
    }

    /// Test alignment with different voice speeds produces different timings
    func testAlignmentWithDifferentSpeeds() async throws {
        // Given: Same text synthesized at different speeds
        let text = "Testing alignment with different speeds."
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Synthesize at slow speed
        let slowResult = try await ttsProvider.synthesize(text, speed: 0.5)
        let slowURL = try createTempAudioFile(from: slowResult.audioData)

        // Synthesize at fast speed
        let fastResult = try await ttsProvider.synthesize(text, speed: 2.0)
        let fastURL = try createTempAudioFile(from: fastResult.audioData)

        // Align both
        let slowAlignment = try await alignmentService.align(
            audioURL: slowURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        let fastAlignment = try await alignmentService.align(
            audioURL: fastURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify different speeds produce different durations
        XCTAssertGreaterThan(
            slowAlignment.totalDuration,
            fastAlignment.totalDuration,
            "Slower speed should produce longer audio duration"
        )

        // Both should have same number of words
        XCTAssertEqual(
            slowAlignment.wordTimings.count,
            fastAlignment.wordTimings.count,
            "Both should align the same number of words"
        )

        print("Slow alignment: \(slowAlignment.totalDuration)s")
        print("Fast alignment: \(fastAlignment.totalDuration)s")
        print("✅ Different speed alignment test passed")
    }

    /// Test alignment with contractions (e.g., "don't", "I'll")
    func testAlignmentWithContractions() async throws {
        // Given: Text with contractions
        let text = "I don't think we'll need it."
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Synthesize and align
        let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData
        let audioURL = try createTempAudioFile(from: audioData)

        let alignment = try await alignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify alignment handles contractions
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should align words with contractions")

        // Find contractions in word timings
        let contractions = alignment.wordTimings.filter { $0.text.contains("'") }
        print("Found \(contractions.count) contractions: \(contractions.map { $0.text })")

        // Each contraction should have valid timing
        for contraction in contractions {
            XCTAssertGreaterThan(contraction.duration, 0, "Contraction '\(contraction.text)' should have positive duration")
        }

        print("✅ Contractions alignment test passed")
    }

    /// Test alignment with punctuation
    func testAlignmentWithPunctuation() async throws {
        // Given: Text with various punctuation
        let text = "Hello, world! How are you? I'm fine."
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Synthesize and align
        let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData
        let audioURL = try createTempAudioFile(from: audioData)

        let alignment = try await alignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify alignment handles punctuation
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should align words with punctuation")

        // All words should have valid timings
        for wordTiming in alignment.wordTimings {
            XCTAssertGreaterThan(
                wordTiming.duration,
                0,
                "Word '\(wordTiming.text)' should have positive duration"
            )
        }

        print("Aligned \(alignment.wordTimings.count) words with punctuation")
        print("✅ Punctuation alignment test passed")
    }

    /// Test alignment performance meets target (<2s per plan Section 7.3)
    func testAlignmentPerformanceMeetsTarget() async throws {
        // Given: A realistic paragraph (~100 words, ~30s audio)
        let paragraphText = """
        The quick brown fox jumps over the lazy dog. This sentence is often used for testing \
        because it contains every letter of the alphabet. In our application, we need to ensure \
        that word-level alignment works efficiently even for longer paragraphs. The alignment \
        service uses dynamic time warping to map ASR tokens to VoxPDF words, which requires \
        careful optimization. Each word must be precisely timed so that highlighting remains \
        synchronized with audio playback. Performance is critical because users expect smooth, \
        responsive playback without noticeable delays.
        """

        let words = createWordMapFromText(paragraphText, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Synthesize audio
        let synthesisResult = try await ttsProvider.synthesize(paragraphText, speed: 1.0)
        let audioData = synthesisResult.audioData
        let audioURL = try createTempAudioFile(from: audioData)

        // Measure alignment time
        let startTime = CFAbsoluteTimeGetCurrent()

        let alignment = try await alignmentService.align(
            audioURL: audioURL,
            text: paragraphText,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        let alignmentTime = CFAbsoluteTimeGetCurrent() - startTime

        // Verify performance target
        XCTAssertLessThan(
            alignmentTime,
            2.0,
            "Alignment should complete in < 2s (actual: \(alignmentTime)s)"
        )

        print("Alignment performance: \(alignmentTime)s for \(alignment.wordTimings.count) words")
        print("Audio duration: \(alignment.totalDuration)s")
        print("✅ Performance target met")
    }

    /// Test cache hit rate validation (per plan Section 8.2)
    func testCacheHitRateValidation() async throws {
        // Given: Multiple paragraphs to synthesize and align
        let paragraphs = [
            "First paragraph for cache testing.",
            "Second paragraph for cache testing.",
            "Third paragraph for cache testing.",
            "Fourth paragraph for cache testing.",
            "Fifth paragraph for cache testing."
        ]

        var alignments: [AlignmentResult] = []

        // First pass: Align all paragraphs (cache misses)
        print("First pass: Aligning all paragraphs...")
        for (index, text) in paragraphs.enumerated() {
            let words = createWordMapFromText(text, paragraphIndex: index)
            let wordMap = DocumentWordMap(words: words)

            let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData
            let audioURL = try createTempAudioFile(from: audioData)

            let alignment = try await alignmentService.align(
                audioURL: audioURL,
                text: text,
                wordMap: wordMap,
                paragraphIndex: index
            )

            alignments.append(alignment)

            // Save to persistent cache
            try await alignmentCache.save(alignment, for: testDocumentID, paragraph: index, speed: 1.0)
        }

        // Second pass: Load from cache (cache hits)
        print("Second pass: Loading from cache...")
        var cacheHits = 0

        for index in 0..<paragraphs.count {
            let startTime = CFAbsoluteTimeGetCurrent()
            let cached = try await alignmentCache.load(for: testDocumentID, paragraph: index, speed: 1.0)
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime

            if cached != nil {
                cacheHits += 1
                XCTAssertLessThan(loadTime, 0.010, "Cache load should be < 10ms")
            }
        }

        // Calculate cache hit rate
        let cacheHitRate = Double(cacheHits) / Double(paragraphs.count)

        print("Cache hit rate: \(cacheHitRate * 100)% (\(cacheHits)/\(paragraphs.count))")

        // Verify cache hit rate > 95% (target from plan)
        XCTAssertGreaterThanOrEqual(
            cacheHitRate,
            0.95,
            "Cache hit rate should be > 95% (actual: \(cacheHitRate * 100)%)"
        )

        print("✅ Cache hit rate validation passed")
    }

    /// Test that word highlighting drift is minimal over long paragraph
    /// Verifies: Highlighting drift < 100ms over 5-minute paragraph (plan success metric)
    func testWordHighlightingDrift() async throws {
        // Given: A long paragraph
        let text = generateLongParagraph(targetDuration: 60.0) // ~1 minute for testing
        let words = createWordMapFromText(text, paragraphIndex: 0)
        let wordMap = DocumentWordMap(words: words)

        // Synthesize and align
        let synthesisResult = try await ttsProvider.synthesize(text, speed: 1.0)
        let audioData = synthesisResult.audioData
        let audioURL = try createTempAudioFile(from: audioData)

        let alignment = try await alignmentService.align(
            audioURL: audioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify alignment quality
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should have word timings")

        // Check that word timings are evenly distributed (no large gaps)
        var maxGap: TimeInterval = 0

        for i in 1..<alignment.wordTimings.count {
            let previousEnd = alignment.wordTimings[i-1].startTime + alignment.wordTimings[i-1].duration
            let currentStart = alignment.wordTimings[i].startTime
            let gap = currentStart - previousEnd

            maxGap = max(maxGap, gap)
        }

        print("Maximum gap between words: \(maxGap * 1000)ms")

        // Maximum gap should be reasonable (< 500ms)
        XCTAssertLessThan(maxGap, 0.5, "Gap between words should be < 500ms")

        // Verify last word timing is close to total duration (minimal drift)
        if let lastWord = alignment.wordTimings.last {
            let lastWordEnd = lastWord.startTime + lastWord.duration
            let drift = abs(alignment.totalDuration - lastWordEnd)

            print("Drift at end of paragraph: \(drift * 1000)ms")

            XCTAssertLessThan(drift, 0.1, "Drift should be < 100ms (actual: \(drift * 1000)ms)")
        }

        print("✅ Word highlighting drift test passed")
    }

    // MARK: - Helper Methods

    /// Create a temporary audio file from audio data
    private func createTempAudioFile(from data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test_audio_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try data.write(to: fileURL)

        return fileURL
    }

    /// Create a word map from text by splitting on whitespace
    private func createWordMapFromText(_ text: String, paragraphIndex: Int) -> [WordPosition] {
        var words: [WordPosition] = []
        var characterOffset = 0

        // Split text into words
        let components = text.components(separatedBy: .whitespacesAndNewlines)

        for component in components {
            guard !component.isEmpty else {
                characterOffset += 1
                continue
            }

            words.append(WordPosition(
                text: component,
                characterOffset: characterOffset,
                length: component.count,
                paragraphIndex: paragraphIndex,
                pageNumber: 0
            ))

            characterOffset += component.count + 1
        }

        return words
    }

    /// Generate a long paragraph with approximately the target duration
    private func generateLongParagraph(targetDuration: TimeInterval) -> String {
        // Estimate ~150 words per minute of speech
        let wordsPerSecond = 2.5
        let targetWords = Int(targetDuration * wordsPerSecond)

        let baseWords = [
            "The", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
            "Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
            "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
            "magna", "aliqua", "Ut", "enim", "ad", "minim", "veniam", "quis", "nostrud"
        ]

        var words: [String] = []
        for i in 0..<targetWords {
            words.append(baseWords[i % baseWords.count])
        }

        return words.joined(separator: " ")
    }
}
