//
//  TTSService.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

@MainActor
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
    private var useFallback: Bool = false  // Disable fallback during testing
    private let audioSessionManager = AudioSessionManager()
    private let nowPlayingManager = NowPlayingInfoManager()
    private var audioPlayer: StreamingAudioPlayer!
    private var synthesisQueue: SynthesisQueue?
    private let chunkBuffer = ChunkBuffer()
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentTitle: String = "Document"
    private var shouldAutoAdvance = true // Track whether to auto-advance
    private var wordMap: DocumentWordMap? // Word map for precise highlighting
    private var currentDocumentID: UUID? // Current document ID for alignment caching

    // Alignment services
    private let alignmentService = PhonemeAlignmentService()
    private let alignmentCache = AlignmentCache()

    // Word highlighting for Piper playback
    private var highlightTimer: Timer?
    private var currentAlignment: AlignmentResult?
    private let wordHighlighter = WordHighlighter()

    // Timing validation to prevent getting stuck
    private var lastHighlightedWordIndex: Int?
    private var lastHighlightChangeTime: TimeInterval = 0
    private let maxStuckDuration: TimeInterval = 2.0  // Force move if stuck for > 2 seconds
    private var minWordIndex: Int = 0  // Minimum word index to prevent going backwards after forcing forward
    private var stuckWordWarningCount: [Int: Int] = [:]  // Track warning count per word to limit spam

    // Subscription for word highlighting
    private var highlightSubscription: AnyCancellable?

    // Active continuation for current audio playback (to prevent leaks during stop)
    private var activeContinuation: CheckedContinuation<Void, Error>?

    // Active speak task (to cancel during voice/speed changes)
    private var activeSpeakTask: Task<Void, Never>?

    // MARK: - Initialization

    override init() {
        super.init()
        fallbackSynthesizer.delegate = self

        // Initialize audio player on main actor
        Task { @MainActor in
            self.audioPlayer = StreamingAudioPlayer()
        }

        // Subscribe to word highlighter updates
        setupWordHighlighterSubscription()

        // TEMPORARY FIX: Clear corrupt alignment cache from previous sessions
        // TODO: Remove this after confirmed working - added 2025-11-14
        Task {
            do {
                try await alignmentCache.clearAll()
                print("[TTSService] 🗑️ Cleared corrupt alignment cache")
            } catch {
                print("[TTSService] ⚠️ Failed to clear cache: \(error)")
            }
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

            // Initialize synthesis queue with provider
            self.synthesisQueue = SynthesisQueue(
                provider: piperProvider
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
        // PhonemeAlignmentService doesn't require initialization
        // It works directly with phoneme data from TTS synthesis
        print("[TTSService] ✅ Phoneme alignment service ready (no initialization needed)")
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

    private func setupWordHighlighterSubscription() {
        // Subscribe to word highlighter updates on Main thread
        highlightSubscription = wordHighlighter.$highlightedRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                guard let self = self,
                      let range = range,
                      self.currentProgress.paragraphIndex < self.currentText.count else {
                    return
                }

                // Update current progress with highlighted word range
                self.currentProgress = ReadingProgress(
                    paragraphIndex: self.currentProgress.paragraphIndex,
                    wordRange: range,
                    isPlaying: self.isPlaying
                )
            }
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

        print("[TTSService] 🎚️ Playback rate changed to: \(newRate)")

        // Update now playing info with new rate
        nowPlayingManager.updatePlaybackRate(newRate)

        // Apply rate to audio player immediately (affects currently playing audio)
        audioPlayer.setRate(newRate)
        print("[TTSService] 🔊 Applied playback rate to audio player: \(newRate)")

        // If we were playing, restart current paragraph with new rate
        // NOTE: We don't call stop() because it resets progress to .initial (paragraph 0)
        // Instead, we just stop audio and restart from current position
        if wasPlaying {
            // Cancel active task FIRST - this sets Task.isCancelled which will break the sentence loop
            if let task = activeSpeakTask {
                print("[TTSService] 🛑 Cancelling active speak task for speed change")
                task.cancel()
                activeSpeakTask = nil
            }

            Task {
                // CRITICAL: Must await setSpeed BEFORE restarting playback
                // Otherwise playback starts with old speed (race condition)
                await synthesisQueue?.setSpeed(newRate)
                print("[TTSService] ✅ Speed updated in synthesis queue to: \(newRate)")

                // Resume continuation before stopping to prevent leak
                if let continuation = activeContinuation {
                    print("[TTSService] ⚠️ Resuming active continuation during speed change")
                    continuation.resume(throwing: CancellationError())
                    activeContinuation = nil
                }

                await audioPlayer.stop()
                wordHighlighter.stop()
                fallbackSynthesizer.stopSpeaking(at: .immediate)
                stopHighlightTimer()

                // Now speed is set, restart playback
                print("[TTSService] 🔄 Restarting playback at paragraph \(currentIndex) with new speed")
                speakParagraph(at: currentIndex)
            }
        } else {
            // Not playing, just update speed for next playback
            Task {
                await synthesisQueue?.setSpeed(newRate)
                print("[TTSService] ✅ Speed updated in synthesis queue to: \(newRate) (not playing)")
            }
        }
    }

    func setVoice(_ voice: AVVoice) {
        if voice.isPiperVoice {
            // Validate voice ID format
            guard voice.id.hasPrefix("piper:") else {
                print("[TTSService] ⚠️ Invalid Piper voice ID format: \(voice.id)")
                return
            }

            // Capture playback state before stopping
            let wasPlaying = isPlaying
            let currentIndex = currentProgress.paragraphIndex
            let savedText = currentText
            let savedTitle = currentTitle
            let savedWordMap = wordMap
            let savedDocumentID = currentDocumentID

            // Stop current playback if active
            if wasPlaying {
                stop()
            }

            // Extract voice ID from "piper:en_US-lessac-medium" format
            let voiceID = String(voice.id.dropFirst("piper:".count))

            print("[TTSService] 🎤 Switching to voice: \(voiceID)")

            // Reinitialize Piper provider with new voice
            Task {
                do {
                    let piperProvider = PiperTTSProvider(
                        voiceID: voiceID,
                        voiceManager: voiceManager
                    )
                    try await piperProvider.initialize()

                    // Update properties (already on MainActor)
                    provider = piperProvider

                    // Update synthesis queue with new provider
                    synthesisQueue = SynthesisQueue(
                        provider: piperProvider
                    )

                    print("[TTSService] ✅ Switched to Piper voice: \(voiceID)")

                    // If was playing, restart from saved position with new voice
                    if wasPlaying {
                        // Restore document state
                        currentText = savedText
                        currentTitle = savedTitle
                        wordMap = savedWordMap
                        currentDocumentID = savedDocumentID

                        // Initialize new queue with saved content
                        await synthesisQueue?.setContent(
                            paragraphs: savedText,
                            speed: playbackRate,
                            documentID: savedDocumentID,
                            wordMap: savedWordMap
                        )

                        // Restart playback from saved position
                        print("[TTSService] 🔄 Restarting playback at paragraph \(currentIndex) with new voice")
                        speakParagraph(at: currentIndex)
                    }
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
        Task {
            await synthesisQueue?.setContent(
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
        // Resume continuation before pausing to prevent leaks
        if let continuation = activeContinuation {
            print("[TTSService] ⚠️ Resuming active continuation during pause()")
            continuation.resume(throwing: CancellationError())
            activeContinuation = nil
        }

        Task { @MainActor in
            audioPlayer.pause()
            wordHighlighter.pause()
        }
        fallbackSynthesizer.pauseSpeaking(at: .word)
        stopHighlightTimer()
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func resume() {
        Task { @MainActor in
            audioPlayer.resume()
            wordHighlighter.resume()
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

        // Stop audio but DON'T clear document state (stop() clears currentText)
        stopAudioOnly()
        speakParagraph(at: nextIndex)
    }

    func skipToPrevious() {
        let prevIndex = max(0, currentProgress.paragraphIndex - 1)
        // Stop audio but DON'T clear document state (stop() clears currentText)
        stopAudioOnly()
        speakParagraph(at: prevIndex)
    }

    /// Stop audio playback without clearing document state (for skip buttons)
    private func stopAudioOnly() {
        Task {
            await audioPlayer.stop()
            // Clear sentence cache for new paragraph
            await synthesisQueue?.clearAll()
            await MainActor.run {
                wordHighlighter.stop()
            }
        }
        fallbackSynthesizer.stopSpeaking(at: .immediate)
        stopHighlightTimer()
        isPlaying = false

        // DON'T clear currentText, wordMap, etc. - keep document loaded
        // Just reset playback state
        currentProgress = ReadingProgress(
            paragraphIndex: currentProgress.paragraphIndex,
            wordRange: nil,
            isPlaying: false
        )
        lastHighlightedWordIndex = nil
        lastHighlightChangeTime = 0
    }

    func stop() {
        // Cancel active speak task first (this sets Task.isCancelled)
        if let task = activeSpeakTask {
            print("[TTSService] 🛑 Cancelling active speak task during stop()")
            task.cancel()
            activeSpeakTask = nil
        }

        // CRITICAL: Resume any active continuation to prevent leaks
        // This happens when stop() is called while audio is playing (e.g., during voice/speed change)
        if let continuation = activeContinuation {
            print("[TTSService] ⚠️ Resuming active continuation during stop() to prevent leak")
            continuation.resume(throwing: CancellationError())
            activeContinuation = nil
        }

        Task {
            await audioPlayer.stop()
            // Clear synthesis queue cache when stopped
            await synthesisQueue?.clearAll()
            wordHighlighter.stop()
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

        // Reset timing validation tracking
        lastHighlightedWordIndex = nil
        lastHighlightChangeTime = 0

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

        // Cancel any existing speak task before starting a new one
        if let existingTask = activeSpeakTask {
            print("[TTSService] 🔄 Cancelling existing speak task before starting new one")
            existingTask.cancel()
        }

        // Use chunk-level streaming with synthesis queue
        if let queue = synthesisQueue {
            let taskID = UUID().uuidString.prefix(8)
            print("[TTSService] 🎬 Starting streaming task \(taskID) for paragraph \(index)")

            activeSpeakTask = Task {
                defer {
                    print("[TTSService] 🏁 Ending streaming task \(taskID)")
                    self.activeSpeakTask = nil
                }
                do {
                    // Split into sentences
                    let sentences = SentenceSplitter.split(text)
                    print("[TTSService] 📝 Split paragraph into \(sentences.count) sentences")

                    // Play each sentence with chunk streaming
                    for (sentenceIndex, chunk) in sentences.enumerated() {
                        // Check cancellation
                        guard !Task.isCancelled else {
                            print("[TTSService] 🛑 Task cancelled - breaking loop")
                            throw CancellationError()
                        }

                        print("[TTSService] 🎤 Starting sentence \(sentenceIndex+1)/\(sentences.count)")

                        // Play sentence with chunk streaming
                        try await playSentenceWithChunks(
                            sentence: chunk.text,
                            isLast: sentenceIndex == sentences.count - 1
                        )
                    }

                    // Check cancellation one more time before advancing
                    guard !Task.isCancelled else {
                        print("[TTSService] 🛑 Task cancelled after sentences complete")
                        throw CancellationError()
                    }

                    // All sentences played - advance to next paragraph
                    print("[TTSService] ✅ Paragraph complete, advancing")
                    handleParagraphComplete()

                } catch is CancellationError {
                    print("[TTSService] ⏸️ Playback cancelled")
                    await MainActor.run {
                        self.isPlaying = false
                    }
                } catch {
                    print("[TTSService] ❌ Error during playback: \(error)")
                    if useFallback {
                        print("[TTSService] Falling back to AVSpeech")
                        await MainActor.run {
                            self.fallbackToAVSpeech(text: text)
                        }
                    } else {
                        print("[TTSService] Fallback disabled - stopping")
                        await MainActor.run {
                            self.isPlaying = false
                        }
                    }
                }
            }
        } else {
            print("[TTSService] ⚠️ Synthesis queue unavailable")
            isPlaying = false
        }
    }

    /// Play a sentence with chunk-level streaming
    private func playSentenceWithChunks(sentence: String, isLast: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // Store continuation for clean cancellation
                activeContinuation = continuation

                do {
                    // Start streaming session
                    audioPlayer.startStreaming { [weak self] in
                        // Sentence finished playing
                        print("[TTSService] 🏁 Sentence playback complete")
                        self?.activeContinuation = nil
                        continuation.resume()
                    }

                    // Create delegate to receive chunks
                    let chunkDelegate = ChunkStreamDelegate(audioPlayer: audioPlayer)

                    // Start synthesis with streaming - chunks will be scheduled as they arrive
                    Task {
                        do {
                            // This will call chunkDelegate.didReceiveAudioChunk() for each chunk
                            _ = try await synthesisQueue?.streamSentence(sentence, delegate: chunkDelegate)

                            // All chunks synthesized - mark scheduling complete
                            await MainActor.run {
                                audioPlayer.finishScheduling()
                            }
                        } catch {
                            print("[TTSService] ❌ Synthesis error: \(error)")
                            await MainActor.run {
                                activeContinuation = nil
                                continuation.resume(throwing: error)
                            }
                        }
                    }

                    // Update playback state
                    isPlaying = true
                    shouldAutoAdvance = true

                } catch {
                    activeContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // DEAD CODE - Removed during chunk streaming refactor
    // This method was replaced by playSentenceWithChunks() for streaming audio
    // Kept commented for reference during development
    /*
    /// Play a sentence audio chunk and wait for completion
    /// - Parameters:
    ///   - bundle: Sentence bundle containing audio data and timeline
    ///   - paragraphText: Full paragraph text for word position mapping
    ///   - isFirst: Whether this is the first sentence (for initialization)
    private func playSentenceAudio(bundle: SentenceBundle, paragraphText: String, isFirst: Bool) async throws {
        // Use a continuation to wait for audio playback to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // Store the continuation so we can resume it during stop() to prevent leaks
                activeContinuation = continuation

                do {
                    // Get alignment for current paragraph from synthesis queue (only on first sentence)
                    if isFirst {
                        // NOTE: getAlignment() method was removed from SynthesisQueue
                        currentAlignment = nil
                        minWordIndex = 0
                        stuckWordWarningCount.removeAll()
                        startHighlightTimer()
                    }

                    // NOTE: audioPlayer.play() method was removed - replaced with streaming methods
                    // startStreaming(), scheduleChunk(), finishScheduling()

                    // Update playback state
                    isPlaying = true
                    if isFirst {
                        shouldAutoAdvance = true
                    }
                } catch {
                    activeContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    */

    // DEAD CODE - This method is no longer called
    // Alignment is now handled during chunk streaming
    /*
    private func playAudio(_ data: Data) async throws {
        // NOTE: getAlignment() method was removed from SynthesisQueue
        // Alignment is now managed during chunk streaming in playSentenceWithChunks()

        try await MainActor.run {
            currentAlignment = nil

            // Reset word tracking for new paragraph
            minWordIndex = 0
            stuckWordWarningCount.removeAll()

            // NOTE: audioPlayer.play() was removed - replaced with streaming methods
            // startStreaming(), scheduleChunk(), finishScheduling()

            // Re-enable auto-advance once playback has started
            // (mirrors AVSpeech didStart delegate behavior)
            isPlaying = true
            shouldAutoAdvance = true

            // Start word highlighting timer for Piper playback
            startHighlightTimer()
        }
    }
    */

    private func fallbackToAVSpeech(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice
        utterance.rate = playbackRate * 0.5
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = paragraphPauseDelay
        fallbackSynthesizer.speak(utterance)
    }

    private func getAudioDuration(_ audioData: Data) -> Double {
        // WAV header is 44 bytes, then 16-bit samples at 22050 Hz
        guard audioData.count > 44 else { return 0 }
        let sampleCount = (audioData.count - 44) / 2
        return Double(sampleCount) / 22050.0
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
        // TEMPORARY: Highlighting disabled during chunk streaming development
        // Will revisit with better approach after streaming is stable
        print("[TTSService] ⏸️ Word highlighting temporarily disabled")
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
               let _ = wordTiming.stringRange(in: paragraphText) {

                // Enforce minimum word index to prevent going backwards after forcing forward
                let effectiveWordIndex = max(wordTiming.wordIndex, minWordIndex)

                // If alignment wants to go backwards, skip to the minimum word instead
                let effectiveTiming: AlignmentResult.WordTiming
                if effectiveWordIndex != wordTiming.wordIndex && effectiveWordIndex < alignment.wordTimings.count {
                    effectiveTiming = alignment.wordTimings[effectiveWordIndex]
                } else {
                    effectiveTiming = wordTiming
                }

                guard let effectiveRange = effectiveTiming.stringRange(in: paragraphText) else {
                    return
                }

                // Check if we're stuck on the same word for too long
                let wordChanged = lastHighlightedWordIndex != effectiveTiming.wordIndex

                if wordChanged {
                    // Word changed - update tracking and reset stuck counter
                    lastHighlightedWordIndex = effectiveTiming.wordIndex
                    lastHighlightChangeTime = currentTime
                    stuckWordWarningCount[effectiveTiming.wordIndex] = 0
                } else {
                    // Same word - check if we're stuck
                    let stuckDuration = currentTime - lastHighlightChangeTime
                    if stuckDuration > maxStuckDuration {
                        // Limit warning spam to 3 times per word
                        let warningCount = stuckWordWarningCount[effectiveTiming.wordIndex, default: 0]
                        if warningCount < 3 {
                            print("⚠️  Highlight stuck on word '\(effectiveTiming.text)' for \(String(format: "%.2f", stuckDuration))s, forcing next word")
                            stuckWordWarningCount[effectiveTiming.wordIndex] = warningCount + 1
                        }

                        // Try to find the next word in the alignment
                        let nextWordIndex = effectiveTiming.wordIndex + 1
                        if nextWordIndex < alignment.wordTimings.count {
                            let nextTiming = alignment.wordTimings[nextWordIndex]
                            if let nextRange = nextTiming.stringRange(in: paragraphText) {
                                // Force move to next word and update minimum to prevent going back
                                minWordIndex = nextWordIndex
                                currentProgress = ReadingProgress(
                                    paragraphIndex: currentProgress.paragraphIndex,
                                    wordRange: nextRange,
                                    isPlaying: true
                                )
                                lastHighlightedWordIndex = nextTiming.wordIndex
                                lastHighlightChangeTime = currentTime
                                return
                            }
                        }
                    }
                }

                // Update progress with word range for highlighting
                currentProgress = ReadingProgress(
                    paragraphIndex: currentProgress.paragraphIndex,
                    wordRange: effectiveRange,
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

// MARK: - Buffering Chunk Delegate with Completion Tracking

/// Delegate that receives audio chunks and stores them in ChunkBuffer
/// Tracks pending async chunk additions to ensure all chunks are buffered before marking complete
/// NOT @MainActor on class - runs in background pre-synthesis tasks
private class BufferingChunkDelegate: SynthesisStreamDelegate {
    private let buffer: ChunkBuffer
    private let sentenceIndex: Int

    // Track pending async chunk additions (main-actor isolated)
    @MainActor private var pendingChunks: Int = 0
    @MainActor private var completion: CheckedContinuation<Void, Never>?

    init(buffer: ChunkBuffer, sentenceIndex: Int) {
        self.buffer = buffer
        self.sentenceIndex = sentenceIndex
    }

    /// Wait for all chunk additions to complete
    /// CRITICAL: Call this before markComplete() to prevent race conditions!
    @MainActor func waitForCompletion() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if pendingChunks == 0 {
                // All chunks already buffered
                continuation.resume()
            } else {
                // Store continuation, will resume when pendingChunks reaches 0
                self.completion = continuation
            }
        }
    }

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        Task { @MainActor in
            // Increment pending count
            self.pendingChunks += 1

            // Add chunk to buffer (async actor call)
            await self.buffer.addChunk(chunk, forSentence: self.sentenceIndex)

            // Decrement pending count
            self.pendingChunks -= 1

            // Check if all chunks are now buffered
            if self.pendingChunks == 0, let continuation = self.completion {
                self.completion = nil
                continuation.resume()
            }
        }
        return true // Continue synthesis
    }
}

// MARK: - Chunk Stream Delegate

/// Delegate that receives audio chunks and schedules them on audio player
private class ChunkStreamDelegate: SynthesisStreamDelegate {
    private weak var audioPlayer: StreamingAudioPlayer?

    init(audioPlayer: StreamingAudioPlayer) {
        self.audioPlayer = audioPlayer
    }

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        Task { @MainActor in
            // Schedule chunk immediately on audio player
            audioPlayer?.scheduleChunk(chunk)
        }
        return true // Continue synthesis
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
