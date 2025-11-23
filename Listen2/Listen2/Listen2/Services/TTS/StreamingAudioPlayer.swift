//
//  StreamingAudioPlayer.swift
//  Listen2
//
//  Streaming audio player using AVAudioEngine for chunk-level playback
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

    private let audioEngine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    private var displayLink: CADisplayLink?
    private var onFinished: (() -> Void)?
    private var currentFormat: AVAudioFormat?

    // Track scheduled buffers to know when playback completes
    private var scheduledBufferCount: Int = 0
    private var playedBufferCount: Int = 0
    private var allBuffersScheduled: Bool = false

    // Track total duration for progress
    private var totalDuration: TimeInterval = 0
    private var startTime: TimeInterval = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
    }

    deinit {
        // CRITICAL: Clean up audio engine to prevent system audio corruption
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
        displayLink?.invalidate()
        print("[StreamingAudioPlayer] 🧹 Deinitialized and cleaned up audio engine")
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // Attach player node to engine
        audioEngine.attach(playerNode)

        // Create format: 22050 Hz, mono, float32
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: 1,
            interleaved: false
        ) else {
            print("[StreamingAudioPlayer] ❌ Failed to create audio format")
            return
        }

        currentFormat = format

        // Connect player node to main mixer
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: format
        )

        // Prepare and start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[StreamingAudioPlayer] ✅ Audio engine started")
        } catch {
            print("[StreamingAudioPlayer] ❌ Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Playback Control

    /// Start new streaming session
    func startStreaming(onFinished: @escaping () -> Void) {
        stop()

        self.onFinished = onFinished
        scheduledBufferCount = 0
        playedBufferCount = 0
        allBuffersScheduled = false
        totalDuration = 0
        startTime = CACurrentMediaTime()

        // Start player node
        playerNode.play()
        isPlaying = true
        startDisplayLink()

        print("[StreamingAudioPlayer] 🎬 Started streaming session")
    }

    /// Schedule an audio chunk for playback
    func scheduleChunk(_ audioData: Data) {
        guard let format = currentFormat else {
            print("[StreamingAudioPlayer] ❌ No audio format available")
            return
        }

        // Convert Data (float32 samples) to AVAudioPCMBuffer
        let sampleCount = audioData.count / MemoryLayout<Float>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            print("[StreamingAudioPlayer] ❌ Failed to create buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Copy samples to buffer
        audioData.withUnsafeBytes { rawPtr in
            guard let floatPtr = rawPtr.baseAddress?.assumingMemoryBound(to: Float.self) else {
                return
            }
            guard let channelData = buffer.floatChannelData else {
                return
            }
            channelData[0].update(from: floatPtr, count: sampleCount)
        }

        // Calculate chunk duration
        let chunkDuration = Double(sampleCount) / format.sampleRate
        totalDuration += chunkDuration

        scheduledBufferCount += 1
        let bufferID = scheduledBufferCount

        // Schedule buffer with completion handler
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.onBufferComplete(bufferID: bufferID)
            }
        }

        print("[StreamingAudioPlayer] 📦 Scheduled chunk #\(bufferID): \(sampleCount) samples (\(String(format: "%.3f", chunkDuration))s)")
    }

    /// Mark that all chunks have been scheduled
    func finishScheduling() {
        allBuffersScheduled = true
        print("[StreamingAudioPlayer] ✅ All buffers scheduled (total: \(scheduledBufferCount), duration: \(String(format: "%.3f", totalDuration))s)")

        // Check if already complete (for very short audio)
        checkCompletion()
    }

    private func onBufferComplete(bufferID: Int) {
        playedBufferCount += 1
        print("[StreamingAudioPlayer] ✓ Buffer #\(bufferID) complete (played: \(playedBufferCount)/\(scheduledBufferCount))")

        checkCompletion()
    }

    private func checkCompletion() {
        if allBuffersScheduled && playedBufferCount >= scheduledBufferCount {
            print("[StreamingAudioPlayer] 🏁 All buffers played, calling onFinished")
            isPlaying = false
            stopDisplayLink()
            onFinished?()
        }
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        totalDuration = 0
        stopDisplayLink()
        onFinished = nil
        scheduledBufferCount = 0
        playedBufferCount = 0
        allBuffersScheduled = false
    }

    /// Emergency reset to clear any corrupted audio state
    /// Call this if audio becomes distorted or corrupted
    func emergencyReset() {
        print("[StreamingAudioPlayer] 🚨 Emergency reset initiated")
        stop()
        audioEngine.stop()
        audioEngine.reset()

        // Re-setup the audio engine from scratch
        setupAudioEngine()
        print("[StreamingAudioPlayer] ✅ Emergency reset complete")
    }

    func setRate(_ rate: Float) {
        // TODO: Implement playback rate control for streaming audio
        // This requires AVAudioEngine rate adjustment which is more complex than AVAudioPlayer
        print("[StreamingAudioPlayer] ⚠️ setRate not yet implemented for chunk streaming (rate: \(rate))")
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopDisplayLink()
        print("[StreamingAudioPlayer] ⏸️ Paused")
    }

    func resume() {
        playerNode.play()
        isPlaying = true
        startDisplayLink()
        print("[StreamingAudioPlayer] ▶️ Resumed")
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
        if isPlaying {
            // FIX: Use actual audio position from AVAudioPlayerNode instead of wall-clock time
            // This ensures accurate timing even after pause/resume and avoids drift
            if let nodeTime = playerNode.lastRenderTime,
               nodeTime.isSampleTimeValid,
               let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            } else {
                // Fallback to wall-clock elapsed time if node time unavailable
                let elapsed = CACurrentMediaTime() - startTime
                currentTime = elapsed
            }
        }
    }

    var duration: TimeInterval {
        totalDuration
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
