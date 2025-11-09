# VoxPDF Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace PDFKit-based PDF processing with VoxPDF for superior text extraction, TOC parsing, and performance.

**Architecture:** VoxPDF is a Rust library with Swift bindings that provides word-level, paragraph-level, and structured text extraction from PDFs. We'll integrate it as an XCFramework, create a Swift service wrapper, and replace DocumentProcessor's PDF extraction logic. The integration maintains backward compatibility with existing DocumentProcessor API while leveraging VoxPDF's superior extraction capabilities.

**Tech Stack:**
- VoxPDF (Rust + Swift bindings via XCFramework)
- Existing: DocumentProcessor, TOCService
- Integration: VoxPDFService (new)

**Context:**
- VoxPDF location: `../VoxPDF` (sibling directory)
- Current PDF processing: `DocumentProcessor.swift` uses PDFKit with custom paragraph joining/hyphenation logic
- Current TOC: `TOCService.swift` extracts from PDF metadata or detects headings
- Expected: Iterative development with bug fixes in parallel VoxPDF session

---

## Task 1: Build VoxPDF XCFramework

**Files:**
- External: `../VoxPDF/voxpdf-core/scripts/build-ios.sh`
- External: `../VoxPDF/voxpdf-core/scripts/create-xcframework.sh`
- Output: `../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework`

**Step 1: Verify VoxPDF directory structure**

```bash
cd ../VoxPDF
ls -la
```

Expected output: Should see `voxpdf-core/` and `voxpdf-swift/` directories

**Step 2: Navigate to voxpdf-core**

```bash
cd voxpdf-core
pwd
```

Expected: `/Users/zachswift/projects/VoxPDF/voxpdf-core`

**Step 3: Run iOS build script**

```bash
./scripts/build-ios.sh
```

Expected:
- Compiles Rust for iOS targets (arm64, simulator)
- Output in `target/` directory
- May take 2-5 minutes
- **If errors occur:** Note exact error, communicate to VoxPDF session for fix

**Step 4: Create XCFramework**

```bash
./scripts/create-xcframework.sh
```

Expected:
- Creates `build/VoxPDFCore.xcframework`
- Contains arm64, simulator slices
- **If errors occur:** Note exact error, communicate to VoxPDF session for fix

**Step 5: Verify XCFramework creation**

```bash
ls -lh build/VoxPDFCore.xcframework
```

Expected: Directory exists with Info.plist and architecture directories

**Step 6: Document build location**

No commit yet - external repo change

---

## Task 2: Add VoxPDF to Xcode Project

**Files:**
- Modify: `Listen2/Listen2/Listen2.xcodeproj/project.pbxproj` (via Xcode)
- Add: Copy `../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework` → `Frameworks/VoxPDFCore.xcframework`

**Step 1: Copy XCFramework to project**

```bash
cd /Users/zachswift/projects/Listen2
mkdir -p Frameworks
cp -R ../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework Frameworks/
```

Expected: Framework copied to `Frameworks/VoxPDFCore.xcframework`

**Step 2: Add to Git LFS tracking**

Update `.gitattributes`:

```bash
echo "Frameworks/VoxPDFCore.xcframework/** filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
```

**Step 3: Stage framework for Git LFS**

```bash
git add .gitattributes Frameworks/VoxPDFCore.xcframework/
```

**Step 4: Open Xcode project**

```bash
open Listen2/Listen2/Listen2.xcodeproj
```

**Step 5: Add framework to project (Manual - Xcode GUI)**

1. In Project Navigator, select `Listen2.xcodeproj`
2. Select `Listen2` target
3. Go to "General" tab
4. Scroll to "Frameworks, Libraries, and Embedded Content"
5. Click "+" button
6. Click "Add Other..." → "Add Files..."
7. Navigate to `Frameworks/VoxPDFCore.xcframework`
8. Select it and click "Open"
9. Ensure "Embed & Sign" is selected in the dropdown

**Step 6: Add Swift import bridging (if needed)**

VoxPDF should have Swift bindings already. Test by adding to any Swift file temporarily:

```swift
import VoxPDFCore
```

Build (Cmd+B). If it fails with "No such module", check framework search paths.

**Step 7: Commit framework addition**

```bash
git add Listen2/Listen2/Listen2.xcodeproj/project.pbxproj
git commit -m "feat: add VoxPDF XCFramework to project

- Add VoxPDFCore.xcframework to Frameworks/
- Configure Git LFS tracking for VoxPDF
- Link framework to Listen2 target"
```

---

## Task 3: Create VoxPDFService Wrapper

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/VoxPDFService.swift`

**Step 1: Write failing test first**

Create: `Listen2/Listen2Tests/Services/VoxPDFServiceTests.swift`

```swift
import XCTest
@testable import Listen2
import VoxPDFCore

final class VoxPDFServiceTests: XCTestCase {

    var sut: VoxPDFService!

