# All Piper Voices Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable downloading any of 130+ Piper voices by fetching the catalog dynamically from Hugging Face.

**Architecture:** Fetch `voices.json` from HF at runtime, download `.onnx` + `.onnx.json` files directly (no tar.bz2), generate `tokens.txt` from JSON, use bundled espeak-ng-data for all languages.

**Tech Stack:** Swift, SwiftUI, URLSession, Codable, sherpa-onnx

**Design Doc:** `docs/plans/2025-12-05-all-piper-voices-design.md`

---

## Task 1: Update Voice Model for Hugging Face Schema

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Models/Voice.swift`

**Step 1: Replace Voice struct with HF-compatible version**

Replace the entire contents of `Voice.swift`:

```swift
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
        let totalBytes = files.values.reduce(0) { $0 + $1.sizeBytes }
        return Int(ceil(Double(totalBytes) / 1_000_000))
    }

    /// Display name for UI (e.g., "Amy (Low Quality)")
    var displayName: String {
        "\(name.capitalized) (\(quality.capitalized) Quality)"
    }

    /// Sample audio URL from piper-samples repo
    var sampleURL: URL? {
        let base = "https://raw.githubusercontent.com/rhasspy/piper-samples/master/samples"
        let urlString = "\(base)/\(language.family)/\(language.code)/\(name)/\(quality)/speaker_0.mp3"
        return URL(string: urlString)
    }

    /// URLs to download from Hugging Face (onnx and json files)
    var downloadURLs: [URL] {
        let base = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
        return files.keys.compactMap { path in
            URL(string: "\(base)/\(path)")
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
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | head -50`

Expected: Build errors in VoiceManager and VoiceLibraryView (they use old Voice fields) - this is expected, we'll fix in next tasks.

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Models/Voice.swift
git commit -m "feat: update Voice model for Hugging Face schema"
```

---

## Task 2: Update VoiceManager - Remote Catalog Fetching

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/Voice/VoiceManager.swift`

**Step 1: Add remote catalog fetching to VoiceManager**

Add these properties and methods to VoiceManager (add after the existing properties, before `// MARK: - Storage Paths`):

```swift
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
```

**Step 2: Update existing loadCatalog() to be sync wrapper**

Replace the existing `loadCatalog()` method:

```swift
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
```

**Step 3: Update catalog property type**

Change the catalog property from `VoiceCatalog?` to `[Voice]?`:

```swift
    private var catalog: [Voice]?
```

**Step 4: Build to check progress**

Run: `xcodebuild -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | head -100`

Expected: Still has errors (availableVoices, downloadedVoices need updates)

**Step 5: Commit work in progress**

```bash
git add Listen2/Listen2/Listen2/Services/Voice/VoiceManager.swift
git commit -m "feat: add remote catalog fetching from Hugging Face"
```

---

## Task 3: Update VoiceManager - New Download Logic

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/Voice/VoiceManager.swift`

**Step 1: Replace the download method**

Replace the existing `download(voiceID:progress:)` method with this new implementation:

```swift
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
```

**Step 2: Update availableVoices and downloadedVoices methods**

Replace these methods:

```swift
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
```

**Step 3: Remove bundledVoice() method and isBundled references**

Remove the `bundledVoice()` method (no longer needed - we don't have a bundled voice in the new system).

**Step 4: Update tokensPath to check voice-specific tokens first**

The existing `tokensPath` method should work, but let's verify it checks the voice directory:

```swift
    /// Get tokens.txt path for voice
    func tokensPath(for voiceID: String) -> URL? {
        // Check voice-specific tokens first (downloaded voices)
        let downloadedPath = voicesDirectory
            .appendingPathComponent(voiceID)
            .appendingPathComponent("tokens.txt")

        if fileManager.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }

        // Fallback to bundled tokens (for bundled voice only)
        if let bundledPath = bundle.url(forResource: "tokens", withExtension: "txt") {
            return bundledPath
        }

        return nil
    }
```

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/Voice/VoiceManager.swift
git commit -m "feat: implement HuggingFace direct download with tokens.txt generation"
```

---

## Task 4: Update VoiceLibraryViewModel

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Views/VoiceLibraryView.swift`

**Step 1: Update VoiceLibraryViewModel for async catalog and language filter**

Replace the `VoiceLibraryViewModel` class:

```swift
@MainActor
class VoiceLibraryViewModel: ObservableObject {
    @Published var allVoices: [Voice] = []
    @Published var isLoadingCatalog: Bool = true
    @Published var downloadingVoices: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var filterDownloadStatus: DownloadStatusFilter = .all
    @Published var filterLanguage: String = "en"  // Required, defaults to English
    @Published var filterQuality: String?

    private let voiceManager = VoiceManager()

    init() {
        Task {
            await loadVoices()
        }
    }

    // MARK: - Computed Properties

    /// All unique languages from catalog
    var availableLanguages: [VoiceLanguage] {
        let languages = Set(allVoices.map { $0.language })
        return Array(languages).sorted { $0.nameEnglish < $1.nameEnglish }
    }

    /// Voices filtered by language and quality (for "Available" section)
    var filteredAvailableVoices: [Voice] {
        var voices = allVoices.filter { !isVoiceDownloaded($0) }

        // Filter by language (required)
        voices = voices.filter { $0.language.family == filterLanguage }

        // Filter by quality (optional)
        if let quality = filterQuality {
            voices = voices.filter { $0.quality == quality }
        }

        // Filter by download status
        if filterDownloadStatus == .downloaded {
            return []  // Show none in available when filtering to downloaded only
        }

        return voices.sorted { $0.name < $1.name }
    }

    /// All downloaded voices (ignores language filter)
    var downloadedVoices: [Voice] {
        var voices = allVoices.filter { isVoiceDownloaded($0) }

        // Filter by download status
        if filterDownloadStatus == .available {
            return []  // Show none in downloaded when filtering to available only
        }

        // Optionally filter by quality
        if let quality = filterQuality {
            voices = voices.filter { $0.quality == quality }
        }

        return voices.sorted { $0.name < $1.name }
    }

    var downloadedVoicesCount: Int {
        allVoices.filter { isVoiceDownloaded($0) }.count
    }

    var totalDiskUsage: Int64 {
        voiceManager.diskUsage()
    }

    var hasActiveFilters: Bool {
        filterDownloadStatus != .all || filterQuality != nil
        // Note: language filter is always active, so not included here
    }

    // MARK: - Methods

    func loadVoices() async {
        isLoadingCatalog = true
        allVoices = await voiceManager.loadCatalogAsync()
        isLoadingCatalog = false
    }

    func refreshCatalog() async {
        isLoadingCatalog = true
        // Force refresh by clearing cache (optional - could add a method for this)
        allVoices = await voiceManager.loadCatalogAsync()
        isLoadingCatalog = false
    }

    func download(voice: Voice) async throws {
        guard !downloadingVoices.contains(voice.id) else { return }

        downloadingVoices.insert(voice.id)
        downloadProgress[voice.id] = 0.0

        defer {
            downloadingVoices.remove(voice.id)
            downloadProgress.removeValue(forKey: voice.id)
        }

        try await voiceManager.download(voice: voice) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress[voice.id] = progress
            }
        }

        // Reload to update downloaded status
        await loadVoices()
    }

    func delete(voice: Voice) throws {
        try voiceManager.delete(voiceID: voice.id)
        // Reload to update
        Task {
            await loadVoices()
        }
    }

    func clearFilters() {
        filterDownloadStatus = .all
        filterQuality = nil
        // Don't clear language - it's always required
    }

    // MARK: - Helpers

    private func isVoiceDownloaded(_ voice: Voice) -> Bool {
        voiceManager.isVoiceDownloaded(voice.id)
    }
}
```

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/VoiceLibraryView.swift
git commit -m "feat: update VoiceLibraryViewModel for async catalog and language filter"
```

