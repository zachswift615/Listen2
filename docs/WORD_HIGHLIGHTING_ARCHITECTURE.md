# Listen2 Word Highlighting Architecture Analysis

**Date:** 2025-11-13  
**Status:** Highlighting works, but position data is corrupted  
**Priority:** CRITICAL - Foundation for accurate word-level playback

---

## EXECUTIVE SUMMARY

### What Works
- End-to-end highlighting flow is complete and functional
- Data flows from C++ → C API → Swift → UI
- Words ARE highlighting during playback (confirmed in logs)
- Character range format (Range<String.Index>) is correct

### What's Broken
- **Phoneme positions are corrupted** - all phonemes show identical ranges like `[3..<3]` instead of sequential `[0..<1] [1..<2] [2..<3]`
- This causes word alignment to fail (177 "no phonemes found" warnings)
- Word timings all show `0.000s for 0.000s`
- Highlighting works but is unreliable/inaccurate

### Root Cause
espeak-ng emits **sparse position events** (only 12-75% of phonemes), and the gap-filling strategy in piper-phonemize duplicates positions, resulting in many phonemes with identical character ranges.

---

## ARCHITECTURE OVERVIEW

### Data Flow for Word Highlighting

```
Piper TTS (C++)
    ↓ SynthesisResult.phonemes
PhonemeAlignmentService (Swift)
    ↓ AlignmentResult.wordTimings
TTSService.currentAlignment
    ↓ via highlight timer (60 FPS)
updateHighlightFromTime()
    ↓ wordTiming.stringRange(in: paragraphText)
TTSService.currentProgress.wordRange
    ↓ Combine publisher
ReaderViewModel.currentWordRange
    ↓ AttributedString
ReaderView.paragraphView()
    ✅ User sees highlighted word
```

### Data Structures

#### PhonemeInfo (from Piper TTS)
**File:** `Listen2/Services/TTS/SherpaOnnx.swift`

```swift
struct PhonemeInfo: Codable, Hashable {
    let symbol: String              // "h", "ə", "l", etc.
    let duration: Float?            // MISSING - always nil
    let textRange: Range<Int>       // Character positions [0..<1], [1..<2], etc.
}
```

**Critical Issue:** `textRange` is corrupted - all show identical start/end positions like `[3..<3]`

#### AlignmentResult (from PhonemeAlignmentService)
**File:** `Listen2/Services/TTS/AlignmentResult.swift`

```swift
struct WordTiming: Codable {
    let wordIndex: Int                       // Index in VoxPDF words
    let startTime: TimeInterval              // Computed from phoneme durations
    let duration: TimeInterval               // Sum of phoneme durations
    let text: String                         // "Hello", "world", etc.
    let stringRange: Range<String.Index>     // Character range in paragraph
}
```

#### ReadingProgress (Current playback state)
**File:** `Listen2/Models/ReadingProgress.swift`

```swift
struct ReadingProgress {
    let paragraphIndex: Int
    let wordRange: Range<String.Index>?      // THIS gets highlighted in ReaderView
    let isPlaying: Bool
}
```

---

## HIGHLIGHTING FLOW - DETAILED

### Step 1: Synthesis → Phoneme Data
**File:** `Listen2/Services/TTS/PiperTTSProvider.swift`
**Line:** 88-120 (synthesize method)

```swift
func synthesize(_ text: String, speed: Float) async throws -> SynthesisResult {
    // ...
    // Returns SynthesisResult with:
    // - audioData: WAV file
    // - phonemes: [PhonemeInfo] with corrupted textRange values
    // - text: original input
}
```

**What it does:**
1. Calls sherpa-onnx C API to synthesize text
2. Extracts phoneme data from C++ structure
3. Returns SynthesisResult with phoneme array

**The Problem:** Phonemes have corrupted `textRange` values:
```
h[3..<3]  ə[3..<3]  l[3..<3]  oʊ[3..<3]  ...  ← ALL IDENTICAL!
Expected: h[0..<1]  ə[1..<2]  l[2..<3]  oʊ[3..<5]  ...
```

---

### Step 2: Phoneme → Word Alignment
**File:** `Listen2/Services/TTS/PhonemeAlignmentService.swift`
**Method:** `align()` (lines 28-75)