    override func setUp() {
        super.setUp()
        sut = VoxPDFService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testExtractParagraphs_ValidPDF_ReturnsParagraphs() async throws {
        // Given: A test PDF file
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "test-document", withExtension: "pdf") else {
            XCTFail("Test PDF not found")
            return
        }

        // When: Extracting paragraphs
        let paragraphs = try await sut.extractParagraphs(from: pdfURL)

        // Then: Should return non-empty paragraphs
        XCTAssertFalse(paragraphs.isEmpty, "Should extract at least one paragraph")
        XCTAssertTrue(paragraphs.allSatisfy { !$0.isEmpty }, "No paragraph should be empty")
    }

    func testExtractText_ValidPDF_ReturnsWords() async throws {
        // Given: A test PDF file
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "test-document", withExtension: "pdf") else {
            XCTFail("Test PDF not found")
            return
        }

        // When: Extracting raw text
        let text = try await sut.extractText(from: pdfURL)

        // Then: Should return non-empty text
        XCTAssertFalse(text.isEmpty, "Should extract text content")
        XCTAssertTrue(text.contains(" "), "Text should contain spaces between words")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoxPDFServiceTests 2>&1 | tail -20
```

Expected: Build error - `VoxPDFService` not defined

**Step 3: Create minimal VoxPDFService**

Create: `Listen2/Listen2/Listen2/Services/VoxPDFService.swift`

```swift
//
//  VoxPDFService.swift
//  Listen2
//

import Foundation
import VoxPDFCore

/// Service for extracting text and structure from PDF documents using VoxPDF
final class VoxPDFService {

    enum VoxPDFError: Error {
        case invalidPDF
        case extractionFailed
        case unsupportedOperation
    }

    // MARK: - Public API

    /// Extract paragraphs from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Array of paragraph strings
    func extractParagraphs(from url: URL) async throws -> [String] {
        // TODO: Implement using VoxPDF paragraph extraction
        // For now, basic implementation to pass tests

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxPDFError.invalidPDF
        }

        // Load PDF data
        let data = try Data(contentsOf: url)

        // Use VoxPDF Swift API to extract paragraphs
        // This is placeholder - actual API may differ
        // Check VoxPDF documentation for exact method names
        do {
            let document = try VoxPDFCore.Document.load(from: data)
            let paragraphs = try document.extractParagraphs()

            return paragraphs.map { $0.text }
        } catch {
            throw VoxPDFError.extractionFailed
        }
    }

    /// Extract raw text from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Concatenated text content
    func extractText(from url: URL) async throws -> String {
        let paragraphs = try await extractParagraphs(from: url)
        return paragraphs.joined(separator: "\n\n")
    }

    /// Extract table of contents from PDF metadata
    /// - Parameters:
    ///   - url: URL to the PDF file
    ///   - paragraphs: Already extracted paragraphs for matching
    /// - Returns: Array of TOC entries with paragraph indices
    func extractTOC(from url: URL, paragraphs: [String]) async throws -> [TOCEntry] {
        // TODO: Implement using VoxPDF TOC extraction
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxPDFError.invalidPDF
        }

        let data = try Data(contentsOf: url)

        do {
            let document = try VoxPDFCore.Document.load(from: data)
            let tocItems = try document.extractTOC()

            // Convert VoxPDF TOC items to our TOCEntry model
            return tocItems.enumerated().map { index, item in
                // Find matching paragraph index
                let paragraphIndex = findParagraphIndex(for: item.title, in: paragraphs)

                return TOCEntry(
                    title: item.title,
                    paragraphIndex: paragraphIndex,
                    level: item.level
                )
            }
        } catch {
            throw VoxPDFError.extractionFailed
        }
    }

    // MARK: - Private Helpers

    /// Find the paragraph that best matches a TOC heading
    private func findParagraphIndex(for heading: String, in paragraphs: [String]) -> Int {
        let normalized = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Exact match
        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.lowercased() == normalized {
                return index
            }
        }

        // Starts with match
        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.lowercased().hasPrefix(normalized) {
                return index
            }
        }

        // Contains match (for longer headings)
        if normalized.count > 10 {
            for (index, paragraph) in paragraphs.enumerated() {
                if paragraph.lowercased().contains(normalized) {
                    return index
                }
            }
        }

        return 0 // Fallback
    }
}
```

**Step 4: Add test PDF resource**

```bash
# Create a simple test PDF or copy existing one
# For now, skip this - tests will be skipped if resource missing
# We'll test with real PDFs during integration
```

**Step 5: Build to verify compilation**

```bash
cd Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -i error
```

Expected: Build succeeds OR shows VoxPDF API errors (document actual API)

**Step 6: Update implementation based on actual VoxPDF API**

**STOP HERE - Check VoxPDF Swift API documentation**

The VoxPDF Swift bindings may have different method names than assumed above. Check:
- `../VoxPDF/voxpdf-swift/Sources/VoxPDFCore/` for actual Swift API
- Update `VoxPDFService` implementation to match real API

This is an **iteration point** - communicate with VoxPDF session if API unclear.

**Step 7: Commit service skeleton**

```bash
git add Listen2/Listen2/Listen2/Services/VoxPDFService.swift
git add Listen2/Listen2Tests/Services/VoxPDFServiceTests.swift
git commit -m "feat: add VoxPDFService with basic PDF extraction

