//
//  ReaderView.swift
//  Listen2
//

import SwiftUI
import SwiftData

struct ReaderView: View {
    @EnvironmentObject var ttsService: TTSService
    let document: Document
    let modelContext: ModelContext

    var body: some View {
        ReaderViewContent(document: document, modelContext: modelContext, ttsService: ttsService)
    }
}

private struct ReaderViewContent: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var coordinator = ReaderCoordinator()
    @State private var showingVoicePicker = false

    init(document: Document, modelContext: ModelContext, ttsService: TTSService) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            document: document,
            modelContext: modelContext,
            ttsService: ttsService
        ))
    }

    var body: some View { 
        ZStack {
                // Full-screen text (background layer)
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
                        withAnimation(DesignSystem.Animation.controlSlideIn) {
                            coordinator.toggleControls()
                        }
                    }
                    .onChange(of: viewModel.currentParagraphIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Floating controls (overlay layer)
                VStack(spacing: 0) {
                    if coordinator.areControlsVisible {
                        ReaderTopBar(
                            documentTitle: viewModel.document.title,
                            onBack: {
                                viewModel.cleanup()
                                dismiss()
                            },
                            onTOC: {
                                coordinator.isShowingTOC = true
                                coordinator.keepControlsVisible()
                            },
                            onSettings: {
                                coordinator.isShowingQuickSettings = true
                                coordinator.keepControlsVisible()
                            }
                        )
                        .transition(.move(edge: .top))
                    }

                    Spacer()

                    if coordinator.areControlsVisible {
                        ReaderBottomBar(
                            playbackSpeed: Binding(
                                get: { Double(viewModel.playbackRate) },
                                set: { _ in }  // Set handled in onSpeedChange
                            ),
                            currentVoice: viewModel.selectedVoice?.name ?? "Voice",
                            isPlaying: viewModel.isPlaying,
                            onSpeedChange: { speed in
                                viewModel.setPlaybackRate(Float(speed))
                                coordinator.keepControlsVisible()
                            },
                            onVoicePicker: {
                                showingVoicePicker = true
                                coordinator.keepControlsVisible()
                            },
                            onSkipBack: {
                                viewModel.skipBackward()
                                coordinator.keepControlsVisible()
                            },
                            onPlayPause: {
                                viewModel.togglePlayPause()
                                coordinator.keepControlsVisible()
                            },
                            onSkipForward: {
                                viewModel.skipForward()
                                coordinator.keepControlsVisible()
                            }
                        )
                        .transition(.move(edge: .bottom))
                    }
                }
                .animation(DesignSystem.Animation.controlSlideIn, value: coordinator.areControlsVisible)

                // Loading overlay
                if viewModel.isLoading {
                    Color.clear
                        .loadingOverlay(isLoading: true, message: "Opening book...")
                }

                // Preparing audio overlay
                if viewModel.ttsService.isPreparing {
                    Color.clear
                        .loadingOverlay(isLoading: true, message: "Preparing audio...")
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .sheet(isPresented: $showingVoicePicker) {
                voicePickerSheet
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
                QuickSettingsSheet(viewModel: viewModel, coordinator: coordinator)
                    .presentationDetents([.medium])
            }
            .onAppear {
                viewModel.loadTOC()
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
            // Removed tap gesture - overlay tap gesture now works
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
            attributedString[attrStartIndex..<attrEndIndex].font = DesignSystem.Typography.bodyLarge
        }

        return attributedString
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
