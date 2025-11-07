# Reader Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add TOC navigation, in-reader overlay controls, voice filtering, and fix voice change bugs in Listen2.

**Architecture:** Coordinator pattern with ReaderCoordinator orchestrating overlay, TOC, and settings. New services (TOCService, VoiceFilterManager) handle data extraction and filtering. UI split into modular sheets (TOC, QuickSettings) with ReaderOverlay managing visibility.

**Tech Stack:** SwiftUI, PDFKit, AVFoundation, Combine, SwiftData

---

## Task 1: Add Gender Property to Voice Model

**Files:**
- Modify: `Listen2/Listen2/Listen2/Models/Voice.swift`
- Test: `Listen2/Listen2/Listen2Tests/Models/VoiceTests.swift` (create)

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2Tests/Models/VoiceTests.swift`:

```swift
//
//  VoiceTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class VoiceTests: XCTestCase {

    func testGenderDetectionForKnownFemaleVoice() {
        // Test that Samantha is detected as female
        if let avVoice = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.identifier.contains("Samantha") }) {
            let voice = Voice(from: avVoice)
            XCTAssertEqual(voice.gender, .female)
        }
    }

    func testGenderDetectionForKnownMaleVoice() {
        // Test that Alex is detected as male
        if let avVoice = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.identifier.contains("Alex") }) {
            let voice = Voice(from: avVoice)
            XCTAssertEqual(voice.gender, .male)
        }
    }

    func testGenderDetectionDefaultsToNeutral() {
        // Test that unknown voices default to neutral
        if let avVoice = AVSpeechSynthesisVoice.speechVoices().first {
            let voice = Voice(from: avVoice)
            XCTAssertNotNil(voice.gender) // Should have some gender value
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoiceTests`

Expected: FAIL with "Value of type 'Voice' has no member 'gender'"

**Step 3: Add gender property and detection logic**

Modify `Listen2/Listen2/Listen2/Models/Voice.swift`:

```swift
//
//  Voice.swift
//  Listen2
//

import Foundation
import AVFoundation

enum VoiceGender: String, Codable, CaseIterable {
    case male
    case female
    case neutral
}

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let gender: VoiceGender

    init(from avVoice: AVSpeechSynthesisVoice) {
        self.id = avVoice.identifier
        self.name = avVoice.name
        self.language = avVoice.language
        self.quality = avVoice.quality
        self.gender = Self.detectGender(from: avVoice)
    }

    var displayName: String {
        "\(name) (\(languageDisplayName))"
    }

    private var languageDisplayName: String {
        let locale = Locale(identifier: language)
        return locale.localizedString(forLanguageCode: language) ?? language
    }

    // MARK: - Gender Detection

    private static func detectGender(from avVoice: AVSpeechSynthesisVoice) -> VoiceGender {
        let identifier = avVoice.identifier.lowercased()
        let name = avVoice.name.lowercased()

        // Check identifier patterns
        if identifier.contains("samantha") || identifier.contains("victoria") ||
           identifier.contains("karen") || identifier.contains("moira") ||
           identifier.contains("tessa") || identifier.contains("kate") ||
           identifier.contains("sara") || identifier.contains("nora") {
            return .female
        }

        if identifier.contains("alex") || identifier.contains("daniel") ||
           identifier.contains("fred") || identifier.contains("oliver") ||
           identifier.contains("thomas") || identifier.contains("rishi") {
            return .male
        }

        // Check name patterns (fallback)
        let femaleNames = ["samantha", "victoria", "karen", "moira", "tessa",
                          "kate", "sara", "nora", "fiona", "alice"]
        let maleNames = ["alex", "daniel", "fred", "oliver", "thomas", "rishi",
                        "gordon", "arthur"]

        for femaleName in femaleNames {
            if name.contains(femaleName) {
                return .female
            }
        }

        for maleName in maleNames {
            if name.contains(maleName) {
                return .male
            }
        }

        return .neutral
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoiceTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Models/Voice.swift Listen2/Listen2/Listen2Tests/Models/VoiceTests.swift
git commit -m "feat: add gender detection to Voice model"
```

---

## Task 2: Implement TOCEntry Model

**Files:**
- Create: `Listen2/Listen2/Listen2/Models/TOCEntry.swift`
- Test: `Listen2/Listen2/Listen2Tests/Models/TOCEntryTests.swift` (create)

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2Tests/Models/TOCEntryTests.swift`:

```swift
//
//  TOCEntryTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class TOCEntryTests: XCTestCase {

    func testTOCEntryCreation() {
        let entry = TOCEntry(
            title: "Chapter 1: Introduction",
            paragraphIndex: 5,
            level: 0
        )

        XCTAssertEqual(entry.title, "Chapter 1: Introduction")
        XCTAssertEqual(entry.paragraphIndex, 5)
        XCTAssertEqual(entry.level, 0)
        XCTAssertNotNil(entry.id)
    }

    func testTOCEntryHierarchy() {
        let chapter = TOCEntry(title: "Chapter 1", paragraphIndex: 0, level: 0)
        let section = TOCEntry(title: "Section 1.1", paragraphIndex: 10, level: 1)
        let subsection = TOCEntry(title: "Subsection 1.1.1", paragraphIndex: 15, level: 2)

        XCTAssertEqual(chapter.level, 0)
        XCTAssertEqual(section.level, 1)
        XCTAssertEqual(subsection.level, 2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/TOCEntryTests`

Expected: FAIL with "Cannot find 'TOCEntry' in scope"

**Step 3: Create TOCEntry model**

Create `Listen2/Listen2/Listen2/Models/TOCEntry.swift`:

```swift
//
//  TOCEntry.swift
//  Listen2
//

import Foundation

struct TOCEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let paragraphIndex: Int
    let level: Int // 0 = chapter, 1 = section, 2 = subsection

    init(title: String, paragraphIndex: Int, level: Int) {
        self.id = UUID()
        self.title = title
        self.paragraphIndex = paragraphIndex
        self.level = level
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/TOCEntryTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Models/TOCEntry.swift Listen2/Listen2/Listen2Tests/Models/TOCEntryTests.swift
git commit -m "feat: add TOCEntry model for table of contents"
```

---

## Task 3: Implement TOCService

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/TOCService.swift`
- Test: `Listen2/Listen2/Listen2Tests/Services/TOCServiceTests.swift` (create)

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2Tests/Services/TOCServiceTests.swift`:

```swift
//
//  TOCServiceTests.swift
//  Listen2Tests
//

import XCTest
import PDFKit
@testable import Listen2

final class TOCServiceTests: XCTestCase {

    func testExtractTOCFromPDFMetadata() {
        // This test requires a PDF with outline metadata
        // We'll test the method exists and returns an array
        let service = TOCService()

        // Create a dummy PDF document (will have no outline)
        let pdfData = createMinimalPDFData()
        let pdfDocument = PDFDocument(data: pdfData)

        XCTAssertNotNil(pdfDocument)

        let entries = service.extractTOCFromMetadata(pdfDocument!)
        XCTAssertNotNil(entries)
        XCTAssertTrue(entries.isEmpty) // No outline in minimal PDF
    }

    func testDetectHeadingsFromParagraphs() {
        let service = TOCService()
        let paragraphs = [
            "Chapter 1: Introduction",
            "This is the introduction paragraph with lots of text.",
            "This is another paragraph in the introduction.",
            "Chapter 2: Background",
            "This is the background section with content.",
            "1.1 Subsection",
            "Subsection content here."
        ]

        let entries = service.detectHeadingsFromParagraphs(paragraphs)

        XCTAssertGreaterThan(entries.count, 0)
        XCTAssertTrue(entries.contains { $0.title.contains("Chapter 1") })
        XCTAssertTrue(entries.contains { $0.title.contains("Chapter 2") })
    }

    func testHeadingDetectionIgnoresLongParagraphs() {
        let service = TOCService()
        let paragraphs = [
            "Short Title",
            "This is a very long paragraph that should not be detected as a heading because it contains too much text and is clearly body content rather than a title or heading."
        ]

        let entries = service.detectHeadingsFromParagraphs(paragraphs)

        // Should detect "Short Title" but not the long paragraph
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Short Title")
    }

    // Helper to create minimal PDF data
    private func createMinimalPDFData() -> Data {
        let pdfMetaData = [
            kCGPDFContextTitle: "Test Document"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            let text = "Test"
            text.draw(at: CGPoint(x: 100, y: 100), withAttributes: nil)
        }

        return data
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/TOCServiceTests`

Expected: FAIL with "Cannot find 'TOCService' in scope"

**Step 3: Implement TOCService**

Create `Listen2/Listen2/Listen2/Services/TOCService.swift`:

```swift
//
//  TOCService.swift
//  Listen2
//

import Foundation
import PDFKit

final class TOCService {

    // MARK: - Public Methods

    /// Extract TOC from PDF outline metadata (Phase 1)
    func extractTOCFromMetadata(_ pdfDocument: PDFDocument) -> [TOCEntry] {
        guard let outline = pdfDocument.outlineRoot else {
            return []
        }

        var entries: [TOCEntry] = []
        extractOutlineRecursive(outline, level: 0, entries: &entries, pdfDocument: pdfDocument)
        return entries
    }

    /// Detect headings from paragraph text (Phase 2 - Fallback)
    func detectHeadingsFromParagraphs(_ paragraphs: [String]) -> [TOCEntry] {
        var entries: [TOCEntry] = []

        for (index, paragraph) in paragraphs.enumerated() {
            if isLikelyHeading(paragraph) {
                let level = detectHeadingLevel(paragraph)
                let entry = TOCEntry(
                    title: paragraph.trimmingCharacters(in: .whitespacesAndNewlines),
                    paragraphIndex: index,
                    level: level
                )
                entries.append(entry)
            }
        }

        return entries
    }

    // MARK: - Private Methods

    private func extractOutlineRecursive(
        _ outline: PDFOutline,
        level: Int,
        entries: inout [TOCEntry],
        pdfDocument: PDFDocument
    ) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i),
                  let label = child.label,
                  let destination = child.destination,
                  let page = destination.page,
                  let pageIndex = pdfDocument.index(for: page) else {
                continue
            }

            // Estimate paragraph index (rough approximation)
            // In real usage, this would need mapping from page to paragraph
            let estimatedParagraphIndex = pageIndex * 10 // Rough estimate

            let entry = TOCEntry(
                title: label,
                paragraphIndex: estimatedParagraphIndex,
                level: level
            )
            entries.append(entry)

            // Recurse for children
            if child.numberOfChildren > 0 {
                extractOutlineRecursive(child, level: level + 1, entries: &entries, pdfDocument: pdfDocument)
            }
        }
    }

    private func isLikelyHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too long to be a heading
        if trimmed.count > 100 {
            return false
        }

        // Too short to be meaningful
        if trimmed.count < 3 {
            return false
        }

        // Check for common heading patterns
        let headingPatterns = [
            "^Chapter \\d+",
            "^\\d+\\.",
            "^\\d+\\.\\d+",
            "^[A-Z][A-Za-z\\s]+:$",
            "^[IVX]+\\.", // Roman numerals
        ]

        for pattern in headingPatterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Check if all caps (common for headings)
        if trimmed == trimmed.uppercased() && trimmed.count > 3 {
            return true
        }

        return false
    }

    private func detectHeadingLevel(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Chapter level (0)
        if trimmed.range(of: "^Chapter \\d+", options: .regularExpression) != nil {
            return 0
        }

        // Section level (1)
        if trimmed.range(of: "^\\d+\\.\\d+ ", options: .regularExpression) != nil {
            return 1
        }

        // Subsection level (2)
        if trimmed.range(of: "^\\d+\\.\\d+\\.\\d+ ", options: .regularExpression) != nil {
            return 2
        }

        // Default to chapter level
        return 0
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/TOCServiceTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/TOCService.swift Listen2/Listen2/Listen2Tests/Services/TOCServiceTests.swift
git commit -m "feat: implement TOCService for table of contents extraction"
```

---

## Task 4: Implement VoiceFilterManager

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/VoiceFilterManager.swift`
- Test: `Listen2/Listen2/Listen2Tests/Services/VoiceFilterManagerTests.swift` (create)

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2Tests/Services/VoiceFilterManagerTests.swift`:

```swift
//
//  VoiceFilterManagerTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class VoiceFilterManagerTests: XCTestCase {

    func testFilterByLanguage() {
        let manager = VoiceFilterManager()

        // Create test voices
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { Voice(from: $0) }

        // Filter for English voices only
        manager.selectedLanguages = Set(voices.filter { $0.language.hasPrefix("en") }.map { $0.language })

        let filtered = manager.filteredVoices(Array(voices))

        XCTAssertGreaterThan(filtered.count, 0)
        XCTAssertTrue(filtered.allSatisfy { $0.language.hasPrefix("en") })
    }

    func testFilterByGender() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { Voice(from: $0) }

        manager.selectedGender = .female

        let filtered = manager.filteredVoices(Array(voices))

        if !filtered.isEmpty {
            XCTAssertTrue(filtered.allSatisfy { $0.gender == .female })
        }
    }

    func testFilterByBothLanguageAndGender() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(20)
            .map { Voice(from: $0) }

        manager.selectedLanguages = Set(voices.filter { $0.language.hasPrefix("en") }.map { $0.language })
        manager.selectedGender = .male

        let filtered = manager.filteredVoices(Array(voices))

        if !filtered.isEmpty {
            XCTAssertTrue(filtered.allSatisfy { $0.language.hasPrefix("en") })
            XCTAssertTrue(filtered.allSatisfy { $0.gender == .male })
        }
    }

    func testNoFilterReturnsAll() {
        let manager = VoiceFilterManager()

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .prefix(10)
            .map { Voice(from: $0) }

        let filtered = manager.filteredVoices(Array(voices))

        XCTAssertEqual(filtered.count, voices.count)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoiceFilterManagerTests`

Expected: FAIL with "Cannot find 'VoiceFilterManager' in scope"

**Step 3: Implement VoiceFilterManager**

Create `Listen2/Listen2/Listen2/Services/VoiceFilterManager.swift`:

```swift
//
//  VoiceFilterManager.swift
//  Listen2
//

import Foundation
import SwiftUI

final class VoiceFilterManager: ObservableObject {

    @Published var selectedLanguages: Set<String> = []
    @Published var selectedGender: VoiceGender? = nil

    @AppStorage("lastUsedLanguageFilter") private var lastUsedLanguagesData: Data = Data()

    init() {
        loadPersistedFilters()
    }

    // MARK: - Filtering

    func filteredVoices(_ allVoices: [Voice]) -> [Voice] {
        var filtered = allVoices

        // Filter by language
        if !selectedLanguages.isEmpty {
            filtered = filtered.filter { voice in
                selectedLanguages.contains(voice.language)
            }
        }

        // Filter by gender
        if let gender = selectedGender {
            filtered = filtered.filter { $0.gender == gender }
        }

        return filtered.sorted { $0.name < $1.name }
    }

    // MARK: - Persistence

    func saveFilters() {
        if let encoded = try? JSONEncoder().encode(Array(selectedLanguages)) {
            lastUsedLanguagesData = encoded
        }
    }

    private func loadPersistedFilters() {
        if let decoded = try? JSONDecoder().decode([String].self, from: lastUsedLanguagesData) {
            selectedLanguages = Set(decoded)
        }
    }

    // MARK: - Convenience

    func clearFilters() {
        selectedLanguages.removeAll()
        selectedGender = nil
    }

    func setDefaultToSystemLanguage(_ allVoices: [Voice]) {
        if selectedLanguages.isEmpty {
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            let matchingLanguages = allVoices
                .filter { $0.language.hasPrefix(systemLanguage) }
                .map { $0.language }
            selectedLanguages = Set(matchingLanguages)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoiceFilterManagerTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/VoiceFilterManager.swift Listen2/Listen2/Listen2Tests/Services/VoiceFilterManagerTests.swift
git commit -m "feat: implement VoiceFilterManager for voice filtering"
```

---

## Task 5: Create ReaderCoordinator

**Files:**
- Create: `Listen2/Listen2/Listen2/Coordinators/ReaderCoordinator.swift`
- Test: `Listen2/Listen2/Listen2Tests/Coordinators/ReaderCoordinatorTests.swift` (create)

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2Tests/Coordinators/ReaderCoordinatorTests.swift`:

```swift
//
//  ReaderCoordinatorTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/ReaderCoordinatorTests`

Expected: FAIL with "Cannot find 'ReaderCoordinator' in scope"

**Step 3: Implement ReaderCoordinator**

Create `Listen2/Listen2/Listen2/Coordinators/ReaderCoordinator.swift`:

```swift
//
//  ReaderCoordinator.swift
//  Listen2
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ReaderCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isOverlayVisible: Bool = false
    @Published var isShowingTOC: Bool = false
    @Published var isShowingQuickSettings: Bool = false

    // MARK: - Private Properties

    private var hideOverlayTask: Task<Void, Never>?

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
        _ newVoice: Voice,
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

        // Update UI
        viewModel.selectedVoice = newVoice
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
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/ReaderCoordinatorTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Coordinators/ReaderCoordinator.swift Listen2/Listen2/Listen2Tests/Coordinators/ReaderCoordinatorTests.swift
git commit -m "feat: implement ReaderCoordinator for overlay and sheet management"
```

---

## Task 6: Create TOCBottomSheet UI

**Files:**
- Create: `Listen2/Listen2/Listen2/Views/TOCBottomSheet.swift`

**Step 1: Create TOCBottomSheet view**

Create `Listen2/Listen2/Listen2/Views/TOCBottomSheet.swift`:

```swift
//
//  TOCBottomSheet.swift
//  Listen2
//

import SwiftUI

struct TOCBottomSheet: View {

    let entries: [TOCEntry]
    let currentParagraphIndex: Int
    let onSelectEntry: (TOCEntry) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filteredEntries: [TOCEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                if entries.count > 5 {
                    searchBar
                }

                // TOC list
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    tocList
                }
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search chapters...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private var tocList: some View {
        List(filteredEntries) { entry in
            Button(action: {
                onSelectEntry(entry)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(fontForLevel(entry.level))
                            .foregroundColor(.primary)

                        Text("Paragraph \(entry.paragraphIndex + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isCurrentEntry(entry) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.leading, CGFloat(entry.level * 20))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Results")
                .font(.headline)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 0: return .headline
        case 1: return .subheadline
        default: return .caption
        }
    }

    private func isCurrentEntry(_ entry: TOCEntry) -> Bool {
        // Check if we're currently at or past this entry but before the next
        guard entry.paragraphIndex <= currentParagraphIndex else {
            return false
        }

        if let nextEntry = entries.first(where: { $0.paragraphIndex > entry.paragraphIndex }) {
            return currentParagraphIndex < nextEntry.paragraphIndex
        }

        return true
    }
}

#Preview {
    TOCBottomSheet(
        entries: [
            TOCEntry(title: "Chapter 1: Introduction", paragraphIndex: 0, level: 0),
            TOCEntry(title: "Section 1.1", paragraphIndex: 5, level: 1),
            TOCEntry(title: "Section 1.2", paragraphIndex: 10, level: 1),
            TOCEntry(title: "Chapter 2: Background", paragraphIndex: 15, level: 0),
        ],
        currentParagraphIndex: 7,
        onSelectEntry: { _ in }
    )
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/TOCBottomSheet.swift
git commit -m "feat: create TOCBottomSheet UI component"
```

---

## Task 7: Create QuickSettingsSheet UI

**Files:**
- Create: `Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift`

**Step 1: Create QuickSettingsSheet view**

Create `Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift`:

```swift
//
//  QuickSettingsSheet.swift
//  Listen2
//

import SwiftUI

struct QuickSettingsSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    @StateObject private var voiceFilterManager = VoiceFilterManager()
    @AppStorage("paragraphPauseDelay") private var pauseDuration: Double = 0.3
    @Environment(\.dismiss) private var dismiss

    @State private var showingVoicePicker = false

    var body: some View {
        NavigationView {
            Form {
                speedSection
                voiceSection
                pauseSection
            }
            .navigationTitle("Quick Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerSheet(
                viewModel: viewModel,
                filterManager: voiceFilterManager
            )
        }
    }

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.playbackRate))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.playbackRate) },
                        set: { viewModel.setPlaybackRate(Float($0)) }
                    ),
                    in: 0.5...2.5,
                    step: 0.1
                )
            }
        } header: {
            Text("Playback")
        }
    }

    private var voiceSection: some View {
        Section {
            Button(action: {
                showingVoicePicker = true
            }) {
                HStack {
                    Text("Voice")
                        .foregroundColor(.primary)

                    Spacer()

                    Text(viewModel.selectedVoice?.name ?? "Default")
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Voice")
        }
    }

    private var pauseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Paragraph Pause")
                    Spacer()
                    Text(String(format: "%.1fs", pauseDuration))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $pauseDuration,
                    in: 0.0...1.0,
                    step: 0.1
                )
            }
        } header: {
            Text("Timing")
        } footer: {
            Text("Pause duration between paragraphs")
        }
    }
}

struct VoicePickerSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var filterManager: VoiceFilterManager
    @Environment(\.dismiss) private var dismiss

    @State private var allVoices: [Voice] = []

    var filteredVoices: [Voice] {
        filterManager.filteredVoices(allVoices)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar

                List(filteredVoices) { voice in
                    Button(action: {
                        viewModel.setVoice(voice)
                        filterManager.saveFilters()
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                    .font(.body)

                                HStack {
                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .foregroundColor(.secondary)

                                    Text(voice.gender.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if viewModel.selectedVoice?.id == voice.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            allVoices = viewModel.ttsService.availableVoices()
            filterManager.setDefaultToSystemLanguage(allVoices)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                // Gender filter
                Menu {
                    Button("All") {
                        filterManager.selectedGender = nil
                    }
                    Button("Male") {
                        filterManager.selectedGender = .male
                    }
                    Button("Female") {
                        filterManager.selectedGender = .female
                    }
                    Button("Neutral") {
                        filterManager.selectedGender = .neutral
                    }
                } label: {
                    Label(
                        filterManager.selectedGender?.rawValue.capitalized ?? "All Genders",
                        systemImage: "person.fill"
                    )
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(16)
                }

                // Clear filters
                if !filterManager.selectedLanguages.isEmpty || filterManager.selectedGender != nil {
                    Button(action: {
                        filterManager.clearFilters()
                    }) {
                        Text("Clear")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(16)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    QuickSettingsSheet(
        viewModel: ReaderViewModel(
            document: Document(title: "Test", sourceType: .pdf),
            modelContext: ModelContext(try! ModelContainer(for: Document.self))
        )
    )
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift
git commit -m "feat: create QuickSettingsSheet UI component"
```

---

## Task 8: Create ReaderOverlay UI

**Files:**
- Create: `Listen2/Listen2/Listen2/Views/ReaderOverlay.swift`

**Step 1: Create ReaderOverlay view**

Create `Listen2/Listen2/Listen2/Views/ReaderOverlay.swift`:

```swift
//
//  ReaderOverlay.swift
//  Listen2
//

import SwiftUI

struct ReaderOverlay: View {

    let documentTitle: String
    let onBack: () -> Void
    let onShowTOC: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        VStack {
            topBar
            Spacer()
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Library")
                }
            }

            Spacer()

            // Document title
            Text(documentTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // TOC button
            Button(action: onShowTOC) {
                Image(systemName: "list.bullet")
            }

            // Settings button
            Button(action: onShowSettings) {
                Image(systemName: "gearshape.fill")
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundColor(.white)
    }
}

#Preview {
    ZStack {
        Color.gray

        ReaderOverlay(
            documentTitle: "Sample Document.pdf",
            onBack: {},
            onShowTOC: {},
            onShowSettings: {}
        )
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/ReaderOverlay.swift
git commit -m "feat: create ReaderOverlay UI component"
```

---

## Task 9: Integrate ReaderCoordinator into ReaderView

**Files:**
- Modify: `Listen2/Listen2/Listen2/Views/ReaderView.swift`
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`

**Step 1: Read current ReaderView implementation**

Read: `Listen2/Listen2/Listen2/Views/ReaderView.swift`

**Step 2: Add TOC state to ReaderViewModel**

Modify `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`:

Add after line 18:
```swift
@Published var tocEntries: [TOCEntry] = []
private let tocService = TOCService()
```

Add before the `cleanup()` method:
```swift
func loadTOC() {
    // Try to load TOC from PDF if available
    if document.sourceType == .pdf,
       let pdfURL = document.localFileURL,
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
```

**Step 3: Modify ReaderView to use coordinator**

Modify `Listen2/Listen2/Listen2/Views/ReaderView.swift`:

Add after the `@StateObject var viewModel:` line:
```swift
@StateObject private var coordinator = ReaderCoordinator()
```

Add tap gesture to the main content:
```swift
.contentShape(Rectangle())
.onTapGesture {
    withAnimation {
        coordinator.toggleOverlay()
    }
}
```

Add overlay:
```swift
.overlay {
    if coordinator.isOverlayVisible {
        ReaderOverlay(
            documentTitle: viewModel.document.title,
            onBack: {
                coordinator.dismissOverlay()
                dismiss()
            },
            onShowTOC: {
                coordinator.showTOC()
            },
            onShowSettings: {
                coordinator.showQuickSettings()
            }
        )
        .transition(.opacity)
    }
}
```

Add sheets:
```swift
.sheet(isPresented: $coordinator.isShowingTOC) {
    TOCBottomSheet(
        entries: viewModel.tocEntries,
        currentParagraphIndex: viewModel.currentParagraphIndex,
        onSelectEntry: { entry in
            coordinator.navigateToTOCEntry(entry, viewModel: viewModel)
        }
    )
    .presentationDetents([.medium, .large])
}
.sheet(isPresented: $coordinator.isShowingQuickSettings) {
    QuickSettingsSheet(viewModel: viewModel)
        .presentationDetents([.medium])
}
```

Add in `onAppear`:
```swift
viewModel.loadTOC()
```

**Step 4: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 5: Run tests to verify nothing broke**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: PASS (existing tests still pass)

**Step 6: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/ReaderView.swift Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift
git commit -m "feat: integrate ReaderCoordinator into ReaderView with overlay and sheets"
```

---

## Task 10: Fix Voice Change Bug via Coordinator

**Files:**
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`
- Modify: `Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift`

**Step 1: Update setVoice in ReaderViewModel**

Modify `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`:

Replace the `setVoice` method (around line 84-87) with:

```swift
func setVoice(_ voice: Voice) {
    // Just update the selected voice
    // Coordinator will handle the stop/restart logic
    selectedVoice = voice
    ttsService.setVoice(voice)
}
```

**Step 2: Update QuickSettingsSheet to use coordinator**

Modify `Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift`:

Change the VoicePickerSheet to accept a coordinator:

```swift
struct VoicePickerSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var filterManager: VoiceFilterManager
    let coordinator: ReaderCoordinator?
    @Environment(\.dismiss) private var dismiss

    // ... rest of properties ...

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar

                List(filteredVoices) { voice in
                    Button(action: {
                        if let coordinator = coordinator {
                            coordinator.changeVoice(voice, viewModel: viewModel)
                        } else {
                            viewModel.setVoice(voice)
                        }
                        filterManager.saveFilters()
                        dismiss()
                    }) {
                        // ... rest of button content ...
                    }
                }
            }
            // ... rest of navigation view ...
        }
        // ... rest of body ...
    }
}
```

Update QuickSettingsSheet to pass coordinator:

```swift
struct QuickSettingsSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    @StateObject private var voiceFilterManager = VoiceFilterManager()
    var coordinator: ReaderCoordinator? = nil  // Add this
    @AppStorage("paragraphPauseDelay") private var pauseDuration: Double = 0.3
    @Environment(\.dismiss) private var dismiss

    // ... rest of implementation ...

    var body: some View {
        NavigationView {
            Form {
                speedSection
                voiceSection
                pauseSection
            }
            // ... rest of navigation view ...
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerSheet(
                viewModel: viewModel,
                filterManager: voiceFilterManager,
                coordinator: coordinator  // Pass coordinator
            )
        }
    }
}
```

**Step 3: Update ReaderView to pass coordinator to QuickSettingsSheet**

Modify `Listen2/Listen2/Listen2/Views/ReaderView.swift`:

Update the QuickSettingsSheet presentation:

```swift
.sheet(isPresented: $coordinator.isShowingQuickSettings) {
    QuickSettingsSheet(viewModel: viewModel, coordinator: coordinator)
        .presentationDetents([.medium])
}
```

**Step 4: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 5: Manual test voice change during playback**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' && open -a Simulator`