---

## Task 5: Update VoiceLibraryView UI

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Views/VoiceLibraryView.swift`

**Step 1: Update filter bar to use language instead of gender**

Replace the `filterBar` computed property:

```swift
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                // Language filter (required)
                Menu {
                    ForEach(viewModel.availableLanguages, id: \.code) { language in
                        Button(language.displayName) {
                            viewModel.filterLanguage = language.family
                        }
                    }
                } label: {
                    Label(
                        currentLanguageDisplayName,
                        systemImage: "globe"
                    )
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.primary.opacity(0.3))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Filter by language")
                .accessibilityValue(currentLanguageDisplayName)

                // Download status filter
                Menu {
                    Button("All Voices") {
                        viewModel.filterDownloadStatus = .all
                    }
                    Button("Downloaded") {
                        viewModel.filterDownloadStatus = .downloaded
                    }
                    Button("Available") {
                        viewModel.filterDownloadStatus = .available
                    }
                } label: {
                    Label(
                        viewModel.filterDownloadStatus.displayName,
                        systemImage: "arrow.down.circle.fill"
                    )
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.primary.opacity(0.2))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Filter by download status")
                .accessibilityValue(viewModel.filterDownloadStatus.displayName)

                // Quality filter
                Menu {
                    Button("All Quality") {
                        viewModel.filterQuality = nil
                    }
                    Button("High") {
                        viewModel.filterQuality = "high"
                    }
                    Button("Medium") {
                        viewModel.filterQuality = "medium"
                    }
                    Button("Low") {
                        viewModel.filterQuality = "low"
                    }
                } label: {
                    Label(
                        viewModel.filterQuality?.capitalized ?? "All Quality",
                        systemImage: "waveform"
                    )
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.primary.opacity(0.2))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Filter by quality")
                .accessibilityValue(viewModel.filterQuality?.capitalized ?? "All")

                // Clear filters (only shows if non-default filters active)
                if viewModel.hasActiveFilters {
                    Button(action: {
                        viewModel.clearFilters()
                    }) {
                        Text("Clear")
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(Color(.systemGray5))
                            .cornerRadius(DesignSystem.CornerRadius.round)
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear filters")
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .background(DesignSystem.Colors.background)
    }

    /// Display name for currently selected language
    private var currentLanguageDisplayName: String {
        viewModel.availableLanguages
            .first { $0.family == viewModel.filterLanguage }?
            .displayName ?? "English"
    }
```

**Step 2: Update voiceList to use new view model properties**

Replace the `voiceList` computed property:

```swift
    private var voiceList: some View {
        List {
            // Storage info section
            Section {
                storageInfo
            }

            // Downloaded voices (all languages)
            if !viewModel.downloadedVoices.isEmpty {
                Section {
                    ForEach(viewModel.downloadedVoices) { voice in
                        VoiceRowView(
                            voice: voice,
                            isDownloaded: true,
                            isDownloading: viewModel.downloadingVoices.contains(voice.id),
                            downloadProgress: viewModel.downloadProgress[voice.id] ?? 0.0,
                            isPlayingSample: samplePlayer.currentlyPlayingVoiceID == voice.id,
                            isLoadingSample: samplePlayer.isLoading && samplePlayer.currentlyPlayingVoiceID == voice.id,
                            onDownload: { downloadVoice(voice) },
                            onDelete: { showingDeleteConfirmation = voice },
                            onPlaySample: { samplePlayer.togglePlayback(voice: voice) }
                        )
                    }
                } header: {
                    Text("Downloaded")
                }
            }

            // Available voices (filtered by language)
            if !viewModel.filteredAvailableVoices.isEmpty {
                Section {
                    ForEach(viewModel.filteredAvailableVoices) { voice in
                        VoiceRowView(
                            voice: voice,
                            isDownloaded: false,
                            isDownloading: viewModel.downloadingVoices.contains(voice.id),
                            downloadProgress: viewModel.downloadProgress[voice.id] ?? 0.0,
                            isPlayingSample: samplePlayer.currentlyPlayingVoiceID == voice.id,
                            isLoadingSample: samplePlayer.isLoading && samplePlayer.currentlyPlayingVoiceID == voice.id,
                            onDownload: { downloadVoice(voice) },
                            onDelete: { showingDeleteConfirmation = voice },
                            onPlaySample: { samplePlayer.togglePlayback(voice: voice) }
                        )
                    }
                } header: {
                    Text("Available for Download")
                }
            }
        }
        .refreshable {
            await viewModel.refreshCatalog()
        }
    }
```

**Step 3: Add loading state to body**

Update the body to show loading state:

```swift
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                if !viewModel.isLoadingCatalog {
                    filterBar
                }

                // Voice list or loading
                if viewModel.isLoadingCatalog {
                    ProgressView("Loading voices...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredAvailableVoices.isEmpty && viewModel.downloadedVoices.isEmpty {
                    emptyState
                } else {
                    voiceList
                }
            }
            .navigationTitle("Voice Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .confirmationDialog(
                "Delete Voice",
                isPresented: .constant(showingDeleteConfirmation != nil),
                presenting: showingDeleteConfirmation
            ) { voice in
                Button("Delete", role: .destructive) {
                    deleteVoice(voice)
                }
                Button("Cancel", role: .cancel) {
                    showingDeleteConfirmation = nil
                }
            } message: { voice in
                Text("Delete '\(voice.displayName)'? This will free \(voice.sizeMB) MB of storage.")
            }
        }
    }
