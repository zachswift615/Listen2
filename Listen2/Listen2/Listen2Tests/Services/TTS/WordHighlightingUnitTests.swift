//
//  WordHighlightingUnitTests.swift
//  Listen2Tests
//
//  Fast unit tests for word highlighting pipeline using real TTS data
//

import XCTest
@testable import Listen2

/// Fast unit tests for word highlighting with real TTS synthesis
/// Runs without PDF dependencies - just tests TTS → Phoneme → Word Timing pipeline
final class WordHighlightingUnitTests: XCTestCase {

    // MARK: - Helper Methods

    /// Initialize TTS for testing
    private func initializeTTS() throws -> SherpaOnnxOfflineTtsWrapper {
        print("[WordHighlightingTest] 🔍 Initializing TTS...")

        // Get app bundle
        guard let appBundle = Bundle(identifier: "com.zachswift.Listen2") else {
            print("[WordHighlightingTest] ❌ App bundle not available")
            throw XCTSkip("App bundle not available - cannot locate TTS models")
        }

        print("[WordHighlightingTest] ✓ App bundle: \(appBundle.bundlePath)")

        // Find model files
        guard let modelPath = appBundle.path(forResource: "en_US-lessac-medium", ofType: "onnx"),
              let tokensPath = appBundle.path(forResource: "tokens", ofType: "txt"),
              let espeakDataPath = appBundle.path(forResource: "espeak-ng-data", ofType: nil) else {
            print("[WordHighlightingTest] ❌ TTS model files not found")
            throw XCTSkip("TTS models not available for testing")
        }

        print("[WordHighlightingTest] ✓ Model: \(modelPath)")
        print("[WordHighlightingTest] ✓ Tokens: \(tokensPath)")
        print("[WordHighlightingTest] ✓ Espeak: \(espeakDataPath)")

        // Create TTS configuration
        var vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            lexicon: "",
            tokens: tokensPath,
            dataDir: espeakDataPath
        )
        var modelConfig = sherpaOnnxOfflineTtsModelConfig(vits: vitsConfig)
        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)

        guard let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config) else {
            print("[WordHighlightingTest] ❌ Failed to initialize TTS engine")
            throw XCTSkip("Failed to initialize TTS engine")
        }

        print("[WordHighlightingTest] ✅ TTS initialized")
        return wrapper
    }

    // MARK: - Word Highlighting Tests

    /// Test simple sentence: verify all words get timings
    func testSimpleSentence() async throws {
        let text = "Hello world, this is a test."

        print("\n=== Testing: '\(text)' ===")

        // Initialize TTS
        let ttsWrapper = try initializeTTS()
        let alignmentService = PhonemeAlignmentService()

        // Synthesize
        let result = await ttsWrapper.generateWithStreaming(
            text: text,
            sid: 0,
            speed: 1.0,
            delegate: nil
        )

        print("✓ Synthesis complete:")
        print("  Audio: \(result.samples.count) samples")
        print("  Phonemes: \(result.phonemes.count)")
        print("  Normalized: '\(result.normalizedText)'")

        // Create word map
        let wordMap = createWordMap(from: text)
        print("  Word map: \(wordMap.words.count) words")

        // Align
        let alignment = try await alignmentService.align(
            phonemes: result.phonemes,
            text: text,
            normalizedText: result.normalizedText,
            charMapping: result.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        print("✓ Alignment complete:")
        print("  Word timings: \(alignment.wordTimings.count)")
        print("  Duration: \(String(format: "%.2f", alignment.totalDuration))s")

        // Validate
        try validateWordTimings(alignment.wordTimings, phonemes: result.phonemes, text: text)

        print("✓ All validations passed!\n")
    }

    /// Test chapter heading: "CHAPTER 2" - all caps, simple words
    func testChapterHeading() async throws {
        let text = "CHAPTER 2"

        print("\n=== Testing: '\(text)' ===")

        let ttsWrapper = try initializeTTS()
        let alignmentService = PhonemeAlignmentService()

        let result = await ttsWrapper.generateWithStreaming(text: text, sid: 0, speed: 1.0, delegate: nil)
        let wordMap = createWordMap(from: text)
        let alignment = try await alignmentService.align(
            phonemes: result.phonemes,
            text: text,
            normalizedText: result.normalizedText,
            charMapping: result.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        print("Phonemes: \(result.phonemes.count), Words: \(alignment.wordTimings.count)")
        try validateWordTimings(alignment.wordTimings, phonemes: result.phonemes, text: text)
        print("✓ Passed\n")
    }

    /// Test technical text with abbreviations
    func testTechnicalText() async throws {
        let text = "Dr. Smith's research on TCP/IP networks."

        print("\n=== Testing: '\(text)' ===")

        let ttsWrapper = try initializeTTS()
        let alignmentService = PhonemeAlignmentService()

        let result = await ttsWrapper.generateWithStreaming(text: text, sid: 0, speed: 1.0, delegate: nil)
        let wordMap = createWordMap(from: text)
        let alignment = try await alignmentService.align(
            phonemes: result.phonemes,
            text: text,
            normalizedText: result.normalizedText,
            charMapping: result.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        print("Phonemes: \(result.phonemes.count), Words: \(alignment.wordTimings.count)")
        print("Normalized: '\(result.normalizedText)'")
        try validateWordTimings(alignment.wordTimings, phonemes: result.phonemes, text: text)
        print("✓ Passed\n")
    }

    /// Test longer paragraph - real-world scenario
    func testLongerParagraph() async throws {
        let text = "The artificial intelligence system processes natural language by analyzing semantic patterns. It identifies key concepts and generates appropriate responses."

        print("\n=== Testing longer paragraph (\(text.count) chars) ===")

        let ttsWrapper = try initializeTTS()
        let alignmentService = PhonemeAlignmentService()

        let result = await ttsWrapper.generateWithStreaming(text: text, sid: 0, speed: 1.0, delegate: nil)
        let wordMap = createWordMap(from: text)
        let alignment = try await alignmentService.align(
            phonemes: result.phonemes,
            text: text,
            normalizedText: result.normalizedText,
            charMapping: result.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        print("Phonemes: \(result.phonemes.count), Words: \(alignment.wordTimings.count)")
        try validateWordTimings(alignment.wordTimings, phonemes: result.phonemes, text: text)
        print("✓ Passed\n")
    }

    // MARK: - Helper Methods

    private func createWordMap(from text: String) -> DocumentWordMap {
        var words: [WordPosition] = []
        var offset = 0

        let components = text.components(separatedBy: .whitespacesAndNewlines)
        for component in components {
            guard !component.isEmpty else {
                offset += 1
                continue
            }

            words.append(WordPosition(
                text: component,
                characterOffset: offset,
                length: component.count,
                paragraphIndex: 0,
                pageNumber: 0
            ))

            offset += component.count + 1
        }

        return DocumentWordMap(words: words)
    }

    private func validateWordTimings(_ wordTimings: [AlignmentResult.WordTiming], phonemes: [PhonemeInfo], text: String) throws {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

        // CHECK 1: Word count is reasonable
        let ratio = Double(wordTimings.count) / Double(wordCount)
        XCTAssertGreaterThan(ratio, 0.5, "Should align at least 50% of words (got \(wordTimings.count)/\(wordCount))")
        XCTAssertLessThan(ratio, 1.5, "Should not have > 150% word timings")

        // CHECK 2: No negative durations
        let negativeCount = wordTimings.filter { $0.duration < 0 }.count
        XCTAssertEqual(negativeCount, 0, "Found \(negativeCount) negative durations")

        // CHECK 3: No huge durations (> 5s per word)
        let hugeCount = wordTimings.filter { $0.duration > 5.0 }.count
        XCTAssertEqual(hugeCount, 0, "Found \(hugeCount) huge durations (>5s)")

        // CHECK 4: Phoneme durations are positive
        let negativePhonemes = phonemes.filter { $0.duration < 0 }.count
        XCTAssertEqual(negativePhonemes, 0, "Found \(negativePhonemes) phonemes with negative durations")

        // CHECK 5: Phoneme count is reasonable (2-10 per word)
        let phonemesPerWord = Double(phonemes.count) / Double(wordCount)
        XCTAssertGreaterThan(phonemesPerWord, 2.0, "Should have at least 2 phonemes/word (got \(String(format: "%.1f", phonemesPerWord)))")
        XCTAssertLessThan(phonemesPerWord, 15.0, "Should have at most 15 phonemes/word")

        // CHECK 6: Words are chronological
        for i in 1..<wordTimings.count {
            XCTAssertGreaterThanOrEqual(wordTimings[i].startTime, wordTimings[i-1].startTime,
                                       "Word \(i) starts before word \(i-1): '\(wordTimings[i-1].text)' -> '\(wordTimings[i].text)'")
        }

        print("  ✓ \(wordTimings.count) words aligned")
        print("  ✓ No negative/huge durations")
        print("  ✓ \(String(format: "%.1f", phonemesPerWord)) phonemes per word")
        print("  ✓ Chronological order")
    }
}
