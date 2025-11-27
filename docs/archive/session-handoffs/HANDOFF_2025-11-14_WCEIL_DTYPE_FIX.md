# Session Handoff: w_ceil Data Type Fix - TTS Stack Debugging

**Date:** November 14, 2025
**Status:** 🟡 MAJOR PROGRESS - w_ceil extraction fixed, UX issues remain
**Next Session:** Focus on synthesis performance and word highlighting accuracy

---

## 🎯 What We Accomplished This Session

### Fixed: w_ceil Tensor Corruption (ROOT CAUSE FOUND!)

**Problem:** Phoneme durations were showing garbage values (-2,147,483,648 or 1,073,741,824 samples = 13 hours!)

**Root Causes Identified and Fixed:**

1. **Tensor Shape Mismatch** ✅
   - Issue: w_ceil was 3D `[batch, 1, phonemes]` but sherpa-onnx expected 1D `[phonemes]`
   - Fix: Added `.squeeze()` to remove batch and channel dimensions
   - File: `piper/src/python/piper_train/export_onnx.py:69`

2. **Data Type Mismatch** ✅ (THE SMOKING GUN)
   - Issue: w_ceil was `float32` but sherpa-onnx reads as `int64`
   - Impact: Reading float32 bytes as int64 produced garbage values
   - Fix: Added `.long()` to cast to int64 before export
   - File: `piper/src/python/piper_train/export_onnx.py:69`
   - Commit: `0dad73a`

3. **Missing Metadata** ✅
   - Issue: Model lacked required sherpa-onnx metadata causing crash
   - Fix: Automatically add 7 required metadata fields from model hyperparameters
   - File: `piper/src/python/piper_train/export_onnx.py:106-126`
   - Commit: `748ad5b`

### Created: Export Automation Script ✅

**Script:** `Listen2/scripts/export-and-update-model.sh`

**Features:**
- One command to export checkpoint → copy to app
- Automatic verification of w_ceil shape (1D) and dtype (int64)
- Automatic verification of required metadata
- Clear success/failure messages

**Usage:**
```bash
./scripts/export-and-update-model.sh \
  ~/projects/piper/checkpoints/lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt \
  en_US-lessac-high
```

---

## 📊 Technical Details

### Data Flow (Now CORRECT)

```
Piper VITS Model
  ↓ infer() returns (audio, w_ceil)
w_ceil: torch.ceil(w)  [batch=1, channels=1, phonemes=94]
  ↓ .squeeze()         → [phonemes=94]
  ↓ .long()            → int64 dtype
ONNX Export
  ↓
sherpa-onnx C++ reads:
  int64_t num_phonemes = durations_shape[0];  // Now gets 94, not 1!
  const int64_t* data = GetTensorData<int64_t>();  // Now reads correct dtype!
  ↓ multiply by 256
  ↓ cast to int32
Swift receives:
  duration = TimeInterval(sampleCount) / TimeInterval(22050)
```

### Before vs After

| Metric | Before (Broken) | After (Fixed) |
|--------|-----------------|---------------|
| w_ceil shape | `[1, 1, 94]` (3D) | `[94]` (1D) ✅ |
| w_ceil dtype | `float32` | `int64` ✅ |
| Metadata | 0 fields | 7 fields ✅ |
| First phoneme | -2147483648 samples | 2-5 samples ✅ |
| Total duration | 801,708s (222 hours!) | 4.8s ✅ |
| Sample counts | Garbage | 256-1280 samples ✅ |

### Verification

**Model outputs test:**
```python
import onnxruntime as ort
session = ort.InferenceSession("en_US-lessac-high.onnx")
outputs = session.run(...)

# Now returns:
w_ceil dtype: int64  ✅
w_ceil values: [2 1 2 1 2 3 1 1 5 5]  ✅
After ×256: [512 256 512 256 512 768 256 256 1280 1280]  ✅
Durations: [0.023s, 0.012s, 0.023s, ...]  ✅
```

---

## 🔴 Current Issues (To Address Next Session)

### Issue #0: CRITICAL - CPU Overload (476% CPU Usage!)

**Symptom:** App is using 476% CPU and 3.23 GB RAM, causing thermal throttling

**Evidence:** Xcode Activity Monitor screenshot shows:
- CPU: 476% (using ~4.76 cores simultaneously!)
- Memory: 3.23 GB
- This explains the multi-minute pauses and hangs

**Likely Causes:**
1. Multiple paragraphs synthesizing simultaneously (no queue throttling)
2. Synthesis running on too many threads
3. ONNX inference creating thread pool explosion
4. No CPU budget or rate limiting

