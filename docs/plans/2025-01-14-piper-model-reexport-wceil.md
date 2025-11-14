# Piper Model Re-export with w_ceil - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Re-export three Piper TTS models (lessac-high, hfc_female-medium, hfc_male-medium) with w_ceil tensor as second ONNX output to enable real phoneme duration extraction.

**Architecture:** Fork Piper repository, modify VITS model's infer() method to return w_ceil alongside audio, update ONNX export script to include w_ceil as second output tensor, download model checkpoints from HuggingFace, re-export all three models, replace in Listen2 app.

**Tech Stack:** Python, PyTorch, ONNX, Piper TTS, HuggingFace datasets

**Note:** This work is **completely independent** from espeak normalization and can proceed in parallel.

---

## Task 1: Fork and Setup Piper Repository

**Goal:** Get Piper training/export environment set up

**Files:**
- Clone: `~/projects/piper`
- Create branch: `feature/export-wceil-tensor`

**Step 1: Fork Piper repository**

```bash
cd ~/projects
gh repo fork rhasspy/piper --clone
cd piper
git checkout -b feature/export-wceil-tensor
```

**Step 2: Install Piper training dependencies**

```bash
cd ~/projects/piper
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -e .
pip install torch onnx onnxruntime
```

Expected: Dependencies install successfully

**Step 3: Verify export script exists**

```bash
ls -la src/python/piper_train/export_onnx.py
```

Expected: File exists

**Step 4: Commit initial setup**

```bash
git add .gitignore
git commit -m "chore: set up Piper fork for w_ceil export modifications"
```

---

## Task 2: Modify VITS Model to Return w_ceil

**Goal:** Update the VITS infer() method to return both audio and w_ceil tensor

**Files:**
- Modify: `~/projects/piper/src/python/piper_train/vits/models.py` (around line 703)

**Step 1: Locate the infer() method**

```bash
cd ~/projects/piper
grep -n "def infer" src/python/piper_train/vits/models.py
```

Expected: Shows line number where `def infer(` is defined (around line 500-600)

**Step 2: Find w_ceil computation**

```bash
grep -n "w_ceil = torch.ceil" src/python/piper_train/vits/models.py
```

Expected: Shows line ~703 where `w_ceil = torch.ceil(w)`

**Step 3: Read current infer() implementation**

```bash
sed -n '500,800p' src/python/piper_train/vits/models.py | grep -A 50 "def infer"
```

Expected: See the current infer() method that returns only audio

**Step 4: Modify infer() to return w_ceil**

Currently the method returns:
```python
def infer(self, x, x_lengths, ...):
    # ... existing code ...
    w_ceil = torch.ceil(w)
    y_lengths = torch.clamp_min(torch.sum(w_ceil, [1, 2]), 1).long()
    # ... generate audio ...
    y = y[:, :, :y_lengths.max()]
    return y  # Only returns audio
```

Change the return statement to:
```python
def infer(self, x, x_lengths, ...):
    # ... existing code ...
    w_ceil = torch.ceil(w)
    y_lengths = torch.clamp_min(torch.sum(w_ceil, [1, 2]), 1).long()
    # ... generate audio ...
    y = y[:, :, :y_lengths.max()]
    return y, w_ceil  # NEW: Return both audio and durations
```

Edit the file:
```bash
# Find the exact line number of the return statement
grep -n "return y" src/python/piper_train/vits/models.py | tail -5
```

Then manually edit to change `return y` to `return y, w_ceil` in the infer() method.

**Step 5: Verify the change**

```bash
git diff src/python/piper_train/vits/models.py
```

Expected: Shows the modified return statement

**Step 6: Commit the change**

```bash
git add src/python/piper_train/vits/models.py
git commit -m "feat: modify VITS infer() to return w_ceil tensor alongside audio"
```

---

## Task 3: Update ONNX Export to Include w_ceil

**Goal:** Modify export_onnx.py to export w_ceil as second ONNX output

**Files:**
- Modify: `~/projects/piper/src/python/piper_train/export_onnx.py`

**Step 1: Locate the infer_forward wrapper**

```bash
grep -n "def infer_forward" src/python/piper_train/export_onnx.py
```

Expected: Shows line number of infer_forward function

**Step 2: Read current export implementation**

```bash
sed -n '1,100p' src/python/piper_train/export_onnx.py
```