```swift
func align(
    phonemes: [PhonemeInfo],
    text: String,
    wordMap: DocumentWordMap,
    paragraphIndex: Int
) async throws -> AlignmentResult {
    // Get VoxPDF words for this paragraph
    let voxPDFWords = wordMap.words(for: paragraphIndex)
    
    // Map phonemes to words using character position overlaps
    let wordTimings = try mapPhonemesToWords(
        phonemes: phonemes,
        text: text,
        voxPDFWords: voxPDFWords
    )
    
    return AlignmentResult(
        paragraphIndex: paragraphIndex,
        totalDuration: totalDuration,
        wordTimings: wordTimings
    )
}
```

**The Algorithm:** `mapPhonemesToWords()` (lines 97-181)

1. **Build phoneme index** by character position (line 110)
   ```swift
   let phonemesByChar = buildPhonemeIndex(phonemes: phonemes)
   // Maps character positions to phonemes for fast lookup
   ```

2. **For each VoxPDF word** (lines 112-177):
   - Get character range: `word.characterOffset..<(word.characterOffset + word.length)`
   - Find all phonemes overlapping this range (line 117-120)
   - Calculate timing from phoneme durations

3. **Create WordTiming** with character range from VoxPDF (lines 162-168):
   ```swift
   wordTimings.append(AlignmentResult.WordTiming(
       wordIndex: wordIndex,
       startTime: startTime,
       duration: duration,
       text: word.text,
       stringRange: stringRange  // From VoxPDF word position
   ))
   ```

**Why It Fails:**
```
VoxPDF word "Hello" at [0..<5]
  ↓
Find phonemes in range [0..<5]:
  h[3..<3]  ← Doesn't overlap! (3 >= 5 is false, but [3..<3] is empty)
  ə[3..<3]  ← Doesn't overlap!
  l[3..<3]  ← Doesn't overlap!
  ...
Result: "No phonemes found for word 'Hello'" ❌
```

**Lines 122-126 log this:**
```swift
if wordPhonemes.isEmpty {
    print("⚠️  [PhonemeAlign] No phonemes found for word '\(word.text)' at chars \(wordCharRange)")
    // Skip words without phonemes
    continue
}
```

---

### Step 3: Alignment → Playback Timer
**File:** `Listen2/Services/TTSService.swift`
**Method:** `startHighlightTimer()` (lines 474-489)

```swift
private func startHighlightTimer() {
    guard currentAlignment != nil else { return }  // FAILS if no alignment
    
    stopHighlightTimer()
    
    // Create 60 FPS timer for smooth highlighting
    highlightTimer = Timer.scheduledTimer(
        withTimeInterval: 1.0 / 60.0,  // ~16ms
        repeats: true
    ) { [weak self] _ in
        self?.updateHighlightFromTime()
    }
}
```

**What happens:**
- Timer fires 60 times per second
- Each time calls `updateHighlightFromTime()`
- Updates `currentProgress.wordRange` for UI

---

### Step 4: Playback Timer → Progress Update
**File:** `Listen2/Services/TTSService.swift`
**Method:** `updateHighlightFromTime()` (lines 498-552)

```swift
private func updateHighlightFromTime() {
    guard let alignment = currentAlignment else { return }
    
    let currentTime = audioPlayer.currentTime
    
    // Binary search to find word at current time
    if let wordTiming = alignment.wordTiming(at: currentTime),
       let stringRange = wordTiming.stringRange(in: paragraphText) {
        
        // Update progress with highlighted word range
        currentProgress = ReadingProgress(
            paragraphIndex: currentProgress.paragraphIndex,
            wordRange: stringRange,
            isPlaying: true
        )
    }
}
```

**Key Point:** Uses `AlignmentResult.wordTiming(at:)` to find current word (lines 88-143)
- Binary search for O(log n) performance
- Returns word timing at given playback time

**The Problem:**
- If alignment failed (no phonemes found), `wordTimings` is empty
- No word timing can be found
- Highlighting stops working

---

### Step 5: Progress Update → UI Highlighting
**File:** `Listen2/Views/ReaderView.swift`
**Method:** `attributedText()` (lines 139-172)

