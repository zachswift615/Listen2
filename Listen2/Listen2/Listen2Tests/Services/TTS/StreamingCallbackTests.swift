//
//  StreamingCallbackTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class StreamingCallbackTests: XCTestCase {

    class TestDelegate: SynthesisStreamDelegate {
        var chunks: [Data] = []
        var progressValues: [Double] = []

        func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
            chunks.append(chunk)
            progressValues.append(progress)
            return true  // Continue
        }
    }

    func testStreamingCallback() async throws {
        // NOTE: This test requires actual TTS models to be available
        // If models are not present, the test will be skipped

        // Get path to model (this would need to be configured for testing)
        guard let modelBundle = Bundle(identifier: "com.anthropic.Listen2") else {
            throw XCTSkip("App bundle not available - cannot locate TTS models")
        }

        guard let modelPath = modelBundle.path(forResource: "en_US-lessac-medium", ofType: "onnx"),
              let tokensPath = modelBundle.path(forResource: "tokens", ofType: "txt"),
              let espeakDataDir = modelBundle.path(forResource: "espeak-ng-data", ofType: nil) else {
            throw XCTSkip("TTS models not available for testing")
        }

        // Create TTS configuration
        var vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            lexicon: "",
            tokens: tokensPath,
            dataDir: espeakDataDir
        )
        var modelConfig = sherpaOnnxOfflineTtsModelConfig(vits: vitsConfig)
        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)

        guard let ttsWrapper = SherpaOnnxOfflineTtsWrapper(config: &config) else {
            throw XCTSkip("Failed to initialize TTS engine")
        }

        let delegate = TestDelegate()

        let text = "First sentence. Second sentence. Third sentence."
        let result = ttsWrapper.generateWithStreaming(
            text: text,
            sid: 0,
            speed: 1.0,
            delegate: delegate
        )

        // Verify callbacks were called
        XCTAssertGreaterThan(delegate.chunks.count, 0, "Should receive at least one chunk")
        XCTAssertGreaterThan(delegate.progressValues.count, 0, "Should receive progress updates")

        // Verify progress increases
        for i in 1..<delegate.progressValues.count {
            XCTAssertGreaterThanOrEqual(
                delegate.progressValues[i],
                delegate.progressValues[i-1],
                "Progress should increase"
            )
        }

        // Verify final audio exists
        XCTAssertGreaterThan(result.samples.count, 0, "Should have audio samples")

        // Log for debugging
        print("[StreamingCallbackTests] Received \(delegate.chunks.count) chunks")
        print("[StreamingCallbackTests] Progress values: \(delegate.progressValues)")
        print("[StreamingCallbackTests] Final audio: \(result.samples.count) samples @ \(result.sampleRate)Hz")
    }
}
