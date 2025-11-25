# Phoneme Duration Cleanup & Voice System Refactoring

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove dead phoneme duration code now that CTC forced alignment is working, reduce app bundle size by ~230MB by removing extra bundled voices.

**Architecture:** The app originally had two alignment approaches: (1) PhonemeAlignmentService using w_ceil tensor from Piper, and (2) CTCForcedAligner using MMS_FA model. CTC won. PhonemeAlignmentService is now dead code - instantiated but never called. We also bundled 4 voice models (~291MB) for testing; only 1 should ship.

**Tech Stack:** Swift, Xcode, sherpa-onnx xcframework

**Design Document:** Analysis in previous session identified all dead code paths.

**Known Constraints:**
- Do NOT remove CTCForcedAligner or related code - that's the ACTIVE alignment system
- Do NOT remove espeak-ng-data - still needed for Piper TTS synthesis
- Fork reversion to official repos is deferred to a separate plan (requires framework rebuild)

---

## Task 1: Remove PhonemeAlignmentService

**Files:**
- Delete: `Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift`
- Modify: `Listen2/Listen2/Listen2/Services/TTSService.swift`

**Step 1: Remove alignmentService property from TTSService**

In `TTSService.swift`, find and delete this line (around line 100):

```swift
private let alignmentService = PhonemeAlignmentService()
```

Also delete any initialization message for it (around line 201-203):

```swift
print("[TTSService] ✅ Phoneme alignment service ready (no initialization needed)")
```

**Step 2: Delete PhonemeAlignmentService.swift**

```bash
rm Listen2/Listen2/Listen2/Services/TTS/PhonemeAlignmentService.swift
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "refactor(tts): remove dead PhonemeAlignmentService

CTC forced alignment is the active system. PhonemeAlignmentService
was instantiated but never called - pure dead code."
```

---

## Task 2: Remove PhonemeTimelineBuilder

**Files:**
- Delete: `Listen2/Listen2/Listen2/Services/TTS/PhonemeTimelineBuilder.swift`

**Step 1: Check for references**

```bash
grep -r "PhonemeTimelineBuilder" Listen2/Listen2/Listen2/Services --include="*.swift"
```

Expected: No matches (or only in the file itself)

**Step 2: Delete the file**

```bash
rm Listen2/Listen2/Listen2/Services/TTS/PhonemeTimelineBuilder.swift
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "refactor(tts): remove dead PhonemeTimelineBuilder"
```

---

## Task 3: Remove Dead Phoneme Duration Test Files

**Files:**
- Delete: `Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeAlignmentDurationTests.swift`
- Delete: `Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeAlignmentAbbreviationTests.swift`
- Delete: `Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeDurationTests.swift`
- Delete: `Listen2/Listen2/Listen2Tests/Services/TTS/DurationExtractionTests.swift`

**Step 1: Delete the test files**

```bash
rm Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeAlignmentDurationTests.swift
rm Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeAlignmentAbbreviationTests.swift
rm Listen2/Listen2/Listen2Tests/Services/TTS/PhonemeDurationTests.swift
rm Listen2/Listen2/Listen2Tests/Services/TTS/DurationExtractionTests.swift
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "test: remove dead phoneme duration test files

These tested PhonemeAlignmentService which is now removed.
CTC alignment tests remain in place."
```

---

## Task 4: Clean Up Phoneme Duration Code in SherpaOnnx.swift

**Files:**
- Modify: `Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift`

**Step 1: Search for phoneme duration references**

```bash
grep -n "phoneme_duration\|phonemeDuration\|w_ceil" Listen2/Listen2/Listen2/Services/TTS/SherpaOnnx.swift
```

Review the output. If there are comments or dead code paths related to phoneme durations, remove them.

**Step 2: Remove any dead phoneme duration extraction code**

Look for patterns like:
- `audio.pointee.phoneme_durations`
- Comments about w_ceil tensor
- Unused phoneme duration variables

Remove these if found. Keep the core TTS synthesis code.

**Step 3: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -u
git commit -m "refactor(tts): remove phoneme duration extraction code from SherpaOnnx

The C API never exposed phoneme_durations to Swift anyway.
CTC alignment doesn't need this data."
```

---

## Task 5: Remove Extra Bundled Voice Models

**Files:**
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_female-medium.onnx`
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_female-medium.onnx.json`
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_male-medium.onnx`
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_male-medium.onnx.json`
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx`
- Delete: `Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx.json`

**Step 1: Verify current bundle size**

```bash
du -sh Listen2/Listen2/Listen2/Resources/PiperModels/
```

Expected: ~290MB

**Step 2: Delete extra voice models (keep only lessac-medium)**

```bash
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_female-medium.onnx
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_female-medium.onnx.json
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_male-medium.onnx
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-hfc_male-medium.onnx.json
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx
rm Listen2/Listen2/Listen2/Resources/PiperModels/en_US-lessac-high.onnx.json
```

**Step 3: Verify new bundle size**

