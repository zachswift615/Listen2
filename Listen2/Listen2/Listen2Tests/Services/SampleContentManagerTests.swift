//
//  SampleContentManagerTests.swift
//  Listen2Tests
//
//  Unit tests for SampleContentManager
//

import XCTest
import SwiftData
@testable import Listen2

@MainActor
final class SampleContentManagerTests: XCTestCase {

    var manager: SampleContentManager!
    var modelContext: ModelContext!
    var modelContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        manager = SampleContentManager.shared

        // Create in-memory model container for testing
        let schema = Schema([Document.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
    }

    override func tearDown() async throws {
        manager = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Sample Document Metadata Tests

    func testSampleDocumentsList() {
        // Verify we have expected sample documents defined
        let samples = SampleContentManager.sampleDocuments

        XCTAssertEqual(samples.count, 2, "Should have 2 sample documents")

        // Verify Welcome sample
        let welcomeSample = samples.first { $0.filename == "welcome-sample.pdf" }
        XCTAssertNotNil(welcomeSample, "Should have welcome-sample.pdf")
        XCTAssertEqual(welcomeSample?.displayName, "Welcome to Listen2")
        XCTAssertEqual(welcomeSample?.sourceType, .pdf)

        // Verify Alice sample
        let aliceSample = samples.first { $0.filename == "alice-in-wonderland.epub" }
        XCTAssertNotNil(aliceSample, "Should have alice-in-wonderland.epub")
        XCTAssertEqual(aliceSample?.displayName, "Alice's Adventures in Wonderland")
        XCTAssertEqual(aliceSample?.sourceType, .epub)
    }

    // MARK: - Bundle Resource Tests

    func testWelcomePDFExists() {
        // Verify welcome PDF is in bundle
        let url = manager.getSampleDocumentURL(filename: "welcome-sample.pdf")
        XCTAssertNotNil(url, "welcome-sample.pdf should exist in bundle")

        if let url = url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist at URL")
        }
    }

    func testAliceEPUBExists() {
        // Verify Alice EPUB is in bundle
        let url = manager.getSampleDocumentURL(filename: "alice-in-wonderland.epub")
        XCTAssertNotNil(url, "alice-in-wonderland.epub should exist in bundle")

        if let url = url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist at URL")
        }
    }

    func testWelcomePDFHasContent() throws {
        // Verify welcome PDF has actual content
        let url = try XCTUnwrap(manager.getSampleDocumentURL(filename: "welcome-sample.pdf"))

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "Welcome PDF should have content")

