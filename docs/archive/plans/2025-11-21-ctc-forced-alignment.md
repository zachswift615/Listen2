# CTC Forced Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace drifty phoneme-duration and error-prone ASR+DTW approaches with true CTC forced alignment for frame-accurate word highlighting.

**Architecture:** Use MMS_FA model (wav2vec2-based) exported to ONNX for on-device forced alignment. The model takes audio + known transcript and outputs frame-level alignments via CTC trellis algorithm. This eliminates ASR transcription errors since we already know the text.

**Tech Stack:** Swift, ONNX Runtime, MMS_FA model (TorchAudio), Python (model export only)

---

## Spike Results (2025-11-21)

Validated via `scripts/spike_mms_fa.py`:

| Aspect | Result |
|--------|--------|
| Model loads | ✅ torchaudio.pipelines.MMS_FA |
| Labels | 29 chars: `'-', 'a', 'i', 'e', 'n', 'o', 'u', 't', 's', 'r', 'm', 'k', 'l', 'd', 'g', 'h', 'y', 'b', 'p', 'w', 'c', 'v', 'j', 'z', 'f', "'", 'q', 'x', '*'` |
| **ONNX size** | **3.1 MB** (not 1.2GB!) |
| ONNX inference | ✅ Matches PyTorch |
| Frame rate | 49 fps (20ms frames) |
| Variable length | ✅ Dynamic axes work |

**Key:** Blank token is `-` at index 0. Space token is `*` at index 28. Apostrophe `'` is at index 25.

---

## Background

### Why Change?

**Current Phoneme Duration Approach Problems:**
- Durations drift because they don't account for pauses, spaces, punctuation
- Requires re-exporting voice models with w_ceil tensor (locks us to specific voices)
- Scaling durations to audio length doesn't fix non-linear timing errors

**Current ASR+DTW Approach (WordAlignmentService) Problems:**
- ASR transcription introduces errors (wrong words = wrong timestamps)
- DTW matching between ASR tokens and VoxPDF words is fuzzy and error-prone
- Crashes on apostrophes, punctuation, Unicode edge cases
- 44MB+ model files for ASR that we don't really need

**Why CTC Forced Alignment is Different:**
- Uses **known transcript** (no guessing what was said)
- CTC trellis algorithm provides **frame-level alignment**
- No DTW approximation - exact alignment path through probability matrix
- Works with any Piper voice (no model re-export required)

---

## Task 1: Export MMS_FA Model to ONNX

**Files:**
- Create: `scripts/export_mms_fa_model.py`
- Create: `Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa/mms-fa.onnx`
- Create: `Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa/labels.txt`

**Step 1: Create Python virtual environment**

Run:
```bash
cd /Users/zachswift/projects/Listen2
python3 -m venv venv-mms-export
source venv-mms-export/bin/activate
pip install torch torchaudio onnx onnxruntime
```

**Step 2: Write the export script**

Create `scripts/export_mms_fa_model.py`:

```python
#!/usr/bin/env python3
"""Export MMS_FA model to ONNX for iOS forced alignment."""

import torch
import torchaudio
from torchaudio.pipelines import MMS_FA as bundle
import os

def export_mms_fa():
    print("Loading MMS_FA model...")
    model = bundle.get_model()
    model.eval()

    # Get sample rate and create dummy input
    sample_rate = bundle.sample_rate  # 16000
    dummy_audio = torch.randn(1, 16000)  # 1 second of audio

    print(f"Model sample rate: {sample_rate}")
    print(f"Dummy input shape: {dummy_audio.shape}")

    # Export to ONNX
    output_dir = "Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa"
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "mms-fa.onnx")

    print(f"Exporting to {output_path}...")
    torch.onnx.export(
        model,
        dummy_audio,
        output_path,
        input_names=["audio"],
        output_names=["emissions"],
        dynamic_axes={
            "audio": {0: "batch", 1: "time"},
            "emissions": {0: "batch", 1: "frames", 2: "vocab"}
        },
        opset_version=14
    )

    print("Export complete!")

    # Save labels
    labels = bundle.get_labels()
    labels_path = os.path.join(output_dir, "labels.txt")
    with open(labels_path, "w") as f:
        for label in labels:
            f.write(f"{label}\n")
    print(f"Saved {len(labels)} labels to {labels_path}")

    # Print labels for reference
    print(f"Labels: {labels}")

    # Verify export
    import onnxruntime as ort
    session = ort.InferenceSession(output_path)
    test_output = session.run(None, {"audio": dummy_audio.numpy()})
    print(f"Verification - Output shape: {test_output[0].shape}")
    print(f"Expected frames: ~{16000 // 320} (320 sample hop)")

    # Check file size
    file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"Model size: {file_size_mb:.1f} MB")

    return output_path, labels_path

if __name__ == "__main__":
    export_mms_fa()
```

**Step 3: Run the export**

Run:
```bash
source venv-mms-export/bin/activate
python scripts/export_mms_fa_model.py
```
Expected: Model exported, labels saved, verification passes

**Step 4: Add model to Git LFS**

Run:
```bash
# Ensure .gitattributes has ONNX rule
grep -q "*.onnx" .gitattributes || echo "*.onnx filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
git add .gitattributes
git add scripts/export_mms_fa_model.py
git add Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa/
git commit -m "feat: add MMS_FA model export script and ONNX model for forced alignment"
```

---

## Task 2: Create CTCTokenizer

**Files:**
- Create: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCTokenizer.swift`
- Create: `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCTokenizerTests.swift`

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCTokenizerTests.swift`:

```swift
import XCTest
@testable import Listen2

final class CTCTokenizerTests: XCTestCase {

    var tokenizer: CTCTokenizer!

    override func setUp() async throws {
        try await super.setUp()
        // Load labels from test bundle or create mock
        let testLabels = ["-", "|", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "'"]
        tokenizer = CTCTokenizer(labels: testLabels)
    }

    func testTokenizeSimpleWord() {
        let tokens = tokenizer.tokenize("hello")
        XCTAssertEqual(tokens.count, 5) // h, e, l, l, o
        XCTAssertTrue(tokens.allSatisfy { $0 >= 0 })
    }

    func testTokenizeWithSpaces() {
        let tokens = tokenizer.tokenize("hello world")
        XCTAssertEqual(tokens.count, 11) // hello + space + world
    }

    func testTokenizeHandlesUnknownChars() {
        let tokens = tokenizer.tokenize("hello!")
        // Exclamation not in vocab, should be skipped
        XCTAssertEqual(tokens.count, 5)
    }

    func testTokenizeUppercase() {
        let tokens = tokenizer.tokenize("HELLO")
        // Should lowercase
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens, tokenizer.tokenize("hello"))
    }

    func testBlankTokenIndex() {
        XCTAssertEqual(tokenizer.blankIndex, 0) // "-" is blank at index 0
    }

    func testSpaceTokenIndex() {
        XCTAssertEqual(tokenizer.spaceIndex, 1) // "|" is space at index 1
    }

    func testVocabSize() {
        XCTAssertEqual(tokenizer.vocabSize, 29)
    }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCTokenizerTests 2>&1 | head -50
```
Expected: FAIL - CTCTokenizer not found

**Step 3: Write implementation**

Create `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCTokenizer.swift`:

```swift
//
//  CTCTokenizer.swift
//  Listen2
//
//  Tokenizes text for CTC forced alignment using MMS_FA vocabulary
//

import Foundation

/// Tokenizes text into indices for CTC forced alignment
final class CTCTokenizer {

    // MARK: - Properties

    /// Label to index mapping
    private let labelToIndex: [String: Int]

    /// Index to label mapping (for debugging)
    private let indexToLabel: [Int: String]

    /// Blank token index (for CTC)
    let blankIndex: Int

    /// Space token index
    let spaceIndex: Int?

    /// Vocabulary size
    let vocabSize: Int

    // MARK: - Initialization

    /// Initialize with labels array
    /// - Parameter labels: Array of label strings in vocabulary order
    init(labels: [String]) {
        var l2i: [String: Int] = [:]
        var i2l: [Int: String] = [:]

        for (index, label) in labels.enumerated() {
            l2i[label] = index
            i2l[index] = label
        }

        self.labelToIndex = l2i
        self.indexToLabel = i2l
        self.vocabSize = labels.count

        // CTC blank is typically "-" or "*" at index 0
        self.blankIndex = l2i["-"] ?? l2i["*"] ?? l2i["<blank>"] ?? 0

        // Space token is typically "|" in MMS_FA
        self.spaceIndex = l2i["|"] ?? l2i[" "] ?? l2i["<space>"]
    }

    /// Initialize from labels file
    /// - Parameter labelsPath: Path to labels.txt file (one label per line)
    convenience init(labelsPath: String) throws {
        let content = try String(contentsOfFile: labelsPath, encoding: .utf8)
        let labels = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        self.init(labels: labels)
    }

    // MARK: - Tokenization

    /// Tokenize text into token indices
    /// - Parameter text: Text to tokenize
    /// - Returns: Array of token indices
    func tokenize(_ text: String) -> [Int] {
        var tokens: [Int] = []

        let normalized = text.lowercased()

        for char in normalized {
            if char == " " {
                // Add space token if available
                if let spaceIdx = spaceIndex {
                    tokens.append(spaceIdx)
                }
            } else {
                let charStr = String(char)
                if let idx = labelToIndex[charStr] {
                    tokens.append(idx)
                }
                // Skip unknown characters silently
            }
        }

        return tokens
    }

    /// Get label for token index (for debugging)
    /// - Parameter index: Token index
    /// - Returns: Label string or nil if invalid index
    func label(for index: Int) -> String? {
        return indexToLabel[index]
    }

    /// Convert token indices back to text (for debugging)
    /// - Parameter tokens: Array of token indices
    /// - Returns: Reconstructed text
    func detokenize(_ tokens: [Int]) -> String {
        return tokens.compactMap { indexToLabel[$0] }
            .joined()
            .replacingOccurrences(of: "|", with: " ")
    }
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCTokenizerTests 2>&1 | tail -20
```
Expected: All tests pass

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCTokenizer.swift
git add Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCTokenizerTests.swift
git commit -m "feat: add CTCTokenizer for MMS_FA vocabulary"
```

---

## Task 3: Create CTCForcedAligner - Core Structure

**Files:**
- Create: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`
- Create: `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift`

**Step 1: Write the failing test**

Create `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift`:

```swift
import XCTest
@testable import Listen2

final class CTCForcedAlignerTests: XCTestCase {

    func testInitializationWithMockLabels() async throws {
        let aligner = CTCForcedAligner()

        // Initialize with test labels (no model needed for structure test)
        let testLabels = ["-", "|", "a", "b", "c", "d", "e", "h", "l", "o", "w", "r"]
        try await aligner.initializeWithLabels(testLabels)

        XCTAssertTrue(aligner.isInitialized)
    }

    func testSampleRateIs16kHz() {
        let aligner = CTCForcedAligner()
        XCTAssertEqual(aligner.sampleRate, 16000)
    }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests/testInitializationWithMockLabels 2>&1 | head -50
```
Expected: FAIL - CTCForcedAligner not found

**Step 3: Write implementation**

Create `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`:

