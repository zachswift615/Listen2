//
//  TextNormalizationMapper.swift
//  Listen2
//
//  Maps between display text words and espeak-normalized synthesized text words
//  Handles abbreviations, contractions, possessives, numbers, and technical terms
//

import Foundation

/// Maps between display text words and synthesized (normalized) text words
struct TextNormalizationMapper {

    /// Represents a mapping between display and synthesized word indices
    struct WordMapping {
        /// Indices in the display word array (usually single element)
        let displayIndices: [Int]
        /// Indices in the synthesized word array (can be multiple for expansions)
        let synthesizedIndices: [Int]
    }

    // MARK: - Public Methods

    /// Build mapping between display and synthesized words using pattern matching and edit distance
    /// - Parameters:
    ///   - display: Array of words from display text (original text)
    ///   - synthesized: Array of words from synthesized text (espeak-normalized)
    /// - Returns: Array of word mappings showing correspondence
    func buildMapping(display: [String], synthesized: [String]) -> [WordMapping] {
        guard !display.isEmpty else { return [] }
        guard !synthesized.isEmpty else { return [] }

        var mappings: [WordMapping] = []
        var synthIndex = 0

        for (dispIndex, dispWord) in display.enumerated() {
            guard synthIndex < synthesized.count else {
                // Ran out of synthesized words - shouldn't happen with good input
                print("[NormMapper] Warning: Ran out of synthesized words at display word '\(dispWord)'")
                break
            }

            // Find best match in synthesized text
            let matchIndices = findBestMatch(
                for: dispWord,
                in: synthesized,
                startingFrom: synthIndex
            )

            if let indices = matchIndices {
                mappings.append(WordMapping(
                    displayIndices: [dispIndex],
                    synthesizedIndices: indices
                ))
                synthIndex = indices.last! + 1
            } else {
                // No match found - word might have been dropped
                print("[NormMapper] Warning: No match for '\(dispWord)' starting at synth index \(synthIndex)")
                // Try to continue with next synth word
                synthIndex += 1
            }
        }

        return mappings
    }

    // MARK: - Pattern Matching

    /// Find the best match for a display word in the synthesized text
    private func findBestMatch(
        for displayWord: String,
        in synthesized: [String],
        startingFrom startIndex: Int
    ) -> [Int]? {

        // 1. Check abbreviations
        if let indices = matchAbbreviation(displayWord, synthesized, startIndex) {
            return indices
        }

        // 2. Check contractions (must come before possessive to handle "I'll" etc.)
        if let indices = matchContraction(displayWord, synthesized, startIndex) {
            return indices
        }

        // 3. Check possessives
        if let indices = matchPossessive(displayWord, synthesized, startIndex) {
            return indices
        }

        // 4. Check numbers
        if let indices = matchNumber(displayWord, synthesized, startIndex) {
            return indices
        }

        // 5. Check technical terms (slashes, etc.)
        if let indices = matchTechnicalTerm(displayWord, synthesized, startIndex) {
            return indices
        }

        // 6. Direct match (case-insensitive, punctuation-stripped)
        if startIndex < synthesized.count &&
           normalizeForComparison(displayWord) == normalizeForComparison(synthesized[startIndex]) {
            return [startIndex]
        }

        // 7. Fuzzy match using edit distance
        return fuzzyMatch(displayWord, synthesized, startIndex)
    }

    // MARK: - Abbreviation Matching

    private func matchAbbreviation(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        let abbreviations: [String: String] = [
            "Dr.": "Doctor",
            "Mr.": "Mister",
            "Mrs.": "Missus",
            "Ms.": "Miss",
            "St.": "Street",
            "Ave.": "Avenue",
            "Blvd.": "Boulevard",
            "Rd.": "Road",
            "Ln.": "Lane",
            "Ct.": "Court",
            "Pl.": "Place",
            "Jr.": "Junior",
            "Sr.": "Senior",
            "Inc.": "Incorporated",
            "Corp.": "Corporation",
            "Ltd.": "Limited"
        ]

        if let expanded = abbreviations[word], start < synthesized.count {
            if normalizeForComparison(synthesized[start]) == normalizeForComparison(expanded) {
                return [start]
            }
        }

        return nil
    }

    // MARK: - Contraction Matching

