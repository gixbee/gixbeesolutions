Gixbee Catering Customer — prototype
====================================

PRIMARY DEMO:

  docs/prototypes/GIXBEE-CATERING-CUSTOMER-FINALFLOW5.html

Customer flow:

  Search (location, date, guests, budget) → Caterer results → Profile → Menu
  Packages (food preference + serving style filters) · Individual food items (nine groups)
  Package / dish detail · Initiate interest

Sources:

  catering-customer-flow-shell.html
  _catering_menu_catalog.js
  _catering_customer_shared.js
  _catering_customer_app.js

Regenerate HTML demos:

  python3 docs/prototypes/_gen_catering_customer_prototypes.py

Align catalogue with owner:

  python3 docs/prototypes/_gen_catering_catalog_from_doc.py
  python3 docs/prototypes/_gen_catering_customer_prototypes.py

NOT for demo: catering-customer-flow-shell.html

Build tag: CC_BUILD in _catering_customer_app.js
