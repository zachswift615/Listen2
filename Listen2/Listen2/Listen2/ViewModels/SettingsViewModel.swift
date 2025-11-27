//
//  SettingsViewModel.swift
//  Listen2
//

import SwiftUI
import AVFoundation

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Persisted Settings

    @AppStorage("defaultSpeed") var defaultSpeed: Double = 1.0
    @AppStorage("defaultVoiceIdentifier") var defaultVoiceIdentifier: String?
    @AppStorage("paragraphPauseDelay") var paragraphPauseDelay: Double = 0.3 // Pause between paragraphs in seconds
    @AppStorage("wordHighlightingEnabled") var wordHighlightingEnabled: Bool = true

    // MARK: - Available Voices

    // Use VoiceManager directly to avoid loading ONNX models (~500MB) just for voice queries
    private let voiceManager = VoiceManager()

    var piperVoices: [AVVoice] {
        voiceManager.downloadedVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    var iosVoices: [AVVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    var availableVoices: [AVVoice] {
        piperVoices + iosVoices
    }

    var selectedVoice: AVVoice? {
        get {
            guard let identifier = defaultVoiceIdentifier else {
                return availableVoices.first { $0.language.hasPrefix("en") }
            }

            // Handle Piper voices (IDs start with "piper:")
            if identifier.hasPrefix("piper:") {
                return piperVoices.first { $0.id == identifier }
                    ?? iosVoices.first { $0.id == identifier }
            }

            // Handle iOS voices
            guard let avVoice = AVSpeechSynthesisVoice(identifier: identifier) else {
                return availableVoices.first { $0.language.hasPrefix("en") }
            }
            return AVVoice(from: avVoice)
        }
        set {
            defaultVoiceIdentifier = newValue?.id
        }
    }
}
