//
//  PhonemeAlignmentAbbreviationTests.swift
//  Listen2Tests
//
//  Tests for normalized text mapping in PhonemeAlignmentService
//  This verifies that VoxPDF words (original text) are correctly mapped to
//  phoneme positions (normalized text) using character mapping.
//

import XCTest
@testable import Listen2

class PhonemeAlignmentAbbreviationTests: XCTestCase {

    /// Test mapping "Dr." abbreviation to "Doctor" phonemes
    /// This is the CRITICAL test case from the plan - verifies the normalized text integration works
    func testDoctorAbbreviation() async throws {
        let service = PhonemeAlignmentService()

        // Original text from VoxPDF: "Dr. Smith"
        let originalText = "Dr. Smith"

        // Normalized by espeak: "Doctor Smith" (Dr. -> Doctor)
        let normalizedText = "Doctor Smith"

        // Character mapping: "Dr." (0-4 including space) -> "Doctor" (0-7 including space)
        // Note: espeak typically includes the space after abbreviations in the mapping
        let charMapping: [(Int, Int)] = [
            (0, 0),   // Start of "Dr." -> Start of "Doctor"
            (4, 7)    // After "Dr. " (position 4) -> After "Doctor " (position 7)
        ]

        // Phonemes with positions in NORMALIZED text (0-6 for "Doctor", 7-12 for "Smith")
        // These are realistic IPA phonemes for "Doctor Smith"
        let phonemes = [
            // "Doctor" phonemes (positions in normalized text)
            PhonemeInfo(symbol: "d", duration: 0.077, textRange: 0..<1),
            PhonemeInfo(symbol: "ɑ", duration: 0.054, textRange: 1..<2),
            PhonemeInfo(symbol: "k", duration: 0.065, textRange: 2..<3),
            PhonemeInfo(symbol: "t", duration: 0.042, textRange: 3..<4),
            PhonemeInfo(symbol: "ə", duration: 0.033, textRange: 4..<5),
            PhonemeInfo(symbol: "ɹ", duration: 0.056, textRange: 5..<6),
            // "Smith" phonemes (positions in normalized text)
            PhonemeInfo(symbol: "s", duration: 0.088, textRange: 7..<8),
            PhonemeInfo(symbol: "m", duration: 0.045, textRange: 8..<9),
            PhonemeInfo(symbol: "ɪ", duration: 0.039, textRange: 9..<10),
            PhonemeInfo(symbol: "θ", duration: 0.067, textRange: 10..<11)
        ]

        // VoxPDF word map (positions in ORIGINAL text)
        let wordMap = DocumentWordMap(
            words: [
                WordPosition(text: "Dr.", characterOffset: 0, length: 3, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "Smith", characterOffset: 4, length: 5, paragraphIndex: 0, pageNumber: 0)
            ]
        )

        // Call align with normalized text mapping
        let result = try await service.align(
            phonemes: phonemes,
            text: originalText,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify we got 2 word timings
        XCTAssertEqual(result.wordTimings.count, 2, "Should have 2 word timings")

        // Verify first word timing corresponds to "Dr." in original text
        let firstWord = result.wordTimings[0]
        XCTAssertEqual(firstWord.text, "Dr.", "First word should be 'Dr.'")
        XCTAssertEqual(firstWord.wordIndex, 0)

        // Verify timing is based on "Doctor" phonemes (6 phonemes)
        // Expected duration: sum of first 6 phonemes = 0.077 + 0.054 + 0.065 + 0.042 + 0.033 + 0.056 = 0.327s
        let expectedDuration = 0.077 + 0.054 + 0.065 + 0.042 + 0.033 + 0.056
        XCTAssertEqual(firstWord.duration, expectedDuration, accuracy: 0.001,
                      "Duration should match 'Doctor' phonemes")

        // Verify start time is 0
        XCTAssertEqual(firstWord.startTime, 0.0, accuracy: 0.001,
                      "First word should start at 0")

        // Verify second word is "Smith"
        let secondWord = result.wordTimings[1]
        XCTAssertEqual(secondWord.text, "Smith", "Second word should be 'Smith'")
        XCTAssertEqual(secondWord.wordIndex, 1)

        // Verify timing is based on "Smith" phonemes (4 phonemes)
        let expectedSmithDuration = 0.088 + 0.045 + 0.039 + 0.067
        XCTAssertEqual(secondWord.duration, expectedSmithDuration, accuracy: 0.001,
                      "Duration should match 'Smith' phonemes")

        // Verify start time follows "Doctor"
        XCTAssertEqual(secondWord.startTime, expectedDuration, accuracy: 0.001,
                      "Second word should start after 'Doctor'")

        print("✅ Abbreviation mapping works correctly: 'Dr.' -> 'Doctor' phonemes")
    }

    /// Test multiple abbreviations in sequence
    func testMultipleAbbreviations() async throws {
        let service = PhonemeAlignmentService()

        // Original: "Dr. Smith's office is on Main St."
        // Normalized: "Doctor Smith s office is on Main Street"
        let originalText = "Dr. Smith's office is on Main St."
        let normalizedText = "Doctor Smith s office is on Main Street"

        // Simplified character mapping for this test
        let charMapping: [(Int, Int)] = [
            (0, 0),      // "Dr." -> "Doctor"
            (4, 7),      // After "Dr. " -> After "Doctor "
            (10, 13),    // "Smith's" -> "Smith s"
            (32, 37)     // "St." -> "Street"
        ]

        // Create minimal phonemes for testing (just focusing on abbreviations)
        let phonemes = [
            // "Doctor" (0-6)
            PhonemeInfo(symbol: "d", duration: 0.05, textRange: 0..<6),
            // "Smith" (7-12)
            PhonemeInfo(symbol: "s", duration: 0.05, textRange: 7..<12),
            // "s" (13-14)
            PhonemeInfo(symbol: "s", duration: 0.02, textRange: 13..<14),
            // "office" (15-21)
            PhonemeInfo(symbol: "ɔ", duration: 0.05, textRange: 15..<21),
            // "is" (22-24)
            PhonemeInfo(symbol: "ɪ", duration: 0.03, textRange: 22..<24),
            // "on" (25-27)
            PhonemeInfo(symbol: "ɑ", duration: 0.03, textRange: 25..<27),
            // "Main" (28-32)
            PhonemeInfo(symbol: "m", duration: 0.04, textRange: 28..<32),
            // "Street" (33-39)
            PhonemeInfo(symbol: "s", duration: 0.06, textRange: 33..<39)
        ]

        // VoxPDF words in original text
        let wordMap = DocumentWordMap(
            words: [
                WordPosition(text: "Dr.", characterOffset: 0, length: 3, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "Smith's", characterOffset: 4, length: 7, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "office", characterOffset: 12, length: 6, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "is", characterOffset: 19, length: 2, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "on", characterOffset: 22, length: 2, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "Main", characterOffset: 25, length: 4, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "St.", characterOffset: 30, length: 3, paragraphIndex: 0, pageNumber: 0)
            ]
        )

        let result = try await service.align(
            phonemes: phonemes,
            text: originalText,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify all words were aligned
        XCTAssertEqual(result.wordTimings.count, 7, "Should have 7 word timings")

        // Verify abbreviations are in original form
        XCTAssertEqual(result.wordTimings[0].text, "Dr.")
        XCTAssertEqual(result.wordTimings[6].text, "St.")

        // Verify all words have valid timings
        for timing in result.wordTimings {
            XCTAssertGreaterThan(timing.duration, 0, "Word '\(timing.text)' should have positive duration")
            XCTAssertGreaterThanOrEqual(timing.startTime, 0, "Word '\(timing.text)' should have non-negative start time")
        }

        print("✅ Multiple abbreviations handled correctly")
    }

    /// Test edge case: empty character mapping (fallback behavior)
    func testEmptyCharMapping() async throws {
        let service = PhonemeAlignmentService()

        let originalText = "Hello world"
        let normalizedText = "Hello world"  // No normalization
        let charMapping: [(Int, Int)] = []  // Empty mapping

        let phonemes = [
            PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<5),
            PhonemeInfo(symbol: "w", duration: 0.05, textRange: 6..<11)
        ]

        let wordMap = DocumentWordMap(
            words: [
                WordPosition(text: "Hello", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
                WordPosition(text: "world", characterOffset: 6, length: 5, paragraphIndex: 0, pageNumber: 0)
            ]
        )

        // Should not crash with empty mapping
        let result = try await service.align(
            phonemes: phonemes,
            text: originalText,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        XCTAssertEqual(result.wordTimings.count, 2, "Should handle empty mapping gracefully")
        print("✅ Empty character mapping handled gracefully")
    }

    /// Test edge case: no word map (EPUB/clipboard fallback)
    func testNoWordMapFallback() async throws {
        let service = PhonemeAlignmentService()

        let originalText = "Dr. Smith"
        let normalizedText = "Doctor Smith"
        let charMapping: [(Int, Int)] = [(0, 0), (4, 7)]

        let phonemes = [
            PhonemeInfo(symbol: "d", duration: 0.05, textRange: 0..<6),
            PhonemeInfo(symbol: "s", duration: 0.05, textRange: 7..<12)
        ]

        // No word map - should fall back to espeak word grouping
        let result = try await service.align(
            phonemes: phonemes,
            text: originalText,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: nil,
            paragraphIndex: 0
        )

        // Should use normalized text for word extraction
        XCTAssertGreaterThan(result.wordTimings.count, 0, "Should extract words from normalized text")
        print("✅ Fallback to espeak word grouping works")
    }
}
