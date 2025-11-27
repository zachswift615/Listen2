# Voice Reader App MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build iOS voice reader app with PDF/EPUB/clipboard import, native TTS, and smart text extraction that fixes hyphenated words.

**Architecture:** SwiftUI MVVM app with service layer for document processing and TTS. Swift Data for persistence. Protocol-oriented design for testability and future extensibility.

**Tech Stack:** SwiftUI, Swift Data, PDFKit, AVFoundation, Combine, XCTest

---

## Prerequisites

**Development Environment:**
- macOS with Xcode 15.0+ installed
- iOS 17.0+ deployment target
- iPhone or iPad simulator

**Before Starting:**
- Open this project in Xcode (will create project in Task 1)
- Ensure you have an Apple Developer account (free tier works for simulator testing)

---

## Task 1: Create Xcode Project

**Files:**
- Create: Xcode project at `/Users/zachswift/projects/Listen2/`

**Step 1: Create new Xcode project**

1. Open Xcode
2. File → New → Project
3. Choose "iOS" → "App" → Next
4. Configuration:
   - Product Name: `Listen2`
   - Team: Select your team (or None for simulator only)
   - Organization Identifier: `com.yourname` (use your actual identifier)
   - Interface: SwiftUI
   - Language: Swift
   - Storage: Swift Data
   - Include Tests: ✓ Checked
5. Save to: `/Users/zachswift/projects/Listen2/Listen2`
   - **Important**: Save inside a `Listen2` subfolder to avoid conflicts with existing git repo
6. Click "Create"

**Step 2: Verify project structure**

Expected structure:
```
Listen2/
├── Listen2/
│   ├── Listen2/        # ← New Xcode project here
│   │   ├── Listen2App.swift
│   │   ├── ContentView.swift
│   │   └── ...
│   └── Listen2.xcodeproj
├── docs/
│   └── plans/
└── .git/
```

**Step 3: Update .gitignore**

Run from `/Users/zachswift/projects/Listen2/`:
```bash
cat >> .gitignore <<'EOF'
# Xcode
Listen2/Listen2.xcodeproj/xcuserdata/
Listen2/Listen2.xcodeproj/project.xcworkspace/xcuserdata/
Listen2/*.xcworkspace/xcuserdata/
Listen2/DerivedData/
Listen2/build/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xcuserstate
*.xcuserdatad
*.hmap
*.ipa
*.dSYM.zip
*.dSYM
EOF
```

**Step 4: Initial commit**

```bash
git add .gitignore Listen2/
git commit -m "feat: create Xcode project for Listen2 app"
```

**Step 5: Open project in Xcode**

```bash
open Listen2/Listen2.xcodeproj
```

Expected: Xcode opens with project, builds successfully (⌘B)

---

## Task 2: Establish Design System

**Goal:** Create a cohesive, thoughtful design language that makes the app feel polished and professional.

**Files:**
- Create: `Listen2/Design/DesignSystem.swift`
- Create: `Listen2/Design/ViewModifiers.swift`

**Step 1: Create Design group**

1. In Xcode Project Navigator, right-click `Listen2` folder
2. New Group → Name it "Design"

**Step 2: Create DesignSystem.swift**

Create: `Listen2/Design/DesignSystem.swift`

```swift
//
//  DesignSystem.swift
//  Listen2
//
//  Design tokens and constants for consistent styling throughout the app
//

import SwiftUI

enum DesignSystem {

    // MARK: - Colors

    enum Colors {
        // Primary brand color - calm blue for reading focus
        static let primary = Color(red: 0.0, green: 0.48, blue: 0.80) // #007ACC
        static let primaryLight = Color(red: 0.20, green: 0.60, blue: 0.90)

        // Accent colors
        static let accent = Color(red: 0.40, green: 0.65, blue: 1.0) // Lighter blue
        static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let warning = Color(red: 1.0, green: 0.58, blue: 0.0)
        static let error = Color(red: 0.96, green: 0.26, blue: 0.21)

        // Reading highlights
        static let highlightWord = Color.yellow.opacity(0.5)
        static let highlightParagraph = Color.blue.opacity(0.08)
        static let highlightSentence = Color.blue.opacity(0.05)

        // Neutrals (adapt to light/dark mode)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(UIColor.tertiaryLabel)

        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)

        static let separator = Color(UIColor.separator)
    }

    // MARK: - Typography

    enum Typography {
        // Title sizes
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)

        // Body text (reading content)
        static let bodyLarge = Font.system(size: 18, weight: .regular)
        static let body = Font.body
        static let bodySmall = Font.system(size: 15, weight: .regular)

        // UI text
        static let headline = Font.headline
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let caption2 = Font.caption2

        // Specialized
        static let mono = Font.system(.body, design: .monospaced)
        static let monoSmall = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let round: CGFloat = 999 // Fully rounded
    }

    // MARK: - Shadows

    enum Shadow {
        static let small = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.15), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.20), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
    }

    // MARK: - Animation

    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }

    // MARK: - Icon Sizes

    enum IconSize {
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
    }
}
```

**Step 3: Create custom view modifiers**

Create: `Listen2/Design/ViewModifiers.swift`

