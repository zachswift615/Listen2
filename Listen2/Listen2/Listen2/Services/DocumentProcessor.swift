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

        // Join lines into proper paragraphs (handles hyphenation during joining)
        // PDF text has hard line breaks within paragraphs - we need to join them
        let paragraphs = joinLinesIntoParagraphs(fullText)

        guard !paragraphs.isEmpty else {
            throw DocumentProcessorError.extractionFailed
        }

        return paragraphs
    }

    /// Intelligently joins PDF lines into semantic paragraphs
    private func joinLinesIntoParagraphs(_ text: String) -> [String] {
        // Split on newlines and clean up each line
        let lines = text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var paragraphs: [String] = []
        var currentParagraph = ""

        for line in lines {
            // Skip very short lines (likely page numbers, headers, TOC dots)
            if line.count < 15 && !line.hasSuffix(".") && !line.hasSuffix("!") && !line.hasSuffix("?") {
                continue
            }

            // Check if this line ends a sentence/paragraph
            let endsWithPunctuation = line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?")

            if currentParagraph.isEmpty {
                // Start new paragraph
                currentParagraph = line
            } else {
                // Check if we need to join a hyphenated word
                // Look for hyphen at end of accumulated paragraph
                if let lastChar = currentParagraph.last, lastChar == "-" {
                    // Hyphenated word split across lines
                    // Remove hyphen and join directly (no space)
                    currentParagraph = String(currentParagraph.dropLast())
                    currentParagraph += line
                } else {
                    // Normal line continuation - add space
                    currentParagraph += " " + line
                }
            }

            // Finalize paragraph if we hit sentence-ending punctuation
            if endsWithPunctuation && currentParagraph.count > 50 {
                paragraphs.append(currentParagraph)
                currentParagraph = ""
            }
        }

        // Add any remaining text
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph)
        }

        return paragraphs
    }

    // MARK: - Clipboard Processing

    func processClipboardText(_ text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return paragraphs
    }

    // MARK: - Private EPUB Extraction (Stub for now)

    private func extractEPUBText(from url: URL) async throws -> [String] {
        // TODO: Implement EPUB extraction in next task
        throw DocumentProcessorError.unsupportedFormat
    }
}
