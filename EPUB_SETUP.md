# EPUB Support Setup

EPUB support has been implemented in Listen2 using a lightweight, native approach. To complete the setup, you need to add one Swift package dependency.

## Add ZIPFoundation Dependency

ZIPFoundation is a lightweight, pure-Swift library for ZIP file extraction (which EPUBs are).

### Steps to Add in Xcode:

1. **Open the project in Xcode**
   ```bash
   open Listen2/Listen2.xcodeproj
   ```

2. **Add Package Dependency**
   - Select the "Listen2" project in the navigator (blue project icon)
   - Click on "Project" → "Listen2" (under PROJECT, not TARGETS)
   - Go to the "Package Dependencies" tab
   - Click the "+" button at the bottom
   - Enter the URL: `https://github.com/weichsel/ZIPFoundation.git`
   - Dependency Rule: "Up to Next Major Version" `0.9.0`
   - Click "Add Package"
   - Wait for package resolution (latest version is 0.9.20)

3. **Link ZIPFoundation to Target** ⚠️ CRITICAL STEP
   - Select the "Listen2" target (under TARGETS)
   - Go to the "General" tab
   - Scroll down to "Frameworks, Libraries, and Embedded Content"
   - Click the "+" button
   - Under "Swift Packages", select "ZIPFoundation"
   - Click "Add"

4. **Build the Project**
   - Press ⌘B to build
   - Should compile successfully

## How EPUB Extraction Works

```
EPUB File (.epub)
    ↓
1. Unzip (ZIPFoundation)
    ↓
2. Read META-INF/container.xml → Find content.opf location
    ↓
3. Parse content.opf (XMLParser) → Get spine (reading order)
    ↓
4. Extract text from XHTML files in spine order
    ↓
5. Strip HTML tags, decode entities
    ↓
6. Return paragraphs for TTS
```

## What's Included

- **EPUBExtractor.swift** - Core EPUB extraction logic
  - ZIP extraction using ZIPFoundation
  - XML parsing with native XMLParser
  - HTML tag stripping with regex
  - HTML entity decoding

- **DocumentProcessor.swift** - Integration with existing PDF pipeline

- **LibraryView.swift** - Updated file picker to accept `.epub` files

## Testing

Once ZIPFoundation is added:

1. **Build the project** (⌘B)
2. **Run in simulator** (⌘R)
3. **Import an EPUB file**:
   - Tap "+" → "Import File"
   - File picker now shows both PDF and EPUB files
   - Select an EPUB
4. **Verify extraction**:
   - Document should appear in library
   - Tap to open reader
   - Text should be readable and flow correctly

## Architecture

This implementation follows the Voice Dream Reader approach:
- **Zero heavy dependencies** - Only ZIPFoundation for ZIP extraction
- **Native iOS frameworks** - XMLParser, Foundation
- **Lightweight** - ~200 lines of code
- **TTS-optimized** - Extracts clean text, removes formatting

## Future Enhancements

Potential improvements:
- Better HTML entity decoding
- Handle embedded images (for description)
- Parse CSS for better formatting hints
- Support for EPUB 3 features
- Better error messages for malformed EPUBs
