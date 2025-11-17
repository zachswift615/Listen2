//
//  MinimalTest.swift
//  Listen2Tests
//
//  Minimal test for word highlighting diagnostic trace
//

import XCTest
@testable import Listen2

/// Minimal test to trace "CHAPTER 2" through the entire pipeline
final class MinimalTest: XCTestCase {

    func testChapter2Synthesis() async throws {
        print("\n\n")
        print(String(repeating: "=", count: 80))
        print("DIAGNOSTIC TEST: Synthesizing 'CHAPTER 2'")
        print(String(repeating: "=", count: 80))
        print("\n")

        // Get app bundle
        guard let appBundle = Bundle(identifier: "com.zachswift.Listen2") else {
            throw XCTSkip("Could not locate app bundle")
        }

        // Initialize voice manager
        let voiceManager = VoiceManager(bundle: appBundle)

        // Get Lessac voice
        let allVoices = voiceManager.availableVoices()
        guard let lessacVoice = allVoices.first(where: {
            $0.name.lowercased().contains("lessac")
        }) else {
            throw XCTSkip("Lessac voice not found")
        }

        print("[Test] Using voice: \(lessacVoice.name)")

        // Initialize TTS provider
        let ttsProvider = PiperTTSProvider(
            voiceID: lessacVoice.id,
            voiceManager: voiceManager
        )

        try await ttsProvider.initialize()

        // Synthesize "CHAPTER 2"
        let testText = "CHAPTER 2"
        print("[Test] Synthesizing: '\(testText)'")
        print("\n" + String(repeating: "-", count: 80))

        let result = try await ttsProvider.synthesize(testText, speed: 1.0)

        print("\n" + String(repeating: "-", count: 80))
        print("[Test] Synthesis complete!")
        print("[Test] Audio bytes: \(result.audioData.count)")
        print("[Test] Phonemes: \(result.phonemes.count)")
        print("[Test] Normalized text: '\(result.normalizedText)'")

        // Basic validation
        XCTAssertGreaterThan(result.phonemes.count, 0, "Should have phonemes")
        XCTAssertGreaterThan(result.audioData.count, 0, "Should have audio")

        // Check for durations
        let hasDurations = result.phonemes.contains { $0.duration > 0 }
        print("[Test] Has durations: \(hasDurations)")

        if hasDurations {
            let totalDuration = result.phonemes.reduce(0.0) { $0 + $1.duration }
            print("[Test] Total duration: \(String(format: "%.3f", totalDuration))s")

            // Check for negative or huge durations
            let negativeDurations = result.phonemes.filter { $0.duration < 0 }
            let hugeDurations = result.phonemes.filter { $0.duration > 1.0 }

            XCTAssertEqual(negativeDurations.count, 0, "Should have no negative durations")
            XCTAssertLessThan(hugeDurations.count, result.phonemes.count / 10, "Should have < 10% huge durations")
        }

        print("\n")
        print(String(repeating: "=", count: 80))
        print("TEST COMPLETE - Review logs above for data flow trace")
        print(String(repeating: "=", count: 80))
        print("\n\n")
    }
}