```swift
//
//  ViewModifiers.swift
//  Listen2
//
//  Reusable view modifiers for consistent styling
//

import SwiftUI

// MARK: - Card Style

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.md
    var padding: CGFloat = DesignSystem.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.secondaryBackground)
            .cornerRadius(cornerRadius)
            .shadow(
                color: DesignSystem.Shadow.small.color,
                radius: DesignSystem.Shadow.small.radius,
                x: DesignSystem.Shadow.small.x,
                y: DesignSystem.Shadow.small.y
            )
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = DesignSystem.CornerRadius.md, padding: CGFloat = DesignSystem.Spacing.md) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(isDestructive ? DesignSystem.Colors.error : DesignSystem.Colors.primary)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var destructive: PrimaryButtonStyle { PrimaryButtonStyle(isDestructive: true) }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadline)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.primary.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Icon Button Style

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = DesignSystem.IconSize.large

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size))
            .foregroundColor(DesignSystem.Colors.primary)
            .frame(width: size + DesignSystem.Spacing.md, height: size + DesignSystem.Spacing.md)
            .background(
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(DesignSystem.Animation.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    static func icon(size: CGFloat) -> IconButtonStyle { IconButtonStyle(size: size) }
}

// MARK: - Empty State Style

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text(message)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(.white)
                }
                .padding(DesignSystem.Spacing.xl)
                .background(.ultraThinMaterial)
                .cornerRadius(DesignSystem.CornerRadius.xl)
            }
        }
        .animation(DesignSystem.Animation.standard, value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}
```

**Step 4: Build project**

Press ⌘B (Build)

Expected: "Build Succeeded"

**Step 5: Commit**

```bash
git add Listen2/Design/
git commit -m "feat: add design system with tokens and modifiers"
```

**Design Philosophy:**

- **Colors**: Calm blue palette ideal for reading apps, excellent contrast, supports light/dark mode
- **Typography**: Clear hierarchy, larger body text for comfortable reading, monospaced for technical info
- **Spacing**: 8px base grid system (xs=8, sm=12, md=16, lg=24, xl=32)
- **Animations**: Fast interactions (200ms), standard transitions (300ms), spring for playful touches
- **Consistency**: All UI elements will use these tokens, ensuring cohesive feel throughout

**Usage Notes:**

Throughout the remaining tasks, we'll apply these design tokens to make the app feel professional:
- Document cards use `cardStyle()` modifier
- Buttons use `.buttonStyle(.primary)` or `.buttonStyle(.secondary)`
- Colors reference `DesignSystem.Colors.*`
- Spacing uses `DesignSystem.Spacing.*`
- Empty states use `EmptyStateView` component

---

## Task 3: Create Project Structure & Models

**Files:**
- Create: `Listen2/Models/Document.swift`
- Create: `Listen2/Models/ReadingProgress.swift`
- Create: `Listen2/Models/Voice.swift`
- Create: `Listen2Tests/Models/DocumentTests.swift`

**Step 1: Create Models group in Xcode**

1. In Xcode Project Navigator, right-click `Listen2` folder
2. New Group → Name it "Models"
3. Repeat for: "Services", "ViewModels", "Views"

Expected structure:
```
Listen2/
├── Models/
├── Services/
├── ViewModels/
├── Views/
├── Listen2App.swift
└── Item.swift (can delete this later)
```

**Step 2: Create SourceType enum**

File → New → File → Swift File → Name: `SourceType.swift` in `Models/`

```swift
//
//  SourceType.swift
//  Listen2
//

import Foundation

enum SourceType: String, Codable {
    case pdf = "PDF"
    case epub = "EPUB"
    case clipboard = "Clipboard"

    var iconName: String {
        switch self {
        case .pdf: return "doc.fill"
        case .epub: return "book.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        }
    }
}
```

**Step 3: Create Document model**

File → New → File → Swift File → Name: `Document.swift` in `Models/`

```swift
//
//  Document.swift
//  Listen2
//

import Foundation
import SwiftData

@Model
final class Document {
    var id: UUID
    var title: String
    var sourceType: SourceType
    var extractedText: [String] // Array of paragraphs
    var currentPosition: Int // Current paragraph index
    var lastRead: Date
    var createdAt: Date
    var fileURL: URL? // Original file location

    init(
        title: String,
        sourceType: SourceType,
        extractedText: [String],
        fileURL: URL? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.sourceType = sourceType
        self.extractedText = extractedText
        self.currentPosition = 0
        self.lastRead = Date()
        self.createdAt = Date()
        self.fileURL = fileURL
    }

    var progressPercentage: Int {
        guard !extractedText.isEmpty else { return 0 }
        return Int((Double(currentPosition) / Double(extractedText.count)) * 100)
    }
}
```

**Step 4: Create ReadingProgress model**

File → New → File → Swift File → Name: `ReadingProgress.swift` in `Models/`

```swift
//
//  ReadingProgress.swift
//  Listen2
//

import Foundation

struct ReadingProgress {
    let paragraphIndex: Int
    let wordRange: Range<String.Index>?
    let isPlaying: Bool

    static let initial = ReadingProgress(
        paragraphIndex: 0,
        wordRange: nil,
        isPlaying: false
    )
}
```

**Step 5: Create Voice model**

File → New → File → Swift File → Name: `Voice.swift` in `Models/`

```swift
//
//  Voice.swift
//  Listen2
//

import Foundation
import AVFoundation

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    init(from avVoice: AVSpeechSynthesisVoice) {
        self.id = avVoice.identifier
        self.name = avVoice.name
        self.language = avVoice.language
        self.quality = avVoice.quality
    }

    var displayName: String {
        "\(name) (\(languageDisplayName))"
    }

    private var languageDisplayName: String {
        let locale = Locale(identifier: language)
        return locale.localizedString(forLanguageCode: language) ?? language
    }
}
```

**Step 6: Build project**

Press ⌘B (Build)

Expected: "Build Succeeded"

**Step 7: Write test for Document model**

Create: `Listen2Tests/Models/` folder (New Group with folder)
File → New → File → Unit Test Case Class → Name: `DocumentTests.swift`

