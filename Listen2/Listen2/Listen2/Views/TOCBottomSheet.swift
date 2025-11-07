//
//  TOCBottomSheet.swift
//  Listen2
//

import SwiftUI

struct TOCBottomSheet: View {

    let entries: [TOCEntry]
    let currentParagraphIndex: Int
    let onSelectEntry: (TOCEntry) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filteredEntries: [TOCEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                if entries.count > 5 {
                    searchBar
                }

                // TOC list
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    tocList
                }
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search chapters...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private var tocList: some View {
        List(filteredEntries) { entry in
            Button(action: {
                onSelectEntry(entry)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(fontForLevel(entry.level))
                            .foregroundColor(.primary)

                        Text("Paragraph \(entry.paragraphIndex + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isCurrentEntry(entry) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.leading, CGFloat(entry.level * 20))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Results")
                .font(.headline)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 0: return .headline
        case 1: return .subheadline
        default: return .caption
        }
    }

    private func isCurrentEntry(_ entry: TOCEntry) -> Bool {
        // Check if we're currently at or past this entry but before the next
        guard entry.paragraphIndex <= currentParagraphIndex else {
            return false
        }

        if let nextEntry = entries.first(where: { $0.paragraphIndex > entry.paragraphIndex }) {
            return currentParagraphIndex < nextEntry.paragraphIndex
        }

        return true
    }
}

#Preview {
    TOCBottomSheet(
        entries: [
            TOCEntry(title: "Chapter 1: Introduction", paragraphIndex: 0, level: 0),
            TOCEntry(title: "Section 1.1", paragraphIndex: 5, level: 1),
            TOCEntry(title: "Section 1.2", paragraphIndex: 10, level: 1),
            TOCEntry(title: "Chapter 2: Background", paragraphIndex: 15, level: 0),
        ],
        currentParagraphIndex: 7,
        onSelectEntry: { _ in }
    )
}
