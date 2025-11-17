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
    ///   - sentenceOffset: Character offset of sentence start within paragraph (for multi-sentence paragraphs)
    /// - Returns: PhonemeTimeline if successful, nil if phonemes are empty
    static func build(
        from synthesis: SynthesisResult,
        sentence: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int,
        sentenceOffset: Int = 0
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
        var wordBoundaries = findWordBoundaries(
            timedPhonemes: timedPhonemes,
            originalText: sentence,
            normalizedText: synthesis.normalizedText,
            charMapping: synthesis.charMapping,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex,
            sentenceOffset: sentenceOffset
        )

        // Calculate total duration from all phonemes (includes orphaned phonemes)
        let totalDuration = timedPhonemes.last?.endTime ?? 0

        // Scale word boundaries to match actual audio duration
        // This fixes the issue where orphaned phonemes (blanks, pauses, stress marks)
        // aren't assigned to any words, causing word boundaries to be shorter than audio
        if !wordBoundaries.isEmpty, let lastWordEnd = wordBoundaries.last?.endTime, lastWordEnd > 0 {
            let wordBoundaryDuration = lastWordEnd

            if abs(totalDuration - wordBoundaryDuration) > 0.01 { // Only scale if there's a meaningful difference
                let scaleFactor = totalDuration / wordBoundaryDuration

                print("[PhonemeTimelineBuilder] ⚖️  SCALING FIX: Word boundaries span \(String(format: "%.3f", wordBoundaryDuration))s but audio is \(String(format: "%.3f", totalDuration))s")
                print("[PhonemeTimelineBuilder]   Applying scale factor: \(String(format: "%.3f", scaleFactor))x")

                // Scale all word boundary times proportionally
                wordBoundaries = wordBoundaries.map { boundary in
                    PhonemeTimeline.WordBoundary(
                        word: boundary.word,
                        startTime: boundary.startTime * scaleFactor,
                        endTime: boundary.endTime * scaleFactor,
                        originalStartOffset: boundary.originalStartOffset,
                        originalEndOffset: boundary.originalEndOffset,
                        voxPDFWord: boundary.voxPDFWord
                    )
                }

                print("[PhonemeTimelineBuilder]   Scaled last word end time: \(String(format: "%.3f", wordBoundaries.last!.endTime))s (matches audio)")
            }
        }

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

        // Check if we have valid durations
        let totalDuration = phonemes.reduce(0.0) { $0 + $1.duration }
        let hasValidDurations = totalDuration > 0

        // If no valid durations, estimate based on phoneme count
        // Typical speech rate is ~10-15 phonemes per second
        let estimatedDurationPerPhoneme: TimeInterval = 0.08 // ~12.5 phonemes/sec

        for (index, phoneme) in phonemes.enumerated() {
            // Map normalized range to original if possible
            let originalRange = mapToOriginal(
                normalizedRange: phoneme.textRange,
                using: charMapping
            )

            let duration = hasValidDurations ? phoneme.duration : estimatedDurationPerPhoneme

            let timed = PhonemeTimeline.TimedPhoneme(
                symbol: phoneme.symbol,
                startTime: currentTime,
                endTime: currentTime + duration,
                normalizedRange: phoneme.textRange,
                originalRange: originalRange
            )

            timedPhonemes.append(timed)
            currentTime += duration
        }

        if !hasValidDurations {
            print("[PhonemeTimelineBuilder] WARNING: No phoneme durations available, using estimated timing")
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
        paragraphIndex: Int,
        sentenceOffset: Int
    ) -> [PhonemeTimeline.WordBoundary] {
        print("[PhonemeTimelineBuilder] Finding word boundaries (word-level approach)...")
        print("  Original text: '\(originalText)'")
        print("  Normalized text: '\(normalizedText)'")
        print("  Phonemes: \(timedPhonemes.count)")

        var boundaries: [PhonemeTimeline.WordBoundary] = []

        // Step 1: Group phonemes by their textRange (same position = same word)
        let phonemeGroups = groupPhonemesByPosition(timedPhonemes)
        print("  Grouped into \(phonemeGroups.count) phoneme word groups")

        // Step 2: Split normalized text into words
        let normalizedWords = findWordsInNormalizedText(normalizedText)
        print("  Found \(normalizedWords.count) words in normalized text")

        // Step 3: Split original text into words
        let originalWords = findWordsInNormalizedText(originalText)
        print("  Found \(originalWords.count) words in original text")

        // Step 4: Match groups 1:1 with normalized words
        // Both phoneme groups and normalized words are in the same order
        var groupIndex = 0
        var originalWordIndex = 0

        for (normalizedWord, _) in normalizedWords {
            guard groupIndex < phonemeGroups.count else {
                print("  ⚠️ Ran out of phoneme groups at normalized word '\(normalizedWord)'")
                break
            }

            let wordPhonemes = phonemeGroups[groupIndex]
            groupIndex += 1

            print("  Phoneme group \(groupIndex - 1): \(wordPhonemes.count) phonemes for '\(normalizedWord)'")

            // Get timing from phonemes
            let startTime = wordPhonemes.first!.startTime
            let endTime = wordPhonemes.last!.endTime

            // Map to original word by position
            // Handle edge case: contractions like "don't" → ["do", "not"]
            // If normalized has more words than original, it's likely a contraction
            // For now, use simple 1:1 mapping by index
            guard originalWordIndex < originalWords.count else {
                print("  ⚠️ Ran out of original words at normalized '\(normalizedWord)'")
                break
            }

            let (originalWord, originalRange) = originalWords[originalWordIndex]

            // Check if this might be a contraction that expanded
            // Simple heuristic: if next normalized word starts with same letter as current original word
            // and original word contains apostrophe, it's likely a contraction
            let isContraction = originalWord.contains("'") &&
                               groupIndex < normalizedWords.count &&
                               normalizedWords[groupIndex].word.first == normalizedWord.first

            if isContraction {
                // This original word maps to multiple normalized words
                // Consume next phoneme group too
                print("  📝 Detected contraction: '\(originalWord)' → '\(normalizedWord)' + next word")
                // Don't increment originalWordIndex yet - will do it after processing both groups
                // For now, just use this group's timing
            } else {
                // Normal 1:1 mapping
                originalWordIndex += 1
            }

            // Apply sentence offset to make positions paragraph-relative
            let paragraphStart = originalRange.lowerBound + sentenceOffset
            let paragraphEnd = originalRange.upperBound + sentenceOffset

            let boundary = PhonemeTimeline.WordBoundary(
                word: originalWord,
                startTime: startTime,
                endTime: endTime,
                originalStartOffset: paragraphStart,
                originalEndOffset: paragraphEnd,
                voxPDFWord: wordMap?.word(at: paragraphStart, in: paragraphIndex)
            )

            boundaries.append(boundary)
            print("  Word '\(originalWord)': \(startTime)-\(endTime)s (offset \(paragraphStart)-\(paragraphEnd))")
        }

        // Sort by time to ensure correct order
        boundaries.sort { $0.startTime < $1.startTime }

        print("  Created \(boundaries.count) word boundaries")
        return boundaries
    }

    /// Group phonemes by their textRange position (same position = same word)
    private static func groupPhonemesByPosition(_ phonemes: [PhonemeTimeline.TimedPhoneme]) -> [[PhonemeTimeline.TimedPhoneme]] {
        var groups: [[PhonemeTimeline.TimedPhoneme]] = []
        var currentGroup: [PhonemeTimeline.TimedPhoneme] = []
        var currentRange: Range<Int>? = nil

        for phoneme in phonemes {
            if let range = currentRange, range == phoneme.normalizedRange {
                // Same word - add to current group
                currentGroup.append(phoneme)
            } else {
                // New word - save previous group and start new one
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [phoneme]
                currentRange = phoneme.normalizedRange
            }
        }

        // Don't forget the last group
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
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
        // Handle sparse/incomplete character mappings
        if charMapping.isEmpty {
            // No mapping available - try direct mapping
            return normalizedRange.lowerBound..<min(normalizedRange.upperBound, originalText.count)
        }

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
                    // Estimate based on distance from mapped position
                    let diff = normalizedRange.lowerBound - mapping.normalizedPos
                    originalStart = mapping.originalPos + diff
                } else if let firstMapping = sortedMappings.first {
                    // Use first mapping as reference
                    originalStart = max(0, firstMapping.originalPos - (firstMapping.normalizedPos - normalizedRange.lowerBound))
                } else {
                    // Fallback: assume direct mapping
                    originalStart = normalizedRange.lowerBound
                }
            }

            if originalEnd == nil {
                // Find the first mapping after or at our end position
                if let mapping = sortedMappings.first(where: { $0.normalizedPos >= normalizedRange.upperBound - 1 }) {
                    let diff = mapping.normalizedPos - (normalizedRange.upperBound - 1)
                    originalEnd = mapping.originalPos - diff + 1
                } else if let lastMapping = sortedMappings.last {
                    // Extrapolate from last mapping
                    let diff = (normalizedRange.upperBound - 1) - lastMapping.normalizedPos
                    originalEnd = min(lastMapping.originalPos + diff + 1, originalText.count)
                } else {
                    // Fallback: use text length
                    originalEnd = min(normalizedRange.upperBound, originalText.count)
                }
            }
        }

        guard let start = originalStart, let end = originalEnd else {
            // Last resort: use normalized range directly
            return normalizedRange.lowerBound..<min(normalizedRange.upperBound, originalText.count)
        }

        // Ensure valid range
        let validStart = max(0, start)
        let validEnd = min(end, originalText.count)

        if validStart >= validEnd {
            return normalizedRange.lowerBound..<min(normalizedRange.upperBound, originalText.count)
        }

        return validStart..<validEnd
    }


}