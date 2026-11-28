# Gixbee Decoration Owner — spec analysis (vs catering pattern)

**Sources:** `Gixbee_Decoration_Owner_Flow_Developer_Specification.docx`, flow mockup `decoration-owner-flow-mockup.png` (12 phone screens, 5-step wizard + success).

**Goal:** Mobile-first HTML prototype like catering owner — shell + JS + `_gen_decoration_prototypes.py` → `GIXBEE-DECORATION-OWNER-FINALFLOW5.html`.

---

## 1. Mockup ↔ document alignment

| # | Mockup screen | Spec section | Match |
|---|---------------|--------------|-------|
| 1 | Owner dashboard (6 tiles) | §3 Dashboard | Yes — Packages, Individual Services, Enquiries (12), Calendar, Gallery, Business Profile |
| 2 | Package hub empty + filters | §4 Package management | Yes — Packages \| Individual Services, search, Basic/Standard/Premium chips, + Create Package |
| 3 | Step 1 category | §5 Step 1 | Yes — Wedding & Related vs Other Functions |
| 4 | Step 2 details | §5 Step 2 | Yes — level, event type, community, style, name, images |
| 5 | Step 3 category list (8 rows) | §5 Step 3 | Partial — mockup shows 8 categories; **spec lists 14** (add Dining, Vehicle/Personal Flowers, Traditional/Ceremony, Other Items) |
| 6 | Select items in category | §5.1 | Yes — search, multi-select, Included/Extra tags |
| 7 | Item detail Included/Extra | §5.2 | Yes — extra price + unit (Per Event, etc.) |
| 8 | Selected items summary | §5.3 | Yes — counts, edit/remove, add more |
| 9 | Step 4 pricing | §5 Step 4 | Yes — Fixed/Starting/Range/Quotation, discount %, GST chips |
| 10 | Step 5 preview | §5 Step 5 | Yes — inclusions vs optional extras, publish |
| 11 | Success + share | §4 Share menu | Yes — WhatsApp, PDF, link, View Packages |

**Visual:** Doc says reuse **catering purple/magenta**, white, green success — mockup matches (not catering green).

**Not on mockup but in spec (phase 2 stubs OK):** Service Areas, Reviews, Enquiries detail, Quotation builder (D19–D20), Individual Services wizard D12–D18, venue/safety logistics (§9).

---

## 2. Catering → Decoration mapping

| Catering owner | Decoration owner |
|----------------|------------------|
| Menu & Packages hub | Packages & Individual Services hub |
| 9 food groups (`g01`–`g09`) | **14 decoration categories** (catalogue) |
| Dish Included in package (veg filter) | Item **Included** vs **Extra** + unit price |
| Per-plate **guest slabs** | **Package price** types — no per-guest slabs |
| Food preference + serving style | Event types + optional tradition/style/ceremony |
| Package wizard 5 steps | Same **5 steps** (different fields) |
| Offer 1–90% on slabs | Offer % or amount on **package price** |
| `_catering_menu_catalog.js` | `_decoration_catalog.js` (mock catalogue) |
| `_catering_menu_hub.js` | `_decoration_package_hub.js` + `_decoration_individual.js` |
| Photo calendar reuse | Reuse `_photo_calendar.js` pattern / copy for decor |
| LMB → Manage → Dashboard | Same entry — **Decor Mart** demo business |

---

## 3. Decoration catalogue (14 categories — from spec)

1. Stage / Mandapam  
2. Entrance & Welcome  
3. Pathway Decoration  
4. Floral Decoration  
5. Lighting & Sound  
6. Seating & Furniture  
7. Dining & Table  
8. Photo & Display  
9. Special Effects  
10. Vehicle & Personal Flowers  
11. Traditional / Ceremony Setup  
12. Other Items  
(+ each has example sub-items in doc for seed data)

**Rules:**

- Multi-select per category; **Add Your Own** custom item.
- **Included** → optional qty/description; no add-on price.
- **Extra** → required price + unit (Per Event, Per Set, Per Unit, Per Item, Per Hour, Custom Quotation).
- No automatic “Excluded” section unless owner adds one (spec §5.2).

---

## 4. Step 5 wizard — required fields

| Step | Required (prototype) |
|------|----------------------|
| 1 | Package category: Wedding & Related **or** Other Functions |
| 2 | **Event type** (multi), **package name**; level/tradition/style/images optional |
| 3 | At least one catalogue/custom item (validate like catering “pick dishes”) |
| 4 | Pricing type + amount when not Custom Quotation; GST chip; discount optional |
| 5 | Preview from draft; Publish or Save Draft |

---

## 5. Data model (prototype localStorage)

Align with spec §12:

- `decorationMenu` or `store.decoration`: `catPackages[]`, `individualServices[]`, `catalogue` defs, hub filters.
- `Package`: category, `eventTypes[]`, optional `level`, `traditionTags[]`, `ceremonySetup[]`, `styles[]`, name, description, images[], `pricing` object, `gstTreatment`, status live/draft, `items[]` as PackageItem.
- `PackageItem`: categoryId, catalogueId or customName, `inclusionType` included|extra, quantity, unit, extraPrice, description.

Keep generators isolated like catering for future API.

---

## 6. Suggested prototype layout (like catering)

```
docs/prototypes/
  decoration-owner-flow-shell.html
  _decoration_owner_icons.js          (optional; or extend catering icons)
  _decoration_catalog.js              (14 categories + seed items)
  _decoration_package_hub.js          (list, wizard steps 1–5, pickers)
  _decoration_individual_services.js  (phase 1b or stub)
  _decoration_owner_app.js            (LMB, dashboard, stubs: enquiries/calendar/gallery)
  _gen_decoration_prototypes.py
  GIXBEE-DECORATION-OWNER-FINALFLOW5.html
  DECORATION_OWNER_PROTOTYPES_README.txt
```

**V1 deliverable (match mockup):** Dashboard → package hub → **full 5-step wizard** → success/share → package list with edit/delete. Stubs for Individual Services tab, Enquiries, Calendar (wire calendar later like catering).

---

## 7. Scope boundaries (do not ship in V1)

- Real WhatsApp/PDF/backend calendar (toast simulate per spec §13–16).
- Religion-specific **mandatory** items — tags are optional suggestions only.
- Guest-count / per-plate pricing (catering-only).
- Production payment / advance collection.
- Full D13–D18 individual service wizard (list + “coming soon” OK for first PR if you want faster mockup parity).

---

## 8. Customer flow

Not in this doc. After owner V1, plan **decoration-customer** like `catering-customer-flow-b579`: search, caterer profile, package detail with inclusions/extras, initiate enquiry.

---

## 9. Next implementation steps

1. Branch `cursor/decoration-owner-lmb-b579` off current stack base.  
2. Shell CSS: fork catering-owner tokens → purple theme from mockup.  
3. Seed catalogue JSON from spec §5 item examples (editable).  
4. Implement wizard + `cc`-style validators + live preview math (discount, extra totals).  
5. Playwright smoke: create package end-to-end.  
6. Customer flow in follow-up PR.

**Spec copy on disk:** `Gixbee_Decoration_Owner_Flow_Developer_Specification.docx`