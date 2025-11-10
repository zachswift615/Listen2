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

    // MARK: - Helper Methods

    /// Create a test WAV audio file
    /// - Parameter withText: Optional text to synthesize (currently just creates silence)
    /// - Returns: URL to the created test file
    private func createTestAudioFile(withText text: String? = nil) throws -> URL {
        // Create a short silent WAV file at 16kHz mono
        let sampleRate: Double = 16000
        let duration: Double = 1.0
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
}
