# Event-Driven Word Highlighting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace polling-based word highlighting with audio render callback for frame-accurate word synchronization.

**Architecture:** New `WordHighlightScheduler` class installs tap on `AVAudioPlayerNode`, monitors frame position in audio callback, dispatches word changes to main thread. TTSService creates scheduler per sentence, tears down on pause/stop.

**Tech Stack:** AVAudioEngine, AVAudioPlayerNode.installTap, Swift async/await, Combine (for testing)

**Design Document:** `docs/plans/2025-11-23-event-driven-word-highlighting-design.md`

---

## Task 1: Create WordHighlightScheduler Class

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`
- Create: `Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift`

**Step 1: Create the test file with first test**

Create `Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift`:

```swift
//
//  WordHighlightSchedulerTests.swift
//  Listen2Tests
//

import XCTest
import AVFoundation
@testable import Listen2

final class WordHighlightSchedulerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeAlignment(words: [(text: String, start: Double, duration: Double)]) -> AlignmentResult {
        var currentLocation = 0
        let timings = words.enumerated().map { index, word in
            let timing = AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: word.start,
                duration: word.duration,
                text: word.text,
                rangeLocation: currentLocation,
                rangeLength: word.text.count
            )
            currentLocation += word.text.count + 1  // +1 for space between words
            return timing
        }
        let totalDuration = words.last.map { $0.start + $0.duration } ?? 0
        return AlignmentResult(
            paragraphIndex: 0,
            totalDuration: totalDuration,
            wordTimings: timings
        )
    }

    // MARK: - Tests

    func testSchedulerInitializesWithAlignment() {
        // Given
        let alignment = makeAlignment(words: [
            ("The", 0.0, 0.1),
            ("Knowledge", 0.1, 0.5)
        ])

        // When
        let scheduler = WordHighlightScheduler(alignment: alignment)

        // Then
        XCTAssertNotNil(scheduler)
        XCTAssertFalse(scheduler.isActive)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testSchedulerInitializesWithAlignment 2>&1 | tail -20`

Expected: FAIL with "Cannot find 'WordHighlightScheduler' in scope"

**Step 3: Create minimal WordHighlightScheduler implementation**

Create `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`:

```swift
//
//  WordHighlightScheduler.swift
//  Listen2
//
//  Schedules word highlight updates by monitoring audio playback position
//  via AVAudioEngine tap and comparing against CTC alignment data.
//

import Foundation
import AVFoundation

/// Schedules word highlight callbacks based on audio playback position.
/// Uses AVAudioPlayerNode tap to get frame-accurate timing.
@MainActor
final class WordHighlightScheduler {

    // MARK: - Types

    /// Callback when the highlighted word changes
    typealias WordChangeHandler = (AlignmentResult.WordTiming) -> Void

    // MARK: - Properties

    /// The alignment data for this sentence
    private let alignment: AlignmentResult

    /// Sample rate of the audio (Piper TTS uses 22050 Hz)
    private let sampleRate: Double = 22050

    /// Currently highlighted word index (-1 = none)
    private var currentWordIndex: Int = -1

    /// Whether the scheduler is actively monitoring
    private(set) var isActive: Bool = false

    /// Callback when word changes
    var onWordChange: WordChangeHandler?

    // MARK: - Initialization

    init(alignment: AlignmentResult) {
        self.alignment = alignment
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testSchedulerInitializesWithAlignment 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift
git commit -m "feat(highlighting): add WordHighlightScheduler skeleton

New class to replace polling-based word highlighting.
Initializes with AlignmentResult, exposes isActive state."
```

---

## Task 2: Add Word Lookup Logic

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`
- Modify: `Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift`

**Step 1: Add test for word lookup**

Add to `WordHighlightSchedulerTests.swift`:

```swift
func testFindWordIndexAtTime() {
    // Given
    let alignment = makeAlignment(words: [
        ("The", 0.0, 0.1),        // 0.0 - 0.1
        ("Knowledge", 0.1, 0.5),  // 0.1 - 0.6
        ("is", 0.6, 0.05)         // 0.6 - 0.65 (short word)
    ])
    let scheduler = WordHighlightScheduler(alignment: alignment)

    // Then - exact start times
    XCTAssertEqual(scheduler.testFindWordIndex(at: 0.0), 0)   // Start of "The"
    XCTAssertEqual(scheduler.testFindWordIndex(at: 0.1), 1)   // Start of "Knowledge"
    XCTAssertEqual(scheduler.testFindWordIndex(at: 0.6), 2)   // Start of "is"

    // Mid-word times
    XCTAssertEqual(scheduler.testFindWordIndex(at: 0.05), 0)  // Mid "The"
    XCTAssertEqual(scheduler.testFindWordIndex(at: 0.3), 1)   // Mid "Knowledge"

    // Edge cases
    XCTAssertEqual(scheduler.testFindWordIndex(at: -0.1), 0)  // Before first word -> first word
    XCTAssertEqual(scheduler.testFindWordIndex(at: 1.0), 2)   // After last word -> last word
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testFindWordIndexAtTime 2>&1 | tail -20`

Expected: FAIL with "has no member 'testFindWordIndex'"

**Step 3: Implement word lookup**

Add to `WordHighlightScheduler.swift`:

```swift
// MARK: - Word Lookup

/// Find the word index at a given time
/// - Parameter time: Time in seconds from start of audio
/// - Returns: Index of word being spoken, or nil if no words
private func findWordIndex(at time: TimeInterval) -> Int? {
    guard !alignment.wordTimings.isEmpty else { return nil }

    // Before first word - return first word (audio is playing, highlight it)
    if time < alignment.wordTimings[0].startTime {
        return 0
    }

    // Find word containing this time
    for (index, timing) in alignment.wordTimings.enumerated() {
        if time >= timing.startTime && time < timing.endTime {
            return index
        }
    }

    // After all words - return last word
    if let last = alignment.wordTimings.last, time >= last.startTime {
        return alignment.wordTimings.count - 1
    }

    return nil
}

#if DEBUG
/// Test-only access to findWordIndex
func testFindWordIndex(at time: TimeInterval) -> Int? {
    return findWordIndex(at: time)
}
#endif
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testFindWordIndexAtTime 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add -u
git commit -m "feat(highlighting): add word lookup by time

findWordIndex(at:) returns the word being spoken at a given time.
Handles edge cases: before first word, after last word, mid-word."
```

---

## Task 3: Add Frame Position Handler

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`
- Modify: `Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift`

**Step 1: Add test for word change callback**

Add to `WordHighlightSchedulerTests.swift`:

```swift
func testHandleFramePositionEmitsWordChange() async {
    // Given
    let alignment = makeAlignment(words: [
        ("The", 0.0, 0.1),
        ("Knowledge", 0.1, 0.5)
    ])
    let scheduler = WordHighlightScheduler(alignment: alignment)

    var receivedWords: [String] = []
    scheduler.onWordChange = { timing in
        receivedWords.append(timing.text)
    }

    // When - simulate frame positions (22050 Hz sample rate)
    // Frame 0 = time 0.0s -> "The"
    await scheduler.testHandleFramePosition(0)

    // Frame 2205 = time 0.1s -> "Knowledge"
    await scheduler.testHandleFramePosition(2205)

    // Frame 4410 = time 0.2s -> still "Knowledge" (no change)
    await scheduler.testHandleFramePosition(4410)

    // Then - should only emit when word changes
    XCTAssertEqual(receivedWords, ["The", "Knowledge"])
}

func testHandleFramePositionContinuesAfterPauseResume() async {
    // Given - simulates pause/resume where tap stops and restarts mid-word
    let alignment = makeAlignment(words: [
        ("The", 0.0, 0.1),
        ("Knowledge", 0.1, 0.5)
    ])
    let scheduler = WordHighlightScheduler(alignment: alignment)

    var receivedWords: [String] = []
    scheduler.onWordChange = { timing in
        receivedWords.append(timing.text)
    }

    // When - play starts
    await scheduler.testHandleFramePosition(0)      // "The" at 0.0s

    // Pause happens (no callbacks during pause)

    // Resume - tap fires again from where audio left off
    await scheduler.testHandleFramePosition(1103)   // Still "The" at 0.05s (mid-word)
    await scheduler.testHandleFramePosition(2205)   // "Knowledge" at 0.1s

    // Then - should emit "The" once (not again on resume), then "Knowledge"
    XCTAssertEqual(receivedWords, ["The", "Knowledge"])
}

func testHandleFramePositionIgnoredWhenInactive() async {
    // Given - scheduler that was stopped (simulates race condition)
    let alignment = makeAlignment(words: [
        ("The", 0.0, 0.1),
        ("Knowledge", 0.1, 0.5)
    ])
    let scheduler = WordHighlightScheduler(alignment: alignment)

    var receivedWords: [String] = []
    scheduler.onWordChange = { timing in
        receivedWords.append(timing.text)
    }

    // When - callbacks arrive but scheduler is not active
    // (simulates callbacks queued before stop() but delivered after)
    await scheduler.testHandleFramePosition(0)
    await scheduler.testHandleFramePosition(2205)

    // Then - no callbacks because isActive is false (never started)
    XCTAssertEqual(receivedWords, [])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testHandleFramePositionEmitsWordChange 2>&1 | tail -20`

Expected: FAIL with "has no member 'testHandleFramePosition'"

**Step 3: Implement frame position handler**

Add to `WordHighlightScheduler.swift`:

```swift
// MARK: - Frame Position Handling

/// Handle a frame position update from the audio tap
/// Called on main thread after dispatch from audio callback
/// - Parameter framePosition: Current frame position in samples
private func handleFramePosition(_ framePosition: Int64) {
    // Ignore callbacks that arrive after stop() was called
    // (they may have been queued before stop() but dispatched after)
    guard isActive else { return }

    // Convert frame position to seconds
    let currentTime = Double(framePosition) / sampleRate

    // Find which word should be highlighted
    guard let wordIndex = findWordIndex(at: currentTime) else { return }

    // Only emit if word changed
    if wordIndex != currentWordIndex {
        currentWordIndex = wordIndex
        let timing = alignment.wordTimings[wordIndex]
        onWordChange?(timing)
    }
}

#if DEBUG
/// Test-only access to handleFramePosition
func testHandleFramePosition(_ framePosition: Int64) async {
    handleFramePosition(framePosition)
}
#endif
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests/testHandleFramePositionEmitsWordChange 2>&1 | tail -20`

Expected: PASS

**Step 5: Commit**

```bash
git add -u
git commit -m "feat(highlighting): add frame position handler

handleFramePosition converts frame to time, finds word, emits callback.
Only emits when word actually changes (not every frame)."
```

---

## Task 4: Add Audio Tap Installation

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Testing Note:** This task does not add a new unit test because `AVAudioPlayerNode.installTap()` requires a real audio engine and cannot be easily mocked. The tap functionality is tested via integration testing in Task 11 (manual testing). The existing unit tests from Tasks 1-3 verify the core logic (word lookup, frame handling) which is the complex part. The tap is just a thin callback wrapper.

**Step 1: Add playerNode dependency and tap methods**

Update `WordHighlightScheduler.swift` to add playerNode and tap lifecycle:

```swift
// Update the class to include playerNode:

@MainActor
final class WordHighlightScheduler {

    // MARK: - Types

    typealias WordChangeHandler = (AlignmentResult.WordTiming) -> Void

    // MARK: - Properties

    private let alignment: AlignmentResult
    private weak var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 22050
    private var currentWordIndex: Int = -1
    private(set) var isActive: Bool = false
    var onWordChange: WordChangeHandler?

    // MARK: - Initialization

    init(playerNode: AVAudioPlayerNode, alignment: AlignmentResult) {
        self.playerNode = playerNode
        self.alignment = alignment
    }

    /// Convenience init for testing without playerNode
    init(alignment: AlignmentResult) {
        self.playerNode = nil
        self.alignment = alignment
    }

    // MARK: - Lifecycle

    /// Start monitoring audio playback for word highlighting
    func start() {
        guard !isActive else { return }
        installTap()
        isActive = true
    }

    /// Stop monitoring and clean up
    func stop() {
        guard isActive else { return }
        removeTap()
        isActive = false
        currentWordIndex = -1
    }

    // MARK: - Audio Tap

    private func installTap() {
        guard let playerNode = playerNode else {
            print("[WordHighlightScheduler] No playerNode available")
            return
        }

        // Get format from player node
        let format = playerNode.outputFormat(forBus: 0)

        // Install tap - callback runs on audio thread
        playerNode.installTap(
            onBus: 0,
            bufferSize: 1024,  // ~46ms at 22050Hz
            format: format
        ) { [weak self] buffer, time in
            // AUDIO THREAD - minimal work only!
            guard let self = self else { return }

            // Get frame position from audio time
            let framePosition = time.sampleTime

            // Dispatch to main thread for processing
            DispatchQueue.main.async {
                self.handleFramePosition(framePosition)
            }
        }

        print("[WordHighlightScheduler] Tap installed")
    }

    private func removeTap() {
        playerNode?.removeTap(onBus: 0)
        print("[WordHighlightScheduler] Tap removed")
    }

    // ... keep existing findWordIndex and handleFramePosition methods ...
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 3: Run existing tests to ensure no regressions**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests 2>&1 | tail -20`

Expected: All tests PASS

**Step 4: Commit**

```bash
git add -u
git commit -m "feat(highlighting): add audio tap lifecycle

start() installs tap on playerNode, stop() removes it.
Tap callback dispatches frame position to main thread.
Audio thread work is minimal (3 lines)."
```

---

## Task 5: Expose playerNode in StreamingAudioPlayer

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift:24`

**Step 1: Change playerNode from private to internal**

In `StreamingAudioPlayer.swift`, change line 24:

```swift
// BEFORE:
private let playerNode = AVAudioPlayerNode()

// AFTER:
let playerNode = AVAudioPlayerNode()
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "refactor(audio): expose playerNode for word highlighting

Changed from private to internal so WordHighlightScheduler can install tap."
```

---

## Task 6: Integrate WordHighlightScheduler in TTSService

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Add wordScheduler property**

Add after line 108 (after `private var highlightTimer: Timer?`):

```swift
/// Event-driven word highlighting scheduler
private var wordScheduler: WordHighlightScheduler?
```

**Step 2: Create setupWordScheduler method**

Add after the `stopHighlightTimer()` method (around line 1312):

```swift
// MARK: - Event-Driven Word Highlighting

/// Set up word highlighting scheduler for a sentence
private func setupWordScheduler(alignment: AlignmentResult) {
    // Tear down any existing scheduler
    wordScheduler?.stop()

    // Create new scheduler
    let scheduler = WordHighlightScheduler(
        playerNode: audioPlayer.playerNode,
        alignment: alignment
    )

    scheduler.onWordChange = { [weak self] timing in
        self?.handleScheduledWordChange(timing)
    }

    scheduler.start()
    wordScheduler = scheduler

    print("[TTSService] Word scheduler started for \(alignment.wordTimings.count) words")
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
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "feat(tts): add word scheduler integration methods

setupWordScheduler creates scheduler and connects to progress updates.
handleScheduledWordChange updates currentProgress for UI.
stopWordScheduler cleans up scheduler."
```

---

## Task 7: Wire Up Scheduler in playReadySentence

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift:767-815`

**Step 1: Replace timer-based highlighting with scheduler**

In `playReadySentence()` method, replace the timer-based highlighting:

Find this block (around lines 805-808):
```swift
// Start highlight timer only if we have alignment AND highlighting enabled
if sentence.alignment != nil && wordHighlightingEnabled {
    startHighlightTimerWithCTCAlignment()
}
```

Replace with:
```swift
// Start word scheduler only if we have alignment AND highlighting enabled
if let alignment = sentence.alignment, wordHighlightingEnabled {
    setupWordScheduler(alignment: alignment)
}
```

Also at line 770, replace:
```swift
stopHighlightTimer()
```

With:
```swift
stopWordScheduler()
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "feat(tts): use word scheduler in playReadySentence

Replace startHighlightTimerWithCTCAlignment with setupWordScheduler.
Replace stopHighlightTimer with stopWordScheduler in sentence setup."
```

---

## Task 8: Update Pause/Stop to Use Scheduler

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Design Note:** The audio tap naturally stops firing when `playerNode.pause()` is called because no new buffers are rendered. Therefore:
- `pause()` does NOT stop the scheduler - the tap just stops firing naturally
- `stop()` DOES stop the scheduler - we're ending playback entirely
- `handleParagraphComplete()` stops scheduler - moving to next paragraph
- Speed change stops scheduler - audio is restarted from current position

**Step 1: Update pause() method**

Find the `pause()` method (around line 514). Remove `stopHighlightTimer()` entirely - DO NOT replace with `stopWordScheduler()`:

```swift
func pause() {
    // NOTE: Don't stop word scheduler here!
    // The tap naturally stops firing when playerNode.pause() is called.
    // This allows resume() to continue highlighting without recreating the scheduler.

    Task { @MainActor in
        audioPlayer.pause()
        wordHighlighter.pause()
    }
    fallbackSynthesizer.pauseSpeaking(at: .word)
    stopHighlightTimer()  // REMOVE this line (old timer code)
    isPlaying = false
    nowPlayingManager.updatePlaybackState(isPlaying: false)
}
```

**Step 2: Update resume() method**

Find the `resume()` method (around line 529). Remove `startHighlightTimer()`:

```swift
func resume() {
    Task { @MainActor in
        audioPlayer.resume()
        wordHighlighter.resume()
    }
    fallbackSynthesizer.continueSpeaking()
    // REMOVE: startHighlightTimer()  // Scheduler tap resumes automatically
    isPlaying = true
    nowPlayingManager.updatePlaybackState(isPlaying: true)
}
```

**Step 3: Update stop() method**

Find the `stop()` method (around line 601). Replace `stopHighlightTimer()` with `stopWordScheduler()`:

```swift
// In stop() method, change:
stopHighlightTimer()

// To:
stopWordScheduler()
```

**Step 4: Update handleParagraphComplete()**

Find `handleParagraphComplete()` (around line 1271). Replace:

```swift
stopHighlightTimer()
currentAlignment = nil
```

With:
```swift
stopWordScheduler()
```

**Step 5: Update other stopHighlightTimer calls**

Search for remaining `stopHighlightTimer()` calls and replace with `stopWordScheduler()`:
- Line 374 (in setPlaybackRate) - scheduler needs restart because audio is restarted
- Line 587 (in stopAudioOnly) - stopping playback entirely

**Step 6: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add -u
git commit -m "feat(tts): update pause/stop to use word scheduler

- pause(): Don't stop scheduler - tap naturally pauses with audio
- resume(): Don't restart scheduler - tap resumes with audio
- stop()/handleParagraphComplete(): Stop scheduler - ending playback
- setPlaybackRate()/stopAudioOnly(): Stop scheduler - restarting audio"
```

---

## Task 9: Add Settings Change Detection

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Add previous setting tracker**

Add after line 67 (`@AppStorage("wordHighlightingEnabled")`):

```swift
/// Track previous highlighting setting to detect changes
private var previousHighlightingSetting: Bool = true
```

**Step 2: Initialize in init()**

Add at end of `override init()` (around line 160):

```swift
// Track initial highlighting setting
previousHighlightingSetting = wordHighlightingEnabled
```

**Step 3: Add detection in startReading()**

At the beginning of `startReading()` method (around line 471), add:

```swift
func startReading(paragraphs: [String], from index: Int, title: String = "Document", wordMap: DocumentWordMap? = nil, documentID: UUID? = nil) {
    // Check if highlighting setting changed - invalidate cache if so
    if wordHighlightingEnabled != previousHighlightingSetting {
        print("[TTSService] Highlighting setting changed, invalidating pipeline")
        Task {
            await readyQueue?.stopPipeline()
        }
        previousHighlightingSetting = wordHighlightingEnabled
    }

    // ... rest of existing method ...
```

**Step 4: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add -u
git commit -m "fix(tts): detect highlighting setting changes

Track previousHighlightingSetting, invalidate pipeline when changed.
Fixes crash/no-playback when toggling word highlighting in settings."
```

---

## Task 10: Remove Old Polling Code

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Remove unused properties**

Delete these properties (keep wordScheduler, remove the rest):

```swift
// DELETE these lines:
private var highlightTimer: Timer?                    // ~line 106
private var currentAlignment: AlignmentResult?       // ~line 107
private var lastHighlightedWordIndex: Int?           // ~line 111
private var lastHighlightChangeTime: TimeInterval = 0  // ~line 112
private let maxStuckDuration: TimeInterval = 2.0     // ~line 113
private var minWordIndex: Int = 0                    // ~line 114
private var stuckWordWarningCount: [Int: Int] = [:]  // ~line 115
private static var highlightLogCounter = 0          // ~line 1315
```

**Step 2: Remove unused methods**

Delete these entire methods:

```swift
// DELETE startHighlightTimerWithCTCAlignment() - around lines 1020-1038
// DELETE stopHighlightTimer() - around lines 1308-1311
// DELETE updateHighlightFromTime() - around lines 1317-1414
```

**Step 3: Remove dead code references**

Search for and remove any remaining references to:
- `currentAlignment` - assignments in `playBufferedChunks()` (~lines 1113-1122), `playSentenceWithChunks()` (~line 888), `performCTCAlignmentSync()` (~line 943)
- `minWordIndex`
- `stuckWordWarningCount`
- `lastHighlightedWordIndex`
- `lastHighlightChangeTime`
- `startHighlightTimer()` references in `resume()` method

**Note:** Keep `wordHighlighter` property and `highlightSubscription` - these are used for AVSpeech fallback, not Piper highlighting.

These may appear in methods like `playReadySentence`, `performCTCAlignmentSync`, `resume()`, etc.

**Step 4: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 5: Run all tests**

Run: `xcodebuild test -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "(Test Case|passed|failed)"`

Expected: All tests pass

**Step 6: Commit**

```bash
git add -u
git commit -m "refactor(tts): remove polling-based highlighting code

Deleted ~150 lines of timer/polling code:
- highlightTimer and related properties
- startHighlightTimerWithCTCAlignment()
- stopHighlightTimer()
- updateHighlightFromTime()
- Stuck word detection logic

Event-driven WordHighlightScheduler replaces all of this."
```

---

## Task 11: Manual Testing

**Step 1: Build and run on simulator**

```bash
xcodebuild build -project Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Step 2: Manual test checklist**

Test each scenario and verify:

- [ ] Open a book, press play - first word highlights immediately
- [ ] Short words like "The", "is", "a" are highlighted (not skipped)
- [ ] Highlighting matches audio timing (not behind)
- [ ] Pause playback - highlight clears
- [ ] Resume playback - sentence restarts from beginning
- [ ] Skip to next paragraph - highlighting works
- [ ] Change highlighting setting in Settings
- [ ] Return to book, press play - playback works (no crash)
- [ ] With highlighting OFF, playback works without crashes

**Step 3: Document results**

Record any issues found for follow-up.

---

## Summary

**Total Tasks:** 11
**New Files:** 2 (WordHighlightScheduler.swift, WordHighlightSchedulerTests.swift)
**Modified Files:** 2 (TTSService.swift, StreamingAudioPlayer.swift)
**Lines Added:** ~150
**Lines Removed:** ~150
**Net Change:** ~0 (cleaner code, same functionality, better timing)
