# Rust ↔ Nest Backend Parity Tracker

Goal: **every** Nest capability available on `BACKEND_IMPL=rust` with identical HTTP contracts and Socket.IO events.

## Status legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Complete / verified |
| 🟡 | Partial — routes exist but logic simplified or stubbed |
| ❌ | Missing or not wired |
| 🔌 | Socket.IO / background job |

---

## Global infrastructure

| Feature | Nest | Rust | Status |
|---------|------|------|--------|
| Validation pipe (whitelist) | `ValidationPipe` | per-handler | 🟡 |
| Class serializer | global | manual JSON | 🟡 |
| Exception filter envelope | `AllExceptionsFilter` | `AppError` | ✅ |
| Throttle 120/min | `ThrottlerGuard` | stub middleware (unwired) | ❌ |
| API request logging | `ApiLoggingInterceptor` | `api_logging_middleware` | ✅ |
| Static `/uploads` | `ServeStaticModule` | `ServeDir` | ✅ |
| `POST /uploads/image` | `UploadController` | `uploads` module | ✅ |
| Redis required (multi-replica) | yes | yes | ✅ |
| Socket.IO + Redis adapter | `@socket.io/redis-adapter` | `socketioxide` + `socketioxide-redis` | 🔌 🟡 in progress |
| Bull queue `outbox` | `OutboxDispatcher` | tokio poller (no handler) | 🔌 🟡 |
| Bull queue `bookings` | `BookingsProcessor` | — | 🔌 ❌ |
| Bull queue `hiring` | `HiringMatchProcessor` | — | 🔌 ❌ |
| FCM push | `NotificationsService` | stub | ❌ |
| Razorpay order API | `PaymentsService` | local DB orders only | 🟡 |
| Razorpay webhook fulfillment | credits/wallet/hiring | status update only | 🟡 |

---

## Socket.IO events

| Gateway | Client → Server | Server → Client | Rust |
|---------|-----------------|-----------------|------|
| Messages | `joinUserRoom` | `joinedUserRoom`, `new_message`, `new_booking_request`, `booking_accepted`, `booking_status_update` | ❌ |
| Worker | `updateLocation`, `joinJobRoom`, `leaveJobRoom` | `locationUpdated`, `joined`, `left` | ✅ |
| Voice | — | — | ⏭️ Not required (intentionally excluded from Rust backend) |

---

## Module checklist

### auth ✅
All 7 routes implemented.

### users (`/admin-user-list`) ✅
All routes implemented.

### admin-staff 🟡
Missing: `GET /pages`, `GET /me`. Update only toggles `isActive`.

### workers 🟡
Missing/stub: geo `nearby`/`nearby-counts`, strikes detail/appeal, `pay-period-fee`, admin strike resolve, `/{id}/packages`.

### worker-engine 🔌 ❌
Not mounted.

### bookings 🟡
Stub: cancel workflow variants, completion OTP verify, ratings, disputes, admin disputes, confirm, refresh-completion-otp.

### outbox 🔌 🟡
Poller marks `DISPATCHED` without side effects.

### wallets ✅ (feature-flagged off)
Matches dormant-wallet contract.

### billing/credits 🟡
`create-order` / `verify` stubbed (no Razorpay).

### payments 🟡
Orders created locally; webhook doesn't fulfill balances.

### notifications ❌
No FCM send.

### messages 🟡
Wrong paths (`/threads` vs `/conversations`). No socket push on send.

### voice-calls ⏭️
Intentionally not ported to Rust (product decision).

### hiring 🟡
`jobs/matched` returns all jobs (no matching).

### hiring/match 🟡
CRUD only; no batch/finalize processor.

### talent 🟡
Aadhaar/Surepass production path stubbed.

### businesses 🟡
Calendar offline days stubbed.

### rentals ✅

### favourites ✅

### addresses ✅

### cities ✅

### master-entries ✅

### support ✅

### redis/admin 🟡
`keys` returns empty array.

### system-logs ✅

### system-metrics ❌
Hardcoded empty samples.

### sms (internal) ✅
Via `auth` + MSG91.

---

## Implementation waves

1. **Realtime core** — Socket.IO (3 gateways), Redis adapter, emit hub, JWT handshake
2. **Outbox + jobs** — booking lifecycle handler, delayed job scheduler (90s timeout, 7m reminder, GPS check), hiring match batch/finalize
3. **Notifications** — FCM via service account
4. **Payments** — Razorpay REST order create + webhook fulfillment
5. **Bookings** — full cancel workflow, OTP gates, ratings, disputes
6. **Workers** — geo index, strikes, packages, period fee
7. **Route fixes** — messages, admin-staff, throttle middleware
8. **Monitoring** — system-metrics, redis admin keys scan
9. **Contract tests** — expand `backend_rust/tests/contract.rs` against Nest fixtures

---

## Notes

- `socketioxide-redis` uses a different Redis protocol than `@socket.io/redis-adapter`; fine for Rust-only replicas, not for mixing Nest + Rust Socket.IO on the same cluster.
- Flutter clients use standard `socket.io-client` — compatible with `socketioxide`.