**CRITICAL Next Steps:**
1. Check how many synthesis tasks run concurrently
2. Add queue with maxConcurrentOperationCount = 1
3. Profile thread count during synthesis
4. Check ONNX Runtime thread settings
5. Add CPU usage monitoring/logging

**This must be fixed FIRST** - nothing else matters if the phone is unusable.

### Issue #1: Synthesis Performance - Long Pauses

**Symptom:** Audio stops for minutes between paragraphs with no feedback

**User Experience:**
- No indication if paused, stopped, or synthesizing
- Can't tell if app is frozen or working
- Very frustrating UX

**Possible Causes:**
1. Synthesis is blocking the UI thread
2. Disk cache operations are slow
3. PhonemeAlignmentService computation is heavy
4. No progress indicator during synthesis

**Evidence Needed:**
- Profile synthesis time per paragraph
- Check if synthesis is on background queue
- Measure cache write time
- Add progress logging to identify bottleneck

**Next Steps:**
1. Add timestamps to all synthesis pipeline stages
2. Profile where the time is spent (synthesis vs alignment vs caching)
3. Add loading indicator in UI
4. Consider async/streaming synthesis

### Issue #2: Word Highlighting Accuracy ~50%

**Symptom:** Word highlighting is correct less than half the time

**Specific Issues:**
- Sometimes highlights wrong word
- Sometimes skips words
- Gets stuck on last word of paragraph

**Possible Causes:**
1. VoxPDF word positions don't match normalized text positions
2. Phoneme-to-word mapping logic is incorrect
3. Character mapping from espeak normalization is wrong
4. DTW alignment is inaccurate
5. Timing calculation (samples → seconds) has error

**Evidence Needed:**
- Log one failing paragraph with:
  - Original VoxPDF text and word positions
  - Normalized text from sherpa-onnx
  - Character mapping from espeak
  - Phoneme positions and durations
  - Final word timings
  - Which word SHOULD be highlighted vs which IS highlighted

**Next Steps:**
1. Add detailed logging to PhonemeAlignmentService
2. Create test case with one failing paragraph
3. Manually verify the mapping chain:
   - VoxPDF position → normalized position (via char_mapping)
   - Normalized position → phoneme range (via textRange)
   - Phoneme range → duration (via w_ceil)
4. Check if `mapToNormalized()` is working correctly
5. Verify DTW alignment logic

### Issue #3: Gets Stuck on Last Word

**Symptom:** Highlighting gets stuck on the last word of a paragraph

**Possible Causes:**
1. Last word duration is too long (estimate vs real)
2. Audio ends but highlight timing hasn't caught up
3. Off-by-one error in word boundary detection
4. CADisplayLink timing issue

**Evidence Needed:**
- Log for stuck paragraph:
  - Last word text and position
  - Last word calculated duration
  - Actual audio duration
  - Playback time when it gets stuck

**Next Steps:**
1. Add forced word completion when audio ends
2. Check if last word has accurate duration
3. Verify CADisplayLink receives final updates
4. Add timeout/completion logic

---

## 📁 Files Modified This Session

### Piper Export Script (~/projects/piper)
- `src/python/piper_train/export_onnx.py`
  - Line 69: Added `.squeeze().long()` for correct shape and dtype
  - Lines 106-126: Added automatic metadata generation
  - Commits: `b94571f`, `748ad5b`, `0dad73a`

### Listen2 Automation (~/projects/Listen2)
- `scripts/export-and-update-model.sh` (NEW)
  - Automated export + copy + verification
  - Commit: `8986815`

### Models Updated
- `en_US-lessac-high.onnx` (109 MB)
  - Now has correct w_ceil: 1D, int64, with metadata
  - Timestamp: Nov 14 23:29

---

## 🔧 Quick Debugging Commands

### Check w_ceil in Deployed Model

```bash
cd ~/projects/piper
source venv/bin/activate

python3 << 'EOF'
import onnxruntime as ort
import numpy as np

session = ort.InferenceSession(
    "/Users/zachswift/projects/Listen2/Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx"
)

dummy_phonemes = np.array([[1, 2, 3, 4, 5]], dtype=np.int64)
dummy_lengths = np.array([5], dtype=np.int64)
dummy_scales = np.array([0.667, 1.0, 0.8], dtype=np.float32)

outputs = session.run(None, {
    "input": dummy_phonemes,
    "input_lengths": dummy_lengths,
    "scales": dummy_scales,
})

print(f"w_ceil dtype: {outputs[1].dtype}")
print(f"w_ceil values: {outputs[1]}")
print(f"Sample counts: {outputs[1] * 256}")
EOF
```

