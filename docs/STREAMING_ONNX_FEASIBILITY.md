# Streaming ONNX Inference Feasibility Analysis

**Date:** 2025-11-14
**Status:** PARTIALLY IMPLEMENTED - Streaming via callbacks already exists!

---

## Executive Summary

**TL;DR:** True frame-by-frame streaming isn't feasible with ONNX Runtime, BUT sherpa-onnx **already supports sentence-level streaming via callbacks**. We just need to leverage it properly!

### What's Already There

1. ✅ **Callback mechanism exists** (sherpa-onnx/csrc/offline-tts.h:79-80)
2. ✅ **Sentence-level batching implemented** (offline-tts-vits-impl.h:275-351)
3. ✅ **espeak-ng does sentence segmentation automatically**
4. ✅ **Config parameter `max_num_sentences` controls batch size**

### What We Need

- **Expose callbacks to Swift** (currently not used)
- **Set `max_num_sentences = 1`** for maximum responsiveness
- **Stream audio chunks as they arrive** via callback

---

## Architecture Analysis

### Current Flow

```
Text → espeak-ng → [sentence1, sentence2, ...]
     → piper-phonemize → [phonemes1, phonemes2, ...]
     → sherpa-onnx batching:
         IF sentences <= max_num_sentences:
             Process all at once (blocking 2-3 min)
         ELSE:
             FOR each batch:
                 Process batch (ONNX inference - blocking)
                 Call callback with audio chunk ← STREAMING HERE!
```

### Key Code Locations

**1. Callback Definition** (`sherpa-onnx/csrc/offline-tts.h:79-80`)

```cpp
using GeneratedAudioCallback = std::function<int32_t(
    const float * /*samples*/, int32_t /*n*/, float /*progress*/)>;
```

**2. Sentence Splitting** (`sherpa-onnx/csrc/piper-phonemize-lexicon.cc:664-694`)

```cpp
std::vector<TokenIDs> PiperPhonemizeLexicon::ConvertTextToTokenIdsVits(...) {
    // espeak-ng splits text into sentences
    CallPhonemizeEspeakWithNormalized(text, config, &phonemes, ...);

    std::vector<TokenIDs> ans;
    for (const auto &p : phonemes) {  // Each phoneme vector = one sentence
        phoneme_ids = PiperPhonemesToIdsVits(token2id_, p);
        ans.emplace_back(std::move(phoneme_ids));  // One TokenIDs per sentence
    }
    return ans;
}
```

**3. Batching with Callbacks** (`sherpa-onnx/csrc/offline-tts-vits-impl.h:275-351`)

```cpp
// If text too long, process in batches
int32_t num_batches = x_size / batch_size;

for (int32_t b = 0; b != num_batches && should_continue; ++b) {
    auto audio = Process(batch_x, batch_tones, sid, speed);  // ONNX inference
    ans.samples.insert(ans.samples.end(), audio.samples.begin(), audio.samples.end());

    if (callback) {
        // ← STREAMING CALLBACK HERE!
        should_continue = callback(audio.samples.data(), audio.samples.size(),
                                   (b + 1) * 1.0 / num_batches);
    }
}
```

### The Bottleneck

**ONNX Runtime `sess_->Run()` is synchronous and blocking** (`sherpa-onnx/csrc/offline-tts-vits-model.cc:111-113`)

```cpp
auto out = sess_->Run({}, input_names_ptr_.data(), inputs.data(), inputs.size(),
                      output_names_ptr_.data(), output_names_ptr_.size());
// ↑ This blocks for ~0.5s per word (no way to cancel or stream internally)
```

**Why this matters:**
- A sentence = ~15-20 words
- ~0.5s per word = ~7-10 seconds per sentence
- But we get the ENTIRE sentence audio at once (not frame-by-frame)

---

## Streaming Options Evaluated

### Option A: Leverage Existing Callbacks ✅ RECOMMENDED

**How it works:**
1. Set `max_num_sentences = 1` in sherpa-onnx config
2. Expose `GeneratedAudioCallback` to Swift via C API
3. Stream sentence audio chunks as they complete
4. Display "Synthesizing sentence X of Y..." progress

