# Ready Queue Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate gaps between paragraphs by treating synthesis + CTC alignment as one atomic unit, with a 5-sentence lookahead buffer that spans paragraph boundaries. Include a settings toggle to enable/disable word highlighting.

**Architecture:** Create a `ReadyQueue` actor that processes sentences through a pipeline (synthesis → alignment) and buffers up to 5 ready sentences. The pipeline continues across paragraph boundaries using a **sliding window of 5 paragraphs** for memory efficiency - only paragraphs near the current playback position are kept in memory. Playback only starts when a sentence is fully ready (both audio chunks AND alignment when enabled). As sentences are consumed, the pipeline refills the buffer and slides the paragraph window forward. When word highlighting is disabled, skip alignment entirely for faster processing.

**Tech Stack:** Swift actors, AVAudioEngine (existing), ONNX Runtime for CTC alignment (existing), @AppStorage for settings

**Code Review Notes (v4 - FINAL - all issues addressed):**
- ✅ Fixed file paths (added extra `/Listen2` directory level)
- ✅ Added `nonisolated` to PipelineChunkDelegate (matches existing delegates)
- ✅ Added `@unchecked Sendable` and `final` to PipelineChunkDelegate
- ✅ Added 30-second timeout to `waitAndTake` to prevent infinite loops
- ✅ Fixed `isPreparing` stuck state (reset before throwing in else clause)
- ✅ Added defer pattern to clear `activeSpeakTask`
- ✅ Fixed method name references (speakParagraph, not speakParagraphWithStreaming)
- ✅ Cross-paragraph lookahead with **sliding window** (memory efficient)
- ✅ Buffer refill on consumption with `preserveBuffer` support
- ✅ Use returned Data from streamSentence (avoid redundant computation)
- ✅ Configurable constants for buffer limits
- ✅ Evict old paragraphs when window slides forward
- ✅ **v4:** Made `AlignmentResult` and `WordTiming` Sendable (Task 0)
- ✅ **v4:** Added `nonisolated` to `getChunks()` for consistency
- ✅ **v4:** Simplified ReaderView to use `viewModel.ttsService.isPreparing`
- ✅ **v4:** Added `pipelineIdleIntervalNanos` constant

---

