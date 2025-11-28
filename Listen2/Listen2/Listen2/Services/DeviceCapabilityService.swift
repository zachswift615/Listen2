//
//  DeviceCapabilityService.swift
//  Listen2
//
//  Detects device capabilities and provides adaptive configuration
//  for memory-intensive features like CTC forced alignment.
//

import Foundation

/// Service for detecting device capabilities and recommending feature configurations
enum DeviceCapabilityService {

    // MARK: - Device Tier Classification

    /// Device tier based on memory and capability
    enum DeviceTier: Int, Comparable {
        /// iPhone 8 and earlier, very constrained (<3GB RAM)
        case legacy = 0
        /// iPhone X/XS/XR, constrained (3-4GB RAM)
        case lowMemory = 1
        /// iPhone 11-14, standard capability (4-6GB RAM)
        case standard = 2
        /// iPhone 14 Pro+, high capability (6GB+ RAM)
        case high = 3

        static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Memory Detection

    /// Total physical memory in bytes
    static var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Total physical memory in GB
    static var physicalMemoryGB: Double {
        Double(physicalMemoryBytes) / (1024 * 1024 * 1024)
    }

    // MARK: - Device Model Detection

    /// Whether running in simulator
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Simulated device model from environment (only available in simulator)
    static var simulatorModelIdentifier: String? {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        #else
        return nil
        #endif
    }

    /// Device model identifier (e.g., "iPhone11,6" for iPhone XS Max)
    static var modelIdentifier: String {
        // In simulator, use the SIMULATOR_MODEL_IDENTIFIER environment variable
        if let simModel = simulatorModelIdentifier {
            return simModel
        }

        // On real device, use uname
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    // MARK: - Device Model Lists

    /// Devices known to have limited memory (4GB or less)
    private static let lowMemoryDevices: Set<String> = [
        // iPhone X series (3-4GB)
        "iPhone10,3", "iPhone10,6",  // iPhone X
        "iPhone11,2",                 // iPhone XS
        "iPhone11,4", "iPhone11,6",   // iPhone XS Max
        "iPhone11,8",                 // iPhone XR
        // iPhone 11 (4GB)
        "iPhone12,1",                 // iPhone 11
    ]

    /// Legacy devices with very limited memory (<3GB)
    private static let legacyDevices: Set<String> = [
        // iPhone 8 and earlier
        "iPhone10,1", "iPhone10,2", "iPhone10,4", "iPhone10,5",  // iPhone 8/8 Plus
        "iPhone9,1", "iPhone9,2", "iPhone9,3", "iPhone9,4",      // iPhone 7/7 Plus
        "iPhone8,1", "iPhone8,2", "iPhone8,4",                   // iPhone 6s/6s Plus/SE
    ]

    // MARK: - Tier Classification

    /// Current device's capability tier based on device model (more reliable than memory on simulator)
    static var deviceTier: DeviceTier {
        let model = modelIdentifier

        // Check by device model first (most reliable)
        if legacyDevices.contains(model) {
            return .legacy
        }
        if lowMemoryDevices.contains(model) {
            return .lowMemory
        }

        // Fallback to memory-based detection for unknown devices
        let memoryGB = physicalMemoryGB
        if memoryGB < 3.0 {
            return .legacy
        } else if memoryGB < 5.0 {
            return .lowMemory
        } else if memoryGB < 7.0 {
            return .standard
        } else {
            return .high
        }
    }

    // MARK: - Feature Recommendations

    /// Recommended highlight level for this device
    static var recommendedHighlightLevel: HighlightLevel {
        switch deviceTier {
        case .legacy:
            return .paragraph
        case .lowMemory:
            return .sentence
        case .standard, .high:
            return .word
        }
    }

    /// Whether word-level highlighting should be restricted on this device
    static var isWordLevelRestricted: Bool {
        deviceTier <= .lowMemory
    }

    /// Maximum highlight level allowed on this device
    /// Note: This is a recommendation, not a hard limit - users can still choose higher levels
    static var maxAllowedHighlightLevel: HighlightLevel {
        // Allow all levels on all devices - user can override
        // The warning in Settings UI will inform users of potential issues
        return .word
    }

    // MARK: - Buffer Configuration

    /// Recommended maximum sentences to buffer ahead
    static var maxSentenceLookahead: Int {
        switch deviceTier {
        case .legacy:
            return 2
        case .lowMemory:
            return 3
        case .standard, .high:
            return 5
        }
    }

    /// Recommended maximum audio buffer size in bytes
    static var maxBufferBytes: Int {
        switch deviceTier {
        case .legacy:
            return 3 * 1024 * 1024  // 3MB
        case .lowMemory:
            return 5 * 1024 * 1024  // 5MB
        case .standard, .high:
            return 10 * 1024 * 1024  // 10MB
        }
    }

    /// Recommended maximum trellis size for CTC alignment
    static var maxTrellisSize: Int {
        switch deviceTier {
        case .legacy:
            return 250_000
        case .lowMemory:
            return 500_000
        case .standard:
            return 1_000_000
        case .high:
            return 2_000_000
        }
    }

    // MARK: - Debug Info

    /// Human-readable description of current device capabilities
    static var debugDescription: String {
        """
        Device: \(modelIdentifier)
        Memory: \(String(format: "%.1f", physicalMemoryGB)) GB
        Tier: \(deviceTier)
        Recommended Highlight: \(recommendedHighlightLevel.displayName)
        Max Lookahead: \(maxSentenceLookahead) sentences
        Max Buffer: \(maxBufferBytes / (1024 * 1024)) MB
        """
    }
}
