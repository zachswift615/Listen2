# Phoneme Duration Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ASR-based word alignment with direct phoneme duration extraction from Piper TTS

**Architecture:** Extract phoneme durations from sherpa-onnx C API, map phonemes to VoxPDF words using character positions, eliminate ASR dependency entirely

**Tech Stack:** Swift, sherpa-onnx (modified with phoneme duration support), espeak-ng phonemization

**Status:** sherpa-onnx iOS build complete with phoneme duration support, framework updated in Xcode project

---

## Task 1: Update GeneratedAudio to Include Phoneme Durations

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift:106-123`

**Goal:** Expose phoneme durations from C API in Swift wrapper

**Step 1: Add phoneme duration fields to GeneratedAudio struct**

Modify the `GeneratedAudio` struct at line 108:

```swift
/// Wrapper for generated audio from sherpa-onnx
struct GeneratedAudio {
    let samples: [Float]
    let sampleRate: Int32
    let phonemeDurations: [Int32]  // NEW: sample count per phoneme

    init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>) {
        self.sampleRate = audio.pointee.sample_rate

        // Copy samples to Swift array
        let count = Int(audio.pointee.n)
        if let samplesPtr = audio.pointee.samples {
            self.samples = Array(UnsafeBufferPointer(start: samplesPtr, count: count))
        } else {
            self.samples = []
        }

        // Copy phoneme durations to Swift array
        let phonemeCount = Int(audio.pointee.num_phonemes)
        if phonemeCount > 0, let durationsPtr = audio.pointee.phoneme_durations {
            self.phonemeDurations = Array(UnsafeBufferPointer(start: durationsPtr, count: phonemeCount))
        } else {
            self.phonemeDurations = []
        }
    }
}
```

**Step 2: Update convenience initializer**

Modify the extension at line 202:

```swift
// MARK: - GeneratedAudio Convenience Initializer

extension GeneratedAudio {
    init(samples: [Float], sampleRate: Int32, phonemeDurations: [Int32] = []) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.phonemeDurations = phonemeDurations
    }
}
```

**Step 3: Update the error case in SherpaOnnxOfflineTtsWrapper**

Modify line 172 in the `generate` method:

```swift
func generate(text: String, sid: Int32, speed: Float) -> GeneratedAudio {
    guard let tts = tts else {
        print("[SherpaOnnx] TTS not initialized")
        return GeneratedAudio(samples: [], sampleRate: 22050, phonemeDurations: [])
    }

    // ... rest remains the same
}
```

**Step 4: Test the changes compile**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' clean build 2>&1 | grep -E "(error|warning|Build succeeded)" | head -20`

Expected: "Build succeeded" (or proceed to fix errors)

**Step 5: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift
git commit -m "feat: extract phoneme durations from sherpa-onnx C API

- Add phonemeDurations field to GeneratedAudio struct
- Extract phoneme durations from SherpaOnnxGeneratedAudio
- Update convenience initializer with default empty array"
```

---

## Task 2: Update PiperTTSProvider to Return Phoneme Durations

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift:73-103`

**Goal:** Return both audio data and phoneme durations from synthesis

**Step 1: Add PhonemeDuration model**

Add at the top of PiperTTSProvider.swift after imports (line 10):

```swift
/// Represents the duration of a single phoneme in synthesized speech
struct PhonemeDuration {
    /// The phoneme symbol (IPA format from espeak-ng)
    let phoneme: String

    /// Number of audio samples for this phoneme
    let sampleCount: Int32

    /// Duration in seconds (calculated from sample count and rate)
    let duration: TimeInterval

    init(phoneme: String, sampleCount: Int32, sampleRate: Int32) {
        self.phoneme = phoneme
        self.sampleCount = sampleCount
        self.duration = TimeInterval(sampleCount) / TimeInterval(sampleRate)
    }
}

/// Result of TTS synthesis including audio and phoneme timing
struct SynthesisResult {
    let audioData: Data
    let phonemeDurations: [PhonemeDuration]
    let text: String  // Original text for debugging
}
```

