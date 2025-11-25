//
//  PiperTTSProvider.swift
//  Listen2
//
//  Piper TTS implementation using sherpa-onnx
//

import Foundation
import AVFoundation

/// Result of TTS synthesis including audio and phoneme timing
struct SynthesisResult {
    /// WAV audio data
    let audioData: Data

    /// Phoneme sequence with durations and character positions
    let phonemes: [PhonemeInfo]

    /// Original text that was synthesized (for debugging/validation)
    let text: String

    /// Sample rate of the audio
    let sampleRate: Int32

    /// Normalized text from espeak (e.g., "Dr." -> "Doctor")
    let normalizedText: String

    /// Character position mapping: [(originalPos, normalizedPos)]
    /// Maps positions in original text to positions in normalized text
    let charMapping: [(originalPos: Int, normalizedPos: Int)]
}

/// Piper TTS provider using sherpa-onnx inference
final class PiperTTSProvider: TTSProvider {

    // MARK: - Properties

    private let voiceID: String
    private let voiceManager: VoiceManager
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var isInitialized = false

    // MARK: - TTSProvider Protocol

    var sampleRate: Int { 22050 }

    // MARK: - Initialization

    init(voiceID: String, voiceManager: VoiceManager) {
        self.voiceID = voiceID
        self.voiceManager = voiceManager
    }

    func initialize() async throws {
        guard !isInitialized else { return }

        // Get model paths from VoiceManager with detailed logging
        let modelPath = voiceManager.modelPath(for: voiceID)
        let tokensPath = voiceManager.tokensPath(for: voiceID)
        let espeakDataPath = voiceManager.speakNGDataPath(for: voiceID)

        guard let modelPath = modelPath,
              let tokensPath = tokensPath,
              let espeakDataPath = espeakDataPath else {
            throw TTSError.synthesisFailed(reason: "Voice '\(voiceID)' not found")
        }

        // Configure VITS model
        let vits = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath.path,
            lexicon: "",
            tokens: tokensPath.path,
            dataDir: espeakDataPath.path
        )

        let modelConfig = sherpaOnnxOfflineTtsModelConfig(vits: vits)
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: modelConfig)

        // Initialize TTS engine
        tts = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)

        // Validate initialization succeeded
        guard let tts = tts, tts.tts != nil else {
            throw TTSError.synthesisFailed(reason: "sherpa-onnx initialization returned NULL")
        }

        isInitialized = true
    }

    func synthesize(_ text: String, speed: Float) async throws -> SynthesisResult {
        guard isInitialized, let tts = tts else {
            throw TTSError.notInitialized
        }

        // Validate text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSError.emptyText
        }

        guard text.utf8.count <= 10_000 else {
            throw TTSError.textTooLong(maxLength: 10_000)
        }

        guard text.data(using: .utf8) != nil else {
            throw TTSError.invalidEncoding
        }

        // Clamp speed to valid range
        let clampedSpeed = max(0.5, min(2.0, speed))

        // Generate audio with phoneme sequence
        let audio = tts.generate(text: text, sid: 0, speed: clampedSpeed)

        // Convert to WAV data
        let wavData = createWAVData(samples: audio.samples, sampleRate: Int(audio.sampleRate))

        return SynthesisResult(
            audioData: wavData,
            phonemes: audio.phonemes,
            text: text,
            sampleRate: audio.sampleRate,
            normalizedText: audio.normalizedText,
            charMapping: audio.charMapping
        )
    }

    /// Synthesize with streaming callback support
    func synthesizeWithStreaming(
        _ text: String,
        speed: Float,
        delegate: SynthesisStreamDelegate?
    ) async throws -> SynthesisResult {
        guard isInitialized, let tts = tts else {
            throw TTSError.notInitialized
        }

        // Validate text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSError.emptyText
        }

        guard text.utf8.count <= 10_000 else {
            throw TTSError.textTooLong(maxLength: 10_000)
        }

        guard text.data(using: .utf8) != nil else {
            throw TTSError.invalidEncoding
        }

        // Clamp speed to valid range
        let clampedSpeed = max(0.5, min(2.0, speed))

        // Use sherpa-onnx streaming API
        let audio = await tts.generateWithStreaming(
            text: text,
            sid: 0,
            speed: clampedSpeed,
            delegate: delegate
        )

        // Convert to WAV data
        let wavData = createWAVData(samples: audio.samples, sampleRate: Int(audio.sampleRate))

        return SynthesisResult(
            audioData: wavData,
            phonemes: audio.phonemes,
            text: text,
            sampleRate: audio.sampleRate,
            normalizedText: audio.normalizedText,
            charMapping: audio.charMapping
        )
    }

    func cleanup() {
        tts = nil
        isInitialized = false
    }

    // MARK: - Private Helpers

    private func createWAVData(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()

        // Convert samples to 16-bit PCM
        let pcmSamples: [Int16] = samples.map { sample in
            let scaled = sample * 32767.0
            return Int16(max(-32768, min(32767, scaled)))
        }

        // WAV header
        let numSamples = pcmSamples.count
        let dataSize = numSamples * 2  // 2 bytes per sample
        let fileSize = 36 + dataSize

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(fileSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)  // Chunk size
        data.append(UInt16(1).littleEndianData)   // Audio format (PCM)
        data.append(UInt16(1).littleEndianData)   // Num channels (mono)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)  // Byte rate
        data.append(UInt16(2).littleEndianData)   // Block align
        data.append(UInt16(16).littleEndianData)  // Bits per sample

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)

        // PCM data
        for sample in pcmSamples {
            data.append(sample.littleEndianData)
        }

        return data
    }
}

// MARK: - Data Extensions

private extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

private extension Int16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Int16>.size)
    }
}
