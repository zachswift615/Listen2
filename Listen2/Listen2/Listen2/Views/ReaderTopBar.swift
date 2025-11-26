//
//  ReaderTopBar.swift
//  Listen2
//
//  Top navigation bar for the reader view with back, TOC, and settings buttons
//

import SwiftUI

struct ReaderTopBar: View {
    let documentTitle: String
    let onBack: () -> Void
    let onTOC: () -> Void
    let onSettings: () -> Void
    let topSafeArea: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Library")
                            .font(DesignSystem.Typography.body)
                    }
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(height: DesignSystem.ControlBar.largeTouchTarget)
                }

                Spacer()

                // Document title (center)
                Text(documentTitle)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 200)

                Spacer()

                // TOC button
                Button(action: onTOC) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: DesignSystem.ControlBar.largeIconSize))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(
                            width: DesignSystem.ControlBar.largeTouchTarget,
                            height: DesignSystem.ControlBar.largeTouchTarget
                        )
                }

                // Settings button
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: DesignSystem.ControlBar.largeIconSize))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(
                            width: DesignSystem.ControlBar.largeTouchTarget,
                            height: DesignSystem.ControlBar.largeTouchTarget
                        )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, topSafeArea + DesignSystem.Spacing.xs)
            .padding(.bottom, DesignSystem.Spacing.sm)
        }
        .background(Color(UIColor.systemBackground))
        .shadow(
            color: DesignSystem.Shadow.small.color,
            radius: DesignSystem.Shadow.small.radius,
            x: DesignSystem.Shadow.small.x,
            y: DesignSystem.Shadow.small.y
        )
    }
}