```swift
private func attributedText(for text: String, isCurrentParagraph: Bool) -> AttributedString {
    var attributedString = AttributedString(text)
    
    guard isCurrentParagraph, let wordRange = viewModel.currentWordRange else {
        return attributedString
    }
    
    // Convert String.Index range to AttributedString range
    let startOffset = text.distance(from: text.startIndex, to: wordRange.lowerBound)
    let endOffset = text.distance(from: text.startIndex, to: wordRange.upperBound)
    
    let attrStartIndex = attributedString.index(
        attributedString.startIndex,
        offsetByCharacters: startOffset
    )
    let attrEndIndex = attributedString.index(
        attributedString.startIndex,
        offsetByCharacters: endOffset
    )
    
    // Apply yellow highlight
    attributedString[attrStartIndex..<attrEndIndex].backgroundColor = DesignSystem.Colors.highlightWord
    
    return attributedString
}
```

**What it expects:**
- `currentWordRange`: Range<String.Index> with valid start and end positions
- Extracted text MUST match paragraph text

**Why it works even with corrupted data:**
- `wordRange` is from VoxPDF word positions (not from phonemes!)
- Phoneme corruption doesn't affect this fallback
- Result: Highlighting works but with wrong timing

---

## THE WORD MAP ARCHITECTURE

### DocumentWordMap
**File:** `Listen2/Models/WordPosition.swift`
**Lines:** 56-119

```swift
struct DocumentWordMap: Codable {
    let words: [WordPosition]
    private(set) var wordsByParagraph: [Int: [WordPosition]] = [:]
    
    func words(for paragraphIndex: Int) -> [WordPosition] {
        return wordsByParagraph[paragraphIndex] ?? []
    }
}
```

### WordPosition
**Lines:** 11-53

```swift
struct WordPosition: Codable {
    let text: String                    // "Hello"
    let characterOffset: Int            // 0
    let length: Int                     // 5
    let paragraphIndex: Int             // 0
    let pageNumber: Int                 // 1
    let boundingBox: BoundingBox?       // PDF visual position (unused for TTS)
}
```

**Key Point:** WordMap comes from VoxPDF (PDF text extraction)
- NOT from TTS phonemes
- Contains accurate character positions from PDF
- Used as reference to validate phoneme alignment

### Where WordMap Comes From
**File:** `Listen2/Services/DocumentProcessor.swift`
1. Extracts text from PDF
2. Calls VoxPDFService to get word positions
3. Creates DocumentWordMap
4. Stores in Document.wordMap

**Key Line in TTSService (line 278):**
```swift
func startReading(
    paragraphs: [String],
    from index: Int,
    title: String = "Document",
    wordMap: DocumentWordMap? = nil,  // Passed from ReaderViewModel
    documentID: UUID? = nil
) {
    self.wordMap = wordMap
    // ...
    synthesisQueue?.setContent(
        paragraphs: paragraphs,
        speed: playbackRate,
        documentID: documentID,
        wordMap: wordMap
    )
}
```

**And in ReaderViewModel (lines 74-82):**
```swift
if ttsService.currentProgress.paragraphIndex == 0 && ttsService.currentProgress.wordRange == nil {
    ttsService.startReading(
        paragraphs: document.extractedText,
        from: currentParagraphIndex,
        title: document.title,
        wordMap: document.wordMap,  // ← Passed here!
        documentID: document.id
    )
}
```

---

## WHERE THE "NO WORD MAP" ERROR COMES FROM

**File:** `Listen2/Services/TTS/SynthesisQueue.swift`
**Lines:** 196-251

```swift
private func performAlignment(for index: Int, result: SynthesisResult) async {
    guard let wordMap = wordMap else {
        print("[SynthesisQueue] No word map available for alignment")  // ← THIS LOG
        return
    }
    
    // Only proceed if word map is set
    let alignment = try await alignmentService.align(
        phonemes: result.phonemes,
        text: result.text,
        wordMap: wordMap,
        paragraphIndex: index
    )
    
    alignments[index] = alignment
}
```

**When This Happens:**
1. `synthesisQueue.setContent()` called without wordMap parameter
2. `wordMap` property is nil
3. Early return, no alignment performed
4. `currentAlignment` stays nil
5. Highlight timer doesn't start
6. No word highlighting occurs

**Root Cause in ReaderViewModel:** If `document.wordMap` is nil, highlighting fails entirely.

---

## FORMAT EXPECTATIONS

### Does the Code Expect Character Ranges or Word Indices?

**Answer:** CHARACTER RANGES (Range<String.Index>)

#### Evidence 1: wordRange Type
**File:** `Listen2/Models/ReadingProgress.swift`
```swift
let wordRange: Range<String.Index>?
```