**Expected output:**
```
w_ceil dtype: int64
w_ceil values: [2 1 2 1 2]
Sample counts: [512 256 512 256 512]
```

### Profile Synthesis Performance

Add timestamps in Swift code:

```swift
// In TTSService.swift or SynthesisQueue.swift
let start = Date()
// ... synthesis code ...
print("[PROFILE] Synthesis took: \(Date().timeIntervalSince(start))s")
```

### Grep Useful Log Patterns

```bash
LOG_FILE="/Users/zachswift/listen-2-logs-2025-11-13.txt"

# Check phoneme durations are correct
grep "First phoneme duration:" $LOG_FILE | head -10

# Check total paragraph durations
grep "Extracted.*phonemes.*total:" $LOG_FILE | tail -10

# Check synthesis failures
grep "synthesis failed\|Synthesis returned nil" $LOG_FILE

# Check stuck highlighting
grep "stuck on word\|forcing next word" $LOG_FILE

# Check cache operations
grep "Saved alignment to disk cache\|Loaded from cache" $LOG_FILE
```

---

## 🎯 Next Session Priorities

### Priority 1: Fix Synthesis Performance (UX Critical)

**Goal:** Eliminate multi-minute pauses between paragraphs

**Investigation Steps:**
1. Add comprehensive profiling timestamps:
   ```swift
   [PROFILE] Synthesis request started
   [PROFILE] ONNX inference: 0.5s
   [PROFILE] PhonemeAlignment: 0.2s
   [PROFILE] Cache write: 0.1s
   [PROFILE] Total: 0.8s
   ```

2. Identify bottleneck:
   - If ONNX inference: Check model size, consider quantization
   - If PhonemeAlignment: Optimize DTW or mapping logic
   - If Cache: Check disk I/O, consider in-memory cache

3. Add UI feedback:
   - Show loading indicator during synthesis
   - Display "Synthesizing paragraph X of Y"
   - Show progress bar if possible

4. Consider async improvements:
   - Pre-synthesize next paragraph while current is playing
   - Use background queue for synthesis
   - Stream audio chunks instead of waiting for full synthesis

### Priority 2: Debug Word Highlighting Accuracy

**Goal:** Understand why highlighting is wrong 50% of the time

**Investigation Steps:**
1. Add detailed logging for ONE failing paragraph:
   ```swift
   print("[DEBUG_ALIGN] === Paragraph Debug ===")
   print("[DEBUG_ALIGN] VoxPDF words:")
   for word in voxWords {
       print("  '\(word.text)' orig[\(word.range)]")
   }
   print("[DEBUG_ALIGN] Normalized text: '\(normalizedText)'")
   print("[DEBUG_ALIGN] Character mapping: \(charMapping)")
   print("[DEBUG_ALIGN] Phonemes:")
   for (i, phoneme) in phonemes.enumerated() {
       print("  [\(i)] '\(phoneme.symbol)' range[\(phoneme.textRange)] duration=\(phoneme.duration)s")
   }
   print("[DEBUG_ALIGN] Word timings:")
   for timing in wordTimings {
       print("  '\(timing.text)' start=\(timing.startTime)s duration=\(timing.duration)s")
   }
   ```

2. Manually trace the mapping:
   - Pick a failing word (e.g., "Dr." that becomes "Doctor")
   - Verify VoxPDF position (e.g., [0..<3])
   - Verify char_mapping maps it correctly to normalized position
   - Verify phonemes have correct textRange in normalized space
   - Verify DTW assigns phonemes to correct word

3. Check `mapToNormalized()` correctness:
   - Test with known examples ("Dr." → "Doctor")
   - Verify binary search logic is correct
   - Check boundary conditions (first/last word)

### Priority 3: Fix Last Word Stuck Issue

**Goal:** Word highlighting completes smoothly at paragraph end

**Quick Fixes to Try:**
1. Add completion handler when audio finishes:
   ```swift
   // When audio completes
   if currentWordIndex < wordTimings.count - 1 {
       // Force advance to last word
       currentWordIndex = wordTimings.count - 1
   }
   ```

2. Check last word duration is reasonable:
   - Log last word duration vs actual audio remaining
   - If mismatch, may need forced completion

3. Add timeout for stuck detection:
   - If word highlighted for > 2x its expected duration, force next

---

## 📚 Key Resources

