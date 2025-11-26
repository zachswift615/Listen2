# Background Audio Playback - Session 2 Handoff

<original_task>
Fix background audio playback in Listen2 iOS TTS app. Audio stops/pauses when the iPhone screen is locked or the app goes to background. The app should continue reading aloud with the screen locked, like other audiobook apps (Voice Dream Reader, Audible, etc.).
</original_task>

<previous_session_summary>
Session 1 concluded that **gaps between sentences** were causing iOS to suspend background audio. The recommendation was to implement AVQueuePlayer for gapless playback.

**THIS SESSION DISPROVED THAT THEORY.**
</previous_session_summary>

<work_completed>
## Session 2 Investigation

### Test 1: Single Long Audio File (CRITICAL TEST)

**Purpose:** Determine if gaps between sentences are truly the root cause.

**Method:**
- Created `BackgroundAudioTester.swift` - synthesizes ~60 seconds of continuous audio as ONE file
- Uses same audio session config as main playback
- Plays via AVAudioPlayer from file URL
- No gaps, no sentence switching - just one long file

**Result:** **AUDIO STILL STOPPED WHEN SCREEN LOCKED**

**Conclusion:** The gap theory is WRONG. The issue is more fundamental.

### Test 2: Diagnostic Logging in Main Playback Code

**Files modified:**
- `StreamingAudioPlayer.swift` - added interruption/route observers, heartbeat timer
- `AudioSessionManager.swift` - enhanced logging
- `Listen2App.swift` - added scene phase handling

**Key findings from heartbeat logs:**

```
[StreamingAudioPlayer] 💓 Heartbeat: app=active, player.isPlaying=true, time=2.0/9.3
[Listen2App] 📱 Scene phase: active -> inactive
[Listen2App] 📱 Scene phase: inactive -> background
[Listen2App] ✅ Audio session re-activated for background
[StreamingAudioPlayer] 💓 Heartbeat: app=BACKGROUND, player.isPlaying=true, time=3.0/10.6
[StreamingAudioPlayer] 💓 Heartbeat: app=BACKGROUND, player.isPlaying=true, time=3.0/10.6  <- TIME FROZEN!
[StreamingAudioPlayer] 💓 Heartbeat: app=BACKGROUND, player.isPlaying=true, time=3.0/10.6
... (time stays at 3.0 forever, isPlaying stays true)
```

**What this reveals:**
1. App successfully enters background (logs keep coming)
2. Audio session re-activation succeeds
3. `isPlaying` stays `true` (iOS LIES to us!)
4. `currentTime` advances ~1 second after lock, then **freezes**
5. **NO** interruption notification received
6. **NO** route change notification received
7. iOS silently pauses playback without telling anyone

### Test 3: Switch from AVAudioPlayer to AVPlayer

**Rationale:** AVPlayer is what podcast/music apps use, might have better background support.

**Changes to `StreamingAudioPlayer.swift`:**
- Replaced `AVAudioPlayer` with `AVPlayer` + `AVPlayerItem`
- Changed delegate methods to notification observers (`AVPlayerItemDidPlayToEndTime`)
- Added `automaticallyWaitsToMinimizeStalling = false`
- Heartbeat now shows `rate` instead of `isPlaying`

**Result:** **SAME BEHAVIOR**

```
[StreamingAudioPlayer] 💓 Heartbeat: app=active, rate=1.0, time=2.0/9.3
[Listen2App] 📱 Scene phase: inactive -> background
[Listen2App] ✅ Audio session re-activated for background
[StreamingAudioPlayer] 💓 Heartbeat: app=BACKGROUND, rate=0.0, time=3.1/9.3  <- RATE DROPPED TO 0!
[StreamingAudioPlayer] 💓 Heartbeat: app=BACKGROUND, rate=0.0, time=3.1/9.3
```

With AVPlayer, iOS actively sets `rate = 0` (pauses the player) without sending any notification.

### Test 4: Re-activate Audio Session on Background Entry

**Changes to `Listen2App.swift`:**
```swift
.onChange(of: scenePhase) { oldPhase, newPhase in
    if newPhase == .background {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true, options: [])
    }
}
```

**Result:** **NO CHANGE** - audio session re-activates successfully but audio still stops.

## What We Confirmed

