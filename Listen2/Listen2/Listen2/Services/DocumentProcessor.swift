//
//  DocumentProcessor.swift
//  Listen2
//

import Foundation
import PDFKit
import UniformTypeIdentifiers
import UIKit

final class DocumentProcessor {

    // MARK: - Dependencies

    private let voxPDFService = VoxPDFService()

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

    /// Extract word positions for word-level highlighting
    /// - PDF: Uses VoxPDF for precise layout-aware word positions
    /// - EPUB/Clipboard: Uses plain text word mapping
    /// Returns nil if extraction fails
    func extractWordPositions(from url: URL, sourceType: SourceType, paragraphs: [String]) async -> DocumentWordMap? {
        switch sourceType {
        case .pdf:
            do {
                let wordMap = try await voxPDFService.extractWordPositions(from: url)
                return wordMap
            } catch {
                return nil
            }

        case .epub, .clipboard:
            let wordMap = PlainTextWordMapper.createWordMap(from: paragraphs)
            return wordMap
        }
    }

    /// Extracts and encodes TOC metadata during document import
    /// Returns nil if extraction fails
    func extractTOCData(from url: URL, sourceType: SourceType, paragraphs: [String]) async -> Data? {
        var entries: [TOCEntry] = []

        switch sourceType {
        case .pdf:
            // Try VoxPDF first
            do {
                entries = try await voxPDFService.extractTOC(from: url, paragraphs: paragraphs)

                if entries.isEmpty {
                    throw DocumentProcessorError.extractionFailed
                }
            } catch {
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

    // MARK: - Private PDF Extraction

    private func extractPDFText(from url: URL) async throws -> [String] {
        // Use VoxPDF for superior extraction
        do {
            let paragraphs = try await voxPDFService.extractParagraphs(from: url)

            guard !paragraphs.isEmpty else {
                throw DocumentProcessorError.extractionFailed
            }

            return paragraphs
        } catch {
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
        // Split on newlines (DON'T trim yet - need to detect hyphens first)
        let rawLines = text.components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var paragraphs: [String] = []
        var currentParagraph = ""

        var lastLineWasHeading = false

        for rawLine in rawLines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            // Check if this is a heading (preserve headings even if short)
            let isHeading = isLikelyHeading(trimmedLine)

            // Skip very short lines UNLESS they're headings or end with sentence punctuation
            if !isHeading && trimmedLine.count < 15 && !trimmedLine.hasSuffix(".") && !trimmedLine.hasSuffix("!") && !trimmedLine.hasSuffix("?") {
                continue
            }

            // If we encounter a heading
            if isHeading {
                // Only merge if the previous line was a chapter marker (e.g., "CHAPTER 4")
                // This prevents merging TOC entries or other consecutive headings
                let isChapterMarker = currentParagraph.range(of: "^CHAPTER \\d+$", options: .regularExpression) != nil

                if lastLineWasHeading && !currentParagraph.isEmpty && isChapterMarker {
                    // Merge chapter marker with title (e.g., "CHAPTER 4" + "Tool Use")
                    currentParagraph += " " + trimmedLine
                    lastLineWasHeading = false // Don't merge more than 2 lines
                    continue
                }

                // Otherwise, finalize the current paragraph and start a new heading
                if !currentParagraph.isEmpty {
                    paragraphs.append(currentParagraph)
                    currentParagraph = ""
                }

                currentParagraph = trimmedLine
                lastLineWasHeading = true
                continue
            }

            // If we were processing a heading and now hit body text, finalize the heading
            if lastLineWasHeading && !currentParagraph.isEmpty {
                paragraphs.append(currentParagraph)
                currentParagraph = ""
            }

            lastLineWasHeading = false

            // Check if this line ends a sentence/paragraph
            let endsWithPunctuation = trimmedLine.hasSuffix(".") || trimmedLine.hasSuffix("!") || trimmedLine.hasSuffix("?")

            if currentParagraph.isEmpty {
                // Start new paragraph
                currentParagraph = trimmedLine
            } else {
                // Check if PREVIOUS line (before trimming current) ended with hyphen
                // This handles: "interrupt- " or "interrupt-" or "interrupt‐"
                let hyphenChars: Set<Character> = ["-", "‐", "‑"]  // ASCII hyphen, Unicode hyphen, non-breaking hyphen

                // Trim trailing whitespace from current paragraph and check last char
                let trimmedParagraph = currentParagraph.trimmingCharacters(in: .whitespaces)
                if let lastChar = trimmedParagraph.last, hyphenChars.contains(lastChar) {
                    // Hyphenated word split across lines
                    // Remove hyphen and join directly (no space)
                    currentParagraph = String(trimmedParagraph.dropLast())
                    currentParagraph += trimmedLine
                } else {
                    // Normal line continuation - add space
                    currentParagraph += " " + trimmedLine
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

    /// Detects if a line of text is likely a heading
    private func isLikelyHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty
        if trimmed.isEmpty {
            return false
        }

        // Common heading patterns
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

        // Short text starting with capital, no sentence-ending punctuation
        let endsWithSentencePunctuation = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
        if !endsWithSentencePunctuation && trimmed.count <= 80 && trimmed.first?.isUppercase == true {
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 1 && words.count <= 10 {
                // Reject common body text starters
                let bodyTextStarters = ["to see", "to understand", "to implement", "the following", "in this", "here's", "this is", "we'll", "you can", "for example"]
                let lowercaseText = trimmed.lowercased()
                for starter in bodyTextStarters {
                    if lowercaseText.hasPrefix(starter) {
                        return false
                    }
                }
                return true
            }
        }

        return false
    }

    // MARK: - Clipboard Processing

    func processClipboardText(_ text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return paragraphs
    }

    // MARK: - Private EPUB Extraction

    private func extractEPUBText(from url: URL) async throws -> [String] {
        let extractor = EPUBExtractor()

        do {
            return try await extractor.extractText(from: url)
        } catch {
            throw DocumentProcessorError.extractionFailed
        }
    }

    // MARK: - Cover Image Extraction

    /// Extract cover image thumbnail from document
    /// Returns PNG data for the cover image, or nil if extraction fails
    func extractCoverImage(from url: URL, sourceType: SourceType) async -> Data? {
        switch sourceType {
        case .pdf:
            return await extractPDFCover(from: url)
        case .epub:
            return await extractEPUBCover(from: url)
        case .clipboard:
            return nil // No cover for clipboard text
        }
    }

    /// Extract cover from PDF (first page thumbnail)
    private func extractPDFCover(from url: URL) async -> Data? {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0) else {
            return nil
        }

        // Get page bounds
        let pageBounds = firstPage.bounds(for: .mediaBox)

        // Calculate thumbnail size (max 200 points on the longest side)
        let maxDimension: CGFloat = 200
        let aspectRatio = pageBounds.width / pageBounds.height
        let thumbnailSize: CGSize

        if pageBounds.width > pageBounds.height {
            thumbnailSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            thumbnailSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Render the page to an image
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: thumbnailSize))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: thumbnailSize.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)

            let scaleX = thumbnailSize.width / pageBounds.width
            let scaleY = thumbnailSize.height / pageBounds.height
            context.cgContext.scaleBy(x: scaleX, y: scaleY)

            firstPage.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }

        // Convert to PNG data
        return image.pngData()
    }

    /// Extract cover from EPUB using OPF metadata, with filename fallback
    private func extractEPUBCover(from url: URL) async -> Data? {
        // Unzip EPUB to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            try FileManager.default.unzipItem(at: url, to: tempDir)

            // Step 1: Try to find cover via OPF metadata (most reliable)
            if let coverPath = findCoverFromOPF(in: tempDir) {
                if let imageData = try? Data(contentsOf: coverPath),
                   let image = UIImage(data: imageData) {
                    return resizeImageToThumbnail(image)
                }
            }

            // Step 2: Fall back to common cover filenames
            let coverNames = [
                "cover.jpg", "cover.jpeg", "cover.png",
                "Cover.jpg", "Cover.jpeg", "Cover.png",
                "cover-image.jpg", "cover-image.png"
            ]

            let searchPaths = [
                tempDir,
                tempDir.appendingPathComponent("OEBPS"),
                tempDir.appendingPathComponent("OPS"),
                tempDir.appendingPathComponent("images"),
                tempDir.appendingPathComponent("Images"),
                tempDir.appendingPathComponent("OEBPS/images"),
                tempDir.appendingPathComponent("OPS/images")
            ]

            for searchPath in searchPaths {
                for coverName in coverNames {
                    let coverURL = searchPath.appendingPathComponent(coverName)
                    if FileManager.default.fileExists(atPath: coverURL.path),
                       let imageData = try? Data(contentsOf: coverURL),
                       let image = UIImage(data: imageData) {
                        return resizeImageToThumbnail(image)
                    }
                }
            }

            // Step 3: No random fallback - if we can't find a proper cover, return nil
            // This prevents grabbing Twitter logos or other random images

        } catch {
            return nil
        }

        return nil
    }

    /// Parse OPF file to find the cover image path
    private func findCoverFromOPF(in epubDir: URL) -> URL? {
        // Find container.xml to locate content.opf
        let containerURL = epubDir.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL),
              let containerString = String(data: containerData, encoding: .utf8) else {
            return nil
        }

        // Extract content.opf path from container.xml
        guard let opfPathMatch = containerString.range(of: "full-path=\"([^\"]+)\"", options: .regularExpression),
              let opfPath = containerString[opfPathMatch].split(separator: "\"").dropFirst().first else {
            return nil
        }

        let opfURL = epubDir.appendingPathComponent(String(opfPath))
        let opfBaseURL = opfURL.deletingLastPathComponent()

        guard let opfData = try? Data(contentsOf: opfURL),
              let opfString = String(data: opfData, encoding: .utf8) else {
            return nil
        }

        // Build manifest dictionary: id -> href
        var manifest: [String: String] = [:]
        let itemPattern = "<item[^>]+id=\"([^\"]+)\"[^>]+href=\"([^\"]+)\"|<item[^>]+href=\"([^\"]+)\"[^>]+id=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: itemPattern, options: []) {
            let range = NSRange(opfString.startIndex..., in: opfString)
            regex.enumerateMatches(in: opfString, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                // Handle both attribute orderings
                if let idRange = Range(match.range(at: 1), in: opfString),
                   let hrefRange = Range(match.range(at: 2), in: opfString) {
                    manifest[String(opfString[idRange])] = String(opfString[hrefRange])
                } else if let hrefRange = Range(match.range(at: 3), in: opfString),
                          let idRange = Range(match.range(at: 4), in: opfString) {
                    manifest[String(opfString[idRange])] = String(opfString[hrefRange])
                }
            }
        }

