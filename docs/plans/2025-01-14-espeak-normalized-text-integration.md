# Espeak Normalized Text Integration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose espeak-ng's normalized text and character position mapping through the entire TTS stack (espeak-ng → piper-phonemize → sherpa-onnx → Swift) to enable accurate word highlighting for abbreviations, contractions, and numbers.

**Architecture:** Fork espeak-ng to capture normalized text during tokenization. Thread normalized text + character mapping through piper-phonemize and sherpa-onnx C API. Update Swift PhonemeAlignmentService to map VoxPDF words (in original text) to phoneme positions (in normalized text) using the character mapping.

**Tech Stack:** C (espeak-ng), C++ (piper-phonemize, sherpa-onnx), Swift, Git submodules

---

## Task 1: Research espeak-ng Tokenization Code

**Goal:** Understand where espeak-ng performs text normalization to identify modification points

**Files:**
- Read: `espeak-ng/src/libespeak-ng/translate.c` (tokenization entry points)
- Read: `espeak-ng/src/libespeak-ng/dictionary.c` (text expansion)
- Read: `espeak-ng/src/include/espeak-ng/speak_lib.h` (public API)

**Step 1: Fork espeak-ng repository**

```bash
cd ~/projects
gh repo fork espeak-ng/espeak-ng --clone
cd espeak-ng
git checkout -b feature/expose-normalized-text
```

**Step 2: Locate text normalization functions**

Search for key functions:
```bash
grep -rn "TranslateWord\|TranslateClause\|TokenizeText" src/libespeak-ng/*.c | head -20
```

Expected: Find functions in `translate.c` that convert input text to normalized form

**Step 3: Document current flow**

Create: `docs/plans/2025-01-14-normalized-text-capture-notes.md`

Document:
- Where original text enters (`espeak_Synth`, `espeak_TextToPhonemes`)
- Where normalization happens (number expansion, abbreviation expansion)
- Where phonemes are generated with character positions
- Current callback structure (`espeak_EVENT` with `text_position`)

**Step 4: Commit research notes**

```bash
git add docs/plans/2025-01-14-normalized-text-capture-notes.md
git commit -m "docs: research espeak-ng text normalization flow"
```

---

## Task 2: Add Normalized Text Buffer to espeak-ng

**Goal:** Capture normalized text as espeak processes input

**Files:**
- Modify: `espeak-ng/src/libespeak-ng/translate.c` (add normalization buffer)
- Modify: `espeak-ng/src/include/espeak-ng/speak_lib.h` (expose in API)

**Step 1: Add normalized text buffer to translation context**

In `translate.c`, locate the translation state struct and add:

```c
// Near other translation state variables
static char normalized_text_buffer[1024];
static int normalized_text_pos = 0;
static int char_position_map[1024][2]; // [orig_pos, norm_pos] pairs
static int char_map_count = 0;
```

**Step 2: Capture normalized text during tokenization**

Find the function that processes each word (likely `TranslateWord` or similar):

```c
// In the word processing function, after normalization
void TranslateWord(Translator *tr, char *word, int word_length, ...) {
    // ... existing normalization code ...

    // NEW: Track original position before normalization
    int original_start = current_input_position;

    // ... normalization happens here (expand "Dr." to "Doctor") ...

    // NEW: After normalization, record mapping
    if (normalized_text_pos + normalized_length < sizeof(normalized_text_buffer)) {
        strncpy(normalized_text_buffer + normalized_text_pos, normalized_word, normalized_length);

        // Record character position mapping
        char_position_map[char_map_count][0] = original_start;
        char_position_map[char_map_count][1] = normalized_text_pos;
        char_map_count++;

        normalized_text_pos += normalized_length;
    }
}
```

**Step 3: Write test to verify capture**

Create: `espeak-ng/tests/normalized_text_test.c`

