Gixbee Photography Owner — FINALFLOW HTML (like hall owner)
=============================================================

STATUS: LOCKED V1 (2026-10-13) — see PHOTO_OWNER_FLOW_LOCK.md

Same build pattern as GIXBEE-HALL-OWNER-FINALFLOW.html:
  one self-contained .html file · all CSS + JS inline · localStorage

PRIMARY FILES (download / double-click — same build, pick one name):

  docs/prototypes/GIXBEE-PHOTO-OWNER-FINALFLOW5.html   ← recommended working copy
  docs/prototypes/GIXBEE-PHOTO-OWNER-FINALFLOW.html    ← master name from generator

Every code change is in shell + _photo_*.js; then run the generator. It writes
FINALFLOW and copies to FINALFLOW5 (only the HTML comment + browser title differ).

Spec (V1): docs/prototypes/Gixbee_Photography_Package_Service_Flow_Final_V1.docx

Navigation:
  List My Business → Archana Photography → Manage
  Calendar & Bookings: Calendar tab · Bookings tab (month register) · Settings
  Bookings: month list → booking detail → Edit · Change history (audit)

NOT for demo: photo-owner-flow-shell.html

Regenerate: python3 docs/prototypes/_gen_photo_prototypes.py

Build tag: check PHOTO_OWNER_BUILD in _photo_owner_app.js after open (e.g. 2026-10-13-photo-owner-flow-locked-v1)

Sources: _photo_owner_app.js + _photo_pkg_wizard.js + _photo_svc_wizard.js + _photo_calendar.js + _photo_owner_icons.js

Raw download (FINALFLOW5):
  https://raw.githubusercontent.com/gixbee/gixbeesolutions/cursor/prelaunch-worker-community-b579/docs/prototypes/GIXBEE-PHOTO-OWNER-FINALFLOW5.html
