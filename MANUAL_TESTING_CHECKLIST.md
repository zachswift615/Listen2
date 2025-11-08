# Manual Testing Checklist
**Feature:** Piper TTS Integration
**Date:** November 8, 2025
**Branch:** feature-piper-tts-integration
**Platform:** iOS 18.2+

## Overview

This checklist covers comprehensive manual testing of the Listen2 app with Piper TTS integration. Each test should be performed on both simulator and physical device where applicable.

**Testing Environment:**
- Simulator: iPhone 16 Pro (iOS 18.2)
- Physical Device: (if available)

**Pre-requisites:**
- App built successfully
- Sample content available in bundle
- Bundled Piper voice model installed

---

## 1. Library Management

### 1.1 Empty State Display

**Test ID:** LIB-001
**Priority:** High

**Steps:**
1. Install fresh app (no documents)
2. Launch app
3. Verify empty state UI

**Expected Results:**
- [ ] "No Documents" message displayed
- [ ] Book illustration icon visible
- [ ] "Try Sample Content" button prominently displayed
- [ ] "+ Add Document" button visible in navigation bar
- [ ] No crash or errors

**Notes:**
_____________________________________________

---

### 1.2 Sample Content Import

**Test ID:** LIB-002
**Priority:** High

**Steps:**
1. From empty state, tap "Try Sample Content"
2. Wait for import to complete
3. Verify documents appear in library

**Expected Results:**
- [ ] Loading indicator appears during import
- [ ] Two documents appear: "Welcome to Listen2" (PDF) and "Alice's Adventures in Wonderland" (EPUB)
- [ ] Each document shows title, type badge (PDF/EPUB), and page count
- [ ] Import completes in < 5 seconds
- [ ] No error messages
- [ ] Sample content button disappears or shows "Already Imported"

**Notes:**
_____________________________________________

---

### 1.3 Document Deletion

**Test ID:** LIB-003
**Priority:** High

**Steps:**
1. In library, swipe left on a document
2. Tap "Delete" button
3. Confirm deletion

**Expected Results:**
- [ ] Swipe reveals delete button
- [ ] Delete button has red background
- [ ] Document removed from library immediately
- [ ] Smooth animation
- [ ] Document file deleted from disk
- [ ] If last document, empty state reappears

**Notes:**
_____________________________________________

---

### 1.4 PDF Import from Files App

**Test ID:** LIB-004
**Priority:** High

**Steps:**
1. Tap "+ Add Document" in navigation bar
2. Select "Files" from document picker
3. Navigate to a PDF file
4. Select the PDF

**Expected Results:**
- [ ] Document picker opens
- [ ] PDF is imported successfully
- [ ] Document appears in library with correct title
- [ ] Text is extracted and accessible
- [ ] Page count is accurate
- [ ] Import notification shows success

**Notes:**
_____________________________________________

---

### 1.5 EPUB Import from Files App

**Test ID:** LIB-005
**Priority:** High

**Steps:**
1. Tap "+ Add Document" in navigation bar
2. Select "Files" from document picker
3. Navigate to an EPUB file
4. Select the EPUB

**Expected Results:**
- [ ] Document picker opens
- [ ] EPUB is imported successfully
- [ ] Document appears in library with correct title
- [ ] Text is extracted and accessible
- [ ] Chapter information extracted
- [ ] Import notification shows success

**Notes:**
_____________________________________________

---

## 2. Reader View

### 2.1 Document Opening

**Test ID:** READ-001
**Priority:** High

**Steps:**
1. Tap on a document in library
2. Wait for reader view to open

**Expected Results:**
- [ ] Reader view opens smoothly (< 1 second)
- [ ] Document title in navigation bar
- [ ] Text content displayed and readable
- [ ] Current paragraph highlighted
- [ ] Playback controls visible at bottom
- [ ] "Table of Contents" button visible (top right)
- [ ] Settings button visible (top right)

