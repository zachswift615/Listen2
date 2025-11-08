//
//  VoiceFilterManager.swift
//  Listen2
//

import Foundation
import SwiftUI

final class VoiceFilterManager: ObservableObject {

    @Published var selectedLanguages: Set<String> = []
    @Published var selectedGender: AVVoiceGender? = nil

    @AppStorage("lastUsedLanguageFilter") private var lastUsedLanguagesData: Data = Data()

    init() {
        loadPersistedFilters()
    }

    // MARK: - Filtering

    func filteredVoices(_ allVoices: [AVVoice]) -> [AVVoice] {
        var filtered = allVoices

        // Filter by language
        if !selectedLanguages.isEmpty {
            filtered = filtered.filter { voice in
                selectedLanguages.contains(voice.language)
            }
        }

        // Filter by gender
        if let gender = selectedGender {
            filtered = filtered.filter { $0.gender == gender }
        }

        return filtered.sorted { $0.name < $1.name }
    }

    // MARK: - Persistence

    func saveFilters() {
        if let encoded = try? JSONEncoder().encode(Array(selectedLanguages)) {
            lastUsedLanguagesData = encoded
        }
    }

    private func loadPersistedFilters() {
        if let decoded = try? JSONDecoder().decode([String].self, from: lastUsedLanguagesData) {
            selectedLanguages = Set(decoded)
        }
    }

    // MARK: - Convenience

    func clearFilters() {
        selectedLanguages.removeAll()
        selectedGender = nil
    }

    func setDefaultToSystemLanguage(_ allVoices: [AVVoice]) {
        if selectedLanguages.isEmpty {
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            let matchingLanguages = allVoices
                .filter { $0.language.hasPrefix(systemLanguage) }
                .map { $0.language }
            selectedLanguages = Set(matchingLanguages)
        }
    }
}
