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
        var boundaries: [PhonemeTimeline.WordBoundary] = []

        // Alternative approach: Group phonemes into words based on timing gaps
        // This avoids the complexity of mapping between normalized and original text
        var currentWordPhonemes: [PhonemeTimeline.TimedPhoneme] = []
        var currentWordStart: TimeInterval = 0
        let gapThreshold: TimeInterval = 0.05 // 50ms gap indicates word boundary

        for (index, phoneme) in timedPhonemes.enumerated() {
            if currentWordPhonemes.isEmpty {
                // Start new word
                currentWordPhonemes.append(phoneme)
                currentWordStart = phoneme.startTime
            } else {
                // Check if there's a gap indicating word boundary
                let previousEnd = currentWordPhonemes.last!.endTime
                let gap = phoneme.startTime - previousEnd

                if gap > gapThreshold {
                    // Gap detected - finish current word
                    if let wordBoundary = createWordBoundary(
                        from: currentWordPhonemes,
                        in: originalText,
                        wordMap: wordMap,
                        paragraphIndex: paragraphIndex
                    ) {
                        boundaries.append(wordBoundary)
                    }

                    // Start new word
                    currentWordPhonemes = [phoneme]
                    currentWordStart = phoneme.startTime
                } else {
                    // Continue current word
                    currentWordPhonemes.append(phoneme)
                }
            }
        }

        // Don't forget the last word
        if !currentWordPhonemes.isEmpty {
            if let wordBoundary = createWordBoundary(
                from: currentWordPhonemes,
                in: originalText,
                wordMap: wordMap,
                paragraphIndex: paragraphIndex
            ) {
                boundaries.append(wordBoundary)
            }
        }

        // If gap-based detection didn't work well, fall back to simple division
        if boundaries.isEmpty && !timedPhonemes.isEmpty {
            print("[PhonemeTimelineBuilder] Gap-based word detection failed, using simple division")
            boundaries = createSimpleWordBoundaries(
                timedPhonemes: timedPhonemes,
                originalText: originalText,
                wordMap: wordMap,
                paragraphIndex: paragraphIndex
            )
        }

        return boundaries
    }

    /// Create a word boundary from a group of phonemes
    private static func createWordBoundary(
        from phonemes: [PhonemeTimeline.TimedPhoneme],
        in text: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> PhonemeTimeline.WordBoundary? {
        guard !phonemes.isEmpty else { return nil }

        let startTime = phonemes.first!.startTime
        let endTime = phonemes.last!.endTime

        // Try to find the word in the original text
        // Use the first phoneme's original position if available
        var wordText = "?"
        var startOffset = 0
        var endOffset = 0

        if let firstOriginalRange = phonemes.first?.originalRange,
           let lastOriginalRange = phonemes.last?.originalRange {
            startOffset = firstOriginalRange.lowerBound
            endOffset = lastOriginalRange.upperBound

            // Extract word from text
            if startOffset >= 0 && endOffset <= text.count {
                let startIndex = text.index(text.startIndex, offsetBy: startOffset)
                let endIndex = text.index(text.startIndex, offsetBy: endOffset)
                wordText = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Find VoxPDF word if available
        let voxWord = wordMap?.word(at: startOffset, in: paragraphIndex)

        return PhonemeTimeline.WordBoundary(
            word: wordText,
            startTime: startTime,
            endTime: endTime,
            originalStartOffset: startOffset,
            originalEndOffset: endOffset,
            voxPDFWord: voxWord
        )
    }

    /// Create simple word boundaries by dividing phonemes evenly
    private static func createSimpleWordBoundaries(
        timedPhonemes: [PhonemeTimeline.TimedPhoneme],
        originalText: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) -> [PhonemeTimeline.WordBoundary] {
        // Split original text into words
        let words = originalText.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var boundaries: [PhonemeTimeline.WordBoundary] = []
        let phonemesPerWord = max(1, timedPhonemes.count / words.count)

        var phonemeIndex = 0
        var charOffset = 0

        for word in words {
            let startPhonemeIndex = phonemeIndex
            let endPhonemeIndex = min(phonemeIndex + phonemesPerWord, timedPhonemes.count)

            if startPhonemeIndex < timedPhonemes.count {
                let wordPhonemes = Array(timedPhonemes[startPhonemeIndex..<endPhonemeIndex])
                if !wordPhonemes.isEmpty {
                    let boundary = PhonemeTimeline.WordBoundary(
                        word: word,
                        startTime: wordPhonemes.first!.startTime,
                        endTime: wordPhonemes.last!.endTime,
                        originalStartOffset: charOffset,
                        originalEndOffset: charOffset + word.count,
                        voxPDFWord: wordMap?.word(at: charOffset, in: paragraphIndex)
                    )
                    boundaries.append(boundary)
                }

                phonemeIndex = endPhonemeIndex
            }

            charOffset += word.count + 1 // +1 for space
        }

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

}