# Photography owner flow — LOCKED (prototype V1)

**Status:** Locked for review and handoff (2026-10-13).  
**Canonical demo:** `GIXBEE-PHOTO-OWNER-FINALFLOW5.html`  
**Build tag:** `PHOTO_OWNER_BUILD` in `_photo_owner_app.js` (see `2026-10-13-photo-owner-flow-locked-v1`).

## What is locked

Interactive HTML prototype for the **photography business owner** journey (List My Business → manage catalog, calendar, bookings, profile). Spec baseline: `Gixbee_Photography_Package_Service_Flow_Final_V1.docx`.

### In scope (V1)

| Area | Notes |
|------|--------|
| List / pick business | Archana Photography demo seed |
| Manage hub | Wedding packages + individual services tabs |
| Package wizard | Levels, ceremony types, coverage, deliverables, pricing, payment stages, extras (incl. live stream cameras) |
| Service wizard | One service per category, pricing preview, team rows, deliverables, live streaming |
| Catalog UX | Package filters; service CTA below list with spacing |
| Calendar & bookings | Month calendar, day status, booking register, detail, audit |
| Service areas | State/district with registered location locked |
| Profile / settings | Business profile, delete listing flow |

### Explicitly out of scope (defer to later)

- Photography **customer** booking flow (separate prototype track).
- Extra per-event service categories (Baptism, Birthday, etc.) beyond current `SVC_CATEGORIES`.
- Production API, GST provider, or Flutter wiring.
- Rich customer-facing package page beyond owner review summaries.

## Source files (edit only when unlocking)

| File | Role |
|------|------|
| `photo-owner-flow-shell.html` | Layout + CSS |
| `_photo_owner_app.js` | App shell, catalog, manage, profile |
| `_photo_pkg_wizard.js` | Wedding package wizard |
| `_photo_svc_wizard.js` | Individual service wizard |
| `_photo_calendar.js` | Calendar + bookings |
| `_photo_owner_icons.js` | Icons |

After any source change:

```bash
python3 docs/prototypes/_gen_photo_prototypes.py
node --check docs/prototypes/_photo_owner_app.js
```

Do **not** demo from `photo-owner-flow-shell.html` (no inlined JS).

## Unlock policy

Treat this flow as **frozen** unless the team agrees on a V1.1/V2 change list. Cosmetic copy tweaks and bugfixes are fine; new steps, categories, or navigation should be tracked as a deliberate unlock.
