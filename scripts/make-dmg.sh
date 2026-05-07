#!/bin/bash
# Build Typa (Release) and package as a DMG with drag-to-Applications layout.
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Typa"
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

# Sparkle EdDSA signature for appcast.xml. Sparkle's sign_update tool ships
# inside the resolved package artifacts; print the values to paste into the
# new <item> block in appcast.xml.
SIGN_UPDATE="$PROJECT_ROOT/build/.derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
if [ -x "$SIGN_UPDATE" ]; then
  echo ""
  echo "▶ Signing DMG for Sparkle..."
  EDDSA_LINE=$("$SIGN_UPDATE" "$DMG_OUT" 2>/dev/null || true)
  EDDSA_SIG=$(echo "$EDDSA_LINE" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//; s/"$//')
  DMG_BYTES=$(stat -f%z "$DMG_OUT")
  if [ -n "$EDDSA_SIG" ]; then
    echo "  Paste these into a new <item> block in appcast.xml:"
    echo "    sparkle:shortVersionString=\"$VERSION\""
    echo "    sparkle:edSignature=\"$EDDSA_SIG\""
    echo "    length=\"$DMG_BYTES\""
  else
    echo "  sign_update returned no signature. Have you generated keys?"
    echo "    $SIGN_UPDATE_DIR/generate_keys"
  fi
else
  echo ""
  echo "⚠️  Sparkle sign_update not found at:"
  echo "      $SIGN_UPDATE"
  echo "   First-time setup: open the .xcodeproj once so SwiftPM resolves"
  echo "   Sparkle, then generate the EdDSA key pair:"
  echo "      \$(dirname $SIGN_UPDATE)/generate_keys"
  echo "   Paste the printed public key into Typa/App/Info.plist"
  echo "   under SUPublicEDKey, then re-run this script."
fi
