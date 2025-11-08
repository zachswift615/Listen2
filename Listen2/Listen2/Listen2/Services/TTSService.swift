//
//  TTSService.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

final class TTSService: NSObject, ObservableObject {

    // MARK: - Settings

    @AppStorage("paragraphPauseDelay") private var paragraphPauseDelay: Double = 0.3
    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0

    // MARK: - Published Properties

    @Published private(set) var currentProgress: ReadingProgress = .initial
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Float = 1.0

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSessionManager = AudioSessionManager()
    private let nowPlayingManager = NowPlayingInfoManager()
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentTitle: String = "Document"
    private var shouldAutoAdvance = true // Track whether to auto-advance

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self

        // Set default voice (first English voice)
        currentVoice = AVSpeechSynthesisVoice.speechVoices()
            .first { $0.language.hasPrefix("en") }

        // Setup now playing manager with command handlers
        setupNowPlayingManager()

        // Setup audio session manager
        setupAudioSessionObservers()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            try audioSessionManager.activateSession()
        } catch {
            // Log error but don't fail - audio will still work with default settings
            print("Warning: Could not activate audio session: \(error.localizedDescription)")
        }
    }

    private func setupAudioSessionObservers() {
        // Monitor interruption state changes
        audioSessionManager.$isInterrupted
            .sink { [weak self] isInterrupted in
                if isInterrupted {
                    // Pause playback when interrupted
                    self?.pause()
                }
                // Note: Resume is handled by user action or remote command center
            }
            .store(in: &cancellables)

        // Monitor route changes for headphone disconnection
        audioSessionManager.$currentRoute
            .dropFirst() // Skip initial value
            .sink { [weak self] route in
                // Pause when headphones are unplugged
                // This is a common UX pattern for audio apps
                if self?.isPlaying == true && !route.contains("Headphone") {
                    self?.pause()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    deinit {
        // Clean up audio session
        try? audioSessionManager.deactivateSession()
    }

    private func setupNowPlayingManager() {
        // Set up command handlers for lock screen controls
        nowPlayingManager.setCommandHandlers(
            play: { [weak self] in
                self?.resume()
            },
            pause: { [weak self] in
                self?.pause()
            },
            next: { [weak self] in
                self?.skipToNext()
            },
            previous: { [weak self] in
                self?.skipToPrevious()
            }
        )
    }

    // MARK: - Public Methods

    func availableVoices() -> [AVVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    func setPlaybackRate(_ rate: Float) {
        let newRate = max(0.5, min(2.5, rate))

        // Save to defaults for future sessions
        defaultPlaybackRate = Double(newRate)

        // Check if we were playing BEFORE we modify state
        let wasPlaying = isPlaying || synthesizer.isSpeaking
        let currentIndex = currentProgress.paragraphIndex

        // Update the rate
        playbackRate = newRate

        // Update now playing info with new rate
        nowPlayingManager.updatePlaybackRate(newRate)

        // If we were playing, restart current paragraph with new rate
        // This ensures rapid slider changes all trigger restarts
        if wasPlaying {
            stop()
            speakParagraph(at: currentIndex)
        }
    }

    func setVoice(_ voice: AVVoice) {
        currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
    }

    // MARK: - Playback Control

    func startReading(paragraphs: [String], from index: Int, title: String = "Document") {
        // Configure audio session on first playback (lazy initialization)
        configureAudioSession()

        currentText = paragraphs
        currentTitle = title

        guard index < paragraphs.count else { return }

        // Stop auto-advance temporarily when jumping to specific paragraph
        // This prevents race condition with didFinish from previous utterance
        shouldAutoAdvance = false

        currentProgress = ReadingProgress(
            paragraphIndex: index,
            wordRange: nil,
            isPlaying: false
        )

        speakParagraph(at: index)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func resume() {
        synthesizer.continueSpeaking()
        isPlaying = true
        nowPlayingManager.updatePlaybackState(isPlaying: true)
    }

    func skipToNext() {
        let nextIndex = currentProgress.paragraphIndex + 1
        guard nextIndex < currentText.count else {
            stop()
            return
        }

        stop()
        speakParagraph(at: nextIndex)
    }

    func skipToPrevious() {
        let prevIndex = max(0, currentProgress.paragraphIndex - 1)
        stop()
        speakParagraph(at: prevIndex)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        nowPlayingManager.clearNowPlayingInfo()
    }

    // MARK: - Private Methods

    private func speakParagraph(at index: Int) {
        guard index < currentText.count else { return }

        let text = currentText[index]
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice
        utterance.rate = playbackRate * 0.5 // AVSpeechUtterance rate is 0-1 scale

        // Configure delays for smooth continuous reading
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = paragraphPauseDelay // User-configurable pause

        currentProgress = ReadingProgress(
            paragraphIndex: index,
            wordRange: nil,
            isPlaying: true
        )

        // Update now playing info for lock screen
        nowPlayingManager.updateNowPlayingInfo(
            documentTitle: currentTitle,
            paragraphIndex: index,
            totalParagraphs: currentText.count,
            isPlaying: true,
            rate: playbackRate
        )

        synthesizer.speak(utterance)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlaying = true
        // Re-enable auto-advance once utterance has actually started
        shouldAutoAdvance = true
        nowPlayingManager.updatePlaybackState(isPlaying: true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false

        // Auto-advance to next paragraph (only if not jumping to specific paragraph)
        guard shouldAutoAdvance else { return }

        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            speakParagraph(at: nextIndex)
        } else {
            // Reached end of document, clear now playing info
            nowPlayingManager.clearNowPlayingInfo()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // DISABLED: Word highlighting causes severe performance issues on real devices
        // This delegate fires 100+ times per paragraph, triggering expensive UI updates
        // Keeping only paragraph highlighting for smooth performance

        // TODO: Re-enable with throttling/debouncing if needed
    }
}