```c
#include <espeak-ng/speak_lib.h>
#include <assert.h>
#include <string.h>

void test_normalized_text_simple() {
    espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, NULL, 0);

    const char* input = "Dr. Smith's address is 123 Main St.";
    const char* normalized = espeak_GetNormalizedText(input);

    // Should expand "Dr." to "Doctor" and "123" to "one hundred twenty three"
    assert(strstr(normalized, "Doctor") != NULL);
    assert(strstr(normalized, "one hundred") != NULL);

    printf("✓ Normalized text capture works\n");
}

int main() {
    test_normalized_text_simple();
    return 0;
}
```

**Step 4: Add public API function**

In `speak_lib.h`:

```c
/**
 * Get the normalized text from the last synthesis operation.
 * This includes text expansion (Dr. -> Doctor, 123 -> one hundred twenty three)
 *
 * @return Pointer to normalized text buffer (valid until next synthesis call)
 */
ESPEAK_NG_API const char* espeak_GetNormalizedText();

/**
 * Get the character position mapping between original and normalized text.
 *
 * @param map_array Output array of [original_pos, normalized_pos] pairs
 * @param max_entries Maximum number of entries to write
 * @return Number of entries written
 */
ESPEAK_NG_API int espeak_GetCharacterMapping(int (*map_array)[2], int max_entries);
```

Implement in `speak_lib.c`:

```c
const char* espeak_GetNormalizedText() {
    return normalized_text_buffer;
}

int espeak_GetCharacterMapping(int (*map_array)[2], int max_entries) {
    int count = (char_map_count < max_entries) ? char_map_count : max_entries;
    memcpy(map_array, char_position_map, count * sizeof(int) * 2);
    return count;
}
```

**Step 5: Build and test**

```bash
cd ~/projects/espeak-ng
./autogen.sh
./configure --prefix=/usr/local
make
make check

# Run custom test
gcc tests/normalized_text_test.c -lespeak-ng -o test_normalized
./test_normalized
```

Expected: "✓ Normalized text capture works"

**Step 6: Commit espeak-ng modifications**

```bash
git add src/libespeak-ng/translate.c src/include/espeak-ng/speak_lib.h tests/normalized_text_test.c
git commit -m "feat: expose normalized text and character position mapping via API"
```

---

## Task 3: Update piper-phonemize to Capture Normalized Text

**Goal:** Modify piper-phonemize to call espeak's new API and include normalized text in output

**Files:**
- Modify: `~/projects/piper-phonemize/src/phonemize.cpp`
- Modify: `~/projects/piper-phonemize/src/phonemize.hpp`

**Step 1: Update espeak submodule to forked version**

```bash
cd ~/projects/piper-phonemize
git submodule update --init
cd lib/espeak-ng
git remote add fork ~/projects/espeak-ng
git fetch fork
git checkout fork/feature/expose-normalized-text
cd ../..
```

**Step 2: Add normalized text to PhonemeResult struct**

In `phonemize.hpp`:

```cpp
struct PhonemeResult {
    std::vector<Phoneme> phonemes;
    std::string normalized_text;  // NEW: espeak's normalized text
    std::vector<std::pair<int, int>> char_mapping;  // NEW: [orig_pos, norm_pos]
};
```

**Step 3: Capture normalized text in phonemize_eSpeak**

In `phonemize.cpp`, after the espeak call:

```cpp
void phonemize_eSpeak(std::string text, eSpeakPhonemeConfig &config,
                     PhonemeResult &result) {
    // ... existing phoneme extraction code ...

    // NEW: Get normalized text after phonemization
    const char* normalized = espeak_GetNormalizedText();
    if (normalized) {
        result.normalized_text = std::string(normalized);
    }

    // NEW: Get character position mapping
    int mapping[1024][2];
    int map_count = espeak_GetCharacterMapping(mapping, 1024);
    result.char_mapping.reserve(map_count);
    for (int i = 0; i < map_count; i++) {
        result.char_mapping.push_back({mapping[i][0], mapping[i][1]});
    }
}
```

**Step 4: Write test**

Create: `~/projects/piper-phonemize/tests/test_normalized_text.cpp`

