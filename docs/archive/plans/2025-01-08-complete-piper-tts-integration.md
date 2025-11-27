# Complete Piper TTS Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete remaining Piper TTS features: voice picker UX, loading indicator, and play button fix.

**Architecture:** Prioritize Piper voices in UI with iOS voices as fallback option. Add async loading state. Fix isPlaying state management.

**Tech Stack:** SwiftUI, AVFoundation, Piper TTS (sherpa-onnx), Combine

---

## Context

Piper TTS is now functional:
- espeak-ng-data directory structure preserved (folder reference)
- Auto-advance working correctly
- tar.bz2 extraction implemented
- AVVoice model extended to support Piper voices (isPiperVoice flag)

Remaining work:
1. Voice picker shows ONLY Piper voices (iOS voices in separate fallback menu)
2. Loading indicator during slow Piper initialization
3. Fix play button flickering (isPlaying state issue)

**Working Directory:** `/Users/zachswift/projects/Listen2/.worktrees/feature-piper-tts-integration/Listen2/Listen2`

---

## Task 1: Update TTSService to Provide Piper Voices

**Files:**
- Modify: `Listen2/Services/TTSService.swift:149-153`

**Goal:** Change `availableVoices()` to return only downloaded Piper voices, add separate method for iOS voices.

**Step 1: Add method to get Piper voices only**

In `TTSService.swift` after line 153, add:

```swift
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
```

**Step 2: Update availableVoices() to return Piper voices by default**

Replace the existing `availableVoices()` method (lines 149-153) with:

```swift
func availableVoices() -> [AVVoice] {
    piperVoices()
}
```

**Step 3: Update setVoice() to handle Piper voices**

Replace `setVoice(_ voice: AVVoice)` method (lines 184-186) with:

```swift
func setVoice(_ voice: AVVoice) {
    if voice.isPiperVoice {
        // Extract voice ID from "piper:en_US-lessac-medium" format
        let voiceID = String(voice.id.dropFirst(6))  // Remove "piper:" prefix

        // Reinitialize Piper provider with new voice
        Task {
            do {
                let piperProvider = PiperTTSProvider(
                    voiceID: voiceID,
                    voiceManager: voiceManager
                )
                try await piperProvider.initialize()
                self.provider = piperProvider

                // Update synthesis queue
                self.synthesisQueue = await SynthesisQueue(provider: piperProvider)

                print("[TTSService] ✅ Switched to Piper voice: \(voiceID)")
            } catch {
                print("[TTSService] ⚠️ Failed to switch Piper voice: \(error)")
            }
        }
    } else {
        // iOS voice - set for fallback
        currentVoice = AVSpeechSynthesisVoice(identifier: voice.id)
    }
}
```

**Step 4: Build and verify compilation**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add Listen2/Services/TTSService.swift
git commit -m "feat: add Piper voice selection support

- Add piperVoices() and iosVoices() methods
- Update availableVoices() to return Piper voices by default
- Add voice switching logic for Piper voices
- Reinitialize provider when Piper voice changes"
```

---

## Task 2: Update Voice Picker UI

**Files:**
- Modify: `Listen2/Views/SettingsView.swift` (voice picker section)

**Goal:** Show Piper voices by default, add "Use iOS Voices" option to access fallback.

**Step 1: Find the voice picker section in SettingsView**

Use grep to locate:

Run: `grep -n "Picker.*Voice" Listen2/Views/SettingsView.swift`

**Step 2: Replace voice picker with Piper-first UI**

Locate the voice picker (likely around Section with "Voice" header). Replace with:

```swift
Section {
    // Piper voices
    Picker("Voice", selection: $selectedVoiceID) {
        ForEach(ttsService.piperVoices()) { voice in
            Text(voice.displayName)
                .tag(voice.id)
        }
    }

    // Toggle to show iOS voices (fallback)
    Toggle("Use iOS Voice (Fallback)", isOn: $useIOSVoice)

    // iOS voice picker (only shown when toggle enabled)
    if useIOSVoice {
        Picker("iOS Voice", selection: $selectedVoiceID) {
            ForEach(ttsService.iosVoices()) { voice in
                Text(voice.displayName)
                    .tag(voice.id)
            }
        }
    }
} header: {
    Text("Voice")
} footer: {
    if useIOSVoice {
        Text("Using iOS voice as fallback. Piper voices offer better quality.")
    } else {
        Text("Neural TTS voices powered by Piper")
    }
}
```

**Step 3: Add @State variable for iOS voice toggle**

At the top of SettingsView (near other @State variables), add:

```swift
@State private var useIOSVoice = false
```

**Step 4: Build and verify**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add Listen2/Views/SettingsView.swift
git commit -m "feat: prioritize Piper voices in voice picker UI

- Show Piper voices by default
- Add toggle to access iOS voices (fallback)
- Update footer text to explain voice types
- Hide iOS picker unless toggle enabled"
```

---

## Task 3: Add Loading Indicator During Piper Initialization

**Files:**
- Modify: `Listen2/Services/TTSService.swift:42-84`
- Modify: `Listen2/Listen2App.swift` (main app entry point)

**Goal:** Show loading screen while Piper TTS loads 60MB model on startup.

