//
//  SampleContentManager.swift
//  Listen2
//

import Foundation
import SwiftData

@MainActor
class SampleContentManager {

    static let shared = SampleContentManager()

    private init() {}

    struct SampleDocument {
        let filename: String
        let displayName: String
        let sourceType: SourceType
    }

    static let sampleDocuments: [SampleDocument] = [
        SampleDocument(
            filename: "welcome-sample.pdf",
            displayName: "Welcome to Listen2",
            sourceType: .pdf
        ),
        SampleDocument(
            filename: "alice-in-wonderland.epub",
            displayName: "Alice's Adventures in Wonderland",
            sourceType: .epub
        )
    ]

    /// Get URL for a sample document in the app bundle
    func getSampleDocumentURL(filename: String) -> URL? {
        // Extract file name and extension
        let components = filename.split(separator: ".")
        guard components.count >= 2 else {
            print("Invalid filename format: \(filename)")
            return nil
        }

        let name = components.dropLast().joined(separator: ".")
        let ext = String(components.last ?? "")

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("Could not find sample document: \(filename)")
            return nil
        }
        return url
    }

    /// Check if sample documents have already been imported
    func hasSampleDocuments(modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Document>()

        do {
            let documents = try modelContext.fetch(descriptor)
            return documents.contains { doc in
                Self.sampleDocuments.contains { $0.displayName == doc.title }
            }
        } catch {
            print("Error checking for sample documents: \(error)")
            return false
        }
    }

    /// Import all sample documents into the library
    func importSampleDocuments(modelContext: ModelContext, documentProcessor: DocumentProcessor) async throws {
        for sample in Self.sampleDocuments {
            guard let url = getSampleDocumentURL(filename: sample.filename) else {
                print("Skipping \(sample.filename) - not found in bundle")
                continue
            }

            do {
                // Extract text from the sample document
                let paragraphs = try await documentProcessor.extractText(from: url, sourceType: sample.sourceType)

                // Extract TOC data
                let tocData = await documentProcessor.extractTOCData(from: url, sourceType: sample.sourceType, paragraphs: paragraphs)

                // Create document
                let document = Document(
                    title: sample.displayName,
                    sourceType: sample.sourceType,
                    extractedText: paragraphs,
                    fileURL: url,
                    tocEntriesData: tocData
                )

                modelContext.insert(document)
                print("Imported sample document: \(sample.displayName)")

            } catch {
                print("Failed to import sample document \(sample.displayName): \(error)")
                throw error
            }
        }

        try modelContext.save()
    }
}