```bash
du -sh Listen2/Listen2/Listen2/Resources/PiperModels/
```

Expected: ~64MB (lessac-medium + espeak-ng-data + tokens.txt)

**Step 4: Commit**

```bash
git add -u
git commit -m "chore: remove extra bundled voice models

Reduces app bundle by ~230MB.
Only en_US-lessac-medium remains bundled.
Other voices available for download."
```

---

## Task 6: Update Voice Catalog

**Files:**
- Modify: `Listen2/Listen2/Listen2/Resources/voice-catalog.json`

**Step 1: Update voice catalog to mark removed voices as downloadable**

Replace the entire contents of `voice-catalog.json` with:

```json
{
  "voices": [
    {
      "id": "en_US-lessac-medium",
      "name": "Lessac",
      "language": "en_US",
      "gender": "female",
      "quality": "medium",
      "size_mb": 60,
      "sample_url": null,
      "download_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
      "checksum": "sha256:placeholder",
      "is_bundled": true
    },
    {
      "id": "en_US-lessac-high",
      "name": "Lessac (High Quality)",
      "language": "en_US",
      "gender": "female",
      "quality": "high",
      "size_mb": 109,
      "sample_url": null,
      "download_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-high.tar.bz2",
      "checksum": "sha256:placeholder",
      "is_bundled": false
    },
    {
      "id": "en_US-hfc_female-medium",
      "name": "HFC Female",
      "language": "en_US",
      "gender": "female",
      "quality": "medium",
      "size_mb": 61,
      "sample_url": null,
      "download_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-hfc_female-medium.tar.bz2",
      "checksum": "sha256:placeholder",
      "is_bundled": false
    },
    {
      "id": "en_US-hfc_male-medium",
      "name": "HFC Male",
      "language": "en_US",
      "gender": "male",
      "quality": "medium",
      "size_mb": 61,
      "sample_url": null,
      "download_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-hfc_male-medium.tar.bz2",
      "checksum": "sha256:placeholder",
      "is_bundled": false
    },
    {
      "id": "en_US-ryan-high",
      "name": "Ryan",
      "language": "en_US",
      "gender": "male",
      "quality": "high",
      "size_mb": 75,
      "sample_url": null,
      "download_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-high.tar.bz2",
      "checksum": "sha256:placeholder",
      "is_bundled": false
    }
  ],
  "version": "1.1",
  "last_updated": "2025-11-23"
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -u
git commit -m "chore: update voice catalog for downloadable voices

- en_US-lessac-medium: bundled (default)
- en_US-lessac-high: downloadable
- en_US-hfc_female-medium: downloadable
- en_US-hfc_male-medium: downloadable
- en_US-ryan-high: downloadable"
```

---

## Task 7: Verify Voice Download Still Works

**Step 1: Build and run on simulator**

```bash
xcodebuild build -project Listen2/Listen2/Listen2.xcodeproj -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Step 2: Manual testing checklist**

Test in the app:
- [ ] Default voice (Lessac) works for TTS playback
- [ ] Word highlighting works with default voice
- [ ] Voice settings shows Lessac as available
- [ ] Other voices show as downloadable (not installed)
- [ ] Download a voice (e.g., HFC Female) - verify it downloads and extracts
- [ ] Switch to downloaded voice - verify TTS playback works
- [ ] Word highlighting works with downloaded voice

**Step 3: Document any issues found**

---

## Task 8: Clean Up Dead Documentation (Optional)

**Files to review and potentially remove:**
- `docs/technical/w_ceil_tensor_analysis.md`
- `docs/WCEIL_SESSION_HANDOFF.md`
- `docs/SESSION_HANDOFF_2.md` through `docs/SESSION_HANDOFF_8.md` (if they only cover phoneme duration work)

**Step 1: Review each file**

Check if the documentation is purely about the now-dead phoneme duration approach or if it contains useful historical context.

**Step 2: Either delete or add deprecation notice**

For files with historical value, add at the top:

```markdown
> **DEPRECATED:** This document describes the phoneme duration approach which was replaced by CTC forced alignment in November 2025.
```

**Step 3: Commit**

```bash
git add -A
git commit -m "docs: mark phoneme duration documentation as deprecated"
```

---

## Summary

**Total Tasks:** 8
**Files Deleted:** ~10 (Swift files + models)
**Bundle Size Reduction:** ~230MB
**Lines of Dead Code Removed:** ~500+

**What Remains Active:**
- CTCForcedAligner and related code
- WordHighlightScheduler (new event-driven system)
- Voice download infrastructure
- espeak-ng-data (still needed for Piper synthesis)

**Deferred to Future Plan:**
- Reverting forked repos to official (sherpa-onnx, piper, piper-phonemize)
- This requires rebuilding the xcframework and thorough testing

**Future Enhancement (Separate Plan):**
- Dynamic voice registry from Piper's Hugging Face
- Voice sample previews
- Multi-language support
