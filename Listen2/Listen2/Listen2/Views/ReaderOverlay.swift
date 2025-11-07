//
//  ReaderOverlay.swift
//  Listen2
//

import SwiftUI

struct ReaderOverlay: View {

    let documentTitle: String
    let onBack: () -> Void
    let onShowTOC: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        VStack {
            topBar
            Spacer()
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Library")
                }
            }

            Spacer()

            // Document title
            Text(documentTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // TOC button
            Button(action: onShowTOC) {
                Image(systemName: "list.bullet")
            }

            // Settings button
            Button(action: onShowSettings) {
                Image(systemName: "gearshape.fill")
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundColor(.white)
    }
}

#Preview {
    ZStack {
        Color.gray

        ReaderOverlay(
            documentTitle: "Sample Document.pdf",
            onBack: {},
            onShowTOC: {},
            onShowSettings: {}
        )
    }
}
