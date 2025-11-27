# Word-Level Highlighting Implementation Handoff
**Date:** November 15, 2024
**Session Summary:** Implemented phoneme-aware word highlighting for Piper TTS with rolling cache architecture

## 🎯 Session Objectives & Accomplishments

### What We Built
1. **Phoneme-aware streaming architecture** - Bundles phoneme timing with audio chunks
2. **PhonemeTimeline system** - Self-contained timing per sentence (no global sync issues)
3. **Character mapping pipeline** - Maps phonemes → normalized text → original text → VoxPDF words
4. **WordHighlighter with CADisplayLink** - 60 FPS highlighting with binary search
5. **Comprehensive logging** - Full visibility into the pipeline

### Key Files Created/Modified
- `PhonemeTimeline.swift` - Core data structures
- `PhonemeTimelineBuilder.swift` - Builds timelines from synthesis results
- `WordHighlighter.swift` - Manages highlighting state
- `SynthesisQueue.swift` - Modified to stream sentence bundles
- `TTSService.swift` - Integrated highlighting with playback

## 🔴 Critical Issues Found

### 1. **Word Detection is Completely Broken**
The character mapping from espeak-ng is producing incorrect word boundaries:
- "CHAPTER 2" → "APTER 2" (missing first 2 chars)
- "Designing Agent Systems" → "signing A" / "ent S" / "stems"
- "Most practitioners" → "st p" / "actitioners"

**Root Cause:** The character position mappings are starting at position 2 instead of 0, and are sparse/incomplete.

### 2. **Normalized Text Mismatch**
Multiple logs show mismatched text:
```
[PhonemeAlign] Original text: 'Building'
[PhonemeAlign] Normalized text: 'chapter 2 '
```
This suggests the alignment service is getting confused about which text to process.

### 3. **Character Mapping is Sparse**
For "CHAPTER 2" (9 chars), we only get 4 mappings:
```
[0]: orig_pos=2, norm_pos=0  # Missing CH at start
[1]: orig_pos=9, norm_pos=7
[2]: orig_pos=10, norm_pos=8
```

## ✅ What's Working

1. **Phoneme durations ARE available** (w_ceil models working)
   - `durations=✓` in logs
   - Proper timing values (e.g., 0.476s for "chapter 2")

2. **Pipeline is connected end-to-end**
   - Synthesis → Timeline building → Highlighting
   - All components are communicating

3. **Highlighting is visible** (though on wrong words)

## 🔍 Key Discoveries from Logs

### Good News - W_ceil Models Working:
```
[SherpaOnnx] C API returned: num_phonemes=12, symbols=✓, durations=✓, char_start=✓, char_length=✓
[SherpaOnnx] Extracted 12 phonemes (durations: ✓, total: 0.476s)
```

### Bad News - Word Boundaries Wrong:
```
Found 2 words in normalized text
Word 0: 'APTER 2' at 0.0s-0.29s (chars 2-9)  # Should be "CHAPTER"
```

### Character Mapping Issues:
```
[SherpaOnnx] Extracting 4 character mapping entries  # Should be 9 for "CHAPTER 2"
orig_pos=2, norm_pos=0  # Starts at position 2, not 0!
```

## 🎯 Next Steps for Investigation

### 1. **Fix Character Position Mapping**
The core issue is that espeak-ng's character positions are wrong. Need to investigate:
- Why positions start at 2 instead of 0
- Why mapping is sparse (only 4 entries for 9 chars)
- Whether this is a sherpa-onnx C API issue or espeak-ng issue

### 2. **Debug Text Alignment**
- Why is PhonemeAlign showing mismatched texts?
- The alignment service seems to be processing wrong text pairs

### 3. **Test with Simpler Text**
Try single words without capitalization:
- "hello"
- "world"
- "test"

This will help isolate if it's a case sensitivity or multi-word issue.

## 🔧 Debugging Commands to Run

### Check Phoneme Positions in C++
In sherpa-onnx C++ code, add logging to see raw espeak data:
```cpp
// In tts synthesis
printf("Phoneme %d: symbol=%s, start=%d, length=%d\n",
       i, phonemes[i].symbol, phonemes[i].char_start, phonemes[i].char_length);
```

### Test Character Mapping Directly
Create a test that synthesizes "CHAPTER" and logs every mapping:
```swift
let test = "CHAPTER"
let result = synthesize(test)
for (i, mapping) in result.charMapping.enumerated() {
    print("[\(i)] orig=\(mapping.originalPos) norm=\(mapping.normalizedPos)")
}
```

## 📊 Pattern Analysis from Logs

### Character Position Pattern
All word boundaries have wrong starting positions:
- "CHAPTER 2" starts at position 2 (missing "CH")
- "Designing" starts at position 2 (missing "De")
- "Most" starts at position 2 (missing "Mo")

**This suggests a systematic off-by-2 error in the character position calculation.**

### Sparse Mapping Pattern
Character mappings only include certain positions:
- 4 mappings for 9-char "CHAPTER 2"
- 6 mappings for longer texts
- Never complete coverage

**This suggests espeak only maps certain "anchor" characters, not every position.**

## 💡 Hypotheses to Test

### Hypothesis 1: Uppercase Handling
The system might struggle with uppercase text. Test with:
- All lowercase: "chapter 2"
- Mixed case: "Chapter 2"
- All uppercase: "CHAPTER 2"

### Hypothesis 2: Punctuation/Whitespace
Spaces and punctuation might throw off position counting. Test with:
- No spaces: "chapter2"
- No punctuation: "chapter 2" vs "chapter 2."

### Hypothesis 3: Text Preprocessing
Something might be modifying the text before espeak sees it. Check:
- What exact text is sent to espeak-ng
- Whether preprocessing strips/adds characters

## 🚀 Recommended Fix Approach

### Short-term Workaround
1. **Offset correction**: Add 2 to all character positions (compensate for off-by-2)
2. **Word matching fallback**: Match words by content, not position
3. **Simple word division**: Divide phonemes evenly among detected words

### Long-term Solution
1. **Fix espeak-ng integration**: Debug why positions are wrong
2. **Complete mapping**: Ensure every character has a mapping
3. **Test suite**: Create comprehensive tests for various text types

## 📋 Testing Checklist

When testing the fix:
- [ ] Single lowercase word: "hello"
- [ ] Multiple lowercase words: "hello world"
- [ ] Uppercase word: "HELLO"
- [ ] Mixed case: "Hello World"
- [ ] Numbers: "123"
- [ ] Punctuation: "Hello, world!"
- [ ] Contractions: "don't"
- [ ] Abbreviations: "Dr. Smith"

## 🔗 Related Context

### Workshop Gotchas Recorded
1. "Phoneme text positions from espeak are in normalized text, not original"
2. "Piper models must have w_ceil tensors exposed for phoneme durations"
3. "Character mapping between normalized and original is unreliable"

### Key Design Decisions
- Use phoneme-aware streaming (bundles timing with audio)
- Self-contained timing per sentence
- Binary search for word lookup efficiency

## 📝 Summary for Next Session

**The Good:** We have a complete pipeline with proper phoneme durations from w_ceil models.

**The Bad:** Word boundaries are completely wrong due to incorrect character position mappings.

**The Fix:** Debug why espeak-ng character positions start at offset 2 and are sparse. This is likely a bug in either:
1. How sherpa-onnx extracts positions from espeak
2. How espeak calculates positions
3. Some preprocessing that modifies the text

**Priority:** Fix the character position mapping - everything else is working!