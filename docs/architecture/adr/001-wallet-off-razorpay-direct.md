# ADR-001: Wallet OFF — Direct Razorpay for Platform Fees

**Status:** Accepted  
**Date:** 2026-07 (codified in `money-model.ts`)  
**Deciders:** Product + backend

## Context

Gixbee originally modeled in-app wallet settlement (customer → worker via platform balance). This adds regulatory, reconciliation, and race-condition complexity. Job settlement in the Indian market is predominantly cash/UPI direct to the pro.

## Decision

Set `WALLET_PAYMENTS_ENABLED = false` in `backend/src/common/money-model.ts`.

**Live payment paths:**

1. **Job settlement** — customer pays pro directly (cash/UPI). App records dual-confirm via `markPaid`. Instant Help adds frozen one-way petrol charge on the booking.
2. **Go Live access** — Razorpay checkout for `PERIOD_FEE` → job credit batch.
3. **Late-cancel compensation** — Razorpay `LATE_CANCEL_COMPENSATION` after 3 strikes.
4. **Smart Hiring** — Razorpay `HIRING_MATCH_FEE` / `EXTRA_JOB_TYPE_FEE`; guarantee credits land in `users.hiringCreditBalance`.

**Default:** new bookings use `DEFAULT_BOOKING_PAYMENT_METHOD = 'CASH'`.

Wallet module code remains behind the flag for a potential future product return.

## Consequences

**Positive**
- Simpler settlement; no platform float for job amounts
- Fewer wallet race conditions (July audit fixes remain for dormant path)
- Clear separation: Razorpay = Gixbee fees; cash/UPI = pro payment

**Negative**
- No in-app escrow or automated worker payout for job amounts
- Flutter still ships `wallet_repository` / wallet screens (mostly dormant UX)
- Re-enabling wallet requires coordinated backend + Flutter + compliance review

## Compliance

Any change that adds wallet charges must:
1. Flip `WALLET_PAYMENTS_ENABLED` deliberately
2. Update this ADR and `CURRENT_STATUS.md`
3. Re-audit `BookingSettlementService` and `WalletsService` for row locks
