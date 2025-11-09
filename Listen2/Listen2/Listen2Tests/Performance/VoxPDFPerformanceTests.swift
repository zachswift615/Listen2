//
//  VoxPDFPerformanceTests.swift
//  Listen2Tests
//
//  Performance benchmarks for VoxPDF text and TOC extraction
//

import XCTest
@testable import Listen2

final class VoxPDFPerformanceTests: XCTestCase {

    func testPDFExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()

        measure {
            let expectation = XCTestExpectation(description: "Extract paragraphs")

            Task {
                do {
                    _ = try await service.extractParagraphs(from: pdfURL)
                    expectation.fulfill()
                } catch {
                    XCTFail("Extraction failed: \(error)")
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testTOCExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()
        let paragraphs = ["Sample"] // Simplified for performance test

        measure {
            let expectation = XCTestExpectation(description: "Extract TOC")

            Task {
                do {
                    _ = try await service.extractTOC(from: pdfURL, paragraphs: paragraphs)
                    expectation.fulfill()
                } catch {
                    XCTFail("TOC extraction failed: \(error)")
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testTextExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()

        measure {
            let expectation = XCTestExpectation(description: "Extract text")

            Task {
                do {
                    _ = try await service.extractText(from: pdfURL)
                    expectation.fulfill()
                } catch {
                    XCTFail("Text extraction failed: \(error)")
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testWordPositionExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()

        measure {
            let expectation = XCTestExpectation(description: "Extract word positions")

            Task {
                do {
                    _ = try await service.extractWordPositions(from: pdfURL)
                    expectation.fulfill()
                } catch {
                    XCTFail("Word position extraction failed: \(error)")
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }
}
