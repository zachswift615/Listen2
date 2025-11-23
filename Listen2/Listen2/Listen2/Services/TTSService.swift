//
//  TTSService.swift
//  Listen2
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

// MARK: - ContinuationResumer

/// Thread-safe wrapper to ensure continuation is only resumed once
/// Prevents crashes from race conditions between stop() and playback completion
private final class ContinuationResumer<T, E: Error>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, E>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    /// Resume with success value. Safe to call multiple times - only first call takes effect.
    func resume(returning value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()  // Unlock BEFORE calling resume to prevent deadlocks
        #if DEBUG
        if cont == nil {
            print("[ContinuationResumer] ⚠️ Ignored duplicate resume(returning:)")
        }
        #endif
        cont?.resume(returning: value)
    }

    /// Resume with error. Safe to call multiple times - only first call takes effect.
    func resume(throwing error: E) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()  // Unlock BEFORE calling resume to prevent deadlocks
        #if DEBUG
        if cont == nil {
            print("[ContinuationResumer] ⚠️ Ignored duplicate resume(throwing:)")
        }
        #endif
        cont?.resume(throwing: error)
    }

    /// Check if already resumed
    var isResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation == nil
    }
}

@MainActor
final class TTSService: NSObject, ObservableObject {

    // MARK: - Settings

    @AppStorage("paragraphPauseDelay") private var paragraphPauseDelay: Double = 0.3
    @AppStorage("defaultPlaybackRate") private var defaultPlaybackRate: Double = 1.0
    @AppStorage("wordHighlightingEnabled") private var wordHighlightingEnabled: Bool = true

    // MARK: - Published Properties

    @Published private(set) var currentProgress: ReadingProgress = .initial
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var isInitializing: Bool = true
    @Published private(set) var isPreparing: Bool = false

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
    private var readyQueue: ReadyQueue?
    private var currentText: [String] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentTitle: String = "Document"
    private var shouldAutoAdvance = true // Track whether to auto-advance
    private var wordMap: DocumentWordMap? // Word map for precise highlighting
    private var currentDocumentID: UUID? // Current document ID for alignment caching

    // Alignment services
    private let alignmentService = PhonemeAlignmentService()
    private let alignmentCache = AlignmentCache()
    private let ctcAligner = CTCForcedAligner()

    // Feature flag: use CTC forced alignment for word highlighting
    private var useCTCAlignment = true

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

    // Active continuation resumer for current audio playback (prevents double-resume crashes)
    private var activeResumer: ContinuationResumer<Void, Error>?

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

            // Initialize ready queue with dependencies
            self.readyQueue = ReadyQueue(synthesisQueue: self.synthesisQueue!, ctcAligner: self.ctcAligner)

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

