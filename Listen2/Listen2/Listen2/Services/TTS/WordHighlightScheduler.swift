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

    /// Starting sample time when tap was installed (for relative position calculation)
    private var startSampleTime: Int64 = 0

    /// Scheduled work items for each word - cancelled on stop
    private var scheduledWorkItems: [DispatchWorkItem] = []

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
        isActive = true
        currentWordIndex = -1
        scheduleWordChanges()
    }

    /// Stop monitoring and clean up
    func stop() {
        guard isActive else { return }
        isActive = false
        cancelScheduledWorkItems()
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

        // Reset start time - will be captured on first callback
        startSampleTime = 0

        // Install tap - callback runs on audio thread
        // Use smaller buffer for more frequent callbacks (better short-word detection)
        playerNode.installTap(
            onBus: 0,
            bufferSize: 512,  // ~23ms at 22050Hz - should catch 50ms+ words
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

    /// Cancel all scheduled word change events
    private func cancelScheduledWorkItems() {
        let count = scheduledWorkItems.count
        for workItem in scheduledWorkItems {
            workItem.cancel()
        }
        scheduledWorkItems.removeAll()
        if count > 0 {
            print("[WordHighlightScheduler] Cancelled \(count) scheduled work items")
        }
    }

    /// Schedule word change callbacks at exact times
    /// Each word gets a DispatchWorkItem that fires at its startTime
    private func scheduleWordChanges() {
        // Cancel any existing scheduled items
        cancelScheduledWorkItems()

        guard !alignment.wordTimings.isEmpty else {
            print("[WordHighlightScheduler] No words to schedule")
            return
        }

        let startTime = DispatchTime.now()

        for (index, timing) in alignment.wordTimings.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isActive else { return }
                self.emitWordChange(at: index)
            }

            scheduledWorkItems.append(workItem)

            // Schedule at exact word start time
            let deadline = startTime + timing.startTime
            DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
        }

        print("[WordHighlightScheduler] Scheduled \(scheduledWorkItems.count) word changes")
    }

    /// Emit word change callback for word at index
    private func emitWordChange(at index: Int) {
        guard index >= 0 && index < alignment.wordTimings.count else { return }
        guard index != currentWordIndex else { return }  // Don't re-emit same word

        currentWordIndex = index
        let timing = alignment.wordTimings[index]
        print("[WordHighlightScheduler] Word \(index): '\(timing.text)' @ \(String(format: "%.3f", timing.startTime))s")
        onWordChange?(timing)
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
    /// - Parameter framePosition: Current frame position in samples (absolute since engine start)
    private func handleFramePosition(_ framePosition: Int64) {
        // Ignore callbacks that arrive after stop() was called
        // (they may have been queued before stop() but dispatched after)
        guard isActive else { return }

        // Capture start time on first callback
        if startSampleTime == 0 {
            startSampleTime = framePosition
            print("[WordHighlightScheduler] Captured startSampleTime=\(startSampleTime)")
        }

        // Convert RELATIVE frame position to seconds
        let relativeSamples = framePosition - startSampleTime
        let currentTime = Double(relativeSamples) / sampleRate

        // DEBUG: Log frame position and calculated time
        print("[WordHighlightScheduler] relativeTime=\(String(format: "%.3f", currentTime))s, totalDuration=\(String(format: "%.3f", alignment.totalDuration))s")

        // Find which word should be highlighted
        guard let wordIndex = findWordIndex(at: currentTime) else { return }

        // Only emit if word changed
        if wordIndex != currentWordIndex {
            currentWordIndex = wordIndex
            let timing = alignment.wordTimings[wordIndex]
            print("[WordHighlightScheduler] Word changed to index \(wordIndex): '\(timing.text)'")
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
