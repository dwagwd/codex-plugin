#!/usr/bin/env python3
"""Install a status-line bridge while retaining the user's current status line command."""
import argparse
import json
from pathlib import Path
import shlex
import shutil
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("provider", choices=["claude", "antigravity"])
    args = parser.parse_args()
    base = Path.home() / (".claude" if args.provider == "claude" else ".gemini/antigravity-cli")
    base.mkdir(parents=True, exist_ok=True)
    config = base / "settings.json"
    data = json.loads(config.read_text()) if config.exists() else {}
    old = data.get("statusLine") or {}
    bridge = Path.home() / "Library/Application Support/CodexUsageWidget/bridges"
    bridge.mkdir(parents=True, exist_ok=True, mode=0o700)
    script = bridge / (args.provider + "-statusline.py")
    command = shlex.quote(sys.executable) + " " + shlex.quote(str(script))
    if old.get("command") == command:
        print("Bridge already installed."); return
    if old and (old.get("type") != "command" or not isinstance(old.get("command"), str)):
        raise SystemExit("Existing status line is not a shell command; configure manually using docs/providers.md.")
    shutil.copyfile(Path(__file__).with_name("provider_bridge.py"), bridge / "provider_bridge.py")
    script.write_text('''import json, subprocess, sys
from provider_bridge import normalize, write_snapshot
raw = sys.stdin.buffer.read(262145)
try:
    if len(raw) > 262144: raise ValueError()
    write_snapshot(normalize(PROVIDER, json.loads(raw)))
except Exception:
    pass
if ORIGINAL:
    result = subprocess.run(ORIGINAL, shell=True, input=raw, timeout=10)
    sys.exit(result.returncode)
else:
    print(PROVIDER.capitalize() + " usage → desktop widget")
'''.replace("PROVIDER", repr(args.provider)).replace("ORIGINAL", repr(old.get("command"))))
    if config.exists():
        backup = base / ("settings.json.usage-widget-backup-" + str(time.time_ns()))
        shutil.copy2(config, backup); backup.chmod(0o600)
    data["statusLine"] = {**old, "type": "command", "command": command}
    temporary = config.with_suffix(".usage-widget.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temporary.chmod(0o600); temporary.replace(config)
    print("Bridge installed. Enable ‘Import other agents’ in widget Settings. Existing status line preserved.")

if __name__ == "__main__":
    main()
