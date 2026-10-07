#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/build-release"
BUILD_DIR="$OUTPUT_DIR/build"
APP_PATH="$BUILD_DIR/QuickRecorder.app"
DMG_PATH="$OUTPUT_DIR/QuickRecorder-1.8.2-arm64.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-root"

rm -rf "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/QuickRecorder.xcodeproj" \
  -scheme QuickRecorder \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build

# Ad-hoc builds must re-sign embedded frameworks, or hardened runtime library
# validation rejects Sparkle's original Developer ID signature at launch
# (dyld: "mapping process and mapped file ... have different Team IDs").
find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 |
  xargs -0 -I{} codesign --force --deep --sign - --timestamp=none {}
codesign --force --sign - --timestamp=none "$APP_PATH"

test -d "$APP_PATH"
ditto "$APP_PATH" "$STAGING_DIR/QuickRecorder.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "QuickRecorder 1.8.2" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Created $DMG_PATH"
