# Word Highlighting Documentation Index

**Date:** 2025-11-13  
**Status:** Analysis Complete - Ready for Debugging  
**Total Documentation:** 40+ KB across 3 files

---

## Quick Navigation

### For a Quick Understanding (5 minutes)
Start with: **`WORD_HIGHLIGHTING_QUICK_REF.md`** (4.6 KB)
- Overview of the problem
- 5-step data flow
- Where "No word map" error comes from
- Success vs failure states

### For Complete Architecture (30 minutes)
Read: **`WORD_HIGHLIGHTING_ARCHITECTURE.md`** (23 KB)
- Detailed data flow for highlighting
- All data structures explained
- Why corruption is catastrophic
- Diagnostic logging strategy

### For Code Implementation Details (15 minutes)
Consult: **`WORD_HIGHLIGHTING_CODE_LOCATIONS.md`** (10 KB)
- Exact file paths and line numbers
- Every component with code samples
- Critical failure points
- Code path visualization

---

## The 30-Second Summary

**The Problem:**
- Words highlight during playback (good!)
- But timing is wrong - all words show 0.000s duration (bad!)

**The Root Cause:**
- Phoneme position data is corrupted
- All positions are identical: `[3..<3]` instead of `[0..<1] [1..<2] [2..<3]`
- This causes word alignment to fail

**The Solution:**
- Run diagnostic logs to locate corruption point
- Fix in appropriate layer (C++ or Swift)
- Estimated: 1-3 hours

**Current Format:**
- Characters ranges: `Range<String.Index>`
- NOT word indices: `[0, 1, 2]`

---

## Detailed File Overview

### WORD_HIGHLIGHTING_QUICK_REF.md

**Best For:** 
- New engineers joining the project
- Quick understanding before diving into code
- Decision-making on next steps

**Contains:**
- 5-step data flow with issues at each step
- Format expectations (Range<String.Index>)
- Where "No word map" error comes from
- Critical files and current issues
- Diagnostic points to check
- Success vs failure metrics

**Key Sections:**
1. The Problem
2. Why It's Corrupted (ASCII flowchart)
3. Data Flow (5 Steps)
4. What Format Does It Expect?
5. Critical Files
6. Where the "No Word Map" Error Comes From
7. Diagnostic Points
8. Success Metrics

---

### WORD_HIGHLIGHTING_ARCHITECTURE.md

**Best For:**
- Complete understanding of the system
- Debugging specific components
- Implementing fixes
- Understanding design decisions

**Contains:**
- Executive summary with what works/what's broken
- Architecture overview with data flow diagram
- Detailed explanation of each data structure
- 5-step highlighting flow with code samples
- Word map architecture explanation
- Alignment logic deep dive
- How highlighting works during playback
- Diagnostic logging guidance
- Configuration and initialization details
- Success criteria

**Key Sections:**
1. Executive Summary
2. Architecture Overview
3. Highlighting Flow - Detailed (Steps 1-5)
4. The Word Map Architecture
5. Where the "No Word Map" Error Comes From
6. Format Expectations (with evidence)
7. The Alignment Logic
8. Highlighting During Playback
9. Critical Data Flow Issue
10. Diagnostic Logging Locations
11. Configuration & Initialization
12. Summary Table
13. What We Need to Fix

**Code Examples:**
- PhonemeInfo structure
- AlignmentResult structure
- ReadingProgress structure
- DocumentWordMap usage
- Alignment algorithm details

---

### WORD_HIGHLIGHTING_CODE_LOCATIONS.md

**Best For:**
- Finding exact code to modify
- Understanding component interactions
- Navigating the codebase
- Debugging at specific lines

**Contains:**
- 10 files with complete references
- Line numbers for every component
- Code samples for critical sections
- The highlighting flow as code path
- Critical points where highlighting can fail
- Diagnostic output locations with log prefixes
- Related files that aren't directly used

**Key Sections:**
1. Complete File Reference (10 files)
2. The Highlighting Flow - Code Path
3. Critical Points Where Highlighting Can Fail
4. Diagnostic Output Locations

**File References Include:**
1. ReaderView.swift - Word highlighting in UI
2. ReaderViewModel.swift - Subscribes to progress
3. TTSService.swift - Synthesis and timing
4. SynthesisQueue.swift - Manages alignment
5. PhonemeAlignmentService.swift - Maps phonemes to words
6. AlignmentResult.swift - Stores word timing data
7. ReadingProgress.swift - Current playback state
8. WordPosition.swift - Word position metadata
9. SherpaOnnx.swift - C API interface
10. PiperTTSProvider.swift - TTS synthesis

---

## Understanding the Problem Visually

### Data Corruption Flowchart

```
espeak-ng (12% coverage)
    ↓ Emits position events
piper-phonemize (fills gaps)
    ↓ Duplicates positions
Swift (reads corrupted data)
    ↓ All identical [3..<3]
PhonemeAlignmentService
    ↓ Finds no overlaps
Word timings (empty)
    ↓ No words to highlight
Highlighting (broken)
```

