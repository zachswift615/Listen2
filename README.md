# Listen2 🎧

A modern, elegant voice reader app for iOS. Using Piper voices, VoxPDF technology, having PDF, clipboard and EPUB support, as well as word level highlighting. 

## Why Listen2?

Listen2 was born from frustration with existing voice reader apps. They are either too celebrity voice focused and expensive, or filled with bugs that drive me nuts that I can't fix. 

Listen2 solves these problems with:
- ✅ **Intelligent hyphenation handling** - Seamlessly joins hyphenated words across PDF line breaks
- ✅ **Zero friction** - Import and start listening in seconds
- ✅ **Completely free** - No subscriptions, no ads, no paywalls
- ✅ **Native performance** - Built with SwiftUI and native iOS voices

## Features

### Core Reading Experience
- 📄 **PDF Support** - Import and read PDF documents with smart text extraction
- 📋 **Clipboard Import** - Paste text and start listening immediately
- 🎙️ **Piper** - A fast and local neural text-to-speech engine that embeds espeak-ng for phonemization
- ⚡ **Background Playback** - Continues reading when app is backgrounded or device is locked
- 🎚️ **Playback Controls** - Adjust speed (0.5x-2.5x), pause duration, and voice selection
- 🔖 **Position Saving** - Automatically remembers where you left off

### Smart Text Processing
- 🔧 **Hyphenation Fix** - Intelligently joins words split across PDF lines
- 📖 **Paragraph Detection** - Groups lines into semantic paragraphs for natural reading
- 🗑️ **Clutter Filtering** - Skips page numbers, headers, and TOC entries
- 📍 **Paragraph Highlighting** - Visual feedback shows current reading position

### User Experience
- 🎨 **Thoughtful Design** - Comprehensive design system with calm blue palette
- ⚙️ **Configurable Settings** - Customize speed, voice, and pause preferences
- 🔒 **Lock Screen Controls** - Play, pause, and skip from lock screen
- 📱 **Universal App** - Optimized for both iPhone and iPad

## Screenshots

[Coming Soon]

## Requirements

- iOS 17.0+
- Xcode 15.0+
- iPhone or iPad

## Installation

### For Development

1. Clone the repository:
   ```bash
   git clone https://github.com/zachswift/Listen2.git
   cd Listen2
   ```

2. Open the project in Xcode:
   ```bash
   cd Listen2/Listen2
   open Listen2.xcodeproj
   ```

3. Build and run (⌘R) on your device or simulator

### For Users

[App Store link coming soon]

## Architecture

Listen2 follows a clean **MVVM architecture** with modern iOS patterns:

```
Listen2/
├── Models/          # SwiftData models (Document, Voice, ReadingProgress)
├── ViewModels/      # Observable view models with Combine bindings
├── Views/           # SwiftUI views (Library, Reader, Settings)
├── Services/        # Business logic (DocumentProcessor, TTSService)
└── Design/          # Design system with comprehensive tokens
```

### Key Technologies
- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Type-safe persistence layer
- **AVFoundation** - Native text-to-speech with AVSpeechSynthesizer
- **PDFKit** - PDF text extraction and processing
- **Combine** - Reactive state management

### Design Patterns
- MVVM with protocol-oriented design
- Service layer for business logic
- Design tokens for consistent styling
- Dependency injection via initializers

## Development

### Running Tests

```bash
cd Listen2/Listen2
xcodebuild test -project Listen2.xcodeproj -scheme Listen2 \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Project Structure

- **Design System** - `Listen2/Design/DesignSystem.swift` contains all color, typography, spacing, and animation tokens
- **Document Processing** - `Listen2/Services/DocumentProcessor.swift` handles PDF text extraction and hyphenation fixing
- **TTS Engine** - `Listen2/Services/TTSService.swift` manages text-to-speech playback with word-level tracking
- **Persistence** - SwiftData models in `Listen2/Models/` with automatic change tracking

### Documentation

- **Framework Updates**: See `docs/FRAMEWORK_UPDATE_GUIDE.md` for updating sherpa-onnx.xcframework
- **EPUB Setup**: See `EPUB_SETUP.md` for ZIPFoundation dependency setup
- **Implementation Plans**: Current plans in `docs/plans/`
- **Testing**: Test documentation in `docs/testing/`
- **Archived Docs**: Historical design docs and session handoffs in `docs/archive/`

## How It Works

### The Hyphenation Fix

PDFs often break words across line boundaries with hyphens:
```
This is an ex-
ample of hyphenation.
```

Other readers process this as: "This is an ex [pause] ample of hyphenation."

**Listen2's solution:**
1. During paragraph joining, detect lines ending with hyphens (including trailing whitespace)
2. Remove the hyphen and join directly without space
3. Result: "This is an example of hyphenation." ✨

See `DocumentProcessor.swift:joinLinesIntoParagraphs()` for implementation.

### Performance Optimizations

Listen2 is optimized for real-device performance:
- **Word highlighting disabled** - Prevented 0.6s UI hangs on iPhone 15 Pro Max
- **Lazy audio session** - Configured only on first playback
- **Paragraph-only highlighting** - Smooth 60fps scrolling during TTS
- **Efficient text processing** - Minimal memory allocations during paragraph joining

## Roadmap

### v1.1 - Reader Enhancements (In Design)
- 📑 Table of Contents navigation
- 🎛️ In-reader settings overlay
- 🌍 Voice filtering by language and gender
- 🔧 Voice change reliability improvements

### Future Considerations
- 📚 EPUB support
- 🌐 Web article import via URL
- 📊 Reading statistics
- ☁️ iCloud sync
- 📱 Widgets and Siri shortcuts

## Contributing

This is a personal project, but feedback and suggestions are welcome! Feel free to:
- Open issues for bugs or feature requests
- Share your experience using Listen2
- Suggest improvements to the text processing algorithms

## Credits

**Built with:**
- SwiftUI and SwiftData
- AVFoundation for native iOS voices
- PDFKit for PDF text extraction

**Inspired by:**
- Voice Dream Reader (but with better hyphenation!)
- Apple Books (for UX patterns)
- Speechify (validated the need for a simpler alternative)

**Developed by:** Zach Swift
**Development Partner:** Claude (Anthropic)
**Project Repository:** [GitHub](https://github.com/zachswift/Listen2)

## License

[License TBD]

---

**Built with ❤️ and 🤖 to make reading accessible and enjoyable.**
