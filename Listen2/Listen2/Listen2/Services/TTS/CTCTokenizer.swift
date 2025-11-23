//
//  CTCTokenizer.swift
//  Listen2
//
//  Tokenizes text for CTC forced alignment using MMS_FA vocabulary
//

import Foundation

/// Tokenizes text into indices for CTC forced alignment
final class CTCTokenizer {

    // MARK: - Properties

    /// Label to index mapping
    private let labelToIndex: [Character: Int]

    /// Index to label mapping (for debugging)
    private let indexToLabel: [Int: Character]

    /// Blank token index (for CTC)
    let blankIndex: Int

    /// Space token index
    let spaceIndex: Int?

    /// Vocabulary size
    let vocabSize: Int

    // MARK: - Initialization

    /// Initialize with labels array
    /// - Parameter labels: Array of label strings in vocabulary order
    init(labels: [String]) {
        var l2i: [Character: Int] = [:]
        var i2l: [Int: Character] = [:]

        for (index, label) in labels.enumerated() {
            if let char = label.first {
                l2i[char] = index
                i2l[index] = char
            }
        }

        self.labelToIndex = l2i
        self.indexToLabel = i2l
        self.vocabSize = labels.count

        // CTC blank is "-" at index 0 in MMS_FA
        self.blankIndex = l2i["-"] ?? 0

        // Space token is "*" at index 28 in MMS_FA
        self.spaceIndex = l2i["*"]
    }

    /// Initialize from labels file
    /// - Parameter labelsURL: URL to labels.txt file (one label per line)
    convenience init(labelsURL: URL) throws {
        let content = try String(contentsOf: labelsURL, encoding: .utf8)
        let labels = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        self.init(labels: labels)
    }

    // MARK: - Tokenization

    /// Tokenize text into token indices
    /// - Parameter text: Text to tokenize
    /// - Returns: Array of token indices (unknown chars are skipped)
    func tokenize(_ text: String) -> [Int] {
        return tokenize(text, includeSpaces: true)
    }

    /// Tokenize text into token indices with option to skip spaces
    /// - Parameters:
    ///   - text: Text to tokenize
    ///   - includeSpaces: Whether to include space tokens (default true)
    /// - Returns: Array of token indices (unknown chars are skipped)
    func tokenize(_ text: String, includeSpaces: Bool) -> [Int] {
        var tokens: [Int] = []

        let normalized = text.lowercased()

        for char in normalized {
            if char == " " {
                // Add space token only if requested and available
                if includeSpaces, let spaceIdx = spaceIndex {
                    tokens.append(spaceIdx)
                }
            } else if let idx = labelToIndex[char] {
                tokens.append(idx)
            }
            // Skip unknown characters silently
        }

        return tokens
    }

    /// Get label for token index (for debugging)
    /// - Parameter index: Token index
    /// - Returns: Label character or nil if invalid index
    func label(for index: Int) -> Character? {
        return indexToLabel[index]
    }

    /// Convert token indices back to text (for debugging)
    /// - Parameter tokens: Array of token indices
    /// - Returns: Reconstructed text
    func detokenize(_ tokens: [Int]) -> String {
        return tokens.compactMap { indexToLabel[$0] }
            .map { $0 == "*" ? " " : String($0) }
            .joined()
    }
}