### 5-Step Highlighting Flow

```
Piper TTS
    ↓ phonemes with positions
PhonemeAlignmentService
    ↓ word timings with character ranges
TTSService.currentAlignment
    ↓ 60 FPS timer
TTSService.updateHighlightFromTime()
    ↓ wordRange update
TTSService.currentProgress
    ↓ Combine publisher
ReaderViewModel.currentWordRange
    ↓ AttributedString
ReaderView.paragraphView()
    ↓ Yellow highlight
✅ User sees highlighted word
```

---

## Key Takeaways

### What Format Does It Expect?

**Answer: Character ranges (Range<String.Index>)**

NOT: Word indices like [0, 1, 2]
BUT: Character position ranges like:
- `text.index(text.startIndex, offsetBy: 0)..<text.index(text.startIndex, offsetBy: 5)`

### Why Is It Broken?

All phoneme positions are identical: `[3..<3]` instead of sequential `[0..<1] [1..<2]`
→ Word alignment finds zero phonemes for each word
→ Word timings are empty (0.000s duration)
→ Highlighting timer can't find any words to highlight

### Where Does "No Word Map" Error Come From?

`Listen2/Services/TTS/SynthesisQueue.swift:202`

```swift
guard let wordMap = wordMap else {
    print("[SynthesisQueue] No word map available for alignment")
    return
}
```

This is NOT a bug - it's expected behavior when document doesn't have word positions extracted.

### What Needs to Be Fixed?

1. **Phoneme position corruption** (PRIMARY)
   - Investigate why all positions are identical
   - Check C API and Swift pointer reading
   - Fix gap-filling logic in piper-phonemize

2. **Phoneme duration data** (SECONDARY)
   - Currently always nil
   - Need to extract from Piper TTS or estimate

3. **espeak event sparsity** (ROOT CAUSE)
   - Only 12-75% of phonemes get position events
   - Investigate espeak configuration

---

## Diagnostic Workflow

### For Next Session:

1. **Run the app** with current code
2. **Capture logs** (look for [SHERPA_C_API] and [SherpaOnnx])
3. **Compare diagnostics:**
   - C API logs: Do they show sequential positions?
   - Swift logs: Same as C API?
   - Alignment logs: How many "no phonemes found"?
4. **Determine corruption location:**
   - C++ piper-phonemize?
   - Swift pointer reading?
   - Downstream alignment logic?
5. **Apply fix** in appropriate layer

### Log Search Commands:

```bash
# Find C API diagnostic output
grep "\[SHERPA_C_API\] First.*phonemes' position data" console.log -A 6

# Find Swift diagnostic output
grep "\[SherpaOnnx\] First.*phonemes' raw position data" console.log -A 6

# Compare side-by-side
diff <(grep "\[SHERPA_C_API\]" console.log) <(grep "\[SherpaOnnx\]" console.log)

# Count "no phonemes found" errors
grep -c "No phonemes found" console.log
```

---

## Files Changed in Recent Sessions

### Session 6 (2025-11-13)
- Added diagnostic logging at C API boundary
- Added diagnostic logging at Swift pointer reading
- Fixed phoneme events initialization in espeak-ng
- Made phoneme_durations optional in Swift

### Session 5
- Implemented comprehensive position tracking logging
- Created detailed session handoff documentation

### Session 4
- Framework deployment debugging

---

## Success Metrics

### When Highlighting Works Correctly:

1. Phoneme positions are sequential
   - C API logs: `[0..<1] [1..<2] [2..<3]`
   - Swift logs: Same values

2. Word timings are created
   - Each word has non-zero duration
   - No "no phonemes found" warnings

3. Highlighting is smooth
   - Words highlight in sequence
   - Timing roughly matches audio
   - No words get stuck (>2 second timeout)

4. Performance is acceptable
   - Highlight timer runs at 60 FPS
   - No UI stuttering
   - Memory usage stable

---

## Important Context

### Why This Matters

Word highlighting is the foundation for:
- Accurate playback progress tracking
- Efficient book position saving
- User experience (visual feedback during listening)
- Future features (bookmarks, annotation, search sync)

### Architecture Layers

1. **TTS Synthesis Layer** (Piper)
   - Generates phonemes with character positions
   - Currently broken: positions corrupted

2. **Alignment Layer** (PhonemeAlignmentService)
   - Maps phonemes to words
   - Currently broken: can't find overlaps

3. **UI Layer** (ReaderView)
   - Displays highlighted word
   - Works fine: receives valid ranges from alignment

---

## Document Maintenance

Last Updated: 2025-11-13
Status: Analysis Complete
Confidence Level: 95%
Ready for: Debugging phase

Questions? Refer to appropriate document:
- Quick question? → QUICK_REF.md
- Architecture question? → ARCHITECTURE.md
- Code location? → CODE_LOCATIONS.md

