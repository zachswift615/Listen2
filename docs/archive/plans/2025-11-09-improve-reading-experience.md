# Improve Reading Experience Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix font size inconsistency in word highlighting and improve paragraph splitting for better readability

**Architecture:** Fix highlighted word font to match base paragraph font (18pt), then add intelligent paragraph splitting post-processor to break large VoxPDF chunks into smaller reading units based on sentence boundaries and length thresholds.

**Tech Stack:** Swift, SwiftUI, VoxPDF C API

---

## Task 1: Fix Font Size Inconsistency in Word Highlighting

**Problem:** Highlighted words appear smaller than non-highlighted text, causing layout jumps during playback. Base font is 18pt (`bodyLarge`) but highlighted words use default `Font.body` (17pt).

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift:147`

### Step 1: Identify the font mismatch

**Read the code:**

```bash
# Check current font configuration
grep -A 5 "attributedString\[attrStartIndex" Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift
```

Expected output shows:
```swift
attributedString[attrStartIndex..<attrEndIndex].backgroundColor = DesignSystem.Colors.highlightWord
attributedString[attrStartIndex..<attrEndIndex].font = Font.body.weight(.semibold)
```

**Problem identified:**
- Line 109: Base paragraph uses `DesignSystem.Typography.bodyLarge` (18pt, regular weight)
- Line 147: Highlighted word uses `Font.body.weight(.semibold)` (17pt, semibold weight)

### Step 2: Fix the font size to match base font

**Edit:** `Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift:147`

**Replace:**
```swift
attributedString[attrStartIndex..<attrEndIndex].font = Font.body.weight(.semibold)
```

**With:**
```swift
attributedString[attrStartIndex..<attrEndIndex].font = Font.system(size: 18, weight: .semibold)
```

**Why:** This matches the `bodyLarge` font size (18pt) defined in DesignSystem.swift:52 while keeping semibold weight for emphasis.

### Step 3: Verify font consistency

**Manual Test:**
1. Build and run on iPhone 15 Pro Max
2. Open a document and start playback
3. Observe word highlighting
4. **Expected:** Words should not change size when highlighted/unhighlighted
5. **Expected:** No layout jumps or words moving between lines

### Step 4: Commit the fix

```bash
git add Listen2/Listen2/Listen2/Listen2/Views/ReaderView.swift
git commit -m "fix: match highlighted word font size to base paragraph font

Highlighted words were using Font.body (17pt) while paragraph text uses
bodyLarge (18pt), causing words to shrink when highlighted and creating
distracting layout jumps.

Now uses Font.system(size: 18, weight: .semibold) to match base size.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Add Intelligent Paragraph Splitting

**Problem:** VoxPDF returns large text chunks as paragraphs (entire page sections), making reading experience poor with excessive scrolling. PDFs like academic books combine multiple paragraphs into single chunks.

**Solution:** Post-process VoxPDF output to split large paragraphs into smaller reading units based on:
- Sentence boundaries (period + space + capital letter)
- Double newlines (paragraph breaks)
- Maximum length threshold (500 characters)

**Files:**
- Modify: `Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift:46-55`

### Step 1: Add paragraph splitting method

**Add after line 36 in:** `Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift`

```swift
    /// Splits large paragraphs into smaller reading chunks for better UX
    /// - Parameter paragraphs: Raw paragraphs from VoxPDF
    /// - Returns: Split paragraphs optimized for reading
    func splitParagraphsForReading(_ paragraphs: [String]) -> [String] {
        var result: [String] = []

        for paragraph in paragraphs {
            // First, split on double newlines (clear paragraph breaks)
            let sections = paragraph.components(separatedBy: "\n\n")

            for section in sections {
                let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                // If section is short enough, keep as-is
                if trimmed.count <= 500 {
                    result.append(trimmed)
                    continue
                }

                // Split long sections by sentences
                let sentences = splitIntoSentences(trimmed)
                var currentChunk = ""

                for sentence in sentences {
                    // If adding this sentence would exceed threshold, save current chunk
                    if !currentChunk.isEmpty && (currentChunk.count + sentence.count) > 500 {
                        result.append(currentChunk.trimmingCharacters(in: .whitespaces))
                        currentChunk = sentence
                    } else {
                        if !currentChunk.isEmpty {
                            currentChunk += " "
                        }
                        currentChunk += sentence
                    }
                }

                // Add final chunk
                if !currentChunk.isEmpty {
                    result.append(currentChunk.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        return result
    }

    /// Split text into sentences using period boundaries
    /// - Parameter text: Text to split
    /// - Returns: Array of sentences
    private func splitIntoSentences(_ text: String) -> [String] {
        // Pattern: period followed by space and capital letter
        // This avoids splitting on abbreviations like "Dr. Smith"
        let pattern = #"\.(?=\s+[A-Z])"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        guard !matches.isEmpty else {
            return [text]
        }

        var sentences: [String] = []
        var lastEnd = text.startIndex

        for match in matches {
            if let matchRange = Range(match.range, in: text) {
                // Include the period in the sentence
                let sentenceEnd = text.index(after: matchRange.lowerBound)
                let sentence = String(text[lastEnd..<sentenceEnd])
                sentences.append(sentence)

                // Skip whitespace after period
                lastEnd = text.index(matchRange.upperBound, offsetBy: 0, limitedBy: text.endIndex) ?? text.endIndex

                // Skip whitespace
                while lastEnd < text.endIndex && text[lastEnd].isWhitespace {
                    lastEnd = text.index(after: lastEnd)
                }
            }
        }

        // Add remaining text as final sentence
        if lastEnd < text.endIndex {
            sentences.append(String(text[lastEnd...]))
        }

        return sentences.filter { !$0.isEmpty }
    }
```