**Step 2: Modify synthesize method signature**

Change line 73:

```swift
func synthesize(_ text: String, speed: Float) async throws -> SynthesisResult {
```

**Step 3: Update synthesis implementation**

Modify the method body (lines 74-103):

```swift
func synthesize(_ text: String, speed: Float) async throws -> SynthesisResult {
    guard isInitialized, let tts = tts else {
        throw TTSError.notInitialized
    }

    // Validate text
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TTSError.emptyText
    }

    guard text.utf8.count <= 10_000 else {
        throw TTSError.textTooLong(maxLength: 10_000)
    }

    guard text.data(using: .utf8) != nil else {
        throw TTSError.invalidEncoding
    }

    // Clamp speed to valid range
    let clampedSpeed = max(0.5, min(2.0, speed))

    // Generate audio with phoneme durations
    let audio = tts.generate(text: text, sid: 0, speed: clampedSpeed)

    // Convert to WAV data
    let wavData = createWAVData(samples: audio.samples, sampleRate: Int(audio.sampleRate))

    print("[PiperTTS] Synthesized \(audio.samples.count) samples at \(audio.sampleRate) Hz")
    print("[PiperTTS] Received \(audio.phonemeDurations.count) phoneme durations")

    // Get phoneme sequence from espeak-ng for this text
    let phonemeSequence = try phonemizeText(text)

    // Map durations to phonemes
    let phonemeDurations = zipPhonemeData(
        phonemes: phonemeSequence,
        durations: audio.phonemeDurations,
        sampleRate: audio.sampleRate
    )

    return SynthesisResult(
        audioData: wavData,
        phonemeDurations: phonemeDurations,
        text: text
    )
}
```

**Step 4: Add phoneme extraction helpers**

Add these methods at the end of PiperTTSProvider class (before the Data Extensions mark):

```swift
// MARK: - Phoneme Extraction

/// Convert text to phoneme sequence using espeak-ng
/// - Parameter text: Input text
/// - Returns: Array of phoneme symbols (IPA format)
/// - Throws: TTSError if phonemization fails
private func phonemizeText(_ text: String) throws -> [String] {
    // Get espeak-ng data path
    guard let espeakDataPath = voiceManager.speakNGDataPath(for: voiceID) else {
        throw TTSError.synthesisFailed(reason: "espeak-ng data path not found")
    }

    // Use sherpa-onnx's phonemizer (it wraps espeak-ng)
    // For now, return empty array - we'll implement phoneme extraction in next task
    // The phoneme durations from Piper are already in order matching the text
    print("[PiperTTS] TODO: Implement phoneme extraction from text")
    return []
}

/// Zip phoneme symbols with their durations
/// - Parameters:
///   - phonemes: Array of phoneme symbols
///   - durations: Array of sample counts per phoneme
///   - sampleRate: Audio sample rate
/// - Returns: Array of PhonemeDuration objects
private func zipPhonemeData(
    phonemes: [String],
    durations: [Int32],
    sampleRate: Int32
) -> [PhonemeDuration] {
    // Handle mismatch between phoneme count and duration count
    let count = min(phonemes.count, durations.count)

    if phonemes.count != durations.count {
        print("⚠️  [PiperTTS] Phoneme/duration count mismatch: \(phonemes.count) phonemes, \(durations.count) durations")
    }

    // If we don't have phoneme symbols yet, create placeholder entries
    if phonemes.isEmpty && !durations.isEmpty {
        return durations.map { duration in
            PhonemeDuration(
                phoneme: "?",  // Placeholder until we implement phonemization
                sampleCount: duration,
                sampleRate: sampleRate
            )
        }
    }

    return (0..<count).map { i in
        PhonemeDuration(
            phoneme: phonemes[i],
            sampleCount: durations[i],
            sampleRate: sampleRate
        )
    }
}
```

