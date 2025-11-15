# Session Handoff: Memory Profiling Setup - Next Steps

**Date:** November 15, 2025
**Status:** ✅ Concurrency Fixed, ⚠️ Memory Leak Identified (2.29 GB)
**Next Session:** Profile memory with Instruments or analyze breakdown logs

---

## ✅ What We Fixed This Session

### 1. Critical Concurrency Bugs (CPU 476% → ~100%)
- **Fixed defer bug** (Line 219): `defer { Task { await ... } }` released gate immediately
- **Implemented atomic lock**: Continuation queue eliminates check-then-set race condition
- **Actor conversion**: Compiler-enforced thread safety for all SynthesisQueue state
- **Result:** CPU stable at ~100%, synthesis properly serialized

### 2. Playback Bugs
- **Fixed getAudio() nil returns**: Now waits for pre-synthesis instead of failing
- **Fixed skip buttons**: Added `stopAudioOnly()` that preserves document state
- **Result:** Next/Previous buttons work correctly, no "Synthesis returned nil" errors

### 3. Added Memory Profiling
- **New method**: `logMemoryBreakdown()` in SynthesisQueue
- **Auto-logs** every 5 paragraphs during playback
- **Shows:** Total memory, audio cache, alignment cache, unaccounted memory

---

## ⚠️ Critical Issue: Memory Leak (2.29 GB)

**Current State:**
- Memory: **2.29 GB** (iOS jetsam kills at ~2.5 GB)
- Cache eviction: **Working correctly** (10 evictions logged)
- Memory **NOT released** despite evictions
- Pattern: Stays 1.9-2.3 GB throughout playback

**What's NOT the problem:**
- ✅ Alignment is FAST (included in synthesis time)
- ✅ Cache size is small (~25 MB for 2 paragraphs)
- ✅ Eviction logic works

**What IS the problem:**
- ❌ **~2.26 GB unaccounted memory** (not in our caches!)
- Likely: ONNX runtime, framework buffers, or Swift retain cycles

---

## 🎯 Next Session: Priority 0 - Find the Memory Leak

### Option A: Use New Memory Breakdown Logs

**Steps:**
1. Run app, play 10 paragraphs
2. Check logs for `📊 [MEMORY]` entries (every 5 paragraphs)
3. Look for pattern:
   ```
   📊 [MEMORY] Total: 2290.0 MB
   📊 [MEMORY] Audio cache: 2 entries, 25.3 MB
   📊 [MEMORY] Alignment cache: 2 entries, ~0.2 MB estimated
   📊 [MEMORY] Unaccounted: ~2264.5 MB ← THIS IS THE LEAK!
   ```

**Questions to answer:**
- Does "Unaccounted" grow with each paragraph?
- Does it plateau or keep growing?
- What's the minimum "Unaccounted" value (baseline frameworks)?

### Option B: Profile with Xcode Instruments (Recommended)

**Steps:**
1. Open Xcode
2. Product → Profile (⌘I)
3. Select "Allocations" template
4. Click Record
5. In app: Play 5-10 paragraphs
6. Stop recording
7. Click "Allocations" in left sidebar
8. Sort by "Persistent Bytes" (descending)

**What to look for:**
- Large allocations >100 MB
- Types to check:
  - `Data` (audio buffers)
  - `SherpaOnnx*` (ONNX sessions)
  - `Array` / `Dictionary` (caches)
  - `CFData` / `NSData` (C++ allocations)
  - `String` (phoneme/alignment data)

**Screenshot areas:**
- "All Heap & Anonymous VM" view
- Top 10 allocations by size
- Call trees for large allocations

---

## 🔍 Hypotheses to Test

### Hypothesis 1: ONNX Runtime Not Releasing Memory
**Test:**
- Check if memory drops when you call `stop()` (clears queue)
- Profile sherpa-onnx C++ allocations in Instruments

**If true:**
- May need to recreate ONNX sessions periodically
- Or call explicit cleanup after synthesis

### Hypothesis 2: Audio Data Retained Elsewhere
**Test:**
- Check if AudioPlayer is holding references to old Data
- Look for retain cycles in closures (`[weak self]`)

**If true:**
- Add explicit `nil` assignments after playback
- Check AudioPlayer implementation for leaks

