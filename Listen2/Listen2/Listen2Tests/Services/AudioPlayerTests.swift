//
//  AudioPlayerTests.swift
//  Listen2Tests
//
//  Tests for AudioPlayer with CADisplayLink-based time tracking
//

import XCTest
@testable import Listen2
import AVFoundation

@MainActor
final class AudioPlayerTests: XCTestCase {

    var sut: AudioPlayer!

    override func setUp() async throws {
        try await super.setUp()
        sut = AudioPlayer()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Display Link Time Tracking Tests

    func testCurrentTimeInitiallyZero() {
        // Given a new audio player
        // When checking initial time
        // Then it should be zero
        XCTAssertEqual(sut.currentTime, 0.0)
    }

    func testCurrentTimeUpdatesAfterPlay() async throws {
        // Given a test audio file
        let audioData = try createTestAudioData()

        // When playing audio
        let playExpectation = expectation(description: "Audio started playing")
        try sut.play(data: audioData) {
            // Completion handler
        }

        // Allow display link to update at least once
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then current time should be greater than zero
        XCTAssertGreaterThan(sut.currentTime, 0.0)
    }

    func testCurrentTimeResetsAfterStop() async throws {
        // Given a playing audio file
        let audioData = try createTestAudioData()
        try sut.play(data: audioData) {}

        // Wait for playback to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertGreaterThan(sut.currentTime, 0.0)

        // When stopping playback
        sut.stop()

        // Then current time should reset to zero
        XCTAssertEqual(sut.currentTime, 0.0)
    }

    func testCurrentTimeStopsUpdatingAfterPause() async throws {
        // Given a playing audio file
        let audioData = try createTestAudioData()
        try sut.play(data: audioData) {}

        // Wait for playback to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // When pausing playback
        sut.pause()
        let pausedTime = sut.currentTime

        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then current time should not advance
        XCTAssertEqual(sut.currentTime, pausedTime, accuracy: 0.01)
    }

    func testCurrentTimeResumesAfterPause() async throws {
        // Given a paused audio file
        let audioData = try createTestAudioData()
        try sut.play(data: audioData) {}
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        sut.pause()
        let pausedTime = sut.currentTime

        // When resuming playback
        sut.resume()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then current time should advance beyond paused time
        XCTAssertGreaterThan(sut.currentTime, pausedTime)
    }

    // MARK: - Display Link Cleanup Tests

    func testDisplayLinkStopsOnStop() async throws {
        // Given a playing audio file
        let audioData = try createTestAudioData()
        try sut.play(data: audioData) {}
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // When stopping
        sut.stop()

        // Then display link should be cleaned up (time shouldn't update)
        let stoppedTime = sut.currentTime // Should be 0
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(sut.currentTime, stoppedTime)
    }

    func testDisplayLinkStopsOnPause() async throws {
        // Given a playing audio file
        let audioData = try createTestAudioData()
        try sut.play(data: audioData) {}
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // When pausing
        sut.pause()
        let pausedTime = sut.currentTime

        // Then display link should be stopped (time shouldn't update)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(sut.currentTime, pausedTime, accuracy: 0.01)
    }

    // MARK: - Helper Methods

    /// Create a simple test audio data (1 second of silence at 16kHz)
    private func createTestAudioData() throws -> Data {
        let sampleRate: Double = 16000
        let duration: TimeInterval = 1.0
        let numSamples = Int(sampleRate * duration)

        // WAV header
        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + numSamples * 2)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) }) // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(numSamples * 2).littleEndian) { Data($0) })

        // Silence samples (all zeros)
        for _ in 0..<numSamples {
            data.append(contentsOf: withUnsafeBytes(of: Int16(0).littleEndian) { Data($0) })
        }

        return data
    }
}
