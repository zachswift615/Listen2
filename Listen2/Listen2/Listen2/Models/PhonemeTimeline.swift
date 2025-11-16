//
//  PhonemeTimeline.swift
//  Listen2
//
//  Phoneme timeline for word-level highlighting during TTS playback
//

import Foundation

/// Timeline of phonemes and word boundaries for a sentence
struct PhonemeTimeline: Codable {
    let sentenceText: String           // Original sentence text
    let normalizedText: String          // After espeak normalization
    let phonemes: [TimedPhoneme]       // Phonemes with relative times
    let wordBoundaries: [WordBoundary] // Word start/end times
    let duration: TimeInterval          // Total sentence duration

    /// A phoneme with timing information relative to sentence start
    struct TimedPhoneme: Codable {
        let symbol: String                  // IPA phoneme symbol
        let startTime: TimeInterval         // Relative to sentence start
        let endTime: TimeInterval           // startTime + duration
        let normalizedRange: Range<Int>     // Position in normalized text
        let originalRange: Range<Int>?      // Position in original (via mapping)

        var duration: TimeInterval {
            endTime - startTime
        }
    }

    /// Word boundary with timing and position information
    struct WordBoundary: Codable {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let originalStartOffset: Int        // Character offset in original text
        let originalEndOffset: Int          // End offset in original text
        let voxPDFWord: WordPosition?       // VoxPDF word data if available

        var duration: TimeInterval {
            endTime - startTime
        }

        /// Get String.Index range for highlighting
        func stringRange(in text: String) -> Range<String.Index>? {
            guard originalStartOffset >= 0,
                  originalEndOffset <= text.count,
                  originalStartOffset < originalEndOffset else {
                return nil
            }

            let startIndex = text.index(text.startIndex, offsetBy: originalStartOffset)
            let endIndex = text.index(text.startIndex, offsetBy: originalEndOffset)
            return startIndex..<endIndex
        }
    }

    /// Find the active word at a given time offset using binary search
    func findWord(at timeOffset: TimeInterval) -> WordBoundary? {
        // Handle edge cases
        guard !wordBoundaries.isEmpty else { return nil }
        guard timeOffset >= 0 else { return nil }
        guard timeOffset < duration else { return wordBoundaries.last }

        // Binary search for efficiency
        var left = 0
        var right = wordBoundaries.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let word = wordBoundaries[mid]

            if timeOffset >= word.startTime && timeOffset < word.endTime {
                return word
            } else if timeOffset < word.startTime {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }

        // If we're between words, return the previous word
        // This keeps highlighting stable during inter-word gaps
        if left > 0 {
            return wordBoundaries[left - 1]
        }

        return nil
    }

    /// Find the active phoneme at a given time offset
    func findPhoneme(at timeOffset: TimeInterval) -> TimedPhoneme? {
        // Binary search similar to findWord
        guard !phonemes.isEmpty else { return nil }
        guard timeOffset >= 0 else { return nil }
        guard timeOffset < duration else { return phonemes.last }

        var left = 0
        var right = phonemes.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let phoneme = phonemes[mid]

            if timeOffset >= phoneme.startTime && timeOffset < phoneme.endTime {
                return phoneme
            } else if timeOffset < phoneme.startTime {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }

        return nil
    }
}

/// Bundle of sentence audio with phoneme timeline
struct SentenceBundle {
    let chunk: TextChunk              // Sentence text and metadata
    let audioData: Data               // WAV audio data
    let timeline: PhonemeTimeline?   // Optional - may fail to generate
    let paragraphIndex: Int
    let sentenceIndex: Int

    var sentenceKey: String {
        "\(paragraphIndex)-\(sentenceIndex)"
    }

    var hasTiming: Bool {
        timeline != nil
    }
}