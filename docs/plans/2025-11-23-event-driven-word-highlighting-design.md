# Event-Driven Word Highlighting Design

**Date:** 2025-11-23
**Status:** Approved
**Author:** Claude + Zach

## Problem Statement

The current word highlighting system uses polling (CADisplayLink at 60fps) to check "what word is playing now?" This approach has fundamental flaws:

1. **First word skipping**: By the time the first poll fires (~85-149ms), short words like "The" (ends at 123ms) have already finished
2. **Highlighting one word behind**: Timer fires AFTER the word has started, so we're always catching up
3. **Short word skipping**: Words shorter than ~16.7ms (one frame) can be missed entirely
4. **Wall-clock drift**: Polling uses wall-clock time which can drift from actual audio playback

The CTC forced alignment data is accurate. The problem is HOW we use it.

## Solution: Event-Driven Word Scheduling

Replace polling with scheduled callbacks based on audio render position.

### Core Insight

Instead of:
```
Timer fires → Check currentTime → Find word at that time → Update UI
```

Do:
```
Audio callback fires → Get actual frame position → Find word → Update UI only if changed
```

The key difference: we use the **audio render callback** which is locked to actual playback, not a wall-clock timer that can drift.

## Architecture

### New Component: WordHighlightScheduler

A dedicated class that:
- Receives `playerNode` reference and `AlignmentResult`
- Installs tap on the audio node
- Monitors frame position in audio callback
- Dispatches word change events to main thread
- Has simple lifecycle: `start()` and `stop()`

### Component Responsibilities

```
┌─────────────────────────────────────────────────────────────────┐
│                         TTSService                               │
│  ┌─────────────┐    ┌──────────────────────┐                    │
│  │ ReadyQueue  │───▶│ playReadySentence()  │                    │
│  │ (synthesis  │    │                      │                    │
│  │ + alignment)│    │  Creates scheduler   │                    │
│  └─────────────┘    │  per sentence        │                    │
│                     └──────────┬───────────┘                    │
│                                │                                 │
│                                ▼                                 │
│                     ┌──────────────────────┐                    │
│                     │ WordHighlightScheduler│                    │
│                     │                      │                    │
│                     │  • Owns alignment    │                    │
│                     │  • Installs tap      │                    │
│                     │  • Emits word changes│                    │
│                     └──────────┬───────────┘                    │
│                                │                                 │
│                                │ onWordChange                    │
│                                ▼                                 │
│                     ┌──────────────────────┐                    │
│                     │ currentProgress      │───▶ UI (ReaderView)│
│                     │ (Published)          │                    │
│                     └──────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ playerNode reference
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    StreamingAudioPlayer                          │
│  ┌─────────────┐                                                │
│  │ playerNode  │◀─── tap installed by WordHighlightScheduler    │
│  │ (exposed)   │                                                │
│  └─────────────┘                                                │
│                                                                  │
│  • Schedules audio buffers                                      │
│  • Manages AVAudioEngine                                        │
│  • No highlighting logic                                        │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Design

### WordHighlightScheduler

```swift
@MainActor
final class WordHighlightScheduler {

    // Dependencies
    private let playerNode: AVAudioPlayerNode
    private let alignment: AlignmentResult
    private let sampleRate: Double = 22050

    // State
    private var currentWordIndex: Int = -1
    private var isActive: Bool = false

    // Output
    var onWordChange: ((AlignmentResult.WordTiming) -> Void)?

    init(playerNode: AVAudioPlayerNode, alignment: AlignmentResult)
    func start()  // Installs tap
    func stop()   // Removes tap
}
```

### Audio Tap Implementation

```swift
private func installTap() {
    playerNode.installTap(
        onBus: 0,
        bufferSize: 1024,
        format: playerNode.outputFormat(forBus: 0)
    ) { [weak self] buffer, time in
        // AUDIO THREAD - minimal work only!
        guard let self = self else { return }
        let framePosition = time.sampleTime

        DispatchQueue.main.async {
            self.handleFramePosition(framePosition)
        }
    }
}

