//
//  ReaderViewModel.swift
//  Listen2
//

import Foundation
import SwiftData
import Combine
import SwiftUI
import PDFKit

@MainActor
final class ReaderViewModel: ObservableObject {

    @Published var currentParagraphIndex: Int
    @Published var currentWordRange: Range<String.Index>?
    @Published var currentSentenceLocation: Int?
    @Published var currentSentenceLength: Int?
    @Published var isPlaying: Bool = false
    @Published var playbackRate: Float = 1.0
    @Published var selectedVoice: AVVoice?
    @Published var tocEntries: [TOCEntry] = []
    @Published var isLoading: Bool = true
    @Published var showUpgradePrompt: Bool = false

    /// Cached highlight level (updated when settings change)
    @Published var effectiveHighlightLevel: HighlightLevel = .word

    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0
    @AppStorage("selectedVoiceId") private var selectedVoiceId: String = ""
    @AppStorage("highlightLevel") private var highlightLevelRaw: String = ""

    let document: Document
    let ttsService: TTSService
    private let modelContext: ModelContext
    private let purchaseManager: PurchaseManager
    private let tocService = TOCService()
    private var cancellables = Set<AnyCancellable>()

    init(document: Document, modelContext: ModelContext, ttsService: TTSService, purchaseManager: PurchaseManager = .shared) {
        self.document = document
        self.currentParagraphIndex = document.currentPosition
        self.modelContext = modelContext
        self.ttsService = ttsService
        self.purchaseManager = purchaseManager

        // Set initial playback rate from defaults
        self.playbackRate = Float(defaultPlaybackRate)
        ttsService.setPlaybackRate(Float(defaultPlaybackRate))

        // Set initial voice from saved preference or default to first English voice
        if !selectedVoiceId.isEmpty,
           let savedVoice = ttsService.availableVoices().first(where: { $0.id == selectedVoiceId }) {
            self.selectedVoice = savedVoice
            ttsService.setVoice(savedVoice)
        } else {
            self.selectedVoice = ttsService.availableVoices().first { $0.language.hasPrefix("en") }
        }

        // Set initial highlight level from AppStorage, or use device-recommended default
        if let savedLevel = HighlightLevel(rawValue: highlightLevelRaw) {
            self.effectiveHighlightLevel = savedLevel
        } else {
            self.effectiveHighlightLevel = DeviceCapabilityService.recommendedHighlightLevel
        }

        // Delay bindings to avoid publishing during view init
        Task { @MainActor in
            setupBindings()
        }
    }

    private func setupBindings() {
        // Subscribe to TTS service updates
        // Use dropFirst() to skip initial value and preserve saved position
        ttsService.$currentProgress
            .dropFirst()
            .sink { [weak self] progress in
                self?.currentParagraphIndex = progress.paragraphIndex
                self?.currentWordRange = progress.wordRange
            }
            .store(in: &cancellables)

        // Update isPlaying state immediately
        ttsService.$isPlaying
            .assign(to: &$isPlaying)

        // Save position when playback pauses (skip initial emission)
        ttsService.$isPlaying
            .dropFirst()
            .sink { [weak self] isPlaying in
                if !isPlaying {
                    self?.savePosition()
                }
            }
            .store(in: &cancellables)

        ttsService.$playbackRate
            .assign(to: &$playbackRate)

        // Subscribe to sentence range for sentence-level highlighting
        ttsService.$currentSentenceLocation
            .sink { [weak self] location in
                self?.currentSentenceLocation = location
            }
            .store(in: &cancellables)

        ttsService.$currentSentenceLength
            .sink { [weak self] length in
                self?.currentSentenceLength = length
            }
            .store(in: &cancellables)
    }

    /// Attempt to start playback, showing upgrade prompt if trial expired
    func attemptPlay() {
        if purchaseManager.entitlementState.canUseTTS {
            togglePlayPause()
        } else {
            showUpgradePrompt = true
        }
    }

    func togglePlayPause() {
        if isPlaying {
            ttsService.pause()
        } else {
            if ttsService.currentProgress.paragraphIndex == 0 && ttsService.currentProgress.wordRange == nil {
                // First play - pass word map and document ID if available
                ttsService.startReading(
                    paragraphs: document.extractedText,
                    from: currentParagraphIndex,
                    title: document.title,
                    wordMap: document.wordMap,
                    documentID: document.id
                )
            } else {
                ttsService.resume()
            }
        }
    }

    func skipForward() {
        ttsService.skipToNext()
    }

    func skipBackward() {
        ttsService.skipToPrevious()
    }

    func setPlaybackRate(_ rate: Float) {
        ttsService.setPlaybackRate(rate)
    }

    func setVoice(_ voice: AVVoice) {
        // Just update the selected voice
        // Coordinator will handle the stop/restart logic
        selectedVoice = voice
        selectedVoiceId = voice.id  // Persist selection
        ttsService.setVoice(voice)
    }

    func savePosition() {
        document.currentPosition = currentParagraphIndex
        document.lastRead = Date()

        do {
            try modelContext.save()
        } catch {
            // Error saving position
        }
    }

    func loadTOC() {
        // First, try to load from stored TOC data
        if let tocData = document.tocEntriesData {
            let decoder = JSONDecoder()
            if let entries = try? decoder.decode([TOCEntry].self, from: tocData) {
                // Validate stored TOC against current document (sanity check)
                let totalParagraphs = document.extractedText.count
                let invalidEntries = entries.filter { $0.paragraphIndex >= totalParagraphs }

                if invalidEntries.isEmpty {
                    // Stored TOC is valid for this document
                    tocEntries = entries
                    isLoading = false
                    return
                } else {
                    // Stored TOC is stale (from different version of document)
                    // Fall through to re-extract TOC
                }
            }
        }

        // Try to load TOC from PDF if available
        if document.sourceType == .pdf {
            if let pdfURL = document.fileURL {
                // Try loading PDF data first (works better with File Provider Storage)
                do {
                    let pdfData = try Data(contentsOf: pdfURL)

                    if let pdfDocument = PDFDocument(data: pdfData) {
                        let entries = tocService.extractTOCFromMetadata(pdfDocument, paragraphs: document.extractedText)

                        if !entries.isEmpty {
                            tocEntries = entries
                            isLoading = false
                            return
                        }
                    }
                } catch {
                    // Failed to load PDF data
                }
            }
        }

        // Fallback to heading detection
        let detectedEntries = tocService.detectHeadingsFromParagraphs(document.extractedText)
        tocEntries = detectedEntries
        isLoading = false
    }

    func cleanup() {
        savePosition()  // Save correct position BEFORE stopping
        cancellables.removeAll()  // Cancel subscriptions so TTS reset doesn't overwrite position
        ttsService.stop()
    }
}
