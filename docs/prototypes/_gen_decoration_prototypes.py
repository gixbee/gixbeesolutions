#!/usr/bin/env python3
"""Build decoration owner single-file HTML demo."""
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "decoration-owner-flow-shell.html"
PARTS = [
    "_catering_owner_icons.js",
    "_photo_calendar.js",
    "_decoration_catalog.js",
    "_decoration_package_hub.js",
    "_decoration_individual_hub.js",
    "_decoration_owner_platform.js",
    "_decoration_owner_app.js",
]
MASTER = DIR / "GIXBEE-DECORATION-OWNER-FINALFLOW.html"
ALIASES = [
    "GIXBEE-DECORATION-OWNER-FINALFLOW5.html",
    "OPEN-gixbee-decoration-owner-demo.html",
    "DOWNLOAD-gixbee-decoration-owner.html",
]
PLACEHOLDER = """<!-- APP_START -->
<div style="margin:16px;padding:16px;border:2px solid #DC2626;border-radius:12px"><b>Not the demo file.</b> Open GIXBEE-DECORATION-OWNER-FINALFLOW5.html</div>
<!-- APP_END -->"""


def build() -> str:
    shell = SHELL.read_text(encoding="utf-8")
    scripts = "\n".join(DIR.joinpath(p).read_text(encoding="utf-8") for p in PARTS)
    block = "<!-- APP_START -->\n<script>\n" + scripts + "\n</script>\n<!-- APP_END -->"
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit("shell missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    if "DECORATION_MODULES" not in out or "bootDecoration" not in out:
        raise SystemExit("missing decoration bundle")
    if "bindPhotoCalendarUi" not in out or "renderPhotoDash" not in out:
        raise SystemExit("missing platform/calendar bundle")
    if "decPkgListPrice" not in out or "Vehicle & Personal Flowers" not in out:
        raise SystemExit("missing catalogue or pricing UI")
    return out


def main() -> None:
    out = build()
    MASTER.write_text(out, encoding="utf-8")
    for name in ALIASES:
        (DIR / name).write_text(out, encoding="utf-8")
    raw = SHELL.read_text(encoding="utf-8")
    if "<script>" in raw.split("<!-- APP_START -->")[1].split("<!-- APP_END -->")[0]:
        pass
    else:
        SHELL.write_text(
            raw.split("<!-- APP_START -->")[0] + PLACEHOLDER + raw.split("<!-- APP_END -->")[1],
            encoding="utf-8",
        )
    print(f"wrote {MASTER.name} ({MASTER.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()