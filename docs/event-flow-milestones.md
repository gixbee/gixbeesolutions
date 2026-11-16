# Event flow backend: quote milestones and customer customization

Applies to Gixbee's Rust-only stack, with the changes in PR #12.

## Prerequisites and migration

The base event and hall tables must exist first:
- `scripts/marketplace_migrate_events_rentals.sql`
- `scripts/azure_hall_migrations.sql`

Then apply **`scripts/azure_event_quote_milestones.sql`** to the target
PostgreSQL database. It is additive and idempotent, but does **not** migrate
legacy bookings or charge customers.

```bash
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db \
  -v ON_ERROR_STOP=1 -f - < scripts/azure_event_quote_milestones.sql
```

`scripts/azure_sync_and_deploy.sh` executes this migration after the hall
migration and before starting the new Rust image. If it fails, the deployment
stops before the new backend is started. If deploying with another workflow,
run the migration explicitly before switching any API replicas.

Verify presence:
```sql
SELECT to_regclass('public.event_quote_milestones') AS milestones,
       to_regclass('public.event_quote_milestone_events') AS audit;
```

## Existing endpoints (unchanged)

- `PUT /events/catalogues/{businessId}/{service}`
- `POST /events` (optionally targeted to a vendor)
- `POST /events/{planId}/quotes`
- `POST /events/quotes/{quoteId}/{action}`
- Hall booking, availability, calendar and enquiry endpoints

All prices are recalculated by Rust from the stored catalogue / hall
selection, and cannot be overridden through customer customization.

## New Rust contracts

Requests require an authenticated access token, and API authorization
checks the event customer or the business owner associated with each quote.

`GET /events/quotes/{quoteId}/milestones`

Returns payment and delivery milestones, each with position, label,
details, amount/percent for payments, optional dueAt, both acknowledgement
timestamps, completedAt and computed overdue flag. No phone or other
participant secrets are added.

`POST /events/quotes/{quoteId}/milestones` — vendor only, once per
confirmed quote with no existing schedule.

```json
{
  "milestones": [
    {"kind": "PAYMENT", "label": "Advance", "percent": 30},
    {"kind": "PAYMENT", "label": "Balance", "percent": 70},
    {"kind": "DELIVERY", "label": "Final album", "details": "JPEG files and printed album"}
  ]
}
```

Payment percentages must add to 100. Milestones cannot be silently
replaced once published; changes to agreed scope require a separate
design/revision workflow.

`POST /events/quotes/{quoteId}/milestones/{milestoneId}/ack` — either
participant, independently and idempotently. The caller can only set
their own acknowledgement timestamp. After both acknowledge, the row
is completed and an audit row is recorded. The operation does not
transfer money.

### Automatic creation on quote acceptance

- Photography: structured `paymentSplit` from the selected catalogue
  item's **request-time snapshot** seeds payment stages; a nonempty
  `delivery` string seeds one delivery milestone.
- Hall: the agreed hall package terms snapshot seeds a **direct-pay
  advance** milestone if an advance is configured. Its informational
  dueAt is at most 24 hours after acceptance and no later than the event
  start.
- Older quotes or catalogues with no valid stage metadata may have no
  automatic milestones. The vendor can publish a schedule while
  the quote is confirmed.

`payment` acknowledgement on an event quote now requires all defined
PAYMENT milestones to be acknowledged by both parties.
`complete` requires all defined DELIVERY milestones. If there are no
milestones of that type, existing behavior is preserved.

### Customer-specific requirements

`POST /events` accepts `serviceRequest.customization` for targeted
CATERING and PHOTOGRAPHY enquiries. Rust whitelists and bounds fields:

- CATERING: servingStyle, dietaryNeeds, menuChanges
- PHOTOGRAPHY: functions, coverage, team, deliverables, extras

These requests are stored in the event's existing `serviceRequest`
JSONB and do not change the calculated catalogue estimate. Final
scope/price must be agreed through the vendor quote.

### Catalogue metadata validation

Photography package `paymentSplit` must contain 1–6 valid stages,
each with a label and percentage; percentage sum must equal 100.
Structured arrays (functions, ceremonies, inclusions, extras) and notes
are bounded. Catering's optional `baseTiers` / `discountPct`
must produce the same displayed pricing stored in `tiers`.

## Test plan

1. Run `cargo test --manifest-path backend_rust/Cargo.toml` for new
   pure validation tests.
2. Run Flutter checks: `flutter pub get`, `flutter analyze`,
   `flutter test`, `flutter build apk --debug`.
3. On a disposable DB with migration applied, test two users (customer
   and business owner), plus a stranger:
   - Owner creates catalogue, customer sends interest and vendor quotes.
   - Customer accepts; inspect auto-generated milestones.
   - Stranger cannot list, create or acknowledge milestones.
   - Customer acknowledgement does not set vendor acknowledgement.
   - Vendor acknowledgement completes one milestone, creates one audit entry.
   - Repeated acknowledgement is idempotent.
   - Full-payment / service-complete actions reject outstanding milestones.
   - Expired/declined/cancelled quotes cannot accept acknowledgements.
   - Confirm hall advance amount agrees with the immutable terms snapshot.
   - Test quote amendments and concurrent requests in a separate transaction test.
4. Check owner/customer Flutter booking detail after save and reload.

## Agreed hall deadline semantics

Do not add HTML demo timers without a product change:

1. **Owner response:** quote-first. The hall owner assigns and quotes; there is
   no 90-second auto-reject of enquiries.
2. **Advance:** after quote acceptance, a PAYMENT milestone may carry
   `dueAt = min(now + 24h, event start)`. It is **not** an automatic
   cancellation, refund, or inventory release.

## Known limitations — not a complete production booking engine

- The reference HTML's 90-second demo owner-response timeout is **not**
  introduced here. Hall owners still use the existing Rust quote-first
  approval and assignment lifecycle.
- Hall advance dueAt is **informational only**. There is no automatic
  cancellation/refund or release of a confirmed hall after 24 hours.
- Direct payments remain external. No payment provider verifies funds.
  Both parties only acknowledge payment; disputes need a separate workflow.
- Photography deliverables are an agreed stage, not uploaded assets,
  crew scheduling, proofing/revision, versioning or media storage.
- Deployment, database migration, Dart compilation, Rust tests and
  end-to-end QA must be executed in the target environment before
  merging/releasing this PR.
