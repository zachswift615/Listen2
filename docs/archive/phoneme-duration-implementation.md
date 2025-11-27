# Piper Phoneme Duration Implementation Plan

**Date**: 2025-11-12
**Author**: Claude Code + Zach Swift
**Goal**: Extract phoneme durations directly from Piper TTS instead of using ASR-based alignment

## Overview

Replace the current fragile approach (Text → Audio → ASR → DTW → Words) with direct phoneme duration extraction from Piper TTS (Text → Phonemes with Durations → Words).

## Current Architecture (TO BE REPLACED)

```
Text Input
  ↓
Piper TTS → Audio (WAV)
  ↓
NeMo CTC ASR → Token Timestamps
  ↓
DTW Alignment → Map tokens to VoxPDF words
  ↓
Word Timestamps (with bugs!)
```

**Problems**:
- 4 different representations (text, audio, ASR tokens, VoxPDF words)
- ASR tokenization doesn't match VoxPDF word boundaries
- Apostrophes, punctuation, Unicode cause crashes
- Complex index mapping between layers
- 44MB NeMo model needed

## New Architecture (TARGET)

```
Text Input
  ↓
Piper TTS → Audio + Phoneme Durations
  ↓
Phoneme-to-Word Mapper → Map durations to VoxPDF words
  ↓
Word Timestamps (clean!)
```

**Benefits**:
- 2 representations (text → phonemes → words)
- Direct relationship, no re-transcription
- Phonemes from espeak-ng match text exactly
- Simpler code, fewer edge cases
- No ASR model needed (-44MB)

---

## Part 1: sherpa-onnx Modifications

### Repository
- **Source**: https://github.com/k2-fsa/sherpa-onnx
- **Fork**: (TODO: Create fork)
- **Target Branch**: `feature/piper-phoneme-durations`

### Key Findings from Piper Issue #425

**The `w_ceil` Tensor**:
- Variable name: `w_ceil` (ceiling-rounded phoneme durations)
- Location: Generated in VITS model during inference
- Format: Tensor of integers (one per phoneme)
- Conversion: Multiply by 256 to get audio sample count

### Required Modifications

#### 1. ONNX Model Export (Piper Side)

**IF** we need to re-export models (check existing models first):

**File**: `piper/src/python/piper_train/vits/models.py`
**Change**: Line ~703, include `w_ceil` in model outputs

**File**: `piper/src/python/piper_train/export_onnx.py`
**Change**: Export `w_ceil` as additional output tensor

**Status**: Check if pre-trained Piper models already include this output

#### 2. sherpa-onnx C++ API

**File**: `sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h` (likely location)
**Changes needed**:
1. Modify ONNX session to handle multiple output tensors
2. Extract `w_ceil` tensor from model output
3. Multiply values by 256 to get sample counts
4. Store in struct alongside audio data

**Struct modification** (estimated):
```cpp
struct PiperTTSOutput {
  float* audio_samples;
  int32_t audio_length;
  int32_t* phoneme_samples;  // NEW: samples per phoneme
  int32_t phoneme_count;     // NEW: number of phonemes
};
```

#### 3. sherpa-onnx C API Bridge

**File**: `sherpa-onnx/sherpa-onnx/c-api/c-api.h`
**Changes needed**:
1. Add phoneme duration fields to C struct
2. Update generation function to populate these fields
3. Add cleanup for new fields

**C API struct** (estimated):
```c
typedef struct SherpaOnnxGeneratedAudio {
  const float* samples;
  int32_t n;
  int32_t sample_rate;
  const int32_t* phoneme_durations;  // NEW
  int32_t phoneme_count;             // NEW
} SherpaOnnxGeneratedAudio;
```

### Build Process

**Platforms needed**:
- iOS arm64 (iPhone/iPad)
- iOS Simulator x86_64/arm64 (Mac)

**Build steps** (from sherpa-onnx docs):
1. Clone fork
2. Install dependencies (cmake, xcode command line tools)
3. Build iOS frameworks:
   ```bash
   ./build-ios.sh
   ```
4. Build creates xcframeworks in `build-ios/install/`

**Output**: `sherpa-onnx.xcframework` (replace in Listen2/Frameworks/)

---

## Part 2: Swift Integration

### 1. Update Swift Bindings

**File**: `Listen2/Services/TTS/PiperTTSProvider.swift`

**Current** (returns audio only):
```swift
func synthesize(text: String) async throws -> Data
```

**New** (returns audio + phoneme durations):
```swift
func synthesize(text: String) async throws -> (audio: Data, phonemes: [PhonemeDuration])
```

**Struct**:
```swift
struct PhonemeDuration {
    let phoneme: String      // IPA symbol (from espeak-ng)
    let sampleCount: Int     // Audio samples for this phoneme
    let duration: TimeInterval  // Calculated: sampleCount / sampleRate
}
```

### 2. Create PhonemeAlignmentService

**New File**: `Listen2/Services/TTS/PhonemeAlignmentService.swift`

**Responsibilities**:
1. Convert text to phoneme sequence (via espeak-ng)
2. Match Piper's phoneme durations to espeak phoneme sequence
3. Accumulate phoneme durations to find word boundaries
4. Map to VoxPDF word positions
5. Return `AlignmentResult` (same structure as current ASR approach)

