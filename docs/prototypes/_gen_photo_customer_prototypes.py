#!/usr/bin/env python3
"""Build photography customer flow single-file HTML demo."""
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "photo-customer-flow-shell.html"
ICONS = DIR / "_customer_flow_icons.js"
CATALOG = DIR / "_photo_customer_catalog.js"
PAYLOADS = DIR / "_photo_customer_owner_payloads.js"
VIEWS = DIR / "_photo_customer_views.js"
CUSTOMIZE = DIR / "_photo_customer_customize.js"
APP = DIR / "_photo_customer_flow_app.js"
MASTER = DIR / "GIXBEE-PHOTO-CUSTOMER-FINALFLOW.html"

ALIASES = [
    "GIXBEE-PHOTO-CUSTOMER-FINALFLOW5.html",
    "OPEN-gixbee-photo-customer-demo.html",
    "DOWNLOAD-gixbee-photo-customer.html",
    "GIXBEE-PHOTO-CUSTOMER-WORKING.html",
]


def build_master() -> str:
    shell = SHELL.read_text(encoding="utf-8")
    icons = ICONS.read_text(encoding="utf-8")
    catalog = CATALOG.read_text(encoding="utf-8")
    payloads = PAYLOADS.read_text(encoding="utf-8")
    views = VIEWS.read_text(encoding="utf-8")
    customize = CUSTOMIZE.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    block = (
        "<!-- APP_START -->\n<script>\n"
        + icons
        + "\n"
        + views
        + "\n"
        + customize
        + "\n"
        + payloads
        + "\n"
        + catalog
        + "\n"
        + app
        + "\n</script>\n<!-- APP_END -->"
    )
    i, j = shell.find("<!-- APP_START -->"), shell.find("<!-- APP_END -->")
    if i < 0 or j < 0:
        raise SystemExit("photo-customer-flow-shell.html missing APP markers")
    out = shell[:i] + block + shell[j + len("<!-- APP_END -->") :]
    if "PHOTO_CUSTOMER_BUILD" not in out or "bootPhotoCustomer" not in out:
        raise SystemExit("missing photo customer app")
    if out.count("<script>") != 1:
        raise SystemExit("expected one inlined script")
    banner = (
        "<!-- GIXBEE PHOTO CUSTOMER — single self-contained flow HTML. "
        "Open GIXBEE-PHOTO-CUSTOMER-FINALFLOW5.html. "
        "Do NOT open photo-customer-flow-shell.html. -->\n"
    )
    out = out.replace("<!DOCTYPE html>", "<!DOCTYPE html>\n" + banner, 1)
    return out


def main() -> None:
    text = build_master()
    MASTER.write_text(text, encoding="utf-8")
    print(f"Wrote {MASTER.name} ({MASTER.stat().st_size // 1024} KB)")
    for name in ALIASES:
        path = DIR / name
        if name.endswith("FINALFLOW5.html"):
            t = text.replace(
                "<title>Gixbee — Photography (Customer)</title>",
                "<title>Gixbee Photo Customer — FINALFLOW5</title>",
            )
        else:
            t = text
        path.write_text(t, encoding="utf-8")
        print(f"Wrote {name} (copy)")


if __name__ == "__main__":
    main()
