#!/bin/bash

# Build script for FLEX dylib injection
# This script builds FLEX as a dynamic library directly using clang

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/Build"
OBJ_DIR="$BUILD_DIR/Objects"
DYLIB_NAME="FLEX.dylib"
OUTPUT_DYLIB="$BUILD_DIR/$DYLIB_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building FLEX as injectable dylib...${NC}"

# Check if we're on macOS with Xcode
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}Error: xcrun not found. Please install Xcode.${NC}"
    exit 1
fi

# Get SDK path
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
if [ -z "$SDK_PATH" ]; then
    echo -e "${RED}Error: Could not find iOS SDK.${NC}"
    exit 1
fi

echo -e "${BLUE}Using SDK: $SDK_PATH${NC}"

# Detect architecture (default to arm64 for device, or x86_64 for simulator)
ARCH="${1:-arm64}"
if [ "$ARCH" = "simulator" ] || [ "$ARCH" = "x86_64" ]; then
    ARCH="x86_64"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
    echo -e "${YELLOW}Building for iOS Simulator (x86_64)${NC}"
else
    ARCH="arm64"
    echo -e "${YELLOW}Building for iOS Device (arm64)${NC}"
fi

# Clean previous builds
echo -e "${BLUE}Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$OBJ_DIR"

# Find all source files
echo -e "${BLUE}Collecting source files...${NC}"
SOURCES=()
while IFS= read -r -d '' file; do
    SOURCES+=("$file")
done < <(find "$PROJECT_DIR/Classes" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.c" \) ! -path "*/Headers/*" -print0)

# Check if dylib entry point is included
HAS_ENTRY=false
for src in "${SOURCES[@]}"; do
    if [[ "$src" == *"FLEXDylibEntry.m" ]]; then
        HAS_ENTRY=true
        break
    fi
done

if [ "$HAS_ENTRY" = true ]; then
    echo -e "${GREEN}Found FLEXDylibEntry.m${NC}"
else
    if [ -f "$PROJECT_DIR/Classes/FLEXDylibEntry.m" ]; then
        SOURCES+=("$PROJECT_DIR/Classes/FLEXDylibEntry.m")
        echo -e "${GREEN}Added FLEXDylibEntry.m${NC}"
    else
        echo -e "${RED}Warning: FLEXDylibEntry.m not found!${NC}"
    fi
fi

echo -e "${GREEN}Found ${#SOURCES[@]} source files${NC}"

# Compiler settings
MIN_IOS_VERSION="9.0"
CC="$(xcrun --find clang)"
CFLAGS=(
    -arch "$ARCH"
    -isysroot "$SDK_PATH"
    -mios-version-min="$MIN_IOS_VERSION"
    -fobjc-arc
    -fobjc-weak
    -fmodules
    -Wno-unsupported-availability-guard
    -Wno-deprecated-declarations
    -Wno-strict-prototypes
    -O2
    -g
    -fPIC
)

# Framework and library paths
FRAMEWORKS=(
    -framework Foundation
    -framework UIKit
    -framework CoreGraphics
    -framework ImageIO
    -framework QuartzCore
    -framework WebKit
    -framework Security
    -framework SceneKit
)

LIBS=(
    -lz
    -lsqlite3
    -lc++
)

# Include directories - add all subdirectories
INCLUDES=(-I"$SDK_PATH/usr/include")
while IFS= read -r -d '' dir; do
    INCLUDES+=(-I"$dir")
done < <(find "$PROJECT_DIR/Classes" -type d -print0)

# Compile all source files
echo -e "${BLUE}Compiling source files...${NC}"
OBJECT_FILES=()
FAILED=0

for src in "${SOURCES[@]}"; do
    obj_file="$OBJ_DIR/$(basename "$src" | sed 's/\.[^.]*$/.o/')"
    OBJECT_FILES+=("$obj_file")
    
    # Determine if it's C++ or Objective-C++
    if [[ "$src" == *.mm ]] || [[ "$src" == *.cpp ]]; then
        LANG_FLAGS=(-x objective-c++ -std=gnu++11)
    elif [[ "$src" == *.c ]]; then
        LANG_FLAGS=(-x c)
    else
        LANG_FLAGS=(-x objective-c)
    fi
    
    echo -e "  Compiling: $(basename "$src")"
    if ! "$CC" "${CFLAGS[@]}" "${LANG_FLAGS[@]}" "${INCLUDES[@]}" -c "$src" -o "$obj_file" 2>&1 | grep -E "(error|Error)" || true; then
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo -e "${RED}Failed to compile: $src${NC}"
            FAILED=$((FAILED + 1))
        fi
    fi
done

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed to compile $FAILED file(s)${NC}"
    exit 1
fi

# Link the dylib
echo -e "${BLUE}Linking dylib...${NC}"
"$CC" \
    -arch "$ARCH" \
    -isysroot "$SDK_PATH" \
    -mios-version-min="$MIN_IOS_VERSION" \
    -dynamiclib \
    -install_name "@rpath/$DYLIB_NAME" \
    -compatibility_version 1.0 \
    -current_version 1.0 \
    "${OBJECT_FILES[@]}" \
    "${FRAMEWORKS[@]}" \
    "${LIBS[@]}" \
    -o "$OUTPUT_DYLIB"

if [ ! -f "$OUTPUT_DYLIB" ]; then
    echo -e "${RED}Error: Failed to create dylib${NC}"
    exit 1
fi

# Code sign (optional, but recommended)
if command -v codesign &> /dev/null; then
    echo -e "${BLUE}Code signing dylib...${NC}"
    # Try to find a development certificate
    CERT=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
    
    if [ -n "$CERT" ]; then
        echo -e "${GREEN}Signing with: $CERT${NC}"
        if [ -f "$PROJECT_DIR/entitlements.plist" ]; then
            codesign --force --sign "$CERT" --entitlements "$PROJECT_DIR/entitlements.plist" "$OUTPUT_DYLIB" 2>/dev/null || \
            codesign --force --sign "$CERT" "$OUTPUT_DYLIB" 2>/dev/null || \
            echo -e "${YELLOW}Warning: Code signing failed, but dylib was created${NC}"
        else
            codesign --force --sign "$CERT" "$OUTPUT_DYLIB" 2>/dev/null || \
            echo -e "${YELLOW}Warning: Code signing failed, but dylib was created${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: No code signing certificate found. You may need to sign manually.${NC}"
        echo -e "${YELLOW}  codesign --force --sign \"Apple Development: Your Name\" --entitlements entitlements.plist \"$OUTPUT_DYLIB\"${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Build Complete!"
echo "==========================================${NC}"
echo ""
echo -e "Dylib location: ${GREEN}$OUTPUT_DYLIB${NC}"
echo -e "Size: $(du -h "$OUTPUT_DYLIB" | cut -f1)"
echo ""
echo -e "To inject with Frida:"
echo -e "  ${YELLOW}frida -U -f com.example.app -l \"$OUTPUT_DYLIB\"${NC}"
echo ""