**Pros:**
- ✅ Already implemented in C++!
- ✅ No C++ modifications needed
- ✅ Just expose existing API to Swift
- ✅ Sentence-level streaming = good UX
- ✅ Works TODAY with minimal effort

**Cons:**
- ⚠️ Still 7-10s per sentence (not instant)
- ⚠️ Callback only fires AFTER sentence completes
- ⚠️ Not frame-by-frame streaming

**Implementation Effort:** **LOW** (1-2 days)

**Files to Modify:**
- `sherpa-onnx/c-api/c-api.h` - Add callback parameter to synthesis function
- `sherpa-onnx/c-api/c-api.cc` - Bridge C++ callback to C callback
- `SherpaOnnx.swift` - Add Swift callback closure
- `PiperTTSProvider.swift` - Use callback for progress/streaming

**Example Swift API:**

```swift
func synthesize(
    text: String,
    speed: Float,
    onChunk: @escaping (Data, Double) -> Void  // (audioData, progress)
) async throws -> SynthesisResult {
    // C API calls callback for each sentence
    // Swift closure receives audio chunks as they arrive
}
```

---

### Option B: Modify espeak-ng for Word-Level Splitting 🤔 COMPLEX

**How it works:**
- Modify espeak-ng to return words instead of sentences
- Each word becomes a separate ONNX inference call
- More frequent callbacks (every ~0.5s instead of ~7-10s)

**Pros:**
- ✅ More frequent progress updates
- ✅ Faster time-to-first-audio

**Cons:**
- ❌ Prosody will suffer (word-level synthesis = robotic)
- ❌ espeak-ng modification required
- ❌ More ONNX overhead (many small calls vs few large calls)
- ❌ May be slower overall due to overhead

**Implementation Effort:** **MEDIUM-HIGH** (3-5 days)

**Recommendation:** ❌ NOT WORTH IT - worse audio quality

---

### Option C: True Frame-Level Streaming ❌ NOT FEASIBLE

**How it would work:**
- Modify VITS model architecture to be autoregressive
- Inference generates audio frame-by-frame
- Stream each frame as it's generated

**Why it's not feasible:**

1. **VITS is non-autoregressive by design**
   - Generates entire mel-spectrogram in one shot
   - Not designed for incremental generation
   - Model architecture would need complete redesign

2. **ONNX Runtime doesn't support streaming**
   - `sess_->Run()` is blocking and synchronous
   - No APIs for partial outputs or cancellation
   - Would need to switch to native PyTorch/TensorFlow

3. **Massive engineering effort**
   - Redesign VITS architecture
   - Re-train all models
   - Implement custom inference engine
   - 6+ months of work

**Implementation Effort:** **VERY HIGH** (6+ months)

**Recommendation:** ❌ NOT PRACTICAL for this project

---

### Option D: Hybrid Approach (Sentence Callbacks + Swift Chunking) ✅ BEST UX

**How it works:**
1. Use Option A (sentence-level callbacks)
2. Swift layer does additional sentence → sub-sentence chunking
3. Start playing first sub-chunk while rest synthesizes

**Example:**
```
Sentence: "Dr. Smith visited 123 Main Street today."
         ↓
espeak-ng: [whole sentence] → ONNX (7s)
         ↓
Callback fires with full sentence audio
         ↓
Swift: Split audio at silence boundaries
         ↓
Play first 2s while synthesizing next sentence
```

**Pros:**
- ✅ Faster perceived time-to-audio
- ✅ Leverages existing callback infrastructure
- ✅ Good prosody (sentence-level synthesis)
- ✅ Smooth UX

**Cons:**
- ⚠️ Audio splitting logic needed in Swift
- ⚠️ Silence detection required
- ⚠️ More complex alignment handling

**Implementation Effort:** **MEDIUM** (2-3 days)

---

## Recommended Implementation Plan

### Phase 1: Expose Callbacks (1-2 days)

**Goal:** Get sentence-level streaming working

**Tasks:**
1. Add callback parameter to sherpa-onnx C API
2. Bridge C++ `GeneratedAudioCallback` to C function pointer
3. Expose to Swift as closure
4. Update PiperTTSProvider to use callback
5. Set `max_num_sentences = 1` in config

