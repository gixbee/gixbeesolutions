Gixbee Photography Customer — FINALFLOW HTML
=============================================

PRIMARY DEMO (double-click):

  docs/prototypes/GIXBEE-PHOTO-CUSTOMER-FINALFLOW5.html

Default Home / Search screen:

  Hero: Find Your Wedding Photographer
  Fields: Location → Event Date → What do you need photography for? (required)
  If wedding-related (marriage, engagement, save the date, pre/post wedding, etc.):
    Community / Religion + Package Type
  If funeral, baptism, event, etc.: no community or package filters
  Budget (optional) → Search Photographers

  Wedding need → packages path. Individual service need → services catalog path.

  Service flow (funeral, baptism, event, portrait, corporate):
    Search hero + service budget → results (studios that list that service)
    → Profile → View Service
       (one matching service: straight to detail + date picker once)
       (several services: services catalog + date, then detail without repeat date)
    → Customize / Initiate Interest → Review → Send Interest

Sources:

  photo-customer-flow-shell.html
  _photo_customer_flow_app.js
  _photo_customer_catalog.js
  _photo_customer_owner_payloads.js  (full owner-wizard-shaped demo data)
  _photo_customer_views.js           (customer renderers for that data)
  _customer_flow_icons.js (bundled at build)

Regenerate:

  python3 docs/prototypes/_gen_photo_customer_prototypes.py

NOT for demo: photo-customer-flow-shell.html

Build tag: PHOTO_CUSTOMER_BUILD in _photo_customer_flow_app.js
