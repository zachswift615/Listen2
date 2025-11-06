//
//  ViewModifiers.swift
//  Listen2
//
//  Reusable view modifiers for consistent styling
//

import SwiftUI

// MARK: - Card Style

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.md
    var padding: CGFloat = DesignSystem.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.secondaryBackground)
            .cornerRadius(cornerRadius)
            .shadow(
                color: DesignSystem.Shadow.small.color,
                radius: DesignSystem.Shadow.small.radius,
                x: DesignSystem.Shadow.small.x,
                y: DesignSystem.Shadow.small.y
            )
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = DesignSystem.CornerRadius.md, padding: CGFloat = DesignSystem.Spacing.md) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(isDestructive ? DesignSystem.Colors.error : DesignSystem.Colors.primary)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var destructive: PrimaryButtonStyle { PrimaryButtonStyle(isDestructive: true) }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadline)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.primary.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Icon Button Style

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = DesignSystem.IconSize.large

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size))
            .foregroundColor(DesignSystem.Colors.primary)
            .frame(width: size + DesignSystem.Spacing.md, height: size + DesignSystem.Spacing.md)
            .background(
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(DesignSystem.Animation.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    static func icon(size: CGFloat) -> IconButtonStyle { IconButtonStyle(size: size) }
}

// MARK: - Empty State Style

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text(message)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(.white)
                }
                .padding(DesignSystem.Spacing.xl)
                .background(.ultraThinMaterial)
                .cornerRadius(DesignSystem.CornerRadius.xl)
            }
        }
        .animation(DesignSystem.Animation.standard, value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}
