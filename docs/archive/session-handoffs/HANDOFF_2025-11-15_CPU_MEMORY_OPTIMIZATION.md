# Session Handoff: CPU & Memory Optimization - Synthesis Queue Fixes

**Date:** November 15, 2025
**Status:** 🟡 PARTIAL SUCCESS - CPU improved (476% → 200%), memory still critical (2.34 GB)
**Next Session:** Fix memory leak (2.34 GB) and playback stuck issue

---

## 🎯 What We Accomplished This Session

### ✅ Major Achievement: Reduced CPU Usage (476% → 200%)

**Three-phase optimization:**

#### Phase 1: Serial OperationQueue (476% → 294%)
- **Problem:** Unbounded Task concurrency in `preSynthesizeAhead()` spawned 3+ concurrent ONNX sessions
- **Fix:** Added `OperationQueue` with `maxConcurrentOperationCount = 1`
- **Result:** CPU dropped from 476% to 294% (~38% reduction)
- **Files:** `SynthesisQueue.swift`
- **Commit reference:** Workshop decision recorded

#### Phase 2: Simplified Concurrency + Cache Limits (294% → ~100% initial)
- **Problem:** Task-inside-OperationQueue pattern still caused thread pool explosion
- **Fixes:**
  1. Removed OperationQueue+Task wrapper, simplified to direct async calls
  2. Reduced `lookaheadCount: 3 → 1`
  3. Added `maxCacheSize = 2` (current + next paragraph only)
  4. Added `evictOldCacheEntries()` for aggressive cache cleanup
  5. Added memory profiling with `getMemoryUsageMB()`
- **Result:** Initial CPU ~100%, memory targeted <500 MB
- **Files:** `SynthesisQueue.swift:14-20, 309-345`

#### Phase 3: Serialization Gate (Attempted fix for 295% regression)
- **Problem:** On pause/resume, CPU grew back to 295% - logs showed paragraphs 0, 3, 5 synthesizing concurrently
- **Root cause:** Swift `Task {}` blocks run **concurrently by default**!
- **Fix:** Added `isSynthesizing` gate with wait loop
- **Result:** CPU down to 200% (better but not fully serialized)
- **Files:** `SynthesisQueue.swift:35-38, 122-128, 190-265`

### ✅ Added Comprehensive Memory & Performance Profiling

**New instrumentation in SynthesisQueue.swift:**

```swift
// Memory tracking
let memoryBefore = getMemoryUsageMB()
// ... synthesis ...
let memoryAfter = getMemoryUsageMB()
print("memory: \(memoryAfter) MB (+\(memoryDelta) MB)")

// Timing breakdown
synthesis time, alignment time, total time
```

**Cache eviction logging:**
```
[SynthesisQueue] 🗑️ Evicted audio cache for paragraph X
[SynthesisQueue] 🗑️ Evicted alignment cache for paragraph X
```

### ✅ Prevented Memory Explosion from Unbounded Cache

- Reduced lookahead window from 3 → 1 paragraph
- Added `maxCacheSize = 2` limit
- Implemented `evictOldCacheEntries()` that runs after every synthesis
- **Evidence:** Logs show evictions working (10 evictions in latest run)

---

## 🔴 Current Critical Issues

### Issue #0: CRITICAL - Memory Still at 2.34 GB (iOS Jetsam Kills!)

**Status:** ⚠️ NOT FIXED - App still gets killed by iOS

**Evidence from logs (180k lines):**
```
Starting on-demand synthesis for paragraph 0, memory: 1892.3 MB
Starting on-demand synthesis for paragraph 0, memory: 1772.4 MB
Pre-synthesis paragraph 86 done - 120.89s, memory: 1366.3 MB
```

**Memory stays between 1.3 GB - 1.9 GB throughout playback**

**What we know:**
- ✅ Cache eviction IS working (logs show evictions)
- ✅ Only 2 paragraphs cached at most (maxCacheSize=2)
- ❌ Memory NOT being released
- ❌ Disk alignment cache barely used (only 6 saves, 3 loads in 180k lines)

**Likely causes:**
1. **Audio WAV data not released** - Cache stores `Data` objects, Swift may not release immediately
2. **ONNX Runtime accumulation** - sherpa-onnx may be keeping internal state/sessions
3. **Alignment data bloat** - WordTimings arrays might be huge
4. **Swift retain cycles** - Closures/Tasks capturing self

**Evidence from logs:**
```
[PiperTTS] Synthesized 2480896 samples at 22050 Hz
[PIPER_DEBUG] synth_callback invoked, numsamples=1324  (repeated 100s of times)
```

That's **2.48 million samples × 4 bytes (Float) = ~10 MB per paragraph** just for audio!
With alignment data, could be 20-30 MB per paragraph.
2 paragraphs × 30 MB = **60 MB expected**, but we're seeing **2.34 GB!**

