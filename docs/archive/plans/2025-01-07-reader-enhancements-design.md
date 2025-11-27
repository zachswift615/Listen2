# Reader Enhancements Design
**Date:** 2025-01-07
**Status:** Approved
**Author:** Claude + User

## Overview

This design enhances the Listen2 reader experience with four key improvements:
1. Table of Contents navigation
2. In-reader settings access via overlay
3. Voice filtering by language and gender
4. Voice change bug fixes

## Goals

- **Quick Navigation:** Users can jump to chapters via TOC without leaving the reader
- **Convenient Controls:** Speed, voice, and pause settings accessible in-context
- **Better Voice Discovery:** Filter 50+ voices by language and gender
- **Reliable Voice Changes:** Voice selection works consistently every time

## Architecture

### Component Overview

```
ReaderCoordinator
├── ReaderView (simplified, delegates to coordinator)
├── ReaderViewModel (current reading state + TTS binding)
├── TOCService (extracts and generates table of contents)
├── VoiceFilterManager (handles voice filtering)
└── ReaderOverlay (tap-to-show controls)
```

### Responsibilities

**ReaderCoordinator:**
- Manages overlay visibility state
- Coordinates TOC presentation
- Handles settings sheet display
- Orchestrates voice changes with proper TTS restart

**ReaderView:**
- Displays text with highlighting
- Detects tap gestures for overlay toggle
- Shows/hides overlay based on coordinator state

**ReaderViewModel:**
- Current paragraph tracking
- TTS service binding
- Playback state management
- No UI concerns (stays focused on state)

**TOCService:**
- PDF metadata extraction
- Heading detection fallback
- TOCEntry model generation

**VoiceFilterManager:**
- Language filtering logic
- Gender filtering logic
- Filter persistence

## Table of Contents

### Extraction Strategy

**Two-Phase Approach:**

1. **Phase 1: PDF Metadata Extraction**
   - Use `PDFDocument.outlineRoot` to get built-in TOC
   - Parse outline hierarchy into `TOCEntry` models
   - Fastest, cleanest when available

2. **Phase 2: Heading Detection (Fallback)**
   - Analyze font sizes (detect text larger than body)
   - Check font weights (bold, semibold)
   - Pattern matching for numbering ("Chapter 1", "1.", "1.1")
   - Detect short lines followed by content (likely headings)

### TOCEntry Model

```swift
struct TOCEntry: Identifiable {
    let id: UUID
    let title: String           // "Chapter 1: Introduction"
    let paragraphIndex: Int     // Index in document.extractedText
    let level: Int             // 0 = chapter, 1 = section, 2 = subsection
}
```

### UI Presentation

**Bottom Sheet:**
- Slides up from bottom (iOS standard pattern)
- Partial height initially (~60% screen)
- Hierarchical list with indentation for levels
- Search bar at top for long TOCs
- Current chapter highlighted
- Tap entry → jumps to paragraph and dismisses

## In-Reader Controls Overlay

### Behavior (Apple Books Style)

**Initial State:**
- Text area shows only content
- Bottom playback controls always visible
- Top navigation hidden

**Tap Interaction:**
- Tap anywhere on text → Shows overlay
- Overlay components:
  - **Top bar:** Back | Document Title | TOC + Settings buttons
  - **Bottom bar:** Existing playback controls (unchanged)

**Auto-Hide Behavior:**
- Hides after 3 seconds of inactivity
- Stays visible during interaction
- Faster hide during playback (2 seconds)
- Tap outside controls → dismisses immediately

### Quick Settings Sheet

**Triggered by:** Settings button in overlay

**Content:**
- Speed slider (0.5x - 2.5x)
- Voice picker button
- Pause duration slider (0.0s - 1.0s)
- Changes apply immediately to current playback

**Presentation:**
- Bottom sheet (partial height, ~40% screen)
- Dismissible with swipe or tap outside
- Separate from full Settings in Library

**Difference from Library Settings:**
- Quick settings: Current playback adjustments
- Library settings: Defaults + app info + about

## Voice Filtering

### VoiceFilterManager

