#!/usr/bin/env python3
"""Build GIXBEE-PHOTO-OWNER-WORKING.html from shell + icons + app."""
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "photo-owner-flow-shell.html"
ICONS = DIR / "_photo_owner_icons.js"
APP = DIR / "_photo_owner_app.js"
OUT = DIR / "GIXBEE-PHOTO-OWNER-WORKING.html"
OUT_OPEN = DIR / "OPEN-gixbee-photo-owner-demo.html"


def main() -> None:
    shell = SHELL.read_text(encoding="utf-8")
    icons = ICONS.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    block = "<!-- APP_START -->\n<script>\n" + icons + "\n" + app + "\n</script>\n<!-- APP_END -->"
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit("photo-owner-flow-shell.html missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    banner = "<!-- GIXBEE PHOTO OWNER — single self-contained file (CSS + HTML + JS). Open this file or GIXBEE-PHOTO-OWNER-WORKING.html. Do NOT open photo-owner-flow-shell.html. -->\n"
    if not out.lstrip().startswith("<!-- GIXBEE PHOTO"):
        out = out.replace("<!DOCTYPE html>", "<!DOCTYPE html>\n" + banner, 1)
    OUT.write_text(out, encoding="utf-8")
    open_banner = "<!-- GIXBEE PHOTO DEMO — double-click OPEN-gixbee-photo-owner-demo.html (same app as GIXBEE-PHOTO-OWNER-WORKING.html). -->\n"
    open_out = out.replace(banner, open_banner, 1) if banner in out else out
    open_out = open_out.replace("<title>Gixbee — Photography Owner</title>", "<title>Gixbee — Photography Owner (demo)</title>", 1)
    OUT_OPEN.write_text(open_out, encoding="utf-8")
    print(f"Wrote {OUT.name} ({len(out) // 1024} KB)")
    print(f"Wrote {OUT_OPEN.name} ({len(open_out) // 1024} KB)")


if __name__ == "__main__":
    main()