```swift
//
//  DocumentTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class DocumentTests: XCTestCase {

    func testDocumentInitialization() {
        // Given
        let title = "Test Document"
        let sourceType = SourceType.pdf
        let text = ["Paragraph one.", "Paragraph two."]

        // When
        let document = Document(
            title: title,
            sourceType: sourceType,
            extractedText: text
        )

        // Then
        XCTAssertEqual(document.title, title)
        XCTAssertEqual(document.sourceType, sourceType)
        XCTAssertEqual(document.extractedText, text)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.progressPercentage, 0)
    }

    func testProgressPercentage() {
        // Given
        let document = Document(
            title: "Test",
            sourceType: .clipboard,
            extractedText: ["1", "2", "3", "4"]
        )

        // When
        document.currentPosition = 2

        // Then
        XCTAssertEqual(document.progressPercentage, 50)
    }

    func testProgressPercentageEmpty() {
        // Given
        let document = Document(
            title: "Empty",
            sourceType: .clipboard,
            extractedText: []
        )

        // Then
        XCTAssertEqual(document.progressPercentage, 0)
    }
}
```

**Step 8: Run tests**

Press ⌘U (Test)

Expected: All tests pass ✓

**Step 9: Commit**

```bash
git add Listen2/
git commit -m "feat: add core data models (Document, Voice, ReadingProgress)"
```

---

## Task 4: Document Processor Service - PDF Text Extraction

**Files:**
- Create: `Listen2/Services/DocumentProcessor.swift`
- Create: `Listen2Tests/Services/DocumentProcessorTests.swift`

**Step 1: Write failing test for hyphenation fix**

Create: `Listen2Tests/Services/DocumentProcessorTests.swift`

```swift
//
//  DocumentProcessorTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class DocumentProcessorTests: XCTestCase {

    var processor: DocumentProcessor!

    override func setUp() {
        super.setUp()
        processor = DocumentProcessor()
    }

    func testFixHyphenation_SimpleCase() {
        // Given
        let input = "This is an ex-\nample of hyphenation."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "This is an example of hyphenation.")
    }

    func testFixHyphenation_MultipleHyphens() {
        // Given
        let input = "Hyphen-\nated words can ap-\npear multiple times."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "Hyphenated words can appear multiple times.")
    }

    func testFixHyphenation_PreservesNormalHyphens() {
        // Given
        let input = "This is a well-known fact."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "This is a well-known fact.")
    }

    func testFixHyphenation_HandlesWhitespace() {
        // Given
        let input = "Ex-  \n  ample with spaces."

        // When
        let result = processor.fixHyphenation(in: input)

        // Then
        XCTAssertEqual(result, "Example with spaces.")
    }
}
```

**Step 2: Run test to verify it fails**

Press ⌘U

Expected: FAIL - "Use of unresolved identifier 'DocumentProcessor'"

**Step 3: Create DocumentProcessor with hyphenation fix**

Create: `Listen2/Services/DocumentProcessor.swift`

```swift
//
//  DocumentProcessor.swift
//  Listen2
//

import Foundation
import PDFKit
import UniformTypeIdentifiers

final class DocumentProcessor {

    // MARK: - Public Methods

    /// Fixes hyphenated words that are broken across lines in PDF text
    func fixHyphenation(in text: String) -> String {
        // Pattern: word characters, hyphen, whitespace including newlines, more word characters
        let pattern = #"(\w+)-\s*\n\s*(\w+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let result = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "$1$2" // Join the two word parts
        )

        return result
    }
}
```

**Step 4: Run tests to verify they pass**

Press ⌘U

Expected: All tests pass ✓

**Step 5: Commit**

```bash
git add Listen2/Services/DocumentProcessor.swift Listen2Tests/Services/DocumentProcessorTests.swift
git commit -m "feat: add hyphenation fix for PDF text extraction"
```

**Step 6: Write test for PDF text extraction**

Add to `DocumentProcessorTests.swift`:

```swift
func testExtractTextFromPDF_WithHyphenation() async throws {
    // Given
    let pdfText = """
    This is a sam-
    ple document with hyphen-
    ated words.
    """
    let pdfURL = try createTestPDF(withText: pdfText)

    // When
    let result = try await processor.extractText(from: pdfURL, sourceType: .pdf)

    // Then
    XCTAssertTrue(result.contains("sample document"))
    XCTAssertTrue(result.contains("hyphenated words"))
    XCTAssertFalse(result.contains("sam-\n"))

    // Cleanup
    try? FileManager.default.removeItem(at: pdfURL)
}

// Helper to create test PDF
private func createTestPDF(withText text: String) throws -> URL {
    let pdfMetaData = [
        kCGPDFContextTitle: "Test PDF"
    ]
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = pdfMetaData as [String: Any]

    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

    let data = renderer.pdfData { context in
        context.beginPage()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12)
        ]
        text.draw(in: pageRect.insetBy(dx: 50, dy: 50), withAttributes: attributes)
    }

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    try data.write(to: tempURL)

    return tempURL
}
```

**Step 7: Run test to verify it fails**

Press ⌘U

Expected: FAIL - "Value of type 'DocumentProcessor' has no member 'extractText'"

**Step 8: Implement PDF text extraction**

Add to `DocumentProcessor.swift`:

