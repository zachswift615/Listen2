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
                  let page = destination.page else {
                continue
            }

            let pageIndex = pdfDocument.index(for: page)

            // TODO: CRITICAL - Paragraph index estimation is currently a rough approximation
            // WARNING: This multiplier (pageIndex * 10) is arbitrary and will be inaccurate
            // INTEGRATION REQUIREMENT: Before Phase 3 integration with ReaderView:
            //   - Replace this with actual mapping from PDFPage to paragraph indices
            //   - Use ParagraphManager to get precise paragraph positions
            //   - Consider maintaining a page-to-paragraph-range lookup table
            let estimatedParagraphIndex = pageIndex * 10 // Rough estimate - REPLACE BEFORE INTEGRATION

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

        // Short text that starts with a capital letter is likely a heading
        // (common for simple titles without special formatting)
        if trimmed.count <= 50 && trimmed.first?.isUppercase == true {
            // Make sure it doesn't look like a sentence (no lowercase words suggesting body text)
            let words = trimmed.components(separatedBy: " ")
            if words.count <= 5 {
                return true
            }
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
