# Background Audio Playback - Session Handoff

<original_task>
Fix background audio playback in Listen2 iOS TTS app. Audio stops/pauses when the iPhone screen is locked or the app goes to background. The app should continue reading aloud with the screen locked, like other audiobook apps (Voice Dream Reader, Audible, etc.).
</original_task>

<work_completed>
## Investigation & Diagnosis

### Initial Exploration (2 parallel Explore agents)
- Confirmed `UIBackgroundModes` with `audio` present in Info.plist (line with `<string>audio</string>`)
- Confirmed AVAudioSession configured with `.playback` category, `.spokenAudio` mode in `AudioSessionManager.swift`
- Confirmed no `.mixWithOthers` option (correct - claims exclusive audio focus)
- Confirmed NowPlayingInfoManager integration exists for lock screen controls
- Found existing interruption/route change handling in AudioSessionManager

### Root Cause Discovery
Through testing and research, discovered **AVAudioEngine cannot be started/restarted while app is backgrounded since iOS 12.4**. This is a fundamental iOS limitation, not a configuration issue.

Evidence:
- Logs showed `audioEngine.isRunning: true` and `playerNode.isPlaying: true` even in background
- Buffers completed successfully while backgrounded
- Code continued executing in background
- But **no audio output** - iOS disconnects the engine's audio output when backgrounded

### Attempted Fix #1: AVAudioEngine Configuration (FAILED)
**Files modified:** `StreamingAudioPlayer.swift`, `Listen2App.swift`

**Changes made:**
- Added observer for `AVAudioEngine.configurationChangeNotification`
- Implemented `handleEngineConfigurationChange()` to restart engine
- Added `mediaServicesResetObserver` and handler
- Added app lifecycle observers with `scenePhase` to re-activate audio session on background
- Added logging throughout to track engine/node state

**Why it failed:**
- iOS doesn't fire configuration change notification when screen locks
- Even if notification fired, engine cannot be restarted while backgrounded (iOS 12.4+ limitation)
- Web research confirmed this is a known limitation with no workaround at AVAudioEngine level

**All changes from Attempt #1 were REVERTED via `git checkout`**

### Attempted Fix #2: Route Change Observer Bug (PARTIAL FIX)
**File modified:** `TTSService.swift` (lines 223-240)

**Bug found:** Original route change observer paused playback whenever route didn't contain "Headphone":
```swift
if self?.isPlaying == true && !route.contains("Headphone") {
    self?.pause()
}
```
This incorrectly paused when:
- Playing through speaker (no headphones)
- Screen locked (iOS may internally change route slightly)
- Any route change occurred

**Fix applied:** Modified to only pause on actual device disconnection:
1. First iteration: Track previous route, only pause if headphones were connected then disconnected
2. Second iteration: Simplified to use `AudioSessionManager.$deviceWasDisconnected` published property

**File modified:** `AudioSessionManager.swift`
- Added `@Published private(set) var deviceWasDisconnected: Bool = false` (line 19)
- Modified `handleRouteChange()` to set `deviceWasDisconnected = true` on `.oldDeviceUnavailable` (lines 179-186)

**Result:** Bug fixed but audio still stopped in background - not the root cause

### Attempted Fix #3: Switched to AVAudioPlayer with In-Memory Data (FAILED)
**File completely rewritten:** `StreamingAudioPlayer.swift`

**What we did:**
- Removed all AVAudioEngine code (audioEngine, playerNode, buffer scheduling)
- Changed to AVAudioPlayer-based implementation
- Accumulated chunks in `Data` buffer via `scheduleChunk()`
- Created WAV header (44 bytes) + wrapped float32 PCM data
- Used `AVAudioPlayer(data: wavData)` to play from memory in `finishScheduling()`

**WAV header implementation:**
```swift
private func createWAVData(from pcmData: Data) -> Data {
    // RIFF header + fmt chunk + data chunk
    // Format: Float32 PCM (format tag 3), 22050 Hz, mono, 32 bits per sample
}
```

**Why it failed:**
Consulted Claude.ai for fresh perspective. Key finding: **AVAudioPlayer initialized with in-memory `Data` doesn't reliably play in background**, even with correct audio session setup. This is a known iOS limitation (undocumented but widely reported).

### Attempted Fix #4: File-Based AVAudioPlayer (CURRENT STATE - STILL FAILS)
**File modified:** `StreamingAudioPlayer.swift`