```swift
// MARK: - Text Extraction

enum DocumentProcessorError: Error {
    case invalidFile
    case extractionFailed
    case unsupportedFormat
}

func extractText(from url: URL, sourceType: SourceType) async throws -> [String] {
    switch sourceType {
    case .pdf:
        return try await extractPDFText(from: url)
    case .epub:
        return try await extractEPUBText(from: url)
    case .clipboard:
        throw DocumentProcessorError.unsupportedFormat
    }
}

// MARK: - Private PDF Extraction

private func extractPDFText(from url: URL) async throws -> [String] {
    guard let document = PDFDocument(url: url) else {
        throw DocumentProcessorError.invalidFile
    }

    var fullText = ""

    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex),
              let pageText = page.string else {
            continue
        }
        fullText += pageText + "\n"
    }

    // Fix hyphenation issues
    let cleanedText = fixHyphenation(in: fullText)

    // Split into paragraphs
    let paragraphs = cleanedText
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard !paragraphs.isEmpty else {
        throw DocumentProcessorError.extractionFailed
    }

    return paragraphs
}

// MARK: - Private EPUB Extraction (Stub for now)

private func extractEPUBText(from url: URL) async throws -> [String] {
    // TODO: Implement EPUB extraction in next task
    throw DocumentProcessorError.unsupportedFormat
}
```

**Step 9: Run tests**

Press ⌘U

Expected: All tests pass ✓

**Step 10: Commit**

```bash
git add Listen2/Services/DocumentProcessor.swift Listen2Tests/Services/DocumentProcessorTests.swift
git commit -m "feat: add PDF text extraction with hyphenation fixing"
```

---

## Task 5: Document Processor - Clipboard & EPUB Support

**Files:**
- Modify: `Listen2/Services/DocumentProcessor.swift`
- Modify: `Listen2Tests/Services/DocumentProcessorTests.swift`

**Step 1: Write test for clipboard text processing**

Add to `DocumentProcessorTests.swift`:

```swift
func testProcessClipboardText() {
    // Given
    let clipboardText = """
    First paragraph with content.

    Second paragraph after blank line.

    Third paragraph.
    """

    // When
    let result = processor.processClipboardText(clipboardText)

    // Then
    XCTAssertEqual(result.count, 3)
    XCTAssertEqual(result[0], "First paragraph with content.")
    XCTAssertEqual(result[1], "Second paragraph after blank line.")
    XCTAssertEqual(result[2], "Third paragraph.")
}

func testProcessClipboardText_EmptyLines() {
    // Given
    let clipboardText = "\n\n  \n\nActual content.\n\n  \n"

    // When
    let result = processor.processClipboardText(clipboardText)

    // Then
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0], "Actual content.")
}
```

**Step 2: Run test to fail**

Press ⌘U

Expected: FAIL - "Value of type 'DocumentProcessor' has no member 'processClipboardText'"

**Step 3: Implement clipboard processing**

Add to `DocumentProcessor.swift`:

```swift
// MARK: - Clipboard Processing

func processClipboardText(_ text: String) -> [String] {
    let paragraphs = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    return paragraphs
}
```

**Step 4: Run tests**

Press ⌘U

Expected: All tests pass ✓

**Step 5: Add basic EPUB support (simplified)**

For MVP, we'll do simple EPUB text extraction without external libraries.

Add to `DocumentProcessorTests.swift`:

```swift
func testExtractEPUBText_Basic() async throws {
    // For MVP, we'll test the interface exists
    // Full EPUB parsing can be enhanced later
    let testURL = URL(fileURLWithPath: "/tmp/test.epub")

    do {
        _ = try await processor.extractText(from: testURL, sourceType: .epub)
        XCTFail("Should throw unsupportedFormat for now")
    } catch DocumentProcessorError.unsupportedFormat {
        // Expected for MVP
        XCTAssertTrue(true)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
```

**Step 6: Run test**

Press ⌘U

Expected: Test passes ✓ (confirms EPUB throws unsupportedFormat for now)

**Step 7: Commit**

```bash
git add Listen2/Services/DocumentProcessor.swift Listen2Tests/Services/DocumentProcessorTests.swift
git commit -m "feat: add clipboard text processing, stub EPUB support"
```

---

## Task 6: TTS Service - Native Voice Playback

**Files:**
- Create: `Listen2/Services/TTSService.swift`
- Create: `Listen2Tests/Services/TTSServiceTests.swift`

**Step 1: Write test for TTS service initialization**

Create: `Listen2Tests/Services/TTSServiceTests.swift`

```swift
//
//  TTSServiceTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class TTSServiceTests: XCTestCase {

    var service: TTSService!

    override func setUp() {
        super.setUp()
        service = TTSService()
    }

    override func tearDown() {
        service.stop()
        service = nil
        super.tearDown()
    }

    func testInitialization() {
        // Then
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentProgress.paragraphIndex, 0)
    }

    func testAvailableVoices_NotEmpty() {
        // When
        let voices = service.availableVoices()

        // Then
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.contains { $0.language.hasPrefix("en") })
    }

    func testSetPlaybackRate() {
        // When
        service.setPlaybackRate(1.5)

        // Then
        XCTAssertEqual(service.playbackRate, 1.5)
    }
}
```

**Step 2: Run test to fail**

Press ⌘U

Expected: FAIL - "Use of unresolved identifier 'TTSService'"

**Step 3: Create TTSService**

Create: `Listen2/Services/TTSService.swift`

```swift
//
//  TTSService.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine

final class TTSService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentProgress: ReadingProgress = .initial
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Float = 1.0

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self

        // Set default voice (first English voice)
        currentVoice = AVSpeechSynthesisVoice.speechVoices()
            .first { $0.language.hasPrefix("en") }
    }

    // MARK: - Public Methods

    func availableVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { Voice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.5, rate))
    }

    func setVoice(_ voice: Voice) {
        currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
    }
}
```

**Step 4: Run tests**

Press ⌘U

Expected: All tests pass ✓

**Step 5: Commit**

