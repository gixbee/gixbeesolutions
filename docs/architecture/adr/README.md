# Architecture Decision Records (ADRs)

Lightweight records of significant architectural choices. Format: Context → Decision → Consequences.

| ADR | Title | Status |
|---|---|---|
| [001](./001-wallet-off-razorpay-direct.md) | Wallet OFF — Direct Razorpay for platform fees | Accepted |
| [002](./002-realtime-socket-fcm-outbox.md) | Realtime: Socket.IO + FCM + transactional outbox | Accepted |
| [003](./003-pgbouncer-transaction-pooling.md) | PgBouncer transaction pooling | Accepted |
| [004](./004-intent-based-user-model.md) | Intent-based user model | Accepted |
| [005](./005-auth-redis-otp-jwt.md) | Auth: Redis OTP + JWT (REST/WS) | Accepted |
| [006](./006-payments-razorpay-webhook-only.md) | Payments: Razorpay webhook-only | Accepted |
| [007](./007-aadhaar-surepass-ekyc.md) | Aadhaar eKYC: Surepass, masked storage | Accepted (creds pending) |
| [008](./008-v147-profiles-alerts-ux.md) | v147 UX: profiles + alerts on Smart Hiring API | Proposed |
| [009](./009-rust-backend-drop-in.md) | Rust backend drop-in + `BACKEND_IMPL` switch | Accepted |

When adding an ADR:
1. Copy the next number (`005-…`)
2. Link from [../ARCHITECTURE.md](../ARCHITECTURE.md)
3. Notify god if the decision affects security, money, or cross-team contracts