```cpp
#include "phonemize.hpp"
#include <cassert>
#include <iostream>

void test_abbreviation_normalization() {
    piper::eSpeakPhonemeConfig config;
    config.voice = "en-us";

    piper::PhonemeResult result;
    piper::phonemize_eSpeak("Dr. Smith", config, result);

    // Normalized should expand "Dr." to "Doctor"
    assert(result.normalized_text.find("Doctor") != std::string::npos);

    // Should have character mapping
    assert(result.char_mapping.size() > 0);

    std::cout << "✓ piper-phonemize normalized text extraction works\n";
}

int main() {
    test_abbreviation_normalization();
    return 0;
}
```

**Step 5: Build and test**

```bash
cd ~/projects/piper-phonemize
mkdir -p build && cd build
cmake ..
make
make test
```

Expected: Tests pass

**Step 6: Commit piper-phonemize changes**

```bash
git add src/phonemize.cpp src/phonemize.hpp tests/test_normalized_text.cpp lib/espeak-ng
git commit -m "feat: capture normalized text and character mapping from espeak-ng"
```

---

## Task 4: Thread Normalized Text Through sherpa-onnx C API

**Goal:** Add normalized_text field to sherpa-onnx C API structs

**Files:**
- Modify: `~/projects/sherpa-onnx/sherpa-onnx/c-api/c-api.h`
- Modify: `~/projects/sherpa-onnx/sherpa-onnx/csrc/offline-tts.h`

**Step 1: Add normalized text to GeneratedAudio struct**

In `c-api.h`:

```c
typedef struct SherpaOnnxGeneratedAudio {
  const float* samples;
  int32_t n;
  int32_t sample_rate;

  // Phoneme timing (already exists from your work)
  const SherpaOnnxPhonemeInfo* phonemes;
  int32_t num_phonemes;

  // NEW: Normalized text and character mapping
  const char* normalized_text;
  const int32_t* char_mapping;  // Pairs of [orig_pos, norm_pos]
  int32_t char_mapping_count;
} SherpaOnnxGeneratedAudio;
```

**Step 2: Update C++ GeneratedAudio struct**

In `offline-tts.h`:

```cpp
struct GeneratedAudio {
  std::vector<float> samples;
  int32_t sample_rate;
  std::vector<PhonemeInfo> phonemes;

  // NEW
  std::string normalized_text;
  std::vector<std::pair<int32_t, int32_t>> char_mapping;
};
```

**Step 3: Populate normalized text in TTS generation**

Find where piper-phonemize is called (likely in `offline-tts-vits-impl.h`):

```cpp
GeneratedAudio OfflineTtsVitsImpl::Generate(const std::string &text, ...) {
    // ... existing code ...

    // Call piper-phonemize
    piper::PhonemeResult phoneme_result;
    piper::phonemize_eSpeak(text, config, phoneme_result);

    GeneratedAudio audio;
    // ... populate samples, sample_rate, phonemes ...

    // NEW: Populate normalized text
    audio.normalized_text = phoneme_result.normalized_text;
    audio.char_mapping = phoneme_result.char_mapping;

    return audio;
}
```

**Step 4: Bridge to C API**

In `c-api.cc`, where `SherpaOnnxGeneratedAudio` is created:

```cpp
SherpaOnnxGeneratedAudio* CreateGeneratedAudio(const GeneratedAudio& audio) {
    auto* result = new SherpaOnnxGeneratedAudio;

    // ... existing sample/phoneme population ...

    // NEW: Normalized text
    result->normalized_text = audio.normalized_text.empty()
        ? nullptr
        : strdup(audio.normalized_text.c_str());

    // NEW: Character mapping (flatten pairs into single array)
    if (!audio.char_mapping.empty()) {
        result->char_mapping_count = audio.char_mapping.size();
        auto* mapping = new int32_t[audio.char_mapping.size() * 2];
        for (size_t i = 0; i < audio.char_mapping.size(); i++) {
            mapping[i * 2] = audio.char_mapping[i].first;
            mapping[i * 2 + 1] = audio.char_mapping[i].second;
        }
        result->char_mapping = mapping;
    } else {
        result->char_mapping = nullptr;
        result->char_mapping_count = 0;
    }

    return result;
}
```

**Step 5: Write C API test**

Create: `~/projects/sherpa-onnx/sherpa-onnx/c-api/test-normalized-text.c`

