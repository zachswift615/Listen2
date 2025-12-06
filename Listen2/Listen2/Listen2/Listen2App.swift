//
//  Listen2App.swift
//  Listen2
//
//  Created by zach swift on 11/6/25.
//

import SwiftUI
import SwiftData
import AppIntents

@main
struct Listen2App: App {
    @StateObject private var ttsService = TTSService()
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var urlToImport: URL?
    @State private var siriReadClipboard: Bool = false

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
            Group {
                if ttsService.isInitializing || purchaseManager.entitlementState == .loading {
                    LoadingView()
                } else {
                    LibraryView(
                        modelContext: sharedModelContainer.mainContext,
                        urlToImport: $urlToImport,
                        siriReadClipboard: $siriReadClipboard
                    )
                    .environmentObject(ttsService)
                    .environmentObject(purchaseManager)
                    .onOpenURL { url in
                        // Handle incoming document URLs from "Open With"
                        urlToImport = url
                    }
                    .onAppear {
                        checkSiriTrigger()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        checkSiriTrigger()
                    }
                }
            }
            .task {
                await purchaseManager.initialize()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private func checkSiriTrigger() {
        if UserDefaults.standard.bool(forKey: "siriReadClipboard") {
            UserDefaults.standard.set(false, forKey: "siriReadClipboard")
            siriReadClipboard = true
        }
    }

    init() {
        // Register App Shortcuts with Siri
        Listen2Shortcuts.updateAppShortcutParameters()
    }
}
