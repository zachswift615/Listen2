# Premium Word-Level Highlighting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement premium-quality word-level highlighting using real phoneme durations from Piper's w_ceil tensor with robust text normalization handling.

**Architecture:** Extract actual phoneme durations from Piper VITS model's w_ceil tensor, build intelligent word correspondence mapping between display and synthesized text using edit distance, and implement dynamic programming-based alignment for 95%+ accuracy on technical content.

**Tech Stack:** C++ (sherpa-onnx modifications), Swift (alignment engine), ONNX Runtime (tensor extraction), Dynamic Programming (sequence alignment)

---

## Phase 1: Extract w_ceil Durations from Piper VITS

### Task 1: Understand w_ceil Tensor Structure

**Files:**
- Read: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h`
- Create: `/Users/zachswift/projects/Listen2/docs/technical/w_ceil_tensor_analysis.md`

**Step 1: Analyze current VITS implementation**

Read the Generate() method in offline-tts-vits-impl.h and locate where ONNX inference happens. Look for:
```cpp
// Around line 150-200
std::vector<Ort::Value> ort_outputs = session_->Run(
    Ort::RunOptions{nullptr},
    input_names_ptr.data(),
    ort_inputs.data(),
    ort_inputs.size(),
    output_names_ptr.data(),
    output_names_ptr.size()
);
```

**Step 2: Identify w_ceil in outputs**

The VITS model outputs multiple tensors. Document which index contains w_ceil:
```cpp
// Typical VITS outputs:
// ort_outputs[0] = audio samples
// ort_outputs[1] = w_ceil (durations in log scale)
// ort_outputs[2] = other tensors...
```

**Step 3: Document tensor shape and format**

Create technical documentation:
```markdown
# w_ceil Tensor Analysis

## Tensor Location
- Model: Piper VITS (en_US-amy-medium.onnx)
- Output Index: 1 (second output tensor)
- Shape: [1, num_phonemes]
- Data Type: float32

## Value Interpretation
- Values are in log-scale frame counts
- Need exp() to get actual frame count
- Frame rate: 256 samples per frame at 22050 Hz
- Duration in seconds = exp(w_ceil[i]) * 256 / 22050

## Current Status
- Tensor is present but discarded
- Need to extract and attach to GeneratedAudio
```

**Step 4: Commit documentation**

```bash
git add docs/technical/w_ceil_tensor_analysis.md
git commit -m "docs: analyze w_ceil tensor structure for duration extraction"
```

---

### Task 2: Add Duration Field to GeneratedAudio Struct

**Files:**
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts.h:45-60`
- Test: Create `/Users/zachswift/projects/sherpa-onnx/test_duration_extraction.cpp`

**Step 1: Write the test first**

```cpp
// test_duration_extraction.cpp
#include "sherpa-onnx/csrc/offline-tts.h"
#include <cassert>
#include <iostream>

void test_generated_audio_has_durations() {
    // This test will fail initially - GeneratedAudio doesn't have phoneme_durations yet
    GeneratedAudio audio;
    audio.phoneme_durations = {0.1f, 0.2f, 0.15f};
    assert(audio.phoneme_durations.size() == 3);
    assert(audio.phoneme_durations[0] == 0.1f);
    std::cout << "✓ GeneratedAudio can store phoneme durations" << std::endl;
}

int main() {
    test_generated_audio_has_durations();
    return 0;
}
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/zachswift/projects/sherpa-onnx
g++ -I. test_duration_extraction.cpp -std=c++14 -o test_duration
./test_duration
```
Expected: Compilation error "no member named 'phoneme_durations'"

**Step 3: Add phoneme_durations field to GeneratedAudio**

Modify `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts.h`:
```cpp
struct GeneratedAudio {
  // Existing fields around line 45-50
  std::vector<float> samples;
  float sample_rate;

  // Add this NEW field for phoneme durations (in seconds)
  std::vector<float> phoneme_durations;

  // Existing phoneme info field
  std::vector<PhonemeInfo> phonemes;
};
```

**Step 4: Run test to verify it passes**

```bash
g++ -I. test_duration_extraction.cpp -std=c++14 -o test_duration
./test_duration
```
Expected: "✓ GeneratedAudio can store phoneme durations"

**Step 5: Commit the change**

```bash
git add sherpa-onnx/csrc/offline-tts.h test_duration_extraction.cpp
git commit -m "feat: add phoneme_durations field to GeneratedAudio struct"
```

---

### Task 3: Extract w_ceil Tensor in VITS Generate()

**Files:**
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h:180-250`
- Test: Extend `/Users/zachswift/projects/sherpa-onnx/test_duration_extraction.cpp`

**Step 1: Write test for duration extraction**

Add to test_duration_extraction.cpp:
```cpp
void test_vits_extracts_durations() {
    // Create a mock VITS output to test extraction logic
    std::vector<float> w_ceil_log = {-2.3f, -1.8f, -2.0f};  // Log scale
    std::vector<float> expected_durations;

    for (float log_val : w_ceil_log) {
        float frames = std::exp(log_val);
        float duration = frames * 256.0f / 22050.0f;
        expected_durations.push_back(duration);
    }

    // This will test our extraction function
    std::vector<float> extracted = extract_durations_from_w_ceil(w_ceil_log);
    assert(extracted.size() == expected_durations.size());
    for (size_t i = 0; i < extracted.size(); ++i) {
        assert(std::abs(extracted[i] - expected_durations[i]) < 0.0001f);
    }
    std::cout << "✓ Duration extraction from w_ceil works correctly" << std::endl;
}
```

**Step 2: Add duration extraction logic**

Modify `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts-vits-impl.h`:
```cpp
// Around line 200, after ONNX inference
std::vector<Ort::Value> ort_outputs = session_->Run(...);