```bash
git add Listen2/Services/TTSService.swift Listen2Tests/Services/TTSServiceTests.swift
git commit -m "feat: add TTS service with voice management"
```

**Step 6: Add playback functionality test**

Add to `TTSServiceTests.swift`:

```swift
func testStartReading() {
    // Given
    let paragraphs = ["First paragraph.", "Second paragraph."]

    // When
    service.startReading(paragraphs: paragraphs, from: 0)

    // Then
    XCTAssertEqual(service.currentProgress.paragraphIndex, 0)

    // Wait briefly for speech to start
    let expectation = expectation(description: "Speech starts")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        XCTAssertTrue(self.service.isPlaying)
        expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
}

func testPauseAndResume() {
    // Given
    service.startReading(paragraphs: ["Test text."], from: 0)

    // Wait for speech to start
    let startExpectation = expectation(description: "Speech starts")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        startExpectation.fulfill()
    }
    wait(for: [startExpectation], timeout: 1.0)

    // When
    service.pause()

    // Then
    XCTAssertFalse(service.isPlaying)

    // When
    service.resume()

    // Then - wait for resume
    let resumeExpectation = expectation(description: "Speech resumes")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        XCTAssertTrue(self.service.isPlaying)
        resumeExpectation.fulfill()
    }
    wait(for: [resumeExpectation], timeout: 1.0)
}
```

**Step 7: Run test to fail**

Press ⌘U

Expected: FAIL - "Value of type 'TTSService' has no member 'startReading'"

**Step 8: Implement playback methods**

Add to `TTSService.swift`:

```swift
// MARK: - Playback Control

func startReading(paragraphs: [String], from index: Int) {
    currentText = paragraphs

    guard index < paragraphs.count else { return }

    currentProgress = ReadingProgress(
        paragraphIndex: index,
        wordRange: nil,
        isPlaying: false
    )

    speakParagraph(at: index)
}

func pause() {
    synthesizer.pauseSpeaking(at: .word)
    isPlaying = false
}

func resume() {
    synthesizer.continueSpeaking()
    isPlaying = true
}

func skipToNext() {
    let nextIndex = currentProgress.paragraphIndex + 1
    guard nextIndex < currentText.count else {
        stop()
        return
    }

    stop()
    speakParagraph(at: nextIndex)
}

func skipToPrevious() {
    let prevIndex = max(0, currentProgress.paragraphIndex - 1)
    stop()
    speakParagraph(at: prevIndex)
}

// MARK: - Private Methods

private func speakParagraph(at index: Int) {
    guard index < currentText.count else { return }

    let text = currentText[index]
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = currentVoice
    utterance.rate = playbackRate * 0.5 // AVSpeechUtterance rate is 0-1 scale

    currentProgress = ReadingProgress(
        paragraphIndex: index,
        wordRange: nil,
        isPlaying: true
    )

    synthesizer.speak(utterance)
}
```

Update delegate methods in extension:

```swift
extension TTSService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false

        // Auto-advance to next paragraph
        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            speakParagraph(at: nextIndex)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Update word range for highlighting
        if let text = utterance.speechString as? String,
           let range = Range(characterRange, in: text) {
            currentProgress = ReadingProgress(
                paragraphIndex: currentProgress.paragraphIndex,
                wordRange: range,
                isPlaying: true
            )
        }
    }
}
```

**Step 9: Run tests**

Press ⌘U

Expected: All tests pass ✓

**Step 10: Commit**

```bash
git add Listen2/Services/TTSService.swift Listen2Tests/Services/TTSServiceTests.swift
git commit -m "feat: add TTS playback controls with auto-advance"
```

---

## Task 7: Library View - UI and ViewModel

**Files:**
- Create: `Listen2/ViewModels/LibraryViewModel.swift`
- Create: `Listen2/Views/LibraryView.swift`
- Create: `Listen2/Views/DocumentRowView.swift`

**Step 1: Create LibraryViewModel**

Create: `Listen2/ViewModels/LibraryViewModel.swift`

```swift
//
//  LibraryViewModel.swift
//  Listen2
//

import Foundation
import SwiftData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var documents: [Document] = []
    @Published var searchText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let documentProcessor = DocumentProcessor()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadDocuments()
    }

    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadDocuments() {
        let descriptor = FetchDescriptor<Document>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)]
        )

        do {
            documents = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
        }
    }

    func deleteDocument(_ document: Document) {
        modelContext.delete(document)

        do {
            try modelContext.save()
            loadDocuments()
        } catch {
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
        }
    }

    func importFromClipboard(_ text: String) async {
        isProcessing = true
        errorMessage = nil

        let paragraphs = documentProcessor.processClipboardText(text)

        guard !paragraphs.isEmpty else {
            errorMessage = "No text found in clipboard"
            isProcessing = false
            return
        }

        let document = Document(
            title: "Clipboard \(Date().formatted(date: .abbreviated, time: .shortened))",
            sourceType: .clipboard,
            extractedText: paragraphs
        )

        modelContext.insert(document)

        do {
            try modelContext.save()
            loadDocuments()
        } catch {
            errorMessage = "Failed to save document: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func importDocument(from url: URL, sourceType: SourceType) async {
        isProcessing = true
        errorMessage = nil

        do {
            let paragraphs = try await documentProcessor.extractText(from: url, sourceType: sourceType)

            let title = url.deletingPathExtension().lastPathComponent

            let document = Document(
                title: title,
                sourceType: sourceType,
                extractedText: paragraphs,
                fileURL: url
            )

            modelContext.insert(document)
            try modelContext.save()
            loadDocuments()

        } catch {
            errorMessage = "Failed to import document: \(error.localizedDescription)"
        }

        isProcessing = false
    }
}
```

