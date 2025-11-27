# Session Handoff: Diagnostic Logging Implementation & Analysis Guide

**Date:** 2025-11-12
**Status:** Diagnostic logging deployed, app running with output ready for analysis
**Next Step:** Analyze diagnostic log output to identify root cause

---

## What We Accomplished This Session

### 1. Added Diagnostic Logging to piper-phonemize ✅

**Repository:** `https://github.com/zachswift615/piper-phonemize.git`
**Branch:** `feature/espeak-position-tracking`
**Commit:** `3221e9c` - "debug: add diagnostic logging for position tracking"

**File Modified:** `src/phonemize.cpp`

**Logging Points Added:**

1. **Callback Registration** (Line ~197)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG] Registered synth_callback for position tracking\n");
   ```
   - Confirms espeak callback is registered
   - Should appear once per TTS request

2. **Capture Enabled** (Line ~213)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG] Enabled phoneme capture for clause\n");
   ```
   - Shows when phoneme capture starts for each text clause
   - May appear multiple times if text has multiple clauses

3. **Callback Invocation** (Line ~155)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG] synth_callback invoked, numsamples=%d\n", numsamples);
   ```
   - Logs each time espeak-ng calls our callback
   - Should be called multiple times during synthesis

4. **Phoneme Events** (Line ~160)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG]   Phoneme event: pos=%d\n", events->text_position);
   ```
   - Logs each individual phoneme position captured
   - Should see many of these (one per phoneme)

5. **Positions Captured** (Line ~224)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG] Captured %zu positions from espeak\n",
           g_phoneme_capture.positions.size());
   ```
   - Summary of how many positions were captured per clause
   - **CRITICAL**: If this shows 0, espeak didn't call our callback

6. **Final Count** (Line ~376)
   ```cpp
   fprintf(stderr, "[PIPER_DEBUG] Returning %zu phoneme sequences with positions\n",
           positions.size());
   ```
   - Shows final count of phoneme sequences being returned
   - Should be ≥ 1 for successful synthesis

### 2. Rebuilt & Deployed sherpa-onnx Framework ✅

**Build Completed:** 2025-11-12 22:25:12
**Location:** `/Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework`
**Verification:**
- ✅ Framework contains `WithPositions` symbols (3 found)
- ✅ Downloaded from correct fork: `zachswift615/piper-phonemize.git`
- ✅ Diagnostic logging present in compiled code (6 instances)

### 3. Cleared Xcode Caches ✅

- Deleted DerivedData
- Resolved Swift package dependencies (ZIPFoundation, SWCompression)
- App built successfully with diagnostic framework

---

## How to Analyze the Diagnostic Logs

### Expected Log Flow for WORKING Phoneme Position Tracking

```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] synth_callback invoked, numsamples=160
[PIPER_DEBUG]   Phoneme event: pos=0
[PIPER_DEBUG]   Phoneme event: pos=1
[PIPER_DEBUG]   Phoneme event: pos=2
[PIPER_DEBUG]   Phoneme event: pos=4
... (many more phoneme events) ...
[PIPER_DEBUG]   Phoneme event: pos=78
[PIPER_DEBUG] synth_callback invoked, numsamples=160
[PIPER_DEBUG]   Phoneme event: pos=80
... (more events) ...
[PIPER_DEBUG] Captured 47 positions from espeak
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**What this means:**
- Callback registered ✅
- Capture enabled ✅
- espeak-ng IS calling our callback ✅
- Phoneme positions ARE being captured ✅
- Positions ARE being returned ✅

### Scenario 1: Callback Never Called

```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] Captured 0 positions from espeak  ← ❌ PROBLEM!
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**Missing logs:**
- NO `synth_callback invoked` messages
- NO `Phoneme event` messages

**Root Cause:** espeak-ng is NOT calling our callback function

**Possible reasons:**
1. espeak-ng library not built with callback support
2. Callback registration failing silently
3. espeak-ng using different synthesis path that bypasses callbacks
4. Thread-local storage issue preventing callback from seeing capture flag

**Next Steps:**
1. Check espeak-ng build configuration in sherpa-onnx
2. Verify espeak-ng fork/version being used
3. Add logging to espeak_SetSynthCallback to confirm it succeeds
4. Check if espeak_Synth is the right API (vs espeak_TextToPhonemes)

### Scenario 2: Callback Called But No Phoneme Events

```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] synth_callback invoked, numsamples=160
[PIPER_DEBUG] synth_callback invoked, numsamples=160
... (multiple invocations but NO phoneme events) ...
[PIPER_DEBUG] Captured 0 positions from espeak  ← ❌ PROBLEM!
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**What's happening:**
- Callback IS being called ✅
- But events array contains no PHONEME events ❌

