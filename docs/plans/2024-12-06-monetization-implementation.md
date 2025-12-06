# Listen2 Monetization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 7-day free trial with $24.99 one-time purchase, gating TTS playback after trial expiration.

**Architecture:** StoreKit 2 for purchases, dual-source trial tracking (Keychain + App Receipt with "earliest wins" logic), EntitlementState enum as single source of truth injected via SwiftUI environment.

**Tech Stack:** StoreKit 2, SwiftUI, Keychain Services, @AppStorage

---

## Task 1: Create EntitlementState Model

**Files:**
- Create: `Listen2/Listen2/Listen2/Models/EntitlementState.swift`

**Step 1: Create the EntitlementState enum**

```swift
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
```

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2/Models/EntitlementState.swift
git commit -m "feat: add EntitlementState model for purchase/trial tracking"
```

---

## Task 2: Create TrialManager

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/Purchase/TrialManager.swift`

**Step 1: Create TrialManager with Keychain support**

```swift
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
```

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/Purchase/TrialManager.swift
git commit -m "feat: add TrialManager with Keychain + Receipt dual-source tracking"
```

---

## Task 3: Create PurchaseManager

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/Purchase/PurchaseManager.swift`

**Step 1: Create PurchaseManager with StoreKit 2**

```swift
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
```

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/Purchase/PurchaseManager.swift
git commit -m "feat: add PurchaseManager with StoreKit 2 integration"
```

---

## Task 4: Create StoreKit Configuration File for Testing

**Files:**
- Create: `Listen2/Listen2/Listen2/Configuration/StoreKit Configuration.storekit`

**Step 1: Create StoreKit configuration**

In Xcode:
1. File > New > File
2. Search for "StoreKit Configuration File"
3. Name it "StoreKit Configuration"
4. Save to `Listen2/Listen2/Listen2/Configuration/`
5. Click the + button and add a Non-Consumable product:
   - Reference Name: "Listen2 Full Access"
   - Product ID: `com.listen2.fullaccess`
   - Price: $24.99

**Step 2: Enable StoreKit Testing in scheme**

1. Edit Scheme (⌘<)
2. Run > Options
3. Set "StoreKit Configuration" to your new file

**Step 3: Commit**

```bash
git add "Listen2/Listen2/Listen2/Configuration/StoreKit Configuration.storekit"
git commit -m "feat: add StoreKit configuration file for testing"
```

---

## Task 5: Create UpgradePromptView

**Files:**
- Create: `Listen2/Listen2/Listen2/Views/UpgradePromptView.swift`

**Step 1: Create the upgrade prompt sheet**

```swift
//
//  UpgradePromptView.swift
//  Listen2
//

import SwiftUI

