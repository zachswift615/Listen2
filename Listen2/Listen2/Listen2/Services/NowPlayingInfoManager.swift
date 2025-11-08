//
//  NowPlayingInfoManager.swift
//  Listen2
//

import Foundation
import MediaPlayer
import Combine

/// Manages lock screen and Control Center media controls for TTS playback
/// Provides rich now playing information and handles remote commands
final class NowPlayingInfoManager: ObservableObject {

    // MARK: - Private Properties

    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    /// Current document metadata
    private var currentDocumentTitle: String = ""
    private var currentParagraphIndex: Int = 0
    private var totalParagraphs: Int = 0

    /// Playback state
    private var isPlaying: Bool = false
    private var playbackRate: Float = 1.0

    /// Timing information for progress tracking
    private var paragraphStartTime: Date?
    private var estimatedParagraphDuration: TimeInterval = 0

    /// Command handlers (weak to prevent retain cycles)
    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var nextHandler: (() -> Void)?
    private var previousHandler: (() -> Void)?

    // MARK: - Initialization

    init() {
        setupRemoteCommands()
    }

    deinit {
        clearNowPlayingInfo()
        removeRemoteCommands()
    }

    // MARK: - Public Configuration

    /// Set up command handlers for remote control
    /// - Parameters:
    ///   - play: Handler called when play command is received
    ///   - pause: Handler called when pause command is received
    ///   - next: Handler called when next track command is received
    ///   - previous: Handler called when previous track command is received
    func setCommandHandlers(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        self.playHandler = play
        self.pauseHandler = pause
        self.nextHandler = next
        self.previousHandler = previous
    }

    // MARK: - Now Playing Info Updates

    /// Update now playing info when starting a new document or paragraph
    /// - Parameters:
    ///   - documentTitle: Title of the document being read
    ///   - paragraphIndex: Current paragraph index (0-based)
    ///   - totalParagraphs: Total number of paragraphs in the document
    ///   - isPlaying: Whether playback is currently active
    ///   - rate: Current playback rate
    func updateNowPlayingInfo(
        documentTitle: String,
        paragraphIndex: Int,
        totalParagraphs: Int,
        isPlaying: Bool,
        rate: Float = 1.0
    ) {
        // Update cached state
        self.currentDocumentTitle = documentTitle
        self.currentParagraphIndex = paragraphIndex
        self.totalParagraphs = totalParagraphs
        self.isPlaying = isPlaying
        self.playbackRate = rate

        // Reset timing for new paragraph
        if isPlaying {
            paragraphStartTime = Date()
        }

        // Build and set now playing info
        var nowPlayingInfo = [String: Any]()

        // Title: Document name
        nowPlayingInfo[MPMediaItemPropertyTitle] = documentTitle

        // Artist: Paragraph position info
        let paragraphInfo = "Paragraph \(paragraphIndex + 1) of \(totalParagraphs)"
        nowPlayingInfo[MPMediaItemPropertyArtist] = paragraphInfo

        // Album: App name
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Listen2"

        // Playback rate
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0

        // Elapsed time (reset to 0 for new paragraph)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        // Duration (estimated based on paragraph - optional)
        // We don't set this since TTS duration is hard to predict accurately
        // Without duration, the lock screen won't show a progress bar, which is fine

        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
    }

    /// Update playback state (playing/paused) without changing other metadata
    /// - Parameter isPlaying: Whether playback is currently active
    func updatePlaybackState(isPlaying: Bool) {
        self.isPlaying = isPlaying

        guard var info = nowPlayingCenter.nowPlayingInfo else {
            return
        }

        // Update playback rate (0 when paused, normal rate when playing)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0

        // Update elapsed time if we have timing info
        if isPlaying {
            paragraphStartTime = Date()
        }

        nowPlayingCenter.nowPlayingInfo = info
    }

    /// Update elapsed playback time for the current paragraph
    /// Call this periodically during playback to keep lock screen in sync
    /// - Parameter elapsedTime: Elapsed time in seconds since paragraph started
    func updateElapsedTime(_ elapsedTime: TimeInterval) {
        guard var info = nowPlayingCenter.nowPlayingInfo else {
            return
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        nowPlayingCenter.nowPlayingInfo = info
    }

    /// Update playback rate when user changes speed
    /// - Parameter rate: New playback rate
    func updatePlaybackRate(_ rate: Float) {
        self.playbackRate = rate

        guard var info = nowPlayingCenter.nowPlayingInfo else {
            return
        }

        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        nowPlayingCenter.nowPlayingInfo = info
    }

    /// Clear all now playing information (call when stopping playback)
    func clearNowPlayingInfo() {
        nowPlayingCenter.nowPlayingInfo = nil
        paragraphStartTime = nil
        estimatedParagraphDuration = 0
    }

    // MARK: - Remote Command Setup

    private func setupRemoteCommands() {
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.playHandler?()
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pauseHandler?()
            return .success
        }

        // Next track (next paragraph)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextHandler?()
            return .success
        }

        // Previous track (previous paragraph)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousHandler?()
            return .success
        }

        // Toggle play/pause (convenience for single button)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true {
                self?.pauseHandler?()
            } else {
                self?.playHandler?()
            }
            return .success
        }

        // Disable commands we don't support
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.enableLanguageOptionCommand.isEnabled = false
        commandCenter.disableLanguageOptionCommand.isEnabled = false
    }

    private func removeRemoteCommands() {
        // Remove all command handlers
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        // Disable all commands
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
    }
}
