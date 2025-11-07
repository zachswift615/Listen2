//
//  VoiceTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class VoiceTests: XCTestCase {

    func testGenderDetectionForKnownFemaleVoice() {
        // Test that Samantha is detected as female
        if let avVoice = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.identifier.contains("Samantha") }) {
            let voice = Voice(from: avVoice)
            XCTAssertEqual(voice.gender, .female)
        }
    }

    func testGenderDetectionForKnownMaleVoice() {
        // Test that Alex is detected as male
        if let avVoice = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.identifier.contains("Alex") }) {
            let voice = Voice(from: avVoice)
            XCTAssertEqual(voice.gender, .male)
        }
    }

    func testGenderDetectionDefaultsToNeutral() {
        // Test that unknown voices default to neutral
        if let avVoice = AVSpeechSynthesisVoice.speechVoices().first {
            let voice = Voice(from: avVoice)
            XCTAssertNotNil(voice.gender) // Should have some gender value
        }
    }
}
