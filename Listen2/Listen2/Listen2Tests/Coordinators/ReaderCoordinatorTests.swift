//
//  ReaderCoordinatorTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

@MainActor
final class ReaderCoordinatorTests: XCTestCase {

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
}
