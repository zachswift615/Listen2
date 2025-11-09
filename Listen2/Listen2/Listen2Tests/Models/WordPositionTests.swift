//
//  WordPositionTests.swift
//  Listen2Tests
//
//  Tests for word position models
//

import XCTest
@testable import Listen2

final class WordPositionTests: XCTestCase {

    // MARK: - WordPosition Tests

    func testWordPosition_BasicProperties() {
        let word = WordPosition(
            text: "Hello",
            characterOffset: 0,
            length: 5,
            paragraphIndex: 0,
            pageNumber: 0
        )

        XCTAssertEqual(word.text, "Hello")
        XCTAssertEqual(word.characterOffset, 0)
        XCTAssertEqual(word.length, 5)
        XCTAssertEqual(word.paragraphIndex, 0)
        XCTAssertEqual(word.pageNumber, 0)
        XCTAssertNil(word.boundingBox)
    }

    func testWordPosition_WithBoundingBox() {
        let bbox = WordPosition.BoundingBox(x: 10, y: 20, width: 50, height: 12)
        let word = WordPosition(
            text: "Test",
            characterOffset: 6,
            length: 4,
            paragraphIndex: 1,
            pageNumber: 2,
            boundingBox: bbox
        )

        XCTAssertEqual(word.boundingBox?.x, 10)
        XCTAssertEqual(word.boundingBox?.y, 20)
        XCTAssertEqual(word.boundingBox?.width, 50)
        XCTAssertEqual(word.boundingBox?.height, 12)
    }

    func testWordPosition_Codable() throws {
        let word = WordPosition(
            text: "World",
            characterOffset: 6,
            length: 5,
            paragraphIndex: 0,
            pageNumber: 0
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(word)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WordPosition.self, from: data)

        XCTAssertEqual(decoded, word)
    }

    // MARK: - DocumentWordMap Tests

