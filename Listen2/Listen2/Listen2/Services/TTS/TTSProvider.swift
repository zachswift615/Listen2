//
//  TTSProvider.swift
//  Listen2
//
//  TTS provider protocol for abstracting synthesis engines
//

import Foundation

/// Protocol for text-to-speech synthesis engines
protocol TTSProvider {
    /// Sample rate of synthesized audio (e.g., 22050 Hz)
    var sampleRate: Int { get }

    /// Initialize the TTS provider (load models, configure session)
    func initialize() async throws

    /// Synthesize text to WAV audio data
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - speed: Playback speed (0.5-2.0, default 1.0)
    /// - Returns: WAV audio data
    func synthesize(_ text: String, speed: Float) async throws -> Data

    /// Clean up resources (unload models, release memory)
    func cleanup()
}

/// Errors that can occur during TTS operations
enum TTSError: Error, LocalizedError {
    case notInitialized
    case emptyText
    case textTooLong(maxLength: Int)
    case invalidEncoding
    case synthesisFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "TTS provider not initialized"
        case .emptyText:
            return "Cannot synthesize empty text"
        case .textTooLong(let maxLength):
            return "Text too long (max \(maxLength) characters)"
        case .invalidEncoding:
            return "Text contains invalid UTF-8 characters"
        case .synthesisFailed(let reason):
            return "Synthesis failed: \(reason)"
        }
    }
}
