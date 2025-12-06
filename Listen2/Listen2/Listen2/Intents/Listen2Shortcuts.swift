//
//  Listen2Shortcuts.swift
//  Listen2
//
//  App Shortcuts provider for Siri integration
//

import AppIntents

struct Listen2Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadClipboardIntent(),
            phrases: [
                "Read my clipboard in \(.applicationName)",
                "Read my clipboard with \(.applicationName)",
                "Read clipboard in \(.applicationName)",
                "Read clipboard with \(.applicationName)",
                "Read what's on my clipboard in \(.applicationName)",
                "\(.applicationName) read my clipboard",
                "\(.applicationName) read clipboard"
            ],
            shortTitle: "Read Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