### Documentation
- **This handoff:** `docs/HANDOFF_2025-11-14_WCEIL_DTYPE_FIX.md`
- **Previous session:** `docs/HANDOFF_2025-11-14_WORD_HIGHLIGHTING_DEBUG.md`
- **w_ceil verification:** `~/projects/sherpa-onnx/WCEIL_VERIFICATION.md`
- **Framework update guide:** `docs/FRAMEWORK_UPDATE_GUIDE.md`

### Code Locations
- **w_ceil extraction:** `sherpa-onnx/csrc/offline-tts-vits-impl.h:502-519`
- **Swift wrapper:** `Services/TTS/SherpaOnnx.swift:190-204`
- **Phoneme alignment:** `Services/TTS/PhonemeAlignmentService.swift:500-556`
- **Export script:** `piper/src/python/piper_train/export_onnx.py`
- **Automation:** `scripts/export-and-update-model.sh`

### Git Commits (Piper)
- `b94571f` - fix: squeeze w_ceil to 1D tensor
- `748ad5b` - feat: automatically add sherpa-onnx metadata
- `0dad73a` - fix: cast w_ceil to int64 for compatibility

### Git Commits (Listen2)
- `8986815` - feat: add automated export and update script

---

## 💡 Lessons Learned

### What Worked
✅ Systematic debugging skill - traced through entire data pipeline
✅ Testing with minimal ONNX inference confirmed the issue
✅ Comparing old vs new model metadata revealed missing fields
✅ Automation script prevents future manual errors

### What Didn't Work Initially
❌ Assumed framework was stale (it wasn't)
❌ Assumed tensor shape was the only issue (dtype was the real problem)
❌ Assumed models had correct w_ceil (they had float32 instead of int64)

### Key Insights

**The Bug Was a Perfect Storm:**
1. Tensor shape wrong (3D → 1D)
2. Data type wrong (float32 → int64)
3. Metadata missing (0 → 7 fields)

**Any ONE of these** would have caused crashes or corruption.

**The float32 → int64 issue was especially insidious** because:
- Model exported successfully
- ONNX Runtime could run it
- Values LOOKED reasonable in Python (1-7)
- But sherpa-onnx C++ reading float32 bytes as int64 got garbage
- This explained the exact corruption pattern we saw

**Why w_ceil was float32:**
- Piper VITS uses `torch.ceil(w)` which returns float32
- We needed explicit `.long()` cast to get int64
- ONNX export preserves the PyTorch dtype

---

## ✅ Success Criteria for Next Session

### Minimum Viable
- [ ] No multi-minute pauses between paragraphs
- [ ] User knows when synthesis is happening (loading indicator)
- [ ] Word highlighting is correct >80% of the time
- [ ] Last word completes smoothly (no stuck highlighting)

### Ideal
- [ ] Synthesis feels instant (<1s perceived delay)
- [ ] Word highlighting is correct >95% of the time
- [ ] Smooth paragraph transitions
- [ ] Pre-synthesis of next paragraph (true async pipeline)

### Acceptable Fallback
If word highlighting accuracy can't be fixed:
- [ ] Document known issues with normalization mapping
- [ ] Provide clear examples of what works vs what doesn't
- [ ] Plan alternative approach (different alignment method?)
- [ ] Set user expectations about accuracy

---

## 🚨 Critical Notes for Next Session

### The w_ceil Fix is COMPLETE
The tensor corruption is **fully fixed**. Do not revisit this unless you see:
- `First phoneme duration: -2147483648` (would indicate wrong dtype)
- `First phoneme duration: 1073741824` (would indicate float32→int64 issue)
- Durations that are clearly wrong (hours instead of milliseconds)

If durations look reasonable (0.01-0.1s per phoneme), **the w_ceil extraction is working correctly**.

### Focus on the Right Problems
The remaining issues are **NOT w_ceil extraction**. They are:

1. **Performance:** Synthesis is slow or blocking
2. **Mapping:** VoxPDF → normalized → phoneme mapping has bugs
3. **Timing:** Word completion logic needs work

### Use the Automation
When exporting models, **always use** `./scripts/export-and-update-model.sh`.
It ensures correct shape, dtype, and metadata automatically.

### Don't Waste Time on These
- ❌ Re-verifying w_ceil tensor shape
- ❌ Re-checking model metadata
- ❌ Re-exporting models "just to be sure"
- ❌ Debugging sherpa-onnx C++ extraction (it works now!)

**Trust the verification script** - if it says ✅, move on.

---

**End of Handoff**

*Next session should start with Priority 1: Profile synthesis performance to find the bottleneck causing multi-minute pauses*
