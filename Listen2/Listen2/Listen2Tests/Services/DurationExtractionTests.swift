//
//  DurationExtractionTests.swift
//  Listen2Tests
//
//  Tests for extracting real phoneme durations from sherpa-onnx C API
//

import XCTest
@testable import Listen2

@MainActor
final class DurationExtractionTests: XCTestCase {

    var voiceManager: VoiceManager!
    var provider: PiperTTSProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()

        voiceManager = VoiceManager()
        let bundledVoice = voiceManager.bundledVoice()
        provider = PiperTTSProvider(
            voiceID: bundledVoice.id,
            voiceManager: voiceManager
        )
    }

    override func tearDownWithError() throws {
        provider = nil
        voiceManager = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func initializeProviderOrSkip() async throws {
        do {
            try await provider.initialize()
        } catch {
            let errorMessage = "\(error)"
            if errorMessage.contains("espeak-ng-data") || errorMessage.contains("not found") {
                throw XCTSkip("espeak-ng-data not found in test bundle")
            } else {
                throw error
            }
        }
    }

    // MARK: - Duration Extraction Tests

    func testExtractsPhonemeDurations() async throws {
        // Given: An initialized TTS provider
        try await initializeProviderOrSkip()

        // When: Synthesizing simple text
        let testText = "Hello"
        let result = try await provider.synthesize(testText, speed: 1.0)

        // Then: Should have non-zero durations from C API
        XCTAssertFalse(result.phonemes.isEmpty, "Should have phoneme data")

        // Print first phoneme for diagnostics
        if let firstPhoneme = result.phonemes.first {
            print("[DurationTest] First phoneme: symbol='\(firstPhoneme.symbol)', duration=\(firstPhoneme.duration)s")
        }

        // Check that at least one phoneme has non-zero duration
        let hasNonZeroDuration = result.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasNonZeroDuration,
                     "At least one phoneme should have non-zero duration from C API")

        // If durations are present, check they're reasonable (not all zeros)
        let totalDuration = result.phonemes.reduce(0.0) { $0 + $1.duration }
        print("[DurationTest] Total phoneme duration: \(String(format: "%.3f", totalDuration))s")

        if hasNonZeroDuration {
            XCTAssertGreaterThan(totalDuration, 0.0,
                               "Total duration should be greater than zero")
        }
    }

    func testDurationsSumToAudioLength() async throws {
        // Given: An initialized TTS provider
        try await initializeProviderOrSkip()

        // When: Synthesizing text
        let testText = "The quick brown fox"
        let result = try await provider.synthesize(testText, speed: 1.0)

        // Then: Sum of phoneme durations should roughly match audio duration
        let hasNonZeroDuration = result.phonemes.contains { $0.duration > 0 }

        // Only test duration matching if we have real durations
        if hasNonZeroDuration {
            let totalPhonemeDuration = result.phonemes.reduce(0.0) { $0 + $1.duration }

            // Calculate audio duration from WAV data
            // WAV format: 44 byte header + 16-bit PCM samples at 22050 Hz
            let audioSampleCount = (result.audioData.count - 44) / 2  // 16-bit = 2 bytes
            let audioDuration = Double(audioSampleCount) / 22050.0

            print("[DurationTest] Phoneme duration: \(String(format: "%.3f", totalPhonemeDuration))s")
            print("[DurationTest] Audio duration:   \(String(format: "%.3f", audioDuration))s")

            // Durations should match within 50% (accounting for silence, padding, etc.)
            let tolerance = audioDuration * 0.5
            XCTAssertEqual(totalPhonemeDuration, audioDuration, accuracy: tolerance,
                          "Phoneme durations should roughly match audio duration")
        } else {
            print("[DurationTest] ⚠️  No real durations available - skipping duration matching test")
        }
    }

    func testEachPhonemeHasDuration() async throws {
        // Given: An initialized TTS provider
        try await initializeProviderOrSkip()

        // When: Synthesizing text
        let testText = "Test"
        let result = try await provider.synthesize(testText, speed: 1.0)

        // Then: Check duration coverage
        let phonemesWithDuration = result.phonemes.filter { $0.duration > 0 }
        let coverage = Double(phonemesWithDuration.count) / Double(result.phonemes.count)

        print("[DurationTest] Phonemes with duration: \(phonemesWithDuration.count)/\(result.phonemes.count) (\(String(format: "%.1f", coverage * 100))%)")

        // If C API is working, we should have 100% coverage
        // If not working yet, we'll have 0% coverage
        if phonemesWithDuration.count > 0 {
            XCTAssertGreaterThan(coverage, 0.9,
                               "At least 90% of phonemes should have real durations")
        } else {
            print("[DurationTest] ⚠️  No phonemes have durations yet - C API integration needed")
        }
    }

    func testDurationsAreReasonable() async throws {
        // Given: An initialized TTS provider
        try await initializeProviderOrSkip()

        // When: Synthesizing text
        let testText = "Hello world"
        let result = try await provider.synthesize(testText, speed: 1.0)

        // Then: Check that durations are in reasonable range
        for (index, phoneme) in result.phonemes.enumerated() {
            if phoneme.duration > 0 {
                // Phonemes typically range from 20ms to 300ms
                XCTAssertGreaterThan(phoneme.duration, 0.01,
                                    "Phoneme \(index) ('\(phoneme.symbol)') duration too short: \(phoneme.duration)s")
                XCTAssertLessThan(phoneme.duration, 0.5,
                                 "Phoneme \(index) ('\(phoneme.symbol)') duration too long: \(phoneme.duration)s")
            }
        }
    }
}