- Create VoxPDFService wrapper for VoxPDF library
- Add paragraph and text extraction methods
- Add TOC extraction method
- Add unit tests (pending test resources)
- Implementation may need updates based on actual VoxPDF API"
```

---

## Task 4: Update DocumentProcessor to Use VoxPDF

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/DocumentProcessor.swift:42-113`

**Step 1: Add VoxPDF service dependency**

Update `DocumentProcessor.swift`:

```swift
final class DocumentProcessor {

    // MARK: - Dependencies

    private let voxPDFService = VoxPDFService()

    // ... rest of class
}
```

**Step 2: Update extractPDFText to use VoxPDF**

Replace `extractPDFText` method (lines 89-113):

```swift
private func extractPDFText(from url: URL) async throws -> [String] {
    // Use VoxPDF for superior extraction
    do {
        let paragraphs = try await voxPDFService.extractParagraphs(from: url)

        guard !paragraphs.isEmpty else {
            throw DocumentProcessorError.extractionFailed
        }

        return paragraphs
    } catch {
        print("⚠️ VoxPDF extraction failed: \(error), falling back to PDFKit")

        // Fallback to PDFKit if VoxPDF fails
        return try await extractPDFTextFallback(from: url)
    }
}

/// Fallback PDF extraction using PDFKit (original implementation)
private func extractPDFTextFallback(from url: URL) async throws -> [String] {
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

    let paragraphs = joinLinesIntoParagraphs(fullText)

    guard !paragraphs.isEmpty else {
        throw DocumentProcessorError.extractionFailed
    }

    return paragraphs
}
```

**Step 3: Keep existing paragraph joining logic as fallback**

Keep `joinLinesIntoParagraphs` and related methods unchanged - they're needed for PDFKit fallback.

**Step 4: Build and test**

```bash
cd Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -i error
```

Expected: Build succeeds (or VoxPDF API errors to fix)

**Step 5: Manual testing**

Run the app in simulator:

```bash
xcodebuild -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -quiet
```

1. Open the app
2. Import a PDF document
3. Check if text extraction works
4. Check console for VoxPDF vs PDFKit usage
5. **If errors:** Note exact error, communicate to VoxPDF session

**Step 6: Commit integration**

```bash
git add Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
git commit -m "feat: integrate VoxPDF into DocumentProcessor

- Use VoxPDFService for PDF text extraction
- Keep PDFKit as fallback if VoxPDF fails
- Maintain existing paragraph joining logic for fallback
- Add error logging for debugging"
```

---

## Task 5: Integrate VoxPDF TOC Extraction

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/DocumentProcessor.swift:55-85`
- Modify: `Listen2/Listen2/Listen2/Services/TOCService.swift`

**Step 1: Update extractTOCData to use VoxPDF**

In `DocumentProcessor.swift`, update the PDF case in `extractTOCData`:

```swift
func extractTOCData(from url: URL, sourceType: SourceType, paragraphs: [String]) async -> Data? {
    let entries: [TOCEntry]

    switch sourceType {
    case .pdf:
        // Try VoxPDF first
        do {
            entries = try await voxPDFService.extractTOC(from: url, paragraphs: paragraphs)

            if !entries.isEmpty {
                print("✅ VoxPDF extracted \(entries.count) TOC entries")
            } else {
                print("⚠️ VoxPDF returned empty TOC, falling back to PDFKit")
                throw DocumentProcessorError.extractionFailed
            }
        } catch {
            print("⚠️ VoxPDF TOC extraction failed: \(error), falling back to PDFKit")

            // Fallback to PDFKit metadata extraction
            guard let pdfDocument = PDFDocument(url: url) else {
                return nil
            }

            let tocService = TOCService()
            entries = tocService.extractTOCFromMetadata(pdfDocument, paragraphs: paragraphs)
        }

    case .epub:
        let extractor = EPUBExtractor()
        guard let tocEntries = try? await extractor.extractTOC(from: url, paragraphs: paragraphs) else {
            return nil
        }
        entries = tocEntries

    case .clipboard:
        return nil
    }

    guard !entries.isEmpty else {
        return nil
    }

    // Encode to JSON
    let encoder = JSONEncoder()
    return try? encoder.encode(entries)
}
```

**Step 2: Build and verify**

```bash
cd Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -i error
```

**Step 3: Manual TOC testing**

1. Run app in simulator
2. Import a PDF with a table of contents
3. Check if TOC navigation works
4. Verify TOC entries match document structure
5. Check console logs for VoxPDF vs PDFKit usage

**Step 4: Commit TOC integration**

```bash
git add Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
git commit -m "feat: use VoxPDF for TOC extraction

