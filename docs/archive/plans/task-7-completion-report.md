# Task 7 Completion Report: Streaming Callbacks in sherpa-onnx C API

**Date:** 2025-11-15
**Task:** Task 7 from `docs/plans/2025-11-14-tts-performance-optimization.md`
**Status:** ALREADY COMPLETE (No implementation needed)

## Summary

Task 7 required adding streaming callback support to the sherpa-onnx C API. Upon investigation, **this functionality already exists** in the sherpa-onnx codebase and has been present since March-August 2024.

## Verification Evidence

### 1. Callback Typedefs (c-api.h)

**Location:** `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.h`

Found 4 callback typedefs (lines 1111-1122):
```c
typedef int32_t (*SherpaOnnxGeneratedAudioCallback)(const float *samples, int32_t n);
typedef int32_t (*SherpaOnnxGeneratedAudioCallbackWithArg)(const float *samples, int32_t n, void *arg);
typedef int32_t (*SherpaOnnxGeneratedAudioProgressCallback)(const float *samples, int32_t n, float p);
typedef int32_t (*SherpaOnnxGeneratedAudioProgressCallbackWithArg)(const float *samples, int32_t n, float p, void *arg);
```

### 2. Function Declarations (c-api.h)

Found 4 callback-enabled generation functions (lines 1155-1176):
- `SherpaOnnxOfflineTtsGenerateWithCallback`
- `SherpaOnnxOfflineTtsGenerateWithProgressCallback`
- `SherpaOnnxOfflineTtsGenerateWithProgressCallbackWithArg`
- `SherpaOnnxOfflineTtsGenerateWithCallbackWithArg`

### 3. Implementations (c-api.cc)

**Location:** `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.cc`

All 4 functions are fully implemented (lines 1386-1427):
- Each bridges C callbacks to C++ `GeneratedAudioCallback`
- Properly wraps callbacks with lambda functions
- Calls internal `SherpaOnnxOfflineTtsGenerateInternal` with callback

### 4. C++ API Support (offline-tts.h)

**Location:** `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts.h`

C++ `OfflineTts::Generate()` method supports callbacks (lines 79-105):
```cpp
using GeneratedAudioCallback = std::function<int32_t(
    const float * /*samples*/, int32_t /*n*/, float /*progress*/)>;

GeneratedAudio Generate(const std::string &text, int64_t sid = 0,
                        float speed = 1.0,
                        GeneratedAudioCallback callback = nullptr) const;
```

### 5. iOS Framework Export

**Verified in:** `build-ios/sherpa-onnx.xcframework/`

Headers confirmed present in both architectures:
- `ios-arm64_x86_64-simulator/Headers/sherpa-onnx/c-api/c-api.h`
- `ios-arm64/Headers/sherpa-onnx/c-api/c-api.h`

Binary symbols verified with `nm`:
```
$ nm build-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a | grep SherpaOnnxOfflineTtsGenerateWithCallback
0000000000004bac T _SherpaOnnxOfflineTtsGenerateWithCallback
0000000000004e34 T _SherpaOnnxOfflineTtsGenerateWithCallbackWithArg
```

### 6. Listen2 Project Framework

**Verified in:** `/Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework`

- Framework last updated: Nov 15, 2025 10:56
- Callbacks present in headers: ✅
- Symbols exported in binary: ✅

## Historical Context

Git history shows callback support was added in 2024:
- **Mar 9, 2024:** "Support user provided data in tts callback" (#653)
- **Mar 28, 2024:** "Added progress for callback of tts generator" (#712)
- **Aug 5, 2024:** "Support passing TTS callback in Swift API" (#1218)
- **May 14, 2025:** "Add Go implementation of the TTS generation callback" (#2213)

## Functionality Available

The existing implementation provides:

1. **Basic callback:** Audio chunks without progress
2. **Progress callback:** Audio chunks with synthesis progress (0.0-1.0)
3. **User data variants:** Both callback types with `void *arg` for context
4. **Sentence-level streaming:** Callbacks fired after `max_num_sentences` processed
5. **Cancellation support:** Return 0 from callback to stop synthesis

## Implementation Details

The callback signature includes:
- `samples`: Pointer to audio samples (float array)
- `n`: Number of samples
- `progress`: Synthesis progress (0.0 to 1.0) - available in Progress variants
- `arg`: User-provided context pointer - available in WithArg variants

The callback is invoked after processing `config.max_num_sentences` sentences, allowing sentence-by-sentence streaming to the caller.

## Next Steps

Since Task 7 is already complete:

1. **No code changes needed** in sherpa-onnx C API
2. **No iOS framework rebuild needed** (already up to date)
3. **Proceed to Task 8:** Bridge these EXISTING callbacks to Swift
4. **Note:** Task 8 may also already have Swift bindings (commit #1218 mentions Swift API support)

## Task 7 Requirements vs. Reality

| Requirement | Status | Location |
|-------------|--------|----------|
| Add callback typedef to c-api.h | ✅ Already exists | Lines 1111-1122 |
| Add callback parameter to generation function | ✅ Already exists | Lines 1155-1176 |
| Implement callback bridge in c-api.cc | ✅ Already exists | Lines 1386-1427 |
| Build sherpa-onnx with callback support | ✅ Already built | Verified with nm |
| Rebuild iOS framework with callbacks | ✅ Already rebuilt | Updated Nov 15 10:56 |
| Commit changes | ❌ Not needed | No changes made |

## Conclusion

**Task 7 requires ZERO implementation work.** The streaming callback infrastructure that the plan calls for has existed in sherpa-onnx since March 2024, and is already present in:
- The sherpa-onnx source code
- The compiled iOS framework in sherpa-onnx/build-ios/
- The Listen2 project's Frameworks directory

The plan appears to have been written without checking the current state of sherpa-onnx. This is actually **good news** - we get the callback infrastructure for free and can proceed directly to using it in Swift (Task 8).

## Recommendations

1. **Skip to Task 8** - Bridge the existing callbacks to Swift
2. **Verify Task 8 status** - Check if Swift bindings already exist (commit #1218)
3. **Update the plan** - Note that Tasks 7 is already complete
4. **Consider** - The plan may be based on outdated assumptions about sherpa-onnx capabilities