        // Verify it's actually a PDF (starts with PDF header)
        let header = data.prefix(4)
        let pdfHeader = Data([0x25, 0x50, 0x44, 0x46]) // %PDF
        XCTAssertEqual(header, pdfHeader, "Should have valid PDF header")
    }

    func testAliceEPUBHasContent() throws {
        // Verify Alice EPUB has actual content
        let url = try XCTUnwrap(manager.getSampleDocumentURL(filename: "alice-in-wonderland.epub"))

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "Alice EPUB should have content")

        // Verify it's actually a ZIP/EPUB (starts with PK header)
        let header = data.prefix(2)
        let zipHeader = Data([0x50, 0x4B]) // PK
        XCTAssertEqual(header, zipHeader, "EPUB should have valid ZIP header")
    }

    // MARK: - Import Detection Tests

    func testHasSampleDocuments_EmptyLibrary() {
        // Verify returns false for empty library
        let hasSamples = manager.hasSampleDocuments(modelContext: modelContext)
        XCTAssertFalse(hasSamples, "Should return false for empty library")
    }

    func testHasSampleDocuments_WithSamples() {
        // Add a sample document to library
        let doc = Document(
            title: "Welcome to Listen2",
            sourceType: .pdf,
            extractedText: ["Test paragraph"]
        )
        modelContext.insert(doc)

        // Verify detection works
        let hasSamples = manager.hasSampleDocuments(modelContext: modelContext)
        XCTAssertTrue(hasSamples, "Should detect sample document by title")
    }

    func testHasSampleDocuments_WithOtherDocuments() {
        // Add a non-sample document
        let doc = Document(
            title: "Some Other Document",
            sourceType: .pdf,
            extractedText: ["Test paragraph"]
        )
        modelContext.insert(doc)

        // Verify returns false
        let hasSamples = manager.hasSampleDocuments(modelContext: modelContext)
        XCTAssertFalse(hasSamples, "Should return false when only non-sample documents exist")
    }

    // MARK: - Integration Tests

    func testImportSampleDocuments() async throws {
        // This is an integration test that requires DocumentProcessor
        // It verifies the end-to-end import flow

        let processor = DocumentProcessor()

        // Import samples
        try await manager.importSampleDocuments(
            modelContext: modelContext,
            documentProcessor: processor
        )

        // Verify documents were created
        let descriptor = FetchDescriptor<Document>()
        let documents = try modelContext.fetch(descriptor)

        XCTAssertEqual(documents.count, 2, "Should have imported 2 documents")

        // Verify Welcome document
        let welcomeDoc = documents.first { $0.title == "Welcome to Listen2" }
        XCTAssertNotNil(welcomeDoc, "Should have Welcome document")
        XCTAssertEqual(welcomeDoc?.sourceType, .pdf)
        XCTAssertFalse(welcomeDoc?.extractedText.isEmpty ?? true, "Should have extracted text")

        // Verify Alice document
        let aliceDoc = documents.first { $0.title == "Alice's Adventures in Wonderland" }
        XCTAssertNotNil(aliceDoc, "Should have Alice document")
        XCTAssertEqual(aliceDoc?.sourceType, .epub)
        XCTAssertFalse(aliceDoc?.extractedText.isEmpty ?? true, "Should have extracted text")
    }

    func testImportSampleDocuments_ExtractsText() async throws {
        // Verify that text extraction works for sample content
        let processor = DocumentProcessor()

        try await manager.importSampleDocuments(
            modelContext: modelContext,
            documentProcessor: processor
        )

        let descriptor = FetchDescriptor<Document>()
        let documents = try modelContext.fetch(descriptor)

        // Check Welcome PDF
        let welcomeDoc = documents.first { $0.title == "Welcome to Listen2" }
        if let doc = welcomeDoc {
            XCTAssertGreaterThan(doc.extractedText.count, 0, "Welcome PDF should have paragraphs")

            // Verify the text is readable (not binary garbage)
            let firstParagraph = doc.extractedText.first ?? ""
            XCTAssertGreaterThan(firstParagraph.count, 10, "First paragraph should have content")

            // Welcome document should contain certain keywords
            let allText = doc.extractedText.joined(separator: " ").lowercased()
            XCTAssertTrue(
                allText.contains("listen") || allText.contains("welcome"),
                "Welcome document should contain relevant keywords"
            )
        }

        // Check Alice EPUB
        let aliceDoc = documents.first { $0.title == "Alice's Adventures in Wonderland" }
        if let doc = aliceDoc {
            XCTAssertGreaterThan(doc.extractedText.count, 0, "Alice EPUB should have paragraphs")

            // Alice should have substantial content
            XCTAssertGreaterThan(doc.extractedText.count, 10, "Alice should have many paragraphs")

            // Should contain Alice-related content
            let allText = doc.extractedText.joined(separator: " ").lowercased()
            XCTAssertTrue(
                allText.contains("alice") || allText.contains("rabbit"),
                "Alice document should contain story content"
            )
        }
    }

    func testImportSampleDocuments_SetsTOCData() async throws {
        // Verify that TOC data is extracted and stored
        let processor = DocumentProcessor()

        try await manager.importSampleDocuments(
            modelContext: modelContext,
            documentProcessor: processor
        )

        let descriptor = FetchDescriptor<Document>()
        let documents = try modelContext.fetch(descriptor)

        // At least one document should have TOC data
        let docsWithTOC = documents.filter { $0.tocEntriesData != nil }
        XCTAssertGreaterThan(docsWithTOC.count, 0, "At least one document should have TOC data")

        // If Alice has TOC data, verify it's valid
        let aliceDoc = documents.first { $0.title == "Alice's Adventures in Wonderland" }
        if let tocData = aliceDoc?.tocEntriesData {
            // Try to decode TOC entries
            let decoder = JSONDecoder()
            let entries = try? decoder.decode([TOCEntry].self, from: tocData)
            XCTAssertNotNil(entries, "Should be able to decode TOC entries")

            if let entries = entries {
                XCTAssertGreaterThan(entries.count, 0, "Should have at least one TOC entry")
            }
        }
    }

    // MARK: - Error Handling Tests

    func testGetSampleDocumentURL_InvalidFilename() {
        // Test with invalid filename format
        let url = manager.getSampleDocumentURL(filename: "noextension")
        XCTAssertNil(url, "Should return nil for invalid filename")
    }

    func testGetSampleDocumentURL_NonexistentFile() {
        // Test with file that doesn't exist
        let url = manager.getSampleDocumentURL(filename: "nonexistent.pdf")
        XCTAssertNil(url, "Should return nil for nonexistent file")
    }
}
