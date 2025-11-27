# Word Highlighting Architecture

## Table of Contents
1. [System Overview](#system-overview)
2. [TTS Stack Architecture](#tts-stack-architecture)
3. [Word Highlighting Pipeline](#word-highlighting-pipeline)
4. [Component Details](#component-details)
5. [Critical Technical Details](#critical-technical-details)
6. [Known Issues & Fixes](#known-issues--fixes)

---

## System Overview

The Listen2 app provides real-time word-by-word highlighting synchronized with Text-to-Speech audio playback. This requires precise coordination between:
- **Text processing** (normalization, phonemization)
- **Audio synthesis** (TTS model)
- **Position tracking** (character offsets, phoneme positions)
- **Visual highlighting** (mapping normalized text back to original display text)

```
┌─────────────────────────────────────────────────────────────────┐
│                        LISTEN2 APP                              │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │   VoxPDF     │    │  TTS Stack   │    │ Highlighting │    │
│  │  Document    │───▶│ (Piper/Sherpa)│───▶│   Engine     │    │
│  │  Extraction  │    │              │    │              │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│         │                    │                    │            │
│         ▼                    ▼                    ▼            │
│  Original Text ──▶ Normalized Text ──▶ Word Timings ──▶ UI   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## TTS Stack Architecture

### Layer 1: Swift Layer (Listen2 App)
```
┌──────────────────────────────────────────────────────────────┐
│ TTSService.swift                                              │
│ - Manages voice selection                                    │
│ - Handles sentence queueing                                  │
│ - Coordinates synthesis and playback                         │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────────┐
│ SherpaOnnx.swift (Swift wrapper)                             │
│ - Wraps sherpa-onnx C API                                    │
│ - Extracts phoneme data from C structs                       │
│ - Converts positions, durations, symbols to Swift types      │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
```

### Layer 2: C API Bridge (sherpa-onnx)
```
┌──────────────────────────────────────────────────────────────┐
│ sherpa-onnx C API (c-api.cc)                                 │
│ - SherpaOnnxOfflineTtsGenerate()                            │
│ - Populates SherpaOnnxGeneratedAudio struct                 │
│   - samples (audio data)                                     │
│   - phoneme_symbols (char**)                                 │
│   - phoneme_durations (int32_t*)                             │
│   - phoneme_char_start (int32_t*)                            │
│   - phoneme_char_length (int32_t*)                           │
│   - normalized_text (char*)                                  │
│   - char_mapping (int32_t*)                                  │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
```

### Layer 3: TTS Implementation (sherpa-onnx C++)
```
┌──────────────────────────────────────────────────────────────┐
│ offline-tts-vits-impl.h (C++)                                │
│ - Implements TTS model inference                             │
│ - Calls piper-phonemize for text → phonemes                  │
│ - Runs ONNX model for phonemes → audio                       │
│ - Captures normalized_text immediately after tokenization    │
│   (CRITICAL: prevents state contamination from lookahead)    │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
```

### Layer 4: Phonemization (piper-phonemize)
```
┌──────────────────────────────────────────────────────────────┐
│ piper-phonemize (phonemize.cpp)                              │
│ - Text normalization (Dr. → doctor, don't → do not)         │
│ - Phoneme generation via espeak-ng                           │
│ - Position tracking (WORD and PHONEME events)                │
│ - Character mapping (original ↔ normalized)                  │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
```

### Layer 5: Speech Engine (espeak-ng)
```
┌──────────────────────────────────────────────────────────────┐
│ espeak-ng (C library)                                        │
│ - Text-to-phoneme conversion                                │
│ - Language-specific rules                                    │
│ - Event callbacks:                                           │
│   - espeakEVENT_WORD (word boundaries)                       │
│   - espeakEVENT_PHONEME (individual phonemes)                │
│ - APIs:                                                      │
│   - espeak_GetNormalizedText()                               │
│   - espeak_GetCharacterMapping()                             │
└──────────────────────────────────────────────────────────────┘
```

---

## Word Highlighting Pipeline

### Step 1: Text Input
```
┌─────────────────────────────────────────────────────────────┐
│ User opens PDF document                                      │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ VoxPDF extracts text by paragraph                           │
│ - Preserves original formatting (caps, punctuation)         │
│ - Example: "CHAPTER 2"                                       │
│ - Example: "Dr. Smith's research on TCP/IP"                 │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 2: TTS Synthesis (with position tracking)
```
┌─────────────────────────────────────────────────────────────┐
│ SherpaOnnx.generate(text: "CHAPTER 2")                      │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ piper-phonemize processes text                              │
│                                                              │
│ 1. Text normalization (espeak-ng)                           │
│    "CHAPTER 2" → "chapter 2 "                               │
│                                                              │
│ 2. Event stream from espeak-ng:                             │
│    [WORD] position=1, length=7  ("chapter")                 │
│    [PHONEME] t  [PHONEME] ʃ  [PHONEME] æ ...                │
│    [WORD] position=9, length=1  ("2")                       │
│    [PHONEME] t  [PHONEME] u  [PHONEME] ː                    │
│                                                              │
│ 3. Position tracking:                                       │
│    - Apply -1 offset to WORD positions (1-based → 0-based)  │
│    - Word 0: position=0, length=7                           │
│    - Word 1: position=8, length=1                           │
│    - Assign word positions to all phonemes in that word     │
│                                                              │
│ 4. Character mapping extraction:                            │
│    - Call espeak_GetCharacterMapping()                      │
│    - Apply -2 offset (different API, different indexing!)   │
│    - [(orig=0, norm=0), (orig=8, norm=8), ...]              │
│                                                              │
│ 5. Normalized text accumulation:                            │
│    - Capture after EACH clause (not at end!)                │
│    - accumulatedNormalizedText += "chapter 2 "              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 3: Phoneme Data Flow
```
┌─────────────────────────────────────────────────────────────┐
│ sherpa-onnx receives PhonemeResult from piper-phonemize:    │
│                                                              │
│ phonemes: [["t", "ʃ", "æ", "p", "t", "ɚ", ...], ...]        │
│ positions: [(pos=0, len=7), (pos=0, len=7), ... (pos=8)]   │
│ normalized_text: "chapter 2 "                               │
│ char_mapping: [(0,0), (8,8), (9,9)]                         │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ sherpa-onnx populates C API struct:                         │
│                                                              │
│ audio.phoneme_symbols = ["t", "ʃ", "æ", "p", "t", "ɚ", ...]│
│ audio.phoneme_char_start = [0, 0, 0, 0, 0, 0, ..., 8]      │
│ audio.phoneme_char_length = [7, 7, 7, 7, 7, 7, ..., 1]     │
│ audio.phoneme_durations = [samples from w_ceil tensor]      │
│ audio.normalized_text = "chapter 2 "                        │
│ audio.char_mapping = [0, 0, 8, 8, 9, 9] (flattened pairs)  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 4: Swift Extraction
```
┌─────────────────────────────────────────────────────────────┐
│ SherpaOnnx.swift extracts from C struct:                    │
│                                                              │
│ GeneratedAudio {                                             │
│   samples: [Float]          // PCM audio                    │
│   sampleRate: 22050                                         │
│   phonemes: [PhonemeInfo] {                                 │
│     symbol: "t"                                             │
│     duration: 0.034s        // from w_ceil tensor           │
│     textRange: 0..<7        // char_start..<char_start+len  │
│   }                                                          │
│   normalizedText: "chapter 2 "                              │
│   charMapping: [(0,0), (8,8), (9,9)]                        │
│ }                                                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 5: Alignment Creation
```
┌─────────────────────────────────────────────────────────────┐
│ PhonemeAlignmentService.align()                             │
│                                                              │
│ Input:                                                       │
│   phonemes: [PhonemeInfo] (12 phonemes for "CHAPTER 2")    │
│   text: "CHAPTER 2"                                         │
│   normalizedText: "chapter 2 "                              │
│   charMapping: [(0,0), (8,8), (9,9)]                        │
│                                                              │
│ Process:                                                     │
│   1. Split normalized text into words: ["chapter", "2"]    │
│   2. Group phonemes by textRange:                           │
│      Group 0: phonemes[0..6] (range 0..<7)                  │
│      Group 1: phonemes[7..11] (range 8..<9)                 │
│   3. Match normalized words to phoneme groups (1:1)         │
│   4. Map back to original text using charMapping:           │
│      - Find "chapter" at normalized pos 0                   │
│      - charMapping says orig 0 → norm 0                     │
│      - Extract "CHAPTER" from original text[0..<7]          │
│      - Find "2" at normalized pos 8                         │
│      - charMapping says orig 8 → norm 8                     │
│      - Extract "2" from original text[8..<9]                │
│   5. Calculate timing from phoneme durations                │
│                                                              │
│ Output: AlignmentResult {                                    │
│   wordTimings: [                                             │
│     { text: "CHAPTER", start: 0.0s, duration: 0.29s,        │
│       rangeLocation: 0, rangeLength: 7 },                   │
│     { text: "2", start: 0.29s, duration: 0.12s,             │
│       rangeLocation: 8, rangeLength: 1 }                    │
│   ]                                                          │
│ }                                                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 6: Timeline Building
```
┌─────────────────────────────────────────────────────────────┐
│ PhonemeTimelineBuilder.build()                              │
│                                                              │
│ Input (from SynthesisQueue):                                │
│   - synthesis result (phonemes, normalized text, mappings) │
│   - sentence text: "CHAPTER 2"                              │
│   - sentenceOffset: 0 (or N for Nth sentence in paragraph) │
│                                                              │
│ CRITICAL: Applies sentenceOffset to word boundaries!        │
│ This makes word positions paragraph-relative, not           │
│ sentence-relative. Essential for multi-sentence paragraphs. │
│                                                              │
│ Creates PhonemeTimeline from SynthesisResult:               │
│                                                              │
│ PhonemeTimeline {                                            │
│   sentenceText: "CHAPTER 2"                                 │
│   phonemes: [TimedPhoneme] (with start/end times)          │
│   wordBoundaries: [                                         │
│     { word: "CHAPTER",                                      │
│       startTime: 0.0s, endTime: 0.29s,                      │
│       originalStartOffset: 0, originalEndOffset: 7 },       │
│     { word: "2",                                            │
│       startTime: 0.29s, endTime: 0.41s,                     │
│       originalStartOffset: 8, originalEndOffset: 9 }        │
│   ]                                                          │
│   duration: 0.41s                                           │
│ }                                                            │
│                                                              │
│ Note: If this was sentence 2 starting at offset 50 in       │
│ the paragraph, all originalStartOffset values would have    │
│ 50 added to them.                                           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
```

### Step 7: Real-time Highlighting
```
┌─────────────────────────────────────────────────────────────┐
│ WordHighlighter (60 FPS CADisplayLink)                      │
│                                                              │
│ On startSentence():                                         │
│   - Store timeline (contains word timings)                  │
│   - Store paragraphText (full paragraph for highlighting)   │
│                                                              │
│ Every frame (16.67ms):                                      │
│   currentTime = audioPlayer.currentTime                     │
│                                                              │
│   for word in timeline.wordBoundaries:                      │
│     if word.startTime <= currentTime < word.endTime:        │
│       // Highlight this word!                               │
│       // Use paragraphText, not sentenceText!               │
│       highlightRange = word.stringRange(in: paragraphText)  │
│       UI updates with highlighted range                     │
│       break                                                  │
│                                                              │
│ CRITICAL: Word offsets are paragraph-relative, so we        │
│ must use paragraphText for range calculation!               │
│                                                              │
│ Timeline:                                                    │
│   0.00s ──────▶ 0.29s ──────▶ 0.41s                        │
│   [   CHAPTER   ] [    2     ]                              │
│         ↑               ↑                                    │
│    Highlight 1      Highlight 2                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Details

### Component: SherpaOnnx.swift
**Location:** `Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

**Responsibilities:**
1. Wrap sherpa-onnx C API for Swift
2. Extract phoneme data from C structs
3. Handle data type conversions (C → Swift)

**Critical Code:**
```swift
// Lines 150-280: GeneratedAudio initialization
init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>) {
  // Extract phonemes with positions
  for i in 0..<phonemeCount {
    let charStart = Int(startsPtr[i])
    let charLength = Int(lengthsPtr[i])
    let textRange = charStart..<(charStart + charLength)

    phonemes.append(PhonemeInfo(
      symbol: symbol,
      duration: duration,
      textRange: textRange
    ))
  }

  // Extract normalized text
  self.normalizedText = String(cString: normalized)

  // Extract character mapping
  for i in 0..<mapCount {
    let origPos = Int(mapping[i * 2])
    let normPos = Int(mapping[i * 2 + 1])
    charMapping.append((origPos, normPos))
  }
}
```

---

### Component: piper-phonemize
**Location:** `piper-phonemize/src/phonemize.cpp`

**Responsibilities:**
1. Text normalization via espeak-ng
2. Phoneme generation
3. Position tracking (WORD and PHONEME events)
4. Character mapping extraction

**Critical Code Sections:**

#### Event Callback (Lines 184-230)
```cpp
// Callback receives events from espeak-ng during synthesis
int SynthCallback(short* wav, int numsamples, espeak_EVENT* events) {
  while (events->type != espeakEVENT_LIST_TERMINATED) {
    if (events->type == espeakEVENT_WORD) {
      // CRITICAL: Apply -1 offset (espeak uses 1-based indexing)
      int adjusted_position = events->text_position >= 1
        ? events->text_position - 1
        : 0;

      WordInfo word;
      word.text_position = adjusted_position;
      word.length = events->length;
      g_phoneme_capture.words.push_back(word);
    }
    else if (events->type == espeakEVENT_PHONEME) {
      // Track which phonemes belong to current word
      g_phoneme_capture.current_word->phoneme_indices.push_back(
        g_phoneme_capture.current_phoneme_index
      );
      g_phoneme_capture.current_phoneme_index++;
    }
    events++;
  }
}
```

#### Normalized Text Accumulation (Lines 472-488)
```cpp
// CRITICAL: Accumulate INSIDE loop, not after!
std::string accumulatedNormalizedText;

while (inputTextPointer != NULL) {
  // Process each clause/sentence
  std::string clausePhonemes(espeak_TextToPhonemesWithTerminator(...));

  // Capture normalized text for THIS clause immediately
  const char* clauseNormalized = espeak_GetNormalizedText();
  if (clauseNormalized) {
    accumulatedNormalizedText += std::string(clauseNormalized);
  }

  // ... rest of processing ...
}

// Use accumulated text, not just last clause
result.normalized_text = accumulatedNormalizedText;
```

#### Character Mapping Extraction (Lines 580-590)
```cpp
// Get character mapping from espeak
int mapping[1024][2];
int map_count = espeak_GetCharacterMapping(mapping, 1024);

for (int i = 0; i < map_count; i++) {
  // CRITICAL: Apply -2 offset (different API than WORD events!)
  int adjusted_orig_pos = mapping[i][0] >= 2
    ? mapping[i][0] - 2
    : 0;
  result.char_mapping.push_back({adjusted_orig_pos, mapping[i][1]});
}
```

---

### Component: PhonemeAlignmentService
**Location:** `Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`

**Responsibilities:**
1. Match phoneme groups to words
2. Map normalized text back to original text
3. Calculate word timing from phoneme durations
4. Handle text normalization edge cases (contractions, abbreviations)

**Algorithm Flow:**
```
1. Extract words from original text: ["CHAPTER", "2"]
2. Extract words from normalized text: ["chapter", "2"]
3. Group phonemes by textRange:
   - All phonemes with range 0..<7 → Group 0
   - All phonemes with range 8..<9 → Group 1
4. Match normalized words to groups (should be 1:1)
5. For each display word:
   - Find corresponding phoneme group
   - Calculate duration from phoneme durations
   - Map normalized position → original position via charMapping
   - Create WordTiming with original text range
```

**Edge Cases Handled:**
- Contractions: "don't" → ["do", "not"] (combine phoneme groups)
- Abbreviations: "Dr." → "doctor" (map via abbreviations table)
- Numbers: "$99.99" → multiple words (consume multiple groups)
- Punctuation: Strip from normalized, match positionally

---

## Critical Technical Details

### espeak-ng Position Offsets

**Why we have different offsets for different data:**

espeak-ng has **two separate APIs** with **different indexing**:

1. **Event Callback (WORD events):**
   - Uses 1-based indexing
   - First character is at position 1
   - **Needs -1 offset** to convert to 0-based
   - Example: "CHAPTER" starts at position 1 → adjust to 0

2. **Character Mapping API (GetCharacterMapping):**
   - Uses different internal indexing
   - First character is at position 2 (!)
   - **Needs -2 offset** to convert to 0-based
   - Example: "CHAPTER" starts at position 2 → adjust to 0

**This is NOT a bug - it's two different espeak APIs with different conventions.**

```
Text:     C  H  A  P  T  E  R     2
Index:    0  1  2  3  4  5  6  7  8  (0-based, what we want)

WORD API: 1  -  -  -  -  -  -  9  -  (reports word start positions)
          └─ "CHAPTER" starts here (pos=1)
                                  └─ "2" starts here (pos=9)
Offset:  -1                    -1    (subtract 1 to get 0-based)

CharMap:  2  -  -  -  -  -  - 10  -  (character mapping entries)
          └─ position 2                └─ position 10
Offset:  -2                   -2    (subtract 2 to get 0-based)
```

### Normalized Text Accumulation

**Problem:** espeak-ng processes long text in chunks (clauses/sentences). When you call `espeak_GetNormalizedText()` after all processing, it only returns the **last chunk's** normalized text.

**Example:**
```
Input: "They start with a messy problem, a foundation model API key,
        and a rough idea of what might help."

espeak processes as:
  Chunk 1: "They start with a messy problem"
  Chunk 2: "a foundation model API key"
  Chunk 3: "and a rough idea of what might help"

espeak_GetNormalizedText() at end → "and a rough idea of what might help" ❌
```

**Solution:** Capture normalized text **inside the loop** after each chunk:
```cpp
while (inputTextPointer != NULL) {
  espeak_TextToPhonemesWithTerminator(...);

  // Capture THIS chunk's normalized text immediately
  const char* clauseNormalized = espeak_GetNormalizedText();
  if (clauseNormalized) {
    accumulatedNormalizedText += std::string(clauseNormalized);
  }
}
```

### State Management & Lookahead Synthesis

**Problem:** sherpa-onnx uses a **shared mutable state** for `last_normalized_text_`. When lookahead synthesis runs (pre-generating future sentences for smooth playback), it **overwrites** the normalized text before Swift can read it.

**Timeline of bug:**
```
1. User plays sentence A
2. Synthesize sentence A → normalized_text = "sentence a"
3. Start lookahead for sentence B
4. Synthesize sentence B → normalized_text = "sentence b" ← OVERWRITES!
5. Swift reads normalized_text → gets "sentence b" ❌ (should be "sentence a")
```

**Solution:** Capture normalized text **immediately** after tokenization, before lookahead can run:
```cpp
// offline-tts-vits-impl.h lines 218-228
auto result = lexicon->ConvertTextToTokenIds(text, voice);

// IMMEDIATELY capture normalized text into local variable
std::string captured_normalized_text = lexicon->GetLastNormalizedText();
std::vector<std::pair<int32_t, int32_t>> captured_char_mapping =
  lexicon->GetLastCharMapping();

// ... later, lookahead synthesis can run ...

// Use captured values (immune to state changes)
normalized_text = captured_normalized_text;
char_mapping = captured_char_mapping;
```

### Phoneme Duration Extraction

Phoneme durations come from the TTS model's **w_ceil tensor** (duration predictor output):

```cpp
// offline-tts-vits-impl.h
auto w_ceil_values = w_ceil_tensor.GetTensorMutableData<int64_t>();

for (int64_t i = 0; i < total_w_ceil; i++) {
  int64_t duration = w_ceil_values[i];
  phoneme_durations.push_back(static_cast<int32_t>(duration));
}
```

**Units:** Duration is in **samples**, not seconds.
**Conversion:** `duration_seconds = samples / sample_rate`
**Example:** 750 samples @ 22050 Hz = 0.034 seconds

---

## Known Issues & Fixes

### Issue #1: Character Offset Bug (FIXED)
**Commit:** `1882de7` in piper-phonemize (2024-11-16)

**Symptom:** "CHAPTER" highlighted as "APTER" (missing first 2 characters)

**Root Cause:** Character mapping positions had espeak's +2 offset, but no correction was applied.

**Fix:** Apply -2 offset to character mapping:
```cpp
// phonemize.cpp:578
int adjusted_orig_pos = mapping[i][0] >= 2 ? mapping[i][0] - 2 : 0;
result.char_mapping.push_back({adjusted_orig_pos, mapping[i][1]});
```

---

### Issue #2: Normalized Text Truncation (FIXED)
**Commit:** `f2640e8` in piper-phonemize (2024-11-16)

**Symptom:** Long sentences only captured the last clause

**Root Cause:** `espeak_GetNormalizedText()` called once after phonemization loop, returning only last chunk.

**Fix:** Accumulate inside loop:
```cpp
// phonemize.cpp:485-488
const char* clauseNormalized = espeak_GetNormalizedText();
if (clauseNormalized) {
  accumulatedNormalizedText += std::string(clauseNormalized);
}
```

---

### Issue #3: WORD Position Offset Bug (FIXED)
**Commit:** `5266ed0` in piper-phonemize (2024-11-16)

**Symptom:** Words being skipped during highlighting ("2" in "CHAPTER 2", "Agent" in "Designing Agent Systems")

**Root Cause:** WORD events use 1-based indexing but were getting -2 offset (correct for character mapping API but wrong for WORD events)

**Example of bug:**
```
Text: "CHAPTER 2"
Positions: C=0, H=1, A=2, P=3, T=4, E=5, R=6, (space)=7, 2=8

WORD event for "2": raw_position=9
With -2 offset: adjusted=7 ❌ (phonemes at position 7)
But "2" is at position 8 in text!
Result: No overlap between phoneme range 7..<8 and word position 8..<9
```

**Fix:** Change WORD offset from -2 to -1:
```cpp
// phonemize.cpp:204
int adjusted_position = events->text_position >= 1
  ? events->text_position - 1
  : 0;
```

**Why different offsets are correct:**
- WORD events: 1-based indexing → -1 offset
- Character mapping: 2-based indexing → -2 offset
- These are different espeak APIs with different indexing!

---

### Issue #4: State Contamination (FIXED)
**Commit:** Previous session (sherpa-onnx, 2024-11-15)

**Symptom:** Normalized text from previous synthesis appearing in current synthesis

**Root Cause:** Shared mutable state `last_normalized_text_` overwritten by lookahead synthesis

**Fix:** Capture immediately after tokenization:
```cpp
// offline-tts-vits-impl.h:218-228
auto result = lexicon->ConvertTextToTokenIds(text, voice);
std::string captured_normalized_text = lexicon->GetLastNormalizedText();
// ... use captured value later, immune to state changes
```

---

## Testing & Validation

### Test Cases

1. **Simple words:**
   - "Building" → "building "
   - Should highlight entire word ✓

2. **Multi-word with numbers:**
   - "CHAPTER 2" → "chapter 2 "
   - Should highlight "CHAPTER", then "2" ✓

3. **Multi-word phrases:**
   - "Designing Agent Systems" → "designing agent systems "
   - Should highlight all three words in sequence ✓

4. **Long sentences:**
   - Input with multiple clauses
   - Should get complete normalized text, not just last clause ✓

5. **Contractions:**
   - "don't" → "do not"
   - Should highlight entire contraction word, using combined phoneme groups ✓

6. **Abbreviations:**
   - "Dr. Smith" → "doctor smith"
   - Should highlight "Dr." when speaking "doctor" ✓

### Debug Logging

Key log points for troubleshooting:

1. **piper-phonemize (stderr):**
   ```
   [PIPER-PHONEMIZE] WORD event: raw_position=X, adjusted_position=Y
   [PIPER-PHONEMIZE] Processing N words with positions
   [DEBUG] New normalized text is: '...'
   ```

2. **SherpaOnnx.swift:**
   ```
   [SherpaOnnx] Extracted N phonemes (durations: ✓/✗, total: X.XXs)
   [SherpaOnnx] Extracted normalized text: '...'
   [SherpaOnnx] First 3 char mappings: [(orig, norm), ...]
   ```

3. **PhonemeAlignmentService:**
   ```
   [PhonemeAlign] Original text: '...'
   [PhonemeAlign] Normalized text: '...'
   [PhonemeAlign] Simplified alignment: X display words, Y normalized words
   Word[0] 'TEXT' @ 0.000s for 0.XXXs
   ```

4. **PhonemeTimelineBuilder:**
   ```
   [PhonemeTimelineBuilder] Finding word boundaries...
   Word 'TEXT': start-end
   Created N word boundaries
   ```

### Common Issues & Solutions

**Problem:** Word not highlighting at all
**Check:** Does the word have phonemes? Look for "No phonemes for normalized word" in logs
**Solution:** Check phoneme grouping logic, ensure textRange overlaps with normalized word position

**Problem:** Wrong word highlighted
**Check:** Character mapping - is normalized position mapping to correct original position?
**Solution:** Verify charMapping is correct, check offset calculations

**Problem:** Timing is off (highlighting too early/late)
**Check:** Phoneme durations - are they present? Are they reasonable values?
**Solution:** Verify w_ceil tensor extraction, check duration calculations

**Problem:** First/last word skipped
**Check:** Offset calculations - are positions 0-based after conversion?
**Solution:** Verify -1 offset for WORD events, -2 for character mapping

---

## File Reference

### Core Files
- `Listen2/Services/TTS/SherpaOnnx.swift` - C API wrapper
- `Listen2/Services/TTS/PhonemeAlignmentService.swift` - Word alignment logic
- `Listen2/Services/TTS/PhonemeTimelineBuilder.swift` - Timeline construction
- `Listen2/Services/Reading/WordHighlighter.swift` - Real-time highlighting
- `piper-phonemize/src/phonemize.cpp` - Text normalization & position tracking
- `sherpa-onnx/csrc/offline-tts-vits-impl.h` - TTS implementation
- `sherpa-onnx/csrc/piper-phonemize-lexicon.cc` - Phoneme extraction

### Documentation
- `docs/WORD_HIGHLIGHTING_ARCHITECTURE.md` - This file
- `docs/handoff-normalized-text-truncation-bug.md` - Truncation bug analysis
- `docs/plan-for-word-highlighting-fix-simplification.md` - Original plan
- `docs/FRAMEWORK_UPDATE_GUIDE.md` - Framework rebuild instructions

---

## Glossary

**Phoneme:** Smallest unit of sound in speech (e.g., /t/, /ʃ/, /æ/)
**IPA:** International Phonetic Alphabet - standard notation for phonemes
**espeak-ng:** Open-source speech synthesis engine providing text-to-phoneme conversion
**ONNX:** Open Neural Network Exchange - model format for TTS inference
**w_ceil:** Duration prediction tensor from TTS model (predicts phoneme durations)
**Normalization:** Converting text to standard form (Dr. → doctor, don't → do not)
**Character mapping:** Mapping between original text positions and normalized text positions
**Lookahead synthesis:** Pre-generating future sentences for smooth playback
**LRU cache:** Least Recently Used cache with automatic eviction of old entries

---

**Version:** 2024-11-16
**Last Updated:** After fixing all three position offset bugs
**Status:** All known bugs fixed, system working as designed
