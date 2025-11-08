//
//  QuickSettingsSheet.swift
//  Listen2
//

import SwiftUI
import SwiftData

struct QuickSettingsSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    var coordinator: ReaderCoordinator? = nil
    @StateObject private var voiceFilterManager = VoiceFilterManager()
    @AppStorage("paragraphPauseDelay") private var pauseDuration: Double = 0.3
    @Environment(\.dismiss) private var dismiss

    @State private var showingVoicePicker = false

    var body: some View {
        NavigationView {
            Form {
                speedSection
                voiceSection
                pauseSection
            }
            .navigationTitle("Quick Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerSheet(
                viewModel: viewModel,
                filterManager: voiceFilterManager,
                coordinator: coordinator
            )
        }
    }

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.playbackRate))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.playbackRate) },
                        set: { viewModel.setPlaybackRate(Float($0)) }
                    ),
                    in: 0.5...2.5,
                    step: 0.1
                )
            }
        } header: {
            Text("Playback")
        }
    }

    private var voiceSection: some View {
        Section {
            Button(action: {
                showingVoicePicker = true
            }) {
                HStack {
                    Text("Voice")
                        .foregroundColor(.primary)

                    Spacer()

                    Text(viewModel.selectedVoice?.name ?? "Default")
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Voice")
        }
    }

    private var pauseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Paragraph Pause")
                    Spacer()
                    Text(String(format: "%.1fs", pauseDuration))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $pauseDuration,
                    in: 0.0...1.0,
                    step: 0.1
                )
            }
        } header: {
            Text("Timing")
        } footer: {
            Text("Pause duration between paragraphs")
        }
    }
}

struct VoicePickerSheet: View {

    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var filterManager: VoiceFilterManager
    let coordinator: ReaderCoordinator?
    @Environment(\.dismiss) private var dismiss

    @State private var allVoices: [AVVoice] = []

    var filteredVoices: [AVVoice] {
        filterManager.filteredVoices(allVoices)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar

                List(filteredVoices) { voice in
                    Button(action: {
                        if let coordinator = coordinator {
                            coordinator.changeVoice(voice, viewModel: viewModel)
                        } else {
                            viewModel.setVoice(voice)
                        }
                        filterManager.saveFilters()
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                    .font(.body)

                                HStack {
                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .foregroundColor(.secondary)

                                    Text(voice.gender.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if viewModel.selectedVoice?.id == voice.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            allVoices = viewModel.ttsService.availableVoices()
            filterManager.setDefaultToSystemLanguage(allVoices)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                // Gender filter
                Menu {
                    Button("All") {
                        filterManager.selectedGender = nil
                    }
                    Button("Male") {
                        filterManager.selectedGender = .male
                    }
                    Button("Female") {
                        filterManager.selectedGender = .female
                    }
                    Button("Neutral") {
                        filterManager.selectedGender = .neutral
                    }
                } label: {
                    Label(
                        filterManager.selectedGender?.rawValue.capitalized ?? "All Genders",
                        systemImage: "person.fill"
                    )
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(16)
                }

                // Clear filters
                if !filterManager.selectedLanguages.isEmpty || filterManager.selectedGender != nil {
                    Button(action: {
                        filterManager.clearFilters()
                    }) {
                        Text("Clear")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(16)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    QuickSettingsSheet(
        viewModel: ReaderViewModel(
            document: Document(title: "Test", sourceType: .pdf, extractedText: []),
            modelContext: ModelContext(try! ModelContainer(for: Document.self))
        )
    )
}
