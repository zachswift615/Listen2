//
//  ReaderView.swift
//  Listen2
//

import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var coordinator = ReaderCoordinator()
    @State private var showingVoicePicker = false

    init(document: Document, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(document: document, modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            ForEach(Array(viewModel.document.extractedText.enumerated()), id: \.offset) { index, paragraph in
                                paragraphView(text: paragraph, index: index)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            coordinator.toggleOverlay()
                        }
                    }
                    .onChange(of: viewModel.currentParagraphIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                Divider()

                // Controls
                playbackControls
                    .padding()
                    .background(.regularMaterial)
            }
            .navigationTitle(viewModel.document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.cleanup()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingVoicePicker) {
                voicePickerSheet
            }
            .overlay {
                if coordinator.isOverlayVisible {
                    ReaderOverlay(
                        documentTitle: viewModel.document.title,
                        onBack: {
                            coordinator.dismissOverlay()
                            dismiss()
                        },
                        onShowTOC: {
                            coordinator.showTOC()
                        },
                        onShowSettings: {
                            coordinator.showQuickSettings()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $coordinator.isShowingTOC) {
                TOCBottomSheet(
                    entries: viewModel.tocEntries,
                    currentParagraphIndex: viewModel.currentParagraphIndex,
                    onSelectEntry: { entry in
                        coordinator.navigateToTOCEntry(entry, viewModel: viewModel)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $coordinator.isShowingQuickSettings) {
                QuickSettingsSheet(viewModel: viewModel)
                    .presentationDetents([.medium])
            }
            .onAppear {
                viewModel.loadTOC()
            }
        }
    }

    private func paragraphView(text: String, index: Int) -> some View {
        let isCurrentParagraph = index == viewModel.currentParagraphIndex

        return Text(attributedText(for: text, isCurrentParagraph: isCurrentParagraph))
            .font(DesignSystem.Typography.bodyLarge)
            .padding(DesignSystem.Spacing.sm)
            .background(
                isCurrentParagraph ? DesignSystem.Colors.highlightParagraph : Color.clear
            )
            .cornerRadius(DesignSystem.CornerRadius.md)
            .onTapGesture {
                viewModel.ttsService.stop()
                viewModel.ttsService.startReading(
                    paragraphs: viewModel.document.extractedText,
                    from: index,
                    title: viewModel.document.title
                )
            }
    }

    private func attributedText(for text: String, isCurrentParagraph: Bool) -> AttributedString {
        var attributedString = AttributedString(text)

        // Only apply word highlighting if this is the currently playing paragraph
        // This reduces unnecessary computations for inactive paragraphs
        guard isCurrentParagraph, let wordRange = viewModel.currentWordRange else {
            return attributedString
        }

        // Validate that the word range is within the text bounds
        guard wordRange.lowerBound >= text.startIndex &&
              wordRange.upperBound <= text.endIndex else {
            return attributedString
        }

        // Convert String.Index range to AttributedString range
        let startOffset = text.distance(from: text.startIndex, to: wordRange.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: wordRange.upperBound)

        // Validate offsets are within bounds
        guard startOffset >= 0 && endOffset <= text.count && startOffset < endOffset else {
            return attributedString
        }

        let attrStartIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
        let attrEndIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)

        if attrStartIndex < attributedString.endIndex && attrEndIndex <= attributedString.endIndex {
            attributedString[attrStartIndex..<attrEndIndex].backgroundColor = DesignSystem.Colors.highlightWord
            attributedString[attrStartIndex..<attrEndIndex].font = Font.body.weight(.semibold)
        }

        return attributedString
    }

    private var playbackControls: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Speed and Voice
            HStack {
                // Speed
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text("Speed:")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(String(format: "%.1fx", viewModel.playbackRate))
                        .font(DesignSystem.Typography.caption)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { viewModel.playbackRate },
                    set: { viewModel.setPlaybackRate($0) }
                ), in: 0.5...2.5, step: 0.1)
                .frame(maxWidth: 150)

                Spacer()

                // Voice picker button
                Button {
                    showingVoicePicker = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "waveform")
                        Text(viewModel.selectedVoice?.name ?? "Voice")
                            .lineLimit(1)
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(.bordered)
            }

            // Playback buttons
            HStack(spacing: DesignSystem.Spacing.xl) {
                // Skip back
                Button {
                    viewModel.skipBackward()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(DesignSystem.Typography.title)
                }
                .foregroundColor(DesignSystem.Colors.primary)

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .foregroundColor(DesignSystem.Colors.primary)

                // Skip forward
                Button {
                    viewModel.skipForward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(DesignSystem.Typography.title)
                }
                .foregroundColor(DesignSystem.Colors.primary)
            }
        }
    }

    private var voicePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.ttsService.availableVoices()) { voice in
                    Button {
                        viewModel.setVoice(voice)
                        showingVoicePicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                                Text(voice.name)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(voice.displayName)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }

                            Spacer()

                            if voice.id == viewModel.selectedVoice?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignSystem.Colors.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingVoicePicker = false
                    }
                }
            }
        }
    }
}
