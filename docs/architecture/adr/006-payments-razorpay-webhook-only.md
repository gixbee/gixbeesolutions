# ADR-006: Payments — Razorpay Webhook-Only Fulfillment

**Status:** Accepted  
**Date:** 2026-08-28 (gateway guards + hiring purposes)  
**Deciders:** Backend + product (see ADR-001 for wallet OFF)

## Context

Gixbee collects platform fees via Razorpay while job amounts settle cash/UPI direct to pros (wallet OFF). Client-side payment success callbacks are spoofable; webhook HMAC verification is the trust boundary.

PhonePe/UPI integration remains a stub.

## Decision

### Trust boundary

```
App: POST /payments/*/order → PaymentOrder (CREATED) + razorpayOrderId
App: Razorpay Checkout (client key from --dart-define=RAZORPAY_KEY)
Razorpay: POST /payments/webhook (raw body HMAC) → atomic CREATED → CREDITED → fulfil by purpose
```

**Client success callback never credits anything.**

`main.ts` enables `rawBody: true` for webhook signature verification. Webhook uses `@SkipThrottle`.

### Gateway readiness

`GET /payments/gateway-status` (via `getGatewayStatus()`):

| Field | Meaning |
|---|---|
| `wallet.available` | `false` while `WALLET_PAYMENTS_ENABLED=false` |
| `cash.available` | `true` — default job settlement |
| `razorpay.available` | `true` only when `isRealSecret()` on key id + secret |
| `upi.available` | `false` (stub) |

Production boot requires real Razorpay keys or process exits.

### Live `PaymentPurpose` values (wallet OFF)

| Purpose | Trigger | Fulfilment |
|---|---|---|
| `PERIOD_FEE` | Go Live period fee | Job credit batch reset |
| `LATE_CANCEL_COMPENSATION` | 3-strike unblock | Unblocks Instant Help; records worker payout |
| `HIRING_MATCH_FEE` | Hire Employee match | Creates `HiringRequest`; starts matching |
| `EXTRA_JOB_TYPE_FEE` | 3rd+ Job Type | Creates paid `JobPreference` |
| `WALLET_RECHARGE` | Dormant | Blocked when wallet OFF |

### Flutter contract

| Backend | Client |
|---|---|
| `GET /payments/gateway-status` | `payments_repository` — payment picker UX |
| `POST /payments/period-fee/order` | `job_credits_repository` |
| `POST /payments/late-cancel/order` | booking unblock screens |
| `POST /hiring/match/...` (order via matching) | `matching_repository` |
| `RAZORPAY_KEY` dart-define | Razorpay Flutter SDK |

Release APK warns (does not crash) on placeholder Razorpay key; checkout screens surface errors.

## Consequences

**Positive**
- Idempotent webhook claim prevents double-credit
- Clear separation: Razorpay = Gixbee fees; cash = pro payment
- `isRealSecret()` rejects `placeholder_*` at boot and runtime

**Negative**
- Requires live webhook secret + public URL on EC2
- Wallet recharge endpoints exist but are dead paths — confusing for new devs
- PhonePe/UPI stub may mislead if UI copy isn't gated on `gateway-status`

## Contract recommendations

1. **Oscar:** new fee types need new `PaymentPurpose` enum + webhook fulfilment branch + migration if metadata stored
2. **Pam:** always read `gateway-status` before showing Razorpay checkout; friendly copy when `needsApiKey`
3. **Ryan/god:** EC2 must expose webhook path through Nginx; rotate `RAZORPAY_WEBHOOK_SECRET` with provider dashboard