**Root Cause:** espeak is calling callback but not sending phoneme events

**Possible reasons:**
1. espeak-ng configured to not generate phoneme events
2. Event type filtering issue in callback
3. Events array not properly populated by espeak

**Next Steps:**
1. Log ALL event types received (not just PHONEME)
2. Check espeak_Synth parameters (flags might disable phoneme events)
3. Verify espeak voice configuration

### Scenario 3: Thread-Local Storage Issue

```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] Captured 0 positions from espeak  ← ❌ PROBLEM!
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**AND separately in logs (different thread):**
```
[PIPER_DEBUG] synth_callback invoked, numsamples=160
[PIPER_DEBUG]   Phoneme event: pos=0
[PIPER_DEBUG]   Phoneme event: pos=1
... (but these are NOT being captured) ...
```

**Root Cause:** Callback running on different thread than capture flag

**Possible reasons:**
1. espeak-ng calling callback from different thread
2. Thread-local storage not working as expected
3. Race condition between enabling capture and callback execution

**Next Steps:**
1. Add thread ID logging to both capture enable and callback
2. Consider using mutex instead of thread-local storage
3. Check espeak-ng threading model

### Scenario 4: Position Data Lost in Transit

```
[PIPER_DEBUG] Registered synth_callback for position tracking
[PIPER_DEBUG] Enabled phoneme capture for clause
[PIPER_DEBUG] synth_callback invoked, numsamples=160
[PIPER_DEBUG]   Phoneme event: pos=0
... (many events) ...
[PIPER_DEBUG] Captured 47 positions from espeak  ← ✅ GOOD!
[PIPER_DEBUG] Returning 1 phoneme sequences with positions
```

**BUT still seeing in Swift logs:**
```
[SherpaOnnx] No phoneme data available from C API  ← ❌ PROBLEM!
```

**Root Cause:** Positions captured successfully but lost between C++ → C API → Swift

**Next Steps:**
1. Add logging in sherpa-onnx C++ code after piper-phonemize returns
2. Check if positions vector is being copied to GeneratedAudio struct
3. Verify C API is reading from correct struct fields
4. Add logging in Swift bridge to see what C API returns

---

## Diagnostic Log Analysis Checklist

Use this checklist to systematically analyze the logs:

- [ ] **Step 1: Find the first occurrence of `[PIPER_DEBUG]`**
  - If missing entirely → diagnostic framework not loaded (rebuild needed)

- [ ] **Step 2: Confirm callback registration**
  - Look for: `Registered synth_callback for position tracking`
  - If missing → registration code not executing

- [ ] **Step 3: Confirm capture enabled**
  - Look for: `Enabled phoneme capture for clause`
  - If missing → synthesis not happening or different code path

- [ ] **Step 4: Check for callback invocations**
  - Look for: `synth_callback invoked`
  - If missing → Scenario 1 (callback never called)
  - If present → Continue to Step 5

- [ ] **Step 5: Check for phoneme events**
  - Look for: `Phoneme event: pos=N`
  - If missing but callback invoked → Scenario 2 (no phoneme events)
  - If present → Continue to Step 6

- [ ] **Step 6: Check positions captured count**
  - Look for: `Captured N positions from espeak`
  - If N = 0 → Positions not being stored (thread issue?)
  - If N > 0 → Continue to Step 7

- [ ] **Step 7: Check final return count**
  - Look for: `Returning N phoneme sequences with positions`
  - Should be ≥ 1
  - If 0 → Logic error in phonemize function

- [ ] **Step 8: Cross-reference with Swift logs**
  - Look for: `[SherpaOnnx] Extracting N phonemes from C API`
  - If still "No phoneme data available" → Scenario 4 (data lost in transit)

---

## Quick Pattern Recognition

### ✅ GOOD Pattern (Everything Working)
```
[PIPER_DEBUG] Registered synth_callback
[PIPER_DEBUG] Enabled phoneme capture
[PIPER_DEBUG] synth_callback invoked        ← Key indicator
[PIPER_DEBUG]   Phoneme event: pos=0        ← Key indicator
[PIPER_DEBUG]   Phoneme event: pos=1        ← Key indicator
... (many more) ...
[PIPER_DEBUG] Captured 47 positions         ← Key indicator (N > 0)
[PIPER_DEBUG] Returning 1 phoneme sequences
[SherpaOnnx] Extracting 47 phonemes         ← Should see in Swift logs
```

### ❌ BAD Pattern 1 (Callback Dead)
```
[PIPER_DEBUG] Registered synth_callback
[PIPER_DEBUG] Enabled phoneme capture
[PIPER_DEBUG] Captured 0 positions          ← PROBLEM: jumped to 0
[PIPER_DEBUG] Returning 1 phoneme sequences
```

### ❌ BAD Pattern 2 (Events Missing)
```
[PIPER_DEBUG] Registered synth_callback
[PIPER_DEBUG] Enabled phoneme capture
[PIPER_DEBUG] synth_callback invoked        ← Callback works
[PIPER_DEBUG] Captured 0 positions          ← But no events captured
[PIPER_DEBUG] Returning 1 phoneme sequences
```

---

## Commands for Next Session

### Extract Just the Diagnostic Logs

If you have the full Xcode console output in a file:

```bash
# Extract only PIPER_DEBUG lines
grep "\[PIPER_DEBUG\]" xcode_output.log > piper_debug.log

