# TTS Performance Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:verification-before-completion before marking any task complete.

**Goal:** Eliminate 2-3 minute synthesis delays and enable fast, smooth TTS playback with robust word highlighting using native ONNX streaming

**Architecture:** Incremental hybrid approach with 3 phases: (1) Eager pre-synthesis to unblock testing, (2) ONNX streaming callbacks + sentence-level chunking for parallel synthesis with zero-gap playback, (3) Integration for production-ready UX. Leverages sherpa-onnx's existing callback infrastructure for true streaming while Swift layer handles async parallel synthesis.

**Tech Stack:** Swift 5, AVFoundation, Combine, Piper TTS, sherpa-onnx (with callbacks), NaturalLanguage framework

**Problem Context:**
- Current 100ms timeout causes immediate fallback to iOS voice
- Long paragraphs (257-374 words) take 2-3 minutes to synthesize
- Dual playback (iOS + Piper) creates chaos
- Blocks testing of w_ceil and normalized text features
- User wants robust long-term solution, not quick hacks
- DISCOVERY: sherpa-onnx already has streaming callbacks (not exposed to Swift!)
- Sequential synthesis causes gaps between sentences (unacceptable UX)

**Success Criteria:**
- Phase 1: Can test w_ceil and normalized text on device
- Phase 2: Time-to-first-audio < 10 seconds + zero gaps between sentences
- Phase 3: Seamless paragraph transitions, production-ready streaming UX

---

## Phase 1: Unblock Testing

**Goal:** Remove synthesis timeout, add progress tracking, enable device testing

### Task 1: Add Synthesis Progress Tracking

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Add progress state to SynthesisQueue**

Add after line 31 (activeTasks declaration):

```swift
/// Progress tracking for synthesis (0.0 to 1.0 per paragraph)
@Published private(set) var synthesisProgress: [Int: Double] = [:]

/// Currently synthesizing paragraph index (for UI display)
@Published private(set) var currentlySynthesizing: Int? = nil
```

**Step 2: Update progress during synthesis**

In `getAudio(for index:)` method, after line 107 ("Synthesize now (blocking)"):

```swift
// Mark as synthesizing and update published state
await MainActor.run {
    synthesizing.insert(index)
    currentlySynthesizing = index
    synthesisProgress[index] = 0.0
}

guard index < paragraphs.count else {
    throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
}

let text = paragraphs[index]

// Note: We can't track real progress inside provider.synthesize()
// because it's synchronous. Set to 0.5 to show "in progress"
await MainActor.run {
    synthesisProgress[index] = 0.5
}

let result = try await provider.synthesize(text, speed: speed)

// Mark as complete
await MainActor.run {
    synthesisProgress[index] = 1.0
    synthesizing.remove(index)
    currentlySynthesizing = nil
}
```

**Step 3: Update background synthesis progress tracking**

In `preSynthesizeAhead(from:)` method, update the Task block (around line 168):

```swift
let task = Task {
    do {
        // Update progress
        await MainActor.run {
            synthesisProgress[index] = 0.0
        }

        let text = paragraphs[index]

        await MainActor.run {
            synthesisProgress[index] = 0.5
        }

        let result = try await provider.synthesize(text, speed: speed)

        // Cache audio data
        await MainActor.run {
            cache[index] = result.audioData
            synthesisProgress[index] = 1.0
            synthesizing.remove(index)
            activeTasks.removeValue(forKey: index)
        }

        // Perform alignment
        await performAlignment(for: index, result: result)

    } catch {
        await MainActor.run {
            synthesizing.remove(index)
            synthesisProgress.removeValue(forKey: index)
            activeTasks.removeValue(forKey: index)
        }
        print("[SynthesisQueue] ⚠️ Background synthesis failed for paragraph \(index): \(error)")
    }
}
```

**Step 4: Clear progress on content change**

In `setContent(paragraphs:speed:documentID:wordMap:)` method, add after line 74:

```swift
self.synthesisProgress.removeAll()
self.currentlySynthesizing = nil
```

**Step 5: Build and verify no compilation errors**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded" or only pre-existing warnings

**Step 6: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git commit -m "feat: add synthesis progress tracking to SynthesisQueue

- Add @Published synthesisProgress and currentlySynthesizing
- Update progress during foreground and background synthesis
- Clear progress on content change
- Enables UI to show synthesis status"
```

---

### Task 2: Remove Synthesis Timeout

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift:399-415`

**Step 1: Remove timeout logic**

Replace lines 399-415 with:

```swift
// Get audio from queue (will synthesize if needed)
// Note: This may take 2-3 minutes for long paragraphs
// Progress is tracked via synthesisQueue.synthesisProgress
guard let wavData = try await queue.getAudio(for: index) else {
    throw TTSError.synthesisFailed(reason: "Synthesis returned nil")
}
try await playAudio(wavData)
```

**Step 2: Build and verify no compilation errors**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 3: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: remove synthesis timeout to support long paragraphs

- Remove 100ms timeout that caused immediate fallback
- Long paragraphs (2-3 min synthesis) now supported
- Progress tracked via SynthesisQueue.synthesisProgress
- Required for w_ceil and normalized text testing"
```

---

### Task 3: Disable iOS Fallback During Testing

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift:31`
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift:396-414`

**Step 1: Add feature flag for fallback**

After line 31 (usePiper declaration):

```swift
private var useFallback: Bool = false  // Disable fallback during testing
```

**Step 2: Wrap fallback logic**

Update the Task block (around line 396-414) to respect the flag:

```swift
Task {
    do {
        // Get audio from queue (will synthesize if needed)
        guard let wavData = try await queue.getAudio(for: index) else {
            throw TTSError.synthesisFailed(reason: "Synthesis returned nil")
        }
        try await playAudio(wavData)
    } catch {
        print("[TTSService] ⚠️ Piper synthesis failed: \(error)")

        if useFallback {
            print("[TTSService] Falling back to AVSpeech")
            await MainActor.run {
                self.fallbackToAVSpeech(text: text)
            }
        } else {
            print("[TTSService] Fallback disabled - stopping playback")
            await MainActor.run {
                self.isPlaying = false
            }
        }
    }
}
```

**Step 3: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 4: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: add feature flag to disable iOS fallback

- Add useFallback flag (default false for testing)
- Prevents dual playback during testing
- Can be re-enabled after fixing cancellation logic
- Fails gracefully by stopping playback instead of fallback"
```

---

### Task 4: Add Eager Pre-Synthesis

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Add startPreSynthesis method**

Add after the `setContent` method (around line 77):

```swift
/// Start pre-synthesizing first N paragraphs immediately
/// - Parameter count: Number of paragraphs to pre-synthesize (default 1)
func startPreSynthesis(count: Int = 1) {
    let endIndex = min(count - 1, paragraphs.count - 1)

    for index in 0...endIndex {
        // Skip if already cached or synthesizing
        guard cache[index] == nil && !synthesizing.contains(index) else {
            continue
        }

        // Mark as synthesizing
        synthesizing.insert(index)

        // Start synthesis task
        let task = Task {
            do {
                await MainActor.run {
                    synthesisProgress[index] = 0.0
                }

                let text = paragraphs[index]

                await MainActor.run {
                    synthesisProgress[index] = 0.5
                }

                let result = try await provider.synthesize(text, speed: speed)

                // Cache audio data
                await MainActor.run {
                    cache[index] = result.audioData
                    synthesisProgress[index] = 1.0
                    synthesizing.remove(index)
                    activeTasks.removeValue(forKey: index)
                }

                // Perform alignment
                await performAlignment(for: index, result: result)

            } catch {
                await MainActor.run {
                    synthesizing.remove(index)
                    synthesisProgress.removeValue(forKey: index)
                    activeTasks.removeValue(forKey: index)
                }
                print("[SynthesisQueue] ⚠️ Pre-synthesis failed for paragraph \(index): \(error)")
            }
        }

        activeTasks[index] = task
    }
}
```

