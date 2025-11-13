//
//  PhonemeAlignmentService.swift
//  Listen2
//
//  Service for aligning phoneme sequences to text words using character positions
//

import Foundation

/// Service for word-level alignment using phoneme sequences from Piper TTS
actor PhonemeAlignmentService {

    // MARK: - Properties

    /// Cache of alignments by text hash
    private var alignmentCache: [String: AlignmentResult] = [:]

    // MARK: - Public Methods

    /// Align phoneme sequence to VoxPDF words using character positions
    /// - Parameters:
    ///   - phonemes: Array of phonemes with character positions from Piper
    ///   - text: The text that was synthesized
    ///   - wordMap: Document word map containing word positions
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with precise word timings
    /// - Throws: AlignmentError if alignment fails
    func align(
        phonemes: [PhonemeInfo],
        text: String,
        wordMap: DocumentWordMap,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {
        // Check cache first (keyed by text + paragraph)
        let cacheKey = "\(paragraphIndex):\(text)"
        if let cached = alignmentCache[cacheKey] {
            print("[PhonemeAlign] Using cached alignment for paragraph \(paragraphIndex)")
            return cached
        }

        print("[PhonemeAlign] Aligning \(phonemes.count) phonemes to text (length: \(text.count))")

        // Get VoxPDF words for this paragraph
        let voxPDFWords = wordMap.words(for: paragraphIndex)

        guard !voxPDFWords.isEmpty else {
            throw AlignmentError.recognitionFailed("No words found for paragraph \(paragraphIndex)")
        }

        print("[PhonemeAlign] Found \(voxPDFWords.count) VoxPDF words")

        // Map phonemes to words using character position overlaps
        let wordTimings = try mapPhonemesToWords(
            phonemes: phonemes,
            text: text,
            voxPDFWords: voxPDFWords
        )

        // Calculate total duration from phoneme durations
        let totalDuration = phonemes.reduce(0.0) { $0 + $1.duration }

        // Create alignment result
        let alignmentResult = AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )

        print("[PhonemeAlign] ✅ Created alignment with \(wordTimings.count) word timings, total duration: \(String(format: "%.2f", totalDuration))s")

        // Cache the result
        alignmentCache[cacheKey] = alignmentResult

        return alignmentResult
    }

    /// Get cached alignment for specific text/paragraph
    func getCachedAlignment(for text: String, paragraphIndex: Int) -> AlignmentResult? {
        let cacheKey = "\(paragraphIndex):\(text)"
        return alignmentCache[cacheKey]
    }

    /// Clear the alignment cache
    func clearCache() {
        alignmentCache.removeAll()
    }

    // MARK: - Private Methods

    /// Map phoneme sequence to VoxPDF words using character position overlaps
    /// - Parameters:
    ///   - phonemes: Array of phonemes with character positions
    ///   - text: Full paragraph text
    ///   - voxPDFWords: Array of word positions
    /// - Returns: Array of word timings
    /// - Throws: AlignmentError if mapping fails
    private func mapPhonemesToWords(
        phonemes: [PhonemeInfo],
        text: String,
        voxPDFWords: [WordPosition]
    ) throws -> [AlignmentResult.WordTiming] {
        guard !phonemes.isEmpty else {
            throw AlignmentError.recognitionFailed("No phonemes to map")
        }

        var wordTimings: [AlignmentResult.WordTiming] = []
        var currentTime: TimeInterval = 0

        // Build index of phonemes by their character ranges for fast lookup
        let phonemesByChar = buildPhonemeIndex(phonemes: phonemes)

        for (wordIndex, word) in voxPDFWords.enumerated() {
            // Word's character range
            let wordCharRange = word.characterOffset..<(word.characterOffset + word.length)

            // Find all phonemes that overlap with this word's character range
            let wordPhonemes = findPhonemesForCharRange(
                charRange: wordCharRange,
                phonemeIndex: phonemesByChar
            )

            if wordPhonemes.isEmpty {
                print("⚠️  [PhonemeAlign] No phonemes found for word '\(word.text)' at chars \(wordCharRange)")
                // Skip words without phonemes (might be punctuation-only)
                continue
            }

            // Calculate timing from phonemes
            let startTime = currentTime
            let duration = wordPhonemes.reduce(0.0) { $0 + $1.duration }

            // Convert character offset to String.Index
            guard let startIndex = text.index(
                text.startIndex,
                offsetBy: word.characterOffset,
                limitedBy: text.endIndex
            ) else {
                print("⚠️  [PhonemeAlign] Invalid character offset \(word.characterOffset) for word '\(word.text)'")
                continue
            }

            guard let endIndex = text.index(
                startIndex,
                offsetBy: word.length,
                limitedBy: text.endIndex
            ) else {
                print("⚠️  [PhonemeAlign] Invalid length \(word.length) for word '\(word.text)'")
                continue
            }

            let stringRange = startIndex..<endIndex

            // Validate extracted text matches expected word
            let extractedText = String(text[stringRange])
            if extractedText != word.text {
                print("⚠️  [PhonemeAlign] VoxPDF position mismatch:")
                print("    Expected: '\(word.text)', Got: '\(extractedText)' at offset \(word.characterOffset)")
                continue
            }

            // Create word timing
            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: wordIndex,
                startTime: startTime,
                duration: duration,
                text: word.text,
                stringRange: stringRange
            ))

            // Debug log for first few words
            if wordIndex < 5 {
                let phonemeList = wordPhonemes.map { $0.symbol }.joined(separator: " ")
                print("   Word[\(wordIndex)] '\(word.text)' = [\(phonemeList)] @ \(String(format: "%.3f", startTime))s for \(String(format: "%.3f", duration))s")
            }

            currentTime += duration
        }

        print("[PhonemeAlign] Mapped \(wordTimings.count) words from \(voxPDFWords.count) VoxPDF words")
        return wordTimings
    }

    /// Build an index mapping character positions to phonemes for fast lookup
    private func buildPhonemeIndex(phonemes: [PhonemeInfo]) -> [Int: [PhonemeInfo]] {
        var index: [Int: [PhonemeInfo]] = [:]

        for phoneme in phonemes {
            for charPos in phoneme.textRange {
                index[charPos, default: []].append(phoneme)
            }
        }

        return index
    }

    /// Find all phonemes that overlap with a character range
    private func findPhonemesForCharRange(
        charRange: Range<Int>,
        phonemeIndex: [Int: [PhonemeInfo]]
    ) -> [PhonemeInfo] {
        var foundPhonemes: Set<PhonemeInfo> = []

        for charPos in charRange {
            if let phonemes = phonemeIndex[charPos] {
                foundPhonemes.formUnion(phonemes)
            }
        }

        // Return in original order (sorted by text position)
        return foundPhonemes.sorted { $0.textRange.lowerBound < $1.textRange.lowerBound }
    }
}

// Make PhonemeInfo Hashable for Set operations
extension PhonemeInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(symbol)
        hasher.combine(textRange.lowerBound)
        hasher.combine(textRange.upperBound)
    }
}
