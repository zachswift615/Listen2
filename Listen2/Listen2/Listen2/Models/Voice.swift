//
//  Voice.swift
//  Listen2
//
//  Model representing a Piper TTS voice (Hugging Face schema)
//

import Foundation

// MARK: - Voice Language

/// Language metadata from Hugging Face voices.json
struct VoiceLanguage: Codable, Equatable, Hashable {
    let code: String           // "en_US"
    let family: String         // "en"
    let region: String         // "US"
    let nameNative: String     // "English"
    let nameEnglish: String    // "English"
    let countryEnglish: String // "United States"

    enum CodingKeys: String, CodingKey {
        case code
        case family
        case region
        case nameNative = "name_native"
        case nameEnglish = "name_english"
        case countryEnglish = "country_english"
    }

    /// Display name for UI (e.g., "English (United States)" or "German")
    var displayName: String {
        if countryEnglish.isEmpty {
            return nameEnglish
        } else {
            return "\(nameEnglish) (\(countryEnglish))"
        }
    }
}

// MARK: - Voice File

/// File metadata from Hugging Face voices.json
struct VoiceFile: Codable, Equatable {
    let sizeBytes: Int
    let md5Digest: String

    enum CodingKeys: String, CodingKey {
        case sizeBytes = "size_bytes"
        case md5Digest = "md5_digest"
    }
}

// MARK: - Voice

/// Represents a Piper TTS voice with metadata from Hugging Face
struct Voice: Identifiable, Codable, Equatable {
    let id: String              // "en_US-amy-low"
    let name: String            // "amy"
    let language: VoiceLanguage
    let quality: String         // "low", "medium", "high", "x_low"
    let numSpeakers: Int
    let speakerIdMap: [String: Int]
    let files: [String: VoiceFile]  // Relative path -> file info

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case language
        case quality
        case numSpeakers = "num_speakers"
        case speakerIdMap = "speaker_id_map"
        case files
    }

    /// Total size of all files in MB
    var sizeMB: Int {
        let downloadableFiles = files.filter { key, _ in
            key.hasSuffix(".onnx") || key.hasSuffix(".onnx.json")
        }
        let totalBytes = downloadableFiles.values.reduce(0) { $0 + $1.sizeBytes }
        return max(1, Int(ceil(Double(totalBytes) / 1_000_000)))
    }

    /// Display name for UI (e.g., "Amy (Low Quality)")
    var displayName: String {
        "\(name.capitalized) (\(quality.capitalized) Quality)"
    }

    /// Sample audio URL from piper-samples repo
    var sampleURL: URL? {
        let base = "https://raw.githubusercontent.com/rhasspy/piper-samples/master/samples"
        let path = "\(language.family)/\(language.code)/\(name)/\(quality)/speaker_0.mp3"
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(base)/\(encodedPath)")
    }

    /// URLs to download from Hugging Face (onnx and json files)
    var downloadURLs: [URL] {
        let base = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
        return files.keys.compactMap { path in
            guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                return nil
            }
            return URL(string: "\(base)/\(encodedPath)")
        }
    }

    /// Path to the .onnx file (relative, for download)
    var onnxFilePath: String? {
        files.keys.first { $0.hasSuffix(".onnx") && !$0.hasSuffix(".onnx.json") }
    }

    /// Path to the .onnx.json file (relative, for download)
    var onnxJsonFilePath: String? {
        files.keys.first { $0.hasSuffix(".onnx.json") }
    }
}

// MARK: - Voice Catalog (Remote)

/// Voice catalog fetched from Hugging Face
/// Note: HF voices.json is a dictionary keyed by voice ID, not an array
struct RemoteVoiceCatalog {
    let voices: [Voice]
    let fetchedAt: Date

    /// Parse from Hugging Face voices.json format
    /// Format: { "en_US-amy-low": { "name": "amy", ... }, ... }
    static func parse(from data: Data) throws -> RemoteVoiceCatalog {
        let decoder = JSONDecoder()

        // HF format is a dictionary, not an array
        let rawDict = try decoder.decode([String: RawVoiceEntry].self, from: data)

        let voices = rawDict.compactMap { (id, entry) -> Voice? in
            Voice(
                id: id,
                name: entry.name,
                language: entry.language,
                quality: entry.quality,
                numSpeakers: entry.num_speakers,
                speakerIdMap: entry.speaker_id_map,
                files: entry.files
            )
        }.sorted { $0.id < $1.id }

        return RemoteVoiceCatalog(voices: voices, fetchedAt: Date())
    }
}

/// Raw entry from HF voices.json (intermediate parsing)
private struct RawVoiceEntry: Codable {
    let name: String
    let language: VoiceLanguage
    let quality: String
    let num_speakers: Int
    let speaker_id_map: [String: Int]
    let files: [String: VoiceFile]
}

// MARK: - Cached Catalog

/// Wrapper for caching the catalog locally
struct CachedVoiceCatalog: Codable {
    let voices: [Voice]
    let fetchedAt: Date

    var isStale: Bool {
        // Stale if older than 24 hours
        Date().timeIntervalSince(fetchedAt) > 24 * 60 * 60
    }
}