Expected: See how model_g.infer() is currently called

**Step 3: Modify infer_forward to capture w_ceil**

Currently:
```python
def infer_forward(text, text_lengths, scales, sid=None):
    noise_scale = scales[0]
    length_scale = scales[1]
    noise_scale_w = scales[2]

    audio = model_g.infer(
        text,
        text_lengths,
        noise_scale=noise_scale,
        length_scale=length_scale,
        noise_scale_w=noise_scale_w,
        sid=sid,
    )[0].unsqueeze(1)

    return audio
```

Change to:
```python
def infer_forward(text, text_lengths, scales, sid=None):
    noise_scale = scales[0]
    length_scale = scales[1]
    noise_scale_w = scales[2]

    # NEW: Capture both audio and w_ceil
    result = model_g.infer(
        text,
        text_lengths,
        noise_scale=noise_scale,
        length_scale=length_scale,
        noise_scale_w=noise_scale_w,
        sid=sid,
    )

    audio = result[0].unsqueeze(1)
    w_ceil = result[1]  # NEW: Second return value is w_ceil

    return audio, w_ceil  # NEW: Return both
```

**Step 4: Update torch.onnx.export() call**

Find the export call (around line 60-80):
```bash
grep -n "torch.onnx.export" src/python/piper_train/export_onnx.py
```

Currently:
```python
torch.onnx.export(
    model=model,
    args=dummy_input,
    f=str(output_path),
    verbose=False,
    opset_version=15,
    input_names=["input", "input_lengths", "scales", "sid"],
    output_names=["output"],  # Only audio
    dynamic_axes={
        "input": {0: "batch_size", 1: "phonemes"},
        "input_lengths": {0: "batch_size"},
        "scales": {0: "batch_size"},
        "sid": {0: "batch_size"},
        "output": {0: "batch_size", 1: "time"},
    },
)
```

Change to:
```python
torch.onnx.export(
    model=model,
    args=dummy_input,
    f=str(output_path),
    verbose=False,
    opset_version=15,
    input_names=["input", "input_lengths", "scales", "sid"],
    output_names=["output", "w_ceil"],  # NEW: Both audio and w_ceil
    dynamic_axes={
        "input": {0: "batch_size", 1: "phonemes"},
        "input_lengths": {0: "batch_size"},
        "scales": {0: "batch_size"},
        "sid": {0: "batch_size"},
        "output": {0: "batch_size", 1: "time"},
        "w_ceil": {0: "batch_size", 1: "phonemes"},  # NEW: w_ceil dynamic axes
    },
)
```

**Step 5: Verify changes**

```bash
git diff src/python/piper_train/export_onnx.py
```

Expected: Shows both infer_forward and torch.onnx.export modifications

**Step 6: Commit changes**

```bash
git add src/python/piper_train/export_onnx.py
git commit -m "feat: export w_ceil tensor as second ONNX output"
```

---

## Task 4: Download Model Checkpoints from HuggingFace

**Goal:** Download the 3 model checkpoints needed for re-export

**Files:**
- Download to: `~/projects/piper/checkpoints/`

**Step 1: Create checkpoints directory**

```bash
cd ~/projects/piper
mkdir -p checkpoints/{lessac-high,hfc_female-medium,hfc_male-medium}
```

**Step 2: Install HuggingFace CLI**

```bash
pip install huggingface-hub[cli]
```

**Step 3: Download lessac-high checkpoint**

```bash
huggingface-cli download \
    rhasspy/piper-checkpoints \
    --repo-type dataset \
    --include "en/en_US/lessac/high/*" \
    --local-dir checkpoints/lessac-high
```

Expected: Downloads epoch=2218-step=838782.ckpt (998 MB), config.json, MODEL_CARD

**Step 4: Download hfc_female-medium checkpoint**

```bash
huggingface-cli download \
    rhasspy/piper-checkpoints \
    --repo-type dataset \
    --include "en/en_US/hfc_female/medium/*" \
    --local-dir checkpoints/hfc_female-medium
```

Expected: Downloads epoch=2868-step=1575188.ckpt (846 MB), config.json, MODEL_CARD

**Step 5: Download hfc_male-medium checkpoint**

```bash
huggingface-cli download \
    rhasspy/piper-checkpoints \
    --repo-type dataset \
    --include "en/en_US/hfc_male/medium/*" \
    --local-dir checkpoints/hfc_male-medium
```