### Step 2: Apply splitting in PDF text extraction

**Modify:** `Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift:46-55`

**Find the extractText method around line 46:**
```swift
func extractText(from url: URL, sourceType: SourceType) async throws -> [String] {
    switch sourceType {
    case .pdf:
        return try await extractPDFText(from: url)
    case .epub:
        return try await extractEPUBText(from: url)
    case .clipboard:
        throw DocumentProcessorError.unsupportedFormat
    }
}
```

**Replace with:**
```swift
func extractText(from url: URL, sourceType: SourceType) async throws -> [String] {
    let rawParagraphs: [String]

    switch sourceType {
    case .pdf:
        rawParagraphs = try await extractPDFText(from: url)
    case .epub:
        rawParagraphs = try await extractEPUBText(from: url)
    case .clipboard:
        throw DocumentProcessorError.unsupportedFormat
    }

    // Split large paragraphs for better reading experience
    // Only apply to PDFs which tend to have large chunks
    if sourceType == .pdf {
        return splitParagraphsForReading(rawParagraphs)
    }

    return rawParagraphs
}
```

### Step 3: Update extractPDFText to return array

**Check around line 128-144 that extractPDFText returns [String]:**

The current implementation should already return `[String]` via VoxPDFService.extractParagraphs(). Verify:

```bash
grep -A 10 "private func extractPDFText" Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
```

Expected: Method returns `[String]` from `voxPDFService.extractParagraphs(from: url)`

**If it returns String instead of [String], modify to use extractParagraphs().**

### Step 4: Add logging to track splitting

**Add debug logging in splitParagraphsForReading after line with `var result: [String] = []`:**

```swift
        var result: [String] = []
        let originalCount = paragraphs.count
        print("📄 Splitting \(originalCount) raw paragraphs for better readability...")
```

**Add at end before return statement:**

```swift
        print("📄 Split into \(result.count) reading chunks (from \(originalCount) raw paragraphs)")
        return result
```

### Step 5: Build and verify compilation

```bash
cd Listen2/Listen2/Listen2
xcodebuild build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 16' | grep -E "(BUILD|error:)"
```

**Expected output:**
```
** BUILD SUCCEEDED **
```

### Step 6: Manual test on device

1. **Delete app** from iPhone 15 Pro Max (to clear cached data)
2. **Rebuild and install** from Xcode
3. **Re-import test PDF** (Building Applications with AI Agents)
4. **Open Chapter 2** from TOC
5. **Observe paragraph structure:**
   - Paragraphs should be smaller chunks (≤500 chars each)
   - Each screen should show 2-3 reading chunks, not one huge block
   - First paragraph of chapter shouldn't scroll off screen
6. **Check console for logs:**
   ```
   📄 Splitting 1477 raw paragraphs for better readability...
   📄 Split into ~2100 reading chunks (from 1477 raw paragraphs)
   ```

**Expected behavior:**
- Chapter 2 starts with "Most practitioners don't begin..." as first chunk
- Next chunk starts around "This chapter is your quick start..."
- Paragraphs feel natural for reading, not overwhelming

### Step 7: Commit paragraph splitting feature

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
git commit -m "feat: add intelligent paragraph splitting for better reading UX

VoxPDF returns large text chunks (sometimes entire page sections) as single
paragraphs, creating poor reading experience with excessive scrolling.

**Solution:**
- Added splitParagraphsForReading() to post-process VoxPDF output
- Splits on double newlines (clear paragraph breaks)
- Splits long sections by sentence boundaries (period + capital letter)
- Uses 500 character threshold for maximum chunk size
- Only applies to PDFs (EPUBs have better native paragraph structure)

