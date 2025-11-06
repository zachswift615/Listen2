//
//  Voice.swift
//  Listen2
//

import Foundation
import AVFoundation

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    init(from avVoice: AVSpeechSynthesisVoice) {
        self.id = avVoice.identifier
        self.name = avVoice.name
        self.language = avVoice.language
        self.quality = avVoice.quality
    }

    var displayName: String {
        "\(name) (\(languageDisplayName))"
    }

    private var languageDisplayName: String {
        let locale = Locale(identifier: language)
        return locale.localizedString(forLanguageCode: language) ?? language
    }
}
