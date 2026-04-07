#!/bin/bash
# Builds ClaudeMulti as a proper macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ClaudeMulti"
APP_BUNDLE="$SCRIPT_DIR/build/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building $APP_NAME..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

# Copy executable
cp ".build/release/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "Sources/ClaudeMulti/Resources/Info.plist" "$CONTENTS/Info.plist"

# Ad-hoc codesign for stable identity (required for macOS permissions)
echo "Codesigning..."
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open $APP_BUNDLE"
