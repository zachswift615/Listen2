//
//  SherpaOnnx.swift
//  Listen2
//
//  Swift wrapper for sherpa-onnx C API (offline TTS)
//

import Foundation

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

    init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>) {
        self.sampleRate = audio.pointee.sample_rate

        // Copy samples to Swift array
        let count = Int(audio.pointee.n)
        if let samplesPtr = audio.pointee.samples {
            self.samples = Array(UnsafeBufferPointer(start: samplesPtr, count: count))
        } else {
            self.samples = []
        }
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
            return GeneratedAudio(samples: [], sampleRate: 22050)
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
}

// MARK: - GeneratedAudio Convenience Initializer

extension GeneratedAudio {
    init(samples: [Float], sampleRate: Int32) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}
