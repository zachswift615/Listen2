# Voice Reader App - Design Document

**Date**: 2025-11-05
**Status**: Approved Design
**Platform**: iOS (iPhone/iPad)

## Overview

A voice reader app focused on quick access and quality reading experience. Built to solve specific pain points from existing apps: Voice Dream's poor PDF hyphenation handling and Speechify's excessive friction before use.

## Core Requirements

### Document Formats
- PDF with intelligent text extraction (primary focus)
- EPUB (e-books)
- Clipboard/plain text (quick reads)

### Key Features
- Native iOS text-to-speech (50+ high-quality voices)
- Visual word/sentence highlighting during playback
- Navigation controls (skip by paragraph, speed adjustment)
- Bookmark and auto-resume functionality
- Background audio playback
- Flat library (import-based, like Voice Dream)

### User Experience Priorities
1. **Quick access**: Open app → start reading immediately
2. **Smart defaults**: Minimal configuration required
3. **No friction**: No questions/prompts before use

## Architecture

### Tech Stack
- **UI Framework**: SwiftUI (iOS 17+)
- **Architecture**: MVVM pattern
- **TTS**: AVSpeechSynthesizer (native iOS voices)
- **PDF/EPUB**: PDFKit + custom EPUB parser
- **Persistence**: Swift Data
- **Reactive**: Combine for state management
- **Text Processing**: Foundation regex for hyphenation fixes

### Core Components

```
Views (SwiftUI)
├── LibraryView - Main screen, document list
├── ReaderView - Reading interface with controls
└── SettingsView - App configuration

ViewModels (ObservableObject)
├── LibraryViewModel - Document management
├── ReaderViewModel - Playback state & controls
└── SettingsViewModel - User preferences

Services
├── DocumentProcessor - Import & text extraction
├── TTSService - Playback management
└── LibraryManager - Storage & retrieval

Models
├── Document - Imported content
├── ReadingProgress - Current position
└── Voice - TTS voice configuration
```

### Design Principles
- **Protocol-oriented**: Extensible service interfaces
- **Separation of concerns**: Services isolated from UI
- **Reactive state**: Combine publishers for live updates
- **Testable**: Services can be tested independently

## Document Processing

### PDF Text Extraction

The critical feature solving Voice Dream's hyphenation problem:

**Processing Pipeline**:
1. Extract raw text from PDFDocument page by page
2. **Fix hyphenation**: Regex pattern `(\w+)-\s*\n\s*(\w+)` → join as single word
3. **Smart content filtering**:
   - Headers/footers: Detect repeating text in same position across pages
   - Page numbers: Regex for isolated numbers at page edges
   - Tables/code: Detect monospace fonts or grid-like spacing
   - Preserve only body text in natural reading flow
4. Output: Array of clean paragraphs ready for TTS

**Trade-offs**: Regex-based approach handles 90%+ of PDFs. Complex academic documents with equations may need iteration.

### EPUB Processing
- Parse EPUB as ZIP container
- Extract XHTML content files in reading order
- Strip HTML tags, preserve paragraph structure
- No hyphenation issues (already clean text)

### Clipboard/Plain Text
- Direct input, minimal processing
- Split by paragraph breaks
- Fastest import path

### Document Model

```swift
struct Document {
    let id: UUID
    let title: String // from filename or metadata
    let sourceType: SourceType // .pdf, .epub, .clipboard
    let extractedText: [String] // paragraphs
    let metadata: DocumentMetadata
    var currentPosition: Int // paragraph index
    var lastRead: Date
}
```

## Text-to-Speech System

### TTSProvider Protocol

Unified interface for future extensibility:

```swift
protocol TTSProvider {
    var availableVoices: [Voice] { get }
    func speak(text: String, voice: Voice, rate: Float)
    func pause()
    func resume()
    func stop()
    var currentWordRange: Range<String.Index>? { get } // for highlighting
}
```

### Native TTS Implementation

**MVP uses only native voices**:
- `AVSpeechSynthesizer` wrapper implementing TTSProvider
- iOS includes 50+ high-quality voices (including Siri voices)
- Fully offline, no API costs, no backend needed
- Word-boundary callbacks enable live highlighting
- Supports 0.5x to 2.5x playback speed

### TTSService

Orchestrates playback:
- Manages current TTSProvider instance
- Publishes `ReadingProgress` via Combine
- Handles paragraph navigation (skip forward/back)
- Persists voice/speed preferences per document
- Manages audio session for background playback

```swift
struct ReadingProgress {
    let paragraphIndex: Int
    let wordRange: Range<String.Index>?
    let isPlaying: Bool
}
```

## Reading Experience

### Reader View Layout

```
┌─────────────────────────────┐
│ Document Title         [X]  │ ← Top bar
├─────────────────────────────┤
│                             │
│  Main text view with        │
│  highlighted current word   │ ← Scrollable content
│  and dimmed sentence.       │   with auto-scroll
│                             │
│  Auto-scrolls to keep       │
│  current word visible.      │
│                             │
├─────────────────────────────┤
│ [◄◄] [▶️/⏸️] [►►]          │ ← Playback controls
│ Speed: 1.0x  Voice: Samantha│
└─────────────────────────────┘
```

### Visual Highlighting
- **Current word**: Bold highlight (uses AVSpeechSynthesizer word boundaries)
- **Current sentence**: Dimmed background for context
- **Auto-scroll**: View follows along to keep highlighted word centered
- SwiftUI AttributedString with dynamic styling

### Navigation Controls
- **Skip back**: 15 seconds (like podcast apps)
- **Skip forward**: Next paragraph
- **Tap paragraph**: Jump to location and start reading
- **Timeline scrubber**: Optional for long documents

