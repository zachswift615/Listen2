//
//  AudioSessionManager.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine

/// Manages AVAudioSession configuration for background audio playback
/// Handles audio interruptions, route changes, and session lifecycle
final class AudioSessionManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isSessionActive: Bool = false
    @Published private(set) var isInterrupted: Bool = false
    @Published private(set) var currentRoute: String = "Unknown"

    // MARK: - Private Properties

    private let audioSession = AVAudioSession.sharedInstance()
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Errors

    enum AudioSessionError: Error, LocalizedError {
        case activationFailed(Error)
        case deactivationFailed(Error)
        case categoryConfigurationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .activationFailed(let error):
                return "Failed to activate audio session: \(error.localizedDescription)"
            case .deactivationFailed(let error):
                return "Failed to deactivate audio session: \(error.localizedDescription)"
            case .categoryConfigurationFailed(let error):
                return "Failed to configure audio session category: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
        updateCurrentRoute()
    }

    deinit {
        removeNotificationObservers()
    }

    // MARK: - Public Methods

    /// Configures and activates the audio session for background playback
    /// - Throws: AudioSessionError if configuration or activation fails
    func activateSession() throws {
        do {
            // Configure for background playback with spoken audio optimization
            // .mixWithOthers allows audio to play alongside other apps (e.g., music)
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers]
            )

            // Activate the session
            try audioSession.setActive(true, options: [])

            isSessionActive = true
            updateCurrentRoute()
        } catch {
            throw AudioSessionError.categoryConfigurationFailed(error)
        }
    }

    /// Deactivates the audio session
    /// - Parameter notifyOthers: Whether to notify other audio sessions that this session is now inactive
    /// - Throws: AudioSessionError if deactivation fails
    func deactivateSession(notifyOthers: Bool = true) throws {
        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers ? .notifyOthersOnDeactivation : []
            try audioSession.setActive(false, options: options)
            isSessionActive = false
        } catch {
            throw AudioSessionError.deactivationFailed(error)
        }
    }

    /// Reactivates the session after an interruption
    /// Call this when resuming playback after an interruption ends
    func reactivateAfterInterruption() {
        do {
            try audioSession.setActive(true, options: [])
            isSessionActive = true
            isInterrupted = false
        } catch {
            // Error reactivating audio session - will be handled by caller
        }
    }

    // MARK: - Private Methods

    private func setupNotificationObservers() {
        // Handle audio interruptions (phone calls, alarms, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // Handle route changes (headphones plugged/unplugged, etc.)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func removeNotificationObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Audio session has been interrupted (e.g., phone call)
            isInterrupted = true

        case .ended:
            // Interruption has ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                isInterrupted = false
                return
            }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // System suggests we should resume playback
                reactivateAfterInterruption()
            } else {
                isInterrupted = false
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        updateCurrentRoute()

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged - playback should pause
            // TTSService will handle the actual pause
            break

        case .newDeviceAvailable:
            // New device connected (e.g., headphones plugged in)
            break

        case .categoryChange:
            // Audio category changed
            break

        default:
            break
        }
    }

    private func updateCurrentRoute() {
        let outputs = audioSession.currentRoute.outputs
        if let output = outputs.first {
            currentRoute = output.portType.rawValue
        } else {
            currentRoute = "Unknown"
        }
    }
}
