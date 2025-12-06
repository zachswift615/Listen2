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
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
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
