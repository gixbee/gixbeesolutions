# Gixbee Rust Backend

Drop-in replacement for `backend/` (NestJS). Same REST contract, JWT secrets, Redis keys, and Postgres schema.

## Quick start

```bash
# From repo root — uses BACKEND_IMPL from .env.example (default: rust)
make dev

# Explicit flip
BACKEND_IMPL=rust make dev
BACKEND_IMPL=nest make dev   # rollback
```

## Layout

Mirrors NestJS modules under `src/`:

- `auth/` — OTP, JWT, admin login
- `bookings/` — lifecycle, instant broadcast
- `payments/` — Razorpay orders + webhook
- `hiring/`, `matching/` — job board + Smart Hiring
- `workers/`, `worker_engine/` — Go Live + Socket.IO events

## API parity

Route paths and response keys are aligned with the NestJS controllers Flutter calls (`/hiring/jobs`, `/workers/live-toggle`, `{ favourited }`, etc.). Run contract tests against a live instance before flipping production traffic.

```bash
API_BASE=http://localhost:3000 cargo test --test contract
```

## Environment

Reads the same `backend/.env` as NestJS. Key vars: `JWT_SECRET`, `DATABASE_*`, `REDIS_*`, `MSG91_*`, `RAZORPAY_*`.