- Integrate VoxPDF TOC extraction in DocumentProcessor
- Keep PDFKit TOC metadata as fallback
- Add detailed logging for debugging
- Maintains existing EPUB TOC extraction"
```

---

## Task 6: Add Iteration Testing Documentation

**Files:**
- Create: `docs/voxpdf-integration-testing.md`

**Step 1: Create testing guide**

```markdown
# VoxPDF Integration Testing Guide

## Test Scenarios

### 1. Basic PDF Text Extraction

**Test:** Import simple PDF
**Expected:** Text extracted successfully via VoxPDF
**Check:** Console should show "VoxPDF" not "PDFKit fallback"

### 2. Complex PDF with Formatting

**Test:** Import PDF with:
- Multi-column layout
- Headers/footers
- Footnotes
- Tables

**Expected:** Clean paragraph extraction
**Check:** Paragraphs should be properly segmented

### 3. TOC Extraction

**Test:** Import PDF with embedded TOC
**Expected:** TOC entries correctly extracted
**Check:** Navigation to TOC items works

### 4. Fallback to PDFKit

**Test:** If VoxPDF fails (corrupt PDF, missing features)
**Expected:** Graceful fallback to PDFKit
**Check:** Console shows fallback message, extraction still works

## Bug Reporting to VoxPDF Session

When encountering VoxPDF issues:

1. **Capture the error:**
   - Exact error message
   - Console logs
   - PDF file characteristics (if possible, share file)

2. **Document the issue:**
   - What operation failed (text extraction, TOC, etc.)
   - Input PDF characteristics
   - Expected vs actual behavior

3. **Communicate to VoxPDF session:**
   - Share error details
   - Wait for fix
   - Rebuild XCFramework
   - Re-copy to Frameworks/
   - Re-test

## Iteration Workflow

```bash
# After VoxPDF session provides fix:

# 1. Rebuild VoxPDF
cd ../VoxPDF/voxpdf-core
./scripts/build-ios.sh
./scripts/create-xcframework.sh

# 2. Update framework in Listen2
cd /Users/zachswift/projects/Listen2
rm -rf Frameworks/VoxPDFCore.xcframework
cp -R ../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework Frameworks/

# 3. Clean Xcode build
cd Listen2/Listen2
rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*

# 4. Rebuild and test
xcodebuild clean build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'

# 5. Re-run manual tests
```

## Known Issues

(Document issues as they arise during integration)

- Issue 1: [Description]
  - Status: [Reported to VoxPDF / Fixed / Workaround]
  - Workaround: [If applicable]

- Issue 2: [Description]
  - Status: [Reported to VoxPDF / Fixed / Workaround]
  - Workaround: [If applicable]
```

**Step 2: Commit testing documentation**

```bash
git add docs/voxpdf-integration-testing.md
git commit -m "docs: add VoxPDF integration testing guide

- Document test scenarios
- Add bug reporting process to VoxPDF session
- Document iteration workflow for framework updates
- Add known issues section for tracking"
```

---

## Task 7: Integration with Piper TTS

**Files:**
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`

**Step 1: Verify TTS integration point**

Read `ReaderViewModel.swift` to find where paragraphs are fed to TTS:

```bash
cd /Users/zachswift/projects/Listen2
grep -n "tts" Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift -i
```

**Step 2: Check if paragraph quality affects TTS**

VoxPDF's superior paragraph extraction should improve TTS quality:
- Better sentence boundaries
- Proper handling of hyphenation
- Cleaner text (no artifacts)

This should "just work" since we're replacing `extractParagraphs` upstream.

**Step 3: Manual TTS testing**

1. Run app
2. Import a PDF
3. Start TTS playback
4. Listen for:
   - Improved pronunciation (fewer artifacts)
   - Better sentence flow
   - Proper pauses at paragraph breaks

**Step 4: Document TTS improvements**

If TTS quality improves, document in:

```markdown
# VoxPDF + Piper TTS Integration

## Improvements from VoxPDF

- **Better sentence segmentation:** VoxPDF's paragraph extraction creates cleaner boundaries
- **Hyphenation handling:** No more awkward "inter- ruption" pronunciations
- **Artifact removal:** Fewer PDF encoding artifacts in text
- **Consistent paragraph structure:** More natural TTS flow

## Testing

Compare before/after:
1. Same PDF document
2. Same passage
3. Note pronunciation differences
```

Add to existing `PIPER_TTS_SPIKE.md` or create new doc.

**Step 5: Commit if changes needed**

```bash
# Only if ReaderViewModel changes needed
git add Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift
git commit -m "feat: improve TTS quality with VoxPDF text extraction"
```

---

