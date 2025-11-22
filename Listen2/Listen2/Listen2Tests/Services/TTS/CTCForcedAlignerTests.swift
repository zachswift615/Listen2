//
//  CTCForcedAlignerTests.swift
//  Listen2Tests
//
//  Tests for CTCForcedAligner
//

import XCTest
@testable import Listen2

final class CTCForcedAlignerTests: XCTestCase {

    func testInitializationWithMockLabels() async throws {
        let aligner = CTCForcedAligner()

        // Initialize with test labels
        let testLabels = ["-", "a", "i", "e", "n", "o", "u", "t", "s", "r", "m", "k", "l", "d", "g", "h", "y", "b", "p", "w", "c", "v", "j", "z", "f", "'", "q", "x", "*"]
        try await aligner.initializeWithLabels(testLabels)

        let isInitialized = await aligner.isInitialized
        XCTAssertTrue(isInitialized)
    }

    func testSampleRateIs16kHz() {
        let aligner = CTCForcedAligner()
        XCTAssertEqual(aligner.sampleRate, 16000)
    }

    func testTokenizerAvailableAfterInit() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "i", "e", "n", "o", "u", "t", "s", "r", "m", "k", "l", "d", "g", "h", "y", "b", "p", "w", "c", "v", "j", "z", "f", "'", "q", "x", "*"]
        try await aligner.initializeWithLabels(testLabels)

        let tokenizer = await aligner.getTokenizer()
        XCTAssertNotNil(tokenizer)
        XCTAssertEqual(tokenizer?.vocabSize, 29)
    }

    func testNotInitializedByDefault() async {
        let aligner = CTCForcedAligner()
        let isInitialized = await aligner.isInitialized
        XCTAssertFalse(isInitialized)
    }
}