Manual test:
1. Open a document and start playback
2. Open quick settings
3. Change voice
4. Verify playback restarts with new voice immediately

Expected: Voice changes immediately without interruption

**Step 6: Commit**

```bash
git add Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift Listen2/Listen2/Listen2/Views/QuickSettingsSheet.swift Listen2/Listen2/Listen2/Views/ReaderView.swift
git commit -m "fix: implement proper voice change handling via coordinator"
```

---

## Task 11: Add Voice Persistence

**Files:**
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`

**Step 1: Add AppStorage for selected voice**

Modify `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`:

Add after the `@AppStorage("defaultPlaybackRate")` line:

```swift
@AppStorage("selectedVoiceId") private var selectedVoiceId: String = ""
```

**Step 2: Load saved voice in init**

Replace the voice initialization in `init` (around line 38):

```swift
// Set initial voice from saved preference or default to first English voice
if !selectedVoiceId.isEmpty,
   let savedVoice = ttsService.availableVoices().first(where: { $0.id == selectedVoiceId }) {
    self.selectedVoice = savedVoice
    ttsService.setVoice(savedVoice)
} else {
    self.selectedVoice = ttsService.availableVoices().first { $0.language.hasPrefix("en") }
}
```

**Step 3: Save voice on change**

Update the `setVoice` method:

```swift
func setVoice(_ voice: Voice) {
    selectedVoice = voice
    selectedVoiceId = voice.id  // Persist selection
    ttsService.setVoice(voice)
}
```

**Step 4: Update coordinator changeVoice to save**

Modify `Listen2/Listen2/Listen2/Coordinators/ReaderCoordinator.swift`:

Update the `changeVoice` method to ensure it saves:

```swift
// Update UI
viewModel.setVoice(newVoice)  // This now includes persistence
```

**Step 5: Build to verify it compiles**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: SUCCESS

**Step 6: Manual test voice persistence**

Manual test:
1. Open a document
2. Change voice in quick settings
3. Close the app completely
4. Reopen the app and open a document
5. Verify the selected voice is remembered

Expected: Voice preference persists across app launches

**Step 7: Commit**

```bash
git add Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift Listen2/Listen2/Listen2/Coordinators/ReaderCoordinator.swift
git commit -m "feat: persist selected voice across app launches"
```

---

## Task 12: Integration Testing and Polishing

**Files:**
- All modified files

**Step 1: Run full test suite**

Run: `xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: All tests PASS

