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

        // Fix hyphenation issues
        let cleanedText = fixHyphenation(in: fullText)

        // Split into paragraphs and apply basic filtering
        let paragraphs = cleanedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { paragraph in
                // Skip empty lines
                guard !paragraph.isEmpty else { return false }

                // Skip very short lines (likely page numbers, single letters, etc.)
                // But keep lines that end with punctuation (might be short sentences)
                if paragraph.count < 15 {
                    let lastChar = paragraph.last
                    let hasPunctuation = lastChar == "." || lastChar == "!" || lastChar == "?"
                    return hasPunctuation
                }

                return true
            }

        guard !paragraphs.isEmpty else {
            throw DocumentProcessorError.extractionFailed
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
