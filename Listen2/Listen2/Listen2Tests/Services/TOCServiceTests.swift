//
//  TOCServiceTests.swift
//  Listen2Tests
//

import XCTest
import PDFKit
@testable import Listen2

final class TOCServiceTests: XCTestCase {

    func testExtractTOCFromPDFMetadata() {
        // This test requires a PDF with outline metadata
        // We'll test the method exists and returns an array
        let service = TOCService()

        // Create a dummy PDF document (will have no outline)
        let pdfData = createMinimalPDFData()
        let pdfDocument = PDFDocument(data: pdfData)

        XCTAssertNotNil(pdfDocument)

        let entries = service.extractTOCFromMetadata(pdfDocument!)
        XCTAssertNotNil(entries)
        XCTAssertTrue(entries.isEmpty) // No outline in minimal PDF
    }

    func testDetectHeadingsFromParagraphs() {
        let service = TOCService()
        let paragraphs = [
            "Chapter 1: Introduction",
            "This is the introduction paragraph with lots of text.",
            "This is another paragraph in the introduction.",
            "Chapter 2: Background",
            "This is the background section with content.",
            "1.1 Subsection",
            "Subsection content here."
        ]

        let entries = service.detectHeadingsFromParagraphs(paragraphs)

        XCTAssertGreaterThan(entries.count, 0)
        XCTAssertTrue(entries.contains { $0.title.contains("Chapter 1") })
        XCTAssertTrue(entries.contains { $0.title.contains("Chapter 2") })
    }

    func testHeadingDetectionIgnoresLongParagraphs() {
        let service = TOCService()
        let paragraphs = [
            "Short Title",
            "This is a very long paragraph that should not be detected as a heading because it contains too much text and is clearly body content rather than a title or heading."
        ]

        let entries = service.detectHeadingsFromParagraphs(paragraphs)

        // Should detect "Short Title" but not the long paragraph
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Short Title")
    }

    // Helper to create minimal PDF data
    private func createMinimalPDFData() -> Data {
        let pdfMetaData = [
            kCGPDFContextTitle: "Test Document"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            let text = "Test"
            text.draw(at: CGPoint(x: 100, y: 100), withAttributes: nil)
        }

        return data
    }
}
