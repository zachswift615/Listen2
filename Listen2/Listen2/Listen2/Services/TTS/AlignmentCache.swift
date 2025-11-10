//
//  AlignmentCache.swift
//  Listen2
//
//  Persistent disk cache for alignment results
//

import Foundation

/// Actor for managing persistent disk cache of word-level alignments
actor AlignmentCache {
    // MARK: - Properties

    /// File manager for file operations
    private let fileManager = FileManager.default

    /// Base cache directory URL (Caches/WordAlignments)
    private let cacheBaseURL: URL

    // MARK: - Initialization

    init() {
        // Get the Caches directory
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheBaseURL = cachesDir.appendingPathComponent("WordAlignments")

        // Create base directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheBaseURL, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Save an alignment result to disk
    /// - Parameters:
    ///   - alignment: The alignment result to save
    ///   - documentID: UUID of the document
    ///   - paragraph: Paragraph index
    /// - Throws: AlignmentError.cacheWriteFailed if save fails
    func save(_ alignment: AlignmentResult, for documentID: UUID, paragraph: Int) async throws {
        let fileURL = getFileURL(for: documentID, paragraph: paragraph)

        // Create document directory if needed
        let documentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: documentDir.path) {
            do {
                try fileManager.createDirectory(at: documentDir, withIntermediateDirectories: true)
            } catch {
                throw AlignmentError.cacheWriteFailed("Failed to create cache directory: \(error.localizedDescription)")
            }
        }

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(alignment)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw AlignmentError.cacheWriteFailed("Failed to encode or write alignment: \(error.localizedDescription)")
        }
    }

    /// Load an alignment result from disk
    /// - Parameters:
    ///   - documentID: UUID of the document
    ///   - paragraph: Paragraph index
    /// - Returns: The cached alignment, or nil if not found
    /// - Throws: AlignmentError.cacheReadFailed if file exists but cannot be decoded
    func load(for documentID: UUID, paragraph: Int) async throws -> AlignmentResult? {
        let fileURL = getFileURL(for: documentID, paragraph: paragraph)

        // Check if file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Read and decode
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let alignment = try decoder.decode(AlignmentResult.self, from: data)
            return alignment
        } catch {
            throw AlignmentError.cacheReadFailed("Failed to read or decode alignment: \(error.localizedDescription)")
        }
    }

    /// Clear all cached alignments for a document
    /// - Parameter documentID: UUID of the document
    /// - Throws: AlignmentError.cacheWriteFailed if deletion fails
    func clear(for documentID: UUID) async throws {
        let documentDir = getDocumentDirectoryURL(for: documentID)

        // Check if directory exists
        guard fileManager.fileExists(atPath: documentDir.path) else {
            // Nothing to clear
            return
        }

        // Remove the entire document directory
        do {
            try fileManager.removeItem(at: documentDir)
        } catch {
            throw AlignmentError.cacheWriteFailed("Failed to clear cache: \(error.localizedDescription)")
        }
    }

    /// Clear all cached alignments for all documents
    /// - Throws: AlignmentError.cacheWriteFailed if deletion fails
    func clearAll() async throws {
        // Check if cache directory exists
        guard fileManager.fileExists(atPath: cacheBaseURL.path) else {
            // Nothing to clear
            return
        }

        do {
            // Get all document directories
            let contents = try fileManager.contentsOfDirectory(at: cacheBaseURL, includingPropertiesForKeys: nil)

            // Remove each document directory
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw AlignmentError.cacheWriteFailed("Failed to clear all cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal Methods (for testing)

    /// Get the cache directory URL (for testing)
    func getCacheDirectoryURL() throws -> URL {
        return cacheBaseURL
    }

    // MARK: - Private Methods

    /// Get the file URL for a specific alignment
    /// - Parameters:
    ///   - documentID: UUID of the document
    ///   - paragraph: Paragraph index
    /// - Returns: URL to the cache file
    private func getFileURL(for documentID: UUID, paragraph: Int) -> URL {
        let documentDir = getDocumentDirectoryURL(for: documentID)
        return documentDir.appendingPathComponent("\(paragraph).json")
    }

    /// Get the directory URL for a document's cache
    /// - Parameter documentID: UUID of the document
    /// - Returns: URL to the document's cache directory
    private func getDocumentDirectoryURL(for documentID: UUID) -> URL {
        return cacheBaseURL.appendingPathComponent(documentID.uuidString)
    }
}
