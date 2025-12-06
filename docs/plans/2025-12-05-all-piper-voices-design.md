# All Piper Voices Integration Design

**Date:** 2025-12-05
**Status:** Approved

## Overview

Enable downloading any Piper voice (130+ voices across 35 languages) by fetching the voice catalog dynamically from Hugging Face instead of maintaining a static curated list.

## Goals

- Support all Piper voices, not just a curated subset
- Keep catalog always up-to-date without app updates
- Faster downloads by eliminating bzip2 extraction
- Simplify codebase by removing SWCompression dependency

## Architecture

### Catalog Source

**Current:** Static `voice-catalog.json` bundled in app (11 voices)

**New:** Fetch `voices.json` from Hugging Face at runtime

```
URL: https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json
```

**Caching Strategy:**
- Cache locally at `Documents/voice-catalog-cache.json`
- Refresh if cache is older than 24 hours
- Fall back to cached version when offline
- Keep minimal bundled fallback for first launch without network

### Voice Model Changes

**Current Voice struct:**
```swift
struct Voice {
    let id: String
    let name: String
    let language: String
    let gender: String
    let quality: String
    let sizeMB: Int
    let sampleURL: String?
    let downloadURL: String
    let checksum: String
    let isBundled: Bool
}
```

**New Voice struct:**
```swift
struct Voice: Identifiable, Codable, Equatable {
    let id: String                    // "en_US-amy-low"
    let name: String                  // "amy"
    let language: VoiceLanguage       // Nested struct
    let quality: String               // "low", "medium", "high"
    let numSpeakers: Int              // For multi-speaker voices
    let files: [String: VoiceFile]    // Path -> size/checksum

    // Computed properties
    var sampleURL: URL? { /* construct from piper-samples */ }
    var downloadURLs: [URL] { /* construct from HF */ }
    var sizeMB: Int { /* sum file sizes */ }
}

struct VoiceLanguage: Codable, Equatable, Hashable {
    let code: String          // "en_US"
    let family: String        // "en"
    let region: String        // "US"
    let nameNative: String    // "English"
    let nameEnglish: String   // "English"
    let countryEnglish: String // "United States"

    var displayName: String {
        if region.isEmpty {
            return nameEnglish
        } else {
            return "\(nameEnglish) (\(countryEnglish))"
        }
    }
}

struct VoiceFile: Codable, Equatable {
    let sizeBytes: Int
    let md5Digest: String
}
```

**Note:** Gender field dropped (not provided by Hugging Face)

### Download Logic Changes

**Current flow:**
```
Download tar.bz2 from sherpa-onnx → Decompress bzip2 → Extract tar → 2-3 min
```

**New flow:**
```
Download from Hugging Face in parallel:
    1. {voice}.onnx      (~60 MB)
    2. {voice}.onnx.json (~5 KB)

Generate tokens.txt from phoneme_id_map in JSON

Save to Documents/Voices/{voice_id}/
    → model.onnx
    → model.onnx.json
    → tokens.txt (generated)
```

**Download URL pattern:**
```
https://huggingface.co/rhasspy/piper-voices/resolve/main/{file_path}
```

**tokens.txt generation:**
```swift
func generateTokensFile(from json: VoiceConfig, to path: URL) throws {
    // json.phoneme_id_map = {"_": [0], "^": [1], "a": [14], ...}
    let lines = json.phonemeIdMap
        .sorted { $0.value[0] < $1.value[0] }
        .map { "\($0.key) \($0.value[0])" }
        .joined(separator: "\n")
    try lines.write(to: path, atomically: true, encoding: .utf8)
}
```

**espeak-ng-data:** Already bundled in app, supports all 35 languages. No per-voice download needed.

### Sample URL Construction

Samples hosted at `rhasspy/piper-samples` on GitHub.

**URL pattern:**
```
https://raw.githubusercontent.com/rhasspy/piper-samples/master/samples/{lang_family}/{locale}/{voice_name}/{quality}/speaker_0.mp3
```

**Example:**
```swift
extension Voice {
    var sampleURL: URL? {
        let base = "https://raw.githubusercontent.com/rhasspy/piper-samples/master/samples"
        return URL(string: "\(base)/\(language.family)/\(language.code)/\(name)/\(quality)/speaker_0.mp3")
    }
}
```

Some voices may not have samples - handle gracefully by hiding play button.

### UI Changes

**Filters:**
- Download Status: All / Downloaded / Available
- **Language:** Required filter, defaults to "en" (English)
- Quality: All / Low / Medium / High

**Language filter behavior:**
- Always active (no "All Languages" option)
- Defaults to English on first launch
- User must select a language to browse voices

**Downloaded section behavior:**
- Shows ALL downloaded voices regardless of selected language filter
- Provides quick access to voices user has already downloaded

**Available section:**
- Shows only voices matching the selected language

## Benefits

| Aspect | Before | After |
|--------|--------|-------|
| Voice count | 11 curated | 130+ all voices |
| Languages | 2 (en_US, en_GB) | 35 languages |
| Catalog freshness | Requires app update | Always up-to-date |
| Download time | 2-3 min (extraction) | ~30 sec (direct) |
| Dependencies | SWCompression | None (can remove) |

## Files to Modify

1. `Models/Voice.swift` - Update struct to match HF schema
2. `Services/Voice/VoiceManager.swift` - Remote catalog fetch, new download logic
3. `Views/VoiceLibraryView.swift` - Language filter, remove gender filter
4. `Resources/voice-catalog.json` - Keep minimal fallback only

## Testing Considerations

- Test offline behavior (cached catalog, no network)
- Test download progress UI with new flow
- Test sample playback for various languages
- Test tokens.txt generation correctness
- Verify sherpa-onnx initializes correctly with generated tokens