**Step 2: Auto-start pre-synthesis on setContent**

Update `setContent` method to optionally start pre-synthesis. Add parameter:

```swift
func setContent(paragraphs: [String], speed: Float, documentID: UUID? = nil, wordMap: DocumentWordMap? = nil, autoPreSynthesize: Bool = true) {
    // ... existing code ...

    // Auto-start pre-synthesis for first paragraph if enabled
    if autoPreSynthesize && !paragraphs.isEmpty {
        startPreSynthesis(count: 1)
    }
}
```

**Step 3: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 4: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git commit -m "feat: add eager pre-synthesis for first paragraph

- Add startPreSynthesis() method to begin synthesis immediately
- Auto-start on setContent() when document loads
- Pre-synthesizes first paragraph before playback requested
- Reduces time-to-first-audio for initial playback"
```

---

### Task 5: Manual Device Testing - Phase 1

**Goal:** Verify timeout fix and test w_ceil + normalized text features

**Files:**
- Test on: iPhone (physical device)

**Step 1: Build for device**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)' 2>&1 | tee build.log | grep -E "error:|warning:|BUILD SUCCEEDED"
```

Expected: "BUILD SUCCEEDED"

**Step 2: Deploy and launch app**

- Connect iPhone via cable
- Run from Xcode: ⌘R
- Wait for app to launch

**Step 3: Test normalized text feature**

Test document text: "Dr. Smith visited 123 Main St. today."

Expected behavior:
- "Dr." highlights when "Doctor" is spoken
- "123" highlights when "one hundred twenty three" is spoken
- "St." highlights when "Street" is spoken
- No crashes or freezes
- No dual playback

**Step 4: Test w_ceil tensor**

Check Console logs for:
```
[PhonemeAlign] Phoneme durations: [actual durations]
```

Expected: Phoneme durations should NOT all be 0 (w_ceil working)

**Step 5: Test long paragraphs**

Test with 257-374 word paragraph

Expected:
- Progress indicator shows synthesis happening
- Wait 2-3 minutes for synthesis
- Playback starts smoothly when ready
- No timeout, no fallback
- Word highlighting works

**Step 6: Collect test results**

Document in workshop:

```bash
workshop note "Phase 1 testing complete - [results here]"
workshop decision "Timeout fix works for long paragraphs" -r "Tested 374-word paragraph, synthesis completed in ~2.5 minutes, no fallback triggered"
```

**Step 7: Mark complete only if all tests pass**

> **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion

Verify:
- [x] App builds successfully
- [x] No crashes on launch
- [x] Normalized text highlighting works
- [x] w_ceil provides non-zero phoneme durations
- [x] Long paragraphs synthesize without timeout
- [x] No dual playback
- [x] Word highlighting accurate

---

## Phase 2: ONNX Streaming + Async Sentence Chunking

**Goal:** Fast time-to-first-audio (<10s) with zero gaps between sentences via native ONNX callbacks + parallel async synthesis

**Key Insight:** Combine sherpa-onnx's existing streaming callbacks (for progress/streaming) with Swift async sentence synthesis (for parallel processing and zero gaps)

### Task 6: Create Sentence Splitter

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/TTS/SentenceSplitter.swift`

**Step 1: Create SentenceSplitter struct**

```swift
//
//  SentenceSplitter.swift
//  Listen2
//

import Foundation
import NaturalLanguage

/// Represents a sentence chunk with its position in the original text
struct SentenceChunk {
    /// The sentence text
    let text: String

    /// Character range in original paragraph (using Int offsets)
    let range: Range<Int>

    /// Sentence index within paragraph (0-based)
    let index: Int
}

/// Splits paragraphs into sentences for chunked synthesis
struct SentenceSplitter {

    /// Split paragraph into sentences using NLTokenizer
    /// - Parameter text: The paragraph text to split
    /// - Returns: Array of sentence chunks with ranges
    static func split(_ text: String) -> [SentenceChunk] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var chunks: [SentenceChunk] = []
        var sentenceIndex = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentenceText = String(text[range])

            // Convert String.Index range to Int range
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)

            let chunk = SentenceChunk(
                text: sentenceText,
                range: startOffset..<endOffset,
                index: sentenceIndex
            )

            chunks.append(chunk)
            sentenceIndex += 1

            return true  // Continue enumeration
        }

        // Fallback: if no sentences detected, treat entire text as one sentence
        if chunks.isEmpty {
            chunks.append(SentenceChunk(
                text: text,
                range: 0..<text.count,
                index: 0
            ))
        }

        return chunks
    }
}
```

**Step 2: Write tests for SentenceSplitter**

Create: `Listen2/Listen2/Listen2Tests/Services/TTS/SentenceSplitterTests.swift`

```swift
//
//  SentenceSplitterTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class SentenceSplitterTests: XCTestCase {

    func testSingleSentence() {
        let text = "This is a single sentence."
        let chunks = SentenceSplitter.split(text)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "This is a single sentence.")
        XCTAssertEqual(chunks[0].range, 0..<27)
        XCTAssertEqual(chunks[0].index, 0)
    }

    func testMultipleSentences() {
        let text = "First sentence. Second sentence! Third question?"
        let chunks = SentenceSplitter.split(text)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].text, "First sentence. ")
        XCTAssertEqual(chunks[1].text, "Second sentence! ")
        XCTAssertEqual(chunks[2].text, "Third question?")
    }

    func testAbbreviations() {
        let text = "Dr. Smith works at St. Mary's Hospital."
        let chunks = SentenceSplitter.split(text)

        // Should treat as single sentence despite abbreviations
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, text)
    }

    func testEmptyString() {
        let chunks = SentenceSplitter.split("")
        XCTAssertEqual(chunks.count, 0)
    }

    func testRangesAreAccurate() {
        let text = "First. Second. Third."
        let chunks = SentenceSplitter.split(text)

        for chunk in chunks {
            let startIdx = text.index(text.startIndex, offsetBy: chunk.range.lowerBound)
            let endIdx = text.index(text.startIndex, offsetBy: chunk.range.upperBound)
            let extracted = String(text[startIdx..<endIdx])

            XCTAssertEqual(extracted, chunk.text)
        }
    }
}
```

**Step 3: Run tests to verify they fail**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/SentenceSplitterTests 2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: Tests fail because files don't exist yet

**Step 4: Add SentenceSplitter.swift to project**

- Open Xcode
- Right-click `Services/TTS` folder
- New File → Swift File
- Name: `SentenceSplitter.swift`
- Add code from Step 1

**Step 5: Add SentenceSplitterTests.swift to test target**

- Right-click `Listen2Tests/Services/TTS` folder
- New File → Unit Test Case Class
- Name: `SentenceSplitterTests`
- Replace with code from Step 2

**Step 6: Run tests to verify they pass**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/SentenceSplitterTests 2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: All 5 tests pass

**Step 7: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SentenceSplitter.swift \
        Listen2/Listen2/Listen2Tests/Services/TTS/SentenceSplitterTests.swift
git commit -m "feat: add SentenceSplitter for chunked synthesis

- Implement sentence splitting using NLTokenizer
- Handle abbreviations (Dr., St., etc.) correctly
- Return chunks with Int-based character ranges
- Add comprehensive test suite with 5 test cases
- Foundation for sentence-level chunking in Phase 2"
```