**Changes made:**
```swift
func finishScheduling() {
    let wavData = createWAVData(from: audioDataBuffer)

    // Write to temporary file (required for background audio)
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")
    try wavData.write(to: tempURL)

    // Initialize from file URL (not Data)
    player = try AVAudioPlayer(contentsOf: tempURL)
    player?.delegate = self
    player?.prepareToPlay()
    player?.play()

    // Track temp file for cleanup
    currentTempFileURL = tempURL
}
```

- Added `private var currentTempFileURL: URL?` property
- Added `cleanupTempFile()` method to remove temp files
- Called cleanup in `stop()` and `deinit`

**Testing:**
- Built and tested on physical iPhone (no debugger attached)
- Audio still pauses when screen locks
- **This fix addressed the AVAudioPlayer requirement but NOT the root cause**

## Research & External Consultation

### Web Research Findings

**AVAudioEngine background limitations:**
- Cannot start/restart in background since iOS 12.4 (confirmed Apple limitation)
- All open-source libraries inherit this: AudioStreaming, SwiftAudioPlayer, SwiftAudioEx, SFBAudioEngine
- Only workaround: Use RemoteIO Audio Units (low-level C API, very complex)

**AVAudioPlayer background requirements (from Claude.ai):**
1. ✅ Must use file-based initialization (`contentsOf:`) not in-memory (`data:`)
2. ⚠️ **Must have continuous playback with no gaps between segments**
3. ✅ Audio session properly configured (.playback, .spokenAudio)
4. ✅ Background mode enabled in Info.plist

**Voice Dream Reader (successful iOS TTS app):**
- Supports background playback: "all voices work offline and play in the background even with the screen locked"
- Likely uses AVAudioPlayer/AVPlayer (not AVAudioEngine)
- Possibly uses RemoteIO Audio Units for streaming

### Critical Discovery: Playback Gaps Cause Suspension

**The likely root cause of background audio failure:**

Current playback flow creates gaps between sentences:
1. Sentence 1 finishes playing → `audioPlayerDidFinishPlaying()` fires
2. Calls `onFinished()` callback → continuation resumes
3. Async function returns
4. **GAP - NO AUDIO PLAYING** while next sentence is prepared
5. TTSService gets next sentence from ReadyQueue
6. New `playReadySentence()` call starts
7. Sentence 2 begins playing

**During the gap:**
- No audio is playing
- iOS detects silence in a "background audio" app
- iOS suspends background audio capability
- Even when next sentence starts, audio output remains disconnected

