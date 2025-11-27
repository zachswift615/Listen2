# sherpa-onnx Modifications for Phoneme Durations

**Date**: 2025-11-12
**Status**: Research Complete - Ready for Implementation

## Key Findings

### 1. ONNX Model Output Structure

**Current Behavior**:
- ONNX session `Run()` returns ALL model outputs in array
- Code only uses `out[0]` (audio samples)
- Additional outputs (like durations) are discarded

**Piper VITS Model Outputs** (from GitHub issue #425):
- Output 0: Audio samples (float array)
- Output 1: `w_ceil` tensor (int array of phoneme sample counts) - **This is what we need!**

### 2. Exact Code Changes Needed

#### File: `sherpa-onnx/csrc/offline-tts-vits-model.h`

**Current return type**:
```cpp
Ort::Value Run(Ort::Value x, int64_t sid = 0, float speed = 1.0);
```

**New return type**:
```cpp
struct VitsOutput {
  Ort::Value audio;
  Ort::Value phoneme_durations;  // w_ceil tensor
};

VitsOutput Run(Ort::Value x, int64_t sid = 0, float speed = 1.0);
```

#### File: `sherpa-onnx/csrc/offline-tts-vits-model.cc`

**Current** (lines 48-54):
```cpp
auto out = sess_->Run({}, input_names_ptr_.data(), inputs.data(), 
                      inputs.size(), output_names_ptr_.data(), 
                      output_names_ptr_.size());
return std::move(out[0]);  // Only audio
```

**New**:
```cpp
auto out = sess_->Run({}, input_names_ptr_.data(), inputs.data(), 
                      inputs.size(), output_names_ptr_.data(), 
                      output_names_ptr_.size());

VitsOutput result;
result.audio = std::move(out[0]);

if (out.size() > 1) {
  result.phoneme_durations = std::move(out[1]);  // w_ceil tensor
}

return result;
```

#### File: `sherpa-onnx/csrc/offline-tts-vits-impl.h`

**Current** (line ~360):
```cpp
audio = model_->Run(std::move(x_tensor), sid, speed);
```

**New**:
```cpp
auto vits_output = model_->Run(std::move(x_tensor), sid, speed);
audio = std::move(vits_output.audio);

// Extract phoneme durations
std::vector<int32_t> phoneme_durations;
if (vits_output.phoneme_durations) {
  auto shape = vits_output.phoneme_durations.GetTensorTypeAndShapeInfo().GetShape();
  const int64_t* duration_data = vits_output.phoneme_durations.GetTensorData<int64_t>();
  int64_t num_phonemes = shape[0];
  
  phoneme_durations.reserve(num_phonemes);
  for (int64_t i = 0; i < num_phonemes; i++) {
    // Multiply by 256 to get actual sample counts (per GitHub issue #425)
    phoneme_durations.push_back(static_cast<int32_t>(duration_data[i] * 256));
  }
}
```

**Update GeneratedAudio struct**:
```cpp
struct GeneratedAudio {
  int32_t sample_rate;
  std::vector<float> samples;
  std::vector<int32_t> phoneme_durations;  // NEW: samples per phoneme
};

// Store in GeneratedAudio
ans.phoneme_durations = std::move(phoneme_durations);
```

### 3. C API Bridge

#### File: `sherpa-onnx/c-api/c-api.h`

**Current struct**:
```c
typedef struct SherpaOnnxGeneratedAudio {
  const float* samples;
  int32_t n;
  int32_t sample_rate;
} SherpaOnnxGeneratedAudio;
```

**New struct**:
```c
typedef struct SherpaOnnxGeneratedAudio {
  const float* samples;
  int32_t n;
  int32_t sample_rate;
  const int32_t* phoneme_durations;  // NEW
  int32_t num_phonemes;              // NEW
} SherpaOnnxGeneratedAudio;
```

**Update allocation/deallocation functions** to handle new fields.

---

## Build Instructions

### Prerequisites
- macOS with Xcode Command Line Tools
- CMake 3.20+
- Python 3 (for model export if needed)

### Steps

1. **Fork and clone**:
```bash
cd ~/projects
git clone https://github.com/YOUR_USERNAME/sherpa-onnx.git
cd sherpa-onnx
git checkout -b feature/piper-phoneme-durations
```

2. **Apply modifications** (listed above)

3. **Build for iOS**:
```bash
./build-ios.sh
```

4. **Output location**:
```
build-ios-shared/install/sherpa-onnx.xcframework
```

5. **Replace in Listen2**:
```bash
cp -r build-ios-shared/install/sherpa-onnx.xcframework \
      ~/projects/Listen2/Frameworks/
```

---

## Verification Steps

### 1. Test Basic TTS Still Works

After rebuild, verify Piper TTS still synthesizes audio:

```swift
let audio = try await piperProvider.synthesize(text: "Hello world")
// Should produce audio without crashes
```

### 2. Test Phoneme Durations Are Returned

```swift
let (audio, phonemes) = try await piperProvider.synthesize(text: "Hello")
print("Audio samples: \(audio.count)")
print("Phoneme count: \(phonemes.count)")
print("Phonemes: \(phonemes)")
// Should print phoneme durations, e.g., [h: 1200 samples, ɛ: 800 samples, ...]
```

### 3. Validate Sample Counts

Sum of phoneme sample counts should approximately equal audio length:

```swift
let totalPhonemeSamples = phonemes.reduce(0) { $0 + $1.sampleCount }
let audioSamples = audio.count / MemoryLayout<Float>.size
assert(abs(totalPhonemeSamples - audioSamples) < 1000,  // Allow small variance
       "Phoneme samples don't match audio length")
```

---

## Risk Assessment

### Risk: Model doesn't output durations
**Likelihood**: Low (w_ceil is core to VITS)
**Mitigation**: Verify with a test inference first; re-export model if needed

### Risk: Build process fails
**Likelihood**: Medium (iOS builds can be tricky)
**Mitigation**: Use sherpa-onnx's existing `build-ios.sh` script, well-tested

### Risk: ABI incompatibility
**Likelihood**: Low
**Mitigation**: Full rebuild, not just linking against prebuilt

---

## Next Steps

1. ✅ Research complete - understand modifications needed
2. ⏭️ Fork sherpa-onnx repository
3. ⏭️ Apply C++ code changes
4. ⏭️ Build and test iOS framework
5. ⏭️ Update Swift bindings
6. ⏭️ Implement PhonemeAlignmentService

---

## Questions to Resolve

1. **Output tensor index**: Is `w_ceil` always output index 1? (Check model outputs)
2. **Data type**: Confirm `w_ceil` is int64 or float64
3. **Phoneme-to-token mapping**: How do we get the phoneme symbols corresponding to durations?
   - Need to also capture phoneme IDs from the model
   - Or use espeak-ng separately to get phoneme sequence

