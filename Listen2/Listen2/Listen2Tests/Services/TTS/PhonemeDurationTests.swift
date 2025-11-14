//
//  PhonemeDurationTests.swift
//  Listen2Tests
//
//  Tests to verify w_ceil phoneme durations are extracted from Piper models
//

import XCTest
@testable import Listen2

final class PhonemeDurationTests: XCTestCase {

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

    func testWCeilExtraction() async throws {
        // Initialize TTS with lessac-high (w_ceil enabled)
        try await provider.initialize()

        // Synthesize test text
        let result = try await provider.synthesize("Hello world", speed: 1.0)

        // Verify we got phonemes
        XCTAssertGreaterThan(result.phonemes.count, 0, "Should have phonemes")

        // Verify phonemes have REAL durations (not 0)
        let hasDurations = result.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasDurations, "Phonemes should have real durations from w_ceil")

        // Log durations for inspection
        print("[PhonemeDurationTests] Phoneme durations:")
        for (i, phoneme) in result.phonemes.prefix(10).enumerated() {
            print("  [\(i)] '\(phoneme.symbol)' duration=\(phoneme.duration)s")
        }

        // Verify durations are reasonable (not 50ms estimates)
        let avgDuration = result.phonemes.map { $0.duration }.reduce(0, +) / Double(result.phonemes.count)
        print("[PhonemeDurationTests] Average phoneme duration: \(avgDuration)s")

        // Real durations should vary (not all 0.05s)
        let uniqueDurations = Set(result.phonemes.map { $0.duration })
        XCTAssertGreaterThan(uniqueDurations.count, 3, "Should have varied durations, not uniform 50ms")
    }

    func testCompareEstimatedVsRealDurations() async throws {
        // This test compares old behavior (50ms estimates) vs new (w_ceil)
        try await provider.initialize()

        let text = "The quick brown fox jumps over the lazy dog"
        let result = try await provider.synthesize(text, speed: 1.0)

        // Calculate what ESTIMATED duration would be (50ms per phoneme)
        let estimatedTotal = Double(result.phonemes.count) * 0.05

        // Calculate ACTUAL duration from w_ceil
        let actualTotal = result.phonemes.reduce(0.0) { $0 + $1.duration }

        print("[Compare] Text: '\(text)'")
        print("[Compare] Phoneme count: \(result.phonemes.count)")
        print("[Compare] Estimated total (50ms/phoneme): \(estimatedTotal)s")
        print("[Compare] Actual total (w_ceil): \(actualTotal)s")
        print("[Compare] Difference: \(abs(estimatedTotal - actualTotal))s")

        // Real durations should differ from 50ms estimates by at least 10%
        let percentDiff = abs(estimatedTotal - actualTotal) / estimatedTotal * 100
        XCTAssertGreaterThan(percentDiff, 10, "Real durations should differ significantly from 50ms estimates")
    }
}
