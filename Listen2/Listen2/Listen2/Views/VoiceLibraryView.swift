//
//  VoiceLibraryView.swift
//  Listen2
//
//  Voice library for browsing and downloading Piper TTS voices
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Sample Audio Player

/// Manages playback of voice sample audio from URLs
@MainActor
class SampleAudioPlayer: ObservableObject {
    @Published var currentlyPlayingVoiceID: String?
    @Published var isLoading: Bool = false

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var observation: NSKeyValueObservation?
    private var endObserver: Any?

    func play(voiceID: String, sampleURL: URL) {
        // Stop current playback if any
        stop()

        // Ensure audio session is active and configured for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[SamplePlayer] Failed to configure audio session: \(error)")
        }

        isLoading = true
        currentlyPlayingVoiceID = voiceID

        // Create player item and player
        playerItem = AVPlayerItem(url: sampleURL)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = 1.0

        // Observe when playback ends
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }

        // Observe when ready to play
        observation = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.player?.play()
                case .failed:
                    self.isLoading = false
                    self.stop()
                default:
                    break
                }
            }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        currentlyPlayingVoiceID = nil
        isLoading = false

        // Clean up observers
        observation?.invalidate()
        observation = nil
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    func togglePlayback(voice: Voice) {
        if currentlyPlayingVoiceID == voice.id {
            stop()
        } else if let sampleURL = voice.sampleURL {
            play(voiceID: voice.id, sampleURL: sampleURL)
        }
    }
}

struct VoiceLibraryView: View {
    @StateObject private var viewModel = VoiceLibraryViewModel()
    @StateObject private var samplePlayer = SampleAudioPlayer()
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation: Voice?
    @State private var errorMessage: String?

    private var currentLanguageDisplayName: String {
        viewModel.availableLanguages
            .first { $0.family == viewModel.filterLanguage }?
            .displayName ?? "English"
    }

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

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
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
                .frame(minHeight: 44) // Minimum touch target
                .accessibilityLabel("Filter by download status")
                .accessibilityValue(viewModel.filterDownloadStatus.displayName)

                // Language filter (required)
                Menu {
                    ForEach(viewModel.availableLanguages, id: \.family) { language in
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
                .frame(minHeight: 44) // Minimum touch target
                .accessibilityLabel("Filter by language")
                .accessibilityValue(currentLanguageDisplayName)

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
                .frame(minHeight: 44) // Minimum touch target
                .accessibilityLabel("Filter by quality")
                .accessibilityValue(viewModel.filterQuality?.capitalized ?? "All")

                // Clear filters
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
                    .frame(minHeight: 44) // Minimum touch target
                    .accessibilityLabel("Clear all filters")
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Voice List

    private var voiceList: some View {
        List {
            // Storage info section
            Section {
                storageInfo
            }

            // Voices grouped by download status
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
                if !viewModel.downloadedVoices.isEmpty {
                    Text("Downloaded")
                }
            }

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
                if !viewModel.filteredAvailableVoices.isEmpty {
                    Text("Available for Download")
                }
            }
        }
        .refreshable {
            await viewModel.refreshCatalog()
        }
    }

    // MARK: - Storage Info

    private var storageInfo: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .font(.system(size: DesignSystem.IconSize.medium))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                    Text("Voice Storage")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("\(viewModel.downloadedVoicesCount) voices • \(formatBytes(viewModel.totalDiskUsage))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Voice Storage: \(viewModel.downloadedVoicesCount) voices using \(formatBytes(viewModel.totalDiskUsage))")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "speaker.wave.3")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .accessibilityHidden(true)

            Text("No Voices Found")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Try adjusting your filters")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No voices found. Try adjusting your filters.")
    }

    // MARK: - Actions

    private func downloadVoice(_ voice: Voice) {
        // Stop any sample playback before starting download
        // (prevents audio distortion from resource contention)
        samplePlayer.stop()

        Task {
            do {
                try await viewModel.download(voice: voice)
                // Announce download completion for VoiceOver users
                UIAccessibility.post(notification: .announcement, argument: "\(voice.name) voice downloaded successfully")
            } catch {
                errorMessage = error.localizedDescription
                // Announce download failure for VoiceOver users
                UIAccessibility.post(notification: .announcement, argument: "Failed to download \(voice.name) voice")
            }
        }
    }

    private func deleteVoice(_ voice: Voice) {
        do {
            try viewModel.delete(voice: voice)
            showingDeleteConfirmation = nil
        } catch {
            errorMessage = error.localizedDescription
            showingDeleteConfirmation = nil
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Voice Row View

struct VoiceRowView: View {
    let voice: Voice
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let isPlayingSample: Bool
    let isLoadingSample: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onPlaySample: () -> Void

    /// Whether this voice has a sample available
    private var hasSample: Bool {
        voice.sampleURL != nil
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Play sample button (if available)
            if hasSample {
                Button(action: onPlaySample) {
                    if isLoadingSample {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: isPlayingSample ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isPlayingSample ? DesignSystem.Colors.error : DesignSystem.Colors.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingSample ? "Stop sample" : "Play sample")
                .accessibilityHint(isPlayingSample ? "Stop playing voice sample" : "Listen to a sample of this voice")
            }

            // Voice info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                // Voice name (capitalized)
                Text(voice.name.capitalized)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                // Language, quality, and size
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(voice.language.displayName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(voice.quality.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("\(voice.sizeMB) MB")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            // Action button
            if isDownloading {
                // Download/extraction progress
                VStack(spacing: DesignSystem.Spacing.xxs) {
                    if downloadProgress >= 0.5 {
                        // Extraction phase - show indeterminate spinner
                        ProgressView()
                            .frame(width: 50, height: 4)
                        Text("Extracting...")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    } else {
                        // Download phase - show progress bar
                        ProgressView(value: downloadProgress, total: 0.5)
                            .frame(width: 50)
                        Text("\(Int(downloadProgress * 200))%")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .accessibilityLabel("Downloading")
                .accessibilityValue(downloadProgress >= 0.5 ? "Extracting" : "\(Int(downloadProgress * 200)) percent")
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
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - View Model

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

// MARK: - Download Status Filter

enum DownloadStatusFilter {
    case all
    case downloaded
    case available

    var displayName: String {
        switch self {
        case .all: return "All Voices"
        case .downloaded: return "Downloaded"
        case .available: return "Available"
        }
    }
}

// MARK: - Preview

#Preview {
    VoiceLibraryView()
}
