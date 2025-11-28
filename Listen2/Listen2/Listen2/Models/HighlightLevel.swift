//
//  HighlightLevel.swift
//  Listen2
//
//  Defines the granularity levels for text highlighting during playback.
//

import Foundation

/// The level of text highlighting granularity during audio playback
enum HighlightLevel: String, CaseIterable, Identifiable, Codable, Equatable {
    /// Highlight individual words as they're spoken (requires CTC alignment)
    case word = "word"
    /// Highlight the current sentence being spoken
    case sentence = "sentence"
    /// Highlight the current paragraph being spoken
    case paragraph = "paragraph"
    /// No text highlighting
    case off = "off"

    var id: String { rawValue }

    /// User-facing display name
    var displayName: String {
        switch self {
        case .word: return "Word"
        case .sentence: return "Sentence"
        case .paragraph: return "Paragraph"
        case .off: return "Off"
        }
    }

    /// User-facing description of what this level does
    var description: String {
        switch self {
        case .word: return "Highlight each word as it's spoken"
        case .sentence: return "Highlight the current sentence"
        case .paragraph: return "Highlight the current paragraph"
        case .off: return "No highlighting during playback"
        }
    }

    /// Whether this highlight level requires CTC forced alignment
    /// Only word-level highlighting needs the expensive CTC processing
    var requiresCTC: Bool {
        self == .word
    }

    /// Granularity order (higher = more granular)
    var granularity: Int {
        switch self {
        case .off: return 0
        case .paragraph: return 1
        case .sentence: return 2
        case .word: return 3
        }
    }

    /// Whether this level is at least as granular as another level
    func isAtLeastAsGranularAs(_ other: HighlightLevel) -> Bool {
        self.granularity >= other.granularity
    }
}
