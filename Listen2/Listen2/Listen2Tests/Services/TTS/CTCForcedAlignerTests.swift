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

    // MARK: - Trellis Tests

    func testBuildTrellis() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "b", "c"]  // blank=0, a=1, b=2, c=3
        try await aligner.initializeWithLabels(testLabels)

        // Simulate emissions: 6 frames, vocab size 4
        // Token sequence: [1, 2] (characters "a", "b")
        let emissions: [[Float]] = [
            [-1.0, -0.1, -10.0, -10.0],  // Frame 0: "a" likely
            [-1.0, -0.1, -10.0, -10.0],  // Frame 1: "a" likely
            [-0.1, -10.0, -10.0, -10.0], // Frame 2: blank likely
            [-10.0, -10.0, -0.1, -10.0], // Frame 3: "b" likely
            [-10.0, -10.0, -0.1, -10.0], // Frame 4: "b" likely
            [-0.1, -10.0, -10.0, -10.0], // Frame 5: blank likely
        ]

        let tokens = [1, 2]  // "a", "b"

        let trellis = await aligner.buildTrellis(emissions: emissions, tokens: tokens)

        // Trellis should have 6 rows (frames) and 5 columns (blank, a, blank, b, blank)
        XCTAssertEqual(trellis.count, 6)
        XCTAssertEqual(trellis[0].count, 5)  // 2*2 + 1 = 5 states
    }

    func testBacktrack() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "b", "c"]
        try await aligner.initializeWithLabels(testLabels)

        let tokens = [1, 2]  // "a", "b"

        // Simple emissions that clearly favor: blank->a->a->blank->b->b
        let emissions: [[Float]] = [
            [-0.1, -10.0, -10.0, -10.0], // Frame 0: blank
            [-10.0, -0.1, -10.0, -10.0], // Frame 1: "a"
            [-10.0, -0.1, -10.0, -10.0], // Frame 2: "a"
            [-0.1, -10.0, -10.0, -10.0], // Frame 3: blank
            [-10.0, -10.0, -0.1, -10.0], // Frame 4: "b"
            [-10.0, -10.0, -0.1, -10.0], // Frame 5: "b"
        ]

        let trellis = await aligner.buildTrellis(emissions: emissions, tokens: tokens)
        let spans = await aligner.backtrack(trellis: trellis, tokens: tokens)

        // Should find 2 token spans
        XCTAssertEqual(spans.count, 2)

        // First span: "a" (token index 0) at frames 1-2
        XCTAssertEqual(spans[0].tokenIndex, 0)
        XCTAssertGreaterThanOrEqual(spans[0].startFrame, 1)
        XCTAssertLessThanOrEqual(spans[0].endFrame, 2)

        // Second span: "b" (token index 1) at frames 4-5
        XCTAssertEqual(spans[1].tokenIndex, 1)
        XCTAssertGreaterThanOrEqual(spans[1].startFrame, 4)
        XCTAssertLessThanOrEqual(spans[1].endFrame, 5)
    }

    func testBacktrackEmptyTokens() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "b"]
        try await aligner.initializeWithLabels(testLabels)

        let emissions: [[Float]] = [[-0.1, -1.0, -1.0]]
        let trellis = await aligner.buildTrellis(emissions: emissions, tokens: [])
        let spans = await aligner.backtrack(trellis: trellis, tokens: [])

        XCTAssertTrue(spans.isEmpty)
    }

    func testRepeatedTokensRequireBlank() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "l", "o"]  // blank=0, a=1, l=2, o=3
        try await aligner.initializeWithLabels(testLabels)

        // "ll" requires blank between repeated tokens (CTC rule)
        let tokens = [2, 2]  // l, l
        let emissions: [[Float]] = [
            [-0.1, -10.0, -10.0, -10.0],  // Frame 0: blank
            [-10.0, -10.0, -0.1, -10.0],  // Frame 1: l
            [-0.1, -10.0, -10.0, -10.0],  // Frame 2: blank (required between repeated!)
            [-10.0, -10.0, -0.1, -10.0],  // Frame 3: l
        ]

        let trellis = await aligner.buildTrellis(emissions: emissions, tokens: tokens)
        let spans = await aligner.backtrack(trellis: trellis, tokens: tokens)

        // Should find 2 token spans for the two 'l's
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].tokenIndex, 0)  // First 'l'
        XCTAssertEqual(spans[1].tokenIndex, 1)  // Second 'l'
    }

    func testSingleToken() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "b"]
        try await aligner.initializeWithLabels(testLabels)

        let tokens = [1]  // Just "a"
        let emissions: [[Float]] = [
            [-0.1, -10.0, -10.0],  // Frame 0: blank
            [-10.0, -0.1, -10.0],  // Frame 1: a
            [-10.0, -0.1, -10.0],  // Frame 2: a
        ]

        let trellis = await aligner.buildTrellis(emissions: emissions, tokens: tokens)
        let spans = await aligner.backtrack(trellis: trellis, tokens: tokens)

        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].tokenIndex, 0)
    }
}
