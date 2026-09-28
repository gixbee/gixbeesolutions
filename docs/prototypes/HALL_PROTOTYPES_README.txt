Gixbee Hall / Service booking — HTML prototypes (2 files)
============================================================

OWNER (List My Business — hall service unit)
  docs/prototypes/hall-owner-lmb-master.html

  Manage menu: Calendar, Booking Requests, Packages & Pricing, etc.
  Full 5-step Packages wizard (event categories → venue → slots/prices →
  payment/cancellation → review). Calendar stub + Booking Settings.
  Demo storage: localStorage key GIXBEE_HALL_PACKAGE

CUSTOMER (Find a hall)
  docs/prototypes/hall-customer-book-master.html

  Search filters → results → hall detail → date/time + AC → booking enquiry
  → request sent.

Regenerate both from shell + JS:
  python3 docs/prototypes/_gen_hall_prototypes.py

Source (edit these, then regenerate):
  hall-owner-lmb-shell.html + _hall_owner_app.js
  hall-customer-book-shell.html + _hall_customer_app.js

Serve locally:
  cd docs/prototypes && python3 -m http.server 8765

Related Flutter: lib/features/business/business_unit_dashboard.dart (SERVICE)
Docs: docs/GIXBEE_V147_FOUR_FLOW_REVIEW.md § Service / event booking
