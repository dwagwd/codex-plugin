#!/usr/bin/env python3
"""Read Cursor's official Team Admin API; keep the key only in this process's memory."""
import argparse
import base64
import getpass
import json
import time
import urllib.request
from provider_bridge import normalize, write_snapshot


def collect(key, email):
    request = urllib.request.Request("https://api.cursor.com/teams/spend",
        data=json.dumps({"searchTerm": email, "page": 1, "pageSize": 100}).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Basic " + base64.b64encode((key + ":").encode()).decode()})
    # Never follow a redirect with an administrator credential.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
        raw = response.read(262145)
        if len(raw) > 262144:
            raise ValueError("Response too large")
        return normalize("cursor", json.loads(raw), identity=email)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watch", action="store_true", help="Continue every 120 seconds; Ctrl-C stops")
    args = parser.parse_args()
    email = input("Exact team member email: ").strip()
    key = getpass.getpass("Cursor Team Admin API key (not saved): ").strip()
    delay = 120
    while True:
        try:
            write_snapshot(collect(key, email)); print("Cursor spending snapshot updated."); delay = 120
        except Exception:
            print("Cursor unavailable; check the admin key, member email, and network.")
            delay = min(300, delay * 2)
        if not args.watch:
            break
        time.sleep(delay)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
