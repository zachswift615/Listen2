# Word-Level Alignment Manual Testing Checklist

**Feature:** Word-Level Alignment with ASR
**Implementation Plan:** docs/plans/2025-11-09-word-alignment-implementation-plan.md
**Date:** 2025-11-10
**Platform:** iOS 18.2+

## Overview

This checklist covers manual testing of the word-level alignment feature that uses sherpa-onnx ASR to provide accurate word-by-word highlighting during Piper TTS playback.

**Testing Environment:**
- Simulator: iPhone 16 Pro (iOS 18.2)
- Physical Device: (if available)

**Pre-requisites:**
- App built successfully
- ASR model files bundled (whisper-tiny INT8)
- Sample content available in bundle
- Piper TTS voice model installed

---

## 1. Word Highlighting Accuracy

### 1.1 Basic Word Highlighting Sync

**Test ID:** ALIGN-001
**Priority:** Critical
**Reference:** Plan Section 8.3

**Steps:**
1. Open a document with sample content
2. Start playback on a paragraph
3. Watch word-by-word highlighting as audio plays
4. Observe synchronization between audio and highlighting

**Expected Results:**
- [ ] Each word highlights individually as it is spoken
- [ ] Highlight appears at the exact moment the word is spoken (±50ms tolerance)
- [ ] Highlight transitions smoothly between words
- [ ] No words are skipped in highlighting
- [ ] Highlighting color is distinct and visible
- [ ] Word highlighting syncs accurately with audio

**Notes:**
_____________________________________________

---

### 1.2 Long Paragraph Drift Test

**Test ID:** ALIGN-002
**Priority:** Critical
**Reference:** Plan Section 8.3 - "No visible drift over long paragraphs"

**Steps:**
1. Find a long paragraph (>200 words or >2 minutes audio)
2. Start playback from the beginning
3. Watch highlighting throughout entire paragraph
4. Pay attention to sync at the end of paragraph

**Expected Results:**
- [ ] Highlighting remains synchronized throughout
- [ ] No visible drift accumulates over time
- [ ] Last word highlights correctly when spoken
- [ ] Drift < 100ms even at end of 5-minute paragraph
- [ ] No "catch-up" jumps in highlighting

**Notes:**
_____________________________________________

---

### 1.3 Highlighting with Different Voices

**Test ID:** ALIGN-003
**Priority:** High
**Reference:** Plan Section 8.3 - "Works with different voices"

**Steps:**
1. Open Quick Settings and note current voice
2. Play a paragraph and observe highlighting
3. Change to a different voice (if available)
4. Play the same paragraph again
5. Observe highlighting accuracy

**Expected Results:**
- [ ] Highlighting works with bundled voice (Lessac)
- [ ] Changing voice triggers re-alignment
- [ ] New voice has accurate highlighting
- [ ] Different voices may have different timing but all sync correctly
- [ ] Voice change doesn't break highlighting

**Notes:**
_____________________________________________

---

## 2. Special Text Handling

### 2.1 Contractions

**Test ID:** ALIGN-004
**Priority:** High
**Reference:** Plan Section 8.3 - "Handles contractions correctly"

**Steps:**
1. Find text with contractions (e.g., "don't", "I'll", "we're", "it's")
2. Start playback
3. Watch how contractions are highlighted

**Expected Results:**
- [ ] Contractions highlight as single words (not split)
- [ ] "don't" highlights as one unit, not "don" and "t" separately
- [ ] "I'll" highlights as one unit
- [ ] Timing is accurate for contractions
- [ ] No visual glitches when highlighting contractions

**Test Cases:**
- "don't" - _____ (pass/fail)
- "I'll" - _____ (pass/fail)
- "we're" - _____ (pass/fail)
- "it's" - _____ (pass/fail)
- "won't" - _____ (pass/fail)

**Notes:**
_____________________________________________

---

### 2.2 Punctuation

**Test ID:** ALIGN-005
**Priority:** High
**Reference:** Plan Section 8.3 - "Handles punctuation correctly"

