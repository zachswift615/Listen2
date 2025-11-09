//
//  VoxPDFService.swift
//  Listen2
//
//  Service for extracting text and structure from PDF documents using VoxPDF C API
//

import Foundation

/// Service for extracting text and structure from PDF documents using VoxPDF
final class VoxPDFService {

    // MARK: - Constants

    /// Minimum heading length for contains-based matching
    private static let minimumHeadingLengthForContainsMatch = 10

    enum VoxPDFError: Error, LocalizedError {
        case invalidPDF
        case extractionFailed(underlying: Error)
        case unsupportedOperation
        case emptyDocument
        case corruptedStructure
        case pageNotFound
        case ioError
        case outOfMemory
        case invalidText

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
            case .pageNotFound:
                return "The requested page was not found in the PDF"
            case .ioError:
                return "An I/O error occurred while reading the PDF"
            case .outOfMemory:
                return "Insufficient memory to process the PDF"
            case .invalidText:
                return "The PDF contains invalid text encoding"
            }
        }

        init(from cError: CVoxPDFError) {
            switch cError {
            case CVoxPDFErrorInvalidPDF:
                self = .invalidPDF
            case CVoxPDFErrorPageNotFound:
                self = .pageNotFound
            case CVoxPDFErrorIoError:
                self = .ioError
            case CVoxPDFErrorOutOfMemory:
                self = .outOfMemory
            case CVoxPDFErrorInvalidText:
                self = .invalidText
            default:
                self = .corruptedStructure
            }
        }
    }

    // MARK: - Validation

    /// Validate that a file is a valid PDF
    /// - Parameter url: URL to the PDF file
    /// - Throws: VoxPDFError if the file is invalid
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

    // MARK: - Public API

    /// Extract paragraphs from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Array of paragraph strings
    func extractParagraphs(from url: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            // Validate PDF before attempting extraction
            do {
                try self.validatePDF(at: url)
            } catch let error as VoxPDFError {
                throw error
            } catch {
                throw VoxPDFError.extractionFailed(underlying: error)
            }

            var error: CVoxPDFError = CVoxPDFErrorOk

            // Open PDF document
            guard let doc = voxpdf_open(url.path, &error) else {
                throw VoxPDFError(from: error)
            }
            defer { voxpdf_free_document(doc) }

            // Get page count
            let pageCount = voxpdf_get_page_count(doc)
            guard pageCount > 0 else {
                throw VoxPDFError.emptyDocument
            }

            var allParagraphs: [String] = []

            // Extract paragraphs from each page
            for page in 0..<pageCount {
                let paragraphCount = voxpdf_get_paragraph_count(doc, UInt32(page), &error)
                guard error == CVoxPDFErrorOk else {
                    throw VoxPDFError(from: error)
                }

                // Extract each paragraph
                for paraIndex in 0..<paragraphCount {
                    var paragraph = CParagraph()
                    var textPtr: UnsafePointer<CChar>?

                    let success = voxpdf_get_paragraph(
                        doc,
                        UInt32(page),
                        paraIndex,
                        &paragraph,
                        &textPtr,
                        &error
                    )

                    guard success, error == CVoxPDFErrorOk, let text = textPtr else {
                        continue // Skip problematic paragraphs
                    }
                    defer { voxpdf_free_string(UnsafeMutablePointer(mutating: text)) }

                    let paragraphText = String(cString: text)
                    if !paragraphText.isEmpty {
                        allParagraphs.append(paragraphText)
                    }
                }
            }

            guard !allParagraphs.isEmpty else {
                throw VoxPDFError.emptyDocument
            }

            return allParagraphs
        }.value
    }

    /// Extract raw text from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Concatenated text content
    func extractText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            // Validate PDF before attempting extraction
            do {
                try self.validatePDF(at: url)
            } catch let error as VoxPDFError {
                throw error
            } catch {
                throw VoxPDFError.extractionFailed(underlying: error)
            }

            var error: CVoxPDFError = CVoxPDFErrorOk

            // Open PDF document
            guard let doc = voxpdf_open(url.path, &error) else {
                throw VoxPDFError(from: error)
            }
            defer { voxpdf_free_document(doc) }

            // Get page count
            let pageCount = voxpdf_get_page_count(doc)
            guard pageCount > 0 else {
                throw VoxPDFError.emptyDocument
            }

            var allText: [String] = []

            // Extract text from each page
            for page in 0..<pageCount {
                var textPtr: UnsafePointer<CChar>?

                let success = voxpdf_extract_page_text(
                    doc,
                    UInt32(page),
                    &textPtr,
                    &error
                )

                guard success, error == CVoxPDFErrorOk, let text = textPtr else {
                    continue // Skip problematic pages
                }
                defer { voxpdf_free_string(UnsafeMutablePointer(mutating: text)) }

                let pageText = String(cString: text)
                if !pageText.isEmpty {
                    allText.append(pageText)
                }
            }

            guard !allText.isEmpty else {
                throw VoxPDFError.emptyDocument
            }

            return allText.joined(separator: "\n\n")
        }.value
    }

    /// Extract table of contents from PDF metadata
    /// - Parameters:
    ///   - url: URL to the PDF file
    ///   - paragraphs: Already extracted paragraphs for matching
    /// - Returns: Array of TOC entries with paragraph indices
    func extractTOC(from url: URL, paragraphs: [String]) async throws -> [TOCEntry] {
        try await Task.detached(priority: .userInitiated) {
            // Validate PDF before attempting extraction
            do {
                try self.validatePDF(at: url)
            } catch let error as VoxPDFError {
                throw error
            } catch {
                throw VoxPDFError.extractionFailed(underlying: error)
            }

            var error: CVoxPDFError = CVoxPDFErrorOk

            // Open PDF document
            guard let doc = voxpdf_open(url.path, &error) else {
                throw VoxPDFError(from: error)
            }
            defer { voxpdf_free_document(doc) }

            // Get TOC count
            let tocCount = voxpdf_get_toc_count(doc, &error)
            guard error == CVoxPDFErrorOk else {
                throw VoxPDFError(from: error)
            }

            var tocEntries: [TOCEntry] = []

            // Extract each TOC entry
            for tocIndex in 0..<tocCount {
                var tocEntry = CTocEntry()
                var titlePtr: UnsafePointer<CChar>?

                let success = voxpdf_get_toc_entry(
                    doc,
                    tocIndex,
                    &tocEntry,
                    &titlePtr,
                    &error
                )

                guard success, error == CVoxPDFErrorOk, let title = titlePtr else {
                    continue // Skip problematic TOC entries
                }
                defer { voxpdf_free_string(UnsafeMutablePointer(mutating: title)) }

                let titleText = String(cString: title)

                // Always use semantic matching to find the paragraph index
                // The paragraph_index from VoxPDF may be in a different index space
                let paragraphIndex = self.findParagraphIndex(for: titleText, in: paragraphs)

                tocEntries.append(TOCEntry(
                    title: titleText,
                    paragraphIndex: paragraphIndex,
                    level: Int(tocEntry.level)
                ))
            }

            return tocEntries
        }.value
    }

    /// Extract word-level positions from PDF for word highlighting
    /// - Parameter url: URL to the PDF file
    /// - Returns: Document word map for word-level navigation
    func extractWordPositions(from url: URL) async throws -> DocumentWordMap {
        try await Task.detached(priority: .userInitiated) {
            // Validate PDF before attempting extraction
            do {
                try self.validatePDF(at: url)
            } catch let error as VoxPDFError {
                throw error
            } catch {
                throw VoxPDFError.extractionFailed(underlying: error)
            }

            var error: CVoxPDFError = CVoxPDFErrorOk

            // Open PDF document
            guard let doc = voxpdf_open(url.path, &error) else {
                throw VoxPDFError(from: error)
            }
            defer { voxpdf_free_document(doc) }

            // Get page count
            let pageCount = voxpdf_get_page_count(doc)
            guard pageCount > 0 else {
                throw VoxPDFError.emptyDocument
            }

            var allWords: [WordPosition] = []
            var globalParagraphIndex = 0
            var characterOffsetInCurrentParagraph = 0
            var wordsInCurrentParagraph: [WordPosition] = []

            // Extract words from each page
            for pageNum in 0..<pageCount {
                let page = UInt32(pageNum)

                // Get paragraph count for this page
                let paragraphCount = voxpdf_get_paragraph_count(doc, page, &error)
                guard error == CVoxPDFErrorOk else {
                    continue // Skip problematic pages
                }

                // Process each paragraph on this page
                for paraIndex in 0..<paragraphCount {
                    var paragraph = CParagraph()
                    var paraTextPtr: UnsafePointer<CChar>?

                    let paraSuccess = voxpdf_get_paragraph(
                        doc,
                        page,
                        paraIndex,
                        &paragraph,
                        &paraTextPtr,
                        &error
                    )

                    guard paraSuccess, error == CVoxPDFErrorOk else {
                        continue
                    }
                    defer {
                        if let ptr = paraTextPtr {
                            voxpdf_free_string(UnsafeMutablePointer(mutating: ptr))
                        }
                    }

                    // If starting a new paragraph, finalize the previous one
                    if !wordsInCurrentParagraph.isEmpty {
                        allWords.append(contentsOf: wordsInCurrentParagraph)
                        wordsInCurrentParagraph = []
                        globalParagraphIndex += 1
                        characterOffsetInCurrentParagraph = 0
                    }

                    // Get word count for this paragraph
                    let wordCount = voxpdf_get_word_count(doc, page, &error)
                    guard error == CVoxPDFErrorOk else {
                        continue
                    }

                    // Extract each word
                    for wordIndex in 0..<wordCount {
                        var wordPos = CWordPosition()
                        var wordTextPtr: UnsafePointer<CChar>?

                        let wordSuccess = voxpdf_get_word(
                            doc,
                            page,
                            wordIndex,
                            &wordPos,
                            &wordTextPtr,
                            &error
                        )

                        guard wordSuccess, error == CVoxPDFErrorOk, let textPtr = wordTextPtr else {
                            continue
                        }
                        defer { voxpdf_free_string(UnsafeMutablePointer(mutating: textPtr)) }

                        let wordText = String(cString: textPtr)
                        guard !wordText.isEmpty else { continue }

                        let bbox = WordPosition.BoundingBox(
                            x: wordPos.x,
                            y: wordPos.y,
                            width: wordPos.width,
                            height: wordPos.height
                        )

                        let word = WordPosition(
                            text: wordText,
                            characterOffset: characterOffsetInCurrentParagraph,
                            length: wordText.count,
                            paragraphIndex: globalParagraphIndex,
                            pageNumber: Int(wordPos.page),
                            boundingBox: bbox
                        )

                        wordsInCurrentParagraph.append(word)
                        // Add 1 for space between words
                        characterOffsetInCurrentParagraph += wordText.count + 1
                    }
                }
            }

            // Append any remaining words
            if !wordsInCurrentParagraph.isEmpty {
                allWords.append(contentsOf: wordsInCurrentParagraph)
            }

            guard !allWords.isEmpty else {
                throw VoxPDFError.emptyDocument
            }

            return DocumentWordMap(words: allWords)
        }.value
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
        if normalized.count > Self.minimumHeadingLengthForContainsMatch {
            for (index, paragraph) in paragraphs.enumerated() {
                if paragraph.lowercased().contains(normalized) {
                    return index
                }
            }
        }

        return 0 // Fallback to first paragraph
    }
}