/// Full-screen prompt shown when expired user tries to use TTS
struct UpgradePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.Colors.primary)

            // Title
            Text("Your free trial has ended")
                .font(DesignSystem.Typography.title)
                .multilineTextAlignment(.center)

            // Description
            Text("Unlock TTS playback and all voices with a one-time purchase.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.lg)

            Spacer()

            // Purchase button
            Button {
                Task {
                    await purchase()
                }
            } label: {
                HStack {
                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Unlock Listen2 — \(priceText)")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DesignSystem.Colors.primary)
                .foregroundStyle(.white)
                .font(DesignSystem.Typography.headline)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .disabled(purchaseManager.isPurchasing)
            .padding(.horizontal, DesignSystem.Spacing.lg)

            // Restore button
            Button("Restore Purchase") {
                Task {
                    await purchaseManager.restorePurchases()
                    if purchaseManager.entitlementState == .purchased {
                        dismiss()
                    }
                }
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.primary)

            // Cancel button
            Button("Not Now") {
                dismiss()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: purchaseManager.entitlementState) { _, newState in
            if newState == .purchased {
                dismiss()
            }
        }
    }

    private var priceText: String {
        purchaseManager.product?.displayPrice ?? "$24.99"
    }

    private func purchase() async {
        do {
            try await purchaseManager.purchase()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
```

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/UpgradePromptView.swift
git commit -m "feat: add UpgradePromptView for expired trial users"
```

---

## Task 6: Add Upgrade Section to SettingsView

**Files:**
- Modify: `Listen2/Listen2/Listen2/Views/SettingsView.swift`

**Step 1: Add PurchaseManager environment object**

At the top of SettingsView, add:

```swift
@EnvironmentObject private var purchaseManager: PurchaseManager
```

**Step 2: Add upgrade section before Playback section**

Insert this new section at the beginning of the Form (before the Playback section):

```swift
// MARK: - Upgrade Section
Section {
    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
        HStack {
            Image(systemName: purchaseManager.entitlementState == .purchased ? "checkmark.seal.fill" : "waveform")
                .font(.system(size: DesignSystem.IconSize.large))
                .foregroundStyle(DesignSystem.Colors.primary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                Text("Listen2 Pro")
                    .font(DesignSystem.Typography.headline)

                Text(purchaseManager.entitlementState.displayText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(purchaseManager.entitlementState == .expired ? .orange : DesignSystem.Colors.textSecondary)
            }
        }

        if purchaseManager.entitlementState != .purchased {
            // Purchase button
            Button {
                Task {
                    try? await purchaseManager.purchase()
                }
            } label: {
                HStack {
                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(purchaseManager.entitlementState == .expired ? "Unlock Listen2" : "Upgrade")
                        Spacer()
                        Text(purchaseManager.product?.displayPrice ?? "$24.99")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.primary)
                .foregroundStyle(.white)
                .font(DesignSystem.Typography.body.weight(.medium))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
            .disabled(purchaseManager.isPurchasing)

            // Restore purchases
            Button("Restore Purchase") {
                Task {
                    await purchaseManager.restorePurchases()
                }
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.primary)
        }
    }
    .padding(.vertical, DesignSystem.Spacing.xs)
} header: {
    Text("Subscription")
}
```

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/SettingsView.swift
git commit -m "feat: add upgrade section to SettingsView"
```

---

## Task 7: Integrate PurchaseManager into App

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2App.swift`

**Step 1: Add PurchaseManager StateObject**

Add this property to Listen2App:

```swift
@StateObject private var purchaseManager = PurchaseManager.shared
```

**Step 2: Initialize PurchaseManager on app launch**

In the `body` property, wrap the existing content and add initialization. Update the WindowGroup:

```swift
WindowGroup {
    Group {
        if ttsService.isInitializing || purchaseManager.entitlementState == .loading {
            LoadingView()
        } else {
            LibraryView(
                modelContext: sharedModelContainer.mainContext,
                urlToImport: $urlToImport,
                siriReadClipboard: $siriReadClipboard
            )
            .environmentObject(ttsService)
            .environmentObject(purchaseManager)
            .onOpenURL { url in
                urlToImport = url
            }
            .onAppear {
                checkSiriTrigger()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkSiriTrigger()
            }
        }
    }
    .task {
        await purchaseManager.initialize()
    }
}
```

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2App.swift
git commit -m "feat: integrate PurchaseManager into app lifecycle"
```

---

## Task 8: Gate TTS Playback in ReaderViewModel

**Files:**
- Modify: `Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`

**Step 1: Add PurchaseManager dependency and state**

Add these properties to ReaderViewModel:

```swift
@Published var showUpgradePrompt: Bool = false
private let purchaseManager: PurchaseManager
```

**Step 2: Update init to accept PurchaseManager**

Update the init signature:

```swift
init(document: Document, modelContext: ModelContext, ttsService: TTSService, purchaseManager: PurchaseManager = .shared) {
    self.document = document
    self.currentParagraphIndex = document.currentPosition
    self.modelContext = modelContext
    self.ttsService = ttsService
    self.purchaseManager = purchaseManager
    // ... rest of init
}
```

**Step 3: Add play gating method**

Add this method to ReaderViewModel:

```swift
/// Attempt to start playback, showing upgrade prompt if trial expired
func attemptPlay() {
    if purchaseManager.entitlementState.canUseTTS {
        togglePlayPause()
    } else {
        showUpgradePrompt = true
    }
}
```

**Step 4: Commit**

```bash
git add Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift
git commit -m "feat: add TTS gating to ReaderViewModel"
```

---

## Task 9: Update ReaderView to Show Upgrade Prompt

**Files:**
- Modify: `Listen2/Listen2/Listen2/Views/ReaderView.swift`

**Step 1: Find the play button action and update it**

Find where the play button calls `viewModel.togglePlayPause()` and change it to `viewModel.attemptPlay()`.

**Step 2: Add sheet for upgrade prompt**

Add this modifier to the main view:

```swift
.sheet(isPresented: $viewModel.showUpgradePrompt) {
    UpgradePromptView()
}
```

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/ReaderView.swift
git commit -m "feat: show upgrade prompt when trial expired user tries to play"
```

---

## Task 10: Pass PurchaseManager Through View Hierarchy

**Files:**
- Modify: Views that create ReaderViewModel to pass PurchaseManager

**Step 1: Update LibraryView**

Add `@EnvironmentObject private var purchaseManager: PurchaseManager` and pass it when creating ReaderView/ReaderViewModel.

**Step 2: Update any NavigationLink destinations**

Ensure purchaseManager is passed through the view hierarchy.

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Views/LibraryView.swift
git commit -m "feat: pass PurchaseManager through view hierarchy"
```

---

## Task 11: Add In-App Purchase Capability

**Files:**
- Modify: Xcode project capabilities

**Step 1: Add capability in Xcode**

1. Select the Listen2 project in the navigator
2. Select the Listen2 target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Search for "In-App Purchase" and add it

**Step 2: Commit**

```bash
git add Listen2/Listen2/Listen2.xcodeproj/project.pbxproj
git commit -m "feat: add In-App Purchase capability"
```

---

## Task 12: Test the Implementation

**Test Scenarios:**

1. **Fresh install (no Keychain, no receipt):**
   - Launch app
   - Verify `.trial(7)` state
   - Verify TTS works
   - Check Settings shows "Trial: 7 days remaining"

2. **Trial expiration:**
   - Manually set Keychain date to 8 days ago (or use StoreKit testing)
   - Launch app
   - Verify `.expired` state
   - Tap play button → Verify upgrade prompt appears
   - Settings shows "Trial Expired"

3. **Purchase during trial:**
   - With active trial, tap "Upgrade" in Settings
   - Complete purchase in StoreKit sandbox
   - Verify immediate `.purchased` state
   - Verify Settings shows "Full Version Unlocked"

4. **Purchase after expiration:**
   - With expired trial, tap play
   - Complete purchase from upgrade prompt
   - Verify prompt dismisses
   - Verify TTS now works

5. **Restore purchases:**
   - Delete app (keep Keychain)
   - Reinstall
   - Go to Settings > Restore Purchase
   - Verify purchase restored

**Step 1: Run through all test scenarios**

```bash
# Build and run in Xcode with StoreKit Configuration enabled
# Test each scenario manually
```

**Step 2: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during testing"
```

---

## Summary

| Task | Component | Files |
|------|-----------|-------|
| 1 | EntitlementState | Create Models/EntitlementState.swift |
| 2 | TrialManager | Create Services/Purchase/TrialManager.swift |
| 3 | PurchaseManager | Create Services/Purchase/PurchaseManager.swift |
| 4 | StoreKit Config | Create Configuration/StoreKit Configuration.storekit |
| 5 | UpgradePromptView | Create Views/UpgradePromptView.swift |
| 6 | Settings UI | Modify Views/SettingsView.swift |
| 7 | App Integration | Modify Listen2App.swift |
| 8 | TTS Gating | Modify ViewModels/ReaderViewModel.swift |
| 9 | Reader UI | Modify Views/ReaderView.swift |
| 10 | View Hierarchy | Modify Views/LibraryView.swift |
| 11 | Capability | Add In-App Purchase to project |
| 12 | Testing | Verify all scenarios |