---

### Task 7: Add Streaming Callbacks to sherpa-onnx C API

**Files:**
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.h`
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.cc`

**Step 1: Add callback typedef to c-api.h**

Add after existing typedefs (around line 50):

```c
/// Callback for streaming audio chunks during synthesis
/// @param samples Audio samples (float array)
/// @param n Number of samples
/// @param progress Synthesis progress (0.0 to 1.0)
/// @param user_data User-provided context pointer
/// @return 1 to continue synthesis, 0 to cancel
typedef int32_t (*SherpaOnnxGeneratedAudioCallback)(
    const float *samples,
    int32_t n,
    float progress,
    void *user_data
);
```

**Step 2: Add callback parameter to generation function**

Find `SherpaOfflineTtsGenerate` function declaration and add callback version:

```c
/// Generate audio with streaming callback
/// Callback is fired after each sentence/batch completes
SHERPA_ONNX_API const SherpaOfflineTtsGeneratedAudio *
SherpaOfflineTtsGenerateWithCallback(
    const SherpaOfflineTts *tts,
    const char *text,
    int64_t sid,
    float speed,
    SherpaOnnxGeneratedAudioCallback callback,
    void *user_data
);
```

**Step 3: Implement callback bridge in c-api.cc**

Add implementation:

```cpp
const SherpaOfflineTtsGeneratedAudio *
SherpaOfflineTtsGenerateWithCallback(
    const SherpaOfflineTts *tts,
    const char *text,
    int64_t sid,
    float speed,
    SherpaOnnxGeneratedAudioCallback c_callback,
    void *user_data
) {
    // Bridge C callback to C++ GeneratedAudioCallback
    sherpa_onnx::GeneratedAudioCallback cpp_callback = nullptr;

    if (c_callback) {
        cpp_callback = [c_callback, user_data](
            const float *samples, int32_t n, float progress
        ) -> int32_t {
            return c_callback(samples, n, progress, user_data);
        };
    }

    // Call C++ Generate with callback
    auto audio = tts->impl->Generate(text, sid, speed, cpp_callback);

    // Convert to C struct (same as non-callback version)
    auto r = new SherpaOfflineTtsGeneratedAudio;
    r->samples = audio.samples.data();
    r->n = audio.samples.size();
    r->sample_rate = audio.sample_rate;
    // ... copy other fields

    return r;
}
```

**Step 4: Build sherpa-onnx with callback support**

```bash
cd /Users/zachswift/projects/sherpa-onnx
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j8
```

Expected: Build succeeds with new callback functions

**Step 5: Rebuild iOS framework with callbacks**

```bash
cd /Users/zachswift/projects/sherpa-onnx
./build-ios.sh
```

Expected: sherpa-onnx.xcframework rebuilt with callback support

**Step 6: Commit**

```bash
cd /Users/zachswift/projects/sherpa-onnx
git add sherpa-onnx/c-api/c-api.h sherpa-onnx/c-api/c-api.cc
git commit -m "feat: add streaming callback support to C API

- Add SherpaOnnxGeneratedAudioCallback typedef
- Add SherpaOfflineTtsGenerateWithCallback function
- Bridge C callback to C++ GeneratedAudioCallback
- Enables sentence-level streaming to Swift layer
- Foundation for zero-gap playback with async synthesis"
```

---

### Task 8: Bridge ONNX Callbacks to Swift

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`
- Create: `Listen2/Listen2/Listen2/Services/TTS/SynthesisStreamDelegate.swift`

**Step 1: Create Swift callback delegate protocol**

```swift
//
//  SynthesisStreamDelegate.swift
//  Listen2
//

import Foundation

/// Delegate for receiving streaming synthesis callbacks
protocol SynthesisStreamDelegate: AnyObject {
    /// Called when an audio chunk is ready
    /// - Parameters:
    ///   - chunk: Audio samples (Float array)
    ///   - progress: Synthesis progress (0.0 to 1.0)
    /// - Returns: true to continue, false to cancel
    func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool
}
```

**Step 2: Add callback wrapper to SherpaOnnx.swift**

Add to `SherpaOnnx` class:

```swift
/// Synthesize with streaming callback
/// - Parameters:
///   - text: Text to synthesize
///   - speed: Playback speed multiplier
///   - delegate: Callback delegate for streaming chunks
/// - Returns: Complete synthesis result
func synthesizeWithStreaming(
    _ text: String,
    speed: Float = 1.0,
    delegate: SynthesisStreamDelegate?
) async throws -> GeneratedAudio {

    return try await withCheckedThrowingContinuation { continuation in
        var allSamples: [Float] = []
        var sampleRate: Int32 = 22050
        var cancelled = false

        // Create context to pass to C callback
        class CallbackContext {
            weak var delegate: SynthesisStreamDelegate?
            var allSamples: [Float] = []
            var cancelled: Bool = false

            init(delegate: SynthesisStreamDelegate?) {
                self.delegate = delegate
            }
        }

        let context = CallbackContext(delegate: delegate)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        // C callback function
        let callback: SherpaOnnxGeneratedAudioCallback = { samples, n, progress, userData in
            guard let userData = userData else { return 0 }
            let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()

            // Convert samples to Data
            let buffer = UnsafeBufferPointer(start: samples, count: Int(n))
            let floatArray = Array(buffer)
            let data = Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float>.stride)

            // Accumulate samples
            context.allSamples.append(contentsOf: floatArray)

            // Call delegate
            if let delegate = context.delegate {
                let shouldContinue = delegate.didReceiveAudioChunk(data, progress: Double(progress))
                if !shouldContinue {
                    context.cancelled = true
                    return 0  // Cancel synthesis
                }
            }

            return 1  // Continue synthesis
        }

        // Call C API with callback
        text.withCString { textPtr in
            guard let audio = SherpaOfflineTtsGenerateWithCallback(
                tts,
                textPtr,
                0,  // speaker ID
                speed,
                callback,
                contextPtr
            ) else {
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
                continuation.resume(throwing: SherpaOnnxError.synthesisFailed)
                return
            }

            // Extract final result
            sampleRate = audio.pointee.sample_rate

            // Free C struct
            SherpaOfflineTtsDestroyGeneratedAudio(audio)
            Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()

            // Return result
            let result = GeneratedAudio(
                samples: context.allSamples,
                sampleRate: Int(sampleRate),
                phonemes: [],  // TODO: extract from audio struct
                normalizedText: "",
                charMapping: []
            )

            continuation.resume(returning: result)
        }
    }
}
```

**Step 3: Write test for callback mechanism**

Create: `Listen2/Listen2/Listen2Tests/Services/TTS/StreamingCallbackTests.swift`

```swift
//
//  StreamingCallbackTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class StreamingCallbackTests: XCTestCase {

    class TestDelegate: SynthesisStreamDelegate {
        var chunks: [Data] = []
        var progressValues: [Double] = []

        func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
            chunks.append(chunk)
            progressValues.append(progress)
            return true  // Continue
        }
    }

    func testStreamingCallback() async throws {
        // Initialize sherpa-onnx (assumes test model available)
        let sherpaOnnx = try SherpaOnnx(
            modelPath: "path/to/test/model.onnx",
            tokensPath: "path/to/tokens.txt",
            dataDir: "path/to/espeak-ng-data"
        )

        let delegate = TestDelegate()

        let text = "First sentence. Second sentence. Third sentence."
        let result = try await sherpaOnnx.synthesizeWithStreaming(
            text,
            speed: 1.0,
            delegate: delegate
        )

        // Verify callbacks were called
        XCTAssertGreaterThan(delegate.chunks.count, 0, "Should receive at least one chunk")
        XCTAssertGreaterThan(delegate.progressValues.count, 0, "Should receive progress updates")

        // Verify progress increases
        for i in 1..<delegate.progressValues.count {
            XCTAssertGreaterThanOrEqual(
                delegate.progressValues[i],
                delegate.progressValues[i-1],
                "Progress should increase"
            )
        }

        // Verify final audio exists
        XCTAssertGreaterThan(result.samples.count, 0, "Should have audio samples")
    }
}
```

**Step 4: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 5: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift \
        Listen2/Listen2/Listen2/Services/TTS/SynthesisStreamDelegate.swift \
        Listen2/Listen2/Listen2Tests/Services/TTS/StreamingCallbackTests.swift
git commit -m "feat: bridge ONNX streaming callbacks to Swift

- Add SynthesisStreamDelegate protocol
- Implement synthesizeWithStreaming() in SherpaOnnx
- Bridge C callbacks to Swift closures
- Add comprehensive test suite
- Foundation for sentence-by-sentence streaming playback"
```

