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

    init(
        title: String,
        sourceType: SourceType,
        extractedText: [String],
        fileURL: URL? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.sourceType = sourceType
        self.extractedText = extractedText
        self.currentPosition = 0
        self.lastRead = Date()
        self.createdAt = Date()
        self.fileURL = fileURL
    }

    var progressPercentage: Int {
        guard !extractedText.isEmpty else { return 0 }
        return Int((Double(currentPosition) / Double(extractedText.count)) * 100)
    }
}
