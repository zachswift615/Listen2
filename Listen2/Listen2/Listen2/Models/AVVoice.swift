//
//  AVVoice.swift
//  Listen2
//

import Foundation
import AVFoundation

enum AVVoiceGender: String, Codable, CaseIterable {
    case male
    case female
    case neutral
}

struct AVVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let gender: AVVoiceGender
    let isPiperVoice: Bool  // True if this is a Piper TTS voice

    init(from avVoice: AVSpeechSynthesisVoice) {
        self.id = avVoice.identifier
        self.name = avVoice.name
        self.language = avVoice.language
        self.quality = avVoice.quality
        self.gender = Self.detectGender(from: avVoice)
        self.isPiperVoice = false
    }

    /// Initialize from Piper Voice model
    init(from piperVoice: Voice) {
        self.id = "piper:\(piperVoice.id)"  // Prefix to distinguish from AVSpeech
        self.name = piperVoice.displayName
        self.language = piperVoice.language.code  // Use language code
        // Map Piper quality to AVSpeech quality
        self.quality = Self.mapPiperQuality(piperVoice.quality)
        // Piper voices don't have gender metadata, default to neutral
        self.gender = .neutral
        self.isPiperVoice = true
    }

    private static func mapPiperQuality(_ quality: String) -> AVSpeechSynthesisVoiceQuality {
        switch quality.lowercased() {
        case "low":
            return .default
        case "medium":
            return .enhanced
        case "high", "very_high":
            return .premium
        default:
            return .enhanced
        }
    }

    var displayName: String {
        "\(name) (\(languageDisplayName))"
    }

    private var languageDisplayName: String {
        let locale = Locale(identifier: language)
        return locale.localizedString(forLanguageCode: language) ?? language
    }

    // MARK: - Gender Detection

    private static func detectGender(from avVoice: AVSpeechSynthesisVoice) -> AVVoiceGender {
        let identifier = avVoice.identifier.lowercased()
        let name = avVoice.name.lowercased()

        // Check identifier patterns
        if identifier.contains("samantha") || identifier.contains("victoria") ||
           identifier.contains("karen") || identifier.contains("moira") ||
           identifier.contains("tessa") || identifier.contains("kate") ||
           identifier.contains("sara") || identifier.contains("nora") {
            return .female
        }

        if identifier.contains("alex") || identifier.contains("daniel") ||
           identifier.contains("fred") || identifier.contains("oliver") ||
           identifier.contains("thomas") || identifier.contains("rishi") {
            return .male
        }

        // Check name patterns (fallback)
        let femaleNames = ["samantha", "victoria", "karen", "moira", "tessa",
                          "kate", "sara", "nora", "fiona", "alice"]
        let maleNames = ["alex", "daniel", "fred", "oliver", "thomas", "rishi",
                        "gordon", "arthur"]

        for femaleName in femaleNames {
            if name.contains(femaleName) {
                return .female
            }
        }

        for maleName in maleNames {
            if name.contains(maleName) {
                return .male
            }
        }

        return .neutral
    }
}
