# Session Handoff: Memory Profiling - Next Steps

**Date:** 2025-11-15  
**Status:** ✅ Concurrency Fixed | ⚠️ Memory Leak (2.29 GB)  
**Next:** Profile memory with logs or Instruments

---

## ✅ Fixed This Session

**Concurrency (CPU 476% → ~100%):**
- Fixed defer bug releasing gate immediately
- Atomic lock with continuation queue  
- Actor conversion for thread safety

**Playback:**
- getAudio() waits for pre-synthesis (no more nil errors)
- Skip buttons work (added stopAudioOnly())

**Memory Profiling:**
- Added logMemoryBreakdown() - auto-logs every 5 paragraphs
- Shows: total, audio cache, alignment cache, unaccounted

---

## ⚠️ Critical: 2.29 GB Memory Leak

**Evidence:**
- Memory: 2.29 GB (jetsam at ~2.5 GB)
- Cache: ~25 MB (working correctly)
- **Unaccounted: ~2.26 GB** ← THE LEAK

**Next Steps:**

1. **Check logs** - Run app, play 10 paragraphs, grep for:
   ```bash
   grep "📊 \[MEMORY\]" logs.txt
   ```

2. **Profile with Instruments:**
   - Product → Profile (⌘I)
   - Allocations template
   - Play 5-10 paragraphs
   - Sort by "Persistent Bytes"
   - Look for: Data, SherpaOnnx*, Array, CFData

3. **Test hypotheses:**
   - ONNX runtime not releasing?
   - Audio data retained?  
   - Alignment service accumulating?

**Quick wins to try:**
- Disable alignment (test if memory stays low)
- Reduce maxCacheSize to 1
- Add keepingCapacity: false to removeAll()

---

## 📊 What Logs Will Show

```
📊 [MEMORY] Total: 2290.0 MB
📊 [MEMORY] Audio cache: 2 entries, 25.3 MB  
📊 [MEMORY] Alignment cache: 2 entries, ~0.2 MB
📊 [MEMORY] Unaccounted: ~2264.5 MB ← Find this!
```

If "Unaccounted" grows → leak  
If stable → baseline (unlikely)

---

## 📁 Files Modified

- **SynthesisQueue.swift**: Atomic lock, memory logging
- **TTSService.swift**: stopAudioOnly(), await fixes

See commit: `fix: critical concurrency and playback bugs`

---

**Start next session:** Run app → Check memory logs → Profile if needed
