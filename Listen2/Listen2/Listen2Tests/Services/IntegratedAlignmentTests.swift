//
//  IntegratedAlignmentTests.swift
//  Listen2Tests
//
//  Integration tests for premium word alignment combining:
//  - Real phoneme durations from w_ceil tensor (Task 6)
//  - Text normalization mapping (Task 7)
//  - Dynamic alignment engine (Task 8)
//

import XCTest
@testable import Listen2

class IntegratedAlignmentTests: XCTestCase {

    // MARK: - Basic Premium Alignment

    func testPremiumAlignmentWithRealDurations() async throws {
        let service = PhonemeAlignmentService()

        // Mock data with real durations from w_ceil
        // Simulating "Hello world" with realistic phoneme durations
        let phonemes = [
            // "Hello" - 4 phonemes
            PhonemeInfo(symbol: "h", duration: 0.045, textRange: 0..<5),
            PhonemeInfo(symbol: "ə", duration: 0.032, textRange: 0..<5),
            PhonemeInfo(symbol: "l", duration: 0.058, textRange: 0..<5),
            PhonemeInfo(symbol: "oʊ", duration: 0.091, textRange: 0..<5),
            // "world" - 4 phonemes
            PhonemeInfo(symbol: "w", duration: 0.048, textRange: 6..<11),
            PhonemeInfo(symbol: "ɝ", duration: 0.067, textRange: 6..<11),
            PhonemeInfo(symbol: "l", duration: 0.055, textRange: 6..<11),
            PhonemeInfo(symbol: "d", duration: 0.041, textRange: 6..<11)
        ]

        let displayText = "Hello world"
        let synthesizedText = "Hello world"  // No normalization in this case

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Verify we got 2 words
        XCTAssertEqual(result.wordTimings.count, 2, "Should have 2 words")

        // First word timing
        let firstWord = result.wordTimings[0]
        XCTAssertEqual(firstWord.text, "Hello")
        XCTAssertEqual(firstWord.startTime, 0, accuracy: 0.001)
        XCTAssertEqual(firstWord.duration, 0.226, accuracy: 0.001, "Hello duration = 0.045 + 0.032 + 0.058 + 0.091")

        // Second word timing
        let secondWord = result.wordTimings[1]
        XCTAssertEqual(secondWord.text, "world")
        XCTAssertEqual(secondWord.startTime, 0.226, accuracy: 0.001)
        XCTAssertEqual(secondWord.duration, 0.211, accuracy: 0.001, "world duration = 0.048 + 0.067 + 0.055 + 0.041")

        // Total duration should match sum of phoneme durations
        XCTAssertEqual(result.totalDuration, 0.437, accuracy: 0.001)
    }

    // MARK: - Text Normalization

    func testHandlesAbbreviations() async throws {
        let service = PhonemeAlignmentService()

        // Test with "Dr." -> "Doctor"
        let phonemes = createMockPhonemes(for: "Doctor Smith", wordDurations: [0.250, 0.180])
        let displayText = "Dr. Smith"
        let synthesizedText = "Doctor Smith"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map back to display words
        XCTAssertEqual(result.wordTimings.count, 2)
        XCTAssertEqual(result.wordTimings[0].text, "Dr.")
        XCTAssertEqual(result.wordTimings[1].text, "Smith")
    }

    func testHandlesPossessives() async throws {
        let service = PhonemeAlignmentService()

        // Test with "Smith's" -> "Smith s"
        let phonemes = createMockPhonemes(for: "Smith s office", wordDurations: [0.180, 0.040, 0.200])
        let displayText = "Smith's office"
        let synthesizedText = "Smith s office"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map possessive
        XCTAssertEqual(result.wordTimings.count, 2)
        XCTAssertEqual(result.wordTimings[0].text, "Smith's")
        XCTAssertEqual(result.wordTimings[0].duration, 0.220, accuracy: 0.001, "Should combine Smith + s durations")
        XCTAssertEqual(result.wordTimings[1].text, "office")
    }

    func testHandlesContractions() async throws {
        let service = PhonemeAlignmentService()

        // Test with "couldn't" -> "could not"
        let phonemes = createMockPhonemes(for: "He could not go", wordDurations: [0.100, 0.150, 0.120, 0.110])
        let displayText = "He couldn't go"
        let synthesizedText = "He could not go"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map contraction
        XCTAssertEqual(result.wordTimings.count, 3)
        XCTAssertEqual(result.wordTimings[0].text, "He")
        XCTAssertEqual(result.wordTimings[1].text, "couldn't")
        XCTAssertEqual(result.wordTimings[1].duration, 0.270, accuracy: 0.001, "Should combine could + not durations")
        XCTAssertEqual(result.wordTimings[2].text, "go")
    }

