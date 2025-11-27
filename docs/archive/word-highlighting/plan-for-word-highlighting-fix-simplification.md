Based on my analysis of your word highlighting implementation, yes, you are significantly 
  overcomplicating this. Let me provide a critical analysis with concrete recommendations:

  Critical Analysis

  The Core Issue

  You're trying to maintain character-level precision for a word-level problem. Since you only need
  word-level highlighting, the complexity around character mapping is unnecessary and causing most
  of your problems.

  Current Architecture Problems

  1. Three Different Text Representations:
    - Original: "Dr. Smith's"
    - Normalized: "doctor smith s"
    - Phoneme positions: word-level groupings
  2. Multiple Broken Layers:
    - State bug: Normalized text persisting across calls
    - Character offset: espeak starting at 1-2 instead of 0
    - Sparse mapping: Only getting partial character mappings
    - Wrong abstraction: Character-level mapping for word-level highlighting
  3. Overengineered Solutions:
    - Three different alignment methods in PhonemeAlignmentService
    - Complex character mapping that doesn't work
    - Multiple position transformation layers
    - Premium alignment with dynamic programming (unused)
  ⎿  User rejected Claude's plan:
     ╭─────────────────────────────────────────────────────────────────────────────────────────────────╮
     │ Critical Analysis: Yes, You're Overcomplicating It                                              │
     │                                                                                                 │
     │ The Real Problem                                                                                │
     │                                                                                                 │
     │ You only need word-level highlighting, but you're maintaining character-level precision         │
     │ infrastructure that doesn't work. The broken character mapping is causing cascading complexity. │
     │                                                                                                 │
     │ Simplified Architecture (What You Actually Need)                                                │
     │                                                                                                 │
     │ Step 1: Fix the State Bug First                                                                 │
     │ - The normalized text persisting across calls is your #1 issue                                  │
     │ - This makes everything else impossible to debug                                                │
     │ - Fix in sherpa-onnx C++ where synthesis state is managed                                       │
     │                                                                                                 │
     │ Step 2: Abandon Character Mapping Entirely                                                      │
     │ Since phonemes are already grouped by word and you only need word highlighting:                 │
     │ 1. Use normalized text for phoneme-to-word matching                                             │
     │ 2. Map normalized words back to original words by position/content                              │
     │ 3. Stop trying to track character-level positions                                               │
     │                                                                                                 │
     │ Step 3: Simplified Alignment Algorithm                                                          │
     │ 1. Split original text into words → ["Dr.", "Smith's"]                                          │
     │ 2. Get normalized text → "doctor smith s"                                                       │
     │ 3. Split normalized into words → ["doctor", "smith", "s"]                                       │
     │ 4. Get phoneme groups (already word-level) → [group1, group2, group3]                           │
     │ 5. Simple mapping:                                                                              │
     │    - "Dr." → "doctor" → group1 → sum durations                                                  │
     │    - "Smith's" → "smith s" → group2+group3 → sum durations                                      │
     │                                                                                                 │
     │ Implementation Plan                                                                             │
     │                                                                                                 │
     │ Phase 1: Debug & Fix Core Issues                                                                │
     │ 1. Fix state management bug in s
herpa-onnx (normalized text persistence)                        │
     │ 2. Add comprehensive logging to trace actual vs expected text                                   │
     │ 3. Verify phoneme groups match normalized words                                                 │
     │                                                                                                 │
     │ Phase 2: Simplify Alignment Service                                                             │
     │ 1. Remove character mapping logic entirely                                                      │
     │ 2. Keep only word-level alignment (alignWithEspeakWords)                                        │
     │ 3. Implement simple word matching between original/normalized                                   │
     │ 4. Use fuzzy matching for contractions/abbreviations                                            │
     │                                                                                                 │
     │ Phase 3: Handle Edge Cases Simply                                                               │
     │ 1. Contractions: "don't" → "do not" (2 phoneme groups for 1 display word)                       │
     │ 2. Abbreviations: "Dr." → "doctor" (1-to-1 mapping by position)                                 │
     │ 3. Numbers: "$99.99" → "ninety nine dollars and ninety nine cents" (multiple groups)            │
     │                                                                                                 │
     │ Why This Will Work Better                                                                       │
     │                                                                                                 │
     │ 1. Eliminates broken dependencies: No more character mapping offsets                            │
     │ 2. Matches actual data structure: Phonemes are already word-grouped                             │
     │ 3. Simpler to debug: Word matching vs character position arithmetic                             │
     │ 4. Handles normalization naturally: Word-level matching is more forgiving                       │
     │ 5. Already partially working: Your alignWithEspeakWords is closest to correct                   │
     │                                                                                                 │
     │ The Gotcha You're Missing                                                                       │
     │                                                                                                 │
     │ The character mapping from espeak-ng was never meant for character-level precision - it marks   │
     │ WORD BOUNDARIES. You've been trying to use a word-level feature for character-level mapping,    │
     │ which is why it's sparse and offset.                                                            │
     │                                                                                                 │
     │ Immediate Next Steps                                                                            │
     │                                                                                                 │
     │ 1. Test hypothesis: Log normalized text for each synthesis to confirm state bug                 │
     │ 2. Simplify first: Strip out character mapping code, use word matching only                     │
     │ 3. Fix state bug: Ensure each synthesis gets fresh normalized text                              │
     │ 4. Add fallback: If word matching fails, distribute duration evenly                             │
     │                                                                                                 │
     │ This approach will be 10x simpler and actually work reliably.  