**Notes:**
_____________________________________________

---

### 2.2 Text Display

**Test ID:** READ-002
**Priority:** High

**Steps:**
1. Open a document
2. Scroll through content
3. Check text formatting

**Expected Results:**
- [ ] Text is clear and readable
- [ ] Proper paragraph breaks
- [ ] No encoding issues (special characters render correctly)
- [ ] No overlapping text
- [ ] Hyphenation handled correctly
- [ ] Smooth scrolling performance

**Notes:**
_____________________________________________

---

### 2.3 TOC Navigation

**Test ID:** READ-003
**Priority:** Medium

**Steps:**
1. Open a document with chapters
2. Tap "Table of Contents" button
3. Select a chapter from TOC
4. Verify navigation

**Expected Results:**
- [ ] TOC sheet slides up from bottom
- [ ] All chapters listed
- [ ] Chapter titles readable
- [ ] Tapping chapter jumps to that section
- [ ] Sheet dismisses after selection
- [ ] Correct paragraph highlighted after jump
- [ ] Playback position updates

**Notes:**
_____________________________________________

---

### 2.4 Paragraph Highlighting

**Test ID:** READ-004
**Priority:** High

**Steps:**
1. Open a document
2. Start playback
3. Observe paragraph highlighting

**Expected Results:**
- [ ] Current paragraph highlighted with distinct color
- [ ] Highlight color is semi-transparent blue/gray
- [ ] Highlight updates as playback progresses
- [ ] Smooth transition between paragraphs
- [ ] Highlighted paragraph scrolls into view automatically
- [ ] Highlight removed when playback stops

**Notes:**
_____________________________________________

---

## 3. TTS Playback

### 3.1 Play/Pause Functionality

**Test ID:** TTS-001
**Priority:** Critical

**Steps:**
1. Open a document
2. Tap play button
3. Listen to audio
4. Tap pause button
5. Tap play again

**Expected Results:**
- [ ] Play button changes to pause icon
- [ ] Audio starts immediately (< 500ms latency)
- [ ] Text-to-speech is clear and understandable
- [ ] Paragraph highlighting follows playback
- [ ] Pause stops audio immediately
- [ ] Pause button changes back to play icon
- [ ] Resume continues from exact pause point

**Notes:**
_____________________________________________

---

### 3.2 Skip Forward/Backward

**Test ID:** TTS-002
**Priority:** High

**Steps:**
1. Start playback
2. Tap "skip forward" button (>>)
3. Tap "skip backward" button (<<)
4. Repeat several times

**Expected Results:**
- [ ] Skip forward advances to next paragraph
- [ ] Skip backward returns to previous paragraph
- [ ] Audio restarts from beginning of new paragraph
- [ ] Highlight updates correctly
- [ ] No lag or freeze
- [ ] Works while playing and paused
- [ ] Cannot skip beyond document boundaries

**Notes:**
_____________________________________________

---

### 3.3 Playback Speed Adjustment

**Test ID:** TTS-003
**Priority:** High

**Steps:**
1. Start playback at default speed (1.0x)
2. Open Quick Settings sheet
3. Adjust speed slider to 0.5x
4. Listen for speed change
5. Adjust to 2.5x
6. Test intermediate speeds

**Expected Results:**
- [ ] Speed slider accessible in Quick Settings
- [ ] Current speed displayed (e.g., "1.0x")
- [ ] Slider range: 0.5x to 2.5x
- [ ] Speed changes apply immediately
- [ ] 0.5x: noticeably slower, still natural
- [ ] 1.0x: normal conversational pace
- [ ] 2.5x: very fast but still intelligible
- [ ] Speed preference persisted (survives app restart)

**Notes:**
_____________________________________________

---

### 3.4 Voice Selection

**Test ID:** TTS-004
**Priority:** High

**Steps:**
1. Open Quick Settings sheet
2. Tap "Voice" picker
3. Select different voice
4. Verify voice change
5. Test with multiple voices

