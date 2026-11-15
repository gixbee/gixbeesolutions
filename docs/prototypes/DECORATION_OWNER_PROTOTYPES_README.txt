Gixbee Decoration Owner — prototype
=====================================

PRIMARY DEMO:

  docs/prototypes/GIXBEE-DECORATION-OWNER-FINALFLOW5.html

Flow:

  List My Business → Decor Mart → Dashboard (same layout & flows as catering owner)
  Service areas, calendar/bookings, gallery, booking requests, operators, deleted business, profile
  Packages & Individual Services (hub)
  5-step package wizard (category → details → items → Basic/Standard/Premium amounts → preview)
  Individual service wizard (4 steps): category → details → optional designs →
  single service price + unit (NOT Basic/Standard/Premium)
  Enquiries, Calendar, Gallery, Profile (stubs)

Catalogue:

  python3 docs/prototypes/_gen_decoration_catalog.py
  python3 docs/prototypes/_gen_decoration_prototypes.py

Sources:

  decoration-owner-flow-shell.html
  _decoration_catalog.js
  _decoration_package_hub.js
  _decoration_individual_hub.js
  _decoration_owner_app.js

Spec: Gixbee_Decoration_Owner_Flow_Developer_Specification.docx

Build tag: DECORATION_OWNER_BUILD in _decoration_owner_app.js