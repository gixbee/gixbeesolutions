# Photography Owner: implementation and acceptance

Reference: `GIXBEE-PHOTO-OWNER-FINALFLOW.html`.

## Implemented in Flutter and Rust

- List My Business → Photography catalogue: Wedding Packages vs Individual
  Services, name search, Basic/Standard/Premium filters, Live/Draft state,
  editing and moving to draft without deleting historical service snapshots.
- Ten-step wedding package wizard: name/description, base price inclusive
  of GST, integer percentage offer, wedding functions and ceremonies,
  function-level coverage/duration/side, crew and extra hours, selected
  deliverables with quantity/format, optional extras with prices,
  delivery timelines, payment milestones summing to 100%, cancellation and
  rescheduling deduction tiers, customer requirements and review/publish.
- Eight-step standalone service wizard: category, description, list/offer
  pricing, duration/team, selected deliverables/quantities, extra services
  with separate prices, delivery timelines, policies, and review/publish.
- Both editors save to the existing versioned Rust JSONB catalogue API and
  **close only on a successful response**. Errors preserve editor inputs.
  Retry with unchanged IDs; a stale revision results in a 409 conflict.
- Owner calendar: IST month grid, day schedule, Gixbee confirmed bookings
  plus outside shoots, booking register, unavailable-day controls, booking
  settings and manual shoot add/edit/cancel.
- New `GET /events/vendor/calendar/:businessId/overview`: only accessible
  to its business owner, merges confirmed `event_quotes` and noncancelled
  `event_vendor_calendar` entries.
- New `PUT /events/vendor/calendar/:businessId/:entryId`: edit a manual
  shoot, protected by business ownership and overlapping booking checks.

No new SQL table or migration is required. Existing
`event_service_catalogues`, `event_vendor_calendar`, `event_quotes`,
`event_plans` and `businesses.offlineDays` are reused.

## Automated tests

```bash
flutter pub get
flutter test test/features/events/photography_owner_pricing_test.dart
flutter test test/features/events/photography_calendar_math_test.dart
flutter test test/features/events/photography_owner_wizard_test.dart
flutter test test/repositories/photography_owner_repository_test.dart
cd backend_rust
cargo check
cargo test catalogue_metadata_tests
```

CI: `.github/workflows/photography-owner.yml`. The repository uses a
Flutter 3.41 toolchain for this targeted workflow, matching its current
Gradle 8.14 setup.

## Manual QA on a connected development database

1. Open an owner's photography catalogue; create a published wedding
   package and a draft individual service.
2. Enter ₹100,000 list price and 10% discount. Confirm customer price is
   ₹90,000; edit to 5% and confirm ₹95,000 after save/reload.
3. Fill coverage per function, deliverable quantity/format and delivery
   days, add-on prices, four payment stages totaling 100%, and cancellation
   policy tiers; reopen and compare all fields.
4. Disconnect network or use a stale catalogue revision; ensure save
   failure does not close the wizard or lose data.
5. Check published vs draft customer visibility from another account.
6. Confirm a Gixbee photography quote; inspect its day and month calendar
   entry. Create an outside shoot on a free day; edit its time and verify
   it cannot overlap an existing shoot or confirmed quote.
7. Mark an available day unavailable; verify provider quote confirmation
   rejects that day. Release it and verify capacity settings persist.
8. Verify an unauthorized user cannot load the calendar or edit an outside
   shoot belonging to someone else's business.
9. Compare reference screens against a mobile device or emulator for
   visual spacing, keyboard behavior, navigation and narrow widths.

## Known limits

- The HTML contains simulated clients, reviews, bookings and service areas;
  the app intentionally never seeds those mock records in production.
- Existing business operators management and photo gallery remain in their
  existing dashboard/catalogue sections. Full role-scoped operator calendar
  writes and a persistent per-edit audit trail are *not included* in this
  change. These require a separate explicit authorization/audit design.
- Cancellation/rescheduling policy tiers are catalogue information. They
  do not by themselves trigger automatic refunds; quotes and payment
  workflow remain the authoritative transaction logic.
- CI uses mocked repository calls and Rust unit tests; it does not run a
  live PostgreSQL booking acceptance test.
- The repository lacks real generated Firebase
  `lib/firebase_options.dart` and `android/app/google-services.json`.
  A full Android APK build requires project-specific Firebase setup.
