# Gixbee completion checklist

Started 10 September 2026. Release target: **Rust**, selected by the user. Reference: [four-flow review](GIXBEE_V147_FOUR_FLOW_REVIEW.md). Existing auth/logout edits are preserved.

Testing and deployment owner: **the user**, confirmed 11 September 2026. Implementation work includes local code, migrations and handover instructions. Do not run additional tests or deploy. Items below distinguish implementation from the user's pending validation.

## Implementation

- [ ] Rust builds locally and has repeatable isolated database tests.
- [ ] Business registration, ownership, moderation, staff permissions and calendar persist correctly.
- [ ] Rental pricing, availability and role-specific transitions are correct under concurrency.
- [ ] Rental quantity, delivery, handover, return and settlement are connected to business inventory and Flutter.
- [ ] Career profiles persist all supported matching criteria with correct free/paid entitlement rules.
- [ ] Hiring requests enforce business ownership and payment; candidate privacy and employer decisions are protected.
- [ ] Hiring interview, offer and joining outcomes are visible to both participants.
- [ ] Scheduled event plans retain date, guests and every service; vendor packages/quotes and capacity reservations have a complete lifecycle.
- [ ] Customer and business screens expose those journeys with loading, empty, error and recovery states.
- [ ] Deferred events/deadlines recover after restart and support multiple replicas.
- [ ] Admin operations, migrations and release checks support the implemented flows.
- [ ] Build, analysis and relevant end-to-end/contract checks pass.

## Operating and release dependencies

- [ ] Pilot city, service areas, verified supply and operating hours are configured.
- [ ] Live provider credentials, payment reconciliation and notification delivery are verified.
- [ ] Required migrations are committed before the Rust binary is released.
- [ ] Consenting real-device pilot confirms fulfillment and issue resolution.

Prototype subscription prices and response guarantees are not automatically adopted. Existing implemented commercial rules remain the baseline until a concrete change is agreed. Each item stays open until implemented and validated; this checklist is not a claim that the whole platform is complete.