private func handleFramePosition(_ framePosition: AVAudioFramePosition) {
    // MAIN THREAD - safe to do real work
    guard isActive else { return }

    let currentTime = Double(framePosition) / sampleRate
    guard let wordIndex = findWordIndex(at: currentTime) else { return }

    // Only emit if word changed
    if wordIndex != currentWordIndex {
        currentWordIndex = wordIndex
        onWordChange?(alignment.wordTimings[wordIndex])
    }
}
```

### Audio Thread Safety

The audio callback runs on a real-time thread with strict constraints:

**Cannot do:**
- Allocate memory
- Take locks
- Call Objective-C runtime
- Any I/O

**Our approach:**
- Callback does only 2 things: read frame position, dispatch to main
- All real work happens on main thread
- This is the standard pattern for audio visualization

### TTSService Integration

```swift
// New property
private var wordScheduler: WordHighlightScheduler?

// In playReadySentence()
if let alignment = sentence.alignment {
    wordScheduler?.stop()

    let scheduler = WordHighlightScheduler(
        playerNode: audioPlayer.playerNode,
        alignment: alignment
    )

    scheduler.onWordChange = { [weak self] timing in
        self?.handleWordChange(timing)
    }

    scheduler.start()
    wordScheduler = scheduler
}

// Word change handler
private func handleWordChange(_ timing: AlignmentResult.WordTiming) {
    guard let paragraphText = currentText[safe: currentProgress.paragraphIndex],
          let range = timing.stringRange(in: paragraphText) else {
        return
    }

    currentProgress = ReadingProgress(
        paragraphIndex: currentProgress.paragraphIndex,
        wordRange: range,
        isPlaying: true
    )
}
```

### StreamingAudioPlayer Changes

Minimal change - just expose the player node:

```swift
// Change from private to internal
let playerNode = AVAudioPlayerNode()
```

Remove display link code (no longer needed for highlighting).

### Pause/Resume Behavior

Following Voice Dream Reader UX:
- On pause: Stop scheduler, clear highlight
- On resume: Restart from sentence beginning (scheduler recreated)

```swift
func pause() {
    wordScheduler?.stop()
    wordScheduler = nil

    audioPlayer.pause()
    isPlaying = false

    currentProgress = ReadingProgress(
        paragraphIndex: currentProgress.paragraphIndex,
        wordRange: nil,
        isPlaying: false
    )
}
```

### Settings Change Fix

Track highlighting setting changes to invalidate stale buffers:

```swift
private var previousHighlightingSetting: Bool = true

func startReading(paragraphs: [String], from index: Int, ...) {
    if wordHighlightingEnabled != previousHighlightingSetting {
        Task {
            await readyQueue?.stopPipeline()
            await readyQueue?.clearAll()
        }
        previousHighlightingSetting = wordHighlightingEnabled
    }
    // ... existing code ...
}
```

## Code to Remove

The following polling-related code will be deleted:

**Properties (~7):**
- `highlightTimer: Timer?`
- `currentAlignment: AlignmentResult?` (scheduler owns this now)
- `lastHighlightedWordIndex: Int?`
- `lastHighlightChangeTime: TimeInterval`
- `maxStuckDuration: TimeInterval`
- `minWordIndex: Int`
- `stuckWordWarningCount: [Int: Int]`

**Methods (~4):**
- `startHighlightTimer()`
- `stopHighlightTimer()`
- `startHighlightTimerWithCTCAlignment()`
- `updateHighlightFromTime()`

**Estimated removal:** ~150 lines of timer/polling code

## Benefits

1. **No drift by design**: Reading actual audio position, not guessing
2. **Pause/resume for free**: When audio stops, callback stops
3. **Frame-level accuracy**: Uses CTC alignment precision properly
4. **Simpler code**: Remove ~150 lines of workarounds
5. **No fallback needed**: Event-driven or nothing (clean failure)

## Testing Strategy

1. **Unit test WordHighlightScheduler**: Mock playerNode, verify word change emissions
2. **Integration test**: Verify first word highlights immediately on playback start
3. **Edge cases**: Very short words, pause during word, speed changes
4. **Manual testing**: Compare against Voice Dream Reader behavior

## Implementation Order

1. Create `WordHighlightScheduler` class
2. Expose `playerNode` in `StreamingAudioPlayer`
3. Integrate scheduler in `TTSService.playReadySentence()`
4. Update pause/resume to use scheduler lifecycle
5. Add settings change detection
6. Remove old polling code
7. Test thoroughly
