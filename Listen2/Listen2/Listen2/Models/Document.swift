//
//  Document.swift
//  Listen2
//

import Foundation
import SwiftData

@Model
final class Document {
    var id: UUID
    var title: String
    var sourceType: SourceType
    var extractedText: [String] // Array of paragraphs
    var currentPosition: Int // Current paragraph index
    var lastRead: Date
    var createdAt: Date
    var fileURL: URL? // Original file location
    var tocEntriesData: Data? // Stored TOC entries as JSON

    @Attribute(.externalStorage)
    var wordMapData: Data? // Stored word map for word-level highlighting (PDF only)

    @Attribute(.externalStorage)
    var coverImageData: Data? // Cover image thumbnail (PNG/JPEG data)

    init(
        title: String,
        sourceType: SourceType,
        extractedText: [String],
        fileURL: URL? = nil,
        tocEntriesData: Data? = nil,
        wordMapData: Data? = nil,
        coverImageData: Data? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.sourceType = sourceType
        self.extractedText = extractedText
        self.currentPosition = 0
        self.lastRead = Date()
        self.createdAt = Date()
        self.fileURL = fileURL
        self.tocEntriesData = tocEntriesData
        self.wordMapData = wordMapData
        self.coverImageData = coverImageData
    }

    var progressPercentage: Int {
        guard !extractedText.isEmpty else { return 0 }
        return Int((Double(currentPosition) / Double(extractedText.count)) * 100)
    }

    /// Decode word map from stored data (for word-level highlighting)
    var wordMap: DocumentWordMap? {
        guard let data = wordMapData else { return nil }
        return try? JSONDecoder().decode(DocumentWordMap.self, from: data)
    }
}