### Working Correctly
- ✅ `UIBackgroundModes` with `audio` in Info.plist
- ✅ `AVAudioSession` category `.playback`, mode `.spokenAudio`
- ✅ No `.mixWithOthers` option (claims exclusive audio focus)
- ✅ File-based audio player initialization (not in-memory Data)
- ✅ `NowPlayingInfoManager` with remote commands configured
- ✅ Audio session re-activation on background entry
- ✅ App continues running in background (logs prove it)
- ✅ No interruption notifications being fired
- ✅ No route changes when locking screen

### Confirmed Broken
- ❌ Both AVAudioPlayer and AVPlayer silently pause ~1 second after entering background
- ❌ `isPlaying` property lies (stays true while playback is frozen)
- ❌ No iOS notification or callback when this happens
- ❌ Re-activating audio session doesn't prevent the pause

## Key Discovery: iOS Silent Pause Behavior

**What happens:**
1. App enters background
2. Audio continues for ~1 second
3. iOS silently pauses the player internally
4. No delegate method / notification fired
5. `isPlaying` / `rate` properties may still report "playing"
6. `currentTime` freezes
7. App code continues executing normally

**This is undocumented iOS behavior.** The system is disconnecting audio output without using the standard interruption mechanism.

</work_completed>

<work_remaining>
## Test Without Debugger: COMPLETED - STILL FAILS

User tested without debugger attached - audio still pauses when screen locks. This is NOT a debugger artifact.

## Option 1: Convert Audio to 16-bit PCM (QUICK TEST)

Current audio format is Float32 PCM in WAV container. Some iOS versions may have issues with float audio in background.

**Changes needed:**
- Modify `createWAVData()` to convert float32 samples to int16
- Change WAV format tag from 3 (IEEE float) to 1 (PCM)
- Adjust bytes per sample from 4 to 2

**Why this might help:** iOS audio decoders may have different background behavior for different formats.

## Option 2: Use Bundled Test Audio File (DIAGNOSTIC)

Test with a known-good audio format (MP3/AAC/M4A) to isolate whether the issue is:
- Our WAV format
- Our audio session config
- Something else entirely

**Test procedure:**
1. Add a 60-second MP3 file to the bundle
2. Create simple test that plays it via AVPlayer
3. Lock screen, see if it continues

If bundled MP3 works but our WAV doesn't → format issue
If bundled MP3 also fails → deeper configuration issue

## Option 3: Add UIBackgroundTaskIdentifier (CAREFULLY)

Previous session removed `beginBackgroundTask()` because it was "unnecessary for audio apps."

**However:** Maybe we need it during the transition period when iOS is deciding whether to allow background audio.

**Implementation:**
```swift
var backgroundTask: UIBackgroundTaskIdentifier = .invalid

func applicationDidEnterBackground() {
    backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
        UIApplication.shared.endBackgroundTask(self?.backgroundTask ?? .invalid)
        self?.backgroundTask = .invalid
    }
}

// End task only when audio playback actually finishes
func audioPlayerDidFinishPlaying() {
    if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
```

**Caution:** Previous attempt crashed when screen locked. Need to handle carefully.

## Option 4: RemoteIO Audio Units (NUCLEAR OPTION)

If all else fails, Audio Units run in a real-time priority thread that iOS cannot pause.

**Pros:**
- Guaranteed to work in background
- Full control over audio pipeline

**Cons:**
- Requires C/Objective-C code
- Significant rewrite
- Complex thread synchronization
- 1-2 day implementation time

**Only pursue this if Options 1-3 fail and without-debugger test fails.**

## Option 5: Research What Working Apps Do

Study apps that successfully do background TTS:
- Voice Dream Reader
- Speechify
- Natural Reader
- NaturalReader

Could try:
- Network traffic analysis during background playback
- Decompile/inspect their audio configuration
- Contact developers

</work_remaining>

<attempted_approaches>
## Session 2 Attempts (All Failed So Far)

### 1. Single Long Audio File Test
- **Purpose:** Disprove gap theory
- **Result:** Audio still stops → gaps are NOT the root cause

### 2. Diagnostic Heartbeat Logging
- **Purpose:** See exactly what happens when screen locks
- **Result:** Confirmed iOS silently pauses without notification

### 3. AVAudioPlayer → AVPlayer Switch
- **Purpose:** Try different player API
- **Result:** Same behavior - iOS sets rate=0 silently

### 4. Audio Session Re-activation on Background
- **Purpose:** Ensure session stays active
- **Result:** Re-activation succeeds but doesn't prevent pause

### 5. automaticallyWaitsToMinimizeStalling = false
- **Purpose:** Prevent buffering-related pauses
- **Result:** No change

