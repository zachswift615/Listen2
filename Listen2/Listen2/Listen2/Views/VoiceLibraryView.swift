//
//  VoiceLibraryView.swift
//  Listen2
//
//  Voice library for browsing and downloading Piper TTS voices
//

import SwiftUI
import AVFoundation

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

        isLoading = true
        currentlyPlayingVoiceID = voiceID

        // Create player item and player
        playerItem = AVPlayerItem(url: sampleURL)
        player = AVPlayer(playerItem: playerItem)

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
        } else if let sampleURLString = voice.sampleURL,
                  let sampleURL = URL(string: sampleURLString) {
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                filterBar

                // Voice list
                if viewModel.filteredVoices.isEmpty {
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
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .background(DesignSystem.Colors.primary.opacity(0.2))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }

                // Gender filter
                Menu {
                    Button("All Genders") {
                        viewModel.filterGender = nil
                    }
                    Button("Female") {
                        viewModel.filterGender = "female"
                    }
                    Button("Male") {
                        viewModel.filterGender = "male"
                    }
                } label: {
                    Label(
                        viewModel.filterGender?.capitalized ?? "All Genders",
                        systemImage: "person.fill"
                    )
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .background(DesignSystem.Colors.primary.opacity(0.2))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }

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
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .background(DesignSystem.Colors.primary.opacity(0.2))
                    .cornerRadius(DesignSystem.CornerRadius.round)
                }

                // Clear filters
                if viewModel.hasActiveFilters {
                    Button(action: {
                        viewModel.clearFilters()
                    }) {
                        Text("Clear")
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xxs)
                            .background(Color(.systemGray5))
                            .cornerRadius(DesignSystem.CornerRadius.round)
                    }
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
                ForEach(viewModel.availableVoices) { voice in
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
                if !viewModel.availableVoices.isEmpty {
                    Text("Available for Download")
                }
            }
        }
    }

    // MARK: - Storage Info

    private var storageInfo: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .font(.system(size: DesignSystem.IconSize.medium))

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
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "speaker.wave.3")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Voices Found")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Try adjusting your filters")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }

    // MARK: - Actions

    private func downloadVoice(_ voice: Voice) {
        Task {
            do {
                try await viewModel.download(voice: voice)
            } catch {
                errorMessage = error.localizedDescription
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
            }

            // Voice info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                // Voice name
                Text(voice.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                // Language and gender
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(voice.language)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(voice.gender.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("\(voice.quality.capitalized) Quality")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                // Size and bundled status
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text("\(voice.sizeMB) MB")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if voice.isBundled {
                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        Text("Bundled")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }

            Spacer()

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
            } else if isDownloaded {
                // Delete button (only for non-bundled voices)
                if !voice.isBundled {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: DesignSystem.IconSize.medium))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
            } else {
                // Download button
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}

// MARK: - View Model

@MainActor
class VoiceLibraryViewModel: ObservableObject {
    @Published var downloadingVoices: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var filterDownloadStatus: DownloadStatusFilter = .all
    @Published var filterGender: String?
    @Published var filterQuality: String?

    private let voiceManager = VoiceManager()
    private var allVoices: [Voice] = []

    init() {
        loadVoices()
    }

    // MARK: - Computed Properties

    var filteredVoices: [Voice] {
        var voices = allVoices

        // Filter by download status
        switch filterDownloadStatus {
        case .all:
            break
        case .downloaded:
            voices = voices.filter { isVoiceDownloaded($0) }
        case .available:
            voices = voices.filter { !isVoiceDownloaded($0) }
        }

        // Filter by gender
        if let gender = filterGender {
            voices = voices.filter { $0.gender == gender }
        }

        // Filter by quality
        if let quality = filterQuality {
            voices = voices.filter { $0.quality == quality }
        }

        return voices
    }

    var downloadedVoices: [Voice] {
        filteredVoices.filter { isVoiceDownloaded($0) }
    }

    var availableVoices: [Voice] {
        filteredVoices.filter { !isVoiceDownloaded($0) }
    }

    var downloadedVoicesCount: Int {
        allVoices.filter { isVoiceDownloaded($0) }.count
    }

    var totalDiskUsage: Int64 {
        voiceManager.diskUsage()
    }

    var hasActiveFilters: Bool {
        filterDownloadStatus != .all || filterGender != nil || filterQuality != nil
    }

    // MARK: - Methods

    func loadVoices() {
        allVoices = voiceManager.availableVoices()
    }

    func download(voice: Voice) async throws {
        guard !downloadingVoices.contains(voice.id) else { return }

        downloadingVoices.insert(voice.id)
        downloadProgress[voice.id] = 0.0

        defer {
            downloadingVoices.remove(voice.id)
            downloadProgress.removeValue(forKey: voice.id)
        }

        try await voiceManager.download(voiceID: voice.id) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress[voice.id] = progress
            }
        }

        // Reload voices after download
        loadVoices()
    }

    func delete(voice: Voice) throws {
        try voiceManager.delete(voiceID: voice.id)
        loadVoices()
    }

    func clearFilters() {
        filterDownloadStatus = .all
        filterGender = nil
        filterQuality = nil
    }

    // MARK: - Helpers

    private func isVoiceDownloaded(_ voice: Voice) -> Bool {
        voiceManager.downloadedVoices().contains { $0.id == voice.id }
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
