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

        // Debug: Print first few word boundaries
        for (index, boundary) in wordBoundaries.prefix(5).enumerated() {
            print("[PhonemeTimelineBuilder] Word \(index): '\(boundary.word)' at \(boundary.startTime)s-\(boundary.endTime)s (chars \(boundary.originalStartOffset)-\(boundary.originalEndOffset))")
        }

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
        print("[PhonemeTimelineBuilder] Finding word boundaries...")
        print("  Original text: '\(originalText)'")
        print("  Normalized text: '\(normalizedText)'")
        print("  Phonemes: \(timedPhonemes.count)")
        print("  Char mappings: \(charMapping.count)")

        var boundaries: [PhonemeTimeline.WordBoundary] = []

        // Step 1: Split NORMALIZED text into words
        let normalizedWords = findWordsInNormalizedText(normalizedText)
        print("  Found \(normalizedWords.count) words in normalized text")

        // Step 2: For each normalized word, find its phonemes and map to original text
        for (normalizedWord, normalizedRange) in normalizedWords {
            // Find phonemes that belong to this normalized word
            let wordPhonemes = timedPhonemes.filter { phoneme in
                // Phoneme positions are in normalized text
                let phonemeRange = phoneme.normalizedRange
                // Check if phoneme overlaps with normalized word
                return phonemeRange.overlaps(normalizedRange)
            }

            guard !wordPhonemes.isEmpty else {
                print("  ⚠️ No phonemes for normalized word '\(normalizedWord)' at \(normalizedRange)")
                continue
            }

            // Get timing from phonemes
            let startTime = wordPhonemes.first!.startTime
            let endTime = wordPhonemes.last!.endTime

            // Map normalized position to original position
            let originalWord: String
            let originalStart: Int
            let originalEnd: Int

            if let mappedRange = mapNormalizedRangeToOriginal(
                normalizedRange: normalizedRange,
                charMapping: charMapping,
                originalText: originalText
            ) {
                originalStart = mappedRange.lowerBound
                originalEnd = mappedRange.upperBound

                // Extract word from original text
                let startIdx = originalText.index(originalText.startIndex, offsetBy: originalStart)
                let endIdx = originalText.index(originalText.startIndex, offsetBy: min(originalEnd, originalText.count))
                originalWord = String(originalText[startIdx..<endIdx])
            } else {
                // Fallback: use normalized word
                print("  ⚠️ Failed to map '\(normalizedWord)' to original text")
                originalWord = normalizedWord
                originalStart = 0
                originalEnd = normalizedWord.count
            }

            let boundary = PhonemeTimeline.WordBoundary(
                word: originalWord,
                startTime: startTime,
                endTime: endTime,
                originalStartOffset: originalStart,
                originalEndOffset: originalEnd,
                voxPDFWord: wordMap?.word(at: originalStart, in: paragraphIndex)
            )

            boundaries.append(boundary)
            print("  Word '\(originalWord)': \(startTime)-\(endTime)s")
        }

        // Sort by time to ensure correct order
        boundaries.sort { $0.startTime < $1.startTime }

        print("  Created \(boundaries.count) word boundaries")
        return boundaries
    }

    /// Find words in normalized text with their positions
    private static func findWordsInNormalizedText(_ text: String) -> [(word: String, range: Range<Int>)] {
        var words: [(String, Range<Int>)] = []
        let nsText = text as NSString

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byWords, .localized]
        ) { substring, substringRange, _, _ in
            if let word = substring {
                let range = substringRange.location..<(substringRange.location + substringRange.length)
                words.append((word, range))
            }
        }

        return words
    }

    /// Map a range in normalized text to a range in original text
    private static func mapNormalizedRangeToOriginal(
        normalizedRange: Range<Int>,
        charMapping: [(originalPos: Int, normalizedPos: Int)],
        originalText: String
    ) -> Range<Int>? {
        // Find the mapping for the start of the normalized range
        var originalStart: Int?
        var originalEnd: Int?

        // The charMapping contains pairs of (originalPos, normalizedPos)
        // We need to find entries where normalizedPos matches our range

        for mapping in charMapping {
            if mapping.normalizedPos == normalizedRange.lowerBound {
                originalStart = mapping.originalPos
            }
            if mapping.normalizedPos == normalizedRange.upperBound - 1 {
                originalEnd = mapping.originalPos + 1
            }
        }

        // If we couldn't find exact matches, try to interpolate
        if originalStart == nil || originalEnd == nil {
            // Find the closest mappings
            let sortedMappings = charMapping.sorted { $0.normalizedPos < $1.normalizedPos }

            if originalStart == nil {
                // Find the last mapping before or at our start position
                if let mapping = sortedMappings.last(where: { $0.normalizedPos <= normalizedRange.lowerBound }) {
                    originalStart = mapping.originalPos
                }
            }

            if originalEnd == nil {
                // Find the first mapping after or at our end position
                if let mapping = sortedMappings.first(where: { $0.normalizedPos >= normalizedRange.upperBound - 1 }) {
                    originalEnd = mapping.originalPos + 1
                } else if let lastMapping = sortedMappings.last {
                    // Use the last position if we're at the end
                    originalEnd = min(lastMapping.originalPos + 1, originalText.count)
                }
            }
        }

        guard let start = originalStart, let end = originalEnd else {
            return nil
        }

        return start..<end
    }


}