Gixbee Catering Owner — prototype
=================================

PRIMARY DEMO:

  docs/prototypes/GIXBEE-CATERING-OWNER-FINALFLOW5.html

Owner flow:

  List My Business → Archana Catering → Manage → Dashboard
  Menu & Packages (packages + 13-module food catalogue, item editor, package wizard)
  Service areas, business profile, calendar & bookings
  Photos & Gallery, Booking Requests (stubs)
  Operators, Deleted business

Sources:

  catering-owner-flow-shell.html
  _catering_owner_icons.js
  _photo_calendar.js
  _catering_menu_catalog.js
  _catering_menu_hub.js
  _catering_owner_app.js

Regenerate HTML demos:

  python3 docs/prototypes/_gen_catering_prototypes.py

Refresh master catalogue from gixbee-catering-almostfinal.docx (459 items):

  python3 docs/prototypes/_gen_catering_catalog_from_doc.py
  python3 docs/prototypes/_gen_catering_prototypes.py

NOT for demo: catering-owner-flow-shell.html

Build tag: CATERING_OWNER_BUILD in _catering_owner_app.js
