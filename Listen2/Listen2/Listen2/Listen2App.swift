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
            LibraryView(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}