**Step 2: Create DocumentRowView**

Create: `Listen2/Views/DocumentRowView.swift`

```swift
//
//  DocumentRowView.swift
//  Listen2
//

import SwiftUI

struct DocumentRowView: View {
    let document: Document

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Icon
            Image(systemName: document.sourceType.iconName)
                .font(.system(size: DesignSystem.IconSize.large))
                .foregroundStyle(DesignSystem.Colors.primary)
                .frame(width: 40)

            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(document.title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(document.sourceType.rawValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if document.progressPercentage > 0 {
                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("Resume at \(document.progressPercentage)%")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }

            Spacer()

            // Metadata
            Text(document.lastRead, style: .relative)
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}
```

**Step 3: Create LibraryView**

Create: `Listen2/Views/LibraryView.swift`

```swift
//
//  LibraryView.swift
//  Listen2
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingFilePicker = false
    @State private var showingReader = false
    @State private var selectedDocument: Document?

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                if viewModel.filteredDocuments.isEmpty {
                    emptyStateView
                } else {
                    documentList
                }

                // Processing overlay
                if viewModel.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("Library")
            .searchable(text: $viewModel.searchText, prompt: "Search documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                if let clipboardText = UIPasteboard.general.string {
                                    await viewModel.importFromClipboard(clipboardText)
                                }
                            }
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }

                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Import File", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    if let url = try? result.get().first {
                        await viewModel.importDocument(from: url, sourceType: .pdf)
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .sheet(item: $selectedDocument) { document in
                ReaderView(document: document)
            }
        }
    }

    private var documentList: some View {
        List {
            ForEach(viewModel.filteredDocuments) { document in
                Button {
                    selectedDocument = document
                } label: {
                    DocumentRowView(document: document)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteDocument(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "books.vertical",
            title: "No Documents",
            message: "Import a PDF or paste text to get started"
        )
    }

    private var processingOverlay: some View {
        Color.clear
            .loadingOverlay(isLoading: true, message: "Processing...")
    }
}
```

**Step 4: Update app entry point**

Modify `Listen2App.swift`:

```swift
//
//  Listen2App.swift
//  Listen2
//

import SwiftUI
import SwiftData

@main
struct Listen2App: App {

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Document.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            LibraryView(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Step 5: Create stub ReaderView**

Create: `Listen2/Views/ReaderView.swift`

```swift
//
//  ReaderView.swift
//  Listen2
//

import SwiftUI

struct ReaderView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Reader View - Coming in next task")
                .navigationTitle(document.title)
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
}
```

**Step 6: Build and run in simulator**

Press ⌘R

Expected:
- App launches
- Shows empty library state
- Can tap "+" menu
- Can see "Paste from Clipboard" and "Import File" options

**Step 7: Test clipboard import**

1. Copy some text to clipboard
2. Tap "+" → "Paste from Clipboard"
3. Should see "Processing..." overlay
4. Document appears in list with "Clipboard [timestamp]" title

**Step 8: Commit**

```bash
git add Listen2/
git commit -m "feat: add library view with document import"
```

---

## Task 8: Reader View - Playback UI

**Files:**
- Modify: `Listen2/Views/ReaderView.swift`
- Create: `Listen2/ViewModels/ReaderViewModel.swift`

**Step 1: Create ReaderViewModel**

Create: `Listen2/ViewModels/ReaderViewModel.swift`

```swift
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
```

**Step 2: Update ReaderView**

Replace content of `Listen2/Views/ReaderView.swift`:

```swift
//
//  ReaderView.swift
//  Listen2
//