## What We Ruled Out

- ❌ **Gap theory** - single long file also fails
- ❌ **AVAudioPlayer vs AVPlayer** - both fail identically
- ❌ **Audio session not active** - it IS active, verified in logs
- ❌ **Interruption handling** - no interruption is fired
- ❌ **Route changes** - no route change occurs
- ❌ **Configuration issues** - all configs verified correct

</attempted_approaches>

<critical_context>
## Current Code State

### StreamingAudioPlayer.swift (AVPlayer version)
```swift
// Now uses AVPlayer instead of AVAudioPlayer
private var player: AVPlayer?
private var playerItem: AVPlayerItem?

func finishScheduling() {
    // Write WAV to temp file
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")
    try wavData.write(to: tempURL)

    // Create AVPlayer
    let asset = AVURLAsset(url: tempURL)
    playerItem = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: playerItem)
    player?.automaticallyWaitsToMinimizeStalling = false

    // Observe end
    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, ...)

    player?.play()
}
```

### Listen2App.swift
```swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { oldPhase, newPhase in
    if newPhase == .background {
        // Re-activate audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true, options: [])
    }
}
```

### Heartbeat Timer (Debug - can remove later)
```swift
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    let appState = UIApplication.shared.applicationState
    let rate = player?.rate ?? 0
    let time = player?.currentTime().seconds ?? 0
    print("💓 Heartbeat: app=\(appState), rate=\(rate), time=\(time)")
}
```

## Audio Format Details
- **Sample rate:** 22050 Hz
- **Channels:** 1 (mono)
- **Format:** Float32 PCM (IEEE float)
- **WAV format tag:** 3
- **Container:** WAV file in temp directory

## Files Modified This Session

1. **`StreamingAudioPlayer.swift`** - Major rewrite to AVPlayer + diagnostic logging
2. **`AudioSessionManager.swift`** - Enhanced interruption/route logging
3. **`Listen2App.swift`** - Added scene phase handling + audio session re-activation
4. **`BackgroundAudioTester.swift`** (NEW) - Single-file test utility
5. **`SettingsView.swift`** - Added debug section for test (file not in Xcode project)

## Git Status

**Branch:** background-audio-spike (or current branch)

**Changes:** Multiple files modified, not committed (solution doesn't work yet)

## Testing Environment

- **Device:** Physical iPhone (required for background audio testing)
- **Debugger:** Attached (NEED TO TEST WITHOUT)
- **Audio output:** iPhone speaker
- **iOS Version:** Not specified (likely 17 or 18)

</critical_context>

<current_state>
## Summary

**Root cause:** UNKNOWN - but NOT gaps between sentences

**Behavior:** iOS silently pauses audio playback ~1 second after entering background, without:
- Firing interruption notification
- Changing audio route
- Calling any delegate method
- Updating `isPlaying` property (it lies)

**What works:** Everything EXCEPT actual background playback

**What's been tried:**
- AVAudioPlayer (file-based) ❌
- AVPlayer ❌
- Audio session re-activation ❌
- Single long file (no gaps) ❌

## Most Likely Next Steps

1. **TEST WITHOUT DEBUGGER** ← Do this first!
2. If still fails: Try 16-bit PCM instead of Float32
3. If still fails: Test with bundled MP3 file
4. If still fails: Try UIBackgroundTaskIdentifier
5. If still fails: RemoteIO Audio Units (nuclear option)

## Command to Resume Next Session

```
Background audio in Listen2 iOS TTS app stops when screen locks. We've ruled out the "gap theory" - even a single 60-second audio file stops. iOS silently pauses playback ~1 second after backgrounding without any notification. Both AVAudioPlayer and AVPlayer exhibit this behavior. See whats-next-2.md for full context. First step: test WITHOUT Xcode debugger attached to see if it's a debug-only issue.
```

</current_state>

<open_questions>
1. **Does it work without debugger?** - MUST TEST THIS FIRST
2. **Is Float32 WAV format the issue?** - Try 16-bit PCM
3. **Does a bundled MP3 file work?** - Isolates format vs config
4. **Do we need UIBackgroundTaskIdentifier?** - Previous removal may have been wrong
5. **What do Voice Dream Reader / Speechify do differently?** - Research needed
6. **Is there an iOS 17/18 specific issue?** - Check release notes
7. **Are there entitlements we're missing?** - None found, but worth checking
</open_questions>