    private func matchContraction(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        let contractions: [String: [String]] = [
            // Not contractions
            "can't": ["can", "not"],
            "won't": ["will", "not"],
            "couldn't": ["could", "not"],
            "shouldn't": ["should", "not"],
            "wouldn't": ["would", "not"],
            "didn't": ["did", "not"],
            "doesn't": ["does", "not"],
            "don't": ["do", "not"],
            "isn't": ["is", "not"],
            "aren't": ["are", "not"],
            "wasn't": ["was", "not"],
            "weren't": ["were", "not"],
            "hasn't": ["has", "not"],
            "haven't": ["have", "not"],
            "hadn't": ["had", "not"],
            // Will contractions
            "I'll": ["I", "will"],
            "you'll": ["you", "will"],
            "he'll": ["he", "will"],
            "she'll": ["she", "will"],
            "we'll": ["we", "will"],
            "they'll": ["they", "will"],
            "it'll": ["it", "will"],
            "that'll": ["that", "will"],
            // Have contractions
            "I've": ["I", "have"],
            "you've": ["you", "have"],
            "we've": ["we", "have"],
            "they've": ["they", "have"],
            // Am/Are/Is contractions
            "I'm": ["I", "am"],
            "you're": ["you", "are"],
            "we're": ["we", "are"],
            "they're": ["they", "are"],
            "he's": ["he", "is"],
            "she's": ["she", "is"],
            "it's": ["it", "is"],
            "that's": ["that", "is"],
            // Had/Would contractions
            "I'd": ["I", "would"],
            "you'd": ["you", "would"],
            "he'd": ["he", "would"],
            "she'd": ["she", "would"],
            "we'd": ["we", "would"],
            "they'd": ["they", "would"]
        ]

        let normalized = normalizeForComparison(word)

        // Try to find exact contraction match
        for (contraction, expansion) in contractions {
            if normalizeForComparison(contraction) == normalized {
                // Check if synthesized text has this expansion
                if start + expansion.count <= synthesized.count {
                    let synthSlice = synthesized[start..<(start + expansion.count)]
                        .map { normalizeForComparison($0) }
                    let expectedExpansion = expansion.map { normalizeForComparison($0) }

                    if synthSlice == expectedExpansion {
                        return Array(start..<(start + expansion.count))
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Possessive Matching

    private func matchPossessive(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Handle possessives (e.g., "John's" -> "John" "s")
        // This includes both 's and s' forms
        if (word.hasSuffix("'s") || word.hasSuffix("s'")) && start + 1 < synthesized.count {
            let base = word.hasSuffix("'s") ? String(word.dropLast(2)) : String(word.dropLast(1))

            // Check if next two synth words match the base + "s" pattern
            if normalizeForComparison(base) == normalizeForComparison(synthesized[start]) &&
               normalizeForComparison(synthesized[start + 1]) == "s" {
                return [start, start + 1]
            }
        }

        return nil
    }

    // MARK: - Number Matching

    private func matchNumber(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Check if word is a number
        guard let number = Int(word) else { return nil }

        // Greedy approach: consume all consecutive number words
        // This handles "23" -> "twenty three", "2024" -> "two thousand twenty four", etc.
        var indices: [Int] = []
        var currentIndex = start

        while currentIndex < synthesized.count && isNumberWord(synthesized[currentIndex]) {
            indices.append(currentIndex)
            currentIndex += 1
        }

        // Return the indices if we matched at least one number word
        return indices.isEmpty ? nil : indices
    }

    /// Check if a word is a number-related word
    private func isNumberWord(_ word: String) -> Bool {
        let numberWords = Set([
            "zero", "one", "two", "three", "four", "five",
            "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen",
            "sixteen", "seventeen", "eighteen", "nineteen",
            "twenty", "thirty", "forty", "fifty", "sixty",
            "seventy", "eighty", "ninety",
            "hundred", "thousand", "million", "billion"
        ])

        return numberWords.contains(normalizeForComparison(word))
    }

    // MARK: - Technical Term Matching

    private func matchTechnicalTerm(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Handle technical terms with slashes (TCP/IP, HTTP/HTTPS, etc.)
        if word.contains("/") {
            // Split by slash
            let parts = word.split(separator: "/").map { String($0) }

            // Estimate how many synth words this could expand to
            // Each letter becomes a word, plus "slash" between parts
            var expectedCount = 0

            for (index, part) in parts.enumerated() {
                // Check if this part is an acronym (all caps or letters)
                if part.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                    // Each character becomes a word
                    expectedCount += part.count
                } else {
                    // Non-acronym - might be one word or multiple
                    expectedCount += 1
                }

                // Add "slash" word between parts
                if index < parts.count - 1 {
                    expectedCount += 1
                }
            }

            // Try to match this many synth words
            if start + expectedCount <= synthesized.count {
                // Verify this looks plausible
                let segment = synthesized[start..<(start + expectedCount)]

                // Check for "slash" word(s) in the segment
                if segment.contains(where: { normalizeForComparison($0) == "slash" }) {
                    return Array(start..<(start + expectedCount))
                }
            }
        }

        return nil
    }

    // MARK: - Fuzzy Matching

    private func fuzzyMatch(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Use Levenshtein distance for fuzzy matching
        let threshold = 3  // Maximum edit distance

        // Look ahead a few words
        let lookAhead = min(5, synthesized.count - start)

        for i in 0..<lookAhead {
            let synthIndex = start + i
            let distance = levenshteinDistance(
                normalizeForComparison(word),
                normalizeForComparison(synthesized[synthIndex])
            )

            if distance <= threshold {
                return [synthIndex]
            }
        }

        return nil
    }

    // MARK: - Helper Methods

    /// Normalize a word for comparison (lowercase, strip punctuation)
    private func normalizeForComparison(_ word: String) -> String {
        // Remove all non-alphanumeric characters and lowercase
        let cleaned = word.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: "",
            options: .regularExpression
        )
        return cleaned.lowercased()
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize first row and column
        for i in 1...m { matrix[i][0] = i }
        for j in 1...n { matrix[0][j] = j }

        // Fill matrix
        let s1Array = Array(s1)
        let s2Array = Array(s2)

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1

                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