**Expected Results:**
- [ ] Voice picker shows available voices
- [ ] Current voice indicated with checkmark
- [ ] Voice names displayed (e.g., "Lessac (Medium Quality)")
- [ ] Selecting new voice restarts current paragraph
- [ ] Voice change is immediate
- [ ] Different voices have distinct characteristics
- [ ] Voice preference persisted

**Notes:**
_____________________________________________

---

### 3.5 Background Audio Continuation

**Test ID:** TTS-005
**Priority:** Critical

**Steps:**
1. Start playback
2. Press home button (go to home screen)
3. Wait and listen
4. Return to app

**Expected Results:**
- [ ] Audio continues playing in background
- [ ] No interruption when backgrounding
- [ ] Paragraph continues to advance
- [ ] Position saved when returning to app
- [ ] Highlight updated to current position
- [ ] No audio glitches or stutters

**Notes:**
_____________________________________________

---

### 3.6 Lock Screen Controls

**Test ID:** TTS-006
**Priority:** Critical
**Device:** Physical device required (simulator limited)

**Steps:**
1. Start playback
2. Lock device
3. Check lock screen
4. Test lock screen controls

**Expected Results:**
- [ ] Document title displayed on lock screen
- [ ] Current paragraph info shown
- [ ] Play/pause button works
- [ ] Skip forward button works
- [ ] Skip backward button works
- [ ] Progress indicator updates
- [ ] Album art or app icon displayed

**Notes:**
_____________________________________________

---

### 3.7 Headphone Controls

**Test ID:** TTS-007
**Priority:** High
**Device:** Physical device with headphones required

**Steps:**
1. Connect headphones (wired or Bluetooth)
2. Start playback
3. Test headphone button controls:
   - Single press: play/pause
   - Double press: skip forward
   - Triple press: skip backward

**Expected Results:**
- [ ] Single press toggles play/pause
- [ ] Double press skips to next paragraph
- [ ] Triple press returns to previous paragraph
- [ ] Controls work consistently
- [ ] Audio output to headphones
- [ ] No delay in command response

**Notes:**
_____________________________________________

---

## 4. Voice Library

### 4.1 Voice Browsing

**Test ID:** VOICE-001
**Priority:** Medium

**Steps:**
1. Open Settings
2. Tap "Voice Library" section
3. Browse available voices

**Expected Results:**
- [ ] Voice library view opens
- [ ] All voices from catalog displayed
- [ ] Each voice shows:
  - Voice name
  - Language (e.g., "English (US)")
  - Gender icon
  - Quality level
  - File size in MB
- [ ] Bundled voice indicated (e.g., "Bundled" badge)
- [ ] Downloaded voices show checkmark or "Downloaded"
- [ ] Smooth scrolling performance

**Notes:**
_____________________________________________

---

### 4.2 Filter Functionality

**Test ID:** VOICE-002
**Priority:** Medium

**Steps:**
1. Open Voice Library
2. Test language filter (if multiple languages available)
3. Test quality filter
4. Test gender filter
5. Clear all filters

**Expected Results:**
- [ ] Filter options easily accessible
- [ ] Applying filter updates voice list immediately
- [ ] Filter count badge shows active filters
- [ ] Multiple filters can be combined
- [ ] Clear filters button works
- [ ] Filtered results accurate

**Notes:**
_____________________________________________

---

### 4.3 Download Progress (Mock Test)

**Test ID:** VOICE-003
**Priority:** Low
**Note:** Download functionality may not be fully implemented

**Steps:**
1. In Voice Library, select a non-downloaded voice
2. Tap "Download" button
3. Observe UI

**Expected Results:**
- [ ] Download button visible for non-downloaded voices
- [ ] UI updates when download initiated
- [ ] Progress indicator shown (if implemented)
- [ ] Download can be cancelled (if implemented)
- [ ] Error handling for network issues
- [ ] Voice becomes available after download

