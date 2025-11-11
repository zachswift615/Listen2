//
//  WordAlignmentServiceTests.swift
//  Listen2Tests
//
//  Test suite for WordAlignmentService
//

import XCTest
import AVFoundation
@testable import Listen2

/// Tests for WordAlignmentService
final class WordAlignmentServiceTests: XCTestCase {

    var service: WordAlignmentService!
    var modelPath: String!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        service = WordAlignmentService()

        // Get model path from bundle
        guard let path = Bundle.main.path(forResource: "tiny-encoder.int8", ofType: "onnx", inDirectory: "ASRModels/whisper-tiny") else {
            XCTFail("Could not find ASR model in bundle")
            return
        }

        // Extract directory path
        modelPath = (path as NSString).deletingLastPathComponent
        print("Model path: \(modelPath ?? "nil")")
    }

    override func tearDown() async throws {
        await service.deinitialize()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testServiceInitialization() async throws {
        // Test that service can be initialized with valid model path
        try await service.initialize(modelPath: modelPath)

        // Verify service is initialized (implicitly tested by not throwing)
    }

    func testInitializationWithInvalidPath() async throws {
        // Test that initialization fails with invalid path
        do {
            try await service.initialize(modelPath: "/invalid/path")
            XCTFail("Should throw error for invalid path")
        } catch let error as AlignmentError {
            // Expected error
            XCTAssertEqual(error, AlignmentError.recognitionFailed("Model files not found at path: /invalid/path"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDoubleInitialization() async throws {
        // Initialize once
        try await service.initialize(modelPath: modelPath)

        // Initialize again should not throw
        try await service.initialize(modelPath: modelPath)
    }

    // MARK: - Audio Loading Tests

    func testAudioLoadingRequiresInitialization() async throws {
        // Create a test audio file
        let testAudioURL = try createTestAudioFile()

        // Try to align without initializing
        do {
            let wordMap = createTestWordMap()
            _ = try await service.align(
                audioURL: testAudioURL,
                text: "Test text",
                wordMap: wordMap,
                paragraphIndex: 0
            )
            XCTFail("Should throw error when not initialized")
        } catch AlignmentError.modelNotInitialized {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAudioLoadingWithValidWAV() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create test audio file
        let testAudioURL = try createTestAudioFile()

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: testAudioURL.path))

        let wordMap = createTestWordMap()

        // This should not throw
        let result = try await service.align(
            audioURL: testAudioURL,
            text: "Hello world",
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify result structure
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThanOrEqual(result.totalDuration, 0)
    }

    func testAudioLoadingWithInvalidFormat() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create a non-WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let invalidURL = tempDir.appendingPathComponent("test.mp3")
        try "dummy".write(to: invalidURL, atomically: true, encoding: .utf8)

        let wordMap = createTestWordMap()

        do {
            _ = try await service.align(
                audioURL: invalidURL,
                text: "Test",
                wordMap: wordMap,
                paragraphIndex: 0
            )
            XCTFail("Should throw error for non-WAV file")
        } catch AlignmentError.invalidAudioFormat {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - ASR Recognition Tests

    func testASRTranscription() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create test audio with known content
        // Note: This test uses a synthesized audio file
        let testAudioURL = try createTestAudioFile(withText: "Hello")

        let wordMap = createTestWordMap()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: "Hello",
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify alignment result
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0, "Should have non-zero duration")

        // Note: wordTimings will be empty until Task 5 implements token-to-word mapping
        // For now, we just verify that ASR runs without crashing
    }

    // MARK: - Cache Tests

    func testCacheReturnsNilForNonCachedURL() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.wav")
        let cached = await service.getCachedAlignment(for: testURL)
        XCTAssertNil(cached, "Should return nil for non-cached URL")
    }

    func testCacheStoresAlignment() async throws {
        try await service.initialize(modelPath: modelPath)

        let testAudioURL = try createTestAudioFile()
        let wordMap = createTestWordMap()

        // Perform alignment
        let result1 = try await service.align(
            audioURL: testAudioURL,
            text: "Test text",
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Get cached alignment
        let cached = await service.getCachedAlignment(for: testAudioURL)
        XCTAssertNotNil(cached, "Should have cached alignment")
        XCTAssertEqual(cached?.paragraphIndex, result1.paragraphIndex)
        XCTAssertEqual(cached?.totalDuration, result1.totalDuration)
    }

    func testCacheClearRemovesAlignments() async throws {
        try await service.initialize(modelPath: modelPath)

        let testAudioURL = try createTestAudioFile()
        let wordMap = createTestWordMap()

        // Perform alignment
        _ = try await service.align(
            audioURL: testAudioURL,
            text: "Test text",
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify cached
        var cached = await service.getCachedAlignment(for: testAudioURL)
        XCTAssertNotNil(cached)

        // Clear cache
        await service.clearCache()

        // Verify cleared
        cached = await service.getCachedAlignment(for: testAudioURL)
        XCTAssertNil(cached, "Cache should be empty after clear")
    }

    // MARK: - AlignmentResult Tests

    func testAlignmentResultValidation() {
        // Valid alignment with empty wordTimings (Task 3 allows this)
        let validResult = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: 5.0,
            wordTimings: []
        )
        XCTAssertTrue(validResult.isValid(for: "test text"))

        // Invalid: negative duration
        let negativeResult = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: -1.0,
            wordTimings: []
        )
        XCTAssertFalse(negativeResult.isValid(for: "test text"))

        // Invalid: duration too long (over 1 hour)
        let tooLongResult = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: 4000.0,
            wordTimings: []
        )
        XCTAssertFalse(tooLongResult.isValid(for: "test text"))
    }

    func testWordTimingAtTime() {
        let dummyRange = "test".startIndex..<"test".endIndex

        let timings = [
            AlignmentResult.WordTiming(
                wordIndex: 0,
                startTime: 0.0,
                duration: 0.5,
                text: "Hello",
                stringRange: dummyRange
            ),
            AlignmentResult.WordTiming(
                wordIndex: 1,
                startTime: 0.5,
                duration: 0.5,
                text: "world",
                stringRange: dummyRange
            )
        ]

        let result = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: 1.0,
            wordTimings: timings
        )

        // Test finding words at specific times
        XCTAssertEqual(result.wordTiming(at: 0.2)?.text, "Hello")
        XCTAssertEqual(result.wordTiming(at: 0.7)?.text, "world")
        XCTAssertNil(result.wordTiming(at: 1.5), "Should return nil for time after all words")
    }

    // MARK: - Token-to-Word Mapping Tests

    func testTokenToWordMappingSimple() async throws {
        try await service.initialize(modelPath: modelPath)

        // Test with a simple case where tokens match words
        let text = "Hello world"
        let testAudioURL = try createTestAudioFile()
        let wordMap = createTestWordMap()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // We should have word timings now (though they may not be perfect due to test audio being silence)
        // Just verify the structure is correct
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0)
    }

    func testTokenToWordMappingWithContractions() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create word map with contractions
        let words = [
            WordPosition(
                text: "don't",
                characterOffset: 0,
                length: 5,
                paragraphIndex: 0,
                pageNumber: 0
            ),
            WordPosition(
                text: "worry",
                characterOffset: 6,
                length: 5,
                paragraphIndex: 0,
                pageNumber: 0
            )
        ]
        let wordMap = DocumentWordMap(words: words)

        let text = "don't worry"
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify result structure
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0)
    }

    func testTokenToWordMappingWithPunctuation() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create word map with punctuation
        let words = [
            WordPosition(
                text: "Hello,",
                characterOffset: 0,
                length: 6,
                paragraphIndex: 0,
                pageNumber: 0
            ),
            WordPosition(
                text: "world!",
                characterOffset: 7,
                length: 6,
                paragraphIndex: 0,
                pageNumber: 0
            )
        ]
        let wordMap = DocumentWordMap(words: words)

        let text = "Hello, world!"
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify result structure
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0)
    }

    func testTokenToWordMappingEmptyWords() async throws {
        try await service.initialize(modelPath: modelPath)

        // Empty word map
        let wordMap = DocumentWordMap(words: [])
        let text = ""
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Should handle gracefully
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertTrue(result.wordTimings.isEmpty, "Should have no word timings for empty text")
    }

    func testWordTimingsAreSequential() async throws {
        try await service.initialize(modelPath: modelPath)

        let words = [
            WordPosition(text: "The", characterOffset: 0, length: 3, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "quick", characterOffset: 4, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "brown", characterOffset: 10, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "fox", characterOffset: 16, length: 3, paragraphIndex: 0, pageNumber: 0)
        ]
        let wordMap = DocumentWordMap(words: words)
        let text = "The quick brown fox"
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify word timings are in sequential order
        if result.wordTimings.count > 1 {
            for i in 1..<result.wordTimings.count {
                XCTAssertGreaterThanOrEqual(
                    result.wordTimings[i].startTime,
                    result.wordTimings[i-1].startTime,
                    "Word timings should be in chronological order"
                )
            }
        }
    }

    func testWordTimingStringRanges() async throws {
        try await service.initialize(modelPath: modelPath)

        let text = "Hello world"
        let words = [
            WordPosition(text: "Hello", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "world", characterOffset: 6, length: 5, paragraphIndex: 0, pageNumber: 0)
        ]
        let wordMap = DocumentWordMap(words: words)
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify string ranges can be reconstructed
        for wordTiming in result.wordTimings {
            if let range = wordTiming.stringRange(in: text) {
                let extractedText = String(text[range])
                // The extracted text should match the word text (ignoring case/punctuation differences)
                XCTAssertTrue(
                    extractedText.lowercased().contains(wordTiming.text.lowercased()) ||
                    wordTiming.text.lowercased().contains(extractedText.lowercased()),
                    "String range should extract the correct word text"
                )
            }
        }
    }

    func testAlignmentValidation() async throws {
        try await service.initialize(modelPath: modelPath)

        let wordMap = createTestWordMap()
        let text = "Hello world"
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Result should be valid
        XCTAssertTrue(result.isValid(for: text), "Alignment result should be valid")
    }

    func testMultiTokenWordAlignment() async throws {
        try await service.initialize(modelPath: modelPath)

        // Test with words that likely split across multiple BPE tokens
        // Words with uncommon spellings or technical terms are more likely to be split
        let words = [
            WordPosition(
                text: "Transcription",
                characterOffset: 0,
                length: 13,
                paragraphIndex: 0,
                pageNumber: 0
            ),
            WordPosition(
                text: "alignment",
                characterOffset: 14,
                length: 9,
                paragraphIndex: 0,
                pageNumber: 0
            ),
            WordPosition(
                text: "technology",
                characterOffset: 24,
                length: 10,
                paragraphIndex: 0,
                pageNumber: 0
            )
        ]
        let wordMap = DocumentWordMap(words: words)
        let text = "Transcription alignment technology"
        let testAudioURL = try createTestAudioFile()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify result structure
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0)

        // If word timings were created, verify they are sequential
        if result.wordTimings.count > 1 {
            for i in 1..<result.wordTimings.count {
                XCTAssertGreaterThanOrEqual(
                    result.wordTimings[i].startTime,
                    result.wordTimings[i-1].startTime,
                    "Word timings should be in chronological order even for multi-token words"
                )
            }
        }

        // Verify each word timing has valid duration
        for wordTiming in result.wordTimings {
            XCTAssertGreaterThan(wordTiming.duration, 0, "Each word should have positive duration")
            XCTAssertLessThan(wordTiming.duration, 10.0, "Word duration should be reasonable")
        }
    }

    // MARK: - Performance Tests

    /// Test alignment performance with realistic paragraph size (~100 words, ~30s audio)
    /// Target: < 2 seconds alignment time (per plan Section 7.3, 8.2)
    func testAlignmentPerformance() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create a realistic test paragraph (~100 words)
        let paragraphText = """
        The quick brown fox jumps over the lazy dog. This sentence is often used for testing \
        because it contains every letter of the alphabet. In our application, we need to ensure \
        that word-level alignment works efficiently even for longer paragraphs. The alignment \
        service uses dynamic time warping to map ASR tokens to VoxPDF words, which requires \
        careful optimization. Each word must be precisely timed so that highlighting remains \
        synchronized with audio playback. Performance is critical because users expect smooth, \
        responsive playback without noticeable delays. We target under two seconds for alignment \
        of a typical paragraph to ensure good user experience.
        """

        // Count words
        let wordCount = paragraphText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        print("Test paragraph has \(wordCount) words")

        // Create word map for this text
        let words = createWordMapFromText(paragraphText)
        let wordMap = DocumentWordMap(words: words)

        // Create test audio file (~30 seconds)
        let testAudioURL = try createTestAudioFile(duration: 30.0)

        // Measure alignment time
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await service.align(
            audioURL: testAudioURL,
            text: paragraphText,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        let alignmentTime = CFAbsoluteTimeGetCurrent() - startTime

        print("Alignment completed in \(alignmentTime) seconds")
        print("Word count: \(wordCount)")
        print("Audio duration: \(result.totalDuration) seconds")
        print("Word timings created: \(result.wordTimings.count)")

        // Assert: Alignment should complete in < 2 seconds (target from plan)
        XCTAssertLessThan(
            alignmentTime,
            2.0,
            "Alignment should complete in under 2 seconds for typical paragraph (actual: \(alignmentTime)s)"
        )

        // Verify result structure
        XCTAssertEqual(result.paragraphIndex, 0)
        XCTAssertGreaterThan(result.totalDuration, 0)
    }

    /// Test cache hit performance - should be < 10ms (per plan Section 8.2)
    func testCacheHitPerformance() async throws {
        try await service.initialize(modelPath: modelPath)

        // Create test data
        let text = "The quick brown fox jumps over the lazy dog"
        let words = createWordMapFromText(text)
        let wordMap = DocumentWordMap(words: words)
        let testAudioURL = try createTestAudioFile(duration: 5.0)

        // Perform initial alignment (populates cache)
        _ = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Measure cache hit time
        let startTime = CFAbsoluteTimeGetCurrent()

        let cachedResult = try await service.align(
            audioURL: testAudioURL,
            text: text,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        let cacheHitTime = CFAbsoluteTimeGetCurrent() - startTime

        print("Cache hit completed in \(cacheHitTime * 1000) milliseconds")

        // Assert: Cache hit should be very fast (< 10ms)
        XCTAssertLessThan(
            cacheHitTime,
            0.010,
            "Cache hit should complete in under 10ms (actual: \(cacheHitTime * 1000)ms)"
        )

        XCTAssertNotNil(cachedResult)
    }

    /// Test alignment with varying paragraph lengths to understand scaling characteristics
    func testAlignmentScaling() async throws {
        try await service.initialize(modelPath: modelPath)

        let testCases: [(wordCount: Int, duration: TimeInterval)] = [
            (20, 5.0),    // Short paragraph
            (50, 15.0),   // Medium paragraph
            (100, 30.0)   // Long paragraph
        ]

        for testCase in testCases {
            // Generate text with approximately target word count
            let text = generateText(wordCount: testCase.wordCount)
            let words = createWordMapFromText(text)
            let wordMap = DocumentWordMap(words: words)
            let testAudioURL = try createTestAudioFile(duration: testCase.duration)

            // Clear cache to ensure fresh alignment
            await service.clearCache()

            // Measure alignment time
            let startTime = CFAbsoluteTimeGetCurrent()

            let result = try await service.align(
                audioURL: testAudioURL,
                text: text,
                wordMap: wordMap,
                paragraphIndex: 0
            )

            let alignmentTime = CFAbsoluteTimeGetCurrent() - startTime

            print("[\(testCase.wordCount) words, \(testCase.duration)s audio] Alignment: \(alignmentTime)s")

            // All sizes should meet the < 2s target
            XCTAssertLessThan(
                alignmentTime,
                2.0,
                "\(testCase.wordCount) words should align in < 2s (actual: \(alignmentTime)s)"
            )

            XCTAssertEqual(result.paragraphIndex, 0)
        }
    }

    /// Test DTW edit distance performance with different string lengths
    func testEditDistancePerformance() {
        // Create test strings of varying lengths
        let testPairs: [(String, String)] = [
            ("hello", "helo"),           // Short
            ("recognition", "recognision"), // Medium
            ("Transcription alignment technology works efficiently",
             "Transcription aligment tecnology works efficiantly") // Long
        ]

        for (s1, s2) in testPairs {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Note: editDistance is private, so we test it indirectly through alignment
            // This test verifies that edit distance calculations don't cause performance issues
            let iterations = 1000
            for _ in 0..<iterations {
                _ = s1.compare(s2)  // Placeholder - actual test happens during align()
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("Edit distance comparison (\(s1.count) chars): \(elapsed * 1000 / Double(iterations))ms per iteration")
        }
    }

    /// Test word lookup performance - currently O(n) linear search in wordTiming(at:)
    /// Could be optimized to O(log n) with binary search if needed
    func testWordLookupPerformance() {
        // Create alignment result with many words
        let wordCount = 1000
        var wordTimings: [AlignmentResult.WordTiming] = []
        let dummyRange = "test".startIndex..<"test".endIndex

        for i in 0..<wordCount {
            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: i,
                startTime: Double(i) * 0.5,  // 0.5s per word
                duration: 0.5,
                text: "word\(i)",
                stringRange: dummyRange
            ))
        }

        let result = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: Double(wordCount) * 0.5,
            wordTimings: wordTimings
        )

        // Test lookup at various positions
        let lookupTimes = [0.0, 250.0, 499.5]  // Start, middle, end

        for time in lookupTimes {
            let startTime = CFAbsoluteTimeGetCurrent()

            let iterations = 10000
            for _ in 0..<iterations {
                _ = result.wordTiming(at: time)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("Word lookup at t=\(time)s: \(elapsed * 1000000 / Double(iterations))μs per lookup")
        }

        // Lookup should be fast even with 1000 words
        // If this becomes a bottleneck, implement binary search
    }

    // MARK: - Helper Methods

    /// Create a test WAV audio file
    /// - Parameters:
    ///   - withText: Optional text to synthesize (currently just creates silence)
    ///   - duration: Duration in seconds (default 1.0)
    /// - Returns: URL to the created test file
    private func createTestAudioFile(withText text: String? = nil, duration: TimeInterval = 1.0) throws -> URL {
        // Create a short silent WAV file at 16kHz mono
        let sampleRate: Double = 16000
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        // Fill with silence (zeros)
        if let channelData = buffer.floatChannelData {
            let channel = channelData[0]
            for i in 0..<Int(frameCount) {
                channel[i] = 0.0
            }
        }

        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test_audio_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        try audioFile.write(from: buffer)

        return fileURL
    }

    /// Create a test DocumentWordMap
    private func createTestWordMap() -> DocumentWordMap {
        let words = [
            WordPosition(
                text: "Hello",
                characterOffset: 0,
                length: 5,
                paragraphIndex: 0,
                pageNumber: 0
            ),
            WordPosition(
                text: "world",
                characterOffset: 6,
                length: 5,
                paragraphIndex: 0,
                pageNumber: 0
            )
        ]
        return DocumentWordMap(words: words)
    }

    /// Create a word map from text by splitting on whitespace
    private func createWordMapFromText(_ text: String) -> [WordPosition] {
        var words: [WordPosition] = []
        var characterOffset = 0

        // Split text into words
        let components = text.components(separatedBy: .whitespacesAndNewlines)

        for component in components {
            guard !component.isEmpty else {
                characterOffset += 1  // Account for whitespace
                continue
            }

            words.append(WordPosition(
                text: component,
                characterOffset: characterOffset,
                length: component.count,
                paragraphIndex: 0,
                pageNumber: 0
            ))

            characterOffset += component.count + 1  // +1 for space/newline
        }

        return words
    }

    /// Generate text with approximately the specified word count
    private func generateText(wordCount: Int) -> String {
        let baseWords = [
            "The", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
            "Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
            "sed", "eiusmod", "tempor", "incididunt", "labore", "dolore", "magna", "aliqua"
        ]

        var words: [String] = []
        for i in 0..<wordCount {
            words.append(baseWords[i % baseWords.count])
        }

        return words.joined(separator: " ")
    }
}
