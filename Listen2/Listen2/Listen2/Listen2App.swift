//
//  Listen2App.swift
//  Listen2
//
//  Created by zach swift on 11/6/25.
//

import SwiftUI
import SwiftData

@main
struct Listen2App: App {
    @StateObject private var ttsService = TTSService()
    @State private var urlToImport: URL?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Document.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if ttsService.isInitializing {
                LoadingView()
            } else {
                LibraryView(modelContext: sharedModelContainer.mainContext, urlToImport: $urlToImport)
                    .environmentObject(ttsService)
                    .onOpenURL { url in
                        // Handle incoming document URLs from "Open With"
                        urlToImport = url
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
