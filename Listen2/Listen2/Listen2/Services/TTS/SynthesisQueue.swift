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

    // MARK: - Initialization

    init(provider: TTSProvider) {
        self.provider = provider
    }

    // MARK: - Public Methods

    /// Update the content and reset the queue
    func setContent(paragraphs: [String], speed: Float) {
        // Cancel all active tasks
        cancelAll()

        // Update state
        self.paragraphs = paragraphs
        self.speed = speed
        self.cache.removeAll()
        self.synthesizing.removeAll()
    }

    /// Update playback speed (clears cache as audio needs re-synthesis)
    func setSpeed(_ speed: Float) {
        guard self.speed != speed else { return }

        self.speed = speed

        // Clear cache - speed change requires re-synthesis
        cancelAll()
        cache.removeAll()
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
        synthesizing.removeAll()
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

    private func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