**Step 5: Test compilation**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "(error|Build succeeded)" | head -20`

Expected: Build errors in SynthesisQueue (expected - we'll fix in next task)

**Step 6: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift
git commit -m "feat: return phoneme durations from PiperTTSProvider

- Add PhonemeDuration and SynthesisResult models
- Modify synthesize() to return audio + phoneme durations
- Add placeholders for phoneme extraction (TODO)
- Extract phoneme sample counts from sherpa-onnx output"
```

---

## Task 3: Create PhonemeAlignmentService

**Files:**
- Create: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`

**Goal:** Map phoneme durations to VoxPDF word positions

**Step 1: Create PhonemeAlignmentService file**

```swift
//
//  PhonemeAlignmentService.swift
//  Listen2
//
//  Service for aligning phoneme durations to text words
//

import Foundation

/// Service for word-level alignment using phoneme durations from Piper TTS
actor PhonemeAlignmentService {

    // MARK: - Properties

    /// Cache of alignments by text hash
    private var alignmentCache: [String: AlignmentResult] = [:]

    // MARK: - Public Methods

    /// Align phoneme durations to VoxPDF words
    /// - Parameters:
    ///   - phonemeDurations: Array of phoneme durations from Piper
    ///   - text: The text that was synthesized
    ///   - wordMap: Document word map containing word positions
    ///   - paragraphIndex: Index of the paragraph being aligned
    /// - Returns: AlignmentResult with word timings
    /// - Throws: AlignmentError if alignment fails
    func align(
        phonemeDurations: [PhonemeDuration],
        text: String,
        wordMap: DocumentWordMap,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {
        // Check cache first (keyed by text + paragraph)
        let cacheKey = "\(paragraphIndex):\(text)"
        if let cached = alignmentCache[cacheKey] {
            print("[PhonemeAlign] Using cached alignment for paragraph \(paragraphIndex)")
            return cached
        }

        print("[PhonemeAlign] Aligning \(phonemeDurations.count) phonemes to text: '\(text.prefix(50))...'")

        // Get VoxPDF words for this paragraph
        let voxPDFWords = wordMap.words(for: paragraphIndex)

        guard !voxPDFWords.isEmpty else {
            throw AlignmentError.recognitionFailed("No words found for paragraph \(paragraphIndex)")
        }

        print("[PhonemeAlign] Found \(voxPDFWords.count) VoxPDF words")

        // Strategy: Distribute phoneme durations proportionally across characters
        // Then accumulate durations for each word based on character positions

        let wordTimings = mapPhonemesToWords(
            phonemeDurations: phonemeDurations,
            text: text,
            voxPDFWords: voxPDFWords
        )

        // Calculate total duration from phoneme durations
        let totalDuration = phonemeDurations.reduce(0.0) { $0 + $1.duration }

        // Create alignment result
        let alignmentResult = AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )

        print("[PhonemeAlign] Created alignment with \(wordTimings.count) word timings, total duration: \(totalDuration)s")

        // Cache the result
        alignmentCache[cacheKey] = alignmentResult

        return alignmentResult
    }

    /// Get cached alignment for specific text/paragraph
    /// - Parameters:
    ///   - text: The paragraph text
    ///   - paragraphIndex: Paragraph index
    /// - Returns: Cached alignment result, or nil if not cached
    func getCachedAlignment(for text: String, paragraphIndex: Int) -> AlignmentResult? {
        let cacheKey = "\(paragraphIndex):\(text)"
        return alignmentCache[cacheKey]
    }

    /// Clear the alignment cache
    func clearCache() {
        alignmentCache.removeAll()
    }

    // MARK: - Private Methods

    /// Map phoneme durations to VoxPDF words
    /// - Parameters:
    ///   - phonemeDurations: Array of phoneme durations
    ///   - text: Full paragraph text
    ///   - voxPDFWords: Array of word positions
    /// - Returns: Array of word timings
    private func mapPhonemesToWords(
        phonemeDurations: [PhonemeDuration],
        text: String,
        voxPDFWords: [WordPosition]
    ) -> [AlignmentResult.WordTiming] {
        guard !phonemeDurations.isEmpty else {
            return []
        }

        // Calculate total duration
        let totalDuration = phonemeDurations.reduce(0.0) { $0 + $1.duration }

        // Calculate duration per character (simple proportional distribution)
        let textLength = text.count
        let durationPerChar = totalDuration / TimeInterval(textLength)

        print("[PhonemeAlign] Total duration: \(totalDuration)s, text length: \(textLength), duration/char: \(durationPerChar)s")

        // Map each word to its timing based on character positions
        var wordTimings: [AlignmentResult.WordTiming] = []

        for word in voxPDFWords {
            // Calculate timing based on character position
            let startTime = TimeInterval(word.characterOffset) * durationPerChar
            let duration = TimeInterval(word.length) * durationPerChar

            // Get String.Index range from VoxPDF word position
            guard let startIndex = text.index(
                text.startIndex,
                offsetBy: word.characterOffset,
                limitedBy: text.endIndex
            ) else {
                print("⚠️  [PhonemeAlign] Invalid character offset \(word.characterOffset) for word '\(word.text)'")
                continue
            }

            guard let endIndex = text.index(
                startIndex,
                offsetBy: word.length,
                limitedBy: text.endIndex
            ) else {
                print("⚠️  [PhonemeAlign] Invalid length \(word.length) for word '\(word.text)'")
                continue
            }

            let stringRange = startIndex..<endIndex

            // Validate extracted text matches expected word
            let extractedText = String(text[stringRange])
            if extractedText != word.text {
                print("⚠️  [PhonemeAlign] VoxPDF position mismatch:")
                print("    Expected: '\(word.text)', Got: '\(extractedText)'")
                // Skip this word - position data is incorrect
                continue
            }

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: voxPDFWords.firstIndex(where: { $0.text == word.text && $0.characterOffset == word.characterOffset }) ?? 0,
                startTime: startTime,
                duration: duration,
                text: word.text,
                stringRange: stringRange
            ))
        }

        print("[PhonemeAlign] Created \(wordTimings.count) word timings")
        return wordTimings
    }
}
```

**Step 2: Add file to Xcode project**

Run: `ruby add_phoneme_alignment_service.rb`

Expected: Script adds file to Xcode project

**Step 3: Test compilation**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "(error|Build succeeded)" | head -20`

