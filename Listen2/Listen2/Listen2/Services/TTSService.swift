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
    @Published private(set) var isInitializing: Bool = true

    // MARK: - Private Properties

    private var provider: TTSProvider?
    private var fallbackSynthesizer = AVSpeechSynthesizer()
    private let voiceManager = VoiceManager()
    private var usePiper: Bool = true  // Feature flag
    private let audioSessionManager = AudioSessionManager()
    private let nowPlayingManager = NowPlayingInfoManager()
    private var audioPlayer: AudioPlayer!
    private var synthesisQueue: SynthesisQueue?
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentTitle: String = "Document"
    private var shouldAutoAdvance = true // Track whether to auto-advance
    private var wordMap: DocumentWordMap? // Word map for precise highlighting
    private var currentDocumentID: UUID? // Current document ID for alignment caching

    // Alignment services
    private let alignmentService = WordAlignmentService()
    private let alignmentCache = AlignmentCache()

    // Word highlighting for Piper playback
    private var highlightTimer: Timer?
    private var currentAlignment: AlignmentResult?

    // MARK: - Initialization

    override init() {
        super.init()
        fallbackSynthesizer.delegate = self

        // Initialize audio player on main actor
        Task { @MainActor in
            self.audioPlayer = AudioPlayer()
        }

        // Try to initialize Piper TTS and alignment service
        Task {
            await initializePiperProvider()
            await initializeAlignmentService()
        }

        // Setup now playing manager
        setupNowPlayingManager()

        // Setup audio session observers
        setupAudioSessionObservers()
    }

    private func initializePiperProvider() async {
        guard usePiper else { return }

        await MainActor.run {
            isInitializing = true
        }

        do {
            let bundledVoice = voiceManager.bundledVoice()
            let piperProvider = PiperTTSProvider(
                voiceID: bundledVoice.id,
                voiceManager: voiceManager
            )
            try await piperProvider.initialize()
            self.provider = piperProvider

            // Initialize synthesis queue with provider and alignment services
            self.synthesisQueue = await SynthesisQueue(
                provider: piperProvider,
                alignmentService: alignmentService,
                alignmentCache: alignmentCache
            )

            print("[TTSService] ✅ Piper TTS initialized with voice: \(bundledVoice.id)")
        } catch {
            print("[TTSService] ⚠️ Piper initialization failed, using AVSpeech fallback: \(error)")
            self.provider = nil
            self.synthesisQueue = nil
        }

        await MainActor.run {
            isInitializing = false
        }
    }

    private func initializeAlignmentService() async {
        do {
            // Get path to ASR model
            guard let modelPath = Bundle.main.resourcePath else {
                throw AlignmentError.recognitionFailed("Cannot find app bundle")
            }
            let asrModelPath = (modelPath as NSString).appendingPathComponent("Resources/ASRModels/whisper-tiny")

            // Initialize alignment service
            try await alignmentService.initialize(modelPath: asrModelPath)
            print("[TTSService] ✅ Word alignment service initialized")
        } catch {
            print("[TTSService] ⚠️ Alignment service initialization failed: \(error)")
            // Continue without alignment - it's optional
        }
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
        piperVoices()
    }

    func piperVoices() -> [AVVoice] {
        voiceManager.downloadedVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    func iosVoices() -> [AVVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { AVVoice(from: $0) }
            .sorted { $0.language < $1.language }
    }

    func setPlaybackRate(_ rate: Float) {
        let newRate = max(0.5, min(2.5, rate))

        // Save to defaults for future sessions
        defaultPlaybackRate = Double(newRate)

        // Check if we were playing BEFORE we modify state
        let wasPlaying = isPlaying || fallbackSynthesizer.isSpeaking
        let currentIndex = currentProgress.paragraphIndex

        // Update the rate
        playbackRate = newRate

        // Update synthesis queue with new speed (clears cache)
        Task { @MainActor in
            synthesisQueue?.setSpeed(newRate)
        }

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
        if voice.isPiperVoice {
            // Validate voice ID format
            guard voice.id.hasPrefix("piper:") else {
                print("[TTSService] ⚠️ Invalid Piper voice ID format: \(voice.id)")
                return
            }

            // Stop current playback if active
            if isPlaying {
                stop()
            }

            // Extract voice ID from "piper:en_US-lessac-medium" format
            let voiceID = String(voice.id.dropFirst("piper:".count))

            // Reinitialize Piper provider with new voice
            Task {
                do {
                    let piperProvider = PiperTTSProvider(
                        voiceID: voiceID,
                        voiceManager: voiceManager
                    )
                    try await piperProvider.initialize()

                    await MainActor.run {
                        self.provider = piperProvider
                    }

                    // Update synthesis queue with new provider and alignment services
                    self.synthesisQueue = await SynthesisQueue(
                        provider: piperProvider,
                        alignmentService: alignmentService,
                        alignmentCache: alignmentCache
                    )

                    print("[TTSService] ✅ Switched to Piper voice: \(voiceID)")
                } catch {
                    print("[TTSService] ⚠️ Failed to switch Piper voice: \(error)")
                }
            }
        } else {
            // iOS voice - set for fallback
            currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
        }
    }

    // MARK: - Playback Control

    func startReading(paragraphs: [String], from index: Int, title: String = "Document", wordMap: DocumentWordMap? = nil, documentID: UUID? = nil) {
        // Configure audio session on first playback (lazy initialization)
        configureAudioSession()

        currentText = paragraphs
        currentTitle = title
        self.wordMap = wordMap
        self.currentDocumentID = documentID

        guard index < paragraphs.count else { return }

        // Initialize synthesis queue with new content
        Task { @MainActor in
            synthesisQueue?.setContent(
                paragraphs: paragraphs,
                speed: playbackRate,
                documentID: documentID,
                wordMap: wordMap
            )
        }

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
        Task { @MainActor in
            audioPlayer.pause()
        }
        fallbackSynthesizer.pauseSpeaking(at: .word)
        stopHighlightTimer()
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func resume() {
        Task { @MainActor in
            audioPlayer.resume()
        }
        fallbackSynthesizer.continueSpeaking()
        startHighlightTimer()
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
        Task { @MainActor in
            audioPlayer.stop()
            // Clear synthesis queue cache when stopped
            synthesisQueue?.clearAll()
        }
        fallbackSynthesizer.stopSpeaking(at: .immediate)
        stopHighlightTimer()
        isPlaying = false

        // Reset state to prevent stale content when switching documents
        currentText = []
        currentProgress = .initial
        wordMap = nil
        currentDocumentID = nil
        currentAlignment = nil

        nowPlayingManager.clearNowPlayingInfo()
    }

    // MARK: - Private Methods

    private func speakParagraph(at index: Int) {
        guard index < currentText.count else { return }

        let text = currentText[index]

        currentProgress = ReadingProgress(
            paragraphIndex: index,
            wordRange: nil,
            isPlaying: false
        )

        nowPlayingManager.updateNowPlayingInfo(
            documentTitle: currentTitle,
            paragraphIndex: index,
            totalParagraphs: currentText.count,
            isPlaying: true,
            rate: playbackRate
        )

        // Try Piper TTS with synthesis queue first, fallback to AVSpeech if unavailable or on error
        if let queue = synthesisQueue {
            Task {
                do {
                    // Get audio from queue (may be pre-synthesized or synthesize on-demand)
                    guard let wavData = try await queue.getAudio(for: index) else {
                        // Audio is being synthesized, wait briefly and retry
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        guard let retryData = try await queue.getAudio(for: index) else {
                            throw TTSError.synthesisFailed(reason: "Synthesis timeout")
                        }
                        try await playAudio(retryData)
                        return
                    }
                    try await playAudio(wavData)
                } catch {
                    print("[TTSService] ⚠️ Piper synthesis failed: \(error), falling back to AVSpeech")
                    await MainActor.run {
                        self.fallbackToAVSpeech(text: text)
                    }
                }
            }
        } else {
            fallbackToAVSpeech(text: text)
        }
    }

    private func playAudio(_ data: Data) async throws {
        try await MainActor.run {
            // Get alignment for current paragraph from synthesis queue
            let paragraphIndex = currentProgress.paragraphIndex
            currentAlignment = synthesisQueue?.getAlignment(for: paragraphIndex)

            try audioPlayer.play(data: data) { [weak self] in
                self?.handleParagraphComplete()
            }

            // Re-enable auto-advance once playback has started
            // (mirrors AVSpeech didStart delegate behavior)
            isPlaying = true
            shouldAutoAdvance = true

            // Start word highlighting timer for Piper playback
            startHighlightTimer()
        }
    }

    private func fallbackToAVSpeech(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice
        utterance.rate = playbackRate * 0.5
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = paragraphPauseDelay
        fallbackSynthesizer.speak(utterance)
    }

    private func handleParagraphComplete() {
        // Don't set isPlaying to false yet if we're auto-advancing
        // This prevents flicker when transitioning between paragraphs

        guard shouldAutoAdvance else {
            isPlaying = false
            return
        }

        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            // Auto-advance to next paragraph WITHOUT setting isPlaying to false
            // The next paragraph will maintain isPlaying = true
            speakParagraph(at: nextIndex)
        } else {
            // Reached end of document - now we can set to false
            isPlaying = false
            nowPlayingManager.clearNowPlayingInfo()
        }
    }

    // MARK: - Word Highlighting

    /// Start timer for word highlighting during Piper playback (60 FPS)
    private func startHighlightTimer() {
        // Only start timer if we have alignment data
        guard currentAlignment != nil else { return }

        // Clean up any existing timer
        stopHighlightTimer()

        // Create timer running at ~60 FPS for smooth highlighting
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateHighlightFromTime()
        }
    }

    /// Stop and clean up highlight timer
    private func stopHighlightTimer() {
        highlightTimer?.invalidate()
        highlightTimer = nil
    }

    /// Update current word highlight based on audio playback time
    private func updateHighlightFromTime() {
        guard let alignment = currentAlignment else { return }

        // Get current playback time from audio player
        Task { @MainActor in
            let currentTime = audioPlayer.currentTime

            // Find the word being spoken at this time
            if let wordTiming = alignment.wordTiming(at: currentTime),
               let paragraphText = currentText[safe: currentProgress.paragraphIndex],
               let stringRange = wordTiming.stringRange(in: paragraphText) {
                // Update progress with word range for highlighting
                currentProgress = ReadingProgress(
                    paragraphIndex: currentProgress.paragraphIndex,
                    wordRange: stringRange,
                    isPlaying: true
                )
            }
        }
    }
}

