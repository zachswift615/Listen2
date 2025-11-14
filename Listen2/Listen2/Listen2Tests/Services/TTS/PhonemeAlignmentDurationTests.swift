//
//  PhonemeAlignmentDurationTests.swift
//  Listen2Tests
//
//  Tests to verify PhonemeAlignmentService uses real phoneme durations
//

import XCTest
@testable import Listen2

final class PhonemeAlignmentDurationTests: XCTestCase {

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
        alignmentService = nil
        provider = nil
        voiceManager = nil
        try super.tearDownWithError()
    }

    func testAlignmentWithRealDurations() async throws {
        try await provider.initialize()

        // Synthesize and get phonemes with REAL durations
        let text = "Dr. Smith's office"
        let synthesis = try await provider.synthesize(text, speed: 1.0)

        // Verify phonemes have real durations
        XCTAssertTrue(synthesis.phonemes.allSatisfy { $0.duration > 0 })

        // Create alignment (no wordMap for this test)
        let result = try await alignmentService.align(
            phonemes: synthesis.phonemes,
            text: text,
            wordMap: nil,
            paragraphIndex: 0
        )

        // Verify alignment used REAL durations
        let totalDuration = result.totalDuration
        let estimatedDuration = Double(synthesis.phonemes.count) * 0.05

        print("[Alignment] Real duration: \(totalDuration)s")
        print("[Alignment] Estimated (50ms): \(estimatedDuration)s")

        // Real durations should produce different total
        XCTAssertNotEqual(totalDuration, estimatedDuration, accuracy: 0.1)

        // Word timings should exist
        XCTAssertGreaterThan(result.wordTimings.count, 0)

        // Each word should have reasonable duration
        for timing in result.wordTimings {
            XCTAssertGreaterThan(timing.duration, 0.01, "Word '\(timing.text)' has suspiciously short duration")
            XCTAssertLessThan(timing.duration, 2.0, "Word '\(timing.text)' has suspiciously long duration")
        }
    }
}