Expected: Downloads checkpoint (~850 MB), config.json, MODEL_CARD

**Step 6: Verify downloads**

```bash
ls -lh checkpoints/*/en/en_US/*/*/*ckpt
```

Expected: Shows 3 checkpoint files totaling ~2.6 GB

**Step 7: Document download locations**

Create: `checkpoints/README.md`

```markdown
# Piper Model Checkpoints

Downloaded from HuggingFace rhasspy/piper-checkpoints dataset.

## Checkpoints:

1. **en_US-lessac-high**
   - Path: `lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt`
   - Size: 998 MB
   - Quality: high
   - Training: from scratch

2. **en_US-hfc_female-medium**
   - Path: `hfc_female-medium/en/en_US/hfc_female/medium/epoch=2868-step=1575188.ckpt`
   - Size: 846 MB
   - Quality: medium
   - Training: finetuned from lessac

3. **en_US-hfc_male-medium**
   - Path: `hfc_male-medium/en/en_US/hfc_male/medium/epoch=XXXX-step=XXXXX.ckpt`
   - Size: ~850 MB
   - Quality: medium
   - Training: finetuned from lessac

## Re-export Command:

```bash
python3 -m piper_train.export_onnx \
    --checkpoint <path-to-ckpt> \
    --output models/<voice-name>.onnx
```
```

**Step 8: Commit documentation**

```bash
git add checkpoints/README.md
git commit -m "docs: document downloaded model checkpoints"
```

---

## Task 5: Test Export with lessac-high Model

**Goal:** Verify the modified export works and produces w_ceil tensor

**Files:**
- Input: `checkpoints/lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt`
- Output: `~/projects/piper/models/en_US-lessac-high.onnx`

**Step 1: Create models output directory**

```bash
cd ~/projects/piper
mkdir -p models
```

**Step 2: Run export command**

```bash
source venv/bin/activate
python3 -m piper_train.export_onnx \
    --checkpoint checkpoints/lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt \
    --output models/en_US-lessac-high.onnx
```

Expected: Export completes without errors, creates .onnx file

**Step 3: Verify ONNX model has w_ceil output**

Create test script: `test_wceil_output.py`

```python
import onnx

model_path = "models/en_US-lessac-high.onnx"
model = onnx.load(model_path)

print(f"Model outputs:")
for output in model.graph.output:
    print(f"  - {output.name}: {output.type}")

# Verify we have 2 outputs
assert len(model.graph.output) == 2, f"Expected 2 outputs, got {len(model.graph.output)}"

output_names = [o.name for o in model.graph.output]
assert "output" in output_names, "Missing 'output' (audio) tensor"
assert "w_ceil" in output_names, "Missing 'w_ceil' (durations) tensor"

print("\n✅ Model has both 'output' and 'w_ceil' tensors!")
```

**Step 4: Run verification**

```bash
python test_wceil_output.py
```

Expected:
```
Model outputs:
  - output: ...
  - w_ceil: ...

✅ Model has both 'output' and 'w_ceil' tensors!
```

**Step 5: Test with ONNX Runtime**

Create: `test_wceil_inference.py`

```python
import onnxruntime as ort
import numpy as np

session = ort.InferenceSession("models/en_US-lessac-high.onnx")

# Print output names
print("Output names:")
for output in session.get_outputs():
    print(f"  - {output.name}: shape={output.shape}, dtype={output.type}")

# Create dummy inputs (small test)
dummy_phonemes = np.array([[1, 2, 3, 4, 5]], dtype=np.int64)
dummy_lengths = np.array([5], dtype=np.int64)
dummy_scales = np.array([[0.667, 1.0, 0.8]], dtype=np.float32)
dummy_sid = np.array([0], dtype=np.int64)

# Run inference
outputs = session.run(None, {
    "input": dummy_phonemes,
    "input_lengths": dummy_lengths,
    "scales": dummy_scales,
    "sid": dummy_sid
})

print(f"\nInference outputs:")
print(f"  audio shape: {outputs[0].shape}")
print(f"  w_ceil shape: {outputs[1].shape}")
print(f"  w_ceil values (first 10): {outputs[1].flatten()[:10]}")

assert outputs[0].shape[0] == 1, "Audio batch size should be 1"
assert outputs[1].shape[0] == 1, "w_ceil batch size should be 1"
assert outputs[1].shape[1] == 5, f"w_ceil should have 5 phoneme durations, got {outputs[1].shape[1]}"

print("\n✅ ONNX inference with w_ceil works!")
```

