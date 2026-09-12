#!/bin/bash
set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$PLUGIN_ROOT/scripts/build.sh"
python3 "$PLUGIN_ROOT/scripts/check-release.py"
DIST_DIR="${CODEX_WIDGET_DIST_DIR:-$HOME/Library/Caches/CodexUsageWidget/dist}"
VERSION="$(cat "$PLUGIN_ROOT/VERSION")"
APP="$DIST_DIR/Codex Usage Widget.app"
ARCH="$(uname -m)"
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/CodexUsageWidget-$VERSION-macos-$ARCH.zip"
python3 "$PLUGIN_ROOT/scripts/source-archive.py" "$DIST_DIR/CodexUsageWidget-$VERSION-source.zip"
echo "Packages: $DIST_DIR"