---

### Task 9: Create SentenceSynthesisResult Model

**Files:**
- Create: `Listen2/Listen2/Listen2/Services/TTS/SentenceSynthesisResult.swift`

**Step 1: Create model struct**

```swift
//
//  SentenceSynthesisResult.swift
//  Listen2
//

import Foundation

/// Result of synthesizing a single sentence chunk
struct SentenceSynthesisResult {
    /// The sentence chunk that was synthesized
    let chunk: SentenceChunk

    /// Synthesized audio data (WAV format)
    let audioData: Data

    /// Word-level alignment for this sentence
    let alignment: AlignmentResult?

    /// Audio duration in seconds
    var audioDuration: Double {
        // WAV header is 44 bytes, then 16-bit samples at 22050 Hz
        guard audioData.count > 44 else { return 0 }
        let sampleCount = (audioData.count - 44) / 2
        return Double(sampleCount) / 22050.0
    }
}

/// Container for all sentences in a paragraph
struct ParagraphSynthesisResult {
    /// Paragraph index
    let paragraphIndex: Int

    /// All sentence results (ordered)
    let sentences: [SentenceSynthesisResult]

    /// Concatenated audio data for entire paragraph
    var combinedAudioData: Data {
        // Concatenate audio data (skip WAV headers for sentences 2+)
        guard !sentences.isEmpty else { return Data() }

        var combined = sentences[0].audioData

        for sentence in sentences.dropFirst() {
            // Skip 44-byte WAV header on subsequent chunks
            let audioOnly = sentence.audioData.dropFirst(44)
            combined.append(audioOnly)
        }

        return combined
    }

    /// Combined alignment for entire paragraph
    var combinedAlignment: AlignmentResult? {
        guard !sentences.isEmpty else { return nil }

        // TODO: Implement alignment concatenation in Task 9
        // For now, return first sentence alignment
        return sentences.first?.alignment
    }

    /// Total duration of paragraph in seconds
    var totalDuration: Double {
        sentences.reduce(0.0) { $0 + $1.audioDuration }
    }
}
```

**Step 2: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 3: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SentenceSynthesisResult.swift
git commit -m "feat: add SentenceSynthesisResult models

- SentenceSynthesisResult for individual sentence chunks
- ParagraphSynthesisResult for combined paragraph results
- Audio concatenation logic (skip WAV headers)
- Duration calculation for timing
- Stub for alignment concatenation (implemented in Task 9)"
```

---

### Task 10: Refactor SynthesisQueue with Streaming Callbacks + Async Synthesis

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`
- Modify: `Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift`

**Key Insight:** Use ONNX callbacks for streaming + Swift Tasks for parallel async synthesis = zero gaps!

**Step 1: Add sentence-level cache structure**

Add after line 21 (alignments cache):

```swift
/// Cache of sentence-level synthesis results
/// Key: paragraph index, Value: array of sentence results
private var sentenceCache: [Int: [SentenceSynthesisResult]] = [:]

/// Tracks which sentences are currently being synthesized
/// Key format: "paragraphIndex-sentenceIndex"
private var synthesizingSentences: Set<String> = []
```

**Step 2: Add streaming synthesis delegate implementation**

Add conformance to SynthesisStreamDelegate:

```swift
// Add to SynthesisQueue class
extension SynthesisQueue: SynthesisStreamDelegate {
    func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool {
        // Store chunk for currently synthesizing sentence
        // This is called from ONNX thread - update on main actor
        Task { @MainActor in
            if let currentIndex = currentlySynthesizing {
                synthesisProgress[currentIndex] = progress
            }
        }

        return true  // Continue synthesis
    }
}
```

**Step 3: Add async sentence synthesis with callbacks**

Add after `getAlignment` method (around line 148):

```swift
/// Synthesize a single sentence with streaming callbacks
/// Uses ONNX streaming for progress + async for parallelization
/// - Parameters:
///   - paragraphIndex: The paragraph index
///   - sentenceIndex: The sentence index within paragraph
/// - Returns: Sentence synthesis result
private func synthesizeSentenceAsync(paragraphIndex: Int, sentenceIndex: Int) async throws -> SentenceSynthesisResult {
    let key = "\(paragraphIndex)-\(sentenceIndex)"

    // Get paragraph text
    guard paragraphIndex < paragraphs.count else {
        throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
    }

    let paragraphText = paragraphs[paragraphIndex]
    let chunks = SentenceSplitter.split(paragraphText)

    guard sentenceIndex < chunks.count else {
        throw TTSError.synthesisFailed(reason: "Invalid sentence index")
    }

    let chunk = chunks[sentenceIndex]

    // Mark as synthesizing
    await MainActor.run {
        synthesizingSentences.insert(key)
        currentlySynthesizing = paragraphIndex
        synthesisProgress[paragraphIndex] = Double(sentenceIndex) / Double(chunks.count)
    }

    // Synthesize with streaming callback (ONNX native streaming!)
    let result = try await provider.synthesizeWithStreaming(
        chunk.text,
        speed: speed,
        delegate: self  // Receive progress callbacks
    )

    // Perform alignment for this sentence
    let alignment = await performAlignmentForSentence(
        paragraphIndex: paragraphIndex,
        chunk: chunk,
        result: result
    )

    let sentenceResult = SentenceSynthesisResult(
        chunk: chunk,
        audioData: result.audioData,
        alignment: alignment
    )

    // Cache the result
    await MainActor.run {
        if sentenceCache[paragraphIndex] == nil {
            sentenceCache[paragraphIndex] = []
        }
        sentenceCache[paragraphIndex]?.append(sentenceResult)
        synthesizingSentences.remove(key)

        // Update progress
        let completedCount = sentenceCache[paragraphIndex]?.count ?? 0
        synthesisProgress[paragraphIndex] = Double(completedCount) / Double(chunks.count)

        if completedCount == chunks.count {
            currentlySynthesizing = nil
        }
    }

    return sentenceResult
}
```