#### Evidence 2: UI Implementation
**File:** `Listen2/Views/ReaderView.swift` lines 154-169
```swift
// Convert String.Index range to AttributedString range
let startOffset = text.distance(from: text.startIndex, to: wordRange.lowerBound)
let endOffset = text.distance(from: text.startIndex, to: wordRange.upperBound)

attributedString[attrStartIndex..<attrEndIndex].backgroundColor = ...
```

#### Evidence 3: Highlight Timer Updates
**File:** `Listen2/Services/TTSService.swift` lines 531-535
```swift
currentProgress = ReadingProgress(
    paragraphIndex: currentProgress.paragraphIndex,
    wordRange: nextRange,  // ← String.Index range, not word index
    isPlaying: true
)
```

#### Evidence 4: WordTiming Structure
**File:** `Listen2/Services/TTS/AlignmentResult.swift` lines 13-73
```swift
struct WordTiming: Codable, Equatable {
    let wordIndex: Int                      // Index in word array
    let stringRange: Range<String.Index>    // ← CHARACTER RANGE for highlighting
    
    func stringRange(in text: String) -> Range<String.Index>? {
        // Reconstructs range from stored offsets
        guard let start = text.index(text.startIndex, offsetBy: rangeLocation, ...),
              let end = text.index(start, offsetBy: rangeLength, ...) else {
            return nil
        }
        return start..<end
    }
}
```

### How Positions are Converted

**From VoxPDF word position (integer offsets):**
```swift
let characterOffset: Int = 0    // Position in paragraph text
let length: Int = 5             // Number of characters

// Convert to String.Index range
guard let startIndex = text.index(
    text.startIndex,
    offsetBy: characterOffset,
    limitedBy: text.endIndex
) else { return nil }

guard let endIndex = text.index(
    startIndex,
    offsetBy: length,
    limitedBy: text.endIndex
) else { return nil }

let stringRange = startIndex..<endIndex  // ← Result: Range<String.Index>
```

---

## THE ALIGNMENT LOGIC

### How PhonemeAlignmentService Maps Positions to Words

**File:** `Listen2/Services/TTS/PhonemeAlignmentService.swift`
**Lines:** 97-181

**The Algorithm:**

1. **Build character → phoneme index** (line 110)
   ```swift
   let phonemesByChar = buildPhonemeIndex(phonemes: phonemes)
   // phonemesByChar[0] = [PhonemeInfo(symbol: "h", textRange: 0..<1), ...]
   // phonemesByChar[1] = [PhonemeInfo(symbol: "ə", textRange: 1..<2), ...]
   // ...
   ```

2. **For each VoxPDF word:**
   ```swift
   for (wordIndex, word) in voxPDFWords.enumerated() {
       let wordCharRange = word.characterOffset..<(word.characterOffset + word.length)
       // word.text = "Hello"
       // wordCharRange = 0..<5
   ```

3. **Find all phonemes that overlap the word's character range:**
   ```swift
   let wordPhonemes = findPhonemesForCharRange(
       charRange: wordCharRange,
       phonemeIndex: phonemesByChar
   )
   // Returns: [PhonemeInfo] for all phonemes whose textRange overlaps [0..<5]
   ```

4. **Calculate word timing from phonemes:**
   ```swift
   let startTime = currentTime
   let duration = wordPhonemes.reduce(0.0) { $0 + $1.duration }
   // Sums all phoneme durations for this word
   ```

5. **Create WordTiming with character range from VoxPDF:**
   ```swift
   wordTimings.append(AlignmentResult.WordTiming(
       wordIndex: wordIndex,
       startTime: startTime,
       duration: duration,
       text: word.text,
       stringRange: stringRange  // ← From VoxPDF, not from phonemes!
   ))
   ```

**Why stringRange is from VoxPDF:**
- Lines 133-151 extract range using word's characterOffset and length
- This is more reliable than trying to reconstruct from phonemes
- Phoneme positions are currently corrupted anyway

---

## HIGHLIGHTING DURING PLAYBACK

### How Timing Works with Corrupted Positions

**The Workaround:** Even though phoneme positions are wrong, highlighting still works because:

1. **Word timings come from phoneme DURATIONS** (not positions)
   ```swift
   let duration = wordPhonemes.reduce(0.0) { $0 + $1.duration }
   ```

