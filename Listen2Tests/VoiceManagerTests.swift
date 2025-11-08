//
//  VoiceManagerTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class VoiceManagerTests: XCTestCase {

    var voiceManager: VoiceManager!

    override func setUp() {
        super.setUp()
        voiceManager = VoiceManager()
    }

    override func tearDown() {
        voiceManager = nil
        super.tearDown()
    }

    func testLoadCatalog_LoadsVoices() {
        let catalog = voiceManager.loadCatalog()

        XCTAssertGreaterThan(catalog.voices.count, 0, "Catalog should contain voices")
        XCTAssertEqual(catalog.version, "1.0")
    }

    func testLoadCatalog_ContainsBundledVoice() {
        let catalog = voiceManager.loadCatalog()

        let bundledVoices = catalog.voices.filter { $0.isBundled }
        XCTAssertEqual(bundledVoices.count, 1, "Should have exactly one bundled voice")
        XCTAssertEqual(bundledVoices.first?.id, "en_US-lessac-medium")
    }

    func testAvailableVoices_ReturnsAllVoices() {
        let voices = voiceManager.availableVoices()

        XCTAssertGreaterThan(voices.count, 0)
        XCTAssertTrue(voices.contains { $0.id == "en_US-lessac-medium" })
    }

    func testBundledVoice_ReturnsDefaultVoice() {
        let bundled = voiceManager.bundledVoice()

        XCTAssertEqual(bundled.id, "en_US-lessac-medium")
        XCTAssertTrue(bundled.isBundled)
    }

    func testModelPath_ForBundledVoice_ReturnsPath() {
        let path = voiceManager.modelPath(for: "en_US-lessac-medium")

        XCTAssertNotNil(path, "Bundled voice should have model path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path!.path))
    }

    func testTokensPath_ForBundledVoice_ReturnsPath() {
        let path = voiceManager.tokensPath(for: "en_US-lessac-medium")

        XCTAssertNotNil(path, "Bundled voice should have tokens path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path!.path))
    }

    func testModelPath_ForNonExistentVoice_ReturnsNil() {
        let path = voiceManager.modelPath(for: "nonexistent-voice")

        XCTAssertNil(path, "Non-existent voice should return nil")
    }
}
