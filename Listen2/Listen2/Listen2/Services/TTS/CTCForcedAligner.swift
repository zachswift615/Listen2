//
//  CTCForcedAligner.swift
//  Listen2
//
//  CTC forced alignment for word-level timestamps using MMS_FA model.
//  Uses known transcript (not ASR transcription) for accurate alignment.
//

import Foundation
import AVFoundation

/// Performs CTC forced alignment to get word timestamps from audio + known text
actor CTCForcedAligner {

    // MARK: - Types

    /// Token span from backtracking
    struct TokenSpan {
        let tokenIndex: Int
        let startFrame: Int
        let endFrame: Int
    }

    // MARK: - Properties

    /// Tokenizer for converting text to tokens
    private var tokenizer: CTCTokenizer?

    /// Whether initialized
    private(set) var isInitialized = false

    /// Expected sample rate (MMS_FA uses 16kHz)
    nonisolated let sampleRate: Int = 16000

    /// Frame hop size in samples (MMS_FA uses 320)
    private let hopSize: Int = 320

    // MARK: - Initialization

    /// Initialize with bundled model
    func initialize() async throws {
        guard let modelURL = Bundle.main.url(forResource: "mms-fa", withExtension: nil, subdirectory: "Models") else {
            // Try alternative path without Models subdirectory
            guard let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "txt", subdirectory: "mms-fa") else {
                throw AlignmentError.modelNotInitialized
            }
            try await initialize(modelDirectory: labelsURL.deletingLastPathComponent())
            return
        }
        try await initialize(modelDirectory: modelURL)
    }

    /// Initialize with custom model directory
    func initialize(modelDirectory: URL) async throws {
        let labelsURL = modelDirectory.appendingPathComponent("labels.txt")

        guard FileManager.default.fileExists(atPath: labelsURL.path) else {
            throw AlignmentError.modelNotInitialized
        }

        // Initialize tokenizer
        tokenizer = try CTCTokenizer(labelsURL: labelsURL)

        // TODO: Initialize ONNX session in Task 6

        isInitialized = true
        print("[CTCForcedAligner] Initialized with vocab size: \(tokenizer?.vocabSize ?? 0)")
    }

    /// Initialize with labels array (for testing)
    func initializeWithLabels(_ labels: [String]) async throws {
        tokenizer = CTCTokenizer(labels: labels)
        isInitialized = true
    }

    // MARK: - Public API (stubs for now)

    /// Get the tokenizer (for testing)
    func getTokenizer() -> CTCTokenizer? {
        return tokenizer
    }

    deinit {
        // Cleanup will be added when ONNX session is implemented
    }
}
