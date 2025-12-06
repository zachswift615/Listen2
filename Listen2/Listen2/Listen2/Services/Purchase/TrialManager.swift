//
//  TrialManager.swift
//  Listen2
//

import Foundation
import Security
import StoreKit

/// Manages trial period tracking using dual-source "earliest wins" logic
actor TrialManager {

    static let shared = TrialManager()

    private let trialDurationDays = 7
    private let keychainKey = "com.listen2.trialStartDate"

    private init() {}

    // MARK: - Public API

    /// Get trial status based on earliest start date from Keychain or Receipt
    func getTrialStatus() async -> EntitlementState {
        let startDate = await getTrialStartDate()
        let daysRemaining = calculateDaysRemaining(from: startDate)

        if daysRemaining > 0 {
            return .trial(daysRemaining: daysRemaining)
        } else {
            return .expired
        }
    }

    /// Get the trial start date using "earliest wins" logic
    func getTrialStartDate() async -> Date {
        let receiptDate = await getReceiptDate()
        let keychainDate = getKeychainDate()

        switch (receiptDate, keychainDate) {
        case let (r?, k?):
            // Both available - use earliest (most conservative)
            return min(r, k)
        case let (r?, nil):
            // Receipt only - save to Keychain for consistency
            saveToKeychain(r)
            return r
        case let (nil, k?):
            // Keychain only (receipt fetch failed)
            return k
        case (nil, nil):
            // True fresh install - start trial now
            let now = Date()
            saveToKeychain(now)
            return now
        }
    }

    // MARK: - Day Calculation

    private func calculateDaysRemaining(from startDate: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let daysPassed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return max(0, trialDurationDays - daysPassed)
    }

    // MARK: - Receipt Date (StoreKit 2)

    private func getReceiptDate() async -> Date? {
        do {
            let result = try await AppTransaction.shared
            switch result {
            case .verified(let appTransaction):
                return appTransaction.originalPurchaseDate
            case .unverified:
                return nil
            }
        } catch {
            // Receipt fetch failed (network, sandbox, etc.)
            print("TrialManager: Failed to get app transaction: \(error)")
            return nil
        }
    }

    // MARK: - Keychain Storage

    private func getKeychainDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let timeInterval = try? JSONDecoder().decode(Double.self, from: data) else {
            return nil
        }

        return Date(timeIntervalSince1970: timeInterval)
    }

    private func saveToKeychain(_ date: Date) {
        let timeInterval = date.timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(timeInterval) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
