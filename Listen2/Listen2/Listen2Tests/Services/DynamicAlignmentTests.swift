//
//  DynamicAlignmentTests.swift
//  Listen2Tests
//
//  Tests for dynamic alignment engine that maps phoneme groups to display words
//

import XCTest
@testable import Listen2

class DynamicAlignmentTests: XCTestCase {

    // MARK: - Identity Mapping Tests

    func testAlignsIdentityMapping() {
        // Test simplest case: display words match synthesized words exactly
        let engine = DynamicAlignmentEngine()

        // Mock phoneme groups (from espeak word boundaries)
        let phonemeGroups = [
            // "Hello" phonemes
            [
                PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<5),
                PhonemeInfo(symbol: "ə", duration: 0.04, textRange: 0..<5),
                PhonemeInfo(symbol: "l", duration: 0.06, textRange: 0..<5),
                PhonemeInfo(symbol: "oʊ", duration: 0.08, textRange: 0..<5)
            ],
            // "world" phonemes
            [
                PhonemeInfo(symbol: "w", duration: 0.05, textRange: 6..<11),
                PhonemeInfo(symbol: "ɝ", duration: 0.07, textRange: 6..<11),
                PhonemeInfo(symbol: "l", duration: 0.06, textRange: 6..<11),
                PhonemeInfo(symbol: "d", duration: 0.04, textRange: 6..<11)
            ]
        ]

        // Display words
        let displayWords = ["Hello", "world"]

