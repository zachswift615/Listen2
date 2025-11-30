# Listen2

A native iOS app that transforms PDFs and ebooks into natural-sounding audiobooks using on-device neural text-to-speech.

## Why Listen2?

Listen2 was built to provide a simple, focused reading experience with high-quality voices that work entirely offline.

- **On-device neural TTS** - Natural-sounding voices powered by Piper, no internet required
- **Word-level highlighting** - Follow along with synchronized text highlighting
- **Multiple voice options** - Download additional voices from the Voice Library
- **Zero friction** - Import from Files, Google Drive, or clipboard and start listening

## Features

### Core Reading Experience
- **PDF & EPUB Support** - Import documents with smart text extraction
- **Google Drive Integration** - Browse and import documents directly from your Drive
- **Clipboard Import** - Paste text and start listening immediately
- **Neural TTS** - On-device Piper voices with natural prosody and intonation
- **Background Playback** - Continues reading when backgrounded or locked
- **Lock Screen Controls** - Play, pause, and skip from Now Playing

### Text Highlighting
- **Word-level highlighting** - Real-time highlighting synchronized via CTC forced alignment
- **Sentence-level highlighting** - Alternative mode for less visual distraction
- **Paragraph-level highlighting** - Minimal highlighting showing current position
- **Configurable** - Choose your preferred highlighting style in settings

### Voice Library
- **Multiple voices** - Download additional Piper voices (male, female, various accents)
- **Voice preview** - Sample voices before downloading
- **Easy switching** - Change voices mid-playback without losing position
- **Offline storage** - Downloaded voices work without internet

### Smart Text Processing
- **Hyphenation fix** - Intelligently joins words split across PDF lines
- **Paragraph detection** - Groups lines into semantic paragraphs for natural reading
- **TOC extraction** - Navigate via table of contents when available
- **Clutter filtering** - Skips page numbers, headers, and boilerplate

### User Experience
- **Reading position memory** - Automatically remembers where you left off
- **Playback speed control** - Adjust from 0.5x to 2.5x
- **Paragraph pause** - Configurable pause duration between paragraphs
- **Quick Settings** - Access speed, voice, and highlighting without leaving reader

## Architecture

Listen2 uses a streaming audio pipeline architecture for smooth, responsive playback:

```
┌─────────────────────────────────────────────────────────────────┐
│                        TTSService                                │
│  Orchestrates playback, manages state, handles voice switching  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ SynthesisQueue│  │  ReadyQueue   │  │ AudioPlayer   │
│ Generates     │  │ Buffers ready │  │ Streams via   │
│ audio chunks  │──▶│ sentences    │──▶│ AVAudioEngine │
└───────────────┘  └───────────────┘  └───────────────┘
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ PiperTTS      │  │ CTCAligner    │  │ WordScheduler │
│ Neural speech │  │ Forced align  │  │ Timed highlight│
│ synthesis     │  │ for timing    │  │ events        │
└───────────────┘  └───────────────┘  └───────────────┘
```

### Project Structure

```
Listen2/
├── Models/              # SwiftData models (Document, ReadingProgress)
├── ViewModels/          # Observable view models with Combine bindings
├── Views/               # SwiftUI views (Library, Reader, Settings, VoiceLibrary)
├── Coordinators/        # Navigation and complex view interactions
├── Services/
│   ├── TTSService       # Main playback orchestration
│   ├── TTS/             # Audio pipeline components
│   │   ├── SynthesisQueue      # Async audio generation
│   │   ├── ReadyQueue          # Sentence buffering & scheduling
│   │   ├── StreamingAudioPlayer# AVAudioEngine streaming
│   │   ├── PiperTTSProvider    # Neural TTS wrapper
│   │   └── CTCForcedAligner    # Word timing extraction
│   ├── Voice/           # Voice management & downloads
│   ├── DocumentProcessor# PDF/EPUB text extraction
│   └── GoogleDrive/     # Drive API integration
├── Design/              # Design system tokens
└── Frameworks/          # sherpa-onnx, ONNX Runtime
```

### Key Technologies
- **SwiftUI** - Declarative UI with iOS 17+ features
- **SwiftData** - Type-safe persistence for documents and settings
- **AVAudioEngine** - Low-latency streaming audio playback
- **Piper TTS** - On-device neural text-to-speech via sherpa-onnx
- **ONNX Runtime** - ML inference for TTS and alignment models
- **CTC Forced Alignment** - Word-level timing extraction for highlighting

## Requirements

- iOS 17.0+
- Xcode 15.0+
- iPhone or iPad

## Installation

### For Development

1. Clone the repository:
   ```bash
   git clone https://github.com/zachswift615/Listen2.git
   cd Listen2
   ```

2. Open the project in Xcode:
   ```bash
   open Listen2/Listen2/Listen2.xcodeproj
   ```

3. Build and run (⌘R) on your device or simulator

### For Users

TestFlight beta available - contact for access.

## Documentation

- **Framework Updates**: See `docs/FRAMEWORK_UPDATE_GUIDE.md` for updating sherpa-onnx
- **EPUB Setup**: See `EPUB_SETUP.md` for ZIPFoundation dependency
- **Scripts**: Xcode project configuration scripts in `scripts/xcode/`

## How It Works

### Streaming Audio Pipeline

Listen2 uses a multi-stage pipeline for responsive playback:

1. **SynthesisQueue** - Generates audio chunks asynchronously using Piper TTS
2. **ReadyQueue** - Buffers synthesized sentences with alignment data
3. **StreamingAudioPlayer** - Streams chunks via AVAudioEngine for gapless playback
4. **WordScheduler** - Fires timed events to update word highlighting

This architecture enables:
- Starting playback before entire document is synthesized
- Smooth voice switching without losing position
- Responsive pause/resume and navigation
- Memory-efficient handling of large documents

### Word-Level Highlighting

CTC forced alignment extracts precise word timings:

1. Audio is synthesized by Piper TTS
2. CTC aligner processes the audio waveform and text together
3. The model outputs character-level timestamps aligned to audio frames
4. Word boundaries are calculated by grouping character timestamps
5. WordScheduler fires highlight events synced to playback

### The Hyphenation Fix

PDFs often break words across lines:
```
This is an ex-
ample of hyphenation.
```

Listen2 detects and joins these seamlessly during text extraction.

## Credits

**Built with:**
- SwiftUI, SwiftData, AVFoundation
- [Piper TTS](https://github.com/rhasspy/piper) - Neural text-to-speech
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - On-device inference
- [ONNX Runtime](https://onnxruntime.ai/) - ML model execution

**Developed by:** Zach Swift
**Development Partner:** Claude (Anthropic)

## License

[License TBD]

---

**Built with care to make reading accessible and enjoyable.**