**Step 6: Run inference test**

```bash
python test_wceil_inference.py
```

Expected: Shows w_ceil tensor with actual duration values (non-zero)

**Step 7: Commit test model and scripts**

```bash
git add models/en_US-lessac-high.onnx test_wceil_output.py test_wceil_inference.py
git commit -m "test: verify lessac-high export includes w_ceil tensor"
```

---

## Task 6: Export Remaining Models

**Goal:** Re-export hfc_female and hfc_male with w_ceil

**Files:**
- Output: `models/en_US-hfc_female-medium.onnx`
- Output: `models/en_US-hfc_male-medium.onnx`

**Step 1: Export hfc_female-medium**

```bash
python3 -m piper_train.export_onnx \
    --checkpoint checkpoints/hfc_female-medium/en/en_US/hfc_female/medium/epoch=2868-step=1575188.ckpt \
    --output models/en_US-hfc_female-medium.onnx
```

Expected: Creates en_US-hfc_female-medium.onnx

**Step 2: Verify hfc_female has w_ceil**

```bash
python test_wceil_output.py models/en_US-hfc_female-medium.onnx
```

Expected: ✅ Model has both 'output' and 'w_ceil' tensors!

**Step 3: Export hfc_male-medium**

```bash
python3 -m piper_train.export_onnx \
    --checkpoint checkpoints/hfc_male-medium/en/en_US/hfc_male/medium/epoch=XXXX-step=XXXXX.ckpt \
    --output models/en_US-hfc_male-medium.onnx
```

Expected: Creates en_US-hfc_male-medium.onnx

**Step 4: Verify hfc_male has w_ceil**

```bash
python test_wceil_output.py models/en_US-hfc_male-medium.onnx
```

Expected: ✅ Model has both 'output' and 'w_ceil' tensors!

**Step 5: List all exported models**

```bash
ls -lh models/*.onnx
```

Expected: Shows 3 ONNX files with w_ceil support

**Step 6: Commit all models**

```bash
git add models/
git commit -m "feat: export all three voices with w_ceil tensor support"
```

---

## Task 7: Test w_ceil Extraction in sherpa-onnx

**Goal:** Verify that sherpa-onnx correctly extracts w_ceil from the new models

**Files:**
- Test in: `~/projects/sherpa-onnx`
- Models from: `~/projects/piper/models/`

**Step 1: Copy a test model to sherpa-onnx test directory**

```bash
cp ~/projects/piper/models/en_US-lessac-high.onnx ~/projects/sherpa-onnx/test-model.onnx
```

**Step 2: Create C++ test program**

Create: `~/projects/sherpa-onnx/test-wceil-extraction.cpp`

```cpp
#include "sherpa-onnx/c-api/c-api.h"
#include <stdio.h>
#include <stdlib.h>

int main() {
    // Configure TTS
    SherpaOnnxOfflineTtsVitsModelConfig vits_config;
    memset(&vits_config, 0, sizeof(vits_config));
    vits_config.model = "test-model.onnx";
    vits_config.tokens = "path/to/tokens.txt";  // Adjust path
    vits_config.data_dir = "path/to/espeak-ng-data";  // Adjust path

    SherpaOnnxOfflineTtsModelConfig model_config;
    memset(&model_config, 0, sizeof(model_config));
    model_config.vits = vits_config;

    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));
    tts_config.model = model_config;

    // Create TTS
    SherpaOnnxOfflineTts* tts = SherpaOnnxCreateOfflineTts(&tts_config);
    if (!tts) {
        fprintf(stderr, "Failed to create TTS\n");
        return 1;
    }

    // Generate audio with text
    const char* text = "Hello world";
    SherpaOnnxGeneratedAudio* audio = SherpaOnnxOfflineTtsGenerate(tts, text, 0, 1.0);

    // Check phoneme durations
    printf("Generated %d samples at %d Hz\n", audio->n, audio->sample_rate);
    printf("Phoneme count: %d\n", audio->num_phonemes);

    if (audio->num_phonemes > 0) {
        printf("✅ SUCCESS: w_ceil extracted! First 5 phoneme durations:\n");
        for (int i = 0; i < 5 && i < audio->num_phonemes; i++) {
            printf("  Phoneme %d: duration=%d samples\n", i, audio->phonemes[i].duration);
        }
    } else {
        printf("❌ FAIL: No phoneme durations extracted\n");
        return 1;
    }

    // Cleanup
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    SherpaOnnxDestroyOfflineTts(tts);

    return 0;
}
```