## Task 8: Word-Level Highlighting with VoxPDF

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/VoxPDFService.swift`
- Create: `Listen2/Listen2/Listen2/Models/WordPosition.swift`
- Modify: `Listen2/Listen2/Listen2/Services/DocumentProcessor.swift`
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`
- Create: `Listen2/Listen2Tests/Services/WordPositionTests.swift`

**Context:** The app already has `currentWordRange: Range<String.Index>?` for word highlighting, but it doesn't work well with PDFs because PDFKit lacks word-level extraction. VoxPDF provides word-level text extraction with positions, enabling accurate word highlighting during TTS playback.

**Step 1: Explore VoxPDF word-level API**

Check VoxPDF Swift API for word extraction:

```bash
cd ../VoxPDF/voxpdf-swift
grep -r "word" Sources/ -i | head -20
```

Expected: Find methods like `extractWords()`, `Word` type with text and position

**Step 2: Define WordPosition model**

Create: `Listen2/Listen2/Listen2/Models/WordPosition.swift`

```swift
//
//  WordPosition.swift
//  Listen2
//

import Foundation

/// Represents a word with its position in the document
struct WordPosition: Codable, Equatable {
    /// The word text
    let text: String

    /// Character offset in the combined paragraph text
    let characterOffset: Int

    /// Character length of the word
    let length: Int

    /// Index of the paragraph this word belongs to
    let paragraphIndex: Int

    /// Page number (0-indexed)
    let pageNumber: Int

    /// Computed range in the paragraph text
    var range: Range<String.Index>? {
        // This will be computed when matching against actual paragraph text
        return nil
    }
}

/// Maps paragraph indices to their word positions
struct DocumentWordMap: Codable {
    /// Array of all words in document order
    let words: [WordPosition]

    /// Quick lookup: paragraph index -> word positions
    private(set) var wordsByParagraph: [Int: [WordPosition]] = [:]

    init(words: [WordPosition]) {
        self.words = words
        self.wordsByParagraph = Dictionary(grouping: words, by: { $0.paragraphIndex })
    }

    /// Get words for a specific paragraph
    func words(for paragraphIndex: Int) -> [WordPosition] {
        return wordsByParagraph[paragraphIndex] ?? []
    }

    /// Find word at character offset within a paragraph
    func word(at offset: Int, in paragraphIndex: Int) -> WordPosition? {
        let paragraphWords = words(for: paragraphIndex)
        return paragraphWords.first { word in
            offset >= word.characterOffset && offset < word.characterOffset + word.length
        }
    }
}
```

**Step 3: Add word extraction to VoxPDFService**

Update `VoxPDFService.swift`:

```swift
/// Extract word-level positions from PDF
/// - Parameter url: URL to the PDF file
/// - Returns: Document word map for word-level navigation
func extractWordPositions(from url: URL) async throws -> DocumentWordMap {
    try validatePDF(at: url)

    let data = try Data(contentsOf: url)

    do {
        let document = try VoxPDFCore.Document.load(from: data)

        // VoxPDF API - adjust based on actual API
        let pages = try document.extractPages()

        var allWords: [WordPosition] = []
        var paragraphIndex = 0
        var characterOffset = 0

        for (pageIndex, page) in pages.enumerated() {
            let pageWords = try page.extractWords()

            for voxWord in pageWords {
                // Check if this word starts a new paragraph
                // VoxPDF should provide paragraph boundaries
                let isNewParagraph = voxWord.startsNewParagraph // API TBD

                if isNewParagraph && !allWords.isEmpty {
                    paragraphIndex += 1
                    characterOffset = 0
                }

                let wordPos = WordPosition(
                    text: voxWord.text,
                    characterOffset: characterOffset,
                    length: voxWord.text.count,
                    paragraphIndex: paragraphIndex,
                    pageNumber: pageIndex
                )

                allWords.append(wordPos)
                characterOffset += voxWord.text.count + 1 // +1 for space
            }
        }

        return DocumentWordMap(words: allWords)
    } catch {
        throw VoxPDFError.extractionFailed(underlying: error)
    }
}
```

**Step 4: Update DocumentProcessor to extract and store word map**

Modify `DocumentProcessor.swift` to optionally extract word positions:

```swift
/// Extract word positions for word-level highlighting (PDF only)
/// Returns nil for non-PDF sources or if extraction fails
func extractWordPositions(from url: URL, sourceType: SourceType) async -> DocumentWordMap? {
    guard sourceType == .pdf else {
        return nil
    }

    do {
        let wordMap = try await voxPDFService.extractWordPositions(from: url)
        print("✅ Extracted \(wordMap.words.count) words for highlighting")
        return wordMap
    } catch {
        print("⚠️ Word position extraction failed: \(error), word highlighting unavailable")
        return nil
    }
}
```

**Step 5: Add word map to Document model**

Check if `Document` model needs to store word map:

```bash
grep -n "class Document" Listen2/Listen2/Listen2/Models/*.swift
```

If `Document` is a SwiftData model, add optional word map data:

