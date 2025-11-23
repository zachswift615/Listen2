//
//  WordHighlightSchedulerTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

@MainActor
final class WordHighlightSchedulerTests: XCTestCase {

    // MARK: - Test Helpers

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
            currentLocation += word.text.count + 1  // +1 for space between words
            return timing
        }
        let totalDuration = words.last.map { $0.start + $0.duration } ?? 0
        return AlignmentResult(
            paragraphIndex: 0,
            totalDuration: totalDuration,
            wordTimings: timings
        )
    }

    // MARK: - Tests

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

    func testFindWordIndexAtTime() {
        // Given
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),        // 0.0 - 0.1
            ("Knowledge", 0.1, 0.5),  // 0.1 - 0.6
            ("is", 0.6, 0.05)         // 0.6 - 0.65 (short word)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        // Then - exact start times
        XCTAssertEqual(scheduler.testFindWordIndex(at: 0.0), 0)   // Start of "The"
        XCTAssertEqual(scheduler.testFindWordIndex(at: 0.1), 1)   // Start of "Knowledge"
        XCTAssertEqual(scheduler.testFindWordIndex(at: 0.6), 2)   // Start of "is"

        // Mid-word times
        XCTAssertEqual(scheduler.testFindWordIndex(at: 0.05), 0)  // Mid "The"
        XCTAssertEqual(scheduler.testFindWordIndex(at: 0.3), 1)   // Mid "Knowledge"

        // Edge cases
        XCTAssertEqual(scheduler.testFindWordIndex(at: -0.1), 0)  // Before first word -> first word
        XCTAssertEqual(scheduler.testFindWordIndex(at: 1.0), 2)   // After last word -> last word
    }

    func testHandleFramePositionEmitsWordChange() async {
        // Given
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),
            ("Knowledge", 0.1, 0.5)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When - simulate frame positions (22050 Hz sample rate)
        // Frame 0 = time 0.0s -> "The"
        await scheduler.testHandleFramePosition(0)

        // Frame 2205 = time 0.1s -> "Knowledge"
        await scheduler.testHandleFramePosition(2205)

        // Frame 4410 = time 0.2s -> still "Knowledge" (no change)
        await scheduler.testHandleFramePosition(4410)

        // Then - should only emit when word changes
        XCTAssertEqual(receivedWords, ["The", "Knowledge"])
    }

    func testHandleFramePositionContinuesAfterPauseResume() async {
        // Given - simulates pause/resume where tap stops and restarts mid-word
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),
            ("Knowledge", 0.1, 0.5)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When - play starts
        await scheduler.testHandleFramePosition(0)      // "The" at 0.0s

        // Pause happens (no callbacks during pause)

        // Resume - tap fires again from where audio left off
        await scheduler.testHandleFramePosition(1103)   // Still "The" at 0.05s (mid-word)
        await scheduler.testHandleFramePosition(2205)   // "Knowledge" at 0.1s

        // Then - should emit "The" once (not again on resume), then "Knowledge"
        XCTAssertEqual(receivedWords, ["The", "Knowledge"])
    }

    func testHandleFramePositionIgnoredAfterDeactivation() async {
        // Given - scheduler that was stopped (simulates race condition)
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),
            ("Knowledge", 0.1, 0.5)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When - first callback works
        await scheduler.testHandleFramePosition(0)  // "The" - works, sets isActive = true

        // Then stop() is called (simulated)
        scheduler.testDeactivate()

        // More callbacks arrive (queued before stop() but delivered after)
        await scheduler.testHandleFramePosition(2205)  // Ignored because isActive = false

        // Then - only "The" received, "Knowledge" ignored
        XCTAssertEqual(receivedWords, ["The"])
    }
}
