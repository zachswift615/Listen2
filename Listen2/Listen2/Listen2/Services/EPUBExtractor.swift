//
//  EPUBExtractor.swift
//  Listen2
//
//  EPUB text extraction for TTS
//  Uses ZIPFoundation for ZIP extraction
//

import Foundation
import ZIPFoundation

final class EPUBExtractor {

    // MARK: - Errors

    enum EPUBError: Error {
        case invalidEPUB
        case missingContainer
        case missingContentOPF
        case extractionFailed
        case unzipFailed
    }

    // MARK: - Public Methods

    /// Extract text from EPUB file in reading order
    func extractText(from url: URL) async throws -> [String] {
        // 1. Unzip EPUB to temp directory
        let tempDir = try await unzipEPUB(url)

        defer {
            // Cleanup temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 2. Find content.opf location from container.xml
        let contentOPFPath = try findContentOPF(in: tempDir)
        let contentOPFURL = tempDir.appendingPathComponent(contentOPFPath)

        // 3. Parse content.opf to get spine (reading order)
        let spineItems = try parseSpine(at: contentOPFURL)

        // 4. Extract text from each XHTML file in spine order
        let baseURL = contentOPFURL.deletingLastPathComponent()
        var paragraphs: [String] = []

        for item in spineItems {
            let xhtmlURL = baseURL.appendingPathComponent(item)
            let text = try extractTextFromXHTML(at: xhtmlURL)

            // Split into paragraphs and filter empty ones
            let itemParagraphs = text
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            paragraphs.append(contentsOf: itemParagraphs)
        }

        guard !paragraphs.isEmpty else {
            throw EPUBError.extractionFailed
        }

        return paragraphs
    }

    /// Extract table of contents from EPUB file
    func extractTOC(from url: URL, paragraphs: [String]) async throws -> [TOCEntry] {
        // 1. Unzip EPUB to temp directory
        let tempDir = try await unzipEPUB(url)

        defer {
            // Cleanup temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 2. Find content.opf location
        let contentOPFPath = try findContentOPF(in: tempDir)
        let contentOPFURL = tempDir.appendingPathComponent(contentOPFPath)
        let baseURL = contentOPFURL.deletingLastPathComponent()

        // 3. Parse content.opf to get spine items and TOC reference
        let opfData = try Data(contentsOf: contentOPFURL)
        let opfParser = ContentOPFParser()
        guard opfParser.parse(data: opfData) else {
            return []
        }

        let spineItems = opfParser.spineItems

        // Build spine item to paragraph index mapping
        var spineItemToParagraphIndex: [String: Int] = [:]
        var currentIndex = 0

        // Re-extract to build mapping (not ideal but works for now)
        for item in spineItems {
            spineItemToParagraphIndex[item] = currentIndex
            let xhtmlURL = baseURL.appendingPathComponent(item)
            if let text = try? extractTextFromXHTML(at: xhtmlURL) {
                let itemParagraphs = text
                    .components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                currentIndex += itemParagraphs.count
            }
        }

        // 4. Try to find and parse toc.ncx
        let tocNCXPath = opfParser.tocNCXPath ?? "toc.ncx"
        let tocNCXURL = baseURL.appendingPathComponent(tocNCXPath)

        guard FileManager.default.fileExists(atPath: tocNCXURL.path) else {
            print("⚠️ No toc.ncx found at: \(tocNCXURL.path)")
            return []
        }

        let tocData = try Data(contentsOf: tocNCXURL)
        let tocParser = TOCNCXParser()

        guard tocParser.parse(data: tocData) else {
            return []
        }

        // 5. Map TOC entries to paragraph indices
        var tocEntries: [TOCEntry] = []

        for navPoint in tocParser.navPoints {
            // Extract filename from href (remove fragment identifier)
            let href = navPoint.href.components(separatedBy: "#").first ?? navPoint.href

            // Normalize href (remove leading path components if needed)
            let normalizedHref = (href as NSString).lastPathComponent

            // Find matching spine item
            var paragraphIndex = 0
            for (spineItem, index) in spineItemToParagraphIndex {
                let spineFileName = (spineItem as NSString).lastPathComponent
                if spineFileName == normalizedHref {
                    paragraphIndex = index
                    break
                }
            }

            let entry = TOCEntry(
                title: navPoint.title,
                paragraphIndex: paragraphIndex,
                level: navPoint.level
            )
            tocEntries.append(entry)
        }

        return tocEntries
    }

    // MARK: - Private Methods

    /// Unzip EPUB file to temporary directory
    private func unzipEPUB(_ url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)

        // EPUB is just a ZIP file - use ZIPFoundation to extract
        do {
            try FileManager.default.unzipItem(at: url, to: tempDir)
        } catch {
            throw EPUBError.unzipFailed
        }

        return tempDir
    }

    /// Find content.opf location from META-INF/container.xml
    private func findContentOPF(in epubDir: URL) throws -> String {
        let containerURL = epubDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBError.missingContainer
        }

        let containerData = try Data(contentsOf: containerURL)
        let parser = ContainerXMLParser()

        guard parser.parse(data: containerData) else {
            throw EPUBError.missingContainer
        }

        return parser.contentOPFPath
    }

