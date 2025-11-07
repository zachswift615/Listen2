//
//  ReaderViewModel.swift
//  Listen2
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {

    @Published var currentParagraphIndex: Int
    @Published var currentWordRange: Range<String.Index>?
    @Published var isPlaying: Bool = false
    @Published var playbackRate: Float = 1.0
    @Published var selectedVoice: Voice?

    let document: Document
    let ttsService: TTSService
    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()

    init(document: Document, modelContext: ModelContext) {
        self.document = document
        self.currentParagraphIndex = document.currentPosition
        self.modelContext = modelContext
        self.ttsService = TTSService()

        // Set initial voice
        self.selectedVoice = ttsService.availableVoices().first { $0.language.hasPrefix("en") }

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
                ttsService.startReading(paragraphs: document.extractedText, from: currentParagraphIndex)
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
        selectedVoice = voice
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

    func cleanup() {
        ttsService.stop()
        savePosition()
    }
}