2. **Word character ranges come from VoxPDF** (not from phonemes)
   ```swift
   let stringRange = stringRange  // ← From word.characterOffset + word.length
   ```

3. **Highlighting uses VoxPDF ranges, not phoneme ranges**
   ```swift
   // updateHighlightFromTime()
   if let stringRange = wordTiming.stringRange(in: paragraphText) {
       currentProgress.wordRange = stringRange  // ← VoxPDF range!
   }
   ```

**Result:** Highlighting works but timing is inaccurate because:
- Word timings rely on phoneme durations being calculated correctly
- If phoneme overlap calculation fails (no phonemes found), word gets no duration
- Word appears to play for 0 seconds

---

## CRITICAL DATA FLOW ISSUE

### Why Corruption is Catastrophic

```
Text: "Hello world"

1. espeak-ng phonemization:
   h  ə  l  oʊ  w  ə  ld
   ↓ Emits position events (SPARSE - only ~12%)
   
2. piper-phonemize gap-filling:
   h[0]  ə[0]  l[0]  oʊ[6]  w[6]  ə[6]  ld[6]
   ↓ Duplication creates identical positions
   
3. Position length calculation (BUG):
   h[0..<0]  ə[0..<0]  l[0..<0]  oʊ[6..<0]  w[6..<0]  ...
   ↓ Causes "zero-width" ranges
   
4. Swift receives CORRUPTED data:
   h[3..<3]  ə[3..<3]  l[3..<3]  ...
   ↓ All positions are identical!
   
5. PhonemeAlignmentService finds ZERO phonemes for each word:
   Word "Hello" [0..<5] → Find phonemes in range [0..<5]
   h[3..<3] - No overlap! (3 >= 5, and range is empty)
   Result: "No phonemes found" ❌
   
6. WordTiming gets ZERO duration:
   duration = 0 + 0 + 0 + ... = 0.000s ❌
   
7. Highlighting breaks:
   - Timer fires every 16ms
   - No word timing found (all have 0 duration)
   - currentProgress.wordRange never updates
   - Same word stays highlighted forever
```

---

## DIAGNOSTIC LOGGING LOCATIONS

### Point 1: C++ / C API Boundary
**File:** `sherpa-onnx/c-api/c-api.cc` (lines 1363-1371)

Logs first 5 phonemes' position data BEFORE crossing C API boundary

### Point 2: Swift Pointer Reading
**File:** `Listen2/Services/TTS/SherpaOnnx.swift` (lines 164-172)

Logs first 5 phonemes' position data AFTER reading from C pointers

**Expected comparison:**
- If both show identical positions: **Corruption is in C++**
- If only Swift shows wrong: **Corruption is in pointer reading**
- If both correct: **Corruption is downstream in alignment**

---

## CONFIGURATION & INITIALIZATION

### Where Word Map Gets Set

**File:** `Listen2/Services/TTS/TTSService.swift`
**Lines:** 278-310 (startReading method)

```swift
func startReading(
    paragraphs: [String],
    from index: Int,
    title: String = "Document",
    wordMap: DocumentWordMap? = nil,      // ← Parameter
    documentID: UUID? = nil
) {
    // ...
    self.wordMap = wordMap               // ← Stored
    
    synthesisQueue?.setContent(
        paragraphs: paragraphs,
        speed: playbackRate,
        documentID: documentID,
        wordMap: wordMap                 // ← Passed to queue
    )
}
```

### Where It's Called
**File:** `Listen2/ViewModels/ReaderViewModel.swift`
**Lines:** 74-82

```swift
ttsService.startReading(
    paragraphs: document.extractedText,
    from: currentParagraphIndex,
    title: document.title,
    wordMap: document.wordMap,           // ← From document!
    documentID: document.id
)
```

**Critical Point:** If document is loaded without wordMap, highlighting will fail

---

## SYNTHESIS QUEUE ALIGNMENT MANAGEMENT

**File:** `Listen2/Services/TTS/SynthesisQueue.swift`

### State Variables
```swift
// Line 25: Cache of alignments
private var alignments: [Int: AlignmentResult] = [:]

// Line 52: Word map for alignment
private var wordMap: DocumentWordMap?
```

### Alignment Retrieval
```swift
// Lines 143-148: Get alignment for specific paragraph
func getAlignment(for index: Int) -> AlignmentResult? {
    return alignments[index]
}
```

