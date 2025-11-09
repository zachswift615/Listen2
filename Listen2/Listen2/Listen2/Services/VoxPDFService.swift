//
//  VoxPDFService.swift
//  Listen2
//
//  Service for extracting text and structure from PDF documents using VoxPDF C API
//

import Foundation

/// Service for extracting text and structure from PDF documents using VoxPDF
final class VoxPDFService {

    enum VoxPDFError: Error {
        case invalidPDF
        case extractionFailed(String)
        case pageNotFound
        case ioError
        case outOfMemory
        case invalidText

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
                self = .extractionFailed("Unknown error code: \(cError.rawValue)")
            }
        }
    }

    // MARK: - Public API

    /// Extract paragraphs from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Array of paragraph strings
    func extractParagraphs(from url: URL) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxPDFError.invalidPDF
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
            throw VoxPDFError.invalidPDF
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

                let paragraphText = String(cString: text)
                if !paragraphText.isEmpty {
                    allParagraphs.append(paragraphText)
                }
            }
        }

        return allParagraphs
    }

    /// Extract raw text from a PDF document
    /// - Parameter url: URL to the PDF file
    /// - Returns: Concatenated text content
    func extractText(from url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxPDFError.invalidPDF
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
            throw VoxPDFError.invalidPDF
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

            let pageText = String(cString: text)
            if !pageText.isEmpty {
                allText.append(pageText)
            }
        }

        return allText.joined(separator: "\n\n")
    }

    /// Extract table of contents from PDF metadata
    /// - Parameters:
    ///   - url: URL to the PDF file
    ///   - paragraphs: Already extracted paragraphs for matching
    /// - Returns: Array of TOC entries with paragraph indices
    func extractTOC(from url: URL, paragraphs: [String]) async throws -> [TOCEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxPDFError.invalidPDF
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

            let titleText = String(cString: title)

            // Use the paragraph index from VoxPDF if available
            // Otherwise, try to find matching paragraph
            let paragraphIndex: Int
            if tocEntry.paragraph_index < paragraphs.count {
                paragraphIndex = Int(tocEntry.paragraph_index)
            } else {
                paragraphIndex = findParagraphIndex(for: titleText, in: paragraphs)
            }

            tocEntries.append(TOCEntry(
                title: titleText,
                paragraphIndex: paragraphIndex,
                level: Int(tocEntry.level)
            ))
        }

        return tocEntries
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

        return 0 // Fallback to first paragraph
    }
}
