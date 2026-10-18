#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT_DIR="$ROOT_DIR/releases"
APP_BUNDLE="$ROOT_DIR/dist/RayNeo Steady.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
STAGING="$ROOT_DIR/.build/dmg-staging-$VERSION"
DMG="$OUTPUT_DIR/RayNeo Steady $VERSION.dmg"
if [[ -e "$DMG" ]]; then
  echo "A DMG already exists at $DMG; move it aside before creating another." >&2
  exit 2
fi
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "$STAGING" "$OUTPUT_DIR"
ditto "$APP_BUNDLE" "$STAGING/RayNeo Steady.app"
if [[ ! -e "$STAGING/Applications" ]]; then ln -s /Applications "$STAGING/Applications"; fi
cp "$ROOT_DIR/INSTALL.txt" "$STAGING/Read Me.txt"
cp "$ROOT_DIR/LICENSE" "$STAGING/License.txt"
cp "$ROOT_DIR/Sources/CRayNeo/LICENSE" "$STAGING/RayNeo SDK License.txt"
hdiutil create -volname "RayNeo Steady" -srcfolder "$STAGING" -format UDZO "$DMG"
codesign --force --timestamp --sign "${STEADY_SIGNING_IDENTITY:-Developer ID Application}" "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG"
stat -f 'DMG size: %z bytes' "$DMG"
