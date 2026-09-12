#!/bin/bash
set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/Codex Usage Widget.app"
if [ ! -x "$APP/Contents/MacOS/CodexUsageWidget" ]; then
    "$PLUGIN_ROOT/scripts/build-install.sh"
fi
open "$APP"
