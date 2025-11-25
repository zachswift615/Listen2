//
//  DynamicAlignmentEngine.swift
//  Listen2
//
//  Engine for aligning phoneme groups to display words using word mapping
//  This is the core algorithm that combines:
//  - Phoneme groups (from espeak word boundaries)
//  - Display words (what user sees)
//  - Word mapping (from TextNormalizationMapper)
//  To produce: Aligned words with accurate timing from real phoneme durations
//

import Foundation

/// Engine for aligning phoneme groups to display words using dynamic programming
struct DynamicAlignmentEngine {

    /// Result of aligning phoneme groups to a single display word
    struct AlignedWord {
        /// The display text (what user sees, e.g. "couldn't", "Dr.", "TCP/IP")
        let text: String
        /// When this word starts (cumulative time from beginning)
        let startTime: TimeInterval
        /// How long this word takes to speak (sum of phoneme durations)
        let duration: TimeInterval
        /// All phonemes that make up this word
        let phonemes: [PhonemeInfo]
    }

    // MARK: - Core Alignment Algorithm

    /// Align phoneme groups to display words using word mapping
    ///
    /// Algorithm:
    /// 1. Iterate through word mappings (from TextNormalizationMapper)
    /// 2. For each mapping, collect all phoneme groups that map to this display word
    /// 3. Calculate total duration from real phoneme durations
    /// 4. Create aligned word with accurate timing
    ///
    /// Example:
    /// - Display: ["couldn't"]
    /// - Synthesized: ["could", "not"] (2 phoneme groups)
    /// - Mapping: [0] -> [0, 1]
    /// - Result: AlignedWord("couldn't", phonemes from both groups)
    ///
    /// - Parameters:
    ///   - phonemeGroups: Array of phoneme groups (one group per espeak word)
    ///   - displayWords: Array of display words (original text)
    ///   - wordMapping: Mapping from display indices to synthesized indices
    /// - Returns: Array of aligned words with timing information
    func align(
        phonemeGroups: [[PhonemeInfo]],
        displayWords: [String],
        wordMapping: [TextNormalizationMapper.WordMapping]
    ) -> [AlignedWord] {

        guard !phonemeGroups.isEmpty else {
            return []
        }

        guard !displayWords.isEmpty else {
            return []
        }

        guard !wordMapping.isEmpty else {
            return []
        }

        var alignedWords: [AlignedWord] = []
        var currentTime: TimeInterval = 0
        var processedGroups = 0

        // Process each mapping
        for (mappingIndex, mapping) in wordMapping.enumerated() {
            // Get display word text
            let displayText = mapping.displayIndices
                .compactMap { index in
                    guard index >= 0 && index < displayWords.count else {
                        return nil
                    }
                    return displayWords[index]
                }
                .joined(separator: " ")

            if displayText.isEmpty {
                continue
            }

            // Collect all phonemes for this display word
            var wordPhonemes: [PhonemeInfo] = []
            var wordDuration: TimeInterval = 0

            // Get all phoneme groups that map to this display word
            for synthIndex in mapping.synthesizedIndices {
                // Validate synth index
                guard synthIndex >= 0 && synthIndex < phonemeGroups.count else {
                    continue
                }

                let group = phonemeGroups[synthIndex]

                // Add all phonemes from this group
                wordPhonemes.append(contentsOf: group)

                // Calculate duration for this group
                let groupDuration = group.reduce(0.0) { sum, phoneme in
                    sum + phoneme.duration
                }
                wordDuration += groupDuration

                processedGroups += 1
            }

            // Only create aligned word if we have phonemes
            if !wordPhonemes.isEmpty {
                let alignedWord = AlignedWord(
                    text: displayText,
                    startTime: currentTime,
                    duration: wordDuration,
                    phonemes: wordPhonemes
                )

                alignedWords.append(alignedWord)
                currentTime += wordDuration
            }
        }

        return alignedWords
    }

    // MARK: - Alternative: Dynamic Time Warping

