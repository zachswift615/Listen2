//
//  PDFWordHighlightingIntegrationTests.swift
//  Listen2Tests
//
//  Integration test reproducing real-world PDF + TTS highlighting scenario
//  Tests actual user workflow: PDF → Chapter 2 → Lessac Voice → Word Highlighting Data
//

import XCTest
import PDFKit
@testable import Listen2

/// Integration tests for word highlighting with real PDF documents
/// Reproduces exact user scenario to validate highlighting data correctness
final class PDFWordHighlightingIntegrationTests: XCTestCase {

    var voiceManager: VoiceManager!
    var ttsProvider: PiperTTSProvider!
    var alignmentService: PhonemeAlignmentService!
    var testDocumentID: UUID!

    // PDF test file path
    let pdfPath = "/Users/zachswift/Downloads/Building Applications with AI Agents Designing and Implementing Multiagent Systems (Michael Albada).pdf"

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Skip if PDF file doesn't exist
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            throw XCTSkip("Test PDF file not found at: \(pdfPath)")
        }

        // Get app bundle (test bundle is injected into app, so we can access app resources)
        guard let appBundle = Bundle(identifier: "com.zachswift.Listen2") else {
            throw XCTSkip("Could not locate app bundle - ensure test runs with host application")
        }

        print("[Test Setup] Using app bundle: \(appBundle.bundlePath)")

        // Initialize components with app bundle
        voiceManager = VoiceManager(bundle: appBundle)
        testDocumentID = UUID()

        // Get Lessac (High Quality) voice
        let allVoices = voiceManager.availableVoices()
        guard let lessacVoice = allVoices.first(where: {
            $0.name.lowercased().contains("lessac") && $0.quality.lowercased().contains("high")
        }) else {
            throw XCTSkip("Lessac (High Quality) voice not found")
        }

        print("[Test Setup] Using voice: \(lessacVoice.name)")

        // Initialize TTS provider with Lessac voice
        ttsProvider = PiperTTSProvider(
            voiceID: lessacVoice.id,
            voiceManager: voiceManager
        )

        // Initialize alignment service
        alignmentService = PhonemeAlignmentService()

        // Initialize TTS
        try await ttsProvider.initialize()
    }

    override func tearDown() async throws {
        alignmentService = nil
        ttsProvider = nil
        voiceManager = nil
        testDocumentID = nil

        try await super.tearDown()
    }

    // MARK: - Integration Tests

    /// Test complete flow: PDF → Chapter 2 → Synthesis → Phoneme Data → Word Highlighting
    /// This reproduces the exact scenario the user reported as broken
    func testChapter2WordHighlightingData() async throws {
        // Step 1: Load PDF document using PDFKit
        print("\n=== Step 1: Loading PDF ===")
        let pdfURL = URL(fileURLWithPath: pdfPath)

        guard let document = PDFDocument(url: pdfURL) else {
            XCTFail("Failed to load PDF document")
            return
        }

        print("PDF loaded: \(document.pageCount) pages")

        // Step 2: Find Chapter 2 in outline
        print("\n=== Step 2: Finding Chapter 2 ===")
        guard let chapter2Page = findChapter2Page(in: document) else {
            throw XCTSkip("Could not find Chapter 2 in PDF outline")
        }

        print("Found Chapter 2 page: \(chapter2Page)")

        // Step 3: Extract text from Chapter 2 page
        print("\n=== Step 3: Extracting text ===")
        guard let page = document.page(at: chapter2Page) else {
            XCTFail("Could not load Chapter 2 page")
            return
        }

        let pageText = page.string ?? ""
        guard !pageText.isEmpty else {
            XCTFail("Chapter 2 page has no text")
            return
        }

        // Extract first paragraph (up to first double newline or 500 chars, whichever comes first)
        let firstParagraph = extractFirstParagraph(from: pageText)
        print("Extracted paragraph (\(firstParagraph.count) chars):")
        print("  First 100 chars: '\(String(firstParagraph.prefix(100)))...'")

        // Step 4: Synthesize with Lessac voice
        print("\n=== Step 4: Synthesizing with Lessac ===")
        let synthesisResult = try await ttsProvider.synthesize(firstParagraph, speed: 1.0)

        print("Synthesis complete:")
        print("  Audio data: \(synthesisResult.audioData.count) bytes")
        print("  Phonemes: \(synthesisResult.phonemes.count)")
        print("  Normalized text length: \(synthesisResult.normalizedText.count)")

        // Step 5: Extract word map from PDF (simulate VoxPDF word extraction)
        print("\n=== Step 5: Creating word map ===")
        let wordMap = createWordMapFromText(firstParagraph, paragraphIndex: 0)
        print("Word map: \(wordMap.words.count) words")

        // Step 6: Perform phoneme alignment
        print("\n=== Step 6: Performing phoneme alignment ===")
        let alignment = try await alignmentService.align(
            phonemes: synthesisResult.phonemes,
            text: firstParagraph,
            normalizedText: synthesisResult.normalizedText,
            charMapping: synthesisResult.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        print("Alignment complete:")
        print("  Word timings: \(alignment.wordTimings.count)")
        print("  Total duration: \(String(format: "%.2f", alignment.totalDuration))s")

        // Step 7: Validate the highlighting data
        print("\n=== Step 7: Validating highlighting data ===")
        try validateHighlightingData(
            alignment: alignment,
            synthesisResult: synthesisResult,
            originalText: firstParagraph
        )

        print("\n✅ All validation checks passed!")
    }

    /// Validate that highlighting data meets correctness criteria
    private func validateHighlightingData(
        alignment: AlignmentResult,
        synthesisResult: SynthesisResult,
        originalText: String
    ) throws {
        let phonemes = synthesisResult.phonemes
        let wordTimings = alignment.wordTimings

        // Count actual words in original text
        let actualWordCount = originalText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        print("\n--- Validation Checks ---")

        // CHECK 1: Phoneme count is reasonable (3-5 phonemes per word is typical)
        let phonemesPerWord = Double(phonemes.count) / Double(actualWordCount)
        print("✓ CHECK 1: Phonemes per word: \(String(format: "%.1f", phonemesPerWord))")
        XCTAssertGreaterThan(phonemesPerWord, 2.0, "Should have at least 2 phonemes per word")
        XCTAssertLessThan(phonemesPerWord, 10.0, "Should have at most 10 phonemes per word")

        // CHECK 2: Word timing count matches actual word count (within reasonable range)
        let wordCountRatio = Double(wordTimings.count) / Double(actualWordCount)
        print("✓ CHECK 2: Word timing count: \(wordTimings.count) vs actual: \(actualWordCount) (ratio: \(String(format: "%.2f", wordCountRatio)))")
        XCTAssertGreaterThan(wordCountRatio, 0.7, "Should align at least 70% of words")
        XCTAssertLessThan(wordCountRatio, 1.5, "Should not have > 150% word timings")

        // CHECK 3: All phoneme durations are positive and reasonable
        var negativeCount = 0
        var hugeCount = 0
        var totalDuration: TimeInterval = 0

        for phoneme in phonemes {
            totalDuration += phoneme.duration

            if phoneme.duration < 0 {
                negativeCount += 1
            }

            if phoneme.duration > 1.0 { // Phonemes rarely exceed 1 second
                hugeCount += 1
            }
        }

        print("✓ CHECK 3: Phoneme durations:")
        print("    Total duration: \(String(format: "%.2f", totalDuration))s")
        print("    Negative durations: \(negativeCount)")
        print("    Huge durations (>1s): \(hugeCount)")

        XCTAssertEqual(negativeCount, 0, "Should have NO negative phoneme durations")
        XCTAssertLessThan(hugeCount, phonemes.count / 10, "Should have < 10% huge durations")

        // CHECK 4: Word durations are in reasonable range
        var negativeWordDurations = 0
        var hugeWordDurations = 0

        for wordTiming in wordTimings {
            if wordTiming.duration < 0 {
                negativeWordDurations += 1
                print("    ⚠️ Negative duration for word: '\(wordTiming.text)' @ \(wordTiming.startTime)s for \(wordTiming.duration)s")
            }

            if wordTiming.duration > 5.0 { // Words rarely exceed 5 seconds
                hugeWordDurations += 1
                print("    ⚠️ Huge duration for word: '\(wordTiming.text)' @ \(wordTiming.startTime)s for \(wordTiming.duration)s")
            }
        }

        print("✓ CHECK 4: Word durations:")
        print("    Negative durations: \(negativeWordDurations)")
        print("    Huge durations (>5s): \(hugeWordDurations)")

        XCTAssertEqual(negativeWordDurations, 0, "Should have NO negative word durations")
        XCTAssertEqual(hugeWordDurations, 0, "Should have NO huge word durations")

        // CHECK 5: Words are in chronological order
        var outOfOrderCount = 0
        for i in 1..<wordTimings.count {
            let prev = wordTimings[i-1]
            let curr = wordTimings[i]

            if curr.startTime < prev.startTime {
                outOfOrderCount += 1
                print("    ⚠️ Out of order: '\(prev.text)' @ \(prev.startTime)s -> '\(curr.text)' @ \(curr.startTime)s")
            }
        }

        print("✓ CHECK 5: Word timing order:")
        print("    Out of order: \(outOfOrderCount)")

        XCTAssertEqual(outOfOrderCount, 0, "Words should be in chronological order")

        // CHECK 6: No duplicate or overlapping word time ranges
        var overlapCount = 0
        for i in 1..<wordTimings.count {
            let prev = wordTimings[i-1]
            let curr = wordTimings[i]

            let prevEnd = prev.startTime + prev.duration
            if curr.startTime < prevEnd {
                overlapCount += 1
            }
        }

        print("✓ CHECK 6: Overlapping word ranges: \(overlapCount)")
        XCTAssertLessThan(overlapCount, wordTimings.count / 10, "Should have < 10% overlaps")

        // CHECK 7: Total duration is reasonable
        let durationPerWord = alignment.totalDuration / Double(actualWordCount)
        print("✓ CHECK 7: Duration per word: \(String(format: "%.2f", durationPerWord))s")
        XCTAssertGreaterThan(durationPerWord, 0.1, "Duration per word should be > 0.1s")
        XCTAssertLessThan(durationPerWord, 2.0, "Duration per word should be < 2s")

        // CHECK 8: Normalized text matches original (first word check)
        let normalizedWords = synthesisResult.normalizedText.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let originalWords = originalText.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let firstWordsMatch = normalizedWords.first?.prefix(3) == originalWords.first?.prefix(3)
        print("✓ CHECK 8: Text contamination check:")
        print("    Original first word: '\(originalWords.first ?? "NONE")'")
        print("    Normalized first word: '\(normalizedWords.first ?? "NONE")'")
        print("    Match: \(firstWordsMatch)")

        XCTAssertTrue(firstWordsMatch, "Normalized text should start with same word as original (text contamination check)")

        // Print sample word timings
        print("\n--- Sample Word Timings (first 10 words) ---")
        for (index, wordTiming) in wordTimings.prefix(10).enumerated() {
            print("  [\(index)] '\(wordTiming.text)' @ \(String(format: "%.3f", wordTiming.startTime))s for \(String(format: "%.3f", wordTiming.duration))s")
        }
    }

    // MARK: - Helper Methods

    /// Find Chapter 2 page index in PDF outline
    private func findChapter2Page(in document: PDFDocument) -> Int? {
        guard let outline = document.outlineRoot else {
            // No outline, try to find by searching text
            return findChapter2ByTextSearch(in: document)
        }

        // Search outline for Chapter 2
        return searchOutline(outline, for: "chapter 2")
    }

    /// Search PDF outline recursively for matching title
    private func searchOutline(_ outline: PDFOutline, for searchText: String) -> Int? {
        // Check this node
        if let label = outline.label?.lowercased(),
           (label.contains(searchText) || label == searchText) {
            if let destination = outline.destination,
               let page = destination.page {
                return document(page: page)
            }
        }

        // Search children
        for i in 0..<outline.numberOfChildren {
            if let child = outline.child(at: i),
               let pageIndex = searchOutline(child, for: searchText) {
                return pageIndex
            }
        }

        return nil
    }

    /// Get page index from PDFPage
    private func document(page: PDFPage) -> Int? {
        return page.document?.index(for: page)
    }

    /// Fallback: Find Chapter 2 by searching page text
    private func findChapter2ByTextSearch(in document: PDFDocument) -> Int? {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let text = page.string else {
                continue
            }

            // Look for "CHAPTER 2" or "Chapter 2" at start of page
            let firstLine = text.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if firstLine.lowercased().contains("chapter 2") {
                return pageIndex
            }
        }

        return nil
    }

    /// Extract first paragraph from text
    private func extractFirstParagraph(from text: String) -> String {
        // Find first double newline or take first 500 characters
        if let doubleNewlineRange = text.range(of: "\n\n") {
            let firstParagraph = String(text[..<doubleNewlineRange.lowerBound])
            return firstParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // No double newline found, take first sentence or 500 chars
        let truncated = String(text.prefix(500))
        return truncated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create word map from text (simulates VoxPDF word extraction)
    private func createWordMapFromText(_ text: String, paragraphIndex: Int) -> DocumentWordMap {
        var words: [WordPosition] = []
        var characterOffset = 0

        // Split text into words
        let components = text.components(separatedBy: .whitespacesAndNewlines)

        for component in components {
            guard !component.isEmpty else {
                characterOffset += 1
                continue
            }

            words.append(WordPosition(
                text: component,
                characterOffset: characterOffset,
                length: component.count,
                paragraphIndex: paragraphIndex,
                pageNumber: 0
            ))

            characterOffset += component.count + 1
        }

        return DocumentWordMap(words: words)
    }
}
