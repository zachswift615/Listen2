//
//  PhonemeTimelineBuilder.swift
//  Listen2
//
//  Builds PhonemeTimeline from SynthesisResult with text normalization mapping
//

import Foundation

/// Builds phoneme timelines from synthesis results
struct PhonemeTimelineBuilder {

    /// Build a phoneme timeline from synthesis result
    /// - Parameters:
    ///   - synthesis: The synthesis result containing phonemes and mappings
    ///   - sentence: The original sentence text
    ///   - wordMap: Optional VoxPDF word map for enhanced word positions
    ///   - paragraphIndex: Index of the paragraph containing this sentence
    /// - Returns: PhonemeTimeline if successful, nil if phonemes are empty
    static func build(
        from synthesis: SynthesisResult,
        sentence: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> PhonemeTimeline? {
        // Guard against empty phonemes
        guard !synthesis.phonemes.isEmpty else {
            print("[PhonemeTimelineBuilder] No phonemes available for timeline")
            return nil
        }

        // Build timed phonemes with accumulated timing
        let timedPhonemes = buildTimedPhonemes(
            from: synthesis.phonemes,
            charMapping: synthesis.charMapping
        )

        // Find word boundaries
        let wordBoundaries = findWordBoundaries(
            timedPhonemes: timedPhonemes,
            originalText: sentence,
            normalizedText: synthesis.normalizedText,
            charMapping: synthesis.charMapping,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex
        )

        // Calculate total duration
        let totalDuration = timedPhonemes.last?.endTime ?? 0

        let timeline = PhonemeTimeline(
            sentenceText: sentence,
            normalizedText: synthesis.normalizedText,
            phonemes: timedPhonemes,
            wordBoundaries: wordBoundaries,
            duration: totalDuration
        )

        print("[PhonemeTimelineBuilder] Built timeline: \(timedPhonemes.count) phonemes, \(wordBoundaries.count) words, duration: \(totalDuration)s")

        return timeline
    }

    /// Build timed phonemes with accumulated timing
    private static func buildTimedPhonemes(
        from phonemes: [PhonemeInfo],
        charMapping: [(originalPos: Int, normalizedPos: Int)]
    ) -> [PhonemeTimeline.TimedPhoneme] {
        var timedPhonemes: [PhonemeTimeline.TimedPhoneme] = []
        var currentTime: TimeInterval = 0

        for phoneme in phonemes {
            // Map normalized range to original if possible
            let originalRange = mapToOriginal(
                normalizedRange: phoneme.textRange,
                using: charMapping
            )

            let timed = PhonemeTimeline.TimedPhoneme(
                symbol: phoneme.symbol,
                startTime: currentTime,
                endTime: currentTime + phoneme.duration,
                normalizedRange: phoneme.textRange,
                originalRange: originalRange
            )

            timedPhonemes.append(timed)
            currentTime += phoneme.duration
        }

        return timedPhonemes
    }

    /// Map a normalized text range to original text range
    private static func mapToOriginal(
        normalizedRange: Range<Int>,
        using charMapping: [(originalPos: Int, normalizedPos: Int)]
    ) -> Range<Int>? {
        // Find mapping for start position
        guard let startMapping = charMapping.first(where: {
            $0.normalizedPos == normalizedRange.lowerBound
        }) else { return nil }

        // Find mapping for end position (exclusive)
        // We look for normalizedPos == upperBound - 1 since upperBound is exclusive
        guard let endMapping = charMapping.first(where: {
            $0.normalizedPos == normalizedRange.upperBound - 1
        }) else { return nil }

        // Return inclusive range in original text
        return startMapping.originalPos..<(endMapping.originalPos + 1)
    }

    /// Find word boundaries by analyzing phoneme positions
    private static func findWordBoundaries(
        timedPhonemes: [PhonemeTimeline.TimedPhoneme],
        originalText: String,
        normalizedText: String,
        charMapping: [(originalPos: Int, normalizedPos: Int)],
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> [PhonemeTimeline.WordBoundary] {
        var boundaries: [PhonemeTimeline.WordBoundary] = []

        // Split text into words, preserving their positions
        let words = findWordsWithPositions(in: originalText)

        for (word, range) in words {
            // Find phonemes that overlap this word position
            let wordPhonemes = findPhonemesForWord(
                wordRange: range,
                timedPhonemes: timedPhonemes
            )

            // Skip words with no phonemes (e.g., punctuation only)
            guard !wordPhonemes.isEmpty else { continue }

            // Get timing from first and last phoneme
            let startTime = wordPhonemes.first!.startTime
            let endTime = wordPhonemes.last!.endTime

            // Find VoxPDF word if available
            let voxWord = wordMap?.word(at: range.lowerBound, in: paragraphIndex)

            let boundary = PhonemeTimeline.WordBoundary(
                word: word,
                startTime: startTime,
                endTime: endTime,
                originalStartOffset: range.lowerBound,
                originalEndOffset: range.upperBound,
                voxPDFWord: voxWord
            )

            boundaries.append(boundary)
        }

        // Sort by start time to ensure correct order
        boundaries.sort { $0.startTime < $1.startTime }

        return boundaries
    }

    /// Find words with their character positions in the text
    private static func findWordsWithPositions(in text: String) -> [(word: String, range: Range<Int>)] {
        var words: [(String, Range<Int>)] = []
        var currentIndex = 0

        // Use NSString for more accurate word boundary detection
        let nsText = text as NSString
        let options: NSString.EnumerationOptions = [
            .byWords,
            .localized
        ]

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: options
        ) { substring, substringRange, _, _ in
            if let word = substring {
                let range = substringRange.location..<(substringRange.location + substringRange.length)
                words.append((word, range))
            }
        }

        // If no words found (shouldn't happen), fall back to simple splitting
        if words.isEmpty {
            let components = text.components(separatedBy: .whitespacesAndNewlines)
            var offset = 0

            for component in components where !component.isEmpty {
                let range = offset..<(offset + component.count)
                words.append((component, range))
                offset += component.count

                // Account for separator
                if offset < text.count {
                    offset += 1
                }
            }
        }

        return words
    }

    /// Find phonemes that correspond to a word's character range
    private static func findPhonemesForWord(
        wordRange: Range<Int>,
        timedPhonemes: [PhonemeTimeline.TimedPhoneme]
    ) -> [PhonemeTimeline.TimedPhoneme] {
        return timedPhonemes.filter { phoneme in
            // Check if phoneme's original range overlaps with word range
            if let originalRange = phoneme.originalRange {
                // Check for any overlap
                let phonemeStart = originalRange.lowerBound
                let phonemeEnd = originalRange.upperBound
                let wordStart = wordRange.lowerBound
                let wordEnd = wordRange.upperBound

                // Overlap exists if phoneme ends after word starts AND phoneme starts before word ends
                return phonemeEnd > wordStart && phonemeStart < wordEnd
            }

            // If no original range mapping, skip this phoneme
            return false
        }
    }
}