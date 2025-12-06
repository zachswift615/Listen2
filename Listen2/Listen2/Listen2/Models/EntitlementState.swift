//
//  EntitlementState.swift
//  Listen2
//

import Foundation

/// Single source of truth for user's access level
enum EntitlementState: Equatable {
    case loading                    // Checking purchase/trial status
    case trial(daysRemaining: Int)  // 1-7 days left
    case expired                    // Trial over, must purchase
    case purchased                  // Full access

    /// Whether TTS features are accessible
    var canUseTTS: Bool {
        switch self {
        case .loading:
            return false  // Block until we know status
        case .trial:
            return true
        case .expired:
            return false
        case .purchased:
            return true
        }
    }

    /// Whether trial is active (for UI messaging)
    var isTrialActive: Bool {
        if case .trial = self { return true }
        return false
    }

    /// Display text for settings UI
    var displayText: String {
        switch self {
        case .loading:
            return "Checking status..."
        case .trial(let days):
            return days == 1 ? "Trial: 1 day remaining" : "Trial: \(days) days remaining"
        case .expired:
            return "Trial Expired"
        case .purchased:
            return "Full Version Unlocked"
        }
    }
}
