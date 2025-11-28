//
//  ReadyQueue.swift
//  Listen2
//
//  Manages the unified synthesis + alignment pipeline with lookahead buffering.
//  Uses a sliding window of paragraphs for memory efficiency.
//  Spans paragraph boundaries - continues processing into next paragraph automatically.
//

import Foundation

/// Actor managing the sentence processing pipeline
/// Ensures sentences are only "ready" when both synthesis AND alignment complete
/// Uses sliding window to limit memory usage for large documents
actor ReadyQueue {

    // MARK: - Dependencies

    private let synthesisQueue: SynthesisQueue
    private let ctcAligner: CTCForcedAligner

    /// Logger for pipeline events
    private let logger = TTSLogger.pipeline

    /// Callback to fetch paragraph text on-demand (avoids storing entire document)
    private var fetchParagraph: ((Int) -> String?)?
    private var totalParagraphCount: (() -> Int)?

    // MARK: - Sliding Window State

    /// Sliding window of paragraph text (max `maxParagraphWindow` paragraphs)
    private var paragraphWindow: [Int: String] = [:]

    /// Pre-split sentences for paragraphs in window (evicted with paragraph)
    private var paragraphSentences: [Int: [(text: String, offset: Int)]] = [:]

    // MARK: - Buffer State

    /// Ready sentences: fully processed and waiting for playback
    private var ready: [SentenceKey: ReadySentence] = [:]

    /// Sentences that were skipped (empty/whitespace only)
    private var skipped: Set<SentenceKey> = []

    /// Keys currently being processed (to avoid duplicate work)
    private var processing: Set<SentenceKey> = []

    /// Current buffer size in bytes
    private var currentBufferBytes: Int = 0

    // MARK: - Position Tracking

    /// Current playback position (used for window management)
    private var currentParagraphIndex: Int = 0
    private var currentSentenceIndex: Int = 0

    /// Next position to process in pipeline
    private var nextParagraphToProcess: Int = 0
    private var nextSentenceToProcess: Int = 0

    // MARK: - Pipeline Control

    /// Pipeline task handle
    private var pipelineTask: Task<Void, Never>?

    /// Flag to stop pipeline
    private var shouldStop: Bool = false

    /// Whether word highlighting (and thus alignment) is enabled
    private var wordHighlightingEnabled: Bool = true

    /// Session counter to invalidate stale operations
    private var sessionID: Int = 0

    // MARK: - Initialization

    init(synthesisQueue: SynthesisQueue, ctcAligner: CTCForcedAligner) {
        self.synthesisQueue = synthesisQueue
        self.ctcAligner = ctcAligner
    }

    // MARK: - Configuration

    /// Set document source callbacks (called once when document loads)
    /// This avoids storing the entire document in ReadyQueue
    func setDocumentSource(
        totalCount: @escaping () -> Int,
        fetchParagraph: @escaping (Int) -> String?
    ) {
        self.totalParagraphCount = totalCount
        self.fetchParagraph = fetchParagraph

        // Clear any stale window data
        paragraphWindow.removeAll()
        paragraphSentences.removeAll()
    }

    /// Update whether word highlighting is enabled
    func setWordHighlightingEnabled(_ enabled: Bool) {
        wordHighlightingEnabled = enabled
    }

    // MARK: - Public Methods

    /// Start processing from a specific paragraph
    /// - Parameters:
    ///   - paragraphIndex: Paragraph to start from
    ///   - sentenceIndex: Sentence within paragraph (default 0)
    func startFrom(paragraphIndex: Int, sentenceIndex: Int = 0) {
        // Increment session ID to invalidate any in-flight operations
        sessionID += 1
        let currentSession = sessionID

        // Cancel any existing pipeline
        shouldStop = true
        pipelineTask?.cancel()
        pipelineTask = nil

        // Always clear cache to prevent memory leaks
        ready.removeAll()
        skipped.removeAll()
        processing.removeAll()
        currentBufferBytes = 0
        logger.info("Cache cleared on navigation to P\(paragraphIndex)S\(sentenceIndex)")

        // Update position tracking
        currentParagraphIndex = paragraphIndex
        currentSentenceIndex = sentenceIndex
        nextParagraphToProcess = paragraphIndex
        nextSentenceToProcess = sentenceIndex
        shouldStop = false

        // Slide window to new position
        slideWindowTo(paragraphIndex: paragraphIndex)

        // Start the pipeline
        pipelineTask = Task { [weak self, currentSession] in
            await self?.runPipeline(session: currentSession)
        }
    }

    /// Atomically wait for and take a sentence (prevents race conditions)
    /// Returns nil if cancelled/stopped, timed out, or the sentence was skipped
    func waitAndTake(paragraphIndex: Int, sentenceIndex: Int) async -> ReadySentence? {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        var iterations = 0

        while !shouldStop && !Task.isCancelled && iterations < ReadyQueueConstants.maxWaitIterations {
            iterations += 1

            // Check if skipped (empty sentence)
            if skipped.contains(key) {
                updateCurrentPosition(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
                kickPipeline()
                return nil
            }

            // Atomically check and remove
            if let sentence = ready.removeValue(forKey: key) {
                currentBufferBytes -= sentence.chunks.reduce(0) { $0 + $1.count }

                updateCurrentPosition(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
                kickPipeline()

                return sentence
            }

            // Brief sleep to avoid busy-waiting
            try? await Task.sleep(nanoseconds: ReadyQueueConstants.waitIntervalNanos)
        }

        return nil
    }

    /// Check if a sentence was skipped (empty/whitespace)
    func wasSkipped(paragraphIndex: Int, sentenceIndex: Int) -> Bool {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return skipped.contains(key)
    }

    /// Check if a sentence is ready without removing it
    func isReady(paragraphIndex: Int, sentenceIndex: Int) -> Bool {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return ready[key] != nil || skipped.contains(key)
    }

    /// Get sentence count for a paragraph
    func getSentenceCount(forParagraph index: Int) -> Int {
        return getSentences(forParagraph: index).count
    }

    /// Stop the pipeline and clear all state
    func stopPipeline() {
        sessionID += 1  // Invalidate in-flight operations
        shouldStop = true
        pipelineTask?.cancel()
        pipelineTask = nil
        ready.removeAll()
        skipped.removeAll()
        processing.removeAll()
        currentBufferBytes = 0

        // Clear paragraph cache to release document memory when navigating away
        paragraphWindow.removeAll()
        paragraphSentences.removeAll()
    }

    /// Get current buffer status
    func getStatus() -> String {
        let mbUsed = Double(currentBufferBytes) / (1024 * 1024)
        let processingList = processing.map { $0.description }.joined(separator: ", ")
        let processingInfo = processing.isEmpty ? "none" : "\(processing.count) [\(processingList)]"

        return "Ready: \(ready.count)/\(ReadyQueueConstants.maxSentenceLookahead), Processing: \(processingInfo), Skipped: \(skipped.count), Buffer: \(String(format: "%.2f", mbUsed))MB, Window: \(paragraphWindow.count) paragraphs, Highlighting: \(wordHighlightingEnabled ? "on" : "off")"
    }

    // MARK: - Private: Position Management

    /// Update current playback position and slide window if needed
    private func updateCurrentPosition(paragraphIndex: Int, sentenceIndex: Int) {
        let oldParagraph = currentParagraphIndex
        currentParagraphIndex = paragraphIndex
        currentSentenceIndex = sentenceIndex

        // If we've moved to a new paragraph, slide the window
        if paragraphIndex > oldParagraph {
            slideWindowTo(paragraphIndex: paragraphIndex)
        }
    }

    /// Slide the paragraph window to center around the given index
    /// Evicts paragraphs that are now behind the playback position
    private func slideWindowTo(paragraphIndex: Int) {
        // Remove paragraphs before current position
        let paragraphsToRemove = paragraphWindow.keys.filter { $0 < paragraphIndex }
        for pIdx in paragraphsToRemove {
            paragraphWindow.removeValue(forKey: pIdx)
            paragraphSentences.removeValue(forKey: pIdx)
        }

        // Also evict ready/skipped/processing sentences for removed paragraphs (prevents memory leak)
        if !paragraphsToRemove.isEmpty {
            var evictedSentences = 0
            var freedBytes = 0
            var stuckProcessingSentences = 0

            for pIdx in paragraphsToRemove {
                // Evict ready sentences
                let readyKeysToEvict = ready.keys.filter { $0.paragraphIndex == pIdx }
                for key in readyKeysToEvict {
                    if let sentence = ready.removeValue(forKey: key) {
                        let bytes = sentence.chunks.reduce(0) { $0 + $1.count }
                        currentBufferBytes -= bytes
                        freedBytes += bytes
                        evictedSentences += 1
                    }
                }

                // Evict skipped sentences
                let skippedCountBefore = skipped.count
                skipped = skipped.filter { $0.paragraphIndex != pIdx }
                evictedSentences += (skippedCountBefore - skipped.count)

                // Evict stuck processing sentences (cleanup orphaned processing state)
                let processingKeysToEvict = processing.filter { $0.paragraphIndex == pIdx }
                for key in processingKeysToEvict {
                    processing.remove(key)
                    stuckProcessingSentences += 1
                }
            }

            // Log buffer eviction
            if evictedSentences > 0 {
                let freedMB = Double(freedBytes) / (1024 * 1024)
                TTSLogger.buffer.info("Evicted \(evictedSentences) sentences from buffer, freed \(String(format: "%.2f", freedMB)) MB")
            }

            // Warn about stuck processing sentences
            if stuckProcessingSentences > 0 {
                TTSLogger.buffer.warning("Cleaned up \(stuckProcessingSentences) stuck processing sentences during window slide")
            }
        }
    }

    // MARK: - Private: Paragraph/Sentence Access

    /// Get paragraph text, loading into window if needed
    private func getParagraphText(at index: Int) -> String? {
        // Check window first
        if let text = paragraphWindow[index] {
            return text
        }

        // Fetch from source
        guard let fetch = fetchParagraph, let text = fetch(index) else {
            return nil
        }

        // Enforce window size limit before adding
        while paragraphWindow.count >= ReadyQueueConstants.maxParagraphWindow {
            // Remove oldest paragraph (lowest index)
            if let oldest = paragraphWindow.keys.min() {
                paragraphWindow.removeValue(forKey: oldest)
                paragraphSentences.removeValue(forKey: oldest)
            }
        }

        // Add to window
        paragraphWindow[index] = text
        return text
    }

    /// Get or compute sentences for a paragraph
    private func getSentences(forParagraph index: Int) -> [(text: String, offset: Int)] {
        // Check cache first
        if let cached = paragraphSentences[index] {
            return cached
        }

        // Get paragraph text (loads into window if needed)
        guard let text = getParagraphText(at: index) else {
            return []
        }

        // Split into sentences
        let chunks = SentenceSplitter.split(text)
        let sentences = chunks.map { ($0.text, $0.range.lowerBound) }
        paragraphSentences[index] = sentences
        return sentences
    }

    /// Get total paragraph count from source
    private func getTotalParagraphCount() -> Int {
        return totalParagraphCount?() ?? 0
    }

    // MARK: - Private: Pipeline Position

    /// Get next position to process, advancing across paragraph boundaries
    private func getNextPosition() -> (paragraphIndex: Int, sentenceIndex: Int)? {
        var pIdx = nextParagraphToProcess
        var sIdx = nextSentenceToProcess
        let total = getTotalParagraphCount()

        while pIdx < total {
            let sentences = getSentences(forParagraph: pIdx)
            if sIdx < sentences.count {
                return (pIdx, sIdx)
            }
            // Move to next paragraph
            pIdx += 1
            sIdx = 0
        }

        return nil // End of document
    }

    /// Advance the next-to-process pointer
    private func advanceNextPosition() {
        let sentences = getSentences(forParagraph: nextParagraphToProcess)
        nextSentenceToProcess += 1

        if nextSentenceToProcess >= sentences.count {
            // Move to next paragraph
            nextParagraphToProcess += 1
            nextSentenceToProcess = 0
        }
    }

    /// Kick the pipeline to continue processing (called after taking a sentence)
    private func kickPipeline() {
        // If pipeline task is nil or cancelled, restart it
        if pipelineTask == nil || (pipelineTask?.isCancelled ?? true) {
            let currentSession = sessionID
            shouldStop = false
            pipelineTask = Task { [weak self, currentSession] in
                await self?.runPipeline(session: currentSession)
            }
        }
    }

    // MARK: - Private: Pipeline Loop

    /// Main pipeline loop - processes sentences ahead of playback across paragraphs
    private func runPipeline(session: Int) async {
        while !shouldStop && !Task.isCancelled && session == sessionID {
            // Check if we have room in the buffer (count and memory)
            guard ready.count < ReadyQueueConstants.maxSentenceLookahead &&
                  currentBufferBytes < ReadyQueueConstants.maxBufferBytes else {
                try? await Task.sleep(nanoseconds: ReadyQueueConstants.pipelineIdleIntervalNanos)
                continue
            }

            // Get next position to process (spans paragraphs)
            guard let (pIdx, sIdx) = getNextPosition() else {
                // End of document - pipeline exits, will restart if needed via kickPipeline
                break
            }

            let key = SentenceKey(paragraphIndex: pIdx, sentenceIndex: sIdx)

            // Skip if already processing, ready, or skipped
            guard !processing.contains(key) && ready[key] == nil && !skipped.contains(key) else {
                advanceNextPosition()
                continue
            }

            // Mark as processing
            processing.insert(key)
            advanceNextPosition()

            let sentences = getSentences(forParagraph: pIdx)
            guard sIdx < sentences.count else {
                processing.remove(key)
                continue
            }

            let (text, offset) = sentences[sIdx]

            // Check cancellation/session before slow operation
            guard !Task.isCancelled && !shouldStop && session == sessionID else {
                break
            }

            // Process the sentence (synthesis + alignment if enabled)
            if let readySentence = await processSentence(
                text: text,
                offset: offset,
                paragraphIndex: pIdx,
                sentenceIndex: sIdx,
                session: session
            ) {
                // Check cancellation/session after slow operation
                guard !Task.isCancelled && !shouldStop && session == sessionID else {
                    break
                }

                // Add to ready buffer
                ready[key] = readySentence
                currentBufferBytes += readySentence.chunks.reduce(0) { $0 + $1.count }
                processing.remove(key)
            } else {
                // processSentence returned nil - check if it was due to session invalidation
                // IMPORTANT: Don't mark as "skipped" if session was invalidated during processing
                // because the sentence content is NOT actually empty - it just wasn't processed
                guard session == sessionID && !Task.isCancelled && !shouldStop else {
                    processing.remove(key)
                    break
                }

                // Session is still valid, so this was truly an empty/failed sentence
                skipped.insert(key)
                processing.remove(key)
            }
        }
    }

    // MARK: - Private: Sentence Processing

    /// Process a single sentence through synthesis + alignment (if enabled)
    private func processSentence(
        text: String,
        offset: Int,
        paragraphIndex: Int,
        sentenceIndex: Int,
        session: Int
    ) async -> ReadySentence? {
        // Skip empty sentences
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // STEP 1: Synthesize audio
        let chunkDelegate = PipelineChunkDelegate()
        do {
            // streamSentence returns WAV data, but we use raw chunks from delegate for alignment
            _ = try await synthesisQueue.streamSentence(text, delegate: chunkDelegate)
        } catch {
            logger.error("Synthesis failed for P\(paragraphIndex)S\(sentenceIndex): \(error.localizedDescription, privacy: .public) | Text: '\(text, privacy: .public)'")

            // Clean up immediately - remove from processing set
            let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
            processing.remove(key)

            // Return nil to skip this sentence (will be marked as skipped by caller)
            return nil
        }

        let chunks = chunkDelegate.getChunks()

        guard !chunks.isEmpty else {
            logger.warning("Synthesis produced empty chunks for P\(paragraphIndex)S\(sentenceIndex) | Text: '\(text, privacy: .public)'")

            // Clean up - remove from processing set
            let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
            processing.remove(key)

            return nil
        }

        // Check cancellation/session between synthesis and alignment
        guard !Task.isCancelled && !shouldStop && session == sessionID else {
            return nil
        }

        // STEP 2: Run CTC alignment (only if highlighting enabled)
        var alignment: AlignmentResult? = nil

        if wordHighlightingEnabled {
            // FIX: Use raw Float32 chunks instead of WAV-encoded combinedAudio
            // The chunks from PipelineChunkDelegate are raw Float32 samples
            // The combinedAudio from synthesisQueue is WAV format (Int16 PCM with header)
            var allSamples: [Float] = []
            for chunk in chunks {
                chunk.withUnsafeBytes { buffer in
                    allSamples.append(contentsOf: buffer.bindMemory(to: Float.self))
                }
            }

            // Safety check: Skip CTC alignment if audio/text is too large to prevent memory spike
            // Trellis matrix size = numFrames × (2 × numTokens + 1)
            // Estimate: 1 char ≈ 1 token, 22050 samples/sec, 49 frames/sec
            let estimatedFrames = allSamples.count / 450  // ~49 frames/sec @ 22050Hz
            let estimatedTokens = text.count
            let estimatedTrellisSize = estimatedFrames * (2 * estimatedTokens + 1)

            // Skip if trellis would exceed device-specific limit (avoids multi-MB allocation)
            if estimatedTrellisSize > ReadyQueueConstants.maxTrellisSize {
                TTSLogger.alignment.warning("Skipping CTC alignment for large sentence (est. \(estimatedTrellisSize) trellis cells): '\(text.prefix(50), privacy: .public)...'")
            } else {
                do {
                    alignment = try await ctcAligner.align(
                        audioSamples: allSamples,
                        sampleRate: ReadyQueueConstants.sampleRate,
                        transcript: text,
                        paragraphIndex: paragraphIndex,
                        sentenceStartOffset: offset
                    )
                } catch {
                    // Log alignment failure - audio will play but highlighting unavailable
                    TTSLogger.alignment.error("CTC alignment failed for text: '\(text, privacy: .public)' - Error: \(error, privacy: .public)")
                    // alignment remains nil for graceful degradation
                }
            }

            // Check cancellation/session after alignment
            guard !Task.isCancelled && !shouldStop && session == sessionID else {
                return nil
            }
        }

        // Create ready sentence
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return ReadySentence(
            key: key,
            chunks: chunks,
            alignment: alignment,
            text: text,
            sentenceOffset: offset
        )
    }
}

// MARK: - Pipeline Chunk Delegate

/// Delegate that accumulates audio chunks for the pipeline
/// Thread-safe for use from synthesis callbacks across actor boundaries
private final class PipelineChunkDelegate: SynthesisStreamDelegate, @unchecked Sendable {
    private var chunks: [Data] = []
    private let lock = NSLock()

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(chunk)
        return true
    }

    nonisolated func getChunks() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }
}