**Algorithm**:
```
Input:
  - text: "Hello world"
  - phonemeDurations: [h=0.1s, ə=0.05s, l=0.08s, oʊ=0.12s, ...]
  - voxPDFWords: [WordPosition("Hello", offset=0, len=5), ...]

Process:
  1. espeak-ng converts text → phoneme sequence with positions
     ["h", "ə", "l", "oʊ"] → "Hello" (chars 0-5)
     ["w", "ɝ", "l", "d"] → "world" (chars 6-11)

  2. Match Piper phoneme durations to espeak sequence
  3. Accumulate durations for each word
  4. Create WordTiming with accumulated start/duration

Output:
  - AlignmentResult with word timings
```

**Advantages over ASR approach**:
- Phonemes from espeak match Piper exactly (same engine)
- No tokenization mismatch
- Apostrophes/punctuation handled correctly
- Deterministic mapping

### 3. Update SynthesisQueue

**File**: `Listen2/Services/TTS/SynthesisQueue.swift`

**Changes**:
1. Replace `WordAlignmentService` with `PhonemeAlignmentService`
2. Pass phoneme durations from Piper to alignment service
3. Cache phoneme durations alongside audio

**Caching benefits**:
- Phoneme durations are deterministic per text/voice
- Can cache alongside audio
- No re-inference needed

---

## Part 3: Testing & Validation

### Test Cases

1. **Apostrophes**: "author's", "there's", "it's", "don't"
2. **Punctuation**: Em dashes (—), ellipsis (…), quotes ("")
3. **Multi-syllable**: "implementation", "simultaneously"
4. **Timing accuracy**: Compare to audio waveform

### Validation Metrics

- **Accuracy**: Word boundaries within 50ms of actual audio
- **Coverage**: 100% of words get timestamps (no skipped words)
- **Performance**: Alignment < 10ms per paragraph

### Regression Testing

- Keep test suite from ASR implementation
- Compare timing accuracy: phoneme vs ASR approach
- Verify no crashes on edge cases

---

## Part 4: Cleanup

### Code to Remove

**Delete entirely**:
- [ ] `WordAlignmentService.swift` (ASR-based alignment)
- [ ] `Listen2/Resources/ASRModels/` directory (44MB NeMo model)
- [ ] ASR initialization code in `TTSService.swift`
- [ ] DTW alignment functions
- [ ] All debug logging from ASR debugging session

**Keep**:
- [ ] `AlignmentResult.swift` (same structure, different source)
- [ ] `AlignmentCache.swift` (same caching mechanism)
- [ ] Word highlighting UI code (unchanged)

### Documentation Updates

- [ ] Update README.md (remove ASR mentions, add phoneme duration)
- [ ] Update architecture docs
- [ ] Add technical note about Piper modifications

---

## Implementation Timeline

### Week 1: sherpa-onnx Modifications
- [ ] Fork sherpa-onnx repository
- [ ] Locate Piper VITS implementation
- [ ] Identify exact code changes needed
- [ ] Modify C++ to expose `w_ceil` tensor
- [ ] Build iOS xcframework
- [ ] Verify Piper still synthesizes correctly

### Week 2: Swift Integration
- [ ] Create `PhonemeAlignmentService`
- [ ] Implement phoneme-to-word mapping
- [ ] Update `PiperTTSProvider` to use new API
- [ ] Update `SynthesisQueue` integration
- [ ] Initial testing with sample text

### Week 3: Testing & Cleanup
- [ ] Comprehensive testing (apostrophes, punctuation, etc.)
- [ ] Performance benchmarking
- [ ] Remove ASR code and models
- [ ] Update documentation
- [ ] Final validation

---

## Technical Risks & Mitigation

### Risk: sherpa-onnx C++ modifications complex
**Mitigation**: Start with simple proof-of-concept, consult GitHub issue #425

### Risk: Piper models don't include `w_ceil` output
**Mitigation**: Re-export one test model first, verify before full migration

### Risk: Phoneme-to-word mapping inaccurate
**Mitigation**: Extensive testing, fallback to character-based alignment if needed

### Risk: Build process for iOS xcframework unclear
**Mitigation**: sherpa-onnx has `build-ios.sh` script, well-documented

---

## Open Questions

1. **espeak-ng integration**: Piper already uses espeak-ng. Can we reuse the same instance?
2. **Phoneme format**: Verify IPA format matches between Piper output and espeak
3. **Model re-export**: Do existing Piper models include `w_ceil` output, or do we need to re-export?
4. **Multi-voice support**: Do phoneme durations vary significantly between voices for same text?

---

## Success Criteria

- ✅ No ASR model or inference needed
- ✅ Word highlighting works perfectly with apostrophes/punctuation
- ✅ Timing accuracy within 50ms
- ✅ App bundle size reduced by 44MB
- ✅ Simpler, more maintainable code
- ✅ No crashes from index mismatches

---

## Resources

- **Piper GitHub Issue**: https://github.com/rhasspy/piper/discussions/425
- **sherpa-onnx GitHub**: https://github.com/k2-fsa/sherpa-onnx
- **Piper Docs**: https://k2-fsa.github.io/sherpa/onnx/tts/piper.html
- **espeak-ng IPA**: http://espeak.sourceforge.net/phonemes.html
