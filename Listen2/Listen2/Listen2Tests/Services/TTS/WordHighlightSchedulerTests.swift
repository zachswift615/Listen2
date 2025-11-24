//
//  WordHighlightSchedulerTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class WordHighlightSchedulerTests: XCTestCase {

    // MARK: - Test Helpers

    @MainActor
    private func makeAlignment(words: [(text: String, start: Double, duration: Double)]) -> AlignmentResult {
        var currentLocation = 0
        let timings = words.enumerated().map { index, word in
            let timing = AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: word.start,
                duration: word.duration,
                text: word.text,
                rangeLocation: currentLocation,
                rangeLength: word.text.count
            )
            currentLocation += word.text.count + 1
            return timing
        }
        let totalDuration = words.last.map { $0.start + $0.duration } ?? 0
        return AlignmentResult(
            paragraphIndex: 0,
            totalDuration: totalDuration,
            wordTimings: timings
        )
    }

    // MARK: - Initialization Tests

    @MainActor
    func testSchedulerInitializesWithAlignment() {
        // Given
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),
            ("Knowledge", 0.1, 0.5)
        ])

        // When
        let scheduler = WordHighlightScheduler(alignment: alignment)

        // Then
        XCTAssertNotNil(scheduler)
        XCTAssertFalse(scheduler.isActive)
    }

    @MainActor
    func testSchedulerBecomesActiveOnStart() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        // When
        scheduler.start()

        // Then
        XCTAssertTrue(scheduler.isActive)

        // Cleanup
        scheduler.stop()
    }

    @MainActor
    func testSchedulerBecomesInactiveOnStop() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)
        scheduler.start()

        // When
        scheduler.stop()

        // Then
        XCTAssertFalse(scheduler.isActive)
    }

    // MARK: - Scheduled Events Tests

    @MainActor
    func testFirstWordEmittedImmediately() {
        // Given - word starts at 0.0s
        let alignment = makeAlignment(words: [
            ("Hello", 0.0, 0.2),
            ("World", 0.2, 0.3)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "First word emitted")
        var receivedWord: String?

        scheduler.onWordChange = { timing in
            if receivedWord == nil {
                receivedWord = timing.text
                expectation.fulfill()
            }
        }

        // When
        scheduler.start()

        // Then - first word should emit almost immediately
        let result = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(receivedWord, "Hello")

        // Cleanup
        scheduler.stop()
    }

    @MainActor
    func testAllWordsEmittedInOrder() {
        // Given - 3 words with short durations
        let alignment = makeAlignment(words: [
            ("One", 0.0, 0.05),
            ("Two", 0.05, 0.05),
            ("Three", 0.1, 0.05)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "All words emitted")
        expectation.expectedFulfillmentCount = 3
        var receivedWords: [String] = []

        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
            expectation.fulfill()
        }

        // When
        scheduler.start()

        // Then - all 3 words should emit within 500ms
        let result = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(receivedWords, ["One", "Two", "Three"])

        // Cleanup
        scheduler.stop()
    }

    @MainActor
    func testShortWordsNotSkipped() {
        // Given - simulate "I met a" with short "a" (30ms)
        let alignment = makeAlignment(words: [
            ("I", 0.0, 0.03),
            ("met", 0.03, 0.03),
            ("a", 0.06, 0.03)      // Very short word!
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "All words including short 'a'")
        expectation.expectedFulfillmentCount = 3
        var receivedWords: [String] = []

        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
            expectation.fulfill()
        }

        // When
        scheduler.start()

        // Then - all 3 words including short "a" should emit
        let result = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(receivedWords, ["I", "met", "a"])

        // Cleanup
        scheduler.stop()
    }

    @MainActor
    func testStopCancelsScheduledEvents() {
        // Given - word that would emit after 200ms
        let alignment = makeAlignment(words: [
            ("First", 0.0, 0.05),
            ("Later", 0.2, 0.1)  // Should NOT emit if stopped before 0.2s
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []

        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When - start scheduler, first word fires immediately at t=0
        scheduler.start()

        // Stop immediately (before second word at 200ms)
        scheduler.stop()

        // Verify first word was received
        XCTAssertEqual(receivedWords, ["First"])
    }

    @MainActor
    func testEmptyAlignmentDoesNotCrash() {
        // Given
        let alignment = makeAlignment(words: [])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When
        scheduler.start()

        // Wait a bit using XCTWaiter with inverted expectation
        let waitExpectation = XCTestExpectation(description: "Wait")
        waitExpectation.isInverted = true
        let _ = XCTWaiter.wait(for: [waitExpectation], timeout: 0.1)

        // Then - no crashes, no emissions
        XCTAssertEqual(receivedWords, [])
        XCTAssertTrue(scheduler.isActive)

        scheduler.stop()
    }

    @MainActor
    func testDoubleStartIsIdempotent() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "Word emitted")
        var emitCount = 0

        scheduler.onWordChange = { _ in
            emitCount += 1
            expectation.fulfill()
        }

        // When - start twice
        scheduler.start()
        scheduler.start()

        // Wait for emission
        let result = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .completed)

        // Wait a bit more to make sure no extra emissions
        let waitExpectation = XCTestExpectation(description: "Wait for potential extra")
        waitExpectation.isInverted = true
        let _ = XCTWaiter.wait(for: [waitExpectation], timeout: 0.2)

        // Then - should only emit once
        XCTAssertEqual(emitCount, 1)

        // Cleanup
        scheduler.stop()
    }
}
