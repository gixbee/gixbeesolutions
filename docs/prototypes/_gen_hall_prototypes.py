#!/usr/bin/env python3
"""Build hall owner (LMB) and hall customer booking single-file HTML demos."""
from __future__ import annotations

import re
from pathlib import Path

DIR = Path(__file__).resolve().parent

SHELL_ONLY_RE = re.compile(
    r"<!-- SHELL_ONLY_START -->.*?<!-- SHELL_ONLY_END -->",
    re.DOTALL,
)

PAIRS = [
    ("hall-owner-lmb-shell.html", "_hall_owner_app.js", "hall-owner-lmb-master.html"),
    ("hall-customer-book-shell.html", "_hall_customer_app.js", "hall-customer-book-master.html"),
]

SHELL_PLACEHOLDER = """<!-- APP_START -->
<div id="shellOnlyNotice" style="margin:16px;padding:20px;border:2px solid #DC2626;border-radius:12px;background:#FEE2E2;font:15px sans-serif">
  <p style="margin:0 0 8px;font-weight:800;color:#991B1B">This is not the working demo file.</p>
  <p style="margin:0 0 12px;line-height:1.5">Open the single-file demo (JavaScript is inside that file only):</p>
  <p style="margin:0"><a href="{download}" style="font-weight:800;color:#1D4ED8">{download}</a></p>
</div>
<!-- APP_END -->"""


def build(shell_name: str, js_name: str, out_name: str) -> None:
    shell = (DIR / shell_name).read_text(encoding="utf-8")
    app = (DIR / js_name).read_text(encoding="utf-8")
    block = "<!-- APP_START -->\n<script>\n" + app + "\n</script>\n<!-- APP_END -->"
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit(f"{shell_name} missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    out = SHELL_ONLY_RE.sub("", out)
    if "<script src=" in out:
        raise SystemExit(f"{out_name} must not use external script src")
    if out.count("<script>") != 1:
        raise SystemExit(f"{out_name} must have exactly one inlined script block, got {out.count('<script>')}")
    if "CUSTOMER_BUILD" in out_name or "customer" in out_name:
        if "CUSTOMER_BUILD" not in out:
            raise SystemExit(f"{out_name} missing customer JS")
    else:
        if "OWNER_BUILD" not in out or "function boot(" not in out:
            raise SystemExit(f"{out_name} missing owner JS")
    if "Hall customer demo did not start" in out or "Hall owner demo did not start" in out:
        raise SystemExit(f"{out_name} must not include shell-only guard text")
    banner = (
        f"<!-- GIXBEE HALL DEMO — single self-contained file (CSS + HTML + JS inlined). "
        f"Open {out_name} only; do not open {shell_name}. -->\n"
    )
    if not out.startswith("<!DOCTYPE"):
        out = banner + out
    else:
        out = out.replace("<!DOCTYPE html>", "<!DOCTYPE html>\n" + banner, 1)
    (DIR / out_name).write_text(out, encoding="utf-8")
    print(f"Wrote {out_name} ({(DIR / out_name).stat().st_size // 1024} KB)")


def ensure_shell_placeholder(shell_name: str, download_name: str) -> None:
    path = DIR / shell_name
    text = path.read_text(encoding="utf-8")
    i, j = text.find("<!-- APP_START -->"), text.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit(f"{shell_name} missing APP markers")
    inner = text[i + len("<!-- APP_START -->") : j].strip()
    if inner and "<script" not in inner and "shellOnlyNotice" in inner:
        return
    if inner and "<script" in inner:
        raise SystemExit(f"{shell_name} must not contain script in APP region; run generator only on JS files")
    placeholder = SHELL_PLACEHOLDER.format(download=download_name)
    path.write_text(text[:i] + placeholder + text[j + len("<!-- APP_END -->") :], encoding="utf-8")


def main() -> None:
    ensure_shell_placeholder("hall-owner-lmb-shell.html", "DOWNLOAD-gixbee-hall-owner.html")
    ensure_shell_placeholder("hall-customer-book-shell.html", "DOWNLOAD-gixbee-hall-customer.html")
    for shell, js, out in PAIRS:
        build(shell, js, out)
    aliases = [
        ("hall-owner-lmb-master.html", "DOWNLOAD-gixbee-hall-owner.html"),
        ("hall-customer-book-master.html", "DOWNLOAD-gixbee-hall-customer.html"),
        ("hall-owner-lmb-master.html", "OPEN-gixbee-hall-owner-demo.html"),
        ("hall-customer-book-master.html", "OPEN-gixbee-hall-customer-demo.html"),
    ]
    seen: set[str] = set()
    for src, alias in aliases:
        if alias in seen:
            continue
        seen.add(alias)
        p = DIR / src
        (DIR / alias).write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Wrote {alias} (copy of {src})")


if __name__ == "__main__":
    main()