```c
#include "c-api.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

void test_normalized_text_exposure() {
    SherpaOnnxOfflineTts* tts = /* ... initialize ... */;

    const char* text = "Dr. Smith's office is at 42 Main St.";
    SherpaOnnxGeneratedAudio* audio = SherpaOnnxOfflineTtsGenerate(tts, text, 0, 1.0);

    // Verify normalized text is populated
    assert(audio->normalized_text != NULL);
    assert(strstr(audio->normalized_text, "Doctor") != NULL);

    // Verify character mapping exists
    assert(audio->char_mapping_count > 0);
    assert(audio->char_mapping != NULL);

    printf("✓ sherpa-onnx C API normalized text works\n");

    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
}
```

**Step 6: Build and test**

```bash
cd ~/projects/sherpa-onnx
mkdir -p build && cd build
cmake -DBUILD_SHARED_LIBS=ON ..
make -j4

# Run test
./sherpa-onnx/c-api/test-normalized-text
```

Expected: "✓ sherpa-onnx C API normalized text works"

**Step 7: Commit sherpa-onnx changes**

```bash
git add sherpa-onnx/c-api/c-api.h sherpa-onnx/csrc/offline-tts.h sherpa-onnx/c-api/test-normalized-text.c
git commit -m "feat: expose normalized text and character mapping through C API"
```

---

## Task 5: Update Swift SherpaOnnx Wrapper

**Goal:** Expose normalized text in Swift wrapper

**Files:**
- Modify: `~/projects/Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

**Step 1: Add normalized text to GeneratedAudio struct**

```swift
struct GeneratedAudio {
    let samples: [Float]
    let sampleRate: Int32
    let phonemes: [PhonemeInfo]

    // NEW
    let normalizedText: String
    let charMapping: [(originalPos: Int, normalizedPos: Int)]
}
```

**Step 2: Extract from C API in generate()**

```swift
func generate(text: String, sid: Int32, speed: Float) -> GeneratedAudio {
    let audio = SherpaOnnxOfflineTtsGenerate(tts, text, sid, speed)
    defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

    // ... existing sample/phoneme extraction ...

    // NEW: Extract normalized text
    let normalizedText: String
    if let normalized = audio.pointee.normalized_text {
        normalizedText = String(cString: normalized)
    } else {
        normalizedText = ""
    }

    // NEW: Extract character mapping
    var charMapping: [(Int, Int)] = []
    if let mapping = audio.pointee.char_mapping {
        for i in 0..<Int(audio.pointee.char_mapping_count) {
            let origPos = Int(mapping[i * 2])
            let normPos = Int(mapping[i * 2 + 1])
            charMapping.append((origPos, normPos))
        }
    }

    return GeneratedAudio(
        samples: samples,
        sampleRate: sampleRate,
        phonemes: phonemes,
        normalizedText: normalizedText,
        charMapping: charMapping
    )
}
```

**Step 3: Write Swift test**

Create: `~/projects/Listen2/Listen2Tests/Services/TTS/SherpaOnnxNormalizedTextTests.swift`

```swift
import XCTest
@testable import Listen2

class SherpaOnnxNormalizedTextTests: XCTestCase {
    func testNormalizedTextExtraction() async throws {
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: /* ... */)
        let audio = wrapper.generate(text: "Dr. Smith's", sid: 0, speed: 1.0)

        // Verify normalized text
        XCTAssertFalse(audio.normalizedText.isEmpty)
        XCTAssertTrue(audio.normalizedText.contains("Doctor"))

        // Verify character mapping
        XCTAssertGreaterThan(audio.charMapping.count, 0)

        print("✓ Swift normalized text extraction works")
    }
}
```

**Step 4: Run test**

```bash
cd ~/projects/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:Listen2Tests/SherpaOnnxNormalizedTextTests
```

Expected: Test passes

**Step 5: Commit Swift wrapper changes**

```bash
git add Listen2/Services/TTS/SherpaOnnx.swift Listen2Tests/Services/TTS/SherpaOnnxNormalizedTextTests.swift
git commit -m "feat: extract normalized text from sherpa-onnx C API"
```

---

## Task 6: Update PhonemeAlignmentService to Use Normalized Text

**Goal:** Map VoxPDF words (original text) to phoneme positions (normalized text) using character mapping

**Files:**
- Modify: `~/projects/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Modify: `~/projects/Listen2/Listen2/Listen2/Services/TTS/PiperTTSProvider.swift`