// Extract audio samples (existing code)
const float* p = ort_outputs[0].GetTensorData<float>();

// NEW: Extract w_ceil durations if available
std::vector<float> phoneme_durations;
if (ort_outputs.size() > 1) {
    // w_ceil is typically the second output
    auto w_ceil_info = ort_outputs[1].GetTensorTypeAndShapeInfo();
    size_t num_phonemes = w_ceil_info.GetElementCount();
    const float* w_ceil_data = ort_outputs[1].GetTensorData<float>();

    // Convert from log-scale frames to seconds
    const float frame_shift_ms = 256.0f / 22050.0f * 1000.0f;  // ~11.6ms per frame

    for (size_t i = 0; i < num_phonemes; ++i) {
        float log_frames = w_ceil_data[i];
        float frames = std::exp(log_frames);
        float duration_seconds = frames * frame_shift_ms / 1000.0f;
        phoneme_durations.push_back(duration_seconds);
    }

    SHERPA_ONNX_LOGE("Extracted %zu phoneme durations from w_ceil tensor",
                     phoneme_durations.size());
}

// Around line 250, when creating GeneratedAudio
GeneratedAudio audio;
audio.samples = std::move(samples);
audio.sample_rate = sample_rate;
audio.phoneme_durations = std::move(phoneme_durations);  // NEW
audio.phonemes = std::move(phoneme_sequences);  // Existing
```

**Step 3: Run tests**

```bash
cd /Users/zachswift/projects/sherpa-onnx
./build-ios.sh  # Rebuild with changes
```

**Step 4: Commit the changes**

```bash
git add sherpa-onnx/csrc/offline-tts-vits-impl.h
git commit -m "feat: extract phoneme durations from VITS w_ceil tensor"
```

---

### Task 4: Expose Durations Through C API

**Files:**
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.h:350-380`
- Modify: `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.cc:1320-1380`
- Test: Create `/Users/zachswift/projects/sherpa-onnx/test_c_api_durations.c`

**Step 1: Write C API test**

```c
// test_c_api_durations.c
#include "sherpa-onnx/c-api/c-api.h"
#include <assert.h>
#include <stdio.h>

void test_c_api_exposes_durations() {
    // Mock audio struct
    SherpaOnnxGeneratedAudio audio = {0};
    audio.n = 1000;  // samples
    audio.sample_rate = 22050;
    audio.num_phonemes = 3;

    // This will fail initially - no phoneme_durations field
    assert(audio.phoneme_durations != NULL);
    printf("✓ C API exposes phoneme durations\n");
}

int main() {
    test_c_api_exposes_durations();
    return 0;
}
```

**Step 2: Add durations to C API struct**

Modify `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.h`:
```c
// Around line 360
typedef struct SherpaOnnxGeneratedAudio {
  const float *samples;
  int32_t n;
  float sample_rate;

  // Existing phoneme fields
  int32_t num_phonemes;
  const char *const *phoneme_symbols;

  // NEW: Add phoneme durations array (in seconds)
  const float *phoneme_durations;

  // Existing position fields
  const int32_t *phoneme_char_start;
  const int32_t *phoneme_char_length;
} SherpaOnnxGeneratedAudio;
```

**Step 3: Populate durations in C API implementation**

Modify `/Users/zachswift/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.cc`:
```cpp
// Around line 1350, in SherpaOnnxOfflineTtsGenerate function
auto audio = tts->Generate(text, sid, speed);

// Create C struct
auto r = new SherpaOnnxGeneratedAudio;
r->samples = audio.samples.data();
r->n = audio.samples.size();
r->sample_rate = audio.sample_rate;

// Handle phonemes (existing code around line 1360)
r->num_phonemes = audio.phonemes.size();

if (!audio.phonemes.empty()) {
    // Existing symbol/position arrays...

    // NEW: Allocate and copy duration array
    if (!audio.phoneme_durations.empty()) {
        float* durations = new float[audio.phoneme_durations.size()];
        std::copy(audio.phoneme_durations.begin(),
                  audio.phoneme_durations.end(),
                  durations);
        r->phoneme_durations = durations;

        fprintf(stderr, "[SHERPA_C_API] Exposed %d phoneme durations through C API\n",
                r->num_phonemes);
    } else {
        r->phoneme_durations = nullptr;
        fprintf(stderr, "[SHERPA_C_API] No phoneme durations available\n");
    }
}
```

**Step 4: Test and verify**

```bash
gcc -I. test_c_api_durations.c -L./build-ios -lsherpa-onnx -o test_c_api
./test_c_api
```

**Step 5: Commit**

```bash
git add sherpa-onnx/c-api/c-api.h sherpa-onnx/c-api/c-api.cc
git commit -m "feat: expose phoneme durations through C API"
```

---

### Task 5: Build iOS Framework with Duration Support

**Files:**
- Run: `/Users/zachswift/projects/sherpa-onnx/build-ios.sh`
- Verify: Check framework symbols

**Step 1: Clean build directory**

```bash
cd /Users/zachswift/projects/sherpa-onnx
rm -rf build-ios
```

**Step 2: Run iOS build**

```bash
./build-ios.sh 2>&1 | tee build-ios-durations.log
```
Expected: Build completes with exit code 0 (15-20 minutes)

**Step 3: Verify durations in framework**

```bash
# Check that struct has phoneme_durations field
nm build-ios/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a | grep -i duration
```
Expected: Should see symbols related to duration

**Step 4: Copy framework to Listen2**

```bash
rm -rf /Users/zachswift/projects/Listen2/Frameworks/sherpa-onnx.xcframework
cp -R build-ios/sherpa-onnx.xcframework /Users/zachswift/projects/Listen2/Frameworks/
```

**Step 5: Commit framework update timestamp**

