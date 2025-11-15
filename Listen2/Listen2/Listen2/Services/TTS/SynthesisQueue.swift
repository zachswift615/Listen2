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

    /// Paragraphs being synthesized in background tasks
    private var synthesizing: Set<Int> = []

    /// Gate to prevent concurrent synthesis operations
    /// CRITICAL: Only ONE synthesis should run at a time to prevent CPU/memory explosion
    /// Uses continuation queue for atomic lock acquisition (prevents check-then-set race)
    private var isSynthesizing: Bool = false
    private var synthesisWaitQueue: [CheckedContinuation<Void, Never>] = []

    /// Currently active synthesis tasks
    private var activeTasks: [Int: Task<Void, Never>] = [:]

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
    func setContent(paragraphs: [String], speed: Float, documentID: UUID? = nil, wordMap: DocumentWordMap? = nil) {
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
    }

    /// Update playback speed (clears cache as audio needs re-synthesis)
    func setSpeed(_ speed: Float) {
        guard self.speed != speed else { return }

        self.speed = speed

        // Clear cache - speed change requires re-synthesis and re-alignment
        cancelAll()
        cache.removeAll()
        alignments.removeAll()
        synthesizing.removeAll()
    }

    /// Get synthesized audio for a paragraph, synthesizing if not cached
    /// - Returns: Audio data (waits for ongoing synthesis if needed)
    func getAudio(for index: Int) async throws -> Data? {
        // Check cache first
        if let cachedData = cache[index] {
            // Start pre-synthesizing upcoming paragraphs
            preSynthesizeAhead(from: index)
            return cachedData
        }

        // If pre-synthesis is already in progress for this paragraph, WAIT for it
        // FIX: Don't return nil - wait for the background synthesis to complete!
        while synthesizing.contains(index) {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Check cache again - pre-synthesis might have completed
            if let cachedData = cache[index] {
                preSynthesizeAhead(from: index)
                return cachedData
            }
        }

        // Still not in cache - synthesize on-demand (blocking)
        guard index < paragraphs.count else {
            throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
        }

        // CRITICAL: Atomically acquire synthesis lock (prevents race condition)
        await acquireSynthesisLock()
        defer { releaseSynthesisLock() } // Always release lock

        let startTime = Date()
        let memoryBefore = getMemoryUsageMB()
        print("[SynthesisQueue] 🔄 Starting on-demand synthesis for paragraph \(index), memory: \(String(format: "%.1f", memoryBefore)) MB")

        let text = paragraphs[index]

        // Perform synthesis (serialized by isSynthesizing gate)
        let result = try await provider.synthesize(text, speed: speed)

        let synthesisTime = Date().timeIntervalSince(startTime)
        let memoryAfter = getMemoryUsageMB()
        let memoryDelta = memoryAfter - memoryBefore
        print("[SynthesisQueue] ✅ On-demand synthesis for paragraph \(index) completed in \(String(format: "%.2f", synthesisTime))s, memory: \(String(format: "%.1f", memoryAfter)) MB (+\(String(format: "%.1f", memoryDelta)) MB)")

        // Cache audio data
        cache[index] = result.audioData

        // Evict old cache entries to prevent memory buildup
        evictOldCacheEntries(currentIndex: index)

        // Perform alignment if word map is available
        let alignmentStart = Date()
        await performAlignment(for: index, result: result)
        let alignmentTime = Date().timeIntervalSince(alignmentStart)

        let totalTime = Date().timeIntervalSince(startTime)
        let memoryFinal = getMemoryUsageMB()
        print("[SynthesisQueue] 📊 Total time for paragraph \(index): \(String(format: "%.2f", totalTime))s (synthesis: \(String(format: "%.2f", synthesisTime))s, alignment: \(String(format: "%.2f", alignmentTime))s), final memory: \(String(format: "%.1f", memoryFinal)) MB")

        // Start pre-synthesizing upcoming paragraphs
        preSynthesizeAhead(from: index)

        return result.audioData
    }

    /// Clear cached data for a specific paragraph
    func clearCache(for index: Int) {
        cache.removeValue(forKey: index)
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
    }

    /// Get alignment for a specific paragraph
    /// - Parameter index: Paragraph index
    /// - Returns: Alignment result if available, nil otherwise
    func getAlignment(for index: Int) -> AlignmentResult? {
        return alignments[index]
    }

    // MARK: - Private Methods

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
        // CRITICAL: Only pre-synthesize if no synthesis is currently running
        guard !isSynthesizing else {
            print("[SynthesisQueue] ⏭️  Skipping pre-synthesis - another synthesis in progress")
            return
        }

        // Calculate range of paragraphs to pre-synthesize
        let startIndex = currentIndex + 1
        let endIndex = min(currentIndex + lookaheadCount, paragraphs.count - 1)

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

        let startTime = Date()
        let memoryBefore = getMemoryUsageMB()
        print("[SynthesisQueue] 🔄 Pre-synthesis paragraph \(index), memory: \(String(format: "%.1f", memoryBefore)) MB")

        do {
            let text = paragraphs[index]

            // Perform synthesis (serialized by gate)
            let result = try await provider.synthesize(text, speed: speed)

            let totalTime = Date().timeIntervalSince(startTime)
            let memoryFinal = getMemoryUsageMB()

            // Cache audio data
            cache[index] = result.audioData
            synthesizing.remove(index)
            activeTasks.removeValue(forKey: index)

            // Evict old cache entries
            evictOldCacheEntries(currentIndex: currentIndex)

            // Perform alignment
            await performAlignment(for: index, result: result)

            print("[SynthesisQueue] ✅ Pre-synthesis paragraph \(index) done - \(String(format: "%.2f", totalTime))s, memory: \(String(format: "%.1f", memoryFinal)) MB")
        } catch {
            // Remove from synthesizing set on error
            synthesizing.remove(index)
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
}
