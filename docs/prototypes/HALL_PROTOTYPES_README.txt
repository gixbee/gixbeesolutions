Gixbee Hall / Service booking — HTML prototypes (2 files)
============================================================

OPEN THESE (single self-contained .html — all JavaScript is INSIDE):

  OWNER (List My Business):
    docs/prototypes/DOWNLOAD-gixbee-hall-owner.html
    (same as hall-owner-lmb-master.html)

  CUSTOMER (find / book a hall):
    docs/prototypes/DOWNLOAD-gixbee-hall-customer.html
    (same as hall-customer-book-master.html)

Do NOT open for demo (no app JavaScript until you regenerate):
  hall-owner-lmb-shell.html
  hall-customer-book-shell.html

Developer sources: _hall_owner_app.js, _hall_customer_app.js

Regenerate masters + DOWNLOAD copies (inlines JS):
  python3 docs/prototypes/_gen_hall_prototypes.py

If buttons do nothing or menu says "Loading menu…":
  1. Confirm the page footer/build tag shows v3 (2026-09-28-hall-*-v3).
  2. Hard refresh: Ctrl+Shift+R (Cmd+Shift+R on Mac).
  3. Serve locally instead of double-clicking file:
       cd docs/prototypes && python3 -m http.server 8765
     Then open http://localhost:8765/DOWNLOAD-gixbee-hall-owner.html

Raw GitHub downloads (branch cursor/hall-service-html-b579):
  https://raw.githubusercontent.com/gixbee/gixbeesolutions/cursor/hall-service-html-b579/docs/prototypes/DOWNLOAD-gixbee-hall-owner.html
  https://raw.githubusercontent.com/gixbee/gixbeesolutions/cursor/hall-service-html-b579/docs/prototypes/DOWNLOAD-gixbee-hall-customer.html

Related Flutter: lib/features/business/business_unit_dashboard.dart (SERVICE)
Docs: docs/GIXBEE_V147_FOUR_FLOW_REVIEW.md