**Step 1: Add @Published loading state to TTSService**

In `TTSService.swift` after line 23 (after playbackRate property), add:

```swift
@Published private(set) var isInitializing: Bool = false
```

**Step 2: Update initializePiperProvider() to set loading state**

Replace the `initializePiperProvider()` method (lines 63-84) with:

```swift
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
        self.synthesisQueue = await SynthesisQueue(provider: piperProvider)

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
```

**Step 3: Create loading view**

Create new file: `Listen2/Views/LoadingView.swift`

```swift
//
//  LoadingView.swift
//  Listen2
//
//  Loading screen for Piper TTS initialization
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(DesignSystem.Colors.primary)

            Text("Loading Voice Engine...")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("This will only take a moment")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

#Preview {
    LoadingView()
}
```

**Step 4: Update Listen2App.swift to show loading view**

Find the main app body. Wrap ContentView with conditional loading check:

```swift
@main
struct Listen2App: App {
    @StateObject private var ttsService = TTSService()

    var body: some Scene {
        WindowGroup {
            if ttsService.isInitializing {
                LoadingView()
            } else {
                ContentView()
                    .environmentObject(ttsService)
            }
        }
    }
}
```

**Step 5: Build and test**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

**Step 6: Commit**

```bash
git add Listen2/Services/TTSService.swift Listen2/Views/LoadingView.swift Listen2/Listen2App.swift
git commit -m "feat: add loading indicator for Piper initialization

- Add isInitializing published state to TTSService
- Create LoadingView with progress indicator
- Show loading screen during Piper model load
- Update Listen2App to conditionally show loading"
```

---

## Task 4: Fix Play Button Flickering

**Files:**
- Modify: `Listen2/Services/TTSService.swift:266-310`

**Goal:** Fix isPlaying state management to prevent play/pause button flickering.

**Step 1: Analyze the issue**

The flickering is likely caused by:
1. `isPlaying` set to `true` in `speakParagraph()` (line 274)
2. `isPlaying` set to `false` in `handleParagraphComplete()` (line 330)
3. Race condition between these updates

**Step 2: Update speakParagraph() to not set isPlaying immediately**

In `speakParagraph()` method, REMOVE line 274:

```swift
// DELETE THIS LINE:
isPlaying = true  // Remove - will be set in playAudio()
```

The `playAudio()` method already sets `isPlaying = true` (line 320), so this is duplicate.

**Step 3: Ensure handleParagraphComplete() properly manages state**

Update `handleParagraphComplete()` method (line 329-340) to:

```swift
private func handleParagraphComplete() {
    // Only set isPlaying to false after brief delay to prevent flicker
    // when auto-advancing to next paragraph
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Only set to false if we're not already playing next paragraph
        if !isPlaying {
            return
        }

        guard shouldAutoAdvance else {
            isPlaying = false
            return
        }

        let nextIndex = currentProgress.paragraphIndex + 1
        if nextIndex < currentText.count {
            speakParagraph(at: nextIndex)
        } else {
            isPlaying = false
            nowPlayingManager.clearNowPlayingInfo()
        }
    }
}
```

**Step 4: Build and verify**

Run: `xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Test on device**

Manual test: Press play and observe play/pause button. Should not flicker between paragraphs.

**Step 6: Commit**

```bash
git add Listen2/Services/TTSService.swift
git commit -m "fix: prevent play button flickering during auto-advance

- Remove duplicate isPlaying = true in speakParagraph()
- Add delay before state update in handleParagraphComplete()
- Check if already playing before setting false
- Prevents flicker when auto-advancing between paragraphs"
```

---

## Verification Steps

After all tasks complete:

**1. Build for device:**

```bash
xcodebuild build -scheme Listen2 \
  -configuration Debug \
  -destination 'platform=iOS,id=00008130-001258510EA2001C' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

**2. Manual testing checklist:**

- [ ] App shows loading screen on startup (1-2 seconds)
- [ ] Voice picker shows only Piper voices by default
- [ ] Toggle "Use iOS Voice" shows iOS voice picker
- [ ] Selecting different Piper voice switches successfully
- [ ] Play button doesn't flicker during playback
- [ ] Auto-advance works smoothly between paragraphs
- [ ] Downloaded voices appear in voice picker

**3. Console log verification:**

Check for these success messages:
```
[TTSService] ✅ Piper TTS initialized with voice: en_US-lessac-medium
[TTSService] ✅ Switched to Piper voice: [voice-id]
[PiperTTS] Initialized with voice: [voice-id]
```

---

## Success Criteria

- ✅ Voice picker shows ONLY Piper voices by default
- ✅ iOS voices accessible via toggle (fallback option)
- ✅ Loading indicator appears during initialization
- ✅ Play button doesn't flicker during auto-advance
- ✅ Voice switching works for Piper voices
- ✅ No regressions in existing Piper TTS functionality
- ✅ All builds succeed
- ✅ Manual testing checklist passes

---

## Notes

- Piper TTS already working: playback, auto-advance, tar extraction
- espeak-ng-data properly bundled as folder reference
- AVVoice model already extended with isPiperVoice flag
- This plan completes the remaining UX polish
