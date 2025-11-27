# w_ceil Tensor Analysis - Phoneme Duration Extraction from Piper VITS

**Date:** 2025-11-14
**Purpose:** Technical documentation for extracting real phoneme durations from VITS w_ceil tensor
**Target Model:** Piper VITS (en_US-amy-medium.onnx)

---

## Executive Summary

The w_ceil tensor is the **second output** (index 1) from Piper VITS ONNX models and contains the **exact phoneme durations in sample counts**. This tensor is currently extracted and stored in the sherpa-onnx framework but is NOT yet exposed through the C API to Swift. This document details the tensor structure, location in the codebase, and format for implementing accurate word-level highlighting.

**Key Finding:** The durations ARE being extracted (lines 492-508 in offline-tts-vits-impl.h) and stored in `GeneratedAudio.phoneme_durations`, but the C API bridge does NOT expose this field to Swift.

---

## 1. Tensor Location in ONNX Inference

### 1.1 Model Inference Points

The ONNX inference happens in three separate Run methods depending on model type:

#### **For Piper/Coqui Models** (Most Common)
**File:** `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-model.cc`
**Function:** `RunVitsPiperOrCoqui()`
**Lines:** 272-280

```cpp
auto out = sess_->Run({},
    input_names_ptr_.data(),
    inputs.data(),
    inputs.size(),
    output_names_ptr_.data(),
    output_names_ptr_.size()
);

// Return both audio and phoneme durations (w_ceil) if available
if (out.size() > 1) {
    return VitsOutput(std::move(out[0]), std::move(out[1]));
}
return VitsOutput(std::move(out[0]));
```

**Output Structure:**
- `out[0]` = audio samples tensor (shape: [1, num_samples])
- `out[1]` = **w_ceil tensor** (shape: [num_phonemes]) - phoneme durations

#### **For Standard VITS Models**
**File:** Same as above
**Function:** `RunVits()`
**Lines:** 334-342

Same structure - returns both audio and w_ceil if available.

#### **For MeloTTS Models** (With Tones)
**File:** Same as above
**Function:** `Run(Ort::Value x, Ort::Value tones, ...)`
**Lines:** 111-119

Same structure - returns both audio and w_ceil if available.

---

## 2. Tensor Data Type and Shape

### 2.1 Current Implementation

**File:** `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h`
**Function:** `Process()`
**Lines:** 492-508

```cpp
// Extract phoneme durations (w_ceil tensor) if available
if (vits_output.phoneme_durations) {
    try {
        auto durations_shape = vits_output.phoneme_durations.GetTensorTypeAndShapeInfo().GetShape();
        int64_t num_phonemes = durations_shape[0];
        const int64_t* duration_data = vits_output.phoneme_durations.GetTensorData<int64_t>();

        ans.phoneme_durations.reserve(num_phonemes);
        for (int64_t i = 0; i < num_phonemes; i++) {
            // Multiply by 256 to get actual sample counts (per Piper VITS implementation)
            ans.phoneme_durations.push_back(static_cast<int32_t>(duration_data[i] * 256));
        }
    } catch (...) {
        // If extracting durations fails, leave the vector empty
        ans.phoneme_durations.clear();
    }
}
```

### 2.2 Tensor Specifications

| Property | Value | Notes |
|----------|-------|-------|
| **Output Index** | 1 (second output) | First output (index 0) is audio samples |
| **Shape** | `[num_phonemes]` | 1D tensor, one value per phoneme |
| **Data Type** | `int64_t` | Integer values representing frame counts |
| **Value Format** | **Frame counts** (NOT log-scale) | Already converted from log-scale by ONNX model |
| **Scaling** | Multiply by 256 | To get actual audio sample counts |

**IMPORTANT DISCOVERY:** The current code multiplies by 256, suggesting the w_ceil values are **frame counts**, not log-scale values. The ONNX model likely already applies exp() internally.

---

## 3. Value Interpretation and Conversion

### 3.1 From w_ceil to Seconds

```cpp
// Given w_ceil tensor value at index i
int64_t frame_count = duration_data[i];

// Convert to sample count
int32_t sample_count = frame_count * 256;  // Frame shift = 256 samples

// Convert to seconds
float duration_seconds = sample_count / 22050.0f;  // Sample rate = 22050 Hz
```

### 3.2 Example Calculation

```
w_ceil[0] = 4 (frames)
sample_count = 4 * 256 = 1024 samples
duration_seconds = 1024 / 22050 = 0.0464 seconds (46.4ms)
```

### 3.3 Expected Duration Ranges

