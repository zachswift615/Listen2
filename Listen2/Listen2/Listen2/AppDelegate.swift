//
//  AppDelegate.swift
//  Listen2
//
//  Created for background audio support.
//

import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("[AppDelegate] 🚀 App launching...")

        // 1. Configure Audio Session
        setupAudioSession()

        // 2. Register for Remote Control Events
        UIApplication.shared.beginReceivingRemoteControlEvents()
        print("[AppDelegate] 📡 Registered for remote control events")

        return true
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true)
            print("[AppDelegate] ✅ Audio session configured and active")
        } catch {
            print("[AppDelegate] ❌ Failed to configure audio session: \(error)")
        }
    }
}
