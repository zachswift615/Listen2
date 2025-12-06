//
//  SettingsView.swift
//  Listen2
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingVoicePicker = false
    @State private var showingVoiceLibrary = false
    @AppStorage("useIOSVoice") private var useIOSVoice = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Upgrade Section
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Image(systemName: purchaseManager.entitlementState == .purchased ? "checkmark.seal.fill" : "waveform")
                                .font(.system(size: DesignSystem.IconSize.large))
                                .foregroundStyle(DesignSystem.Colors.primary)

                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                                Text("Listen2 Pro")
                                    .font(DesignSystem.Typography.headline)

                                Text(purchaseManager.entitlementState.displayText)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(purchaseManager.entitlementState == .expired ? .orange : DesignSystem.Colors.textSecondary)
                            }
                        }

                        if purchaseManager.entitlementState != .purchased {
                            // Purchase button
                            Button {
                                Task {
                                    try? await purchaseManager.purchase()
                                }
                            } label: {
                                HStack {
                                    if purchaseManager.isPurchasing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(purchaseManager.entitlementState == .expired ? "Unlock Listen2" : "Upgrade")
                                        Spacer()
                                        Text(purchaseManager.product?.displayPrice ?? "$24.99")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.Spacing.sm)
                                .padding(.horizontal, DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.primary)
                                .foregroundStyle(.white)
                                .font(DesignSystem.Typography.body.weight(.medium))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                            .disabled(purchaseManager.isPurchasing)

                            // Restore purchases
                            Button("Restore Purchase") {
                                Task {
                                    await purchaseManager.restorePurchases()
                                }
                            }
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.primary)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                } header: {
                    Text("Subscription")
                }

                // MARK: - Playback Settings
                Section {
                    // Playback Speed
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Text("Default Playback Speed")
                                .font(DesignSystem.Typography.body)
                            Spacer()
                            Text(String(format: "%.1fx", viewModel.defaultSpeed))
                                .font(DesignSystem.Typography.mono)
                                .foregroundStyle(DesignSystem.Colors.primary)
                        }
                        .accessibilityHidden(true)

                        Slider(
                            value: $viewModel.defaultSpeed,
                            in: 0.5...2.5,
                            step: 0.1
                        )
                        .tint(DesignSystem.Colors.primary)
                        .accessibilityLabel("Default playback speed")
                        .accessibilityValue(String(format: "%.1f times", viewModel.defaultSpeed))
                        .accessibilityHint("Range 0.5 to 2.5 times normal speed")

                        Text("Speed range: 0.5x - 2.5x")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    // Paragraph Pause
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Text("Pause Between Paragraphs")
                                .font(DesignSystem.Typography.body)
                            Spacer()
                            Text(String(format: "%.1fs", viewModel.paragraphPauseDelay))
                                .font(DesignSystem.Typography.mono)
                                .foregroundStyle(DesignSystem.Colors.primary)
                        }
                        .accessibilityHidden(true)

                        Slider(
                            value: $viewModel.paragraphPauseDelay,
                            in: 0.0...1.0,
                            step: 0.1
                        )
                        .tint(DesignSystem.Colors.primary)
                        .accessibilityLabel("Pause between paragraphs")
                        .accessibilityValue(String(format: "%.1f seconds", viewModel.paragraphPauseDelay))
                        .accessibilityHint("Range 0 to 1 second")

                        Text("Pause duration: 0.0s - 1.0s")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    // Highlight Level Picker
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Text("Text Highlighting")
                                .font(DesignSystem.Typography.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { viewModel.highlightLevel },
                                set: { viewModel.highlightLevel = $0 }
                            )) {
                                ForEach(HighlightLevel.allCases) { level in
                                    Text(level.displayName)
                                        .tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(DesignSystem.Colors.primary)
                        }

                        Text(viewModel.highlightLevel.description)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        // Show warning on restricted devices
                        if viewModel.isWordLevelRestricted && viewModel.highlightLevel == .word {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text("Word-level highlighting may cause performance issues on this device. Consider using Sentence or Paragraph level instead.")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.top, DesignSystem.Spacing.xxs)
                            .accessibilityLabel("Warning: Word-level highlighting may cause performance issues on this device")
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                } header: {
                    Text("Playback")
                }

                // MARK: - Voice Settings
                Section {
                    Button {
                        showingVoicePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                                Text("Default Voice")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                if let voice = viewModel.selectedVoice {
                                    Text(voice.displayName)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Default Voice")
                    .accessibilityValue(viewModel.selectedVoice?.displayName ?? "Not selected")
                    .accessibilityHint("Double tap to change default voice")

                    Button {
                        showingVoiceLibrary = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                                Text("Voice Library")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Download and manage voices")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voice Library")
                    .accessibilityHint("Download and manage additional voices")
                } header: {
                    Text("Voice")
                }

                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                            .font(DesignSystem.Typography.body)
                        Spacer()
                        Text(appVersion)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "book.fill")
                            .font(.system(size: DesignSystem.IconSize.medium))
                            .foregroundStyle(DesignSystem.Colors.primary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                            Text("Listen2")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            Text("Voice reader for PDFs and text")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingVoicePicker) {
                voicePickerView
            }
            .sheet(isPresented: $showingVoiceLibrary) {
                VoiceLibraryView()
            }
        }
    }

    // MARK: - Voice Picker Sheet
    private var voicePickerView: some View {
        NavigationStack {
            Form {
                Section {
                    // Piper voices
                    ForEach(viewModel.piperVoices) { voice in
                        let isSelected = voice.id == viewModel.selectedVoice?.id
                        Button {
                            viewModel.selectedVoice = voice
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
                                        .font(.system(size: DesignSystem.IconSize.medium, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(voice.name), \(voice.displayName)")
                        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    if useIOSVoice {
                        Text("Using iOS voice as fallback. Piper voices offer better quality.")
                    } else {
                        Text("Neural TTS voices powered by Piper")
                    }
                }

                Section {
                    // Toggle to show iOS voices (fallback)
                    Toggle("Use iOS Voice (Fallback)", isOn: $useIOSVoice)

                    // iOS voice picker (only shown when toggle enabled)
                    if useIOSVoice {
                        ForEach(viewModel.iosVoices) { voice in
                            let isSelected = voice.id == viewModel.selectedVoice?.id
                            Button {
                                viewModel.selectedVoice = voice
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
                                            .font(.system(size: DesignSystem.IconSize.medium, weight: .semibold))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(voice.name), \(voice.displayName)")
                            .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                } header: {
                    Text("Fallback Options")
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

    // MARK: - Computed Properties
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
