//
//  ReaderView.swift
//  Listen2
//

import SwiftUI
import SwiftData
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
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
        GeometryReader { geometry in
            bodyContent(safeAreaTop: geometry.safeAreaInsets.top, safeAreaBottom: geometry.safeAreaInsets.bottom)
        }
    }

    @ViewBuilder
    private func bodyContent(safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> some View {
        ZStack {
                // Full-screen text (background layer)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            ForEach(Array(viewModel.document.extractedText.enumerated()), id: \.offset) { index, paragraph in
                                paragraphView(text: paragraph, index: index)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1) {
                        // Skip tap gesture when VoiceOver is running - controls stay visible
                        guard !UIAccessibility.isVoiceOverRunning else { return }
                        withAnimation(DesignSystem.Animation.controlSlideIn) {
                            coordinator.toggleControls()
                        }
                    }
                    .onChange(of: viewModel.currentParagraphIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                    .onAppear {
                        // Scroll to saved position on initial load
                        if viewModel.currentParagraphIndex > 0 {
                            // Delay scroll slightly to ensure view is laid out
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(viewModel.currentParagraphIndex, anchor: .center)
                            }
                        }
                    }
                }

                // Floating controls (overlay layer)
                VStack(spacing: 0) {
                    if coordinator.effectiveControlsVisible {
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
                            },
                            topSafeArea: safeAreaTop
                        )
                        .transition(.move(edge: .top))
                    }

                    Spacer()

                    if coordinator.effectiveControlsVisible {
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
                            },
                            bottomSafeArea: safeAreaBottom
                        )
                        .transition(.move(edge: .bottom))
                    }
                }
                .animation(DesignSystem.Animation.controlSlideIn, value: coordinator.effectiveControlsVisible)

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
            .onDisappear {
                viewModel.savePosition()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    viewModel.savePosition()
                }
            }
            // Accessibility announcements for state changes
            .onChange(of: viewModel.isPlaying) { _, isPlaying in
                let announcement = isPlaying ? "Playing" : "Paused"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
            .onChange(of: viewModel.currentParagraphIndex) { oldIndex, newIndex in
                // Only announce if VoiceOver is running and index actually changed
                guard UIAccessibility.isVoiceOverRunning, oldIndex != newIndex else { return }
                let total = viewModel.document.extractedText.count
                let announcement = "Paragraph \(newIndex + 1) of \(total)"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }

    }

    private func paragraphView(text: String, index: Int) -> some View {
        let isCurrentParagraph = index == viewModel.currentParagraphIndex
        let totalParagraphs = viewModel.document.extractedText.count

        return Text(attributedText(for: text, isCurrentParagraph: isCurrentParagraph))
            .font(DesignSystem.Typography.bodyLarge)
            .padding(DesignSystem.Spacing.sm)
            .background(
                isCurrentParagraph ? DesignSystem.Colors.highlightParagraph : Color.clear
            )
            .cornerRadius(DesignSystem.CornerRadius.md)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // Double-tap: jump to this paragraph and start playback
                coordinator.navigateToParagraph(index, viewModel: viewModel)
            }
            .accessibilityLabel("Paragraph \(index + 1) of \(totalParagraphs)")
            .accessibilityValue(text)
            .accessibilityHint(isCurrentParagraph ? "Currently playing. Double tap to restart from here" : "Double tap to start reading from here")
            .accessibilityAddTraits(isCurrentParagraph ? [.isSelected] : [])
    }

    private func attributedText(for text: String, isCurrentParagraph: Bool) -> AttributedString {
        var attributedString = AttributedString(text)

        // Only apply highlighting if this is the currently playing paragraph
        guard isCurrentParagraph else {
            return attributedString
        }

        let highlightLevel = viewModel.effectiveHighlightLevel

        switch highlightLevel {
        case .word:
            // Word-level highlighting
            guard let wordRange = viewModel.currentWordRange else {
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

        case .sentence:
            // Sentence-level highlighting
            guard let location = viewModel.currentSentenceLocation,
                  let length = viewModel.currentSentenceLength else {
                return attributedString
            }

            let startOffset = location
            let endOffset = location + length

            // Validate offsets are within bounds
            guard startOffset >= 0 && endOffset <= text.count && startOffset < endOffset else {
                return attributedString
            }

            let attrStartIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
            let attrEndIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)

            if attrStartIndex < attributedString.endIndex && attrEndIndex <= attributedString.endIndex {
                attributedString[attrStartIndex..<attrEndIndex].backgroundColor = DesignSystem.Colors.highlightSentence
            }

        case .paragraph:
            // Paragraph-level highlighting is handled by the background of paragraphView
            // No text-level highlighting needed here
            break

        case .off:
            // No highlighting
            break
        }

        return attributedString
    }

    private var voicePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.ttsService.availableVoices()) { voice in
                    let isSelected = voice.id == viewModel.selectedVoice?.id
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

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignSystem.Colors.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(voice.name), \(voice.displayName)")
                    .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