### Hypothesis 3: Alignment Service Memory Accumulation
**Test:**
- Disable alignment temporarily (comment out `performAlignment()`)
- Check if memory stays low

**If true:**
- PhonemeAlignmentService cache (maxSize=100) might be issue
- Or NeMo model staying loaded in memory

---

## 📊 Quick Memory Test Script

**If you want data before next session:**

```bash
# Run app, play paragraphs, save logs
# Then analyze:

cd /Users/zachswift/projects/Listen2

# Extract memory breakdown logs
grep "📊 \[MEMORY\]" /path/to/new/logs.txt

# Count cache evictions (should see many)
grep "Evicted" /path/to/new/logs.txt | wc -l

# Track memory over time
grep "final memory:" /path/to/new/logs.txt | awk '{print $NF}'
```

---

## 🚧 What NOT to Do Yet

**Don't implement the streaming plan yet:**
- Memory leak will make streaming worse (more buffers in memory)
- Fix memory first, then add streaming
- Streaming is great, but needs stable foundation

**Don't add timeouts:**
- Alignment is fast (you were right!)
- "73.65s" in logs is AUDIO DURATION, not computation time
- Timeout would just break it

**Don't optimize alignment:**
- It's already fast enough
- Real issue is memory, not speed

---

## 📁 Key Files Modified

**SynthesisQueue.swift:**
- Lines 38-39: Added `synthesisWaitQueue` for atomic lock
- Lines 194-215: `acquireSynthesisLock()` / `releaseSynthesisLock()`
- Lines 409-427: New `logMemoryBreakdown()` method
- Lines 164-166: Auto-log every 5 paragraphs

**TTSService.swift:**
- Lines 343-380: Fixed skip buttons with `stopAudioOnly()`
- Updated all SynthesisQueue calls to use `await`

---

## 🎯 Success Criteria for Next Session

**Minimum (Must Have):**
- [ ] Identify what's consuming 2.26 GB
- [ ] Understand if it's leaking or just baseline
- [ ] Have hypothesis for root cause

**Ideal (Nice to Have):**
- [ ] Memory drops below 1 GB
- [ ] Confirmed source of leak
- [ ] Plan for fix

**Stretch Goal:**
- [ ] Memory drops below 500 MB
- [ ] Leak fixed completely

---

## 💡 Quick Wins to Try

**Before profiling, try these quick tests:**

1. **Test memory without alignment:**
   ```swift
   // In performAlignment(), comment out line 319-351
   // Just skip alignment entirely
   // Does memory stay low?
   ```

2. **Test with smaller cache:**
   ```swift
   // In SynthesisQueue.swift line 20:
   private let maxCacheSize: Int = 1  // Was 2
   ```

3. **Force garbage collection after eviction:**
   ```swift
   // After evictOldCacheEntries() line 383:
   cache.removeAll(keepingCapacity: false)  // Add this
   alignments.removeAll(keepingCapacity: false)  // Add this
   ```

---

## 🔗 Related Documents

- **Previous handoff:** `docs/HANDOFF_2025-11-15_CPU_MEMORY_OPTIMIZATION.md`
- **Performance plan:** `docs/plans/2025-11-14-tts-performance-optimization.md`
- **Workshop history:** `workshop context` (comprehensive session tracking)

---

## 📞 Questions for User (If Needed)

1. **What's acceptable memory usage?**
   - iOS typically kills apps at ~2.5 GB
   - Ideal: <500 MB for TTS
   - Acceptable: <1 GB

2. **How many paragraphs do you typically read?**
   - Helps determine if leak is per-paragraph or baseline
   - Affects whether we need aggressive eviction or leak fix

3. **Have you seen crashes from memory pressure?**
   - iOS shows jetsam crash reports
   - Would confirm 2.29 GB is approaching limit

---

**Next session start with:** Run app → Play 10 paragraphs → Check `📊 [MEMORY]` logs → Analyze pattern

**If logs show leak:** Profile with Instruments to find source

**If logs show stable:** Maybe 2 GB is just baseline for ONNX + frameworks (unlikely but possible)

---

**End of Handoff**

*Built successfully. Ready to test. Logs will show memory breakdown every 5 paragraphs.*
