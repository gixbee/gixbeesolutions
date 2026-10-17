Gixbee Catering Owner — prototype (photography parity except menu hub)
=======================================================================

PRIMARY DEMO:

  docs/prototypes/GIXBEE-CATERING-OWNER-FINALFLOW5.html

Same owner capabilities as photography owner, except **Menu & Packages**
(opens a stub screen until catering menu wizard screens are provided):

  List My Business → Archana Catering → Manage → Dashboard
  Service areas (full flow)
  Business profile
  Calendar & bookings (full _photo_calendar.js bundle)
  Photos & Gallery, Booking Requests (stub screens, same as photo)
  Operators, Deleted business

Sources:

  catering-owner-flow-shell.html
  _catering_owner_icons.js
  _photo_calendar.js          (shared calendar module)
  _catering_owner_app.js      (fork of _photo_owner_app.js)

Regenerate:

  python3 docs/prototypes/_gen_catering_prototypes.py

NOT for demo: catering-owner-flow-shell.html

Build tag: CATERING_OWNER_BUILD in _catering_owner_app.js