**Notes:**
_____________________________________________

---

### 4.4 Voice Selection

**Test ID:** VOICE-004
**Priority:** High

**Steps:**
1. In Voice Library, view downloaded voices
2. Select a different voice
3. Return to reader
4. Start playback

**Expected Results:**
- [ ] Can select any downloaded voice
- [ ] Current voice indicated clearly
- [ ] Selection persists
- [ ] New voice used for playback
- [ ] Voice name displayed in settings

**Notes:**
_____________________________________________

---

## 5. Edge Cases

### 5.1 App Backgrounding During Playback

**Test ID:** EDGE-001
**Priority:** Critical

**Steps:**
1. Start playback
2. Background app multiple times
3. Leave backgrounded for 5+ minutes
4. Return to foreground

**Expected Results:**
- [ ] Audio continues in background
- [ ] No crashes when backgrounding
- [ ] App state preserved when returning
- [ ] Position saved correctly
- [ ] UI updates to current state
- [ ] No memory warnings

**Notes:**
_____________________________________________

---

### 5.2 Phone Call Interruption

**Test ID:** EDGE-002
**Priority:** High
**Device:** Physical device required

**Steps:**
1. Start playback
2. Receive or make a phone call
3. Answer call
4. End call
5. Return to app

**Expected Results:**
- [ ] Playback pauses when call starts
- [ ] Audio interruption handled gracefully
- [ ] Playback does NOT auto-resume after call
- [ ] Play button state updated correctly
- [ ] No audio conflicts with phone app
- [ ] User can manually resume playback

**Notes:**
_____________________________________________

---

### 5.3 Headphone Disconnect

**Test ID:** EDGE-003
**Priority:** High
**Device:** Physical device with removable headphones

**Steps:**
1. Connect headphones
2. Start playback
3. Disconnect headphones during playback

**Expected Results:**
- [ ] Playback pauses immediately when headphones disconnect
- [ ] No audio plays through speaker
- [ ] Play button state updated to paused
- [ ] User must manually resume to play through speaker
- [ ] No crashes or errors
- [ ] Reconnecting headphones doesn't auto-resume

**Notes:**
_____________________________________________

---

### 5.4 Low Battery

**Test ID:** EDGE-004
**Priority:** Medium
**Device:** Physical device required

**Steps:**
1. Let device battery drain to < 20%
2. Start playback
3. Let battery drain further
4. Enable Low Power Mode
5. Continue playback

**Expected Results:**
- [ ] Playback continues normally at low battery
- [ ] No unexpected pauses or stops
- [ ] Low Power Mode doesn't disable playback
- [ ] Background audio works in Low Power Mode
- [ ] No performance degradation
- [ ] Battery drains at reasonable rate

**Notes:**
_____________________________________________

---

### 5.5 Large Documents

**Test ID:** EDGE-005
**Priority:** Medium

**Steps:**
1. Import a very large document (> 500 pages or > 10MB)
2. Open document
3. Start playback
4. Skip through content
5. Monitor performance

**Expected Results:**
- [ ] Large document imports successfully
- [ ] Reader view opens without significant delay
- [ ] Text extraction completes
- [ ] Playback starts without lag
- [ ] Skip forward/backward responsive
- [ ] No memory warnings
- [ ] App doesn't crash
- [ ] UI remains responsive

**Notes:**
_____________________________________________

---

### 5.6 App Termination and Restart

**Test ID:** EDGE-006
**Priority:** High

**Steps:**
1. Start playback at a specific paragraph (e.g., paragraph 50)
2. Force quit the app
3. Relaunch app
4. Open the same document

**Expected Results:**
- [ ] App relaunches successfully
- [ ] Document library intact
- [ ] Opening document returns to last read position
- [ ] Reading progress saved correctly
- [ ] Playback settings preserved (speed, voice)
- [ ] No data loss

