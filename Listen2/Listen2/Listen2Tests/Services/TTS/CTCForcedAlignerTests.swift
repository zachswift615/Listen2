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

    // MARK: - Word Merging Tests

    func testMergeToWords() async throws {
        let aligner = CTCForcedAligner()
        // Using subset of MMS_FA labels
        let testLabels = ["-", "a", "d", "e", "h", "l", "o", "r", "w", "*"]
        // Indices:         0    1    2    3    4    5    6    7    8    9
        try await aligner.initializeWithLabels(testLabels)

        let transcript = "hello world"

        // Token spans for "hello world" (h=4, e=3, l=5, l=5, o=6, space=9, w=8, o=6, r=7, l=5, d=2)
        let tokenSpans: [CTCForcedAligner.TokenSpan] = [
            CTCForcedAligner.TokenSpan(tokenIndex: 0, startFrame: 0, endFrame: 4),    // h
            CTCForcedAligner.TokenSpan(tokenIndex: 1, startFrame: 5, endFrame: 9),    // e
            CTCForcedAligner.TokenSpan(tokenIndex: 2, startFrame: 10, endFrame: 14),  // l
            CTCForcedAligner.TokenSpan(tokenIndex: 3, startFrame: 15, endFrame: 19),  // l
            CTCForcedAligner.TokenSpan(tokenIndex: 4, startFrame: 20, endFrame: 24),  // o
            // Space token span (tokenIndex 5) is skipped - word boundary
            CTCForcedAligner.TokenSpan(tokenIndex: 5, startFrame: 25, endFrame: 29),  // space (implicit word break)
            CTCForcedAligner.TokenSpan(tokenIndex: 6, startFrame: 30, endFrame: 34),  // w
            CTCForcedAligner.TokenSpan(tokenIndex: 7, startFrame: 35, endFrame: 39),  // o
            CTCForcedAligner.TokenSpan(tokenIndex: 8, startFrame: 40, endFrame: 44),  // r
            CTCForcedAligner.TokenSpan(tokenIndex: 9, startFrame: 45, endFrame: 49),  // l
            CTCForcedAligner.TokenSpan(tokenIndex: 10, startFrame: 50, endFrame: 54), // d
        ]

        let frameRate = 50.0  // 50 fps for easy math
        let wordTimings = await aligner.mergeToWords(
            tokenSpans: tokenSpans,
            transcript: transcript,
            frameRate: frameRate
        )

        XCTAssertEqual(wordTimings.count, 2)

        // First word: "hello" at frames 0-24 = 0.0s to 0.5s
        XCTAssertEqual(wordTimings[0].text, "hello")
        XCTAssertEqual(wordTimings[0].startTime, 0.0, accuracy: 0.02)
        XCTAssertEqual(wordTimings[0].rangeLocation, 0)
        XCTAssertEqual(wordTimings[0].rangeLength, 5)

        // Second word: "world" at frames 30-54 = 0.6s to 1.1s
        XCTAssertEqual(wordTimings[1].text, "world")
        XCTAssertEqual(wordTimings[1].startTime, 0.6, accuracy: 0.02)
        XCTAssertEqual(wordTimings[1].rangeLocation, 6)
        XCTAssertEqual(wordTimings[1].rangeLength, 5)
    }

    func testMergeToWordsWithApostrophe() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "d", "i", "n", "o", "t", "'", "*"]
        // Indices:         0    1    2    3    4    5    6    7
        try await aligner.initializeWithLabels(testLabels)

        let transcript = "don't do it"

        // Simplified token spans
        let tokenSpans: [CTCForcedAligner.TokenSpan] = [
            CTCForcedAligner.TokenSpan(tokenIndex: 0, startFrame: 0, endFrame: 9),   // d
            CTCForcedAligner.TokenSpan(tokenIndex: 1, startFrame: 10, endFrame: 19), // o
            CTCForcedAligner.TokenSpan(tokenIndex: 2, startFrame: 20, endFrame: 29), // n
            CTCForcedAligner.TokenSpan(tokenIndex: 3, startFrame: 30, endFrame: 34), // '
            CTCForcedAligner.TokenSpan(tokenIndex: 4, startFrame: 35, endFrame: 44), // t
            CTCForcedAligner.TokenSpan(tokenIndex: 5, startFrame: 45, endFrame: 49), // space
            CTCForcedAligner.TokenSpan(tokenIndex: 6, startFrame: 50, endFrame: 59), // d
            CTCForcedAligner.TokenSpan(tokenIndex: 7, startFrame: 60, endFrame: 69), // o
            CTCForcedAligner.TokenSpan(tokenIndex: 8, startFrame: 70, endFrame: 74), // space
            CTCForcedAligner.TokenSpan(tokenIndex: 9, startFrame: 75, endFrame: 84), // i
            CTCForcedAligner.TokenSpan(tokenIndex: 10, startFrame: 85, endFrame: 99), // t
        ]

        let frameRate = 100.0
        let wordTimings = await aligner.mergeToWords(
            tokenSpans: tokenSpans,
            transcript: transcript,
            frameRate: frameRate
        )

        XCTAssertEqual(wordTimings.count, 3)
        XCTAssertEqual(wordTimings[0].text, "don't")
        XCTAssertEqual(wordTimings[0].rangeLocation, 0)
        XCTAssertEqual(wordTimings[0].rangeLength, 5)

        XCTAssertEqual(wordTimings[1].text, "do")
        XCTAssertEqual(wordTimings[1].rangeLocation, 6)

        XCTAssertEqual(wordTimings[2].text, "it")
        XCTAssertEqual(wordTimings[2].rangeLocation, 9)
    }

    func testMergeToWordsEmpty() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "a", "b", "*"]
        try await aligner.initializeWithLabels(testLabels)

        let wordTimings = await aligner.mergeToWords(
            tokenSpans: [],
            transcript: "",
            frameRate: 50.0
        )

        XCTAssertTrue(wordTimings.isEmpty)
    }

    func testMergeToWordsSingleWord() async throws {
        let aligner = CTCForcedAligner()
        let testLabels = ["-", "h", "i", "*"]
        // Indices:         0    1    2    3
        try await aligner.initializeWithLabels(testLabels)

        let transcript = "hi"
        let tokenSpans: [CTCForcedAligner.TokenSpan] = [
            CTCForcedAligner.TokenSpan(tokenIndex: 0, startFrame: 0, endFrame: 4),   // h
            CTCForcedAligner.TokenSpan(tokenIndex: 1, startFrame: 5, endFrame: 9),   // i
        ]

        let frameRate = 50.0
        let wordTimings = await aligner.mergeToWords(
            tokenSpans: tokenSpans,
            transcript: transcript,
            frameRate: frameRate
        )

        XCTAssertEqual(wordTimings.count, 1)
        XCTAssertEqual(wordTimings[0].text, "hi")
        XCTAssertEqual(wordTimings[0].startTime, 0.0, accuracy: 0.02)
        XCTAssertEqual(wordTimings[0].rangeLocation, 0)
        XCTAssertEqual(wordTimings[0].rangeLength, 2)
    }
}
