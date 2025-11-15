//
//  SentenceSplitter.swift
//  Listen2
//

import Foundation
import NaturalLanguage

/// Represents a sentence chunk with its position in the original text
struct SentenceChunk {
    /// The sentence text
    let text: String

    /// Character range in original paragraph (using Int offsets)
    let range: Range<Int>

    /// Sentence index within paragraph (0-based)
    let index: Int
}

/// Splits paragraphs into sentences for chunked synthesis
struct SentenceSplitter {

    /// Split paragraph into sentences using NLTokenizer
    /// - Parameter text: The paragraph text to split
    /// - Returns: Array of sentence chunks with ranges
    static func split(_ text: String) -> [SentenceChunk] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var chunks: [SentenceChunk] = []
        var sentenceIndex = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentenceText = String(text[range])

            // Convert String.Index range to Int range
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)

            let chunk = SentenceChunk(
                text: sentenceText,
                range: startOffset..<endOffset,
                index: sentenceIndex
            )

            chunks.append(chunk)
            sentenceIndex += 1

            return true  // Continue enumeration
        }

        // Fallback: if no sentences detected, treat entire text as one sentence
        if chunks.isEmpty {
            chunks.append(SentenceChunk(
                text: text,
                range: 0..<text.count,
                index: 0
            ))
        }

        return chunks
    }
}