// MARK: - Safe Array Access
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
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
        // Don't set isPlaying to false yet if we're auto-advancing
        // This prevents flicker when transitioning between paragraphs

        guard shouldAutoAdvance else {
            isPlaying = false
            return
        }

        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            // Auto-advance to next paragraph WITHOUT setting isPlaying to false
            // The didStart delegate will set isPlaying = true
            speakParagraph(at: nextIndex)
        } else {
            // Reached end of document - now we can set to false
            isPlaying = false
            nowPlayingManager.clearNowPlayingInfo()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Use word map for precise highlighting if available
        if let wordMap = wordMap {
            let currentIndex = currentProgress.paragraphIndex
            guard currentIndex < currentText.count else { return }
            let paragraphText = currentText[currentIndex]

            // Convert NSRange to word range using word map
            if let wordRange = wordMap.wordRange(for: characterRange, in: currentIndex, paragraphText: paragraphText) {
                currentProgress = ReadingProgress(
                    paragraphIndex: currentIndex,
                    wordRange: wordRange,
                    isPlaying: true
                )
            }
        }
        // Note: Word highlighting without word map is disabled due to performance issues
        // The delegate fires 100+ times per paragraph, and without pre-computed positions,
        // it causes expensive UI updates. Word map provides efficient, pre-computed positions.
    }
}
