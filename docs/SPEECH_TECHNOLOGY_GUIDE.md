# The Complete Guide to Speech Technology in Listen2

**An Educational Journey Through Modern Text-to-Speech Systems**

*Status: Work in Progress - Part 1 of 3*

---

## Foreword

This guide explores the fascinating world of speech synthesis technology that powers Listen2, a modern iOS reading app. Unlike most technical documentation, this guide is designed to be listened to with a voice reader, so we'll take our time explaining concepts, telling the historical stories behind each technology, and diving deep into how everything works together.

By the time you finish this guide, you'll understand not just what Listen2 does, but why each technology exists, how it evolved, and what makes this particular combination so powerful for creating natural-sounding speech with precise word-level highlighting.

---

## Table of Contents

### Part 1: Foundations (This Document)
1. [Introduction](#introduction)
2. [The Big Picture: How Listen2 Really Works](#the-big-picture)
3. [The Evolution of Speech Synthesis](#the-evolution-of-speech-synthesis)
4. [Sherpa-ONNX: The Foundation](#sherpa-onnx-the-foundation)

### Part 2: The Text-to-Speech Pipeline (Coming Soon)
5. espeak-ng: The Linguistic Engine
6. Piper and VITS: Neural Voice Synthesis
7. Phoneme-Based Word Alignment

### Part 3: Advanced Topics (Coming Soon)
8. The Voice Models
9. Performance and Optimization
10. Future Possibilities

---

## Introduction

### What This Guide Covers

Welcome to a deep exploration of speech technology. This isn't just a manual for Listen2 - it's a journey through decades of research, innovation, and engineering that culminated in the ability to make computers speak naturally and highlight words in perfect synchronization with audio.

We'll answer questions like:
- How do computers convert text into natural-sounding speech?
- What are phonemes, and why do they matter?
- How does Listen2 know exactly which word is being spoken at any moment?
- Why does this work offline without any cloud services?
- What's the history behind each technology we use?

### Who This Guide Is For

This guide is designed for:
- **Curious users** who want to understand the technology behind their reading app
- **Developers** interested in speech synthesis and iOS development
- **Students** learning about natural language processing and audio synthesis
- **Researchers** exploring state-of-the-art TTS implementations
- **Anyone fascinated** by how computers process human language

### A Note About Accuracy

This guide is based on the actual Listen2 source code as of November 2025, not on documentation or assumptions. Every technical detail described here reflects the real implementation, including the custom modifications made to sherpa-onnx and the innovative phoneme-based alignment system that makes word highlighting possible without using speech recognition.

---

## The Big Picture: How Listen2 Really Works

Before we dive into the details of each component, let's understand the overall architecture. This high-level overview will help you see how all the pieces fit together.

### The Common Misconception

When people first learn that Listen2 can highlight words in perfect sync with audio, they often assume it works like this:

1. Generate speech audio from text
2. Use speech recognition to transcribe the audio back to text
3. Match the recognized words with timestamps to know when each word is spoken

This approach is called "forced alignment," and while it's common in some systems, **Listen2 doesn't work this way at all**. There's no speech recognition involved. Instead, Listen2 uses something much more elegant: phoneme-level timing data that comes directly from the speech synthesis process itself.

### How Listen2 Actually Works

Here's the real pipeline, which we'll explore in detail throughout this guide:

#### Step 1: Text Preparation (espeak-ng)

When you start reading a paragraph, the text first goes through a normalization process powered by espeak-ng, a linguistic engine with over 15 years of development history.

**Example Input:**
```
Dr. Smith arrived at 3:30 PM with $50.
```

**After espeak-ng normalization:**
```
Doctor Smith arrived at three thirty P M with fifty dollars.
```

This normalization is crucial because neural networks need consistent, speakable text. espeak-ng also converts the text into phonemes - the smallest units of sound in language.

**Phonemes for "Doctor":**
```
d ɑ k t ɚ
```

Each of these symbols represents a distinct sound. English has about 44 phonemes total.

#### Step 2: Neural Speech Synthesis (Piper + sherpa-onnx)

The normalized text and phonemes are fed into a neural network called VITS (Variational Inference with adversarial learning for end-to-end Text-to-Speech). This is where the magic happens - the network generates natural-sounding audio at 22,050 samples per second.

**What makes this special:** The VITS model doesn't just output audio samples. It also provides detailed timing information for every single phoneme. For each phoneme, we know:

- **The symbol**: What sound it represents (like "d" or "ɑ")
- **The duration**: How long it lasts in the audio (like 0.08 seconds)
- **The position**: Where it appears in the original text

This timing data is the secret sauce that makes word highlighting possible.

#### Step 3: Phoneme-to-Word Alignment (PhonemeAlignmentService)

Listen2 has a service called PhonemeAlignmentService that takes the phoneme timing data and groups phonemes into words. It's like connecting the dots:

- Phonemes [d, ɑ, k, t, ɚ] belong to word "Doctor"
- They span from 0.0 to 0.42 seconds in the audio
- They correspond to characters 0-2 in the original text ("Dr.")

The service handles tricky cases like:
- Contractions: "don't" might be synthesized as two words "do not"
- Abbreviations: "Dr." becomes "Doctor" in synthesis
- Numbers: "$50" becomes "fifty dollars"

The alignment service maintains a mapping between what you see on screen ("Dr.") and what was actually synthesized ("Doctor"), ensuring the highlight appears in the right place.

#### Step 4: Building the Timeline (PhonemeTimeline)

For each sentence in the paragraph, Listen2 builds a PhonemeTimeline structure. Think of it as a musical score, but for speech:

```
Time (seconds):  0.0    0.2    0.4    0.6    0.8    1.0
Words:           Doctor ────→ Smith ──→ arrived ────→
Phonemes:        d ɑ k t ɚ    s m ɪ θ   ə r aɪ v d
```

This timeline contains:
- **Word boundaries**: When each word starts and ends
- **Phoneme details**: The complete phonetic breakdown
- **Character offsets**: Where each word appears in the original text
- **Total duration**: The length of the sentence in seconds

#### Step 5: Streaming Playback (SynthesisQueue)

Here's where Listen2's design really shines. Instead of synthesizing an entire paragraph before playback starts, Listen2 uses sentence-by-sentence streaming:

1. **Split** the paragraph into sentences
2. **Synthesize** the first sentence (takes ~200-500ms)
3. **Start playing** the first sentence immediately
4. **While playing**, synthesize the next sentence in the background
5. **Seamlessly transition** to the next sentence when the first finishes

This approach means you hear audio within half a second of pressing play, even for long paragraphs. The user never notices the synthesis happening because it's always one step ahead.

#### Step 6: Real-Time Word Highlighting (WordHighlighter)

While audio plays, a component called WordHighlighter updates the UI at 60 frames per second. Here's how it works:

1. **Track elapsed time**: "We've been playing for 0.35 seconds"
2. **Look up the timeline**: "At 0.35 seconds, we're in word 2: 'Smith'"
3. **Find the text position**: "Word 2 starts at character 4 in the paragraph"
4. **Update the highlight**: Yellow highlight moves to "Smith" on screen

The WordHighlighter uses binary search to find the current word efficiently - it can search through hundreds of words in microseconds, which is why it can update 60 times per second without any lag.

### The Key Innovations

What makes Listen2's approach special:

1. **No speech recognition needed**: By using phoneme timing directly from synthesis, we avoid the computational cost and potential errors of transcription.

2. **Perfect synchronization**: Since the timing comes from the same process that generated the audio, it's always perfectly aligned.

3. **Handles text mismatches**: The phoneme alignment service can map between display text ("Dr.") and synthesized text ("Doctor") intelligently.

4. **Streaming architecture**: Sentence-by-sentence synthesis makes the app feel instant, even though neural synthesis isn't actually instant.

5. **Offline-first**: Everything runs on device using ONNX neural network models. No cloud required.

### What's Coming in This Guide

Now that you understand the big picture, we'll explore each component in depth:

- The fascinating history of speech synthesis, from formant synthesis to neural networks
- How sherpa-onnx makes it possible to run sophisticated models on a phone
- The linguistic wizardry of espeak-ng and its 15-year evolution
- The VITS neural architecture and why it produces such natural speech
- The clever algorithms that map phonemes to words
- How Listen2 optimizes performance to avoid draining your battery
- The voice models and what makes each one unique

Let's begin with understanding where speech synthesis came from, and why the current generation of neural systems represents such a massive leap forward.

---

## The Evolution of Speech Synthesis

To appreciate how modern speech synthesis works, we need to understand the journey that got us here. This isn't just history for history's sake - each generation of technology solved specific problems and introduced new ones, leading to the design decisions you see in Listen2 today.

### The Dream of Talking Machines

The idea of making machines speak is surprisingly old. In the 1770s, Wolfgang von Kempelen built a mechanical speaking machine that could produce vowels and some consonants using bellows, reeds, and a leather tube shaped like a human vocal tract. It was crude, but it proved that speech could be created mechanically.

Fast forward to 1939, when Bell Labs demonstrated the Voder (Voice Operating Demonstrator) at the World's Fair. An operator would use a keyboard and foot pedals to control electronic filters and oscillators, producing recognizable speech. It was impressive for its time, but required a skilled operator and sounded robotic.

The real breakthroughs came with digital computers.

### Era 1: Formant Synthesis (1950s - 1980s)

**The Idea:** Human speech consists of resonant frequencies called formants, produced by the shape of our vocal tract. If you can generate the right formants at the right times, you can create intelligible speech.

**How It Worked:**

Formant synthesizers used mathematical models of how the human vocal tract produces sound. For vowels, they would generate:

- **F1**: First formant (determined by tongue height)
- **F2**: Second formant (determined by tongue position)
- **F3**: Third formant (provides additional resonance)

For example, the "ah" sound in "father" has:
- F1: 700 Hz (low frequency, mouth open)
- F2: 1220 Hz (mid frequency)
- F3: 2600 Hz (high frequency)

The "ee" sound in "beet" has different formant frequencies:
- F1: 270 Hz (high tongue position)
- F2: 2290 Hz (front tongue position)
- F3: 3010 Hz

By generating sine waves at these frequencies and blending them, formant synthesizers could create vowel sounds. Consonants were created using noise generators and filtering.

**The Most Famous Example:**

Stephen Hawking's voice synthesizer, which he used from 1985 until his death in 2018, was a formant-based system called DECtalk. It had a distinctive robotic quality that became iconic, but it was chosen for practical reasons: it was portable, reliable, and completely intelligible despite the robotic tone.

**Advantages:**
- Extremely compact (could run on early 1980s hardware)
- Very fast (real-time on primitive processors)
- Highly intelligible
- Complete control over every speech parameter

**Disadvantages:**
- Robotic, unnatural sound
- No prosody (natural rhythm and intonation)
- Required linguistic experts to hand-tune rules
- Didn't sound remotely human

**Legacy:**

Formant synthesis taught us that speech is fundamentally about resonance patterns, not just waveforms. This insight influences even modern neural systems. espeak-ng, which Listen2 uses for phonemization, actually started as a formant synthesizer and still retains that capability, though Listen2 only uses its linguistic processing features.

### Era 2: Concatenative Synthesis (1990s - 2000s)

**The Breakthrough:** What if instead of generating speech from scratch, we recorded a human saying lots of small pieces and stitched them together?

**How It Worked:**

Speech researchers recorded a human speaker saying thousands of carefully designed sentences, covering all possible sound combinations in the language. They then chopped up these recordings into units:

- **Diphones**: Two-phoneme sequences (like "ah-n" or "n-d")
- **Triphones**: Three-phoneme sequences (better transitions)
- **Half-syllables**: Complete syllable halves for common patterns

When synthesizing new text, the system would:

1. Convert text to phonemes
2. Search the database for the best matching units
3. Concatenate (join) them together
4. Apply signal processing to smooth the transitions

**Example:**

To say "Hello", the system might use:
- The "h-e" diphone from the word "help"
- The "e-l" diphone from "tell"
- The "l-o" diphone from "low"

**The Challenge: Unit Selection**

The key problem was choosing which recordings to use. If you recorded the word "low" in the sentence "The temperature is low" (sad tone), it wouldn't sound right in "Say hello" (cheerful greeting).

Sophisticated algorithms would try to match:
- **Prosodic context**: Is this a question or statement?
- **Phonetic context**: What sounds come before and after?
- **Linguistic context**: Is this word emphasized?

The best systems had massive databases - sometimes 20+ hours of recordings - and could often find units that matched the target context well.

**Advantages:**
- Sounded human (because it was recorded from a human)
- Natural prosody when units matched well
- High intelligibility
- Could work in real-time on 1990s/2000s hardware

**Disadvantages:**
- "Stitched together" quality - you could hear the joins
- Required many hours of professional recordings
- Expensive to create new voices
- No way to add expressiveness not in the recordings
- Large storage requirements (hundreds of megabytes)
- Voice quality depended entirely on recording quality

**Famous Examples:**
- Early GPS navigation voices
- Festival Speech Synthesis System
- AT&T Natural Voices
- First-generation Siri (before Apple switched to neural TTS)

**What We Learned:**

Concatenative synthesis proved that humans prefer hearing actual human speech, even if imperfect, over perfectly intelligible but robotic formant synthesis. It also showed the importance of prosody - the rhythm and melody of speech - in making synthesized voices sound natural.

### Era 3: Statistical Parametric Synthesis (2006 - 2016)

**The New Approach:** Instead of storing recordings, what if we built statistical models of speech parameters and generated new audio from those models?

**How It Worked:**

This era was dominated by HMM-based synthesis (Hidden Markov Models):

1. **Training Phase:**
   - Record a speaker saying many hours of text
   - Extract acoustic features for every frame (5-10ms chunks):
     - Fundamental frequency (F0) - the pitch
     - Mel-cepstral coefficients - spectral envelope
     - Aperiodicity - breathiness and noise
   - Train HMMs to predict these features from linguistic context

2. **Synthesis Phase:**
   - Convert text to linguistic features (phonemes, stress, position in word, etc.)
   - Use HMMs to predict acoustic features
   - Generate audio from the predicted features using a vocoder

**Vocoders: The Speech Synthesizer**

A vocoder (voice encoder/decoder) takes acoustic parameters and generates audio. The most common was STRAIGHT, which could produce smooth, continuous audio from feature vectors.

**Advantages:**
- Much smaller than concatenative systems (models, not recordings)
- Smooth, continuous speech (no stitching artifacts)
- Could create new voices from less data (5-10 hours)
- Could modify speech characteristics (pitch, speed) easily
- Consistent quality (no bad unit selection)

**Disadvantages:**
- Muffled, "underwater" sound quality
- Loss of high-frequency detail
- Overly smooth (lost some natural roughness)
- Required complex feature extraction and vocoding
- Still didn't sound fully human

**Famous Examples:**
- HTS (H Triple S) - HMM-based Speech Synthesis System
- Junichi Yamagishi's research systems
- Some later Siri variants
- Google's early TTS

**Why The Muffled Sound?**

The fundamental problem was information loss. Converting speech to parameters, modeling those parameters statistically, and converting back to audio lost subtle details that make speech sound crisp and natural. It was like compressing an image to JPEG at low quality - you could recognize it, but it didn't look sharp.

**The Bridge to Neural Synthesis:**

Statistical parametric synthesis introduced the idea of learning models from data rather than hand-crafting rules. This paved the way for neural networks, which would learn far more complex patterns from far more data.

### Era 4: Neural Text-to-Speech (2016 - Present)

**The Revolution:** What if we used deep neural networks to learn everything - from text all the way to audio waveforms?

**The Breakthrough: WaveNet (2016)**

DeepMind (Google) published WaveNet in 2016, and it changed everything. Instead of predicting acoustic features and using a vocoder, WaveNet directly predicted audio samples using a deep neural network with "dilated convolutions."

**How WaveNet Works:**

WaveNet predicts each audio sample based on all previous samples:

```
Sample 1: [silence]
Sample 2: Given sample 1, predict sample 2
Sample 3: Given samples 1-2, predict sample 3
Sample 4: Given samples 1-3, predict sample 4
... (predict 22,050 samples per second)
```

This "autoregressive" approach means each sample depends on the entire history before it, capturing incredibly subtle patterns in how speech sounds.

**The Result:**

When people first heard WaveNet, the response was shock. It sounded completely natural - not just "pretty good" but genuinely human. The muffled quality was gone. The prosody was natural. It had breathiness, roughness, and all the subtle qualities of human speech.

**The Problem:**

WaveNet was astonishingly slow. Predicting 22,050 samples per second, one at a time, while considering all previous samples, required enormous computation. On a powerful server, it might take 1-2 minutes to generate 1 second of speech. It was completely impractical for real-time applications.

**The Next Wave: Tacotron and Tacotron 2 (2017-2018)**

Google's Tacotron and Tacotron 2 systems split the problem into two stages:

1. **Acoustic Model (Tacotron 2)**: Convert text → mel-spectrogram
   - Much easier than predicting raw audio
   - Could use attention mechanisms to align text with audio
   - Relatively fast

2. **Vocoder (WaveNet or WaveGlow)**: Convert mel-spectrogram → audio
   - Faster than text-to-audio WaveNet
   - Could be optimized and parallelized

This two-stage approach was much more practical and became the standard architecture for neural TTS.

**Parallel WaveGAN and Other Vocoders:**

Researchers developed faster vocoders that could generate speech in real-time:
- **Parallel WaveGAN**: Parallelized WaveNet
- **MelGAN**: Generative Adversarial Network for mel-to-audio
- **HiFi-GAN**: High-fidelity vocoder (used by Listen2's VITS models)

These vocoders maintained quality while being 100-1000x faster than original WaveNet.

**The Current State: VITS and End-to-End Models (2021-Present)**

VITS (Variational Inference with adversarial learning for end-to-end Text-to-Speech), published in 2021, represents the current state of the art. It combines:

1. **Text encoder**: Converts phonemes to linguistic features
2. **Variational autoencoder**: Learns expressive latent representations
3. **Flow-based model**: Maps latent codes to mel-spectrograms
4. **HiFi-GAN vocoder**: Converts mel-spectrograms to audio

**What Makes VITS Special:**

- **End-to-end training**: All components trained together
- **Variational inference**: Can generate varied expressions from same text
- **Duration prediction**: Automatically learns phoneme timing
- **Fast inference**: Can run in real-time on modern hardware
- **High quality**: Rivals WaveNet quality at 100x+ the speed

**This is what Listen2 uses.** The Piper project provides VITS models optimized for offline use, and sherpa-onnx makes them run efficiently on mobile devices.

### Why Neural TTS Changed Everything

Neural TTS solved problems that plagued synthesis for decades:

1. **Natural prosody**: Learned from data, not hand-coded rules
2. **Expressiveness**: Can convey emotion and emphasis
3. **Data efficiency**: Can train good voices from 10-20 hours of recordings
4. **Consistency**: Same quality across all text
5. **Flexibility**: Easy to fine-tune for new voices or styles

**The Tradeoff:**

The main tradeoff is computational cost. While modern neural TTS (like VITS) is fast enough for real-time on phones, it still requires significantly more computation than concatenative or formant synthesis. Listen2 addresses this through:

- Efficient ONNX models optimized for mobile
- Sentence-by-sentence synthesis to maintain responsiveness
- Background prefetching to hide synthesis latency
- Careful memory management to avoid overwhelming the device

### Where We Are Today

Listen2 represents the current state of what's possible with offline neural TTS:

- **Quality**: Natural-sounding speech indistinguishable from humans in short segments
- **Speed**: Synthesizes 10x faster than real-time on modern phones
- **Size**: Voice models are 60-100 MB (much smaller than concatenative databases)
- **Flexibility**: Can easily switch voices or adjust parameters
- **Timing**: Provides phoneme-level timing for perfect word synchronization

The next frontier is expressiveness - making synthesized speech convey complex emotions, adjust to context automatically, and maintain consistent speaker identity across long passages. Research systems like Microsoft's VALL-E and OpenAI's voice models are exploring these frontiers, but they require massive computational resources. Listen2 prioritizes what works great today, on device, without cloud services.

---

## Sherpa-ONNX: The Foundation

Now that we understand the evolution of speech synthesis, let's dive into the foundation that makes Listen2 work: sherpa-onnx, the framework that enables running sophisticated neural models on mobile devices.

### What Is Sherpa-ONNX?

Sherpa-ONNX is an open-source framework for running speech recognition and synthesis models on edge devices - phones, tablets, embedded systems, and desktops. Think of it as the "engine" that powers Listen2's text-to-speech capabilities.

**Key Facts:**
- **Project**: k2-fsa/sherpa-onnx on GitHub
- **License**: Apache 2.0 (free and open-source)
- **Language**: C++ core with bindings for Swift, Python, Java, JavaScript, and more
- **Creator**: The k2-fsa team (Next-generation Kaldi speech recognition toolkit)
- **First Release**: 2022
- **Current Status**: Actively maintained with frequent updates

### The Name: Sherpa

The name "Sherpa" comes from the legendary mountain guides of the Himalayas - fitting for a framework that helps navigate the complex terrain of speech processing. Just as Sherpas help climbers reach high peaks, sherpa-onnx helps developers deploy sophisticated speech models that would otherwise be inaccessible on resource-constrained devices.

### The ONNX Part: Why It Matters

ONNX stands for **Open Neural Network Exchange**, and it's crucial to understanding why sherpa-onnx exists.

#### The Neural Network Portability Problem

Traditionally, neural networks are tied to the framework they're trained in:

- Train in **PyTorch** → Can only run in PyTorch
- Train in **TensorFlow** → Can only run in TensorFlow
- Train in **JAX** → Can only run in JAX

This creates problems:
1. **Deployment complexity**: Must ship the entire framework with your model
2. **Performance**: Training frameworks aren't optimized for inference
3. **Platform limitations**: Some frameworks don't work on mobile/embedded
4. **Model sharing**: Hard to use models across different ecosystems

#### ONNX: The Universal Format

ONNX solves this by providing a universal intermediate format for neural networks:

```
Training:           Export:              Inference:
PyTorch  ────────→  ONNX Model  ───────→  ONNX Runtime (optimized)
TensorFlow ───────→  ONNX Model  ───────→  On any platform
JAX ──────────────→  ONNX Model  ───────→  With any runtime
```

**What ONNX Represents:**

An ONNX model file contains:
- **Graph structure**: The neural network architecture (layers, connections)
- **Weights**: The trained parameters (billions of floating-point numbers)
- **Metadata**: Input/output shapes, operator versions, documentation

It's like a blueprint that any ONNX runtime can execute.

#### ONNX Runtime: Speed and Efficiency

Microsoft's ONNX Runtime is a highly optimized inference engine that:

- **Graph optimization**: Fuses operations, eliminates redundancy
- **Kernel selection**: Chooses the fastest implementation for each operation
- **Hardware acceleration**: Uses CPU SIMD instructions, GPU, or neural accelerators
- **Quantization**: Supports INT8/INT16 quantization for smaller, faster models
- **Multi-platform**: Runs on Windows, Linux, macOS, iOS, Android, WebAssembly

**Performance Example:**

A VITS model trained in PyTorch might:
- Run at 0.5x real-time in PyTorch (take 2 seconds to generate 1 second of audio)
- Run at 5x real-time in ONNX Runtime on the same hardware (generate 1 second of audio in 0.2 seconds)

That's a 10x speedup just from using the optimized runtime!

### Why Sherpa-ONNX Exists: The Last Mile Problem

ONNX Runtime solves the inference problem, but there's a gap between "I have an ONNX model" and "I have a working speech application":

1. **Audio preprocessing**: Loading audio, resampling, converting formats
2. **Feature extraction**: Converting audio to mel-spectrograms
3. **Text preprocessing**: Tokenization, normalization, phonemization
4. **Model management**: Loading models, handling errors, managing memory
5. **Post-processing**: Converting model outputs back to usable formats
6. **Integration**: Connecting all the pieces into a usable API

Sherpa-ONNX provides all of this. It's the "last mile" that makes ONNX models actually usable for speech applications.

### Sherpa-ONNX Architecture

Let's look at how sherpa-onnx is structured, using Listen2 as a concrete example:

#### Layer 1: Application (Swift)

```swift
// Listen2's Swift code
let piperProvider = PiperTTSProvider(voiceID: "en_US-lessac-medium")
try await piperProvider.initialize()

let result = try await piperProvider.synthesize(
    "Hello world",
    speed: 1.0
)
// result contains audio samples and phoneme timing
```

This is clean, simple Swift code. Under the hood, it's calling...

#### Layer 2: Swift Wrapper (SherpaOnnx.swift)

```swift
final class SherpaOnnxOfflineTtsWrapper {
    private var tts: OpaquePointer?  // C pointer

    func generate(text: String, sid: Int32, speed: Float) -> GeneratedAudio {
        let audio = SherpaOnnxOfflineTtsGenerate(
            tts,
            (text as NSString).utf8String,
            sid,
            speed
        )
        return GeneratedAudio(audio: audio!)
    }
}
```

This wrapper bridges Swift and C, handling memory management and type conversions. It calls...

#### Layer 3: C API (c-api.h)

```c
// sherpa-onnx C API
typedef struct SherpaOnnxGeneratedAudio {
    const float *samples;           // Audio samples
    int32_t n;                      // Number of samples
    int32_t sample_rate;            // 22050 Hz

    // Phoneme timing data
    int32_t num_phonemes;
    const char **phoneme_symbols;
    const int32_t *phoneme_durations;
    const int32_t *phoneme_char_start;
    const int32_t *phoneme_char_length;

    // Text normalization data
    const char *normalized_text;
    const int32_t *char_mapping;
    int32_t char_mapping_count;
} SherpaOnnxGeneratedAudio;

SHERPA_ONNX_API SherpaOnnxGeneratedAudio*
SherpaOnnxOfflineTtsGenerate(
    SherpaOnnxOfflineTts *tts,
    const char *text,
    int32_t sid,
    float speed
);
```

This C API provides a stable interface that works across languages and platforms. Behind it...

#### Layer 4: C++ Implementation

The C++ layer does the heavy lifting:

1. **espeak-ng integration**: Calls espeak for text normalization and phonemization
2. **ONNX Runtime invocation**: Feeds phonemes into the VITS model
3. **Audio generation**: Processes model outputs into PCM samples
4. **Metadata extraction**: Captures phoneme durations and character positions
5. **Memory management**: Allocates and manages all the complex data structures

#### Layer 5: ONNX Runtime

ONNX Runtime executes the actual neural network:
- Loads the VITS model from the .onnx file
- Optimizes the computational graph
- Runs inference using CPU SIMD instructions
- Returns mel-spectrograms and duration predictions

#### Layer 6: espeak-ng

The linguistic engine that sherpa-onnx depends on:
- Text normalization ("Dr." → "Doctor")
- Phonemization ("Doctor" → "d ɑ k t ɚ")
- Event callbacks for position tracking

### What Listen2 Specifically Uses

Listen2 uses sherpa-onnx for **offline TTS (text-to-speech)** with these specific features:

#### Supported Model Types

Sherpa-ONNX supports multiple TTS architectures, but Listen2 uses **VITS** (Piper models):

**VITS (What Listen2 Uses):**
- End-to-end neural TTS
- Fast inference (10x real-time on iPhone)
- High quality natural speech
- Phoneme-level timing data

**Other Models Sherpa-ONNX Supports (Not Used by Listen2):**
- **Matcha-TTS**: Fast TTS using flow matching
- **Kokoro**: Multi-speaker Japanese TTS
- **Kitten**: Lightweight TTS
- **Zipvoice**: Chinese TTS with feature scaling

#### Features Listen2 Uses

**✅ Currently Used:**
1. **VITS model inference**: Core speech synthesis
2. **Phoneme extraction**: Getting phoneme symbols, durations, and positions
3. **Text normalization**: espeak-ng integration for "Dr." → "Doctor"
4. **Character mapping**: Tracking positions through normalization
5. **Single-speaker synthesis**: One voice at a time
6. **Speed control**: Adjustable playback speed (0.5x to 2.0x)
7. **Progress callbacks**: Streaming synthesis with progress updates

**❌ Available But Not Used:**
1. **Multi-speaker models**: Some models support 100+ voices
2. **Streaming recognition**: Real-time speech-to-text
3. **Voice activity detection**: Silence detection
4. **Speaker diarization**: "Who is speaking" identification
5. **Keyword spotting**: Wake word detection
6. **Rule-based text normalization**: FST/FAR files for advanced normalization

### Custom Modifications in Listen2

Listen2 uses a **custom-built sherpa-onnx.xcframework** with modifications to support enhanced word highlighting. Here's what was changed:

#### Standard sherpa-onnx

Out of the box, sherpa-onnx provides basic phoneme information but doesn't capture all the data needed for precise word highlighting:

```c
// Standard output (simplified)
struct SherpaOnnxGeneratedAudio {
    float *samples;
    int num_samples;
    // Basic phoneme info...
};
```

#### Listen2's Enhanced Version

The custom framework adds:

**1. Normalized Text Capture**

Problem: espeak-ng processes text in clauses (sentence fragments), not complete paragraphs. If you only capture normalized text at the end, you lose data from early clauses.

Solution: Capture normalized text after EACH clause and concatenate:

```cpp
// Listen2's modification
std::string full_normalized_text;
for (const auto& clause : clauses) {
    std::string clause_normalized = espeak_normalize(clause);
    full_normalized_text += clause_normalized;  // Accumulate!
}
result.normalized_text = full_normalized_text;
```

**2. Character Position Mapping**

Problem: Normalization changes character positions. "Dr." (3 characters) becomes "Doctor" (6 characters). How do you map back?

Solution: Track position changes during normalization:

```cpp
// Character mapping: original_pos -> normalized_pos
std::vector<std::pair<int, int>> char_mapping;
// Example for "Dr. Smith":
// {0,0}, {1,1}, {2,2}, {3,6} → position 3 (space after "Dr.") maps to position 6 (space after "Doctor")
result.char_mapping = char_mapping.data();
result.char_mapping_count = char_mapping.size();
```

**3. Enhanced Phoneme Position Tracking**

espeak-ng fires events during synthesis:
- `espeakEVENT_WORD`: Fired at word boundaries
- `espeakEVENT_PHONEME`: Fired for each phoneme

The custom framework captures these events and associates each phoneme with its exact character position in both original and normalized text.

### The Framework Files

Listen2's custom framework is located at:
```
Listen2/Frameworks/sherpa-onnx.xcframework/
├── ios-arm64/                      # Device architecture (iPhone/iPad)
│   ├── libsherpa-onnx.a          # Compiled library
│   └── Headers/                   # C/C++ headers
│       ├── sherpa-onnx/c-api/    # C API
│       └── espeak/                # espeak-ng headers
├── ios-arm64_x86_64-simulator/   # Simulator architectures
│   └── (same structure)
└── Info.plist                     # Framework metadata
```

**Size**: ~50 MB (includes ONNX Runtime + espeak-ng + sherpa code)

### Updating the Framework

When sherpa-onnx C++ code changes (bug fixes, new features), the framework must be rebuilt:

```bash
# From Listen2 project root
./scripts/update-frameworks.sh --build
```

This script:
1. Checks out sherpa-onnx source code
2. Applies Listen2's custom patches
3. Builds for iOS device and simulator architectures
4. Creates the .xcframework bundle
5. Copies it into Listen2/Frameworks/

**Why This Matters**: Using a stale framework causes bugs like:
- ❌ Corrupt phoneme durations
- ❌ Missing normalized text
- ❌ Incorrect character mappings
- ❌ Word highlighting getting stuck or jumping

The update script ensures the framework matches the expected API.

### Performance Characteristics

On iPhone 15 Pro Max, Listen2's sherpa-onnx integration achieves:

- **Synthesis speed**: ~10x real-time (generates 10 seconds of audio in 1 second)
- **Cold start**: ~200ms to initialize TTS engine
- **Memory usage**: ~180 MB (VITS model + ONNX Runtime + sherpa framework)
- **CPU usage**: Moderate during synthesis, minimal during playback
- **Battery impact**: Low (offline processing more efficient than streaming)

### What Makes Sherpa-ONNX Special

There are other ways to do TTS on mobile (like cloud APIs), but sherpa-onnx provides unique advantages:

**1. Offline Operation**
- No internet required
- Works on airplanes, in remote areas, anywhere
- Zero latency from network requests
- Complete privacy (no data leaves device)

**2. Cost Efficiency**
- No per-API-call charges
- No monthly subscription fees
- One-time model download
- Unlimited usage

**3. Consistency**
- Same quality every time
- No degradation during high traffic
- No throttling or rate limits
- Predictable performance

**4. Control**
- Full access to timing data
- Custom voice models
- Parameter tuning
- No black-box dependencies

**5. Integration**
- Clean C API works from any language
- Small surface area (easy to maintain)
- Open source (can debug and modify)
- Active community

### The Ecosystem

Sherpa-ONNX is part of a larger ecosystem:

**k2-fsa**: The parent project, focused on next-generation speech recognition

**Other sherpa projects**:
- **sherpa**: Streaming ASR for Kaldi models
- **sherpa-ncnn**: Mobile-optimized ASR using ncnn framework
- **icefall**: Training recipes for speech models

**Related tools**:
- **Piper**: TTS training and model distribution (provides Listen2's voices)
- **Coqui**: Another open-source TTS project (different architecture)
- **ONNX Runtime**: The underlying inference engine

### Looking Forward

Sherpa-ONNX development continues with focus on:
- Faster models (more real-time factors)
- Smaller models (less memory)
- More languages (currently ~50+)
- Better quality (improved architectures)
- More features (emotion control, voice cloning)

Listen2 benefits from these improvements automatically by updating the framework and models.

---

## To Be Continued...

This concludes Part 1 of the guide. We've covered:
- The real architecture of Listen2's word highlighting system
- The 70-year evolution of speech synthesis
- The foundation provided by sherpa-onnx and ONNX

**Coming in Part 2:**
- Deep dive into espeak-ng: How linguistic processing works
- VITS and Piper: The neural voice synthesis pipeline
- Phoneme alignment: Mapping sounds to words

**Coming in Part 3:**
- The voice models: What makes each one unique
- Performance optimization: Making it run smoothly on phones
- Future possibilities: What's on the horizon

---

*Document Status: Part 1 Complete - November 2025*
*Based on Listen2 source code commit: f768d24*
*Author: Listen2 Development Team with Claude Code*
