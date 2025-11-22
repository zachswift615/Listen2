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

        /// Store range as integers for Codable
        internal let rangeLocation: Int
        internal let rangeLength: Int

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
            case rangeLocation
            case rangeLength
        }

        init(
            wordIndex: Int,
            startTime: TimeInterval,
            duration: TimeInterval,
            text: String,
            rangeLocation: Int,
            rangeLength: Int
        ) {
            self.wordIndex = wordIndex
            self.startTime = startTime
            self.duration = duration
            self.text = text
            self.rangeLocation = rangeLocation
            self.rangeLength = rangeLength
        }

        /// Reconstruct string range from paragraph text
        /// - Parameter text: The actual paragraph text
        /// - Returns: The string range in the paragraph text, or nil if offsets are invalid
        func stringRange(in text: String) -> Range<String.Index>? {
            guard let start = text.index(text.startIndex, offsetBy: rangeLocation, limitedBy: text.endIndex),
                  let end = text.index(start, offsetBy: rangeLength, limitedBy: text.endIndex) else {
                return nil
            }
            return start..<end
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
        // Use binary search for O(log n) performance
        // Word timings are guaranteed to be sorted by startTime
        guard !wordTimings.isEmpty else { return nil }

        // Handle time before first word or after last word
        if time < wordTimings[0].startTime {
            return nil
        }
        if time >= wordTimings[wordTimings.count - 1].endTime {
            // Return last word if we're past the end (prevents getting stuck)
            return wordTimings.last
        }

        // Binary search to find the word at the given time
        var left = 0
        var right = wordTimings.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let timing = wordTimings[mid]

            // Add small tolerance (1ms) for floating point precision
            let tolerance: TimeInterval = 0.001

            if time >= timing.startTime - tolerance && time < timing.endTime + tolerance {
                // Found the word
                return timing
            } else if time < timing.startTime {
                // Search left half
                right = mid - 1
            } else {
                // time >= timing.endTime, search right half
                left = mid + 1
            }
        }

        // If binary search fails (shouldn't happen), fall back to linear search
        // This handles edge cases where timing boundaries might be imprecise
        for timing in wordTimings {
            if time >= timing.startTime && time < timing.endTime {
                return timing
            }
        }

        // If still no match and we're between words, return the closest word
        // This prevents getting "stuck" between words
        for i in 0..<wordTimings.count - 1 {
            if time >= wordTimings[i].endTime && time < wordTimings[i + 1].startTime {
                // Between words i and i+1, return the next word
                return wordTimings[i + 1]
            }
        }

        return nil
    }

    /// Check if this alignment is valid for the given text
    /// - Parameter text: The paragraph text to validate against
    /// - Returns: True if the alignment appears valid
    func isValid(for text: String) -> Bool {
        // Allow empty wordTimings until Task 5 implements mapping
        guard totalDuration > 0 && totalDuration < 3600 else { return false }

        // If we have wordTimings, validate they're in order
        for i in 1..<wordTimings.count {
            if wordTimings[i].startTime < wordTimings[i-1].startTime {
                return false
            }
        }

        return true
    }
}

/// Errors that can occur during alignment
enum AlignmentError: Error, LocalizedError, Equatable {
    case modelNotInitialized
    case audioLoadFailed(String)
    case audioConversionFailed(String)
    case recognitionFailed(String)
    case noTimestamps
    case invalidAudioFormat
    case cacheReadFailed(String)
    case cacheWriteFailed(String)
    case emptyAudio
    case inferenceFailed(String)

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
        case .emptyAudio:
            return "Audio samples array is empty or too short for alignment"
        case .inferenceFailed(let details):
            return "ONNX model inference failed: \(details)"
        }
    }
}
