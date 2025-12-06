//
//  ReadClipboardIntent.swift
//  Listen2
//
//  Siri shortcut to read clipboard content aloud
//

import AppIntents
import UIKit

struct ReadClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Clipboard"
    static var description = IntentDescription("Read text from your clipboard aloud using Listen2")

    // Open the app when this intent runs
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        // Check if clipboard has text
        let hasText = await MainActor.run {
            UIPasteboard.general.hasStrings
        }

        guard hasText else {
            return .result(
                dialog: "Your clipboard is empty. Copy some text first."
            )
        }

        // Set flag for app to pick up on launch
        UserDefaults.standard.set(true, forKey: "siriReadClipboard")

        return .result(
            dialog: "Opening Listen2 to read your clipboard."
        )
    }
}