**Step 1: Update SynthesisResult to include normalized text**

In `PiperTTSProvider.swift`:

```swift
struct SynthesisResult {
    let audioData: Data
    let phonemes: [PhonemeInfo]
    let text: String
    let sampleRate: Int32

    // NEW
    let normalizedText: String
    let charMapping: [(originalPos: Int, normalizedPos: Int)]
}
```

**Step 2: Populate in synthesize()**

```swift
func synthesize(_ text: String, speed: Float) async throws -> SynthesisResult {
    let audio = tts.generate(text: text, sid: 0, speed: clampedSpeed)
    let wavData = createWAVData(samples: audio.samples, sampleRate: Int(audio.sampleRate))

    return SynthesisResult(
        audioData: wavData,
        phonemes: audio.phonemes,
        text: text,
        sampleRate: audio.sampleRate,
        normalizedText: audio.normalizedText,  // NEW
        charMapping: audio.charMapping  // NEW
    )
}
```

**Step 3: Add normalized text mapping to PhonemeAlignmentService**

```swift
actor PhonemeAlignmentService {

    func align(
        phonemes: [PhonemeInfo],
        text: String,
        normalizedText: String,  // NEW parameter
        charMapping: [(Int, Int)],  // NEW parameter
        wordMap: DocumentWordMap?,
        paragraphIndex: Int
    ) async throws -> AlignmentResult {

        // Step 1: Extract VoxPDF words from original text
        guard let wordMap = wordMap else {
            // Fallback to text splitting for non-PDF sources
            return try alignWithoutWordMap(phonemes, normalizedText)
        }

        let voxpdfWords = wordMap.words(in: paragraphIndex)

        // Step 2: For each VoxPDF word, find corresponding position in normalized text
        var wordTimings: [AlignmentResult.WordTiming] = []

        for voxWord in voxpdfWords {
            // VoxWord has: .text, .characterRange (in original text)
            let originalStart = voxWord.characterRange.lowerBound
            let originalEnd = voxWord.characterRange.upperBound

            // NEW: Map original positions to normalized positions
            let normalizedStart = mapToNormalized(originalPos: originalStart, mapping: charMapping)
            let normalizedEnd = mapToNormalized(originalPos: originalEnd, mapping: charMapping)

            // Find phonemes in this normalized range
            let wordPhonemes = phonemes.filter { phoneme in
                phoneme.textRange.lowerBound >= normalizedStart &&
                phoneme.textRange.upperBound <= normalizedEnd
            }

            // Calculate timing
            let duration = wordPhonemes.reduce(0.0) { $0 + $1.duration }
            let startTime = wordPhonemes.first?.startTime ?? 0

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: wordTimings.count,
                startTime: startTime,
                duration: duration,
                text: voxWord.text,
                stringRange: voxWord.characterRange  // Original text range
            ))
        }

        return AlignmentResult(
            paragraphIndex: paragraphIndex,
            totalDuration: wordTimings.last?.endTime ?? 0,
            wordTimings: wordTimings
        )
    }

    // NEW: Character position mapping helper
    private func mapToNormalized(originalPos: Int, mapping: [(Int, Int)]) -> Int {
        // Find the mapping entry for this position
        for (i, map) in mapping.enumerated() {
            if originalPos >= map.0 {
                if i + 1 < mapping.count {
                    let nextMap = mapping[i + 1]
                    if originalPos < nextMap.0 {
                        // Position is between map[i] and map[i+1]
                        let offset = originalPos - map.0
                        return map.1 + offset
                    }
                } else {
                    // Last mapping entry
                    let offset = originalPos - map.0
                    return map.1 + offset
                }
            }
        }
        return originalPos  // Fallback if not in mapping
    }
}
```

**Step 4: Write test for abbreviation mapping**

