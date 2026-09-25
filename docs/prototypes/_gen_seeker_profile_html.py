#!/usr/bin/env python3
"""Build seeker-job-profile-master.html (employee job profile wizard + localStorage save)."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "seeker-job-profile-shell.html"
APP_JS = DIR / "_seeker_profile_app.js"
OUT_HTML = DIR / "seeker-job-profile-master.html"
GEN_CATALOG = DIR / "_gen_hire_catalog.py"


def build_catalog_js() -> str:
    """Run hire catalog generator so seeker HTML stays in sync with 18-sector data."""
    subprocess.run([sys.executable, str(GEN_CATALOG)], check=True, cwd=DIR)
    catalog_path = DIR / "hire-employee-skills-catalog.js"
    return catalog_path.read_text(encoding="utf-8")


def main() -> None:
    shell = SHELL.read_text(encoding="utf-8")
    app = APP_JS.read_text(encoding="utf-8")
    js = build_catalog_js()
    if "window.GIXBEE_HIRE_CATALOG" not in js:
        raise SystemExit("Catalog JS missing GIXBEE_HIRE_CATALOG")

    catalog_block = (
        "<!-- CATALOG_START -->\n<script>\n"
        "/* Same SkillsHire catalogue as Hire Employee — shared taxonomy */\n"
        + js
        + "</script>\n<!-- CATALOG_END -->"
    )
    app_block = "<!-- APP_START -->\n<script>\n" + app + "\n</script>\n<!-- APP_END -->"

    for start, end, block in [
        ("<!-- CATALOG_START -->", "<!-- CATALOG_END -->", catalog_block),
        ("<!-- APP_START -->", "<!-- APP_END -->", app_block),
    ]:
        i, j = shell.find(start), shell.find(end)
        if i < 0 or j < 0:
            raise SystemExit(f"Shell missing {start}/{end}")
        shell = shell[:i] + block + shell[j + len(end) :]

    shell = (
        "<!-- GIXBEE SEEKER JOB PROFILE — single self-contained HTML (catalogue + app JS inlined). -->\n"
        + shell
    )
    OUT_HTML.write_text(shell, encoding="utf-8")
    text = OUT_HTML.read_text(encoding="utf-8")
    if "<script src=" in text:
        raise SystemExit("Single-file output must not reference external script src")
    if "function boot(" not in text or "window.GIXBEE_HIRE_CATALOG" not in text:
        raise SystemExit("Generated HTML missing inlined catalogue or app JS")
    if "function renderS4(" not in text:
        raise SystemExit("Generated HTML missing step-4 JS renderer")
    print(f"Wrote {OUT_HTML.name} ({OUT_HTML.stat().st_size // 1024} KB) — open this file only")


if __name__ == "__main__":
    main()
