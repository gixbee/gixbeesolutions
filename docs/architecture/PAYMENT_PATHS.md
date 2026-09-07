# Payment paths — live vs dormant

> **Status source of truth:** [../CURRENT_STATUS.md](../CURRENT_STATUS.md)  
> **Decisions:** [adr/001-wallet-off-razorpay-direct.md](./adr/001-wallet-off-razorpay-direct.md) · [adr/006-payments-razorpay-webhook-only.md](./adr/006-payments-razorpay-webhook-only.md)  
> **Gap:** ARCH-004 in [GAPS.md](./GAPS.md)  
> Last updated: **2026-08-30**

Wallet settlement is **OFF** in shipped code (`WALLET_PAYMENTS_ENABLED = false` in `backend/src/common/money-model.ts`). Job pay is dual-confirm cash/UPI with the pro; Razorpay is for platform charges only.

---

## Gateway readiness API

`GET /payments/gateway-status` (`payments.service.ts` `getGatewayStatus()`):

| Field | Shipped value | Meaning |
|---|---|---|
| `wallet.available` | `false` | In-app wallet charges disabled |
| `cash.available` | `true` | Pay pro directly |
| `razorpay.available` | `true` when live keys set | Period fee, late-cancel, job packs, hiring fees |
| `upi.available` | `false` | PhonePe in-app UPI stub |

Flutter `payment_repository.dart` currently parses **UPI only** in `GatewayStatus.fromJson` — see ARCH-003 in GAPS.

---

## Live Razorpay paths (webhook fulfilment)

Server creates a Razorpay Order; **only** `POST /payments/webhook` (HMAC-verified) credits the user / unlocks jobs.

| Purpose | Create order | Fulfilment |
|---|---|---|
| Go Live period fee | `POST /payments/period-fee/order` | Webhook → reset `jobsSincePayment` |
| Late-cancel compensation | `payments_repository.dart` → payments module | Webhook |
| Job credit packs | `billing/job-credits` controller | Webhook |
| Hiring match / extra job type | Hiring matching module | Webhook in `payments.service.ts` |

Client checkout uses `razorpay_flutter` with publishable key from `AppConfig.razorpayKey` (`--dart-define=RAZORPAY_KEY` at APK build).

---

## Go Live period fee — dual path (ARCH-004)

**Production path (use this):**

1. Flutter `go_live_screen.dart` → `createPeriodFeeOrder()` → Razorpay checkout
2. Razorpay webhook unlocks the next job batch

**Legacy path (returns 400 when wallet OFF — fixed 2026-08-30):**

- `POST /workers/me/pay-period-fee` (`workers.controller.ts` L182)
- `worker-golive.service.ts` L419–422 throws with message to use `POST /payments/period-fee/order`

**Dev fallback (still open — Pam):**

- `go_live_screen.dart` L494–496: on “not configured”, calls `_payPeriodFeeViaWallet()` which hits the legacy endpoint above

**Ops:** configure live Razorpay on EC2 + rebuild APK with live key. **Code follow-up (Oscar/Pam):** remove wallet fallback; 404 legacy endpoint when wallet OFF.

---

## Dormant wallet paths

| Surface | Status |
|---|---|
| `WalletsService.charge` / recharge | Throws when `WALLET_PAYMENTS_ENABLED=false` |
| `wallet_screen.dart` | Orphan UI — no nav route in `lib/`; top-up copy misleading if re-linked |
| `payment_method_screen.dart` | Orphan; defaults `_method = 'WALLET'` |
| `POST /payments/...` wallet recharge | Gated in payments service when wallet OFF |

---

## Verify (local)

```bat
run_tsc.bat
```

Backend smoke (with JWT):

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:3000/payments/gateway-status
# expect wallet.available: false, razorpay.available depends on .env keys
```