import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ReaderViewModel
    @State private var showingVoicePicker = false
    @Namespace private var scrollNamespace

    init(document: Document, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(document: document, modelContext: modelContext))
    }

    // Convenience init for when called from LibraryView
    init(document: Document) {
        // This will be passed the environment's modelContext
        self.init(document: document, modelContext: ModelContext(document.modelContainer!))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(viewModel.document.extractedText.enumerated()), id: \.offset) { index, paragraph in
                                paragraphView(text: paragraph, index: index)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.currentParagraphIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                Divider()

                // Controls
                playbackControls
                    .padding()
                    .background(.regularMaterial)
            }
            .navigationTitle(viewModel.document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.cleanup()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingVoicePicker) {
                voicePickerSheet
            }
        }
    }

    private func paragraphView(text: String, index: Int) -> some View {
        let isCurrentParagraph = index == viewModel.currentParagraphIndex

        return Text(attributedText(for: text, isCurrentParagraph: isCurrentParagraph))
            .font(DesignSystem.Typography.bodyLarge)
            .padding(DesignSystem.Spacing.sm)
            .background(
                isCurrentParagraph ? DesignSystem.Colors.highlightParagraph : Color.clear
            )
            .cornerRadius(DesignSystem.CornerRadius.md)
            .onTapGesture {
                viewModel.ttsService.stop()
                viewModel.ttsService.startReading(
                    paragraphs: viewModel.document.extractedText,
                    from: index
                )
            }
    }

    private func attributedText(for text: String, isCurrentParagraph: Bool) -> AttributedString {
        var attributedString = AttributedString(text)

        // Highlight current word if this is the active paragraph
        if isCurrentParagraph,
           let wordRange = viewModel.currentWordRange,
           let range = Range(wordRange, in: AttributedString(text).characters) {
            attributedString[range].backgroundColor = DesignSystem.Colors.highlightWord
            attributedString[range].font = Font.body.weight(.semibold)
        }

        return attributedString
    }

    private var playbackControls: some View {
        VStack(spacing: 16) {
            // Speed and Voice
            HStack {
                // Speed
                HStack {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fx", viewModel.playbackRate))
                        .font(.caption)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { viewModel.playbackRate },
                    set: { viewModel.setPlaybackRate($0) }
                ), in: 0.5...2.5, step: 0.1)
                .frame(maxWidth: 150)

                Spacer()

                // Voice picker button
                Button {
                    showingVoicePicker = true
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                        Text(viewModel.selectedVoice?.name ?? "Voice")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            // Playback buttons
            HStack(spacing: 32) {
                // Skip back
                Button {
                    viewModel.skipBackward()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                }

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                // Skip forward
                Button {
                    viewModel.skipForward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                }
            }
        }
    }

    private var voicePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.ttsService.availableVoices()) { voice in
                    Button {
                        viewModel.setVoice(voice)
                        showingVoicePicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                    .font(.headline)
                                Text(voice.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if voice.id == viewModel.selectedVoice?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingVoicePicker = false
                    }
                }
            }
        }
    }
}
```

**Step 3: Fix LibraryView to pass modelContext**

Update `LibraryView.swift` sheet presentation:

```swift
.sheet(item: $selectedDocument) { document in
    ReaderView(document: document, modelContext: modelContext)
}
```

**Step 4: Build and run**

Press ⌘R

Expected:
1. Import clipboard text
2. Tap document to open reader
3. See paragraphs listed
4. Tap play button
5. Hear text being read
6. See current paragraph highlighted
7. Can adjust speed slider
8. Can skip forward/backward

**Step 5: Test voice picker**

1. Tap "Voice" button
2. See list of available voices
3. Select different voice
4. Play to hear new voice

**Step 6: Commit**

```bash
git add Listen2/
git commit -m "feat: add reader view with TTS playback controls"
```

---

## Task 9: Background Audio Support

**Files:**
- Modify: `Listen2/Services/TTSService.swift`
- Modify: `Listen2/Info.plist` (create if needed)

**Step 1: Add audio session setup**

Add to `TTSService.swift` in `init()`:

```swift
override init() {
    super.init()
    synthesizer.delegate = self

    // Set default voice
    currentVoice = AVSpeechSynthesisVoice.speechVoices()
        .first { $0.language.hasPrefix("en") }

    // Configure audio session for background playback
    configureAudioSession()
}

private func configureAudioSession() {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
        try audioSession.setActive(true)
    } catch {
        print("Failed to configure audio session: \(error)")
    }
}
```

**Step 2: Add background capability**

1. In Xcode, select project "Listen2" in navigator
2. Select "Listen2" target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Background Modes"
6. Check "Audio, AirPlay, and Picture in Picture"

**Step 3: Add Now Playing info**

Add to `TTSService.swift`:

```swift
import MediaPlayer

// Add this method
private func updateNowPlayingInfo(title: String, paragraph: String) {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = title
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Listen2"
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}