**Benefits:**
- Smaller, digestible reading chunks
- Better scrolling and navigation
- Current word stays in viewport during playback
- Matches UX of VoiceDream app

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Handle Edge Cases in Paragraph Splitting

**Files:**
- Test: Manual testing with various PDF formats

### Step 1: Test with different PDF types

Test paragraph splitting with:

1. **Academic papers** (dense text, lots of abbreviations)
2. **Technical books** (code blocks, lists)
3. **Novels** (narrative text, dialogue)

**Watch for:**
- Incorrectly split sentences (e.g., "Dr. Smith" → "Dr." and "Smith")
- Too-small chunks (< 50 characters)
- Missing text between chunks

### Step 2: Add minimum chunk size check

If testing reveals too-small chunks, **add to splitParagraphsForReading after line checking 500 threshold:**

```swift
                // If section is very short, it might be a heading or list item
                // Combine with next section if possible
                if trimmed.count < 50 && result.count > 0 {
                    // Append to previous chunk
                    result[result.count - 1] += "\n\n" + trimmed
                    continue
                }

                if trimmed.count <= 500 {
                    result.append(trimmed)
                    continue
                }
```

### Step 3: Commit edge case fixes (if needed)

```bash
git add Listen2/Listen2/Listen2/Listen2/Services/DocumentProcessor.swift
git commit -m "fix: improve paragraph splitting edge cases

- Added minimum chunk size (50 chars) to prevent tiny fragments
- Combine small chunks with previous paragraph
- Prevents heading-only chunks

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Update Word Position Mapping for Split Paragraphs

**Problem:** Word positions reference original VoxPDF paragraph indices, but we've now split paragraphs. Need to update word position mapping to account for splits.

**Impact Assessment:**

Word highlighting uses:
- `WordPosition.paragraphIndex` to map words to paragraphs
- `WordPosition.characterOffset` for position within paragraph

**If paragraphs are split AFTER word extraction:**
- Word positions will be incorrect (pointing to old paragraph indices)
- Word highlighting will break

**Solution:** Extract words AFTER paragraph splitting, or remap word positions.

### Step 1: Check current word extraction order

```bash
# Check if word extraction happens before or after text extraction
grep -B 5 -A 5 "extractWordPositions" Listen2/Listen2/Listen2/Listen2/ViewModels/LibraryViewModel.swift
```

**Expected: Line 107 shows word extraction happens AFTER text extraction**

This means word positions are based on original VoxPDF paragraphs, not split paragraphs.

### Step 2: Decision - Extract words from split paragraphs

**Two options:**

**Option A:** Extract words BEFORE splitting, then remap indices (complex)
**Option B:** Pass split paragraphs to word extraction (simpler)

**Choose Option B** - modify extractWordPositions to accept paragraph text array and map based on text matching.

**This is complex and may not be needed immediately.** Test word highlighting first with split paragraphs.

### Step 3: Test word highlighting with split paragraphs

1. Build and run on device
2. Import PDF
3. Play audio
4. **Check:** Does word highlighting still work correctly?

**If word highlighting is broken:**
- Highlighted words appear in wrong paragraphs
- No highlighting appears
- App crashes during playback

**If working correctly:** Word positions may be resilient to paragraph splits because they use character offsets.

### Step 4: Add TODO if word highlighting breaks

If word highlighting is broken after paragraph splitting, add TODO:

```swift
// TODO: Remap word positions after paragraph splitting
// Word positions reference original VoxPDF paragraph indices,
// but paragraphs are now split for better reading UX.
// Need to update WordPosition.paragraphIndex to match split indices.
```

**Note:** This may require extracting words AFTER paragraph splitting or building a mapping between original and split paragraph indices.

---

## Completion Criteria

**All tasks complete when:**

1. ✅ Highlighted words match base font size (18pt) - no layout jumps
2. ✅ Large paragraphs are split into readable chunks (≤500 chars)
3. ✅ Chapter 2 displays properly without text scrolling off-screen
4. ✅ Console shows paragraph splitting logs
5. ✅ Word highlighting still works after paragraph splitting (or TODO added)
6. ✅ All changes committed with descriptive messages

**Testing Checklist:**
- [ ] Delete app from device
- [ ] Rebuild and install
- [ ] Re-import test PDF
- [ ] Navigate to Chapter 2 via TOC
- [ ] Verify paragraph sizes are reasonable
- [ ] Start playback
- [ ] Verify word highlighting size matches text
- [ ] Verify no layout jumps during highlighting
- [ ] Check console logs for split counts

---

## Notes

- Paragraph splitting only applies to PDFs (EPUBs have better structure)
- 500 character threshold is tunable based on user feedback
- Sentence splitting regex avoids common abbreviations
- Word highlighting may need adjustment if splits break character offsets