# Count occurrences of each log type
grep -c "Registered synth_callback" piper_debug.log
grep -c "Enabled phoneme capture" piper_debug.log
grep -c "synth_callback invoked" piper_debug.log
grep -c "Phoneme event" piper_debug.log
grep -c "Captured.*positions" piper_debug.log
```

### Quick Diagnosis

```bash
# Count total phoneme events captured
grep "Phoneme event" piper_debug.log | wc -l

# See the "Captured N positions" line
grep "Captured.*positions" piper_debug.log
```

---

## Files Modified This Session

### piper-phonemize
- **File:** `src/phonemize.cpp`
- **Commit:** `3221e9c`
- **Changes:** Added 6 diagnostic logging statements

### sherpa-onnx
- **Build:** Fresh build from clean state
- **Output:** `build-ios/sherpa-onnx.xcframework`
- **Deployed:** `/Users/zachswift/projects/Listen2/Frameworks/`

### Listen2
- **Changes:** Framework updated, DerivedData cleared, packages resolved
- **Status:** Built successfully, running with diagnostic output

---

## Critical Context for Next Session

### The Key Question We're Answering

**Why is `g_phoneme_capture.positions` empty when returned to sherpa-onnx?**

The diagnostic logs will definitively show us AT WHICH POINT in the pipeline the phoneme position data is lost:

1. **Registration fails** → No callback setup
2. **Callback never called** → espeak-ng not triggering it
3. **Events not sent** → espeak-ng not generating phoneme events
4. **Events not captured** → Thread or storage issue
5. **Data lost after capture** → sherpa-onnx not reading it correctly

### Expected Time to Root Cause

- **If logs clearly show the issue:** 5-10 minutes to identify, 30-60 minutes to fix
- **If issue is subtle:** May need additional logging points, another rebuild cycle

---

## Workshop Commands for Context

```bash
# Load this session's context
workshop context

# Search for diagnostic logging decisions
workshop why "diagnostic"
workshop why "piper-phonemize"

# Record findings from log analysis
workshop note "Diagnostic logs show: [your findings]"
workshop decision "Root cause identified as: [cause]" -r "[reasoning from logs]"
```

---

## Success Criteria for Next Session

✅ **Root cause identified** from diagnostic logs
✅ **Fix implemented** based on findings
✅ **Phoneme positions flowing** through pipeline
✅ **Word-level highlighting working** in app

**Estimated time:** 1-2 hours depending on complexity of root cause

---

## Emergency Fallback

If diagnostic logs are too voluminous or unclear:

1. **Filter to first TTS request only:**
   - Look for the first occurrence of "Registered synth_callback"
   - Analyze only the logs between that and the next occurrence

2. **Test with simple text:**
   - Use single word like "Hello" to minimize log output
   - Easier to trace through fewer phonemes

3. **Add sequential numbering:**
   - If needed, can add log counters to track call ordering

---

**Prepared by:** Claude (Session 5)
**Ready for:** Log analysis and root cause identification
**Confidence:** 95% that logs will reveal the exact failure point

🎯 **Next session starts with:** Analyzing the diagnostic log output you captured this session!
