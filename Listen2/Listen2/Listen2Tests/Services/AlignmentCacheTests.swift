//
//  AlignmentCacheTests.swift
//  Listen2Tests
//
//  Test suite for AlignmentCache
//

import XCTest
@testable import Listen2

/// Tests for AlignmentCache persistent disk caching
final class AlignmentCacheTests: XCTestCase {

    var cache: AlignmentCache!
    var testDocumentID: UUID!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        cache = AlignmentCache()
        testDocumentID = UUID()

        // Clear any existing test cache
        try await cache.clear(for: testDocumentID)
    }

    override func tearDown() async throws {
        // Clean up test cache
        try await cache.clear(for: testDocumentID)
        cache = nil
        testDocumentID = nil
        try await super.tearDown()
    }

    // MARK: - Basic Save/Load Tests

    func testSaveAndLoadAlignment() async throws {
        // Create a test alignment
        let alignment = createTestAlignment(paragraphIndex: 0, duration: 5.0)

        // Save it
        try await cache.save(alignment, for: testDocumentID, paragraph: 0)

        // Load it back
        let loaded = try await cache.load(for: testDocumentID, paragraph: 0)

        // Verify it matches
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.paragraphIndex, alignment.paragraphIndex)
        XCTAssertEqual(loaded?.totalDuration, alignment.totalDuration)
        XCTAssertEqual(loaded?.wordTimings.count, alignment.wordTimings.count)
    }

    func testLoadNonExistentAlignment() async throws {
        // Try to load an alignment that doesn't exist
        let loaded = try await cache.load(for: testDocumentID, paragraph: 99)

        // Should return nil, not throw
        XCTAssertNil(loaded)
    }

    func testLoadFromNonExistentDocument() async throws {
        let nonExistentID = UUID()
        let loaded = try await cache.load(for: nonExistentID, paragraph: 0)

        // Should return nil, not throw
        XCTAssertNil(loaded)
    }

    // MARK: - Multiple Paragraphs Tests

    func testSaveMultipleParagraphs() async throws {
        // Save alignments for multiple paragraphs
        let alignment0 = createTestAlignment(paragraphIndex: 0, duration: 5.0)
        let alignment1 = createTestAlignment(paragraphIndex: 1, duration: 3.0)
        let alignment2 = createTestAlignment(paragraphIndex: 2, duration: 7.0)

        try await cache.save(alignment0, for: testDocumentID, paragraph: 0)
        try await cache.save(alignment1, for: testDocumentID, paragraph: 1)
        try await cache.save(alignment2, for: testDocumentID, paragraph: 2)

        // Load each one back
        let loaded0 = try await cache.load(for: testDocumentID, paragraph: 0)
        let loaded1 = try await cache.load(for: testDocumentID, paragraph: 1)
        let loaded2 = try await cache.load(for: testDocumentID, paragraph: 2)

        // Verify they match
        XCTAssertEqual(loaded0?.paragraphIndex, 0)
        XCTAssertEqual(loaded0?.totalDuration, 5.0)

        XCTAssertEqual(loaded1?.paragraphIndex, 1)
        XCTAssertEqual(loaded1?.totalDuration, 3.0)

        XCTAssertEqual(loaded2?.paragraphIndex, 2)
        XCTAssertEqual(loaded2?.totalDuration, 7.0)
    }

    func testOverwriteExistingAlignment() async throws {
        // Save an alignment
        let alignment1 = createTestAlignment(paragraphIndex: 0, duration: 5.0)
        try await cache.save(alignment1, for: testDocumentID, paragraph: 0)

        // Overwrite with new alignment (voice change scenario)
        let alignment2 = createTestAlignment(paragraphIndex: 0, duration: 7.5)
        try await cache.save(alignment2, for: testDocumentID, paragraph: 0)

        // Load and verify it's the new one
        let loaded = try await cache.load(for: testDocumentID, paragraph: 0)
        XCTAssertEqual(loaded?.totalDuration, 7.5)
    }

    // MARK: - Clear Tests

    func testClearDocument() async throws {
        // Save alignments for multiple paragraphs
        try await cache.save(createTestAlignment(paragraphIndex: 0, duration: 5.0), for: testDocumentID, paragraph: 0)
        try await cache.save(createTestAlignment(paragraphIndex: 1, duration: 3.0), for: testDocumentID, paragraph: 1)
        try await cache.save(createTestAlignment(paragraphIndex: 2, duration: 7.0), for: testDocumentID, paragraph: 2)

        // Clear all alignments for this document
        try await cache.clear(for: testDocumentID)

        // Verify all are gone
        XCTAssertNil(try await cache.load(for: testDocumentID, paragraph: 0))
        XCTAssertNil(try await cache.load(for: testDocumentID, paragraph: 1))
        XCTAssertNil(try await cache.load(for: testDocumentID, paragraph: 2))
    }

    func testClearNonExistentDocument() async throws {
        // Clearing a document that doesn't exist should not throw
        let nonExistentID = UUID()
        try await cache.clear(for: nonExistentID)

        // No assertion needed, just verify it doesn't crash
    }

    func testClearAllCache() async throws {
        // Save alignments for multiple documents
        let doc1 = UUID()
        let doc2 = UUID()

        try await cache.save(createTestAlignment(paragraphIndex: 0, duration: 5.0), for: doc1, paragraph: 0)
        try await cache.save(createTestAlignment(paragraphIndex: 0, duration: 3.0), for: doc2, paragraph: 0)

        // Clear all cache
        try await cache.clearAll()

        // Verify all are gone
        XCTAssertNil(try await cache.load(for: doc1, paragraph: 0))
        XCTAssertNil(try await cache.load(for: doc2, paragraph: 0))

        // Cleanup
        try await cache.clear(for: doc1)
        try await cache.clear(for: doc2)
    }

    // MARK: - File Structure Tests

    func testCacheFileStructure() async throws {
        // Save an alignment
        let alignment = createTestAlignment(paragraphIndex: 5, duration: 5.0)
        try await cache.save(alignment, for: testDocumentID, paragraph: 5)

        // Verify the file structure exists
        let cacheURL = try cache.getCacheDirectoryURL()
        let documentDir = cacheURL.appendingPathComponent(testDocumentID.uuidString)
        let fileURL = documentDir.appendingPathComponent("5.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Cache file should exist at expected path")
    }

    func testMultipleDocumentsAreSeparate() async throws {
        let doc1 = UUID()
        let doc2 = UUID()

        // Save alignments for same paragraph index in different documents
        let alignment1 = createTestAlignment(paragraphIndex: 0, duration: 5.0)
        let alignment2 = createTestAlignment(paragraphIndex: 0, duration: 8.0)

        try await cache.save(alignment1, for: doc1, paragraph: 0)
        try await cache.save(alignment2, for: doc2, paragraph: 0)

        // Load and verify they're separate
        let loaded1 = try await cache.load(for: doc1, paragraph: 0)
        let loaded2 = try await cache.load(for: doc2, paragraph: 0)

        XCTAssertEqual(loaded1?.totalDuration, 5.0)
        XCTAssertEqual(loaded2?.totalDuration, 8.0)

        // Cleanup
        try await cache.clear(for: doc1)
        try await cache.clear(for: doc2)
    }

    // MARK: - WordTiming Persistence Tests

    func testWordTimingsPersistence() async throws {
        // Create alignment with word timings
        let dummyRange = "test text".startIndex..<"test".endIndex

        let wordTimings = [
            AlignmentResult.WordTiming(
                wordIndex: 0,
                startTime: 0.0,
                duration: 0.5,
                text: "Hello",
                stringRange: dummyRange
            ),
            AlignmentResult.WordTiming(
                wordIndex: 1,
                startTime: 0.5,
                duration: 0.7,
                text: "world",
                stringRange: dummyRange
            )
        ]

        let alignment = AlignmentResult(
            paragraphIndex: 0,
            totalDuration: 1.2,
            wordTimings: wordTimings
        )

        // Save and load
        try await cache.save(alignment, for: testDocumentID, paragraph: 0)
        let loaded = try await cache.load(for: testDocumentID, paragraph: 0)

        // Verify word timings are preserved
        XCTAssertEqual(loaded?.wordTimings.count, 2)
        XCTAssertEqual(loaded?.wordTimings[0].text, "Hello")
        XCTAssertEqual(loaded?.wordTimings[0].startTime, 0.0)
        XCTAssertEqual(loaded?.wordTimings[0].duration, 0.5)
        XCTAssertEqual(loaded?.wordTimings[1].text, "world")
        XCTAssertEqual(loaded?.wordTimings[1].startTime, 0.5)
        XCTAssertEqual(loaded?.wordTimings[1].duration, 0.7)
    }

    // MARK: - Error Handling Tests

    func testCorruptedCacheFileHandling() async throws {
        // Create a corrupted cache file
        let cacheURL = try cache.getCacheDirectoryURL()
        let documentDir = cacheURL.appendingPathComponent(testDocumentID.uuidString)
        try FileManager.default.createDirectory(at: documentDir, withIntermediateDirectories: true)

        let fileURL = documentDir.appendingPathComponent("0.json")
        try "corrupted json data {{{".write(to: fileURL, atomically: true, encoding: .utf8)

        // Try to load - should throw error
        do {
            _ = try await cache.load(for: testDocumentID, paragraph: 0)
            XCTFail("Should throw error for corrupted cache file")
        } catch let error as AlignmentError {
            // Verify correct error type
            if case .cacheReadFailed = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Performance Tests

    func testSavePerformance() async throws {
        let alignment = createTestAlignment(paragraphIndex: 0, duration: 5.0)

        measure {
            Task {
                try? await cache.save(alignment, for: testDocumentID, paragraph: 0)
            }
        }
    }

    func testLoadPerformance() async throws {
        // Save first
        let alignment = createTestAlignment(paragraphIndex: 0, duration: 5.0)
        try await cache.save(alignment, for: testDocumentID, paragraph: 0)

        measure {
            Task {
                _ = try? await cache.load(for: testDocumentID, paragraph: 0)
            }
        }
    }

    // MARK: - Helper Methods

    /// Create a test AlignmentResult
    private func createTestAlignment(paragraphIndex: Int, duration: TimeInterval) -> AlignmentResult {
        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: duration,
            wordTimings: []
        )
    }
}