**Deliverable:** Sentence-by-sentence audio streaming

---

### Phase 2: Add Progress UI (0.5 day)

**Goal:** Show synthesis progress

**Tasks:**
1. Display "Synthesizing sentence X of Y..."
2. Progress bar based on callback progress parameter
3. Time remaining estimate

**Deliverable:** User-visible progress during synthesis

---

### Phase 3 (Optional): Audio Sub-Chunking (2-3 days)

**Goal:** Even faster time-to-first-audio

**Tasks:**
1. Implement silence detection in audio
2. Split sentence audio at natural pauses
3. Stream sub-chunks for playback
4. Handle alignment across sub-chunks

**Deliverable:** Sub-second initial playback latency

---

## Comparison to Sentence Chunking Plan

Your **existing plan** (sentence-level chunking in Swift) vs **streaming callbacks**:

| Aspect | Swift Sentence Chunking | Sherpa-ONNX Callbacks |
|--------|-------------------------|----------------------|
| **Where chunking happens** | Swift (NLTokenizer) | espeak-ng (native) |
| **Granularity** | Configurable | Sentence-level |
| **Progress tracking** | Manual (poll cache) | Automatic (callback) |
| **Code complexity** | Higher (cache management) | Lower (use existing API) |
| **Performance** | Same | Same |
| **Implementation time** | 2-3 days | 1-2 days |
| **Maintainability** | More moving parts | Simpler architecture |

**Recommendation:** Consider **combining both approaches**:
1. Use sherpa-onnx callbacks for sentence-level streaming
2. Use Swift sentence splitting for pre-synthesis lookahead
3. Best of both worlds!

---

## Technical Deep Dive: Why ONNX Streaming is Hard

### VITS Model Architecture

VITS (Conditional Variational Autoencoder) is **non-autoregressive**:

```
Text → Phonemes → VITS Encoder → Latent Representation
                                         ↓
                              Flow/Duration Predictor
                                         ↓
                              Mel-Spectrogram (all frames at once!)
                                         ↓
                              HiFi-GAN Vocoder
                                         ↓
                              Audio waveform
```

**Key point:** The model generates the ENTIRE mel-spectrogram in one forward pass. There's no "next frame" generation like in autoregressive models (Tacotron 2, FastSpeech).

### ONNX Runtime Limitations

```cpp
// This is synchronous and blocking:
auto outputs = session.Run(
    run_options,
    input_names, inputs,
    output_names
);
// ↑ Returns only when ALL outputs are computed
```

No APIs for:
- Partial output retrieval
- Cancellation mid-inference
- Progress callbacks during inference
- Streaming outputs

### Why Other TTS Systems Stream

**Google TTS, Amazon Polly, etc.:**
- Run on cloud infrastructure
- Can pre-synthesize and cache
- Use distributed processing
- Not running on-device ONNX

**Our constraints:**
- On-device inference
- ONNX Runtime (not PyTorch/TF)
- Limited compute resources
- Need fast inference

---

## Conclusion

### ✅ What's Achievable

**Sentence-level streaming via callbacks** is:
- Already implemented in sherpa-onnx
- Easy to expose to Swift (1-2 days)
- Provides good UX (7-10s per sentence vs 2-3 min per paragraph)
- Production-ready approach

### ❌ What's Not Feasible

**Frame-level streaming** requires:
- Model architecture redesign
- Re-training all models
- Custom inference engine
- 6+ months of work
- Not practical for this project

### 🎯 Recommended Next Steps

1. **Expose callbacks to Swift** (Option A) - Quick win!
2. **Combine with your sentence chunking plan** - Best UX
3. **Defer sub-chunking** (Option D) until after testing

This gives you:
- ✅ Immediate progress visibility
- ✅ Sentence-by-sentence playback
- ✅ Simple architecture
- ✅ Production-ready in days, not weeks

---

## Code Examples

### Swift Callback Integration

**Modified C API:**

