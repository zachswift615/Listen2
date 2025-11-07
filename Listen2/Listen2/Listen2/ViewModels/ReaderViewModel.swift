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
    @Published var isPlaying: Bool = false
    @Published var playbackRate: Float = 1.0
    @Published var selectedVoice: Voice?
    @Published var tocEntries: [TOCEntry] = []

    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0
    @AppStorage("selectedVoiceId") private var selectedVoiceId: String = ""

    let document: Document
    let ttsService: TTSService
    private let modelContext: ModelContext
    private let tocService = TOCService()
    private var cancellables = Set<AnyCancellable>()

    init(document: Document, modelContext: ModelContext) {
        self.document = document
        self.currentParagraphIndex = document.currentPosition
        self.modelContext = modelContext
        self.ttsService = TTSService()

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

        setupBindings()
    }

    private func setupBindings() {
        // Subscribe to TTS service updates
        ttsService.$currentProgress
            .sink { [weak self] progress in
                self?.currentParagraphIndex = progress.paragraphIndex
                self?.currentWordRange = progress.wordRange
            }
            .store(in: &cancellables)

        ttsService.$isPlaying
            .assign(to: &$isPlaying)

        ttsService.$playbackRate
            .assign(to: &$playbackRate)
    }

    func togglePlayPause() {
        if isPlaying {
            ttsService.pause()
        } else {
            if ttsService.currentProgress.paragraphIndex == 0 && ttsService.currentProgress.wordRange == nil {
                // First play
                ttsService.startReading(paragraphs: document.extractedText, from: currentParagraphIndex, title: document.title)
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

    func setVoice(_ voice: Voice) {
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
            print("Failed to save position: \(error)")
        }
    }

    func loadTOC() {
        // Try to load TOC from PDF if available
        if document.sourceType == .pdf,
           let pdfURL = document.fileURL,
           let pdfDocument = PDFDocument(url: pdfURL) {
            let entries = tocService.extractTOCFromMetadata(pdfDocument)
            if !entries.isEmpty {
                tocEntries = entries
                return
            }
        }

        // Fallback to heading detection
        tocEntries = tocService.detectHeadingsFromParagraphs(document.extractedText)
    }

    func cleanup() {
        ttsService.stop()
        savePosition()
    }
}