Create: `~/projects/Listen2/Listen2Tests/Services/PhonemeAlignmentAbbreviationTests.swift`

```swift
import XCTest
@testable import Listen2

class PhonemeAlignmentAbbreviationTests: XCTestCase {
    func testDoctorAbbreviation() async throws {
        let service = PhonemeAlignmentService()

        // Original text from VoxPDF: "Dr. Smith's"
        let originalText = "Dr. Smith's"

        // Normalized by espeak: "Doctor Smith's"
        let normalizedText = "Doctor Smith's"

        // Character mapping: "Dr." (0-3) -> "Doctor" (0-6)
        let charMapping = [
            (0, 0),   // "D" -> "D"
            (3, 6),   // end of "Dr." -> end of "Doctor"
            (4, 7)    // " " -> " "
        ]

        // Phonemes with positions in NORMALIZED text
        let phonemes = [
            PhonemeInfo(symbol: "d", duration: 0.1, textRange: 0..<1),   // "D" in "Doctor"
            PhonemeInfo(symbol: "ɑ", duration: 0.1, textRange: 1..<2),   // "o" in "Doctor"
            // ... etc for all of "Doctor"
        ]

        // VoxPDF word map (positions in ORIGINAL text)
        let wordMap = DocumentWordMap(
            documentID: "test",
            paragraphs: [
                [
                    VoxWord(text: "Dr.", characterRange: 0..<3),
                    VoxWord(text: "Smith's", characterRange: 4..<11)
                ]
            ]
        )

        let result = try await service.align(
            phonemes: phonemes,
            text: originalText,
            normalizedText: normalizedText,
            charMapping: charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify first word timing corresponds to "Dr." in original text
        XCTAssertEqual(result.wordTimings.first?.text, "Dr.")
        XCTAssertGreaterThan(result.wordTimings.first?.duration ?? 0, 0)

        print("✓ Abbreviation mapping works correctly")
    }
}
```

**Step 5: Run test**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:Listen2Tests/PhonemeAlignmentAbbreviationTests
```

Expected: Test passes

**Step 6: Commit alignment service changes**

```bash
git add Listen2/Services/TTS/PhonemeAlignmentService.swift Listen2/Services/TTS/PiperTTSProvider.swift Listen2Tests/Services/PhonemeAlignmentAbbreviationTests.swift
git commit -m "feat: map VoxPDF words to phoneme positions using normalized text"
```

---

## Task 7: Integration Testing

**Goal:** End-to-end test with real PDF containing abbreviations

**Files:**
- Create: `~/projects/Listen2/Listen2Tests/Integration/NormalizedTextIntegrationTests.swift`

**Step 1: Create test PDF with abbreviations**

```swift
func createTestPDF() -> Data {
    // PDF containing: "Dr. Smith's TCP/IP address is 192.168.1.1"
    // ... PDF generation code ...
}
```

**Step 2: Write integration test**

```swift
class NormalizedTextIntegrationTests: XCTestCase {
    func testAbbreviationsInPDF() async throws {
        let pdfData = createTestPDF()
        let documentID = "test-abbreviations"

        // Step 1: Extract with VoxPDF
        let voxpdf = VoxPDFService()
        let wordMap = try await voxpdf.extractText(from: pdfData, documentID: documentID)

        // Verify VoxPDF sees "Dr." not "Doctor"
        let firstWord = wordMap.paragraphs[0][0]
        XCTAssertEqual(firstWord.text, "Dr.")

        // Step 2: Synthesize with Piper
        let tts = PiperTTSProvider(voiceID: "en_US-lessac-medium")
        try await tts.initialize()

        let paragraphText = "Dr. Smith's TCP/IP address is 192.168.1.1"
        let synthesis = try await tts.synthesize(paragraphText, speed: 1.0)

        // Verify normalized text expanded abbreviations
        XCTAssertTrue(synthesis.normalizedText.contains("Doctor"))
        XCTAssertTrue(synthesis.normalizedText.contains("T C P I P"))

        // Step 3: Align with PhonemeAlignmentService
        let alignment = PhonemeAlignmentService()
        let result = try await alignment.align(
            phonemes: synthesis.phonemes,
            text: paragraphText,
            normalizedText: synthesis.normalizedText,
            charMapping: synthesis.charMapping,
            wordMap: wordMap,
            paragraphIndex: 0
        )

        // Verify word timings exist for all VoxPDF words
        XCTAssertEqual(result.wordTimings.count, wordMap.paragraphs[0].count)

        // Verify first word is "Dr." (original) with valid timing
        let firstTiming = result.wordTimings[0]
        XCTAssertEqual(firstTiming.text, "Dr.")
        XCTAssertGreaterThan(firstTiming.duration, 0)

        print("✓ End-to-end abbreviation handling works")
    }
}
```

**Step 3: Run integration test**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:Listen2Tests/NormalizedTextIntegrationTests
```

