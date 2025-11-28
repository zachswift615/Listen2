
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
        cont?.resume(returning: value)
    }

    /// Resume with error. Safe to call multiple times - only first call takes effect.
    func resume(throwing error: E) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()  // Unlock BEFORE calling resume to prevent deadlocks
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
    @AppStorage("highlightLevel") private var highlightLevelRaw: String = ""

    /// Track previous highlighting setting to detect changes
    private var previousHighlightLevel: HighlightLevel = .sentence

    /// User's selected highlight level (defaults to device-recommended if not set)
    private var highlightLevel: HighlightLevel {
        if highlightLevelRaw.isEmpty {
            return DeviceCapabilityService.recommendedHighlightLevel
        }
        return HighlightLevel(rawValue: highlightLevelRaw) ?? DeviceCapabilityService.recommendedHighlightLevel
    }

    /// Effective highlight level - just returns the user's choice (or device-recommended default)
    var effectiveHighlightLevel: HighlightLevel {
        return highlightLevel
    }

    /// Whether CTC alignment should run (only for word-level highlighting)
    private var shouldRunCTCAlignment: Bool {
        effectiveHighlightLevel == .word
    }

    // MARK: - Published Properties

    @Published private(set) var currentProgress: ReadingProgress = .initial
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var isInitializing: Bool = true
    @Published private(set) var isPreparing: Bool = false

    /// Current sentence range for sentence-level highlighting (paragraph-relative offsets)
    @Published private(set) var currentSentenceLocation: Int?
    @Published private(set) var currentSentenceLength: Int?

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
    private var currentPiperVoiceID: String? // Track current Piper voice to avoid unnecessary reinit
    private var currentTitle: String = "Document"
    private var shouldAutoAdvance = true // Track whether to auto-advance
    private var wordMap: DocumentWordMap? // Word map for precise highlighting
    private var currentDocumentID: UUID? // Current document ID for alignment caching

    // Alignment services
    private let alignmentCache = AlignmentCache()
    private let ctcAligner = CTCForcedAligner()

    // Feature flag: use CTC forced alignment for word highlighting
    private var useCTCAlignment = true

    // Word highlighting for Piper playback
    /// Event-driven word highlighting scheduler
    private var wordScheduler: WordHighlightScheduler?
    /// Current alignment for pause/resume (scheduler needs this to restart)
    private var currentSchedulerAlignment: AlignmentResult?
    private let wordHighlighter = WordHighlighter()

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
            } catch {
                // Failed to clear cache - continue anyway
            }
        }

        // Initialize Piper TTS (alignment service is lazy-loaded when needed)
        Task {
            await initializePiperProvider()
            // NOTE: CTC alignment service is now lazy-loaded when word highlighting is first used
            // This saves ~800MB at app startup
        }

        // Setup now playing manager
        setupNowPlayingManager()

        // Setup audio session observers
        setupAudioSessionObservers()

        // Track initial highlighting setting
        previousHighlightLevel = highlightLevel
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
            self.currentPiperVoiceID = bundledVoice.id  // Track initial voice

            // Initialize synthesis queue with provider
            self.synthesisQueue = SynthesisQueue(
                provider: piperProvider
            )

            // Initialize ready queue with dependencies
            self.readyQueue = ReadyQueue(synthesisQueue: self.synthesisQueue!, ctcAligner: self.ctcAligner)
        } catch {
            self.provider = nil
            self.synthesisQueue = nil
        }

        await MainActor.run {
            isInitializing = false
        }
    }

    private func initializeAlignmentService() async {
        // Initialize CTC Forced Aligner (async)
        if useCTCAlignment {
            do {
                try await ctcAligner.initialize()
            } catch {
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
            // Error activating audio session - audio will still work with default settings
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

        // Update now playing info with new rate
        nowPlayingManager.updatePlaybackRate(newRate)

        // Apply rate to audio player immediately (affects currently playing audio)
        audioPlayer.setRate(newRate)

        // If we were playing, restart current paragraph with new rate
        // NOTE: We don't call stop() because it resets progress to .initial (paragraph 0)
        // Instead, we just stop audio and restart from current position
        if wasPlaying {
            // Cancel active task FIRST - this sets Task.isCancelled which will break the sentence loop
            if let task = activeSpeakTask {
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

                // Resume continuation before stopping to prevent leak (safe - resumer prevents double-resume)
                if let resumer = activeResumer {
                    resumer.resume(throwing: CancellationError())
                    activeResumer = nil
                }

                await audioPlayer.stop()
                wordHighlighter.stop()
                fallbackSynthesizer.stopSpeaking(at: .immediate)
                stopWordScheduler()

                // Now speed is set, restart playback
                speakParagraph(at: currentIndex)
            }
        } else {
            // Not playing, just update speed for next playback
            Task {
                await synthesisQueue?.setSpeed(newRate)
            }
        }
    }

    func setVoice(_ voice: AVVoice) {
        if voice.isPiperVoice {
            // Validate voice ID format
            guard voice.id.hasPrefix("piper:") else {
                return
            }

            // Extract voice ID from "piper:en_US-lessac-medium" format
            let voiceID = String(voice.id.dropFirst("piper:".count))

            // Skip reinitialization if voice hasn't changed
            if voiceID == currentPiperVoiceID {
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
                    currentPiperVoiceID = voiceID  // Track current voice to avoid unnecessary reinit

                    // CORRECT ORDER: Cancel → Clear → Update
                    // Buffer contents are voice-dependent and must be cleared BEFORE creating new queue
                    await chunkBuffer.clearAll()
                    await readyQueue?.stopPipeline()

                    // Update synthesis queue with new provider
                    synthesisQueue = SynthesisQueue(
                        provider: piperProvider
                    )

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
                        speakParagraph(at: currentIndex)
                    }
                } catch {
                    // Failed to switch voice - continue with current voice
                }
            }
        } else {
            // iOS voice - set for fallback
            currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
        }
    }

    // MARK: - Playback Control

    func startReading(paragraphs: [String], from index: Int, title: String = "Document", wordMap: DocumentWordMap? = nil, documentID: UUID? = nil) {
        // Check if highlighting setting changed - invalidate cache if so
        if highlightLevel != previousHighlightLevel {
            Task {
                await readyQueue?.stopPipeline()
            }
            previousHighlightLevel = highlightLevel
        }

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
        // DO NOT throw CancellationError to continuation during pause!
        // The continuation should stay active so the task can resume properly.
        // When audio resumes, it will eventually complete and resume the continuation normally.

        // Stop word scheduler - scheduled events continue firing even when playerNode pauses
        // which causes incorrect highlighting
        stopWordScheduler()

        Task { @MainActor in
            audioPlayer.pause()
            wordHighlighter.pause()
        }
        fallbackSynthesizer.pauseSpeaking(at: .word)
        isPlaying = false
        nowPlayingManager.updatePlaybackState(isPlaying: false)
    }

    func resume() {
        // Restart word scheduler if we have alignment data and using word-level highlighting
        // (scheduler was stopped on pause because scheduled events continue while audio is paused)
        if let alignment = currentSchedulerAlignment, effectiveHighlightLevel == .word {
            setupWordScheduler(alignment: alignment)
        }

        Task { @MainActor in
            audioPlayer.resume()
            wordHighlighter.resume()
        }
        fallbackSynthesizer.continueSpeaking()
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
        stopWordScheduler()
        isPlaying = false

        // DON'T clear currentText, wordMap, etc. - keep document loaded
        // Just reset playback state
        currentProgress = ReadingProgress(
            paragraphIndex: currentProgress.paragraphIndex,
            wordRange: nil,
            isPlaying: false
        )
    }

    func stop() {
        // Cancel active speak task first (this sets Task.isCancelled)
        if let task = activeSpeakTask {
            task.cancel()
            activeSpeakTask = nil
        }

        // Reset preparing state immediately
        isPreparing = false

        // CRITICAL: Resume any active continuation to prevent leaks and double-resume crashes
        if let resumer = activeResumer {
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
        stopWordScheduler()
        currentSchedulerAlignment = nil  // Clear alignment since we're stopping completely
        isPlaying = false

        // Reset state to prevent stale content when switching documents
        currentText = []
        currentProgress = .initial
        wordMap = nil
        currentDocumentID = nil

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
            existingTask.cancel()
        }

        // Use ReadyQueue for unified pipeline
        guard let readyQueue = readyQueue else {
            speakParagraphLegacy(at: index)
            return
        }

        activeSpeakTask = Task {
            defer {
                self.activeSpeakTask = nil
            }

            do {
                // STEP 1: Configure word highlighting setting (only run CTC for word-level)
                await readyQueue.setWordHighlightingEnabled(shouldRunCTCAlignment)

                // STEP 2: Check if first sentence is already buffered (from cross-paragraph lookahead)
                let firstReady = await readyQueue.isReady(paragraphIndex: index, sentenceIndex: 0)

                if firstReady {
                    // Content already buffered - no need to restart pipeline or show loading
                } else {
                    // Show loading indicator and start pipeline
                    await MainActor.run { isPreparing = true }
                    await readyQueue.startFrom(paragraphIndex: index)
                }

                let sentenceCount = await readyQueue.getSentenceCount(forParagraph: index)

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
                handleParagraphComplete()

            } catch is CancellationError {
                await MainActor.run {
                    isPreparing = false
                    isPlaying = false
                }
            } catch {
                await MainActor.run {
                    isPreparing = false
                    isPlaying = false
                }
            }
        }
    }

    /// Play a ready sentence (audio + highlighting if available)
    private func playReadySentence(_ sentence: ReadySentence) async throws {
        // IMPORTANT: Stop any existing word scheduler BEFORE starting new playback
        // This prevents the old scheduler from firing with the new alignment (wrong paragraph)
        stopWordScheduler()

        // Play audio with continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let resumer = ContinuationResumer(continuation)
                activeResumer = resumer

                // Start streaming session
                audioPlayer.startStreaming { [weak self] in
                    self?.activeResumer = nil
                    resumer.resume(returning: ())
                }

                // Schedule all chunks
                for chunk in sentence.chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // Handle highlighting based on effective level
                switch self.effectiveHighlightLevel {
                case .word:
                    // Word-level: start word scheduler if we have alignment
                    if let alignment = sentence.alignment {
                        self.setupWordScheduler(alignment: alignment)
                    }
                    self.currentSentenceLocation = nil
                    self.currentSentenceLength = nil
                case .sentence:
                    // Sentence-level: set the current sentence range
                    self.currentSentenceLocation = sentence.sentenceOffset
                    self.currentSentenceLength = sentence.text.count
                case .paragraph:
                    // Paragraph-level: handled in ReaderView (whole paragraph highlighted)
                    self.currentSentenceLocation = nil
                    self.currentSentenceLength = nil
                case .off:
                    // No highlighting
                    self.currentSentenceLocation = nil
                    self.currentSentenceLength = nil
                }

                // Update state
                isPlaying = true
                shouldAutoAdvance = true
            }
        }
    }

    /// Legacy playback method (fallback when ReadyQueue unavailable)
    private func speakParagraphLegacy(at index: Int) {
        // Legacy playback not implemented - ReadyQueue required
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
            throw error
        }

        let chunks = await accumulatingDelegate.getChunks()
        let combinedAudio = await accumulatingDelegate.getCombinedAudio()

        guard !chunks.isEmpty else {
            return
        }

        // STEP 2: Perform CTC alignment BEFORE starting playback
        // NOTE: combinedAudio is raw Float32 samples from streaming chunks
        if useCTCAlignment {
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
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                // Schedule all accumulated chunks immediately
                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

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
            return
        }

        do {
            _ = try await ctcAligner.align(
                audioSamples: samples,
                sampleRate: 22050,  // Piper TTS output rate
                transcript: sentence,
                paragraphIndex: paragraphIndex,
                sentenceStartOffset: sentenceStartOffset  // Pass offset to adjust rangeLocation
            )
            // NOTE: Alignment result is not used - legacy path; new path uses WordHighlightScheduler
        } catch {
            // CTC alignment failed - continue without highlighting
        }
    }

    /// Start pre-synthesis for a sentence in the background
    /// Returns Task that can be cancelled
    private func startPreSynthesis(sentence: String, index: Int) -> Task<Void, Never> {
        return Task {
            // Check cancellation before expensive work
            guard !Task.isCancelled else {
                return
            }

            guard let queue = await self.synthesisQueue else {
                return
            }

            do {
                let delegate = await BufferingChunkDelegate(
                    buffer: chunkBuffer,
                    sentenceIndex: index
                )

                // Check again after delegate creation
                guard !Task.isCancelled else {
                    return
                }

                // Synthesize with streaming delegate
                _ = try await queue.streamSentence(sentence, delegate: delegate)

                // Check before waiting for completion
                guard !Task.isCancelled else {
                    return
                }

                // CRITICAL: Wait for all chunk additions to complete!
                await delegate.waitForCompletion()

                // Now it's safe to mark complete
                await chunkBuffer.markComplete(forSentence: index)
            } catch is CancellationError {
                // Pre-synthesis cancelled
            } catch {
                // Pre-synthesis failed
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
                    self?.activeResumer = nil
                    resumer.resume(returning: ())  // Safe - won't double-resume
                }

                // Schedule all buffered chunks immediately
                for chunk in chunks {
                    audioPlayer.scheduleChunk(chunk)
                }

                // Mark scheduling complete
                audioPlayer.finishScheduling()

                // Update playback state
                isPlaying = true
                shouldAutoAdvance = true
            }
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
        // CRITICAL: Stop word scheduler BEFORE advancing
        // This prevents the old paragraph's wordRange from being applied to the new paragraph
        stopWordScheduler()

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

    // MARK: - Event-Driven Word Highlighting

    /// Set up word highlighting scheduler for a sentence
    private func setupWordScheduler(alignment: AlignmentResult) {
        // Tear down any existing scheduler
        wordScheduler?.stop()

        // Store alignment for pause/resume
        currentSchedulerAlignment = alignment

        // Create new scheduler (no longer needs playerNode)
        let scheduler = WordHighlightScheduler(alignment: alignment)

        scheduler.onWordChange = { [weak self] timing in
            self?.handleScheduledWordChange(timing)
        }

        scheduler.start()
        wordScheduler = scheduler
    }

    /// Handle word change from scheduler
    private func handleScheduledWordChange(_ timing: AlignmentResult.WordTiming) {
        guard let paragraphText = currentText[safe: currentProgress.paragraphIndex],
              let range = timing.stringRange(in: paragraphText) else {
            return
        }

        // Update published progress - UI reacts automatically
        currentProgress = ReadingProgress(
            paragraphIndex: currentProgress.paragraphIndex,
            wordRange: range,
            isPlaying: true
        )
    }

    /// Stop word scheduler
    private func stopWordScheduler() {
        wordScheduler?.stop()
        wordScheduler = nil
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