```swift
//
//  CTCForcedAligner.swift
//  Listen2
//
//  CTC forced alignment for word-level timestamps using MMS_FA model.
//  Uses known transcript (not ASR transcription) for accurate alignment.
//

import Foundation
import AVFoundation

/// Performs CTC forced alignment to get word timestamps from audio + known text
actor CTCForcedAligner {

    // MARK: - Types

    /// Token span from backtracking
    struct TokenSpan {
        let tokenIndex: Int
        let startFrame: Int
        let endFrame: Int
    }

    // MARK: - Properties

    /// Tokenizer for converting text to tokens
    private var tokenizer: CTCTokenizer?

    /// Whether initialized
    private(set) var isInitialized = false

    /// Expected sample rate (MMS_FA uses 16kHz)
    nonisolated let sampleRate: Int = 16000

    /// Frame hop size in samples (MMS_FA uses 320)
    private let hopSize: Int = 320

    // MARK: - Initialization

    /// Initialize with bundled model
    func initialize() async throws {
        guard let modelDir = Bundle.main.path(forResource: "mms-fa", ofType: nil, inDirectory: "Models") else {
            throw AlignmentError.modelNotInitialized
        }
        try await initialize(modelPath: modelDir)
    }

    /// Initialize with custom model path
    func initialize(modelPath: String) async throws {
        let labelsFile = (modelPath as NSString).appendingPathComponent("labels.txt")

        guard FileManager.default.fileExists(atPath: labelsFile) else {
            throw AlignmentError.modelNotInitialized
        }

        // Initialize tokenizer
        tokenizer = try CTCTokenizer(labelsPath: labelsFile)

        // TODO: Initialize ONNX session in Task 6

        isInitialized = true
        print("[CTCForcedAligner] Initialized with vocab size: \(tokenizer?.vocabSize ?? 0)")
    }

    /// Initialize with labels array (for testing)
    func initializeWithLabels(_ labels: [String]) async throws {
        tokenizer = CTCTokenizer(labels: labels)
        isInitialized = true
    }

    deinit {
        // Cleanup will be added when ONNX session is implemented
    }
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests 2>&1 | tail -20
```
Expected: All tests pass

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift
git add Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift
git commit -m "feat: add CTCForcedAligner core structure"
```

---

## Task 4: Implement CTC Trellis Algorithm

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`
- Modify: `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift`

**Step 1: Write the failing test**

Add to `CTCForcedAlignerTests.swift`:

```swift
func testBuildTrellis() async throws {
    let aligner = CTCForcedAligner()
    let testLabels = ["-", "|", "a", "b"]  // blank, space, a, b
    try await aligner.initializeWithLabels(testLabels)

    // Simulate emissions: 6 frames, vocab size 4
    // Token sequence: [2, 3] (characters "a", "b")
    let emissions: [[Float]] = [
        [-1.0, -10.0, -0.1, -10.0],  // Frame 0: "a" likely
        [-1.0, -10.0, -0.1, -10.0],  // Frame 1: "a" likely
        [-0.1, -10.0, -10.0, -10.0], // Frame 2: blank likely
        [-10.0, -10.0, -10.0, -0.1], // Frame 3: "b" likely
        [-10.0, -10.0, -10.0, -0.1], // Frame 4: "b" likely
        [-0.1, -10.0, -10.0, -10.0], // Frame 5: blank likely
    ]

    let tokens = [2, 3]  // "a", "b"

    let trellis = await aligner.buildTrellis(emissions: emissions, tokens: tokens)

    // Trellis should have 6 rows (frames) and 5 columns (blank, a, blank, b, blank)
    XCTAssertEqual(trellis.count, 6)
    XCTAssertEqual(trellis[0].count, 5)  // 2*2 + 1 = 5 states
}

func testBacktrack() async throws {
    let aligner = CTCForcedAligner()
    let testLabels = ["-", "|", "a", "b"]
    try await aligner.initializeWithLabels(testLabels)

    // Create a trellis where the optimal path is clear
    // States: [blank, a, blank, b, blank]
    let trellis: [[Float]] = [
        [-0.1, -10, -10, -10, -10],  // Frame 0: start at blank
        [-10, -0.1, -10, -10, -10],  // Frame 1: "a"
        [-10, -0.1, -10, -10, -10],  // Frame 2: "a"
        [-10, -10, -0.1, -10, -10],  // Frame 3: blank
        [-10, -10, -10, -0.1, -10],  // Frame 4: "b"
        [-10, -10, -10, -10, -0.1],  // Frame 5: end at blank
    ]

    let tokens = [2, 3]  // "a", "b"
    let spans = await aligner.backtrack(trellis: trellis, tokens: tokens)

    // Should find 2 token spans
    XCTAssertEqual(spans.count, 2)

    // First span: "a" at frames 1-2
    XCTAssertEqual(spans[0].tokenIndex, 0)
    XCTAssertEqual(spans[0].startFrame, 1)
    XCTAssertEqual(spans[0].endFrame, 2)

    // Second span: "b" at frame 4
    XCTAssertEqual(spans[1].tokenIndex, 1)
    XCTAssertEqual(spans[1].startFrame, 4)
    XCTAssertEqual(spans[1].endFrame, 4)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests/testBuildTrellis 2>&1 | head -50
```
Expected: FAIL - buildTrellis method not found

**Step 3: Write implementation**

Add to `CTCForcedAligner.swift`:

```swift
// MARK: - CTC Trellis Algorithm

/// Build CTC trellis matrix for forced alignment
///
/// The trellis has states: [blank, token0, blank, token1, blank, ...]
/// This allows the model to insert blanks between tokens (CTC property).
///
/// - Parameters:
///   - emissions: Frame-wise log probabilities [frames x vocab]
///   - tokens: Target token sequence (without blanks)
/// - Returns: Trellis matrix [frames x (2*tokens+1)]
func buildTrellis(emissions: [[Float]], tokens: [Int]) -> [[Float]] {
    guard let tokenizer = tokenizer else { return [] }

    let numFrames = emissions.count
    let numTokens = tokens.count
    let numStates = 2 * numTokens + 1  // blank, token, blank, token, ..., blank
    let blankIndex = tokenizer.blankIndex

    // Initialize trellis with -infinity (log probability)
    var trellis = [[Float]](
        repeating: [Float](repeating: -.infinity, count: numStates),
        count: numFrames
    )

    // Initial probabilities (can start at first blank or first token)
    trellis[0][0] = emissions[0][blankIndex]  // Start with blank
    if numTokens > 0 {
        trellis[0][1] = emissions[0][tokens[0]]  // Or start with first token
    }

    // Fill trellis using dynamic programming
    for t in 1..<numFrames {
        for s in 0..<numStates {
            let isBlank = (s % 2 == 0)
            let tokenIdx = s / 2  // Which token this state represents

            // Get emission log probability for this state
            let emitProb: Float
            if isBlank {
                emitProb = emissions[t][blankIndex]
            } else if tokenIdx < tokens.count {
                emitProb = emissions[t][tokens[tokenIdx]]
            } else {
                continue
            }

            // Calculate max of valid transitions
            var maxPrev = trellis[t-1][s]  // Stay in current state

            if s > 0 {
                // Can come from previous state
                maxPrev = max(maxPrev, trellis[t-1][s-1])
            }

            // CTC allows skipping blank between different tokens
            if s > 1 && !isBlank {
                let currentToken = tokens[tokenIdx]
                let prevTokenIdx = (s - 2) / 2
                if prevTokenIdx >= 0 && prevTokenIdx < tokens.count {
                    let prevToken = tokens[prevTokenIdx]
                    // Only skip if tokens are different (CTC rule)
                    if currentToken != prevToken {
                        maxPrev = max(maxPrev, trellis[t-1][s-2])
                    }
                }
            }

            trellis[t][s] = maxPrev + emitProb
        }
    }

    return trellis
}

/// Backtrack through trellis to find optimal alignment path
/// - Parameters:
///   - trellis: Filled trellis matrix [frames x states]
///   - tokens: Target token sequence
/// - Returns: Array of token spans with frame boundaries
func backtrack(trellis: [[Float]], tokens: [Int]) -> [TokenSpan] {
    guard !trellis.isEmpty, !tokens.isEmpty else { return [] }

    let numFrames = trellis.count
    let numStates = trellis[0].count

    // Find best ending state (last blank or last token)
    var currentState = numStates - 1  // Last blank
    if numStates >= 2 && trellis[numFrames - 1][numStates - 2] > trellis[numFrames - 1][numStates - 1] {
        currentState = numStates - 2  // Last token
    }

    // Backtrack to build path
    var path: [(frame: Int, state: Int)] = [(numFrames - 1, currentState)]

    for t in stride(from: numFrames - 2, through: 0, by: -1) {
        // Find which previous state we came from
        var bestPrevState = currentState
        var bestScore = trellis[t][currentState]

        // Check coming from previous state
        if currentState > 0 && trellis[t][currentState - 1] > bestScore {
            bestPrevState = currentState - 1
            bestScore = trellis[t][currentState - 1]
        }

        // Check skipping blank (for non-blank states with different tokens)
        if currentState > 1 {
            let isBlank = (currentState % 2 == 0)
            if !isBlank {
                let tokenIdx = currentState / 2
                let prevTokenIdx = (currentState - 2) / 2
                if tokenIdx > 0 && tokenIdx < tokens.count && prevTokenIdx >= 0 && prevTokenIdx < tokens.count {
                    if tokens[tokenIdx] != tokens[prevTokenIdx] {
                        if trellis[t][currentState - 2] > bestScore {
                            bestPrevState = currentState - 2
                        }
                    }
                }
            }
        }

        currentState = bestPrevState
        path.insert((t, currentState), at: 0)
    }

    // Convert path to token spans (merge consecutive frames for same token)
    var spans: [TokenSpan] = []
    var currentTokenIdx = -1
    var spanStart = 0

    for (frame, state) in path {
        let isBlank = (state % 2 == 0)
        if !isBlank {
            let tokenIdx = state / 2
            if tokenIdx != currentTokenIdx {
                // End previous span if exists
                if currentTokenIdx >= 0 && currentTokenIdx < tokens.count {
                    spans.append(TokenSpan(
                        tokenIndex: currentTokenIdx,
                        startFrame: spanStart,
                        endFrame: frame - 1
                    ))
                }
                // Start new span
                currentTokenIdx = tokenIdx
                spanStart = frame
            }
        }
    }

    // Add final span
    if currentTokenIdx >= 0 && currentTokenIdx < tokens.count {
        spans.append(TokenSpan(
            tokenIndex: currentTokenIdx,
            startFrame: spanStart,
            endFrame: path.last?.frame ?? spanStart
        ))
    }

    return spans
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests 2>&1 | tail -30
```
Expected: All tests pass

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift
git add Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift
git commit -m "feat: implement CTC trellis algorithm for forced alignment"
```

---

## Task 5: Implement Word Merging

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`
- Modify: `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift`

**Step 1: Write the failing test**

Add to `CTCForcedAlignerTests.swift`:

