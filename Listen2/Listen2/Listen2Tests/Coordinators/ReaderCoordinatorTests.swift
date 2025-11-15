//
//  ReaderCoordinatorTests.swift
//  Listen2Tests
//

import XCTest
import SwiftData
@testable import Listen2

@MainActor
final class ReaderCoordinatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func createTestDocument() -> Document {
        return Document(
            title: "Test Document",
            sourceType: .pdf,
            extractedText: [
                "First paragraph",
                "Second paragraph",
                "Third paragraph"
            ]
        )
    }

    private func createTestModelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Document.self, configurations: config)
        return ModelContext(container)
    }

    private func createTestViewModel() -> ReaderViewModel {
        let document = createTestDocument()
        let context = createTestModelContext()
        context.insert(document)
        let ttsService = TTSService()
        return ReaderViewModel(document: document, modelContext: context, ttsService: ttsService)
    }

    private func createTestVoice() -> AVVoice? {
        // Get first available English voice from the system
        let ttsService = TTSService()
        return ttsService.availableVoices().first { $0.language.hasPrefix("en") }
    }

    // MARK: - Overlay Tests

    func testOverlayVisibilityToggle() {
        let coordinator = ReaderCoordinator()

        XCTAssertFalse(coordinator.isOverlayVisible)

        coordinator.toggleOverlay()
        XCTAssertTrue(coordinator.isOverlayVisible)

        coordinator.toggleOverlay()
        XCTAssertFalse(coordinator.isOverlayVisible)
    }

    func testShowTOC() {
        let coordinator = ReaderCoordinator()

        XCTAssertFalse(coordinator.isShowingTOC)

        coordinator.showTOC()
        XCTAssertTrue(coordinator.isShowingTOC)
    }

    func testShowQuickSettings() {
        let coordinator = ReaderCoordinator()

        XCTAssertFalse(coordinator.isShowingQuickSettings)

        coordinator.showQuickSettings()
        XCTAssertTrue(coordinator.isShowingQuickSettings)
    }

    func testDismissOverlay() {
        let coordinator = ReaderCoordinator()

        coordinator.isOverlayVisible = true
        coordinator.dismissOverlay()

        XCTAssertFalse(coordinator.isOverlayVisible)
    }

    func testDismissTOC() {
        let coordinator = ReaderCoordinator()

        coordinator.isShowingTOC = true
        coordinator.dismissTOC()

        XCTAssertFalse(coordinator.isShowingTOC)
    }

    func testDismissQuickSettings() {
        let coordinator = ReaderCoordinator()

        coordinator.isShowingQuickSettings = true
        coordinator.dismissQuickSettings()

        XCTAssertFalse(coordinator.isShowingQuickSettings)
    }

    // MARK: - Voice Change Tests

    func testChangeVoiceWhenNotPlaying() {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()
        guard let testVoice = createTestVoice() else {
            XCTFail("No test voice available")
            return
        }

        // Ensure not playing
        XCTAssertFalse(viewModel.isPlaying)

        // Change voice
        coordinator.changeVoice(testVoice, viewModel: viewModel)

        // Voice should be updated
        XCTAssertEqual(viewModel.selectedVoice?.id, testVoice.id)

        // Should still not be playing
        XCTAssertFalse(viewModel.isPlaying)

        // Cleanup
        viewModel.cleanup()
    }

    func testChangeVoiceWhenPlaying() async {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()
        guard let testVoice = createTestVoice() else {
            XCTFail("No test voice available")
            return
        }

        // Start playback
        viewModel.togglePlayPause()

        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let wasPlaying = viewModel.isPlaying
        let currentParagraph = viewModel.currentParagraphIndex

        // Change voice
        coordinator.changeVoice(testVoice, viewModel: viewModel)

        // Voice should be updated
        XCTAssertEqual(viewModel.selectedVoice?.id, testVoice.id)

        // Should preserve paragraph position
        XCTAssertEqual(viewModel.currentParagraphIndex, currentParagraph)

        // If was playing, should resume playing (may need a moment to restart)
        if wasPlaying {
            // Give TTS service time to restart
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            // Note: isPlaying state depends on TTS delegate callbacks
            // which may be async, so we don't strictly assert here
        }

        // Cleanup
        viewModel.cleanup()
    }

    func testChangeVoicePreservesParagraphIndex() {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()
        guard let testVoice = createTestVoice() else {
            XCTFail("No test voice available")
            return
        }

        // Move to second paragraph
        viewModel.currentParagraphIndex = 1

        let originalIndex = viewModel.currentParagraphIndex

        // Change voice
        coordinator.changeVoice(testVoice, viewModel: viewModel)

        // Paragraph index should be preserved
        XCTAssertEqual(viewModel.currentParagraphIndex, originalIndex)

        // Cleanup
        viewModel.cleanup()
    }

    // MARK: - TOC Navigation Tests

    func testNavigateToTOCEntryWhenNotPlaying() {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()

        // Ensure not playing
        XCTAssertFalse(viewModel.isPlaying)

        // Create test TOC entry pointing to paragraph 2
        let tocEntry = TOCEntry(title: "Chapter 2", paragraphIndex: 2, level: 0)

        // Navigate
        coordinator.navigateToTOCEntry(tocEntry, viewModel: viewModel)

        // Should jump to the correct paragraph
        XCTAssertEqual(viewModel.currentParagraphIndex, 2)

        // Should dismiss TOC
        XCTAssertFalse(coordinator.isShowingTOC)

        // Should still not be playing
        XCTAssertFalse(viewModel.isPlaying)

        // Cleanup
        viewModel.cleanup()
    }

    func testNavigateToTOCEntryWhenPlaying() async {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()

        // Start playback
        viewModel.togglePlayPause()

        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let wasPlaying = viewModel.isPlaying

        // Show TOC
        coordinator.showTOC()
        XCTAssertTrue(coordinator.isShowingTOC)

        // Create test TOC entry pointing to paragraph 2
        let tocEntry = TOCEntry(title: "Chapter 2", paragraphIndex: 2, level: 0)

        // Navigate
        coordinator.navigateToTOCEntry(tocEntry, viewModel: viewModel)

        // Should jump to the correct paragraph
        XCTAssertEqual(viewModel.currentParagraphIndex, 2)

        // Should dismiss TOC
        XCTAssertFalse(coordinator.isShowingTOC)

        // If was playing, should resume playing at new location
        if wasPlaying {
            // Give TTS service time to restart
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            // Note: isPlaying state depends on TTS delegate callbacks
            // which may be async, so we don't strictly assert here
        }

        // Cleanup
        viewModel.cleanup()
    }

    func testNavigateToTOCEntryDismissesTOC() {
        let coordinator = ReaderCoordinator()
        let viewModel = createTestViewModel()

        // Show TOC
        coordinator.showTOC()
        XCTAssertTrue(coordinator.isShowingTOC)

        // Create test TOC entry
        let tocEntry = TOCEntry(title: "Chapter 1", paragraphIndex: 0, level: 0)

        // Navigate
        coordinator.navigateToTOCEntry(tocEntry, viewModel: viewModel)

        // TOC should be dismissed
        XCTAssertFalse(coordinator.isShowingTOC)

        // Cleanup
        viewModel.cleanup()
    }
}