```swift
// In Document model
@Attribute(.externalStorage)
var wordMapData: Data?

// Helper to decode word map
var wordMap: DocumentWordMap? {
    guard let data = wordMapData else { return nil }
    return try? JSONDecoder().decode(DocumentWordMap.self, from: data)
}
```

**Step 6: Write tests for word positioning**

Create: `Listen2/Listen2Tests/Services/WordPositionTests.swift`

```swift
import XCTest
@testable import Listen2

final class WordPositionTests: XCTestCase {

    func testWordPosition_RangeCalculation() {
        let word = WordPosition(
            text: "Hello",
            characterOffset: 0,
            length: 5,
            paragraphIndex: 0,
            pageNumber: 0
        )

        XCTAssertEqual(word.text, "Hello")
        XCTAssertEqual(word.length, 5)
    }

    func testDocumentWordMap_WordsByParagraph() {
        let words = [
            WordPosition(text: "First", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "word", characterOffset: 6, length: 4, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "Second", characterOffset: 0, length: 6, paragraphIndex: 1, pageNumber: 0),
            WordPosition(text: "paragraph", characterOffset: 7, length: 9, paragraphIndex: 1, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        let paragraph0Words = wordMap.words(for: 0)
        XCTAssertEqual(paragraph0Words.count, 2)
        XCTAssertEqual(paragraph0Words[0].text, "First")
        XCTAssertEqual(paragraph0Words[1].text, "word")

        let paragraph1Words = wordMap.words(for: 1)
        XCTAssertEqual(paragraph1Words.count, 2)
        XCTAssertEqual(paragraph1Words[0].text, "Second")
    }

    func testDocumentWordMap_FindWordAtOffset() {
        let words = [
            WordPosition(text: "Hello", characterOffset: 0, length: 5, paragraphIndex: 0, pageNumber: 0),
            WordPosition(text: "world", characterOffset: 6, length: 5, paragraphIndex: 0, pageNumber: 0),
        ]

        let wordMap = DocumentWordMap(words: words)

        // Find "Hello" at offset 2
        let word1 = wordMap.word(at: 2, in: 0)
        XCTAssertEqual(word1?.text, "Hello")

        // Find "world" at offset 7
        let word2 = wordMap.word(at: 7, in: 0)
        XCTAssertEqual(word2?.text, "world")

        // Out of range
        let word3 = wordMap.word(at: 100, in: 0)
        XCTAssertNil(word3)
    }
}
```

**Step 7: Integrate word map with TTS service**

Check `TTSService.swift` to see how it reports word progress:

```bash
grep -n "currentProgress\|wordRange" Listen2/Listen2/Listen2/Services/TTSService.swift
```

The TTS service should already have word boundary callbacks from AVSpeechSynthesizer. Update it to use word map if available:

```swift
// In TTSService.swift
private var wordMap: DocumentWordMap?

func startReading(paragraphs: [String], from index: Int, title: String, wordMap: DocumentWordMap? = nil) {
    self.wordMap = wordMap
    // ... existing code
}

// In AVSpeechSynthesizerDelegate
func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                       willSpeakRangeOfSpeechString characterRange: NSRange,
                       utterance: AVSpeechUtterance) {
    if let wordMap = wordMap {
        // Use word map for precise positioning
        let word = wordMap.word(at: characterRange.location, in: currentParagraphIndex)
        if let word = word {
            currentProgress.wordRange = ... // Calculate range from word
        }
    } else {
        // Fallback: use character range directly (existing behavior)
        currentProgress.wordRange = convertNSRangeToRange(characterRange, in: currentParagraph)
    }
}
```

**Step 8: Update document import to extract word map**

In the document import flow (likely `LibraryViewModel` or similar), extract word map during import:

```swift
// After extracting paragraphs
let wordMap = await documentProcessor.extractWordPositions(from: url, sourceType: sourceType)
if let wordMap = wordMap {
    let encoder = JSONEncoder()
    document.wordMapData = try? encoder.encode(wordMap)
}
```

**Step 9: Manual testing**

```bash
cd Listen2/Listen2
xcodebuild -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'
```

Test procedure:
1. Import a PDF document
2. Start TTS playback
3. Observe word highlighting in the UI
4. Verify:
   - Words highlight in sync with speech
   - Highlighting advances smoothly
   - Correct word is highlighted
5. Test with different playback speeds
6. Test navigation (skip forward/back)

**Step 10: Handle edge cases**

Add error handling for:
- PDFs where word extraction fails (fall back to no highlighting)
- Mismatched word positions vs actual text
- Empty word maps

**Step 11: Commit word highlighting**

```bash
git add Listen2/Listen2/Listen2/Models/WordPosition.swift
git add Listen2/Listen2/Listen2/Services/VoxPDFService.swift
git add Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git add Listen2/Listen2Tests/Services/WordPositionTests.swift
git commit -m "feat: implement word-level highlighting for PDFs with VoxPDF

- Add WordPosition model for word-level tracking
- Add DocumentWordMap for efficient word lookup
- Extend VoxPDFService to extract word positions
- Store word map in Document model
- Integrate word map with TTS progress tracking
- Add fallback for non-PDF or extraction failures
- Add unit tests for word positioning

Enables accurate word highlighting during TTS playback for PDFs"
```

