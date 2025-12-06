//
//  PurchaseManager.swift
//  Listen2
//

import Foundation
import StoreKit

/// Manages StoreKit 2 purchases and entitlement state
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // Product ID configured in App Store Connect
    static let productID = "com.listen2.fullaccess"

    @Published private(set) var entitlementState: EntitlementState = .loading
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing: Bool = false

    private var transactionListener: Task<Void, Error>?

    private init() {
        // Start listening for transactions immediately
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Initialization

    /// Call this on app launch to determine entitlement state
    func initialize() async {
        // Load product info
        await loadProduct()

        // Check for existing purchase first
        if await checkForPurchase() {
            entitlementState = .purchased
            return
        }

        // No purchase - check trial status
        entitlementState = await TrialManager.shared.getTrialStatus()
    }

    // MARK: - Product Loading

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("PurchaseManager: Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase Check

    private func checkForPurchase() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.productID {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Purchase

    func purchase() async throws {
        guard let product = product else {
            throw PurchaseError.productNotFound
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            entitlementState = .purchased

        case .userCancelled:
            break

        case .pending:
            // Handle pending (e.g., parental approval)
            break

        @unknown default:
            break
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        // Sync with App Store
        do {
            try await AppStore.sync()
        } catch {
            print("PurchaseManager: Sync failed: \(error)")
        }

        // Re-check entitlements
        if await checkForPurchase() {
            entitlementState = .purchased
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    if transaction.productID == PurchaseManager.productID {
                        await MainActor.run {
                            self.entitlementState = .purchased
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let item):
            return item
        case .unverified:
            throw PurchaseError.verificationFailed
        }
    }
}

// MARK: - Errors

enum PurchaseError: LocalizedError {
    case productNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Product not found. Please try again later."
        case .verificationFailed:
            return "Purchase verification failed."
        }
    }
}