**Step 4: Add parallel async synthesis for all sentences**

Add new method:

```swift
/// Synthesize all sentences in a paragraph concurrently
/// This is where the magic happens - PARALLEL SYNTHESIS!
/// - Parameter index: Paragraph index
func synthesizeAllSentencesAsync(for index: Int) {
    guard index < paragraphs.count else { return }

    let paragraphText = paragraphs[index]
    let chunks = SentenceSplitter.split(paragraphText)

    // Launch parallel synthesis tasks for ALL sentences
    for sentenceIndex in 0..<chunks.count {
        let key = "\(index)-\(sentenceIndex)"
        guard !synthesizingSentences.contains(key) else { continue }

        Task {
            do {
                _ = try await synthesizeSentenceAsync(
                    paragraphIndex: index,
                    sentenceIndex: sentenceIndex
                )
                print("[SynthesisQueue] ✅ Sentence \(sentenceIndex+1)/\(chunks.count) ready")
            } catch {
                print("[SynthesisQueue] ❌ Sentence \(sentenceIndex) failed: \(error)")
            }
        }
    }
}
```

**Step 3: Add alignment helper for sentences**

```swift
/// Perform alignment for a sentence chunk
private func performAlignmentForSentence(paragraphIndex: Int, chunk: SentenceChunk, result: SynthesisResult) async -> AlignmentResult? {
    // Check cache first
    if let documentID = documentID,
       let cached = await alignmentCache.loadAlignment(
           documentID: documentID,
           paragraphIndex: paragraphIndex,
           speedMultiplier: speed
       ) {
        // TODO: Extract alignment for this sentence's range
        // For now, return full paragraph alignment
        return cached
    }

    // Perform alignment for sentence
    guard let wordMap = wordMap else { return nil }

    let alignment = await alignmentService.align(
        phonemes: result.phonemes,
        normalizedText: result.normalizedText,
        characterMapping: result.characterMapping,
        wordMap: wordMap,
        paragraphIndex: paragraphIndex,
        originalText: chunk.text  // Use sentence text, not full paragraph
    )

    // Don't cache sentence-level alignments individually
    // They'll be combined and cached at paragraph level

    return alignment
}
```

**Step 5: Update PiperTTSProvider to support streaming**

Modify `PiperTTSProvider.swift`:

```swift
/// Synthesize with streaming callback support
func synthesizeWithStreaming(
    _ text: String,
    speed: Float,
    delegate: SynthesisStreamDelegate?
) async throws -> SynthesisResult {

    // Use sherpa-onnx streaming API
    let audio = try await sherpaOnnx.synthesizeWithStreaming(
        text,
        speed: speed,
        delegate: delegate
    )

    return SynthesisResult(
        audioData: audio.toWAVData(),
        phonemes: audio.phonemes,
        normalizedText: audio.normalizedText,
        characterMapping: audio.charMapping
    )
}
```

**Step 6: Refactor getAudio to use async sentence synthesis**

Replace `getAudio(for index:)` implementation with:

```swift
/// Get synthesized audio for a paragraph, synthesizing if not cached
/// Uses sentence-level chunking for faster initial playback
/// - Returns: Audio data if available, nil if synthesis is pending
func getAudio(for index: Int) async throws -> Data? {
    // Check if we have all sentences cached for this paragraph
    guard index < paragraphs.count else {
        throw TTSError.synthesisFailed(reason: "Invalid paragraph index")
    }

    let paragraphText = paragraphs[index]
    let chunks = SentenceSplitter.split(paragraphText)

    // Check if all sentences are cached
    if let cached = sentenceCache[index], cached.count == chunks.count {
        let paragraphResult = ParagraphSynthesisResult(
            paragraphIndex: index,
            sentences: cached.sorted { $0.chunk.index < $1.chunk.index }
        )

        // Cache combined alignment
        if let alignment = paragraphResult.combinedAlignment {
            alignments[index] = alignment
        }

        // Start pre-synthesizing upcoming paragraphs
        preSynthesizeAhead(from: index)

        return paragraphResult.combinedAudioData
    }

    // Kick off parallel synthesis for ALL sentences (async magic!)
    synthesizeAllSentencesAsync(for: index)

    // Wait for first sentence to complete
    let firstSentence = try await waitForSentence(paragraphIndex: index, sentenceIndex: 0)

    // Return first sentence audio to start playback immediately
    // Remaining sentences synthesize in parallel while this plays
    return firstSentence.audioData
}

/// Wait for a specific sentence to complete synthesis
private func waitForSentence(paragraphIndex: Int, sentenceIndex: Int) async throws -> SentenceSynthesisResult {
    let key = "\(paragraphIndex)-\(sentenceIndex)"

    // Poll until sentence is ready (or timeout)
    let maxWaitTime: TimeInterval = 300  // 5 minutes max
    let pollInterval: TimeInterval = 0.1  // Check every 100ms
    var elapsed: TimeInterval = 0

    while elapsed < maxWaitTime {
        // Check if sentence is cached
        if let cached = await MainActor.run(body: {
            sentenceCache[paragraphIndex]?.first(where: { $0.chunk.index == sentenceIndex })
        }) {
            return cached
        }

        // Wait a bit
        try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        elapsed += pollInterval
    }

    throw TTSError.synthesisFailed(reason: "Sentence synthesis timeout")
}
}
```

**Step 7: Update clearCache and clearAll methods**

Add to `clearCache(for index:)`:

```swift
sentenceCache.removeValue(forKey: index)
```

Add to `clearAll()`:

```swift
sentenceCache.removeAll()
synthesizingSentences.removeAll()
```

**Step 6: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 9: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift \
        Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift
git commit -m "feat: integrate ONNX streaming with async parallel synthesis