## Task 0: Make AlignmentResult Sendable (Pre-requisite)

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift`

**Why:** `ReadySentence` is marked `Sendable` but contains `AlignmentResult?`. For Swift concurrency correctness, `AlignmentResult` and its nested `WordTiming` must also be `Sendable`.

**Step 1: Add Sendable conformance to AlignmentResult**

Find the struct declaration (around line 11):
```swift
struct AlignmentResult: Codable, Equatable {
```

Change to:
```swift
struct AlignmentResult: Codable, Equatable, Sendable {
```

**Step 2: Add Sendable conformance to WordTiming**

Find the WordTiming struct (around line 20):
```swift
struct WordTiming: Codable, Equatable {
```

Change to:
```swift
struct WordTiming: Codable, Equatable, Sendable {
```

**Step 3: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift
git commit -m "feat: add Sendable conformance to AlignmentResult for concurrency safety"
```

---

## Task 1: Create ReadySentence Model

**Files:**
- Create: `Listen2/Listen2/Listen2/Listen2/Services/TTS/ReadySentence.swift`

**Step 1: Create the model file**

```swift
//
//  ReadySentence.swift
//  Listen2
//
//  Model for a fully-processed sentence ready for playback
//

import Foundation

/// A sentence that has completed both synthesis AND alignment (when enabled)
/// and is ready for immediate playback
struct ReadySentence: Sendable {
    /// Unique key for this sentence
    let key: SentenceKey

    /// Audio chunks (raw Float32 samples from streaming synthesis)
    let chunks: [Data]

    /// CTC forced alignment result with word timings (nil if highlighting disabled)
    let alignment: AlignmentResult?

    /// Original sentence text
    let text: String

    /// Character offset where this sentence starts in the paragraph
    let sentenceOffset: Int

    /// Combined audio data (computed from chunks)
    var combinedAudio: Data {
        chunks.reduce(Data()) { $0 + $1 }
    }

    /// Total audio duration in seconds (from alignment or estimated)
    var audioDuration: TimeInterval {
        alignment?.totalDuration ?? estimatedDuration
    }

    /// Estimated duration based on audio samples
    private var estimatedDuration: TimeInterval {
        let totalSamples = chunks.reduce(0) { $0 + $1.count / MemoryLayout<Float>.size }
        return TimeInterval(totalSamples) / Double(ReadyQueueConstants.sampleRate)
    }
}

/// Key for identifying a sentence in the pipeline
struct SentenceKey: Hashable, CustomStringConvertible, Sendable {
    let paragraphIndex: Int
    let sentenceIndex: Int

    var description: String {
        "P\(paragraphIndex)S\(sentenceIndex)"
    }
}

/// Configurable constants for buffer limits - tune these as needed
enum ReadyQueueConstants {
    /// Maximum sentences to buffer ahead
    static let maxSentenceLookahead: Int = 5

    /// Maximum paragraphs to keep in sliding window
    static let maxParagraphWindow: Int = 5

    /// Maximum buffer size in bytes (~10MB)
    static let maxBufferBytes: Int = 10 * 1024 * 1024

    /// Maximum wait time for a sentence (30 seconds)
    static let maxWaitIterations: Int = 600

    /// Wait interval in nanoseconds (50ms)
    static let waitIntervalNanos: UInt64 = 50_000_000

    /// Pipeline idle sleep interval in nanoseconds (100ms)
    static let pipelineIdleIntervalNanos: UInt64 = 100_000_000

    /// Piper TTS sample rate
    static let sampleRate: Int = 22050
}
```

**Step 2: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/ReadySentence.swift
git commit -m "feat: add ReadySentence model and ReadyQueueConstants"
```

---

## Task 2: Create ReadyQueue Actor with Sliding Window

**Files:**
- Create: `Listen2/Listen2/Listen2/Listen2/Services/TTS/ReadyQueue.swift`

**Step 1: Create the actor file**

```swift
//
//  ReadyQueue.swift
//  Listen2
//
//  Manages the unified synthesis + alignment pipeline with lookahead buffering.
//  Uses a sliding window of paragraphs for memory efficiency.
//  Spans paragraph boundaries - continues processing into next paragraph automatically.
//

import Foundation

/// Actor managing the sentence processing pipeline
/// Ensures sentences are only "ready" when both synthesis AND alignment complete
/// Uses sliding window to limit memory usage for large documents
actor ReadyQueue {

    // MARK: - Dependencies

    private let synthesisQueue: SynthesisQueue
    private let ctcAligner: CTCForcedAligner

    /// Callback to fetch paragraph text on-demand (avoids storing entire document)
    private var fetchParagraph: ((Int) -> String?)?
    private var totalParagraphCount: (() -> Int)?

    // MARK: - Sliding Window State

    /// Sliding window of paragraph text (max `maxParagraphWindow` paragraphs)
    private var paragraphWindow: [Int: String] = [:]

    /// Pre-split sentences for paragraphs in window (evicted with paragraph)
    private var paragraphSentences: [Int: [(text: String, offset: Int)]] = [:]

    // MARK: - Buffer State

    /// Ready sentences: fully processed and waiting for playback
    private var ready: [SentenceKey: ReadySentence] = [:]

    /// Sentences that were skipped (empty/whitespace only)
    private var skipped: Set<SentenceKey> = []

    /// Keys currently being processed (to avoid duplicate work)
    private var processing: Set<SentenceKey> = []

    /// Current buffer size in bytes
    private var currentBufferBytes: Int = 0

    // MARK: - Position Tracking

    /// Current playback position (used for window management)
    private var currentParagraphIndex: Int = 0
    private var currentSentenceIndex: Int = 0

    /// Next position to process in pipeline
    private var nextParagraphToProcess: Int = 0
    private var nextSentenceToProcess: Int = 0

    // MARK: - Pipeline Control

    /// Pipeline task handle
    private var pipelineTask: Task<Void, Never>?

    /// Flag to stop pipeline
    private var shouldStop: Bool = false

    /// Whether word highlighting (and thus alignment) is enabled
    private var wordHighlightingEnabled: Bool = true

    /// Session counter to invalidate stale operations
    private var sessionID: Int = 0

    // MARK: - Initialization

    init(synthesisQueue: SynthesisQueue, ctcAligner: CTCForcedAligner) {
        self.synthesisQueue = synthesisQueue
        self.ctcAligner = ctcAligner
    }

    // MARK: - Configuration

    /// Set document source callbacks (called once when document loads)
    /// This avoids storing the entire document in ReadyQueue
    func setDocumentSource(
        totalCount: @escaping () -> Int,
        fetchParagraph: @escaping (Int) -> String?
    ) {
        self.totalParagraphCount = totalCount
        self.fetchParagraph = fetchParagraph

        // Clear any stale window data
        paragraphWindow.removeAll()
        paragraphSentences.removeAll()

        print("[ReadyQueue] 📚 Document source set (total: \(totalCount()) paragraphs)")
    }

    /// Update whether word highlighting is enabled
    func setWordHighlightingEnabled(_ enabled: Bool) {
        wordHighlightingEnabled = enabled
        print("[ReadyQueue] Word highlighting: \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Public Methods

    /// Start processing from a specific paragraph
    /// - Parameters:
    ///   - paragraphIndex: Paragraph to start from
    ///   - sentenceIndex: Sentence within paragraph (default 0)
    ///   - preserveBuffer: If true, keep buffered sentences for target paragraph and beyond
    func startFrom(paragraphIndex: Int, sentenceIndex: Int = 0, preserveBuffer: Bool = false) {
        // Increment session ID to invalidate any in-flight operations
        sessionID += 1
        let currentSession = sessionID

        // Cancel any existing pipeline
        shouldStop = true
        pipelineTask?.cancel()
        pipelineTask = nil

        // Reset or preserve buffer based on flag
        if preserveBuffer {
            // Keep sentences for target paragraph and beyond, remove older ones
            ready = ready.filter { $0.key.paragraphIndex >= paragraphIndex }
            skipped = skipped.filter { $0.paragraphIndex >= paragraphIndex }
            processing = processing.filter { $0.paragraphIndex >= paragraphIndex }

            // Recalculate buffer bytes
            currentBufferBytes = ready.values.reduce(0) { $0 + $1.chunks.reduce(0) { $0 + $1.count } }

            print("[ReadyQueue] 📝 Preserved \(ready.count) buffered sentences for P\(paragraphIndex)+")
        } else {
            ready.removeAll()
            skipped.removeAll()
            processing.removeAll()
            currentBufferBytes = 0
        }

        // Update position tracking
        currentParagraphIndex = paragraphIndex
        currentSentenceIndex = sentenceIndex
        nextParagraphToProcess = paragraphIndex
        nextSentenceToProcess = sentenceIndex
        shouldStop = false

        // Slide window to new position
        slideWindowTo(paragraphIndex: paragraphIndex)

        let sentenceCount = getSentences(forParagraph: paragraphIndex).count
        print("[ReadyQueue] 📝 Starting from P\(paragraphIndex)S\(sentenceIndex) (paragraph has \(sentenceCount) sentences, highlighting: \(wordHighlightingEnabled ? "on" : "off"), session: \(currentSession))")

        // Start the pipeline
        pipelineTask = Task { [weak self, currentSession] in
            await self?.runPipeline(session: currentSession)
        }
    }

    /// Atomically wait for and take a sentence (prevents race conditions)
    /// Returns nil if cancelled/stopped, timed out, or the sentence was skipped
    func waitAndTake(paragraphIndex: Int, sentenceIndex: Int) async -> ReadySentence? {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        var iterations = 0

        while !shouldStop && !Task.isCancelled && iterations < ReadyQueueConstants.maxWaitIterations {
            iterations += 1

            // Check if skipped (empty sentence)
            if skipped.contains(key) {
                print("[ReadyQueue] ⏭️ \(key) was skipped (empty)")
                updateCurrentPosition(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
                kickPipeline()
                return nil
            }

            // Atomically check and remove
            if let sentence = ready.removeValue(forKey: key) {
                currentBufferBytes -= sentence.chunks.reduce(0) { $0 + $1.count }
                print("[ReadyQueue] 🎯 Took \(key) (buffer: \(ready.count)/\(ReadyQueueConstants.maxSentenceLookahead))")

                updateCurrentPosition(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
                kickPipeline()

                return sentence
            }

            // Brief sleep to avoid busy-waiting
            try? await Task.sleep(nanoseconds: ReadyQueueConstants.waitIntervalNanos)
        }

        if iterations >= ReadyQueueConstants.maxWaitIterations {
            print("[ReadyQueue] ⏰ Timeout waiting for \(key) after \(iterations * 50)ms")
        }

        return nil
    }

    /// Check if a sentence was skipped (empty/whitespace)
    func wasSkipped(paragraphIndex: Int, sentenceIndex: Int) -> Bool {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return skipped.contains(key)
    }

    /// Check if a sentence is ready without removing it
    func isReady(paragraphIndex: Int, sentenceIndex: Int) -> Bool {
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return ready[key] != nil || skipped.contains(key)
    }

    /// Get sentence count for a paragraph
    func getSentenceCount(forParagraph index: Int) -> Int {
        return getSentences(forParagraph: index).count
    }

    /// Stop the pipeline and clear all state
    func stopPipeline() {
        sessionID += 1  // Invalidate in-flight operations
        shouldStop = true
        pipelineTask?.cancel()
        pipelineTask = nil
        ready.removeAll()
        skipped.removeAll()
        processing.removeAll()
        currentBufferBytes = 0
        print("[ReadyQueue] 🛑 Pipeline stopped")
    }

    /// Get current buffer status
    func getStatus() -> String {
        let mbUsed = Double(currentBufferBytes) / (1024 * 1024)
        return "Ready: \(ready.count)/\(ReadyQueueConstants.maxSentenceLookahead), \(String(format: "%.1f", mbUsed))MB, Window: \(paragraphWindow.count) paragraphs, Highlighting: \(wordHighlightingEnabled ? "on" : "off")"
    }

    // MARK: - Private: Position Management

    /// Update current playback position and slide window if needed
    private func updateCurrentPosition(paragraphIndex: Int, sentenceIndex: Int) {
        let oldParagraph = currentParagraphIndex
        currentParagraphIndex = paragraphIndex
        currentSentenceIndex = sentenceIndex

        // If we've moved to a new paragraph, slide the window
        if paragraphIndex > oldParagraph {
            slideWindowTo(paragraphIndex: paragraphIndex)
        }
    }

    /// Slide the paragraph window to center around the given index
    /// Evicts paragraphs that are now behind the playback position
    private func slideWindowTo(paragraphIndex: Int) {
        // Remove paragraphs before current position
        let keysToRemove = paragraphWindow.keys.filter { $0 < paragraphIndex }
        for key in keysToRemove {
            paragraphWindow.removeValue(forKey: key)
            paragraphSentences.removeValue(forKey: key)
        }

        if !keysToRemove.isEmpty {
            print("[ReadyQueue] 🪟 Window slid: evicted \(keysToRemove.count) old paragraph(s), keeping P\(paragraphIndex)+")
        }
    }

    // MARK: - Private: Paragraph/Sentence Access

    /// Get paragraph text, loading into window if needed
    private func getParagraphText(at index: Int) -> String? {
        // Check window first
        if let text = paragraphWindow[index] {
            return text
        }

        // Fetch from source
        guard let fetch = fetchParagraph, let text = fetch(index) else {
            return nil
        }

        // Enforce window size limit before adding
        while paragraphWindow.count >= ReadyQueueConstants.maxParagraphWindow {
            // Remove oldest paragraph (lowest index)
            if let oldest = paragraphWindow.keys.min() {
                paragraphWindow.removeValue(forKey: oldest)
                paragraphSentences.removeValue(forKey: oldest)
                print("[ReadyQueue] 🪟 Evicted P\(oldest) to make room in window")
            }
        }

        // Add to window
        paragraphWindow[index] = text
        return text
    }

    /// Get or compute sentences for a paragraph
    private func getSentences(forParagraph index: Int) -> [(text: String, offset: Int)] {
        // Check cache first
        if let cached = paragraphSentences[index] {
            return cached
        }

        // Get paragraph text (loads into window if needed)
        guard let text = getParagraphText(at: index) else {
            return []
        }

        // Split into sentences
        let chunks = SentenceSplitter.split(text)
        let sentences = chunks.map { ($0.text, $0.range.lowerBound) }
        paragraphSentences[index] = sentences
        return sentences
    }

    /// Get total paragraph count from source
    private func getTotalParagraphCount() -> Int {
        return totalParagraphCount?() ?? 0
    }

    // MARK: - Private: Pipeline Position

    /// Get next position to process, advancing across paragraph boundaries
    private func getNextPosition() -> (paragraphIndex: Int, sentenceIndex: Int)? {
        var pIdx = nextParagraphToProcess
        var sIdx = nextSentenceToProcess
        let total = getTotalParagraphCount()

        while pIdx < total {
            let sentences = getSentences(forParagraph: pIdx)
            if sIdx < sentences.count {
                return (pIdx, sIdx)
            }
            // Move to next paragraph
            pIdx += 1
            sIdx = 0
        }

        return nil // End of document
    }

    /// Advance the next-to-process pointer
    private func advanceNextPosition() {
        let sentences = getSentences(forParagraph: nextParagraphToProcess)
        nextSentenceToProcess += 1

        if nextSentenceToProcess >= sentences.count {
            // Move to next paragraph
            nextParagraphToProcess += 1
            nextSentenceToProcess = 0
        }
    }

    /// Kick the pipeline to continue processing (called after taking a sentence)
    private func kickPipeline() {
        // If pipeline task is nil or cancelled, restart it
        if pipelineTask == nil || (pipelineTask?.isCancelled ?? true) {
            let currentSession = sessionID
            shouldStop = false
            pipelineTask = Task { [weak self, currentSession] in
                await self?.runPipeline(session: currentSession)
            }
        }
    }

    // MARK: - Private: Pipeline Loop

    /// Main pipeline loop - processes sentences ahead of playback across paragraphs
    private func runPipeline(session: Int) async {
        print("[ReadyQueue] 🚀 Pipeline started (session: \(session))")

        while !shouldStop && !Task.isCancelled && session == sessionID {
            // Check if we have room in the buffer (count and memory)
            guard ready.count < ReadyQueueConstants.maxSentenceLookahead &&
                  currentBufferBytes < ReadyQueueConstants.maxBufferBytes else {
                try? await Task.sleep(nanoseconds: ReadyQueueConstants.pipelineIdleIntervalNanos)
                continue
            }

            // Get next position to process (spans paragraphs)
            guard let (pIdx, sIdx) = getNextPosition() else {
                // End of document - pipeline exits, will restart if needed via kickPipeline
                print("[ReadyQueue] 📖 Reached end of document in pipeline")
                break
            }

            let key = SentenceKey(paragraphIndex: pIdx, sentenceIndex: sIdx)

            // Skip if already processing, ready, or skipped
            guard !processing.contains(key) && ready[key] == nil && !skipped.contains(key) else {
                advanceNextPosition()
                continue
            }

            // Mark as processing
            processing.insert(key)
            advanceNextPosition()

            let sentences = getSentences(forParagraph: pIdx)
            guard sIdx < sentences.count else {
                processing.remove(key)
                continue
            }

            let (text, offset) = sentences[sIdx]
            print("[ReadyQueue] 🔄 Processing \(key): '\(text.prefix(30))...'")

            // Check cancellation/session before slow operation
            guard !Task.isCancelled && !shouldStop && session == sessionID else { break }

            // Process the sentence (synthesis + alignment if enabled)
            if let readySentence = await processSentence(
                text: text,
                offset: offset,
                paragraphIndex: pIdx,
                sentenceIndex: sIdx,
                session: session
            ) {
                // Check cancellation/session after slow operation
                guard !Task.isCancelled && !shouldStop && session == sessionID else { break }

                // Add to ready buffer
                ready[key] = readySentence
                currentBufferBytes += readySentence.chunks.reduce(0) { $0 + $1.count }
                processing.remove(key)

                print("[ReadyQueue] ✅ \(key) ready (buffer: \(ready.count)/\(ReadyQueueConstants.maxSentenceLookahead))")
            } else {
                // Sentence was skipped (empty) or failed
                skipped.insert(key)
                processing.remove(key)
                print("[ReadyQueue] ⏭️ \(key) skipped")
            }
        }

        print("[ReadyQueue] 🏁 Pipeline ended (session: \(session))")
    }

    // MARK: - Private: Sentence Processing

    /// Process a single sentence through synthesis + alignment (if enabled)
    private func processSentence(
        text: String,
        offset: Int,
        paragraphIndex: Int,
        sentenceIndex: Int,
        session: Int
    ) async -> ReadySentence? {
        // Skip empty sentences
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // STEP 1: Synthesize audio
        let chunkDelegate = PipelineChunkDelegate()

        let combinedAudio: Data
        do {
            // Use the returned combined audio directly (avoid redundant computation)
            combinedAudio = try await synthesisQueue.streamSentence(text, delegate: chunkDelegate)
        } catch {
            print("[ReadyQueue] ❌ Synthesis failed: \(error)")
            return nil
        }

        let chunks = chunkDelegate.getChunks()

        guard !chunks.isEmpty else {
            print("[ReadyQueue] ⏭️ Empty synthesis result")
            return nil
        }

        // Check cancellation/session between synthesis and alignment
        guard !Task.isCancelled && !shouldStop && session == sessionID else { return nil }

        // STEP 2: Run CTC alignment (only if highlighting enabled)
        var alignment: AlignmentResult? = nil

        if wordHighlightingEnabled {
            let alignmentStartTime = CFAbsoluteTimeGetCurrent()

            // Extract Float32 samples from combined audio
            let samples = combinedAudio.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }

            do {
                alignment = try await ctcAligner.align(
                    audioSamples: samples,
                    sampleRate: ReadyQueueConstants.sampleRate,
                    transcript: text,
                    paragraphIndex: paragraphIndex,
                    sentenceStartOffset: offset
                )

                let alignmentElapsed = CFAbsoluteTimeGetCurrent() - alignmentStartTime
                print("[ReadyQueue] ⏱️ Alignment took \(String(format: "%.3f", alignmentElapsed))s for P\(paragraphIndex)S\(sentenceIndex)")

            } catch {
                print("[ReadyQueue] ⚠️ Alignment failed (continuing without): \(error)")
                // Continue without alignment - highlighting won't work but audio will play
            }

            // Check cancellation/session after alignment
            guard !Task.isCancelled && !shouldStop && session == sessionID else { return nil }
        } else {
            print("[ReadyQueue] ⏭️ Skipping alignment (highlighting disabled)")
        }

        // Create ready sentence
        let key = SentenceKey(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
        return ReadySentence(
            key: key,
            chunks: chunks,
            alignment: alignment,
            text: text,
            sentenceOffset: offset
        )
    }
}

// MARK: - Pipeline Chunk Delegate

/// Delegate that accumulates audio chunks for the pipeline
/// Thread-safe for use from synthesis callbacks across actor boundaries
private final class PipelineChunkDelegate: SynthesisStreamDelegate, @unchecked Sendable {
    private var chunks: [Data] = []
    private let lock = NSLock()

    nonisolated func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(chunk)
        return true
    }

    nonisolated func getChunks() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }
}
```

**Step 2: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/ReadyQueue.swift
git commit -m "feat: add ReadyQueue actor with sliding window and cross-paragraph lookahead"
```

---

## Task 3: Add Word Highlighting Setting

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/ViewModels/SettingsViewModel.swift`
- Modify: `Listen2/Listen2/Listen2/Listen2/Views/SettingsView.swift`

**Step 1: Add setting to SettingsViewModel**

Find the `@AppStorage` properties in SettingsViewModel (around line 14-16) and add after `paragraphPauseDelay`:

```swift
    @AppStorage("wordHighlightingEnabled") var wordHighlightingEnabled: Bool = true
```

**Step 2: Add toggle to SettingsView**

Find the Playback section in SettingsView. After the "Paragraph Pause" VStack (ends at line 68), add before the section closing brace (line 69):

```swift
                    Divider()

                    // Word Highlighting Toggle
                    Toggle(isOn: $viewModel.wordHighlightingEnabled) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                            Text("Word Highlighting")
                                .font(DesignSystem.Typography.body)
                            Text("Highlight words as they're spoken. Disabling improves performance.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .tint(DesignSystem.Colors.primary)
                    .padding(.vertical, DesignSystem.Spacing.xs)
```

**Step 3: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/ViewModels/SettingsViewModel.swift Listen2/Listen2/Listen2/Listen2/Views/SettingsView.swift
git commit -m "feat: add word highlighting toggle to settings"
```

---

## Task 4: Add Loading State and ReadyQueue to TTSService

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Add isPreparing published property**

Find the Published Properties section (around line 68-73) and add after `isInitializing`:

```swift
    @Published private(set) var isPreparing: Bool = false
```

**Step 2: Add AppStorage for word highlighting setting**

Find the Settings section (around line 63-66) and add after `defaultPlaybackRate`:

```swift
    @AppStorage("wordHighlightingEnabled") private var wordHighlightingEnabled: Bool = true
```

**Step 3: Add readyQueue property**

Find the private properties section (around line 86, after `chunkBuffer`) and add:

```swift
    private var readyQueue: ReadyQueue?
```

**Step 4: Initialize readyQueue in initializePiperProvider()**

Find `initializePiperProvider()` method. After the line that initializes `synthesisQueue` (around line 178-180), add:

```swift
            // Initialize ready queue with dependencies
            self.readyQueue = ReadyQueue(synthesisQueue: self.synthesisQueue!, ctcAligner: self.ctcAligner)
```

**Step 5: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: add isPreparing state and readyQueue to TTSService"
```

---

## Task 5: Integrate ReadyQueue into Playback Flow

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Update startReading to set document source in ReadyQueue**

Find `startReading(paragraphs:from:title:wordMap:documentID:)` method (around line 463). After the line `self.currentDocumentID = documentID` (around line 470), add:

```swift
        // Set document source in ready queue (uses callbacks to avoid storing entire document)
        Task { [weak self] in
            guard let self = self else { return }
            await self.readyQueue?.setDocumentSource(
                totalCount: { [weak self] in self?.currentText.count ?? 0 },
                fetchParagraph: { [weak self] index in self?.currentText[safe: index] }
            )
        }
```

**Step 2: Replace speakParagraph implementation**

Find the `speakParagraph(at:)` method (around line 629) and replace its entire implementation with:

```swift
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

        // Show loading indicator
        isPreparing = true

        // Configure and start pipeline
        Task {
            await readyQueue.setWordHighlightingEnabled(wordHighlightingEnabled)
            await readyQueue.startFrom(paragraphIndex: index)
        }

        activeSpeakTask = Task {
            defer {
                print("[TTSService] 🏁 Ending ReadyQueue task \(taskID)")
                self.activeSpeakTask = nil
            }

            do {
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
```

**Step 3: Update handleParagraphComplete to preserve buffer**

Find `handleParagraphComplete()` method (around line 1218) and update the auto-advance section to preserve buffer:

```swift
    private func handleParagraphComplete() {
        // Don't set isPlaying to false yet if we're auto-advancing
        // This prevents flicker when transitioning between paragraphs

        guard shouldAutoAdvance else {
            isPlaying = false
            return
        }

        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            // Preserve buffered sentences when advancing to next paragraph
            Task {
                await readyQueue?.startFrom(paragraphIndex: nextIndex, preserveBuffer: true)
            }
            // Auto-advance to next paragraph WITHOUT setting isPlaying to false
            // The next paragraph will maintain isPlaying = true
            speakParagraph(at: nextIndex)
        } else {
            // Reached end of document - now we can set to false
            isPlaying = false
            nowPlayingManager.clearNowPlayingInfo()
        }
    }
```

**Step 4: Add playReadySentence method**

Add this new method after `speakParagraph(at:)`:

```swift
    /// Play a ready sentence (audio + highlighting if available)
    private func playReadySentence(_ sentence: ReadySentence) async throws {
        // Store alignment for highlighting (if available)
        if let alignment = sentence.alignment {
            currentAlignment = alignment
            minWordIndex = 0
            stuckWordWarningCount.removeAll()
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
```

**Step 5: Add legacy fallback method**

Add this fallback method (in case ReadyQueue isn't available):

```swift
    /// Legacy playback method (fallback when ReadyQueue unavailable)
    private func speakParagraphLegacy(at index: Int) {
        // This is the old implementation - copy the existing speakParagraph body here
        // before replacing it, or simply log an error
        print("[TTSService] ⚠️ Legacy playback not implemented - ReadyQueue required")
        isPlaying = false
    }
```

**Step 6: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: integrate ReadyQueue into playback flow with buffer preservation"
```

---

## Task 6: Handle Voice/Speed/Skip Changes

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Update stop() to await readyQueue**

Find the `stop()` method (around line 586). Replace the method with a version that properly awaits:

```swift
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
```

**Step 2: Clear readyQueue in setPlaybackRate()**

Find the `setPlaybackRate()` method (around line 314). In the `if wasPlaying` block, add after `await chunkBuffer.clearAll()`:

```swift
                await readyQueue?.stopPipeline()
```

**Step 3: Clear readyQueue in setVoice()**

Find the `setVoice()` method (around line 382). In the Task block after `await chunkBuffer.clearAll()`:

```swift
                    await readyQueue?.stopPipeline()
```

**Step 4: Clear readyQueue in stopAudioOnly()**

Find the `stopAudioOnly()` method (around line 546). Add inside the Task block:

```swift
            await readyQueue?.stopPipeline()
```

**Step 5: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: clear readyQueue on stop/rate/voice/skip changes"
```

---

## Task 7: Add UI Loading Indicator

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift`

**Note:** The existing `ReaderViewContent` already passes `ttsService` to `ReaderViewModel`, and `viewModel` provides access via `viewModel.ttsService`. We use this existing pattern rather than storing a separate reference.

**Step 1: Add preparing overlay**

Find the existing loading overlay in `ReaderViewContent` (around lines 69-73):

```swift
                // Loading overlay
                if viewModel.isLoading {
                    Color.clear
                        .loadingOverlay(isLoading: true, message: "Opening book...")
                }
```

Add the preparing overlay immediately after, using `viewModel.ttsService`:

```swift
                // Preparing audio overlay
                if viewModel.ttsService.isPreparing {
                    Color.clear
                        .loadingOverlay(isLoading: true, message: "Preparing audio...")
                }
```

**Step 2: Verify compilation**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift
git commit -m "feat: add loading indicator for audio preparation"
```

---

## Task 8: Clean Up Old Code (Optional)

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Note:** This task is optional and should only be done after confirming the new implementation works correctly. Keep the old code commented out initially for easy rollback.

**Step 1: Comment out old methods (don't delete yet)**

The following methods are now superseded by ReadyQueue but should be kept commented for rollback:

1. `startPreSynthesis` - pre-synthesis now handled by ReadyQueue
2. `playSentenceWithChunks` - replaced by `playReadySentence`
3. `playBufferedChunks` - replaced by `playReadySentence`
4. `performCTCAlignmentSync` - alignment now done in ReadyQueue

**Step 2: After verification, these can be removed:**

- `BufferingChunkDelegate` class
- `ChunkStreamDelegate` class
- `AccumulatingChunkDelegate` class (if not used elsewhere)
- `chunkBuffer` property and all references

**Step 3: Commit cleanup**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "refactor: comment out old buffering code (ReadyQueue now handles pipeline)"
```

---

## Task 9: Integration Testing

**Step 1: Build and run**

Run: `xcodebuild build -scheme "Listen2" -destination "platform=iOS Simulator,name=iPhone 16 Pro"`

**Step 2: Manual test checklist**

With word highlighting **enabled**:
- [ ] First play shows "Preparing audio..." briefly, then starts
- [ ] No gaps between sentences within a paragraph
- [ ] No gaps between paragraphs (cross-paragraph lookahead working)
- [ ] Words highlight as spoken
- [ ] Stop clears buffer and hides loading
- [ ] Speed change restarts pipeline correctly
- [ ] Voice change restarts pipeline correctly
- [ ] Skip paragraph works correctly
- [ ] Empty sentences are skipped without hanging
- [ ] Long wait (>30s) times out gracefully
- [ ] Sliding window evicts old paragraphs (check logs)

With word highlighting **disabled**:
- [ ] Loading time is noticeably faster (no alignment)
- [ ] No word highlighting occurs
- [ ] Audio plays smoothly
- [ ] Settings toggle works (takes effect immediately on next paragraph)

**Step 3: Check logs**

Expected log pattern (highlighting enabled, cross-paragraph with window):
```
[ReadyQueue] 📚 Document source set (total: 50 paragraphs)
[ReadyQueue] 📝 Starting from P0S0 (paragraph has 3 sentences, highlighting: on, session: 1)
[ReadyQueue] 🚀 Pipeline started (session: 1)
[ReadyQueue] 🔄 Processing P0S0: 'Chapter One...'
[ReadyQueue] ⏱️ Alignment took 0.157s for P0S0
[ReadyQueue] ✅ P0S0 ready (buffer: 1/5)
[ReadyQueue] 🔄 Processing P0S1: 'The story begins...'
[ReadyQueue] ✅ P0S1 ready (buffer: 2/5)
[ReadyQueue] 🔄 Processing P1S0: 'Next paragraph...'  <-- Cross-paragraph!
[ReadyQueue] ✅ P1S0 ready (buffer: 3/5)
[ReadyQueue] 🎯 Took P0S0 (buffer: 2/5)
[TTSService] 🏁 Sentence playback complete
[ReadyQueue] 🪟 Window slid: evicted 1 old paragraph(s), keeping P1+  <-- Window slides!
```

**Step 4: Final commit**

```bash
git add .
git commit -m "feat: complete unified pipeline with sliding window lookahead"
```

---

## Summary of Changes

| File | Change Type | Purpose |
|------|-------------|---------|
| `Listen2/.../Services/TTS/ReadySentence.swift` | Create | Model + constants for pipeline |
| `Listen2/.../Services/TTS/ReadyQueue.swift` | Create | Pipeline actor with sliding window |
| `Listen2/.../Services/TTSService.swift` | Modify | Integration with ReadyQueue |
| `Listen2/.../ViewModels/SettingsViewModel.swift` | Modify | Add wordHighlightingEnabled setting |
| `Listen2/.../Views/SettingsView.swift` | Modify | Add toggle UI |
| `Listen2/.../Views/ReaderView.swift` | Modify | Loading indicator UI |

## Memory Footprint

- Max 5 sentences buffered across paragraphs
- Max 5 paragraphs in sliding window
- ~10MB max audio buffer size (enforced)
- Old paragraphs evicted as playback advances
- Pipeline refills automatically on consumption

## Performance Expectations

With highlighting enabled:
- First sentence: 0.5-2s wait (synthesis + alignment)
- Subsequent sentences: No wait (lookahead buffer catches up)
- Paragraph transitions: Seamless (already buffered)

With highlighting disabled:
- First sentence: 0.3-1s wait (synthesis only)
- Subsequent sentences: No wait (faster lookahead)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         TTSService                          │
│  - Owns ReadyQueue                                          │
│  - Owns document text (currentText)                         │
│  - Manages playback state (isPreparing, isPlaying)          │
│  - Consumes ReadySentences and plays audio                  │
└─────────────────────┬───────────────────────────────────────┘
                      │ waitAndTake() / setDocumentSource()
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                        ReadyQueue                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Sliding Window (max 5 paragraphs)          │    │
│  │  [P3] [P4] [P5] [P6] [P7]  ← Fetched on-demand      │    │
│  │        ↑ current playback                            │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Pipeline (background Task)              │    │
│  │  P4S2 → P5S0 → P5S1 → P6S0 → P6S1 → ...            │    │
│  │    ↓                                                 │    │
│  │  Synthesis → Alignment (if enabled) → Ready Buffer  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Ready Buffer: [P4S2, P5S0, P5S1, P6S0, P6S1] (max 5)      │
│                  └── Cross-paragraph lookahead              │
└─────────────────────────────────────────────────────────────┘
```

## Issues Addressed from Code Reviews (v1 → v4)

| Review | Issue | Status | Resolution |
|--------|-------|--------|------------|
| v1 | File paths wrong | ✅ Fixed | Added `/Listen2` directory level |
| v1 | `nonisolated` protocol mismatch | ✅ Fixed | Added to PipelineChunkDelegate |
| v1 | No timeout in waitAndTake | ✅ Fixed | 30-second timeout via constants |
| v1 | Wrong method name reference | ✅ Fixed | Uses speakParagraph(at:) correctly |
| v1 | Missing defer pattern | ✅ Fixed | Added defer to clear activeSpeakTask |
| v2 | Missing Sendable on delegate | ✅ Fixed | Added `@unchecked Sendable` and `final` |
| v2 | isPreparing stuck state | ✅ Fixed | Reset before throw in else clause |
| v2 | Buffer cleared on transition | ✅ Fixed | preserveBuffer parameter |
| v2 | Redundant audio compute | ✅ Fixed | Use returned Data from streamSentence |
| v2 | stop() race condition | ✅ Fixed | sessionID prevents stale operations |
| v2 | Entire document in memory | ✅ Fixed | Sliding window with callbacks |
| v2 | Hard-coded constants | ✅ Fixed | ReadyQueueConstants enum |
| v3 | AlignmentResult not Sendable | ✅ Fixed | Added Task 0 for Sendable conformance |
| v3 | getChunks() not nonisolated | ✅ Fixed | Added nonisolated for consistency |
| v3 | ReaderView integration unclear | ✅ Fixed | Simplified to use viewModel.ttsService |
| v3 | Magic number in pipeline loop | ✅ Fixed | Added pipelineIdleIntervalNanos constant |