```swift
func testMergeToWords() async throws {
    let aligner = CTCForcedAligner()
    let testLabels = ["-", "|", "a", "b", "c", "h", "e", "l", "o", "w", "r", "d"]
    try await aligner.initializeWithLabels(testLabels)

    // Simulate "hello world" tokenized as: h,e,l,l,o,|,w,o,r,l,d
    // Token indices: 5,6,7,7,8,1,9,8,10,7,11
    let transcript = "hello world"

    // Token spans from backtracking (each character has frames)
    let tokenSpans: [CTCForcedAligner.TokenSpan] = [
        CTCForcedAligner.TokenSpan(tokenIndex: 0, startFrame: 0, endFrame: 4),    // h
        CTCForcedAligner.TokenSpan(tokenIndex: 1, startFrame: 5, endFrame: 9),    // e
        CTCForcedAligner.TokenSpan(tokenIndex: 2, startFrame: 10, endFrame: 14),  // l
        CTCForcedAligner.TokenSpan(tokenIndex: 3, startFrame: 15, endFrame: 19),  // l
        CTCForcedAligner.TokenSpan(tokenIndex: 4, startFrame: 20, endFrame: 24),  // o
        CTCForcedAligner.TokenSpan(tokenIndex: 5, startFrame: 25, endFrame: 29),  // | (space)
        CTCForcedAligner.TokenSpan(tokenIndex: 6, startFrame: 30, endFrame: 34),  // w
        CTCForcedAligner.TokenSpan(tokenIndex: 7, startFrame: 35, endFrame: 39),  // o
        CTCForcedAligner.TokenSpan(tokenIndex: 8, startFrame: 40, endFrame: 44),  // r
        CTCForcedAligner.TokenSpan(tokenIndex: 9, startFrame: 45, endFrame: 49),  // l
        CTCForcedAligner.TokenSpan(tokenIndex: 10, startFrame: 50, endFrame: 54), // d
    ]

    let frameRate = 50.0  // 50 frames per second for easy calculation
    let wordTimings = await aligner.mergeToWords(
        tokenSpans: tokenSpans,
        transcript: transcript,
        frameRate: frameRate
    )

    XCTAssertEqual(wordTimings.count, 2)

    // First word: "hello" at frames 0-24 = 0.0s to 0.5s
    XCTAssertEqual(wordTimings[0].text, "hello")
    XCTAssertEqual(wordTimings[0].startTime, 0.0, accuracy: 0.01)
    XCTAssertEqual(wordTimings[0].duration, 0.5, accuracy: 0.01)
    XCTAssertEqual(wordTimings[0].rangeLocation, 0)
    XCTAssertEqual(wordTimings[0].rangeLength, 5)

    // Second word: "world" at frames 30-54 = 0.6s to 1.1s
    XCTAssertEqual(wordTimings[1].text, "world")
    XCTAssertEqual(wordTimings[1].startTime, 0.6, accuracy: 0.01)
    XCTAssertEqual(wordTimings[1].rangeLocation, 6)
    XCTAssertEqual(wordTimings[1].rangeLength, 5)
}

func testMergeToWordsWithApostrophe() async throws {
    let aligner = CTCForcedAligner()
    let testLabels = ["-", "|", "a", "d", "e", "i", "n", "o", "t", "'", "s"]
    try await aligner.initializeWithLabels(testLabels)

    let transcript = "don't do it"

    // Simplified spans for test
    let tokenSpans: [CTCForcedAligner.TokenSpan] = [
        CTCForcedAligner.TokenSpan(tokenIndex: 0, startFrame: 0, endFrame: 9),   // d
        CTCForcedAligner.TokenSpan(tokenIndex: 1, startFrame: 10, endFrame: 19), // o
        CTCForcedAligner.TokenSpan(tokenIndex: 2, startFrame: 20, endFrame: 29), // n
        CTCForcedAligner.TokenSpan(tokenIndex: 3, startFrame: 30, endFrame: 34), // '
        CTCForcedAligner.TokenSpan(tokenIndex: 4, startFrame: 35, endFrame: 44), // t
        CTCForcedAligner.TokenSpan(tokenIndex: 5, startFrame: 45, endFrame: 49), // | (space)
        CTCForcedAligner.TokenSpan(tokenIndex: 6, startFrame: 50, endFrame: 59), // d
        CTCForcedAligner.TokenSpan(tokenIndex: 7, startFrame: 60, endFrame: 69), // o
        CTCForcedAligner.TokenSpan(tokenIndex: 8, startFrame: 70, endFrame: 74), // | (space)
        CTCForcedAligner.TokenSpan(tokenIndex: 9, startFrame: 75, endFrame: 84), // i
        CTCForcedAligner.TokenSpan(tokenIndex: 10, startFrame: 85, endFrame: 99), // t
    ]

    let frameRate = 100.0
    let wordTimings = await aligner.mergeToWords(
        tokenSpans: tokenSpans,
        transcript: transcript,
        frameRate: frameRate
    )

    XCTAssertEqual(wordTimings.count, 3)
    XCTAssertEqual(wordTimings[0].text, "don't")
    XCTAssertEqual(wordTimings[1].text, "do")
    XCTAssertEqual(wordTimings[2].text, "it")
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests/testMergeToWords 2>&1 | head -50
```
Expected: FAIL - mergeToWords method not found

**Step 3: Write implementation**

Add to `CTCForcedAligner.swift`:

```swift
// MARK: - Word Merging

/// Merge character-level token spans into word-level timings
/// - Parameters:
///   - tokenSpans: Character spans from backtracking
///   - transcript: Original text
///   - frameRate: Frames per second for time conversion
/// - Returns: Word-level timing information
func mergeToWords(
    tokenSpans: [TokenSpan],
    transcript: String,
    frameRate: Double
) -> [AlignmentResult.WordTiming] {
    guard let tokenizer = tokenizer else { return [] }

    // Split transcript into words, preserving their positions
    var words: [(text: String, startOffset: Int)] = []
    var currentOffset = 0
    var currentWord = ""
    var wordStart = 0

    for (i, char) in transcript.enumerated() {
        if char == " " {
            if !currentWord.isEmpty {
                words.append((text: currentWord, startOffset: wordStart))
                currentWord = ""
            }
            wordStart = i + 1
        } else {
            if currentWord.isEmpty {
                wordStart = i
            }
            currentWord.append(char)
        }
    }
    if !currentWord.isEmpty {
        words.append((text: currentWord, startOffset: wordStart))
    }

    // Tokenize to map character positions to tokens
    let tokens = tokenizer.tokenize(transcript)

    // Build character-to-token mapping
    // Each character in the transcript maps to a token index
    var charToTokenIndex: [Int] = []
    var charIndex = 0
    for char in transcript.lowercased() {
        if char == " " {
            // Space maps to space token
            if let spaceIdx = tokenizer.spaceIndex {
                charToTokenIndex.append(charToTokenIndex.count)  // Index in tokenSpans
            }
        } else {
            charToTokenIndex.append(charToTokenIndex.count)
        }
        charIndex += 1
    }

    // Group token spans by word
    var wordTimings: [AlignmentResult.WordTiming] = []
    var tokenSpanIndex = 0

    for (wordIdx, word) in words.enumerated() {
        let wordLength = word.text.count
        let wordStart = word.startOffset

        // Find token spans that belong to this word
        var startFrame: Int?
        var endFrame: Int?

        // Count tokens in this word (excluding spaces before)
        let wordTokenCount = tokenizer.tokenize(word.text).count

        if tokenSpanIndex + wordTokenCount <= tokenSpans.count {
            let wordSpans = Array(tokenSpans[tokenSpanIndex..<tokenSpanIndex + wordTokenCount])

            if let first = wordSpans.first, let last = wordSpans.last {
                startFrame = first.startFrame
                endFrame = last.endFrame
            }

            tokenSpanIndex += wordTokenCount
        }

        // Skip space token if present
        if tokenSpanIndex < tokenSpans.count {
            // Check if next span is a space (we don't include it in word timing)
            tokenSpanIndex += 1  // Skip space between words
        }

        if let start = startFrame, let end = endFrame {
            let startTime = Double(start) / frameRate
            let endTime = Double(end + 1) / frameRate

            wordTimings.append(AlignmentResult.WordTiming(
                wordIndex: wordIdx,
                startTime: startTime,
                duration: endTime - startTime,
                text: word.text,
                rangeLocation: wordStart,
                rangeLength: wordLength
            ))
        }
    }

    return wordTimings
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests 2>&1 | tail -30
```
Expected: All tests pass

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift
git add Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift
git commit -m "feat: implement word merging for CTC forced alignment"
```

---

## Task 6: Implement ONNX Inference

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`

**Step 1: Research sherpa-onnx ONNX runtime access**

The sherpa-onnx framework already includes ONNX Runtime. We need to either:
1. Use sherpa-onnx's C API for generic ONNX inference, or
2. Add onnxruntime-objc directly

Check existing sherpa-onnx usage for patterns:

```bash
grep -r "SherpaOnnx\|OrtSession" Listen2/Listen2/Listen2/Listen2/Services/TTS/*.swift | head -20
```

**Step 2: Implement emissions inference**

Add to `CTCForcedAligner.swift`:

```swift
// MARK: - ONNX Inference

/// ONNX Runtime session for MMS_FA model
private var onnxSession: OpaquePointer?

/// Run MMS_FA model to get frame-wise emission probabilities
/// - Parameter samples: Audio samples at 16kHz
/// - Returns: Log probabilities [frames x vocab_size]
func getEmissions(samples: [Float]) throws -> [[Float]] {
    guard isInitialized else {
        throw AlignmentError.modelNotInitialized
    }

    // For now, use placeholder until ONNX integration is complete
    // The actual implementation will depend on how we access ONNX Runtime

    // Expected output shape: [1, num_frames, vocab_size]
    // num_frames = samples.count / hopSize
    let numFrames = max(1, samples.count / hopSize)
    let vocabSize = tokenizer?.vocabSize ?? 36

    // Placeholder: Return uniform log probabilities
    // TODO: Replace with actual ONNX inference
    let logProb = Float(-log(Float(vocabSize)))
    return (0..<numFrames).map { _ in
        [Float](repeating: logProb, count: vocabSize)
    }
}

/// Initialize ONNX session with model file
private func initializeOnnxSession(modelPath: String) throws {
    // TODO: Implement using sherpa-onnx's ONNX runtime or onnxruntime-objc
    // For now, just verify file exists
    guard FileManager.default.fileExists(atPath: modelPath) else {
        throw AlignmentError.modelNotInitialized
    }

    print("[CTCForcedAligner] ONNX model found at: \(modelPath)")
    print("[CTCForcedAligner] Note: Full ONNX inference pending integration")
}
```

**Step 3: Add integration note**

The full ONNX inference will require either:
- Using sherpa-onnx's existing C API for custom model inference
- Adding `onnxruntime-objc` pod to the project

This task creates the structure; full inference may require additional research.

**Step 4: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift
git commit -m "feat: add ONNX inference scaffolding for MMS_FA model"
```

---

## Task 7: Implement Full Alignment Pipeline

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift`
- Modify: `Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift`

**Step 1: Write the failing test**

Add to `CTCForcedAlignerTests.swift`:

```swift
func testFullAlignmentPipeline() async throws {
    let aligner = CTCForcedAligner()
    let testLabels = ["-", "|", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "'"]
    try await aligner.initializeWithLabels(testLabels)

    // Create 1 second of silent audio at 16kHz
    let samples = [Float](repeating: 0.0, count: 16000)
    let transcript = "hello world"

    let result = try await aligner.align(
        audioSamples: samples,
        sampleRate: 16000,
        transcript: transcript,
        paragraphIndex: 0
    )

    XCTAssertEqual(result.paragraphIndex, 0)
    XCTAssertEqual(result.totalDuration, 1.0, accuracy: 0.01)
    // With placeholder emissions, word timings may not be accurate
    // but pipeline should complete without error
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests/testFullAlignmentPipeline 2>&1 | head -50
```
Expected: FAIL - align method not found

