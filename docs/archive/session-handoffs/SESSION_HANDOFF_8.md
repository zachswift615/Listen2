# Session 8 Handoff - Word Highlighting Architecture Simplification

**Date:** November 13, 2025
**Status:** Word highlighting partially working but glitchy/incorrect
**Latest logs:** `~/listen-2-logs-2025-11-13.txt`

---

## 🎯 Session Goal

Fix word-level highlighting by simplifying architecture away from VoxPDF position mapping to direct espeak-based alignment.

---

## ✅ What We Discovered

### Root Cause Analysis (Systematic Debugging)

**Initial Evidence:**
- EPUB had NO highlighting - logs showed `[SynthesisQueue] No word map available for alignment`
- PDF had JERKY highlighting - jumped randomly between words
- Phoneme data flowing correctly from espeak/piper (332 phonemes captured with positions)

**Root Causes Identified:**

1. **Missing wordMap Guard** - `SynthesisQueue.swift:201` had `guard let wordMap = wordMap else { return }` that blocked ALL alignment for non-PDFs

2. **Position Mismatch Problem** - VoxPDF extracts words from original PDF text, but espeak synthesizes **normalized** text:
   - PDF: "Dr. Smith's couldn't"
   - espeak: "Doctor Smith s could not"
   - VoxPDF positions [0, 4, 12, 20] don't map to normalized text → crashes/gibberish

3. **Missing Phoneme Durations** - `durations=✗` in logs - `w_ceil` tensor not flowing through sherpa-onnx C API

---

## 🔄 Architecture Evolution

### Approach 1: VoxPDF + espeak Position Mapping (FAILED)
**Idea:** Map espeak phoneme positions to VoxPDF word positions using overlap detection
**Problem:** Position mismatch between normalized and original text → gibberish words ("lice'" instead of "Alice")

### Approach 2: Pure espeak Word Extraction (FAILED)
**Idea:** Extract word text directly from espeak character positions
**Problem:** Same normalization issue - espeak positions don't match synthesized text positions

### Approach 3: Hybrid - VoxPDF Words + espeak Timing (FAILED)
**Idea:** Use VoxPDF for word text/ranges, espeak phoneme counts for timing
**Problem:** String index out of bounds crash - 156 VoxPDF words vs 225 espeak groups, positions incompatible

### Approach 4: Text Splitting + espeak Timing (CURRENT - GLITCHY)
**Idea:**
- Split synthesized text by whitespace → words to highlight
- Group espeak phonemes by `textRange` → phoneme counts
- Match sequentially, assign proportional timing

**Status:** No crashes, but phoneme mappings are wrong

**Example of current bug:**
```
Word[0] 'This' = [ð ɪ s] @ 0.000s for 0.150s  ← Correct
Word[1] 'is' = [  ɪ] @ 0.150s for 0.100s      ← WRONG - only 1 phoneme
Word[2] 'a' = [z] @ 0.250s for 0.050s         ← WRONG - 'z' is from 'is'
Word[3] 'sample' = [  ɐ   s ˈ] @ 0.300s       ← WRONG - incomplete
Word[4] 'PDF' = [æ m p ə l   p] @ 0.550s      ← WRONG - has rest of 'sample'
```

**Word counts mismatch:**
- Text splitting: 28 words
- espeak phoneme groups: 39 groups

**Root issue:** espeak's `textRange` groupings (based on normalized positions) don't align with whitespace-split words.

---

## 📊 Current State

### What's Working
✅ No crashes (fixed string index out of bounds)
✅ Phoneme data flows through (positions, symbols)
✅ Alignment runs for all document types
✅ Word text is correct (from text splitting)

### What's NOT Working
❌ Phoneme-to-word mapping is incorrect
❌ Timing is wrong (based on wrong phoneme groups)
❌ Word count mismatches (espeak groups ≠ text words)
❌ No per-phoneme durations (using 50ms estimate)

---

## 🔍 Key Data from Latest Logs

### Alignment Output
```
[PhonemeAlign] Text splitting: 28 words from synthesized text
[PhonemeAlign] Espeak grouped: 39 phoneme groups
⚠️  [PhonemeAlign] Word count mismatch: 28 text words vs 39 phoneme groups
[PhonemeAlign] ✅ Aligned 28 words, total duration: 5.80s
```

### Phoneme Data
```
[SherpaOnnx] C API returned: num_phonemes=206, symbols=✓, durations=✗, char_start=✓, char_length=✓
[SHERPA_C_API] GeneratedAudio: samples=206, phoneme_durations=0, phonemes=206
```

**Key observation:** `phoneme_durations=0` - durations array is not populated

---

## 🤔 Open Questions for Opus

1. **Is sequential matching the right approach?**
   - We assume espeak processes linearly: word1 → word2 → word3
   - But espeak may group phonemes differently (punctuation, contractions)

