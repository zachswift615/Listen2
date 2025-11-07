//
//  DocumentRowView.swift
//  Listen2
//

import SwiftUI

struct DocumentRowView: View {
    let document: Document

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Icon
            Image(systemName: document.sourceType.iconName)
                .font(.system(size: DesignSystem.IconSize.large))
                .foregroundStyle(DesignSystem.Colors.primary)
                .frame(width: 40)

            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(document.title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(document.sourceType.rawValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if document.progressPercentage > 0 {
                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("Resume at \(document.progressPercentage)%")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }

            Spacer()

            // Metadata
            Text(document.lastRead, style: .relative)
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}