**Step 3: Write implementation**

Add to `CTCForcedAligner.swift`:

```swift
// MARK: - Public Alignment API

/// Align audio to transcript and return word timestamps
/// - Parameters:
///   - audioSamples: Audio samples as Float array
///   - sampleRate: Sample rate of input audio
///   - transcript: Known text that was spoken
///   - paragraphIndex: Index for result tracking
/// - Returns: AlignmentResult with word timings
func align(
    audioSamples: [Float],
    sampleRate: Int,
    transcript: String,
    paragraphIndex: Int
) async throws -> AlignmentResult {
    guard isInitialized, let tokenizer = tokenizer else {
        throw AlignmentError.modelNotInitialized
    }

    print("[CTCForcedAligner] Aligning \(audioSamples.count) samples to '\(transcript.prefix(50))...'")

    // 1. Resample if needed
    let samples: [Float]
    if sampleRate != self.sampleRate {
        samples = resample(audioSamples, from: sampleRate, to: self.sampleRate)
        print("[CTCForcedAligner] Resampled from \(sampleRate) to \(self.sampleRate) Hz")
    } else {
        samples = audioSamples
    }

    // 2. Run model to get emissions
    let emissions = try getEmissions(samples: samples)
    print("[CTCForcedAligner] Got \(emissions.count) frames of emissions")

    // 3. Tokenize transcript
    let tokens = tokenizer.tokenize(transcript)
    guard !tokens.isEmpty else {
        print("[CTCForcedAligner] Warning: Empty token sequence")
        return AlignmentResult(paragraphIndex: paragraphIndex, totalDuration: 0, wordTimings: [])
    }
    print("[CTCForcedAligner] Tokenized into \(tokens.count) tokens")

    // 4. Build trellis and backtrack
    let trellis = buildTrellis(emissions: emissions, tokens: tokens)
    let tokenSpans = backtrack(trellis: trellis, tokens: tokens)
    print("[CTCForcedAligner] Found \(tokenSpans.count) token spans")

    // 5. Convert token spans to word timings
    let frameRate = Double(self.sampleRate) / Double(hopSize)
    let wordTimings = mergeToWords(
        tokenSpans: tokenSpans,
        transcript: transcript,
        frameRate: frameRate
    )

    let totalDuration = Double(samples.count) / Double(self.sampleRate)

    print("[CTCForcedAligner] Created \(wordTimings.count) word timings, duration: \(String(format: "%.2f", totalDuration))s")

    return AlignmentResult(
        paragraphIndex: paragraphIndex,
        totalDuration: totalDuration,
        wordTimings: wordTimings
    )
}

// MARK: - Audio Processing

/// Resample audio to target sample rate using linear interpolation
private func resample(_ samples: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
    guard sourceRate != targetRate, sourceRate > 0, targetRate > 0 else {
        return samples
    }

    let ratio = Double(sourceRate) / Double(targetRate)
    let newLength = Int(Double(samples.count) / ratio)

    return (0..<newLength).map { i in
        let srcIdx = Double(i) * ratio
        let srcIdxInt = Int(srcIdx)
        let frac = Float(srcIdx - Double(srcIdxInt))

        if srcIdxInt + 1 < samples.count {
            return samples[srcIdxInt] * (1 - frac) + samples[srcIdxInt + 1] * frac
        } else {
            return samples[min(srcIdxInt, samples.count - 1)]
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Listen2Tests/CTCForcedAlignerTests 2>&1 | tail -30
```
Expected: All tests pass

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCForcedAligner.swift
git add Listen2/Listen2/Listen2/Listen2Tests/Services/TTS/CTCForcedAlignerTests.swift
git commit -m "feat: implement full CTC forced alignment pipeline"
```

---

## Task 8: Integrate with TTSService

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Add CTCForcedAligner property**

Find alignment service declarations (~line 95) and add:

```swift
// Add after existing alignment properties:
private let ctcAligner = CTCForcedAligner()
private var useCtcAlignment = true  // Feature flag for rollback
```

**Step 2: Initialize aligner**

Find initialization code and add:

```swift
// In init or setupTTSProvider():
Task {
    do {
        try await ctcAligner.initialize()
        print("[TTSService] CTC Forced Aligner initialized successfully")
    } catch {
        print("[TTSService] CTC Aligner init failed: \(error)")
        print("[TTSService] Falling back to phoneme alignment")
        useCtcAlignment = false
    }
}
```

**Step 3: Update alignment call**

Find where alignment is performed (search for `alignmentService.align` or similar) and update:

```swift
// Replace or augment existing alignment call:
private func performAlignment(for text: String, audioData: Data, paragraphIndex: Int) async throws -> AlignmentResult {
    if useCtcAlignment {
        // Extract samples from audio data
        let samples = try extractSamples(from: audioData)
        return try await ctcAligner.align(
            audioSamples: samples,
            sampleRate: 22050,  // Piper output sample rate
            transcript: text,
            paragraphIndex: paragraphIndex
        )
    } else {
        // Fallback to existing alignment
        return try await alignmentService.align(
            phonemes: [],  // existing parameters
            text: text,
            paragraphIndex: paragraphIndex
        )
    }
}

/// Extract Float samples from audio Data
private func extractSamples(from audioData: Data) throws -> [Float] {
    // Assuming 16-bit PCM audio
    let int16Samples = audioData.withUnsafeBytes { buffer in
        Array(buffer.bindMemory(to: Int16.self))
    }
    return int16Samples.map { Float($0) / Float(Int16.max) }
}
```

**Step 4: Build to verify**

Run:
```bash
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/TTSService.swift
git commit -m "feat: integrate CTCForcedAligner with TTSService"
```

---

## Task 9: Remove Legacy Phoneme Duration Code

**Files:**
- Delete: `Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Delete: `Listen2/Listen2/Listen2/Listen2/Services/TTS/TextNormalizationMapper.swift`
- Delete: `Listen2/Listen2/Listen2/Listen2/Services/TTS/DynamicAlignmentEngine.swift`
- Modify: Various files to remove references

