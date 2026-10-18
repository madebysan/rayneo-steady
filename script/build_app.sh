#!/bin/bash
set -euo pipefail
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Use debug or release" >&2; exit 2 ;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_BUNDLE="$ROOT_DIR/dist/RayNeo Steady.app"
SIGNING_IDENTITY="${STEADY_SIGNING_IDENTITY:-Developer ID Application}"
cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION"
BUILD_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
# Stop only this checkout's app; do not interrupt a separately installed copy.
while IFS= read -r pid; do
  process_path="$(ps -p "$pid" -o comm=)"
  if [[ "$process_path" == "$APP_BUNDLE/Contents/MacOS/RayNeoSteady" ]]; then
    kill -TERM "$pid"
  fi
done < <(pgrep -x RayNeoSteady || true)
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/RayNeoSteady" "$APP_BUNDLE/Contents/MacOS/RayNeoSteady"
cp "$ROOT_DIR/Sources/CRayNeo/LICENSE" "$APP_BUNDLE/Contents/Resources/RayNeoSDK-LICENSE.txt"
if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RayNeoSteady</string>
<key>CFBundleIdentifier</key><string>com.san.rayneosteady.prototype</string>
<key>CFBundleName</key><string>RayNeo Steady</string>
<key>CFBundleDisplayName</key><string>RayNeo Steady</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Santiago Alonso</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