    /// Parse content.opf to extract spine items in reading order
    private func parseSpine(at opfURL: URL) throws -> [String] {
        let opfData = try Data(contentsOf: opfURL)
        let parser = ContentOPFParser()

        guard parser.parse(data: opfData) else {
            throw EPUBError.missingContentOPF
        }

        return parser.spineItems
    }

    /// Extract text from XHTML file by stripping HTML tags
    private func extractTextFromXHTML(at url: URL) throws -> String {
        guard let html = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }

        var text = html

        // Remove script and style tags with their content
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Replace block-level elements with double newlines (preserves paragraph structure)
        let blockElements = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "br", "blockquote"]
        for element in blockElements {
            // Opening and closing tags
            text = text.replacingOccurrences(
                of: "<\(element)[^>]*>",
                with: "\n\n",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: "</\(element)>",
                with: "\n\n",
                options: .regularExpression
            )
        }

        // Self-closing br tags
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n\n",
            options: .regularExpression
        )

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Replace multiple newlines with double newline (normalize paragraph breaks)
        text = text.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        // Clean up excessive whitespace
        text = text.replacingOccurrences(
            of: "[ \t]+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode common HTML entities
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#8217;": "\u{2019}",  // Right single quotation mark
            "&#8220;": "\u{201C}",  // Left double quotation mark
            "&#8221;": "\u{201D}",  // Right double quotation mark
            "&#8212;": "\u{2014}",  // Em dash
            "&#8211;": "\u{2013}"   // En dash
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Remove remaining numeric entities (&#123; or &#xAB;)
        // For simplicity, just remove them - most common ones are handled above
        result = result.replacingOccurrences(
            of: "&#[0-9]+;",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "&#x[0-9A-Fa-f]+;",
            with: "",
            options: .regularExpression
        )

        return result
    }
}

// MARK: - Container.xml Parser

private class ContainerXMLParser: NSObject, XMLParserDelegate {
    var contentOPFPath: String = ""

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() && !contentOPFPath.isEmpty
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {

        if elementName == "rootfile",
           let fullPath = attributeDict["full-path"] {
            contentOPFPath = fullPath
        }
    }
}

// MARK: - Content.opf Parser

private class ContentOPFParser: NSObject, XMLParserDelegate {
    var spineItems: [String] = []
    var tocNCXPath: String?
    private var manifest: [String: String] = [:]  // id -> href
    private var tocID: String?
    private var currentElement: String = ""

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() && !spineItems.isEmpty
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {

        currentElement = elementName

        // Get TOC reference from spine element
        if elementName == "spine",
           let toc = attributeDict["toc"] {
            tocID = toc
        }

        if elementName == "item",
           let id = attributeDict["id"],
           let href = attributeDict["href"] {
            manifest[id] = href

            // Check if this is the TOC NCX file
            if let mediaType = attributeDict["media-type"],
               mediaType == "application/x-dtbncx+xml" {
                tocNCXPath = href
            }
        }

        if elementName == "itemref",
           let idref = attributeDict["idref"],
           let href = manifest[idref] {
            spineItems.append(href)
        }
    }

    func parser(_ parser: XMLParser, didEndDocument: ()) {
        // If we have a tocID, use it to find the TOC path
        if let tocID = tocID, tocNCXPath == nil {
            tocNCXPath = manifest[tocID]
        }
    }
}

// MARK: - TOC.ncx Parser

private struct NavPoint {
    let title: String
    let href: String
    let level: Int
}

private class TOCNCXParser: NSObject, XMLParserDelegate {
    var navPoints: [NavPoint] = []
    private var currentTitle: String = ""
    private var currentHref: String = ""
    private var currentLevel: Int = 0
    private var levelStack: [String] = []
    private var isInText = false

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {

        if elementName == "navPoint" {
            levelStack.append(elementName)
            currentLevel = levelStack.count - 1
        }

        if elementName == "text" {
            isInText = true
            currentTitle = ""
        }

        if elementName == "content",
           let src = attributeDict["src"] {
            currentHref = src
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText {
            currentTitle += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {

        if elementName == "text" {
            isInText = false
        }

        if elementName == "navPoint" {
            if !currentTitle.isEmpty && !currentHref.isEmpty {
                let navPoint = NavPoint(
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    href: currentHref,
                    level: currentLevel
                )
                navPoints.append(navPoint)
            }

            levelStack.removeLast()
            currentTitle = ""
            currentHref = ""
        }
    }
}
