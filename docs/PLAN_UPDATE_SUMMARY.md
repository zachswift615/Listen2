# Implementation Plan Update - ONNX Streaming Integration

**Date:** 2025-11-14
**Status:** Plan updated to integrate native ONNX streaming callbacks

---

## What Changed

### Added Tasks (Phase 2)

**Task 7: Add Streaming Callbacks to sherpa-onnx C API** (NEW)
- Add `SherpaOnnxGeneratedAudioCallback` typedef to C API
- Add `SherpaOfflineTtsGenerateWithCallback()` function
- Bridge C++ `GeneratedAudioCallback` to C function pointer
- Rebuild iOS framework with callback support

**Task 8: Bridge ONNX Callbacks to Swift** (NEW)
- Create `SynthesisStreamDelegate` protocol
- Implement `synthesizeWithStreaming()` in SherpaOnnx.swift
- Bridge C callbacks to Swift closures
- Add comprehensive test suite

**Task 10: ENHANCED** - Now integrates callbacks with async synthesis
- Use ONNX callbacks for real-time progress
- Use Swift async Tasks for parallel synthesis
- **Result: Zero gaps + streaming progress!**

### Key Architecture Changes

**Before:**
```
Sequential synthesis:
Sentence 1 → synthesize (10s) → play → Sentence 2 → synthesize (10s) → play
                                  ↑ 
                            Gap here!
```

**After:**
```
Parallel synthesis with streaming:
t=0s:  Launch async synthesis for ALL sentences (parallel)
       Sentence 1 ┐
       Sentence 2 ├─ All synthesizing at once
       Sentence 3 ┘

t=10s: Callback fires → Sentence 1 ready → START PLAYING
       (Sentences 2 & 3 still synthesizing in background)

t=20s: Sentence 1 finishes playing
       Sentence 2 already done via callback → NO GAP!

t=30s: Sentence 2 finishes
       Sentence 3 already done via callback → NO GAP!
```

## Updated Metrics

- ✅ Time-to-first-audio < 10 seconds (unchanged)
- ✅ **Zero gaps between sentences** (NEW - via parallel synthesis)
- ✅ **Real-time streaming progress** (NEW - via ONNX callbacks)
- ✅ Paragraph transitions < 1 second (unchanged)

## Updated Timeline

- Phase 1: 4-6 hours (unchanged)
- Phase 2: 10-14 hours (+2-4 hours for ONNX callback tasks)
- Phase 3: 4-6 hours (unchanged)
- **Total: 18-26 hours** (was 16-24 hours)

**Net impact:** +2-4 hours for significantly better UX

## Why This Matters

### Without ONNX Callbacks (Original Plan)
- Swift polls cache to check if synthesis done
- No real-time progress updates during synthesis
- 1-2 second gaps between sentences (sequential synthesis)

### With ONNX Callbacks (Updated Plan)
- Native C++ callbacks fire as soon as audio ready
- Real-time progress during synthesis (0.0 to 1.0)
- Zero gaps (parallel synthesis + immediate streaming)
- Can cancel synthesis mid-way (return 0 from callback)

## Technical Details

**sherpa-onnx already supports this!**

Location: `sherpa-onnx/csrc/offline-tts.h:79-80`

```cpp
using GeneratedAudioCallback = std::function<int32_t(
    const float * /*samples*/, 
    int32_t /*n*/, 
    float /*progress*/
)>;
```

It's just not exposed to the C API or Swift - we're fixing that!

## Files Modified

**New files:**
- `sherpa-onnx/c-api/c-api.h` (callback typedef)
- `sherpa-onnx/c-api/c-api.cc` (callback bridge)
- `Listen2/.../SynthesisStreamDelegate.swift` (Swift protocol)
- `Listen2/.../StreamingCallbackTests.swift` (tests)

**Modified files:**
- `SherpaOnnx.swift` (add synthesizeWithStreaming)
- `PiperTTSProvider.swift` (expose streaming)
- `SynthesisQueue.swift` (integrate callbacks + async)

## Execution Notes

When running with `superpowers:executing-plans` or `superpowers:subagent-driven-development`:

1. **Phase 1 (Tasks 1-5):** Unchanged - proceed as planned
2. **Phase 2 (Tasks 6-13):** Execute in order - callbacks before async integration
3. **Phase 3 (Tasks 14-18):** Unchanged - proceed as planned

**Critical dependency:** Task 10 requires Tasks 7-9 complete (callbacks must exist before async integration uses them)

---

**Plan file:** `/Users/zachswift/projects/Listen2/docs/plans/2025-11-14-tts-performance-optimization.md`