**Something is accumulating** - either old cache not clearing or ONNX internal memory.

### Issue #1: CPU Still at 200% (Not Fully Serialized)

**Status:** 🟡 IMPROVED (476% → 200%) but not target (~100%)

**Problem:** Serialization gate has race condition

**Evidence from logs:**
```
Starting on-demand synthesis for paragraph 0, memory: 1892.3 MB
Starting on-demand synthesis for paragraph 1, memory: 1907.6 MB
Starting on-demand synthesis for paragraph 2, memory: 1909.1 MB
```

Multiple paragraphs still starting (though fewer than before)

**Root cause:** Race condition in gate implementation:
```swift
while isSynthesizing { await Task.sleep(...) }  // Check
isSynthesizing = true  // Set (NOT atomic!)
```

Between check and set, multiple tasks can slip through!

**Solution needed:** Use Swift `actor` for compiler-enforced serialization, or use proper atomic operations.

### Issue #2: Playback Stuck - Replays Same Paragraph

**Status:** 🔴 BROKEN - User experience degraded

**Symptom:** After paragraph completes, pressing play just replays the same paragraph (0, 1, or 2)

**Evidence from logs:**
```
Starting on-demand synthesis for paragraph 0 (multiple times)
Starting on-demand synthesis for paragraph 1 (multiple times)
Starting on-demand synthesis for paragraph 2 (multiple times)
```

Paragraphs 0, 1, 2 synthesized repeatedly, then jumps to paragraph 85!

**Possible causes:**
1. Gate blocking `getAudio()` - synthesis queue always returns nil?
2. Auto-advance broken - `handleParagraphComplete()` not incrementing index?
3. Cache returning old data - eviction happens but cache lookup fails?

**Needs investigation:**
- Check `TTSService.handleParagraphComplete()`
- Check `SynthesisQueue.getAudio()` return flow
- Verify cache lookup logic

---

## 📊 Items from Previous Handoff (Not Addressed)

### Priority 2: Word Highlighting Accuracy ~50% (Deferred)

**From previous handoff:**
- Word highlighting correct <50% of the time
- Sometimes highlights wrong word, skips words, or gets stuck on last word
- Needs detailed logging to trace VoxPDF → normalized → phoneme mapping

**Status:** ⏸️ DEFERRED - Must fix memory/CPU first

**Investigation needed:**
```swift
print("[DEBUG_ALIGN] === Paragraph Debug ===")
// Log VoxPDF words, normalized text, char mapping, phonemes, word timings
```

**Test with known failing cases:**
- "Dr." → "Doctor" normalization
- Numbers and dates
- Contractions

### Priority 3: Last Word Stuck Issue (Deferred)

**From previous handoff:**
- Highlighting gets stuck on last word of paragraph
- Likely duration mismatch or off-by-one error
- Has timeout logic but may need forced completion

**Status:** ⏸️ DEFERRED

**Quick fix to try:**
```swift
// When audio completes
if currentWordIndex < wordTimings.count - 1 {
    currentWordIndex = wordTimings.count - 1
}
```

---

## 🎯 Next Session Priorities

### Priority 0: Fix Memory Leak (CRITICAL - App Unusable)

**Goal:** Reduce memory from 2.34 GB → <500 MB (prevent jetsam kills)

**Investigation steps:**

1. **Profile memory by component:**
   ```swift
   print("[MEMORY] Cache size: \(cache.values.reduce(0) { $0 + $1.count }) bytes")
   print("[MEMORY] Alignments: \(alignments.count) entries")
   // Check each component's contribution
   ```

2. **Check ONNX session lifecycle:**
   - Is `SherpaOnnxOfflineTtsWrapper` being reused or recreated?
   - Does sherpa-onnx C++ code have memory leaks?
   - Try calling cleanup/reset after synthesis

3. **Force cache clear:**
   ```swift
   // In evictOldCacheEntries, add:
   cache.removeAll(keepingCapacity: false)
   alignments.removeAll(keepingCapacity: false)
   // Then re-add only current paragraphs
   ```

4. **Check for retain cycles:**
   - All Task closures use `[weak self]`?
   - Check `activeTasks` dictionary - are tasks actually removed?

5. **Add memory warning handler:**
   ```swift
   NotificationCenter.default.addObserver(
       forName: UIApplication.didReceiveMemoryWarningNotification,
       object: nil,
       queue: .main
   ) { [weak self] _ in
       self?.synthesisQueue?.clearAll()
   }
   ```

**Expected result:** Memory drops to <500 MB and stays there.

### Priority 1: Fix Serialization (True 100% CPU)

**Goal:** Guarantee only ONE synthesis at a time

**Option A: Convert to Actor (Recommended)**

```swift
// Change from:
@MainActor final class SynthesisQueue { }

// To:
actor SynthesisQueue {
    // All methods automatically serialized by Swift!
}
```

