# Gixbee Photography Customer acceptance

HTML reference: `GIXBEE-PHOTO-CUSTOMER-FINALFLOW.html`.

## Implemented

- Search by city, event date, venue/area, photography need, wedding
  ceremony/community, package level and a price budget. Search is backed
  by verified providers' published `PHOTOGRAPHY` catalogue JSON.
- Wedding needs search `PACKAGE` offers by function, ceremony, level
  and real offer price. Individual photography needs search `ITEM`
  offers by published category/name. Drafts and unpriced entries never
  appear.
- Studio profile with About, Portfolio and Reviews tabs; published
  photos and description only, no synthetic ratings, bookings or reviews.
- Package/service catalogue, date editing and offer price display;
  original price and discount badge come from owner-published JSON.
- Detail tabs: overview, inclusions, coverage, extras, policies,
  payment stages and reviews. Per-function coverage, deliverable
  quantities/formats and optional add-on prices are read from
  `event_service_catalogues`.
- Direct interest or customized interest; editable event timing, area,
  optional functions/crew/coverage/album requests, selected extras
  and notes; explicit quote-first acknowledgement.
- `POST /events` with one selected item, `expectedEstimate` from the
  **published offer price**, validated `customization` fields and an
  idempotent `clientRequestId`. A real success response shows the
  interest timeline and opens the existing My Interests / plan detail.
- Errors preserve customer input. Quote amount, availability, payment
  and booking confirmation remain server/vendor-authoritative.

## Tests

```sh
flutter pub get
flutter analyze lib/features/events/photography_customer_model.dart \
  lib/features/events/photography_customer_search_screen.dart \
  lib/features/events/photography_customer_flow_screen.dart \
  lib/features/events/photography_customer_interest_screen.dart \
  lib/features/events/event_service_browser.dart
flutter test test/features/events/photography_customer_model_test.dart \
  test/features/events/photography_customer_flow_test.dart

cd backend_rust
cargo check
cargo test customization_tests
cargo test catalogue_metadata_tests
```

Workflow: `.github/workflows/photography-customer.yml`.

## Development database and device acceptance

1. Owner publishes a wedding package and a portrait service with a
   verified business/service city. Check only matching items appear.
2. Filter wedding function, ceremony and level, then price range.
   Confirm published 10% off ₹100,000 is displayed as ₹90,000.
3. Open studio profile, photos, published package and tabs. Confirm
   owner-entered function coverage, deliverables and policy details
   survive save/reload.
4. Select a future date and add-ons. Confirm the review shows the
   **base** price only, with extras clearly marked subject to a quote.
5. Submit an interest and confirm it appears in My Interests and the
   vendor's inbox. Confirm the vendor can offer a quote.
6. Change or unpublish the offer after the customer opens the detail
   screen. The Rust endpoint must reject stale amount/inactive items.
7. Attempt an unavailable day or a request outside the booking window:
   no booking should be confirmed; server validation is authoritative.
8. Simulate an API timeout; retry with the same `clientRequestId`
   without a duplicate plan.
9. Test narrow screens, package/service change, date/time inputs,
   keyboard insets, and the uploaded HTML layout against an emulator.

## Known limitations

- The reference HTML's fake studio ratings, review counts, distances,
  chat messages and available-date badges are **not fabricated** in the
  production app. Reviews and direct messaging need verified APIs.
- Search validates catalogue matches but cannot confirm date-level
  availability in real time. The provider reviews availability after
  enquiry.
- Optional extras are **requested**, not automatically charged. The
  vendor's confirmed quote is the authoritative price.
- No new PostgreSQL migration is needed: existing `event_plans`,
  `event_service_catalogues`, `event_quotes` are reused.
- CI uses mocked event submission and does not replace real DB/device
  tests. Android APK packaging still requires the repository's real
  `lib/firebase_options.dart` and `android/app/google-services.json`.
