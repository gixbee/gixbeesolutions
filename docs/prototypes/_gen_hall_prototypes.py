#!/usr/bin/env python3
"""Build hall owner (LMB) and hall customer booking single-file HTML demos."""
from __future__ import annotations

from pathlib import Path

DIR = Path(__file__).resolve().parent

PAIRS = [
    ("hall-owner-lmb-shell.html", "_hall_owner_app.js", "hall-owner-lmb-master.html"),
    ("hall-customer-book-shell.html", "_hall_customer_app.js", "hall-customer-book-master.html"),
]


def build(shell_name: str, js_name: str, out_name: str) -> None:
    shell = (DIR / shell_name).read_text(encoding="utf-8")
    app = (DIR / js_name).read_text(encoding="utf-8")
    block = "<!-- APP_START -->\n<script>\n" + app + "\n</script>\n<!-- APP_END -->"
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit(f"{shell_name} missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    if "<script src=" in out:
        raise SystemExit(f"{out_name} must not use external script src")
    if "<script>" not in out or "</script>" not in out:
        raise SystemExit(f"{out_name} missing inlined script block")
    if "CUSTOMER_BUILD" in out_name or "customer" in out_name:
        if "CUSTOMER_BUILD" not in out:
            raise SystemExit(f"{out_name} missing customer JS")
    else:
        if "OWNER_BUILD" not in out or "function boot(" not in out:
            raise SystemExit(f"{out_name} missing owner JS")
    banner = (
        f"<!-- GIXBEE HALL DEMO — single self-contained file (CSS + HTML + JS inlined). "
        f"Open {out_name} only; do not open {shell_name} until regenerated. -->\n"
    )
    if not out.startswith("<!DOCTYPE"):
        out = banner + out
    else:
        out = out.replace("<!DOCTYPE html>", "<!DOCTYPE html>\n" + banner, 1)
    (DIR / out_name).write_text(out, encoding="utf-8")
    print(f"Wrote {out_name} ({(DIR / out_name).stat().st_size // 1024} KB)")


def main() -> None:
    for shell, js, out in PAIRS:
        build(shell, js, out)


if __name__ == "__main__":
    main()
