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
    @Published var selectedVoice: AVVoice?
    @Published var tocEntries: [TOCEntry] = []
    @Published var isLoading: Bool = true

    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0
    @AppStorage("selectedVoiceId") private var selectedVoiceId: String = ""

    let document: Document
    let ttsService: TTSService
    private let modelContext: ModelContext
    private let tocService = TOCService()
    private var cancellables = Set<AnyCancellable>()

    init(document: Document, modelContext: ModelContext, ttsService: TTSService) {
        self.document = document
        self.currentParagraphIndex = document.currentPosition
        self.modelContext = modelContext
        self.ttsService = ttsService

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
            print("Failed to save position: \(error)")
        }
    }

    func loadTOC() {
        print("📖 Loading TOC for: \(document.title)")
        print("📖 Source type: \(document.sourceType)")
        print("📖 File URL: \(document.fileURL?.path ?? "nil")")

        // First, try to load from stored TOC data
        if let tocData = document.tocEntriesData {
            print("📖 Found stored TOC data (\(tocData.count) bytes)")
            let decoder = JSONDecoder()
            if let entries = try? decoder.decode([TOCEntry].self, from: tocData) {
                print("📖 ✅ Decoded \(entries.count) TOC entries from stored data")
                tocEntries = entries
                isLoading = false
                return
            } else {
                print("📖 ⚠️ Failed to decode stored TOC data")
            }
        }

        // Try to load TOC from PDF if available
        if document.sourceType == .pdf {
            print("📖 Document is PDF type")
            if let pdfURL = document.fileURL {
                print("📖 PDF URL exists: \(pdfURL)")

                // Try loading PDF data first (works better with File Provider Storage)
                do {
                    print("📖 Attempting to load PDF data from URL...")
                    let pdfData = try Data(contentsOf: pdfURL)
                    print("📖 ✅ Loaded \(pdfData.count) bytes of PDF data")

                    if let pdfDocument = PDFDocument(data: pdfData) {
                        print("📖 ✅ PDF document created from data!")
                        print("📖 PDF has \(pdfDocument.pageCount) pages")
                        print("📖 PDF outline root: \(pdfDocument.outlineRoot != nil ? "EXISTS ✅" : "nil")")

                        if let outline = pdfDocument.outlineRoot {
                            print("📖 Outline has \(outline.numberOfChildren) top-level entries")
                        }

                        let entries = tocService.extractTOCFromMetadata(pdfDocument, paragraphs: document.extractedText)
                        print("📖 Extracted \(entries.count) entries from PDF metadata")

                        if !entries.isEmpty {
                            tocEntries = entries
                            print("📖 🎉 Using PDF metadata TOC with \(entries.count) entries")
                            isLoading = false
                            return
                        } else {
                            print("📖 ⚠️ PDF outline exists but extracted 0 entries")
                        }
                    } else {
                        print("📖 ❌ Failed to create PDFDocument from data")
                    }
                } catch {
                    print("📖 ❌ Failed to load PDF data: \(error)")
                }
            } else {
                print("📖 ❌ File URL is nil")
            }
        }

        // Fallback to heading detection
        print("📖 Falling back to heading detection...")
        print("📖 Document has \(document.extractedText.count) paragraphs")
        let detectedEntries = tocService.detectHeadingsFromParagraphs(document.extractedText)
        print("📖 Detected \(detectedEntries.count) headings")
        if !detectedEntries.isEmpty {
            for entry in detectedEntries.prefix(5) {
                print("📖   - \(entry.title) (para \(entry.paragraphIndex), level \(entry.level))")
            }
        }
        tocEntries = detectedEntries
        isLoading = false
    }

    func cleanup() {
        ttsService.stop()
        savePosition()
    }
}
