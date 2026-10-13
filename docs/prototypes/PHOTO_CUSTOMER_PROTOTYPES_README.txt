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

  Wedding need → packages path. Individual service need → single-service path.

Sources:

  photo-customer-flow-shell.html
  _photo_customer_flow_app.js
  _customer_flow_icons.js (bundled at build)

Regenerate:

  python3 docs/prototypes/_gen_photo_customer_prototypes.py

NOT for demo: photo-customer-flow-shell.html

Build tag: PHOTO_CUSTOMER_BUILD in _photo_customer_flow_app.js
