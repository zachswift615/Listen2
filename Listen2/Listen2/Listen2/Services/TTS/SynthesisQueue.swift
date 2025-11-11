//
//  SynthesisQueue.swift
//  Listen2
//

import Foundation

/// Manages background pre-synthesis of text paragraphs to maintain low latency playback
@MainActor
final class SynthesisQueue {

    // MARK: - Configuration

    /// Number of paragraphs to pre-synthesize ahead of current playback
    private let lookaheadCount: Int = 3

    // MARK: - State

    /// Cache of pre-synthesized audio data
    /// Key: paragraph index, Value: synthesized WAV data
    private var cache: [Int: Data] = [:]

    /// Cache of word-level alignments
    /// Key: paragraph index, Value: alignment result
    private var alignments: [Int: AlignmentResult] = [:]

    /// Paragraphs being synthesized in background tasks
    private var synthesizing: Set<Int> = []

    /// Currently active synthesis tasks
    private var activeTasks: [Int: Task<Void, Never>] = [:]

    /// The provider used for synthesis
    private let provider: TTSProvider

    /// All paragraphs text
    private var paragraphs: [String] = []

    /// Current playback rate
    private var speed: Float = 1.0

    /// Word alignment service for performing ASR-based alignment
    private let alignmentService: WordAlignmentService

    /// Disk cache for persistent alignment storage
    private let alignmentCache: AlignmentCache

    /// Document ID for caching alignments
    private var documentID: UUID?

    /// Word map for alignment
    private var wordMap: DocumentWordMap?

    // MARK: - Initialization

    init(provider: TTSProvider, alignmentService: WordAlignmentService, alignmentCache: AlignmentCache) {
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
    /// - Returns: Audio data if available, nil if synthesis is pending
    func getAudio(for index: Int) async throws -> Data? {
        // Check cache first
        if let cachedData = cache[index] {
            // Start pre-synthesizing upcoming paragraphs
            preSynthesizeAhead(from: index)
            return cachedData
        }

        // If already synthesizing, return nil (caller should wait)
        guard !synthesizing.contains(index) else {
            return nil
        }

        // Synthesize now (blocking)
        guard index < paragraphs.count else {
            throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
        }

        let text = paragraphs[index]
        let data = try await provider.synthesize(text, speed: speed)

        // Cache result
        cache[index] = data

        // Perform alignment if word map is available
        await performAlignment(for: index, audioData: data, text: text)

        // Start pre-synthesizing upcoming paragraphs
        preSynthesizeAhead(from: index)

        return data
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

    private func preSynthesizeAhead(from currentIndex: Int) {

        // Calculate range of paragraphs to pre-synthesize
        let startIndex = currentIndex + 1
        let endIndex = min(currentIndex + lookaheadCount, paragraphs.count - 1)

        for index in startIndex...endIndex {
            // Skip if already cached or synthesizing
            guard cache[index] == nil && !synthesizing.contains(index) else {
                continue
            }

            // Mark as synthesizing
            synthesizing.insert(index)

            // Start background synthesis task
            let task = Task {
                do {
                    let text = paragraphs[index]
                    let data = try await provider.synthesize(text, speed: speed)

                    // Cache result
                    await MainActor.run {
                        cache[index] = data
                        synthesizing.remove(index)
                        activeTasks.removeValue(forKey: index)
                    }

                    // Perform alignment in background
                    await performAlignment(for: index, audioData: data, text: text)
                } catch {
                    // Remove from synthesizing set on error
                    await MainActor.run {
                        synthesizing.remove(index)
                        activeTasks.removeValue(forKey: index)
                    }
                    print("[SynthesisQueue] Pre-synthesis failed for paragraph \(index): \(error)")
                }
            }

            activeTasks[index] = task
        }
    }

    /// Perform alignment for synthesized audio
    /// - Parameters:
    ///   - index: Paragraph index
    ///   - audioData: Synthesized WAV audio data
    ///   - text: Paragraph text
    private func performAlignment(for index: Int, audioData: Data, text: String) async {
        // Check if we have the required context for alignment
        guard let wordMap = wordMap, let documentID = documentID else {
            // No word map or document ID - skip alignment gracefully
            print("[SynthesisQueue] Skipping alignment for paragraph \(index): No word map or document ID")
            return
        }

        do {
            // Check disk cache first
            if let cachedAlignment = try await alignmentCache.load(for: documentID, paragraph: index) {
                await MainActor.run {
                    alignments[index] = cachedAlignment
                }
                print("[SynthesisQueue] Loaded cached alignment for paragraph \(index)")
                return
            }

            // Write audio data to temporary file for ASR
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("synthesis_\(index)_\(UUID().uuidString).wav")
            try audioData.write(to: tempURL)

            // Perform alignment using ASR
            let alignment = try await alignmentService.align(
                audioURL: tempURL,
                text: text,
                wordMap: wordMap,
                paragraphIndex: index
            )

            // Store in memory cache
            await MainActor.run {
                alignments[index] = alignment
            }

            // Save to disk cache
            try await alignmentCache.save(alignment, for: documentID, paragraph: index)

            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)

            print("[SynthesisQueue] ✅ Alignment complete for paragraph \(index): \(alignment.wordTimings.count) words")
        } catch {
            // Log error but don't fail - alignment is optional
            print("[SynthesisQueue] ⚠️ Alignment failed for paragraph \(index): \(error)")
        }
    }

    private func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
