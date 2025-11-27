# Word Highlighting Fix Session - November 16, 2024

## What We Accomplished

### Found the Real Root Cause
- **Initial observation:** Word highlighting was off by 2 characters ("CHAPTER" → "APTER")
- **Deep investigation revealed:** espeak-ng initializes `count_characters` to -1 in `readclause.c:996`
- **The mechanism:**
  - `count_characters` starts at -1
  - First `GetC()` call increments it to 0
  - Second `GetC()` call increments it to 1
  - By the time actual text processing begins, it's at 2
  - This causes all character positions to be offset by 2

### Applied a Fix
- Located where positions are captured in `/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp`
- Added offset compensation: `word.text_position = events->text_position > 0 ? events->text_position - 1 : 0;`
- Rebuilt piper-phonemize library
- Updated sherpa-onnx framework with the fix
- Framework has been built and copied to Listen2

### Key Files Modified
- `/Users/zachswift/projects/piper-phonemize/src/phonemize.cpp` (line 197) - Applied position offset fix
- Multiple rebuilds of libpiper_phonemize.a
- Updated sherpa-onnx.xcframework

### Important Discoveries
1. espeak-ng's complex initialization causes systematic position offset
2. The offset appears to be by design for handling BOMs or initial processing
3. Modifying espeak-ng internals would be risky - better to compensate in piper-phonemize
4. Build system has multiple layers where caching can occur

## What to Test

1. **Delete app from device** (important to avoid cached libraries)
2. **Clean Build Folder in Xcode** (⇧⌘K)
3. **Build and run** the app
4. **Test with "CHAPTER 2"** - should highlight "CHAPTER" correctly, not "APTER"
5. **Check debug logs** - look for positions starting at 0, not 2

## Potential Next Steps

### If Still Off by 1
- Current fix subtracts 1, but original issue was off by 2
- May need to change offset to -2 in phonemize.cpp line 197
- Watch DEBUG logs to see what raw positions espeak reports

### If Working Correctly
1. Test with various text:
   - Uppercase: "HELLO WORLD"
   - Lowercase: "hello world"
   - Mixed: "Hello World"
   - Numbers: "Chapter 123"
   - Punctuation: "Hello, world!"

2. Consider adding unit tests in sherpa-onnx

3. Document the workaround properly in code comments

### Longer Term
- Consider investigating why espeak has this initialization pattern
- Could potentially fix in espeak-ng fork, but risky
- Add regression tests to catch if espeak behavior changes

## Key Insight
The issue wasn't just "positions are off by 2" - it's that espeak-ng's initialization sequence (starting at -1 and reading ahead) is intentional behavior, likely for handling edge cases. Our fix compensates for this rather than changing core behavior.

## Workshop Context Saved
- Decision: Fixed character position offset by compensating in piper-phonemize
- Gotcha: espeak-ng text_position values start at 1 or 2, not 0
- Note: Using -1 offset, may need -2 based on testing results