**Benefits:**
- Compiler-enforced serialization
- No manual gates
- No race conditions
- Clean code

**Challenges:**
- Need to audit all callers (await everywhere)
- MainActor calls need restructuring

**Option B: Use AsyncSemaphore**

```swift
private let synthesisSemaphore = AsyncSemaphore(value: 1)

func getAudio(for index: Int) async throws -> Data? {
    await synthesisSemaphore.wait()
    defer { synthesisSemaphore.signal() }
    // ... synthesis ...
}
```

**Expected result:** CPU stays at ~100% even on pause/resume.

### Priority 2: Fix Playback Stuck Issue

**Goal:** Paragraphs advance correctly

**Investigation:**

1. **Add logging to TTSService:**
   ```swift
   func handleParagraphComplete() {
       print("[TTSService] Paragraph \(currentProgress.paragraphIndex) completed")
       print("[TTSService] shouldAutoAdvance: \(shouldAutoAdvance)")
       print("[TTSService] Next index: \(nextIndex)")
   }
   ```

2. **Check `getAudio()` return value:**
   - Is it returning nil when synthesis completes?
   - Is gate blocking legitimate requests?

3. **Verify cache logic:**
   - Does `cache[index]` return old data after eviction?
   - Is eviction happening BEFORE playback needs the data?

**Expected result:** Smooth paragraph progression.

### Priority 3: Then Return to Word Highlighting

Once memory/CPU/playback are stable, resume word highlighting accuracy investigation.

---

## 📁 Files Modified This Session

### Major Changes

**SynthesisQueue.swift** - Complete refactor for memory/CPU optimization

**Key changes:**
- Line 14-20: Reduced `lookaheadCount: 3 → 1`, added `maxCacheSize = 2`
- Line 35-38: Added `isSynthesizing` gate
- Line 122-128: Gate wait loop in `getAudio()`
- Line 142-143: `evictOldCacheEntries()` call
- Line 190-265: Refactored `preSynthesizeAhead()` with gate
- Line 309-345: Added `evictOldCacheEntries()` and `getMemoryUsageMB()`

**Impact:** Reduced CPU, added memory tracking, aggressive cache limits

### Workshop Decisions Recorded

1. **CPU Fix Phase 1:** Serial OperationQueue (476% → 294%)
2. **Memory Fix:** Simplified concurrency + cache limits (target <500 MB)
3. **Serialization Gate:** isSynthesizing boolean gate (295% → 200%)

---

## 🔍 Key Debugging Commands

### Memory Analysis

```bash
# Check memory usage over time
grep "memory: [0-9]" /Users/zachswift/listen-2-logs-2025-11-13.txt | tail -50

# Count cache evictions
grep "Evicted" /Users/zachswift/listen-2-logs-2025-11-13.txt | wc -l

# Check synthesis sizes
grep "Synthesized.*samples" /Users/zachswift/listen-2-logs-2025-11-13.txt

# Calculate expected memory
# 2.48M samples × 4 bytes (Float32) = 9.92 MB audio per paragraph
# + alignment data (~10-20 MB estimated)
# = ~20-30 MB per paragraph
# × maxCacheSize=2 = 40-60 MB expected (but seeing 2.34 GB!)
```

### Concurrency Analysis

```bash
# Check concurrent synthesis
grep "Starting.*synthesis for paragraph" /Users/zachswift/listen-2-logs-2025-11-13.txt | tail -30

# Check gate activation
grep "Skipping pre-synthesis" /Users/zachswift/listen-2-logs-2025-11-13.txt

# Count paragraph re-synthesis
grep "Starting.*synthesis for paragraph [0-9]" /path/to/logs | sort | uniq -c
```

### Playback Flow

```bash
# Check paragraph progression
grep -E "handleParagraphComplete|speakParagraph|nextIndex" /path/to/logs

# Check cache hits/misses
grep -E "Loaded from cache|Starting on-demand" /path/to/logs | tail -20
```

---

## 💡 Lessons Learned

### What Worked

✅ **Serial OperationQueue** - Immediate 38% CPU reduction (476% → 294%)
✅ **Aggressive cache limits** - Reduced memory target from unbounded → 60 MB
✅ **Memory profiling** - Now we can see where memory goes
✅ **Cache eviction** - Working correctly (logs confirm)
✅ **Reduced lookahead** - Less memory pressure

### What Didn't Work

❌ **Task-inside-OperationQueue** - Created thread pool explosion
❌ **Simple boolean gate** - Race condition allows concurrent access
❌ **Memory clearing** - Something is retaining 2+ GB
❌ **Disk cache** - Barely being used (alignment saves but not loads?)

### Key Insights

**Swift Task Concurrency is Tricky:**
- `Task {}` blocks run concurrently by default
- Even inside serial OperationQueue!
- Need actor or semaphore for true serialization

