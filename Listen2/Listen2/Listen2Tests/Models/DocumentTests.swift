//
//  DocumentTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class DocumentTests: XCTestCase {

    func testDocumentInitialization() {
        // Given
        let title = "Test Document"
        let sourceType = SourceType.pdf
        let text = ["Paragraph one.", "Paragraph two."]

        // When
        let document = Document(
            title: title,
            sourceType: sourceType,
            extractedText: text
        )

        // Then
        XCTAssertEqual(document.title, title)
        XCTAssertEqual(document.sourceType, sourceType)
        XCTAssertEqual(document.extractedText, text)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.progressPercentage, 0)
    }

    func testProgressPercentage() {
        // Given
        let document = Document(
            title: "Test",
            sourceType: .clipboard,
            extractedText: ["1", "2", "3", "4"]
        )

        // When
        document.currentPosition = 2

        // Then
        XCTAssertEqual(document.progressPercentage, 50)
    }

    func testProgressPercentageEmpty() {
        // Given
        let document = Document(
            title: "Empty",
            sourceType: .clipboard,
            extractedText: []
        )

        // Then
        XCTAssertEqual(document.progressPercentage, 0)
    }
}
