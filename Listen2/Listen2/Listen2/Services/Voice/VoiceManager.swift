//
//  VoiceManager.swift
//  Listen2
//
//  Manages voice catalog, downloads, and storage
//

import Foundation
import SWCompression

// MARK: - Download Progress Delegate

/// URLSession delegate for tracking download progress
private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: (Double) -> Void
    private let completionHandler: (Result<URL, Error>) -> Void

    init(progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Copy to a temp location we control (the original will be deleted)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".download")
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            completionHandler(.success(tempURL))
        } catch {
            completionHandler(.failure(error))
        }
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler(.failure(error))
            session.invalidateAndCancel()
        }
    }
}

/// Manages Piper TTS voices (catalog, downloads, storage)
final class VoiceManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var catalog: [Voice]?
    private let bundle: Bundle

    // MARK: - Initialization

    /// Initialize VoiceManager with a specific bundle (useful for tests)
    /// - Parameter bundle: Bundle to use for resource lookup (defaults to .main)
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: - Remote Catalog

    private let catalogURL = URL(string: "https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json")!
    private let cacheFileName = "voice-catalog-cache.json"

    /// Path to cached catalog
    private var catalogCachePath: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    /// Load catalog - tries cache first, then fetches remote
    func loadCatalogAsync() async -> [Voice] {
        // Try cached first
        if let cached = loadCachedCatalog(), !cached.isStale {
            print("[VoiceManager] Using cached catalog (\(cached.voices.count) voices)")
            return cached.voices
        }

        // Fetch remote
        do {
            let voices = try await fetchRemoteCatalog()
            print("[VoiceManager] Fetched remote catalog (\(voices.count) voices)")
            return voices
        } catch {
            print("[VoiceManager] Failed to fetch remote catalog: \(error)")
            // Fall back to stale cache
            if let cached = loadCachedCatalog() {
                print("[VoiceManager] Using stale cached catalog")
                return cached.voices
            }
            // Fall back to bundled
            print("[VoiceManager] Using bundled fallback catalog")
            return loadBundledCatalog()
        }
    }

    /// Fetch catalog from Hugging Face
    private func fetchRemoteCatalog() async throws -> [Voice] {
        let (data, response) = try await URLSession.shared.data(from: catalogURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VoiceError.downloadFailed(reason: "HTTP error fetching catalog")
        }

        let catalog = try RemoteVoiceCatalog.parse(from: data)

        // Cache it
        saveCatalogToCache(CachedVoiceCatalog(voices: catalog.voices, fetchedAt: catalog.fetchedAt))

        return catalog.voices
    }

    /// Load cached catalog from disk
    private func loadCachedCatalog() -> CachedVoiceCatalog? {
        guard fileManager.fileExists(atPath: catalogCachePath.path),
              let data = try? Data(contentsOf: catalogCachePath),
              let cached = try? JSONDecoder().decode(CachedVoiceCatalog.self, from: data) else {
            return nil
        }
        return cached
    }

    /// Save catalog to cache
    private func saveCatalogToCache(_ catalog: CachedVoiceCatalog) {
        do {
            let data = try JSONEncoder().encode(catalog)
            try data.write(to: catalogCachePath)
        } catch {
            print("[VoiceManager] Failed to cache catalog: \(error)")
        }
    }

    /// Load bundled fallback catalog (minimal English voices)
    private func loadBundledCatalog() -> [Voice] {
        // Return empty for now - bundled catalog uses old format
        // TODO: Create minimal bundled catalog in new format
        return []
    }

    // MARK: - Storage Paths

    /// Documents/Voices/ - user-downloaded voices
    private var voicesDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voices")
    }

    // MARK: - Catalog

    /// Load voice catalog (sync version - uses cache only)
    /// For async loading with network, use loadCatalogAsync()
    func loadCatalog() -> [Voice] {
        if let cached = catalog {
            return cached
        }

        // Try cached catalog first
        if let cached = loadCachedCatalog() {
            self.catalog = cached.voices
            return cached.voices
        }

        // Fall back to bundled
        let voices = loadBundledCatalog()
        self.catalog = voices
        return voices
    }

    /// All voices in catalog
    func availableVoices() -> [Voice] {
        loadCatalog()
    }

    /// Voices that have been downloaded
    func downloadedVoices() -> [Voice] {
        let allVoices = availableVoices()

        return allVoices.filter { voice in
            modelPath(for: voice.id) != nil
        }
    }

    /// Check if a specific voice is downloaded
    func isVoiceDownloaded(_ voiceID: String) -> Bool {
        modelPath(for: voiceID) != nil
    }

    // MARK: - Path Resolution

    /// Get model (.onnx) path for voice
    /// - Returns: Path if voice is bundled or downloaded, nil otherwise
    func modelPath(for voiceID: String) -> URL? {
        // Check if bundled (Xcode 16 flattens Resources to bundle root)
        if let bundledPath = bundle.url(forResource: voiceID, withExtension: "onnx") {
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
        // Check Documents/Voices/ FIRST (downloaded voices)
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("tokens.txt")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }

        // Fallback to bundled (only for bundled voice)
        if let bundledPath = bundle.url(forResource: "tokens", withExtension: "txt") {
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
            return downloadedPath
        }

        // Fallback to bundled (only for bundled voice)
        if let bundledPath = bundle.url(forResource: "espeak-ng-data", withExtension: nil) {
            return bundledPath
        }

        // Second fallback: Check if it's in bundle root (old Xcode 16 flattening workaround)
        if let bundledPath = bundle.resourceURL {
            let espeakDir = bundledPath.appendingPathComponent("espeak-ng-data")
            if fileManager.fileExists(atPath: espeakDir.path) {
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

    /// Download a voice from Hugging Face
    /// - Parameters:
    ///   - voice: Voice to download
    ///   - progress: Progress callback (0.0-1.0)
    func download(voice: Voice, progress: @escaping (Double) -> Void) async throws {
        guard let onnxPath = voice.onnxFilePath,
              let jsonPath = voice.onnxJsonFilePath else {
            throw VoiceError.invalidURL
        }

        // Check free space (require 2x voice size for safety)
        let requiredSpace = Int64(voice.sizeMB * 1024 * 1024 * 2)
        guard freeSpace() >= requiredSpace else {
            throw VoiceError.insufficientSpace(required: voice.sizeMB * 2, available: Int(freeSpace() / 1024 / 1024))
        }

        let voiceDir = voicesDirectory.appendingPathComponent(voice.id)
        try fileManager.createDirectory(at: voiceDir, withIntermediateDirectories: true)

        // Download URLs
        let baseURL = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
        guard let onnxURL = URL(string: "\(baseURL)/\(onnxPath)"),
              let jsonURL = URL(string: "\(baseURL)/\(jsonPath)") else {
            throw VoiceError.invalidURL
        }

        // Download .onnx file (main model, ~95% of size)
        progress(0.0)
        let onnxData = try await downloadFile(from: onnxURL) { downloadProgress in
            progress(downloadProgress * 0.9)  // 0-90%
        }

        // Save .onnx as model.onnx
        let modelPath = voiceDir.appendingPathComponent("model.onnx")
        try onnxData.write(to: modelPath)
        progress(0.9)

        // Download .onnx.json file (small config)
        let jsonData = try await downloadFile(from: jsonURL) { _ in }
        let jsonFilePath = voiceDir.appendingPathComponent("model.onnx.json")
        try jsonData.write(to: jsonFilePath)
        progress(0.95)

        // Generate tokens.txt from phoneme_id_map in JSON
        try generateTokensFile(from: jsonData, to: voiceDir.appendingPathComponent("tokens.txt"))
        progress(1.0)

        print("[VoiceManager] ✅ Downloaded voice: \(voice.id)")
    }

    /// Download a file with progress tracking
    private func downloadFile(from url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VoiceError.downloadFailed(reason: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let expectedLength = httpResponse.expectedContentLength
        var data = Data()
        data.reserveCapacity(expectedLength > 0 ? Int(expectedLength) : 50_000_000)

        var downloadedBytes: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1

            if expectedLength > 0 && downloadedBytes % 100_000 == 0 {
                let progressValue = Double(downloadedBytes) / Double(expectedLength)
                progress(progressValue)
            }
        }

        return data
    }

    /// Generate tokens.txt from phoneme_id_map in .onnx.json
    private func generateTokensFile(from jsonData: Data, to path: URL) throws {
        // Parse the JSON to get phoneme_id_map
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let phonemeIdMap = json["phoneme_id_map"] as? [String: [Int]] else {
            throw VoiceError.extractionFailed(reason: "Missing phoneme_id_map in config")
        }

        // Convert to tokens.txt format: "symbol index" per line
        // Sort by index to maintain order
        let lines = phonemeIdMap
            .compactMap { (symbol, indices) -> (String, Int)? in
                guard let index = indices.first else { return nil }
                return (symbol, index)
            }
            .sorted { $0.1 < $1.1 }
            .map { "\($0.0) \($0.1)" }
            .joined(separator: "\n")

        try lines.write(to: path, atomically: true, encoding: .utf8)
        print("[VoiceManager] Generated tokens.txt with \(phonemeIdMap.count) entries")
    }

    /// Delete a downloaded voice
    func delete(voiceID: String) throws {
        let selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID")

        // Cannot delete active voice
        guard voiceID != selectedVoiceID else {
            throw VoiceError.cannotDeleteActiveVoice
        }

        let voiceDir = voicesDirectory.appendingPathComponent(voiceID)
        guard fileManager.fileExists(atPath: voiceDir.path) else {
            throw VoiceError.voiceNotFound
        }

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
            }
        }
    }
}
