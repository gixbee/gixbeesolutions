# Six event flows — completion matrix

Branch `events/six-flows-complete` vs PR #11 + #12 (`a6ed644a`). HTML files
were **not in this checkout**; UI is matched to the in-repo wizard copy and
comments that describe those references.

## Agreed hall deadlines (quote-first, not HTML demo timers)

| HTML demo behaviour | Production semantics (this branch) |
|---|---|
| ~90s owner-response timeout | **Not implemented.** Owner reviews enquiries and sends a quote. No auto-cancel of unanswered hall requests. |
| 24h advance after acceptance | `dueAt` is set to min(now+24h, event start) on the hall advance **PAYMENT** milestone. **Informational only** — no auto-cancel, refund, or hold release. |

Direct payments are never collected or verified by Gixbee. Both parties
acknowledge independently (`event_quote_milestones` + audit table).

## Screen-by-screen

| Flow | Screen / API | Persist | Status |
|---|---|---|---|
| Catering Owner | `CateringPackageWizardScreen` → `PUT /events/catalogues/{id}/CATERING` | Catalogue JSON: dishes, groups, slabs, live/draft | **Working** after compile fixes |
| Catering Customer | Browser → customize (`servingStyle`, `dietaryNeeds`, `menuChanges`) → `POST /events` → quotes | Event `serviceRequest` JSONB; quotes | **Working**; price still server-recalculated |
| Photography Owner | 10-step package + 8-step individual wizards → catalogue save | `paymentSplit` (must sum 100), functions, deliverables | **Working** |
| Photography Customer | Function customize → quote accept → `EventQuoteMilestones` | Auto milestones from snapshot + delivery string | **Working** |
| Hall Owner | Multi-hall, `HallMonthGrid`, enquiries, assignment, quotes | Hall APIs + terms snapshot | **Working** (calendar compile fix) |
| Hall Customer | Discover → slot → `HallBookingReviewScreen` → request → quote confirm + advance ack | Hall customer APIs + milestone ack | **Working** |

## Tests added / required

- Flutter: `test/event_flow_screens_test.dart` (widget + classify).
- Rust: payment remainder + hall `dueAt` cap (`backend_rust/src/events/milestones.rs`).
- SQL: `scripts/test_event_quote_milestones.sql` (FK / presence; run on a **disposable** DB).

## Remaining limitations

- HTML originals not vendored; pixel-perfect vs uploaded files cannot be signed off here.
- No payment-provider verification of hall/photography/catering money.
- No auto-expiry of hall requests or unpaid advances.
- Photography delivery is a milestone label, not file upload.
- Isolated PostgreSQL + `cargo test` need a complete MSVC/SDK or Linux/Docker toolchain on this Windows machine (`msvcrt.lib` / `vcvarsall.bat` missing).
- Production migration of `azure_event_quote_milestones.sql` still requires explicit approval.
