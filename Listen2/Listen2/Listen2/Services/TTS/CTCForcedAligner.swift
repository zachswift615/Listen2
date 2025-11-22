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

    // MARK: - CTC Trellis Algorithm

    /// Build CTC trellis matrix for forced alignment
    ///
    /// The trellis has states: [blank, token0, blank, token1, blank, ...]
    /// This allows the model to insert blanks between tokens (CTC property).
    ///
    /// - Parameters:
    ///   - emissions: Frame-wise log probabilities [frames x vocab]
    ///   - tokens: Target token sequence (without blanks)
    /// - Returns: Trellis matrix [frames x (2*tokens+1)]
    func buildTrellis(emissions: [[Float]], tokens: [Int]) -> [[Float]] {
        guard let tokenizer = tokenizer else { return [] }
        guard !emissions.isEmpty, !emissions[0].isEmpty else { return [] }

        let numFrames = emissions.count
        let numTokens = tokens.count
        let vocabSize = emissions[0].count

        // Handle empty token case
        guard numTokens > 0 else {
            return emissions.map { _ in [Float]() }
        }

        let numStates = 2 * numTokens + 1  // blank, token, blank, token, ..., blank
        let blankIndex = tokenizer.blankIndex

        // Initialize trellis with -infinity (log probability)
        var trellis = [[Float]](
            repeating: [Float](repeating: -.infinity, count: numStates),
            count: numFrames
        )

        // Initial probabilities (can start at first blank or first token)
        // Bounds check for emissions access
        guard blankIndex < vocabSize, tokens[0] < vocabSize else { return [] }
        trellis[0][0] = emissions[0][blankIndex]  // Start with blank
        trellis[0][1] = emissions[0][tokens[0]]   // Or start with first token

        // Fill trellis using dynamic programming
        for t in 1..<numFrames {
            for s in 0..<numStates {
                let isBlank = (s % 2 == 0)
                let tokenIdx = s / 2  // Which token this state represents

                // Get emission log probability for this state
                let emitProb: Float
                if isBlank {
                    guard blankIndex < vocabSize else { continue }
                    emitProb = emissions[t][blankIndex]
                } else if tokenIdx < tokens.count {
                    let tokenValue = tokens[tokenIdx]
                    guard tokenValue < vocabSize else { continue }
                    emitProb = emissions[t][tokenValue]
                } else {
                    continue
                }

                // Calculate max of valid transitions
                var maxPrev = trellis[t-1][s]  // Stay in current state

                if s > 0 {
                    // Can come from previous state
                    maxPrev = max(maxPrev, trellis[t-1][s-1])
                }

                // CTC allows skipping blank between different tokens
                if s > 1 && !isBlank {
                    let currentToken = tokens[tokenIdx]
                    let prevTokenIdx = (s - 2) / 2
                    if prevTokenIdx >= 0 && prevTokenIdx < tokens.count {
                        let prevToken = tokens[prevTokenIdx]
                        // Only skip if tokens are different (CTC rule)
                        if currentToken != prevToken {
                            maxPrev = max(maxPrev, trellis[t-1][s-2])
                        }
                    }
                }

                trellis[t][s] = maxPrev + emitProb
            }
        }

        return trellis
    }

    /// Backtrack through trellis to find optimal alignment path
    /// - Parameters:
    ///   - trellis: Filled trellis matrix [frames x states]
    ///   - tokens: Target token sequence
    /// - Returns: Array of token spans with frame boundaries
    func backtrack(trellis: [[Float]], tokens: [Int]) -> [TokenSpan] {
        guard !trellis.isEmpty, !tokens.isEmpty else { return [] }
        guard let firstRow = trellis.first, !firstRow.isEmpty else { return [] }

        let numFrames = trellis.count
        let numStates = trellis[0].count

        // Safety check
        guard numStates > 0 && numFrames > 0 else { return [] }

        // Find best ending state (last blank or last token)
        var currentState = numStates - 1  // Last blank
        if numStates >= 2 && trellis[numFrames - 1][numStates - 2] > trellis[numFrames - 1][numStates - 1] {
            currentState = numStates - 2  // Last token
        }

        // Backtrack to build path - store (frame, state) pairs
        var path: [(frame: Int, state: Int)] = [(numFrames - 1, currentState)]

        for t in stride(from: numFrames - 1, to: 0, by: -1) {
            // Safety: ensure we have a valid previous frame
            guard t > 0 else { break }

            // Find which state at frame t-1 led to currentState at frame t
            // Valid predecessors: same state, state-1, or state-2 (if skipping blank between different tokens)
            var bestPrevState = currentState
            var bestScore: Float = -.infinity

            // Check staying in same state (state -> state)
            if currentState < trellis[t-1].count && trellis[t-1][currentState] > bestScore {
                bestPrevState = currentState
                bestScore = trellis[t-1][currentState]
            }

            // Check coming from previous state (state-1 -> state)
            if currentState > 0 && (currentState - 1) < trellis[t-1].count && trellis[t-1][currentState - 1] > bestScore {
                bestPrevState = currentState - 1
                bestScore = trellis[t-1][currentState - 1]
            }

            // Check skipping blank (state-2 -> state) for non-blank states with different tokens
            if currentState > 1 && (currentState - 2) < trellis[t-1].count {
                let isBlank = (currentState % 2 == 0)
                if !isBlank {
                    let tokenIdx = currentState / 2
                    let prevTokenIdx = (currentState - 2) / 2
                    if tokenIdx >= 0 && tokenIdx < tokens.count && prevTokenIdx >= 0 && prevTokenIdx < tokens.count {
                        if tokens[tokenIdx] != tokens[prevTokenIdx] {
                            if trellis[t-1][currentState - 2] > bestScore {
                                bestPrevState = currentState - 2
                                bestScore = trellis[t-1][currentState - 2]
                            }
                        }
                    }
                }
            }

            currentState = bestPrevState
            path.insert((t - 1, currentState), at: 0)
        }

        // Convert path to token spans (merge consecutive frames for same token)
        var spans: [TokenSpan] = []
        var currentTokenIdx = -1
        var spanStart = 0

        for (frame, state) in path {
            let isBlank = (state % 2 == 0)
            if !isBlank {
                let tokenIdx = state / 2
                if tokenIdx != currentTokenIdx && tokenIdx < tokens.count {
                    // End previous span if exists
                    if currentTokenIdx >= 0 {
                        spans.append(TokenSpan(
                            tokenIndex: currentTokenIdx,
                            startFrame: spanStart,
                            endFrame: max(0, frame - 1)
                        ))
                    }
                    // Start new span
                    currentTokenIdx = tokenIdx
                    spanStart = frame
                }
            }
        }

        // Add final span
        if currentTokenIdx >= 0 {
            spans.append(TokenSpan(
                tokenIndex: currentTokenIdx,
                startFrame: spanStart,
                endFrame: path.last?.frame ?? spanStart
            ))
        }

        return spans
    }

    deinit {
        // Cleanup will be added when ONNX session is implemented
    }
}
