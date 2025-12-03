//
//  DocumentRowView.swift
//  Listen2
//

import SwiftUI

struct DocumentRowView: View {
    let document: Document

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Cover thumbnail or icon
            Group {
                if let coverData = document.coverImageData,
                   let uiImage = UIImage(data: coverData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 2)
                } else {
                    // Fallback icon
                    Image(systemName: document.sourceType.iconName)
                        .font(.system(size: DesignSystem.IconSize.large))
                        .foregroundStyle(DesignSystem.Colors.primary)
                        .frame(width: 50, height: 70)
                }
            }

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
            Text(friendlyTimeAgo(document.lastRead))
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to open and read")
    }

    private var accessibilityDescription: String {
        var parts: [String] = [document.title, document.sourceType.rawValue]
        if document.progressPercentage > 0 {
            parts.append("\(document.progressPercentage) percent complete")
        }
        parts.append("Last read \(friendlyTimeAgo(document.lastRead))")
        return parts.joined(separator: ", ")
    }

    private func friendlyTimeAgo(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return days == 1 ? "Yesterday" : "\(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
