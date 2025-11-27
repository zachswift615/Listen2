//
//  LibraryViewModel.swift
//  Listen2
//

import Foundation
import SwiftData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var documents: [Document] = []
    @Published var searchText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let documentProcessor = DocumentProcessor()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadDocuments()
    }

    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadDocuments() {
        let descriptor = FetchDescriptor<Document>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)]
        )

        do {
            documents = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
        }
    }

    func deleteDocument(_ document: Document) {
        modelContext.delete(document)

        do {
            try modelContext.save()
            loadDocuments()
        } catch {
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
        }
    }

    func importFromClipboard(_ text: String) async {
        isProcessing = true
        errorMessage = nil

        let paragraphs = documentProcessor.processClipboardText(text)

        guard !paragraphs.isEmpty else {
            errorMessage = "No text found in clipboard"
            isProcessing = false
            return
        }

        let document = Document(
            title: "Clipboard \(Date().formatted(date: .abbreviated, time: .shortened))",
            sourceType: .clipboard,
            extractedText: paragraphs
        )

        modelContext.insert(document)

        do {
            try modelContext.save()
            loadDocuments()
        } catch {
            errorMessage = "Failed to save document: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func importTextFile(from url: URL) async {
        isProcessing = true
        errorMessage = nil

        // Start accessing security-scoped resource (required for file picker URLs)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Read the text file
            var text = try String(contentsOf: url, encoding: .utf8)

            // Strip markdown syntax if it's a markdown file
            let ext = url.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                text = stripMarkdownSyntax(text)
            }

            // Process into paragraphs
            let paragraphs = documentProcessor.processClipboardText(text)

            guard !paragraphs.isEmpty else {
                errorMessage = "No text found in file"
                isProcessing = false
                return
            }

            // Use the actual filename as the title
            let title = url.deletingPathExtension().lastPathComponent

            let document = Document(
                title: title,
                sourceType: .clipboard,
                extractedText: paragraphs,
                fileURL: url
            )

            modelContext.insert(document)
            try modelContext.save()

            loadDocuments()

        } catch {
            errorMessage = "Failed to import text file: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func importDocument(from url: URL, sourceType: SourceType) async {
        isProcessing = true
        errorMessage = nil

        // Start accessing security-scoped resource (required for file picker URLs)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let paragraphs = try await documentProcessor.extractText(from: url, sourceType: sourceType)

            // Extract TOC data while we have file access (pass paragraphs for accurate index mapping)
            let tocData = await documentProcessor.extractTOCData(from: url, sourceType: sourceType, paragraphs: paragraphs)

            // Extract word positions for word-level highlighting
            let wordMap = await documentProcessor.extractWordPositions(from: url, sourceType: sourceType, paragraphs: paragraphs)
            let wordMapData: Data? = {
                if let wordMap = wordMap {
                    return try? JSONEncoder().encode(wordMap)
                }
                return nil
            }()

            // Extract cover image thumbnail
            let coverImageData = await documentProcessor.extractCoverImage(from: url, sourceType: sourceType)

            let title = url.deletingPathExtension().lastPathComponent

            let document = Document(
                title: title,
                sourceType: sourceType,
                extractedText: paragraphs,
                fileURL: url,
                tocEntriesData: tocData,
                wordMapData: wordMapData,
                coverImageData: coverImageData
            )

            modelContext.insert(document)
            try modelContext.save()

            loadDocuments()

        } catch {
            errorMessage = "Failed to import document: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func importSampleDocuments() async {
        isProcessing = true
        errorMessage = nil

        do {
            try await SampleContentManager.shared.importSampleDocuments(
                modelContext: modelContext,
                documentProcessor: documentProcessor
            )
            loadDocuments()
        } catch {
            errorMessage = "Failed to import sample documents: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    // MARK: - Markdown Processing

    /// Strips markdown syntax to produce clean text for TTS
    private func stripMarkdownSyntax(_ text: String) -> String {
        var result = text

        // Remove code blocks (``` ... ```)
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`code`)
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )

        // Remove images ![alt](url)
        result = result.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]+\\)",
            with: "",
            options: .regularExpression
        )

        // Convert links [text](url) to just text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Remove reference-style links [text][ref]
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\[[^\\]]*\\]",
            with: "$1",
            options: .regularExpression
        )

        // Remove heading markers (# ## ### etc.)
        result = result.replacingOccurrences(
            of: "^#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )
        // Also handle headings not at start of string (after newlines)
        result = result.replacingOccurrences(
            of: "\n#{1,6}\\s*",
            with: "\n",
            options: .regularExpression
        )

        // Remove bold/italic markers (**text**, __text__, *text*, _text_)
        // Bold first (** or __)
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "__([^_]+)__",
            with: "$1",
            options: .regularExpression
        )
        // Then italic (* or _)
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?<![\\w])_([^_]+)_(?![\\w])",
            with: "$1",
            options: .regularExpression
        )

        // Remove strikethrough ~~text~~
        result = result.replacingOccurrences(
            of: "~~([^~]+)~~",
            with: "$1",
            options: .regularExpression
        )

        // Remove horizontal rules (---, ***, ___)
        result = result.replacingOccurrences(
            of: "^[-*_]{3,}\\s*$",
            with: "",
            options: .regularExpression
        )

        // Remove blockquotes (> )
        result = result.replacingOccurrences(
            of: "^>+\\s*",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\n>+\\s*",
            with: "\n",
            options: .regularExpression
        )

        // Remove unordered list markers (- * +)
        result = result.replacingOccurrences(
            of: "^[\\-*+]\\s+",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\n[\\-*+]\\s+",
            with: "\n",
            options: .regularExpression
        )

        // Remove ordered list markers (1. 2. etc.)
        result = result.replacingOccurrences(
            of: "^\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\n\\d+\\.\\s+",
            with: "\n",
            options: .regularExpression
        )

        // Clean up extra whitespace
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
