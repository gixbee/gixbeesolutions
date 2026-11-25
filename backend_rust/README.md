# Gixbee Rust Backend

Production API (Axum + SQLx + Socket.IO). Same REST contract and Postgres schema the Flutter app and admin portal expect.

## Quick start

```bash
# From repo root
cp deploy/.env.example deploy/.env
make dev
```

## Layout

Modules under `src/`: `auth`, `bookings`, `payments`, `hiring`, `matching`, `workers`, `worker_engine`, …

## Contract tests

```bash
API_BASE=http://localhost:3000 cargo test --test contract
```

## Environment

Reads `deploy/.env` via Docker Compose (`JWT_SECRET`, `DATABASE_*`, `REDIS_*`, `MSG91_*`, `RAZORPAY_*`, …).

## Schema

Apply SQL in `scripts/` on the MilesWeb VPS (see `scripts/milesweb_sync_and_deploy.sh`).