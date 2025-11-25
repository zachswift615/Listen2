//
//  SynthesisQueue.swift
//  Listen2
//
//  Manages just-in-time synthesis with streaming callbacks
//

import Foundation

/// Simplified synthesis queue for chunk-level streaming
/// NO caching, NO pre-synthesis, just trigger synthesis and stream chunks
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
    }

    /// Update playback speed
    func setSpeed(_ speed: Float) {
        self.speed = speed
    }

    /// Stream sentence audio chunks with just-in-time synthesis
    /// - Parameter sentence: Sentence text to synthesize
    /// - Parameter delegate: Callback for receiving audio chunks
    /// - Returns: AsyncStream of audio chunks
    func streamSentence(_ sentence: String, delegate: SynthesisStreamDelegate?) async throws -> Data {
        let result = try await provider.synthesizeWithStreaming(
            sentence,
            speed: speed,
            delegate: delegate
        )

        return result.audioData
    }

    /// Clear all state (for voice changes, etc.)
    func clearAll() {
    }
}