    func testDocumentWordMap_Initialization() {
        let words = [
            WordPosition(text: "First", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "word", characterOffset: 6, length: 4, paragraphIndex: 0, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        XCTAssertEqual(wordMap.words.count, 2)
        XCTAssertEqual(wordMap.wordsByParagraph[0]?.count, 2)
    }

    func testDocumentWordMap_WordsByParagraph() {
        let words = [
            WordPosition(text: "First", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "word", characterOffset: 6, length: 4, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "Second", characterOffset: 0, length: 6, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "paragraph", characterOffset: 7, length: 9, paragraphIndex: 1, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        let paragraph0Words = wordMap.words(for: 0)
        XCTAssertEqual(paragraph0Words.count, 2)
        XCTAssertEqual(paragraph0Words[0].text, "First")
        XCTAssertEqual(paragraph0Words[1].text, "word")

        let paragraph1Words = wordMap.words(for: 1)
        XCTAssertEqual(paragraph1Words.count, 2)
        XCTAssertEqual(paragraph1Words[0].text, "Second")
        XCTAssertEqual(paragraph1Words[1].text, "paragraph")

        // Non-existent paragraph
        let paragraph2Words = wordMap.words(for: 2)
        XCTAssertEqual(paragraph2Words.count, 0)
    }

    func testDocumentWordMap_FindWordAtOffset() {
        let words = [
            WordPosition(text: "Hello", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "world", characterOffset: 6, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "today", characterOffset: 12, length: 5, paragraphIndex: 0, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        // Find "Hello" at offset 0
        let word1 = wordMap.word(at: 0, in: 0)
        XCTAssertEqual(word1?.text, "Hello")

        // Find "Hello" at offset 2 (middle of word)
        let word2 = wordMap.word(at: 2, in: 0)
        XCTAssertEqual(word2?.text, "Hello")

        // Find "world" at offset 6 (start)
        let word3 = wordMap.word(at: 6, in: 0)
        XCTAssertEqual(word3?.text, "world")

        // Find "world" at offset 10 (end)
        let word4 = wordMap.word(at: 10, in: 0)
        XCTAssertEqual(word4?.text, "world")

        // Find "today" at offset 14
        let word5 = wordMap.word(at: 14, in: 0)
        XCTAssertEqual(word5?.text, "today")

        // Out of range
        let word6 = wordMap.word(at: 100, in: 0)
        XCTAssertNil(word6)

        // Wrong paragraph
        let word7 = wordMap.word(at: 0, in: 1)
        XCTAssertNil(word7)
    }

    func testDocumentWordMap_WordRangeForNSRange() {
        let words = [
            WordPosition(text: "Hello", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "world", characterOffset: 6, length: 5, paragraphIndex: 0, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)
        let paragraphText = "Hello world"

        // Find range for "Hello" (NSRange: location=0, length=5)
        let nsRange1 = NSRange(location: 0, length: 5)
        let range1 = wordMap.wordRange(for: nsRange1, in: 0, paragraphText: paragraphText)
        XCTAssertNotNil(range1)
        if let range1 = range1 {
            let extractedText = String(paragraphText[range1])
            XCTAssertEqual(extractedText, "Hello")
        }

        // Find range for "world" (NSRange: location=6, length=5)
        let nsRange2 = NSRange(location: 6, length: 5)
        let range2 = wordMap.wordRange(for: nsRange2, in: 0, paragraphText: paragraphText)
        XCTAssertNotNil(range2)
        if let range2 = range2 {
            let extractedText = String(paragraphText[range2])
            XCTAssertEqual(extractedText, "world")
        }

        // Invalid paragraph index
        let nsRange3 = NSRange(location: 0, length: 5)
        let range3 = wordMap.wordRange(for: nsRange3, in: 1, paragraphText: paragraphText)
        XCTAssertNil(range3)
    }

    func testDocumentWordMap_MultiParagraphScenario() {
        // Simulate a realistic multi-paragraph document
        let words = [
            // Paragraph 0: "The quick brown fox"
            WordPosition(text: "The", characterOffset: 0, length: 3, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "quick", characterOffset: 4, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "brown", characterOffset: 10, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "fox", characterOffset: 16, length: 3, paragraphIndex: 0, pageNumber: 0),

            // Paragraph 1: "jumps over the lazy dog"
            WordPosition(text: "jumps", characterOffset: 0, length: 5, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "over", characterOffset: 6, length: 4, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "the", characterOffset: 11, length: 3, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "lazy", characterOffset: 15, length: 4, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "dog", characterOffset: 20, length: 3, paragraphIndex: 1, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        // Verify paragraph separation
        XCTAssertEqual(wordMap.words(for: 0).count, 4)
        XCTAssertEqual(wordMap.words(for: 1).count, 5)

        // Verify word lookup in paragraph 0
        let word0_1 = wordMap.word(at: 4, in: 0)
        XCTAssertEqual(word0_1?.text, "quick")

        // Verify word lookup in paragraph 1
        let word1_1 = wordMap.word(at: 6, in: 1)
        XCTAssertEqual(word1_1?.text, "over")

        // Verify offsets reset per paragraph
        let firstWordP0 = wordMap.words(for: 0).first
        let firstWordP1 = wordMap.words(for: 1).first
        XCTAssertEqual(firstWordP0?.characterOffset, 0)
        XCTAssertEqual(firstWordP1?.characterOffset, 0)
    }

    func testDocumentWordMap_Codable() throws {
        let words = [
            WordPosition(text: "Test", characterOffset: 0, length: 4, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "word", characterOffset: 5, length: 4, paragraphIndex: 0, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(wordMap)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DocumentWordMap.self, from: data)

        // Verify words
        XCTAssertEqual(decoded.words.count, 2)
        XCTAssertEqual(decoded.words[0].text, "Test")
        XCTAssertEqual(decoded.words[1].text, "word")

        // Verify dictionary was reconstructed
        XCTAssertEqual(decoded.wordsByParagraph[0]?.count, 2)
    }
}
