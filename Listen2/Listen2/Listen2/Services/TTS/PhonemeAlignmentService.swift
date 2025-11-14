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
    ///   - phonemes: Array of phonemes with character positions from espeak
    ///   - text: The text that was synthesized (espeak's normalized text)
    ///   - wordMap: Ignored (kept for API compatibility)
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with precise word timings
    /// - Throws: AlignmentError if alignment fails
    func align(
        phonemes: [PhonemeInfo],
        text: String,
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

        // Use espeak phoneme counts for timing + document words for what to highlight
        let alignmentResult = try alignWithEspeakWords(
            phonemes: phonemes,
            text: text,
            wordMap: wordMap,
            paragraphIndex: paragraphIndex
        )

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

        if documentWords.count != phonemeGroups.count {
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
