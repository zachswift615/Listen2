# Word Highlighting - Code Locations & Line Numbers

## Complete File Reference

### 1. ReaderView.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift`

**Key Methods:**
- `attributedText(for:isCurrentParagraph:)` - Lines 139-172
  - Applies yellow highlight to word range
  - Expects `viewModel.currentWordRange: Range<String.Index>`
  
**Critical Line 144:**
```swift
guard isCurrentParagraph, let wordRange = viewModel.currentWordRange else {
    return attributedString
}
```
If `currentWordRange` is nil, no highlighting applied.

---

### 2. ReaderViewModel.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/ViewModels/ReaderViewModel.swift`

**Key Properties:**
- `currentWordRange: Range<String.Index>?` - Line 16
  - Published property that ReaderView observes
  
**Key Method:**
- `setupBindings()` - Lines 54-68
  - Lines 56-61: Subscribes to `ttsService.$currentProgress`
  - Updates `currentWordRange = progress.wordRange`
  
**Key Method:**
- `togglePlayPause()` - Lines 70-87
  - Line 80: Calls `ttsService.startReading(wordMap: document.wordMap)`
  - This is where word map gets passed to alignment system

---

### 3. TTSService.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Key Properties:**
- `currentProgress: ReadingProgress` - Line 21 (Published)
- `currentAlignment: AlignmentResult?` - Line 49
- `highlightTimer: Timer?` - Line 48
- `wordMap: DocumentWordMap?` - Line 40

**Key Methods:**

1. `startReading()` - Lines 278-310
   - Line 284: `self.wordMap = wordMap`
   - Line 291-296: Passes wordMap to synthesisQueue

2. `playAudio()` - Lines 421-439
   - Line 425: `currentAlignment = synthesisQueue?.getAlignment(for: paragraphIndex)`
   - Line 437: Calls `startHighlightTimer()`

3. `startHighlightTimer()` - Lines 474-489
   - Line 476: `guard currentAlignment != nil else { return }`
   - **CRITICAL:** If alignment is nil, timer never starts!
   - Line 486: Creates 60 FPS timer (1/60 second = ~16ms)

4. `updateHighlightFromTime()` - Lines 498-552
   - Line 499: `guard let alignment = currentAlignment else { return }`
   - Line 506: `if let wordTiming = alignment.wordTiming(at: currentTime)`
   - Lines 531-535: Updates `currentProgress.wordRange`

5. `willSpeakRangeOfSpeechString()` - Lines 599-618 (delegate)
   - Fallback highlighting for AVSpeech (when Piper not available)

---

### 4. SynthesisQueue.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Key Properties:**
- `alignments: [Int: AlignmentResult]` - Line 25
- `wordMap: DocumentWordMap?` - Line 52

**Key Methods:**

1. `setContent()` - Lines 65-77
   - Line 73: `self.wordMap = wordMap`
   - Stores word map for later use

2. `getAlignment()` - Lines 143-148
   - Returns cached alignment for a paragraph
   - Called by TTSService at line 425

3. `performAlignment()` - Lines 196-251
   - **Line 201-204: THE "NO WORD MAP" ERROR**
   ```swift
   guard let wordMap = wordMap else {
       print("[SynthesisQueue] No word map available for alignment")  // ← THIS LOG
       return
   }
   ```
   - Lines 220-225: Calls alignment service
   - Line 228: Caches alignment result

---

### 5. PhonemeAlignmentService.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`

**Key Method:**
- `align()` - Lines 28-75
  - Main alignment entry point
  - Gets VoxPDF words: Line 44
  - Calls `mapPhonemesToWords()`: Line 53

**Key Method:**
- `mapPhonemesToWords()` - Lines 97-181
  - Line 110: Builds phoneme index
  - Line 114: Gets word character range
  - Line 117-120: Finds overlapping phonemes
  - **Line 122-126: LOGS "NO PHONEMES FOUND"**
  ```swift
  if wordPhonemes.isEmpty {
      print("⚠️  [PhonemeAlign] No phonemes found for word '\(word.text)' at chars \(wordCharRange)")
      continue
  }
  ```
  - Line 130: Sums phoneme durations
  - Line 162-168: Creates WordTiming

**Key Method:**
- `buildPhonemeIndex()` - Lines 184-194
  - Maps character positions to phonemes
  - For each position in phoneme.textRange, adds phoneme to index

**Key Method:**
- `findPhonemesForCharRange()` - Lines 197-211
  - Returns phonemes whose textRange overlaps the given range

---

### 6. AlignmentResult.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift`

**Key Struct:**
- `WordTiming` - Lines 13-73
  - `wordIndex: Int` - Line 15
  - `startTime: TimeInterval` - Line 18
  - `duration: TimeInterval` - Line 21
  - `text: String` - Line 24
  - `rangeLocation: Int` - Line 27 (stored for Codable)
  - `rangeLength: Int` - Line 28 (stored for Codable)
  
  - `stringRange(in:)` - Lines 67-73
    - Reconstructs Range<String.Index> from stored offsets

- `wordTiming(at:)` - Lines 88-143
  - Binary search to find word at given time
  - Returns WordTiming or nil

---

### 7. ReadingProgress.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Models/ReadingProgress.swift`

**Key Struct:**
- `paragraphIndex: Int` - Line 9
- `wordRange: Range<String.Index>?` - Line 10
  - **THIS IS WHAT GETS HIGHLIGHTED!**
- `isPlaying: Bool` - Line 11

---

### 8. WordPosition.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Models/WordPosition.swift`

