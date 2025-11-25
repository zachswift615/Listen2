# True Event-Driven Word Highlighting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace polling-based word highlighting with truly event-driven scheduling where word changes fire at exact times.

**Architecture:** New approach pre-schedules `DispatchWorkItem` for each word's start time when playback begins. Callbacks fire at exact word boundaries - no polling, no missed short words. Cancel all pending work items on stop/pause.

**Tech Stack:** Swift, DispatchQueue, DispatchWorkItem, XCTest with expectations

**Design Document:** Replaces polling approach from `docs/plans/2025-11-23-event-driven-word-highlighting-implementation.md`

**Known Limitation:** On pause/resume, highlighting restarts from sentence beginning (not mid-word). This is acceptable because the audio also restarts from sentence beginning on resume.

---

## Task 1: Add Scheduled Work Items Infrastructure

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Step 1: Add scheduledWorkItems property**

After line 37 (`private var startSampleTime: Int64 = 0`), add:

```swift
/// Scheduled work items for each word - cancelled on stop
private var scheduledWorkItems: [DispatchWorkItem] = []
```

**Step 2: Add cancelScheduledWorkItems method**

Add after the `removeTap()` method (around line 114):

```swift
/// Cancel all scheduled word change events
private func cancelScheduledWorkItems() {
    let count = scheduledWorkItems.count
    for workItem in scheduledWorkItems {
        workItem.cancel()
    }
    scheduledWorkItems.removeAll()
    if count > 0 {
        print("[WordHighlightScheduler] Cancelled \(count) scheduled work items")
    }
}
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "feat(highlighting): add scheduled work items infrastructure"
```

---

## Task 2: Implement scheduleWordChanges Method

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Step 1: Add scheduleWordChanges method**

Add after `cancelScheduledWorkItems()`:

```swift
/// Schedule word change callbacks at exact times
/// Each word gets a DispatchWorkItem that fires at its startTime
private func scheduleWordChanges() {
    // Cancel any existing scheduled items
    cancelScheduledWorkItems()

    guard !alignment.wordTimings.isEmpty else {
        print("[WordHighlightScheduler] No words to schedule")
        return
    }

    let startTime = DispatchTime.now()

    for (index, timing) in alignment.wordTimings.enumerated() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isActive else { return }
            self.emitWordChange(at: index)
        }

        scheduledWorkItems.append(workItem)

        // Schedule at exact word start time
        let deadline = startTime + timing.startTime
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
    }

    print("[WordHighlightScheduler] Scheduled \(scheduledWorkItems.count) word changes")
}

/// Emit word change callback for word at index
private func emitWordChange(at index: Int) {
    guard index >= 0 && index < alignment.wordTimings.count else { return }
    guard index != currentWordIndex else { return }  // Don't re-emit same word

    currentWordIndex = index
    let timing = alignment.wordTimings[index]
    print("[WordHighlightScheduler] Word \(index): '\(timing.text)' @ \(String(format: "%.3f", timing.startTime))s")
    onWordChange?(timing)
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "feat(highlighting): implement scheduleWordChanges method"
```

---

## Task 3: Update start() to Use Scheduled Events

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Step 1: Update start() method**

Replace the current `start()` method:

```swift
/// Start monitoring audio playback for word highlighting
func start() {
    guard !isActive else { return }
    isActive = true
    currentWordIndex = -1
    scheduleWordChanges()
}
```

**Step 2: Update stop() method**

Replace the current `stop()` method:

```swift
/// Stop monitoring and clean up
func stop() {
    guard isActive else { return }
    isActive = false
    cancelScheduledWorkItems()
    currentWordIndex = -1
}
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "feat(highlighting): use scheduled events in start/stop"
```

---

## Task 4: Remove Audio Tap Code

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Step 1: Remove tap-related properties**

Delete these lines:
- `private weak var playerNode: AVAudioPlayerNode?` (line ~28)
- `private var startSampleTime: Int64 = 0` (line ~37)

**Step 2: Remove tap-related methods**

Delete these entire methods:
- `installTap()` (lines ~77-109)
- `removeTap()` (lines ~111-114)
- `findWordIndex(at:)` (lines ~118-142)
- `handleFramePosition(_:)` (lines ~148-177)

**Step 2b: Remove DEBUG test helpers**

Delete the entire `#if DEBUG` block (lines ~179-204):
- `testWasDeactivated` property
- `testFindWordIndex(at:)` method
- `testHandleFramePosition(_:)` method
- `testDeactivate()` method

These reference deleted methods and are no longer needed.

**Step 3: Update initializers**

Replace both initializers with a single one:

```swift
// MARK: - Initialization

init(alignment: AlignmentResult) {
    self.alignment = alignment
}
```

**Step 4: Remove AVFoundation import if no longer needed**

Check if `AVFoundation` is still used. If not, remove:
```swift
import AVFoundation
```

**Step 5: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add -u
git commit -m "refactor(highlighting): remove audio tap polling code

Deleted ~80 lines of tap-based polling:
- installTap/removeTap methods
- handleFramePosition polling logic
- playerNode dependency

Now uses pure scheduled events."
```

---

## Task 5: Update TTSService Integration

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Update setupWordScheduler to not pass playerNode**

Find `setupWordScheduler(alignment:)` (around line 1122) and update:

```swift
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

    print("[TTSService] Word scheduler started for \(alignment.wordTimings.count) words")
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "refactor(tts): update setupWordScheduler for new API

WordHighlightScheduler no longer needs playerNode reference."
```

---

## Task 6: Update Tests for New Approach

**Files:**
- Modify: `Listen2/Listen2/Listen2Tests/Services/TTS/WordHighlightSchedulerTests.swift`

**Step 1: Replace entire test file with new tests**

```swift
//
//  WordHighlightSchedulerTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

@MainActor
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
            currentLocation += word.text.count + 1
            return timing
        }
        let totalDuration = words.last.map { $0.start + $0.duration } ?? 0
        return AlignmentResult(
            paragraphIndex: 0,
            totalDuration: totalDuration,
            wordTimings: timings
        )
    }

    // MARK: - Initialization Tests

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

    func testSchedulerBecomesActiveOnStart() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        // When
        scheduler.start()

        // Then
        XCTAssertTrue(scheduler.isActive)

        // Cleanup
        scheduler.stop()
    }

    func testSchedulerBecomesInactiveOnStop() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)
        scheduler.start()

        // When
        scheduler.stop()

        // Then
        XCTAssertFalse(scheduler.isActive)
    }

    // MARK: - Scheduled Events Tests

    func testFirstWordEmittedImmediately() {
        // Given - word starts at 0.0s
        let alignment = makeAlignment(words: [
            ("Hello", 0.0, 0.2),
            ("World", 0.2, 0.3)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "First word emitted")
        var receivedWord: String?

        scheduler.onWordChange = { timing in
            if receivedWord == nil {
                receivedWord = timing.text
                expectation.fulfill()
            }
        }

        // When
        scheduler.start()

        // Then - first word should emit almost immediately
        wait(for: [expectation], timeout: 0.3)  // Extra margin for CI
        XCTAssertEqual(receivedWord, "Hello")

        // Cleanup
        scheduler.stop()
    }

    func testAllWordsEmittedInOrder() {
        // Given - 3 words with short durations
        let alignment = makeAlignment(words: [
            ("One", 0.0, 0.05),
            ("Two", 0.05, 0.05),
            ("Three", 0.1, 0.05)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "All words emitted")
        expectation.expectedFulfillmentCount = 3
        var receivedWords: [String] = []

        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
            expectation.fulfill()
        }

        // When
        scheduler.start()

        // Then - all 3 words should emit within 200ms
        wait(for: [expectation], timeout: 0.5)  // Extra margin for CI
        XCTAssertEqual(receivedWords, ["One", "Two", "Three"])

        // Cleanup
        scheduler.stop()
    }

    func testShortWordsNotSkipped() {
        // Given - simulate "I met a traveler" with short "a" (50ms)
        let alignment = makeAlignment(words: [
            ("I", 0.0, 0.08),
            ("met", 0.08, 0.12),
            ("a", 0.20, 0.05),      // Very short word!
            ("traveler", 0.25, 0.3)
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        let expectation = XCTestExpectation(description: "All words including short 'a'")
        expectation.expectedFulfillmentCount = 4
        var receivedWords: [String] = []

        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
            expectation.fulfill()
        }

        // When
        scheduler.start()

        // Then - all 4 words including short "a" should emit
        wait(for: [expectation], timeout: 1.0)  // Extra margin for CI
        XCTAssertEqual(receivedWords, ["I", "met", "a", "traveler"])

        // Cleanup
        scheduler.stop()
    }

    func testStopCancelsScheduledEvents() {
        // Given - word that would emit after 500ms
        let alignment = makeAlignment(words: [
            ("First", 0.0, 0.1),
            ("Later", 0.5, 0.1)  // Should NOT emit if stopped
        ])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When - start, wait for first word, then stop before second
        scheduler.start()

        let stopExpectation = XCTestExpectation(description: "Wait then stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            scheduler.stop()
            stopExpectation.fulfill()
        }

        wait(for: [stopExpectation], timeout: 0.3)

        // Wait a bit more to ensure "Later" doesn't fire
        let waitExpectation = XCTestExpectation(description: "Wait for would-be second word")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            waitExpectation.fulfill()
        }
        wait(for: [waitExpectation], timeout: 0.7)

        // Then - only "First" should have been received
        XCTAssertEqual(receivedWords, ["First"])
    }

    func testEmptyAlignmentDoesNotCrash() {
        // Given
        let alignment = makeAlignment(words: [])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var receivedWords: [String] = []
        scheduler.onWordChange = { timing in
            receivedWords.append(timing.text)
        }

        // When
        scheduler.start()

        let expectation = XCTestExpectation(description: "Wait for any emissions")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.3)

        // Then - no crashes, no emissions
        XCTAssertEqual(receivedWords, [])
        XCTAssertTrue(scheduler.isActive)

        scheduler.stop()
    }

    func testDoubleStartIsIdempotent() {
        // Given
        let alignment = makeAlignment(words: [("Test", 0.0, 0.1)])
        let scheduler = WordHighlightScheduler(alignment: alignment)

        var emitCount = 0
        scheduler.onWordChange = { _ in
            emitCount += 1
        }

        // When - start twice
        scheduler.start()
        scheduler.start()

        let expectation = XCTestExpectation(description: "Wait for emissions")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.3)

        // Then - should only emit once
        XCTAssertEqual(emitCount, 1)

        // Cleanup
        scheduler.stop()
    }
}
```

**Step 2: Run tests**

Run: `xcodebuild test -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests 2>&1 | grep -E "(Test Case|passed|failed|TEST)"`

Expected: All tests PASS

**Step 3: Commit**

```bash
git add -u
git commit -m "test(highlighting): update tests for scheduled event approach

