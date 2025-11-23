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

    /// Sample rate of the audio (Piper TTS uses 22050 Hz)
    private let sampleRate: Double = 22050

    /// Currently highlighted word index (-1 = none)
    private var currentWordIndex: Int = -1

    /// Whether the scheduler is actively monitoring
    private(set) var isActive: Bool = false

    /// Callback when word changes
    var onWordChange: WordChangeHandler?

    // MARK: - Initialization

    init(alignment: AlignmentResult) {
        self.alignment = alignment
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

    #if DEBUG
    /// Test-only access to findWordIndex
    func testFindWordIndex(at time: TimeInterval) -> Int? {
        return findWordIndex(at: time)
    }
    #endif
}