    func testHandlesComplexNormalization() async throws {
        let service = PhonemeAlignmentService()

        // Test with "Dr. Smith's" -> "Doctor Smith s"
        let phonemes = createMockPhonemes(for: "Doctor Smith s office", wordDurations: [0.250, 0.180, 0.040, 0.200])
        let displayText = "Dr. Smith's office"
        let synthesizedText = "Doctor Smith s office"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map all three normalizations
        XCTAssertEqual(result.wordTimings.count, 3)
        XCTAssertEqual(result.wordTimings[0].text, "Dr.")
        XCTAssertEqual(result.wordTimings[1].text, "Smith's")
        XCTAssertEqual(result.wordTimings[2].text, "office")
    }

    // MARK: - Technical Content

    func testHandlesTechnicalSlashTerms() async throws {
        let service = PhonemeAlignmentService()

        // Test with "TCP/IP" -> "T C P slash I P"
        let phonemes = createMockPhonemes(
            for: "T C P slash I P uses",
            wordDurations: [0.080, 0.080, 0.080, 0.100, 0.080, 0.080, 0.150]
        )
        let displayText = "TCP/IP uses"
        let synthesizedText = "T C P slash I P uses"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map technical term
        XCTAssertEqual(result.wordTimings.count, 2)
        XCTAssertEqual(result.wordTimings[0].text, "TCP/IP")
        XCTAssertEqual(result.wordTimings[0].duration, 0.500, accuracy: 0.001, "Should combine all 6 letter durations")
        XCTAssertEqual(result.wordTimings[1].text, "uses")
    }

    func testHandlesNumbers() async throws {
        let service = PhonemeAlignmentService()

        // Test with "23" -> "twenty three"
        let phonemes = createMockPhonemes(
            for: "Chapter twenty three begins",
            wordDurations: [0.200, 0.180, 0.120, 0.180]
        )
        let displayText = "Chapter 23 begins"
        let synthesizedText = "Chapter twenty three begins"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map number
        XCTAssertEqual(result.wordTimings.count, 3)
        XCTAssertEqual(result.wordTimings[0].text, "Chapter")
        XCTAssertEqual(result.wordTimings[1].text, "23")
        XCTAssertEqual(result.wordTimings[1].duration, 0.300, accuracy: 0.001, "Should combine twenty + three")
        XCTAssertEqual(result.wordTimings[2].text, "begins")
    }

    // MARK: - Timing Accuracy

    func testRealDurationsArePreserved() async throws {
        let service = PhonemeAlignmentService()

        // Create phonemes with varying realistic durations
        let phonemes = [
            PhonemeInfo(symbol: "t", duration: 0.025, textRange: 0..<4),
            PhonemeInfo(symbol: "ɛ", duration: 0.055, textRange: 0..<4),
            PhonemeInfo(symbol: "s", duration: 0.070, textRange: 0..<4),
            PhonemeInfo(symbol: "t", duration: 0.030, textRange: 0..<4)
        ]

        let displayText = "test"
        let synthesizedText = "test"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        XCTAssertEqual(result.wordTimings.count, 1)

        // Verify exact duration preservation
        let expectedDuration = 0.025 + 0.055 + 0.070 + 0.030
        XCTAssertEqual(result.wordTimings[0].duration, expectedDuration, accuracy: 0.0001)
        XCTAssertEqual(result.totalDuration, expectedDuration, accuracy: 0.0001)
    }

    func testMultipleWordsHaveSequentialTiming() async throws {
        let service = PhonemeAlignmentService()

        let phonemes = createMockPhonemes(
            for: "one two three",
            wordDurations: [0.150, 0.130, 0.170]
        )

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: "one two three",
            synthesizedText: "one two three",
            paragraphIndex: 0
        )

        XCTAssertEqual(result.wordTimings.count, 3)

        // Verify sequential timing
        XCTAssertEqual(result.wordTimings[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(result.wordTimings[1].startTime, 0.150, accuracy: 0.001)
        XCTAssertEqual(result.wordTimings[2].startTime, 0.280, accuracy: 0.001)

        XCTAssertEqual(result.totalDuration, 0.450, accuracy: 0.001)
    }

    // MARK: - Helper Methods

    /// Create mock phonemes for a synthesized text with specified word durations
    private func createMockPhonemes(for text: String, wordDurations: [TimeInterval]) -> [PhonemeInfo] {
        var phonemes: [PhonemeInfo] = []
        let words = text.split(separator: " ").map { String($0) }

        guard words.count == wordDurations.count else {
            fatalError("Word count mismatch: \(words.count) words but \(wordDurations.count) durations")
        }

        var charPosition = 0

        for (wordIndex, word) in words.enumerated() {
            let wordStart = charPosition
            let wordEnd = charPosition + word.count
            let wordDuration = wordDurations[wordIndex]

            // Estimate phonemes per word (roughly 1.5 per character, min 1)
            let phonemeCount = max(1, Int(Double(word.count) * 1.5))
            let phonemeDuration = wordDuration / Double(phonemeCount)

            // Create phonemes for this word
            for i in 0..<phonemeCount {
                phonemes.append(PhonemeInfo(
                    symbol: "p\(i)",  // Mock symbol
                    duration: phonemeDuration,
                    textRange: wordStart..<wordEnd
                ))
            }

            charPosition = wordEnd + 1  // +1 for space
        }

        return phonemes
    }
}
