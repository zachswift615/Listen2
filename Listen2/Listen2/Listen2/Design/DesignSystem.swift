//
//  DesignSystem.swift
//  Listen2
//
//  Design tokens and constants for consistent styling throughout the app
//

import SwiftUI

enum DesignSystem {

    // MARK: - Colors

    enum Colors {
        // Primary brand color - calm blue for reading focus
        static let primary = Color(red: 0.0, green: 0.48, blue: 0.80) // #007ACC
        static let primaryLight = Color(red: 0.20, green: 0.60, blue: 0.90)

        // Accent colors
        static let accent = Color(red: 0.40, green: 0.65, blue: 1.0) // Lighter blue
        static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let warning = Color(red: 1.0, green: 0.58, blue: 0.0)
        static let error = Color(red: 0.96, green: 0.26, blue: 0.21)

        // Reading highlights
        static let highlightWord = Color.yellow.opacity(0.5)
        static let highlightParagraph = Color.blue.opacity(0.08)
        static let highlightSentence = Color.blue.opacity(0.05)

        // Neutrals (adapt to light/dark mode)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(UIColor.tertiaryLabel)

        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)

        static let separator = Color(UIColor.separator)
    }

    // MARK: - Typography

    enum Typography {
        // Title sizes
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)

        // Body text (reading content)
        static let bodyLarge = Font.system(size: 18, weight: .regular)
        static let body = Font.body
        static let bodySmall = Font.system(size: 15, weight: .regular)

        // UI text
        static let headline = Font.headline
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let caption2 = Font.caption2

        // Specialized
        static let mono = Font.system(.body, design: .monospaced)
        static let monoSmall = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let round: CGFloat = 999 // Fully rounded
    }

    // MARK: - Shadows

    enum Shadow {
        static let small = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.15), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.20), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
    }

    // MARK: - Animation

    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let controlSlideIn = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.8)
        static let controlSlideOut = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.9)
    }

    // MARK: - Icon Sizes

    enum IconSize {
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
    }

    // MARK: - Control Bar

    enum ControlBar {
        static let topBarHeight: CGFloat = 44
        static let bottomBarHeight: CGFloat = 120
        static let largeTouchTarget: CGFloat = 44
        static let largeIconSize: CGFloat = 28
        static let playButtonSize: CGFloat = 48
        static let skipButtonSize: CGFloat = 24
    }
}