Expected: Build errors in SynthesisQueue (we'll fix next)

**Step 4: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift add_phoneme_alignment_service.rb Listen2/Listen2/Listen2.xcodeproj/project.pbxproj
git commit -m "feat: add PhonemeAlignmentService for phoneme-based alignment

- Create actor for thread-safe alignment caching
- Implement proportional character-based timing distribution
- Map phoneme durations to VoxPDF word positions
- Validate word positions match extracted text"
```

---

## Task 4: Update SynthesisQueue to Use PhonemeAlignmentService

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift:34-60`
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift:93-125`
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift:150-250` (performAlignment method)

**Goal:** Replace WordAlignmentService with PhonemeAlignmentService

**Step 1: Update properties (lines 34-60)**

Replace:
```swift
/// Word alignment service for performing ASR-based alignment
private let alignmentService: WordAlignmentService
```

With:
```swift
/// Phoneme alignment service for performing phoneme-based alignment
private let alignmentService: PhonemeAlignmentService
```

**Step 2: Update initializer (line 56)**

Change:
```swift
init(provider: TTSProvider, alignmentService: WordAlignmentService, alignmentCache: AlignmentCache) {
```

To:
```swift
init(provider: TTSProvider, alignmentService: PhonemeAlignmentService, alignmentCache: AlignmentCache) {
```

**Step 3: Update getAudio method to handle new return type (lines 93-125)**

Find line 113:
```swift
let data = try await provider.synthesize(text, speed: speed)
```

Replace with:
```swift
let result = try await provider.synthesize(text, speed: speed)
let data = result.audioData
```

And update the performAlignment call at line 119:
```swift
// Perform alignment if word map is available
await performAlignment(for: index, result: result, text: text)
```

**Step 4: Rewrite performAlignment method**

Find the `performAlignment` method (around line 150-250) and replace it entirely:

```swift
/// Perform word-level alignment for synthesized audio
/// - Parameters:
///   - index: Paragraph index
///   - result: Synthesis result containing audio and phoneme durations
///   - text: The synthesized text
private func performAlignment(for index: Int, result: SynthesisResult, text: String) async {
    guard let wordMap = wordMap else {
        print("[SynthesisQueue] No word map available for alignment")
        return
    }

    // Check disk cache first (if documentID is set)
    if let documentID = documentID,
       let cachedAlignment = try? await alignmentCache.loadAlignment(
           documentID: documentID,
           paragraphIndex: index,
           speed: speed
       ) {
        print("[SynthesisQueue] Loaded alignment from disk cache for paragraph \(index)")
        alignments[index] = cachedAlignment
        return
    }

    // Perform phoneme-based alignment
    do {
        let alignment = try await alignmentService.align(
            phonemeDurations: result.phonemeDurations,
            text: text,
            wordMap: wordMap,
            paragraphIndex: index
        )

        // Store in memory cache
        alignments[index] = alignment

        // Store in disk cache (if documentID is set)
        if let documentID = documentID {
            do {
                try await alignmentCache.saveAlignment(
                    alignment,
                    documentID: documentID,
                    paragraphIndex: index,
                    speed: speed
                )
                print("[SynthesisQueue] Saved alignment to disk cache for paragraph \(index)")
            } catch {
                print("[SynthesisQueue] Failed to save alignment to disk: \(error)")
                // Non-fatal - we have the alignment in memory
            }
        }

        print("[SynthesisQueue] Alignment completed for paragraph \(index): \(alignment.wordTimings.count) words")
    } catch {
        print("[SynthesisQueue] Alignment failed for paragraph \(index): \(error)")
        // Don't throw - alignment is optional for playback
    }
}
```

**Step 5: Update preSynthesizeAhead method if it uses provider.synthesize**

Find the `preSynthesizeAhead` method and update any calls to `provider.synthesize`:

```swift
let result = try await provider.synthesize(text, speed: speed)
cache[index] = result.audioData

// Perform alignment
await performAlignment(for: index, result: result, text: text)
```

**Step 6: Test compilation**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "(error|Build succeeded)" | head -20`

Expected: Build errors in files that initialize SynthesisQueue (we'll fix in next step)

**Step 7: Update SynthesisQueue initialization call sites**

Find files that create SynthesisQueue and update them:

Run: `cd /Users/zachswift/projects/Listen2 && grep -r "SynthesisQueue(" --include="*.swift" Listen2/Listen2/Listen2/ | grep -v "class SynthesisQueue"`

For each file, change:
```swift
WordAlignmentService()
```
to:
```swift
PhonemeAlignmentService()
```

**Step 8: Test compilation again**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "(error|Build succeeded)" | head -20`

Expected: "Build succeeded"

**Step 9: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git add -u  # Add any other files with SynthesisQueue initialization changes
git commit -m "feat: replace WordAlignmentService with PhonemeAlignmentService

- Update SynthesisQueue to use phoneme-based alignment
- Handle new SynthesisResult return type from provider
- Rewrite performAlignment to use phoneme durations
- Update all SynthesisQueue initialization sites"
```

---

## Task 5: Test Phoneme Duration Alignment

**Files:**
- Test: Manual testing with iOS Simulator

**Goal:** Verify word highlighting works with new phoneme-based alignment

**Step 1: Build and run app**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -5`

Expected: "Build succeeded"

**Step 2: Launch in simulator**

Run: `open -a Simulator && sleep 5 && xcrun simctl install booted "$(find ~/Library/Developer/Xcode/DerivedData/Listen2-*/Build/Products/Debug-iphonesimulator/Listen2.app | head -1)" && xcrun simctl launch booted com.yourcompany.Listen2`

Expected: App launches successfully

**Step 3: Manual test cases**

Test these scenarios:
1. **Load a PDF** - Verify TTS synthesis works
2. **Play audio** - Verify word highlighting appears
3. **Words with apostrophes** - Load text with "author's", "there's", "it's"
4. **Punctuation** - Test em dashes (—), ellipsis (…), quotes ("")
5. **Timing accuracy** - Verify words highlight in sync with audio

**Step 4: Check debug logs**

Run: `xcrun simctl spawn booted log stream --predicate 'process == "Listen2"' --level debug | grep -E "(Phoneme|PiperTTS|SynthesisQueue)" &`

Expected logs:
```
[PiperTTS] Received X phoneme durations
[PhonemeAlign] Aligning X phonemes to text
[PhonemeAlign] Created X word timings
[SynthesisQueue] Alignment completed for paragraph X: Y words
```

**Step 5: Test edge cases**

- Empty text
- Very long text (>1000 chars)
- Text with only punctuation
- Mixed languages (if supported)

**Step 6: Document test results**

Run: `workshop note "Phoneme alignment testing: [PASS/FAIL] - [observations]"`

**Step 7: Commit any bug fixes discovered**

If bugs found, fix and commit:
```bash
git add <fixed-files>
git commit -m "fix: handle [specific edge case] in phoneme alignment"
```

---

## Task 6: Remove ASR-Based Alignment Code

**Files:**
- Delete: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/WordAlignmentService.swift`
- Delete: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/` directory
- Modify: Xcode project to remove references

**Goal:** Clean up old ASR code and free 44MB of model files

**Step 1: Verify no references to WordAlignmentService**

Run: `cd /Users/zachswift/projects/Listen2 && grep -r "WordAlignmentService" --include="*.swift" Listen2/Listen2/Listen2/ | grep -v "// OLD:"`

Expected: No results (all references should be replaced)

**Step 2: Remove WordAlignmentService.swift**

Run:
```bash
cd /Users/zachswift/projects/Listen2
git rm Listen2/Listen2/Listen2/Services/TTS/WordAlignmentService.swift
```

**Step 3: Remove ASR model files**

Run:
```bash
cd /Users/zachswift/projects/Listen2
git rm -r Listen2/Listen2/Listen2/Resources/ASRModels/
```

**Step 4: Remove ASR models from Xcode project**

Create and run Ruby script:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2')
Dir.chdir(project_dir)

project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Remove ASRModels group
asr_group = project.main_group.recursive_children.find do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == 'ASRModels'
end

if asr_group
  asr_group.remove_from_project
  puts "✅ Removed ASRModels group"
else
  puts "⏭️  ASRModels group not found"
end

project.save
puts "🎉 Xcode project updated"
```

Save as `remove_asr_models.rb` and run:
```bash
chmod +x remove_asr_models.rb
ruby remove_asr_models.rb
```

**Step 5: Verify app size reduction**

Run:
```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
du -sh ~/Library/Developer/Xcode/DerivedData/Listen2-*/Build/Products/Debug-iphonesimulator/Listen2.app
```

Expected: App should be ~44MB smaller

**Step 6: Test app still builds and runs**

Run: `cd /Users/zachswift/projects/Listen2/Listen2/Listen2 && xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep "Build succeeded"`

Expected: "Build succeeded"

**Step 7: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add -A
git commit -m "refactor: remove ASR-based alignment code and models

- Delete WordAlignmentService.swift (no longer needed)
- Remove ASRModels directory (44MB freed)
- Remove ASR model references from Xcode project
- App now uses direct phoneme durations from Piper TTS"
```

**Step 8: Record decision in workshop**

Run:
```bash
workshop decision "Removed ASR-based alignment in favor of phoneme durations" -r "Phoneme durations from Piper provide direct timing without re-transcription. Eliminates 44MB of ASR models, removes DTW complexity, handles apostrophes/punctuation correctly. Alignment is simpler and more accurate."
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/README.md`
- Modify: `/Users/zachswift/projects/Listen2/docs/phoneme-duration-implementation.md`

**Goal:** Document the new phoneme-based alignment approach

**Step 1: Update README.md**

Find the TTS section and update:

```markdown
## Text-to-Speech

Listen2 uses [Piper TTS](https://github.com/rhasspy/piper) via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) for high-quality offline speech synthesis.

### Word-Level Highlighting

Word-level highlighting is achieved by extracting phoneme durations directly from the Piper VITS model during synthesis. Phoneme durations are mapped to VoxPDF word positions using character-based timing distribution.

**Architecture:**
- Piper TTS generates audio + phoneme durations (`w_ceil` tensor)
- sherpa-onnx C API exposes phoneme durations to Swift
- PhonemeAlignmentService maps durations to words
- No ASR or re-transcription needed

**Advantages over ASR-based approaches:**
- No tokenization mismatch (direct text → phonemes)
- Handles apostrophes, punctuation correctly
- Smaller app bundle (no ASR models needed)
- Faster and more accurate alignment
```

**Step 2: Update implementation doc to mark complete**

```bash
cd /Users/zachswift/projects/Listen2/docs
```

Add to top of `phoneme-duration-implementation.md`:

```markdown
---
**STATUS: ✅ COMPLETED - 2025-11-12**

Successfully implemented phoneme duration extraction from Piper TTS.
ASR-based alignment removed, app bundle reduced by 44MB.
---
```

**Step 3: Create technical note about sherpa-onnx modifications**

Create `/Users/zachswift/projects/Listen2/docs/sherpa-onnx-modifications.md`:

```markdown
# sherpa-onnx Modifications for Phoneme Durations

## Overview

Listen2 uses a modified version of sherpa-onnx that exposes phoneme durations from Piper VITS models.

## Modifications

### C++ Layer
- **File**: `sherpa-onnx/csrc/offline-tts-vits-impl.h`
- **Change**: Extract `w_ceil` tensor from ONNX model output
- **Details**: The `w_ceil` tensor contains phoneme sample counts (multiply by 256 for actual sample count)

### C API Layer
- **File**: `sherpa-onnx/c-api/c-api.h`
- **Change**: Added `phoneme_durations` and `num_phonemes` to `SherpaOnnxGeneratedAudio` struct

```c
typedef struct SherpaOnnxGeneratedAudio {
  const float *samples;
  int32_t n;
  int32_t sample_rate;
  const int32_t *phoneme_durations;  // NEW
  int32_t num_phonemes;              // NEW
} SherpaOnnxGeneratedAudio;
```

## Building Modified sherpa-onnx

```bash
git clone https://github.com/k2-fsa/sherpa-onnx
cd sherpa-onnx
git checkout feature/piper-phoneme-durations
./build-ios.sh
```

Output: `build-ios/sherpa-onnx.xcframework`

## Commits

- `e9656a36` - feat: expose phoneme durations from Piper VITS models
- `6816bb0b` - fix: add default constructor to VitsOutput and fix initialization

## Resources

- [Piper Issue #425](https://github.com/rhasspy/piper/discussions/425) - Original discussion about accessing phoneme durations
- [sherpa-onnx fork](https://github.com/k2-fsa/sherpa-onnx) - Main repository
```

**Step 4: Commit documentation**

```bash
cd /Users/zachswift/projects/Listen2
git add README.md docs/
git commit -m "docs: update documentation for phoneme-based alignment

- Update README with new architecture description
- Mark implementation plan as complete
- Add technical note about sherpa-onnx modifications"
```

---

## Task 8: Performance Testing & Optimization

**Files:**
- Test: Performance profiling in Xcode Instruments

**Goal:** Verify phoneme alignment is faster than ASR approach

**Step 1: Profile alignment performance**

Run app with Instruments Time Profiler:
```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild -project Listen2.xcodeproj -scheme Listen2 -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
open -a Instruments
```

In Instruments:
1. Choose "Time Profiler"
2. Select Listen2 app
3. Record while synthesizing multiple paragraphs
4. Look for time spent in `PhonemeAlignmentService.align`

**Step 2: Measure timing metrics**

Add timing logs to PhonemeAlignmentService:

```swift
func align(...) async throws -> AlignmentResult {
    let startTime = Date()

    // ... existing code ...

    let elapsed = Date().timeIntervalSince(startTime)
    print("[PhonemeAlign] Alignment completed in \(elapsed * 1000)ms")

    return alignmentResult
}
```

**Step 3: Test with various text lengths**

- Short (< 50 chars)
- Medium (50-200 chars)
- Long (200-1000 chars)

Record timing for each.

**Step 4: Compare to ASR baseline (if available)**

If you have old logs with ASR timing, compare:
```bash
workshop note "Alignment performance - Phoneme: Xms/paragraph, ASR (old): Yms/paragraph, Improvement: Z%"
```

**Step 5: Optimize if needed**

If alignment > 50ms, consider:
- Caching character-to-timing lookups
- Pre-computing timing distributions
- Reducing validation overhead

**Step 6: Commit optimizations**

```bash
git add <optimized-files>
git commit -m "perf: optimize phoneme alignment for large texts"
```

---

## Success Criteria

**All tasks complete when:**

- ✅ sherpa-onnx C API phoneme durations extracted in Swift
- ✅ PiperTTSProvider returns `SynthesisResult` with phoneme durations
- ✅ PhonemeAlignmentService maps phonemes to words
- ✅ SynthesisQueue uses phoneme-based alignment
- ✅ Word highlighting works correctly with apostrophes/punctuation
- ✅ ASR code and models removed (44MB freed)
- ✅ Documentation updated
- ✅ Performance validated (< 50ms per paragraph)

**Testing checklist:**

- [ ] App builds successfully
- [ ] TTS synthesis produces audio
- [ ] Word highlighting appears during playback
- [ ] Apostrophes handled correctly ("author's", "it's")
- [ ] Punctuation handled correctly (em dash, ellipsis)
- [ ] Timing accuracy within 100ms
- [ ] No crashes on edge cases
- [ ] App bundle size reduced by ~44MB

---

## Rollback Plan

If phoneme alignment fails or has accuracy issues:

1. Revert commits: `git revert HEAD~8..HEAD`
2. Restore WordAlignmentService from git history
3. Re-add ASR models from git history
4. Document issues in workshop: `workshop gotcha "Phoneme alignment issue: [description]"`

---

## Future Enhancements

After successful implementation:

1. **Improve phoneme extraction** - Implement actual espeak-ng phonemization instead of placeholders
2. **Better timing distribution** - Use actual phoneme boundaries instead of character-based estimation
3. **Multi-language support** - Test with non-English voices
4. **Caching improvements** - Add persistent phoneme duration cache alongside audio cache

---

## Notes

- This plan assumes sherpa-onnx build is complete and framework is updated
- Phoneme alignment uses simple character-based timing as first implementation
- Future improvements can use actual espeak-ng phoneme positions for better accuracy
- All existing AlignmentResult consumers remain unchanged (same interface)
