//
//  TTSService.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer

final class TTSService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentProgress: ReadingProgress = .initial
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Float = 1.0

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentTitle: String = "Document"

    // MARK: - Initialization

    private var audioSessionConfigured = false

    override init() {
        super.init()
        synthesizer.delegate = self

        // Set default voice (first English voice)
        currentVoice = AVSpeechSynthesisVoice.speechVoices()
            .first { $0.language.hasPrefix("en") }

        // Setup remote command center for lock screen controls
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        guard !audioSessionConfigured else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // .playback category automatically routes to speaker
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
            audioSessionConfigured = true
        } catch {
            // Silently fail - audio will still work with default settings
            print("Note: Could not configure custom audio session, using defaults")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious()
            return .success
        }
    }

    private func updateNowPlayingInfo(title: String) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Listen2"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    // MARK: - Public Methods

    func availableVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { Voice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.5, rate))
    }

    func setVoice(_ voice: Voice) {
        currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
    }

    // MARK: - Playback Control

    func startReading(paragraphs: [String], from index: Int, title: String = "Document") {
        // Configure audio session on first playback (lazy initialization)
        configureAudioSession()

        currentText = paragraphs
        currentTitle = title

        guard index < paragraphs.count else { return }

        currentProgress = ReadingProgress(
            paragraphIndex: index,
            wordRange: nil,
            isPlaying: false
        )

        updateNowPlayingInfo(title: title)
        speakParagraph(at: index)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
    }

    func resume() {
        synthesizer.continueSpeaking()
        isPlaying = true
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
    }

    // MARK: - Private Methods

    private func speakParagraph(at index: Int) {
        guard index < currentText.count else { return }

        let text = currentText[index]
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice
        utterance.rate = playbackRate * 0.5 // AVSpeechUtterance rate is 0-1 scale

        // Reduce delay between utterances for smoother continuous reading
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.1 // Very short pause between paragraphs

        currentProgress = ReadingProgress(
            paragraphIndex: index,
            wordRange: nil,
            isPlaying: true
        )

        synthesizer.speak(utterance)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false

        // Auto-advance to next paragraph
        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            speakParagraph(at: nextIndex)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Update word range for highlighting
        // Note: This is called very frequently (once per word)
        // Only update if range is valid to reduce unnecessary UI updates
        let text = utterance.speechString
        if let range = Range(characterRange, in: text),
           range.lowerBound < text.endIndex {
            currentProgress = ReadingProgress(
                paragraphIndex: currentProgress.paragraphIndex,
                wordRange: range,
                isPlaying: true
            )
        }
    }
}
