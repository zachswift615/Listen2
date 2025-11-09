//
//  WordPosition.swift
//  Listen2
//
//  Models for word-level position tracking in documents
//

import Foundation

/// Represents a word with its position in the document
struct WordPosition: Codable, Equatable {
    /// The word text
    let text: String

    /// Character offset in the combined paragraph text
    let characterOffset: Int

    /// Character length of the word
    let length: Int

    /// Index of the paragraph this word belongs to
    let paragraphIndex: Int

    /// Page number (0-indexed)
    let pageNumber: Int

    /// Bounding box position on page (optional, for visual highlighting)
    let boundingBox: BoundingBox?

    /// Bounding box for word position on page
    struct BoundingBox: Codable, Equatable {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }

    init(
        text: String,
        characterOffset: Int,
        length: Int,
        paragraphIndex: Int,
        pageNumber: Int,
        boundingBox: BoundingBox? = nil
    ) {
        self.text = text
        self.characterOffset = characterOffset
        self.length = length
        self.paragraphIndex = paragraphIndex
        self.pageNumber = pageNumber
        self.boundingBox = boundingBox
    }
}

/// Maps paragraph indices to their word positions for efficient lookup
struct DocumentWordMap: Codable {
    /// Array of all words in document order
    let words: [WordPosition]

    /// Quick lookup: paragraph index -> word positions
    private(set) var wordsByParagraph: [Int: [WordPosition]] = [:]

    init(words: [WordPosition]) {
        self.words = words
        self.wordsByParagraph = Dictionary(grouping: words, by: { $0.paragraphIndex })
    }

    /// Get words for a specific paragraph
    func words(for paragraphIndex: Int) -> [WordPosition] {
        return wordsByParagraph[paragraphIndex] ?? []
    }

    /// Find word at character offset within a paragraph
    /// - Parameters:
    ///   - offset: Character offset within the paragraph
    ///   - paragraphIndex: Index of the paragraph
    /// - Returns: The word at the given offset, or nil if not found
    func word(at offset: Int, in paragraphIndex: Int) -> WordPosition? {
        let paragraphWords = words(for: paragraphIndex)
        return paragraphWords.first { word in
            offset >= word.characterOffset && offset < word.characterOffset + word.length
        }
    }

    /// Find the word range for a character range in a paragraph
    /// - Parameters:
    ///   - range: NSRange of characters in the paragraph
    ///   - paragraphIndex: Index of the paragraph
    ///   - paragraphText: The full text of the paragraph for index conversion
    /// - Returns: String.Index range for the word, or nil if not found
    func wordRange(for range: NSRange, in paragraphIndex: Int, paragraphText: String) -> Range<String.Index>? {
        // Convert NSRange to character offset
        let location = range.location

        // Find the word at this location
        guard let word = self.word(at: location, in: paragraphIndex) else {
            return nil
        }

        // Convert character offsets to String.Index
        guard let startIndex = paragraphText.index(
            paragraphText.startIndex,
            offsetBy: word.characterOffset,
            limitedBy: paragraphText.endIndex
        ) else {
            return nil
        }

        guard let endIndex = paragraphText.index(
            startIndex,
            offsetBy: word.length,
            limitedBy: paragraphText.endIndex
        ) else {
            return nil
        }

        return startIndex..<endIndex
    }
}
