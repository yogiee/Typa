#!/bin/bash
# Build TextPad-NXG (Release) and package as a DMG with drag-to-Applications layout.
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="TextPad-NXG"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# Build first if app isn't there
if [ ! -d "$APP_PATH" ]; then
  echo "▶ App not found; running build..."
  "$PROJECT_ROOT/scripts/build-app.sh"
fi

# Read version from the built app's Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")

DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_OUT="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "▶ Staging $APP_NAME $VERSION..."
rm -rf "$DMG_STAGING" "$DMG_OUT"
mkdir -p "$DMG_STAGING"

# Copy the .app into the staging dir, then create an Applications symlink so the
# user can drag-to-install in the Finder window that opens when the DMG mounts.
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "▶ Creating compressed DMG..."
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUT" >/dev/null

rm -rf "$DMG_STAGING"

SIZE=$(du -h "$DMG_OUT" | awk '{print $1}')
echo "✓ DMG ($SIZE): $DMG_OUT"
