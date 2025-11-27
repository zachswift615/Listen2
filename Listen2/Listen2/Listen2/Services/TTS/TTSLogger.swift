//
//  TTSLogger.swift
//  Listen2
//
//  Structured logging for TTS pipeline errors and diagnostics
//

import Foundation
import OSLog

/// Centralized logger for TTS pipeline events
enum TTSLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.listen2.app"

    /// Logger for synthesis errors and pipeline issues
    static let pipeline = Logger(subsystem: subsystem, category: "TTS.Pipeline")

    /// Logger for CTC alignment errors
    static let alignment = Logger(subsystem: subsystem, category: "TTS.Alignment")

    /// Logger for buffer management and eviction
    static let buffer = Logger(subsystem: subsystem, category: "TTS.Buffer")
}
