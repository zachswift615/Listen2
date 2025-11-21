# Chunk-Level Audio Streaming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace sentence-level caching with true audio chunk streaming from sherpa-onnx for lower latency, better memory efficiency, and simpler architecture.

**Architecture:** Remove SynthesisQueue caching logic, create StreamingAudioPlayer using AVAudioEngine for chunk scheduling, implement just-in-time synthesis with direct chunk passthrough.

**Tech Stack:** AVAudioEngine, AVAudioPlayerNode, sherpa-onnx streaming callbacks, Swift async/await

---

## Task 1: Create StreamingAudioPlayer with AVAudioEngine

**Goal:** Replace AVAudioPlayer-based AudioPlayer with AVAudioEngine-based streaming player that can schedule audio chunks as they arrive.

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift`

**Step 1: Create StreamingAudioPlayer class structure**

Create new file with AVAudioEngine setup:

```swift
//
//  StreamingAudioPlayer.swift
//  Listen2
//
//  Streaming audio player using AVAudioEngine for chunk-level playback
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
final class StreamingAudioPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0

    // MARK: - Private Properties

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var displayLink: CADisplayLink?
    private var onFinished: (() -> Void)?
    private var currentFormat: AVAudioFormat?

    // Track scheduled buffers to know when playback completes
    private var scheduledBufferCount: Int = 0
    private var playedBufferCount: Int = 0
    private var allBuffersScheduled: Bool = false

    // Track total duration for progress
    private var totalDuration: TimeInterval = 0
    private var startTime: TimeInterval = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // Attach player node to engine
        audioEngine.attach(playerNode)

        // Create format: 22050 Hz, mono, float32
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: 1,
            interleaved: false
        ) else {
            print("[StreamingAudioPlayer] ❌ Failed to create audio format")
            return
        }

        currentFormat = format

        // Connect player node to main mixer
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: format
        )

        // Prepare and start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[StreamingAudioPlayer] ✅ Audio engine started")
        } catch {
            print("[StreamingAudioPlayer] ❌ Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Playback Control

    /// Start new streaming session
    func startStreaming(onFinished: @escaping () -> Void) {
        stop()

        self.onFinished = onFinished
        scheduledBufferCount = 0
        playedBufferCount = 0
        allBuffersScheduled = false
        totalDuration = 0
        startTime = CACurrentMediaTime()

        // Start player node
        playerNode.play()
        isPlaying = true
        startDisplayLink()

        print("[StreamingAudioPlayer] 🎬 Started streaming session")
    }

    /// Schedule an audio chunk for playback
    func scheduleChunk(_ audioData: Data) {
        guard let format = currentFormat else {
            print("[StreamingAudioPlayer] ❌ No audio format available")
            return
        }

        // Convert Data (float32 samples) to AVAudioPCMBuffer
        let sampleCount = audioData.count / MemoryLayout<Float>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            print("[StreamingAudioPlayer] ❌ Failed to create buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Copy samples to buffer
        audioData.withUnsafeBytes { rawPtr in
            guard let floatPtr = rawPtr.baseAddress?.assumingMemoryBound(to: Float.self) else {
                return
            }
            guard let channelData = buffer.floatChannelData else {
                return
            }
            channelData[0].update(from: floatPtr, count: sampleCount)
        }

        // Calculate chunk duration
        let chunkDuration = Double(sampleCount) / format.sampleRate
        totalDuration += chunkDuration

        scheduledBufferCount += 1
        let bufferID = scheduledBufferCount

        // Schedule buffer with completion handler
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.onBufferComplete(bufferID: bufferID)
            }
        }

        print("[StreamingAudioPlayer] 📦 Scheduled chunk #\(bufferID): \(sampleCount) samples (\(String(format: "%.3f", chunkDuration))s)")
    }

    /// Mark that all chunks have been scheduled
    func finishScheduling() {
        allBuffersScheduled = true
        print("[StreamingAudioPlayer] ✅ All buffers scheduled (total: \(scheduledBufferCount), duration: \(String(format: "%.3f", totalDuration))s)")

        // Check if already complete (for very short audio)
        checkCompletion()
    }

    private func onBufferComplete(bufferID: Int) {
        playedBufferCount += 1
        print("[StreamingAudioPlayer] ✓ Buffer #\(bufferID) complete (played: \(playedBufferCount)/\(scheduledBufferCount))")

        checkCompletion()
    }

    private func checkCompletion() {
        if allBuffersScheduled && playedBufferCount >= scheduledBufferCount {
            print("[StreamingAudioPlayer] 🏁 All buffers played, calling onFinished")
            isPlaying = false
            stopDisplayLink()
            onFinished?()
        }
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        totalDuration = 0
        stopDisplayLink()
        onFinished = nil
        scheduledBufferCount = 0
        playedBufferCount = 0
        allBuffersScheduled = false
    }

    // MARK: - Progress Tracking

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updateCurrentTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateCurrentTime() {
        if isPlaying {
            // Estimate current time based on elapsed time
            let elapsed = CACurrentMediaTime() - startTime
            currentTime = elapsed
        }
    }

    var duration: TimeInterval {
        totalDuration
    }
}