```swift
class VoiceFilterManager: ObservableObject {
    @Published var selectedLanguages: Set<String> = []
    @Published var selectedGender: VoiceGender? = nil
    @AppStorage("lastUsedLanguageFilter") var lastUsedLanguages: [String] = []

    enum VoiceGender {
        case male, female, neutral
    }

    func filteredVoices(_ allVoices: [Voice]) -> [Voice] {
        var filtered = allVoices

        // Filter by language
        if !selectedLanguages.isEmpty {
            filtered = filtered.filter { voice in
                selectedLanguages.contains(voice.languageCode)
            }
        }

        // Filter by gender
        if let gender = selectedGender {
            filtered = filtered.filter { $0.gender == gender }
        }

        return filtered.sorted { $0.name < $1.name }
    }
}
```

### Voice Picker UI

**Filter Bar (Top):**
- **Language chips:** English, Spanish, French, etc.
- **Gender toggle:** All | Male | Female | Neutral
- Default to system language on first use
- Persists last-used filters

**Voice List:**
- Filtered, sorted alphabetically
- Shows: Voice name, language, gender (if available)
- Checkmark for currently selected voice
- Tap voice → applies immediately

### Gender Detection

AVFoundation doesn't provide explicit gender metadata, but we can:
- Detect from voice identifier patterns (e.g., "com.apple.voice.compact.en-US.Samantha")
- Use voice name heuristics (common names)
- Fall back to "Neutral" when uncertain
- Allow manual correction via metadata file if needed

## Voice Change Bug Fixes

### Root Cause

Voice changes fail because:
1. TTS service continues with old voice's utterance
2. State not properly synchronized between UI and service
3. No restart of playback with new voice

### Solution

**Immediate Stop & Restart:**

```swift
func changeVoice(_ newVoice: Voice) {
    // 1. Capture current state
    let wasPlaying = ttsService.isPlaying
    let currentParagraph = viewModel.currentParagraphIndex

    // 2. Stop immediately
    ttsService.stop()

    // 3. Update voice
    ttsService.setVoice(newVoice)

    // 4. Restart if was playing
    if wasPlaying {
        ttsService.startReading(
            paragraphs: document.extractedText,
            from: currentParagraph,
            title: document.title
        )
    }

    // 5. Update UI
    viewModel.selectedVoice = newVoice
}
```

**State Synchronization:**
- Coordinator owns voice change logic
- ViewModel reflects TTS service state via Combine bindings
- UI updates immediately on selection
- No async gaps where old voice could continue

**Persistence:**
- Save selected voice to @AppStorage on change
- Apply saved voice on document open
- Per-document voice memory (future enhancement)

## Implementation Notes

### File Structure

**New Files:**
- `Listen2/Coordinators/ReaderCoordinator.swift`
- `Listen2/Services/TOCService.swift`
- `Listen2/Services/VoiceFilterManager.swift`
- `Listen2/Views/ReaderOverlay.swift`
- `Listen2/Views/TOCBottomSheet.swift`
- `Listen2/Views/QuickSettingsSheet.swift`

**Modified Files:**
- `Listen2/Views/ReaderView.swift` (simplify, delegate to coordinator)
- `Listen2/ViewModels/ReaderViewModel.swift` (add TOC state, voice change)
- `Listen2/Models/Voice.swift` (add gender property)

### Testing Strategy

**Unit Tests:**
- TOCService: PDF metadata extraction
- TOCService: Heading detection heuristics
- VoiceFilterManager: Language filtering
- VoiceFilterManager: Gender filtering

**Integration Tests:**
- Voice change during playback
- TOC navigation while playing
- Overlay state management

**Manual Testing:**
- Test with PDFs that have TOC metadata
- Test with PDFs without TOC (heading detection)
- Verify voice changes work 100% of the time
- Check overlay behavior matches Apple Books

## Success Criteria

- ✅ TOC extracts from PDF metadata or detects headings
- ✅ Bottom sheet TOC navigates to correct paragraphs
- ✅ Tap text shows overlay with TOC and Settings buttons
- ✅ Overlay auto-hides after inactivity
- ✅ Quick settings sheet adjusts playback in real-time
- ✅ Voice filtering by language works
- ✅ Voice filtering by gender works (when detectable)
- ✅ Voice changes apply immediately and consistently
- ✅ Selected voice persists across app launches

## Future Enhancements

These are explicitly out of scope for this design but noted for future consideration:

- Manual bookmark creation (user-defined TOC entries)
- Per-document voice memory
- Export TOC as text
- Jump to page number (for PDFs with page metadata)
- TOC search highlights
- Voice preview (play sample before selecting)