        // Word mapping (identity: 1-to-1)
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [1])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 2, "Should have 2 aligned words")

        // First word
        XCTAssertEqual(result[0].text, "Hello")
        XCTAssertEqual(result[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[0].duration, 0.23, accuracy: 0.01)
        XCTAssertEqual(result[0].phonemes.count, 4)

        // Second word
        XCTAssertEqual(result[1].text, "world")
        XCTAssertEqual(result[1].startTime, 0.23, accuracy: 0.01)
        XCTAssertEqual(result[1].duration, 0.22, accuracy: 0.01)
        XCTAssertEqual(result[1].phonemes.count, 4)
    }

    // MARK: - One-to-Many Mapping Tests (Contractions)

    func testAlignsContractionExpansion() {
        // Test contraction mapping: "couldn't" -> ["could", "not"]
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            // "could" phonemes
            [
                PhonemeInfo(symbol: "k", duration: 0.05, textRange: 0..<5),
                PhonemeInfo(symbol: "ʊ", duration: 0.04, textRange: 0..<5),
                PhonemeInfo(symbol: "d", duration: 0.05, textRange: 0..<5)
            ],
            // "not" phonemes
            [
                PhonemeInfo(symbol: "n", duration: 0.06, textRange: 6..<9),
                PhonemeInfo(symbol: "ɑ", duration: 0.04, textRange: 6..<9),
                PhonemeInfo(symbol: "t", duration: 0.05, textRange: 6..<9)
            ],
            // "go" phonemes
            [
                PhonemeInfo(symbol: "g", duration: 0.05, textRange: 10..<12),
                PhonemeInfo(symbol: "oʊ", duration: 0.08, textRange: 10..<12)
            ]
        ]

        let displayWords = ["couldn't", "go"]

        // Mapping: couldn't maps to indices [0, 1] (could not)
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0, 1]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [2])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 2, "Should have 2 aligned words")

        // "couldn't" should combine phonemes from groups 0 and 1
        XCTAssertEqual(result[0].text, "couldn't")
        XCTAssertEqual(result[0].phonemes.count, 6, "Should have 6 phonemes (3 + 3)")
        XCTAssertEqual(result[0].duration, 0.29, accuracy: 0.01)

        // "go" should use group 2
        XCTAssertEqual(result[1].text, "go")
        XCTAssertEqual(result[1].phonemes.count, 2)
        XCTAssertEqual(result[1].duration, 0.13, accuracy: 0.01)
    }

    func testAlignsAbbreviationExpansion() {
        // Test abbreviation: "Dr." -> "Doctor"
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            // "Doctor" phonemes
            [
                PhonemeInfo(symbol: "d", duration: 0.05, textRange: 0..<6),
                PhonemeInfo(symbol: "ɑ", duration: 0.06, textRange: 0..<6),
                PhonemeInfo(symbol: "k", duration: 0.04, textRange: 0..<6),
                PhonemeInfo(symbol: "t", duration: 0.05, textRange: 0..<6),
                PhonemeInfo(symbol: "ɝ", duration: 0.07, textRange: 0..<6)
            ],
            // "Smith" phonemes
            [
                PhonemeInfo(symbol: "s", duration: 0.06, textRange: 7..<12),
                PhonemeInfo(symbol: "m", duration: 0.05, textRange: 7..<12),
                PhonemeInfo(symbol: "ɪ", duration: 0.04, textRange: 7..<12),
                PhonemeInfo(symbol: "θ", duration: 0.06, textRange: 7..<12)
            ]
        ]

        let displayWords = ["Dr.", "Smith"]

        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [1])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "Dr.")
        XCTAssertEqual(result[0].phonemes.count, 5)
        XCTAssertEqual(result[1].text, "Smith")
    }

    func testAlignsPossessiveExpansion() {
        // Test possessive: "Smith's" -> ["Smith", "s"]
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            // "Smith" phonemes
            [
                PhonemeInfo(symbol: "s", duration: 0.06, textRange: 0..<5),
                PhonemeInfo(symbol: "m", duration: 0.05, textRange: 0..<5),
                PhonemeInfo(symbol: "ɪ", duration: 0.04, textRange: 0..<5),
                PhonemeInfo(symbol: "θ", duration: 0.06, textRange: 0..<5)
            ],
            // "s" phoneme
            [
                PhonemeInfo(symbol: "s", duration: 0.04, textRange: 6..<7)
            ],
            // "office" phonemes
            [
                PhonemeInfo(symbol: "ɑ", duration: 0.05, textRange: 8..<14),
                PhonemeInfo(symbol: "f", duration: 0.06, textRange: 8..<14),
                PhonemeInfo(symbol: "ɪ", duration: 0.04, textRange: 8..<14),
                PhonemeInfo(symbol: "s", duration: 0.05, textRange: 8..<14)
            ]
        ]

        let displayWords = ["Smith's", "office"]

        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0, 1]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [2])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "Smith's")
        XCTAssertEqual(result[0].phonemes.count, 5, "Should combine 4 + 1 phonemes")
        XCTAssertEqual(result[1].text, "office")
    }

    // MARK: - Edge Cases

    func testHandlesEmptyPhonemeGroups() {
        let engine = DynamicAlignmentEngine()

        let phonemeGroups: [[PhonemeInfo]] = []
        let displayWords = ["test"]
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 0, "Should return empty result for empty phoneme groups")
    }

    func testHandlesEmptyDisplayWords() {
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<1)]
        ]
        let displayWords: [String] = []
        let mapping: [TextNormalizationMapper.WordMapping] = []

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 0, "Should return empty result for empty display words")
    }

    func testHandlesMismatchedCounts() {
        // More phoneme groups than mapping entries
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<1)],
            [PhonemeInfo(symbol: "i", duration: 0.05, textRange: 1..<2)],
            [PhonemeInfo(symbol: "w", duration: 0.05, textRange: 2..<3)]
        ]

        let displayWords = ["hi"]

        // Mapping only covers first 2 groups
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0, 1])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 1, "Should handle gracefully")
        XCTAssertEqual(result[0].text, "hi")
        XCTAssertEqual(result[0].phonemes.count, 2)
    }

    func testHandlesInvalidMappingIndices() {
        // Mapping references indices that don't exist
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<1)]
        ]

        let displayWords = ["hi", "there"]

        // Mapping references synth index 5 which doesn't exist
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [5])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        // Should process first mapping successfully, skip second
        XCTAssertEqual(result.count, 1, "Should skip invalid mapping")
        XCTAssertEqual(result[0].text, "hi")
    }

    // MARK: - Multiple Phoneme Groups Per Word

    func testHandlesMultipleGroupsPerWord() {
        // Test complex case: display word maps to 3 synthesized groups
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [PhonemeInfo(symbol: "t", duration: 0.04, textRange: 0..<1)],
            [PhonemeInfo(symbol: "i", duration: 0.03, textRange: 1..<2)],
            [PhonemeInfo(symbol: "s", duration: 0.04, textRange: 2..<3)],
            [PhonemeInfo(symbol: "i", duration: 0.03, textRange: 3..<4)],
            [PhonemeInfo(symbol: "p", duration: 0.04, textRange: 4..<5)]
        ]

        let displayWords = ["TCP/IP"]

        // TCP/IP expands to multiple letter groups
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0, 1, 2, 3, 4])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "TCP/IP")
        XCTAssertEqual(result[0].phonemes.count, 5, "Should combine all phonemes")
        XCTAssertEqual(result[0].duration, 0.18, accuracy: 0.01)
    }

    // MARK: - Timing Calculation Tests

    func testCalculatesCorrectTiming() {
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [
                PhonemeInfo(symbol: "h", duration: 0.045, textRange: 0..<1),
                PhonemeInfo(symbol: "i", duration: 0.032, textRange: 0..<1)
            ],
            [
                PhonemeInfo(symbol: "w", duration: 0.058, textRange: 2..<3),
                PhonemeInfo(symbol: "o", duration: 0.091, textRange: 2..<3),
                PhonemeInfo(symbol: "r", duration: 0.048, textRange: 2..<3),
                PhonemeInfo(symbol: "l", duration: 0.067, textRange: 2..<3),
                PhonemeInfo(symbol: "d", duration: 0.041, textRange: 2..<3)
            ]
        ]

        let displayWords = ["Hi", "world"]
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [1])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        // First word: 0.045 + 0.032 = 0.077
        XCTAssertEqual(result[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[0].duration, 0.077, accuracy: 0.001)

        // Second word starts at 0.077
        XCTAssertEqual(result[1].startTime, 0.077, accuracy: 0.001)
        // Duration: 0.058 + 0.091 + 0.048 + 0.067 + 0.041 = 0.305
        XCTAssertEqual(result[1].duration, 0.305, accuracy: 0.001)
    }

    func testPreservesPhonemeOrder() {
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            [
                PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<1),
                PhonemeInfo(symbol: "e", duration: 0.04, textRange: 0..<1),
                PhonemeInfo(symbol: "l", duration: 0.06, textRange: 0..<1),
                PhonemeInfo(symbol: "o", duration: 0.08, textRange: 0..<1)
            ]
        ]

        let displayWords = ["Hello"]
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result[0].phonemes.count, 4)
        XCTAssertEqual(result[0].phonemes[0].symbol, "h")
        XCTAssertEqual(result[0].phonemes[1].symbol, "e")
        XCTAssertEqual(result[0].phonemes[2].symbol, "l")
        XCTAssertEqual(result[0].phonemes[3].symbol, "o")
    }

    // MARK: - Real-World Scenarios

    func testAlignsComplexSentence() {
        // Test: "Dr. Smith's couldn't go"
        // Synthesized: "Doctor Smith s could not go"
        let engine = DynamicAlignmentEngine()

        let phonemeGroups = [
            // Doctor
            [PhonemeInfo(symbol: "d", duration: 0.05, textRange: 0..<6)],
            // Smith
            [PhonemeInfo(symbol: "s", duration: 0.05, textRange: 7..<12)],
            // s
            [PhonemeInfo(symbol: "s", duration: 0.04, textRange: 13..<14)],
            // could
            [PhonemeInfo(symbol: "k", duration: 0.05, textRange: 15..<20)],
            // not
            [PhonemeInfo(symbol: "n", duration: 0.05, textRange: 21..<24)],
            // go
            [PhonemeInfo(symbol: "g", duration: 0.05, textRange: 25..<27)]
        ]

        let displayWords = ["Dr.", "Smith's", "couldn't", "go"]

        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [1, 2]),
            TextNormalizationMapper.WordMapping(displayIndices: [2], synthesizedIndices: [3, 4]),
            TextNormalizationMapper.WordMapping(displayIndices: [3], synthesizedIndices: [5])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0].text, "Dr.")
        XCTAssertEqual(result[1].text, "Smith's")
        XCTAssertEqual(result[2].text, "couldn't")
        XCTAssertEqual(result[3].text, "go")

        // Verify timing is sequential
        XCTAssertEqual(result[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(result[1].startTime, result[0].startTime)
        XCTAssertGreaterThan(result[2].startTime, result[1].startTime)
        XCTAssertGreaterThan(result[3].startTime, result[2].startTime)
    }
}