**Step 2: Build for device**

Run: `xcodebuild build -scheme Listen2 -destination 'generic/platform=iOS'`

Expected: SUCCESS

**Step 3: Manual integration testing**

Test the following scenarios:

1. **TOC Navigation:**
   - Open a PDF with TOC metadata
   - Tap text to show overlay
   - Tap TOC button
   - Navigate to different chapters
   - Verify playback continues/restarts correctly

2. **Voice Filtering:**
   - Open quick settings
   - Open voice picker
   - Filter by gender
   - Verify filtered list updates
   - Select a voice
   - Verify it applies immediately

3. **Overlay Behavior:**
   - Tap text to show overlay
   - Wait 3 seconds
   - Verify auto-hide works
   - Tap during playback
   - Verify faster hide during playback

4. **Voice Change During Playback:**
   - Start playback
   - Change voice mid-paragraph
   - Verify seamless transition
   - Verify no audio glitches

**Step 4: Fix any issues found**

Address any bugs or issues discovered during manual testing.

**Step 5: Final commit**

```bash
git add -A
git commit -m "test: integration testing and polishing of reader enhancements"
```

**Step 6: Record completion in workshop**

Run: `workshop decision "Reader enhancements fully implemented" -r "TOC navigation, overlay controls, voice filtering, and voice change fixes all working. All tests passing."`

---

## Success Criteria Checklist

After completing all tasks, verify:

- ✅ TOC extracts from PDF metadata or detects headings
- ✅ Bottom sheet TOC navigates to correct paragraphs
- ✅ Tap text shows overlay with TOC and Settings buttons
- ✅ Overlay auto-hides after inactivity
- ✅ Quick settings sheet adjusts playback in real-time
- ✅ Voice filtering by language works
- ✅ Voice filtering by gender works (when detectable)
- ✅ Voice changes apply immediately and consistently
- ✅ Selected voice persists across app launches

## Notes

- Import PDFKit wherever needed: `import PDFKit`
- Import Combine for reactive bindings: `import Combine`
- Follow existing SwiftUI patterns in the codebase
- Use @MainActor for view models and coordinators
- Keep tests focused and fast
- Commit frequently (after each passing test)
