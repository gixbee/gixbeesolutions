# Gixbee business-flow implementation status

9 September 2026 • Scope selected: business flow plus implementation, one Indian city, Instant Help first.

Read [the business blueprint](GIXBEE_BUSINESS_FLOW.md) for positioning, customer/professional journeys, operating queues, monetization, failure handling, pilot economics and the hiring/event/rental expansion flows.

## Implemented in this change

| Area | Result | Main code |
| --- | --- | --- |
| Customer request | Location → presence → task → language → budget → **review** → explicit confirmation. A task description or selected issue is required. The final review uses the same values submitted to the API. | `lib/features/booking/instant_request_screen.dart`, `instant_booking_review.dart` |
| Upfront explanation | Exact offered hourly rate, one-hour minimum, elapsed-minute billing, separate travel/materials, direct cash/UPI payment, OTP meanings and cancellation consequences. Corrected the claim that an onsite contact automatically receives the OTP. | Booking review and request screens |
| No supply | Honest retry/change-service/home options, with no unsupported promise that supply will appear in a few minutes. | `lib/features/booking/no_workers_screen.dart` |
| Worker credits | Both backends quote ₹49 for credits equivalent to three accepts at the current cost. Default: 45 credits at 15 credits/accept. Existing balances are not modified. Acceptance credits and the separate Go Live period fee remain distinct. | Nest `billing/job-credits.service.ts`; Rust `billing/purchases.rs` |
| Credit checkout | Real Razorpay order, stored account ownership and entitlement, checkout signature validation and provider API check for captured payment, correct amount/order/currency/payment reference. | Nest `billing/job-pack-payments.service.ts`; Rust `billing/purchases.rs` |
| Payment recovery | Signed captured-payment webhooks and authenticated callback verification share an atomic credit transaction: order lock, balance, credit receipt and fulfilled state. Generic fee fulfillment excludes credit packs. A duplicate delivery cannot intentionally grant the pack again. | Billing purchase services and payment webhook handlers |
| Worker purchase UI | Riverpod data loading, real pack details, credits and current supported accepts, error/retry states, refresh on resume, pending-payment check and credit history. Failed API loads no longer invent a purchasable pack. Checkout declines changed pack details until reviewed again. | `lib/features/billing/job_pack_screen.dart`, `lib/repositories/job_credits_repository.dart` |
| Credit history | Rust now returns the Flutter/Nest contract: transactions with delta, booking link/skill and timestamp; pagination; summed credits used/refunded per booking. | `backend_rust/src/billing/mod.rs` |
| Direct service payment | Both runtimes lock and read the booking inside the confirmation transaction and write the outbox event in that transaction. Rust only accepts the appropriate participant's confirmation metadata. Nest repairs a stale unpaid cache from the database. | Booking settlement/status services; Rust booking handlers |
| Travel-price consistency | New acceptances freeze rate, distance and travel quote. Completion retains the accepted rate if admin configuration changes during the job. Status exposes the saved quote; legacy jobs fall back to current configuration. | Booking claim, settlement and status handlers |
| Identity trust | Removed Rust's fabricated OTP/client ID and automatic VERIFIED response. Unimplemented automated verification now returns unavailable and does not alter verification records. Manual review and the real Nest provider integration are separate paths. | `backend_rust/src/talent/mod.rs` |

The commercial correction is deliberate: the former Nest pack contained 3 credits for ₹49 while the screen said 3 jobs and acceptance cost defaulted to 15 credits. Rust advertised a different ₹299/30-credit pack with placeholder checkout. New orders now use the same ₹49/three-current-accepts contract on both runtimes. The purchase snapshots credits, not a permanent promise that future acceptance costs will never change. No wallet or service-value commission was added.

## Validation

