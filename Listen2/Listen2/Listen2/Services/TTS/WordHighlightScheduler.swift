//
//  WordHighlightScheduler.swift
//  Listen2
//
//  Schedules word highlight updates by monitoring audio playback position
//  via AVAudioEngine tap and comparing against CTC alignment data.
//

import Foundation
import AVFoundation

/// Schedules word highlight callbacks based on audio playback position.
/// Uses AVAudioPlayerNode tap to get frame-accurate timing.
@MainActor
final class WordHighlightScheduler {

    // MARK: - Types

    /// Callback when the highlighted word changes
    typealias WordChangeHandler = (AlignmentResult.WordTiming) -> Void

    // MARK: - Properties

    /// The alignment data for this sentence
    private let alignment: AlignmentResult

    /// The audio player node to install tap on
    private weak var playerNode: AVAudioPlayerNode?

    /// Sample rate of the audio (Piper TTS uses 22050 Hz)
    private let sampleRate: Double = 22050

    /// Currently highlighted word index (-1 = none)
    private var currentWordIndex: Int = -1

    /// Whether the scheduler is actively monitoring
    private(set) var isActive: Bool = false

    /// Callback when word changes
    var onWordChange: WordChangeHandler?

    // MARK: - Initialization

    init(playerNode: AVAudioPlayerNode, alignment: AlignmentResult) {
        self.playerNode = playerNode
        self.alignment = alignment
    }

    /// Convenience init for testing without playerNode
    init(alignment: AlignmentResult) {
        self.playerNode = nil
        self.alignment = alignment
    }

    // MARK: - Lifecycle

    /// Start monitoring audio playback for word highlighting
    func start() {
        guard !isActive else { return }
        installTap()
        isActive = true
    }

    /// Stop monitoring and clean up
    func stop() {
        guard isActive else { return }
        removeTap()
        isActive = false
        currentWordIndex = -1
    }

    // MARK: - Audio Tap

    private func installTap() {
        guard let playerNode = playerNode else {
            print("[WordHighlightScheduler] No playerNode available")
            return
        }

        // Get format from player node
        let format = playerNode.outputFormat(forBus: 0)

        // Install tap - callback runs on audio thread
        playerNode.installTap(
            onBus: 0,
            bufferSize: 1024,  // ~46ms at 22050Hz
            format: format
        ) { [weak self] buffer, time in
            // AUDIO THREAD - minimal work only!
            guard let self = self else { return }

            // Get frame position from audio time
            let framePosition = time.sampleTime

            // Dispatch to main thread for processing
            DispatchQueue.main.async {
                self.handleFramePosition(framePosition)
            }
        }

        print("[WordHighlightScheduler] Tap installed")
    }

    private func removeTap() {
        playerNode?.removeTap(onBus: 0)
        print("[WordHighlightScheduler] Tap removed")
    }

    // MARK: - Word Lookup

    /// Find the word index at a given time
    /// - Parameter time: Time in seconds from start of audio
    /// - Returns: Index of word being spoken, or nil if no words
    private func findWordIndex(at time: TimeInterval) -> Int? {
        guard !alignment.wordTimings.isEmpty else { return nil }

        // Before first word - return first word (audio is playing, highlight it)
        if time < alignment.wordTimings[0].startTime {
            return 0
        }

        // Find word containing this time
        for (index, timing) in alignment.wordTimings.enumerated() {
            if time >= timing.startTime && time < timing.endTime {
                return index
            }
        }

        // After all words - return last word
        if let last = alignment.wordTimings.last, time >= last.startTime {
            return alignment.wordTimings.count - 1
        }

        return nil
    }

    // MARK: - Frame Position Handling

    /// Handle a frame position update from the audio tap
    /// Called on main thread after dispatch from audio callback
    /// - Parameter framePosition: Current frame position in samples
    private func handleFramePosition(_ framePosition: Int64) {
        // Ignore callbacks that arrive after stop() was called
        // (they may have been queued before stop() but dispatched after)
        guard isActive else { return }

        // Convert frame position to seconds
        let currentTime = Double(framePosition) / sampleRate

        // Find which word should be highlighted
        guard let wordIndex = findWordIndex(at: currentTime) else { return }

        // Only emit if word changed
        if wordIndex != currentWordIndex {
            currentWordIndex = wordIndex
            let timing = alignment.wordTimings[wordIndex]
            onWordChange?(timing)
        }
    }

    #if DEBUG
    /// Track whether testDeactivate was called (for testing only)
    private var testWasDeactivated: Bool = false

    /// Test-only access to findWordIndex
    func testFindWordIndex(at time: TimeInterval) -> Int? {
        return findWordIndex(at: time)
    }

    /// Test-only access to handleFramePosition
    /// Automatically sets isActive = true to allow callbacks in test context,
    /// unless testDeactivate() was called (simulating stop())
    func testHandleFramePosition(_ framePosition: Int64) async {
        if !testWasDeactivated {
            isActive = true  // Allow callbacks without installing real tap
        }
        handleFramePosition(framePosition)
    }

    /// Test-only: manually deactivate scheduler (simulates stop() being called)
    func testDeactivate() {
        isActive = false
        currentWordIndex = -1
        testWasDeactivated = true
    }
    #endif
}
