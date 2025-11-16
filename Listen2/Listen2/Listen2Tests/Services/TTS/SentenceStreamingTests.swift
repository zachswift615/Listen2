//
//  SentenceStreamingTests.swift
//  Listen2Tests
//
//  Tests for sentence-by-sentence streaming playback
//

import XCTest
@testable import Listen2

final class SentenceStreamingTests: XCTestCase {

    var service: TTSService!

    override func setUp() async throws {
        try await super.setUp()
        service = TTSService()

        // Wait for initialization
        let maxWaitTime: TimeInterval = 10.0
        let pollInterval: TimeInterval = 0.1
        var elapsed: TimeInterval = 0

        while service.isInitializing && elapsed < maxWaitTime {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            elapsed += pollInterval
        }

        XCTAssertFalse(service.isInitializing, "Service should finish initializing")
    }

    override func tearDown() {
        service.stop()
        service = nil
        super.tearDown()
    }

    /// Test that multi-sentence paragraphs play ALL sentences, not just the first
    func testPlaybackIncludesAllSentences() async throws {
        // Given: A paragraph with 3 distinct sentences
        let testParagraph = "First sentence here. Second sentence here. Third sentence here."
        let paragraphs = [testParagraph]

        // Track progress updates to verify all sentences are played
        var progressUpdates: [ReadingProgress] = []
        let expectation = XCTestExpectation(description: "Playback completes")
        expectation.expectedFulfillmentCount = 1

        // Monitor progress updates
        let cancellable = service.$currentProgress
            .sink { progress in
                if progress.isPlaying {
                    progressUpdates.append(progress)
                }
                // Check if playback has finished
                if !progress.isPlaying && progressUpdates.count > 0 {
                    expectation.fulfill()
                }
            }

        // When: Start reading
        service.startReading(paragraphs: paragraphs, from: 0)

        // Then: Wait for playback to complete (max 30 seconds for synthesis + playback)
        await fulfillment(of: [expectation], timeout: 30.0)

        cancellable.cancel()

        // Verify we got word-level progress updates spanning the entire paragraph
        // If only first sentence was played, we'd only see words from "First sentence here."
        XCTAssertGreaterThan(progressUpdates.count, 10, "Should have multiple word updates")

        // Check that we saw words from later sentences
        // This is the critical test - if we only played first sentence, we'd never see these
        let paragraphText = testParagraph
        let hasSecondSentenceWords = progressUpdates.contains { progress in
            guard let range = progress.wordRange else { return false }
            let word = String(paragraphText[range])
            return word.lowercased() == "second"
        }
        let hasThirdSentenceWords = progressUpdates.contains { progress in
            guard let range = progress.wordRange else { return false }
            let word = String(paragraphText[range])
            return word.lowercased() == "third"
        }

        XCTAssertTrue(hasSecondSentenceWords, "Should play words from second sentence")
        XCTAssertTrue(hasThirdSentenceWords, "Should play words from third sentence")
    }

    /// Test that streaming starts quickly (< 10s for first audio)
    func testTimeToFirstAudio() async throws {
        // Given: A long paragraph with multiple sentences
        let testParagraph = "First sentence here. Second sentence here. Third sentence here. Fourth sentence here."
        let paragraphs = [testParagraph]

        let startTime = Date()
        var firstAudioTime: TimeInterval?

        let expectation = XCTestExpectation(description: "First audio plays")
        expectation.expectedFulfillmentCount = 1

        // Monitor when playback actually starts
        let cancellable = service.$isPlaying
            .sink { isPlaying in
                if isPlaying && firstAudioTime == nil {
                    firstAudioTime = Date().timeIntervalSince(startTime)
                    expectation.fulfill()
                }
            }

        // When: Start reading
        service.startReading(paragraphs: paragraphs, from: 0)

        // Then: First audio should start within 10 seconds
        await fulfillment(of: [expectation], timeout: 10.0)

        cancellable.cancel()

        XCTAssertNotNil(firstAudioTime)
        XCTAssertLessThan(firstAudioTime!, 10.0, "Time to first audio should be < 10s")

        print("[SentenceStreamingTests] Time to first audio: \(String(format: "%.2f", firstAudioTime!))s")
    }
}
