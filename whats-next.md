# Handoff: CTC Forced Alignment Implementation

<original_task>
Implement CTC forced alignment to replace the drifty phoneme-duration and error-prone ASR+DTW word highlighting approaches. The goal is frame-accurate (<50ms drift) word highlighting that works with ALL Piper voices without requiring model re-export. User wants to clean up all legacy alignment code as part of this effort.
</original_task>

<work_completed>

## 1. Brainstorming & Design (Complete)
- Used superpowers:brainstorming skill to refine requirements
- User confirmed: Frame-accurate highlighting, all voices, bundle size not a concern, remove legacy code

## 2. Implementation Plan (Complete)
- Created comprehensive plan: `docs/plans/2025-11-21-ctc-forced-alignment.md`
- 11 tasks with TDD approach, exact file paths, code snippets
- Plan was reviewed by superpowers:code-reviewer subagent (score 6.5/10)

## 3. Code Review Findings (Addressed)
Key issues identified:
- ONNX Runtime integration was undefined (BLOCKER - now resolved via spike)
- MMS_FA export not validated (BLOCKER - now resolved via spike)
- Word merging algorithm has bugs (needs fixing during implementation)
- Linear resampling causes artifacts (consider Accelerate framework)
- TTSService integration oversimplified (needs more detail)

## 4. Spike Validation (Complete)
Created and ran `scripts/spike_mms_fa.py` to validate approach:

**CRITICAL FINDINGS:**
| Aspect | Result |
|--------|--------|
| Model loads | ✅ torchaudio.pipelines.MMS_FA |
| Labels | 29 chars: `'-', 'a', 'i', 'e', 'n', 'o', 'u', 't', 's', 'r', 'm', 'k', 'l', 'd', 'g', 'h', 'y', 'b', 'p', 'w', 'c', 'v', 'j', 'z', 'f', "'", 'q', 'x', '*'` |
| **ONNX size** | **3.1 MB** (not 1.2GB as feared!) |
| ONNX inference | ✅ Matches PyTorch output |
| Frame rate | 49 fps (20ms per frame) |
| Variable length | ✅ Dynamic axes work |

**Token indices:**
- Blank `-` = index 0
- Space `*` = index 28
- Apostrophe `'` = index 25

## 5. Workshop Decision Recorded
```
workshop decision "Spike validated MMS_FA model export to ONNX for forced alignment"
```

## 6. Plan Updated with Spike Results
Added spike findings section to `docs/plans/2025-11-21-ctc-forced-alignment.md`

## 7. Python Environment Created
- `venv-mms-spike/` with torch, torchaudio, onnx, onnxruntime, onnxscript installed
- Can be reused for model export

</work_completed>

<work_remaining>

## Execute Plan Using Subagent-Driven Development

TodoWrite was set up with 11 tasks:

1. **Task 1: Export MMS_FA Model** (IN_PROGRESS)
   - Use existing `venv-mms-spike` environment
   - Fix export script to save to `Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa/`
   - Save `mms-fa.onnx` (~3.1MB) and `labels.txt`
   - Add to Git LFS, commit

2. **Task 2: Create CTCTokenizer**
   - Create `Listen2/Listen2/Listen2/Listen2/Services/TTS/CTCTokenizer.swift`
   - Create test file
   - Use 29-label vocabulary from spike
   - Follow TDD

3. **Task 3: Create CTCForcedAligner Core Structure**
   - Actor-based Swift service
   - Initialize with ONNX model and labels

4. **Task 4: Implement CTC Trellis Algorithm**
   - Build trellis matrix [frames x (2*tokens+1)]
   - Implement Viterbi backtracking

5. **Task 5: Implement Word Merging**
   - FIX bug identified in code review: don't skip spans unconditionally
   - Track character positions explicitly
   - Handle punctuation, apostrophes

6. **Task 6: Implement ONNX Inference**
   - Use sherpa-onnx's ONNX Runtime (already bundled)
   - Or add onnxruntime-objc CocoaPod
   - Test with real audio samples

7. **Task 7: Implement Full Alignment Pipeline**
   - `align(audioSamples:, sampleRate:, transcript:, paragraphIndex:)` -> `AlignmentResult`
   - Include resampling 22050->16000 Hz

8. **Task 8: Integrate with TTSService**
   - Replace `PhonemeAlignmentService` usage
   - Wire up with streaming architecture

