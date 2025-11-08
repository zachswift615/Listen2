//
//  SampleContentIntegrationTests.swift
//  Listen2UITests
//
//  Integration tests for sample content import and TTS playback
//

import XCTest

final class SampleContentIntegrationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Reset app state for clean test
        app.launchArguments = ["--reset-for-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sample Content Import Tests

    @MainActor
    func testSampleContentImport() throws {
        // Verify we're on the empty library screen
        let emptyStateTitle = app.staticTexts["No Documents"]
        XCTAssertTrue(emptyStateTitle.waitForExistence(timeout: 5), "Empty state should be visible")

        // Find and tap the "Try Sample Content" button
        let sampleContentButton = app.buttons["Try Sample Content"]
        XCTAssertTrue(sampleContentButton.exists, "Sample content button should exist")
        sampleContentButton.tap()

        // Wait for processing to complete
        let processingIndicator = app.staticTexts["Processing..."]
        if processingIndicator.waitForExistence(timeout: 2) {
            // Wait for processing to finish
            let timeout: TimeInterval = 10
            let startTime = Date()
            while processingIndicator.exists && Date().timeIntervalSince(startTime) < timeout {
                sleep(1)
            }
        }

        // Verify documents appear in library
        // Should have both "Welcome to Listen2" and "Alice's Adventures in Wonderland"
        let welcomeDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Welcome'")).firstMatch
        let aliceDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch

        XCTAssertTrue(welcomeDocument.waitForExistence(timeout: 5), "Welcome document should appear")
        XCTAssertTrue(aliceDocument.waitForExistence(timeout: 5), "Alice document should appear")
    }

    // MARK: - TTS Playback Tests

    @MainActor
    func testOpenSampleDocument() throws {
        // First import sample content
        importSampleContent()

        // Open the Welcome document
        let welcomeDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Welcome'")).firstMatch
        XCTAssertTrue(welcomeDocument.waitForExistence(timeout: 5), "Welcome document should exist")
        welcomeDocument.tap()

        // Verify reader view opens
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Reader view should open")

        // Verify playback controls are visible
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play'")).firstMatch
        XCTAssertTrue(playButton.exists, "Play button should be visible")
    }

    @MainActor
    func testPlayPauseTTS() throws {
        // Import content and open document
        importSampleContent()
        openWelcomeDocument()

        // Find and tap play button
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play.circle.fill'")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 3), "Play button should exist")
        playButton.tap()

        // Wait for playback to start (button should change to pause)
        sleep(2)
        let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'pause.circle.fill'")).firstMatch
        XCTAssertTrue(pauseButton.exists, "Pause button should appear when playing")

        // Tap pause
        pauseButton.tap()
        sleep(1)

        // Play button should reappear
        XCTAssertTrue(playButton.exists, "Play button should reappear after pause")
    }

    @MainActor
    func testSkipForward() throws {
        // Import content and open document
        importSampleContent()
        openAliceDocument() // Use Alice document as it has more paragraphs

        // Start playback
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play.circle.fill'")).firstMatch
        playButton.tap()
        sleep(2)

        // Get current paragraph (should be highlighted)
        // Note: We can't easily verify paragraph index in UI tests, but we can verify the skip button works

        // Tap skip forward button
        let skipForwardButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'forward.fill'")).firstMatch
        XCTAssertTrue(skipForwardButton.exists, "Skip forward button should exist")
        skipForwardButton.tap()

        // Verify playback continues (pause button still visible)
        sleep(1)
        let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'pause.circle.fill'")).firstMatch
        XCTAssertTrue(pauseButton.exists, "Should still be playing after skip forward")
    }

    @MainActor
    func testSkipBackward() throws {
        // Import content and open document
        importSampleContent()
        openAliceDocument()

        // Start playback
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play.circle.fill'")).firstMatch
        playButton.tap()
        sleep(2)

        // Skip forward first
        let skipForwardButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'forward.fill'")).firstMatch
        skipForwardButton.tap()
        sleep(1)

        // Now skip backward
        let skipBackwardButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'backward.fill'")).firstMatch
        XCTAssertTrue(skipBackwardButton.exists, "Skip backward button should exist")
        skipBackwardButton.tap()

        // Verify playback continues
        sleep(1)
        let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'pause.circle.fill'")).firstMatch
        XCTAssertTrue(pauseButton.exists, "Should still be playing after skip backward")
    }

    @MainActor
    func testPlaybackSpeedAdjustment() throws {
        // Import content and open document
        importSampleContent()
        openWelcomeDocument()

        // Verify speed slider exists
        let speedSliders = app.sliders
        XCTAssertTrue(speedSliders.count > 0, "Speed slider should exist")

        // Verify speed label exists (shows current speed)
        let speedLabels = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'x'"))
        XCTAssertTrue(speedLabels.count > 0, "Speed label should exist")

        // Start playback
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play.circle.fill'")).firstMatch
        playButton.tap()
        sleep(2)

        // Adjust speed (increase)
        let slider = speedSliders.firstMatch
        slider.adjust(toNormalizedSliderPosition: 0.8) // Should be around 2.0x speed

        // Wait for adjustment to take effect
        sleep(2)

        // Verify playback continues at new speed
        let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'pause.circle.fill'")).firstMatch
        XCTAssertTrue(pauseButton.exists, "Should still be playing after speed adjustment")
    }

    @MainActor
    func testVoiceSelection() throws {
        // Import content and open document
        importSampleContent()
        openWelcomeDocument()

        // Find voice picker button
        let voiceButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Voice' OR label CONTAINS 'waveform'")).firstMatch
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 3), "Voice picker button should exist")
        voiceButton.tap()

        // Verify voice picker sheet appears
        let voicePickerTitle = app.staticTexts["Select Voice"]
        XCTAssertTrue(voicePickerTitle.waitForExistence(timeout: 2), "Voice picker should open")

        // Verify voices are listed
        let voiceList = app.tables.firstMatch
        XCTAssertTrue(voiceList.exists, "Voice list should exist")
        XCTAssertTrue(voiceList.cells.count > 0, "Should have at least one voice available")

        // Close voice picker
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists, "Done button should exist")
        doneButton.tap()
    }

    @MainActor
    func testReaderViewClose() throws {
        // Import content and open document
        importSampleContent()
        openWelcomeDocument()

        // Start playback
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play.circle.fill'")).firstMatch
        playButton.tap()
        sleep(2)

        // Close reader view
        let closeButton = app.buttons["Close"]
        closeButton.tap()

        // Verify we're back at library
        sleep(1)
        let libraryTitle = app.navigationBars["Library"]
        XCTAssertTrue(libraryTitle.exists, "Should return to library view")

        // Verify documents are still there
        let welcomeDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Welcome'")).firstMatch
        XCTAssertTrue(welcomeDocument.exists, "Documents should still be in library")
    }

    @MainActor
    func testDeleteDocument() throws {
        // Import content
        importSampleContent()

        // Find Welcome document
        let welcomeDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Welcome'")).firstMatch
        XCTAssertTrue(welcomeDocument.waitForExistence(timeout: 5), "Welcome document should exist")

        // Swipe to delete
        welcomeDocument.swipeLeft()

        // Tap delete button
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 2) {
            deleteButton.tap()

            // Verify document is removed
            sleep(1)
            XCTAssertFalse(welcomeDocument.exists, "Document should be deleted")
        }
    }

    // MARK: - Helper Methods

    private func importSampleContent() {
        let sampleContentButton = app.buttons["Try Sample Content"]
        if sampleContentButton.waitForExistence(timeout: 5) {
            sampleContentButton.tap()

            // Wait for import to complete
            let processingIndicator = app.staticTexts["Processing..."]
            if processingIndicator.waitForExistence(timeout: 2) {
                let timeout: TimeInterval = 10
                let startTime = Date()
                while processingIndicator.exists && Date().timeIntervalSince(startTime) < timeout {
                    sleep(1)
                }
            }

            // Additional wait for UI to settle
            sleep(2)
        }
    }

    private func openWelcomeDocument() {
        let welcomeDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Welcome'")).firstMatch
        XCTAssertTrue(welcomeDocument.waitForExistence(timeout: 5), "Welcome document should exist")
        welcomeDocument.tap()

        // Wait for reader to open
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Reader view should open")
        sleep(1)
    }

    private func openAliceDocument() {
        let aliceDocument = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
        XCTAssertTrue(aliceDocument.waitForExistence(timeout: 5), "Alice document should exist")
        aliceDocument.tap()

        // Wait for reader to open
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Reader view should open")
        sleep(1)
    }
}
