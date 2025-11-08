//
//  VoiceFilterManagerTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class VoiceFilterManagerTests: XCTestCase {

    func testFilterByLanguage() {
        let manager = VoiceFilterManager()

        // Create test voices
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { AVVoice(from: $0) }

        // Filter for English voices only
        manager.selectedLanguages = Set(voices.filter { $0.language.hasPrefix("en") }.map { $0.language })

        let filtered = manager.filteredVoices(Array(voices))

        XCTAssertGreaterThan(filtered.count, 0)
        XCTAssertTrue(filtered.allSatisfy { $0.language.hasPrefix("en") })
    }

    func testFilterByGender() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { AVVoice(from: $0) }

        manager.selectedGender = .female

        let filtered = manager.filteredVoices(Array(voices))

        if !filtered.isEmpty {
            XCTAssertTrue(filtered.allSatisfy { $0.gender == .female })
        }
    }

    func testFilterByBothLanguageAndGender() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(20)
            .map { AVVoice(from: $0) }

        manager.selectedLanguages = Set(voices.filter { $0.language.hasPrefix("en") }.map { $0.language })
        manager.selectedGender = .male

        let filtered = manager.filteredVoices(Array(voices))

        if !filtered.isEmpty {
            XCTAssertTrue(filtered.allSatisfy { $0.language.hasPrefix("en") })
            XCTAssertTrue(filtered.allSatisfy { $0.gender == .male })
        }
    }

    func testNoFilterReturnsAll() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { AVVoice(from: $0) }

        let filtered = manager.filteredVoices(Array(voices))

        XCTAssertEqual(filtered.count, voices.count)
    }
}
