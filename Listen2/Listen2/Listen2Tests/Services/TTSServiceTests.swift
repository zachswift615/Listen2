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
}
