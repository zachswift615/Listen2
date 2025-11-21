//
//  SynthesisQueue.swift
//  Listen2
//
//  Manages just-in-time synthesis with streaming callbacks
//

import Foundation

/// Simplified synthesis queue for chunk-level streaming
/// Supports optional pre-synthesis to eliminate gaps between sentences
actor SynthesisQueue {

    // MARK: - State

    /// The provider used for synthesis
    private let provider: TTSProvider

    /// All paragraphs text
    private var paragraphs: [String] = []

    /// Current playback rate
    private var speed: Float = 1.0

    /// Document ID for future use (alignment caching removed)
    private var documentID: UUID?

    /// Sentence cache: maps (sentence text, speed) to synthesized audio data
    /// This allows pre-synthesis to eliminate gaps between sentences
    private var sentenceCache: [String: Data] = [:]

    // MARK: - Initialization

    init(provider: TTSProvider) {
        self.provider = provider
    }

    // MARK: - Public Methods

    /// Update the content
    func setContent(paragraphs: [String], speed: Float, documentID: UUID? = nil, wordMap: DocumentWordMap? = nil, autoPreSynthesize: Bool = true) {
        self.paragraphs = paragraphs
        self.speed = speed
        self.documentID = documentID
        print("[SynthesisQueue] Set content: \(paragraphs.count) paragraphs at speed \(speed)")
    }

    /// Update playback speed
    func setSpeed(_ speed: Float) {
        self.speed = speed
        // Clear cache when speed changes since audio is speed-dependent
        sentenceCache.removeAll()
        print("[SynthesisQueue] Speed changed to \(speed), cache cleared")
    }

    /// Pre-synthesize a sentence and store in cache (for eliminating gaps)
    /// - Parameter sentence: Sentence text to synthesize
    /// - Returns: Synthesized audio data
    func synthesizeSentence(_ sentence: String) async throws -> Data {
        let cacheKey = makeCacheKey(sentence: sentence, speed: speed)

        // Check cache first
        if let cached = sentenceCache[cacheKey] {
            print("[SynthesisQueue] 💾 Cache hit for sentence: '\(sentence.prefix(30))...'")
            return cached
        }

        print("[SynthesisQueue] 🎵 Pre-synthesizing sentence: '\(sentence.prefix(50))...'")

        // Synthesize without streaming (we'll stream from cache during playback)
        let result = try await provider.synthesizeWithStreaming(
            sentence,
            speed: speed,
            delegate: nil  // No streaming during pre-synthesis
        )

        // Cache the result
        sentenceCache[cacheKey] = result.audioData
        print("[SynthesisQueue] ✅ Pre-synthesis complete: \(result.audioData.count) bytes (cached)")
        return result.audioData
    }

    /// Stream sentence audio chunks with just-in-time synthesis
    /// - Parameter sentence: Sentence text to synthesize
    /// - Parameter delegate: Callback for receiving audio chunks
    /// - Returns: AsyncStream of audio chunks
    func streamSentence(_ sentence: String, delegate: SynthesisStreamDelegate?) async throws -> Data {
        let cacheKey = makeCacheKey(sentence: sentence, speed: speed)

        // Check cache first (from pre-synthesis)
        if let cached = sentenceCache[cacheKey] {
            print("[SynthesisQueue] 💾 Streaming from cache: '\(sentence.prefix(30))...'")

            // If there's a delegate, send cached data as chunks
            if let delegate = delegate {
                // Split cached audio into chunks and stream them
                let chunkSize = 4096  // ~0.1s at 22050 Hz
                var offset = 0
                while offset < cached.count {
                    let end = min(offset + chunkSize, cached.count)
                    let chunk = cached.subdata(in: offset..<end)
                    let progress = Double(end) / Double(cached.count)
                    _ = delegate.didReceiveAudioChunk(chunk, progress: progress)
                    offset = end
                }
            }

            return cached
        }

        // Not in cache - synthesize with streaming
        print("[SynthesisQueue] 🎵 Synthesizing sentence: '\(sentence.prefix(50))...'")

        let result = try await provider.synthesizeWithStreaming(
            sentence,
            speed: speed,
            delegate: delegate
        )

        // Cache for future use
        sentenceCache[cacheKey] = result.audioData
        print("[SynthesisQueue] ✅ Synthesis complete: \(result.audioData.count) bytes (cached)")
        return result.audioData
    }

    /// Clear all state (for voice changes, etc.)
    func clearAll() {
        sentenceCache.removeAll()
        print("[SynthesisQueue] Cleared (including cache)")
    }

    // MARK: - Private Helpers

    /// Create cache key from sentence and speed
    private func makeCacheKey(sentence: String, speed: Float) -> String {
        // Include speed in key since audio is speed-dependent
        return "\(sentence)|\(speed)"
    }
}