**Evidence:**
- ReadyQueue pre-processes sentences (they're ready before needed)
- But StreamingAudioPlayer only plays ONE sentence at a time
- No queuing or gapless playback mechanism
- Each sentence creates a new AVAudioPlayer instance
- User confirmed: "when I locked the screen on the word 'important'... it faded out from 'important' to 'society' then when I opened the screen (after about 10 seconds) it started playing from 'A fun read'"
  - This shows audio continued in background code-wise (skipped ahead)
  - But output was muted by iOS (no sound heard during locked period)

## Logging & Debug Output

### User-provided logs showed:
```
[Listen2App] 📱 App entered background - ensuring audio session is active
[Listen2App] ✅ Audio session confirmed active - category: AVAudioSessionCategoryPlayback, mode: AVAudioSessionModeSpokenAudio
[CTCForcedAligner] ONNX inference took 2.514s for 166997 samples
[StreamingAudioPlayer] ✓ Buffer #1 complete (played: 1/2)
[StreamingAudioPlayer] 🏁 All buffers played, calling onFinished
[StreamingAudioPlayer] 🎬 Started streaming session
[Listen2App] 📱 App became active
```

Key observation: Buffers completing and new sessions starting while backgrounded, but user heard no audio.

</work_completed>

<work_remaining>
## The Path Forward: Eliminate Playback Gaps

### Option 1: AVQueuePlayer for Gapless Playback (RECOMMENDED)

**Why this should work:**
- AVQueuePlayer is designed specifically for gapless playback of sequential items
- Can pre-queue next item before current one finishes
- Eliminates the gap that causes iOS to suspend background audio
- Higher-level API than Audio Units (less complexity than Option 3)

**Implementation steps:**
1. Modify `StreamingAudioPlayer.swift` to use `AVQueuePlayer` instead of `AVAudioPlayer`
2. Change architecture to queue-based:
   - When `finishScheduling()` called, create `AVPlayerItem` from temp file URL
   - Add item to AVQueuePlayer queue
   - Start observing item completion
3. Pre-queue next sentence:
   - In `TTSService.playReadySentence()`, check if ReadyQueue has next sentence ready
   - If yes, immediately prepare it (write to temp file, create AVPlayerItem)
   - Queue it BEFORE current item finishes
4. Handle item completion:
   - Observe `AVPlayerItemDidPlayToEndTime` notification
   - Remove played item, clean up its temp file
   - Trigger `onFinished()` callback for sentence completion
5. Track current item for progress/word highlighting:
   - Need to know which AVPlayerItem is currently playing
   - Map items to sentence data for word highlighting

**Challenges:**
- More complex than AVAudioPlayer (managing queue, multiple temp files)
- Need to track which item is playing for word highlighting sync
- AVPlayerItem requires URLs (using file:// URLs to temp files)

**Files to modify:**
- `StreamingAudioPlayer.swift` - switch from AVAudioPlayer to AVQueuePlayer
- `TTSService.swift` - modify playReadySentence() to pre-queue next item

### Option 2: Pre-create Next AVAudioPlayer (SIMPLER, MAY NOT WORK)

**Why this might work:**
- Prepare next AVAudioPlayer BEFORE current one finishes
- In `audioPlayerDidFinishPlaying()`, immediately call `play()` on pre-created instance
- Minimize gap to microseconds instead of milliseconds

**Why it might still fail:**
- Even microsecond gaps might trigger suspension
- No guarantee of true gapless playback
- Still requires async coordination

**Implementation:**
1. Add `private var nextPlayer: AVAudioPlayer?` to StreamingAudioPlayer
2. Add method `prepareNext(_ audioData: Data)` that creates but doesn't start next player
3. In TTSService, call `prepareNext()` when current sentence starts playing (with next sentence data)
4. In `audioPlayerDidFinishPlaying()`, immediately `nextPlayer?.play()` and swap references

### Option 3: RemoteIO Audio Units (MOST RELIABLE, MOST COMPLEX)

**Why this WILL work:**
- Audio Units run in real-time priority thread
- Continue operating in background (designed for this)
- Full control over audio rendering pipeline
- Professional audio apps use this approach

**Implementation approach:**
1. Set up RemoteIO Audio Unit (Audio Component API)
2. Implement render callback (C function):
   ```c
   OSStatus renderCallback(void *inRefCon,
                          AudioUnitRenderActionFlags *ioActionFlags,
                          const AudioTimeStamp *inTimeStamp,
                          UInt32 inBusNumber,
                          UInt32 inNumberFrames,
                          AudioBufferList *ioData)
   ```
3. Create ring buffer (TPCircularBuffer or custom)
4. TTS generates chunks → write to ring buffer
5. Render callback pulls from ring buffer → fills ioData

**Challenges:**
- Requires C/Objective-C code (Swift interop possible but awkward)
- Steep learning curve (CoreAudio is complex)
- Need to handle buffer underruns gracefully
- Significant rewrite of audio architecture
- Thread synchronization between TTS generation and render callback

**Resources:**
- [Twilio AVAudioEngine + Audio Units example](https://github.com/twilio/video-quickstart-ios/blob/master/AudioDeviceExample/AudioDevices/ExampleAVAudioEngineDevice.m)
- [Audio Unit Render Callback](https://stackoverflow.com/questions/8259944/how-to-use-ios-audiounit-render-callback-correctly)

### Option 4: Use AVPlayer Instead (SIMILAR TO OPTION 1)

**Difference from AVQueuePlayer:**
- AVPlayer is lower-level, single-item player
- Would need manual queue management
- AVQueuePlayer is built on AVPlayer but handles queuing

**Verdict:** Just use AVQueuePlayer (Option 1) - it's designed for this

## Immediate Next Steps

1. **Try AVQueuePlayer first** (Option 1)
   - Best balance of reliability vs. complexity
   - Designed for gapless playback use case
   - Still high-level API (not as complex as Audio Units)

2. **If AVQueuePlayer fails, measure the gap**
   - Add precise timing logs to measure actual gap duration
   - Determine if gap is the true root cause or if there's something else

3. **If gaps are confirmed as root cause and AVQueuePlayer doesn't work:**
   - Consider Audio Units (Option 3) as the nuclear option
   - Would require dedicated learning time + C/Objective-C code

</work_remaining>

<attempted_approaches>
## What We Tried (In Order)

### 1. AVAudioEngine Configuration & Restart (FAILED)
- Added configuration change notifications
- Attempted to restart engine in background
- Added app lifecycle observers
- **Failed because:** iOS limitation - engine cannot restart while backgrounded

### 2. Fixed Route Change Observer Bug (PARTIAL SUCCESS)
- Fixed overly aggressive pause trigger
- Only pause on actual device disconnection
- **Helped but:** Not the root cause of background suspension

### 3. In-Memory AVAudioPlayer (FAILED)
- Complete rewrite from AVAudioEngine to AVAudioPlayer
- Accumulated chunks, created WAV data in memory
- Used `AVAudioPlayer(data:)`
- **Failed because:** In-memory AVAudioPlayer doesn't work reliably in background (iOS limitation)

### 4. File-Based AVAudioPlayer (FAILED)
- Write WAV to temp file
- Use `AVAudioPlayer(contentsOf:)`
- Clean up temp files
- **Failed because:** Still has gaps between sentences → iOS suspends

## What We Learned

### Confirmed Working
- Info.plist `UIBackgroundModes` configuration is correct
- AVAudioSession category/mode configuration is correct
- File-based AVAudioPlayer initialization is correct
- Route change handling is correct

### Confirmed Problems
- AVAudioEngine fundamentally doesn't support background (iOS 12.4+)
- In-memory AVAudioPlayer doesn't work in background
- **Gaps between sentences cause iOS to suspend background audio**
- One-sentence-at-a-time playback creates unavoidable gaps

### Dead Ends to Avoid
- Don't try to fix AVAudioEngine for background - it's an iOS limitation
- Don't use in-memory Data for AVAudioPlayer - must use file URLs
- Don't try to "fix" the gap with faster code - need architectural change (queuing)

</attempted_approaches>

<critical_context>
## Audio Format Details
- **Sample rate:** 22050 Hz
- **Channels:** 1 (mono)
- **Format:** Float32 PCM (little-endian)
- **WAV format tag:** 3 (IEEE float)
- **Source:** sherpa-onnx TTS engine generates chunks as Data containing float32 samples

## Current Architecture (Playback Flow)

```
TTSService.startReading()
  ↓
ReadyQueue (actor) - pre-processes sentences:
  - Synthesis (sherpa-onnx TTS) → audio chunks
  - Alignment (CTCForcedAligner) → word timings
  - Outputs: ReadySentence (chunks + alignment)
  ↓
TTSService.playReadySentence() - async function:
  1. audioPlayer.startStreaming(onFinished: {...})
  2. for chunk in sentence.chunks:
       audioPlayer.scheduleChunk(chunk)  // accumulates in buffer
  3. audioPlayer.finishScheduling()       // creates file, plays
  4. await continuation                   // waits for onFinished
  ↓
AVAudioPlayer plays file
  ↓
audioPlayerDidFinishPlaying() fires
  ↓
onFinished() callback → continuation.resume()
  ↓
playReadySentence() returns
  ↓
[GAP - NO AUDIO PLAYING]
  ↓
Loop back to get next sentence from ReadyQueue
```

**The gap** occurs between `playReadySentence()` returning and the next call starting.

## Key Constraints & Requirements

### User Requirements
- Continue playing when screen is locked
- Work with ANY audio output: speaker, wired headphones, Bluetooth, AirPods
- Pause when headphones/device disconnected
- Lock screen controls should work (play/pause/skip)

### Technical Constraints
- ReadyQueue already pre-processes sentences (they're ready before needed - good!)
- Word highlighting requires knowing which sentence is playing
- Streaming benefits when highlighting is OFF (could start sooner)
- Cannot use AVAudioEngine (iOS limitation)
- Must use file-based AVAudioPlayer/AVPlayer (not in-memory)
- Must eliminate gaps for background audio to work

## Files Modified This Session

### Modified (uncommitted)
1. **`StreamingAudioPlayer.swift`** - Complete rewrite
   - Removed: AVAudioEngine, AVAudioPlayerNode, buffer scheduling
   - Added: AVAudioPlayer, Data accumulation, WAV file creation, temp file management

2. **`TTSService.swift`** - Route change observer fix
   - Lines 223-240: Changed from route string comparison to deviceWasDisconnected signal

3. **`AudioSessionManager.swift`** - Device disconnection signal
   - Line 19: Added `@Published private(set) var deviceWasDisconnected: Bool = false`
   - Lines 179-186: Set deviceWasDisconnected on `.oldDeviceUnavailable`

### Unmodified (original AVAudioEngine version - before session)
- All other files remain as they were

## Testing Environment

- **Device:** Physical iPhone (not Simulator)
- **iOS Version:** Modern (17/18 likely, not specified)
- **Testing method:** Built from Xcode, then disconnected and launched manually (no debugger)
- **Audio outputs tested:** iPhone speaker, wired headphones - same behavior
- **Result:** Audio pauses ~1 second after screen lock, every time

## Key Insights from User Testing

User provided detailed observation:
> "I locked the screen on the word 'important' in 'basic principles of the most important technologies undergirding modern society... A fun read full of optimism' and it faded out from 'important' to 'society' then when I opened the screen (after about 10 seconds) it started playing from 'A fun read'."

**What this tells us:**
- Audio continued playing for 1-2 words after lock (fade out from "important" to "society")
- Then audio stopped
- Code kept running (progressed from sentence 1 to sentence 2 in background)
- But no audio output during background (skipped ahead when unlocked)
- This confirms: **gaps between sentences cause iOS to disconnect audio output**

## Workshop Context

This session did NOT use the workshop CLI to record decisions. Consider using workshop for the next session to maintain institutional knowledge:
```bash
workshop decision "Background audio requires gapless playback with AVQueuePlayer" \
  -r "AVAudioEngine can't restart in background (iOS 12.4+), AVAudioPlayer gaps cause suspension"

workshop gotcha "AVAudioPlayer(data:) doesn't work in background - must use contentsOf: file URL" \
  -t ios -t background-audio

workshop goal add "Implement AVQueuePlayer for gapless sentence playback"
```

</critical_context>

<current_state>
## Git Status

**Branch:** main
**Uncommitted changes:**
```
Modified: Listen2/Listen2/Listen2/Services/TTS/StreamingAudioPlayer.swift
Modified: Listen2/Listen2/Listen2/Services/TTSService.swift
Modified: Listen2/Listen2/Listen2/Services/AudioSessionManager.swift
```

**Not committed because:** Solution doesn't work yet - audio still stops in background

## Build Status

✅ Code compiles successfully
✅ App runs on device
❌ Background audio still doesn't work

## Known Issues

1. **Primary issue:** Audio stops when screen locks (unresolved)
2. **Root cause identified:** Gaps between sentences cause iOS to suspend background audio
3. **Current implementation:** File-based AVAudioPlayer (correct) but no queuing (incorrect)

## Solution Status

**Confirmed requirements:**
- ✅ UIBackgroundModes: audio
- ✅ AVAudioSession: .playback, .spokenAudio
- ✅ File-based AVAudioPlayer (not in-memory)
- ❌ Gapless playback (NOT IMPLEMENTED YET)

**Next implementation:** AVQueuePlayer to eliminate gaps

## Recommended Next Steps

1. **Implement AVQueuePlayer** (see Option 1 in work_remaining)
   - Should take 2-4 hours to implement and test
   - High confidence this will work

2. **If AVQueuePlayer still fails:**
   - Add precise gap measurement logging
   - Consider if there's another issue beyond gaps

3. **If gaps confirmed but AVQueuePlayer insufficient:**
   - Commit to RemoteIO Audio Units approach
   - Budget 1-2 days for learning + implementation

## Files to Focus On

**For AVQueuePlayer implementation:**
- `StreamingAudioPlayer.swift` - switch from AVAudioPlayer to AVQueuePlayer
- `TTSService.swift` - modify playReadySentence() to queue next item before current finishes

**Reference for understanding flow:**
- `ReadyQueue.swift` - understand sentence preparation pipeline
- `ReadySentence.swift` - sentence data structure

## Open Questions

1. **How long is the actual gap?** - Could add timestamp logging to measure precisely
2. **Does ReadyQueue always have next sentence ready when current finishes?** - Likely yes, but verify
3. **Will 0ms gap still cause suspension?** - Probably yes, need true queuing/overlap
4. **Are there iOS 17/18 specific requirements?** - Research didn't find any

## Useful Resources for Next Session

- [AVQueuePlayer Documentation](https://developer.apple.com/documentation/avfoundation/avqueueplayer)
- [AVPlayerItem Observation](https://developer.apple.com/documentation/avfoundation/avplayeritem)
- [Gapless Playback Guide](https://stackoverflow.com/questions/tagged/avqueueplayer+gapless)
- Voice Dream Reader app - working example of iOS TTS background audio (proprietary)

## Command to Resume Next Session

```
I need to implement gapless background audio playback for my iOS TTS app. We've confirmed the issue is gaps between sentences causing iOS to suspend background audio. See whats-next.md for full context. Current approach: switch from AVAudioPlayer to AVQueuePlayer to pre-queue next sentence before current finishes. Files to modify: StreamingAudioPlayer.swift and TTSService.swift.
```

</current_state>