    /// Alternative alignment using Dynamic Time Warping (DTW)
    /// This is more robust for cases where mapping is uncertain
    ///
    /// Uses a cost matrix to find optimal alignment between display words
    /// and phoneme groups based on similarity heuristics.
    ///
    /// Cost function considers:
    /// - Phoneme count mismatch
    /// - Text similarity (edit distance)
    ///
    /// Note: This is more computationally expensive but handles edge cases better
    ///
    /// - Parameters:
    ///   - phonemeGroups: Array of phoneme groups
    ///   - displayWords: Array of display words
    ///   - synthesizedText: Full synthesized text (for debugging)
    /// - Returns: Array of aligned words
    func alignWithDTW(
        phonemeGroups: [[PhonemeInfo]],
        displayWords: [String],
        synthesizedText: String
    ) -> [AlignedWord] {

        guard !phonemeGroups.isEmpty && !displayWords.isEmpty else {
            return []
        }

        let m = displayWords.count
        let n = phonemeGroups.count

        // Build cost matrix
        var costMatrix = Array(
            repeating: Array(repeating: Double.infinity, count: n + 1),
            count: m + 1
        )
        costMatrix[0][0] = 0

        // Fill cost matrix
        for i in 1...m {
            for j in 1...n {
                let displayWord = displayWords[i-1]
                let phonemeGroup = phonemeGroups[j-1]

                // Cost based on phoneme count mismatch
                let phonemeCount = phonemeGroup.count
                let expectedCount = estimatePhonemeCount(for: displayWord)
                let countCost = abs(Double(phonemeCount - expectedCount))

                // Calculate minimum cost path
                let matchCost = costMatrix[i-1][j-1] + countCost
                let insertCost = costMatrix[i][j-1] + countCost * 2  // Penalty for skipping phoneme group
                let deleteCost = costMatrix[i-1][j] + 10.0  // High penalty for skipping display word

                costMatrix[i][j] = min(matchCost, insertCost, deleteCost)
            }
        }

        // Backtrack to find optimal alignment path
        var path: [(displayIdx: Int, groupIdx: Int)] = []
        var i = m
        var j = n

        while i > 0 && j > 0 {
            let matchCost = costMatrix[i-1][j-1]
            let insertCost = costMatrix[i][j-1]
            let deleteCost = costMatrix[i-1][j]

            if matchCost <= insertCost && matchCost <= deleteCost {
                // Match: display word i-1 maps to phoneme group j-1
                path.append((i-1, j-1))
                i -= 1
                j -= 1
            } else if insertCost <= deleteCost {
                // Skip phoneme group
                j -= 1
            } else {
                // Skip display word
                i -= 1
            }
        }

        // Build aligned words from path (reverse order)
        path.reverse()

        var alignedWords: [AlignedWord] = []
        var currentTime: TimeInterval = 0

        // Group consecutive groups for same display word
        var currentDisplayIdx = -1
        var accumulatedPhonemes: [PhonemeInfo] = []

        for (displayIdx, groupIdx) in path {
            if displayIdx != currentDisplayIdx {
                // Flush previous word
                if currentDisplayIdx >= 0 && !accumulatedPhonemes.isEmpty {
                    let duration = accumulatedPhonemes.reduce(0.0) { $0 + $1.duration }
                    alignedWords.append(AlignedWord(
                        text: displayWords[currentDisplayIdx],
                        startTime: currentTime,
                        duration: duration,
                        phonemes: accumulatedPhonemes
                    ))
                    currentTime += duration
                }

                // Start new word
                currentDisplayIdx = displayIdx
                accumulatedPhonemes = []
            }

            // Add phonemes from this group
            if groupIdx < phonemeGroups.count {
                accumulatedPhonemes.append(contentsOf: phonemeGroups[groupIdx])
            }
        }

        // Flush final word
        if currentDisplayIdx >= 0 && !accumulatedPhonemes.isEmpty {
            let duration = accumulatedPhonemes.reduce(0.0) { $0 + $1.duration }
            alignedWords.append(AlignedWord(
                text: displayWords[currentDisplayIdx],
                startTime: currentTime,
                duration: duration,
                phonemes: accumulatedPhonemes
            ))
        }

        return alignedWords
    }

    // MARK: - Helper Methods

    /// Estimate expected phoneme count for a word
    /// This is a heuristic - real implementation could use phoneme dictionary
    private func estimatePhonemeCount(for word: String) -> Int {
        // Rough heuristic: English words average ~1.2 phonemes per character
        // Adjust for common patterns:
        // - Silent letters reduce count
        // - Digraphs (th, ch, sh) are 1 phoneme for 2 chars
        let baseCount = max(1, Int(Double(word.count) * 1.2))

        // Adjust for silent 'e' at end
        if word.hasSuffix("e") && word.count > 2 {
            return baseCount - 1
        }

        return baseCount
    }
}