- Add SynthesisStreamDelegate conformance for callbacks
- Implement synthesizeSentenceAsync() with ONNX streaming
- Add synthesizeAllSentencesAsync() for parallel synthesis
- Update PiperTTSProvider with streaming support
- Refactor getAudio() to use async sentence synthesis
- MAGIC: Sentences synthesize in parallel while first plays
- Result: Zero gaps between sentences!"
```

---

### Task 11: Implement Alignment Concatenation

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift`
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SentenceSynthesisResult.swift`

**Step 1: Add concatenation method to AlignmentResult**

Add to `AlignmentResult` struct:

```swift
/// Concatenate multiple alignment results into one
/// Adjusts timing offsets for audio concatenation
/// - Parameters:
///   - alignments: Array of alignments to concatenate (in order)
/// - Returns: Combined alignment result
static func concatenate(_ alignments: [AlignmentResult]) -> AlignmentResult? {
    guard !alignments.isEmpty else { return nil }
    guard alignments.count > 1 else { return alignments.first }

    var allWordTimings: [WordTiming] = []
    var currentTimeOffset: Double = 0.0
    var currentCharOffset: Int = 0

    for alignment in alignments {
        // Adjust word timings for this chunk
        for wordTiming in alignment.wordTimings {
            let adjustedTiming = WordTiming(
                word: wordTiming.word,
                startTime: wordTiming.startTime + currentTimeOffset,
                duration: wordTiming.duration,
                startOffset: wordTiming.startOffset + currentCharOffset,
                length: wordTiming.length
            )
            allWordTimings.append(adjustedTiming)
        }

        // Update offsets for next chunk
        if let lastTiming = alignment.wordTimings.last {
            currentTimeOffset += lastTiming.startTime + lastTiming.duration
        }

        // Character offset is the sum of all previous text lengths
        // This assumes chunks are contiguous (which they are for sentences)
        if let lastTiming = alignment.wordTimings.last {
            currentCharOffset = lastTiming.startOffset + lastTiming.length
        }
    }

    return AlignmentResult(wordTimings: allWordTimings)
}
```

**Step 2: Update ParagraphSynthesisResult to use concatenation**

In `SentenceSynthesisResult.swift`, update `combinedAlignment`:

```swift
/// Combined alignment for entire paragraph
var combinedAlignment: AlignmentResult? {
    let alignments = sentences.compactMap { $0.alignment }
    guard !alignments.isEmpty else { return nil }

    return AlignmentResult.concatenate(alignments)
}
```

**Step 3: Write test for alignment concatenation**

Create: `Listen2/Listen2/Listen2Tests/Services/TTS/AlignmentConcatenationTests.swift`

```swift
//
//  AlignmentConcatenationTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class AlignmentConcatenationTests: XCTestCase {

    func testConcatenateTwoAlignments() {
        let alignment1 = AlignmentResult(wordTimings: [
            AlignmentResult.WordTiming(word: "Hello", startTime: 0.0, duration: 0.5, startOffset: 0, length: 5),
            AlignmentResult.WordTiming(word: "world", startTime: 0.5, duration: 0.4, startOffset: 6, length: 5)
        ])

        let alignment2 = AlignmentResult(wordTimings: [
            AlignmentResult.WordTiming(word: "This", startTime: 0.0, duration: 0.3, startOffset: 0, length: 4),
            AlignmentResult.WordTiming(word: "works", startTime: 0.3, duration: 0.4, startOffset: 5, length: 5)
        ])

        let combined = AlignmentResult.concatenate([alignment1, alignment2])!

        XCTAssertEqual(combined.wordTimings.count, 4)

        // First sentence timings unchanged
        XCTAssertEqual(combined.wordTimings[0].word, "Hello")
        XCTAssertEqual(combined.wordTimings[0].startTime, 0.0)
        XCTAssertEqual(combined.wordTimings[1].word, "world")
        XCTAssertEqual(combined.wordTimings[1].startTime, 0.5)

        // Second sentence timings offset by first sentence duration
        XCTAssertEqual(combined.wordTimings[2].word, "This")
        XCTAssertEqual(combined.wordTimings[2].startTime, 0.9)  // 0.5 + 0.4
        XCTAssertEqual(combined.wordTimings[3].word, "works")
        XCTAssertEqual(combined.wordTimings[3].startTime, 1.2)  // 0.9 + 0.3

        // Character offsets
        XCTAssertEqual(combined.wordTimings[2].startOffset, 11)  // 6 + 5
        XCTAssertEqual(combined.wordTimings[3].startOffset, 16)  // 11 + 5
    }

    func testConcatenateEmptyArray() {
        let combined = AlignmentResult.concatenate([])
        XCTAssertNil(combined)
    }

    func testConcatenateSingleAlignment() {
        let alignment = AlignmentResult(wordTimings: [
            AlignmentResult.WordTiming(word: "test", startTime: 0.0, duration: 0.5, startOffset: 0, length: 4)
        ])

        let combined = AlignmentResult.concatenate([alignment])
        XCTAssertEqual(combined?.wordTimings.count, 1)
        XCTAssertEqual(combined?.wordTimings[0].word, "test")
    }
}
```

**Step 4: Run tests**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Listen2Tests/AlignmentConcatenationTests 2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: All 3 tests pass

**Step 5: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/AlignmentResult.swift \
        Listen2/Listen2/Listen2/Services/TTS/SentenceSynthesisResult.swift \
        Listen2/Listen2/Listen2Tests/Services/TTS/AlignmentConcatenationTests.swift
git commit -m "feat: implement alignment concatenation for sentence chunks

- Add AlignmentResult.concatenate() method
- Adjusts timing offsets for concatenated audio
- Adjusts character offsets for sentence boundaries
- Update ParagraphSynthesisResult to use concatenation
- Add comprehensive test suite (3 tests)
- Enables accurate word highlighting across sentences"
```

---

### Task 12: Update Playback for Sentence-by-Sentence Streaming

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Add streaming audio playback support to SynthesisQueue**

Add new method to `SynthesisQueue.swift`:

```swift
/// Stream audio for a paragraph sentence-by-sentence
/// - Parameter index: Paragraph index
/// - Returns: AsyncStream of sentence audio data chunks
func streamAudio(for index: Int) -> AsyncStream<Data> {
    AsyncStream { continuation in
        Task {
            guard index < paragraphs.count else {
                continuation.finish()
                return
            }

            let paragraphText = paragraphs[index]
            let chunks = SentenceSplitter.split(paragraphText)

            for sentenceIndex in 0..<chunks.count {
                do {
                    if let sentence = try await getAudioForSentence(
                        paragraphIndex: index,
                        sentenceIndex: sentenceIndex
                    ) {
                        continuation.yield(sentence.audioData)
                    }
                } catch {
                    print("[SynthesisQueue] Error streaming sentence \(sentenceIndex): \(error)")
                }
            }

            continuation.finish()
        }
    }
}
```

**Step 2: Update TTSService to use streaming playback**

In `TTSService.swift`, update the playback logic (around line 396-408):

```swift
Task {
    do {
        // Use streaming playback for sentence-by-sentence audio
        for await audioChunk in queue.streamAudio(for: index) {
            // Play each sentence as it becomes available
            try await playAudio(audioChunk)

            // Wait for audio to finish before playing next sentence
            // (In a more advanced implementation, we'd queue up audio)
            try await Task.sleep(nanoseconds: UInt64(getAudioDuration(audioChunk) * 1_000_000_000))
        }
    } catch {
        print("[TTSService] ⚠️ Piper synthesis failed: \(error)")

        if useFallback {
            print("[TTSService] Falling back to AVSpeech")
            await MainActor.run {
                self.fallbackToAVSpeech(text: text)
            }
        } else {
            print("[TTSService] Fallback disabled - stopping playback")
            await MainActor.run {
                self.isPlaying = false
            }
        }
    }
}
```

**Step 3: Add helper to calculate audio duration**

Add to `TTSService.swift`:

```swift
private func getAudioDuration(_ audioData: Data) -> Double {
    // WAV header is 44 bytes, then 16-bit samples at 22050 Hz
    guard audioData.count > 44 else { return 0 }
    let sampleCount = (audioData.count - 44) / 2
    return Double(sampleCount) / 22050.0
}
```

**Step 4: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 5: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift \
        Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: implement streaming sentence-by-sentence playback

- Add streamAudio() method to SynthesisQueue
- Update TTSService to use streaming playback
- Play sentences as they become available
- Add audio duration helper for timing
- Achieves <10s time-to-first-audio goal"
```

---

### Task 13: Manual Device Testing - Phase 2

**Goal:** Verify sentence chunking reduces time-to-first-audio

**Files:**
- Test on: iPhone (physical device)

**Step 1: Build and deploy**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)' 2>&1 | grep -E "BUILD SUCCEEDED"
```

**Step 2: Test short paragraph (2-3 sentences)**