2. **Should we ignore espeak's textRange groupings entirely?**
   - Current approach: Group phonemes by `textRange` (espeak's word grouping)
   - Alternative: Distribute phonemes evenly across whitespace-split words?

3. **Is the word count mismatch acceptable?**
   - 28 text words vs 39 phoneme groups suggests espeak is splitting differently
   - Punctuation, spaces, contractions may cause different grouping

4. **Do we need per-phoneme durations?**
   - Currently using proportional estimate (total_duration / phoneme_count)
   - Would actual `w_ceil` data from Piper improve accuracy significantly?

5. **Could we use a simple time-based approach instead?**
   - Distribute `total_audio_duration` evenly across whitespace-split words
   - Completely ignore espeak phoneme groupings
   - Just use: `word_duration = total_duration / word_count`

---

## 📁 Key Files Modified This Session

### PhonemeAlignmentService.swift
**Location:** `Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`

**Changes:**
- Made `wordMap` parameter optional (line 33)
- Removed VoxPDF alignment path entirely
- Simplified to single `alignWithEspeakWords()` method
- Added `extractWordsFromText()` - whitespace splitting
- Added `groupPhonemesByWord()` - group by `textRange`
- Uses proportional timing: `(total_duration / phonemes) * phonemes_in_word`

**Current algorithm:**
```swift
1. Split synthesized text by whitespace → [(text: String, range: Range<String.Index>)]
2. Group phonemes by consecutive identical textRange → [[PhonemeInfo]]
3. Match sequentially: words[i] ← phonemeGroups[i]
4. Calculate duration proportionally
```

### SynthesisQueue.swift
**Location:** `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Changes:**
- Removed `guard let wordMap = wordMap else { return }` (line 201)
- Now always calls alignment service
- Passes `wordMap` optionally (nil for EPUB/clipboard)

---

## 🎓 Key Learnings

### 1. espeak Text Normalization
- espeak normalizes text before synthesis: "Dr." → "Doctor", "couldn't" → "could not"
- Character positions espeak provides are for this **normalized text**
- Any external word positions (PDF, EPUB) are for **original text**
- **This mismatch is the root cause of all position-based bugs**

### 2. espeak Phoneme Grouping
- espeak groups phonemes by word via `textRange` (all phonemes in a word have same range)
- These groupings are based on espeak's internal text processing
- May not match whitespace-based word splitting
- Example: "PDF" might be grouped differently than text splitting sees it

### 3. Phoneme Durations
- Piper model outputs `w_ceil` tensor with phoneme durations (sample counts)
- sherpa-onnx is NOT populating `phoneme_durations` in the C API
- Currently using rough estimate: 50ms per phoneme
- Logs show: `phoneme_durations=0` consistently

### 4. Architecture Trade-offs
| Approach | Pro | Con |
|----------|-----|-----|
| VoxPDF positions | Precise PDF word boundaries | Doesn't work - text normalization mismatch |
| espeak positions | Matches synthesized text | Groupings don't match whitespace words |
| Text splitting | Simple, universal | Mismatches espeak phoneme groups |
| Even distribution | No dependencies | Loses phoneme timing information |

---

## 🚀 Possible Next Steps

### Option A: Fix espeak Phoneme Mapping
- Debug why espeak groups don't match text words
- Add smarter matching (fuzzy alignment, DTW between groups and words)
- Handle punctuation, contractions specially

### Option B: Abandon espeak Groupings
- Distribute phonemes evenly across text words
- Use total phoneme count: `phonemes_per_word = total_phonemes / word_count`
- Assign timing: `word_duration = (total_duration / total_phonemes) * phonemes_for_word`

### Option C: Simple Even Distribution
- Ignore phoneme data entirely for timing
- Split text by whitespace
- Assign even duration: `word_duration = total_audio_duration / word_count`
- Simplest possible approach

### Option D: Get w_ceil Durations Working
- Fix sherpa-onnx C API to populate `phoneme_durations` from Piper's `w_ceil`
- Use actual per-phoneme durations
- May improve timing accuracy even with mapping issues

### Option E: Hybrid DTW Approach
- Keep text splitting for words
- Use DTW to align text words to espeak phoneme groups
- Handle mismatches gracefully
- More complex but more robust

---

## 📝 Workshop Decisions Recorded

1. **Replaced VoxPDF word mapping with direct espeak word alignment**
   - Reasoning: VoxPDF caused position mismatches between normalized and literal text

2. **Hybrid word alignment: Document words for WHAT, espeak counts for WHEN**
   - Reasoning: Separates concerns - what to highlight vs when to highlight

3. **Removed VoxPDF entirely - text splitting for all document types**
   - Reasoning: VoxPDF positions incompatible with espeak normalized text, causing crashes

---

## 💬 Context for Next Session

**User Feedback:** "That didn't work either. Different behavior but not better."

**Current behavior:** Highlighting happens but is glitchy/wrong. Word text is correct but phoneme mappings are incorrect, causing wrong timing.

**User is consulting Opus** to determine if we're on the right track architecturally.

**Critical question to answer:** What's the right way to map espeak phoneme data to highlightable words?

---

## 🔗 References

- Session 7 handoff: `docs/SESSION_HANDOFF_7.md`
- Workshop context: Run `workshop context`
- Latest logs: `~/listen-2-logs-2025-11-13.txt`
- Opus's suggestion: Use `audio_duration / total_phonemes * phonemes_in_word` for timing

---

Good luck! 🚀