### Playback Controls
- **Play/Pause**: Large center button
- **Speed adjustment**: 0.5x to 2.5x, shown as "1.0x"
- **Voice picker**: Dropdown without leaving reader
- **Settings persist**: Speed/voice saved per document

### Bookmarks & Resume
- **Auto-save**: Position saved every 5 seconds during playback
- **Resume indicator**: Library shows "Resume at 23%" on cards
- **Manual bookmarks**: Long-press paragraph to save
- **Bookmark storage**: Paragraph index + timestamp in Document model

### Background Audio
- Continues reading when app backgrounded
- Lock screen controls (play/pause/skip via MPNowPlayingInfoCenter)
- Interruption handling (calls pause, then resume)
- Proper audio session category (AVAudioSession.Category.playback)

## Library Management

### Library View

**Simple, flat structure** (like Voice Dream):
- Chronological list, most recent first
- Document cards show:
  - Title
  - Source type icon (PDF/EPUB/clipboard)
  - "Resume at X%" indicator
  - Last read date
- Pull-down search bar (filter by title)
- No folders, no collections, no organization complexity

### Import Flow

**Optimized for speed**:
1. Tap "+" button → System file picker
2. Select PDF/EPUB → Processing overlay (shows progress)
3. Title auto-extracted from filename or document metadata
4. Document appears at top of library, ready to read
5. **Total time**: 2-3 seconds for typical document

**Clipboard import**:
- Dedicated paste button always visible
- Creates "Clipboard [timestamp]" document
- Optional rename afterward
- Perfect for quick web article reading

### Document Actions

Swipe or long-press for:
- Resume reading (jump to saved position)
- Rename (edit title)
- Delete (remove from library)
- Share export (share original file)

### Storage

- Swift Data stores Document models
- Original files saved to app's Documents directory
- Extracted text cached in Document model (no re-processing)
- Total storage shown in Settings

## Settings

### Configuration Options

**Voice & Playback**:
- Default voice selection
- Default playback speed
- Auto-resume last document on launch (on/off)

**Reading Experience**:
- Highlighting style (word only vs. word + sentence)
- Auto-scroll behavior

**Storage**:
- View total space used
- Clear cache option

### Future Monetization (Not in MVP)

**Option 1 - Pro Features**:
- One-time IAP ($4.99) for:
  - Themes/appearance customization
  - Export annotated text
  - Advanced library features (collections, tags)

**Option 2 - Cloud Voices**:
- Subscription ($4.99/month) for cloud TTS
- Requires backend service (see Future Enhancements)

## Development Phases

### Phase 1 - MVP (First Build)

**Goal**: Validate core value proposition

Features:
- Library view with document list
- Import: PDF, EPUB, clipboard
- PDF text extraction with basic hyphenation fix (regex)
- Native iOS TTS with word highlighting
- Basic playback controls (play/pause, speed, skip paragraph)
- Auto-save reading position
- Simple settings screen

**Success Criteria**:
- PDFs read without hyphenation stuttering
- One-tap resume from library
- Zero friction from app open to listening
- Better PDF experience than Voice Dream

### Phase 2 - Polish

**Goal**: Production-quality experience

Enhancements:
- Enhanced PDF cleaning (headers/footers/page numbers detection)
- Improved highlighting and auto-scroll smoothness
- 15-second skip backward
- Manual bookmarks
- Background audio + lock screen controls
- Refined UI/animations

### Phase 3 - Future Enhancements

**Cloud Voices** (if user demand exists):
- Choose one provider (Google Cloud TTS recommended)
- Build simple backend proxy service
  - Node.js/Python serverless function (AWS Lambda)
  - App → Backend → Google TTS → Return audio
  - Backend validates subscription via StoreKit 2 server notifications
  - Backend manages API key (users never see it)
- Subscription model to cover API costs
- Usage tracking to prevent abuse
- Fallback to native voices if backend unavailable

**Other Ideas**:
- URL/web article import (Safari extension or built-in browser)
- Markdown file support
- Export highlights/bookmarks
- iCloud sync across devices

## Technical Considerations

### Platform Requirements
- iOS 17.0+ (for Swift Data and modern SwiftUI features)
- iPhone and iPad support (universal app)
- Landscape and portrait orientations

### Dependencies
- PDFKit (system framework)
- AVFoundation (system framework)
- SwiftData (system framework, iOS 17+)
- Custom EPUB parser (or lightweight third-party library)

### Testing Strategy
- Unit tests for DocumentProcessor (text extraction logic)
- Unit tests for hyphenation regex patterns
- Manual testing with problematic PDFs
- Background audio testing on device
- Accessibility testing (VoiceOver compatibility)

### Performance
- Lazy loading for large documents
- Background processing for document import
- Efficient highlighting updates (minimize redraws)

### Accessibility
- VoiceOver labels on all controls
- Dynamic Type support for text
- High contrast mode support
- Accessible playback controls

## Open Questions / Future Decisions

1. **EPUB library choice**: Build custom parser or use existing library?
2. **Swift Data vs. alternatives**: Stick with iOS 17+ or support older iOS versions?
3. **Monetization timing**: When to add IAP (if at all)?
4. **Advanced PDF cases**: How to handle complex academic PDFs with equations?

## Conclusion

This design prioritizes **speed to value**: users can be listening to clean PDF text within seconds of opening the app. By starting with native iOS voices only, we avoid backend complexity and can focus on perfecting the core reading experience. Future phases can add monetization and premium features once core value is validated.

The hyphenation fix and smart content filtering directly address the Voice Dream pain points, while the quick-access UX avoids Speechify's friction problems.
