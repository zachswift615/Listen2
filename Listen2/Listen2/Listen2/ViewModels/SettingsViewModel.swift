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

    // MARK: - Available Voices

    var availableVoices: [AVVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
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
}
