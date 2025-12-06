# Listen2 Monetization Design

**Date:** 2024-12-06
**Status:** Approved

## Summary

Implement a 7-day free trial with $24.99 one-time purchase for Listen2. After trial expiration, TTS playback and voice selection are disabled; document reading remains free.

## Business Model

| Aspect | Decision |
|--------|----------|
| Distribution | App Store only |
| Price | $24.99 one-time purchase |
| Trial duration | 7 calendar days |
| Major versions | Separate App Store listings (Listen2 v1, Listen2 v2, etc.) |
| Feature lockout | TTS playback + voice selection disabled after trial |
| Free forever | Document import, reading, bookmarks, highlights, notes |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    App Launch                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   1. EntitlementState = .loading                            │
│                    │                                         │
│                    ▼                                         │
│   2. PurchaseManager.checkPurchase()                        │
│                    │                                         │
│          ┌────────┴────────┐                                │
│          ▼                 ▼                                │
│     purchased          not purchased                        │
│          │                 │                                │
│          ▼                 ▼                                │
│   .purchased      3. TrialManager.getStatus()               │
│                            │                                │
│                   ┌────────┴────────┐                       │
│                   ▼                 ▼                       │
│            .trial(n)           .expired                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Responsibility |
|-----------|----------------|
| `PurchaseManager` | StoreKit 2 transactions, purchase state, restore purchases |
| `TrialManager` | Track trial start (Keychain + Receipt), calculate days remaining |
| `EntitlementState` | Single source of truth enum |

### EntitlementState Enum

```swift
enum EntitlementState: Equatable {
    case loading                    // Checking purchase/trial status
    case trial(daysRemaining: Int)  // 1-7 days left
    case expired                    // Trial over, must purchase
    case purchased                  // Full access
}
```

## Trial Tracking: Dual-Source "Earliest Wins"

Trial start date is determined from **two sources**, using the **earliest (oldest) date**:

1. **Keychain** — Persists across reinstalls on same device/Apple ID
2. **App Receipt** — `AppTransaction.shared.originalPurchaseDate` from StoreKit 2

### Why Earliest Wins

Prevents gaming:
- Reinstall to reset Keychain? Receipt still has original date.
- New device? Receipt syncs via Apple ID.
- Receipt fails? Keychain has the date.

### Fallback Logic

```swift
func getTrialStartDate() async -> Date {
    let receiptDate = await getReceiptDate()  // May be nil if fetch fails
    let keychainDate = getKeychainDate()      // May be nil on fresh install

    switch (receiptDate, keychainDate) {
    case let (r?, k?):
        return min(r, k)  // Earliest wins
    case let (r?, nil):
        saveToKeychain(r)
        return r
    case let (nil, k?):
        return k
    case (nil, nil):
        let now = Date()
        saveToKeychain(now)
        return now  // True fresh install
    }
}
```

### Day Calculation

- **Calendar days**, not 24-hour periods
- Install at 11pm → Day 1 ends at midnight → Full 7 calendar days
- `daysRemaining <= 0` → `.expired` (no "0 days left")

```swift
func daysRemaining(from startDate: Date) -> Int {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: startDate)
    let today = calendar.startOfDay(for: Date())
    let daysPassed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    return max(0, 7 - daysPassed)
}
```

## StoreKit 2 Integration

### Product Configuration

| Field | Value |
|-------|-------|
| Product ID | `com.listen2.fullaccess` |
| Type | Non-consumable |
| Price | $24.99 |

### Purchase Flow

```swift
// In PurchaseManager
func purchase() async throws {
    guard let product = products.first else { return }
    let result = try await product.purchase()

    switch result {
    case .success(let verification):
        let transaction = try checkVerified(verification)
        await transaction.finish()
        state = .purchased
    case .userCancelled:
        break
    case .pending:
        // Handle pending (e.g., parental approval)
        break
    @unknown default:
        break
    }
}
```

### Restore Purchases

Required by App Store guidelines:

```swift
func restorePurchases() async {
    for await result in Transaction.currentEntitlements {
        if case .verified(let transaction) = result {
            if transaction.productID == "com.listen2.fullaccess" {
                state = .purchased
            }
        }
    }
}
```

## UI Design

### Settings Page — Upgrade Section

**During Trial:**
```
┌────────────────────────────────────────────────────────────┐
│  Listen2 Pro                                               │
│                                                            │
│  Trial: 5 days remaining                                   │
│                                                            │
│  [  Upgrade — $24.99  ]                                    │
│                                                            │
│  Restore Purchase                                          │
└────────────────────────────────────────────────────────────┘
```

**After Expiration:**
```
┌────────────────────────────────────────────────────────────┐
│  Listen2 Pro                                               │
│                                                            │
│  Trial Expired                                             │
│                                                            │
│  [  Unlock Listen2 — $24.99  ]                             │
│                                                            │
│  Restore Purchase                                          │
└────────────────────────────────────────────────────────────┘
```

**After Purchase:**
```
┌────────────────────────────────────────────────────────────┐
│  Listen2 Pro                                               │
│                                                            │
│  ✓ Full Version Unlocked                                   │
└────────────────────────────────────────────────────────────┘
```

### Expired Nag (When Tapping Play)

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│     Your free trial has ended                               │
│                                                              │
│     Unlock TTS playback and all voices                      │
│     with a one-time purchase.                               │
│                                                              │
│     [  Unlock Listen2 — $24.99  ]                           │
│                                                              │
│     [  Restore Purchase  ]                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Feature Gating

### What's Locked After Trial

- TTS playback (play button disabled or shows purchase prompt)
- Voice selection in settings

### What Remains Free

- Document import (EPUB, PDF, TXT, MD)
- Document reading/viewing
- Bookmarks, highlights, notes
- Reading position tracking

### Implementation in TTSService

```swift
func play() {
    guard entitlementState == .purchased ||
          entitlementState.isTrialActive else {
        showPurchasePrompt()
        return
    }
    // Normal playback...
}
```

## App Store Configuration

### Required in App Store Connect

1. Create In-App Purchase product:
   - Reference Name: "Listen2 Full Access"
   - Product ID: `com.listen2.fullaccess`
   - Type: Non-consumable
   - Price: $24.99

2. Add to app's In-App Purchases section

3. Submit for review with app update

### Capabilities Required

In Xcode project:
- Add "In-App Purchase" capability

## Testing

### StoreKit Testing in Xcode

1. Create `StoreKit Configuration File` in project
2. Add product with matching Product ID
3. Use `StoreKitTest` environment for unit tests

### Test Scenarios

- [ ] Fresh install → Trial starts, 7 days shown
- [ ] Day 7 → Trial shows "1 day remaining"
- [ ] Day 8 → Trial expired, TTS disabled
- [ ] Purchase during trial → Immediate full access
- [ ] Purchase after expiration → Full access restored
- [ ] Reinstall → Trial date preserved (Keychain)
- [ ] New device → Trial date from receipt
- [ ] Restore purchase → Restores full access
- [ ] Offline launch → Works with cached state
