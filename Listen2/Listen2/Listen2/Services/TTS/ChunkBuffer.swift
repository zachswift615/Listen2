//
//  ChunkBuffer.swift
//  Listen2
//
//  Thread-safe buffer for pre-synthesized audio chunks
//

import Foundation

actor ChunkBuffer {
    // MARK: - State

    /// Buffered chunks per sentence: sentenceIndex → chunks
    private var buffers: [Int: [Data]] = [:]

    /// Sentences that have completed synthesis AND all chunks buffered
    private var completedSentences: Set<Int> = []

    /// Current buffer size in bytes
    private var currentSize: Int = 0

    /// Maximum buffer size (2MB - safety limit for long sentences)
    private let maxBufferSize: Int = 2 * 1024 * 1024

    // Metrics
    private var hitCount: Int = 0
    private var missCount: Int = 0

    // MARK: - Public Methods

    /// Add a chunk for a specific sentence
    func addChunk(_ chunk: Data, forSentence index: Int) {
        // Validate chunk
        guard !chunk.isEmpty else {
            return
        }

        guard chunk.count % MemoryLayout<Float>.size == 0 else {
            return
        }

        // Check buffer size limit
        guard currentSize + chunk.count <= maxBufferSize else {
            return
        }

        // Add chunk to buffer
        buffers[index, default: []].append(chunk)
        currentSize += chunk.count
    }

    /// Mark a sentence as complete (all chunks received and buffered)
    /// CRITICAL: Only call this AFTER all delegate Tasks have completed!
    func markComplete(forSentence index: Int) {
        completedSentences.insert(index)
    }

    /// Atomically take all chunks for a sentence (removes from buffer)
    /// Returns nil if synthesis not marked complete
    func takeChunks(forSentence index: Int) -> [Data]? {
        // Check if synthesis is complete
        guard completedSentences.contains(index) else {
            missCount += 1
            return nil
        }

        // Remove chunks from buffer (may be empty for empty sentences)
        let chunks = buffers.removeValue(forKey: index) ?? []

        // Update size and completion tracking
        let chunkSize = chunks.reduce(0) { $0 + $1.count }
        currentSize -= chunkSize
        completedSentences.remove(index)
        hitCount += 1

        return chunks
    }

    /// Check if a sentence is ready (synthesis complete)
    func isReady(forSentence index: Int) -> Bool {
        return completedSentences.contains(index)
    }

    /// Clear all buffered data
    func clearAll() {
        buffers.removeAll()
        completedSentences.removeAll()
        currentSize = 0
    }

    /// Get buffer hit rate metric
    func getHitRate() -> Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }

    /// Get debug info
    func getStatus() -> String {
        let hitRate = getHitRate()
        return "Buffered: \(buffers.count) sentences, \(currentSize) bytes, Hit rate: \(String(format: "%.1f%%", hitRate * 100))"
    }
}