9. **Task 9: Remove Legacy Phoneme Duration Code**
   - Delete `PhonemeAlignmentService.swift`
   - Delete `TextNormalizationMapper.swift`
   - Delete `DynamicAlignmentEngine.swift`

10. **Task 10: Remove ASR Alignment Code**
    - Delete `WordAlignmentService.swift`
    - Delete `Resources/ASRModels/nemo-ctc-conformer-small/`
    - Delete `Resources/ASRModels/whisper-tiny/`

11. **Task 11: Update Tests and Manual Validation**
    - Update/remove affected tests
    - Manual testing with edge cases

## Execution Approach
Use **superpowers:subagent-driven-development** skill:
- Dispatch fresh subagent per task
- Code review after each task
- Fix issues before proceeding
- Final review when complete

</work_remaining>

<attempted_approaches>

## Spike Export Issues (Resolved)
1. **Model returns tuple** - Fixed by checking `isinstance(output, tuple)` and taking `output[0]`
2. **Missing onnxscript** - Installed via `pip install onnxscript`
3. **ONNX version conversion warning** - Ignorable, model exports successfully at opset 18

## Previous Approaches (Historical)
1. **Phoneme Duration Extraction** - Drifty, requires model re-export, abandoned
2. **ASR + DTW (NeMo CTC)** - Error-prone, crashes on apostrophes, abandoned

</attempted_approaches>

<critical_context>

## Key Architecture Decisions
- **CTC Forced Alignment** uses known transcript (not ASR transcription)
- **MMS_FA model** from torchaudio.pipelines - 315M params but only 3.1MB ONNX
- **Frame rate**: ~49 fps (20ms per frame) - good for word-level accuracy
- **No fallback** - User chose to remove all legacy code

## Important File Paths
```
Listen2/Listen2/Listen2/Listen2/Services/TTS/  # All TTS services
Listen2/Listen2/Listen2/Listen2/Resources/Models/mms-fa/  # New model location
docs/plans/2025-11-21-ctc-forced-alignment.md  # Full implementation plan
scripts/spike_mms_fa.py  # Spike script (working)
venv-mms-spike/  # Python environment with all deps
```

## Existing Code to Understand
- `AlignmentResult.swift` - Reuse this struct (WordTiming with startTime, duration, rangeLocation, rangeLength)
- `AlignmentCache.swift` - Reuse for caching
- `WordHighlighter.swift` - Consumer of alignment results, uses CADisplayLink
- `TTSService.swift` - Integration point, has `PhonemeAlignmentService` and `ctcAligner` placeholders

## ONNX Runtime Options for iOS
1. **sherpa-onnx's ONNX Runtime** - Already bundled in the xcframework
2. **onnxruntime-objc CocoaPod** - Alternative if sherpa-onnx doesn't expose generic inference

## Code Review Issues to Address
1. Word merging algorithm must track character positions (not index counting)
2. Consider Accelerate framework for resampling (not linear interpolation)
3. Need to show how CTC integrates with SynthesisQueue/ChunkBuffer streaming

## Labels Vocabulary (29 chars)
```
Index 0: '-' (blank)
Index 1-27: 'a', 'i', 'e', 'n', 'o', 'u', 't', 's', 'r', 'm', 'k', 'l', 'd', 'g', 'h', 'y', 'b', 'p', 'w', 'c', 'v', 'j', 'z', 'f', "'", 'q', 'x'
Index 28: '*' (space/word boundary)
```

</critical_context>

<current_state>

## Deliverable Status
| Item | Status |
|------|--------|
| Implementation plan | ✅ Complete |
| Code review | ✅ Complete |
| Spike validation | ✅ Complete |
| Model export script | 🟡 Working (needs finalization) |
| CTCTokenizer | ⏳ Not started |
| CTCForcedAligner | ⏳ Not started |
| TTSService integration | ⏳ Not started |
| Legacy code removal | ⏳ Not started |

## Git State
- Branch: main
- No uncommitted changes related to this feature
- spike_mms_fa.py created but not committed

## Python Environment
- `venv-mms-spike/` ready with all dependencies
- Can export model immediately

## Next Immediate Action
Start fresh session and:
1. Run `/taches-cc-resources:run-prompt` with the plan OR
2. Use `superpowers:subagent-driven-development` to dispatch Task 1 subagent

## Command to Resume
```
Read docs/plans/2025-11-21-ctc-forced-alignment.md and execute using subagent-driven development starting from Task 1
```

</current_state>
