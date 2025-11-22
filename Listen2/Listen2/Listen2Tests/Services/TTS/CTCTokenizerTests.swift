//
//  CTCTokenizerTests.swift
//  Listen2Tests
//
//  Tests for CTCTokenizer
//

import XCTest
@testable import Listen2

final class CTCTokenizerTests: XCTestCase {

    var tokenizer: CTCTokenizer!

    override func setUp() {
        super.setUp()
        // Use actual MMS_FA labels
        let mmsLabels = ["-", "a", "i", "e", "n", "o", "u", "t", "s", "r", "m", "k", "l", "d", "g", "h", "y", "b", "p", "w", "c", "v", "j", "z", "f", "'", "q", "x", "*"]
        tokenizer = CTCTokenizer(labels: mmsLabels)
    }

    func testVocabSize() {
        XCTAssertEqual(tokenizer.vocabSize, 29)
    }

    func testBlankTokenIndex() {
        XCTAssertEqual(tokenizer.blankIndex, 0) // "-" is blank at index 0
    }

    func testSpaceTokenIndex() {
        XCTAssertEqual(tokenizer.spaceIndex, 28) // "*" is space at index 28
    }

    func testTokenizeSimpleWord() {
        let tokens = tokenizer.tokenize("hello")
        // h=15, e=3, l=12, l=12, o=5
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens, [15, 3, 12, 12, 5])
    }

    func testTokenizeWithSpaces() {
        let tokens = tokenizer.tokenize("hello world")
        // hello=5 tokens, space=1, world=5 tokens
        XCTAssertEqual(tokens.count, 11)
        XCTAssertTrue(tokens.contains(28)) // Contains space token
    }

    func testTokenizeHandlesUnknownChars() {
        let tokens = tokenizer.tokenize("hello!")
        // Exclamation not in vocab, should be skipped
        XCTAssertEqual(tokens.count, 5)
    }

    func testTokenizeUppercase() {
        let tokens = tokenizer.tokenize("HELLO")
        // Should lowercase
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens, tokenizer.tokenize("hello"))
    }

    func testTokenizeWithApostrophe() {
        let tokens = tokenizer.tokenize("don't")
        // d=13, o=5, n=4, '=25, t=7
        XCTAssertEqual(tokens.count, 5)
        XCTAssertTrue(tokens.contains(25)) // Contains apostrophe token
    }

    func testDetokenize() {
        let tokens = [15, 3, 12, 12, 5] // hello
        let text = tokenizer.detokenize(tokens)
        XCTAssertEqual(text, "hello")
    }

    func testDetokenizeWithSpace() {
        let tokens = [15, 3, 12, 12, 5, 28, 19, 5, 9, 12, 13] // hello world
        let text = tokenizer.detokenize(tokens)
        XCTAssertEqual(text, "hello world")
    }

    func testLabelForIndex() {
        XCTAssertEqual(tokenizer.label(for: 0), "-")
        XCTAssertEqual(tokenizer.label(for: 1), "a")
        XCTAssertEqual(tokenizer.label(for: 28), "*")
        XCTAssertNil(tokenizer.label(for: 100))
    }
}
