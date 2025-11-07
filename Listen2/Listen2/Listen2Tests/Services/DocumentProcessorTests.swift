//
//  DocumentProcessorTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class DocumentProcessorTests: XCTestCase {

    var processor: DocumentProcessor!

    override func setUp() {
        super.setUp()
        processor = DocumentProcessor()
    }

    func testFixHyphenation_SimpleCase() {
        // Given
        let input = "This is an ex-\nample of hyphenation."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "This is an example of hyphenation.")
    }

    func testFixHyphenation_MultipleHyphens() {
        // Given
        let input = "Hyphen-\nated words can ap-\npear multiple times."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "Hyphenated words can appear multiple times.")
    }

    func testFixHyphenation_PreservesNormalHyphens() {
        // Given
        let input = "This is a well-known fact."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "This is a well-known fact.")
    }

    func testFixHyphenation_HandlesWhitespace() {
        // Given
        let input = "Ex-  \n  ample with spaces."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "Example with spaces.")
    }
}
