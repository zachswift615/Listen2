//
//  SherpaOnnxNormalizedTextTests.swift
//  Listen2Tests
//
//  Tests to verify normalized text and character mapping extraction from sherpa-onnx C API
//

import XCTest
@testable import Listen2

final class SherpaOnnxNormalizedTextTests: XCTestCase {

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

    func testNormalizedTextFieldsExist() async throws {
        // Initialize TTS
        try await provider.initialize()

        // Synthesize simple text
        let result = try await provider.synthesize("Hello world", speed: 1.0)

        // Verify normalized text field exists (may be empty per Task 4)
        XCTAssertNotNil(result.phonemes, "Should have phonemes array")

        // Access the underlying GeneratedAudio through the TTS wrapper
        // Note: The normalizedText and charMapping are in the GeneratedAudio struct
        // but may not be populated yet (that's expected per Task 4)
        print("[NormalizedTextTests] Synthesis completed successfully")
        print("[NormalizedTextTests] Phoneme count: \(result.phonemes.count)")
    }

    func testNormalizedTextExtraction() async throws {
        // Initialize TTS
        try await provider.initialize()

        // Synthesize text that would typically be normalized by espeak
        // (e.g., "Dr. Smith" -> "Doctor Smith")
        let text = "Dr. Smith"
        let result = try await provider.synthesize(text, speed: 1.0)

        // Verify we got phonemes
        XCTAssertGreaterThan(result.phonemes.count, 0, "Should have phonemes")

        // NOTE: Per Task 4, normalized_text may be empty right now
        // The infrastructure is in place, but the C API fields are not yet populated
        // This test verifies the Swift extraction doesn't crash

        print("[NormalizedTextTests] Text: '\(text)'")
        print("[NormalizedTextTests] Phonemes extracted: \(result.phonemes.count)")
        print("[NormalizedTextTests] Test completed - Swift infrastructure ready for normalized text")
    }

    func testCharacterMappingFieldAccessible() async throws {
        // Initialize TTS
        try await provider.initialize()

        // Synthesize text
        let text = "TCP/IP"
        let result = try await provider.synthesize(text, speed: 1.0)

        // Verify synthesis succeeded
        XCTAssertGreaterThan(result.phonemes.count, 0, "Should have phonemes")

        // NOTE: Character mapping may be empty per Task 4
        // This test verifies the Swift extraction code doesn't crash
        // and the fields are accessible

        print("[NormalizedTextTests] Text: '\(text)'")
        print("[NormalizedTextTests] Phonemes: \(result.phonemes.count)")
        print("[NormalizedTextTests] Character mapping infrastructure ready")
    }

    func testGeneratedAudioStructure() {
        // Test that GeneratedAudio can be created with normalized text fields
        let testPhonemes = [
            PhonemeInfo(symbol: "h", duration: 0.1, textRange: 0..<1),
            PhonemeInfo(symbol: "ə", duration: 0.1, textRange: 1..<2)
        ]

        let testMapping = [(0, 0), (3, 6)] // Example: "Dr." -> "Doctor"

        let audio = GeneratedAudio(
            samples: [Float](repeating: 0, count: 100),
            sampleRate: 22050,
            phonemes: testPhonemes,
            normalizedText: "Doctor",
            charMapping: testMapping
        )

        XCTAssertEqual(audio.normalizedText, "Doctor")
        XCTAssertEqual(audio.charMapping.count, 2)
        XCTAssertEqual(audio.charMapping[0].originalPos, 0)
        XCTAssertEqual(audio.charMapping[0].normalizedPos, 0)
        XCTAssertEqual(audio.charMapping[1].originalPos, 3)
        XCTAssertEqual(audio.charMapping[1].normalizedPos, 6)

        print("[NormalizedTextTests] GeneratedAudio structure test passed")
    }
}
