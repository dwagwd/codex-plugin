#!/bin/bash
set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"
# Keep SwiftPM from scanning an unrelated repository above this standalone package.
export GIT_CEILING_DIRECTORIES="$(dirname "$PLUGIN_ROOT")"
BUILD_CACHE="${CODEX_WIDGET_BUILD_CACHE:-$HOME/Library/Caches/CodexUsageWidget/build}"
DIST_DIR="${CODEX_WIDGET_DIST_DIR:-$HOME/Library/Caches/CodexUsageWidget/dist}"
APP_VERSION="$(cat "$PLUGIN_ROOT/VERSION")"
swift build --scratch-path "$BUILD_CACHE" -c release --disable-index-store --jobs 2
BIN_DIR="$(swift build --scratch-path "$BUILD_CACHE" -c release --show-bin-path)"
APP="$DIST_DIR/Codex Usage Widget.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodexUsageWidget" "$APP/Contents/MacOS/CodexUsageWidget"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex.usage-widget</string>
<key>CFBundleName</key><string>Codex Usage Widget</string>
<key>CFBundleDisplayName</key><string>Codex Usage Widget</string>
<key>CFBundleExecutable</key><string>CodexUsageWidget</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
