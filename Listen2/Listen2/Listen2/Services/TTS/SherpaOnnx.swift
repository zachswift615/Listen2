//
//  SherpaOnnx.swift
//  Listen2
//
//  Swift wrapper for sherpa-onnx C API (offline TTS)
//

import Foundation

// MARK: - Phoneme Info

/// Information about a single phoneme with its position in the original text
struct PhonemeInfo: Equatable {
    /// IPA phoneme symbol (e.g., "h", "ə", "l", "oʊ")
    let symbol: String

    /// Duration of this phoneme in seconds
    let duration: TimeInterval

    /// Character range in the original text that this phoneme represents
    /// Example: "ough" in "thought" might be represented by character range 2..<6
    let textRange: Range<Int>

    init(symbol: String, duration: TimeInterval, textRange: Range<Int>) {
        self.symbol = symbol
        self.duration = duration
        self.textRange = textRange
    }
}

// MARK: - Helper Functions for Config Creation

/// Create a VITS model configuration
/// - Parameters:
///   - model: Path to the VITS model file (.onnx)
///   - lexicon: Path to lexicon file (empty string if not used)
///   - tokens: Path to tokens file
///   - dataDir: Path to espeak-ng-data directory
/// - Returns: Configured SherpaOnnxOfflineTtsVitsModelConfig
func sherpaOnnxOfflineTtsVitsModelConfig(
    model: String,
    lexicon: String,
    tokens: String,
    dataDir: String
) -> SherpaOnnxOfflineTtsVitsModelConfig {
    return SherpaOnnxOfflineTtsVitsModelConfig(
        model: (model as NSString).utf8String,
        lexicon: (lexicon as NSString).utf8String,
        tokens: (tokens as NSString).utf8String,
        data_dir: (dataDir as NSString).utf8String,
        noise_scale: 0.667,
        noise_scale_w: 0.8,
        length_scale: 1.0,
        dict_dir: nil
    )
}

/// Create an offline TTS model configuration
/// - Parameter vits: VITS model configuration
/// - Returns: Configured SherpaOnnxOfflineTtsModelConfig
func sherpaOnnxOfflineTtsModelConfig(
    vits: SherpaOnnxOfflineTtsVitsModelConfig
) -> SherpaOnnxOfflineTtsModelConfig {
    return SherpaOnnxOfflineTtsModelConfig(
        vits: vits,
        num_threads: 1,
        debug: 0,
        provider: ("cpu" as NSString).utf8String,
        matcha: SherpaOnnxOfflineTtsMatchaModelConfig(
            acoustic_model: nil,
            vocoder: nil,
            lexicon: nil,
            tokens: nil,
            data_dir: nil,
            noise_scale: 0.667,
            length_scale: 1.0,
            dict_dir: nil
        ),
        kokoro: SherpaOnnxOfflineTtsKokoroModelConfig(
            model: nil,
            voices: nil,
            tokens: nil,
            data_dir: nil,
            length_scale: 1.0,
            dict_dir: nil,
            lexicon: nil,
            lang: nil
        ),
        kitten: SherpaOnnxOfflineTtsKittenModelConfig(
            model: nil,
            voices: nil,
            tokens: nil,
            data_dir: nil,
            length_scale: 1.0
        ),
        zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig(
            tokens: nil,
            text_model: nil,
            flow_matching_model: nil,
            vocoder: nil,
            data_dir: nil,
            pinyin_dict: nil,
            feat_scale: 1.0,
            t_shift: 0.0,
            target_rms: 0.1,
            guidance_scale: 3.0
        )
    )
}

/// Create an offline TTS configuration
/// - Parameter model: Model configuration
/// - Returns: Configured SherpaOnnxOfflineTtsConfig
func sherpaOnnxOfflineTtsConfig(
    model: SherpaOnnxOfflineTtsModelConfig
) -> SherpaOnnxOfflineTtsConfig {
    return SherpaOnnxOfflineTtsConfig(
        model: model,
        rule_fsts: ("" as NSString).utf8String,
        max_num_sentences: 1,
        rule_fars: ("" as NSString).utf8String,
        silence_scale: 1.0
    )
}

// MARK: - Generated Audio Result

/// Wrapper for generated audio from sherpa-onnx
struct GeneratedAudio {
    let samples: [Float]
    let sampleRate: Int32
    let phonemes: [PhonemeInfo]  // Complete phoneme data with positions

    // NEW: Normalized text and character mapping from espeak-ng
    let normalizedText: String
    let charMapping: [(originalPos: Int, normalizedPos: Int)]

    init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>) {
        self.sampleRate = audio.pointee.sample_rate

        // Copy samples to Swift array
        let count = Int(audio.pointee.n)
        if let samplesPtr = audio.pointee.samples {
            self.samples = Array(UnsafeBufferPointer(start: samplesPtr, count: count))
        } else {
            self.samples = []
        }

        // Note: Official sherpa-onnx doesn't expose phoneme extraction fields.
        // These were custom additions in the fork for the old PhonemeAlignmentService.
        // We now use CTC forced alignment which doesn't need phoneme data.
        self.phonemes = []

        // Note: Official sherpa-onnx doesn't expose normalized_text or char_mapping
        // These were custom additions in the fork. Since we use CTC forced alignment now,
        // we don't need this data.
        self.normalizedText = ""
        self.charMapping = []
    }
}

