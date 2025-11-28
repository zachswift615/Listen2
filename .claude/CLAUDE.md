  ## Voice/TTS (Text-to-Speech)

  Use `mcp__tts__speak_tool` to speak to the user aloud. Use it liberally - for thinking
  out loud, narrating what you're doing, conversing naturally, or any time voice adds to
  the experience.

  **Parameters:**
  - `text` (required): What to say
  - `tone`: neutral | excited | concerned | calm | urgent (default: neutral)
  - `speed`: 0.5 to 2.0 (default: 1.0)
  - `interrupt`: Stop current speech before starting (default: true)

  **Example uses:**
  - Thinking through a problem out loud
  - Announcing task completion or updates
  - Reading errors or warnings aloud
  - Conversational back-and-forth

  **Tone guide:**
  - `calm` - explanations, walkthroughs
  - `urgent` - errors, critical issues
  - `excited` - successes, good news
  - `concerned` - warnings, risky operations

  Use `mcp__tts__stop_tool` to stop speech mid-playback.

---

# Workshop CLI Integration

This project uses Workshop, a persistent context tool for maintaining institutional knowledge across sessions.

**Note for Windows:** Workshop hooks are currently disabled on Windows due to Claude Code freezing issues. You'll need to manually run Workshop commands to load context and capture sessions. Start each session with `workshop context` to load existing knowledge.

## Workshop Commands

**At the start of each session (especially on Windows):**
- Run `workshop context` to load project knowledge
- Run `workshop recent` to see what was worked on recently
- Run `workshop why "<topic>"` if you need to understand past decisions

**Use Workshop liberally throughout the session to:**
- Record decisions: `workshop decision "<text>" -r "<reasoning>"`
- Document gotchas: `workshop gotcha "<text>" -t tag1 -t tag2`
- Add notes: `workshop note "<text>"`
- Track preferences: `workshop preference "<text>" --category code_style`
- Manage state: `workshop goal add "<text>"` and `workshop next "<text>"`

**Query context (use these frequently!):**
- `workshop why "<topic>"` - THE KILLER FEATURE! Answers "why did we do X?" - prioritizes decisions with reasoning
- `workshop context` - View session summary
- `workshop search "<query>"` - Find relevant entries
- `workshop recent` - Recent activity
- `workshop summary` - Activity overview
- `workshop sessions` - View past session history
- `workshop session last` - View details of the most recent session

**Important:** Workshop helps maintain continuity across sessions. Document architectural decisions, failed approaches, user preferences, and gotchas as you discover them.

**Best Practice:** When you wonder "why did we choose X?" or "why is this implemented this way?", run `workshop why "X"` first before asking the user!

## Importing Past Sessions

Workshop can import context from past Claude Code sessions stored in JSONL transcript files:

- **When to suggest:** If the user mentions wanting context from previous sessions, or asks "why" questions that might be answered by historical context, suggest running `workshop import --execute`
- **First-time import:** Always ask the user before running import for the first time - it can extract hundreds of entries from historical sessions
- **What it does:** Analyzes JSONL transcripts and automatically extracts decisions, gotchas, and preferences from past conversations
- **Command:** `workshop import --execute` (without --execute it's just a preview)
- **Location:** By default, imports from the current project's JSONL files in `~/.claude/projects/`

**Important:** You have permission to run `workshop import --execute`, but always ask the user first, especially if import has never been run in this project. Let them decide if they want to import historical context.

## Framework Updates

**IMPORTANT:** The Listen2 app uses a custom-built sherpa-onnx.xcframework. When sherpa-onnx C++ code changes, you MUST update the framework.

**Quick update:**
```bash
./scripts/update-frameworks.sh
```

**Rebuild + update:**
```bash
./scripts/update-frameworks.sh --build
```

**After updating:**
1. Clean build folder (⇧⌘K)
2. Build and run (⌘R)

See [docs/FRAMEWORK_UPDATE_GUIDE.md](../docs/FRAMEWORK_UPDATE_GUIDE.md) for complete documentation.

**Why this matters:** Stale frameworks cause:
- ❌ Stale normalized text bugs
- ❌ Corrupt phoneme durations
- ❌ Missing new features
- ❌ Hours of debugging time wasted

**Always check** after modifying:
- sherpa-onnx C++ code
- espeak-ng modifications
- piper-phonemize changes
