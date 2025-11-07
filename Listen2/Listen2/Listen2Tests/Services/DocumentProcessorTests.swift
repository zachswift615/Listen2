//
//  DocumentProcessorTests.swift
//  Listen2Tests
//

import XCTest
import UIKit
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

    func testExtractTextFromPDF_WithHyphenation() async throws {
        // Given
        let pdfText = """
        This is a sam-
        ple document with hyphen-
        ated words.
        """
        let pdfURL = try createTestPDF(withText: pdfText)

        // When
        let result = try await processor.extractText(from: pdfURL, sourceType: .pdf)

        // Then
        let fullText = result.joined(separator: " ")
        XCTAssertTrue(fullText.contains("sample document"))
        XCTAssertTrue(fullText.contains("hyphenated words"))
        XCTAssertFalse(fullText.contains("sam-\n"))

        // Cleanup
        try? FileManager.default.removeItem(at: pdfURL)
    }

    func testProcessClipboardText() {
        // Given
        let clipboardText = """
        First paragraph with content.

        Second paragraph after blank line.

        Third paragraph.
        """

        // When
        let result = processor.processClipboardText(clipboardText)

        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "First paragraph with content.")
        XCTAssertEqual(result[1], "Second paragraph after blank line.")
        XCTAssertEqual(result[2], "Third paragraph.")
    }

    func testProcessClipboardText_EmptyLines() {
        // Given
        let clipboardText = "\n\n  \n\nActual content.\n\n  \n"

        // When
        let result = processor.processClipboardText(clipboardText)

        // Then
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], "Actual content.")
    }

    func testExtractEPUBText_Basic() async throws {
        // For MVP, we'll test the interface exists
        // Full EPUB parsing can be enhanced later
        let testURL = URL(fileURLWithPath: "/tmp/test.epub")

        do {
            _ = try await processor.extractText(from: testURL, sourceType: .epub)
            XCTFail("Should throw unsupportedFormat for now")
        } catch DocumentProcessor.DocumentProcessorError.unsupportedFormat {
            // Expected for MVP
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // Helper to create test PDF
    private func createTestPDF(withText text: String) throws -> URL {
        let pdfMetaData = [
            kCGPDFContextTitle: "Test PDF"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            text.draw(in: pageRect.insetBy(dx: 50, dy: 50), withAttributes: attributes)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try data.write(to: tempURL)

        return tempURL
    }
}
