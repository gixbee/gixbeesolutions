Gixbee Hall / Service booking — HTML prototypes
================================================

START HERE (pick one):

  docs/prototypes/index-hall-demos.html   ← links to both working demos

WORKING SINGLE-FILE DEMOS (CSS + HTML + JS in one file — no separate .js):

  Customer (pick any — same file):
    GIXBEE-hall-customer-single-file.html   ← easiest name to share
    OPEN-gixbee-hall-customer-demo.html
    DOWNLOAD-gixbee-hall-customer.html

  Owner (pick any — same file):
    GIXBEE-hall-owner-single-file.html
    OPEN-gixbee-hall-owner-demo.html
    DOWNLOAD-gixbee-hall-owner.html

NOT FOR DEMO (layout only — no app until you regenerate):

  hall-owner-lmb-shell.html
  hall-customer-book-shell.html

If you see a red "Wrong file" or "did not start" message, you opened a shell
file. Use OPEN-gixbee-hall-*-demo.html instead.

Regenerate all masters + OPEN/DOWNLOAD copies:

  python3 docs/prototypes/_gen_hall_prototypes.py

Optional local server:

  cd docs/prototypes && python3 -m http.server 8765
  http://localhost:8765/index-hall-demos.html

Build tag on working files: 2026-09-28-hall-owner-v60 / hall-customer-v12

Raw GitHub (branch cursor/hall-service-html-b579):

  https://raw.githubusercontent.com/gixbee/gixbeesolutions/cursor/hall-service-html-b579/docs/prototypes/OPEN-gixbee-hall-customer-demo.html
  https://raw.githubusercontent.com/gixbee/gixbeesolutions/cursor/hall-service-html-b579/docs/prototypes/OPEN-gixbee-hall-owner-demo.html
