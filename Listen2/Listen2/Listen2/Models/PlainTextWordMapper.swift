//
//  PlainTextWordMapper.swift
//  Listen2
//
//  Generates word position maps from plain text for word-level highlighting
//

import Foundation

/// Utility for generating word position maps from plain text paragraphs
struct PlainTextWordMapper {

    /// Create a DocumentWordMap from plain text paragraphs
    /// - Parameter paragraphs: Array of paragraph strings
    /// - Returns: DocumentWordMap with word positions for all paragraphs
    static func createWordMap(from paragraphs: [String]) -> DocumentWordMap {
        var allWords: [WordPosition] = []

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let paragraphWords = extractWords(from: paragraph, paragraphIndex: paragraphIndex)
            allWords.append(contentsOf: paragraphWords)
        }

        return DocumentWordMap(words: allWords)
    }

    /// Extract words from a single paragraph
    /// - Parameters:
    ///   - text: The paragraph text
    ///   - paragraphIndex: Index of this paragraph in the document
    /// - Returns: Array of WordPosition objects for this paragraph
    private static func extractWords(from text: String, paragraphIndex: Int) -> [WordPosition] {
        var words: [WordPosition] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            // Skip whitespace
            while currentIndex < text.endIndex && text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }

            guard currentIndex < text.endIndex else { break }

            // Collect word characters
            let wordStart = currentIndex
            while currentIndex < text.endIndex && !text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }

            let wordRange = wordStart..<currentIndex
            let wordText = String(text[wordRange])

            // Calculate character offset and length
            let characterOffset = text.distance(from: text.startIndex, to: wordStart)
            let length = text.distance(from: wordStart, to: currentIndex)

            let wordPosition = WordPosition(
                text: wordText,
                characterOffset: characterOffset,
                length: length,
                paragraphIndex: paragraphIndex,
                pageNumber: 0, // N/A for plain text (EPUBs don't have pages)
                boundingBox: nil // No visual layout for plain text
            )

            words.append(wordPosition)
        }

        return words
    }
}