| Phoneme Type | Typical Duration | Frame Count Range |
|--------------|------------------|-------------------|
| Vowels | 60-120ms | 5-10 frames |
| Consonants (stops) | 20-50ms | 2-4 frames |
| Consonants (fricatives) | 80-150ms | 7-13 frames |
| Silence/pause | 100-300ms | 9-26 frames |

---

## 4. Current Status in sherpa-onnx

### 4.1 What's Already Implemented

✅ **VITS Model Outputs w_ceil:**
- The ONNX model returns multiple outputs
- Second output (index 1) is captured as `phoneme_durations`

✅ **C++ Extraction:**
- `OfflineTtsVitsModel::Run()` returns `VitsOutput` with both audio and phoneme_durations
- `offline-tts-vits-impl.h` Process() method extracts durations and stores in `GeneratedAudio.phoneme_durations`

✅ **Data Structure:**
- `GeneratedAudio` struct (line 57-69 in offline-tts.h) has `phoneme_durations` field:
```cpp
struct GeneratedAudio {
    std::vector<float> samples;
    int32_t sample_rate;
    std::vector<int32_t> phoneme_durations;  // w_ceil tensor: sample count per phoneme
    PhonemeSequence phonemes;
};
```

### 4.2 What's Missing - The Critical Gap

❌ **C API Does NOT Expose Durations:**
The C API struct `SherpaOnnxGeneratedAudio` (in c-api.h) does NOT have a `phoneme_durations` field.

**Current C API Structure** (approximate location: sherpa-onnx/c-api/c-api.h ~line 350-380):
```c
typedef struct SherpaOnnxGeneratedAudio {
    const float *samples;
    int32_t n;
    float sample_rate;

    int32_t num_phonemes;
    const char *const *phoneme_symbols;
    const int32_t *phoneme_char_start;
    const int32_t *phoneme_char_length;

    // MISSING: const int32_t *phoneme_durations;
} SherpaOnnxGeneratedAudio;
```

❌ **Swift Cannot Access Durations:**
Since the C API doesn't expose durations, Swift code in `SherpaOnnx.swift` cannot read them.

---

## 5. Implementation Path to Swift

### 5.1 Data Flow Architecture

```
┌─────────────────────┐
│  ONNX Model Output  │
│   out[0]: audio     │
│   out[1]: w_ceil    │ ← Second tensor output
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────┐
│   VitsOutput (C++)          │
│   - audio: Ort::Value       │
│   - phoneme_durations:      │ ← Captured here ✅
│     Ort::Value              │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  GeneratedAudio (C++)       │
│  - samples: vector<float>   │
│  - sample_rate: int32_t     │
│  - phoneme_durations:       │ ← Extracted here ✅
│    vector<int32_t>          │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  C API (c-api.h/cc)         │
│  SherpaOnnxGeneratedAudio   │
│  - samples                  │
│  - sample_rate              │
│  - phoneme_durations        │ ← MISSING ❌
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Swift (SherpaOnnx.swift)   │
│  PhonemeInfo struct         │
│  - duration: TimeInterval   │ ← Cannot populate ❌
└─────────────────────────────┘
```

### 5.2 Required Changes (Summary)

**Phase 1: C API Modification**
1. Add `const int32_t *phoneme_durations` to `SherpaOnnxGeneratedAudio` struct
2. Populate this field in `SherpaOnnxOfflineTtsGenerate()` function
3. Ensure memory management (allocation/deallocation)

**Phase 2: Swift Integration**
1. Read `phoneme_durations` pointer from C API struct
2. Convert int32_t sample counts to TimeInterval (seconds)
3. Populate `PhonemeInfo.duration` with real values instead of 0.05 estimate

---

## 6. Verification Strategy

### 6.1 Debug Logging Points

Add logging at each stage to verify data flow:

**C++ Model Level:**
```cpp
// In offline-tts-vits-model.cc, RunVitsPiperOrCoqui()
SHERPA_ONNX_LOGE("[VITS] ONNX returned %zu outputs", out.size());
if (out.size() > 1) {
    auto shape = out[1].GetTensorTypeAndShapeInfo().GetShape();
    SHERPA_ONNX_LOGE("[VITS] w_ceil tensor shape: [%lld]", shape[0]);
}
```

**C++ Extraction Level:**
```cpp
// In offline-tts-vits-impl.h, Process()
SHERPA_ONNX_LOGE("[VITS] Extracted %zu phoneme durations", ans.phoneme_durations.size());
if (!ans.phoneme_durations.empty()) {
    SHERPA_ONNX_LOGE("[VITS] First 3 durations: %d, %d, %d samples",
        ans.phoneme_durations[0],
        ans.phoneme_durations[1],
        ans.phoneme_durations[2]);
}
```

