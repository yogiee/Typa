#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

mkdir -p "$BUILD_DIR"

echo "▶ Building Typa (Release)..."
xcodebuild \
  -project "$PROJECT_ROOT/Typa.xcodeproj" \
  -scheme "Typa" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/.derived" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  build

echo "✓ Built: $BUILD_DIR/Typa.app"
