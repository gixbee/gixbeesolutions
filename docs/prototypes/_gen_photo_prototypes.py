#!/usr/bin/env python3
"""Build photography owner single-file HTML demos from shell + icons + app."""
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "photo-owner-flow-shell.html"
ICONS = DIR / "_photo_owner_icons.js"
PKG_WIZ = DIR / "_photo_pkg_wizard.js"
SVC_WIZ = DIR / "_photo_svc_wizard.js"
CAL = DIR / "_photo_calendar.js"
APP = DIR / "_photo_owner_app.js"
MASTER = DIR / "GIXBEE-PHOTO-OWNER-FINALFLOW.html"

ALIASES = [
    "DOWNLOAD-gixbee-photo-owner.html",
    "OPEN-gixbee-photo-owner-demo.html",
    "GIXBEE-PHOTO-OWNER-WORKING.html",
    "GIXBEE-PHOTO-OWNER-FlowHtml.html",
    "GIXBEE-PHOTO-OWNER-FINALFLOW5.html",
]

SHELL_PLACEHOLDER = """<!-- APP_START -->
<div id="shellOnlyNotice" style="margin:16px;padding:20px;border:2px solid #DC2626;border-radius:12px;background:#FEE2E2;font:15px sans-serif">
  <p style="margin:0 0 8px;font-weight:800;color:#991B1B">This is not the working demo file.</p>
  <p style="margin:0 0 12px;line-height:1.5">Open the single-file flow HTML (JavaScript is inside that file only):</p>
  <p style="margin:0"><a href="GIXBEE-PHOTO-OWNER-FINALFLOW.html" style="font-weight:800;color:#1D4ED8">GIXBEE-PHOTO-OWNER-FINALFLOW.html</a></p>
</div>
<!-- APP_END -->"""


def build_master() -> str:
    shell = SHELL.read_text(encoding="utf-8")
    icons = ICONS.read_text(encoding="utf-8")
    pkg = PKG_WIZ.read_text(encoding="utf-8")
    svc = SVC_WIZ.read_text(encoding="utf-8")
    cal = CAL.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    block = (
        "<!-- APP_START -->\n<script>\n"
        + icons
        + "\n"
        + pkg
        + "\n"
        + svc
        + "\n"
        + cal
        + "\n"
        + app
        + "\n</script>\n<!-- APP_END -->"
    )
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit("photo-owner-flow-shell.html missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    head = out.split("<!-- APP_START -->")[0]
    for marker in (".fn-pick", "#wizard.wiz-create", "#wizard.wiz-svc-create", ".del-tabs", "wiz-pkg-brand", "wiz-svc-brand"):
        if marker not in head:
            raise SystemExit(f"built HTML missing shell content: {marker!r} — regenerate from updated shell")
    if out.count("<script>") != 1:
        raise SystemExit(f"expected one inlined script, got {out.count('<script>')}")
    if "PHOTO_OWNER_BUILD" not in out or "function boot(" not in out:
        raise SystemExit("missing photo owner app")
    for cal_marker in (
        'id="photoCalGrid"',
        "function openPhotoCalendar",
        "bindPhotoCalendarUi",
        'id="photoBkRegisterList"',
        "renderPhotoBookingRegister",
        'id="photoAuditOverlay"',
    ):
        if cal_marker not in out:
            raise SystemExit(f"built FINALFLOW missing calendar bundle: {cal_marker!r}")
    banner = (
        "<!-- GIXBEE PHOTO OWNER — single self-contained flow HTML (FINALFLOW). "
        "Save as GIXBEE-PHOTO-OWNER-FINALFLOW.html and open in browser. "
        "Do NOT open photo-owner-flow-shell.html. -->\n"
    )
    out = out.replace("<!DOCTYPE html>", "<!DOCTYPE html>\n" + banner, 1)
    return out


def ensure_shell_placeholder() -> None:
    text = SHELL.read_text(encoding="utf-8")
    i, j = text.find("<!-- APP_START -->"), text.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit("photo-owner-flow-shell.html missing APP markers")
    inner = text[i + len("<!-- APP_START -->") : j].strip()
    if inner and "shellOnlyNotice" in inner and "<script" not in inner:
        return
    if inner and "<script" in inner:
        return
    SHELL.write_text(text[:i] + SHELL_PLACEHOLDER + text[j + len("<!-- APP_END -->") :], encoding="utf-8")


def main() -> None:
    ensure_shell_placeholder()
    out = build_master()
    MASTER.write_text(out, encoding="utf-8")
    kb = MASTER.stat().st_size // 1024
    print(f"Wrote {MASTER.name} ({kb} KB)")
    for name in ALIASES:
        body = out
        if name == "GIXBEE-PHOTO-OWNER-FINALFLOW5.html":
            body = out.replace(
                "flow HTML (FINALFLOW). Save as GIXBEE-PHOTO-OWNER-FINALFLOW.html",
                "flow HTML (FINALFLOW5). Save as GIXBEE-PHOTO-OWNER-FINALFLOW5.html",
            )
            body = body.replace(
                "<title>Gixbee — Photography Owner</title>",
                "<title>Gixbee — Photography Owner (FINALFLOW5)</title>",
            )
        (DIR / name).write_text(body, encoding="utf-8")
        print(f"Wrote {name} (copy of {MASTER.name})")


if __name__ == "__main__":
    main()