```bash
cd /Users/zachswift/projects/Listen2
echo "Framework updated: $(date)" >> Frameworks/FRAMEWORK_VERSION.txt
git add Frameworks/FRAMEWORK_VERSION.txt
git commit -m "chore: update sherpa-onnx framework with duration support"
```

---

## Phase 2: Swift Integration of Durations

### Task 6: Update Swift Bridge to Read Durations

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift:150-180`
- Test: Create `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2Tests/DurationExtractionTests.swift`

**Step 1: Write Swift test for duration extraction**

```swift
// DurationExtractionTests.swift
import XCTest
@testable import Listen2

class DurationExtractionTests: XCTestCase {

    func testExtractsPhonemeDurations() {
        // This will initially fail - we haven't updated the extraction code
        let testText = "Hello"
        let provider = PiperTTSProvider()

        let expectation = self.expectation(description: "Synthesis completes")

        Task {
            do {
                let result = try await provider.synthesize(testText, speed: 1.0)

                // Should have non-zero durations
                XCTAssertFalse(result.phonemes.isEmpty)

                let firstPhoneme = result.phonemes.first!
                XCTAssertGreaterThan(firstPhoneme.duration, 0,
                                    "Phoneme should have non-zero duration")

                // Total duration should roughly match audio length
                let totalDuration = result.phonemes.reduce(0.0) { $0 + $1.duration }
                let audioDuration = Double(result.audioData.count) / (2 * 22050) // 16-bit, 22kHz
                XCTAssertEqual(totalDuration, audioDuration, accuracy: 0.5,
                              "Phoneme durations should sum to approximately audio duration")

                expectation.fulfill()
            } catch {
                XCTFail("Synthesis failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
```

**Step 2: Update PhonemeInfo extraction to read durations**

Modify `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`:
```swift
// Around line 160, in extractPhonemes function
if let symbolsPtr = audio.pointee.phoneme_symbols,
   let startsPtr = audio.pointee.phoneme_char_start,
   let lengthsPtr = audio.pointee.phoneme_char_length {

    // NEW: Also get durations pointer
    let durationsPtr = audio.pointee.phoneme_durations  // May be nil

    for i in 0..<phonemeCount {
        let symbol = String(cString: symbolsPtr[i])
        let start = Int(startsPtr[i])
        let length = Int(lengthsPtr[i])

        // NEW: Read actual duration or use estimate
        let duration: TimeInterval
        if let durationsPtr = durationsPtr {
            duration = TimeInterval(durationsPtr[i])
            if i == 0 {
                print("[SherpaOnnx] First phoneme has duration: \(duration)s")
            }
        } else {
            // Fallback: estimate 50ms per phoneme
            duration = 0.05
        }

        // Validate range to prevent crashes
        guard start >= 0, length >= 0 else {
            print("[SherpaOnnx] Warning: Invalid range for phoneme '\(symbol)': start=\(start), length=\(length)")
            continue
        }

        let endIndex = start + length
        let textRange = start..<endIndex

        phonemes.append(PhonemeInfo(
            symbol: symbol,
            duration: duration,  // Now using real duration!
            textRange: textRange
        ))
    }

    // Log duration status
    let hasDurations = durationsPtr != nil
    print("[SherpaOnnx] Extracted \(phonemes.count) phonemes (durations: \(hasDurations ? "✓" : "✗"))")
}
```

**Step 3: Run the test**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/DurationExtractionTests
```

**Step 4: Commit the changes**

```bash
git add Listen2/Services/TTS/SherpaOnnx.swift Listen2Tests/DurationExtractionTests.swift
git commit -m "feat: extract real phoneme durations from C API"
```

---

## Phase 3: Intelligent Word Alignment

### Task 7: Build Word Normalization Mapper

**Files:**
- Create: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/TextNormalizationMapper.swift`
- Test: Create `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2Tests/TextNormalizationTests.swift`

**Step 1: Write tests for normalization mapping**

```swift
// TextNormalizationTests.swift
import XCTest
@testable import Listen2

class TextNormalizationTests: XCTestCase {

    func testMapsAbbreviations() {
        let mapper = TextNormalizationMapper()

        // Test common abbreviations
        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith's", "office"],
            synthesized: ["Doctor", "Smith", "s", "office"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Dr. -> Doctor
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // Smith's -> Smith s
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])
        XCTAssertEqual(mapping[2].displayIndices, [2])      // office -> office
        XCTAssertEqual(mapping[2].synthesizedIndices, [3])
    }

    func testMapsContractions() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["He", "couldn't", "go"],
            synthesized: ["He", "could", "not", "go"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // couldn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // could not
    }

    func testMapsNumbers() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Chapter", "23", "begins"],
            synthesized: ["Chapter", "twenty", "three", "begins"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // 23
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // twenty three
    }
}
```

**Step 2: Implement TextNormalizationMapper**

```swift
// TextNormalizationMapper.swift
import Foundation

/// Maps between display text words and synthesized (normalized) text words
struct TextNormalizationMapper {

    struct WordMapping {
        let displayIndices: [Int]      // Indices in display word array
        let synthesizedIndices: [Int]  // Indices in synthesized word array
    }

    /// Build mapping between display and synthesized words using edit distance
    func buildMapping(display: [String], synthesized: [String]) -> [WordMapping] {
        var mappings: [WordMapping] = []
        var synthIndex = 0

        for (dispIndex, dispWord) in display.enumerated() {
            // Find best match in synthesized text
            let match = findBestMatch(
                for: dispWord,
                in: synthesized,
                startingFrom: synthIndex
            )

            if let matchIndices = match {
                mappings.append(WordMapping(
                    displayIndices: [dispIndex],
                    synthesizedIndices: matchIndices
                ))
                synthIndex = matchIndices.last! + 1
            } else {
                // No match found - word might have been dropped
                print("[NormMapper] Warning: No match for '\(dispWord)'")
            }
        }

        return mappings
    }

    private func findBestMatch(
        for displayWord: String,
        in synthesized: [String],
        startingFrom startIndex: Int
    ) -> [Int]? {

        // Check common patterns
        if let indices = matchAbbreviation(displayWord, synthesized, startIndex) {
            return indices
        }

        if let indices = matchContraction(displayWord, synthesized, startIndex) {
            return indices
        }

        if let indices = matchNumber(displayWord, synthesized, startIndex) {
            return indices
        }

        // Direct match
        if startIndex < synthesized.count &&
           normalizeForComparison(displayWord) == normalizeForComparison(synthesized[startIndex]) {
            return [startIndex]
        }

        // Fuzzy match using edit distance
        return fuzzyMatch(displayWord, synthesized, startIndex)
    }

    private func matchAbbreviation(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        let abbreviations = [
            "Dr.": "Doctor",
            "Mr.": "Mister",
            "Mrs.": "Missus",
            "Ms.": "Miss",
            "St.": "Street",
            "Ave.": "Avenue"
        ]

        if let expanded = abbreviations[word],
           start < synthesized.count,
           synthesized[start].lowercased() == expanded.lowercased() {
            return [start]
        }

        return nil
    }

    private func matchContraction(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        let contractions = [
            "can't": ["can", "not"],
            "won't": ["will", "not"],
            "couldn't": ["could", "not"],
            "shouldn't": ["should", "not"],
            "wouldn't": ["would", "not"],
            "didn't": ["did", "not"],
            "doesn't": ["does", "not"],
            "don't": ["do", "not"],
            "isn't": ["is", "not"],
            "aren't": ["are", "not"],
            "wasn't": ["was", "not"],
            "weren't": ["were", "not"],
            "I'll": ["I", "will"],
            "you'll": ["you", "will"],
            "he'll": ["he", "will"],
            "she'll": ["she", "will"],
            "we'll": ["we", "will"],
            "they'll": ["they", "will"],
            "I've": ["I", "have"],
            "you've": ["you", "have"],
            "we've": ["we", "have"],
            "they've": ["they", "have"]
        ]

        let normalized = word.lowercased()
        if let expansion = contractions[normalized] {
            // Check if synthesized text has the expansion
            if start + expansion.count <= synthesized.count {
                let synthSlice = synthesized[start..<(start + expansion.count)]
                    .map { $0.lowercased() }
                if synthSlice == expansion {
                    return Array(start..<(start + expansion.count))
                }
            }
        }

        // Handle possessives (e.g., "John's" -> "John" "s")
        if word.hasSuffix("'s") && start + 1 < synthesized.count {
            let base = String(word.dropLast(2))
            if normalizeForComparison(base) == normalizeForComparison(synthesized[start]) &&
               synthesized[start + 1] == "s" {
                return [start, start + 1]
            }
        }

        return nil
    }

    private func matchNumber(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Check if word is a number
        guard let number = Int(word) else { return nil }

        // For now, simple heuristic: numbers often expand to 1-3 words
        // More sophisticated: use a number-to-words library
        let maxWords = 4  // "two thousand twenty four"

        for length in 1...maxWords {
            if start + length <= synthesized.count {
                // Check if this segment could be the number
                // This is a simplified check - real implementation would convert number to words
                let segment = synthesized[start..<(start + length)].joined(separator: " ")
                if couldBeNumber(segment, number) {
                    return Array(start..<(start + length))
                }
            }
        }

        return nil
    }

    private func couldBeNumber(_ text: String, _ number: Int) -> Bool {
        // Simplified check - real implementation would use number-to-words conversion
        let numberWords = ["zero", "one", "two", "three", "four", "five",
                          "six", "seven", "eight", "nine", "ten",
                          "twenty", "thirty", "forty", "fifty",
                          "hundred", "thousand"]

        let words = text.lowercased().split(separator: " ")
        return words.allSatisfy { numberWords.contains(String($0)) }
    }

    private func fuzzyMatch(_ word: String, _ synthesized: [String], _ start: Int) -> [Int]? {
        // Use Levenshtein distance for fuzzy matching
        let threshold = 3  // Maximum edit distance

        for i in start..<min(start + 5, synthesized.count) {
            let distance = levenshteinDistance(
                normalizeForComparison(word),
                normalizeForComparison(synthesized[i])
            )

            if distance <= threshold {
                return [i]
            }
        }

        return nil
    }

    private func normalizeForComparison(_ word: String) -> String {
        // Remove punctuation and lowercase for comparison
        let cleaned = word.replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
        return cleaned.lowercased()
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m { matrix[i][0] = i }
        for j in 1...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[s1.index(s1.startIndex, offsetBy: i-1)] ==
                          s2[s2.index(s2.startIndex, offsetBy: j-1)] ? 0 : 1

                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
```

**Step 3: Run tests**

```bash
cd /Users/zachswift/projects/Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/TextNormalizationTests
```

**Step 4: Commit**

```bash
git add Listen2/Services/TTS/TextNormalizationMapper.swift \
        Listen2Tests/TextNormalizationTests.swift
git commit -m "feat: implement text normalization mapping for word alignment"
```

---

### Task 8: Implement Dynamic Programming Alignment

**Files:**
- Create: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/DynamicAlignmentEngine.swift`
- Test: Create `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2Tests/DynamicAlignmentTests.swift`

**Step 1: Write alignment tests**

```swift
// DynamicAlignmentTests.swift
import XCTest
@testable import Listen2

class DynamicAlignmentTests: XCTestCase {

    func testAlignsPhonemeGroupsToWords() {
        let engine = DynamicAlignmentEngine()

        // Mock phoneme groups (from espeak)
        let phonemeGroups = [
            [PhonemeInfo(symbol: "h", duration: 0.05, textRange: 0..<1),
             PhonemeInfo(symbol: "ə", duration: 0.04, textRange: 0..<1),
             PhonemeInfo(symbol: "l", duration: 0.06, textRange: 0..<1),
             PhonemeInfo(symbol: "oʊ", duration: 0.08, textRange: 0..<1)],
            [PhonemeInfo(symbol: "w", duration: 0.05, textRange: 2..<3),
             PhonemeInfo(symbol: "ɝ", duration: 0.07, textRange: 2..<3),
             PhonemeInfo(symbol: "l", duration: 0.06, textRange: 2..<3),
             PhonemeInfo(symbol: "d", duration: 0.04, textRange: 2..<3)]
        ]

        // Display words
        let displayWords = ["Hello", "world"]

        // Word mapping (identity mapping for this test)
        let mapping = [
            TextNormalizationMapper.WordMapping(displayIndices: [0], synthesizedIndices: [0]),
            TextNormalizationMapper.WordMapping(displayIndices: [1], synthesizedIndices: [1])
        ]

        let result = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 2)

        // First word should have first phoneme group
        XCTAssertEqual(result[0].text, "Hello")
        XCTAssertEqual(result[0].duration, 0.23, accuracy: 0.01)  // Sum of phoneme durations

        // Second word should have second phoneme group
        XCTAssertEqual(result[1].text, "world")
        XCTAssertEqual(result[1].duration, 0.22, accuracy: 0.01)
    }

    func testHandlesMismatchedCounts() {
        let engine = DynamicAlignmentEngine()

        // More phoneme groups than display words (common with contractions)
        let phonemeGroups = [
            [PhonemeInfo(symbol: "k", duration: 0.05, textRange: 0..<1)],
            [PhonemeInfo(symbol: "ʊ", duration: 0.04, textRange: 1..<2)],
            [PhonemeInfo(symbol: "d", duration: 0.05, textRange: 1..<2)],
            [PhonemeInfo(symbol: "n", duration: 0.06, textRange: 2..<3)],
            [PhonemeInfo(symbol: "ɑ", duration: 0.04, textRange: 2..<3)],
            [PhonemeInfo(symbol: "t", duration: 0.05, textRange: 2..<3)]
        ]

        let displayWords = ["couldn't"]

        // Mapping shows contraction expanded
        let mapping = [
            TextNormalizationMapper.WordMapping(
                displayIndices: [0],  // couldn't
                synthesizedIndices: [0, 1, 2]  // could not (3 groups)
            )
        ]

        let result = engine.align(
            phonemeGroups: Array(phonemeGroups[0..<3]),  // First 3 groups
            displayWords: displayWords,
            wordMapping: mapping
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "couldn't")
        XCTAssertEqual(result[0].duration, 0.14, accuracy: 0.01)  // Sum of first 3 groups
    }
}
```

**Step 2: Implement Dynamic Alignment Engine**

```swift
// DynamicAlignmentEngine.swift
import Foundation

/// Engine for aligning phoneme groups to display words using dynamic programming
struct DynamicAlignmentEngine {

    struct AlignedWord {
        let text: String
        let startTime: TimeInterval
        let duration: TimeInterval
        let phonemes: [PhonemeInfo]
    }

    /// Align phoneme groups to display words using word mapping
    func align(
        phonemeGroups: [[PhonemeInfo]],
        displayWords: [String],
        wordMapping: [TextNormalizationMapper.WordMapping]
    ) -> [AlignedWord] {

        var alignedWords: [AlignedWord] = []
        var currentTime: TimeInterval = 0
        var groupIndex = 0

        for mapping in wordMapping {
            // Get display word text
            let displayText = mapping.displayIndices
                .compactMap { $0 < displayWords.count ? displayWords[$0] : nil }
                .joined(separator: " ")

            // Collect all phonemes for this display word
            var wordPhonemes: [PhonemeInfo] = []
            var wordDuration: TimeInterval = 0

            // Get all phoneme groups that map to this display word
            for synthIndex in mapping.synthesizedIndices {
                if groupIndex < phonemeGroups.count {
                    let group = phonemeGroups[groupIndex]
                    wordPhonemes.append(contentsOf: group)
                    wordDuration += group.reduce(0) { $0 + $1.duration }
                    groupIndex += 1
                }
            }

            if !wordPhonemes.isEmpty {
                alignedWords.append(AlignedWord(
                    text: displayText,
                    startTime: currentTime,
                    duration: wordDuration,
                    phonemes: wordPhonemes
                ))

                currentTime += wordDuration
            }
        }

        // Handle remaining phoneme groups if any (shouldn't happen with good mapping)
        if groupIndex < phonemeGroups.count {
            print("[DynAlign] Warning: \(phonemeGroups.count - groupIndex) phoneme groups unaligned")
        }

        return alignedWords
    }

    /// Alternative: Use DTW (Dynamic Time Warping) for more robust alignment
    func alignWithDTW(
        phonemeGroups: [[PhonemeInfo]],
        displayWords: [String],
        synthesizedText: String
    ) -> [AlignedWord] {

        // Extract synthesized words
        let synthesizedWords = synthesizedText
            .split(separator: " ")
            .map { String($0) }

        // Build cost matrix for DTW
        let m = displayWords.count
        let n = phonemeGroups.count

        var costMatrix = Array(repeating: Array(repeating: Double.infinity, count: n + 1), count: m + 1)
        costMatrix[0][0] = 0

        // Fill cost matrix
        for i in 1...m {
            for j in 1...n {
                let displayWord = displayWords[i-1]

                // Cost is based on phoneme count mismatch and text similarity
                let phonemeCount = phonemeGroups[j-1].count
                let expectedCount = estimatePhonemeCount(for: displayWord)
                let countCost = abs(Double(phonemeCount - expectedCount))

                // Calculate minimum cost path
                let matchCost = costMatrix[i-1][j-1] + countCost
                let insertCost = costMatrix[i][j-1] + countCost * 2
                let deleteCost = costMatrix[i-1][j] + 10.0  // High penalty for skipping display words

                costMatrix[i][j] = min(matchCost, insertCost, deleteCost)
            }
        }

        // Backtrack to find optimal alignment
        var alignedWords: [AlignedWord] = []
        var i = m, j = n
        var path: [(Int, Int)] = []

        while i > 0 && j > 0 {
            path.append((i-1, j-1))

            let matchCost = costMatrix[i-1][j-1]
            let insertCost = costMatrix[i][j-1]
            let deleteCost = costMatrix[i-1][j]

            if matchCost <= insertCost && matchCost <= deleteCost {
                i -= 1
                j -= 1
            } else if insertCost <= deleteCost {
                j -= 1
            } else {
                i -= 1
            }
        }

        // Build aligned words from path
        path.reverse()
        var currentTime: TimeInterval = 0

        for (displayIdx, groupIdx) in path {
            if displayIdx < displayWords.count && groupIdx < phonemeGroups.count {
                let group = phonemeGroups[groupIdx]
                let duration = group.reduce(0) { $0 + $1.duration }

                alignedWords.append(AlignedWord(
                    text: displayWords[displayIdx],
                    startTime: currentTime,
                    duration: duration,
                    phonemes: group
                ))

                currentTime += duration
            }
        }

        return alignedWords
    }

    private func estimatePhonemeCount(for word: String) -> Int {
        // Rough heuristic: 1.5 phonemes per character
        // Real implementation would use phoneme dictionary
        return max(1, Int(Double(word.count) * 1.5))
    }
}
```

**Step 3: Run tests**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/DynamicAlignmentTests
```

**Step 4: Commit**

```bash
git add Listen2/Services/TTS/DynamicAlignmentEngine.swift \
        Listen2Tests/DynamicAlignmentTests.swift
git commit -m "feat: implement dynamic programming alignment for phoneme-to-word mapping"
```

---

### Task 9: Integration - Premium PhonemeAlignmentService

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Test: Create `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2Tests/IntegratedAlignmentTests.swift`

**Step 1: Write integration tests**

```swift
// IntegratedAlignmentTests.swift
import XCTest
@testable import Listen2

class IntegratedAlignmentTests: XCTestCase {

    func testPremiumAlignmentWithRealDurations() async throws {
        let service = PhonemeAlignmentService()

        // Mock data with real durations from w_ceil
        let phonemes = [
            PhonemeInfo(symbol: "h", duration: 0.045, textRange: 0..<5),
            PhonemeInfo(symbol: "ə", duration: 0.032, textRange: 0..<5),
            PhonemeInfo(symbol: "l", duration: 0.058, textRange: 0..<5),
            PhonemeInfo(symbol: "oʊ", duration: 0.091, textRange: 0..<5),
            PhonemeInfo(symbol: "w", duration: 0.048, textRange: 6..<11),
            PhonemeInfo(symbol: "ɝ", duration: 0.067, textRange: 6..<11),
            PhonemeInfo(symbol: "l", duration: 0.055, textRange: 6..<11),
            PhonemeInfo(symbol: "d", duration: 0.041, textRange: 6..<11)
        ]

        let displayText = "Hello world"
        let synthesizedText = "Hello world"  // No normalization in this case

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        XCTAssertEqual(result.wordTimings.count, 2)

        // First word timing
        let firstWord = result.wordTimings[0]
        XCTAssertEqual(firstWord.text, "Hello")
        XCTAssertEqual(firstWord.duration, 0.226, accuracy: 0.001)

        // Second word timing
        let secondWord = result.wordTimings[1]
        XCTAssertEqual(secondWord.text, "world")
        XCTAssertEqual(secondWord.duration, 0.211, accuracy: 0.001)

        // Total duration should match sum of phoneme durations
        XCTAssertEqual(result.totalDuration, 0.437, accuracy: 0.001)
    }

    func testHandlesComplexNormalization() async throws {
        let service = PhonemeAlignmentService()

        // Test with normalization: "Dr. Smith's" -> "Doctor Smith s"
        let phonemes = createMockPhonemes(for: "Doctor Smith s office")
        let displayText = "Dr. Smith's office"
        let synthesizedText = "Doctor Smith s office"

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Should correctly map back to display words
        XCTAssertEqual(result.wordTimings.count, 3)
        XCTAssertEqual(result.wordTimings[0].text, "Dr.")
        XCTAssertEqual(result.wordTimings[1].text, "Smith's")
        XCTAssertEqual(result.wordTimings[2].text, "office")
    }

    private func createMockPhonemes(for text: String) -> [PhonemeInfo] {
        // Create mock phonemes with realistic durations
        var phonemes: [PhonemeInfo] = []
        var position = 0

        for word in text.split(separator: " ") {
            let wordStart = position
            let wordEnd = position + word.count

            // Estimate 1.5 phonemes per character
            let phonemeCount = max(1, Int(Double(word.count) * 1.5))

            for _ in 0..<phonemeCount {
                phonemes.append(PhonemeInfo(
                    symbol: "x",  // Mock symbol
                    duration: Double.random(in: 0.03...0.09),
                    textRange: wordStart..<wordEnd
                ))
            }

            position = wordEnd + 1  // +1 for space
        }

        return phonemes
    }
}
```

**Step 2: Update PhonemeAlignmentService with premium alignment**

```swift
// Add to PhonemeAlignmentService.swift

extension PhonemeAlignmentService {

    /// Premium alignment using real durations and intelligent normalization mapping
    func alignPremium(
        phonemes: [PhonemeInfo],
        displayText: String,
        synthesizedText: String,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {

        print("[PhonemeAlign] Premium alignment with \(phonemes.count) phonemes")
        print("[PhonemeAlign] Display text: '\(displayText)'")
        print("[PhonemeAlign] Synthesized text: '\(synthesizedText)'")

        // Check if we have real durations
        let hasRealDurations = phonemes.allSatisfy { $0.duration > 0 }
        print("[PhonemeAlign] Using \(hasRealDurations ? "real" : "estimated") durations")

        // Extract words from both texts
        let displayWords = extractWords(from: displayText)
        let synthesizedWords = extractWords(from: synthesizedText)

        print("[PhonemeAlign] Display words: \(displayWords)")
        print("[PhonemeAlign] Synthesized words: \(synthesizedWords)")

        // Build normalization mapping
        let mapper = TextNormalizationMapper()
        let wordMapping = mapper.buildMapping(
            display: displayWords,
            synthesized: synthesizedWords
        )

        print("[PhonemeAlign] Created \(wordMapping.count) word mappings")

        // Group phonemes by espeak word boundaries
        let phonemeGroups = groupPhonemesByWord(phonemes)
        print("[PhonemeAlign] Grouped into \(phonemeGroups.count) phoneme groups")

        // Align using dynamic programming
        let engine = DynamicAlignmentEngine()
        let alignedWords = engine.align(
            phonemeGroups: phonemeGroups,
            displayWords: displayWords,
            wordMapping: wordMapping
        )

        // Convert to AlignmentResult format
        var wordTimings: [AlignmentResult.WordTiming] = []

        for (index, aligned) in alignedWords.enumerated() {
            // Find string range in display text
            let range = findWordRange(for: aligned.text, in: displayText, startingFrom: 0)

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: index,
                startTime: aligned.startTime,
                duration: aligned.duration,
                text: aligned.text,
                stringRange: range ?? displayText.startIndex..<displayText.startIndex
            ))
        }

        let totalDuration = alignedWords.last.map { $0.startTime + $0.duration } ?? 0

        print("[PhonemeAlign] ✅ Premium alignment complete: \(wordTimings.count) words, \(String(format: "%.3f", totalDuration))s")

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: totalDuration,
            wordTimings: wordTimings
        )
    }

    private func extractWords(from text: String) -> [String] {
        text.split(separator: " ")
            .map { String($0) }
    }

    private func findWordRange(
        for word: String,
        in text: String,
        startingFrom start: Int
    ) -> Range<String.Index>? {

        let startIndex = text.index(text.startIndex, offsetBy: start)
        if let range = text.range(of: word, options: [], range: startIndex..<text.endIndex) {
            return range
        }
        return nil
    }
}
```

**Step 3: Run integration tests**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/IntegratedAlignmentTests
```

**Step 4: Commit**

```bash
git add Listen2/Services/TTS/PhonemeAlignmentService.swift \
        Listen2Tests/IntegratedAlignmentTests.swift
git commit -m "feat: integrate premium alignment with real durations and normalization"
```

---

## Phase 4: Testing & Optimization

### Task 10: Test with Technical PDFs

**Files:**
- Create: `/Users/zachswift/projects/Listen2/TestDocuments/technical_test.pdf`
- Create: `/Users/zachswift/projects/Listen2/Listen2Tests/TechnicalContentTests.swift`

**Step 1: Create test for technical content**

```swift
// TechnicalContentTests.swift
import XCTest
@testable import Listen2

class TechnicalContentTests: XCTestCase {

    func testHandlesTechnicalAbbreviations() async throws {
        let service = PhonemeAlignmentService()

        // Technical text with abbreviations
        let displayText = "TCP/IP uses HTTP/HTTPS protocols"
        let synthesizedText = "T C P slash I P uses H T T P slash H T T P S protocols"

        // Create mock phonemes (in real test, would come from actual synthesis)
        let phonemes = createPhonemes(for: synthesizedText)

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        // Verify technical terms are preserved
        let words = result.wordTimings.map { $0.text }
        XCTAssertTrue(words.contains("TCP/IP"))
        XCTAssertTrue(words.contains("HTTP/HTTPS"))
    }

    func testHandlesMathematicalNotation() async throws {
        let service = PhonemeAlignmentService()

        let displayText = "The algorithm runs in O(n²) time"
        let synthesizedText = "The algorithm runs in O n squared time"

        let phonemes = createPhonemes(for: synthesizedText)

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        let words = result.wordTimings.map { $0.text }
        XCTAssertTrue(words.contains("O(n²)"))
    }

    func testHandlesCodeSnippets() async throws {
        let service = PhonemeAlignmentService()

        let displayText = "Call api.getData() method"
        let synthesizedText = "Call api dot get data method"

        let phonemes = createPhonemes(for: synthesizedText)

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        let words = result.wordTimings.map { $0.text }
        XCTAssertTrue(words.contains("api.getData()"))
    }

    private func createPhonemes(for text: String) -> [PhonemeInfo] {
        // Helper to create mock phonemes with realistic durations
        var phonemes: [PhonemeInfo] = []
        var charIndex = 0

        for char in text {
            if !char.isWhitespace {
                phonemes.append(PhonemeInfo(
                    symbol: String(char),
                    duration: 0.05,
                    textRange: charIndex..<(charIndex+1)
                ))
            }
            charIndex += 1
        }

        return phonemes
    }
}
```

**Step 2: Run technical content tests**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/TechnicalContentTests
```

**Step 3: Commit**

```bash
git add Listen2Tests/TechnicalContentTests.swift
git commit -m "test: add tests for technical content alignment"
```

---

### Task 11: Performance Optimization & Caching

**Files:**
- Modify: `/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Test: Create `/Users/zachswift/projects/Listen2/Listen2Tests/PerformanceTests.swift`

**Step 1: Add performance test**

```swift
// PerformanceTests.swift
import XCTest
@testable import Listen2

class PerformanceTests: XCTestCase {

    func testAlignmentPerformance() {
        let service = PhonemeAlignmentService()

        // Create large dataset
        let longText = Array(repeating: "The quick brown fox jumps over the lazy dog", count: 100).joined(separator: " ")
        let phonemes = createLargePhonemeSet(wordCount: 900)  // ~900 words

        measure {
            // Should complete in < 100ms
            Task {
                _ = try? await service.alignPremium(
                    phonemes: phonemes,
                    displayText: longText,
                    synthesizedText: longText,
                    paragraphIndex: 0
                )
            }
        }
    }

    func testCachingReducesLatency() async throws {
        let service = PhonemeAlignmentService()

        let text = "Test caching performance"
        let phonemes = createPhonemes(for: text)

        // First call - no cache
        let start1 = CFAbsoluteTimeGetCurrent()
        _ = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )
        let time1 = CFAbsoluteTimeGetCurrent() - start1

        // Second call - should use cache
        let start2 = CFAbsoluteTimeGetCurrent()
        _ = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )
        let time2 = CFAbsoluteTimeGetCurrent() - start2

        // Cache should be at least 10x faster
        XCTAssertLessThan(time2, time1 / 10)
    }
}
```

**Step 2: Run performance tests**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/PerformanceTests
```

**Step 3: Commit**

```bash
git add Listen2Tests/PerformanceTests.swift
git commit -m "test: add performance tests for alignment"
```

---

### Task 12: End-to-End Integration Test

**Files:**
- Create: `/Users/zachswift/projects/Listen2/Listen2Tests/EndToEndTests.swift`

**Step 1: Create end-to-end test**

```swift
// EndToEndTests.swift
import XCTest
@testable import Listen2

class EndToEndTests: XCTestCase {

    func testCompleteWordHighlightingPipeline() async throws {
        // Test the entire pipeline from synthesis to highlighting

        // 1. Synthesize with Piper TTS
        let provider = PiperTTSProvider()
        let testText = "Dr. Smith's research on TCP/IP protocols couldn't be more timely."

        let synthesisResult = try await provider.synthesize(testText, speed: 1.0)

        // 2. Verify we have phonemes with real durations
        XCTAssertFalse(synthesisResult.phonemes.isEmpty)

        let hasRealDurations = synthesisResult.phonemes.allSatisfy { $0.duration > 0 }
        XCTAssertTrue(hasRealDurations, "Should have real durations from w_ceil")

        // 3. Perform alignment
        let alignmentService = PhonemeAlignmentService()
        let alignment = try await alignmentService.alignPremium(
            phonemes: synthesisResult.phonemes,
            displayText: testText,
            synthesizedText: synthesisResult.text,
            paragraphIndex: 0
        )

        // 4. Verify alignment quality
        XCTAssertGreaterThan(alignment.wordTimings.count, 0)

        // Check specific words are preserved
        let words = alignment.wordTimings.map { $0.text }
        XCTAssertTrue(words.contains("Dr."))
        XCTAssertTrue(words.contains("Smith's"))
        XCTAssertTrue(words.contains("TCP/IP"))
        XCTAssertTrue(words.contains("couldn't"))

        // 5. Verify timing accuracy
        let totalDuration = alignment.totalDuration
        let audioDuration = Double(synthesisResult.audioData.count) / (2 * 22050)  // 16-bit, 22kHz

        // Durations should match within 10%
        XCTAssertEqual(totalDuration, audioDuration, accuracy: audioDuration * 0.1)

        print("✅ End-to-end test successful!")
        print("   Aligned \(alignment.wordTimings.count) words")
        print("   Total duration: \(String(format: "%.3f", totalDuration))s")
        print("   Audio duration: \(String(format: "%.3f", audioDuration))s")
    }
}
```

**Step 2: Run end-to-end test**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:Listen2Tests/EndToEndTests
```

**Step 3: Final commit**

```bash
git add Listen2Tests/EndToEndTests.swift
git commit -m "test: add end-to-end word highlighting pipeline test"
```

---

## Rollback Plan

If any task fails critically:

1. **Revert sherpa-onnx changes:**
   ```bash
   cd /Users/zachswift/projects/sherpa-onnx
   git reset --hard HEAD~5  # Revert last 5 commits
   rm -rf build-ios
   ./build-ios.sh  # Rebuild clean
   ```

2. **Revert Listen2 changes:**
   ```bash
   cd /Users/zachswift/projects/Listen2
   git reset --hard HEAD~10  # Revert recent changes
   ```

3. **Use simple time-based fallback:**
   ```swift
   // In PhonemeAlignmentService
   func alignFallback(text: String, audioDuration: TimeInterval) -> AlignmentResult {
       let words = text.split(separator: " ")
       let durationPerWord = audioDuration / Double(words.count)
       // ... simple even distribution
   }
   ```

---

## Success Criteria

✅ **Phase 1 Success:** w_ceil durations extracted and visible in Swift logs
✅ **Phase 2 Success:** Real durations flow through to PhonemeInfo
✅ **Phase 3 Success:** Complex normalization handled correctly
✅ **Phase 4 Success:** 95%+ accuracy on technical content

**Final Verification:**
- Word highlighting works smoothly on device
- No crashes or hangs
- Timing accuracy within 50ms per word
- Technical content handled correctly

---

## Estimated Timeline

- **Phase 1:** 4-6 hours (C++ modifications, framework rebuild)
- **Phase 2:** 1-2 hours (Swift integration)
- **Phase 3:** 4-6 hours (Alignment algorithms)
- **Phase 4:** 2-3 hours (Testing & optimization)

**Total:** 11-17 hours for complete premium implementation