**Step 12: Document limitations and future work**

Create/update docs:

```markdown
# Word Highlighting

## Current Implementation

- **PDFs:** Full word-level highlighting via VoxPDF
- **EPUB:** Character-range approximation (no word positions)
- **Clipboard:** Character-range approximation (no word positions)

## How It Works

1. During PDF import, VoxPDF extracts word positions
2. Word map stored with document (JSON, external storage)
3. During TTS playback, word map maps speech ranges to UI ranges
4. ReaderView highlights current word using `currentWordRange`

## Known Limitations

- Word map increases document storage (~5-10% of PDF size)
- Only available for PDFs (not EPUB or clipboard)
- Requires VoxPDF extraction to succeed
- Performance: word lookup is O(n) for paragraph words

## Future Improvements

- Add word highlighting for EPUB using HTML parsing
- Optimize word lookup with binary search
- Cache word ranges for current paragraph
- Add smooth animation between word highlights
```

---

## Task 9: Performance Testing

**Files:**
- Create: `Listen2/Listen2Tests/Performance/VoxPDFPerformanceTests.swift`

**Step 1: Write performance test**

```swift
import XCTest
@testable import Listen2

final class VoxPDFPerformanceTests: XCTestCase {

    func testPDFExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()

        measure {
            let expectation = XCTestExpectation(description: "Extract paragraphs")

            Task {
                _ = try await service.extractParagraphs(from: pdfURL)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testTOCExtractionPerformance() throws {
        let testBundle = Bundle(for: type(of: self))
        guard let pdfURL = testBundle.url(forResource: "large-document", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not available")
        }

        let service = VoxPDFService()
        let paragraphs = ["Sample"] // Simplified for performance test

        measure {
            let expectation = XCTestExpectation(description: "Extract TOC")

            Task {
                _ = try await service.extractTOC(from: pdfURL, paragraphs: paragraphs)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }
}
```

**Step 2: Run performance baseline**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/VoxPDFPerformanceTests 2>&1 | grep "Time:"
```

**Step 3: Document baseline**

Create: `docs/performance-baseline.md`

```markdown
# Performance Baseline

## VoxPDF vs PDFKit

### Text Extraction (100-page PDF)

- VoxPDF: [X.XX seconds]
- PDFKit: [Y.YY seconds]
- Improvement: [Z%]

### TOC Extraction

- VoxPDF: [X.XX seconds]
- PDFKit: [Y.YY seconds]
- Improvement: [Z%]

## Notes

- Tested on: iPhone 15 Simulator
- Date: 2025-11-09
- VoxPDF version: [check version]
```

**Step 4: Commit performance tests**

```bash
git add Listen2/Listen2Tests/Performance/VoxPDFPerformanceTests.swift
git add docs/performance-baseline.md
git commit -m "test: add VoxPDF performance benchmarks

- Add performance tests for text and TOC extraction
- Document baseline metrics
- Compare against PDFKit performance"
```

---

## Task 10: Error Handling and Edge Cases

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/VoxPDFService.swift`

**Step 1: Add comprehensive error handling**

Update `VoxPDFService`:

```swift
enum VoxPDFError: Error, LocalizedError {
    case invalidPDF
    case extractionFailed(underlying: Error)
    case unsupportedOperation
    case emptyDocument
    case corruptedStructure

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "The PDF file is invalid or cannot be opened"
        case .extractionFailed(let error):
            return "Failed to extract content: \(error.localizedDescription)"
        case .unsupportedOperation:
            return "This operation is not yet supported"
        case .emptyDocument:
            return "The PDF document is empty"
        case .corruptedStructure:
            return "The PDF structure is corrupted or malformed"
        }
    }
}
```

**Step 2: Add validation**

```swift
private func validatePDF(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw VoxPDFError.invalidPDF
    }

    guard url.pathExtension.lowercased() == "pdf" else {
        throw VoxPDFError.invalidPDF
    }

    let data = try Data(contentsOf: url)
    guard !data.isEmpty else {
        throw VoxPDFError.emptyDocument
    }

    // PDF magic number check
    let pdfHeader = Data([0x25, 0x50, 0x44, 0x46]) // "%PDF"
    guard data.prefix(4) == pdfHeader else {
        throw VoxPDFError.invalidPDF
    }
}
```

**Step 3: Update extraction methods with validation**

```swift
func extractParagraphs(from url: URL) async throws -> [String] {
    try validatePDF(at: url)

    let data = try Data(contentsOf: url)

    do {
        let document = try VoxPDFCore.Document.load(from: data)
        let paragraphs = try document.extractParagraphs()

        guard !paragraphs.isEmpty else {
            throw VoxPDFError.emptyDocument
        }

        return paragraphs.map { $0.text }
    } catch let error as VoxPDFError {
        throw error
    } catch {
        throw VoxPDFError.extractionFailed(underlying: error)
    }
}
```

