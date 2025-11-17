//
//  VoiceManager.swift
//  Listen2
//
//  Manages voice catalog, downloads, and storage
//

import Foundation
import SWCompression

/// Manages Piper TTS voices (catalog, downloads, storage)
final class VoiceManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var catalog: VoiceCatalog?
    private let bundle: Bundle

    // MARK: - Initialization

    /// Initialize VoiceManager with a specific bundle (useful for tests)
    /// - Parameter bundle: Bundle to use for resource lookup (defaults to .main)
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

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

        guard let url = bundle.url(forResource: "voice-catalog", withExtension: "json"),
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

        let downloaded = allVoices.filter { voice in
            if voice.isBundled {
                return true  // Bundled voices always "downloaded"
            }
            let hasModel = modelPath(for: voice.id) != nil
            if !hasModel {
                print("[VoiceManager] 🔍 Voice '\(voice.id)' NOT downloaded - modelPath returned nil")
            }
            return hasModel
        }

        print("[VoiceManager] 📊 Downloaded voices: \(downloaded.count) of \(allVoices.count)")
        return downloaded
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
        // Check if bundled (Xcode 16 flattens Resources to bundle root)
        if let bundledPath = bundle.url(forResource: voiceID, withExtension: "onnx") {
            print("[VoiceManager] 🔍 modelPath(\(voiceID)): Found bundled at \(bundledPath.path)")
            return bundledPath
        }

        // Check Documents/Voices/
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("model.onnx")

        let exists = fileManager.fileExists(atPath: downloadedPath.path)
        print("[VoiceManager] 🔍 modelPath(\(voiceID)): Checking \(downloadedPath.path) - exists: \(exists)")

        if exists {
            return downloadedPath
        }

        return nil
    }

    /// Get tokens.txt path for voice
    /// - Returns: Path if voice is bundled or downloaded, nil otherwise
    func tokensPath(for voiceID: String) -> URL? {
        // Check Documents/Voices/ FIRST (downloaded voices)
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("tokens.txt")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            print("[VoiceManager] 🔍 tokensPath(\(voiceID)): Found downloaded at \(downloadedPath.path)")
            return downloadedPath
        }

        // Fallback to bundled (only for bundled voice)
        if let bundledPath = bundle.url(forResource: "tokens", withExtension: "txt") {
            print("[VoiceManager] 🔍 tokensPath(\(voiceID)): Using bundled at \(bundledPath.path)")
            return bundledPath
        }

        return nil
    }

    /// Get espeak-ng-data directory path
    /// - Returns: Path to espeak-ng-data directory if available, nil otherwise
    func speakNGDataPath(for voiceID: String) -> URL? {
        // Check Documents/Voices/ FIRST (downloaded voices)
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("espeak-ng-data")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            print("[VoiceManager] 🔍 espeakDataPath(\(voiceID)): Found downloaded at \(downloadedPath.path)")
            return downloadedPath
        }

        // Fallback to bundled (only for bundled voice)
        if let bundledPath = bundle.url(forResource: "espeak-ng-data", withExtension: nil) {
            print("[VoiceManager] 🔍 espeakDataPath(\(voiceID)): Using bundled at \(bundledPath.path)")
            return bundledPath
        }

        // Second fallback: Check if it's in bundle root (old Xcode 16 flattening workaround)
        if let bundledPath = bundle.resourceURL {
            let espeakDir = bundledPath.appendingPathComponent("espeak-ng-data")
            if fileManager.fileExists(atPath: espeakDir.path) {
                print("[VoiceManager] 🔍 espeakDataPath(\(voiceID)): Using bundle root at \(espeakDir.path)")
                return espeakDir
            }
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

    // MARK: - Downloads

    /// Download a voice from remote URL
    /// - Parameters:
    ///   - voiceID: Voice ID to download
    ///   - progress: Progress callback (0.0-1.0)
    func download(voiceID: String, progress: @escaping (Double) -> Void) async throws {
        guard let voice = availableVoices().first(where: { $0.id == voiceID }) else {
            throw VoiceError.voiceNotFound
        }

        // Check free space (require 2x voice size for safety)
        let requiredSpace = Int64(voice.sizeMB * 1024 * 1024 * 2)
        guard freeSpace() >= requiredSpace else {
            throw VoiceError.insufficientSpace(required: voice.sizeMB * 2, available: Int(freeSpace() / 1024 / 1024))
        }

        // Download URL
        guard let url = URL(string: voice.downloadURL) else {
            throw VoiceError.invalidURL
        }

        // Download to temp file
        let tempFile = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".tar.bz2")

        // Download
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)

        // Verify response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VoiceError.downloadFailed(reason: "HTTP error")
        }

        // Move to temp location
        try fileManager.moveItem(at: downloadedURL, to: tempFile)

        progress(0.5)  // Download complete, extraction next

        print("[VoiceManager] Starting extraction for \(voiceID)")

        // Extract tar.bz2 using SWCompression (works on both iOS and macOS)
        let voiceDir = voicesDirectory.appendingPathComponent(voiceID)
        try fileManager.createDirectory(at: voiceDir, withIntermediateDirectories: true)

        print("[VoiceManager] Created voice directory: \(voiceDir.path)")

        // Perform CPU-intensive decompression and extraction on background thread
        let extractionResult = try await Task.detached(priority: .userInitiated) { [voiceDir, tempFile, fileManager, progress] in
            do {
                // Read the compressed tar.bz2 file
                print("[VoiceManager] Reading compressed file...")
                let compressedData = try Data(contentsOf: tempFile)
                print("[VoiceManager] Compressed file size: \(compressedData.count / 1024 / 1024) MB")

                // Decompress bzip2 (CPU-intensive - can take 2-3 minutes for 64MB files)
                print("[VoiceManager] Decompressing bzip2 (this may take a few minutes)...")
                progress(0.55)  // Show some progress
                let decompressedData = try BZip2.decompress(data: compressedData)
                print("[VoiceManager] Decompressed size: \(decompressedData.count / 1024 / 1024) MB")
                progress(0.75)  // Decompression complete

                // Extract tar archive
                print("[VoiceManager] Opening tar container...")
                progress(0.80)
                let tarContents = try TarContainer.open(container: decompressedData)
                print("[VoiceManager] Tar contains \(tarContents.count) entries")

                // Extract all files, stripping the top-level directory
                var extractedCount = 0
                let totalEntries = tarContents.count
                for (index, entry) in tarContents.enumerated() {
                    // Skip directories
                    guard entry.info.type == .regular || entry.info.type == .symbolicLink else {
                        continue
                    }

                    // Strip first path component (removes top-level directory from archive)
                    var pathComponents = entry.info.name.split(separator: "/").map(String.init)
                    guard pathComponents.count > 1 else {
                        // Skip if only one component (shouldn't happen)
                        continue
                    }
                    pathComponents.removeFirst()
                    var relativePath = pathComponents.joined(separator: "/")

                    // Rename voice-specific .onnx file to generic model.onnx
                    if relativePath.hasSuffix(".onnx") && !relativePath.hasSuffix("model.onnx") {
                        print("[VoiceManager] 🔄 Renaming \(relativePath) → model.onnx")
                        relativePath = "model.onnx"
                    }

                    let filePath = voiceDir.appendingPathComponent(relativePath)

                    // Create parent directory if needed
                    let parentDir = filePath.deletingLastPathComponent()
                    if !fileManager.fileExists(atPath: parentDir.path) {
                        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }

                    // Write file data
                    if let data = entry.data {
                        try data.write(to: filePath)
                        extractedCount += 1
                        if extractedCount % 100 == 0 {
                            let extractProgress = 0.80 + (0.19 * Double(index) / Double(totalEntries))
                            progress(extractProgress)
                            print("[VoiceManager] Extracted \(extractedCount)/\(totalEntries) files (\(Int(extractProgress * 100))%)...")
                        }
                    }
                }

                print("[VoiceManager] ✅ Extraction complete! Extracted \(extractedCount) files")

                // List extracted files for debugging
                if let contents = try? fileManager.contentsOfDirectory(at: voiceDir, includingPropertiesForKeys: nil) {
                    print("[VoiceManager] 📁 Extracted files in \(voiceDir.lastPathComponent):")
                    for file in contents.prefix(10) {
                        print("[VoiceManager]   - \(file.lastPathComponent)")
                    }
                    if contents.count > 10 {
                        print("[VoiceManager]   ... and \(contents.count - 10) more files")
                    }
                }

                return extractedCount
            } catch {
                print("[VoiceManager] ❌ Extraction failed: \(error.localizedDescription)")
                throw error
            }
        }.value

        // Check if extraction succeeded
        if extractionResult == 0 {
            try? fileManager.removeItem(at: voiceDir)
            throw VoiceError.extractionFailed(reason: "No files extracted")
        }

        progress(1.0)

        // Verify critical files exist
        let modelPath = voiceDir.appendingPathComponent("model.onnx")
        let tokensPath = voiceDir.appendingPathComponent("tokens.txt")

        print("[VoiceManager] 🔍 Verifying extracted files:")
        print("[VoiceManager]   Voice directory: \(voiceDir.path)")
        print("[VoiceManager]   model.onnx exists: \(fileManager.fileExists(atPath: modelPath.path))")
        print("[VoiceManager]   tokens.txt exists: \(fileManager.fileExists(atPath: tokensPath.path))")

        if !fileManager.fileExists(atPath: modelPath.path) {
            print("[VoiceManager] ⚠️ WARNING: model.onnx not found after extraction!")
        }

        // Cleanup temp file
        try? fileManager.removeItem(at: tempFile)
    }

    /// Delete a downloaded voice
    func delete(voiceID: String) throws {
        let selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID")

        // Cannot delete active voice
        guard voiceID != selectedVoiceID else {
            throw VoiceError.cannotDeleteActiveVoice
        }

        // Cannot delete bundled voice
        if availableVoices().first(where: { $0.id == voiceID })?.isBundled == true {
            throw VoiceError.cannotDeleteBundledVoice
        }

        let voiceDir = voicesDirectory.appendingPathComponent(voiceID)
        try fileManager.removeItem(at: voiceDir)
    }

    /// Cancel ongoing download
    func cancelDownload(voiceID: String) {
        // TODO: Track active downloads and cancel
    }

    /// Errors related to voice management
    enum VoiceError: Error, LocalizedError {
        case voiceNotFound
        case insufficientSpace(required: Int, available: Int)
        case invalidURL
        case downloadFailed(reason: String)
        case extractionFailed(reason: String)
        case checksumMismatch
        case cannotDeleteActiveVoice
        case cannotDeleteBundledVoice

        var errorDescription: String? {
            switch self {
            case .voiceNotFound:
                return "Voice not found in catalog"
            case .insufficientSpace(let required, let available):
                return "Not enough storage. Need \(required) MB, but only \(available) MB available."
            case .invalidURL:
                return "Invalid download URL"
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .extractionFailed(let reason):
                return "Extraction failed: \(reason)"
            case .checksumMismatch:
                return "Downloaded file is corrupted (checksum mismatch)"
            case .cannotDeleteActiveVoice:
                return "Cannot delete currently selected voice"
            case .cannotDeleteBundledVoice:
                return "Cannot delete bundled voice"
            }
        }
    }
}