// MARK: - Offline TTS Wrapper

/// Swift wrapper for SherpaOnnxOfflineTts
final class SherpaOnnxOfflineTtsWrapper {

    // MARK: - Properties

    private(set) var tts: OpaquePointer?

    // MARK: - Initialization

    /// Initialize TTS engine with configuration
    /// - Parameter config: Pointer to TTS configuration (must remain valid during init)
    init?(config: inout SherpaOnnxOfflineTtsConfig) {
        // Create TTS instance
        self.tts = SherpaOnnxCreateOfflineTts(&config)

        // Verify creation succeeded
        guard self.tts != nil else {
            print("[SherpaOnnx] Failed to create TTS instance")
            return nil
        }

        // Get sample rate to verify initialization
        let sampleRate = SherpaOnnxOfflineTtsSampleRate(tts)
        let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(tts)

        print("[SherpaOnnx] TTS initialized - Sample Rate: \(sampleRate) Hz, Speakers: \(numSpeakers)")
    }

    deinit {
        if let tts = tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
    }

    // MARK: - Public Methods

    /// Generate audio from text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - sid: Speaker ID (0 for single-speaker models)
    ///   - speed: Speech speed multiplier (1.0 = normal, < 1.0 = faster, > 1.0 = slower)
    /// - Returns: Generated audio with samples and sample rate
    func generate(text: String, sid: Int32, speed: Float) -> GeneratedAudio {
        guard let tts = tts else {
            print("[SherpaOnnx] TTS not initialized")
            return GeneratedAudio(samples: [], sampleRate: 22050, phonemes: [], normalizedText: "", charMapping: [])
        }

        // Generate audio
        let audio = SherpaOnnxOfflineTtsGenerate(tts, (text as NSString).utf8String, sid, speed)

        // Wrap result
        let result = GeneratedAudio(audio: audio!)

        // Free the C struct (Swift array owns the data now)
        SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)

        return result
    }

    /// Get the sample rate of the TTS model
    var sampleRate: Int32 {
        guard let tts = tts else { return 22050 }
        return SherpaOnnxOfflineTtsSampleRate(tts)
    }

    /// Get the number of speakers supported by the model
    var numSpeakers: Int32 {
        guard let tts = tts else { return 0 }
        return SherpaOnnxOfflineTtsNumSpeakers(tts)
    }

    /// Synthesize with streaming callback
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - speed: Playback speed multiplier
    ///   - delegate: Callback delegate for streaming chunks
    /// - Returns: Complete synthesis result
    func generateWithStreaming(
        text: String,
        sid: Int32,
        speed: Float,
        delegate: SynthesisStreamDelegate?
    ) async -> GeneratedAudio {
        return await withCheckedContinuation { continuation in
            guard let tts = tts else {
                print("[SherpaOnnx] TTS not initialized")
                continuation.resume(returning: GeneratedAudio(samples: [], sampleRate: 22050, phonemes: [], normalizedText: "", charMapping: []))
                return
            }

            // Create context to pass to C callback
            class CallbackContext {
                weak var delegate: SynthesisStreamDelegate?
                var cancelled: Bool = false

                init(delegate: SynthesisStreamDelegate?) {
                    self.delegate = delegate
                }
            }

            let context = CallbackContext(delegate: delegate)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            // Ensure cleanup happens even if synthesis fails
            defer {
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
            }

            // C callback function - matches signature: (const float *samples, int32_t n, float p, void *arg) -> int32_t
            let callback: @convention(c) (UnsafePointer<Float>?, Int32, Float, UnsafeMutableRawPointer?) -> Int32 = { samples, n, progress, userData in
                guard let userData = userData else { return 1 }
                let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()

                // Convert samples to Data
                if let samples = samples {
                    let buffer = UnsafeBufferPointer(start: samples, count: Int(n))
                    let floatArray = Array(buffer)
                    let data = Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float>.stride)

                    // Call delegate
                    if let delegate = context.delegate {
                        let shouldContinue = delegate.didReceiveAudioChunk(data, progress: Double(progress))
                        if !shouldContinue {
                            context.cancelled = true
                            return 0  // Cancel synthesis
                        }
                    }
                }

                return 1  // Continue synthesis
            }

            // Call C API with callback using the verified function name
            let audio = SherpaOnnxOfflineTtsGenerateWithProgressCallbackWithArg(
                tts,
                (text as NSString).utf8String,
                sid,
                speed,
                callback,
                contextPtr
            )

            // Safely unwrap result
            guard let audio = audio else {
                print("[SherpaOnnx] TTS generation failed")
                continuation.resume(returning: GeneratedAudio(samples: [], sampleRate: 22050, phonemes: [], normalizedText: "", charMapping: []))
                return
            }

            // Wrap result
            let result = GeneratedAudio(audio: audio)

            // Free C struct
            SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)

            continuation.resume(returning: result)
        }
    }
}

// MARK: - GeneratedAudio Convenience Initializer

extension GeneratedAudio {
    init(samples: [Float], sampleRate: Int32, phonemes: [PhonemeInfo] = [], normalizedText: String = "", charMapping: [(Int, Int)] = []) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.phonemes = phonemes
        self.normalizedText = normalizedText
        self.charMapping = charMapping
    }
}
