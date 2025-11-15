#!/bin/bash
#
# update-frameworks.sh
# Copies the latest sherpa-onnx framework from the build directory to Listen2
#
# Usage:
#   ./scripts/update-frameworks.sh           # Copy from default location
#   ./scripts/update-frameworks.sh --force   # Force copy even if timestamps match
#   ./scripts/update-frameworks.sh --build   # Rebuild sherpa-onnx first, then copy
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SHERPA_SOURCE_DIR="$HOME/projects/sherpa-onnx"
FRAMEWORK_SOURCE="$SHERPA_SOURCE_DIR/build-ios/sherpa-onnx.xcframework"
FRAMEWORK_DEST="$PROJECT_ROOT/Frameworks/sherpa-onnx.xcframework"

# Parse arguments
FORCE_COPY=false
BUILD_FIRST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_COPY=true
            shift
            ;;
        --build)
            BUILD_FIRST=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--force] [--build]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  sherpa-onnx Framework Updater${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Build sherpa-onnx if requested
if [ "$BUILD_FIRST" = true ]; then
    echo -e "${YELLOW}📦 Building sherpa-onnx framework...${NC}"

    if [ ! -d "$SHERPA_SOURCE_DIR" ]; then
        echo -e "${RED}❌ sherpa-onnx source not found at: $SHERPA_SOURCE_DIR${NC}"
        exit 1
    fi

    cd "$SHERPA_SOURCE_DIR"

    # Check git status
    echo -e "${BLUE}Git status:${NC}"
    git log --oneline -1
    echo ""

    # Build
    ./build-ios.sh

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Build failed!${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Build completed${NC}"
    echo ""
fi

# Check if source framework exists
if [ ! -d "$FRAMEWORK_SOURCE" ]; then
    echo -e "${RED}❌ Source framework not found at:${NC}"
    echo -e "   $FRAMEWORK_SOURCE"
    echo ""
    echo -e "${YELLOW}💡 Run with --build to build it first:${NC}"
    echo -e "   $0 --build"
    exit 1
fi

# Get framework version info
cd "$SHERPA_SOURCE_DIR"
SHERPA_COMMIT=$(git log --oneline -1 --no-decorate)
SHERPA_BRANCH=$(git branch --show-current)

echo -e "${BLUE}Source Framework:${NC}"
echo -e "  Location: $FRAMEWORK_SOURCE"
echo -e "  Branch:   $SHERPA_BRANCH"
echo -e "  Commit:   $SHERPA_COMMIT"
echo ""

# Check if destination exists and compare timestamps
if [ -d "$FRAMEWORK_DEST" ] && [ "$FORCE_COPY" = false ]; then
    SOURCE_TIME=$(stat -f %m "$FRAMEWORK_SOURCE")
    DEST_TIME=$(stat -f %m "$FRAMEWORK_DEST")

    if [ "$SOURCE_TIME" -le "$DEST_TIME" ]; then
        echo -e "${YELLOW}⚠️  Destination framework is already up-to-date${NC}"
        echo -e "   (Source timestamp: $(date -r $SOURCE_TIME))"
        echo -e "   (Dest timestamp:   $(date -r $DEST_TIME))"
        echo ""
        echo -e "${BLUE}ℹ️  Use --force to copy anyway${NC}"
        exit 0
    fi
fi

# Copy framework
echo -e "${YELLOW}📋 Copying framework...${NC}"

# Remove old framework if it exists
if [ -d "$FRAMEWORK_DEST" ]; then
    rm -rf "$FRAMEWORK_DEST"
fi

# Create Frameworks directory if it doesn't exist
mkdir -p "$(dirname "$FRAMEWORK_DEST")"

# Copy new framework
cp -R "$FRAMEWORK_SOURCE" "$FRAMEWORK_DEST"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Copy failed!${NC}"
    exit 1
fi

# Verify copy
if [ ! -f "$FRAMEWORK_DEST/Info.plist" ]; then
    echo -e "${RED}❌ Framework copy incomplete (Info.plist missing)${NC}"
    exit 1
fi

# Get framework size
FRAMEWORK_SIZE=$(du -sh "$FRAMEWORK_DEST" | cut -f1)

echo -e "${GREEN}✅ Framework updated successfully${NC}"
echo ""
echo -e "${BLUE}Destination:${NC}"
echo -e "  Location: $FRAMEWORK_DEST"
echo -e "  Size:     $FRAMEWORK_SIZE"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Framework update complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}💡 Next steps:${NC}"
echo -e "   1. Clean build folder in Xcode (⇧⌘K)"
echo -e "   2. Build and run your app (⌘R)"
echo ""