Expected:
- First sentence plays within 5-10 seconds
- Subsequent sentences play smoothly
- Word highlighting works across sentence boundaries
- No gaps or stuttering between sentences

**Step 3: Test long paragraph (10+ sentences)**

Expected:
- First sentence plays within 5-10 seconds (not 2-3 minutes!)
- Remaining sentences stream in background
- Smooth playback throughout
- Progress indicator shows synthesis progress

**Step 4: Test alignment accuracy**

Load PDF with abbreviations, verify:
- Word highlighting works in first sentence
- Word highlighting works across sentence boundaries
- Timing is accurate for all sentences
- No offset errors in later sentences

**Step 5: Measure performance**

Time from "play" to first audio:
- Short paragraphs: [X] seconds
- Long paragraphs: [X] seconds

Compare to Phase 1 (should be much faster!)

**Step 6: Collect results**

```bash
workshop note "Phase 2 testing complete - time-to-first-audio: [X]s"
workshop decision "Sentence chunking achieves <10s playback" -r "Tested with 374-word paragraph, first sentence played in [X] seconds"
```

**Step 7: Mark complete only if tests pass**

> **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion

Verify:
- [x] Time-to-first-audio < 10 seconds
- [x] Smooth playback between sentences
- [x] Word highlighting accurate across boundaries
- [x] No audio gaps or stuttering
- [x] Progress indicator shows synthesis status

---

## Phase 3: Integration & Polish

**Goal:** Combine eager pre-synthesis + sentence chunking for production UX

### Task 14: Enable Sentence-Level Pre-Synthesis

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Update startPreSynthesis for sentence-level**

Modify `startPreSynthesis` to pre-synthesize first sentence of upcoming paragraphs:

```swift
/// Start pre-synthesizing first sentences of upcoming paragraphs
/// - Parameter paragraphCount: Number of paragraphs to pre-synthesize (default 3)
func startPreSynthesis(paragraphCount: Int = 3) {
    let endIndex = min(paragraphCount - 1, paragraphs.count - 1)

    for paragraphIndex in 0...endIndex {
        guard paragraphIndex < paragraphs.count else { continue }

        // Pre-synthesize just the first sentence of each paragraph
        // for fast transitions
        Task {
            do {
                _ = try await getAudioForSentence(
                    paragraphIndex: paragraphIndex,
                    sentenceIndex: 0
                )
            } catch {
                print("[SynthesisQueue] Pre-synthesis failed for paragraph \(paragraphIndex): \(error)")
            }
        }
    }
}
```

**Step 2: Update preSynthesizeAhead to use sentences**

Modify `preSynthesizeAhead` to pre-synthesize first sentence only:

```swift
private func preSynthesizeAhead(from currentIndex: Int) {
    // Calculate range of paragraphs to pre-synthesize
    let startIndex = currentIndex + 1
    let endIndex = min(currentIndex + lookaheadCount, paragraphs.count - 1)

    for index in startIndex...endIndex {
        guard index < paragraphs.count else { continue }

        // Pre-synthesize first sentence only for fast transitions
        let key = "\(index)-0"
        guard !synthesizingSentences.contains(key) else { continue }

        Task {
            do {
                _ = try await getAudioForSentence(
                    paragraphIndex: index,
                    sentenceIndex: 0
                )
            } catch {
                print("[SynthesisQueue] Lookahead synthesis failed for paragraph \(index): \(error)")
            }
        }
    }
}
```

**Step 3: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 4: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git commit -m "feat: enable sentence-level pre-synthesis for lookahead

- Update startPreSynthesis() for first-sentence-only
- Update preSynthesizeAhead() for fast transitions
- Pre-synthesize N paragraphs ahead (first sentences)
- Enables near-instant paragraph transitions
- Combines eager synthesis + sentence chunking"
```

---

### Task 15: Add Memory Management

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Add cache eviction configuration**

Add after `lookaheadCount` (line 15):

```swift
/// Maximum paragraphs to keep cached (current ± this value)
private let maxCachedParagraphs: Int = 5
```

**Step 2: Add eviction method**

```swift
/// Evict old cached data to free memory
/// Keeps only paragraphs within maxCachedParagraphs of currentIndex
private func evictOldCache(currentIndex: Int) {
    let minIndex = max(0, currentIndex - maxCachedParagraphs)
    let maxIndex = min(paragraphs.count - 1, currentIndex + maxCachedParagraphs)

    // Remove sentence cache outside range
    let outdatedParagraphs = sentenceCache.keys.filter { index in
        index < minIndex || index > maxIndex
    }

    for index in outdatedParagraphs {
        sentenceCache.removeValue(forKey: index)
        cache.removeValue(forKey: index)
        alignments.removeValue(forKey: index)
        synthesisProgress.removeValue(forKey: index)
    }

    if !outdatedParagraphs.isEmpty {
        print("[SynthesisQueue] Evicted \(outdatedParagraphs.count) old cached paragraphs")
    }
}
```

**Step 3: Call eviction after synthesis**

In `streamAudio(for index:)`, add at the end:

```swift
// Evict old cache after streaming starts
Task {
    try? await Task.sleep(nanoseconds: 500_000_000)  // Wait 500ms
    await evictOldCache(currentIndex: index)
}
```

**Step 4: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 5: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift
git commit -m "feat: add memory management with cache eviction

- Add maxCachedParagraphs configuration (default 5)
- Implement evictOldCache() to remove old paragraphs
- Automatically evict after synthesis starts
- Prevents unbounded memory growth on long documents
- Keeps memory usage reasonable (±5 paragraphs cached)"
```

---

### Task 16: Add Cancellation on Navigation

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift`

**Step 1: Add cancellation method**

```swift
/// Cancel synthesis for paragraphs outside the active range
/// Called when user jumps to different paragraph
func cancelOutsideRange(currentIndex: Int, range: Int = 10) {
    let minIndex = max(0, currentIndex - range)
    let maxIndex = min(paragraphs.count - 1, currentIndex + range)

    // Cancel tasks for paragraphs outside range
    for (index, task) in activeTasks {
        if index < minIndex || index > maxIndex {
            task.cancel()
            activeTasks.removeValue(forKey: index)
            synthesizing.remove(index)
            synthesisProgress.removeValue(forKey: index)
        }
    }

    // Cancel sentence synthesis outside range
    let outdatedKeys = synthesizingSentences.filter { key in
        let components = key.split(separator: "-")
        guard let paragraphIndex = Int(components[0]) else { return false }
        return paragraphIndex < minIndex || paragraphIndex > maxIndex
    }

    synthesizingSentences.subtract(outdatedKeys)
}
```

**Step 2: Call cancellation on paragraph change**

In `TTSService.swift`, add to `speakParagraph(at index:)` method:

```swift
// Cancel synthesis for paragraphs far from current
synthesisQueue?.cancelOutsideRange(currentIndex: index, range: 10)
```

**Step 3: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 4: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTS/SynthesisQueue.swift \
        Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: cancel synthesis when user navigates away

- Add cancelOutsideRange() to stop irrelevant synthesis
- Call on paragraph navigation
- Prevents wasted resources on skipped paragraphs
- Improves responsiveness when jumping around document"
```

---

### Task 17: Re-enable iOS Fallback with Proper Cancellation

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Add fallback state tracking**

Add after line 40 (currentDocumentID):

