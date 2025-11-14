//
//  ASRModelLoadingTests.swift
//  Listen2Tests
//
//  Test suite for verifying ASR model loading with sherpa-onnx
//

import XCTest
@testable import Listen2

/// Tests for ASR model loading and initialization
final class ASRModelLoadingTests: XCTestCase {

    // MARK: - Test Cases

    /// Test that Whisper-tiny INT8 models can be loaded and initialized with sherpa-onnx
    func testWhisperTinyModelLoading() throws {
        // Get paths to ASR models in the bundle
        guard let encoderPath = Bundle.main.path(forResource: "tiny-encoder.int8", ofType: "onnx", inDirectory: "ASRModels/whisper-tiny"),
              let decoderPath = Bundle.main.path(forResource: "tiny-decoder.int8", ofType: "onnx", inDirectory: "ASRModels/whisper-tiny"),
              let tokensPath = Bundle.main.path(forResource: "tiny-tokens", ofType: "txt", inDirectory: "ASRModels/whisper-tiny") else {
            XCTFail("Failed to find ASR model files in bundle")
            return
        }

        // Verify files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: encoderPath),
                      "Encoder model file should exist at path: \(encoderPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoderPath),
                      "Decoder model file should exist at path: \(decoderPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokensPath),
                      "Tokens file should exist at path: \(tokensPath)")

        // Verify file sizes are reasonable for INT8 models
        let encoderSize = try FileManager.default.attributesOfItem(atPath: encoderPath)[.size] as? UInt64 ?? 0
        let decoderSize = try FileManager.default.attributesOfItem(atPath: decoderPath)[.size] as? UInt64 ?? 0
        let tokensSize = try FileManager.default.attributesOfItem(atPath: tokensPath)[.size] as? UInt64 ?? 0

        // Expected sizes (approximately):
        // - tiny-encoder.int8.onnx: ~12 MB
        // - tiny-decoder.int8.onnx: ~86 MB
        // - tiny-tokens.txt: ~800 KB
        let encoderMB = Double(encoderSize) / (1024 * 1024)
        let decoderMB = Double(decoderSize) / (1024 * 1024)
        let tokensKB = Double(tokensSize) / 1024

        print("Model sizes:")
        print("  Encoder: \(String(format: "%.1f", encoderMB)) MB")
        print("  Decoder: \(String(format: "%.1f", decoderMB)) MB")
        print("  Tokens: \(String(format: "%.1f", tokensKB)) KB")

        XCTAssertGreaterThan(encoderMB, 10, "Encoder should be ~12 MB")
        XCTAssertLessThan(encoderMB, 15, "Encoder should be ~12 MB")
        XCTAssertGreaterThan(decoderMB, 80, "Decoder should be ~86 MB")
        XCTAssertLessThan(decoderMB, 95, "Decoder should be ~86 MB")
        XCTAssertGreaterThan(tokensKB, 700, "Tokens file should be ~800 KB")
        XCTAssertLessThan(tokensKB, 900, "Tokens file should be ~800 KB")

        // Initialize sherpa-onnx recognizer with Whisper models
        var whisperConfig = createWhisperConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            tokens: tokensPath
        )

        var modelConfig = createOfflineModelConfig(whisperConfig: whisperConfig)
        var recognizerConfig = createRecognizerConfig(modelConfig: modelConfig)

        // Create recognizer
        let recognizer = SherpaOnnxCreateOfflineRecognizer(&recognizerConfig)

        XCTAssertNotNil(recognizer, "Recognizer should be created successfully")

        // Cleanup
        if let recognizer = recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }

        print("✅ Successfully loaded and initialized Whisper-tiny INT8 models")
    }

    /// Test that model files are present in bundle
    func testModelFilesExistInBundle() {
        let modelFiles = [
            "ASRModels/whisper-tiny/tiny-encoder.int8.onnx",
            "ASRModels/whisper-tiny/tiny-decoder.int8.onnx",
            "ASRModels/whisper-tiny/tiny-tokens.txt"
        ]

        for relativePath in modelFiles {
            let components = relativePath.components(separatedBy: "/")
            let fileName = components.last!
            let nameComponents = fileName.components(separatedBy: ".")
            let name = nameComponents.dropLast().joined(separator: ".")
            let ext = nameComponents.last!
            let directory = components.dropLast().joined(separator: "/")

            let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: directory)
            XCTAssertNotNil(path, "Model file should exist in bundle: \(relativePath)")

            if let path = path {
                XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                            "File should exist at path: \(path)")
            }
        }
    }

    // MARK: - Helper Functions

    /// Create Whisper model configuration
    private func createWhisperConfig(encoder: String, decoder: String, tokens: String) -> SherpaOnnxOfflineWhisperModelConfig {
        return SherpaOnnxOfflineWhisperModelConfig(
            encoder: (encoder as NSString).utf8String,
            decoder: (decoder as NSString).utf8String,
            language: ("en" as NSString).utf8String,
            task: ("transcribe" as NSString).utf8String,
            tail_paddings: 0
        )
    }

    /// Create offline model configuration
    private func createOfflineModelConfig(whisperConfig: SherpaOnnxOfflineWhisperModelConfig) -> SherpaOnnxOfflineModelConfig {
        return SherpaOnnxOfflineModelConfig(
            transducer: SherpaOnnxOfflineTransducerModelConfig(
                encoder: nil,
                decoder: nil,
                joiner: nil
            ),
            paraformer: SherpaOnnxOfflineParaformerModelConfig(
                model: nil
            ),
            nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(
                model: nil
            ),
            whisper: whisperConfig,
            tdnn: SherpaOnnxOfflineTdnnModelConfig(
                model: nil
            ),
            tokens: ("" as NSString).utf8String,
            num_threads: 1,
            debug: 1,
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
    }

    /// Create recognizer configuration
    private func createRecognizerConfig(modelConfig: SherpaOnnxOfflineModelConfig) -> SherpaOnnxOfflineRecognizerConfig {
        return SherpaOnnxOfflineRecognizerConfig(
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
                dict_dir: ("" as NSString).utf8String,
                lexicon: ("" as NSString).utf8String,
                rule_fsts: ("" as NSString).utf8String
            )
        )
    }
}
