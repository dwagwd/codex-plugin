#!/bin/bash
set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$PLUGIN_ROOT/scripts/build.sh"
DIST_DIR="${CODEX_WIDGET_DIST_DIR:-$HOME/Library/Caches/CodexUsageWidget/dist}"
APP="$DIST_DIR/Codex Usage Widget.app"
mkdir -p "$HOME/Applications"
# Quit this app gracefully before replacing its executable.
if pgrep -x CodexUsageWidget >/dev/null; then
    "$HOME/Applications/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --quit
    for attempt in {1..30}; do
        if ! pgrep -x CodexUsageWidget >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x CodexUsageWidget >/dev/null; then
        echo 'Please quit Codex Usage Widget before reinstalling.' >&2; exit 1
    fi
fi
ditto "$APP" "$HOME/Applications/Codex Usage Widget.app"
echo "Installed: $HOME/Applications/Codex Usage Widget.app"