**Step 4: Test error cases**

```bash
# Try with invalid file
# Try with empty PDF
# Try with corrupted PDF
# Document results
```

**Step 5: Commit error handling**

```bash
git add Listen2/Listen2/Listen2/Services/VoxPDFService.swift
git commit -m "feat: add comprehensive error handling to VoxPDFService

- Add detailed VoxPDFError types with descriptions
- Add PDF validation before extraction
- Wrap underlying VoxPDF errors
- Improve error messages for debugging"
```

---

## Task 11: Update Git LFS and Push

**Files:**
- Modify: `.gitattributes`
- Add: `Frameworks/VoxPDFCore.xcframework/` (if not already)

**Step 1: Verify LFS tracking**

```bash
git lfs ls-files | grep VoxPDF
```

Expected: VoxPDF framework files should be listed

**Step 2: Check framework size**

```bash
du -sh Frameworks/VoxPDFCore.xcframework
```

**Step 3: Stage and commit framework**

```bash
git add Frameworks/VoxPDFCore.xcframework/
git commit -m "feat: add VoxPDF XCFramework (Git LFS)

- Add VoxPDFCore.xcframework for PDF processing
- Size: [X MB]
- Platforms: iOS arm64, simulator"
```

**Step 4: Push to remote**

```bash
git push origin main
```

Expected: LFS objects uploaded

**Step 5: Verify remote**

```bash
git lfs ls-files --size | grep VoxPDF
```

---

## Iteration and Bug Fix Workflow

Throughout this integration, expect to iterate with the VoxPDF session:

### When VoxPDF API is unclear:

1. Read VoxPDF Swift source: `../VoxPDF/voxpdf-swift/Sources/VoxPDFCore/`
2. Check for example usage
3. Ask VoxPDF session to clarify API

### When encountering bugs:

1. Capture exact error message
2. Create minimal reproduction case
3. Report to VoxPDF session with:
   - Error message
   - Input PDF (if shareable)
   - Expected behavior
   - Actual behavior

### After VoxPDF fix:

1. Rebuild XCFramework (Task 1)
2. Replace framework: `rm -rf Frameworks/VoxPDFCore.xcframework && cp -R ../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework Frameworks/`
3. Clean build: `rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*`
4. Test again

### Success Criteria:

- ✅ VoxPDF extracts paragraphs from typical PDFs
- ✅ TOC extraction works for PDFs with outlines
- ✅ Performance is acceptable (< 2s for 100-page PDF)
- ✅ Graceful fallback to PDFKit when VoxPDF fails
- ✅ TTS quality improves with cleaner text
- ✅ No crashes or memory leaks

---

## Post-Integration Tasks

After basic integration works:

1. **Remove deprecated code:** Consider removing `joinLinesIntoParagraphs` if VoxPDF fully replaces it
2. **Update documentation:** Add VoxPDF to architecture docs
3. **Add to README:** Document VoxPDF dependency
4. **Performance tuning:** Profile and optimize if needed
5. **Add more tests:** Edge cases, regression tests
6. **Consider features:** Word-level extraction, metadata, annotations

---

## Notes for Engineer

**VoxPDF API Assumptions:**

The plan assumes VoxPDF Swift API like:
```swift
let document = try VoxPDFCore.Document.load(from: Data)
let paragraphs = try document.extractParagraphs()
let toc = try document.extractTOC()
```

**Check actual API in:** `../VoxPDF/voxpdf-swift/Sources/VoxPDFCore/`

If API differs significantly, update `VoxPDFService.swift` accordingly and document changes.

**Testing Strategy:**

- Unit tests (where possible with test PDFs)
- Manual testing with real documents
- Iteration with VoxPDF session for bug fixes
- Keep PDFKit fallback during development

**DRY Principle:**

- Reuse existing `TOCEntry` model
- Reuse existing error types where applicable
- Don't duplicate paragraph matching logic

**YAGNI Principle:**

- Start with basic paragraph and TOC extraction
- Don't implement word-level extraction until needed
- Don't add advanced features (annotations, etc.) yet

**TDD Approach:**

- Write tests first (where feasible)
- Some tests skipped if resources unavailable
- Focus on integration testing with real PDFs

**Frequent Commits:**

- Commit after each task
- Descriptive commit messages
- Keep commits atomic (one logical change)

---

## Plan Complete

**Next Steps:**

Choose execution approach:

**Option 1: Subagent-Driven (this session)**
- Use superpowers:subagent-driven-development
- Fresh subagent per task
- Code review between tasks
- Fast iteration

**Option 2: Parallel Session (separate)**
- Open new session in worktree
- Use superpowers:executing-plans
- Batch execution with checkpoints
