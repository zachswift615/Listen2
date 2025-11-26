//
//  StreamingAudioPlayer.swift
//  Listen2
//
//  Audio player using AVAudioPlayer for background-compatible playback
//  Collects streamed chunks and plays them when ready
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
final class StreamingAudioPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0

    // MARK: - Private Properties

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var onFinished: (() -> Void)?

    // Audio format constants (matching sherpa-onnx output)
    private let sampleRate: Double = 22050
    private let channels: UInt16 = 1
    private let bitsPerSample: UInt16 = 32

    // Accumulate chunks for playback
    private var audioDataBuffer = Data()
    private var chunkCount: Int = 0

    // Temporary file management for background audio support
    private var currentTempFileURL: URL?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    deinit {
        player?.stop()
        displayLink?.invalidate()

        // Clean up temp file (deinit is nonisolated, so call directly)
        if let tempURL = currentTempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Playback Control

    /// Start new streaming session - prepares to receive chunks
    func startStreaming(onFinished: @escaping () -> Void) {
        stop()

        self.onFinished = onFinished
        audioDataBuffer = Data()
        chunkCount = 0
        isPlaying = true  // Mark as "playing" even while collecting chunks
    }

    /// Schedule an audio chunk for playback (accumulates until finishScheduling is called)
    func scheduleChunk(_ audioData: Data) {
        audioDataBuffer.append(audioData)
        chunkCount += 1
    }

    /// Mark that all chunks have been scheduled - starts actual playback
    func finishScheduling() {
        guard !audioDataBuffer.isEmpty else {
            isPlaying = false
            onFinished?()
            return
        }

        // Convert raw float32 PCM to WAV format
        let wavData = createWAVData(from: audioDataBuffer)

        do {
            // Write to temporary file (required for reliable background audio)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")

            try wavData.write(to: tempURL)

            // Clean up previous temp file
            cleanupTempFile()
            currentTempFileURL = tempURL

            // Initialize AVAudioPlayer from file URL (not Data - critical for background audio)
            player = try AVAudioPlayer(contentsOf: tempURL)
            player?.delegate = self
            player?.prepareToPlay()

            guard player?.play() == true else {
                throw StreamingAudioPlayerError.playbackFailed
            }

            isPlaying = true
            startDisplayLink()
        } catch {
            print("[StreamingAudioPlayer] ❌ Failed to start playback: \(error)")
            isPlaying = false
            onFinished?()
        }
    }

    /// Create WAV file data from raw float32 PCM samples
    private func createWAVData(from pcmData: Data) -> Data {
        var wavData = Data()

        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + dataSize)

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // Chunk size
        wavData.append(withUnsafeBytes(of: UInt16(3).littleEndian) { Data($0) })   // Audio format (3 = IEEE float)
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })    // Channels
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })  // Sample rate
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })    // Byte rate
        let blockAlign = channels * (bitsPerSample / 8)
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })  // Block align
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) }) // Bits per sample

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)

        return wavData
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopDisplayLink()
        onFinished = nil
        audioDataBuffer = Data()
        chunkCount = 0
        cleanupTempFile()
    }

    /// Clean up temporary audio file
    private func cleanupTempFile() {
        if let tempURL = currentTempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            currentTempFileURL = nil
        }
    }

    /// Emergency reset to clear any corrupted audio state
    func emergencyReset() {
        stop()
    }

    func setRate(_ rate: Float) {
        player?.enableRate = true
        player?.rate = rate
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

    // MARK: - Progress Tracking

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updateCurrentTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateCurrentTime() {
        currentTime = player?.currentTime ?? 0
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }
}

// MARK: - AVAudioPlayerDelegate

extension StreamingAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            stopDisplayLink()
            onFinished?()
        }
    }
}

// MARK: - Errors

enum StreamingAudioPlayerError: Error, LocalizedError {
    case playbackFailed
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to start streaming audio playback"
        case .invalidAudioData:
            return "Invalid audio data provided"
        }
    }
}
