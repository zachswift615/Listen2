//
//  VoiceManager.swift
//  Listen2
//
//  Manages voice catalog, downloads, and storage
//

import Foundation

/// Manages Piper TTS voices (catalog, downloads, storage)
final class VoiceManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var catalog: VoiceCatalog?

    // MARK: - Storage Paths

    /// Documents/Voices/ - user-downloaded voices
    private var voicesDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voices")
    }

    // MARK: - Catalog

    /// Load voice catalog from bundle
    func loadCatalog() -> VoiceCatalog {
        if let cached = catalog {
            return cached
        }

        guard let url = Bundle.main.url(forResource: "voice-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VoiceCatalog.self, from: data) else {
            fatalError("Failed to load voice-catalog.json from bundle")
        }

        catalog = decoded
        return decoded
    }

    /// All voices in catalog
    func availableVoices() -> [Voice] {
        loadCatalog().voices
    }

    /// Voices that have been downloaded
    func downloadedVoices() -> [Voice] {
        let allVoices = availableVoices()

        return allVoices.filter { voice in
            if voice.isBundled {
                return true  // Bundled voices always "downloaded"
            }
            return modelPath(for: voice.id) != nil
        }
    }

    /// The bundled voice (en_US-lessac-medium)
    func bundledVoice() -> Voice {
        guard let bundled = availableVoices().first(where: { $0.isBundled }) else {
            fatalError("No bundled voice found in catalog")
        }
        return bundled
    }

    // MARK: - Path Resolution

    /// Get model (.onnx) path for voice
    /// - Returns: Path if voice is bundled or downloaded, nil otherwise
    func modelPath(for voiceID: String) -> URL? {
        // Check if bundled
        if let bundledPath = Bundle.main.url(forResource: voiceID, withExtension: "onnx", subdirectory: "PiperModels") {
            return bundledPath
        }

        // Check Documents/Voices/
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("model.onnx")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }

        return nil
    }

    /// Get tokens.txt path for voice
    /// - Returns: Path if voice is bundled or downloaded, nil otherwise
    func tokensPath(for voiceID: String) -> URL? {
        // Check if bundled
        if let bundledPath = Bundle.main.url(forResource: "tokens", withExtension: "txt", subdirectory: "PiperModels") {
            return bundledPath
        }

        // Check Documents/Voices/
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("tokens.txt")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }

        return nil
    }

    // MARK: - Storage Info

    /// Total disk space used by downloaded voices (bytes)
    func diskUsage() -> Int64 {
        guard fileManager.fileExists(atPath: voicesDirectory.path) else {
            return 0
        }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: voicesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    /// Available free space on device (bytes)
    func freeSpace() -> Int64 {
        guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = systemAttributes[.systemFreeSize] as? Int64 else {
            return 0
        }
        return freeSize
    }
}