**Step 3: Compile test**

```bash
cd ~/projects/sherpa-onnx
mkdir -p build && cd build
cmake ..
make

# Compile test program
g++ -o test-wceil ../test-wceil-extraction.cpp \
    -I../sherpa-onnx/c-api \
    -L. -lsherpa-onnx \
    -Wl,-rpath,.
```

**Step 4: Run test**

```bash
./test-wceil
```

Expected output:
```
Generated 44100 samples at 22050 Hz
Phoneme count: 15
✅ SUCCESS: w_ceil extracted! First 5 phoneme durations:
  Phoneme 0: duration=1280 samples
  Phoneme 1: duration=1536 samples
  Phoneme 2: duration=768 samples
  ...
```

**Step 5: Document test results**

Create: `~/projects/sherpa-onnx/WCEIL_VERIFICATION.md`

```markdown
# w_ceil Tensor Extraction Verification

## Test Date: 2025-01-14

## Models Tested:
- en_US-lessac-high.onnx ✅
- en_US-hfc_female-medium.onnx (pending)
- en_US-hfc_male-medium.onnx (pending)

## Verification Results:

### lessac-high
- **Model outputs**: `output` (audio) + `w_ceil` (durations) ✅
- **sherpa-onnx extraction**: Successfully extracts phoneme durations ✅
- **Sample durations**: Non-zero values observed ✅
- **Duration calculation**: Values × 256 = sample counts ✅

## Conclusion:
The modified Piper export successfully produces w_ceil tensor, and sherpa-onnx correctly extracts phoneme durations from the ONNX model.

**Next step**: Replace models in Listen2 app and verify end-to-end.
```

**Step 6: Commit verification**

```bash
cd ~/projects/sherpa-onnx
git add test-wceil-extraction.cpp WCEIL_VERIFICATION.md
git commit -m "test: verify w_ceil extraction from re-exported Piper models"
```

---

## Task 8: Update Listen2 App with New Models

**Goal:** Replace old ONNX models in Listen2 with w_ceil-enabled versions

**Files:**
- Replace: `~/projects/Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx`
- Add: `~/projects/Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_female-medium.onnx`
- Add: `~/projects/Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_male-medium.onnx`

**Step 1: Backup old models**

```bash
cd ~/projects/Listen2/Listen2/Listen2/Resources/PiperModels
mkdir -p .backup
cp *.onnx .backup/
```

**Step 2: Copy new lessac-high model**

```bash
cp ~/projects/piper/models/en_US-lessac-high.onnx .
```

**Step 3: Add hfc_female and hfc_male models**

```bash
cp ~/projects/piper/models/en_US-hfc_female-medium.onnx .
cp ~/projects/piper/models/en_US-hfc_male-medium.onnx .
```

**Step 4: Copy corresponding config files**

You'll need the .onnx.json config files. Download from HuggingFace piper-voices:

```bash
# lessac-high config
curl -o en_US-lessac-high.onnx.json \
    https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/high/en_US-lessac-high.onnx.json

# hfc_female config
curl -o en_US-hfc_female-medium.onnx.json \
    https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_female/medium/en_US-hfc_female-medium.onnx.json

# hfc_male config
curl -o en_US-hfc_male-medium.onnx.json \
    https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_male/medium/en_US-hfc_male-medium.onnx.json
```

**Step 5: Update VoiceManager to include new voices**

Modify: `~/projects/Listen2/Listen2/Listen2/Services/VoiceManager.swift`

Add new voice IDs:

```swift
enum VoiceID: String, CaseIterable {
    case lessacHigh = "en_US-lessac-high"
    case hfcFemale = "en_US-hfc_female-medium"  // NEW
    case hfcMale = "en_US-hfc_male-medium"      // NEW

    var displayName: String {
        switch self {
        case .lessacHigh: return "Lessac (High Quality)"
        case .hfcFemale: return "HFC Female"  // NEW
        case .hfcMale: return "HFC Male"      // NEW
        }
    }
}
```

