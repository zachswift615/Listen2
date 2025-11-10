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

        // Build paths to model files
        let encoderPath = (modelPath as NSString).appendingPathComponent("tiny-encoder.int8.onnx")
        let decoderPath = (modelPath as NSString).appendingPathComponent("tiny-decoder.int8.onnx")
        let tokensPath = (modelPath as NSString).appendingPathComponent("tiny-tokens.txt")

        // Verify files exist
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: encoderPath),
              fileManager.fileExists(atPath: decoderPath),
              fileManager.fileExists(atPath: tokensPath) else {
            throw AlignmentError.recognitionFailed("Model files not found at path: \(modelPath)")
        }

        // Create Whisper config
        var whisperConfig = SherpaOnnxOfflineWhisperModelConfig(
            encoder: (encoderPath as NSString).utf8String,
            decoder: (decoderPath as NSString).utf8String,
            language: ("en" as NSString).utf8String,
            task: ("transcribe" as NSString).utf8String,
            tail_paddings: 0
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
            nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(
                model: nil,
                num_threads: 0,
                debug: 0,
                provider: nil
            ),
            whisper: whisperConfig,
            tdnn: SherpaOnnxOfflineTdnnModelConfig(
                model: nil
            ),
            zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(
                model: nil
            ),
            wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(
                model: nil,
                chunk_size: 0,
                num_left_chunks: 0
            ),
            telespeech_ctc: ("" as NSString).utf8String,
            tokens: ("" as NSString).utf8String,
            num_threads: 1,
            debug: 0,  // Set to 1 for debugging
            provider: ("cpu" as NSString).utf8String,
            model_type: ("" as NSString).utf8String,
            modeling_unit: ("" as NSString).utf8String,
            bpe_vocab: ("" as NSString).utf8String,
            tokens_buf: nil,
            tokens_buf_size: 0,
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
            ctc_fst_decoder_config: SherpaOnnxOfflineCtcFstDecoderConfig(
                graph: ("" as NSString).utf8String,
                max_active: 3000
            ),
            rule_fsts: ("" as NSString).utf8String,
            rule_fars: ("" as NSString).utf8String,
            decoding_method: ("greedy_search" as NSString).utf8String,
            max_active_paths: 4,
            hotwords_score: 1.5,
            hotwords_file: ("" as NSString).utf8String,
            blank_penalty: 0.0,
            model_name: ("" as NSString).utf8String
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

        // Extract timestamps and durations
        guard let timestamps = result.timestamps,
              let tokensPtr = result.tokens else {
            throw AlignmentError.noTimestamps
        }

        let tokenCount = Int(result.count)

        // Extract token strings and timing information
        var tokenTimings: [(text: String, start: TimeInterval, duration: TimeInterval)] = []

        for i in 0..<tokenCount {
            if let tokenPtr = tokensPtr[i] {
                let tokenText = String(cString: tokenPtr)
                let startTime = TimeInterval(timestamps[i])

                // Calculate duration: either use result.durations if available,
                // or estimate from next token's start time
                var duration: TimeInterval = 0.0
                if i + 1 < tokenCount {
                    duration = TimeInterval(timestamps[i + 1]) - startTime
                } else {
                    // Last token: estimate a small duration
                    duration = 0.1
                }

                tokenTimings.append((text: tokenText, start: startTime, duration: duration))
                print("Token \(i): '\(tokenText)' at \(startTime)s, duration \(duration)s")
            }
        }

        // For now, we'll create a simple alignment result with the tokens
        // TODO: In Task 5, implement proper token-to-word mapping
        let totalDuration = tokenTimings.last?.start ?? 0.0 + (tokenTimings.last?.duration ?? 0.0)

        // Create alignment result (simplified for Task 3)
        let alignmentResult = AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: []  // TODO: Map tokens to words in Task 5
        )

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
}
