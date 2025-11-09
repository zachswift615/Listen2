//
//  AudioPlayer.swift
//  Listen2
//
//  Audio playback wrapper for TTS-generated WAV data
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0

    // MARK: - Private Properties

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
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

        // Start playback
        guard player?.play() == true else {
            throw AudioPlayerError.playbackFailed
        }

        isPlaying = true
        startProgressTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func resume() {
        guard let player = player, !player.isPlaying else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopProgressTimer()
        onFinished = nil
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    // MARK: - Progress Tracking

    private func startProgressTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updateProgress() {
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
            stopProgressTimer()
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