**Memory Leaks are Sneaky:**
- Cache eviction working ≠ memory released
- Swift `Data` objects may be retained elsewhere
- ONNX C++ runtime may accumulate internal state
- Need to profile actual memory layout, not just cache size

**iOS Memory Management is Aggressive:**
- 2.34 GB → jetsam kill
- Need to stay under ~500 MB for safety
- Memory warnings should trigger cache clear

---

## 🧪 Testing Strategy for Next Session

### Test 1: Memory Leak Identification

1. Start app with Xcode Memory Debugger
2. Play 10 paragraphs
3. Take memory snapshot
4. Check allocations:
   - How many `Data` objects?
   - Total audio data size?
   - Alignment data size?
   - ONNX session memory?

### Test 2: Serialization Verification

1. Add atomic counter: `synthesisCount`
2. Increment on synthesis start, decrement on end
3. Assert `synthesisCount <= 1` always
4. Add logging if assertion fails

### Test 3: Playback Flow

1. Add detailed logging in `TTSService`
2. Play through 5 paragraphs
3. Verify:
   - Each paragraph plays once
   - Auto-advance works
   - Cache returns correct data
   - No stuck/replay issues

---

## 📚 Key Resources

### Documentation
- **This handoff:** `docs/HANDOFF_2025-11-15_CPU_MEMORY_OPTIMIZATION.md`
- **Previous session:** `docs/HANDOFF_2025-11-14_WCEIL_DTYPE_FIX.md`
- **Framework update:** `docs/FRAMEWORK_UPDATE_GUIDE.md`

### Code Locations
- **Synthesis queue:** `Services/TTS/SynthesisQueue.swift`
- **TTS service:** `Services/TTSService.swift`
- **ONNX wrapper:** `Services/TTS/SherpaOnnx.swift`
- **Piper provider:** `Services/TTS/PiperTTSProvider.swift`
- **Alignment cache:** `Services/TTS/AlignmentCache.swift`

### Logs
- **Latest run:** `/Users/zachswift/listen-2-logs-2025-11-13.txt` (180,879 lines)
- **Build output:** `/tmp/build_serialization.log`

### Workshop Entries
- Search: `workshop search "cpu" OR "memory" OR "serialization"`
- Why CPU high: `workshop why "cpu overload"`

---

## ✅ Success Criteria for Next Session

### Minimum Viable (Must Have)
- [ ] Memory drops below 1 GB (ideally <500 MB)
- [ ] No jetsam kills during playback
- [ ] CPU stays at ~100% throughout (including pause/resume)
- [ ] Paragraphs advance correctly (no stuck/replay)

### Ideal (Nice to Have)
- [ ] Memory stays under 500 MB
- [ ] CPU at exactly 100% (single core)
- [ ] True actor-based serialization
- [ ] Playback feels instant and smooth

### Acceptable Fallback
If memory can't get below 1 GB:
- [ ] Document root cause clearly
- [ ] Implement memory warning handler
- [ ] Add user-facing memory indicator
- [ ] Consider reducing model quality/size

---

## 🚨 Critical Notes for Next Session

### The CPU Fix is Partial

We went from **476% → 200%** which is great progress, but **200% is still 2 cores**.

**Why 200% is still too high:**
- Should be ~100% (1 core + small overhead)
- Indicates 2 concurrent synthesis operations
- Race condition in gate allows this

**Next fix MUST use actor or AsyncSemaphore** - no more manual gates!

### The Memory Leak is Real

**2.34 GB is NOT sustainable:**
- iOS will kill app (already seen jetsam dialogs)
- Expected: 60 MB (2 paragraphs × 30 MB)
- Actual: 2340 MB (39× too much!)
- **Something is accumulating 2.28 GB of garbage**

This is the **#1 priority** - app is unusable until fixed.

### Don't Get Distracted

**Do NOT work on word highlighting** until memory/CPU are stable.
**Do NOT add new features** until core playback works.
**Do NOT optimize performance** until memory leak is fixed.

**Focus ruthlessly on:**
1. Memory leak (jetsam kills)
2. Full serialization (200% → 100%)
3. Playback stuck issue

Everything else can wait.

---

## 🎬 Session Summary

**We made significant progress on CPU optimization** (476% → 200% is a 58% reduction!), but **memory is still critical** and **playback is broken**.

The good news: We have excellent instrumentation now, clear evidence from logs, and a solid understanding of the root causes.

The bad news: Memory leak is worse than expected (2.34 GB!), and we need to switch from manual gates to proper Swift concurrency primitives.

**Next session should start with:**
Priority 0: Memory profiling with Xcode Instruments to find the 2.34 GB leak.

---

**End of Handoff**

*Next session: Fix memory leak with Instruments profiling, then convert to actor for true serialization*
