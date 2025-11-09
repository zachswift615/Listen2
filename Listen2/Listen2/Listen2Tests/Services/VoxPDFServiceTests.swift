//
//  VoxPDFServiceTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class VoxPDFServiceTests: XCTestCase {

    var sut: VoxPDFService!

    override func setUp() {
        super.setUp()
        sut = VoxPDFService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testExtractParagraphs_ValidPDF_ReturnsParagraphs() async throws {
        // Given: A test PDF file
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "test-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not found - skipping test")
        }

        // When: Extracting paragraphs
        let paragraphs = try await sut.extractParagraphs(from: pdfURL)

        // Then: Should return non-empty paragraphs
        XCTAssertFalse(paragraphs.isEmpty, "Should extract at least one paragraph")
        XCTAssertTrue(paragraphs.allSatisfy { !$0.isEmpty }, "No paragraph should be empty")
    }

    func testExtractText_ValidPDF_ReturnsWords() async throws {
        // Given: A test PDF file
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "test-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not found - skipping test")
        }

        // When: Extracting raw text
        let text = try await sut.extractText(from: pdfURL)

        // Then: Should return non-empty text
        XCTAssertFalse(text.isEmpty, "Should extract text content")
        XCTAssertTrue(text.contains(" "), "Text should contain spaces between words")
    }

    func testExtractTOC_ValidPDF_ReturnsTOCEntries() async throws {
        // Given: A test PDF with TOC
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "test-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not found - skipping test")
        }

        let paragraphs = try await sut.extractParagraphs(from: pdfURL)

        // When: Extracting TOC
        let toc = try await sut.extractTOC(from: pdfURL, paragraphs: paragraphs)

        // Then: Should return TOC entries (may be empty for PDFs without TOC)
        XCTAssertNotNil(toc, "Should return a TOC array")
    }

    func testExtractParagraphs_InvalidPDF_ThrowsError() async {
        // Given: Invalid PDF path
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.pdf")

        // When/Then: Should throw error
        do {
            _ = try await sut.extractParagraphs(from: invalidURL)
            XCTFail("Should throw error for invalid PDF")
        } catch {
            // Expected to throw
            XCTAssertTrue(error is VoxPDFService.VoxPDFError)
        }
    }
}