// Add this method
private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
        self?.resume()
        return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
        self?.pause()
        return .success
    }

    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
        self?.skipToNext()
        return .success
    }

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
        self?.skipToPrevious()
        return .success
    }
}
```

Call in `init()`:

```swift
override init() {
    super.init()
    synthesizer.delegate = self

    currentVoice = AVSpeechSynthesisVoice.speechVoices()
        .first { $0.language.hasPrefix("en") }

    configureAudioSession()
    setupRemoteCommandCenter()
}
```

**Step 4: Update startReading to set now playing**

Modify `startReading` to accept title:

```swift
func startReading(paragraphs: [String], from index: Int, title: String = "Document") {
    currentText = paragraphs

    guard index < paragraphs.count else { return }

    currentProgress = ReadingProgress(
        paragraphIndex: index,
        wordRange: nil,
        isPlaying: false
    )

    updateNowPlayingInfo(title: title, paragraph: paragraphs[index])
    speakParagraph(at: index)
}
```

**Step 5: Update ReaderViewModel calls**

In `ReaderViewModel.swift`, update calls to pass title:

```swift
func togglePlayPause() {
    if isPlaying {
        ttsService.pause()
    } else {
        if ttsService.currentProgress.paragraphIndex == 0 && ttsService.currentProgress.wordRange == nil {
            ttsService.startReading(
                paragraphs: document.extractedText,
                from: currentParagraphIndex,
                title: document.title
            )
        } else {
            ttsService.resume()
        }
    }
}
```

Also update in `ReaderView.swift` `onTapGesture`:

```swift
.onTapGesture {
    viewModel.ttsService.stop()
    viewModel.ttsService.startReading(
        paragraphs: viewModel.document.extractedText,
        from: index,
        title: viewModel.document.title
    )
}
```

**Step 6: Build and test on device (simulator has limited background audio)**

Press ⌘R

Test:
1. Start playing
2. Press home button (background app)
3. Audio continues playing
4. Open Control Center
5. See "Listen2" with document title
6. Can pause/play from Control Center

**Step 7: Commit**

```bash
git add Listen2/
git commit -m "feat: add background audio and lock screen controls"
```

---

## Task 10: Settings View

**Files:**
- Create: `Listen2/Views/SettingsView.swift`
- Modify: `Listen2/Views/LibraryView.swift`

**Step 1: Create SettingsView**

Create: `Listen2/Views/SettingsView.swift`

```swift
//
//  SettingsView.swift
//  Listen2
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0
    @AppStorage("autoResumeLastDocument") private var autoResumeLastDocument: Bool = false
    @AppStorage("highlightStyle") private var highlightStyle: String = "word"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default Speed")
                            Spacer()
                            Text(String(format: "%.1fx", defaultPlaybackRate))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $defaultPlaybackRate, in: 0.5...2.5, step: 0.1)
                    }

                    Toggle("Auto-resume Last Document", isPresented: $autoResumeLastDocument)
                } header: {
                    Text("Playback")
                }

                Section {
                    Picker("Highlighting", selection: $highlightStyle) {
                        Text("Word Only").tag("word")
                        Text("Word + Sentence").tag("sentence")
                    }
                } header: {
                    Text("Reading Experience")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
```

**Step 2: Add settings button to LibraryView**

In `LibraryView.swift`, add state and toolbar item:

```swift
@State private var showingSettings = false

// In .toolbar, add another ToolbarItem:
ToolbarItem(placement: .navigationBarLeading) {
    Button {
        showingSettings = true
    } label: {
        Image(systemName: "gearshape")
    }
}

// Add sheet presentation after existing .sheet:
.sheet(isPresented: $showingSettings) {
    SettingsView()
}
```

**Step 3: Use default playback rate in ReaderViewModel**

In `ReaderViewModel.swift`:

```swift
import SwiftUI // Add this import for @AppStorage

// Add property
@AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0

// In init, set initial rate:
init(document: Document, modelContext: ModelContext) {
    self.document = document
    self.currentParagraphIndex = document.currentPosition
    self.modelContext = modelContext
    self.ttsService = TTSService()

    // Set initial playback rate from defaults
    self.playbackRate = Float(defaultPlaybackRate)
    ttsService.setPlaybackRate(Float(defaultPlaybackRate))

    // Set initial voice
    self.selectedVoice = ttsService.availableVoices().first { $0.language.hasPrefix("en") }

    setupBindings()
}
```

**Step 4: Build and test**

Press ⌘R

Test:
1. Tap settings gear icon
2. See settings screen
3. Adjust default speed
4. Toggle auto-resume
5. Close settings
6. Open a document - should use default speed

**Step 5: Commit**

```bash
git add Listen2/
git commit -m "feat: add settings view with playback preferences"
```

---

## Task 11: Polish & Final Testing

**Files:**
- Modify: `Listen2/Assets.xcassets/` (app icon)
- Modify: Various UI tweaks

**Step 1: Add app icon (if you have one)**

1. In Xcode, open `Assets.xcassets`
2. Click "AppIcon"
3. Drag icon images into appropriate sizes
   - Or use a placeholder for now

**Step 2: Update display name and version**

1. Select Listen2 project
2. Select Listen2 target
3. General tab:
   - Display Name: "Listen2"
   - Version: 1.0
   - Build: 1

**Step 3: Test full flow**

Manual testing checklist:
- [ ] Launch app shows empty state
- [ ] Copy text, paste from clipboard creates document
- [ ] Import PDF file (if you have test PDF)
- [ ] Tap document opens reader
- [ ] Play button starts reading
- [ ] Current paragraph highlights
- [ ] Current word highlights during speech
- [ ] Tap different paragraph jumps to it
- [ ] Skip forward/backward works
- [ ] Speed slider adjusts rate
- [ ] Voice picker shows voices and changes voice
- [ ] Background app continues audio
- [ ] Lock screen shows controls
- [ ] Swipe delete removes document
- [ ] Search filters documents
- [ ] Settings opens and saves preferences
- [ ] Close reader saves position
- [ ] Resume shows correct percentage

**Step 4: Fix any issues found**

Address bugs found during testing.

**Step 5: Add test PDF with hyphenation**

Create a test file to validate hyphenation fix:

1. Create a text file with hyphenated content
2. Convert to PDF (or use existing problematic PDF)
3. Import and test that hyphenation is fixed

**Step 6: Final commit**

```bash
git add Listen2/
git commit -m "polish: final UI tweaks and testing"
```

**Step 7: Tag MVP release**

```bash
git tag -a v1.0-mvp -m "MVP release: Core reading features complete"
git push origin main --tags
```

---

## Post-MVP Enhancements (Future Tasks)

### Priority 1 - Better PDF Cleaning
- Header/footer detection (repeating text across pages)
- Page number removal (regex at page edges)
- Table detection and skipping (grid-like layout)
- Code block detection (monospace fonts)

### Priority 2 - EPUB Support
- Integrate EPUB parser library or build custom
- Extract content.opf for reading order
- Parse XHTML content files
- Handle embedded images/styles

### Priority 3 - Advanced Features
- 15-second skip backward (like podcasts)
- Manual bookmarks with names
- Export highlights
- iCloud sync
- URL import with article extraction
- Dark mode / themes

### Future - Cloud Voices
- Backend service with Google TTS
- Subscription via StoreKit 2
- Premium voice picker
- Usage tracking

---

## Troubleshooting

**Build errors:**
- Clean build folder: Product → Clean Build Folder (⌘⇧K)
- Restart Xcode
- Check all files are added to target membership

**Swift Data issues:**
- Delete app from simulator
- Clean build
- Run again (creates fresh database)

**TTS not working:**
- Check audio session configuration
- Test on real device (simulator audio limited)
- Check system volume is up

**Background audio not continuing:**
- Verify Background Modes capability added
- Check Info.plist has audio background mode
- Test on real device (not simulator)

---

## Success Criteria

MVP is complete when:
- ✅ Can import PDF and clipboard text
- ✅ PDF hyphenation is fixed (no "sam-ple" stuttering)
- ✅ Native TTS reads text with highlighting
- ✅ Can adjust speed and change voices
- ✅ Position saves and resumes correctly
- ✅ Background audio works with lock screen controls
- ✅ Settings persist preferences
- ✅ No crashes during normal use

**You're done!** The MVP is ready to use and can be built upon with the future enhancements.
