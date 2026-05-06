#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

mkdir -p "$BUILD_DIR"

echo "▶ Building TextPad-NXG (Release)..."
xcodebuild \
  -project "$PROJECT_ROOT/TextPad-NXG.xcodeproj" \
  -scheme "TextPad-NXG" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/.derived" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  build

echo "✓ Built: $BUILD_DIR/TextPad-NXG.app"