        // Method 1: EPUB 2 style - <meta name="cover" content="cover-id"/>
        if let metaMatch = opfString.range(of: "<meta[^>]+name=\"cover\"[^>]+content=\"([^\"]+)\"", options: .regularExpression) {
            let metaString = String(opfString[metaMatch])
            if let contentMatch = metaString.range(of: "content=\"([^\"]+)\"", options: .regularExpression) {
                let contentValue = metaString[contentMatch].replacingOccurrences(of: "content=\"", with: "").replacingOccurrences(of: "\"", with: "")
                if let href = manifest[contentValue] {
                    return opfBaseURL.appendingPathComponent(href)
                }
            }
        }

        // Method 2: EPUB 3 style - <item properties="cover-image" .../>
        if let itemMatch = opfString.range(of: "<item[^>]+properties=\"[^\"]*cover-image[^\"]*\"[^>]+href=\"([^\"]+)\"", options: .regularExpression) {
            let itemString = String(opfString[itemMatch])
            if let hrefMatch = itemString.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                let href = itemString[hrefMatch].replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
                return opfBaseURL.appendingPathComponent(href)
            }
        }

        // Method 3: Look for item with id containing "cover" and image media-type
        for (id, href) in manifest {
            if id.lowercased().contains("cover") &&
               (href.lowercased().hasSuffix(".jpg") || href.lowercased().hasSuffix(".jpeg") || href.lowercased().hasSuffix(".png")) {
                return opfBaseURL.appendingPathComponent(href)
            }
        }

        return nil
    }

    /// Resize image to thumbnail size (max 200 points)
    private func resizeImageToThumbnail(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 200
        let aspectRatio = image.size.width / image.size.height
        let thumbnailSize: CGSize

        if image.size.width > image.size.height {
            thumbnailSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            thumbnailSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        return resizedImage.pngData()
    }
}
