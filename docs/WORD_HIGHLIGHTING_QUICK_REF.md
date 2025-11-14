# Word Highlighting - Quick Reference

## The Problem
Words highlight during playback, but timing is wrong because phoneme position data is corrupted.

## Why It's Corrupted
```
espeak-ng                        piper-phonemize               Swift
generates phonemes    ──→        fills gaps with       ──→    receives
h ə l oʊ              (12%)      duplicate positions          [3..<3]
                      (sparse)   creates [3..<3]             [3..<3]
                                 [3..<3] [3..<3] ...         [3..<3]
```

## Data Flow (5 Steps)

### 1️⃣ Piper TTS generates phonemes with positions
- **File:** `Listen2/Services/TTS/SherpaOnnx.swift`
- **Issue:** Positions are `[3..<3]` (all identical)

### 2️⃣ PhonemeAlignmentService tries to map to words
- **File:** `Listen2/Services/TTS/PhonemeAlignmentService.swift`
- **Problem:** Can't find overlaps, gets "No phonemes found" error
- **Result:** WordTimings are empty

### 3️⃣ TTSService starts 60 FPS highlight timer
- **File:** `Listen2/Services/TTSService.swift` (lines 474-489)
- **Problem:** Timer doesn't start if alignment is empty
- **Result:** No updates to `currentProgress.wordRange`

### 4️⃣ Timer updates progress with word range
- **File:** `Listen2/Services/TTSService.swift` (lines 498-552)
- **Problem:** Can't find word at current time (empty word timings)
- **Result:** `wordRange` never updates

### 5️⃣ UI applies highlighting
- **File:** `Listen2/Views/ReaderView.swift` (lines 139-172)
- **Result:** Same word stays highlighted or no highlighting

## What Format Does It Expect?

### Answer: Character Ranges (Range<String.Index>)

```swift
// NOT word indices like [0, 1, 2]
// But character ranges like:
wordRange = Range<String.Index>
// Which highlights paragraphText[startIndex..<endIndex]
```

### Conversion Path:
```
VoxPDF word position (integers):
  characterOffset: 0
  length: 5
         ↓
Converted to String.Index range:
  text.index(text.startIndex, offsetBy: 0)  ──┐
                                              ├─→ Range<String.Index>
  text.index(startIndex, offsetBy: 5)        ──┘
         ↓
Used for highlighting:
  attributedString[attrStartIndex..<attrEndIndex].backgroundColor = yellow
```

## Critical Files

| File | Lines | What It Does | Current Issue |
|------|-------|-------------|---------------|
| `SherpaOnnx.swift` | 150-180 | Reads phoneme positions from C API | Positions corrupted: `[3..<3]` not `[0..<1]` |
| `PhonemeAlignmentService.swift` | 97-181 | Maps phonemes to words | Can't find overlapping phonemes |
| `TTSService.swift` | 298-552 | Manages highlighting timer | Timer doesn't start when alignment fails |
| `ReaderView.swift` | 139-172 | Renders highlighted text | Works, but relies on VoxPDF positions not phoneme data |
| `SynthesisQueue.swift` | 196-251 | Triggers alignment | Checks if wordMap exists (line 201) |

## Where the "No Word Map" Error Comes From

**File:** `Listen2/Services/TTS/SynthesisQueue.swift:202`

```swift
guard let wordMap = wordMap else {
    print("[SynthesisQueue] No word map available for alignment")  // ← THIS LOG
    return
}
```

**When it happens:**
1. User opens a document WITHOUT word map extraction
2. `ReaderViewModel.togglePlayPause()` doesn't pass `wordMap`
3. `SynthesisQueue.setContent()` receives nil
4. Alignment never happens
5. Highlighting stops working

**How to fix:** Always extract word map when loading documents

## Diagnostic Points

Run the app with current code and check:

1. **C API position data** (sherpa-onnx/c-api/c-api.cc:1363)
   - Should show sequential values like `[0..<1] [1..<2] [2..<3]`

2. **Swift position data** (Listen2/Services/TTS/SherpaOnnx.swift:164)
   - Should match C API values
   - If different: Corruption is in pointer reading

3. **Alignment log** (PhonemeAlignmentService.swift:123)
   - Should show "No phonemes found" warnings
   - If present: Confirms position corruption

## Success Metrics

✅ **When highlighting works correctly:**
- Phoneme positions are sequential: `[0..<1] [1..<2] [2..<3]`
- Each word has non-zero duration
- Words highlight in sequence as audio plays
- No "No phonemes found" errors

❌ **Current state:**
- Phoneme positions all identical: `[3..<3] [3..<3]`
- No word timings created
- Highlighting frozen or absent
- 177 "No phonemes found" warnings in logs

## Next Session Action

1. Run app and capture logs
2. Find first `[SHERPA_C_API]` log output
3. Find first `[SherpaOnnx]` log output
4. Compare positions:
   - Same values? → Corruption is downstream
   - Different? → Corruption is in Swift pointer reading
   - C API wrong? → Corruption is in C++ gap-filling

5. Based on comparison, fix in appropriate layer