**Step 6: Verify Xcode sees the new models**

```bash
cd ~/projects/Listen2/Listen2
open Listen2.xcodeproj
```

In Xcode:
1. Navigate to Resources/PiperModels folder
2. Verify all 6 files appear (.onnx and .onnx.json for each voice)
3. Check "Target Membership" is set to Listen2

**Step 7: Build and test**

```bash
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

Expected: BUILD SUCCEEDED

**Step 8: Commit model updates**

```bash
cd ~/projects/Listen2
git add Listen2/Resources/PiperModels/*.onnx Listen2/Resources/PiperModels/*.onnx.json Listen2/Services/VoiceManager.swift
git commit -m "feat: update Piper models with w_ceil tensor support

- Replace lessac-high with w_ceil-enabled version
- Add hfc_female-medium voice with w_ceil
- Add hfc_male-medium voice with w_ceil
- Update VoiceManager to expose new voices"
```

---

## Task 9: End-to-End Testing with Real Durations

**Goal:** Verify that real phoneme durations from w_ceil improve word highlighting accuracy

**Files:**
- Test: `~/projects/Listen2/Listen2Tests/Services/TTS/PhonemeDurationTests.swift`

**Step 1: Write test to verify w_ceil extraction**

Create: `Listen2Tests/Services/TTS/PhonemeDurationTests.swift`

```swift
import XCTest
@testable import Listen2

class PhonemeDurationTests: XCTestCase {

    func testWCeilExtraction() async throws {
        // Initialize TTS with lessac-high (w_ceil enabled)
        let provider = PiperTTSProvider(voiceID: "en_US-lessac-high")
        try await provider.initialize()

        // Synthesize test text
        let result = try await provider.synthesize("Hello world", speed: 1.0)

        // Verify we got phonemes
        XCTAssertGreaterThan(result.phonemes.count, 0, "Should have phonemes")

        // Verify phonemes have REAL durations (not 0)
        let hasDurations = result.phonemes.contains { $0.duration > 0 }
        XCTAssertTrue(hasDurations, "Phonemes should have real durations from w_ceil")

        // Log durations for inspection
        print("[PhonemeDurationTests] Phoneme durations:")
        for (i, phoneme) in result.phonemes.prefix(10).enumerated() {
            print("  [\(i)] '\(phoneme.symbol)' duration=\(phoneme.duration)s")
        }

        // Verify durations are reasonable (not 50ms estimates)
        let avgDuration = result.phonemes.map { $0.duration }.reduce(0, +) / Double(result.phonemes.count)
        print("[PhonemeDurationTests] Average phoneme duration: \(avgDuration)s")

        // Real durations should vary (not all 0.05s)
        let uniqueDurations = Set(result.phonemes.map { $0.duration })
        XCTAssertGreaterThan(uniqueDurations.count, 3, "Should have varied durations, not uniform 50ms")
    }

    func testCompareEstimatedVsRealDurations() async throws {
        // This test compares old behavior (50ms estimates) vs new (w_ceil)
        let provider = PiperTTSProvider(voiceID: "en_US-lessac-high")
        try await provider.initialize()

        let text = "The quick brown fox jumps over the lazy dog"
        let result = try await provider.synthesize(text, speed: 1.0)

        // Calculate what ESTIMATED duration would be (50ms per phoneme)
        let estimatedTotal = Double(result.phonemes.count) * 0.05

        // Calculate ACTUAL duration from w_ceil
        let actualTotal = result.phonemes.reduce(0.0) { $0 + $1.duration }

        print("[Compare] Text: '\(text)'")
        print("[Compare] Phoneme count: \(result.phonemes.count)")
        print("[Compare] Estimated total (50ms/phoneme): \(estimatedTotal)s")
        print("[Compare] Actual total (w_ceil): \(actualTotal)s")
        print("[Compare] Difference: \(abs(estimatedTotal - actualTotal))s")

        // Real durations should differ from 50ms estimates by at least 10%
        let percentDiff = abs(estimatedTotal - actualTotal) / estimatedTotal * 100
        XCTAssertGreaterThan(percentDiff, 10, "Real durations should differ significantly from 50ms estimates")
    }
}
```

**Step 2: Run tests**

```bash
cd ~/projects/Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:Listen2Tests/PhonemeDurationTests
```

Expected: Both tests pass, logs show real varied durations

**Step 3: Test with PhonemeAlignmentService**

Create: `Listen2Tests/Services/PhonemeAlignmentDurationTests.swift`

```swift
import XCTest
@testable import Listen2

class PhonemeAlignmentDurationTests: XCTestCase {

    func testAlignmentWithRealDurations() async throws {
        let alignmentService = PhonemeAlignmentService()
        let provider = PiperTTSProvider(voiceID: "en_US-lessac-high")
        try await provider.initialize()

        // Synthesize and get phonemes with REAL durations
        let text = "Dr. Smith's office"
        let synthesis = try await provider.synthesize(text, speed: 1.0)

        // Verify phonemes have real durations
        XCTAssertTrue(synthesis.phonemes.allSatisfy { $0.duration > 0 })

        // Create alignment (no wordMap for this test)
        let result = try await alignmentService.align(
            phonemes: synthesis.phonemes,
            text: text,
            wordMap: nil,
            paragraphIndex: 0
        )

        // Verify alignment used REAL durations
        let totalDuration = result.totalDuration
        let estimatedDuration = Double(synthesis.phonemes.count) * 0.05

        print("[Alignment] Real duration: \(totalDuration)s")
        print("[Alignment] Estimated (50ms): \(estimatedDuration)s")

        // Real durations should produce different total
        XCTAssertNotEqual(totalDuration, estimatedDuration, accuracy: 0.1)

        // Word timings should exist
        XCTAssertGreaterThan(result.wordTimings.count, 0)

        // Each word should have reasonable duration
        for timing in result.wordTimings {
            XCTAssertGreaterThan(timing.duration, 0.01, "Word '\(timing.text)' has suspiciously short duration")
            XCTAssertLessThan(timing.duration, 2.0, "Word '\(timing.text)' has suspiciously long duration")
        }
    }
}
```

**Step 4: Run alignment tests**

```bash
xcodebuild test -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:Listen2Tests/PhonemeAlignmentDurationTests
```

Expected: Test passes, shows real vs estimated duration differences

**Step 5: Commit tests**

```bash
git add Listen2Tests/Services/TTS/PhonemeDurationTests.swift Listen2Tests/Services/PhonemeAlignmentDurationTests.swift
git commit -m "test: verify w_ceil phoneme durations improve alignment accuracy"
```

---

## Task 10: Manual Device Testing

**Goal:** Test real phoneme durations on actual device with word highlighting

**Steps:**

**Step 1: Build and deploy to iPhone**

1. Connect iPhone 15 Pro Max via USB
2. Open Xcode → Select Listen2 scheme → Select device
3. Product → Run (⌘R)

**Step 2: Test with Welcome PDF**

Navigate to Welcome PDF, play paragraph 4:
- "Try importing your own documents to experience the full capabilities of Listen2!"

**Step 3: Observe word highlighting**

Expected improvements:
- **More accurate timing**: Words highlight closer to when they're actually spoken
- **Natural pacing**: Variable durations (not uniform 50ms) create more natural-feeling highlighting
- **Better sync**: No drift between audio and highlighting

**Step 4: Check console logs**

Xcode → Devices → Console, filter for "PhonemeAlign":

Look for:
```
[PiperTTS] Received 45 phonemes from sherpa-onnx
[PhonemeAlign] ✅ Using REAL phoneme durations (not estimates)
[PhonemeAlign] Total duration: 4.23s (was 2.25s with 50ms estimates)
```

**Step 5: Compare all three voices**

Test the same paragraph with:
1. lessac-high (bundled)
2. hfc_female-medium (new)
3. hfc_male-medium (new)

Note any differences in:
- Timing accuracy
- Voice quality
- Highlighting smoothness

**Step 6: Document results**

Create: `docs/manual-testing/wceil-verification.md`

```markdown
# w_ceil Phoneme Duration Verification

## Test Date: [Date]
## Device: iPhone 15 Pro Max
## iOS Version: [Version]

## Test Results:

### lessac-high
- ✅ Real durations extracted
- ✅ Highlighting matches speech accurately
- ✅ No noticeable drift
- Average phoneme duration: [X]s (vs 50ms estimate)

### hfc_female-medium
- ✅ Real durations extracted
- ✅ Highlighting matches speech accurately
- Voice quality: [Notes]

### hfc_male-medium
- ✅ Real durations extracted
- ✅ Highlighting matches speech accurately
- Voice quality: [Notes]

## Comparison: Before vs After

| Metric | Before (50ms estimates) | After (w_ceil) |
|--------|------------------------|----------------|
| Timing drift | Noticeable after 20s | Minimal |
| Highlighting accuracy | ±200ms | ±50ms |
| User experience | Good | Excellent |

## Conclusion:
Real phoneme durations from w_ceil significantly improve word highlighting accuracy and user experience.
```

---

## Task 11: Contribute Models Back to Community

**Goal:** Share w_ceil-enabled models with Piper community

**Step 1: Create pull request to Piper**

```bash
cd ~/projects/piper
git push origin feature/export-wceil-tensor

gh pr create \
    --repo rhasspy/piper \
    --base master \
    --head zachswift615:feature/export-wceil-tensor \
    --title "feat: export w_ceil tensor for phoneme duration extraction" \
    --body "This PR modifies the ONNX export to include the w_ceil tensor as a second output, enabling downstream applications to extract real phoneme durations for accurate word-level synchronization.

**Changes:**
- Modified \`vits/models.py\` to return w_ceil alongside audio
- Updated \`export_onnx.py\` to export w_ceil as second ONNX output
- Verified with lessac-high, hfc_female-medium, hfc_male-medium models

**Benefits:**
- Enables accurate word-level highlighting in TTS applications
- Provides real phoneme durations instead of estimates
- Maintains backward compatibility (models without w_ceil still work)

**Testing:**
- Verified ONNX models contain w_ceil tensor
- Tested inference with ONNX Runtime
- Integrated with sherpa-onnx for phoneme duration extraction"
```

**Step 2: Share models on HuggingFace**

Consider uploading re-exported models to a HuggingFace repository:

```bash
# Create HuggingFace repo
huggingface-cli repo create piper-wceil-models --type model

# Upload models
huggingface-cli upload \
    zachswift615/piper-wceil-models \
    models/en_US-lessac-high.onnx \
    models/en_US-hfc_female-medium.onnx \
    models/en_US-hfc_male-medium.onnx
```

**Step 3: Document in Workshop**

```bash
cd ~/projects/Listen2
workshop decision "Re-exported Piper models with w_ceil tensor for real phoneme durations" \
    -r "Modified Piper VITS export to include w_ceil as second ONNX output. Replaced all app voices with w_ceil-enabled versions. This eliminates 50ms duration estimates and provides accurate phoneme timing for word-level highlighting. Submitted PR to upstream Piper repository."
```

---

## Verification Checklist

Use @superpowers:verification-before-completion before claiming completion:

- [ ] Piper fork has w_ceil export modifications
- [ ] All 3 models re-exported with w_ceil tensor
- [ ] ONNX models verified to contain w_ceil output
- [ ] sherpa-onnx extracts w_ceil correctly
- [ ] Listen2 app updated with new models
- [ ] All 3 voices available in VoiceManager
- [ ] Unit tests verify real durations extracted
- [ ] PhonemeAlignmentService uses real durations
- [ ] Manual device testing shows improved accuracy
- [ ] PR submitted to Piper repository

## Timeline Estimate

- Task 1-3 (Piper modifications): 1 day
- Task 4 (Download checkpoints): 2 hours
- Task 5-6 (Model export): 1 day
- Task 7-8 (Integration): 1 day
- Task 9-10 (Testing): 2 days
- Task 11 (Contribution): 1 day

**Total: ~1 week** for complete implementation and testing

---

## Success Criteria

✅ **Technical:**
- ONNX models export with both `output` and `w_ceil` tensors
- sherpa-onnx extracts phoneme durations correctly
- PhonemeAlignmentService shows duration variance (not uniform 50ms)

✅ **User Experience:**
- Word highlighting matches speech more accurately
- No noticeable timing drift over long paragraphs
- All three voices work with real durations

✅ **Community:**
- Upstream PR submitted to Piper
- Modifications documented
- Models potentially shared on HuggingFace

---

## Notes

- This work is **independent** of espeak normalization (can run in parallel)
- w_ceil solves **timing accuracy** (not text normalization)
- Both w_ceil + normalized text are needed for complete solution
- Checkpoint downloads are large (~2.6 GB total)
