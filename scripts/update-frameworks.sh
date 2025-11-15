#!/bin/bash
#
# update-frameworks.sh
# Updates Listen2 frameworks (sherpa-onnx and/or VoxPDF)
#
# Usage:
#   ./scripts/update-frameworks.sh                    # Update all frameworks
#   ./scripts/update-frameworks.sh --force            # Force copy even if timestamps match
#   ./scripts/update-frameworks.sh --build            # Rebuild frameworks first, then copy
#   ./scripts/update-frameworks.sh --framework voxpdf # Update only VoxPDF
#   ./scripts/update-frameworks.sh --framework sherpa # Update only sherpa-onnx
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
VOXPDF_SOURCE_DIR="$HOME/projects/VoxPDF/voxpdf-core"

# Parse arguments
FORCE_COPY=false
BUILD_FIRST=false
FRAMEWORK="all"  # Options: all, sherpa, voxpdf

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
        --framework)
            FRAMEWORK="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--force] [--build] [--framework <all|sherpa|voxpdf>]"
            exit 1
            ;;
    esac
done

# Function to update sherpa-onnx framework
update_sherpa_onnx() {
    local FRAMEWORK_SOURCE="$SHERPA_SOURCE_DIR/build-ios/sherpa-onnx.xcframework"
    local FRAMEWORK_DEST="$PROJECT_ROOT/Frameworks/sherpa-onnx.xcframework"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  sherpa-onnx Framework Updater${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Build sherpa-onnx if requested
    if [ "$BUILD_FIRST" = true ]; then
        echo -e "${YELLOW}📦 Building sherpa-onnx framework...${NC}"

        if [ ! -d "$SHERPA_SOURCE_DIR" ]; then
            echo -e "${RED}❌ sherpa-onnx source not found at: $SHERPA_SOURCE_DIR${NC}"
            return 1
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
            return 1
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
        echo -e "   $0 --build --framework sherpa"
        return 1
    fi

    # Get framework version info
    cd "$SHERPA_SOURCE_DIR"
    local SHERPA_COMMIT=$(git log --oneline -1 --no-decorate)
    local SHERPA_BRANCH=$(git branch --show-current)

    echo -e "${BLUE}Source Framework:${NC}"
    echo -e "  Location: $FRAMEWORK_SOURCE"
    echo -e "  Branch:   $SHERPA_BRANCH"
    echo -e "  Commit:   $SHERPA_COMMIT"
    echo ""

    # Check if destination exists and compare timestamps
    if [ -d "$FRAMEWORK_DEST" ] && [ "$FORCE_COPY" = false ]; then
        local SOURCE_TIME=$(stat -f %m "$FRAMEWORK_SOURCE")
        local DEST_TIME=$(stat -f %m "$FRAMEWORK_DEST")

        if [ "$SOURCE_TIME" -le "$DEST_TIME" ]; then
            echo -e "${YELLOW}⚠️  Destination framework is already up-to-date${NC}"
            echo -e "   (Source timestamp: $(date -r $SOURCE_TIME))"
            echo -e "   (Dest timestamp:   $(date -r $DEST_TIME))"
            echo ""
            echo -e "${BLUE}ℹ️  Use --force to copy anyway${NC}"
            return 0
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
        return 1
    fi

    # Verify copy
    if [ ! -f "$FRAMEWORK_DEST/Info.plist" ]; then
        echo -e "${RED}❌ Framework copy incomplete (Info.plist missing)${NC}"
        return 1
    fi

    # Get framework size
    local FRAMEWORK_SIZE=$(du -sh "$FRAMEWORK_DEST" | cut -f1)

    echo -e "${GREEN}✅ sherpa-onnx framework updated successfully${NC}"
    echo ""
    echo -e "${BLUE}Destination:${NC}"
    echo -e "  Location: $FRAMEWORK_DEST"
    echo -e "  Size:     $FRAMEWORK_SIZE"
    echo ""
}

# Function to update VoxPDF framework
update_voxpdf() {
    local FRAMEWORK_SOURCE="$VOXPDF_SOURCE_DIR/build/VoxPDFCore.xcframework"
    local FRAMEWORK_DEST="$PROJECT_ROOT/Frameworks/VoxPDFCore.xcframework"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  VoxPDF Framework Updater${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Build VoxPDF if requested
    if [ "$BUILD_FIRST" = true ]; then
        echo -e "${YELLOW}📦 Building VoxPDF framework...${NC}"

        if [ ! -d "$VOXPDF_SOURCE_DIR" ]; then
            echo -e "${RED}❌ VoxPDF source not found at: $VOXPDF_SOURCE_DIR${NC}"
            return 1
        fi

        cd "$VOXPDF_SOURCE_DIR"

        # Check git status
        echo -e "${BLUE}Git status:${NC}"
        git log --oneline -1
        echo ""

        # Build for iOS
        ./scripts/build-ios.sh

        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Build failed!${NC}"
            return 1
        fi

        # Create xcframework
        ./scripts/create-xcframework.sh

        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ XCFramework creation failed!${NC}"
            return 1
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
        echo -e "   $0 --build --framework voxpdf"
        return 1
    fi

    # Get framework version info
    cd "$VOXPDF_SOURCE_DIR"
    local VOXPDF_COMMIT=$(git log --oneline -1 --no-decorate)
    local VOXPDF_BRANCH=$(git branch --show-current)

    echo -e "${BLUE}Source Framework:${NC}"
    echo -e "  Location: $FRAMEWORK_SOURCE"
    echo -e "  Branch:   $VOXPDF_BRANCH"
    echo -e "  Commit:   $VOXPDF_COMMIT"
    echo ""

    # Check if destination exists and compare timestamps
    if [ -d "$FRAMEWORK_DEST" ] && [ "$FORCE_COPY" = false ]; then
        local SOURCE_TIME=$(stat -f %m "$FRAMEWORK_SOURCE")
        local DEST_TIME=$(stat -f %m "$FRAMEWORK_DEST")

        if [ "$SOURCE_TIME" -le "$DEST_TIME" ]; then
            echo -e "${YELLOW}⚠️  Destination framework is already up-to-date${NC}"
            echo -e "   (Source timestamp: $(date -r $SOURCE_TIME))"
            echo -e "   (Dest timestamp:   $(date -r $DEST_TIME))"
            echo ""
            echo -e "${BLUE}ℹ️  Use --force to copy anyway${NC}"
            return 0
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
        return 1
    fi

    # Verify copy (VoxPDF xcframework may not have Info.plist at root)
    if [ ! -d "$FRAMEWORK_DEST" ]; then
        echo -e "${RED}❌ Framework copy incomplete${NC}"
        return 1
    fi

    # Get framework size
    local FRAMEWORK_SIZE=$(du -sh "$FRAMEWORK_DEST" | cut -f1)

    echo -e "${GREEN}✅ VoxPDF framework updated successfully${NC}"
    echo ""
    echo -e "${BLUE}Destination:${NC}"
    echo -e "  Location: $FRAMEWORK_DEST"
    echo -e "  Size:     $FRAMEWORK_SIZE"
    echo ""
}

# Main execution
case $FRAMEWORK in
    sherpa)
        update_sherpa_onnx
        ;;
    voxpdf)
        update_voxpdf
        ;;
    all)
        update_sherpa_onnx
        echo ""
        update_voxpdf
        ;;
    *)
        echo -e "${RED}Invalid framework: $FRAMEWORK${NC}"
        echo "Valid options: all, sherpa, voxpdf"
        exit 1
        ;;
esac

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Framework update complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}💡 Next steps:${NC}"
echo -e "   1. Clean build folder in Xcode (⇧⌘K)"
echo -e "   2. Build and run your app (⌘R)"
echo ""
