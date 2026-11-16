# Gixbee event marketplace — hall completion and release checklist

Reference prototypes:

- `GIXBEE-HALL-OWNER-FINALFLOW.html`
- `GIXBEE-HALL-CUSTOMER-FINAL.html`

## Hall Owner implemented

- Existing hall business setup with planned hall count and shared car/bike parking, plus a new **Venue & Parking** settings editor in the hall hub
- Multiple hall cards, active/listed switches and archived-hall protection against live bookings
- Direct editable hall name, separate from the read-only business name
- Five-step package wizard: event categories, indoor/outdoor, seating, dining and private/changing rooms, facilities, catering/decor, time slots, original AC/non-AC rent and discounts, advance and full-payment settings, machine-readable cancellation and reschedule tiers
- Existing cover/gallery, operator permissions, calendar blocks, booking-request inbox, owner approval, hall assignment and quote screens
- Dedicated **Booking Settings** screen from calendar for booking window (1–36 months) and minimum notice (0–365 days), saved into existing versioned hall package JSON
- Customer slot price and capacity data published from owner-saved package revisions, never client-provided prices

## Hall Customer implemented

- Dedicated location/city, event type, event date, guest-count, AC preference, indoor/outdoor and budget filtering on **verified active listings**
- Search cards with real hall/venue name, capacity, location, parking and lowest advertised discounted rent
- Hall profile with cover/gallery, capacities, private rooms, parking, amenities and catering/decor options
- Date-specific Rust availability query with available/unavailable morning/evening/full-day slots, AC/non-AC prices, owner list-price strikethrough and discount percent
- Review with exact slot, venue, guest count, quoted base rent, advance amount, remaining balance and published cancellation/rescheduling policies
- Explicit **Request to Book** acknowledgement. Idempotent `POST /events` uses a stable `clientRequestId` and server-revalidated `hallId`, `slotId`, `withAc` and `expectedEstimate`
- Request confirmation and navigation to event details / My Events. Existing owner approval, assignment, quote, reservation hold and payment milestones remain authoritative

## Automatic validation

CI: `.github/workflows/hall-flows.yml`.

```bash
flutter pub get
flutter analyze lib/features/hall_owner \
  lib/features/events/hall_customer_model.dart \
  lib/features/events/hall_customer_search_screen.dart \
  lib/features/events/hall_customer_flow_screen.dart \
  lib/features/events/hall_booking_review_screen.dart
flutter test test/features/events/hall_customer_model_test.dart \
  test/features/events/hall_customer_flow_test.dart \
  test/repositories/hall_contract_test.dart

cd backend_rust
cargo check
cargo test halls
```

Unit/widget tests check discount rounding, seat and event filters, AC pricing, actual slot selection, owner package settings save/reload, API request shape and an idempotent submission. Flutter workflow is pinned to Flutter 3.41 to match this repository's Gradle toolchain. Existing Catering Customer and Photography Customer regressions run on the shared browser changes.

## Mandatory live PostgreSQL and device QA before release

1. In a development database, an authorized owner creates venue and two halls, sets shared parking and rooms, and saves/publishes packages. Reopen and compare all fields.
2. Verify the 5-step wizard correctly persists disabled slots, offered AC/non-AC rent and discounts, payment percent/fixed advance, and policy tier boundaries. Ensure editing one hall does not change another.
3. Sign in as a customer, select a city/date/guest count and AC preference, confirm filtered results and the exact list and offer amounts.
4. Open the venue details, pick a permitted slot and submit. Verify the customer event plan and owner inbox. A duplicate retry with the same `clientRequestId` must not create two plans.
5. Owner approves, assigns a hall and offers a quote. Customer accepts. Verify held and confirmed reservations, the separate advance acknowledgement, and both sides' status timelines.
6. Try two customers requesting the same interval; concurrent approval/assignment must not overbook. Test already-booked, blocked, cancelled and released intervals, as well as future dates outside the configured booking window.
7. Verify hall-level operator permissions: operators may view/manage permitted calendars but must not archive halls, change prices, approve owner-only requests or edit another business.
8. Test changing a published price or disabling a slot between browsing and submission. Rust must return a conflict rather than honor an outdated estimate.
9. Test narrow screens (360px/440px), keyboard scroll, cover/gallery images, Android back navigation and visual comparison with the two reference HTML files.
10. Install real Firebase configuration and run an Android build on the actual Gixbee Firebase project; verify push notifications and logged-in session routing.

## Deliberate limits and caveats

- The HTML's 90-second owner response and 24-hour customer advance messages are **demo text**, not proof that automatic timers or a payment gateway exist. The real Rust quote/reservation state machine and configured hold TTL govern actual status. Do not display a fabricated countdown or collect money automatically.
- The listing search is based on published packages. Date-specific slot availability is checked when opening the slot selector and **revalidated on submission**, not guaranteed from search results.
- Owner-uploaded media needs a real accessible image URL; the UI does not invent or inject demo images.
- No new SQL migration is necessary for the changes here: existing `business_halls`, `business_hall_package_revisions`, `business_hall_venue`, `hall_calendar_blocks`, `hall_reservations`, `event_plans` and `event_quotes` are reused.
- A green mocked API test **does not certify a live Postgres deployment**.
- This repository has previously lacked `lib/firebase_options.dart` and `android/app/google-services.json`; provide genuine Firebase project settings before APK packaging. Never commit synthetic credentials.
