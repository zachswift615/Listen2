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

            let title = url.deletingPathExtension().lastPathComponent

            let document = Document(
                title: title,
                sourceType: sourceType,
                extractedText: paragraphs,
                fileURL: url,
                tocEntriesData: tocData
            )

            modelContext.insert(document)
            try modelContext.save()
            loadDocuments()

        } catch {
            errorMessage = "Failed to import document: \(error.localizedDescription)"
        }

        isProcessing = false
    }
}
