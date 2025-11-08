//
//  Voice.swift
//  Listen2
//
//  Model representing a Piper TTS voice
//

import Foundation

/// Represents a Piper TTS voice with metadata
struct Voice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let language: String
    let gender: String
    let quality: String
    let sizeMB: Int
    let sampleURL: String?
    let downloadURL: String
    let checksum: String
    let isBundled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case language
        case gender
        case quality
        case sizeMB = "size_mb"
        case sampleURL = "sample_url"
        case downloadURL = "download_url"
        case checksum
        case isBundled = "is_bundled"
    }

    /// Display name for UI (e.g., "Lessac (Medium Quality)")
    var displayName: String {
        "\(name) (\(quality.capitalized) Quality)"
    }

    /// Short language code (e.g., "en" from "en_US")
    var languageCode: String {
        String(language.split(separator: "_").first ?? "")
    }
}

/// Voice catalog containing all available voices
struct VoiceCatalog: Codable {
    let voices: [Voice]
    let version: String
    let lastUpdated: String

    enum CodingKeys: String, CodingKey {
        case voices
        case version
        case lastUpdated = "last_updated"
    }
}
