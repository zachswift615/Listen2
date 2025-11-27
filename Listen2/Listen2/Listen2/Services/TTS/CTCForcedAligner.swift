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

    /// ONNX session for MMS_FA model inference
    private var onnxSession: OpaquePointer?

    /// Whether initialized
    private(set) var isInitialized = false

    /// Expected sample rate (MMS_FA uses 16kHz)
    nonisolated let sampleRate: Int = 16000

    /// Frame hop size in samples (MMS_FA actual: 16000/49 ≈ 327)
    /// Note: This is approximate - actual frame rate is calculated dynamically from model output
    private let hopSize: Int = 327

    /// Vocabulary size for MMS_FA model
    private let vocabSize: Int = 29

    /// Model input name (MMS_FA model uses "audio")
    private let inputName = "audio"

    /// Model output name (MMS_FA model uses "emissions")
    private let outputName = "emissions"

    // MARK: - Initialization

    /// Initialize with bundled model
    func initialize() async throws {
        // Try multiple locations for the model files:
        // 1. Models/mms-fa/ subdirectory
        // 2. mms-fa/ subdirectory
        // 3. Bundle root (Xcode 16 flattens synchronized folders)

        if let modelURL = Bundle.main.url(forResource: "mms-fa", withExtension: nil, subdirectory: "Models") {
            try await initialize(modelDirectory: modelURL)
            return
        }

        if let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "txt", subdirectory: "mms-fa") {
            try await initialize(modelDirectory: labelsURL.deletingLastPathComponent())
            return
        }

        // Xcode 16 flattens files to bundle root - check there
        if let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "txt"),
           let modelURL = Bundle.main.url(forResource: "mms-fa", withExtension: "onnx") {
            // Files are at bundle root, create a virtual directory reference
            try await initializeFromBundleRoot(labelsURL: labelsURL, modelURL: modelURL)
            return
        }

        throw AlignmentError.modelNotInitialized
    }

    /// Initialize from files at bundle root (Xcode 16 synchronized folders)
    private func initializeFromBundleRoot(labelsURL: URL, modelURL: URL) async throws {
        // Initialize tokenizer
        tokenizer = try CTCTokenizer(labelsURL: labelsURL)

        // Initialize ONNX session
        let session = OnnxSessionCreate(modelURL.path, 2, 1)
        if session != nil {
            onnxSession = session
            print("[CTCForcedAligner] ONNX session created successfully (bundle root)")
        } else {
            let error = OnnxSessionGetLastError()
            let errorMsg = error != nil ? String(cString: error!) : "Unknown error"
            print("[CTCForcedAligner] Warning: Failed to create ONNX session: \(errorMsg)")
        }

        isInitialized = true
        print("[CTCForcedAligner] Initialized with vocab size: \(tokenizer?.vocabSize ?? 0)")
    }

    /// Initialize with custom model directory
    func initialize(modelDirectory: URL) async throws {
        let labelsURL = modelDirectory.appendingPathComponent("labels.txt")
        let modelURL = modelDirectory.appendingPathComponent("mms-fa.onnx")

        guard FileManager.default.fileExists(atPath: labelsURL.path) else {
            throw AlignmentError.modelNotInitialized
        }

        // Initialize tokenizer
        tokenizer = try CTCTokenizer(labelsURL: labelsURL)

        // Initialize ONNX session if model exists
        if FileManager.default.fileExists(atPath: modelURL.path) {
            let session = OnnxSessionCreate(modelURL.path, 2, 1)  // 2 threads, use CoreML
            if session != nil {
                onnxSession = session
                print("[CTCForcedAligner] ONNX session created successfully")
            } else {
                let error = OnnxSessionGetLastError()
                let errorMsg = error != nil ? String(cString: error!) : "Unknown error"
                print("[CTCForcedAligner] Warning: Failed to create ONNX session: \(errorMsg)")
                // Don't fail initialization - allow testing with mock emissions
            }
        } else {
            print("[CTCForcedAligner] Warning: Model file not found at \(modelURL.path)")
        }

        isInitialized = true
        print("[CTCForcedAligner] Initialized with vocab size: \(tokenizer?.vocabSize ?? 0)")
    }

    /// Initialize with labels array (for testing)
    func initializeWithLabels(_ labels: [String]) async throws {
        tokenizer = CTCTokenizer(labels: labels)
        isInitialized = true
    }

    // MARK: - Public API

    /// Get the tokenizer (for testing)
    func getTokenizer() -> CTCTokenizer? {
        return tokenizer
    }

    /// Whether ONNX session is available for inference
    var hasOnnxSession: Bool {
        return onnxSession != nil
    }

    // MARK: - ONNX Inference

    /// Get emission probabilities from audio samples using MMS_FA model
    ///
    /// - Parameter audioSamples: Audio samples at 16kHz, normalized to [-1, 1]
    /// - Returns: 2D array of log probabilities [frames x vocab_size]
    /// - Throws: AlignmentError if inference fails
    func getEmissions(audioSamples: [Float]) throws -> [[Float]] {
        guard let session = onnxSession else {
            throw AlignmentError.modelNotInitialized
        }

        guard !audioSamples.isEmpty else {
            throw AlignmentError.emptyAudio
        }

        // Input shape: [batch=1, samples]
        var inputShape: [Int64] = [1, Int64(audioSamples.count)]
        let inputShapeLen = inputShape.count

        // Calculate expected output size
        let numFrames = audioSamples.count / hopSize
        guard numFrames > 0 else {
            throw AlignmentError.emptyAudio
        }

        // Allocate output buffer
        let outputSize = numFrames * vocabSize
        var outputData = [Float](repeating: 0, count: outputSize)
        var outputShape: [Int64] = [0, 0, 0]  // [batch, frames, vocab]
        var outputShapeLen = outputShape.count

        // Run inference with timing
        let inferenceStart = CFAbsoluteTimeGetCurrent()
        let result = OnnxSessionRun(
            session,
            inputName,
            audioSamples,
            &inputShape,
            inputShapeLen,
            outputName,
            &outputData,
            &outputShape,
            &outputShapeLen
        )
        let inferenceElapsed = CFAbsoluteTimeGetCurrent() - inferenceStart

        if result != 0 {
            let error = OnnxSessionGetLastError()
            let errorMsg = error != nil ? String(cString: error!) : "Unknown inference error"
            print("[CTCForcedAligner] Inference failed: \(errorMsg)")
            throw AlignmentError.modelNotInitialized
        }

        // Verify output shape
        guard outputShapeLen >= 2 else {
            print("[CTCForcedAligner] Invalid output shape: \(outputShapeLen) dimensions")
            throw AlignmentError.modelNotInitialized
        }

        let actualFrames = Int(outputShape[1])
        let actualVocab = outputShapeLen > 2 ? Int(outputShape[2]) : vocabSize

        // Reshape output into 2D array [frames x vocab]
        var emissions: [[Float]] = []
        for f in 0..<actualFrames {
            let startIdx = f * actualVocab
            let endIdx = startIdx + actualVocab
            if endIdx <= outputData.count {
                let frame = Array(outputData[startIdx..<endIdx])
                emissions.append(frame)
            }
        }

        return emissions
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

    // MARK: - Full Alignment Pipeline

    /// Align audio to transcript and return word timestamps
    /// - Parameters:
    ///   - audioSamples: Audio samples as Float array
    ///   - sampleRate: Sample rate of input audio (e.g., 22050 for Piper)
    ///   - transcript: Known text that was spoken
    ///   - paragraphIndex: Index for result tracking
    ///   - sentenceStartOffset: Character offset where this sentence starts in the paragraph (for correct highlight ranges)
    /// - Returns: AlignmentResult with word timings
    func align(
        audioSamples: [Float],
        sampleRate: Int,
        transcript: String,
        paragraphIndex: Int,
        sentenceStartOffset: Int = 0
    ) async throws -> AlignmentResult {
        // Lazy initialization - load model on first use to save ~800MB at startup
        if !isInitialized {
            try await initialize()
        }

        guard let tokenizer = tokenizer else {
            throw AlignmentError.modelNotInitialized
        }

        guard !audioSamples.isEmpty else {
            throw AlignmentError.emptyAudio
        }

        // 1. Resample if needed
        let samples: [Float]
        if sampleRate != self.sampleRate {
            samples = resample(audioSamples, from: sampleRate, to: self.sampleRate)
        } else {
            samples = audioSamples
        }

        // 2. Get emissions from model (or use mock if no ONNX session)
        let emissions: [[Float]]
        if hasOnnxSession {
            emissions = try getEmissions(audioSamples: samples)
        } else {
            // Mock emissions for testing - uniform distribution
            let numFrames = max(1, samples.count / hopSize)
            let logProb = Float(-log(Float(vocabSize)))
            emissions = (0..<numFrames).map { _ in
                [Float](repeating: logProb, count: vocabSize)
            }
        }

        // 3. Tokenize transcript WITHOUT spaces
        // FIX: Exclude spaces from tokenization so backtrack produces spans only for non-space characters
        // This makes token spans align 1:1 with word characters, eliminating the space-skip bug
        let tokens = tokenizer.tokenize(transcript, includeSpaces: false)
        guard !tokens.isEmpty else {
            // No tokens = return empty result
            let totalDuration = Double(samples.count) / Double(self.sampleRate)
            return AlignmentResult(paragraphIndex: paragraphIndex, totalDuration: totalDuration, wordTimings: [])
        }

        // 4. Build trellis and backtrack
        let trellis = buildTrellis(emissions: emissions, tokens: tokens)
        let tokenSpans = backtrack(trellis: trellis, tokens: tokens)

        // 5. Merge to words (pass sentenceStartOffset for correct paragraph-relative ranges)
        // Calculate actual frame rate from model output for accurate timing
        // MMS_FA produces ~49 frames per second (20.4ms per frame)
        let actualFrameCount = emissions.count
        let audioDurationSecs = Double(samples.count) / Double(self.sampleRate)
        let frameRate = Double(actualFrameCount) / audioDurationSecs

        var wordTimings = mergeToWords(
            tokenSpans: tokenSpans,
            transcript: transcript,
            frameRate: frameRate,
            sentenceStartOffset: sentenceStartOffset
        )

        let totalDuration = Double(samples.count) / Double(self.sampleRate)

        // FALLBACK: If alignment failed (empty tokenSpans), create uniform word timings
        // This ensures highlighting still works, even if timing is approximate
        if wordTimings.isEmpty {
            print("[CTCForcedAligner] ⚠️ Backtrack returned empty - using uniform word distribution")
            wordTimings = createUniformWordTimings(
                transcript: transcript,
                totalDuration: totalDuration,
                paragraphIndex: paragraphIndex,
                sentenceStartOffset: sentenceStartOffset
            )
        }

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )
    }

    // MARK: - Audio Resampling

    /// Resample audio to target sample rate using linear interpolation
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sourceRate: Source sample rate (e.g., 22050)
    ///   - targetRate: Target sample rate (e.g., 16000)
    /// - Returns: Resampled audio samples
    private func resample(_ samples: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
        guard sourceRate != targetRate, sourceRate > 0, targetRate > 0 else {
            return samples
        }

        let ratio = Double(sourceRate) / Double(targetRate)
        let newLength = Int(Double(samples.count) / ratio)

        return (0..<newLength).map { i in
            let srcIdx = Double(i) * ratio
            let srcIdxInt = Int(srcIdx)
            let frac = Float(srcIdx - Double(srcIdxInt))

            if srcIdxInt + 1 < samples.count {
                return samples[srcIdxInt] * (1 - frac) + samples[srcIdxInt + 1] * frac
            } else {
                return samples[min(srcIdxInt, samples.count - 1)]
            }
        }
    }

    // MARK: - Fallback Word Timing

    /// Create uniform word timings when CTC alignment fails
    /// Distributes total duration evenly across words
    private func createUniformWordTimings(
        transcript: String,
        totalDuration: TimeInterval,
        paragraphIndex: Int,
        sentenceStartOffset: Int
    ) -> [AlignmentResult.WordTiming] {
        // Split transcript into words
        let words = transcript.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return [] }

        let wordCount = words.count
        let durationPerWord = totalDuration / Double(wordCount)

        var timings: [AlignmentResult.WordTiming] = []
        var currentOffset = 0

        for (index, word) in words.enumerated() {
            let wordText = String(word)
            // Find actual position in transcript (accounting for spaces)
            if let range = transcript.range(of: wordText, range: transcript.index(transcript.startIndex, offsetBy: currentOffset)..<transcript.endIndex) {
                let rangeLocation = transcript.distance(from: transcript.startIndex, to: range.lowerBound)

                timings.append(AlignmentResult.WordTiming(
                    wordIndex: index,
                    startTime: Double(index) * durationPerWord,
                    duration: durationPerWord,
                    text: wordText,
                    rangeLocation: rangeLocation + sentenceStartOffset,
                    rangeLength: wordText.count
                ))

                currentOffset = transcript.distance(from: transcript.startIndex, to: range.upperBound)
            }
        }

        print("[CTCForcedAligner] 📊 Created \(timings.count) uniform word timings (\(String(format: "%.3f", durationPerWord))s each)")
        return timings
    }

    // MARK: - Word Merging

    /// Merge character-level token spans into word-level timings
    ///
    /// The key insight is that token spans are ordered by position in the tokenized text
    /// (which has unknown chars stripped and spaces converted to space tokens).
    /// We need to:
    /// 1. Split transcript into words with their character positions
    /// 2. Count how many tokens each word contributes (using tokenizer)
    /// 3. Map token spans to words based on token count, skipping space tokens
    ///
    /// - Parameters:
    ///   - tokenSpans: Character spans from backtracking (ordered by token index)
    ///   - transcript: Original text (may contain chars not in vocabulary)
    ///   - frameRate: Frames per second for time conversion
    ///   - sentenceStartOffset: Character offset where this sentence starts in the paragraph
    /// - Returns: Word-level timing information with paragraph-relative ranges
    func mergeToWords(
        tokenSpans: [TokenSpan],
        transcript: String,
        frameRate: Double,
        sentenceStartOffset: Int = 0
    ) -> [AlignmentResult.WordTiming] {
        guard let tokenizer = tokenizer else { return [] }
        guard !tokenSpans.isEmpty else { return [] }

        // 1. Split transcript into words with their character positions
        var words: [(text: String, startOffset: Int, endOffset: Int)] = []
        var currentWord = ""
        var wordStart = 0

        for (i, char) in transcript.enumerated() {
            if char == " " {
                if !currentWord.isEmpty {
                    words.append((text: currentWord, startOffset: wordStart, endOffset: i - 1))
                    currentWord = ""
                }
                wordStart = i + 1
            } else {
                if currentWord.isEmpty {
                    wordStart = i
                }
                currentWord.append(char)
            }
        }
        if !currentWord.isEmpty {
            words.append((text: currentWord, startOffset: wordStart, endOffset: transcript.count - 1))
        }

        guard !words.isEmpty else { return [] }

        // 2. Count tokens per word (using tokenizer - this excludes space tokens)
        var tokenCountPerWord: [Int] = []
        for word in words {
            let wordTokens = tokenizer.tokenize(word.text)
            tokenCountPerWord.append(wordTokens.count)
        }

        // 3. Map token spans to words, skipping space token spans
        var wordTimings: [AlignmentResult.WordTiming] = []
        var spanIndex = 0

        for (wordIdx, word) in words.enumerated() {
            let tokenCount = tokenCountPerWord[wordIdx]
            guard tokenCount > 0, spanIndex < tokenSpans.count else { continue }

            // Collect spans for this word (exactly tokenCount spans)
            var wordSpans: [TokenSpan] = []
            var collected = 0
            while collected < tokenCount && spanIndex < tokenSpans.count {
                wordSpans.append(tokenSpans[spanIndex])
                spanIndex += 1
                collected += 1
            }

            if let firstSpan = wordSpans.first, let lastSpan = wordSpans.last {
                let startTime = Double(firstSpan.startFrame) / frameRate
                // +1 because endFrame is inclusive (frame N ends at time (N+1)/frameRate)
                let endTime = Double(lastSpan.endFrame + 1) / frameRate

                // FIX: Add sentenceStartOffset to get paragraph-relative position
                wordTimings.append(AlignmentResult.WordTiming(
                    wordIndex: wordIdx,
                    startTime: startTime,
                    duration: endTime - startTime,
                    text: word.text,
                    rangeLocation: word.startOffset + sentenceStartOffset,  // Paragraph-relative!
                    rangeLength: word.text.count
                ))
            }

            // NOTE: Space skipping logic removed - we now tokenize WITHOUT spaces
            // so token spans directly map to word characters without any gaps
        }

        return wordTimings
    }

    deinit {
        // Clean up ONNX session
        if let session = onnxSession {
            OnnxSessionDestroy(session)
        }
    }
}
