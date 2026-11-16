# Gixbee Catering Customer: validation and Android prerequisites

The Catering Customer screens use the existing `POST /events` Rust
contract and read prices from the owner-managed CATERING catalogue JSONB.

## Automated checks

CI workflow `.github/workflows/catering-customer.yml` uses Flutter 3.41
with the repository's current Android Gradle toolchain.

```bash
flutter pub get
flutter analyze lib/features/events/catering_customer_pricing.dart \
  lib/features/events/catering_customer_search_screen.dart \
  lib/features/events/catering_customer_flow_screen.dart \
  lib/features/events/catering_customer_interest_screen.dart
flutter test test/features/events/catering_customer_pricing_test.dart \
  test/features/events/catering_customer_request_test.dart \
  test/features/events/catering_customer_flow_test.dart
```

The repository currently does **not** contain the project-specific generated
`lib/firebase_options.dart` file nor
`android/app/google-services.json`. `lib/main.dart` requires the former
and Android's Google Services plugin requires the latter. They must be
generated/copied from the **actual Gixbee Firebase project** for an APK build.

Run `flutterfire configure` against the correct Firebase project (or use the
existing project's verified configuration files) and confirm Android package
name `com.gixbeesolution`. Do not commit service-account private keys or
create synthetic Firebase IDs to make CI pass. Configure the CI build using
an approved secret store if Android compilation in CI is required.

After project configuration is available, build locally:

```bash
flutter pub get
flutter build apk --debug
```

The feature CI checks for these two files and warns if the build cannot
run. A **green unit-test job without a built APK is not an APK certification**.

## Manual development-db acceptance

1. Owner creates and publishes a live package and two individual dishes.
2. Customer searches for a serviceable city, picks a future date, guest
   count and per-plate budget, then opens the caterer's profile.
3. Customer reviews package menu groups, guest-tier offers and discounts.
4. Customer can pick exactly one package *or* up to 20 distinct dishes.
5. Customer submits a request with a valid venue, future start/end times
   and optional custom requirements, and sees an interest detail entry.
6. Rust independently reads the current catalogue prices and rejects a
   stale `expectedEstimate` when a price changes after selection.
7. Vendor offers a quote; customer can find it in My Interests and accept
   only the final vendor-confirmed amount.
8. Check duplicate requests with one `clientRequestId`, unauthorized
   vendors, inactive catalogue items, overlapping guest slabs and
   a full booking calendar.
9. Compare screenshots, spacing, filtering and mobile navigation with
   `GIXBEE-CATERING-CUSTOMER-FINALFLOW5.html`.

No new SQL schema migration is needed for this specific feature. The
provider's live availability and reviews are not guessed from the HTML
demo; show only values actually provided by the Rust service.
