//
//  ReadingProgress.swift
//  Listen2
//

import Foundation

struct ReadingProgress {
    let paragraphIndex: Int
    let wordRange: Range<String.Index>?
    let isPlaying: Bool

    static let initial = ReadingProgress(
        paragraphIndex: 0,
        wordRange: nil,
        isPlaying: false
    )
}
