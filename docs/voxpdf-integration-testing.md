# VoxPDF Integration Testing Guide

## Test Scenarios

### 1. Basic PDF Text Extraction

**Test:** Import simple PDF
**Expected:** Text extracted successfully via VoxPDF
**Check:** Console should show "VoxPDF" not "PDFKit fallback"

### 2. Complex PDF with Formatting

**Test:** Import PDF with:
- Multi-column layout
- Headers/footers
- Footnotes
- Tables

**Expected:** Clean paragraph extraction
**Check:** Paragraphs should be properly segmented

### 3. TOC Extraction

**Test:** Import PDF with embedded TOC
**Expected:** TOC entries correctly extracted
**Check:** Navigation to TOC items works

### 4. Fallback to PDFKit

**Test:** If VoxPDF fails (corrupt PDF, missing features)
**Expected:** Graceful fallback to PDFKit
**Check:** Console shows fallback message, extraction still works

## Bug Reporting to VoxPDF Session

When encountering VoxPDF issues:

1. **Capture the error:**
   - Exact error message
   - Console logs
   - PDF file characteristics (if possible, share file)

2. **Document the issue:**
   - What operation failed (text extraction, TOC, etc.)
   - Input PDF characteristics
   - Expected vs actual behavior

3. **Communicate to VoxPDF session:**
   - Share error details
   - Wait for fix
   - Rebuild XCFramework
   - Re-copy to Frameworks/
   - Re-test

## Iteration Workflow

```bash
# After VoxPDF session provides fix:

# 1. Rebuild VoxPDF
cd ../VoxPDF/voxpdf-core
./scripts/build-ios.sh
./scripts/create-xcframework.sh

# 2. Update framework in Listen2
cd /Users/zachswift/projects/Listen2
rm -rf Frameworks/VoxPDFCore.xcframework
cp -R ../VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework Frameworks/

# 3. Clean Xcode build
cd Listen2/Listen2
rm -rf ~/Library/Developer/Xcode/DerivedData/Listen2-*

# 4. Rebuild and test
xcodebuild clean build -scheme Listen2 -destination 'platform=iOS Simulator,name=iPhone 15'

# 5. Re-run manual tests
```

## Known Issues

(Document issues as they arise during integration)

- Issue 1: [Description]
  - Status: [Reported to VoxPDF / Fixed / Workaround]
  - Workaround: [If applicable]

- Issue 2: [Description]
  - Status: [Reported to VoxPDF / Fixed / Workaround]
  - Workaround: [If applicable]