**Key Struct:**
- `WordPosition` - Lines 11-53
  - `text: String` - Line 13
  - `characterOffset: Int` - Line 16
  - `length: Int` - Line 19
  - `paragraphIndex: Int` - Line 22
  - `boundingBox: BoundingBox?` - Line 28

- `DocumentWordMap` - Lines 56-119
  - `words: [WordPosition]` - Line 58
  - `wordsByParagraph: [Int: [WordPosition]]` - Line 61
  - `words(for:)` - Lines 69-71
  - `word(at:in:)` - Lines 78-83

---

### 9. SherpaOnnx.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

**Key Struct:**
- `PhonemeInfo` - (Bridging code)
  - `symbol: String`
  - `duration: Float?`
  - `textRange: Range<Int>` - **CORRUPTED DATA HERE**

**Key Code:**
- Lines 150-180: Extracting phonemes from C API
  - **Lines 164-172: DIAGNOSTIC LOGGING**
  ```swift
  let sampleCount = min(5, phonemeCount)
  print("[SherpaOnnx] First \(sampleCount) phonemes' raw position data:")
  for i in 0..<sampleCount {
      let start = startsPtr[i]
      let length = lengthsPtr[i]
      print("  [\(i)]: char_start=\(start), char_length=\(length) -> range[\(start)..<\(start+length)]")
  }
  ```

---

### 10. PiperTTSProvider.swift
**Path:** `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift`

**Key Struct:**
- `SynthesisResult` - Lines 12-24
  - `audioData: Data` - Line 14
  - `phonemes: [PhonemeInfo]` - Line 17 (contains corrupted positions)
  - `text: String` - Line 20
  - `sampleRate: Int32` - Line 23

---

## The Highlighting Flow - Code Path

```
User taps Play
    ↓
ReaderViewModel.togglePlayPause() [line 70]
    ↓
ttsService.startReading(wordMap: document.wordMap) [line 76-82]
    ↓
TTSService.startReading() [line 278]
    → synthesisQueue.setContent(wordMap: wordMap) [line 291]
    → speakParagraph(at: index) [line 309]
    ↓
SynthesisQueue.getAudio(for: index) [line 94]
    → provider.synthesize(text, speed) [line 113]
    → performAlignment(for: index) [line 119]
    ↓
SynthesisQueue.performAlignment() [line 200]
    guard let wordMap = wordMap else { return } [line 201-204]  ← Can fail here!
    → alignmentService.align(phonemes, text, wordMap) [line 220]
    → alignments[index] = alignment [line 228]
    ↓
TTSService.playAudio() [line 421]
    → currentAlignment = synthesisQueue.getAlignment() [line 425]
    → startHighlightTimer() [line 437]
    ↓
TTSService.startHighlightTimer() [line 474]
    guard currentAlignment != nil else { return } [line 476]  ← Can fail here!
    → Timer fires every 16ms [line 486]
    ↓
TTSService.updateHighlightFromTime() [line 498]
    guard let alignment = currentAlignment else { return } [line 499]
    if let wordTiming = alignment.wordTiming(at: currentTime) [line 506]
        → currentProgress.wordRange = stringRange [line 545-547]
    ↓
ReaderViewModel (Combine subscription) [line 56-60]
    → currentWordRange = progress.wordRange
    ↓
ReaderView.attributedText() [line 139]
    guard let wordRange = currentWordRange else { return } [line 144]
    → attributedString[range].backgroundColor = highlightColor
    ↓
User sees highlighted word ✅
```

## Critical Points Where Highlighting Can Fail

1. **No word map passed** (line 201 SynthesisQueue.swift)
   - Error: "No word map available for alignment"
   - Result: alignment is nil

2. **Phoneme positions corrupted** (line 164 SherpaOnnx.swift)
   - Positions like [3..<3] instead of [0..<1] [1..<2]
   - Result: PhonemeAlignmentService finds no overlaps

3. **No phonemes found for word** (line 122 PhonemeAlignmentService.swift)
   - Result: WordTiming skipped, word has no timing

4. **currentAlignment is nil** (line 476 TTSService.swift)
   - Result: Timer never starts, no highlighting updates

5. **No word timing at current time** (line 506 TTSService.swift)
   - Result: wordRange stays nil, highlighting doesn't update

6. **Invalid string range** (line 508 TTSService.swift)
   - Result: Highlighting skipped for this frame

## Diagnostic Output Locations

**C++ / C API boundary:**
- File: `sherpa-onnx/c-api/c-api.cc`
- Lines: 1363-1371
- Log prefix: `[SHERPA_C_API] First 5 phonemes' position data:`

**Swift pointer reading:**
- File: `Listen2/Services/TTS/SherpaOnnx.swift`
- Lines: 164-172
- Log prefix: `[SherpaOnnx] First 5 phonemes' raw position data:`

**Word alignment results:**
- File: `Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Lines: 171-173 (success) and 123-125 (failure)
- Log prefix: `[PhonemeAlign]` and `⚠️  [PhonemeAlign]`

**Word alignment mapping:**
- File: `Listen2/Services/TTS/WordAlignmentService.swift`
- Line 718
- Log prefix: `🔗 DTW Alignment`

---

## Related Files Not Directly Used But Important

- `DocumentProcessor.swift` - Creates DocumentWordMap
- `VoxPDFService.swift` - Extracts word positions from PDFs
- `Document.swift` - Stores wordMap
- `AudioPlayer.swift` - Provides `currentTime` for highlighting

