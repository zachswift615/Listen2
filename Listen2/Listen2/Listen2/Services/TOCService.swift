//
//  TOCService.swift
//  Listen2
//

import Foundation
import PDFKit

final class TOCService {

    // MARK: - Public Methods

    /// Extract TOC from PDF outline metadata (Phase 1)
    func extractTOCFromMetadata(_ pdfDocument: PDFDocument, paragraphs: [String]) -> [TOCEntry] {
        guard let outline = pdfDocument.outlineRoot else {
            return []
        }

        var entries: [TOCEntry] = []
        extractOutlineRecursive(outline, level: 0, entries: &entries, pdfDocument: pdfDocument, paragraphs: paragraphs)
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
        pdfDocument: PDFDocument,
        paragraphs: [String]
    ) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i),
                  let label = child.label else {
                continue
            }

            // Find the paragraph that contains this heading text
            let paragraphIndex = findParagraphIndex(for: label, in: paragraphs)

            let entry = TOCEntry(
                title: label,
                paragraphIndex: paragraphIndex,
                level: level
            )
            entries.append(entry)

            // Recurse for children
            if child.numberOfChildren > 0 {
                extractOutlineRecursive(child, level: level + 1, entries: &entries, pdfDocument: pdfDocument, paragraphs: paragraphs)
            }
        }
    }

    /// Finds the paragraph index that contains or matches the heading text
    private func findParagraphIndex(for heading: String, in paragraphs: [String]) -> Int {
        let normalizedHeading = heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Extract core heading text (strip "Chapter X.", "Part X", etc.)
        let coreHeading = extractCoreHeading(from: normalizedHeading)

        // First pass: exact match
        for (index, paragraph) in paragraphs.enumerated() {
            let normalizedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedParagraph == normalizedHeading {
                return index
            }
        }

        // Second pass: match core heading (without "Chapter X" prefix)
        if coreHeading != normalizedHeading {
            for (index, paragraph) in paragraphs.enumerated() {
                let normalizedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let coreParagraph = extractCoreHeading(from: normalizedParagraph)

                if coreParagraph == coreHeading {
                    return index
                }
            }
        }

        // Third pass: paragraph starts with heading
        for (index, paragraph) in paragraphs.enumerated() {
            let normalizedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedParagraph.hasPrefix(normalizedHeading) || normalizedParagraph.hasPrefix(coreHeading) {
                return index
            }
        }

        // Fourth pass: heading text appears in paragraph
        for (index, paragraph) in paragraphs.enumerated() {
            let normalizedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedParagraph.contains(normalizedHeading) || (coreHeading.count > 10 && normalizedParagraph.contains(coreHeading)) {
                return index
            }
        }

        // Fallback: return 0 if not found
        return 0
    }

    /// Extracts core heading text by removing common prefixes like "Chapter 1.", "Part 2", etc.
    private func extractCoreHeading(from text: String) -> String {
        var result = text

        // Remove patterns like "chapter 1. " or "chapter 1: "
        let chapterPattern = "^chapter\\s+\\d+[.:]?\\s*"
        if let regex = try? NSRegularExpression(pattern: chapterPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Remove patterns like "part 1. " or "part 1: "
        let partPattern = "^part\\s+\\d+[.:]?\\s*"
        if let regex = try? NSRegularExpression(pattern: partPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Remove leading numbers like "1. " or "1.1 "
        let numberPattern = "^\\d+(\\.\\d+)*[.:]?\\s*"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty
        if trimmed.isEmpty {
            return false
        }

        // Check for common heading patterns first (highest confidence)
        let headingPatterns = [
            "^Chapter \\d+",
            "^CHAPTER \\d+",
            "^\\d+\\.",
            "^\\d+\\.\\d+",
            "^[A-Z][A-Za-z\\s]+:$",
            "^[IVX]+\\.", // Roman numerals
            "^Part \\d+",
            "^PART \\d+",
            "^Appendix",
            "^APPENDIX",
        ]

        for pattern in headingPatterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // All caps text (common for headings)
        if trimmed == trimmed.uppercased() && trimmed.count >= 3 && trimmed.count <= 100 {
            return true
        }

        // If it ends with sentence-ending punctuation, probably not a heading
        // (unless it's a numbered section)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            if trimmed.hasSuffix("...") || trimmed.range(of: "^\\d+(\\.\\d+)*\\.$", options: .regularExpression) != nil {
                return true // Ellipsis or numbered sections are OK
            }
            return false
        }

        // Character count - real headings are typically short
        // Most technical book headings are under 80 characters
        if trimmed.count > 80 {
            return false
        }

        // Reject common body text patterns
        let bodyTextStarters = ["to see", "to understand", "to implement", "the following", "in this", "here's", "this is", "we'll", "you can", "for example"]
        let lowercaseText = trimmed.lowercased()
        for starter in bodyTextStarters {
            if lowercaseText.hasPrefix(starter) {
                return false
            }
        }

        // Word count check - headings are typically short
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wordCount = words.count

        // More strict: 1-7 words starting with capital
        if wordCount >= 1 && wordCount <= 7 && trimmed.first?.isUppercase == true {
            // Reject if it has common prose indicators
            let proseIndicators = ["the", "and", "with", "from", "that", "this", "these", "those", "which", "where", "will", "can", "has", "have"]
            let hasAnyProse = proseIndicators.contains { lowercaseText.contains(" \($0) ") }

            if !hasAnyProse {
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
