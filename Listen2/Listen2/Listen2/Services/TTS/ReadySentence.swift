//
//  ReadySentence.swift
//  Listen2
//
//  Model for a fully-processed sentence ready for playback
//

import Foundation

/// A sentence that has completed both synthesis AND alignment (when enabled)
/// and is ready for immediate playback
struct ReadySentence: Sendable {
    /// Unique key for this sentence
    let key: SentenceKey

    /// Audio chunks (raw Float32 samples from streaming synthesis)
    let chunks: [Data]

    /// CTC forced alignment result with word timings (nil if highlighting disabled)
    let alignment: AlignmentResult?

    /// Original sentence text
    let text: String

    /// Character offset where this sentence starts in the paragraph
    let sentenceOffset: Int

    /// Combined audio data (computed from chunks)
    var combinedAudio: Data {
        chunks.reduce(Data()) { $0 + $1 }
    }

    /// Total audio duration in seconds (from alignment or estimated)
    var audioDuration: TimeInterval {
        alignment?.totalDuration ?? estimatedDuration
    }

    /// Estimated duration based on audio samples
    private var estimatedDuration: TimeInterval {
        let totalSamples = chunks.reduce(0) { $0 + $1.count / MemoryLayout<Float>.size }
        return TimeInterval(totalSamples) / Double(ReadyQueueConstants.sampleRate)
    }
}

/// Key for identifying a sentence in the pipeline
struct SentenceKey: Hashable, CustomStringConvertible, Sendable {
    let paragraphIndex: Int
    let sentenceIndex: Int

    var description: String {
        "P\(paragraphIndex)S\(sentenceIndex)"
    }
}

/// Configurable constants for buffer limits - tune these as needed
enum ReadyQueueConstants {
    /// Maximum sentences to buffer ahead
    static let maxSentenceLookahead: Int = 5

    /// Maximum paragraphs to keep in sliding window
    static let maxParagraphWindow: Int = 5

    /// Maximum buffer size in bytes (~10MB)
    static let maxBufferBytes: Int = 10 * 1024 * 1024

    /// Maximum wait time for a sentence (30 seconds)
    static let maxWaitIterations: Int = 600

    /// Wait interval in nanoseconds (50ms)
    static let waitIntervalNanos: UInt64 = 50_000_000

    /// Pipeline idle sleep interval in nanoseconds (100ms)
    static let pipelineIdleIntervalNanos: UInt64 = 100_000_000

    /// Piper TTS sample rate
    static let sampleRate: Int = 22050
}
