//
//  SentenceSynthesisResult.swift
//  Listen2
//

import Foundation

/// Result of synthesizing a single sentence chunk
struct SentenceSynthesisResult {
    /// The sentence chunk that was synthesized
    let chunk: SentenceChunk

    /// Synthesized audio data (WAV format)
    let audioData: Data

    /// Word-level alignment for this sentence
    let alignment: AlignmentResult?

    /// Audio duration in seconds
    var audioDuration: Double {
        // WAV header is 44 bytes, then 16-bit samples at 22050 Hz
        guard audioData.count > 44 else { return 0 }
        let sampleCount = (audioData.count - 44) / 2
        return Double(sampleCount) / 22050.0
    }
}

/// Container for all sentences in a paragraph
struct ParagraphSynthesisResult {
    /// Paragraph index
    let paragraphIndex: Int

    /// All sentence results (ordered)
    let sentences: [SentenceSynthesisResult]

    /// Concatenated audio data for entire paragraph
    var combinedAudioData: Data {
        // Concatenate audio data (skip WAV headers for sentences 2+)
        guard !sentences.isEmpty else { return Data() }

        var combined = sentences[0].audioData

        for sentence in sentences.dropFirst() {
            // Skip 44-byte WAV header on subsequent chunks
            let audioOnly = sentence.audioData.dropFirst(44)
            combined.append(audioOnly)
        }

        return combined
    }

    /// Combined alignment for entire paragraph
    var combinedAlignment: AlignmentResult? {
        guard !sentences.isEmpty else { return nil }

        // TODO: Implement alignment concatenation in Task 9
        // For now, return first sentence alignment
        return sentences.first?.alignment
    }

    /// Total duration of paragraph in seconds
    var totalDuration: Double {
        sentences.reduce(0.0) { $0 + $1.audioDuration }
    }
}