Expected: All assertions pass

**Step 4: Commit integration test**

```bash
git add Listen2Tests/Integration/NormalizedTextIntegrationTests.swift
git commit -m "test: end-to-end abbreviation handling with VoxPDF + Piper + alignment"
```

---

## Task 8: Rebuild sherpa-onnx Framework for iOS

**Goal:** Build updated sherpa-onnx with normalized text support for iOS deployment

**Files:**
- Modify: `~/projects/sherpa-onnx/build-ios.sh`

**Step 1: Update build script**

Ensure script builds all architectures:

```bash
#!/bin/bash
# build-ios.sh

set -e

ARCHS="arm64 x86_64"  # arm64 for device, x86_64 for simulator
BUILD_DIR="build-ios"

for ARCH in $ARCHS; do
    echo "Building for $ARCH..."

    cmake -S . -B $BUILD_DIR/$ARCH \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=$ARCH \
        -DBUILD_SHARED_LIBS=OFF \
        -DSHERPA_ONNX_ENABLE_TESTS=OFF

    cmake --build $BUILD_DIR/$ARCH --config Release -j4
done

# Create XCFramework
xcodebuild -create-xcframework \
    -framework $BUILD_DIR/arm64/sherpa-onnx.framework \
    -framework $BUILD_DIR/x86_64/sherpa-onnx.framework \
    -output sherpa-onnx.xcframework
```

**Step 2: Build framework**

```bash
cd ~/projects/sherpa-onnx
chmod +x build-ios.sh
./build-ios.sh
```

Expected: `sherpa-onnx.xcframework` created

**Step 3: Replace framework in Listen2 project**

```bash
rm -rf ~/projects/Listen2/Listen2/Frameworks/sherpa-onnx.xcframework
cp -R ~/projects/sherpa-onnx/sherpa-onnx.xcframework ~/projects/Listen2/Listen2/Frameworks/
```

**Step 4: Verify build in Xcode**

```bash
cd ~/projects/Listen2/Listen2
xcodebuild clean build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

Expected: BUILD SUCCEEDED

**Step 5: Commit framework update**

```bash
cd ~/projects/Listen2
git add Listen2/Frameworks/sherpa-onnx.xcframework
git commit -m "build: update sherpa-onnx framework with normalized text support"
```

---

## Task 9: Manual Testing on Device

**Goal:** Verify word highlighting works correctly with real abbreviations on iPhone

**Steps:**

**Step 1: Build and deploy to iPhone**

1. Connect iPhone 15 Pro Max via USB
2. Open Xcode → Select Listen2 scheme → Select your device
3. Product → Run (⌘R)

**Step 2: Test Welcome PDF with abbreviations**

Create a test PDF with:
```
Dr. Smith's office is located at 123 Main St., Suite 4B.
Please contact him via TCP/IP at 192.168.1.1 or call (555) 123-4567.
```

**Step 3: Observe word highlighting**

1. Open the test PDF in Listen2
2. Tap play ▶️
3. Watch word highlighting

**Expected behavior:**
- "Dr." highlights when "Doctor" is spoken
- "St." highlights when "Street" is spoken
- "TCP/IP" highlights correctly when "T C P I P" is spoken
- Numbers highlight when spelled out versions are spoken

**Step 4: Check console logs**

Xcode → Window → Devices and Simulators → Select iPhone → Open Console

Look for:
```
[PiperTTS] Normalized text: "Doctor Smith's office is located at one hundred twenty three Main Street..."
[PhonemeAlign] Mapping VoxPDF word 'Dr.' (0-3) to normalized 'Doctor' (0-6)
[PhonemeAlign] ✅ Aligned 15 words, total duration: 8.50s
```

**Step 5: Document test results**

Create: `docs/manual-testing/normalized-text-verification.md`

Document:
- Which abbreviations were tested
- Whether highlighting matched speech accurately
- Any edge cases discovered
- Screenshots/video if possible

---

## Task 10: Contribute Back to Open Source

**Goal:** Submit improvements to upstream projects

**Step 1: Create espeak-ng pull request**

```bash
cd ~/projects/espeak-ng
git push fork feature/expose-normalized-text

