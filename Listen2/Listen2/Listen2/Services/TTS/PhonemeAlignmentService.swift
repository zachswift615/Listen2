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

    /// Align phoneme sequence to words using simplified word-level matching
    /// - Parameters:
    ///   - phonemes: Array of phonemes with word-level positions from espeak
    ///   - text: The original text (what the user sees)
    ///   - normalizedText: The text after espeak normalization (e.g., "Dr." -> "Doctor")
    ///   - wordMap: Optional word map for VoxPDF word extraction
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with word timings (or empty if alignment fails)
    func align(
        phonemes: [PhonemeInfo],
        text: String,
        normalizedText: String? = nil,
        charMapping: [(Int, Int)] = [], // Kept for API compatibility but ignored
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

        // DEBUG: Verify normalized text matches current synthesis
        if let normalizedText = normalizedText {
            print("[DEBUG] Normalized text provided: '\(normalizedText)'")
            // Check if it makes sense for the original text
            let originalWords = text.lowercased().split(separator: " ").map { String($0) }
            let normalizedWords = normalizedText.split(separator: " ").map { String($0) }
            print("[DEBUG] Original words: \(originalWords)")
            print("[DEBUG] Normalized words: \(normalizedWords)")

            // Basic sanity check - if completely different, log warning
            if originalWords.first != normalizedWords.first &&
               !normalizedWords.joined().contains(originalWords.first?.prefix(3) ?? "") {
                print("⚠️ [DEBUG] SUSPICIOUS: Normalized text seems unrelated to original!")
            }
        }

        // Simplified: Always use word-level alignment
        // We'll match words between original and normalized text
        let alignmentResult = try alignSimplified(
            phonemes: phonemes,
            originalText: text,
            normalizedText: effectiveNormalizedText,
            paragraphIndex: paragraphIndex
        )

        print("[PhonemeAlign] ✅ Created alignment with \(alignmentResult.wordTimings.count) word timings, total duration: \(String(format: "%.2f", alignmentResult.totalDuration))s")

        // DIAGNOSTIC: Show first few word timings
        for (i, timing) in alignmentResult.wordTimings.prefix(5).enumerated() {
            print("[Alignment] OUTPUT: Word[\(i)] '\(timing.text)' @ \(String(format: "%.3f", timing.startTime))s for \(String(format: "%.3f", timing.duration))s (range \(timing.rangeLocation)..<\(timing.rangeLocation + timing.rangeLength))")
        }

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

    /// Simplified alignment using word-level matching
    /// - What to highlight: Words from original text
    /// - When to highlight: Timing from phoneme groups matched to normalized words
    private func alignSimplified(
        phonemes: [PhonemeInfo],
        originalText: String,
        normalizedText: String,
        paragraphIndex: Int
    ) throws -> AlignmentResult {
        guard !phonemes.isEmpty else {
            // No phonemes - return empty result (no highlighting)
            return AlignmentResult(
                paragraphIndex: paragraphIndex,
                totalDuration: 0,
                wordTimings: []
            )
        }

        // Step 1: Get display words (what to highlight)
        // NOTE: We always use whitespace splitting because VoxPDF's word.characterOffset
        // is relative to the entire document, not the current paragraph
        let displayWords = extractWordsFromText(originalText)

        guard !displayWords.isEmpty else {
            // No words found - return empty result
            return AlignmentResult(
                paragraphIndex: paragraphIndex,
                totalDuration: 0,
                wordTimings: []
            )
        }

        // Step 2: Get normalized words
        let normalizedWords = extractWordsFromText(normalizedText)

        // Step 3: Group phonemes by word (they already come grouped from espeak)
        let phonemeGroups = groupPhonemesByWord(phonemes)

        print("[PhonemeAlign] Simplified alignment: \(displayWords.count) display words, \(normalizedWords.count) normalized words, \(phonemeGroups.count) phoneme groups")

        // Step 4: Match normalized words to phoneme groups
        // Since both come from espeak processing, they should align 1:1
        var normalizedToPhonemes: [String: [PhonemeInfo]] = [:]
        for (index, group) in phonemeGroups.enumerated() {
            if index < normalizedWords.count {
                let normalizedWord = normalizedWords[index].text.lowercased()
                normalizedToPhonemes[normalizedWord] = group
            }
        }

        // Step 5: Match display words to normalized words and calculate timing
        var wordTimings: [AlignmentResult.WordTiming] = []
        var currentTime: TimeInterval = 0
        let hasDurations = phonemes.contains { $0.duration > 0 }
        var consumedPhonemeGroups = Set<Int>() // Track which groups we've used

        for (index, displayWord) in displayWords.enumerated() {
            let displayText = displayWord.text
            let displayRange = displayWord.range

            // Find the next unconsumed phoneme group index
            var currentGroupIndex = index
            while currentGroupIndex < phonemeGroups.count && consumedPhonemeGroups.contains(currentGroupIndex) {
                currentGroupIndex += 1
            }

            // Try to find matching normalized word(s)
            let (matchedPhonemes, groupsUsed) = findPhonemesForDisplayWord(
                displayText: displayText,
                normalizedWords: normalizedWords.map { $0.text },
                normalizedToPhonemes: normalizedToPhonemes,
                allPhonemeGroups: phonemeGroups,
                currentGroupIndex: currentGroupIndex,
                consumedGroups: consumedPhonemeGroups
            )

            // Mark used groups as consumed
            for groupIdx in groupsUsed {
                consumedPhonemeGroups.insert(groupIdx)
            }

            // Calculate duration
            let duration: TimeInterval
            if !matchedPhonemes.isEmpty {
                if hasDurations {
                    duration = matchedPhonemes.reduce(0.0) { $0 + $1.duration }
                } else {
                    // Estimate 50ms per phoneme
                    duration = Double(matchedPhonemes.count) * 0.05
                }
            } else {
                // No phonemes found - skip this word (no highlighting)
                print("[PhonemeAlign] ⚠️ No phonemes found for '\(displayText)' - skipping")
                continue
            }

            let rangeLocation = originalText.distance(from: originalText.startIndex, to: displayRange.lowerBound)
            let rangeLength = originalText.distance(from: displayRange.lowerBound, to: displayRange.upperBound)

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: currentTime,
                duration: duration,
                text: displayText,
                rangeLocation: rangeLocation,
                rangeLength: rangeLength
            ))

            currentTime += duration

            // Debug first few words
            if index < 3 {
                print("   Word[\(index)] '\(displayText)' @ \(String(format: "%.3f", currentTime - duration))s for \(String(format: "%.3f", duration))s")
            }
        }

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: currentTime,
            wordTimings: wordTimings
        )
    }

    /// Find phonemes for a display word by matching with normalized words
    /// Returns both the matched phonemes and the indices of consumed phoneme groups
    private func findPhonemesForDisplayWord(
        displayText: String,
        normalizedWords: [String],
        normalizedToPhonemes: [String: [PhonemeInfo]],
        allPhonemeGroups: [[PhonemeInfo]],
        currentGroupIndex: Int,
        consumedGroups: Set<Int>
    ) -> ([PhonemeInfo], [Int]) {
        let displayLower = displayText.lowercased()
        var usedGroups: [Int] = []

        // Case 1: Direct match
        if let phonemes = normalizedToPhonemes[displayLower] {
            // Find which group index this corresponds to
            for (idx, group) in allPhonemeGroups.enumerated() {
                if !consumedGroups.contains(idx) && group == phonemes {
                    usedGroups.append(idx)
                    break
                }
            }
            return (phonemes, usedGroups)
        }

        // Case 2: Handle contractions (don't -> do not)
        if displayLower.contains("'") {
            // Common contractions
            let expansions: [String: [String]] = [
                "don't": ["do", "not"],
                "won't": ["will", "not"],
                "can't": ["can", "not"],
                "shouldn't": ["should", "not"],
                "wouldn't": ["would", "not"],
                "couldn't": ["could", "not"],
                "didn't": ["did", "not"],
                "isn't": ["is", "not"],
                "aren't": ["are", "not"],
                "wasn't": ["was", "not"],
                "weren't": ["were", "not"],
                "haven't": ["have", "not"],
                "hasn't": ["has", "not"],
                "hadn't": ["had", "not"],
                "i'm": ["i", "am"],
                "you're": ["you", "are"],
                "we're": ["we", "are"],
                "they're": ["they", "are"],
                "it's": ["it", "is"],
                "he's": ["he", "is"],
                "she's": ["she", "is"],
                "that's": ["that", "is"],
                "what's": ["what", "is"],
                "let's": ["let", "us"],
                "i've": ["i", "have"],
                "you've": ["you", "have"],
                "we've": ["we", "have"],
                "they've": ["they", "have"],
                "i'll": ["i", "will"],
                "you'll": ["you", "will"],
                "he'll": ["he", "will"],
                "she'll": ["she", "will"],
                "we'll": ["we", "will"],
                "they'll": ["they", "will"],
                "i'd": ["i", "would"]
            ]

            if let expanded = expansions[displayLower] {
                var combinedPhonemes: [PhonemeInfo] = []
                for word in expanded {
                    if let phonemes = normalizedToPhonemes[word] {
                        combinedPhonemes.append(contentsOf: phonemes)
                        // Find and mark the group as used
                        for (idx, group) in allPhonemeGroups.enumerated() {
                            if !consumedGroups.contains(idx) && !usedGroups.contains(idx) && group == phonemes {
                                usedGroups.append(idx)
                                break
                            }
                        }
                    }
                }
                if !combinedPhonemes.isEmpty {
                    return (combinedPhonemes, usedGroups)
                }
            }
        }

        // Case 3: Handle abbreviations (Dr. -> doctor)
        let abbreviations: [String: String] = [
            "dr": "doctor",
            "mr": "mister",
            "mrs": "missus",
            "ms": "miss",
            "prof": "professor",
            "st": "street",
            "ave": "avenue",
            "blvd": "boulevard",
            "jr": "junior",
            "sr": "senior"
        ]

        let cleanDisplay = displayLower.replacingOccurrences(of: ".", with: "")
        if let expanded = abbreviations[cleanDisplay],
           let phonemes = normalizedToPhonemes[expanded] {
            // Find which group this corresponds to
            for (idx, group) in allPhonemeGroups.enumerated() {
                if !consumedGroups.contains(idx) && group == phonemes {
                    usedGroups.append(idx)
                    break
                }
            }
            return (phonemes, usedGroups)
        }

        // Case 4: Handle numbers and complex expansions
        // Numbers like "$99.99" expand to multiple words: "ninety nine dollars and ninety nine cents"
        // For these cases, we need to consume multiple phoneme groups
        if displayText.contains(where: { $0.isNumber }) || displayText.hasPrefix("$") {
            print("[PhonemeAlign] Detected number/currency: '\(displayText)'")

            // Try to match by position and consume multiple groups if needed
            // This is a heuristic: numbers typically expand to 3-8 words
            var numberPhonemes: [PhonemeInfo] = []
            let startIndex = currentGroupIndex
            let maxGroups = min(startIndex + 8, allPhonemeGroups.count)

            // Consume phoneme groups until we hit a word that might be the next display word
            for i in startIndex..<maxGroups {
                if i < allPhonemeGroups.count && !consumedGroups.contains(i) {
                    let group = allPhonemeGroups[i]
                    numberPhonemes.append(contentsOf: group)
                    usedGroups.append(i)

                    // If we have enough phonemes for a reasonable duration, stop
                    // (typically 5-15 phonemes for a number)
                    if numberPhonemes.count >= 10 {
                        break
                    }
                }
            }

            if !numberPhonemes.isEmpty {
                print("[PhonemeAlign] Assigned \(numberPhonemes.count) phonemes to number '\(displayText)' using groups \(usedGroups)")
                return (numberPhonemes, usedGroups)
            }
        }

        // Case 5: Try to use positional matching as last resort
        // If we're at position N in display words, try phoneme group N
        if currentGroupIndex < allPhonemeGroups.count && !consumedGroups.contains(currentGroupIndex) {
            print("[PhonemeAlign] Using positional match for '\(displayText)' at index \(currentGroupIndex)")
            return (allPhonemeGroups[currentGroupIndex], [currentGroupIndex])
        }

        // No match found - no highlighting for this word per user's request
        print("[PhonemeAlign] No match found for '\(displayText)' - will not highlight")
        return ([], [])
    }

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

            let rangeLocation = text.distance(from: text.startIndex, to: wordRange.lowerBound)
            let rangeLength = text.distance(from: wordRange.lowerBound, to: wordRange.upperBound)

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: i,
                startTime: currentTime,
                duration: duration,
                text: wordText,
                rangeLocation: rangeLocation,
                rangeLength: rangeLength
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
                let rangeLocation = text.distance(from: text.startIndex, to: lastWordRange.lowerBound)
                let rangeLength = text.distance(from: lastWordRange.lowerBound, to: lastWordRange.upperBound)

                // Create new WordTiming with extended duration (struct is immutable)
                let extendedTiming = AlignmentResult.WordTiming(
                    wordIndex: lastTiming.wordIndex,
                    startTime: lastTiming.startTime,
                    duration: lastTiming.duration + extraDuration,
                    text: lastTiming.text,
                    rangeLocation: rangeLocation,
                    rangeLength: rangeLength
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

            let rangeLocation: Int
            let rangeLength: Int
            if let range = range {
                rangeLocation = displayText.distance(from: displayText.startIndex, to: range.lowerBound)
                rangeLength = displayText.distance(from: range.lowerBound, to: range.upperBound)
            } else {
                rangeLocation = 0
                rangeLength = 0
            }

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: aligned.startTime,
                duration: aligned.duration,
                text: aligned.text,
                rangeLocation: rangeLocation,
                rangeLength: rangeLength
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
