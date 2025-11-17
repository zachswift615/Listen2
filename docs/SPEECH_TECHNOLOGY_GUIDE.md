# The Complete Guide to Speech Technology in Listen2

**An Educational Journey Through Text-to-Speech and Speech-to-Text**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Part I: The Foundation - Sherpa-ONNX](#part-i-the-foundation---sherpa-onnx)
3. [Part II: Text-to-Speech - Making Machines Speak](#part-ii-text-to-speech---making-machines-speak)
4. [Part III: Speech-to-Text - Teaching Machines to Listen](#part-iii-speech-to-text---teaching-machines-to-listen)
5. [Part IV: The Linguistic Bridge - espeak-ng and Piper-Phonemize](#part-iv-the-linguistic-bridge---espeak-ng-and-piper-phonemize)
6. [Part V: Voice Models - The Art of Digital Speech](#part-v-voice-models---the-art-of-digital-speech)
7. [Part VI: Integration - How It All Works Together](#part-vi-integration---how-it-all-works-together)
8. [Part VII: Future Possibilities](#part-vii-future-possibilities)
9. [Glossary](#glossary)

---

## Introduction

Welcome to the fascinating world of speech technology! This guide will take you on a journey through the cutting-edge technologies that power Listen2, a modern voice reader app for iOS. Whether you're a curious user, aspiring developer, or speech technology enthusiast, this guide will help you understand how computers can both speak and understand human language.

### What You'll Learn

By the end of this guide, you'll understand:
- How neural networks generate natural-sounding speech
- How machines transcribe audio into text
- The role of phonemes in speech synthesis
- Why different components work together in a speech pipeline
- What makes modern speech technology "offline-first"

### Why Listen2's Approach Matters

Listen2 uses a unique combination of technologies that prioritize:
- **Privacy**: All processing happens on your device - no cloud services
- **Speed**: Optimized for real-time performance on mobile devices
- **Quality**: Neural voice models that sound natural and expressive
- **Accessibility**: Completely free and open-source technologies

Let's begin our journey!

---

## Part I: The Foundation - Sherpa-ONNX

### What is Sherpa-ONNX?

**Sherpa-ONNX** is an open-source framework for running speech recognition and synthesis models on edge devices (phones, tablets, embedded systems). Think of it as the "engine" that makes speech technology work without needing an internet connection.

#### The Origin Story

The name "Sherpa" comes from the legendary mountain guides of the Himalayas - fitting for a framework that helps navigate the complex terrain of speech processing. "ONNX" stands for **Open Neural Network Exchange**, a standard format for representing neural network models.

**Project Details:**
- **Creator**: k2-fsa (Next-gen Kaldi speech recognition toolkit)
- **License**: Apache 2.0 (free and open-source)
- **Repository**: https://github.com/k2-fsa/sherpa-onnx
- **Languages**: C++ core with bindings for Swift, Python, Java, and more

### Why ONNX Format?

Traditional neural networks are framework-specific - a model trained in PyTorch might not work in TensorFlow. ONNX solves this by providing a universal format that any runtime can execute.

**Benefits:**
- ✅ **Portability**: Write once, run anywhere (desktop, mobile, embedded)
- ✅ **Optimization**: ONNX Runtime optimizes models for each platform
- ✅ **Quantization**: Compress models from FP32 (4 bytes) to INT8 (1 byte) for faster inference
- ✅ **Interoperability**: Use models trained in any framework

### Sherpa-ONNX Capabilities

Sherpa-ONNX is a Swiss Army knife for speech technology:

#### 1. **Text-to-Speech (TTS)**

Converts written text into natural-sounding speech using neural vocoder models.

**Supported Model Types:**
- **VITS** (Variational Inference with adversarial learning for end-to-end TTS) - Used by Listen2
- **Matcha-TTS** (Fast TTS using optimal-transport conditional flow matching)
- **Kokoro** (Multi-speaker Japanese TTS)
- **Kitten** (Lightweight TTS model)
- **Zipvoice** (Chinese TTS with feature scaling)

**What Listen2 Uses:**
- Piper VITS models (5 voices in catalog)
- 22050 Hz sample rate audio output
- Real-time synthesis (faster than playback speed)
- Phoneme-level timing information

**What's Available But Not Used Yet:**
- Multiple speaker support (some models support 100+ voices)
- Emotional control via noise_scale parameters
- Speaking rate control independent of audio playback
- Rule-based text normalization (FST/FAR files)
- Batch synthesis for multiple sentences

#### 2. **Speech-to-Text (STT)**

Transcribes audio into text using automatic speech recognition (ASR).

**Supported Model Types:**
- **Whisper** (OpenAI's multilingual ASR) - Used by Listen2 for word alignment
- **Zipformer** (Next-generation Kaldi ASR architecture)
- **Paraformer** (Non-autoregressive ASR from Alibaba)
- **Wenet** (Production-ready ASR toolkit)

**What Listen2 Uses:**
- Whisper Tiny INT8 (English-only, quantized)
- Used for word-level alignment (matching audio timing to text)
- Processes 16kHz mono audio
- Real-time factor: ~0.3x (processes 1 second of audio in 0.3 seconds)

**What's Available But Not Used Yet:**
- Streaming recognition (real-time transcription as audio arrives)
- Voice activity detection (VAD) for silence removal
- Speaker diarization (identifying who is speaking)
- Keyword spotting (wake word detection)
- Audio tagging (identifying non-speech sounds)
- Multilingual transcription (100+ languages with full Whisper models)

#### 3. **Speaker Identification**

Sherpa-ONNX can identify speakers using voice embeddings, though Listen2 doesn't currently use this feature.

### The Architecture

Sherpa-ONNX follows a layered architecture:

```
┌─────────────────────────────────────────────────┐
│         Application Layer (Swift)                │
│  • SherpaOnnx.swift wrapper                     │
│  • TTSService, WordAlignmentService             │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│         C API Layer (sherpa-onnx.h)             │
│  • SherpaOnnxCreateOfflineTts()                 │
│  • SherpaOnnxOfflineTtsGenerate()               │
│  • SherpaOnnxCreateOfflineRecognizer()          │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│         C++ Core (sherpa-onnx C++)              │
│  • Model loading and inference                  │
│  • Audio processing pipeline                    │
│  • Phoneme extraction and timing                │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│         ONNX Runtime (Microsoft)                │
│  • Neural network execution                     │
│  • Hardware acceleration (CPU/GPU)              │
│  • Model optimization                           │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│         espeak-ng + piper-phonemize             │
│  • Text normalization (Dr. → Doctor)            │
│  • Phonemization (text → IPA symbols)           │
│  • Position tracking (character offsets)        │
└─────────────────────────────────────────────────┘
```

### Framework Integration in Listen2

Listen2 uses a **custom-built sherpa-onnx.xcframework** that includes modifications for enhanced phoneme tracking and normalized text extraction.

**Framework Location:**
```
Listen2/Frameworks/sherpa-onnx.xcframework/
├── ios-arm64/                      # Device architecture (iPhone/iPad)
├── ios-arm64_x86_64-simulator/     # Simulator architectures
└── Info.plist                      # Framework metadata
```

**Why Custom Framework?**

The stock sherpa-onnx doesn't expose all the data Listen2 needs for precise word highlighting. Custom modifications add:
- Character mapping from original text to normalized text
- Phoneme-level character positions via espeak-ng callbacks
- Enhanced audio generation metadata extraction

**Keeping It Updated:**

When sherpa-onnx C++ code changes, the framework must be rebuilt:
```bash
./scripts/update-frameworks.sh --build
```

See `docs/FRAMEWORK_UPDATE_GUIDE.md` for details.

### Key Data Structures

#### `SherpaOnnxGeneratedAudio`

The C API returns this structure after synthesis:

```c
typedef struct SherpaOnnxGeneratedAudio {
    // Audio data
    const float *samples;              // PCM audio samples
    int32_t n;                         // Number of samples
    int32_t sample_rate;               // Sample rate (22050 Hz)

    // Phoneme information
    int32_t num_phonemes;              // Number of phonemes
    const char **phoneme_symbols;      // IPA symbols (e.g., "h", "ə", "l", "oʊ")
    const int32_t *phoneme_durations;  // Duration in samples per phoneme
    const int32_t *phoneme_char_start; // Character position in normalized text
    const int32_t *phoneme_char_length;// Character length

    // Text normalization data
    const char *normalized_text;       // Text after normalization
    const int32_t *char_mapping;       // Mapping: original pos → normalized pos
    int32_t char_mapping_count;        // Number of mapping entries
} SherpaOnnxGeneratedAudio;
```

This rich data structure is what enables Listen2's precise word highlighting.

---

## Part II: Text-to-Speech - Making Machines Speak

### The Evolution of TTS

Speech synthesis has come a long way:

**1950s-1980s: Formant Synthesis**
- Hand-crafted rules for vowel formants
- Robotic, unnatural sound
- Example: Stephen Hawking's voice

**1990s-2000s: Concatenative Synthesis**
- Record thousands of speech units (diphones, triphones)
- Concatenate units to form words
- Better quality but still "stitched together" sound
- Example: Early GPS navigation voices

**2010s-2016: Statistical Parametric Synthesis**
- Model speech parameters (pitch, duration, spectral features)
- HMM-based synthesis (Hidden Markov Models)
- Smoother than concatenation but "muffled"
- Example: Original Siri voice

**2016-Present: Neural TTS**
- End-to-end neural networks
- Learn from raw audio waveforms
- Natural prosody and expressiveness
- Example: Modern Alexa, Google Assistant, Listen2

### How Neural TTS Works

Neural TTS follows a multi-stage pipeline:

#### Stage 1: Text Analysis

**Input:** Raw text string
```
"Dr. Smith said, 'Hello, world!' in 2024."
```

**Processing:**
1. **Text Normalization** (via espeak-ng)
   - Expand abbreviations: "Dr." → "Doctor"
   - Convert numbers: "2024" → "two thousand twenty four"
   - Handle punctuation and special characters

2. **Phonemization** (via piper-phonemize + espeak-ng)
   - Convert to IPA phonemes: "Hello" → "h ə l oʊ"
   - Track character positions for alignment

**Output:** Phoneme sequence with positions
```
["d", "ɑ", "k", "t", "ɚ", " ", "s", "m", "ɪ", "θ", ...]
```

#### Stage 2: Neural Acoustic Modeling

**Input:** Phoneme sequence

**The VITS Architecture:**

VITS (Variational Inference with adversarial learning for end-to-end Text-to-Speech) is a state-of-the-art neural TTS architecture that combines:

1. **Text Encoder**
   - Transformer-based architecture
   - Converts phonemes to linguistic features
   - Captures pronunciation patterns

2. **Posterior Encoder**
   - Learns latent representation of speech
   - Variational autoencoder (VAE) for expressiveness
   - Enables voice style variation

3. **Flow-based Generator**
   - Normalizing flow model
   - Transforms latent variables to mel-spectrogram
   - Preserves acoustic detail

4. **HiFi-GAN Vocoder**
   - Neural vocoder (converts mel-spectrogram to waveform)
   - Generative adversarial network (GAN)
   - Produces high-fidelity 22050 Hz audio

**Key Innovation:**

Unlike older systems that require separate duration and acoustic models, VITS is **end-to-end** - it learns everything from text to waveform in one unified model.

**Training Data:**

Piper voice models are trained on:
- 10-20 hours of single-speaker recordings
- Aligned text transcripts
- Phoneme-level timing (forced alignment)

#### Stage 3: Waveform Generation

**Input:** Mel-spectrogram from VITS

**Output:** Raw audio samples (PCM float32)
- Sample rate: 22050 Hz
- Channels: 1 (mono)
- Format: 32-bit floating point (-1.0 to 1.0)

**Real-time Factor:**

On iPhone 15 Pro Max, Listen2 synthesizes speech at approximately **10x real-time** - it can generate 10 seconds of audio in just 1 second.

### Phoneme-Level Timing

One of Listen2's unique features is access to **phoneme-level timing** information from the synthesis process.

#### What Are Phonemes?

Phonemes are the smallest units of sound in a language. English has about 44 phonemes:

**Vowels:**
- Short: /ɪ/ (bit), /ɛ/ (bet), /æ/ (bat)
- Long: /i/ (beat), /eɪ/ (bait), /oʊ/ (boat)

**Consonants:**
- Stops: /p/ (pat), /b/ (bat), /t/ (tap), /d/ (dog)
- Fricatives: /f/ (fat), /v/ (vat), /s/ (sat), /z/ (zap)
- Nasals: /m/ (mat), /n/ (nat), /ŋ/ (rang)

#### How Listen2 Tracks Phonemes

During synthesis, sherpa-onnx provides:

```swift
struct PhonemeInfo {
    let symbol: String           // IPA symbol: "h", "ɛ", "l", "oʊ"
    let duration: TimeInterval   // Duration in seconds: 0.08
    let textRange: Range<Int>    // Character range: 0..<1
}
```

**Example for "Hello":**

| Phoneme | Symbol | Duration | Text Range | Character |
|---------|--------|----------|------------|-----------|
| 1 | h | 0.08s | 0..<1 | H |
| 2 | ə | 0.06s | 1..<2 | e |
| 3 | l | 0.10s | 2..<4 | ll |
| 4 | oʊ | 0.12s | 4..<5 | o |

This data enables precise word highlighting synchronized to the audio.

### Text Normalization

Before synthesis, text must be normalized to handle abbreviations, numbers, and special cases.

#### espeak-ng's Role

espeak-ng (extended speech, next generation) is an open-source formant synthesizer that excels at text normalization and phonemization.

**Normalization Examples:**

| Original | Normalized |
|----------|------------|
| Dr. Smith | Doctor Smith |
| $50 | fifty dollars |
| 2024 | two thousand twenty four |
| U.S.A. | U S A |
| Mr. & Mrs. | Mister and Missus |
| 3:45 PM | three forty five P M |

#### Why This Matters

Without normalization, the neural model would try to pronounce "Dr." as "dur" and "$50" as "dollar sign fifty".

#### Character Mapping

Normalization changes character positions, so Listen2 needs a mapping:

```
Original:  "Dr. Smith"
           0123456789

Normalized: "Doctor Smith"
            0123456789012

Mapping:
  Original[0] → Normalized[0-5]   ("D" → "Doctor")
  Original[4] → Normalized[7]     ("S" → "S")
```

This mapping ensures word highlighting shows the **original** text, not the normalized version.

### Voice Parameters

Piper TTS models expose several parameters for controlling voice characteristics:

#### 1. **noise_scale** (Default: 0.667)

Controls variation in acoustic features:
- **Lower** (0.1-0.5): More consistent, less expressive
- **Higher** (0.8-1.0): More variation, more emotional

**Use case:** Audiobook narration uses lower values for consistency.

#### 2. **noise_scale_w** (Default: 0.8)

Controls duration variability:
- **Lower**: More monotone timing
- **Higher**: More natural rhythm and pacing

#### 3. **length_scale** (Default: 1.0)

Controls overall speaking speed:
- **< 1.0**: Faster speech (independent of playback speed)
- **> 1.0**: Slower speech
- **Range**: 0.5 to 2.0 typically

**Listen2's Approach:**

Currently, Listen2 uses default parameters and controls speed via audio playback (AudioPlayer speed control). However, combining synthesis-time `length_scale` with playback speed could improve quality at extreme speeds.

### Current Listen2 Implementation

**What's Working:**
- ✅ Real-time VITS synthesis (10x faster than playback)
- ✅ Phoneme extraction with durations
- ✅ Character position tracking
- ✅ Normalized text extraction
- ✅ Five bundled voice models (English, male/female)
- ✅ 22050 Hz audio output

**Integration Points:**
```
Listen2/Services/TTS/
├── PiperTTSProvider.swift    # TTSProvider implementation
├── SherpaOnnx.swift           # Swift wrapper for C API
└── TTSService.swift           # Main orchestrator

Listen2/Resources/
├── PiperModels/               # Voice models (*.onnx files)
└── espeak-ng-data/            # Text normalization data (17.5 MB)
```

### Opportunities for Enhancement

**Available but not yet used:**

1. **Multiple Speakers**
   - Some Piper models support 100+ voices
   - Could enable character-specific voices for dialogue

2. **Emotional Control**
   - Adjust `noise_scale` dynamically
   - Create "reading styles" (calm, excited, dramatic)

3. **Prosody Control**
   - Emphasis on specific words
   - Question intonation patterns

4. **Streaming Synthesis**
   - Generate audio chunk-by-chunk
   - Start playback before synthesis completes
   - Already partially implemented via progress callbacks

---

## Part III: Speech-to-Text - Teaching Machines to Listen

### Why ASR in a TTS App?

At first glance, it seems odd for a text-to-speech app to include speech-to-text capabilities. Here's why Listen2 needs both:

**The Word Alignment Challenge:**

When synthesizing "Hello world", we get audio samples but need to know:
- Which samples correspond to "Hello"?
- Which samples correspond to "world"?
- What are the exact start times and durations?

**The Solution: Reverse Transcription**

1. Synthesize text → audio with TTS
2. Transcribe audio → text with ASR (Speech-to-Text)
3. ASR provides **timestamps** for each recognized word
4. Map ASR words back to original text
5. Result: Precise word-level timing for highlighting

This technique is called **forced alignment** or **audio-text synchronization**.

### The Whisper Model

Listen2 uses **Whisper**, OpenAI's open-source multilingual ASR model.

#### Why Whisper?

**Advantages:**
- ✅ Trained on 680,000 hours of multilingual audio
- ✅ Robust to accents, background noise, and audio quality
- ✅ Provides word-level timestamps
- ✅ No need for language-specific acoustic models

**Challenges:**
- ⚠️ Large model size (Tiny: ~150 MB, Base: ~290 MB)
- ⚠️ Slower than real-time on mobile (0.3x real-time factor)

**Listen2's Choice: Whisper Tiny INT8**

Listen2 uses the smallest Whisper variant with INT8 quantization:

| Component | Size | Purpose |
|-----------|------|---------|
| tiny-encoder.int8.onnx | 12 MB | Encodes audio to features |
| tiny-decoder.int8.onnx | 86 MB | Decodes features to text |
| tiny-tokens.txt | 798 KB | Vocabulary (50,000 tokens) |
| **Total** | **~99 MB** | 32% smaller than FP32 |

### How Whisper Works

Whisper is a **transformer-based** encoder-decoder architecture:

#### Audio Processing Pipeline

**Step 1: Audio Preprocessing**

```
Input: WAV file (any sample rate, mono/stereo)
         ↓
Resample to 16kHz mono
         ↓
Compute log mel-spectrogram (80 bins)
         ↓
Chunk into 30-second segments
```

**Step 2: Encoder**

```
Mel-spectrogram (80 × 3000 time steps)
         ↓
Convolutional stem (2 layers)
         ↓
Positional encoding
         ↓
Transformer blocks (4 layers for Tiny)
         ↓
Encoded audio features (384 dimensions)
```

**Step 3: Decoder**

```
Start token: <|startoftranscript|>
         ↓
Transformer decoder (4 layers for Tiny)
         ↓
Cross-attention with encoder outputs
         ↓
Token prediction: "Hello" (token ID: 15947)
         ↓
Next token: "world" (token ID: 1002)
         ↓
Continue until <|endoftranscript|>
```

**Step 4: Timestamp Extraction**

Whisper embeds special timestamp tokens in the output:
```
<|startoftranscript|><|0.00|> Hello <|0.50|> world <|1.00|><|endoftranscript|>
```

These timestamps indicate when each word occurs in the audio.

### Word Alignment Algorithm

Listen2 uses **Dynamic Time Warping (DTW)** to align ASR tokens with the original text.

#### The Challenge

ASR tokenization doesn't match word boundaries:

```
Original text:  ["Hello", "world"]
ASR tokens:     ["Hello", "world"]     ← Perfect case (rarely happens)
ASR tokens:     ["Hel", "lo", "world"] ← Token mismatch
ASR tokens:     ["Hello", "worl", "d"] ← Token mismatch
```

#### DTW Solution

DTW finds the optimal alignment between two sequences, allowing:
- **Many-to-one**: Multiple ASR tokens → one word
- **Substitutions**: Handle transcription errors
- **Flexible matching**: Lowercase vs uppercase, punctuation

**Algorithm:**

```swift
func alignTokensToWords(
    tokens: [(text: String, timestamp: Double, duration: Double)],
    words: [String]
) -> [WordTiming] {
    // Step 1: Normalize both sequences
    let normalizedTokens = tokens.map { $0.text.lowercased() }
    let normalizedWords = words.map { $0.lowercased() }

    // Step 2: Build DTW cost matrix
    var cost = Array(repeating: Array(repeating: Double.infinity,
                                      count: normalizedWords.count + 1),
                     count: normalizedTokens.count + 1)
    cost[0][0] = 0

    for i in 0..<normalizedTokens.count {
        for j in 0..<normalizedWords.count {
            let dist = editDistance(normalizedTokens[i], normalizedWords[j])
            cost[i+1][j+1] = dist + min(
                cost[i][j],     // Match
                cost[i][j+1],   // Insert (skip token)
                cost[i+1][j]    // Delete (skip word)
            )
        }
    }

    // Step 3: Backtrack to find alignment path
    var alignment: [(tokenIndex: Int, wordIndex: Int)] = []
    var i = normalizedTokens.count
    var j = normalizedWords.count

    while i > 0 && j > 0 {
        // Find which direction we came from
        let diagonal = cost[i-1][j-1]
        let up = cost[i-1][j]
        let left = cost[i][j-1]

        if diagonal <= up && diagonal <= left {
            alignment.append((i-1, j-1))
            i -= 1; j -= 1
        } else if up <= left {
            i -= 1  // Skip token
        } else {
            j -= 1  // Skip word
        }
    }

    // Step 4: Convert alignment to WordTiming
    var wordTimings: [WordTiming] = []
    let reversedAlignment = alignment.reversed()

    for wordIndex in 0..<words.count {
        let tokenIndices = reversedAlignment
            .filter { $0.wordIndex == wordIndex }
            .map { $0.tokenIndex }

        if tokenIndices.isEmpty { continue }

        // Aggregate timing from all aligned tokens
        let startTime = tokenIndices.map { tokens[$0].timestamp }.min()!
        let endTime = tokenIndices.map {
            tokens[$0].timestamp + tokens[$0].duration
        }.max()!

        wordTimings.append(WordTiming(
            wordIndex: wordIndex,
            startTime: startTime,
            duration: endTime - startTime,
            text: words[wordIndex]
        ))
    }

    return wordTimings
}
```

#### Example Walkthrough

**Input:**
```
Text:        "Dr. Smith went home."
Normalized:  "Doctor Smith went home"
ASR tokens:  ["Doctor", "Smith", "went", "home"]  ← Timestamps: [0.0, 0.5, 1.0, 1.4]
VoxPDF words: ["Dr.", "Smith", "went", "home"]
```

**DTW Alignment:**
```
Token[0] "Doctor"  → Word[0] "Dr."      → 0.0s - 0.5s
Token[1] "Smith"   → Word[1] "Smith"    → 0.5s - 1.0s
Token[2] "went"    → Word[2] "went"     → 1.0s - 1.4s
Token[3] "home"    → Word[3] "home"     → 1.4s - 1.8s
```

**Output:**
```swift
[
    WordTiming(wordIndex: 0, startTime: 0.0, duration: 0.5, text: "Dr."),
    WordTiming(wordIndex: 1, startTime: 0.5, duration: 0.5, text: "Smith"),
    WordTiming(wordIndex: 2, startTime: 1.0, duration: 0.4, text: "went"),
    WordTiming(wordIndex: 3, startTime: 1.4, duration: 0.4, text: "home")
]
```

### Performance Optimization

ASR alignment is the slowest part of Listen2's pipeline (~1-2 seconds per paragraph).

#### Current Optimizations

1. **Multi-level Caching**
   ```
   Memory Cache → Disk Cache → ASR (only if needed)
   <10ms          ~50-100ms     ~1-2 seconds
   ```

2. **Background Prefetching**
   - Align 3 paragraphs ahead while user listens
   - Hides alignment latency after first paragraph

3. **INT8 Quantization**
   - 32% smaller models
   - 2x faster inference vs FP32

4. **Efficient Resampling**
   - Linear interpolation (good quality, fast)
   - Could use vDSP for 4x speedup (not yet implemented)

#### Future Optimization Opportunities

**1. Streaming ASR**

Currently, Listen2 processes entire paragraphs. Whisper supports streaming for real-time transcription:

```swift
// Potential streaming implementation
func streamingAlign(audioChunks: AsyncStream<Data>) async {
    for await chunk in audioChunks {
        let tokens = recognizer.processChunk(chunk)
        // Update word timings incrementally
    }
}
```

**2. Model Distillation**

Train a smaller custom model specifically for English TTS alignment:
- Faster inference (10x speedup possible)
- Smaller size (~10 MB vs 99 MB)
- Trade-off: Less robust to accents/noise

**3. Phoneme-Based Alignment**

Skip ASR entirely and use phoneme durations from TTS:
- Sherpa-ONNX already provides phoneme timings
- Map phonemes → characters → words
- Challenge: Phoneme boundaries don't always match word boundaries

**Current Approach:**

Listen2 prioritizes **accuracy** over speed, using full ASR alignment. The multi-level caching makes this acceptable for most users.

---

## Part IV: The Linguistic Bridge - espeak-ng and Piper-Phonemize

### espeak-ng: The Phoneme Engine

**espeak-ng** (extended speech, next generation) is the unsung hero of Listen2's TTS pipeline.

#### What It Does

1. **Text Normalization**
   - Expand abbreviations and numbers
   - Handle dates, times, currencies
   - Language-specific rules (120+ languages)

2. **Phonemization**
   - Convert text to IPA (International Phonetic Alphabet)
   - Apply pronunciation dictionaries
   - Handle exceptions and special cases

3. **Position Tracking**
   - Track character offsets during normalization
   - Emit events for word boundaries
   - Maintain original text alignment

#### History and Philosophy

**Origins:**
- Fork of espeak (2007-2015)
- Maintained by Reece H. Dunn since 2015
- Focus on quality and language coverage

**Philosophy:**
- Compact pronunciation rules (vs large dictionaries)
- Formant synthesis (fast, no recordings needed)
- Open data (all pronunciation rules are editable)

**License:** GPL-3.0 (open source)

### The espeak-ng Data Directory

Listen2 bundles espeak-ng-data (17.5 MB):

```
Listen2/Resources/PiperModels/espeak-ng-data/
├── lang/                  # Language-specific rules
│   ├── en/               # English
│   ├── es/               # Spanish
│   └── ...               # 120+ languages
├── voices/                # Voice definitions
│   └── en/               # English variants (US, UK, etc.)
├── phonemes/              # Phoneme definitions
└── intonations/          # Prosody rules
```

This data enables espeak-ng to handle diverse languages and dialects.

### Phonemization Process

#### Step 1: Text Analysis

```
Input: "Dr. Smith's cats"

Tokenization:
  ["Dr.", "Smith's", "cats"]

Dictionary Lookup:
  "Dr." → Exception: "Doctor"
  "Smith's" → Decompose: "Smith" + "'s"
  "cats" → Regular: /kæts/
```

#### Step 2: Rule Application

espeak-ng uses letter-to-sound rules:

```
English rules for "cats":
  c → /k/ (before 'a')
  a → /æ/ (short vowel)
  t → /t/ (unvoiced stop)
  s → /s/ (voiceless fricative)

Result: /kæts/
```

For irregular words, espeak-ng consults pronunciation dictionaries:

```
Dictionary entries:
  "through" → /θɹuː/  (not /θɹoʊɡ/)
  "knight"  → /naɪt/  (silent 'k' and 'gh')
```

#### Step 3: IPA Output

espeak-ng outputs IPA phonemes:

```
Text:     "Hello world"
Phonemes: /həˈloʊ wɜːld/

Breakdown:
  h  → /h/   (voiceless glottal fricative)
  e  → /ə/   (schwa)
  l  → /l/   (voiced alveolar lateral)
  l  → (silent, merged with previous)
  o  → /oʊ/  (diphthong)

  w  → /w/   (voiced labial-velar approximant)
  o  → /ɜː/  (open-mid central unrounded)
  r  → /r/   (alveolar approximant)
  l  → /l/   (lateral)
  d  → /d/   (voiced alveolar stop)
```

### piper-phonemize: The Bridge Layer

**piper-phonemize** is a C++ library that bridges TTS models and espeak-ng.

#### Architecture

```
┌─────────────────────────────────────────┐
│  TTS Model (expects phoneme IDs)        │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│  piper-phonemize                        │
│  • Convert IPA to model-specific IDs    │
│  • Track character positions            │
│  • Handle multi-clause text             │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│  espeak-ng                              │
│  • Text normalization                   │
│  • IPA phonemization                    │
│  • Event callbacks (WORD, PHONEME)      │
└─────────────────────────────────────────┘
```

#### Key Features

1. **Phoneme ID Mapping**

Each Piper model has a `phonemes.txt` file mapping IPA to integers:

```
# phonemes.txt
_	0   # Padding
^	1   # Start
$	2   # End
 	3   # Space
h	4   # /h/
ə	5   # /ə/
l	6   # /l/
oʊ	7   # /oʊ/
...
```

piper-phonemize converts espeak IPA to these IDs.

2. **Position Tracking**

espeak-ng emits events during phonemization:

```c
enum espeakEventType {
    espeakEVENT_WORD,     // Emitted at word start
    espeakEVENT_PHONEME,  // Emitted for each phoneme
    espeakEVENT_END       // Emitted at text end
};

struct espeakEvent {
    int type;
    int text_position;    // Character offset in original text
    int length;           // Character length
    int audio_position;   // Audio sample position
    // ...
};
```

piper-phonemize captures these events and builds character position arrays.

3. **Multi-Clause Handling**

This is where things get tricky. espeak-ng processes text in **clauses** (sentence fragments), not entire paragraphs.

**The Challenge:**

```
Input paragraph: "Dr. Smith said hello. He was happy."

espeak-ng processes in clauses:
  Clause 1: "Dr. Smith said hello."    → Normalized: "Doctor Smith said hello"
  Clause 2: "He was happy."            → Normalized: "He was happy"
```

**The Problem:**

If you only capture normalized text at the end, you lose Clause 1's data.

**Listen2's Solution:**

Modified sherpa-onnx captures normalized text **after each clause**:

```cpp
// In sherpa-onnx/sherpa-onnx/csrc/offline-tts-impl.cc
std::string full_normalized_text;

for (const auto& clause : clauses) {
    std::string clause_normalized = espeak_normalize(clause);
    full_normalized_text += clause_normalized;
    // Continue to next clause...
}

// Return complete normalized text
result.normalized_text = full_normalized_text;
```

See `docs/HANDOFF_2025-11-14_NORMALIZED_TEXT.md` for details on this fix.

### Character Mapping

To enable word highlighting, Listen2 needs to map original text positions to normalized text positions.

#### The Mapping Table

```
Original:  "Dr. Smith went to the U.S.A."
            0123456789...

Normalized: "Doctor Smith went to the U S A"
             0123456789...

Mapping:
  Original[0]   → Normalized[0]     # 'D' → 'D'
  Original[1]   → Normalized[1]     # 'r' → 'o'
  Original[2]   → Normalized[2]     # '.' → 'c'
  Original[3]   → Normalized[6]     # ' ' → ' '
  Original[4]   → Normalized[7]     # 'S' → 'S'
  ...
  Original[23]  → Normalized[23]    # 'U' → 'U'
  Original[25]  → Normalized[25]    # 'S' → 'S'
  Original[27]  → Normalized[27]    # 'A' → 'A'
```

**Storage:**

```c
int32_t char_mapping[] = {
    0, 0,    // Original[0] → Normalized[0]
    1, 1,    // Original[1] → Normalized[1]
    2, 2,    // Original[2] → Normalized[2]
    3, 6,    // Original[3] → Normalized[6]  ← Jump due to expansion
    // ...
};
```

This array is returned in `SherpaOnnxGeneratedAudio` and used by `PhonemeAlignmentService` to map phoneme positions back to original text.

### Integration in Listen2

**Current Implementation:**
```
Listen2/Services/TTS/
├── PiperTTSProvider.swift
│   └── synthesize() calls sherpa-onnx
│
└── SherpaOnnx.swift
    └── Extracts phonemes + character mapping

Frameworks/sherpa-onnx.xcframework/
└── Contains modified espeak-ng integration
```

**Data Flow:**
```
"Dr. Smith" → espeak-ng → "Doctor Smith" + phonemes + char_mapping
            ↓
    SherpaOnnxGeneratedAudio
            ↓
      GeneratedAudio
            ↓
  PhonemeAlignmentService (maps back to "Dr. Smith")
```

### Advanced espeak-ng Features (Not Yet Used)

**1. Custom Dictionaries**

Add custom pronunciations:

```
// my_dictionary.txt
Google  g'u:gl
iOS     'aIoUEs
```

**2. Voice Variants**

espeak-ng supports multiple English variants:
- en-US (American)
- en-GB (British)
- en-AU (Australian)
- en-IN (Indian)
- en-ZA (South African)

Piper could use different espeak variants for different voice models.

**3. SSML Support**

Speech Synthesis Markup Language for prosody control:

```xml
<speak>
  <prosody rate="slow">This is slow.</prosody>
  <break time="500ms"/>
  <prosody pitch="+10%">This is higher pitch.</prosody>
</speak>
```

espeak-ng understands basic SSML tags.

**4. Tone Languages**

espeak-ng supports tone marking for Chinese, Vietnamese, etc.:

```
Mandarin: 你好 (nǐ hǎo) → /ni˨˩˦ hau˨˩˦/
```

This enables multi-language TTS expansion.

---

## Part V: Voice Models - The Art of Digital Speech

### Understanding VITS Models

VITS (Variational Inference with adversarial learning for end-to-end Text-to-Speech) represents the current state-of-the-art in neural TTS.

#### Model Architecture Deep Dive

**1. Text Encoder (Transformer)**

Converts phoneme sequence to linguistic features:

```
Input:  [h, ə, l, oʊ]  (phoneme IDs)
        ↓
Embedding layer (256 dimensions)
        ↓
Positional encoding
        ↓
6 Transformer blocks:
  • Multi-head self-attention (4 heads)
  • Feed-forward network (1024 hidden units)
  • Layer normalization
  • Residual connections
        ↓
Output: Linguistic features (192 dimensions)
```

**2. Posterior Encoder (VAE)**

Learns variational representation of speech:

```
Input: Ground truth mel-spectrogram (training only)
        ↓
Convolutional layers (16 blocks)
        ↓
WaveNet residual blocks
        ↓
Output: μ (mean), σ (variance) of latent distribution
        ↓
Sampling: z ~ N(μ, σ)  (latent variable)
```

This VAE enables voice style variation even from the same text.

**3. Flow-based Generator**

Maps latent variables to mel-spectrogram:

```
Latent z + linguistic features
        ↓
Coupling layers (4 blocks):
  • Affine transformation
  • 1×1 convolutions
  • Residual coupling
        ↓
Output: Mel-spectrogram (80 bins × T frames)
```

Normalizing flows are **invertible** - during inference, we reverse the flow to generate speech.

**4. Duration Predictor**

Predicts phoneme durations:

```
Linguistic features
        ↓
Convolutional layers
        ↓
Output: Duration per phoneme (in frames)

Example:
  "h" → 8 frames (80ms)
  "ə" → 6 frames (60ms)
  "l" → 10 frames (100ms)
  "oʊ" → 12 frames (120ms)
```

This is where Listen2 gets phoneme timing data!

**5. HiFi-GAN Vocoder**

Converts mel-spectrogram to waveform:

```
Mel-spectrogram
        ↓
Transposed convolutions (upsampling):
  80 frames/sec → 22050 samples/sec
        ↓
Multi-receptive field fusion (MRF):
  • 3 residual blocks (kernel size: 3, 7, 11)
  • Captures different time scales
        ↓
Discriminators (adversarial training):
  • Multi-scale discriminator
  • Multi-period discriminator
        ↓
Output: Waveform (22050 Hz)
```

**Adversarial Training:**

Generator tries to fool discriminator into thinking synthesized audio is real. This produces high-quality, natural-sounding audio.

### Piper Voice Catalog

Listen2 includes 5 voices in `voice-catalog.json`:

#### Voice Profiles

**1. en_US-lessac-medium** (Default, Bundled)
- **Speaker:** Linda Johnson (Lessac Technologies)
- **Gender:** Female
- **Quality:** Medium (60 MB)
- **Characteristics:** Clear, neutral American accent
- **Sample Rate:** 22050 Hz
- **Best for:** General reading, audiobooks

**2. en_US-lessac-high** (Bundled)
- **Speaker:** Linda Johnson (high quality training)
- **Gender:** Female
- **Quality:** High (109 MB)
- **Characteristics:** More expressive, better prosody
- **Best for:** Expressive narration, emotional content

**3. en_US-hfc_female-medium** (Bundled)
- **Speaker:** HFC (Human-Friendly Conversational) dataset
- **Gender:** Female
- **Quality:** Medium (61 MB)
- **Characteristics:** Conversational, friendly tone
- **Best for:** Casual reading, blog posts

**4. en_US-hfc_male-medium** (Bundled)
- **Speaker:** HFC dataset
- **Gender:** Male
- **Quality:** Medium (61 MB)
- **Characteristics:** Deep voice, authoritative
- **Best for:** News articles, technical content

**5. en_US-ryan-high** (Downloadable)
- **Speaker:** Ryan (community contribution)
- **Gender:** Male
- **Quality:** High (75 MB)
- **Characteristics:** Expressive male voice
- **Best for:** Audiobook narration

#### Model File Structure

Each voice consists of:

```
en_US-lessac-medium/
├── model.onnx          # Neural network weights (60 MB)
├── model.onnx.json     # Model configuration
└── phonemes.txt        # Phoneme-to-ID mapping
```

**model.onnx.json example:**

```json
{
  "audio": {
    "sample_rate": 22050
  },
  "espeak": {
    "voice": "en-us"
  },
  "inference": {
    "noise_scale": 0.667,
    "noise_scale_w": 0.8,
    "length_scale": 1.0
  },
  "num_speakers": 1,
  "speaker_id_map": {}
}
```

### Voice Training Process

Creating a Piper voice model involves several steps:

#### 1. Data Collection

Record single speaker audio:
- **Duration:** 10-20 hours (minimum)
- **Quality:** Studio-quality recording (no background noise)
- **Content:** Diverse sentences covering phonetic variety
- **Format:** WAV, 22050 Hz or higher

**Phonetic Coverage:**

Good training data includes:
- All phonemes in the language
- Various phoneme combinations
- Different sentence structures
- Range of prosody patterns

#### 2. Forced Alignment

Align audio with text transcripts:

```
Audio: [waveform of "Hello world"]
Text:  "Hello world"
        ↓
Force aligner (Montreal Forced Aligner)
        ↓
Output: Phoneme-level timestamps
  [h, 0.00-0.08]
  [ə, 0.08-0.14]
  [l, 0.14-0.24]
  [oʊ, 0.24-0.36]
  ...
```

This creates training targets for the duration predictor.

#### 3. Feature Extraction

Extract mel-spectrograms from audio:

```
Audio waveform (22050 Hz)
        ↓
Short-time Fourier transform (STFT)
  • Window size: 1024 samples
  • Hop length: 256 samples
        ↓
Mel filterbank (80 bins)
        ↓
Log-scale compression
        ↓
Mel-spectrogram (80 × T)
```

#### 4. Training

Train VITS model with multiple objectives:

**Reconstruction Loss:**
- Mel-spectrogram should match ground truth
- Phoneme durations should match alignment

**KL Divergence:**
- Latent distribution should be close to Gaussian
- Enables sampling variation

**Adversarial Loss:**
- Generated audio should fool discriminator
- Multi-scale and multi-period discriminators

**Training Time:**
- ~1-3 days on modern GPU (RTX 3090)
- ~100k training steps
- Batch size: 16-32 utterances

#### 5. Export to ONNX

Convert trained PyTorch model to ONNX:

```python
import torch
import onnx

# Load trained model
model = load_vits_model("checkpoint.pt")

# Export to ONNX
dummy_input = torch.randint(0, 256, (1, 50))  # Phoneme IDs
torch.onnx.export(
    model,
    dummy_input,
    "model.onnx",
    opset_version=15,
    input_names=["input"],
    output_names=["output"]
)
```

#### 6. Quantization (Optional)

Reduce model size with INT8 quantization:

```python
from onnxruntime.quantization import quantize_dynamic

quantize_dynamic(
    "model.onnx",
    "model.int8.onnx",
    weight_type=QuantType.QInt8
)
```

**Trade-offs:**
- ✅ 50-75% size reduction
- ✅ 2x faster inference
- ⚠️ Slight quality degradation (usually imperceptible)

### Multi-Speaker Models

Some Piper models support multiple speakers in a single model.

#### Speaker Embedding

Multi-speaker models add a speaker ID input:

```
Phoneme sequence + Speaker ID
        ↓
Speaker embedding layer (256 dimensions)
        ↓
Concatenate with phoneme embeddings
        ↓
Rest of VITS architecture
```

**Example:**

```swift
// Single-speaker model
let audio = tts.generate(text: "Hello", sid: 0, speed: 1.0)

// Multi-speaker model (100 speakers)
let audio_speaker1 = tts.generate(text: "Hello", sid: 0, speed: 1.0)
let audio_speaker2 = tts.generate(text: "Hello", sid: 25, speed: 1.0)
let audio_speaker3 = tts.generate(text: "Hello", sid: 99, speed: 1.0)
```

**Use Cases:**
- Dialogue with multiple characters
- Audiobook narration (narrator + character voices)
- Voice customization without retraining

**Listen2 Opportunity:**

Multi-speaker models could enable:
- Gender-specific voices for quoted speech
- Character voices in fiction
- Narrator vs dialogue differentiation

### Voice Quality Comparison

| Aspect | Medium Quality | High Quality |
|--------|----------------|--------------|
| Model Size | 60 MB | 109 MB |
| Training Data | 10-15 hours | 20+ hours |
| Sample Rate | 22050 Hz | 22050 Hz |
| Prosody | Basic | Enhanced |
| Expressiveness | Good | Excellent |
| Inference Speed | 10x real-time | 8x real-time |
| Best Use | General reading | Expressive narration |

**Listen2's Default Choice:**

`en_US-lessac-medium` provides the best balance of quality and performance for most users.

---

## Part VI: Integration - How It All Works Together

### The Complete Pipeline

Let's trace a single paragraph through Listen2's entire speech pipeline.

#### Input: PDF Document

```
User imports: "quantum_physics.pdf"
         ↓
VoxPDF extracts text and word positions
         ↓
DocumentWordMap created with paragraphs and word metadata
```

**VoxPDF Output:**

```swift
struct DocumentWordMap {
    let paragraphs: [String]  // ["The quantum state...", "Heisenberg's uncertainty..."]
    let wordPositions: [[WordPosition]]  // Character offsets per paragraph
}

struct WordPosition {
    let text: String              // "quantum"
    let characterOffset: Int      // 4
    let length: Int               // 7
    let paragraphIndex: Int       // 0
}
```

#### Step 1: User Starts Reading

```
User taps Play on paragraph 0
         ↓
TTSService.startReading(
    paragraphs: ["The quantum state describes..."],
    wordMap: documentWordMap,
    documentID: uuid
)
         ↓
SynthesisQueue.setContent(paragraphs, wordMap, documentID)
```

#### Step 2: TTS Synthesis

```
SynthesisQueue.getAudio(index: 0)
         ↓
Check memory cache → MISS
         ↓
PiperTTSProvider.synthesize("The quantum state describes...")
         ↓
sherpa-onnx C++ pipeline:
  ┌─────────────────────────────────────┐
  │ 1. espeak-ng text normalization     │
  │    "The quantum state describes..." │
  │    (no changes in this case)        │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 2. espeak-ng phonemization          │
  │    /ðə kwɑntəm steɪt dɪskɹaɪbz/    │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 3. VITS neural synthesis            │
  │    Phoneme IDs → Mel-spectrogram    │
  │    → HiFi-GAN → Audio samples       │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 4. Phoneme duration extraction      │
  │    Extract from w_ceil tensor       │
  └────────────────┬────────────────────┘
                   ↓
         SherpaOnnxGeneratedAudio {
             samples: [0.01, 0.03, -0.02, ...],  // 66,150 samples (3 sec)
             sample_rate: 22050,
             num_phonemes: 25,
             phoneme_symbols: ["ð", "ə", " ", "k", "w", ...],
             phoneme_durations: [1764, 1323, 220, 882, ...],  // In samples
             phoneme_char_start: [0, 1, 2, 3, 4, ...],
             phoneme_char_length: [1, 1, 1, 1, 1, ...],
             normalized_text: "The quantum state describes...",
             char_mapping: [0,0, 1,1, 2,2, ...],
             char_mapping_count: 30
         }
         ↓
SherpaOnnx.swift wraps into GeneratedAudio
         ↓
Convert WAV data (16kHz mono) and save to temp file
```

#### Step 3: ASR Word Alignment

```
SynthesisQueue.performAlignment()
         ↓
Check disk cache → MISS
         ↓
WordAlignmentService.align(
    audioURL: "/tmp/paragraph_0.wav",
    text: "The quantum state describes...",
    wordMap: documentWordMap,
    paragraphIndex: 0
)
         ↓
sherpa-onnx Whisper ASR:
  ┌─────────────────────────────────────┐
  │ 1. Load audio and resample to 16kHz │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 2. Compute mel-spectrogram (80 bins)│
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 3. Whisper encoder                  │
  │    Audio features → Context vectors │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 4. Whisper decoder                  │
  │    Autoregressive token generation  │
  └────────────────┬────────────────────┘
                   ↓
  Tokens with timestamps:
  [
      ("The", 0.0s, 0.2s),
      ("quantum", 0.2s, 0.5s),
      ("state", 0.7s, 0.3s),
      ("describes", 1.0s, 0.6s),
      ...
  ]
         ↓
Dynamic Time Warping alignment:
  Map ASR tokens → VoxPDF words
         ↓
AlignmentResult {
    paragraphIndex: 0,
    totalDuration: 3.0,
    wordTimings: [
        WordTiming(wordIndex: 0, startTime: 0.0, duration: 0.2, text: "The"),
        WordTiming(wordIndex: 1, startTime: 0.2, duration: 0.5, text: "quantum"),
        WordTiming(wordIndex: 2, startTime: 0.7, duration: 0.3, text: "state"),
        ...
    ]
}
         ↓
Cache to disk and memory
```

#### Step 4: Playback with Word Highlighting

```
TTSService.playAudio(audioData, alignment)
         ↓
AudioPlayer.play(audioData)
         ↓
Start 60 FPS timer (fires every 16ms)
         ↓
Timer callback:
  ┌─────────────────────────────────────┐
  │ 1. Get currentTime from AudioPlayer │
  │    currentTime = 0.35s              │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 2. Binary search in wordTimings     │
  │    0.0-0.2 (The)                    │
  │    0.2-0.7 (quantum) ← Match!       │
  │    0.7-1.0 (state)                  │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 3. Get WordPosition from wordMap    │
  │    wordIndex: 1 → characterOffset: 4│
  │    length: 7                        │
  └────────────────┬────────────────────┘
                   ↓
  ┌─────────────────────────────────────┐
  │ 4. Update ReadingProgress           │
  │    wordRange: 4..<11 (in paragraph) │
  └────────────────┬────────────────────┘
                   ↓
  UI updates: "The **quantum** state describes..."
  (Yellow highlight on "quantum")
```

#### Step 5: Background Prefetching

```
While user listens to paragraph 0...
         ↓
SynthesisQueue.preSynthesizeAhead(from: 0)
         ↓
Spawn 3 background tasks:
  ├─> Task 1: Synthesize + align paragraph 1
  ├─> Task 2: Synthesize + align paragraph 2
  └─> Task 3: Synthesize + align paragraph 3
         ↓
All tasks run concurrently (async/await)
         ↓
Results cached before user reaches them
         ↓
User navigates to paragraph 1 → Instant playback! ✨
```

### Performance Characteristics

#### Timing Breakdown for 100-Word Paragraph

| Stage | Duration | Can Cache? | Can Prefetch? |
|-------|----------|------------|---------------|
| Text normalization | ~10ms | ✅ Yes | ✅ Yes |
| TTS synthesis | ~300ms | ✅ Yes | ✅ Yes |
| ASR alignment | ~1500ms | ✅ Yes | ✅ Yes |
| Word lookup (60 FPS) | <1ms | N/A | N/A |
| Total (first time) | ~1810ms | - | - |
| Total (cached) | <10ms | - | - |

**Key Optimizations:**
1. Multi-level caching (memory + disk) eliminates repeat work
2. Background prefetching hides alignment latency
3. Binary search keeps word lookup fast (60 FPS requirement)

#### Memory Footprint

| Component | Size | Persistent? |
|-----------|------|-------------|
| Whisper Tiny INT8 | 99 MB | Yes (loaded once) |
| VITS voice model | 60 MB | Yes (loaded once) |
| espeak-ng-data | 17.5 MB | Yes (bundled) |
| Per-paragraph audio | ~500 KB | No (streamed) |
| Per-paragraph alignment | ~10 KB | Yes (cached) |
| **Total baseline** | **~177 MB** | - |
| **Per-document overhead** | **~10 KB/paragraph** | - |

**Memory Management:**
- Models loaded lazily (only when needed)
- Audio samples not retained (streamed to AudioPlayer)
- Alignment cache limited to recent documents
- Old cache files deleted on app launch

### Thread Safety and Concurrency

Listen2 uses Swift's modern concurrency features:

#### Actor Isolation

```swift
@MainActor class TTSService {
    // All UI-related operations
    // Serial execution on main thread
}

actor WordAlignmentService {
    // Isolates sherpa-onnx ASR calls
    // Prevents data races on recognizer pointer
}

actor AlignmentCache {
    // Isolates file I/O
    // Prevents concurrent writes
}
```

#### Async/Await Flow

```swift
// Main thread
let alignment = await synthesisQueue.getAlignment(index: 0)
                        ↓ (crosses actor boundary)
// Background thread
let result = await wordAlignmentService.align(...)
                        ↓ (crosses actor boundary)
// Main thread
updateUI(with: result)
```

#### Cancellation Handling

```swift
func align(...) async throws -> AlignmentResult {
    // Check for cancellation before expensive operations
    guard !Task.isCancelled else {
        throw CancellationError()
    }

    let samples = try await loadAudio(...)

    guard !Task.isCancelled else {
        throw CancellationError()
    }

    let result = performASR(samples)
    return result
}
```

This enables responsive speed/voice changes - ongoing alignment tasks are cancelled immediately.

### Error Handling and Graceful Degradation

Listen2 prioritizes **never breaking playback**:

#### Failure Modes

**1. TTS Synthesis Fails**
```
PiperTTSProvider.synthesize() throws error
         ↓
Fallback to AVSpeechSynthesizer (native iOS voice)
         ↓
Still get word-level timing from AVSpeech
         ↓
Playback continues ✅
```

**2. ASR Alignment Fails**
```
WordAlignmentService.align() throws error
         ↓
Log error for debugging
         ↓
Play audio WITHOUT word highlighting
         ↓
Playback continues ✅
```

**3. Cache Corrupted**
```
AlignmentCache.load() returns corrupted data
         ↓
Delete corrupted cache file
         ↓
Regenerate alignment
         ↓
Playback continues (with delay) ✅
```

**Philosophy:** Audio playback is critical; word highlighting is a bonus feature.

---

## Part VII: Future Possibilities

### Unused Features with High Potential

#### 1. Emotional TTS Control

**Current State:** Using default noise_scale parameters

**Opportunity:** Dynamic emotional control

```swift
enum ReadingStyle {
    case calm        // noise_scale: 0.3, noise_scale_w: 0.6
    case neutral     // noise_scale: 0.667, noise_scale_w: 0.8 (default)
    case expressive  // noise_scale: 0.9, noise_scale_w: 1.0
    case dramatic    // noise_scale: 1.2, noise_scale_w: 1.2
}

// UI: "Reading Style" picker in settings
let audio = tts.generate(text: text, style: .expressive)
```

**Use Cases:**
- Fiction: More dramatic for action scenes
- Non-fiction: Calm for technical content
- Audiobooks: Expressive for character dialogue

#### 2. Multi-Speaker Dialogue

**Current State:** Single voice for all text

**Opportunity:** Character-specific voices

```swift
// Detect quoted speech
let text = """
"Hello," said Alice.
"Welcome!" replied Bob enthusiastically.
"""

// Parse dialogue
let dialogue = parseDialogue(text)
// [
//     (narrator: "said Alice", voice: 0),
//     (alice: "Hello,", voice: 1),
//     (narrator: "replied Bob enthusiastically.", voice: 0),
//     (bob: "Welcome!", voice: 2)
// ]

// Synthesize with different speaker IDs
for segment in dialogue {
    let audio = tts.generate(
        text: segment.text,
        sid: segment.voice,
        speed: 1.0
    )
}
```

**Requirements:**
- Multi-speaker Piper model
- Dialogue parsing (regex or NLP)
- UI for assigning voices to characters

**Impact:** Dramatically improves fiction audiobooks!

#### 3. Streaming TTS

**Current State:** Synthesize full paragraph before playback

**Opportunity:** Start playback immediately

```swift
func streamingSynthesize(text: String) -> AsyncStream<Data> {
    AsyncStream { continuation in
        let callback: AudioChunkCallback = { chunk in
            continuation.yield(chunk)
        }

        tts.generateWithStreaming(
            text: text,
            delegate: callback
        )

        continuation.finish()
    }
}

// Usage
for await audioChunk in streamingSynthesize("Long paragraph...") {
    audioPlayer.append(chunk)  // Start playing immediately
}
```

**Benefits:**
- Eliminate perceived latency for first paragraph
- Better user experience on slower devices

**Challenge:**
- Word alignment needs full audio (ASR requires complete file)
- Could disable highlighting during streaming, enable after completion

#### 4. Custom Voice Training

**Current State:** 5 pre-trained voices

**Opportunity:** User-created custom voices

**Implementation Path:**
1. Record user reading 100-500 sentences (~2-5 hours)
2. Upload to cloud service for training (or on-device with future hardware)
3. Fine-tune base Piper model on user's voice
4. Download personalized voice model

**Use Cases:**
- Personal voice backup (before voice loss due to medical conditions)
- Family member's voice for sentimental content
- Custom voices for content creators

**Technical Challenges:**
- Requires GPU for training (cloud service needed)
- Data privacy concerns (voice data is sensitive)
- Quality depends on recording setup

#### 5. Real-Time ASR for Dictation

**Current State:** ASR only used for alignment

**Opportunity:** Voice input for document creation

```swift
func startDictation() async {
    let stream = recognizer.startStreaming()

    for await result in stream {
        if result.isFinal {
            appendText(result.text)
        } else {
            updateLivePreview(result.text)
        }
    }
}
```

**Features:**
- Voice commands: "New paragraph", "Delete last sentence"
- Punctuation detection
- Real-time editing

**Use Cases:**
- Voice notes while walking
- Hands-free document editing
- Accessibility for motor impairments

#### 6. Multilingual Support

**Current State:** English only (Whisper Tiny English, espeak-ng en-US)

**Opportunity:** 100+ languages

**Requirements:**
1. Download multilingual Whisper model (larger: ~500 MB for Base)
2. Bundle espeak-ng data for target languages (included, 17.5 MB covers 120+ languages)
3. Download Piper models for other languages

**Available Languages (examples):**
- **Spanish:** es_ES-carlfm-x_low (15 MB)
- **French:** fr_FR-siwis-medium (50 MB)
- **German:** de_DE-thorsten-medium (60 MB)
- **Chinese:** zh_CN-huayan-medium (70 MB)
- **Japanese:** ja_JP-kokoro-medium (40 MB)

**Implementation:**
```swift
// Voice catalog with language support
struct Voice {
    let id: String
    let language: String  // ISO 639-1 code
    let espeakVoice: String  // "en-us", "es-es", etc.
}

// Auto-detect document language
let language = detectLanguage(text)
let voice = selectVoice(forLanguage: language)
```

#### 7. Voice Activity Detection (VAD)

**Current State:** Process all audio equally

**Opportunity:** Detect speech vs silence in recordings

```swift
// Detect speech segments in audio file
let segments = vad.detectSpeech(audioURL)
// [
//     (start: 0.0, end: 2.5),    // Speech
//     (start: 5.0, end: 8.3),    // Speech
//     (start: 10.2, end: 12.0)   // Speech
// ]

// Skip silence when transcribing
for segment in segments {
    let text = recognizer.transcribe(audioURL, range: segment)
}
```

**Use Cases:**
- Faster ASR (skip silence)
- Audio cleanup for recordings
- Podcast chapter detection

#### 8. Speaker Diarization

**Current State:** Single speaker assumed

**Opportunity:** Identify who is speaking

```swift
// Identify speakers in audio
let diarization = recognizer.diarize(audioURL)
// [
//     (speaker: "A", start: 0.0, end: 3.2, text: "Hello there"),
//     (speaker: "B", start: 3.2, end: 5.8, text: "Hi, how are you?"),
//     (speaker: "A", start: 5.8, end: 8.1, text: "I'm doing well")
// ]
```

**Use Cases:**
- Meeting transcription (who said what)
- Podcast transcript generation
- Audiobook narrator vs character identification

#### 9. Pronunciation Dictionary

**Current State:** espeak-ng default pronunciations

**Opportunity:** Custom pronunciations for names and jargon

```swift
// User-defined pronunciations
let customDict = [
    "Xiaomi": "ʃaʊmi",        // Not "ziaomi"
    "LLVM": "ɛl ɛl vi ɛm",    // Spell out acronym
    "SQL": "sikwəl",          // "sequel", not "ess queue ell"
]

// Apply before synthesis
let normalizedText = applyCustomDict(text, customDict)
```

**Use Cases:**
- Technical documents (acronyms, project names)
- Fiction (character names, fantasy words)
- Personal content (family names, local places)

#### 10. SSML Support

**Current State:** Plain text only

**Opportunity:** Prosody markup language

```xml
<speak>
  <p>
    This is a paragraph.
    <break time="500ms"/>
    This comes after a pause.
  </p>

  <p>
    <prosody rate="slow" pitch="+10%">
      This is slow and high-pitched.
    </prosody>
  </p>

  <p>
    <emphasis level="strong">This is emphasized!</emphasis>
  </p>
</speak>
```

**Implementation:**
- Parse SSML tags
- Convert to espeak control codes
- Adjust synthesis parameters dynamically

**Use Cases:**
- Dramatic pauses in fiction
- Emphasis for important points
- Questions vs statements intonation

### Research Directions

#### 1. Zero-Shot Voice Cloning

**Technology:** Reference audio → voice model

**Example:** Coqui XTTS, Microsoft VALL-E

**Potential:**
- Listen2 could synthesize in any voice from 5-10 second sample
- Ethical concerns: voice forgery, consent

#### 2. Emotion Recognition

**Technology:** ASR + emotion classifier

**Potential:**
- Detect emotion in recorded speech
- Adjust TTS synthesis to match emotional tone

#### 3. Prosody Transfer

**Technology:** Extract prosody from reference audio, apply to synthesis

**Use Case:**
- "Read this document in the style of this audiobook"
- Professional narrator quality without professional narrator

#### 4. End-to-End Document Understanding

**Technology:** Large Language Models + TTS

**Vision:**
- LLM summarizes document before reading
- Adjusts reading style per section (technical vs narrative)
- Skips irrelevant content (page numbers, headers)

---

## Glossary

### Speech Technology Terms

**Acoustic Model**
: Neural network that maps audio features to phonemes or characters. Used in ASR.

**ASR (Automatic Speech Recognition)**
: Technology that converts spoken audio to text. Also called Speech-to-Text (STT).

**Alignment**
: Process of matching audio timestamps to text positions. Enables word highlighting.

**Concatenative Synthesis**
: TTS technique that stitches together pre-recorded speech units. Used in older systems.

**Discriminator**
: Neural network in GAN that tries to distinguish real from generated data.

**DTW (Dynamic Time Warping)**
: Algorithm for finding optimal alignment between two sequences. Used in Listen2 for token-to-word mapping.

**Encoder-Decoder**
: Neural architecture with two parts: encoder compresses input, decoder generates output.

**espeak-ng**
: Open-source formant synthesizer and text normalizer. Provides phonemization for Piper.

**Formant Synthesis**
: Rule-based TTS using vowel formants. Robotic sound but very compact.

**Forced Alignment**
: Technique to extract word-level timestamps by transcribing synthesized audio.

**GAN (Generative Adversarial Network)**
: Training technique where generator and discriminator compete. Produces high-quality outputs.

**HiFi-GAN**
: High-Fidelity Generative Adversarial Network. Neural vocoder used in VITS.

**IPA (International Phonetic Alphabet)**
: Standardized symbols for representing speech sounds across languages.

**INT8 Quantization**
: Compressing neural network weights from 32-bit floats to 8-bit integers. 4x smaller, 2x faster.

**Mel-Spectrogram**
: Time-frequency representation of audio using mel scale (perceptually motivated frequency scale).

**Neural Vocoder**
: Neural network that converts spectral features (mel-spectrogram) to audio waveform.

**ONNX (Open Neural Network Exchange)**
: Standard format for representing neural networks. Enables cross-framework compatibility.

**Phoneme**
: Smallest unit of sound in a language. English has ~44 phonemes.

**Phonemization**
: Converting text to phoneme sequence. Essential for TTS.

**Piper**
: Fast, local neural TTS engine based on VITS. Used by Listen2.

**piper-phonemize**
: C++ library bridging Piper and espeak-ng.

**Prosody**
: Rhythm, stress, and intonation of speech. Makes speech sound natural.

**Quantization**
: Reducing numerical precision of model weights. Trades accuracy for size/speed.

**Sample Rate**
: Number of audio samples per second. Listen2 uses 22050 Hz (22.05 kHz).

**Sherpa-ONNX**
: Open-source framework for running speech models on edge devices.

**Speaker Diarization**
: Identifying who is speaking when in multi-speaker audio.

**SSML (Speech Synthesis Markup Language)**
: XML-based markup for controlling TTS prosody and pronunciation.

**STT (Speech-to-Text)**
: Same as ASR. Converts audio to text.

**Streaming Recognition**
: Real-time ASR that processes audio as it arrives, without waiting for complete file.

**Text Normalization**
: Converting written text to speakable form. "Dr." → "Doctor", "123" → "one hundred twenty three".

**Timestamp**
: Time position in audio when a word/phoneme occurs.

**Token**
: Unit of text in ASR/NLP. Can be words, subwords, or characters.

**TTS (Text-to-Speech)**
: Technology that converts written text to spoken audio.

**VAD (Voice Activity Detection)**
: Detecting speech vs non-speech (silence) in audio.

**VITS (Variational Inference with adversarial learning for end-to-end TTS)**
: State-of-the-art neural TTS architecture. Used by Piper.

**Vocoder**
: Component that generates audio waveform from acoustic features.

**Waveform**
: Raw audio represented as amplitude values over time. PCM format.

**Whisper**
: OpenAI's open-source multilingual ASR model. Used by Listen2 for alignment.

### Software Architecture Terms

**Actor**
: Swift concurrency primitive that isolates mutable state. Prevents data races.

**async/await**
: Swift concurrency syntax for asynchronous operations.

**Binary Search**
: O(log n) search algorithm. Used for fast word timing lookup.

**Cache**
: Temporary storage for expensive computations. Listen2 has memory and disk caches.

**C API**
: C-language interface for calling library functions. Provides sherpa-onnx bindings.

**Framework (iOS)**
: Bundle of code and resources. Listen2 uses sherpa-onnx.xcframework.

**MainActor**
: Swift actor representing main thread. All UI updates must use @MainActor.

**Prefetching**
: Loading data before it's needed. Listen2 prefetches next 3 paragraphs.

**Real-time Factor**
: Speed of processing relative to audio duration. 0.3x means 1 sec audio processed in 0.3 sec.

**SIMD (Single Instruction, Multiple Data)**
: CPU instructions that process multiple values simultaneously. Used in audio processing.

**Streaming Synthesis**
: Generating audio incrementally instead of all at once.

**Swift Wrapper**
: Swift code that wraps C/C++ API for easier use. SherpaOnnx.swift wraps sherpa-onnx C API.

**Thread Safety**
: Property of code that works correctly when accessed from multiple threads simultaneously.

**xcframework**
: iOS/macOS framework format supporting multiple architectures (device + simulator).

---

## Conclusion

Listen2 represents a synthesis (pun intended) of cutting-edge speech technologies:

- **Sherpa-ONNX** provides the execution runtime
- **VITS/Piper** generates natural-sounding speech
- **Whisper** enables precise word-level timing
- **espeak-ng** bridges written and spoken language
- **piper-phonemize** connects all the pieces

This guide has taken you from high-level concepts to implementation details, showing not just what Listen2 does, but **why** each component exists and **how** they work together.

### Key Takeaways

1. **Offline-First is Powerful**: All processing happens on-device, ensuring privacy and reliability.

2. **Neural TTS is a Multi-Stage Pipeline**: Text → Phonemes → Acoustic Features → Waveform, each stage critical.

3. **Word Alignment Requires Reverse Transcription**: Can't get timing from TTS alone; need ASR to map audio back to text.

4. **Optimization is About Trade-offs**: Quantization, caching, and prefetching balance quality, speed, and user experience.

5. **Unused Features Unlock New Possibilities**: Multi-speaker models, streaming synthesis, and SSML support could transform Listen2.

### Resources for Further Learning

**Speech Technology:**
- [Piper TTS Documentation](https://github.com/rhasspy/piper)
- [sherpa-onnx Documentation](https://k2-fsa.github.io/sherpa/)
- [Whisper Paper](https://arxiv.org/abs/2212.04356)
- [VITS Paper](https://arxiv.org/abs/2106.06103)

**Implementation:**
- Listen2 GitHub Repository: [github.com/zachswift/Listen2]
- Architecture Docs: `docs/architecture/`
- Code Examples: `Listen2/Services/`

**Community:**
- k2-fsa Discussions: https://github.com/k2-fsa/sherpa-onnx/discussions
- Piper Discord: https://discord.gg/rhasspy

---

**Thank you for reading! May your journey into speech technology be as exciting as the technology itself.** 🎙️✨

*Document Version: 1.0*
*Last Updated: 2025-11-17*
*Author: Listen2 Development Team*