# Create PR on GitHub
gh pr create \
    --repo espeak-ng/espeak-ng \
    --base master \
    --head zachswift615:feature/expose-normalized-text \
    --title "feat: expose normalized text and character mapping via API" \
    --body "This PR adds API functions to retrieve the normalized text and character position mapping from espeak-ng text processing. This enables downstream applications to map between original input text and espeak's normalized representation, which is essential for accurate word-level synchronization in TTS applications."
```

**Step 2: Create piper-phonemize pull request**

```bash
cd ~/projects/piper-phonemize
git push origin feature/normalized-text-exposure

gh pr create \
    --repo rhasspy/piper-phonemize \
    --base master \
    --head zachswift615:feature/normalized-text-exposure \
    --title "feat: expose normalized text from espeak-ng" \
    --body "Captures and exposes the normalized text and character mapping from espeak-ng, enabling accurate word-level alignment for TTS applications."
```

**Step 3: Create sherpa-onnx pull request**

```bash
cd ~/projects/sherpa-onnx
git push origin feature/expose-normalized-text

gh pr create \
    --repo k2-fsa/sherpa-onnx \
    --base master \
    --head zachswift615:feature/expose-normalized-text \
    --title "feat: expose normalized text through TTS C API" \
    --body "Threads normalized text and character position mapping through the TTS pipeline and exposes it via C API, enabling accurate word-level synchronization for applications using espeak-based TTS."
```

**Step 4: Document contributions**

```bash
cd ~/projects/Listen2
workshop decision "Contributed normalized text exposure to espeak-ng, piper-phonemize, and sherpa-onnx" \
    -r "These changes enable the entire open-source TTS ecosystem to support accurate word-level highlighting with abbreviations, contractions, and number normalization. Submitted PRs to upstream projects for community benefit."
```

---

## Verification Checklist

Use @superpowers:verification-before-completion before claiming completion:

- [ ] espeak-ng fork compiles and passes tests
- [ ] piper-phonemize captures normalized text correctly
- [ ] sherpa-onnx C API exposes normalized text
- [ ] Swift wrapper extracts normalized text
- [ ] PhonemeAlignmentService maps VoxPDF → normalized correctly
- [ ] Unit tests pass for all modified components
- [ ] Integration test with abbreviations passes
- [ ] iOS framework builds successfully
- [ ] Manual device testing shows accurate highlighting
- [ ] Pull requests submitted to upstream projects

## Timeline Estimate

- Tasks 1-3 (espeak-ng + piper-phonemize): 1-2 weeks
- Tasks 4-6 (sherpa-onnx + Swift): 1 week
- Tasks 7-9 (testing + iOS build): 3-5 days
- Task 10 (upstream contributions): 2-3 days

**Total: 3-4 weeks** for complete implementation and testing

---

## Notes for Future Sessions

- espeak-ng fork: `~/projects/espeak-ng` (branch: `feature/expose-normalized-text`)
- piper-phonemize fork: `~/projects/piper-phonemize` (branch: `feature/normalized-text-exposure`)
- sherpa-onnx fork: `~/projects/sherpa-onnx` (branch: `feature/expose-normalized-text`)

All modifications follow the principle: **capture at the source (espeak), thread through the pipeline, use at the destination (Swift)**.