New tests verify:
- First word emits immediately
- All words emit in order
- Short words (50ms) are NOT skipped
- Stop cancels pending events
- Empty alignment doesn't crash
- Double-start is idempotent"
```

---

## Task 7: Remove Debug Logging and Final Cleanup

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/WordHighlightScheduler.swift`

**Step 1: Remove verbose debug print statements**

Change the print statements to be less verbose:

In `scheduleWordChanges()`:
```swift
// Change:
print("[WordHighlightScheduler] Scheduled \(scheduledWorkItems.count) word changes")
// To:
print("[WordHighlightScheduler] Started (\(alignment.wordTimings.count) words)")
```

In `cancelScheduledWorkItems()`:
```swift
// Remove the print statement entirely or change to:
// (only print if there were items to cancel)
if !scheduledWorkItems.isEmpty {
    print("[WordHighlightScheduler] Stopped")
}
```

In `emitWordChange(at:)`:
```swift
// Remove the detailed logging:
// print("[WordHighlightScheduler] Word \(index): '\(timing.text)' @ ...")
// Or keep minimal version without timing details
```

**Step 2: Verify build and tests**

Run: `xcodebuild test -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/WordHighlightSchedulerTests 2>&1 | grep -E "(Test Case|passed|failed|TEST)"`

Expected: All tests PASS

**Step 3: Commit**

```bash
git add -u
git commit -m "chore(highlighting): clean up debug logging

Production-ready logging levels."
```

---

## Task 8: Manual Integration Testing

**Step 1: Build and run on simulator**

```bash
xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Step 2: Manual test checklist**

Test with Chapter 10 "I met a traveler from an antique land":

- [ ] "I" is highlighted
- [ ] "met" is highlighted
- [ ] "a" is highlighted (was previously skipped!)
- [ ] "traveler" is highlighted
- [ ] "from" is highlighted
- [ ] "an" is highlighted (was previously skipped!)
- [ ] "antique" is highlighted
- [ ] "land" is highlighted

Test pause/resume:
- [ ] Pause stops highlighting
- [ ] Resume restarts highlighting from current sentence beginning
- [ ] No crashes on pause/resume

Test "Chapter 10":
- [ ] "Chapter" is highlighted
- [ ] "10" is highlighted

**Step 3: Document any issues found**

---

## Summary

**Total Tasks:** 8
**Files Modified:** 3 (WordHighlightScheduler.swift, TTSService.swift, WordHighlightSchedulerTests.swift)
**Lines Added:** ~120
**Lines Removed:** ~100
**Net Change:** +20 lines, dramatically simpler architecture

**Key Improvement:** Short words like "a", "an", "from" will now ALWAYS be highlighted because we schedule events at exact times instead of polling.
