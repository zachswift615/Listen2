# Documentation Archive

This directory contains historical documentation that has been archived to keep the main docs/ directory clean and focused.

**Archive Date:** November 26, 2025

## What's Archived Here

### Session Handoffs (22 files)
- All SESSION_HANDOFF*.md files
- All HANDOFF_*.md files
- Session-specific context documents
- Word highlighting debugging sessions
- Bug fix handoffs

**Why Archived:** Session handoffs are ephemeral context documents meant for specific Claude Code sessions. Once the work is complete, these become historical artifacts rather than active documentation.

### Implementation Plans (27 files)
- Plans from 2024-2025 (completed features)
- Initial Piper TTS integration plans
- Multiple iterations of chunk buffer implementation
- VoxPDF integration plans
- Reader enhancements
- Word alignment and phoneme duration work
- Task completion reports

**Why Archived:** These plans represent completed work. The current state of the codebase is the authoritative source. Only the most recent active plans remain in docs/plans/.

### Word Highlighting Documentation (11 files)
- Architecture documents
- Code locations
- Fix summaries
- Timeline
- Quick reference
- Implementation details
- Word alignment flow diagrams

**Why Archived:** Over-documentation of a single feature. The feature is now implemented and the code is the source of truth.

### Performance & Testing (5 files)
- PERFORMANCE_PROFILE.md
- PERFORMANCE_ANALYSIS.md
- MANUAL_TESTING_CHECKLIST.md
- TESTING_REPORT.md
- performance-baseline.md
- word-alignment-performance.md

**Why Archived:** Outdated performance snapshots and testing checklists from November 2025. Current performance should be measured fresh when needed.

### Technical Specifications (4 files)
- phoneme-duration-implementation.md
- sherpa-onnx-modifications-spec.md
- task-8-background-processing-report.md
- task-8-system-flow.md
- w_ceil_tensor_analysis.md

**Why Archived:** Implementation details that are no longer actively referenced. Code and active documentation serve as current reference.

### Miscellaneous (3 files)
- CHARACTER_MAPPING_FIX_SUMMARY.md
- PLAN_UPDATE_SUMMARY.md
- STREAMING_ONNX_FEASIBILITY.md
- deployment-readiness-checklist.md

**Why Archived:** Completed bug fixes, feasibility studies, and outdated checklists.

## Current Active Documentation

The following remain in the main docs/ directory:

- **FRAMEWORK_UPDATE_GUIDE.md** - Essential guide for updating sherpa-onnx.xcframework (referenced in .claude/CLAUDE.md)
- **voxpdf-integration-testing.md** - Active integration documentation
- **docs/plans/** - Only the 4 most recent implementation plans (November 23, 2025)
- **docs/testing/** - Current test documentation (manual-testing-checklist.md, test-coverage-summary.md)

## Root Level Documentation

- **README.md** - Main project documentation
- **EPUB_SETUP.md** - ZIPFoundation setup guide

## Archive Structure

```
archive/
├── session-handoffs/  # 22 session context files
├── plans/             # 27 completed implementation plans
├── word-highlighting/ # 11 feature-specific docs
├── testing/           # 5 outdated test/performance docs
├── *.md              # 7 miscellaneous technical docs
└── README.md         # This file
```

## Total Files Archived

**77 files** moved from active documentation to archive.

## Restoration

If you need to reference any archived documentation:
1. All files are preserved in this archive
2. Git history contains the original locations
3. Files can be moved back to active docs if needed

## Future Maintenance

Consider archiving documentation when:
- Session handoffs are complete
- Implementation plans are fully executed
- Features are stable and code is the source of truth
- Performance snapshots become outdated (>3 months old)
- Bug fix summaries describe resolved issues

Keep active documentation focused on:
- Current architecture
- Essential setup guides
- Active implementation plans
- Living test documentation
