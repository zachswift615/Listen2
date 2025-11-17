//
//  AudioPlayer.swift
//  Listen2
//
//  Audio playback wrapper for TTS-generated WAV data
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
final class AudioPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0

    // MARK: - Private Properties

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var onFinished: (() -> Void)?

    // MARK: - Playback Control

    func play(data: Data, onFinished: @escaping () -> Void) throws {
        // Stop any existing playback
        stop()

        // Create player from WAV data
        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()

        self.onFinished = onFinished

        // Log actual audio duration from WAV file
        if let actualDuration = player?.duration {
            print("[AudioPlayer] 🎵 Actual WAV duration: \(String(format: "%.3f", actualDuration))s (from AVAudioPlayer)")
        }

        // Start playback
        guard player?.play() == true else {
            throw AudioPlayerError.playbackFailed
        }

        isPlaying = true
        startDisplayLink()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopDisplayLink()
    }

    func resume() {
        guard let player = player, !player.isPlaying else { return }
        player.play()
        isPlaying = true
        startDisplayLink()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopDisplayLink()
        onFinished = nil
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    // MARK: - Progress Tracking

    /// Start CADisplayLink for smooth 60 FPS time updates
    private func startDisplayLink() {
        // Clean up any existing display link
        stopDisplayLink()

        // Create display link targeting the update method
        displayLink = CADisplayLink(target: self, selector: #selector(updateCurrentTime))

        // Add to main run loop for UI updates
        displayLink?.add(to: .main, forMode: .common)
    }

    /// Stop and clean up display link
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Called by CADisplayLink at ~60 FPS to update current time
    @objc private func updateCurrentTime() {
        currentTime = player?.currentTime ?? 0
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            stopDisplayLink()
            onFinished?()
        }
    }
}

// MARK: - Errors

enum AudioPlayerError: Error, LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to start audio playback"
        }
    }
}