- Nest backend build passed.
- 121 tests passed across eight selected Nest suites covering credit purchases, signed webhook wiring, booking acceptance/completion, frozen travel pricing, payment confirmation/status and payment controllers.
- Nine Flutter tests passed across four files. They cover the full request-to-review-to-submit flow, small-screen review layout, pack API failures/contracts and existing cash/UPI payment screens.
- `flutter analyze`: **No issues found**. Two existing analyzer issues were corrected with one-line changes (a string interpolation and a deprecated dropdown argument). The existing city-autocomplete edits in `job_types_screen.dart` were preserved.
- `git diff --check` passed.

These are local build, unit and widget checks. Repository/database collaborators are mocked in the Nest tests; they do not prove real PostgreSQL locking under concurrent load. No live payment, OTP, notification, migration or deployment was performed. Existing `load-tests/node_modules` changes were not part of this implementation.

Rust source has matching payment-validation unit tests, but they could not run here: Cargo/Rust are not installed on the available PATH and the Docker Linux engine was unavailable. The Rust changes require compilation, formatting and real PostgreSQL contract tests before deployment. Windows Flutter was found through `android/local.properties`, and its installed SDK was used without upgrading dependencies.

## Required release work

| Priority | Work | Acceptance evidence |
| --- | --- | --- |
| P0 | Select and configure the actual pilot city, areas, categories, hours and verified supply. No city name was guessed or production configuration changed. | A customer and eligible professional can complete a consenting pilot booking in each opened area/category. |
| P0 | Apply `1754800000000-JobCreditPayments.ts` through the existing migration process before enabling new purchases. Confirm schema compatibility on the selected runtime. | Payment purpose accepts JOB_CREDITS; an order and its balance/receipt commit successfully on the real DB. Rust does not run Nest migrations automatically. |
| P0 | Reconcile older in-flight credit purchases before rollout. Old Nest JOB_PACK orders were not stored in payment_orders; this change does not backfill them or trust an unknown callback. | Provider order/payment and previous credit receipt identify the owner and whether credits were already granted; manually resolve outstanding legacy orders once. |
| P0 | Configure test/live provider credentials and captured-payment webhook delivery, and exercise restart/retry/concurrency against PostgreSQL. | Captured order with app closed credits once; malformed/wrong-owner/amount/currency events do not; two simultaneous callbacks do not double-credit. |
| P0 | Complete durable Rust scheduling and proper outbox processing claims before choosing Rust for paid launch. Existing process-local sleeps can lose search/progress deadlines on restart. Nest already has Bull scheduling but still needs delivery/claim testing. | API/worker restart during both search waves and accepted progress checks recovers the deadline; replica delivery does not duplicate strikes or financial effects. |
| P0 | Verify identity, skill approval and admin operations on the selected runtime. Audit existing Rust verification records created through the retired stub; do not automatically revoke real users without evidence/review. | A new professional cannot Go Live without required checks; an authorized reviewer can approve/reject with a recorded reason. Automated KYC never claims success without real verification. |
| P0 | Resolve remaining Rust authorization/parity gaps if that runtime will expose hiring/business/admin routes. | Ownership and admin-action contract tests reject unrelated users, including routes not prominent in the pilot UI. |
| P0 | Test a real-device fulfillment and issue-resolution journey. | Notifications resume the correct booking; OTP starts/ends work; bill and travel match; both payment confirmations persist; no-show/cancel/report reaches a staffed admin queue. |
| P1 | Replace chat-based extra-scope agreement with a versioned change-order record when materials and complex tasks require it. | Customer approves scope and amount before the new work is included in the bill. |
| P1 | Build operational metrics, compensation payout reconciliation and measurable service-area expansion gates. | Daily supply, fulfillment, confirmation lag, disputes, worker earnings and contribution can be reconciled from records. |
| Later | Implement the event-specific enquiry/quote/calendar/milestone flow, rental condition/deposit/extension flow and hiring interview/offer/joining experience in the blueprint. | Separate lifecycle and exception tests for each vertical before marketing it as fully supported. |

The business blueprint is complete for the agreed scope. This change implements the request, pricing and payment improvements above; it does **not** certify the entire platform or the live service as launch-ready. The release items are outstanding implementation/operating work, not claims of completed functionality.
