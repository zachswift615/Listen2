//
//  SynthesisQueue.swift
//  Listen2
//

import Foundation

/// Manages background pre-synthesis of text paragraphs to maintain low latency playback
/// Uses actor isolation for thread-safe access to synthesis state
actor SynthesisQueue {

    // MARK: - Configuration

    /// Number of paragraphs to pre-synthesize ahead of current playback
    /// REDUCED from 3→1 to prevent memory exhaustion (was causing jetsam kills at 2.46 GB)
    private let lookaheadCount: Int = 1

    /// Maximum number of paragraphs to keep cached (current + next)
    /// Prevents unbounded memory growth
    private let maxCacheSize: Int = 2

    // MARK: - State

    /// Cache of pre-synthesized audio data
    /// Key: paragraph index, Value: synthesized WAV data
    private var cache: [Int: Data] = [:]

    /// Cache of word-level alignments
    /// Key: paragraph index, Value: alignment result
    private var alignments: [Int: AlignmentResult] = [:]

    /// Cache of sentence-level synthesis results
    /// Key: paragraph index, Value: array of sentence results
    private var sentenceCache: [Int: [SentenceSynthesisResult]] = [:]

    /// Cache of raw synthesis results for phoneme timeline building
    /// Key: "paragraphIndex-sentenceIndex", Value: synthesis result
    private var synthesisCacheForTimeline: [String: SynthesisResult] = [:]

    /// Tracks which sentences are currently being synthesized
    /// Key format: "paragraphIndex-sentenceIndex"
    private var synthesizingSentences: Set<String> = []

    /// Paragraphs being synthesized in background tasks
    private var synthesizing: Set<Int> = []

    /// Producer-consumer state for sentence synthesis
    private var isProcessingSentences: Bool = false
    private var currentSentenceIndex: Int = 0
    private var currentParagraphIndex: Int = 0
    private let maxSentenceCacheSize: Int = 7  // Cache 5-10 sentences (configurable)

    /// Gate to prevent concurrent synthesis operations
    /// CRITICAL: Only ONE synthesis should run at a time to prevent CPU/memory explosion
    /// Uses continuation queue for atomic lock acquisition (prevents check-then-set race)
    private var isSynthesizing: Bool = false
    private var synthesisWaitQueue: [CheckedContinuation<Void, Never>] = []

    /// Currently active synthesis tasks
    private var activeTasks: [Int: Task<Void, Never>] = [:]

    /// Progress tracking for synthesis (0.0 to 1.0 per paragraph)
    private(set) var synthesisProgress: [Int: Double] = [:]

    /// Currently synthesizing paragraph index (for UI display)
    private(set) var currentlySynthesizing: Int? = nil

    /// The provider used for synthesis
    private let provider: TTSProvider

    /// All paragraphs text
    private var paragraphs: [String] = []

    /// Current playback rate
    private var speed: Float = 1.0

    /// Phoneme alignment service for performing phoneme-based alignment
    private let alignmentService: PhonemeAlignmentService

    /// Disk cache for persistent alignment storage
    private let alignmentCache: AlignmentCache

    /// Document ID for caching alignments
    private var documentID: UUID?

    /// Word map for alignment
    private var wordMap: DocumentWordMap?

    // MARK: - Initialization

    init(provider: TTSProvider, alignmentService: PhonemeAlignmentService, alignmentCache: AlignmentCache) {
        self.provider = provider
        self.alignmentService = alignmentService
        self.alignmentCache = alignmentCache
    }

    // MARK: - Public Methods

    /// Update the content and reset the queue
    func setContent(paragraphs: [String], speed: Float, documentID: UUID? = nil, wordMap: DocumentWordMap? = nil, autoPreSynthesize: Bool = true) {
        // Cancel all active tasks
        cancelAll()

        // Update state
        self.paragraphs = paragraphs
        self.speed = speed
        self.documentID = documentID
        self.wordMap = wordMap
        self.cache.removeAll()
        self.alignments.removeAll()
        self.synthesizing.removeAll()
        self.sentenceCache.removeAll()
        self.synthesizingSentences.removeAll()
        self.synthesisProgress.removeAll()
        self.currentlySynthesizing = nil

        // Reset producer-consumer state
        self.isProcessingSentences = false
        self.currentSentenceIndex = 0
        self.currentParagraphIndex = 0

        // Auto-start pre-synthesis for first paragraph if enabled
        if autoPreSynthesize && !paragraphs.isEmpty {
            startPreSynthesis(count: 1)
        }
    }

    /// Start pre-synthesizing first N paragraphs immediately
    /// - Parameter count: Number of paragraphs to pre-synthesize (default 1)
    func startPreSynthesis(count: Int = 1) {
        let endIndex = min(count - 1, paragraphs.count - 1)

        for index in 0...endIndex {
            // Skip if already cached or synthesizing
            guard cache[index] == nil && !synthesizing.contains(index) else {
                continue
            }

            // Mark as synthesizing
            synthesizing.insert(index)

            // Start synthesis task
            let task = Task {
                do {
                    synthesisProgress[index] = 0.0

                    let text = paragraphs[index]

                    synthesisProgress[index] = 0.5

                    let result = try await provider.synthesize(text, speed: speed)

                    // Cache audio data
                    cache[index] = result.audioData
                    synthesisProgress[index] = 1.0
                    synthesizing.remove(index)
                    activeTasks.removeValue(forKey: index)

                    // Perform alignment
                    await performAlignment(for: index, result: result)

                } catch {
                    synthesizing.remove(index)
                    synthesisProgress.removeValue(forKey: index)
                    activeTasks.removeValue(forKey: index)
                    print("[SynthesisQueue] ⚠️ Pre-synthesis failed for paragraph \(index): \(error)")
                }
            }

            activeTasks[index] = task
        }
    }

    /// Update playback speed (clears cache as audio needs re-synthesis)
    func setSpeed(_ speed: Float) {
        guard self.speed != speed else {
            print("[SynthesisQueue] ⚠️ Speed already set to \(speed), skipping")
            return
        }

        print("[SynthesisQueue] 🎚️ Changing speed from \(self.speed) to \(speed)")
        self.speed = speed

        // Clear ALL caches - speed change requires complete re-synthesis and re-alignment
        print("[SynthesisQueue] 🗑️ Clearing ALL caches for speed change (including sentence-level)")
        cancelAll()

        // Paragraph-level caches
        cache.removeAll()
        alignments.removeAll()
        synthesizing.removeAll()

        // Sentence-level caches (CRITICAL: these must be cleared too!)
        sentenceCache.removeAll()
        synthesisCacheForTimeline.removeAll()
        synthesizingSentences.removeAll()

        // Reset sentence synthesis state
        isProcessingSentences = false
        currentSentenceIndex = 0
        currentParagraphIndex = 0
    }

    /// Get synthesized audio for a paragraph, synthesizing if not cached
    /// Uses sentence-level chunking for faster initial playback
    /// NOTE: This method is primarily for testing. Production code should use streamAudio() for rolling window synthesis.
    /// - Returns: Audio data if available, nil if synthesis is pending
    func getAudio(for index: Int) async throws -> Data? {
        // Check if we have all sentences cached for this paragraph
        guard index < paragraphs.count else {
            throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
        }

        let paragraphText = paragraphs[index]
        let chunks = SentenceSplitter.split(paragraphText)

        // Check if all sentences are cached
        if let cached = sentenceCache[index], cached.count == chunks.count {
            let paragraphResult = ParagraphSynthesisResult(
                paragraphIndex: index,
                sentences: cached.sorted { $0.chunk.index < $1.chunk.index }
            )

            // Cache combined alignment
            if let alignment = paragraphResult.combinedAlignment {
                alignments[index] = alignment
            }

            // Start pre-synthesizing upcoming paragraphs
            preSynthesizeAhead(from: index)

            return paragraphResult.combinedAudioData
        }

        // For tests, synthesize first sentence only and return it
        // (In production, use streamAudio() which does rolling window synthesis)
        let firstSentence = try await synthesizeSentenceAsync(paragraphIndex: index, sentenceIndex: 0)

        // Return first sentence audio to start playback immediately
        return firstSentence.audioData
    }

    /// Clear cached data for a specific paragraph
    func clearCache(for index: Int) {
        cache.removeValue(forKey: index)
        sentenceCache.removeValue(forKey: index)
        activeTasks[index]?.cancel()
        activeTasks.removeValue(forKey: index)
        synthesizing.remove(index)
    }

    /// Clear all cached data and cancel all synthesis tasks
    func clearAll() {
        cancelAll()
        cache.removeAll()
        alignments.removeAll()
        synthesizing.removeAll()
        sentenceCache.removeAll()
        synthesisCacheForTimeline.removeAll()
        synthesizingSentences.removeAll()
        isProcessingSentences = false
        currentSentenceIndex = 0
        currentParagraphIndex = 0
    }

    /// Get alignment for a specific paragraph
    /// - Parameter index: Paragraph index
    /// - Returns: Alignment result if available, nil otherwise
    func getAlignment(for index: Int) -> AlignmentResult? {
        return alignments[index]
    }

    /// Stream audio for a paragraph sentence-by-sentence with producer-consumer architecture
    /// Producer fills cache with sentences, consumer plays them
    /// - Parameter index: Paragraph index
    /// - Returns: AsyncStream of sentence audio data chunks
    func streamAudio(for index: Int) -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                guard index < paragraphs.count else {
                    continuation.finish()
                    return
                }

                let paragraphText = paragraphs[index]
                let chunks = SentenceSplitter.split(paragraphText)

                guard !chunks.isEmpty else {
                    continuation.finish()
                    return
                }

                // Update current paragraph (but DON'T reset sentence index!)
                currentParagraphIndex = index

                // If this is a NEW paragraph (not already cached), reset sentence index
                if sentenceCache[index] == nil || sentenceCache[index]?.isEmpty == true {
                    currentSentenceIndex = 0
                }

                // Start the producer task
                startSentenceProcessing(paragraphIndex: index)

                // Consumer: play sentences as they become available
                for sentenceIndex in 0..<chunks.count {
                    do {
                        // Wait for sentence to be cached
                        let sentence = try await waitForSentence(
                            paragraphIndex: index,
                            sentenceIndex: sentenceIndex
                        )

                        // Yield for playback
                        continuation.yield(sentence.audioData)

                        // Don't call onSentenceFinished here - TTSService will call it
                        // after actual playback completes

                    } catch {
                        print("[SynthesisQueue] Error streaming sentence \(sentenceIndex): \(error)")
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Stream sentence bundles with phoneme timelines for word highlighting
    /// - Parameter index: Paragraph index
    /// - Returns: AsyncStream of sentence bundles with timing data
    func streamSentenceBundles(for index: Int) -> AsyncStream<SentenceBundle> {
        AsyncStream { continuation in
            Task {
                guard index < paragraphs.count else {
                    continuation.finish()
                    return
                }

                let paragraphText = paragraphs[index]
                let chunks = SentenceSplitter.split(paragraphText)

                guard !chunks.isEmpty else {
                    continuation.finish()
                    return
                }

                // Update current paragraph
                currentParagraphIndex = index

                // Reset sentence index for new paragraph
                if sentenceCache[index] == nil || sentenceCache[index]?.isEmpty == true {
                    currentSentenceIndex = 0
                }

                // Start the producer task
                startSentenceProcessing(paragraphIndex: index)

                // Consumer: yield sentence bundles as they become available
                for sentenceIndex in 0..<chunks.count {
                    do {
                        // Wait for sentence to be cached
                        let sentence = try await waitForSentence(
                            paragraphIndex: index,
                            sentenceIndex: sentenceIndex
                        )

                        // Create bundle with phoneme timeline
                        let bundle = createSentenceBundle(
                            from: sentence,
                            paragraphIndex: index,
                            sentenceIndex: sentenceIndex
                        )

                        // Yield bundle for playback and highlighting
                        continuation.yield(bundle)

                    } catch {
                        print("[SynthesisQueue] Error streaming bundle \(sentenceIndex): \(error)")
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Clear cache when user navigates (skip/TOC/etc)
    func clearCacheAndReset() {
        sentenceCache.removeAll()
        synthesizingSentences.removeAll()
        currentSentenceIndex = 0
        isProcessingSentences = false
        print("[SynthesisQueue] Cache cleared, ready for new paragraph")
    }

    /// Callback to start sentence processing if not already running
    /// Called by: streamAudio() initially, and onSentenceFinished
    func startSentenceProcessing(paragraphIndex: Int) {
        // Check if already running
        if isProcessingSentences {
            return  // Already running, do nothing
        }

        // Start the processing task
        Task {
            await runSentenceProcessingTask(paragraphIndex: paragraphIndex)
        }
    }

    /// Called when a sentence finishes playing
    /// Removes sentence from cache and restarts processing if needed
    func onSentenceFinished(paragraphIndex: Int, sentenceIndex: Int) {
        // Remove finished sentence from cache
        if var sentences = sentenceCache[paragraphIndex] {
            sentences = sentences.filter { $0.chunk.index != sentenceIndex }
            if sentences.isEmpty {
                sentenceCache.removeValue(forKey: paragraphIndex)
            } else {
                sentenceCache[paragraphIndex] = sentences
            }
        }

        let key = "\(paragraphIndex)-\(sentenceIndex)"
        synthesizingSentences.remove(key)

        print("[SynthesisQueue] 🗑️ Removed sentence \(paragraphIndex)-\(sentenceIndex)")

        // Check if we're near end of current paragraph
        let paragraphText = paragraphs[safe: paragraphIndex] ?? ""
        let chunks = SentenceSplitter.split(paragraphText)
        let remainingSentences = chunks.count - sentenceIndex - 1

        // If 2 or fewer sentences left in current paragraph, start next paragraph lookahead
        if remainingSentences <= 2 {
            let nextParagraphIndex = paragraphIndex + 1
            if nextParagraphIndex < paragraphs.count {
                print("[SynthesisQueue] 🔮 Starting lookahead for paragraph \(nextParagraphIndex)")
                startSentenceProcessing(paragraphIndex: nextParagraphIndex)
            }
        }

        // Also restart current paragraph processing if cache has space
        startSentenceProcessing(paragraphIndex: paragraphIndex)
    }

    // MARK: - Private Methods

    /// Background task that fills cache with sentences
    /// Runs in loop until cache is full, then stops
    /// Will be restarted by onSentenceFinished when space is available
    /// Processes across paragraph boundaries to maintain lookahead
    private func runSentenceProcessingTask(paragraphIndex: Int) async {
        isProcessingSentences = true
        defer { isProcessingSentences = false }

        var currentPara = paragraphIndex

        // Loop across paragraphs until cache is full
        while currentPara < paragraphs.count {
            guard currentPara < paragraphs.count else { break }

            let paragraphText = paragraphs[currentPara]
            let chunks = SentenceSplitter.split(paragraphText)

            // Find next sentence index to process for THIS paragraph
            var processingIndex = 0
            if currentPara == currentParagraphIndex {
                processingIndex = currentSentenceIndex
            }
            // For lookahead paragraphs, start from 0

            // Loop: process sentences in this paragraph until done or cache full
            while processingIndex < chunks.count {
                // Check TOTAL cache size across all paragraphs
                let totalCacheSize = sentenceCache.values.reduce(0) { $0 + $1.count }
                if totalCacheSize >= maxSentenceCacheSize {
                    print("[SynthesisQueue] Total cache full (\(totalCacheSize)/\(maxSentenceCacheSize)), pausing")
                    return  // Exit entirely - cache is full
                }

                // Process next sentence
                let key = "\(currentPara)-\(processingIndex)"
                if !synthesizingSentences.contains(key) {
                    do {
                        _ = try await synthesizeSentenceAsync(
                            paragraphIndex: currentPara,
                            sentenceIndex: processingIndex
                        )
                        print("[SynthesisQueue] ✅ Cached \(currentPara)-\(processingIndex)")
                        processingIndex += 1

                        // Update currentSentenceIndex only for current playback paragraph
                        if currentPara == currentParagraphIndex {
                            currentSentenceIndex = processingIndex
                        }
                    } catch {
                        print("[SynthesisQueue] ❌ \(currentPara)-\(processingIndex) failed: \(error)")
                        return  // Exit on error
                    }
                } else {
                    processingIndex += 1
                }
            }

            print("[SynthesisQueue] Paragraph \(currentPara) complete, moving to next")
            currentPara += 1  // Move to next paragraph
        }

        print("[SynthesisQueue] All paragraphs processed")
    }

    /// Remove played sentence from cache to free memory
    /// Only keeps unplayed sentences (sentenceIndex+1 onwards)
    private func cleanupPlayedSentence(paragraphIndex: Int, sentenceIndex: Int) {
        let key = "\(paragraphIndex)-\(sentenceIndex)"

        // Remove from sentence cache
        if var sentences = sentenceCache[paragraphIndex] {
            // Keep only unplayed sentences (sentenceIndex+1 onwards)
            sentences = sentences.filter { $0.chunk.index > sentenceIndex }
            if sentences.isEmpty {
                sentenceCache.removeValue(forKey: paragraphIndex)
            } else {
                sentenceCache[paragraphIndex] = sentences
            }
        }

        // Remove from tracking
        synthesizingSentences.remove(key)

        print("[SynthesisQueue] 🗑️ Cleaned up played sentence \(paragraphIndex)-\(sentenceIndex)")
    }

    /// Synthesize a single sentence with streaming callbacks
    /// Uses ONNX streaming for progress + async for parallelization
    /// - Parameters:
    ///   - paragraphIndex: The paragraph index
    ///   - sentenceIndex: The sentence index within paragraph
    /// - Returns: Sentence synthesis result
    private func synthesizeSentenceAsync(paragraphIndex: Int, sentenceIndex: Int) async throws -> SentenceSynthesisResult {
        let key = "\(paragraphIndex)-\(sentenceIndex)"

        // Get paragraph text
        guard paragraphIndex < paragraphs.count else {
            throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
        }

        let paragraphText = paragraphs[paragraphIndex]
        let chunks = SentenceSplitter.split(paragraphText)

        guard sentenceIndex < chunks.count else {
            throw TTSError.synthesisFailed(reason: "Invalid sentence index")
        }

        let chunk = chunks[sentenceIndex]

        // Mark as synthesizing
        synthesizingSentences.insert(key)
        currentlySynthesizing = paragraphIndex
        synthesisProgress[paragraphIndex] = Double(sentenceIndex) / Double(chunks.count)

        // Synthesize with streaming callback (ONNX native streaming!)
        print("[SynthesisQueue] 🎵 Synthesizing sentence \(sentenceIndex) of paragraph \(paragraphIndex) at speed: \(speed)")
        let result = try await provider.synthesizeWithStreaming(
            chunk.text,
            speed: speed,
            delegate: self  // Receive progress callbacks
        )

        // Store synthesis result for timeline building
        synthesisCacheForTimeline[key] = result

        // Perform alignment for this sentence
        let alignment = await performAlignmentForSentence(
            paragraphIndex: paragraphIndex,
            chunk: chunk,
            result: result
        )

        let sentenceResult = SentenceSynthesisResult(
            chunk: chunk,
            audioData: result.audioData,
            alignment: alignment
        )

        // Cache the result
        if sentenceCache[paragraphIndex] == nil {
            sentenceCache[paragraphIndex] = []
        }
        sentenceCache[paragraphIndex]?.append(sentenceResult)
        synthesizingSentences.remove(key)

        // Update progress
        let completedCount = sentenceCache[paragraphIndex]?.count ?? 0
        synthesisProgress[paragraphIndex] = Double(completedCount) / Double(chunks.count)

        if completedCount == chunks.count {
            currentlySynthesizing = nil
        }

        return sentenceResult
    }

    /// Synthesize all sentences in a paragraph concurrently
    /// This is where the magic happens - PARALLEL SYNTHESIS!
    /// - Parameter index: Paragraph index
    func synthesizeAllSentencesAsync(for index: Int) {
        guard index < paragraphs.count else { return }

        let paragraphText = paragraphs[index]
        let chunks = SentenceSplitter.split(paragraphText)

        // Launch parallel synthesis tasks for ALL sentences
        for sentenceIndex in 0..<chunks.count {
            let key = "\(index)-\(sentenceIndex)"
            guard !synthesizingSentences.contains(key) else { continue }

            Task {
                do {
                    _ = try await synthesizeSentenceAsync(
                        paragraphIndex: index,
                        sentenceIndex: sentenceIndex
                    )
                    print("[SynthesisQueue] ✅ Sentence \(sentenceIndex+1)/\(chunks.count) ready")
                } catch {
                    print("[SynthesisQueue] ❌ Sentence \(sentenceIndex) failed: \(error)")
                }
            }
        }
    }

    /// Create a sentence bundle with phoneme timeline
    private func createSentenceBundle(
        from sentenceResult: SentenceSynthesisResult,
        paragraphIndex: Int,
        sentenceIndex: Int
    ) -> SentenceBundle {
        let key = "\(paragraphIndex)-\(sentenceIndex)"
        print("[SynthesisQueue] Creating bundle for sentence \(key)")

        // Try to get cached synthesis result for timeline building
        var timeline: PhonemeTimeline? = nil
        if let synthesisResult = synthesisCacheForTimeline[key] {
            print("[SynthesisQueue] Found synthesis result with \(synthesisResult.phonemes.count) phonemes")
            print("[SynthesisQueue] Normalized text: '\(synthesisResult.normalizedText)'")
            print("[SynthesisQueue] CharMapping count: \(synthesisResult.charMapping.count)")

            timeline = PhonemeTimelineBuilder.build(
                from: synthesisResult,
                sentence: sentenceResult.chunk.text,
                wordMap: wordMap,
                paragraphIndex: paragraphIndex,
                sentenceOffset: sentenceResult.chunk.range.lowerBound
            )

            if timeline == nil {
                print("[SynthesisQueue] ❌ Failed to build timeline for sentence \(key)")
            } else {
                print("[SynthesisQueue] ✓ Built timeline with \(timeline!.wordBoundaries.count) words")
            }
        } else {
            print("[SynthesisQueue] ❌ No synthesis result cached for \(key)")
        }

        return SentenceBundle(
            chunk: sentenceResult.chunk,
            audioData: sentenceResult.audioData,
            timeline: timeline,
            paragraphIndex: paragraphIndex,
            sentenceIndex: sentenceIndex
        )
    }

    /// Perform alignment for a sentence chunk
    private func performAlignmentForSentence(paragraphIndex: Int, chunk: SentenceChunk, result: SynthesisResult) async -> AlignmentResult? {
        // Check cache first
        if let documentID = documentID,
           let cached = try? await alignmentCache.load(
               for: documentID,
               paragraph: paragraphIndex,
               speed: speed
           ) {
            return cached
        }

        // Perform alignment for sentence
        guard let wordMap = wordMap else { return nil }

        do {
            let alignment = try await alignmentService.align(
                phonemes: result.phonemes,
                text: result.text,
                normalizedText: result.normalizedText,
                charMapping: result.charMapping,
                wordMap: wordMap,
                paragraphIndex: paragraphIndex
            )

            // Don't cache sentence-level alignments individually
            // They'll be combined and cached at paragraph level

            return alignment
        } catch {
            print("[SynthesisQueue] ⚠️ Alignment failed for sentence: \(error)")
            return nil
        }
    }

    /// Wait for a specific sentence to complete synthesis
    private func waitForSentence(paragraphIndex: Int, sentenceIndex: Int) async throws -> SentenceSynthesisResult {
        // Poll until sentence is ready (or timeout)
        let maxWaitTime: TimeInterval = 300  // 5 minutes max
        let pollInterval: TimeInterval = 0.1  // Check every 100ms
        var elapsed: TimeInterval = 0

        while elapsed < maxWaitTime {
            // Check if sentence is cached
            if let cached = sentenceCache[paragraphIndex]?.first(where: { $0.chunk.index == sentenceIndex }) {
                print("[SynthesisQueue] ✅ CACHE HIT: Sentence \(paragraphIndex)-\(sentenceIndex) found in cache (synthesized at speed \(self.speed))")
                return cached
            }

            // Wait a bit
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            elapsed += pollInterval
        }

        print("[SynthesisQueue] ❌ CACHE MISS: Sentence \(paragraphIndex)-\(sentenceIndex) not found after \(maxWaitTime)s")
        throw TTSError.synthesisFailed(reason: "Sentence synthesis timeout")
    }

    /// Atomically acquire synthesis lock (prevents check-then-set race condition)
    private func acquireSynthesisLock() async {
        if isSynthesizing {
            // Lock is held - wait in queue
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                synthesisWaitQueue.append(continuation)
            }
        }
        // Acquired lock
        isSynthesizing = true
    }

    /// Release synthesis lock and resume next waiter in queue
    private func releaseSynthesisLock() {
        if let next = synthesisWaitQueue.first {
            synthesisWaitQueue.removeFirst()
            next.resume()  // Transfer lock to next waiter
        } else {
            // No waiters - release lock
            isSynthesizing = false
        }
    }

    /// Start pre-synthesis in background (nonisolated, returns immediately)
    nonisolated private func preSynthesizeAhead(from currentIndex: Int) {
        Task {
            await doPreSynthesis(from: currentIndex)
        }
    }

    /// Perform pre-synthesis (actor-isolated, serialized)
    private func doPreSynthesis(from currentIndex: Int) async {
        // CRITICAL: Don't start pre-synthesis if ANY synthesis is running
        // This prevents creating multiple concurrent synthesis tasks
        guard !isSynthesizing && activeTasks.isEmpty else {
            print("[SynthesisQueue] ⏭️  Skipping pre-synthesis - synthesis already in progress")
            return
        }

        // Calculate range of paragraphs to pre-synthesize
        let startIndex = currentIndex + 1
        let endIndex = min(currentIndex + lookaheadCount, paragraphs.count - 1)

        // Early return if no paragraphs to pre-synthesize (e.g., already at last paragraph)
        guard startIndex <= endIndex else { return }

        // Only pre-synthesize ONE paragraph at a time
        for index in startIndex...endIndex {
            // Skip if already cached or synthesizing
            guard cache[index] == nil && !synthesizing.contains(index) else {
                continue
            }

            // Mark as synthesizing
            synthesizing.insert(index)

            // Start background synthesis
            let task = Task {
                await synthesizeParagraph(index, currentIndex: currentIndex)
            }

            activeTasks[index] = task

            // CRITICAL: Only start ONE pre-synthesis task at a time
            break
        }
    }

    /// Synthesize a single paragraph (actor-isolated, serialized by atomic lock)
    private func synthesizeParagraph(_ index: Int, currentIndex: Int) async {
        // CRITICAL: Atomically acquire synthesis lock (prevents race condition)
        await acquireSynthesisLock()
        defer { releaseSynthesisLock() } // Always release lock

        // Update progress
        synthesisProgress[index] = 0.0

        let startTime = Date()
        let memoryBefore = getMemoryUsageMB()
        print("[SynthesisQueue] 🔄 Pre-synthesis paragraph \(index), memory: \(String(format: "%.1f", memoryBefore)) MB")

        do {
            let text = paragraphs[index]

            synthesisProgress[index] = 0.5

            // Perform synthesis (serialized by gate)
            let result = try await provider.synthesize(text, speed: speed)

            let totalTime = Date().timeIntervalSince(startTime)
            let memoryFinal = getMemoryUsageMB()

            // Cache audio data
            cache[index] = result.audioData
            synthesisProgress[index] = 1.0
            synthesizing.remove(index)
            activeTasks.removeValue(forKey: index)

            // Evict old cache entries
            evictOldCacheEntries(currentIndex: currentIndex)

            // Perform alignment
            await performAlignment(for: index, result: result)

            print("[SynthesisQueue] ✅ Pre-synthesis paragraph \(index) done - \(String(format: "%.2f", totalTime))s, memory: \(String(format: "%.1f", memoryFinal)) MB")

            // Trigger pre-synthesis for NEXT paragraph (ensures serialization - only called after completion, not on cache hits)
            preSynthesizeAhead(from: index)
        } catch {
            // Remove from synthesizing set on error
            synthesizing.remove(index)
            synthesisProgress.removeValue(forKey: index)
            activeTasks.removeValue(forKey: index)
            let failureTime = Date().timeIntervalSince(startTime)
            print("[SynthesisQueue] ❌ Pre-synthesis failed for paragraph \(index) after \(String(format: "%.2f", failureTime))s: \(error)")
        }
    }

    /// Perform word-level alignment using phoneme sequence from espeak
    /// - Parameters:
    ///   - index: Paragraph index
    ///   - result: Synthesis result containing phonemes
    private func performAlignment(for index: Int, result: SynthesisResult) async {
        // Check disk cache first (if documentID is set)
        if let documentID = documentID,
           let cachedAlignment = try? await alignmentCache.load(
               for: documentID,
               paragraph: index,
               speed: speed
           ) {
            print("[SynthesisQueue] Loaded alignment from disk cache for paragraph \(index)")
            alignments[index] = cachedAlignment
            return
        }

        // Perform phoneme-based alignment with normalized text mapping
        // - PDF: Maps VoxPDF words (original text) to phonemes (normalized text)
        // - EPUB/Clipboard: Uses espeak word grouping in normalized text
        do {
            let alignment = try await alignmentService.align(
                phonemes: result.phonemes,
                text: result.text,
                normalizedText: result.normalizedText,
                charMapping: result.charMapping,
                wordMap: wordMap,  // Optional - used for PDF word extraction
                paragraphIndex: index
            )

            // Store in memory cache
            alignments[index] = alignment

            // Store in disk cache (if documentID is set)
            if let documentID = documentID {
                do {
                    try await alignmentCache.save(
                        alignment,
                        for: documentID,
                        paragraph: index,
                        speed: speed
                    )
                    print("[SynthesisQueue] Saved alignment to disk cache for paragraph \(index)")
                } catch {
                    print("[SynthesisQueue] Failed to save alignment to disk: \(error)")
                    // Non-fatal - we have the alignment in memory
                }
            }

            print("[SynthesisQueue] ✅ Alignment completed for paragraph \(index): \(alignment.wordTimings.count) words, \(String(format: "%.2f", alignment.totalDuration))s")
        } catch {
            print("[SynthesisQueue] ❌ Alignment failed for paragraph \(index): \(error)")
            // Don't throw - alignment is optional for playback
        }
    }

    private func cancelAll() {
        // Cancel all active tasks
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()

        // Resume all waiting continuations (they'll see cancelled tasks)
        for continuation in synthesisWaitQueue {
            continuation.resume()
        }
        synthesisWaitQueue.removeAll()

        // Reset synthesis gate
        isSynthesizing = false
    }

    /// Evict old cache entries to prevent memory buildup
    /// Keeps only current paragraph + lookahead (maxCacheSize)
    private func evictOldCacheEntries(currentIndex: Int) {
        let keepIndices = Set((currentIndex...min(currentIndex + maxCacheSize - 1, paragraphs.count - 1)))

        // Remove audio cache entries outside the window
        let audioToRemove = cache.keys.filter { !keepIndices.contains($0) }
        for index in audioToRemove {
            cache.removeValue(forKey: index)
            print("[SynthesisQueue] 🗑️ Evicted audio cache for paragraph \(index)")
        }

        // Remove alignment cache entries outside the window
        let alignmentToRemove = alignments.keys.filter { !keepIndices.contains($0) }
        for index in alignmentToRemove {
            alignments.removeValue(forKey: index)
            print("[SynthesisQueue] 🗑️ Evicted alignment cache for paragraph \(index)")
        }

        // Remove sentence cache entries outside the window
        let sentenceToRemove = sentenceCache.keys.filter { !keepIndices.contains($0) }
        for index in sentenceToRemove {
            sentenceCache.removeValue(forKey: index)
            print("[SynthesisQueue] 🗑️ Evicted sentence cache for paragraph \(index)")
        }
    }

    /// Get current memory usage in MB
    private func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    /// Log detailed memory breakdown for debugging
    func logMemoryBreakdown() {
        let totalMB = getMemoryUsageMB()

        // Calculate cache sizes
        let audioDataSize = cache.values.reduce(0) { $0 + $1.count }
        let audioDataMB = Double(audioDataSize) / 1024.0 / 1024.0

        // Estimate alignment data size (rough calculation)
        let alignmentCount = alignments.values.reduce(0) { $0 + $1.wordTimings.count }
        let estimatedAlignmentMB = Double(alignmentCount * 64) / 1024.0 / 1024.0 // ~64 bytes per WordTiming

        print("📊 [MEMORY] Total: \(String(format: "%.1f", totalMB)) MB")
        print("📊 [MEMORY] Audio cache: \(cache.count) entries, \(String(format: "%.1f", audioDataMB)) MB")
        print("📊 [MEMORY] Alignment cache: \(alignments.count) entries, ~\(String(format: "%.1f", estimatedAlignmentMB)) MB estimated")
        print("📊 [MEMORY] Synthesizing: \(synthesizing.count) active")
        print("📊 [MEMORY] Tasks: \(activeTasks.count) active")
        print("📊 [MEMORY] Unaccounted: ~\(String(format: "%.1f", totalMB - audioDataMB - estimatedAlignmentMB)) MB (ONNX runtime, frameworks, etc.)")
    }
}

// MARK: - SynthesisStreamDelegate

extension SynthesisQueue: SynthesisStreamDelegate {
    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        // Store chunk for currently synthesizing sentence
        // This is called from ONNX thread - update on actor
        Task {
            await updateProgress(progress: progress)
        }

        return true  // Continue synthesis
    }

    /// Update synthesis progress (internal actor method for streaming callback)
    private func updateProgress(progress: Double) {
        if let currentIndex = currentlySynthesizing {
            synthesisProgress[currentIndex] = progress
        }
    }
}
