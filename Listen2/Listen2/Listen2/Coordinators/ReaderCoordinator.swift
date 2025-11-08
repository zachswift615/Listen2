//
//  ReaderCoordinator.swift
//  Listen2
//

import Foundation
import SwiftUI

@MainActor
final class ReaderCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isOverlayVisible: Bool = false
    @Published var isShowingTOC: Bool = false
    @Published var isShowingQuickSettings: Bool = false

    // MARK: - Private Properties

    private var hideOverlayTask: Task<Void, Never>?

    // MARK: - Lifecycle

    deinit {
        hideOverlayTask?.cancel()
    }

    // MARK: - Overlay Management

    func toggleOverlay() {
        isOverlayVisible.toggle()

        if isOverlayVisible {
            scheduleAutoHide()
        } else {
            cancelAutoHide()
        }
    }

    func dismissOverlay() {
        isOverlayVisible = false
        cancelAutoHide()
    }

    func scheduleAutoHide(after delay: TimeInterval = 3.0) {
        cancelAutoHide()

        hideOverlayTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                dismissOverlay()
            }
        }
    }

    private func cancelAutoHide() {
        hideOverlayTask?.cancel()
        hideOverlayTask = nil
    }

    // MARK: - Sheet Management

    func showTOC() {
        isShowingTOC = true
    }

    func dismissTOC() {
        isShowingTOC = false
    }

    func showQuickSettings() {
        isShowingQuickSettings = true
    }

    func dismissQuickSettings() {
        isShowingQuickSettings = false
    }

    // MARK: - Voice Change Handling

    func changeVoice(
        _ newVoice: AVVoice,
        viewModel: ReaderViewModel
    ) {
        // Capture current state
        let wasPlaying = viewModel.isPlaying
        let currentParagraph = viewModel.currentParagraphIndex

        // Stop immediately
        viewModel.ttsService.stop()

        // Update voice
        viewModel.ttsService.setVoice(newVoice)

        // Restart if was playing
        if wasPlaying {
            viewModel.ttsService.startReading(
                paragraphs: viewModel.document.extractedText,
                from: currentParagraph,
                title: viewModel.document.title
            )
        }

        // Update UI and persist
        viewModel.setVoice(newVoice)  // This now includes persistence
    }

    // MARK: - TOC Navigation

    func navigateToTOCEntry(
        _ entry: TOCEntry,
        viewModel: ReaderViewModel
    ) {
        // Capture playback state
        let wasPlaying = viewModel.isPlaying

        // Stop current playback
        viewModel.ttsService.stop()

        // Jump to paragraph
        viewModel.currentParagraphIndex = entry.paragraphIndex

        // Restart if was playing
        if wasPlaying {
            viewModel.ttsService.startReading(
                paragraphs: viewModel.document.extractedText,
                from: entry.paragraphIndex,
                title: viewModel.document.title
            )
        }

        // Dismiss TOC
        dismissTOC()
    }
}