**Notes:**
_____________________________________________

---

### 5.7 Simultaneous Document Switches

**Test ID:** EDGE-007
**Priority:** Medium

**Steps:**
1. Open Document A, start playback
2. Return to library (playback continues)
3. Open Document B
4. Verify behavior

**Expected Results:**
- [ ] Document A playback stops when opening Document B
- [ ] Document A position saved
- [ ] Document B opens cleanly
- [ ] No audio overlap
- [ ] No crashes or state corruption
- [ ] Can return to Document A and resume

**Notes:**
_____________________________________________

---

### 5.8 Empty or Corrupted Documents

**Test ID:** EDGE-008
**Priority:** Medium

**Steps:**
1. Attempt to import an empty PDF
2. Attempt to import a corrupted EPUB
3. Attempt to import unsupported file type

**Expected Results:**
- [ ] Error message for empty documents
- [ ] Error message for corrupted files
- [ ] Error message for unsupported types
- [ ] No crashes
- [ ] App remains stable
- [ ] User-friendly error descriptions
- [ ] Document not added to library

**Notes:**
_____________________________________________

---

## 6. Performance Benchmarks

### 6.1 App Launch Time

**Test ID:** PERF-001
**Priority:** Medium

**Steps:**
1. Force quit app
2. Start timer
3. Launch app
4. Stop timer when UI is interactive

**Target:** < 2 seconds cold launch

**Results:**
- Cold launch time: _________ seconds
- Warm launch time: _________ seconds
- [ ] Meets target performance

**Notes:**
_____________________________________________

---

### 6.2 Document Loading Time

**Test ID:** PERF-002
**Priority:** Medium

**Steps:**
1. Time opening small document (< 1MB)
2. Time opening large document (> 5MB)

**Target:** < 1 second for small, < 3 seconds for large

**Results:**
- Small PDF load time: _________ seconds
- Large PDF load time: _________ seconds
- EPUB load time: _________ seconds
- [ ] Meets target performance

**Notes:**
_____________________________________________

---

### 6.3 TTS Response Time

**Test ID:** PERF-003
**Priority:** High

**Steps:**
1. Tap play button
2. Measure time until audio starts

**Target:** < 500ms from tap to audio

**Results:**
- Time to first audio: _________ ms
- [ ] Meets target performance

**Notes:**
_____________________________________________

---

## 7. Regression Testing

### 7.1 Previously Fixed Issues

**Test ID:** REG-001
**Priority:** High

**Steps:**
1. Test hyphenation handling (previous bug fix)
2. Verify trailing whitespace handled correctly
3. Check line joining works properly

**Expected Results:**
- [ ] Hyphenated words joined correctly
- [ ] No extra spaces from trailing whitespace
- [ ] Text flows naturally across lines

**Notes:**
_____________________________________________

---

## 8. Accessibility

### 8.1 VoiceOver Support

**Test ID:** ACC-001
**Priority:** Medium
**Device:** Any (simulator or physical)

**Steps:**
1. Enable VoiceOver
2. Navigate library
3. Open document
4. Test playback controls

**Expected Results:**
- [ ] All buttons have accessibility labels
- [ ] Document titles announced
- [ ] Playback state announced
- [ ] Slider controls accessible
- [ ] Navigation logical and clear

**Notes:**
_____________________________________________

---

### 8.2 Dynamic Type

**Test ID:** ACC-002
**Priority:** Low

**Steps:**
1. Settings > Accessibility > Display & Text Size > Larger Text
2. Increase text size to maximum
3. Navigate app

**Expected Results:**
- [ ] Text scales appropriately
- [ ] No text truncation
- [ ] UI layout adapts
- [ ] Buttons remain accessible
- [ ] No overlapping content

**Notes:**
_____________________________________________

---

## Summary

### Test Results

**Total Tests:** 42
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

### Recommendations

_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________

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
