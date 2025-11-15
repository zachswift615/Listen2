//
//  WordAlignmentService.swift
//  Listen2
//
//  Service for aligning synthesized audio to text using ASR (sherpa-onnx)
//

import Foundation
import AVFoundation

/// Service for word-level alignment of audio to text using sherpa-onnx ASR
actor WordAlignmentService {
    // MARK: - Properties

    /// The sherpa-onnx offline recognizer
    private var recognizer: OpaquePointer?

    /// Whether the service has been initialized
    private var isInitialized: Bool = false

    /// Cache of alignments by audio URL
    private var alignmentCache: [URL: AlignmentResult] = [:]

    // MARK: - Initialization

    /// Initialize the ASR recognizer with model files
    /// - Parameter modelPath: Path to the directory containing ASR model files
    /// - Throws: AlignmentError if initialization fails
    func initialize(modelPath: String) async throws {
        guard !isInitialized else {
            print("WordAlignmentService already initialized")
            return
        }

        // Build paths to model files (they're at the root of modelPath)
        let modelFilePath = (modelPath as NSString).appendingPathComponent("nemo-ctc-model.int8.onnx")
        let tokensPath = (modelPath as NSString).appendingPathComponent("nemo-ctc-tokens.txt")

        // Verify files exist
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelFilePath),
              fileManager.fileExists(atPath: tokensPath) else {
            throw AlignmentError.recognitionFailed("Model files not found at path: \(modelPath)")
        }

        // Create NeMo CTC config
        var nemoConfig = SherpaOnnxOfflineNemoEncDecCtcModelConfig(
            model: (modelFilePath as NSString).utf8String
        )

        // Create model config
        var modelConfig = SherpaOnnxOfflineModelConfig(
            transducer: SherpaOnnxOfflineTransducerModelConfig(
                encoder: nil,
                decoder: nil,
                joiner: nil
            ),
            paraformer: SherpaOnnxOfflineParaformerModelConfig(
                model: nil
            ),
            nemo_ctc: nemoConfig,
            whisper: SherpaOnnxOfflineWhisperModelConfig(
                encoder: nil,
                decoder: nil,
                language: nil,
                task: nil,
                tail_paddings: 0
            ),
            tdnn: SherpaOnnxOfflineTdnnModelConfig(
                model: nil
            ),
            tokens: (tokensPath as NSString).utf8String,
            num_threads: 1,
            debug: 0,  // Set to 1 for debugging
            provider: ("cpu" as NSString).utf8String,
            model_type: ("" as NSString).utf8String,
            modeling_unit: ("" as NSString).utf8String,
            bpe_vocab: ("" as NSString).utf8String,
            telespeech_ctc: ("" as NSString).utf8String,
            sense_voice: SherpaOnnxOfflineSenseVoiceModelConfig(
                model: nil,
                language: nil,
                use_itn: 0
            ),
            moonshine: SherpaOnnxOfflineMoonshineModelConfig(
                preprocessor: nil,
                encoder: nil,
                uncached_decoder: nil,
                cached_decoder: nil
            ),
            fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(
                encoder: nil,
                decoder: nil
            ),
            dolphin: SherpaOnnxOfflineDolphinModelConfig(
                model: nil
            ),
            zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(
                model: nil
            ),
            canary: SherpaOnnxOfflineCanaryModelConfig(
                encoder: nil,
                decoder: nil,
                src_lang: nil,
                tgt_lang: nil,
                use_pnc: 0
            ),
            wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(
                model: nil
            )
        )

        // Create recognizer config
        var recognizerConfig = SherpaOnnxOfflineRecognizerConfig(
            feat_config: SherpaOnnxFeatureConfig(
                sample_rate: 16000,
                feature_dim: 80
            ),
            model_config: modelConfig,
            lm_config: SherpaOnnxOfflineLMConfig(
                model: ("" as NSString).utf8String,
                scale: 0.5
            ),
            decoding_method: ("greedy_search" as NSString).utf8String,
            max_active_paths: 4,
            hotwords_file: ("" as NSString).utf8String,
            hotwords_score: 1.5,
            rule_fsts: ("" as NSString).utf8String,
            rule_fars: ("" as NSString).utf8String,
            blank_penalty: 0.0,
            hr: SherpaOnnxHomophoneReplacerConfig(
                dict_dir: nil,
                lexicon: nil,
                rule_fsts: nil
            )
        )

        // Create recognizer
        recognizer = SherpaOnnxCreateOfflineRecognizer(&recognizerConfig)

        guard recognizer != nil else {
            throw AlignmentError.recognitionFailed("Failed to create ASR recognizer")
        }

        isInitialized = true
        print("WordAlignmentService initialized successfully")
    }

    /// Deinitialize and clean up resources
    func deinitialize() {
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
            self.recognizer = nil
        }
        isInitialized = false
        alignmentCache.removeAll()
    }

    deinit {
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
    }

    // MARK: - Alignment

    /// Align audio to text and return word timestamps
    /// - Parameters:
    ///   - audioURL: URL to the audio file (WAV format)
    ///   - text: The text that was synthesized
    ///   - wordMap: Document word map containing word positions
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with word timings
    /// - Throws: AlignmentError if alignment fails
    func align(
        audioURL: URL,
        text: String,
        wordMap: DocumentWordMap,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {
        // Check if initialized
        guard isInitialized, let recognizer = recognizer else {
            throw AlignmentError.modelNotInitialized
        }

        // Check cache first
        if let cached = alignmentCache[audioURL] {
            print("Using cached alignment for \(audioURL.lastPathComponent)")
            return cached
        }

        print("Aligning audio: \(audioURL.lastPathComponent)")

        // Load and convert audio
        let (samples, sampleRate) = try await loadAudioSamples(from: audioURL)

        print("Loaded \(samples.count) samples at \(sampleRate) Hz")

        // Create offline stream
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            throw AlignmentError.recognitionFailed("Failed to create offline stream")
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        // Feed audio samples to the stream
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), baseAddress, Int32(samples.count))
        }

        // Decode the audio
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        // Get result with timestamps
        guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw AlignmentError.recognitionFailed("Failed to get recognition result")
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(resultPtr) }

        let result = resultPtr.pointee

        // Extract transcribed text
        let transcribedText = String(cString: result.text)
        print("Transcribed text: '\(transcribedText)'")
        print("Token count: \(result.count)")

        let tokenCount = Int(result.count)
        guard tokenCount > 0 else {
            throw AlignmentError.recognitionFailed("No tokens recognized")
        }

        // Extract timestamps - NeMo CTC provides them
        guard let timestamps = result.timestamps else {
            throw AlignmentError.noTimestamps
        }

        print("✅ Got \(tokenCount) tokens with timestamps from NeMo CTC model")

        // Get VoxPDF words for this paragraph
        let voxPDFWords = wordMap.words(for: paragraphIndex)

        // Map tokens to words using DTW alignment
        let wordTimings = mapTokensToWords(
            asrTokens: result.tokens_arr,
            timestamps: timestamps,
            durations: result.durations,
            tokenCount: tokenCount,
            voxPDFWords: voxPDFWords,
            paragraphText: text
        )

        // Calculate total duration from last word or estimate from audio
        let audioDuration = TimeInterval(samples.count) / TimeInterval(sampleRate)
        let totalDuration = wordTimings.last?.endTime ?? audioDuration

        // Create alignment result
        let alignmentResult = AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )

        print("Created alignment with \(wordTimings.count) word timings, total duration: \(totalDuration)s")

        // Cache the result
        alignmentCache[audioURL] = alignmentResult

        return alignmentResult
    }

    /// Get cached alignment for an audio file
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Cached alignment result, or nil if not cached
    func getCachedAlignment(for audioURL: URL) -> AlignmentResult? {
        return alignmentCache[audioURL]
    }

    /// Clear the alignment cache
    func clearCache() {
        alignmentCache.removeAll()
    }

    // MARK: - Audio Processing

    /// Load audio samples from a WAV file
    /// - Parameter url: URL to the WAV file
    /// - Returns: Tuple of (samples as Float array, sample rate)
    /// - Throws: AlignmentError if loading or conversion fails
    private func loadAudioSamples(from url: URL) async throws -> ([Float], Int) {
        guard url.pathExtension.lowercased() == "wav" else {
            throw AlignmentError.invalidAudioFormat
        }

        // Load audio file using AVAudioFile
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AlignmentError.audioLoadFailed("Failed to open audio file: \(error.localizedDescription)")
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AlignmentError.audioConversionFailed("Failed to create audio buffer")
        }

        do {
            try file.read(into: buffer)
        } catch {
            throw AlignmentError.audioLoadFailed("Failed to read audio data: \(error.localizedDescription)")
        }

        // Convert to mono if needed
        guard let channelData = buffer.floatChannelData else {
            throw AlignmentError.audioConversionFailed("No channel data in audio buffer")
        }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)

        // Extract mono samples (mix down if stereo)
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(frameLength)

        if channelCount == 1 {
            // Already mono
            let channel = channelData[0]
            for i in 0..<frameLength {
                monoSamples.append(channel[i])
            }
        } else {
            // Mix down to mono by averaging channels
            for i in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][i]
                }
                monoSamples.append(sum / Float(channelCount))
            }
        }

        // Resample to 16kHz if needed
        let originalSampleRate = Int(format.sampleRate)
        if originalSampleRate != 16000 {
            print("Resampling from \(originalSampleRate) Hz to 16000 Hz")
            monoSamples = try resample(monoSamples, from: originalSampleRate, to: 16000)
            return (monoSamples, 16000)
        }

        return (monoSamples, originalSampleRate)
    }

    /// Resample audio to target sample rate using linear interpolation
    /// - Parameters:
    ///   - samples: Input samples
    ///   - fromRate: Original sample rate
    ///   - toRate: Target sample rate
    /// - Returns: Resampled audio
    private func resample(_ samples: [Float], from fromRate: Int, to toRate: Int) throws -> [Float] {
        guard fromRate > 0 && toRate > 0 else {
            throw AlignmentError.audioConversionFailed("Invalid sample rates")
        }

        if fromRate == toRate {
            return samples
        }

        let ratio = Double(fromRate) / Double(toRate)
        let newLength = Int(Double(samples.count) / ratio)
        var resampled: [Float] = []
        resampled.reserveCapacity(newLength)

        for i in 0..<newLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                // Linear interpolation
                let sample1 = samples[srcIndexInt]
                let sample2 = samples[srcIndexInt + 1]
                resampled.append(sample1 + (sample2 - sample1) * fraction)
            } else if srcIndexInt < samples.count {
                resampled.append(samples[srcIndexInt])
            }
        }

        return resampled
    }

    // MARK: - Token-to-Word Mapping

    /// Find a word in paragraph text near an expected offset (for correcting VoxPDF errors)
    /// - Parameters:
    ///   - word: The word to find
    ///   - nearOffset: Expected offset to search near
    ///   - paragraphText: The full paragraph text
    /// - Returns: String range of the word, or nil if not found
    private func findWordInParagraph(
        word: String,
        nearOffset: Int,
        in paragraphText: String
    ) -> Range<String.Index>? {
        let normalizedWord = normalize(word)
        let searchRadius = 100 // Search within 100 characters of expected position

        // Calculate search range
        let searchStart = max(0, nearOffset - searchRadius)
        let searchEnd = min(paragraphText.count, nearOffset + searchRadius)

        guard let searchStartIndex = paragraphText.index(
            paragraphText.startIndex,
            offsetBy: searchStart,
            limitedBy: paragraphText.endIndex
        ),
        let searchEndIndex = paragraphText.index(
            paragraphText.startIndex,
            offsetBy: searchEnd,
            limitedBy: paragraphText.endIndex
        ) else {
            return nil
        }

        let searchText = String(paragraphText[searchStartIndex..<searchEndIndex])

        // Try to find the word in the search area
        // We'll look for word boundaries to get exact matches
        let words = searchText.components(separatedBy: .whitespaces)
        var currentOffset = searchStart

        for searchWord in words {
            let normalizedSearchWord = normalize(searchWord)

            if normalizedSearchWord == normalizedWord {
                // Found it! Calculate the exact range
                if let wordStartIndex = paragraphText.index(
                    paragraphText.startIndex,
                    offsetBy: currentOffset,
                    limitedBy: paragraphText.endIndex
                ),
                let wordEndIndex = paragraphText.index(
                    wordStartIndex,
                    offsetBy: searchWord.count,
                    limitedBy: paragraphText.endIndex
                ) {
                    return wordStartIndex..<wordEndIndex
                }
            }

            currentOffset += searchWord.count + 1 // +1 for space
        }

        return nil
    }

    /// Normalize text for alignment (lowercase, remove punctuation)
    /// - Parameter text: Input text
    /// - Returns: Normalized text suitable for alignment
    private func normalize(_ text: String) -> String {
        // Convert to lowercase
        var normalized = text.lowercased()

        // Remove ALL punctuation including apostrophes for better alignment
        // This handles cases where ASR tokenizes "author's" as "authors" or splits it differently
        // We'll use the original VoxPDF word positions (with apostrophes) for the final character ranges
        normalized = normalized.components(separatedBy: .punctuationCharacters).joined()

        // Remove extra whitespace
        normalized = normalized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized
    }

    /// Compute Levenshtein (edit) distance between two strings
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: Edit distance (lower is more similar)
    private func editDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        // Handle empty strings (can happen when normalizing punctuation-only words)
        if m == 0 { return n }
        if n == 0 { return m }

        // Create DP table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize base cases
        for i in 0...m {
            dp[i][0] = i
        }
        for j in 0...n {
            dp[0][j] = j
        }

        // Fill DP table
        for i in 1...m {
            for j in 1...n {
                if s1Array[i-1] == s2Array[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(
                        dp[i-1][j],     // deletion
                        dp[i][j-1],     // insertion
                        dp[i-1][j-1]    // substitution
                    )
                }
            }
        }

        return dp[m][n]
    }

    /// Align ASR token sequence to VoxPDF word sequence using Dynamic Time Warping
    /// - Parameters:
    ///   - asrTokens: Array of ASR token strings
    ///   - voxWords: Array of VoxPDF word strings
    /// - Returns: Array of (wordIndex, [tokenIndices]) pairs showing alignment
    private func alignSequences(_ asrTokens: [String], _ voxWords: [String]) -> [(wordIndex: Int, tokenIndices: [Int])] {
        guard !asrTokens.isEmpty && !voxWords.isEmpty else {
            return []
        }

        let m = asrTokens.count
        let n = voxWords.count

        // Memoization cache for edit distance calculations
        // Key: "token|word", Value: edit distance
        var editDistanceCache: [String: Int] = [:]

        // Helper function to get cached edit distance
        func getCachedEditDistance(_ s1: String, _ s2: String) -> Int {
            let cacheKey = "\(s1)|\(s2)"
            if let cached = editDistanceCache[cacheKey] {
                return cached
            }
            let distance = editDistance(s1, s2)
            editDistanceCache[cacheKey] = distance
            return distance
        }

        // DTW cost matrix
        var cost = Array(repeating: Array(repeating: Double.infinity, count: n + 1), count: m + 1)
        cost[0][0] = 0

        // Compute DTW costs with memoized edit distance
        for i in 1...m {
            for j in 1...n {
                // Cost of matching token i-1 to word j-1 (memoized)
                let matchCost = Double(getCachedEditDistance(asrTokens[i-1], voxWords[j-1]))

                // DTW allows staying on same word (many tokens -> one word)
                // or skipping words (one token -> many words, less common)
                cost[i][j] = matchCost + min(
                    cost[i-1][j-1],  // diagonal: align token to word
                    cost[i-1][j],    // vertical: multiple tokens per word
                    cost[i][j-1]     // horizontal: skip word (less common)
                )
            }
        }

        // Backtrack to find alignment path
        var alignment: [(wordIndex: Int, tokenIndices: [Int])] = []
        var i = m
        var j = n
        var currentWord: (wordIndex: Int, tokenIndices: [Int])?

        while i > 0 && j > 0 {
            // Determine which direction we came from
            let diag = cost[i-1][j-1]
            let up = cost[i-1][j]
            let left = cost[i][j-1]

            if diag <= up && diag <= left {
                // Diagonal: token i-1 aligns to word j-1
                if let current = currentWord, current.wordIndex == j-1 {
                    // Same word, prepend token
                    currentWord?.tokenIndices.insert(i-1, at: 0)
                } else {
                    // New word, save previous
                    if let current = currentWord {
                        alignment.insert(current, at: 0)
                    }
                    currentWord = (wordIndex: j-1, tokenIndices: [i-1])
                }
                i -= 1
                j -= 1
            } else if up <= left {
                // Vertical: multiple tokens for same word
                currentWord?.tokenIndices.insert(i-1, at: 0)
                i -= 1
            } else {
                // Horizontal: skip word j-1 (no tokens align to it)
                j -= 1
            }
        }

        // Handle remaining tokens/words
        if i > 0 || j > 0 {
            print("⚠️ [Alignment] Incomplete alignment: \(i) tokens, \(j) words remaining")
        }

        // Add last word
        if let current = currentWord {
            alignment.insert(current, at: 0)
        }

        return alignment
    }

    /// Map ASR tokens to VoxPDF words and create WordTiming array
    /// - Parameters:
    ///   - asrTokens: ASR token pointer array
    ///   - timestamps: Start time for each token
    ///   - durations: Duration of each token
    ///   - tokenCount: Number of tokens
    ///   - voxPDFWords: Array of VoxPDF word positions
    ///   - paragraphText: Full text of the paragraph
    /// - Returns: Array of WordTiming entries
    private func mapTokensToWords(
        asrTokens: UnsafePointer<UnsafePointer<CChar>?>,
        timestamps: UnsafePointer<Float>,
        durations: UnsafePointer<Float>?,
        tokenCount: Int,
        voxPDFWords: [WordPosition],
        paragraphText: String
    ) -> [AlignmentResult.WordTiming] {
        guard tokenCount > 0 && !voxPDFWords.isEmpty else {
            return []
        }

        // 1. Convert ASR tokens to strings
        var asrTokenStrings: [String] = []
        var originalIndices: [Int] = []  // NEW: Track original indices
        for i in 0..<tokenCount {
            if let tokenPtr = asrTokens[i] {
                let tokenText = String(cString: tokenPtr)
                // Filter out whitespace-only tokens
                if !tokenText.trimmingCharacters(in: .whitespaces).isEmpty {
                    asrTokenStrings.append(tokenText)
                    originalIndices.append(i)  // Store original index
                }
            }
        }

        print("🔤 ASR tokens (\(asrTokenStrings.count)): \(asrTokenStrings)")

        // Log tokens with apostrophes specifically
        let tokensWithApostrophes = asrTokenStrings.enumerated().filter { $0.element.contains("'") || $0.element.contains("'") }
        if !tokensWithApostrophes.isEmpty {
            print("⚠️  ASR tokens with apostrophes: \(tokensWithApostrophes.map { "[\($0.offset)]: '\($0.element)'" })")
        }

        // 2. Extract VoxPDF word texts and normalize both
        let voxWordStrings = voxPDFWords.map { $0.text }
        print("📚 VoxPDF words (\(voxWordStrings.count)): \(voxWordStrings)")

        // Log VoxPDF words with apostrophes and their offsets
        let voxWordsWithApostrophes = voxPDFWords.enumerated().filter {
            $0.element.text.contains("'") || $0.element.text.contains("'")
        }
        if !voxWordsWithApostrophes.isEmpty {
            print("⚠️  VoxPDF words with apostrophes:")
            for (idx, word) in voxWordsWithApostrophes {
                print("   [\(idx)]: '\(word.text)' offset=\(word.characterOffset) length=\(word.length)")
            }
        }

        let normalizedASR = asrTokenStrings.map { normalize($0) }
        let normalizedWords = voxWordStrings.map { normalize($0) }

        print("🔧 Normalized ASR: \(normalizedASR)")
        print("🔧 Normalized VoxPDF: \(normalizedWords)")

        // Filter out empty normalized strings (punctuation-only words)
        // Keep track of original indices for mapping back
        var filteredASR: [String] = []
        var filteredASRIndices: [Int] = []
        for (idx, normalized) in normalizedASR.enumerated() {
            if !normalized.isEmpty {
                filteredASR.append(normalized)
                filteredASRIndices.append(idx)
            } else {
                print("⚠️  Skipping empty ASR token at index \(idx): '\(asrTokenStrings[idx])'")
            }
        }

        var filteredWords: [String] = []
        var filteredWordIndices: [Int] = []
        for (idx, normalized) in normalizedWords.enumerated() {
            if !normalized.isEmpty {
                filteredWords.append(normalized)
                filteredWordIndices.append(idx)
            } else {
                print("⚠️  Skipping empty VoxPDF word at index \(idx): '\(voxWordStrings[idx])'")
            }
        }

        // 3. Align sequences using DTW (with filtered, non-empty strings)
        let filteredAlignment = alignSequences(filteredASR, filteredWords)

        // Map filtered indices back to original indices
        var alignment: [(wordIndex: Int, tokenIndices: [Int])] = []
        for (filteredWordIdx, filteredTokenIdxs) in filteredAlignment {
            let originalWordIdx = filteredWordIndices[filteredWordIdx]
            let originalTokenIdxs = filteredTokenIdxs.map { filteredASRIndices[$0] }
            alignment.append((wordIndex: originalWordIdx, tokenIndices: originalTokenIdxs))
        }

        print("🔗 DTW Alignment (\(alignment.count) words mapped):")
        for (wordIdx, tokenIdxs) in alignment.prefix(10) {
            let word = wordIdx < voxWordStrings.count ? voxWordStrings[wordIdx] : "???"
            let tokens = tokenIdxs.compactMap { $0 < asrTokenStrings.count ? asrTokenStrings[$0] : nil }
            print("   Word[\(wordIdx)] '\(word)' ← Tokens\(tokenIdxs): \(tokens)")
        }
        if alignment.count > 10 {
            print("   ... (\(alignment.count - 10) more)")
        }

        // 4. Build WordTiming array
        var wordTimings: [AlignmentResult.WordTiming] = []

        for (wordIndex, tokenIndices) in alignment {
            guard wordIndex < voxPDFWords.count else { continue }

            let voxWord = voxPDFWords[wordIndex]

            // Calculate timing from aligned tokens
            guard !tokenIndices.isEmpty else { continue }

            let firstToken = tokenIndices.first!
            let lastToken = tokenIndices.last!

            // Use original indices to access timestamps
            let originalFirstToken = originalIndices[firstToken]
            let originalLastToken = originalIndices[lastToken]

            let startTime = TimeInterval(timestamps[originalFirstToken])

            // Calculate end time
            var endTime: TimeInterval
            if let durations = durations {
                endTime = TimeInterval(timestamps[originalLastToken] + durations[originalLastToken])
            } else {
                // Estimate from next token's start time
                if originalLastToken + 1 < tokenCount {
                    endTime = TimeInterval(timestamps[originalLastToken + 1])
                } else {
                    // Last token: add a small duration
                    endTime = startTime + 0.2
                }
            }

            let duration = endTime - startTime

            // Get String.Index range from VoxPDF word position
            guard let startIndex = paragraphText.index(
                paragraphText.startIndex,
                offsetBy: voxWord.characterOffset,
                limitedBy: paragraphText.endIndex
            ) else {
                print("⚠️  Invalid character offset \(voxWord.characterOffset) for word '\(voxWord.text)'")
                continue
            }

            guard let endIndex = paragraphText.index(
                startIndex,
                offsetBy: voxWord.length,
                limitedBy: paragraphText.endIndex
            ) else {
                print("⚠️  Invalid length \(voxWord.length) for word '\(voxWord.text)'")
                continue
            }

            let stringRange = startIndex..<endIndex

            // CRITICAL VALIDATION: Check if extracted text matches expected word
            let extractedText = String(paragraphText[stringRange])
            let normalizedExtracted = normalize(extractedText)
            let normalizedExpected = normalize(voxWord.text)

            if normalizedExtracted != normalizedExpected {
                // VoxPDF word position is WRONG! This is the bug!
                print("❌ VoxPDF POSITION ERROR:")
                print("   Expected word: '\(voxWord.text)' (normalized: '\(normalizedExpected)')")
                print("   But extracted: '\(extractedText)' (normalized: '\(normalizedExtracted)')")
                print("   At offset=\(voxWord.characterOffset), length=\(voxWord.length)")
                print("   This will cause all subsequent words to have wrong positions!")

                // Try to find the correct position by searching nearby
                if let correctedRange = findWordInParagraph(
                    word: voxWord.text,
                    nearOffset: voxWord.characterOffset,
                    in: paragraphText
                ) {
                    print("   ✅ CORRECTED: Found word at corrected position")
                    // Use corrected range instead
                    let rangeLocation = paragraphText.distance(from: paragraphText.startIndex, to: correctedRange.lowerBound)
                    let rangeLength = paragraphText.distance(from: correctedRange.lowerBound, to: correctedRange.upperBound)

                    wordTimings.append(AlignmentResult.WordTiming(
                        wordIndex: wordIndex,
                        startTime: startTime,
                        duration: duration,
                        text: voxWord.text,
                        rangeLocation: rangeLocation,
                        rangeLength: rangeLength
                    ))
                    continue
                } else {
                    print("   ❌ Could not find correct position, skipping word")
                    continue
                }
            }

            // Debug log for words with apostrophes
            if voxWord.text.contains("'") || voxWord.text.contains("'") {
                let extractedText = String(paragraphText[stringRange])
                print("   ⚠️  APOSTROPHE WORD: '\(voxWord.text)' @ offset=\(voxWord.characterOffset), length=\(voxWord.length)")
                print("       Range: \(stringRange), Extracted: '\(extractedText)'")
                print("       Time: \(startTime)s - \(endTime)s (duration: \(duration)s)")
                print("       Tokens: \(tokenIndices)")
            }

            let rangeLocation = paragraphText.distance(from: paragraphText.startIndex, to: stringRange.lowerBound)
            let rangeLength = paragraphText.distance(from: stringRange.lowerBound, to: stringRange.upperBound)

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: wordIndex,
                startTime: startTime,
                duration: duration,
                text: voxWord.text,
                rangeLocation: rangeLocation,
                rangeLength: rangeLength
            ))
        }

        print("✅ Created \(wordTimings.count) word timings")
        return wordTimings
    }
}