```

**Step 4: Update VoiceRowView to remove isBundled check**

In `VoiceRowView`, update the action button section to remove bundled voice handling:

```swift
            // Action button
            if isDownloading {
                // Download progress
                VStack(spacing: DesignSystem.Spacing.xxs) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 50)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .accessibilityLabel("Downloading")
                .accessibilityValue("\(Int(downloadProgress * 100)) percent")
            } else if isDownloaded {
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                .accessibilityLabel("Delete voice")
                .accessibilityHint("Remove this voice from device")
            } else {
                // Download button
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                .accessibilityLabel("Download voice")
                .accessibilityHint("Download this voice to use it")
            }
```

**Step 5: Update VoiceRowView to use new Voice properties**

Update the voice info display in VoiceRowView to remove gender:

```swift
            // Voice info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                // Voice name
                Text(voice.name.capitalized)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                // Language and quality
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(voice.language.displayName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("\(voice.quality.capitalized) Quality")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                // Size
                Text("\(voice.sizeMB) MB")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
```

**Step 6: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/VoiceLibraryView.swift
git commit -m "feat: update VoiceLibraryView with language filter and HF support"
```

---

## Task 6: Update Sample Player for new Voice model

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Views/VoiceLibraryView.swift`

**Step 1: Update SampleAudioPlayer.togglePlayback**

The `togglePlayback` method should work with the new Voice model since we added `sampleURL` as a computed property. Verify it works:

```swift
    func togglePlayback(voice: Voice) {
        if currentlyPlayingVoiceID == voice.id {
            stop()
        } else if let sampleURL = voice.sampleURL {
            play(voiceID: voice.id, sampleURL: sampleURL)
        }
    }
```

**Step 2: Build and test**

Run: `xcodebuild -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit if any changes**

```bash
git add -A
git commit -m "fix: ensure sample player works with new Voice model" --allow-empty
```

---

## Task 7: Clean Up Old Code

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/Voice/VoiceManager.swift`
- Delete or update: Voice catalog JSON

**Step 1: Remove DownloadProgressDelegate class**

The old `DownloadProgressDelegate` class is no longer needed since we use async/await. Remove it from VoiceManager.swift (lines 14-48 approximately).

**Step 2: Remove old tar.bz2 extraction code**

Remove any remaining references to SWCompression or tar.bz2 handling.

**Step 3: Update delete method to not check for bundled**

```swift
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
```

**Step 4: Remove VoiceError.cannotDeleteBundledVoice**

Remove from the enum since we no longer have bundled voices that can't be deleted.

**Step 5: Build and verify**

Run: `xcodebuild -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' build`

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove old tar.bz2 download code and bundled voice handling"
```

---

## Task 8: Test End-to-End

**Step 1: Run the app in simulator**

1. Build and run in Xcode
2. Open Voice Library
3. Verify catalog loads (should see 100+ voices)
4. Select different languages
5. Try downloading a voice
6. Verify it plays correctly

**Step 2: Test offline behavior**

1. Enable airplane mode in simulator
2. Open Voice Library
3. Verify cached catalog is used
4. Verify downloaded voices still work

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "test: verify all-piper-voices integration works end-to-end"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Update Voice model | Voice.swift |
| 2 | Add remote catalog fetching | VoiceManager.swift |
| 3 | Implement HF direct download | VoiceManager.swift |
| 4 | Update ViewModel | VoiceLibraryView.swift |
| 5 | Update UI with language filter | VoiceLibraryView.swift |
| 6 | Verify sample player | VoiceLibraryView.swift |
| 7 | Clean up old code | VoiceManager.swift |
| 8 | End-to-end testing | Manual testing |
