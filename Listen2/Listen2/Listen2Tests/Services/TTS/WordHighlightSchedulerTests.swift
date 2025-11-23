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
}