        // Initialize CTC Forced Aligner (async)
        if useCTCAlignment {
            do {
                try await ctcAligner.initialize()
                let hasOnnx = await ctcAligner.hasOnnxSession
                print("[TTSService] ✅ CTC Forced Aligner initialized (ONNX: \(hasOnnx ? "available" : "mock mode"))")
            } catch {
                print("[TTSService] ⚠️ CTC Forced Aligner init failed: \(error)")
                print("[TTSService] 🔄 Falling back to phoneme alignment")
                await MainActor.run {
                    useCTCAlignment = false
                }
            }
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
                // CORRECT ORDER: Cancel → Clear → Update
                // Buffer contents are speed-dependent and must be cleared BEFORE updating speed
                await chunkBuffer.clearAll()
                await readyQueue?.stopPipeline()

                // CRITICAL: Must await setSpeed BEFORE restarting playback
                // Otherwise playback starts with old speed (race condition)
                await synthesisQueue?.setSpeed(newRate)
                print("[TTSService] ✅ Speed updated in synthesis queue to: \(newRate)")

                // Resume continuation before stopping to prevent leak (safe - resumer prevents double-resume)
                if let resumer = activeResumer {
                    print("[TTSService] ⚠️ Resuming active continuation during speed change")
                    resumer.resume(throwing: CancellationError())
                    activeResumer = nil
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

                    // CORRECT ORDER: Cancel → Clear → Update
                    // Buffer contents are voice-dependent and must be cleared BEFORE creating new queue
                    await chunkBuffer.clearAll()
                    await readyQueue?.stopPipeline()

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

        // Set document source in ready queue (uses callbacks to avoid storing entire document)
        Task { [weak self] in
            guard let self = self else { return }
            await self.readyQueue?.setDocumentSource(
                totalCount: { [weak self] in self?.currentText.count ?? 0 },
                fetchParagraph: { [weak self] index in self?.currentText[safe: index] }
            )
        }

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
        // Resume continuation before pausing to prevent leaks (safe - resumer prevents double-resume)
        if let resumer = activeResumer {
            print("[TTSService] ⚠️ Resuming active continuation during pause()")
            resumer.resume(throwing: CancellationError())
            activeResumer = nil
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
        // Cancel active speak task to stop pre-synthesis and playback
        if let task = activeSpeakTask {
            task.cancel()
            activeSpeakTask = nil
        }

        // CRITICAL: Resume any active continuation to prevent double-resume crash
        // This was missing and caused crashes when skip buttons were pressed during playback
        if let resumer = activeResumer {
            print("[TTSService] ⚠️ Resuming active continuation during stopAudioOnly()")
            resumer.resume(throwing: CancellationError())
            activeResumer = nil
        }

        Task {
            await audioPlayer.stop()
            // Clear chunk buffer (prevents stale pre-synthesized chunks from previous paragraph)
            await chunkBuffer.clearAll()
            // Clear sentence cache for new paragraph
            await synthesisQueue?.clearAll()
            await readyQueue?.stopPipeline()
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

        // Reset preparing state immediately
        isPreparing = false

        // CRITICAL: Resume any active continuation to prevent leaks and double-resume crashes
        if let resumer = activeResumer {
            print("[TTSService] ⚠️ Resuming active continuation during stop() to prevent leak")
            resumer.resume(throwing: CancellationError())
            activeResumer = nil
        }

        // Stop ready queue pipeline (fire-and-forget is OK here because sessionID prevents races)
        Task {
            await readyQueue?.stopPipeline()
        }

        Task {
            await audioPlayer.stop()
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

        // Use ReadyQueue for unified pipeline
        guard let readyQueue = readyQueue else {
            print("[TTSService] ⚠️ ReadyQueue unavailable, falling back to legacy")
            speakParagraphLegacy(at: index)
            return
        }

        let taskID = UUID().uuidString.prefix(8)
        print("[TTSService] 🎬 Starting ReadyQueue task \(taskID) for paragraph \(index)")

        activeSpeakTask = Task {
            defer {
                print("[TTSService] 🏁 Ending ReadyQueue task \(taskID)")
                self.activeSpeakTask = nil
            }

            do {
                // STEP 1: Configure word highlighting setting
                await readyQueue.setWordHighlightingEnabled(wordHighlightingEnabled)

                // STEP 2: Check if first sentence is already buffered (from cross-paragraph lookahead)
                let firstReady = await readyQueue.isReady(paragraphIndex: index, sentenceIndex: 0)

                if firstReady {
                    // Content already buffered - no need to restart pipeline or show loading
                    print("[TTSService] ✅ First sentence already buffered for P\(index)")
                } else {
                    // Show loading indicator and start pipeline
                    await MainActor.run { isPreparing = true }
                    await readyQueue.startFrom(paragraphIndex: index)
                }

                let sentenceCount = await readyQueue.getSentenceCount(forParagraph: index)
                print("[TTSService] 📝 Paragraph \(index) has \(sentenceCount) sentences")

                // Play sentences sequentially
                for sentenceIndex in 0..<sentenceCount {
                    guard !Task.isCancelled else {
                        throw CancellationError()
                    }

                    // Wait for and take sentence atomically
                    if let readySentence = await readyQueue.waitAndTake(
                        paragraphIndex: index,
                        sentenceIndex: sentenceIndex
                    ) {
                        // Hide loading indicator after first sentence
                        if sentenceIndex == 0 {
                            await MainActor.run {
                                isPreparing = false
                            }
                        }

                        // Play the ready sentence
                        try await playReadySentence(readySentence)

                    } else if await readyQueue.wasSkipped(paragraphIndex: index, sentenceIndex: sentenceIndex) {
                        // Empty sentence, skip it
                        if sentenceIndex == 0 {
                            await MainActor.run {
                                isPreparing = false
                            }
                        }
                        print("[TTSService] ⏭️ Skipping empty sentence \(sentenceIndex)")
                        continue
                    } else {
                        // Cancelled, stopped, or timed out - reset isPreparing before throwing
                        await MainActor.run {
                            isPreparing = false
                        }
                        throw CancellationError()
                    }
                }

                // All sentences played
                print("[TTSService] ✅ Paragraph \(index) complete, advancing")
                handleParagraphComplete()

            } catch is CancellationError {
                print("[TTSService] ⏸️ Playback cancelled")
                await MainActor.run {
                    isPreparing = false
                    isPlaying = false
                }
            } catch {
                print("[TTSService] ❌ Playback error: \(error)")
                await MainActor.run {
                    isPreparing = false
                    isPlaying = false
                }
            }
        }
    }

    /// Play a ready sentence (audio + highlighting if available)
    private func playReadySentence(_ sentence: ReadySentence) async throws {
        // IMPORTANT: Stop any existing highlight timer BEFORE changing alignment
        // This prevents the old timer from firing with the new alignment (wrong paragraph)
        stopHighlightTimer()

        // Store alignment for highlighting (if available)
        if let alignment = sentence.alignment {
            currentAlignment = alignment
            minWordIndex = 0
            stuckWordWarningCount.removeAll()
            // Reset highlight tracking for new sentence
            lastHighlightedWordIndex = nil
            lastHighlightChangeTime = 0
        } else {
            currentAlignment = nil
        }

        // Play audio with continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let resumer = ContinuationResumer(continuation)
                activeResumer = resumer

                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    print("[TTSService] 🏁 Sentence playback complete")
                    self?.activeResumer = nil
                    resumer.resume(returning: ())
                }

                // Schedule all chunks
                for chunk in sentence.chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // Start highlight timer only if we have alignment AND highlighting enabled
                if sentence.alignment != nil && wordHighlightingEnabled {
                    startHighlightTimerWithCTCAlignment()
                }

                // Update state
                isPlaying = true
                shouldAutoAdvance = true
            }
        }
    }

    /// Legacy playback method (fallback when ReadyQueue unavailable)
    private func speakParagraphLegacy(at index: Int) {
        // This is the old implementation - copy the existing speakParagraph body here
        // before replacing it, or simply log an error
        print("[TTSService] ⚠️ Legacy playback not implemented - ReadyQueue required")
        isPlaying = false
    }

    /// Play a sentence with chunk-level streaming
    /// FIX: Restructured to perform alignment BEFORE playback for correct highlighting
    private func playSentenceWithChunks(sentence: String, isLast: Bool, sentenceStartOffset: Int = 0) async throws {
        // Capture paragraph index for alignment
        let paragraphIndex = currentProgress.paragraphIndex

        // STEP 1: Synthesize and accumulate ALL chunks first (don't play yet)
        let accumulatingDelegate = AccumulatingChunkDelegate()

        do {
            _ = try await synthesisQueue?.streamSentence(sentence, delegate: accumulatingDelegate)
        } catch {
            print("[TTSService] ❌ Synthesis error: \(error)")
            throw error
        }

        let chunks = await accumulatingDelegate.getChunks()
        let combinedAudio = await accumulatingDelegate.getCombinedAudio()

        guard !chunks.isEmpty else {
            print("[TTSService] ⏭️ Skipping empty synthesized sentence")
            return
        }

        print("[TTSService] 📦 Synthesized \(chunks.count) chunks for sentence")

        // STEP 2: Perform CTC alignment BEFORE starting playback
        // NOTE: combinedAudio is raw Float32 samples from streaming chunks
        if useCTCAlignment {
            print("[TTSService] 🎯 Performing CTC alignment BEFORE playback starts (offset=\(sentenceStartOffset))")
            await performCTCAlignmentSync(
                sentence: sentence,
                audioData: combinedAudio,
                paragraphIndex: paragraphIndex,
                sentenceStartOffset: sentenceStartOffset,
                isFloat32: true  // Streaming chunks are raw Float32
            )
        }

        // STEP 3: NOW start playback with all chunks ready
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // Wrap continuation in thread-safe resumer to prevent double-resume crashes
                let resumer = ContinuationResumer(continuation)
                activeResumer = resumer

                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    // Sentence finished playing
                    print("[TTSService] 🏁 Sentence playback complete")
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                // Schedule all accumulated chunks immediately
                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // FIX: Start highlight timer IMMEDIATELY when playback starts
                if self.currentAlignment != nil {
                    self.startHighlightTimerWithCTCAlignment()
                }

                // Update playback state
                isPlaying = true
                shouldAutoAdvance = true
            }
        }
    }

    /// Perform CTC forced alignment synchronously (for use BEFORE playback starts)
    /// This version stores the alignment but does NOT start the highlight timer
    /// - Parameters:
    ///   - sentence: The sentence text that was synthesized
    ///   - audioData: Raw audio data from synthesis
    ///   - paragraphIndex: Current paragraph index
    ///   - sentenceStartOffset: Character offset where this sentence starts in the paragraph
    ///   - isFloat32: If true, audioData is raw Float32 samples; if false, it's WAV format with Int16 samples
    private func performCTCAlignmentSync(sentence: String, audioData: Data, paragraphIndex: Int, sentenceStartOffset: Int = 0, isFloat32: Bool = false) async {
        guard !audioData.isEmpty else {
            print("[TTSService] ⚠️ CTC alignment skipped - no audio data")
            return
        }

        // Extract samples based on format
        // Streaming chunks are raw Float32 (4 bytes per sample)
        // WAV data has 44-byte header + Int16 samples (2 bytes per sample)
        let samples: [Float]
        if isFloat32 {
            samples = extractSamplesFromFloat32(audioData)
        } else {
            samples = extractSamples(from: audioData)
        }
        guard !samples.isEmpty else {
            print("[TTSService] ⚠️ CTC alignment skipped - no samples extracted")
            return
        }

        print("[TTSService] 🎯 CTC alignment (sync) for '\(sentence.prefix(30))...' (\(samples.count) samples, format=\(isFloat32 ? "Float32" : "WAV"), offset=\(sentenceStartOffset))")

        let alignmentStartTime = CFAbsoluteTimeGetCurrent()
        do {
            let alignment = try await ctcAligner.align(
                audioSamples: samples,
                sampleRate: 22050,  // Piper TTS output rate
                transcript: sentence,
                paragraphIndex: paragraphIndex,
                sentenceStartOffset: sentenceStartOffset  // Pass offset to adjust rangeLocation
            )

            let alignmentElapsed = CFAbsoluteTimeGetCurrent() - alignmentStartTime
            await MainActor.run {
                // Store alignment for word highlighting
                currentAlignment = alignment
                print("[TTSService] ✅ CTC alignment (sync) complete: \(alignment.wordTimings.count) words, \(String(format: "%.2f", alignment.totalDuration))s audio, took \(String(format: "%.3f", alignmentElapsed))s")

                // Reset word tracking for new alignment
                minWordIndex = 0
                stuckWordWarningCount.removeAll()

                // NOTE: Timer is NOT started here - caller starts it after playback begins
            }
        } catch {
            print("[TTSService] ⚠️ CTC alignment failed: \(error)")
        }
    }

    /// Perform CTC forced alignment on synthesized audio (legacy async version)
    /// NOTE: This version starts the timer after alignment, causing a race condition
    /// Prefer performCTCAlignmentSync() called BEFORE playback starts
    /// - Parameters:
    ///   - sentence: The sentence text that was synthesized
    ///   - audioData: Raw audio data from synthesis
    ///   - paragraphIndex: Current paragraph index
    private func performCTCAlignment(sentence: String, audioData: Data, paragraphIndex: Int) async {
        guard !audioData.isEmpty else {
            print("[TTSService] ⚠️ CTC alignment skipped - no audio data")
            return
        }

        let samples = extractSamples(from: audioData)
        guard !samples.isEmpty else {
            print("[TTSService] ⚠️ CTC alignment skipped - no samples extracted")
            return
        }

        // DEBUG: Capture current playback time BEFORE alignment starts
        let preAlignTime = await MainActor.run { audioPlayer.currentTime }
        print("[TTSService] 🎯 Starting CTC alignment for '\(sentence.prefix(30))...' (\(samples.count) samples)")
        print("[TTSService] 🕐 DEBUG: audioPlayer.currentTime at alignment START = \(String(format: "%.3f", preAlignTime))s")

        do {
            let alignment = try await ctcAligner.align(
                audioSamples: samples,
                sampleRate: 22050,  // Piper TTS output rate
                transcript: sentence,
                paragraphIndex: paragraphIndex
            )

            await MainActor.run {
                // DEBUG: Log timing when alignment completes
                let postAlignTime = audioPlayer.currentTime
                print("[TTSService] 🕐 DEBUG: audioPlayer.currentTime at alignment END = \(String(format: "%.3f", postAlignTime))s")
                print("[TTSService] 🕐 DEBUG: Alignment took \(String(format: "%.3f", postAlignTime - preAlignTime))s of playback time")

                // DEBUG: Log word timings
                print("[TTSService] 📊 DEBUG: Word timings from CTC alignment:")
                for (i, word) in alignment.wordTimings.prefix(5).enumerated() {
                    print("[TTSService]   Word[\(i)]: '\(word.text)' @ \(String(format: "%.3f", word.startTime))-\(String(format: "%.3f", word.endTime))s, range=\(word.rangeLocation)...\(word.rangeLocation + word.rangeLength)")
                }
                if alignment.wordTimings.count > 5 {
                    print("[TTSService]   ... and \(alignment.wordTimings.count - 5) more words")
                }

                // Store alignment for word highlighting
                currentAlignment = alignment
                print("[TTSService] ✅ CTC alignment complete: \(alignment.wordTimings.count) words, \(String(format: "%.2f", alignment.totalDuration))s")

                // Reset word tracking for new alignment
                minWordIndex = 0
                stuckWordWarningCount.removeAll()

                // Re-enable highlight timer now that we have alignment
                startHighlightTimerWithCTCAlignment()
            }
        } catch {
            print("[TTSService] ⚠️ CTC alignment failed: \(error)")
        }
    }

    /// Start highlight timer using CTC alignment data
    private func startHighlightTimerWithCTCAlignment() {
        stopHighlightTimer()

        guard let alignment = currentAlignment else {
            print("[TTSService] ⏸️ No alignment available for highlighting")
            return
        }

        // DEBUG: Log timer start time
        let startTime = audioPlayer.currentTime
        print("[TTSService] 🎬 Starting CTC word highlighting timer at audioPlayer.currentTime = \(String(format: "%.3f", startTime))s")
        print("[TTSService] 🎬 DEBUG: First word starts at \(String(format: "%.3f", alignment.wordTimings.first?.startTime ?? -1))s")

        // Use 60 FPS timer for smooth word highlighting
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateHighlightFromTime()
        }
        print("[TTSService] 🎬 Started CTC word highlighting timer")
    }

    /// Start pre-synthesis for a sentence in the background
    /// Returns Task that can be cancelled
    private func startPreSynthesis(sentence: String, index: Int) -> Task<Void, Never> {
        return Task {
            // Check cancellation before expensive work
            guard !Task.isCancelled else {
                print("[TTSService] 🛑 Pre-synthesis cancelled before starting for sentence \(index)")
                return
            }

            guard let queue = await self.synthesisQueue else {
                return
            }

            print("[TTSService] 🔮 Pre-synthesizing sentence \(index): '\(sentence.prefix(50))...'")

            do {
                let delegate = await BufferingChunkDelegate(
                    buffer: chunkBuffer,
                    sentenceIndex: index
                )

                // Check again after delegate creation
                guard !Task.isCancelled else {
                    print("[TTSService] 🛑 Pre-synthesis cancelled during setup for sentence \(index)")
                    return
                }

                // Synthesize with streaming delegate
                _ = try await queue.streamSentence(sentence, delegate: delegate)

                // Check before waiting for completion
                guard !Task.isCancelled else {
                    print("[TTSService] 🛑 Pre-synthesis cancelled after synthesis for sentence \(index)")
                    return
                }

                // CRITICAL: Wait for all chunk additions to complete!
                await delegate.waitForCompletion()

                // Now it's safe to mark complete
                await chunkBuffer.markComplete(forSentence: index)

                print("[TTSService] ✅ Pre-synthesis complete for sentence \(index)")
            } catch is CancellationError {
                print("[TTSService] 🛑 Pre-synthesis cancelled for sentence \(index)")
            } catch {
                print("[TTSService] ⚠️ Pre-synthesis failed for sentence \(index): \(error)")
            }
        }
    }

    /// Play buffered chunks that were pre-synthesized
    /// - Parameters:
    ///   - chunks: Array of audio data chunks
    ///   - sentence: The sentence text for CTC alignment
    ///   - sentenceStartOffset: Character offset where this sentence starts in the paragraph
    private func playBufferedChunks(_ chunks: [Data], sentence: String, sentenceStartOffset: Int = 0) async throws {
        // Handle empty sentences (e.g., only punctuation)
        guard !chunks.isEmpty else {
            print("[TTSService] ⏭️ Skipping empty buffered sentence")
            return
        }

        // Capture paragraph index for alignment
        let paragraphIndex = currentProgress.paragraphIndex

        // Combine chunks for CTC alignment
        let combinedAudio = chunks.reduce(Data()) { $0 + $1 }

        // FIX: Perform CTC alignment BEFORE starting playback to avoid race condition
        // This ensures highlight timer starts at time 0 when playback starts
        // NOTE: Buffered chunks are raw Float32 samples from streaming synthesis
        if useCTCAlignment {
            print("[TTSService] 🎯 Performing CTC alignment BEFORE playback starts (offset=\(sentenceStartOffset))")
            await performCTCAlignmentSync(
                sentence: sentence,
                audioData: combinedAudio,
                paragraphIndex: paragraphIndex,
                sentenceStartOffset: sentenceStartOffset,
                isFloat32: true  // Buffered chunks are raw Float32
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // Wrap continuation in thread-safe resumer to prevent double-resume crashes
                let resumer = ContinuationResumer(continuation)
                activeResumer = resumer

                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    print("[TTSService] 🏁 Buffered playback complete")
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                // Schedule all buffered chunks immediately
                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // FIX: Start highlight timer IMMEDIATELY when playback starts (alignment already done)
                if self.currentAlignment != nil {
                    self.startHighlightTimerWithCTCAlignment()
                }

                // Update playback state
                isPlaying = true
                shouldAutoAdvance = true
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

    /// Extract Float samples from raw audio Data (16-bit PCM WAV format)
    /// Used for CTC forced alignment which requires normalized float samples
    /// - Parameter audioData: Raw audio bytes (may include WAV header)
    /// - Returns: Array of Float samples normalized to [-1, 1]
    private func extractSamples(from audioData: Data) -> [Float] {
        // Skip WAV header if present (44 bytes)
        let offset = audioData.count > 44 ? 44 : 0
        let pcmData = audioData.subdata(in: offset..<audioData.count)

        // Convert 16-bit PCM samples to Float [-1, 1]
        let int16Samples = pcmData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }
        return int16Samples.map { Float($0) / Float(Int16.max) }
    }

    /// Extract Float samples from raw Float32 streaming chunks
    /// Streaming chunks from sherpa-onnx are raw Float32 samples (already normalized [-1, 1])
    /// - Parameter audioData: Raw Float32 bytes from streaming synthesis
    /// - Returns: Array of Float samples (already normalized)
    private func extractSamplesFromFloat32(_ audioData: Data) -> [Float] {
        // Streaming chunks are raw Float32 (4 bytes per sample), no header
        return audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
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
            // Note: speakParagraph will call readyQueue.startFrom() - no duplicate call needed
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
    /// DEBUG counter to throttle logging
    private static var highlightLogCounter = 0

    private func updateHighlightFromTime() {
        guard let alignment = currentAlignment else { return }

        // IMPORTANT: Ensure alignment belongs to the current paragraph
        // This prevents applying wrong paragraph's alignment after paragraph switch
        guard alignment.paragraphIndex == currentProgress.paragraphIndex else {
            // Alignment is stale - will be updated when new sentence starts
            return
        }

        // Get current playback time from audio player
        Task { @MainActor in
            let currentTime = audioPlayer.currentTime

            // DEBUG: Log first few calls and then every 60th call (1 per second at 60fps)
            TTSService.highlightLogCounter += 1
            let shouldLog = TTSService.highlightLogCounter <= 5 || TTSService.highlightLogCounter % 60 == 0

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

                // DEBUG: Log word selection
                if shouldLog || wordChanged {
                    print("[TTSService] 🔍 DEBUG updateHighlight: time=\(String(format: "%.3f", currentTime))s → word[\(effectiveTiming.wordIndex)]='\(effectiveTiming.text)' (start=\(String(format: "%.3f", effectiveTiming.startTime))s, changed=\(wordChanged))")
                }

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
                // DEBUG: Log the actual range being applied
                if shouldLog || wordChanged {
                    let rangeStart = paragraphText.distance(from: paragraphText.startIndex, to: effectiveRange.lowerBound)
                    let rangeEnd = paragraphText.distance(from: paragraphText.startIndex, to: effectiveRange.upperBound)
                    let highlightedText = String(paragraphText[effectiveRange])
                    print("[TTSService] 🎯 HIGHLIGHT: applying range \(rangeStart)..<\(rangeEnd) = '\(highlightedText)' to P\(currentProgress.paragraphIndex)")
                }
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

/// Delegate that receives audio chunks, schedules them on audio player, and accumulates for alignment
private class ChunkStreamDelegate: SynthesisStreamDelegate {
    private weak var audioPlayer: StreamingAudioPlayer?

    // Accumulated audio data for alignment
    @MainActor private var accumulatedAudio = Data()

    init(audioPlayer: StreamingAudioPlayer) {
        self.audioPlayer = audioPlayer
    }

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        Task { @MainActor in
            // Schedule chunk immediately on audio player
            audioPlayer?.scheduleChunk(chunk)
            // Also accumulate for alignment
            accumulatedAudio.append(chunk)
        }
        return true // Continue synthesis
    }

    /// Get accumulated audio data for alignment
    @MainActor func getAccumulatedAudio() -> Data {
        return accumulatedAudio
    }
}

// MARK: - Accumulating Chunk Delegate

/// Delegate that accumulates audio chunks WITHOUT scheduling them
/// Used when we need to complete synthesis and alignment BEFORE starting playback
private class AccumulatingChunkDelegate: SynthesisStreamDelegate {
    // Store chunks as array for later scheduling
    private var chunks: [Data] = []
    private var combinedAudio = Data()
    private let lock = NSLock()

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Just accumulate - don't schedule
        chunks.append(chunk)
        combinedAudio.append(chunk)
        return true // Continue synthesis
    }

    /// Get accumulated chunks (thread-safe)
    func getChunks() async -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }

    /// Get combined audio data (thread-safe)
    func getCombinedAudio() async -> Data {
        lock.lock()
        defer { lock.unlock() }
        return combinedAudio
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
