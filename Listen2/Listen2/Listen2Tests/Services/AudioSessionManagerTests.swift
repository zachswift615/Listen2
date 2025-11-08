//
//  AudioSessionManagerTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class AudioSessionManagerTests: XCTestCase {

    var manager: AudioSessionManager!

    override func setUp() {
        super.setUp()
        manager = AudioSessionManager()
    }

    override func tearDown() {
        // Deactivate session to clean up
        try? manager.deactivateSession()
        manager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        // Then
        XCTAssertFalse(manager.isSessionActive)
        XCTAssertFalse(manager.isInterrupted)
        XCTAssertNotEqual(manager.currentRoute, "Unknown")
    }

    // MARK: - Session Activation Tests

    func testActivateSession_Success() throws {
        // When
        try manager.activateSession()

        // Then
        XCTAssertTrue(manager.isSessionActive)
        XCTAssertFalse(manager.isInterrupted)

        // Verify audio session configuration
        let audioSession = AVAudioSession.sharedInstance()
        XCTAssertEqual(audioSession.category, .playback)
        XCTAssertEqual(audioSession.mode, .spokenAudio)
    }

    func testActivateSession_MultipleCalls() throws {
        // Given - First activation
        try manager.activateSession()
        XCTAssertTrue(manager.isSessionActive)

        // When - Second activation
        try manager.activateSession()

        // Then - Should still be active without errors
        XCTAssertTrue(manager.isSessionActive)
    }

    // MARK: - Session Deactivation Tests

    func testDeactivateSession_Success() throws {
        // Given
        try manager.activateSession()
        XCTAssertTrue(manager.isSessionActive)

        // When
        try manager.deactivateSession()

        // Then
        XCTAssertFalse(manager.isSessionActive)
    }

    func testDeactivateSession_WithoutPriorActivation() throws {
        // When - Deactivate without activating first
        // Then - Should not throw
        XCTAssertNoThrow(try manager.deactivateSession())
    }

    func testDeactivateSession_NotifyOthersOption() throws {
        // Given
        try manager.activateSession()

        // When - Deactivate with notifyOthers option
        XCTAssertNoThrow(try manager.deactivateSession(notifyOthers: true))
        XCTAssertFalse(manager.isSessionActive)

        // Activate again for second test
        try manager.activateSession()

        // When - Deactivate without notifying others
        XCTAssertNoThrow(try manager.deactivateSession(notifyOthers: false))
        XCTAssertFalse(manager.isSessionActive)
    }

    // MARK: - Route Change Tests

    func testCurrentRoute_ReflectsAudioOutput() throws {
        // Given
        try manager.activateSession()

        // Then - Route should be a valid output (typically Speaker or Receiver)
        XCTAssertFalse(manager.currentRoute.isEmpty)
        XCTAssertNotEqual(manager.currentRoute, "Unknown")
    }

    // MARK: - Reactivation Tests

    func testReactivateAfterInterruption() throws {
        // Given - Session is active
        try manager.activateSession()
        XCTAssertTrue(manager.isSessionActive)

        // Simulate interruption by deactivating
        try manager.deactivateSession()

        // When
        manager.reactivateAfterInterruption()

        // Then
        XCTAssertTrue(manager.isSessionActive)
        XCTAssertFalse(manager.isInterrupted)
    }

    // MARK: - Integration Tests

    func testSessionLifecycle() throws {
        // Test full lifecycle: activate -> deactivate -> reactivate

        // Activate
        try manager.activateSession()
        XCTAssertTrue(manager.isSessionActive)

        // Deactivate
        try manager.deactivateSession()
        XCTAssertFalse(manager.isSessionActive)

        // Reactivate
        try manager.activateSession()
        XCTAssertTrue(manager.isSessionActive)
    }

    func testAudioSessionConfiguration_BackgroundPlayback() throws {
        // When
        try manager.activateSession()

        // Then - Verify session is configured for background playback
        let audioSession = AVAudioSession.sharedInstance()

        // Category should be .playback for background audio
        XCTAssertEqual(audioSession.category, .playback)

        // Mode should be .spokenAudio for TTS optimization
        XCTAssertEqual(audioSession.mode, .spokenAudio)

        // Session should be active
        XCTAssertTrue(manager.isSessionActive)
    }

    // MARK: - Error Handling Tests

    func testErrorTypes_HaveDescriptions() {
        // Given
        let testError = NSError(domain: "TestDomain", code: 1, userInfo: nil)

        let activationError = AudioSessionManager.AudioSessionError.activationFailed(testError)
        let deactivationError = AudioSessionManager.AudioSessionError.deactivationFailed(testError)
        let configError = AudioSessionManager.AudioSessionError.categoryConfigurationFailed(testError)

        // Then - All errors should have descriptions
        XCTAssertNotNil(activationError.errorDescription)
        XCTAssertNotNil(deactivationError.errorDescription)
        XCTAssertNotNil(configError.errorDescription)

        XCTAssertTrue(activationError.errorDescription!.contains("activate"))
        XCTAssertTrue(deactivationError.errorDescription!.contains("deactivate"))
        XCTAssertTrue(configError.errorDescription!.contains("configure"))
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentActivation() throws {
        // Given
        let expectation = self.expectation(description: "Concurrent activation")
        expectation.expectedFulfillmentCount = 3

        // When - Activate from multiple threads
        DispatchQueue.global().async {
            try? self.manager.activateSession()
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            try? self.manager.activateSession()
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            try? self.manager.activateSession()
            expectation.fulfill()
        }

        // Then - Should handle concurrent calls gracefully
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(manager.isSessionActive)
    }
}
