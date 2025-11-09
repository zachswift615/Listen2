//
//  SettingsViewModel.swift
//  Listen2
//

import SwiftUI
import AVFoundation

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Services

    let ttsService: TTSService

    // MARK: - Persisted Settings

    @AppStorage("defaultSpeed") var defaultSpeed: Double = 1.0
    @AppStorage("defaultVoiceIdentifier") var defaultVoiceIdentifier: String?
    @AppStorage("paragraphPauseDelay") var paragraphPauseDelay: Double = 0.3 // Pause between paragraphs in seconds

    // MARK: - Available Voices

    var piperVoices: [AVVoice] {
        ttsService.piperVoices()
    }

    var iosVoices: [AVVoice] {
        ttsService.iosVoices()
    }

    var availableVoices: [AVVoice] {
        piperVoices
    }

    var selectedVoice: AVVoice? {
        get {
            guard let identifier = defaultVoiceIdentifier,
                  let avVoice = AVSpeechSynthesisVoice(identifier: identifier) else {
                return availableVoices.first { $0.language.hasPrefix("en") }
            }
            return AVVoice(from: avVoice)
        }
        set {
            defaultVoiceIdentifier = newValue?.id
        }
    }

    // MARK: - Initialization

    init(ttsService: TTSService = TTSService()) {
        self.ttsService = ttsService
    }
}