**Steps:**
1. Find text with heavy punctuation (commas, periods, quotes, etc.)
2. Start playback
3. Observe how words with punctuation are highlighted

**Expected Results:**
- [ ] Words with trailing punctuation highlight correctly ("Hello," highlights entire unit)
- [ ] Quotation marks don't break highlighting
- [ ] Em dashes and hyphens handled correctly
- [ ] Ellipsis (...) doesn't cause issues
- [ ] Punctuation doesn't create timing gaps

**Test Cases:**
- "Hello," - _____ (pass/fail)
- "world!" - _____ (pass/fail)
- "wait..." - _____ (pass/fail)
- Hyphenated words - _____ (pass/fail)
- "Quoted text" - _____ (pass/fail)

**Notes:**
_____________________________________________

---

## 3. Performance

### 3.1 Alignment Time

**Test ID:** ALIGN-006
**Priority:** High
**Reference:** Plan Section 8.3 - "Performance acceptable (<2s alignment time)"

**Steps:**
1. Select a paragraph that hasn't been played before (cache miss)
2. Start playback and observe loading behavior
3. Measure time from play button tap to audio starting

**Expected Results:**
- [ ] First playback has slight delay for alignment
- [ ] Alignment completes in < 2 seconds
- [ ] Loading indicator appears during alignment (if implemented)
- [ ] Audio starts automatically after alignment
- [ ] No app freeze or UI blocking during alignment

**Measurements:**
- Short paragraph (~50 words): _________ seconds
- Medium paragraph (~100 words): _________ seconds
- Long paragraph (~200 words): _________ seconds

**Notes:**
_____________________________________________

---

### 3.2 Cache Hit Performance

**Test ID:** ALIGN-007
**Priority:** Medium
**Reference:** Plan Section 4.2 - Caching Strategy

**Steps:**
1. Play a paragraph for the first time (forces alignment)
2. Let it play to completion
3. Skip back to the same paragraph
4. Measure time to start playback

**Expected Results:**
- [ ] Second playback starts immediately (< 100ms)
- [ ] No re-alignment needed
- [ ] Cache is used transparently
- [ ] Highlighting still accurate on cached playback

**Measurements:**
- First playback delay: _________ seconds
- Cached playback delay: _________ milliseconds

**Notes:**
_____________________________________________

---

## 4. Cache Persistence

### 4.1 Cache Survives App Restart

**Test ID:** ALIGN-008
**Priority:** High
**Reference:** Plan Section 8.3 - "Cache survives app restart"

**Steps:**
1. Play several paragraphs (to populate cache)
2. Note which paragraphs were played
3. Force quit the app completely
4. Relaunch the app
5. Open the same document
6. Play the previously-played paragraphs

**Expected Results:**
- [ ] App relaunches successfully
- [ ] Document opens to last read position
- [ ] Previously-aligned paragraphs use cached alignment
- [ ] No re-alignment needed for cached paragraphs
- [ ] Highlighting remains accurate after restart
- [ ] Cache persists across app sessions

**Notes:**
_____________________________________________

---

### 4.2 Cache Invalidation on Voice Change

**Test ID:** ALIGN-009
**Priority:** Medium
**Reference:** Plan Section 4.2 - "Voice change: Re-align"

**Steps:**
1. Play a paragraph with Voice A
2. Change to Voice B in settings
3. Play the same paragraph again
4. Observe alignment behavior

**Expected Results:**
- [ ] Voice change triggers re-alignment
- [ ] New alignment created for Voice B
- [ ] Old cache for Voice A discarded/invalidated
- [ ] Highlighting accurate with new voice
- [ ] Performance acceptable for re-alignment

**Notes:**
_____________________________________________

---

## 5. Edge Cases

### 5.1 Very Short Text

**Test ID:** ALIGN-010
**Priority:** Low

**Steps:**
1. Find a very short paragraph (1-3 words)
2. Start playback
3. Observe highlighting

