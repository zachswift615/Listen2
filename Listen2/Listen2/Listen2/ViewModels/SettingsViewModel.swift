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

    // MARK: - Available Voices

    var availableVoices: [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { Voice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    var selectedVoice: Voice? {
        get {
            guard let identifier = defaultVoiceIdentifier,
                  let avVoice = AVSpeechSynthesisVoice(identifier: identifier) else {
                return availableVoices.first { $0.language.hasPrefix("en") }
            }
            return Voice(from: avVoice)
        }
        set {
            defaultVoiceIdentifier = newValue?.id
        }
    }
}
