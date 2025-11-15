# Framework Update Guide

This guide explains how to keep the frameworks (sherpa-onnx and VoxPDF) up-to-date in the Listen2 project.

## The Problem

The Listen2 app uses two custom-built frameworks:
- **sherpa-onnx.xcframework** - TTS engine with normalized text and phoneme alignment
- **VoxPDFCore.xcframework** - PDF text extraction with paragraph detection

When changes are made to either framework's source code, they need to be rebuilt and copied into the Listen2 project.

**Previous workflow problems:**
- ❌ Manually copying frameworks is error-prone
- ❌ Easy to forget to update after source changes
- ❌ Stale frameworks cause hard-to-debug issues
- ❌ No visibility into which framework version is deployed

## The Solution

Use the `update-frameworks.sh` script to automate framework updates.

## Quick Start

### Manual Update (Recommended)

When you've made changes to source code and want to use them in Listen2:

```bash
cd /Users/zachswift/projects/Listen2

# Update both frameworks (default)
./scripts/update-frameworks.sh

# Update only VoxPDF
./scripts/update-frameworks.sh --framework voxpdf

# Update only sherpa-onnx
./scripts/update-frameworks.sh --framework sherpa

# Rebuild + update both frameworks
./scripts/update-frameworks.sh --build

# Rebuild + update VoxPDF only
./scripts/update-frameworks.sh --build --framework voxpdf

# Force copy even if timestamps match
./scripts/update-frameworks.sh --force
```

After running the script:
1. Clean build folder in Xcode (`⇧⌘K`)
2. Build and run (`⌘R`)

### Automatic Update (Optional)

To automatically update the framework every time you build in Xcode:

1. Open `Listen2.xcodeproj` in Xcode
2. Select the "Listen2" target
3. Go to **Build Phases** tab
4. Click **+** → **New Run Script Phase**
5. Name it "Update sherpa-onnx Framework"
6. **IMPORTANT:** Drag it to be the **FIRST** phase (before "Compile Sources")
7. Add this script:

```bash
# Update sherpa-onnx framework if needed
"${PROJECT_DIR}/scripts/update-frameworks.sh"

# Exit with success even if framework is already up-to-date
exit 0
```

8. Check **"Show environment variables in build log"** for debugging

**Pros:**
- ✅ Never forget to update framework
- ✅ Always use latest sherpa-onnx changes
- ✅ Works for all team members

**Cons:**
- ⚠️ Adds ~1 second to every build (timestamp check is fast)
- ⚠️ Full rebuild adds ~5 minutes if you use `--build`

### Recommended Workflow

**For daily development:**
```bash
# Just use manual updates when needed
./scripts/update-frameworks.sh
```

**For CI/CD or team environments:**
Add the automatic build phase to ensure everyone uses the correct framework.

## Script Options

### `update-frameworks.sh`
Copies frameworks from their build directories to Listen2.

**Checks:**
- ✅ Framework exists at source location
- ✅ Timestamps match (skips copy if destination is newer)
- ✅ Displays git commit info
- ✅ Verifies copy succeeded

**Usage:**
```bash
./scripts/update-frameworks.sh                    # Update all frameworks
./scripts/update-frameworks.sh --framework voxpdf # Update VoxPDF only
./scripts/update-frameworks.sh --framework sherpa # Update sherpa-onnx only
./scripts/update-frameworks.sh --force            # Force copy
./scripts/update-frameworks.sh --build            # Rebuild + copy
```

### `update-frameworks.sh --build`
Rebuilds the iOS frameworks AND copies them.

**Use when:**
- You've modified sherpa-onnx C++ code
- You've updated espeak-ng or piper-phonemize
- You've modified VoxPDF Rust code
- You've updated VoxPDF paragraph detection
- You want to ensure a clean build

**Time:**
- sherpa-onnx: ~5-6 minutes (full rebuild)
- VoxPDF: ~1-2 minutes (Rust compile + xcframework)

### `update-frameworks.sh --force`
Forces copy even if timestamps suggest destination is up-to-date.

**Use when:**
- You suspect the framework is corrupted
- You've manually modified the framework
- Timestamps are misleading

