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
    @Published var areControlsVisible: Bool = true  // Unified control visibility (starts visible)

    // MARK: - Private Properties

    private var hideOverlayTask: Task<Void, Never>?
    private var autoHideTask: Task<Void, Never>?

    // MARK: - Lifecycle

    deinit {
        hideOverlayTask?.cancel()
        autoHideTask?.cancel()
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
                title: viewModel.document.title,
                wordMap: viewModel.document.wordMap,
                documentID: viewModel.document.id
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
                title: viewModel.document.title,
                wordMap: viewModel.document.wordMap,
                documentID: viewModel.document.id
            )
        }

        // Dismiss TOC
        dismissTOC()
    }

    // MARK: - Paragraph Navigation (Double-tap)

    func navigateToParagraph(
        _ paragraphIndex: Int,
        viewModel: ReaderViewModel
    ) {
        // Stop current playback (this clears all buffers/queues in TTSService)
        viewModel.ttsService.stop()

        // Jump to paragraph
        viewModel.currentParagraphIndex = paragraphIndex

        // Start playback from the new paragraph
        viewModel.ttsService.startReading(
            paragraphs: viewModel.document.extractedText,
            from: paragraphIndex,
            title: viewModel.document.title,
            wordMap: viewModel.document.wordMap,
            documentID: viewModel.document.id
        )
    }

    // MARK: - Unified Controls Management

    func toggleControls() {
        areControlsVisible.toggle()
        // No auto-hide - user must tap again to hide controls
    }

    func keepControlsVisible() {
        // No-op - auto-hide is disabled, controls stay visible until user taps
    }

    func scheduleControlsAutoHide(after delay: TimeInterval = 3.0) {
        cancelControlsAutoHide()

        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                areControlsVisible = false
            }
        }
    }

    private func cancelControlsAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