**Step 1: Remove files**

```bash
git rm Listen2/Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift
git rm Listen2/Listen2/Listen2/Listen2/Services/TTS/TextNormalizationMapper.swift
git rm Listen2/Listen2/Listen2/Listen2/Services/TTS/DynamicAlignmentEngine.swift
```

**Step 2: Find and fix references**

```bash
grep -r "PhonemeAlignmentService\|TextNormalizationMapper\|DynamicAlignmentEngine" Listen2/Listen2/Listen2/Listen2/ --include="*.swift" | grep -v ".swift-"
```

Update each file to remove imports and usage.

**Step 3: Update TTSService to remove fallback**

```swift
// Remove or comment out:
// private let alignmentService = PhonemeAlignmentService()
// private var useCtcAlignment = true  // No longer needed

// Update performAlignment to only use CTC:
private func performAlignment(...) async throws -> AlignmentResult {
    let samples = try extractSamples(from: audioData)
    return try await ctcAligner.align(...)
}
```

**Step 4: Build to verify**

```bash
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove legacy phoneme duration alignment code"
```

---

## Task 10: Remove ASR Alignment Code

**Files:**
- Delete: `Listen2/Listen2/Listen2/Listen2/Services/TTS/WordAlignmentService.swift`
- Delete: `Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/nemo-ctc-conformer-small/`
- Delete: `Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/whisper-tiny/`

**Step 1: Remove WordAlignmentService**

```bash
git rm Listen2/Listen2/Listen2/Listen2/Services/TTS/WordAlignmentService.swift
```

**Step 2: Remove ASR model directories**

```bash
git rm -r Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/nemo-ctc-conformer-small/
git rm -r Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/whisper-tiny/
```

**Step 3: Remove ASRModels directory if empty**

```bash
rmdir Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/ 2>/dev/null || true
git rm -r Listen2/Listen2/Listen2/Listen2/Resources/ASRModels/ 2>/dev/null || true
```

**Step 4: Find and fix references**

```bash
grep -r "WordAlignmentService\|nemo-ctc\|whisper-tiny" Listen2/Listen2/Listen2/Listen2/ --include="*.swift"
```

**Step 5: Build to verify**

```bash
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove ASR-based word alignment code and models

This removes ~44MB of model files and simplifies the alignment architecture.
CTC forced alignment with known transcript is more accurate and doesn't need ASR."
```

---

## Task 11: Update Tests and Manual Validation

**Files:**
- Update/delete test files referencing removed services

**Step 1: Find affected tests**

```bash
grep -r "PhonemeAlignmentService\|WordAlignmentService\|TextNormalizationMapper\|DynamicAlignmentEngine" Listen2/Listen2/Listen2/Listen2Tests/ --include="*.swift" -l
```

**Step 2: Update or remove each affected test file**

For each file found:
- If test is for removed service: delete the file
- If test references removed service: update to use new API

**Step 3: Run full test suite**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "(Test Case|passed|failed|error:)"
```

**Step 4: Manual validation checklist**

Test the following scenarios:
- [ ] Basic playback with word highlighting
- [ ] Apostrophes: "don't", "author's", "it's"
- [ ] Numbers: "Chapter 2", "1984", "42"
- [ ] Abbreviations: "Dr.", "Mr.", "etc."
- [ ] Long sentences (10+ words)
- [ ] Multiple sentences in sequence
- [ ] Skip forward/backward during playback

**Step 5: Document results**

```bash
workshop decision "Implemented CTC forced alignment for word highlighting" -r "Replaced phoneme duration (drifty) and ASR+DTW (error-prone) approaches with true CTC forced alignment using MMS_FA model. Uses known transcript for frame-accurate alignment. Removed ~44MB of ASR models and simplified architecture significantly."
```

**Step 6: Final commit**

```bash
git add -A
git commit -m "test: update tests for CTC forced alignment architecture"
```

---

## Summary

### Files Created
- `scripts/export_mms_fa_model.py`
- `Listen2/.../Services/TTS/CTCTokenizer.swift`
- `Listen2/.../Services/TTS/CTCForcedAligner.swift`
- `Listen2/.../Resources/Models/mms-fa/mms-fa.onnx`
- `Listen2/.../Resources/Models/mms-fa/labels.txt`
- `Listen2/.../Tests/Services/TTS/CTCTokenizerTests.swift`
- `Listen2/.../Tests/Services/TTS/CTCForcedAlignerTests.swift`

### Files Deleted
- `Listen2/.../Services/TTS/PhonemeAlignmentService.swift`
- `Listen2/.../Services/TTS/TextNormalizationMapper.swift`
- `Listen2/.../Services/TTS/DynamicAlignmentEngine.swift`
- `Listen2/.../Services/TTS/WordAlignmentService.swift`
- `Listen2/.../Resources/ASRModels/nemo-ctc-conformer-small/*`
- `Listen2/.../Resources/ASRModels/whisper-tiny/*`

### Files Modified
- `Listen2/.../Services/TTSService.swift`

### Success Criteria
- [ ] Word highlighting syncs within 50ms of audio
- [ ] Works with all Piper voices (no model re-export needed)
- [ ] Handles apostrophes, numbers, abbreviations correctly
- [ ] Zero drift over multi-sentence playback
- [ ] First sentence latency <300ms
- [ ] Build succeeds with no errors
- [ ] All tests pass
