//
//  EndToEndTests.swift
//  Listen2Tests
//
//  End-to-end integration tests for premium word-level highlighting pipeline
//  Tests the complete flow: Piper TTS → phoneme extraction → normalization → alignment
//

import XCTest
@testable import Listen2

@MainActor
final class EndToEndTests: XCTestCase {

    var voiceManager: VoiceManager!
    var provider: PiperTTSProvider!
    var alignmentService: PhonemeAlignmentService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        voiceManager = VoiceManager()
        let bundledVoice = voiceManager.bundledVoice()

        provider = PiperTTSProvider(
            voiceID: bundledVoice.id,
            voiceManager: voiceManager
        )

        alignmentService = PhonemeAlignmentService()
    }

    override func tearDownWithError() throws {
        provider = nil
        voiceManager = nil
        alignmentService = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    /// Initialize provider or skip test if espeak-ng-data is missing
    private func initializeProviderOrSkip() async throws {
        do {
            try await provider.initialize()
        } catch {
            let errorMessage = "\(error)"
            if errorMessage.contains("espeak-ng-data") || errorMessage.contains("not found") {
                throw XCTSkip("espeak-ng-data not found in test bundle - requires Xcode project configuration")
            } else {
                throw error
            }
        }
    }

    // MARK: - End-to-End Pipeline Tests

    func testCompleteWordHighlightingPipeline_SimpleText() async throws {
        // Test the entire pipeline from synthesis to highlighting with simple text

        // Given: An initialized provider
        try await initializeProviderOrSkip()

        let testText = "Hello world"

        // When: Step 1 - Synthesize with Piper TTS
        let synthesisResult = try await provider.synthesize(testText, speed: 1.0)

        // Then: Verify we have phonemes
        XCTAssertFalse(synthesisResult.phonemes.isEmpty, "Should have phonemes from synthesis")
        print("✓ Synthesis complete: \(synthesisResult.phonemes.count) phonemes")

        // And: Verify we have real durations (not all zeros)
        let hasRealDurations = synthesisResult.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasRealDurations, "Should have real durations from w_ceil tensor")
        print("✓ Real phoneme durations present")

        // Log first few phoneme durations for verification
        for (i, phoneme) in synthesisResult.phonemes.prefix(5).enumerated() {
            print("   Phoneme[\(i)] '\(phoneme.symbol)' duration: \(String(format: "%.4f", phoneme.duration))s")
        }

        // When: Step 2 - Perform alignment
        let alignment = try await alignmentService.alignPremium(
            phonemes: synthesisResult.phonemes,
            displayText: testText,
            synthesizedText: synthesisResult.text,
            paragraphIndex: 0
        )

        // Then: Verify alignment quality
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should have word timings")
        print("✓ Alignment complete: \(alignment.wordTimings.count) words")

        // And: Verify expected words are present
        let words = alignment.wordTimings.map { $0.text }
        XCTAssertEqual(words.count, 2, "Should have exactly 2 words")
        XCTAssertEqual(words[0], "Hello", "First word should be 'Hello'")
        XCTAssertEqual(words[1], "world", "Second word should be 'world'")

        // And: Verify timing accuracy
        let totalDuration = alignment.totalDuration
        let audioDuration = calculateAudioDuration(samples: synthesisResult.audioData, sampleRate: synthesisResult.sampleRate)

        // Durations should match within 10% tolerance
        let tolerance = audioDuration * 0.1
        XCTAssertEqual(totalDuration, audioDuration, accuracy: tolerance,
                      "Total duration should match audio duration within 10%")

        print("✓ Timing validation:")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   Audio duration: \(String(format: "%.3f", audioDuration))s")
        print("   Difference: \(String(format: "%.1f", abs(totalDuration - audioDuration) / audioDuration * 100))%")

        // And: Verify word timings are reasonable
        for (i, timing) in alignment.wordTimings.enumerated() {
            XCTAssertGreaterThan(timing.duration, 0, "Word '\(timing.text)' should have non-zero duration")
            XCTAssertLessThan(timing.duration, 5.0, "Word '\(timing.text)' duration should be reasonable (<5s)")
            print("   Word[\(i)] '\(timing.text)' @ \(String(format: "%.3f", timing.startTime))s for \(String(format: "%.3f", timing.duration))s")
        }

        print("✅ Simple text E2E test PASSED")
    }

    func testCompleteWordHighlightingPipeline_TechnicalText() async throws {
        // Test pipeline with technical text containing abbreviations and contractions

        // Given: An initialized provider
        try await initializeProviderOrSkip()

        let testText = "Dr. Smith's TCP/IP research couldn't be more timely."

        // When: Synthesize with Piper TTS
        let synthesisResult = try await provider.synthesize(testText, speed: 1.0)

        // Then: Verify phonemes with real durations
        XCTAssertFalse(synthesisResult.phonemes.isEmpty, "Should have phonemes from synthesis")
        let hasRealDurations = synthesisResult.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasRealDurations, "Should have real durations from w_ceil tensor")
        print("✓ Synthesis complete: \(synthesisResult.phonemes.count) phonemes with real durations")

        // When: Perform premium alignment
        let alignment = try await alignmentService.alignPremium(
            phonemes: synthesisResult.phonemes,
            displayText: testText,
            synthesizedText: synthesisResult.text,
            paragraphIndex: 0
        )

        // Then: Verify critical technical terms are preserved
        let words = alignment.wordTimings.map { $0.text }
        print("✓ Aligned words: \(words)")

        // Note: The actual preservation of technical terms depends on normalization mapping
        // We verify the alignment succeeded and produced reasonable word count
        XCTAssertGreaterThan(words.count, 5, "Should have multiple words from technical text")

        // And: Verify no crashes or errors occurred with complex normalization
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should have word timings")

        // And: Verify timing accuracy
        let totalDuration = alignment.totalDuration
        let audioDuration = calculateAudioDuration(samples: synthesisResult.audioData, sampleRate: synthesisResult.sampleRate)
        let tolerance = audioDuration * 0.1

        XCTAssertEqual(totalDuration, audioDuration, accuracy: tolerance,
                      "Total duration should match audio duration within 10%")

        print("✓ Technical text timing:")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   Audio duration: \(String(format: "%.3f", audioDuration))s")
        print("   Word count: \(words.count)")

        // And: Verify all words have valid timings
        for timing in alignment.wordTimings {
            XCTAssertGreaterThan(timing.duration, 0, "Word '\(timing.text)' should have positive duration")
            XCTAssertGreaterThanOrEqual(timing.startTime, 0, "Word '\(timing.text)' should have non-negative start time")
        }

        print("✅ Technical text E2E test PASSED")
    }

    func testCompleteWordHighlightingPipeline_ComplexTechnical() async throws {
        // Test pipeline with highly complex technical content

        // Given: An initialized provider
        try await initializeProviderOrSkip()

        let testText = "The API's HTTP/2 protocol doesn't support IPv6 yet."

        // When: Synthesize and align
        let synthesisResult = try await provider.synthesize(testText, speed: 1.0)

        // Then: Verify synthesis succeeded
        XCTAssertFalse(synthesisResult.phonemes.isEmpty)
        let hasRealDurations = synthesisResult.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasRealDurations, "Should have real durations")

        // When: Align with premium method
        let alignment = try await alignmentService.alignPremium(
            phonemes: synthesisResult.phonemes,
            displayText: testText,
            synthesizedText: synthesisResult.text,
            paragraphIndex: 0
        )

        // Then: Verify alignment succeeded without crashes
        XCTAssertGreaterThan(alignment.wordTimings.count, 0, "Should produce word timings for complex text")

        let words = alignment.wordTimings.map { $0.text }
        print("✓ Complex technical words: \(words)")

        // And: Verify timing consistency
        let totalDuration = alignment.totalDuration
        let audioDuration = calculateAudioDuration(samples: synthesisResult.audioData, sampleRate: synthesisResult.sampleRate)

        // More lenient tolerance for complex text (15%)
        let tolerance = audioDuration * 0.15
        XCTAssertEqual(totalDuration, audioDuration, accuracy: tolerance,
                      "Complex text timing should be within 15% of audio duration")

        print("✓ Complex text validation:")
        print("   Phoneme count: \(synthesisResult.phonemes.count)")
        print("   Word count: \(words.count)")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   Audio duration: \(String(format: "%.3f", audioDuration))s")

        // And: Verify edge case handling (no crashes, no zero/negative durations)
        for timing in alignment.wordTimings {
            XCTAssertGreaterThan(timing.duration, 0, "Word '\(timing.text)' must have positive duration")
            XCTAssertLessThan(timing.duration, 10.0, "Word '\(timing.text)' duration should be reasonable")
        }

        print("✅ Complex technical E2E test PASSED")
    }

    func testRealPhonemeDurations() async throws {
        // Verify that we're getting real durations from w_ceil, not estimates

        // Given: An initialized provider
        try await initializeProviderOrSkip()

        let testText = "Testing real phoneme durations from Piper VITS model."

        // When: Synthesize
        let result = try await provider.synthesize(testText, speed: 1.0)

        // Then: All phonemes should have positive durations
        XCTAssertFalse(result.phonemes.isEmpty, "Should have phonemes")

        let allHavePositiveDurations = result.phonemes.allSatisfy { $0.duration > 0 }
        XCTAssertTrue(allHavePositiveDurations, "All phonemes should have positive durations")

        // And: Durations should vary (not all the same estimate like 0.05)
        let uniqueDurations = Set(result.phonemes.map { $0.duration })
        XCTAssertGreaterThan(uniqueDurations.count, 1, "Durations should vary (not constant estimates)")

        // And: Durations should be in reasonable range (0.01s to 0.5s per phoneme)
        for phoneme in result.phonemes {
            XCTAssertGreaterThan(phoneme.duration, 0.001, "Phoneme '\(phoneme.symbol)' duration too small")
            XCTAssertLessThan(phoneme.duration, 0.5, "Phoneme '\(phoneme.symbol)' duration too large")
        }

        // Log statistics
        let durations = result.phonemes.map { $0.duration }
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let minDuration = durations.min() ?? 0
        let maxDuration = durations.max() ?? 0

        print("✓ Real phoneme duration statistics:")
        print("   Count: \(result.phonemes.count)")
        print("   Average: \(String(format: "%.4f", avgDuration))s")
        print("   Min: \(String(format: "%.4f", minDuration))s")
        print("   Max: \(String(format: "%.4f", maxDuration))s")
        print("   Unique values: \(uniqueDurations.count)")

        print("✅ Real phoneme duration test PASSED")
    }

    func testAlignmentAccuracyMetrics() async throws {
        // Measure alignment accuracy for different text types

        // Given: An initialized provider
        try await initializeProviderOrSkip()

        let testCases: [(name: String, text: String, maxTolerancePercent: Double)] = [
            ("Simple", "Hello world", 5.0),
            ("Medium", "The quick brown fox jumps over the lazy dog", 8.0),
            ("Technical", "Dr. Smith's research on AI couldn't be better", 10.0)
        ]

        print("✓ Running accuracy tests on \(testCases.count) test cases...")

        for testCase in testCases {
            print("\n📊 Testing: \(testCase.name) - '\(testCase.text)'")

            // When: Synthesize and align
            let synthesis = try await provider.synthesize(testCase.text, speed: 1.0)
            let alignment = try await alignmentService.alignPremium(
                phonemes: synthesis.phonemes,
                displayText: testCase.text,
                synthesizedText: synthesis.text,
                paragraphIndex: 0
            )

            // Then: Measure accuracy
            let audioDuration = calculateAudioDuration(samples: synthesis.audioData, sampleRate: synthesis.sampleRate)
            let accuracyError = abs(alignment.totalDuration - audioDuration) / audioDuration * 100

            XCTAssertLessThan(accuracyError, testCase.maxTolerancePercent,
                            "Alignment accuracy for '\(testCase.name)' should be within \(testCase.maxTolerancePercent)%")

            print("   Words aligned: \(alignment.wordTimings.count)")
            print("   Duration match: \(String(format: "%.1f", 100 - accuracyError))% accurate")
            print("   Error: \(String(format: "%.2f", accuracyError))%")
            print("   ✓ PASS (within \(testCase.maxTolerancePercent)% tolerance)")
        }

        print("\n✅ All accuracy metrics PASSED")
    }

    // MARK: - Helper Methods

    /// Calculate audio duration from WAV data
    /// Assumes 16-bit PCM samples at the given sample rate
    private func calculateAudioDuration(samples audioData: Data, sampleRate: Int32) -> TimeInterval {
        // WAV header is 44 bytes, then comes PCM data
        guard audioData.count > 44 else { return 0 }

        let pcmDataSize = audioData.count - 44
        let bytesPerSample = 2 // 16-bit = 2 bytes
        let sampleCount = pcmDataSize / bytesPerSample

        return Double(sampleCount) / Double(sampleRate)
    }
}