// MARK: - Errors

enum StreamingAudioPlayerError: Error, LocalizedError {
    case playbackFailed
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to start streaming audio playback"
        case .invalidAudioData:
            return "Invalid audio data provided"
        }
    }
}
```

**Step 2: Commit StreamingAudioPlayer**

```bash
git add Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift
git commit -m "feat: add StreamingAudioPlayer with AVAudioEngine for chunk-level playback

Uses AVAudioPlayerNode.scheduleBuffer() to play audio chunks as they
arrive from sherpa-onnx streaming callbacks. Replaces AVAudioPlayer
which requires complete audio files.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Simplify SynthesisQueue to Remove Caching

**Goal:** Strip out sentence caching, producer-consumer logic, and pre-synthesis. Keep only the streaming synthesis trigger.

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Replace SynthesisQueue implementation**

Replace the entire file with simplified version:

```swift
//
//  SynthesisQueue.swift
//  Listen2
//
//  Manages just-in-time synthesis with streaming callbacks
//

import Foundation

/// Simplified synthesis queue for chunk-level streaming
/// NO caching, NO pre-synthesis, just trigger synthesis and stream chunks
actor SynthesisQueue {

    // MARK: - State

    /// The provider used for synthesis
    private let provider: TTSProvider

    /// All paragraphs text
    private var paragraphs: [String] = []

    /// Current playback rate
    private var speed: Float = 1.0

    /// Document ID for future use (alignment caching removed)
    private var documentID: UUID?

    // MARK: - Initialization

    init(provider: TTSProvider) {
        self.provider = provider
    }

    // MARK: - Public Methods

    /// Update the content
    func setContent(paragraphs: [String], speed: Float, documentID: UUID? = nil, wordMap: DocumentWordMap? = nil, autoPreSynthesize: Bool = true) {
        self.paragraphs = paragraphs
        self.speed = speed
        self.documentID = documentID
        print("[SynthesisQueue] Set content: \(paragraphs.count) paragraphs at speed \(speed)")
    }

    /// Update playback speed
    func setSpeed(_ speed: Float) {
        self.speed = speed
        print("[SynthesisQueue] Speed changed to \(speed)")
    }

    /// Stream sentence audio chunks with just-in-time synthesis
    /// - Parameter sentence: Sentence text to synthesize
    /// - Parameter delegate: Callback for receiving audio chunks
    /// - Returns: AsyncStream of audio chunks
    func streamSentence(_ sentence: String, delegate: SynthesisStreamDelegate?) async throws -> Data {
        print("[SynthesisQueue] 🎵 Synthesizing sentence: '\(sentence.prefix(50))...'")

        let result = try await provider.synthesizeWithStreaming(
            sentence,
            speed: speed,
            delegate: delegate
        )

        print("[SynthesisQueue] ✅ Synthesis complete: \(result.audioData.count) bytes")
        return result.audioData
    }

    /// Clear all state (for voice changes, etc.)
    func clearAll() {
        print("[SynthesisQueue] Cleared")
    }
}
```

**Step 2: Commit simplified SynthesisQueue**

```bash
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git commit -m "refactor: simplify SynthesisQueue to remove caching

Removes ~900 lines of sentence caching, producer-consumer pattern,
and pre-synthesis logic. Now only triggers just-in-time synthesis
with streaming callbacks. Chunk-level streaming replaces sentence-level
buffering.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Update TTSService for Chunk Streaming

**Goal:** Replace sentence bundle streaming with direct chunk streaming. Use StreamingAudioPlayer instead of AudioPlayer.

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Update imports and properties**

At the top of TTSService.swift, change:

```swift
// OLD:
private var audioPlayer: AudioPlayer!

// NEW:
private var audioPlayer: StreamingAudioPlayer!
```

And in init():

```swift
// OLD:
Task { @MainActor in
    self.audioPlayer = AudioPlayer()
}

// NEW:
Task { @MainActor in
    self.audioPlayer = StreamingAudioPlayer()
}
```

**Step 2: Replace speakParagraph method**

Replace the entire `speakParagraph(at:)` method (lines ~540-636) with:

```swift
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
```

**Step 3: Add playSentenceWithChunks method**

Add new method after `speakParagraph`:

```swift
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
```

**Step 4: Add ChunkStreamDelegate helper**

Add at the bottom of TTSService.swift, before the AVSpeechSynthesizerDelegate extension:

```swift
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
```

**Step 5: Disable word highlighting temporarily**

Find the `startHighlightTimer()` method and replace its body with:

```swift
private func startHighlightTimer() {
    // TEMPORARY: Highlighting disabled during chunk streaming development
    // Will revisit with better approach after streaming is stable
    print("[TTSService] ⏸️ Word highlighting temporarily disabled")
}
```

Also comment out the word highlighter subscription in `playSentenceWithChunks` (don't start highlighting).

**Step 6: Commit TTSService changes**

```bash
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: implement chunk-level streaming in TTSService

- Replace AudioPlayer with StreamingAudioPlayer
- Stream audio chunks directly from sherpa-onnx callbacks
- Schedule chunks on AVAudioPlayerNode as they arrive
- Disable word highlighting temporarily (will revisit)
- Remove sentence bundle caching logic

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Update Xcode Project

