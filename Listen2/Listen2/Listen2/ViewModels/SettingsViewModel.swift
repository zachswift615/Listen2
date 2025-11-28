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

    /// Raw stored highlight level (use effectiveHighlightLevel for device-aware value)
    /// Default is empty string - means "use device-recommended"
    @AppStorage("highlightLevel") var highlightLevelRaw: String = ""

    // MARK: - Highlight Level

    /// User's selected highlight level (defaults to device-recommended if not set)
    var highlightLevel: HighlightLevel {
        get {
            if highlightLevelRaw.isEmpty {
                return DeviceCapabilityService.recommendedHighlightLevel
            }
            return HighlightLevel(rawValue: highlightLevelRaw) ?? DeviceCapabilityService.recommendedHighlightLevel
        }
        set { highlightLevelRaw = newValue.rawValue }
    }

    /// Effective highlight level considering device constraints
    /// On low-memory devices, word-level is capped to sentence-level
    var effectiveHighlightLevel: HighlightLevel {
        let userChoice = highlightLevel

        // Cap based on device capability
        let maxAllowed = DeviceCapabilityService.maxAllowedHighlightLevel

        // If user's choice requires more capability than device allows, use max allowed
        if userChoice.granularity > maxAllowed.granularity {
            return maxAllowed
        }

        return userChoice
    }

    /// Whether word-level highlighting is restricted on this device
    var isWordLevelRestricted: Bool {
        DeviceCapabilityService.isWordLevelRestricted
    }

    /// Device tier for display in UI
    var deviceTier: DeviceCapabilityService.DeviceTier {
        DeviceCapabilityService.deviceTier
    }

    /// Recommended highlight level for this device
    var recommendedHighlightLevel: HighlightLevel {
        DeviceCapabilityService.recommendedHighlightLevel
    }

    // MARK: - Initialization

    init() {
        // Migrate from old wordHighlightingEnabled setting
        migrateFromLegacySetting()
    }

    /// Migrate from old boolean wordHighlightingEnabled to new highlightLevel
    private func migrateFromLegacySetting() {
        let defaults = UserDefaults.standard
        let legacyKey = "wordHighlightingEnabled"

        // Check if old setting exists (it will be stored as a boolean)
        if defaults.object(forKey: legacyKey) != nil {
            let wasEnabled = defaults.bool(forKey: legacyKey)

            // Only migrate if highlightLevel hasn't been set yet
            if defaults.object(forKey: "highlightLevel") == nil {
                highlightLevelRaw = wasEnabled ? HighlightLevel.word.rawValue : HighlightLevel.off.rawValue
            }

            // Remove the old key to prevent repeated migration
            defaults.removeObject(forKey: legacyKey)
        }
    }

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