```swift
/// Track whether we're currently using fallback
private var isFallbackActive: Bool = false

/// Task handle for current synthesis (for cancellation)
private var currentSynthesisTask: Task<Void, Never>?
```

**Step 2: Update playback to track synthesis task**

In `speakParagraph(at index:)`, update Task assignment:

```swift
currentSynthesisTask = Task {
    do {
        // Use streaming playback for sentence-by-sentence audio
        for await audioChunk in queue.streamAudio(for: index) {
            // If fallback activated while we were synthesizing, stop
            guard !isFallbackActive else {
                print("[TTSService] Piper synthesis completed but fallback already active - discarding")
                return
            }

            try await playAudio(audioChunk)
            try await Task.sleep(nanoseconds: UInt64(getAudioDuration(audioChunk) * 1_000_000_000))
        }

        await MainActor.run {
            currentSynthesisTask = nil
        }

    } catch {
        await MainActor.run {
            currentSynthesisTask = nil
        }

        print("[TTSService] ⚠️ Piper synthesis failed: \(error)")

        if useFallback {
            print("[TTSService] Falling back to AVSpeech")
            await MainActor.run {
                self.isFallbackActive = true
                self.fallbackToAVSpeech(text: text)
            }
        } else {
            print("[TTSService] Fallback disabled - stopping playback")
            await MainActor.run {
                self.isPlaying = false
            }
        }
    }
}
```

**Step 3: Cancel Piper synthesis when fallback starts**

Update `fallbackToAVSpeech`:

```swift
private func fallbackToAVSpeech(text: String) {
    // Cancel any ongoing Piper synthesis
    currentSynthesisTask?.cancel()
    currentSynthesisTask = nil
    isFallbackActive = true

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = currentVoice
    utterance.rate = playbackRate * 0.5
    utterance.preUtteranceDelay = 0.0
    utterance.postUtteranceDelay = paragraphPauseDelay
    fallbackSynthesizer.speak(utterance)
}
```

**Step 4: Reset fallback state on new paragraph**

In `speakParagraph(at index:)`, add at the start:

```swift
// Reset fallback state for new paragraph
isFallbackActive = false
```

**Step 5: Re-enable fallback**

Change `useFallback` default value:

```swift
private var useFallback: Bool = true  // Re-enable with proper cancellation
```

**Step 6: Build and verify**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: "Build succeeded"

**Step 7: Commit**

```bash
cd /Users/zachswift/projects/Listen2
git add Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: re-enable iOS fallback with proper cancellation

- Add isFallbackActive and currentSynthesisTask tracking
- Cancel Piper synthesis when fallback starts
- Discard Piper results if fallback already active
- Reset fallback state on new paragraph
- Re-enable useFallback flag (default true)
- Prevents dual playback issue from Phase 1"
```

---

### Task 18: Final Device Testing - Phase 3

**Goal:** Verify production-ready performance and UX

**Files:**
- Test on: iPhone (physical device)

**Step 1: Build and deploy**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)' 2>&1 | grep -E "BUILD SUCCEEDED"
```

**Step 2: Test eager pre-synthesis**

- Load document
- Wait 10 seconds (let pre-synthesis run)
- Press play

Expected: Immediate playback (< 1 second to first audio)

**Step 3: Test paragraph transitions**

- Play through multiple paragraphs
- Observe transitions between paragraphs

Expected: Seamless transitions with no delays

**Step 4: Test memory management**

- Load 100+ paragraph document
- Play through 50 paragraphs
- Check memory usage (Xcode Instruments)

Expected: Memory usage stays reasonable (not growing unbounded)

**Step 5: Test navigation cancellation**

- Start playback
- Jump to paragraph 50 paragraphs ahead
- Observe synthesis behavior

Expected:
- Old synthesis tasks cancelled
- New paragraph synthesizes quickly
- No wasted resources on skipped paragraphs

**Step 6: Test fallback (error case)**

- Corrupt a model file or force an error
- Start playback

Expected:
- Piper fails gracefully
- Falls back to iOS voice
- No dual playback
- Fallback cancels if Piper completes

**Step 7: Test w_ceil + normalized text with chunking**

- Load PDF with abbreviations
- Play through multiple sentences

Expected:
- Word highlighting accurate across sentence boundaries
- "Dr." highlights correctly when "Doctor" spoken
- w_ceil provides accurate timing
- No alignment offset errors

**Step 8: Performance measurements**

Document:
- Time-to-first-audio: [X] seconds
- Paragraph transition time: [X] seconds
- Memory usage for 100-paragraph document: [X] MB
- Word highlighting accuracy: [subjective rating]

**Step 9: Record results**

```bash
workshop note "Phase 3 testing complete - production ready"
workshop decision "Hybrid approach achieves all performance goals" -r "Time-to-first-audio <10s, seamless transitions, memory managed, word highlighting accurate"
workshop next "Monitor production usage, consider future optimizations if needed"
```

**Step 10: Mark complete only if all tests pass**

> **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion

Verify:
- [x] Time-to-first-audio < 10 seconds
- [x] Paragraph transitions seamless (< 1 second)
- [x] Memory usage reasonable for long documents
- [x] Navigation cancels unnecessary synthesis
- [x] Fallback works without dual playback
- [x] Word highlighting accurate with chunking
- [x] w_ceil and normalized text fully functional
- [x] No crashes, freezes, or errors

---

## Summary

**Total Tasks:** 18 tasks across 3 phases

**Phase 1 (Tasks 1-5):** Unblock testing
- Add progress tracking
- Remove timeout
- Disable fallback
- Add eager pre-synthesis
- Test on device

**Phase 2 (Tasks 6-13):** ONNX streaming + async sentence chunking
- Create sentence splitter
- **Add ONNX streaming callbacks to C API** ⭐ NEW
- **Bridge callbacks to Swift** ⭐ NEW
- Add synthesis result models
- **Refactor SynthesisQueue with streaming + async** ⭐ ENHANCED
- Implement alignment concatenation
- Update playback for streaming
- Test on device

**Phase 3 (Tasks 14-18):** Production polish
- Enable sentence-level pre-synthesis
- Add memory management
- Add cancellation on navigation
- Re-enable fallback with fixes
- Final device testing

**Estimated Timeline:**
- Phase 1: 4-6 hours (unblock testing)
- Phase 2: 10-14 hours (ONNX streaming + async synthesis)
  - Tasks 7-8 (ONNX callbacks): 2-3 hours
  - Task 10 (async integration): 3-4 hours
  - Other tasks: 5-7 hours
- Phase 3: 4-6 hours (production polish)
- **Total: 18-26 hours (2.5-3.5 days)**

**Key Success Metrics:**
- ✅ Time-to-first-audio < 10 seconds
- ✅ **Zero gaps between sentences** (parallel synthesis) ⭐
- ✅ **Real-time streaming progress** (ONNX callbacks) ⭐
- ✅ Paragraph transitions < 1 second
- ✅ Memory usage bounded for long documents
- ✅ w_ceil and normalized text fully functional
- ✅ Word highlighting accurate across sentences
- ✅ Production-ready UX

---

**Next Steps:**

Choose execution approach:

1. **Subagent-Driven (recommended):** Execute in this session using superpowers:subagent-driven-development
   - Fresh subagent per task
   - Code review between tasks
   - Fast iteration

2. **Parallel Session:** Open new session and use superpowers:executing-plans
   - Batch execution
   - Review checkpoints between phases

Which approach would you like to use?
