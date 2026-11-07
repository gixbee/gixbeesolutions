#!/usr/bin/env python3
"""Build the catering customer single-file HTML demo from shell + catalog + shared + app."""
from pathlib import Path

DIR = Path(__file__).resolve().parent
SHELL = DIR / "catering-customer-flow-shell.html"
CATALOG = DIR / "_catering_menu_catalog.js"
SHARED = DIR / "_catering_customer_shared.js"
APP = DIR / "_catering_customer_app.js"
MASTER = DIR / "GIXBEE-CATERING-CUSTOMER-FINALFLOW.html"
ALIASES = [
    "GIXBEE-CATERING-CUSTOMER-FINALFLOW5.html",
    "OPEN-gixbee-catering-customer-demo.html",
    "DOWNLOAD-gixbee-catering-customer.html",
]
SHELL_PLACEHOLDER = """<!-- APP_START -->
<div id="shellOnlyNotice" style="margin:16px;padding:20px;border:2px solid #DC2626;border-radius:12px;background:#FEE2E2;font:15px sans-serif">
  <p style="margin:0 0 8px;font-weight:800;color:#991B1B">This is not the working demo file.</p>
  <p style="margin:0">Open <a href="GIXBEE-CATERING-CUSTOMER-FINALFLOW.html" style="font-weight:800">GIXBEE-CATERING-CUSTOMER-FINALFLOW.html</a>.</p>
</div>
<!-- APP_END -->"""


def build_master() -> str:
    shell = SHELL.read_text(encoding="utf-8")
    catalog = CATALOG.read_text(encoding="utf-8")
    shared = SHARED.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    block = (
        "<!-- APP_START -->\n<script>\n"
        + catalog
        + "\n"
        + shared
        + "\n"
        + app
        + "\n</script>\n<!-- APP_END -->"
    )
    start = shell.find("<!-- APP_START -->")
    end = shell.find("<!-- APP_END -->")
    if start < 0 or end < 0:
        raise SystemExit("shell is missing APP markers")
    end += len("<!-- APP_END -->")
    out = shell[:start] + block + shell[end:]
    if "FOOD_MODULES" not in out or "bootCustomer" not in out:
        raise SystemExit("customer demo is missing catalog or app")
    if "Christian Wedding" not in out or "Archana Catering" not in out:
        raise SystemExit("customer demo missing Archana / Christian Wedding seed")
    return out


def main() -> None:
    html = build_master()
    if "shellOnlyNotice" in html and "function bootCustomer" not in html:
        raise SystemExit("placeholder leaked into the master")
    MASTER.write_text(html, encoding="utf-8")
    for name in ALIASES:
        (DIR / name).write_text(html, encoding="utf-8")
    raw = SHELL.read_text(encoding="utf-8")
    SHELL.write_text(
        raw.split("<!-- APP_START -->")[0] + SHELL_PLACEHOLDER + raw.split("<!-- APP_END -->")[1],
        encoding="utf-8",
    )
    kb = MASTER.stat().st_size // 1024
    print(f"wrote {MASTER.name} and {len(ALIASES)} copies ({kb} KB)")


if __name__ == "__main__":
    main()
