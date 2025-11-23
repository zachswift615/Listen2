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
}
