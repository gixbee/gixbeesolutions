Gixbee Hall / Service booking — HTML prototypes (2 files)
============================================================

IMPORTANT — USE THESE SINGLE FILES (all JavaScript is INSIDE the .html):

  OWNER:    docs/prototypes/hall-owner-lmb-master.html
  CUSTOMER: docs/prototypes/hall-customer-book-master.html

Do NOT open for demo:
  hall-owner-lmb-shell.html
  hall-customer-book-shell.html
  _hall_owner_app.js / _hall_customer_app.js
Those are source files for developers; run the generator to refresh the master HTML.

Regenerate (inlines JS into both masters):
  python3 docs/prototypes/_gen_hall_prototypes.py

Serve locally:
  cd docs/prototypes && python3 -m http.server 8765

Related Flutter: lib/features/business/business_unit_dashboard.dart (SERVICE)
Docs: docs/GIXBEE_V147_FOUR_FLOW_REVIEW.md § Service / event booking