```c
// sherpa-onnx/c-api/c-api.h
typedef int32_t (*SherpaOnnxGeneratedAudioCallback)(
    const float *samples,
    int32_t n,
    float progress,
    void *user_data
);

struct SherpaOnnxGeneratedAudio {
    const float *samples;
    int32_t n;
    int32_t sample_rate;
    // ... other fields
};

SherpaOnnxGeneratedAudio SherpaOnnxGenerateWithCallback(
    const SherpaOnnxOfflineTts *tts,
    const char *text,
    int64_t sid,
    float speed,
    SherpaOnnxGeneratedAudioCallback callback,
    void *user_data
);
```

**Swift Wrapper:**

```swift
func synthesize(
    text: String,
    speed: Float = 1.0,
    onProgress: @escaping (Data, Double) -> Void
) async throws -> SynthesisResult {

    return try await withCheckedThrowingContinuation { continuation in
        var allAudioData = Data()

        // C callback that bridges to Swift closure
        let callback: SherpaOnnxGeneratedAudioCallback = { samples, n, progress, userData in
            let audioData = Data(bytes: samples!, count: Int(n) * MemoryLayout<Float>.size)

            // Call Swift closure
            onProgress(audioData, Double(progress))

            // Accumulate for final result
            allAudioData.append(audioData)

            return 1  // Continue synthesis
        }

        // Call C API with callback
        let result = SherpaOnnxGenerateWithCallback(
            tts, text, 0, speed, callback, nil
        )

        continuation.resume(returning: SynthesisResult(
            audioData: allAudioData,
            // ... other fields
        ))
    }
}
```

**Usage in PiperTTSProvider:**

```swift
let result = try await sherpaOnnx.synthesize(
    text: paragraph,
    speed: speed,
    onProgress: { audioChunk, progress in
        // Stream audio chunk to player
        await audioPlayer.enqueue(audioChunk)

        // Update UI
        await updateProgress(progress)
    }
)
```

---

## Performance Estimates

### With Callback Streaming (Option A)

**Paragraph: 300 words, 15 sentences**

```
Time breakdown (sentence-by-sentence):
- Sentence 1 (20 words):  ~10s synthesis → callback → playback starts
- Sentence 2 (20 words):  ~10s synthesis → callback → playback continues
- ...
- Sentence 15 (20 words): ~10s synthesis → callback → playback ends

Total time: ~150s
Time to first audio: ~10s (vs 150s without streaming!)
```

### With Sub-Chunking (Option D)

**Same paragraph:**

```
- Sentence 1 synthesis: 10s total
  - Sub-chunk 1 (first 5 words): Play after 10s while sentence 2 synthesizes
  - Sub-chunk 2 (next 5 words):  Play seamlessly
  - Sub-chunk 3 (last 10 words): Play seamlessly

Time to first audio: ~10s (same)
Perceived latency: Lower (playback starts earlier in sentence)
```

---

## Questions & Answers

**Q: Can we cancel synthesis mid-way?**
A: Yes! The callback can return 0 to stop synthesis. Already supported in sherpa-onnx.

**Q: Does this work with w_ceil and normalized text?**
A: Yes! The callback just streams audio chunks. Alignment happens per-sentence.

**Q: Will this break alignment?**
A: No. Each sentence has its own alignment result. Concatenate them like in your current plan.

**Q: How does this compare to cloud TTS APIs?**
A: Similar latency (7-10s first chunk). They also synthesize sentence-by-sentence server-side.

**Q: Can we do better than 7-10s per sentence?**
A: Not without sacrificing quality. Could reduce via:
  - Word-level splitting (worse prosody)
  - Smaller/faster model (worse quality)
  - GPU acceleration (iOS CoreML? Worth exploring!)

---

## Final Recommendation

**Implement Option A (Callback Streaming) + Your Existing Sentence Chunking Plan**

**Why this combination:**
1. **Callbacks** give you progress visibility and sentence streaming
2. **Swift chunking** enables lookahead pre-synthesis for smooth transitions
3. **Both together** provide the best UX with manageable complexity

**Timeline:**
- Expose callbacks: 1-2 days
- Integrate with chunking: 1 day
- Testing: 1 day
- **Total: 3-4 days**

vs. your current plan: 3.5-5 days

**Net result:** Similar timeline, better architecture, real streaming!

---

**Questions? Let me know and I can dive deeper into any aspect!**
