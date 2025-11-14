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

    /// LRU cache: tracks access order for eviction
    private var cacheAccessOrder: [String] = []

    /// Maximum cache size (prevents unbounded memory growth)
    private let maxCacheSize = 100

    /// Cache statistics
    private var cacheHits = 0
    private var cacheMisses = 0

    // MARK: - Public Methods

    /// Align phoneme sequence to words using espeak word groupings
    /// This works for ALL document types (PDF, EPUB, clipboard) by using espeak's
    /// built-in word grouping instead of external word extraction.
    /// - Parameters:
    ///   - phonemes: Array of phonemes with character positions from espeak (positions in normalized text)
    ///   - text: The original text (before normalization)
    ///   - normalizedText: The text after espeak normalization (e.g., "Dr." -> "Doctor")
    ///   - charMapping: Character position mapping [(originalPos, normalizedPos)]
    ///   - wordMap: Optional word map for VoxPDF word extraction (positions in original text)
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with precise word timings
    /// - Throws: AlignmentError if alignment fails
    func align(
        phonemes: [PhonemeInfo],
        text: String,
        normalizedText: String? = nil,
        charMapping: [(Int, Int)] = [],
        wordMap: DocumentWordMap? = nil,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {
        // Check cache first (keyed by text + paragraph)
        let cacheKey = "\(paragraphIndex):\(text)"
        if let cached = alignmentCache[cacheKey] {
            cacheHits += 1
            updateCacheAccessOrder(key: cacheKey)
            print("[PhonemeAlign] ✅ Cache hit for paragraph \(paragraphIndex) (hits: \(cacheHits), misses: \(cacheMisses), rate: \(String(format: "%.1f", Double(cacheHits) / Double(cacheHits + cacheMisses) * 100))%)")
            return cached
        }

        cacheMisses += 1

        print("[PhonemeAlign] Aligning \(phonemes.count) phonemes to text (length: \(text.count))")

        // Determine which text to use for alignment
        let effectiveNormalizedText = normalizedText ?? text

        print("[PhonemeAlign] Original text: '\(text)'")
        print("[PhonemeAlign] Normalized text: '\(effectiveNormalizedText)'")
        print("[PhonemeAlign] Character mapping entries: \(charMapping.count)")

        // Use normalized text mapping if we have a wordMap (VoxPDF case) AND normalized text
        let alignmentResult: AlignmentResult
        if let wordMap = wordMap, normalizedText != nil {
            alignmentResult = try alignWithNormalizedMapping(
                phonemes: phonemes,
                originalText: text,
                normalizedText: effectiveNormalizedText,
                charMapping: charMapping,
                wordMap: wordMap,
                paragraphIndex: paragraphIndex
            )
        } else {
            // Fallback to existing espeak word alignment for non-PDF sources or when no normalized text
            alignmentResult = try alignWithEspeakWords(
                phonemes: phonemes,
                text: effectiveNormalizedText,  // Use normalized text (or original if not provided) for word extraction
                wordMap: nil,
                paragraphIndex: paragraphIndex
            )
        }

        print("[PhonemeAlign] ✅ Created alignment with \(alignmentResult.wordTimings.count) word timings, total duration: \(String(format: "%.2f", alignmentResult.totalDuration))s")

        // Cache the result with LRU eviction
        updateCache(key: cacheKey, result: alignmentResult)

        return alignmentResult
    }

    /// Get cached alignment for specific text/paragraph
    func getCachedAlignment(for text: String, paragraphIndex: Int) -> AlignmentResult? {
        let cacheKey = "\(paragraphIndex):\(text)"
        return alignmentCache[cacheKey]
    }

    /// Clear the alignment cache and reset statistics
    func clearCache() {
        alignmentCache.removeAll()
        cacheAccessOrder.removeAll()
        cacheHits = 0
        cacheMisses = 0
        print("[PhonemeAlign] Cache cleared")
    }

    // MARK: - Private Methods

    /// Align using text splitting + espeak phoneme counts for timing
    /// - What to highlight: Words from splitting synthesized text by whitespace
    /// - When to highlight: Timing distributed proportionally by espeak phoneme count
    ///
    /// This avoids VoxPDF position mismatches by using espeak's actual synthesized text
    /// for word boundaries. Works for ALL document types (PDF, EPUB, clipboard).
    ///
    /// - Parameters:
    ///   - phonemes: Array of phonemes with character positions from espeak
    ///   - text: The synthesized text (normalized by espeak)
    ///   - wordMap: Ignored (kept for API compatibility)
    ///   - paragraphIndex: Paragraph index
    /// - Returns: AlignmentResult with word timings
    /// - Throws: AlignmentError if alignment fails
    private func alignWithEspeakWords(
        phonemes: [PhonemeInfo],
        text: String,
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) throws -> AlignmentResult {
        guard !phonemes.isEmpty else {
            throw AlignmentError.recognitionFailed("No phonemes to align")
        }

        // Step 1: Split synthesized text by whitespace to get words
        let documentWords = extractWordsFromText(text)
        print("[PhonemeAlign] Text splitting: \(documentWords.count) words from synthesized text")

        guard !documentWords.isEmpty else {
            throw AlignmentError.recognitionFailed("No words found in text")
        }

        // Step 2: Group espeak phonemes by textRange (word groupings)
        let phonemeGroups = groupPhonemesByWord(phonemes)
        print("[PhonemeAlign] Espeak grouped: \(phonemeGroups.count) phoneme groups")

        // Step 3: Calculate timing proportionally
        let hasPhonemeDurations = phonemes.contains { $0.duration > 0 }
        let totalDuration: TimeInterval

        if hasPhonemeDurations {
            totalDuration = phonemes.reduce(0.0) { $0 + $1.duration }
        } else {
            // Estimate: 50ms per phoneme
            totalDuration = Double(phonemes.count) * 0.05
            print("[PhonemeAlign] ⚠️ No per-phoneme durations, using estimate: \(String(format: "%.2f", totalDuration))s")
        }

        let durationPerPhoneme = totalDuration / Double(phonemes.count)

        // Step 4: Match text words to phoneme groups sequentially and assign timing
        var wordTimings: [AlignmentResult.WordTiming] = []
        var currentTime: TimeInterval = 0

        // Match sequentially (espeak processes linearly, word order preserved)
        let matchCount = min(documentWords.count, phonemeGroups.count)

        for i in 0..<matchCount {
            let (wordText, wordRange) = documentWords[i]
            let phonemeGroup = phonemeGroups[i]

            // Calculate duration for this word
            let duration: TimeInterval
            if hasPhonemeDurations {
                duration = phonemeGroup.reduce(0.0) { $0 + $1.duration }
            } else {
                duration = durationPerPhoneme * Double(phonemeGroup.count)
            }

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: i,
                startTime: currentTime,
                duration: duration,
                text: wordText,
                stringRange: wordRange
            ))

            // Debug log for first few words
            if i < 5 {
                let phonemeList = phonemeGroup.map { $0.symbol }.joined(separator: " ")
                print("   Word[\(i)] '\(wordText)' = [\(phonemeList)] @ \(String(format: "%.3f", currentTime))s for \(String(format: "%.3f", duration))s")
            }

            currentTime += duration
        }

        // CRITICAL FIX: Handle extra phoneme groups when espeak detects more words than text splitting
        // This prevents highlight from getting stuck on the last word when audio continues playing
        if phonemeGroups.count > documentWords.count {
            print("⚠️  [PhonemeAlign] Word count mismatch: \(documentWords.count) text words vs \(phonemeGroups.count) phoneme groups")

            // Calculate duration of unmatched phoneme groups
            var extraDuration: TimeInterval = 0
            for i in matchCount..<phonemeGroups.count {
                let phonemeGroup = phonemeGroups[i]
                if hasPhonemeDurations {
                    extraDuration += phonemeGroup.reduce(0.0) { $0 + $1.duration }
                } else {
                    extraDuration += durationPerPhoneme * Double(phonemeGroup.count)
                }
            }

            // Extend the last matched word to cover the extra duration
            // This ensures alignment.totalDuration matches actual audio duration
            if let lastTiming = wordTimings.last, matchCount > 0 {
                wordTimings.removeLast()

                // Get the original string range from documentWords
                let (_, lastWordRange) = documentWords[matchCount - 1]

                // Create new WordTiming with extended duration (struct is immutable)
                let extendedTiming = AlignmentResult.WordTiming(
                    wordIndex: lastTiming.wordIndex,
                    startTime: lastTiming.startTime,
                    duration: lastTiming.duration + extraDuration,
                    text: lastTiming.text,
                    stringRange: lastWordRange
                )

                wordTimings.append(extendedTiming)
                currentTime += extraDuration
                print("   Extended last word '\(lastTiming.text)' by \(String(format: "%.3f", extraDuration))s to cover \(phonemeGroups.count - matchCount) unmatched phoneme groups")
            }
        } else if documentWords.count != phonemeGroups.count {
            // Word count mismatch but fewer phoneme groups - less critical but still log
            print("⚠️  [PhonemeAlign] Word count mismatch: \(documentWords.count) text words vs \(phonemeGroups.count) phoneme groups")
        }

        print("[PhonemeAlign] ✅ Aligned \(wordTimings.count) words, total duration: \(String(format: "%.2f", currentTime))s")

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: currentTime,
            wordTimings: wordTimings
        )
    }

    /// Group consecutive phonemes that share the same textRange (espeak word groupings)
    private func groupPhonemesByWord(_ phonemes: [PhonemeInfo]) -> [[PhonemeInfo]] {
        var groups: [[PhonemeInfo]] = []
        var i = 0

        while i < phonemes.count {
            let wordRange = phonemes[i].textRange

            // Skip invalid positions
            guard wordRange.lowerBound >= 0 else {
                i += 1
                continue
            }

            // Collect all consecutive phonemes with same range
            var group: [PhonemeInfo] = []
            while i < phonemes.count && phonemes[i].textRange == wordRange {
                group.append(phonemes[i])
                i += 1
            }

            if !group.isEmpty {
                groups.append(group)
            }
        }

        return groups
    }

    /// Extract words from text by splitting on whitespace
    private func extractWordsFromText(_ text: String) -> [(text: String, range: Range<String.Index>)] {
        var words: [(String, Range<String.Index>)] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            // Skip whitespace
            while currentIndex < text.endIndex && text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }

            guard currentIndex < text.endIndex else { break }

            // Collect word characters
            let wordStart = currentIndex
            while currentIndex < text.endIndex && !text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }

            let wordRange = wordStart..<currentIndex
            let wordText = String(text[wordRange])
            words.append((wordText, wordRange))
        }

        return words
    }

    // MARK: - Premium Alignment (Task 9)

    /// Premium alignment using real durations and intelligent normalization mapping
    ///
    /// This method integrates all components from the premium word highlighting plan:
    /// - Real phoneme durations from w_ceil tensor (Task 6)
    /// - Text normalization mapping for Dr./couldn't/TCP/IP (Task 7)
    /// - Dynamic alignment engine (Task 8)
    ///
    /// - Parameters:
    ///   - phonemes: Array of phonemes with real durations from w_ceil
    ///   - displayText: Original text that user sees (e.g., "Dr. Smith's")
    ///   - synthesizedText: Normalized text from espeak (e.g., "Doctor Smith s")
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with precise word timings
    /// - Throws: AlignmentError if alignment fails
    func alignPremium(
        phonemes: [PhonemeInfo],
        displayText: String,
        synthesizedText: String,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {

        print("[PhonemeAlign] Premium alignment with \(phonemes.count) phonemes")
        print("[PhonemeAlign] Display text: '\(displayText)'")
        print("[PhonemeAlign] Synthesized text: '\(synthesizedText)'")

        // Check if we have real durations
        let hasRealDurations = phonemes.contains { $0.duration > 0 }
        print("[PhonemeAlign] Using \(hasRealDurations ? "real" : "estimated") durations")

        // Step 1: Extract words from both texts
        let displayWords = extractWords(from: displayText)
        let synthesizedWords = extractWords(from: synthesizedText)

        print("[PhonemeAlign] Display words: \(displayWords)")
        print("[PhonemeAlign] Synthesized words: \(synthesizedWords)")

        // Step 2: Build normalization mapping
        let mapper = TextNormalizationMapper()
        let wordMapping = mapper.buildMapping(
            display: displayWords,
            synthesized: synthesizedWords
        )

        print("[PhonemeAlign] Created \(wordMapping.count) word mappings")

        // Step 3: Group phonemes by espeak word boundaries
        let phonemeGroups = groupPhonemesByWord(phonemes)
        print("[PhonemeAlign] Grouped into \(phonemeGroups.count) phoneme groups")

        // Step 4: Align using dynamic programming
        let engine = DynamicAlignmentEngine()
        let alignedWords = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: wordMapping
        )

        // Step 5: Convert to AlignmentResult format
        var wordTimings: [AlignmentResult.WordTiming] = []
        var searchStartIndex: String.Index? = nil

        for (index, aligned) in alignedWords.enumerated() {
            // Find string range in display text
            let range = findWordRange(for: aligned.text, in: displayText, afterIndex: searchStartIndex)

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: aligned.startTime,
                duration: aligned.duration,
                text: aligned.text,
                stringRange: range ?? displayText.startIndex..<displayText.startIndex
            ))

            // Update search start for next word
            if let wordRange = range {
                searchStartIndex = wordRange.upperBound
            }
        }

        let totalDuration = alignedWords.last.map { $0.startTime + $0.duration } ?? 0

        print("[PhonemeAlign] ✅ Premium alignment complete: \(wordTimings.count) words, \(String(format: "%.3f", totalDuration))s")

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )
    }

    /// Extract words from text (just the text, no ranges)
    private func extractWords(from text: String) -> [String] {
        text.split(separator: " ")
            .map { String($0) }
    }

    /// Find the range of a word in the display text
    private func findWordRange(
        for word: String,
        in text: String,
        afterIndex: String.Index?
    ) -> Range<String.Index>? {

        let searchStart = afterIndex ?? text.startIndex

        // Search for the word after the given index
        if let range = text.range(of: word, options: [], range: searchStart..<text.endIndex) {
            return range
        }

        // Fallback: search from beginning
        return text.range(of: word)
    }

    /// Align using normalized text mapping for VoxPDF words
    /// This is the CRITICAL integration point where we map VoxPDF words (in original text)
    /// to phoneme positions (in normalized text) using the character mapping.
    ///
    /// Example:
    /// - VoxPDF sees "Dr." at positions 0-3 in original text
    /// - espeak normalized it to "Doctor" at positions 0-6
    /// - Phonemes have positions in normalized text (0-6 for "Doctor")
    /// - We map VoxPDF's "Dr." to the phonemes for "Doctor"
    ///
    /// - Parameters:
    ///   - phonemes: Array of phonemes with positions in normalized text
    ///   - originalText: The original text (what VoxPDF sees)
    ///   - normalizedText: The text after espeak normalization
    ///   - charMapping: Character position mapping [(originalPos, normalizedPos)]
    ///   - wordMap: VoxPDF word map with positions in original text
    ///   - paragraphIndex: Paragraph index
    /// - Returns: AlignmentResult with word timings
    /// - Throws: AlignmentError if alignment fails
    private func alignWithNormalizedMapping(
        phonemes: [PhonemeInfo],
        originalText: String,
        normalizedText: String,
        charMapping: [(Int, Int)],
        wordMap: DocumentWordMap,
        paragraphIndex: Int
    ) throws -> AlignmentResult {
        guard !phonemes.isEmpty else {
            throw AlignmentError.recognitionFailed("No phonemes to align")
        }

        // Step 1: Extract VoxPDF words from original text
        let voxpdfWords = wordMap.words(for: paragraphIndex)
        print("[PhonemeAlign] VoxPDF extracted \(voxpdfWords.count) words from original text")

        guard !voxpdfWords.isEmpty else {
            throw AlignmentError.recognitionFailed("No words found in word map")
        }

        // Step 2: Calculate total duration
        let hasPhonemeDurations = phonemes.contains { $0.duration > 0 }
        let totalDuration: TimeInterval
        if hasPhonemeDurations {
            totalDuration = phonemes.reduce(0.0) { $0 + $1.duration }
        } else {
            totalDuration = Double(phonemes.count) * 0.05
            print("[PhonemeAlign] ⚠️ No per-phoneme durations, using estimate: \(String(format: "%.2f", totalDuration))s")
        }

        // Step 3: For each VoxPDF word, map to phonemes in normalized text
        var wordTimings: [AlignmentResult.WordTiming] = []

        for (index, voxWord) in voxpdfWords.enumerated() {
            // WordPosition has .characterOffset and .length (in original text)
            let originalStart = voxWord.characterOffset
            let originalEnd = voxWord.characterOffset + voxWord.length

            // Map original positions to normalized positions
            let normalizedStart = mapToNormalized(originalPos: originalStart, mapping: charMapping)
            let normalizedEnd = mapToNormalized(originalPos: originalEnd, mapping: charMapping)

            print("[PhonemeAlign]   Word[\(index)] '\(voxWord.text)': orig[\(originalStart)..<\(originalEnd)] -> norm[\(normalizedStart)..<\(normalizedEnd)]")

            // Find phonemes in this normalized range
            let wordPhonemes = phonemes.filter { phoneme in
                phoneme.textRange.lowerBound >= normalizedStart &&
                phoneme.textRange.upperBound <= normalizedEnd
            }

            // Calculate timing from phonemes
            let startTime: TimeInterval
            let duration: TimeInterval

            if !wordPhonemes.isEmpty {
                if hasPhonemeDurations {
                    // Calculate start time by summing durations of all phonemes before this word
                    let phonemesBefore = phonemes.filter { $0.textRange.upperBound <= normalizedStart }
                    startTime = phonemesBefore.reduce(0.0) { $0 + $1.duration }
                    duration = wordPhonemes.reduce(0.0) { $0 + $1.duration }
                } else {
                    // Estimate based on phoneme count
                    let phonemesBefore = phonemes.filter { $0.textRange.upperBound <= normalizedStart }.count
                    startTime = Double(phonemesBefore) * 0.05
                    duration = Double(wordPhonemes.count) * 0.05
                }

                print("[PhonemeAlign]     -> \(wordPhonemes.count) phonemes, duration: \(String(format: "%.3f", duration))s")
            } else {
                // No phonemes found - use estimated timing
                startTime = wordTimings.last.map { $0.startTime + $0.duration } ?? 0
                duration = 0.1  // Minimum duration
                print("[PhonemeAlign]     -> ⚠️ No phonemes found, using estimate")
            }

            // Convert character offset/length to String.Index range for AlignmentResult
            let startIndex = originalText.index(originalText.startIndex, offsetBy: originalStart, limitedBy: originalText.endIndex) ?? originalText.startIndex
            let endIndex = originalText.index(startIndex, offsetBy: voxWord.length, limitedBy: originalText.endIndex) ?? originalText.endIndex

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: startTime,
                duration: duration,
                text: voxWord.text,
                stringRange: startIndex..<endIndex
            ))
        }

        let finalDuration = wordTimings.last.map { $0.startTime + $0.duration } ?? totalDuration

        print("[PhonemeAlign] ✅ Aligned \(wordTimings.count) VoxPDF words using normalized mapping, total duration: \(String(format: "%.2f", finalDuration))s")

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: finalDuration,
            wordTimings: wordTimings
        )
    }

    // MARK: - Normalized Text Mapping

    /// Map a position in original text to normalized text using character mapping
    ///
    /// Character mappings define SEGMENT BOUNDARIES, not interpolation points.
    /// Each mapping entry (origPos, normPos) marks where a segment starts.
    /// The segment extends from this mapping to the next one.
    ///
    /// Example:
    ///   Mapping: [(0, 0), (4, 7)]
    ///   Creates segment: orig[0,4) → norm[0,7)
    ///   - orig[0] → norm[0] (start boundary)
    ///   - orig[1] → norm[1] (proportional within segment)
    ///   - orig[3] → norm[6] (proportional, 3/4 through orig segment = 6/7 through norm segment)
    ///   - orig[4] → norm[7] (end boundary = start of next segment)
    ///
    /// For word-level highlighting, we typically map word start/end boundaries:
    ///   Word at orig[start, end) → find segment → map both boundaries
    ///
    /// - Parameters:
    ///   - originalPos: Position in original text
    ///   - mapping: Array of (originalPos, normalizedPos) tuples defining segment starts
    /// - Returns: Position in normalized text
    private func mapToNormalized(originalPos: Int, mapping: [(Int, Int)]) -> Int {
        // Handle empty mapping - return position as-is
        guard !mapping.isEmpty else {
            return originalPos
        }

        // Find the segment this position falls in
        for i in 0..<mapping.count {
            let (origStart, normStart) = mapping[i]

            // Exact boundary match
            if originalPos == origStart {
                return normStart
            }

            // Check if position is before this mapping point
            if originalPos < origStart {
                // Position is before the first mapping - use identity mapping
                if i == 0 {
                    return originalPos
                }

                // Position is in the segment between mapping[i-1] and mapping[i]
                let (prevOrigStart, prevNormStart) = mapping[i - 1]
                let origLength = origStart - prevOrigStart
                let normLength = normStart - prevNormStart
                let offset = originalPos - prevOrigStart

                // Proportional mapping within the segment
                // Use ceiling division to ensure we capture the full expanded text
                // Example: orig[0,4) → norm[0,7), position 3 → (3*7+3)/4 = 6 (not 5)
                let normalizedOffset = (offset * normLength + origLength - 1) / origLength
                return prevNormStart + normalizedOffset
            }
        }

        // Position is after the last mapping point
        let (lastOrigStart, lastNormStart) = mapping[mapping.count - 1]

        // If there's a next mapping, we're in the last segment
        // Otherwise, extend proportionally
        let offset = originalPos - lastOrigStart
        return lastNormStart + offset
    }

    // MARK: - Cache Management

    /// Update cache with LRU eviction policy
    private func updateCache(key: String, result: AlignmentResult) {
        // Add to cache
        alignmentCache[key] = result

        // Update access order
        updateCacheAccessOrder(key: key)

        // Evict oldest if over limit
        if cacheAccessOrder.count > maxCacheSize {
            let oldestKey = cacheAccessOrder.removeFirst()
            alignmentCache.removeValue(forKey: oldestKey)
            print("[PhonemeAlign] 🗑️ Evicted cache entry (size: \(cacheAccessOrder.count)/\(maxCacheSize))")
        }
    }

    /// Update cache access order for LRU tracking
    private func updateCacheAccessOrder(key: String) {
        // Remove existing entry if present
        cacheAccessOrder.removeAll { $0 == key }

        // Add to end (most recently used)
        cacheAccessOrder.append(key)
    }

    /// Get cache statistics
    func getCacheStats() -> (hits: Int, misses: Int, size: Int, hitRate: Double) {
        let total = cacheHits + cacheMisses
        let hitRate = total > 0 ? Double(cacheHits) / Double(total) : 0.0
        return (cacheHits, cacheMisses, alignmentCache.count, hitRate)
    }

}