### `update-frameworks.sh --framework <name>`
Updates only a specific framework.

**Options:**
- `all` (default) - Update both sherpa-onnx and VoxPDF
- `sherpa` - Update sherpa-onnx only
- `voxpdf` - Update VoxPDF only

## Troubleshooting

### "Source framework not found"

**Problem:** Script can't find sherpa-onnx framework

**Solution:**
```bash
# Build it first
./scripts/update-frameworks.sh --build

# Or manually build sherpa-onnx
cd ~/projects/sherpa-onnx
./build-ios.sh
```

### "Destination framework is already up-to-date"

**Problem:** Script skipped copy because timestamps match

**Solutions:**
```bash
# Force the copy
./scripts/update-frameworks.sh --force

# Or rebuild + copy
./scripts/update-frameworks.sh --build
```

### Framework version mismatch

**Problem:** App behavior suggests old framework

**Diagnosis:**
```bash
# Check current framework version
cd ~/projects/Listen2
./scripts/update-frameworks.sh

# Look for commit hash in output
```

**Solution:**
```bash
# Rebuild from scratch
cd ~/projects/sherpa-onnx
rm -rf build-ios
./build-ios.sh

# Copy fresh framework
cd ~/projects/Listen2
./scripts/update-frameworks.sh --force
```

## Framework Locations

### sherpa-onnx Framework

**Source:**
```
~/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework
```

This is the BUILD OUTPUT from sherpa-onnx. Contains:
- `ios-arm64/` - Device architecture
- `ios-arm64_x86_64-simulator/` - Simulator architectures
- `Info.plist` - Framework metadata

**Destination:**
```
~/projects/Listen2/Frameworks/sherpa-onnx.xcframework
```

This is what Xcode links against. MUST match the source or you'll get:
- Stale normalized text
- Corrupt phoneme durations
- Missing features

### VoxPDF Framework

**Source:**
```
~/projects/VoxPDF/voxpdf-core/build/VoxPDFCore.xcframework
```

This is the BUILD OUTPUT from VoxPDF. Contains:
- `ios-arm64/` - Device architecture
- `ios-arm64_x86_64-simulator/` - Simulator architectures (combined fat library)
- Headers for C FFI interface

**Destination:**
```
~/projects/Listen2/Frameworks/VoxPDFCore.xcframework
```

This is what Xcode links against. MUST match the source or you'll get:
- Missing paragraph detection improvements
- Outdated text extraction logic
- Missing font size tracking

## Best Practices

### ✅ DO
- Run `update-frameworks.sh` after modifying sherpa-onnx or VoxPDF
- Clean build folder (`⇧⌘K`) after framework updates
- Commit framework updates with descriptive messages
- Document which framework commits you're using
- Use `--framework` to update only what changed

### ❌ DON'T
- Manually copy frameworks (use the script)
- Modify frameworks in `Listen2/Frameworks/` directly
- Skip framework updates after source changes
- Assume the frameworks auto-update

## Verification

After updating the framework, verify it works:

### 1. Check build logs
Look for:
```
[SherpaOnnx] Extracted normalized text: '<actual paragraph text>'
[SherpaOnnx] First phoneme duration: <reasonable number> samples
```

### 2. Run tests
```bash
cd Listen2/Listen2
xcodebuild test -scheme Listen2 -destination 'platform=iOS,name=iPhone (2)'
```

### 3. Test on device
- Word highlighting should be smooth
- No "stuck" or "glitching" behavior
- Normalized text should be unique per paragraph

## Related Documentation

- [WCEIL_SESSION_HANDOFF.md](WCEIL_SESSION_HANDOFF.md) - w_ceil model verification
- [HANDOFF_2025-11-14_NORMALIZED_TEXT.md](HANDOFF_2025-11-14_NORMALIZED_TEXT.md) - Normalized text integration
- [sherpa-onnx/WCEIL_VERIFICATION.md](../../sherpa-onnx/WCEIL_VERIFICATION.md) - Framework capabilities

## History

**2025-11-14:** Created automated framework update script
- Fixes: Stale framework causing normalized text bugs
- Impact: Saves hours of debugging time
- Commit: 7661f28
