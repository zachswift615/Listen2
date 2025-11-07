//
//  TTSServiceTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class TTSServiceTests: XCTestCase {

    var service: TTSService!

    override func setUp() {
        super.setUp()
        service = TTSService()
    }

    override func tearDown() {
        service.stop()
        service = nil
        super.tearDown()
    }

    func testInitialization() {
        // Then
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentProgress.paragraphIndex, 0)
    }

    func testAvailableVoices_NotEmpty() {
        // When
        let voices = service.availableVoices()

        // Then
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.contains { $0.language.hasPrefix("en") })
    }

    func testSetPlaybackRate() {
        // When
        service.setPlaybackRate(1.5)

        // Then
        XCTAssertEqual(service.playbackRate, 1.5)
    }

    func testStartReading() {
        // Given
        let paragraphs = ["First paragraph.", "Second paragraph."]

        // When
        service.startReading(paragraphs: paragraphs, from: 0)

        // Then
        XCTAssertEqual(service.currentProgress.paragraphIndex, 0)

        // Wait briefly for speech to start
        let expectation = expectation(description: "Speech starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.service.isPlaying)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testPauseAndResume() {
        // Given
        service.startReading(paragraphs: ["Test text."], from: 0)

        // Wait for speech to start
        let startExpectation = expectation(description: "Speech starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // When
        service.pause()

        // Then
        XCTAssertFalse(service.isPlaying)

        // When
        service.resume()

        // Then - wait for resume
        let resumeExpectation = expectation(description: "Speech resumes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.service.isPlaying)
            resumeExpectation.fulfill()
        }
        wait(for: [resumeExpectation], timeout: 1.0)
    }
}
