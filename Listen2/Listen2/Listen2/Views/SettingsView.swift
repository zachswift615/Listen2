//
//  SettingsView.swift
//  Listen2
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingVoicePicker = false

    var body: some View {
        NavigationStack {
            Form {
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

                        Slider(
                            value: $viewModel.defaultSpeed,
                            in: 0.5...2.5,
                            step: 0.1
                        )
                        .tint(DesignSystem.Colors.primary)

                        Text("Speed range: 0.5x - 2.5x")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    Divider()

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

                        Slider(
                            value: $viewModel.paragraphPauseDelay,
                            in: 0.0...1.0,
                            step: 0.1
                        )
                        .tint(DesignSystem.Colors.primary)

                        Text("Pause duration: 0.0s - 1.0s")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
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
        }
    }

    // MARK: - Voice Picker Sheet
    private var voicePickerView: some View {
        NavigationStack {
            List {
                ForEach(viewModel.availableVoices) { voice in
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

                            if voice.id == viewModel.selectedVoice?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignSystem.Colors.primary)
                                    .font(.system(size: DesignSystem.IconSize.medium, weight: .semibold))
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

    // MARK: - Computed Properties
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