**C API Level:**
```c
// In c-api.cc, SherpaOnnxOfflineTtsGenerate()
fprintf(stderr, "[C_API] Exposing %d phoneme durations\n", audio.phoneme_durations.size());
```

**Swift Level:**
```swift
// In SherpaOnnx.swift, extractPhonemes()
if let durationsPtr = audio.pointee.phoneme_durations {
    print("[Swift] First phoneme duration: \(durationsPtr[0]) samples = \(TimeInterval(durationsPtr[0]) / 22050.0)s")
}
```

### 6.2 Validation Tests

**Test 1: Duration Count Matches Phoneme Count**
```swift
assert(phonemes.count == durationCount, "Mismatch between phoneme and duration counts")
```

**Test 2: Total Duration Matches Audio Length**
```swift
let totalDuration = phonemes.reduce(0.0) { $0 + $1.duration }
let audioDuration = Double(audioData.count) / (2 * 22050)  // 16-bit samples
assert(abs(totalDuration - audioDuration) < 0.1, "Duration mismatch > 100ms")
```

**Test 3: Individual Durations Are Reasonable**
```swift
for phoneme in phonemes {
    assert(phoneme.duration > 0.01 && phoneme.duration < 0.5,
           "Phoneme duration out of range: \(phoneme.duration)")
}
```

---

## 7. Known Issues and Gotchas

### 7.1 Frame Shift Constant

The current code uses `* 256` to convert frame counts to sample counts. This is based on:
- Piper VITS uses a hop length of 256 samples
- At 22050 Hz sample rate: 256 samples = ~11.6ms per frame

**Verification needed:** Confirm this is correct for all Piper models, or if it varies by model.

### 7.2 Data Type Assumptions

Current code assumes `int64_t` from ONNX, but stores as `int32_t` in GeneratedAudio:
```cpp
const int64_t* duration_data = vits_output.phoneme_durations.GetTensorData<int64_t>();
ans.phoneme_durations.push_back(static_cast<int32_t>(duration_data[i] * 256));
```

**Potential issue:** Values could overflow if frame count > 8,388,607 (which would be ~93 seconds per phoneme - unlikely but possible).

### 7.3 Log-Scale vs Frame Count

The plan document mentions "log-scale" but the current implementation treats values as raw frame counts. Need to verify:
- Does the ONNX model output log-scale values that need exp()?
- Or does it output frame counts directly?

**Current assumption:** Frame counts directly (no exp() needed).

### 7.4 Alignment with Phoneme Symbols

The durations must align 1:1 with the phoneme symbols returned by espeak-ng. Misalignment causes:
- Wrong word boundaries
- Incorrect highlighting timing
- Possible crashes from array index mismatches

**Critical check:** `phoneme_durations.size() == phonemes.size()` must always be true.

---

## 8. Next Steps (Task 2 Preview)

Once this documentation is complete, Task 2 will:

1. Add `const int32_t *phoneme_durations` to C API struct
2. Allocate and populate the array in c-api.cc
3. Handle memory cleanup in `SherpaOnnxDestroyOfflineTtsGeneratedAudio()`
4. Write test to verify C API exposes durations correctly

---

## 9. References

### Codebase Files
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-model.h` - VitsOutput struct definition
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-model.cc` - ONNX inference and output extraction
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h` - Duration extraction from VitsOutput
- `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts.h` - GeneratedAudio struct with phoneme_durations field

### External References
- Piper TTS: https://github.com/rhasspy/piper
- VITS Paper: https://arxiv.org/abs/2106.06103
- ONNX Runtime: https://onnxruntime.ai/

---

## Appendix A: Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│ w_ceil Tensor Quick Reference                               │
├─────────────────────────────────────────────────────────────┤
│ Location:     ONNX output[1] (second tensor)                │
│ Shape:        [num_phonemes]                                │
│ Data Type:    int64_t (from ONNX) → int32_t (in C++)        │
│ Format:       Frame counts (NOT log-scale)                  │
│ Conversion:   frames * 256 / 22050 = seconds                │
│ Status:       ✅ Extracted in C++, ❌ NOT in C API/Swift     │
├─────────────────────────────────────────────────────────────┤
│ Example:                                                    │
│   w_ceil[i] = 4 frames                                      │
│   samples = 4 * 256 = 1024 samples                          │
│   duration = 1024 / 22050 = 0.046 seconds (46ms)            │
└─────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Last Updated:** 2025-11-14
**Next Review:** After Task 2 completion (C API exposure)