### Flow
1. `setContent()` stores wordMap (line 73)
2. `getAudio()` synthesizes text (line 113)
3. `performAlignment()` creates alignment using wordMap (line 119)
4. Alignment cached in `alignments[index]` (line 228)
5. TTSService retrieves via `getAlignment(for:)` (line 425)
6. Timer uses `currentAlignment` for highlighting (line 499)

---

## SUMMARY: WHAT EACH COMPONENT EXPECTS

| Component | Expects | Format | From Where |
|-----------|---------|--------|------------|
| ReaderView | `currentWordRange` | `Range<String.Index>` | `viewModel.currentWordRange` |
| ReaderViewModel | `currentWordRange` | `Range<String.Index>` | `ttsService.currentProgress.wordRange` |
| TTSService.updateHighlightFromTime() | `wordTiming.stringRange()` | `Range<String.Index>` | `AlignmentResult.WordTiming` |
| PhonemeAlignmentService | phonemes with valid `textRange` | `Range<Int>` with proper overlap | Piper TTS / SherpaOnnx.swift |
| SynthesisQueue | wordMap with valid word positions | `DocumentWordMap` | ReaderViewModel / Document |
| TTSService.highlightTimer | alignment with word timings | `AlignmentResult` | `synthesisQueue.getAlignment()` |

---

## WHAT WE NEED TO FIX

### Issue 1: Phoneme Position Corruption (BLOCKING)
- **Symptom:** All phonemes show `[3..<3]` instead of `[0..<1] [1..<2]...`
- **Impact:** PhonemeAlignmentService can't find overlapping phonemes
- **Result:** No word timings created, no highlighting
- **Location:** Between sherpa-onnx C++ and Swift pointer reading
- **Action:** Run diagnostic logs to pinpoint corruption location

### Issue 2: Phoneme Duration Data Missing (SECONDARY)
- **Symptom:** `duration` field always nil in PhonemeInfo
- **Impact:** Word timings show `0.000s` duration
- **Result:** Timing is completely wrong
- **Location:** Piper TTS doesn't expose phoneme durations
- **Action:** Either extract from internal tensors or use forced alignment

### Issue 3: espeak Event Sparsity (ROOT CAUSE)
- **Symptom:** Only 12-75% of phonemes get position events
- **Impact:** Gap-filling creates duplicate positions
- **Result:** Corrupted position data in step 1
- **Location:** espeak-ng configuration or callback handling
- **Action:** Investigate why espeak isn't emitting events for all phonemes

---

## SUCCESS CRITERIA

When highlighting is working correctly:

1. **Diagnostic logs show:**
   - C API logs: `[0..<1] [1..<2] [2..<3] ...` (sequential)
   - Swift logs: Same as C API (no corruption)

2. **Alignment works:**
   - Each word finds phonemes that overlap
   - WordTimings have non-zero durations
   - No "no phonemes found" warnings

3. **Highlighting is smooth:**
   - Words highlight in sequence
   - Timing roughly matches audio playback
   - No words get stuck (> 2 second timeout)

4. **Performance is acceptable:**
   - Highlight timer runs at 60 FPS
   - No UI stuttering or lag
   - Memory usage stable

---

## KEY FILES REFERENCE

| File | Lines | Purpose |
|------|-------|---------|
| ReaderView.swift | 126-172 | Word highlighting in UI |
| ReaderViewModel.swift | 54-68 | Subscribes to currentProgress |
| TTSService.swift | 298-552 | Synthesis, timing, highlighting |
| PhonemeAlignmentService.swift | 28-181 | Maps phonemes to words |
| SynthesisQueue.swift | 65-251 | Manages synthesis and alignment |
| AlignmentResult.swift | 11-161 | Stores word timing data |
| WordPosition.swift | 11-119 | Stores word position metadata |
| SherpaOnnx.swift | 150-180 | C API interface, phoneme extraction |
| PiperTTSProvider.swift | 88-120 | Piper synthesis |

---

## NEXT STEPS

1. **Run diagnostic logging** with current code to locate corruption point
2. **Fix position data** (either in C++, Swift, or position calculation logic)
3. **Add duration data** (extract from Piper or estimate from audio)
4. **Validate end-to-end** with multiple documents and phoneme patterns
5. **Optimize performance** if needed