**Expected Results:**
- [ ] Short text aligns correctly
- [ ] No crashes or errors
- [ ] Highlighting works even for 1-2 words
- [ ] Performance acceptable

**Notes:**
_____________________________________________

---

### 5.2 Very Long Paragraph

**Test ID:** ALIGN-011
**Priority:** Medium

**Steps:**
1. Find a very long paragraph (>300 words)
2. Start playback
3. Monitor alignment time and highlighting

**Expected Results:**
- [ ] Long paragraph aligns successfully
- [ ] Alignment completes in < 2 seconds (even for long text)
- [ ] No memory warnings
- [ ] Highlighting remains accurate throughout
- [ ] No performance degradation

**Notes:**
_____________________________________________

---

### 5.3 Numbers and Symbols

**Test ID:** ALIGN-012
**Priority:** Low

**Steps:**
1. Find text with numbers ("2024", "1st", etc.)
2. Find text with symbols (@, #, $, etc.)
3. Play and observe highlighting

**Expected Results:**
- [ ] Numbers highlight correctly
- [ ] Ordinals (1st, 2nd) highlight correctly
- [ ] Symbols are handled gracefully
- [ ] No crashes with special characters
- [ ] Timing remains accurate

**Notes:**
_____________________________________________

---

### 5.4 Multi-Byte Characters

**Test ID:** ALIGN-013
**Priority:** Low

**Steps:**
1. Find text with emoji or special Unicode characters
2. Play and observe highlighting

**Expected Results:**
- [ ] Multi-byte characters don't break alignment
- [ ] String ranges calculated correctly
- [ ] No crashes with Unicode
- [ ] Highlighting still accurate

**Notes:**
_____________________________________________

---

### 5.5 Background Playback

**Test ID:** ALIGN-014
**Priority:** Medium

**Steps:**
1. Start playback with highlighting visible
2. Background the app (home button or swipe up)
3. Let audio continue for 30+ seconds
4. Return to foreground
5. Observe highlighting

**Expected Results:**
- [ ] Highlighting updates correctly after returning
- [ ] Current word highlighted matches audio position
- [ ] No desync when backgrounding/foregrounding
- [ ] Smooth transition back to active highlighting

**Notes:**
_____________________________________________

---

## 6. Regression Testing

### 6.1 Paragraph-Level Highlighting Still Works

**Test ID:** ALIGN-015
**Priority:** High

**Steps:**
1. Start playback
2. Verify paragraph-level highlighting (background color)
3. Verify word-level highlighting (overlay)

**Expected Results:**
- [ ] Current paragraph has background highlight
- [ ] Current word has additional highlight
- [ ] Both highlighting styles visible simultaneously
- [ ] Paragraph highlighting updates when moving to next paragraph
- [ ] No visual conflicts between paragraph and word highlighting

**Notes:**
_____________________________________________

---

### 6.2 Skip Forward/Backward

**Test ID:** ALIGN-016
**Priority:** High

**Steps:**
1. Start playback in middle of document
2. Skip forward several paragraphs
3. Skip backward several paragraphs
4. Observe highlighting behavior

**Expected Results:**
- [ ] Skipping updates highlighting immediately
- [ ] Word highlighting works on skipped-to paragraph
- [ ] Cache used if paragraph was previously aligned
- [ ] New alignment triggered if needed
- [ ] No crashes or delays

**Notes:**
_____________________________________________

---

## 7. User Experience

### 7.1 Visual Quality

**Test ID:** UX-001
**Priority:** Medium

**Steps:**
1. Play various paragraphs
2. Evaluate visual highlighting quality

**Expected Results:**
- [ ] Highlighting is smooth and natural
- [ ] No flickering or jumping
- [ ] Highlight color is readable over text
- [ ] Transitions between words are fluid
- [ ] Overall experience feels polished

**Notes:**
_____________________________________________

---

### 7.2 Playback Controls Integration

**Test ID:** UX-002
**Priority:** Medium

**Steps:**
1. Test pause/play during word highlighting
2. Test speed changes (0.5x, 1.0x, 2.0x)
3. Test seeking with progress slider (if available)

**Expected Results:**
- [ ] Pause stops highlighting immediately
- [ ] Resume continues highlighting from correct word
- [ ] Speed changes maintain accurate highlighting
- [ ] Seeking updates highlighting to correct position
- [ ] All controls work seamlessly with alignment

**Notes:**
_____________________________________________

---

## 8. Accessibility

### 8.1 VoiceOver Compatibility

**Test ID:** ACC-001
**Priority:** Low

**Steps:**
1. Enable VoiceOver
2. Navigate to document
3. Start playback
4. Verify accessibility

**Expected Results:**
- [ ] VoiceOver announces current word/paragraph
- [ ] Playback controls accessible
- [ ] No conflicts between TTS and VoiceOver
- [ ] User can navigate with VoiceOver while listening

**Notes:**
_____________________________________________

---

## 9. ASR Model Verification

### 9.1 Model Files Present

**Test ID:** MODEL-001
**Priority:** Critical

**Steps:**
1. Check app bundle for ASR model files
2. Verify file locations

**Expected Results:**
- [ ] tiny-encoder.int8.onnx exists (~12 MB)
- [ ] tiny-decoder.int8.onnx exists (~86 MB)
- [ ] tiny-tokens.txt exists (~800 KB)
- [ ] All files in ASRModels/whisper-tiny directory
- [ ] Total model size ~100 MB

**File Locations:**
- Encoder: _____________________________________________
- Decoder: _____________________________________________
- Tokens: _____________________________________________

**Notes:**
_____________________________________________

---

### 9.2 Model Initialization

**Test ID:** MODEL-002
**Priority:** Critical

**Steps:**
1. Launch app
2. Monitor console logs for ASR initialization
3. Play first paragraph

**Expected Results:**
- [ ] ASR model loads successfully on first use
- [ ] No errors in console
- [ ] Model initialization completes in < 1 second
- [ ] Subsequent alignments don't re-initialize model

**Notes:**
_____________________________________________

---

## 10. Performance Benchmarks

### 10.1 Alignment Performance Targets

**Reference:** Plan Section 7.3, 8.2

**Targets from Implementation Plan:**
- Alignment time: < 2 seconds per paragraph ✓
- Cache hit rate: > 95% on re-reads ✓
- Word highlighting drift: < 100ms over 5-minute paragraph ✓
- Cache load time: < 10ms ✓

**Actual Measurements:**

| Metric | Target | Actual | Pass/Fail |
|--------|--------|--------|-----------|
| Short paragraph alignment (50 words) | < 2s | _____ s | _____ |
| Medium paragraph alignment (100 words) | < 2s | _____ s | _____ |
| Long paragraph alignment (200 words) | < 2s | _____ s | _____ |
| Cache hit time | < 10ms | _____ ms | _____ |
| Highlighting drift (5 min) | < 100ms | _____ ms | _____ |
| Cache hit rate | > 95% | _____ % | _____ |

**Notes:**
_____________________________________________

---

## Summary

### Test Results

**Total Tests:** 24
**Passed:** _______
**Failed:** _______
**Blocked:** _______
**Not Tested:** _______

### Critical Issues Found

1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

### High Priority Issues Found

1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

### Performance Issues

1. _____________________________________________
2. _____________________________________________

### Alignment Accuracy Issues

1. _____________________________________________
2. _____________________________________________

### Recommendations

_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________

### Success Criteria (from Plan Section 432-436)

- [ ] Word highlighting drift < 100ms over 5-minute paragraph
- [ ] Alignment time < 2 seconds per paragraph
- [ ] Cache hit rate > 95% on re-reads
- [ ] User satisfaction: "Highlighting feels natural"

### Sign-off

**Tester Name:** _________________________
**Date:** _________________________
**Platform Tested:** _________________________
**Build Version:** _________________________
**Ready for Release:** [ ] Yes [ ] No [ ] With Caveats

**Notes:**
_____________________________________________
_____________________________________________
_____________________________________________