**Goal:** Add StreamingAudioPlayer.swift to Xcode project so it builds.

**Files:**
- Modify: `Listen2/Listen2/Listen2.xcodeproj/project.pbxproj` (via Xcode)

**Step 1: Add file to Xcode**

Open Xcode:
```bash
open Listen2/Listen2/Listen2.xcodeproj
```

1. Right-click on `Services/TTS` folder in project navigator
2. Select "Add Files to Listen2..."
3. Navigate to `Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift`
4. Ensure "Copy items if needed" is unchecked (file already in place)
5. Ensure target "Listen2" is checked
6. Click "Add"

**Step 2: Verify and commit**

```bash
git add Listen2/Listen2/Listen2.xcodeproj/project.pbxproj
git commit -m "build: add StreamingAudioPlayer to Xcode project

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Build and Test

**Goal:** Verify the code compiles and runs without crashes.

**Step 1: Clean build**

```bash
cd Listen2/Listen2
xcodebuild clean -project Listen2.xcodeproj -scheme Listen2
```

**Step 2: Build project**

```bash
xcodebuild build -project Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected: Build succeeds with 0 errors

**Step 3: Run app in simulator**

```bash
xcodebuild test -project Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/BasicSmokeTests
```

Or manually:
1. Open Xcode
2. Select iPhone 15 simulator
3. Click Run (⌘R)
4. Load a document
5. Start playback
6. Observe:
   - Does audio start quickly? (< 200ms)
   - Are there gaps within sentences?
   - Does it advance between sentences smoothly?
   - Does memory stay low? (check Xcode memory gauge)

**Step 4: Document findings**

Create a test log with observations:

```bash
cat > test-results.md << 'EOF'
# Chunk Streaming Test Results

## Test Date: 2025-11-20

### Latency
- Time to first audio: ___ms
- Expected: < 200ms
- Status: PASS / FAIL

### Playback Quality
- Gaps within sentences: YES / NO
- Gap duration (if any): ___ms
- Audio quality: GOOD / POOR
- Status: PASS / FAIL

### Memory Usage
- Peak memory during playback: ___MB
- Previous implementation: ~100-200MB
- Status: IMPROVED / SAME / WORSE

### User Experience
- Playback feels responsive: YES / NO
- Smooth transitions between sentences: YES / NO
- Overall impression: BETTER / SAME / WORSE

### Issues Found
- [List any issues]

### Next Steps
- [Based on findings]
EOF

git add test-results.md
git commit -m "docs: add chunk streaming test results

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Handle Edge Cases

**Goal:** Test and fix edge cases like skip, speed change, stop during playback.

**Test Cases:**

1. **Stop during playback:**
   - Start playback
   - Click stop mid-sentence
   - Expected: Audio stops immediately, no crashes

2. **Skip forward during synthesis:**
   - Start playback
   - Skip to next paragraph mid-sentence
   - Expected: Current synthesis cancels, new paragraph starts

3. **Speed change during playback:**
   - Start playback at 1.0x
   - Change speed to 1.5x
   - Expected: Current sentence finishes, next sentence uses new speed

4. **Very short sentences:**
   - Play text with 1-2 word sentences
   - Expected: No gaps, smooth playback

5. **Very long sentences:**
   - Play paragraph-length sentence
   - Expected: Chunks stream smoothly, no memory bloat

**If issues found:** Fix them iteratively and commit fixes

---

## Success Criteria

- [ ] Audio playback starts within 200ms
- [ ] No audible gaps within sentences (or < 50ms acceptable)
- [ ] Memory usage < 50MB during playback
- [ ] Clean cancellation on stop/skip
- [ ] Code reduced by ~400-500 lines
- [ ] All edge cases handled gracefully

---

## Rollback Plan

If chunk streaming is unacceptable:

```bash
git log --oneline -6  # Find commits from this implementation
git revert HEAD~5..HEAD  # Revert back to sentence caching
```

Or selectively revert specific commits.

---

## Future Enhancements (After Streaming Stable)

1. **Add minimal chunk buffer** (if gaps unacceptable)
   - Buffer 3-5 chunks before starting playback
   - ~100-200ms latency increase, smoother playback

2. **Reintroduce lookahead synthesis** (if needed)
   - Start synthesizing next sentence when current is 80% complete
   - Keep memory low by only looking ahead 1-2 sentences

3. **Revisit word highlighting**
   - Explore alternatives to phoneme duration scaling
   - Consider frame-based timing from sherpa-onnx
   - Test different alignment approaches

4. **Performance optimization**
   - Measure sherpa-onnx synthesis speed vs playback speed
   - Profile memory allocation in chunk scheduling
   - Optimize buffer sizes for target latency

---

## Notes

- Keep old AudioPlayer.swift file for now (don't delete) in case we need to reference it
- SynthesisQueue.swift old implementation is in git history if needed
- Word highlighting code stays in place but disabled - easy to re-enable later
- Monitor Xcode console for "[StreamingAudioPlayer]" and "[TTSService]" logs during testing
