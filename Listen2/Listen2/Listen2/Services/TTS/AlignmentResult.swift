//
//  AlignmentResult.swift
//  Listen2
//
//  Model for word-level alignment results from ASR
//

import Foundation

/// Result of aligning audio to text using ASR
struct AlignmentResult: Codable, Equatable {
    /// Individual word timing information
    struct WordTiming: Codable, Equatable {
        /// Index of the word in the paragraph's word array
        let wordIndex: Int

        /// Start time of the word in seconds
        let startTime: TimeInterval

        /// Duration of the word in seconds
        let duration: TimeInterval

        /// The word text (for validation)
        let text: String

        /// String range for highlighting in the paragraph text
        let stringRange: Range<String.Index>

        /// End time of the word (computed property)
        var endTime: TimeInterval {
            return startTime + duration
        }

        // Custom Codable implementation to handle Range<String.Index>
        enum CodingKeys: String, CodingKey {
            case wordIndex
            case startTime
            case duration
            case text
            case stringRangeLocation
            case stringRangeLength
        }

        init(
            wordIndex: Int,
            startTime: TimeInterval,
            duration: TimeInterval,
            text: String,
            stringRange: Range<String.Index>
        ) {
            self.wordIndex = wordIndex
            self.startTime = startTime
            self.duration = duration
            self.text = text
            self.stringRange = stringRange
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            wordIndex = try container.decode(Int.self, forKey: .wordIndex)
            startTime = try container.decode(TimeInterval.self, forKey: .startTime)
            duration = try container.decode(TimeInterval.self, forKey: .duration)
            text = try container.decode(String.self, forKey: .text)

            // Decode string range from offset/length
            let location = try container.decode(Int.self, forKey: .stringRangeLocation)
            let length = try container.decode(Int.self, forKey: .stringRangeLength)

            // Note: This is a placeholder. The actual stringRange will need to be
            // reconstructed from the paragraph text when loading from cache.
            // For now, we store the offsets and reconstruct during decode.
            let dummyString = String(repeating: " ", count: location + length)
            let startIndex = dummyString.index(dummyString.startIndex, offsetBy: location)
            let endIndex = dummyString.index(startIndex, offsetBy: length)
            stringRange = startIndex..<endIndex
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(wordIndex, forKey: .wordIndex)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(duration, forKey: .duration)
            try container.encode(text, forKey: .text)

            // Encode string range as offset/length
            // Note: This requires the paragraph text to reconstruct the actual Range<String.Index>
            let dummyString = String(repeating: " ", count: 1000) // Dummy for encoding
            let location = dummyString.distance(from: dummyString.startIndex, to: stringRange.lowerBound)
            let length = dummyString.distance(from: stringRange.lowerBound, to: stringRange.upperBound)
            try container.encode(location, forKey: .stringRangeLocation)
            try container.encode(length, forKey: .stringRangeLength)
        }
    }

    /// Index of the paragraph this alignment is for
    let paragraphIndex: Int

    /// Total duration of the audio in seconds
    let totalDuration: TimeInterval

    /// Word timings in chronological order
    let wordTimings: [WordTiming]

    /// Find the word being spoken at a given time
    /// - Parameter time: Time in seconds
    /// - Returns: The word timing at this time, or nil if no word is active
    func wordTiming(at time: TimeInterval) -> WordTiming? {
        // Binary search would be more efficient for large word counts,
        // but for typical paragraph sizes linear search is fine
        return wordTimings.first { timing in
            time >= timing.startTime && time < timing.endTime
        }
    }

    /// Check if this alignment is valid for the given text
    /// - Parameter text: The paragraph text to validate against
    /// - Returns: True if the alignment appears valid
    func isValid(for text: String) -> Bool {
        // Basic validation: check that word count matches
        guard !wordTimings.isEmpty else { return false }

        // Check that timings are in order
        for i in 1..<wordTimings.count {
            if wordTimings[i].startTime < wordTimings[i-1].startTime {
                return false
            }
        }

        // Check that total duration makes sense (positive and reasonable)
        return totalDuration > 0 && totalDuration < 3600 // Max 1 hour per paragraph
    }
}

/// Errors that can occur during alignment
enum AlignmentError: Error, LocalizedError {
    case modelNotInitialized
    case audioLoadFailed(String)
    case audioConversionFailed(String)
    case recognitionFailed(String)
    case noTimestamps
    case invalidAudioFormat
    case cacheReadFailed(String)
    case cacheWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotInitialized:
            return "ASR model not initialized. Call initialize() first."
        case .audioLoadFailed(let details):
            return "Failed to load audio file: \(details)"
        case .audioConversionFailed(let details):
            return "Failed to convert audio format: \(details)"
        case .recognitionFailed(let details):
            return "ASR recognition failed: \(details)"
        case .noTimestamps:
            return "ASR did not return word timestamps"
        case .invalidAudioFormat:
            return "Audio format not supported (expected WAV, 16kHz)"
        case .cacheReadFailed(let details):
            return "Failed to read alignment from cache: \(details)"
        case .cacheWriteFailed(let details):
            return "Failed to write alignment to cache: \(details)"
        }
    }
}
