# Gixbee Project Rules, Architecture & Publishing Guide

This document defines mandatory operational procedures, system architecture, deployment instructions, and coding standards for all AI agents working on the Gixbee repository.

---

## 🏗️ 1. Codebase Architecture & Directory Map

Gixbee is an on-demand service platform consisting of three containerized/native ecosystems:

### Mobile Client (`lib/`) — Flutter & Riverpod
- **State Management**: Always use Riverpod (`flutter_riverpod`) for state and dependency injection.
- **Navigation Guardrail**: For out-of-context navigation (e.g., Dio HTTP interceptor redirecting to `/welcome` on `401 Unauthorized`), use the global `rootNavigatorKey` defined in `lib/core/navigator_key.dart`. Do NOT create circular dependencies between `dioProvider` and auth state.
- **Real-Time GPS & Maps**: Live tracking (`lib/features/booking/live_tracking_map_screen.dart`) relies on bi-directional Socket.IO streams (`lib/services/socket_service.dart`) and Google/Ola Maps services (`lib/services/ola_maps_style_service.dart`).
- **Realtime State**: Socket.IO + FCM are primary. `bookingStatusProvider` is
  the only periodic booking-status fallback (shared per booking). Pending worker
  offers use socket/FCM plus one HTTP reconciliation at startup/resume; do not
  add screen-local polling timers.
- **Theme Tokens**: Use `context.gx` for shell accents, surfaces, borders, and
  text. Keep fixed `GixbeeTheme` colors only for semantic intent (success,
  warning, danger) and auth/wordmark branding.
- **Crash Reporting**: Keep `CrashReporter` (`lib/services/crash_reporter.dart`) initialized in `main.dart` to transmit unhandled widget/platform exceptions to `POST /client-logs` as `APP_CRASH`.
- **Client Features Index (17 Modules in `lib/features/`)**: `auth`, `billing`, `booking`, `business`, `common`, `graph`, `home`, `jobs`, `map`, `messages`, `notifications`, `onboarding`, `profile`, `reels`, `rentals`, `search`, `worker`.

### Backend API (`backend/src/`) — NestJS, PostgreSQL & Redis
- **Stack & Ports**: Runs on port `3000` via Docker Compose (`gixbee_backend`). Connects to PostgreSQL 16 (`gixbee_postgres:5432`) and Redis 7 (`gixbee_redis:6379`).
- **Transactional Outbox Pattern**: All booking lifecycle state changes MUST emit events via `OutboxService` (`backend/src/outbox/`). The `OutboxDispatcher` handles reliable WebSocket notifications and background tasks.
- **Replica-Safe Schedulers**: The backend runs `replicas: 2`, so every module
  boots its schedulers twice. Bull repeatables MUST pass a constant `jobId` and
  interval so all replicas collapse onto one entry — changing either value
  orphans the old repeatable in Redis, where it keeps firing across deploys, so
  `OutboxDispatcher` prunes non-matching repeatables before registering. Plain
  `setInterval` sweeps MUST elect a single runner via
  `RedisService.acquireLock()` (see the `system_logs` retention purge) and stay
  idempotent, since the lock degrades to per-process when Redis is down.
- **WebSocket Scaling**: Uses `RedisIoAdapter` (`backend/src/redis/`) for real-time worker GPS broadcasting and instant job matching (`backend/src/worker-engine/`).
- **Never Call Redis `KEYS`**: It is O(N) over the whole keyspace and blocks
  Redis's single thread, stalling Bull dispatch and every other caller. Use
  `RedisService.keys()` (cache invalidation) or `getAdminKeys()` (admin
  browser, capped) — both iterate with `SCAN`.
- **Redis / Socket.IO fail-closed with replicas**: Compose sets
  `REDIS_ALLOW_MEMORY_FALLBACK=false`. Do not re-enable memory fallback on a
  multi-replica deploy — OTP, locks, and Socket.IO rooms would silently split
  per process. Local single-process dev may omit the flag (allowed when
  `NODE_ENV != production`) or set it `true` explicitly.
- **PgBouncer transaction pooling**: Backend talks to Postgres via PgBouncer
  (`POOL_MODE=transaction`). Never use session-scoped Postgres features
  (`LISTEN`/`NOTIFY`, session advisory locks, named `PREPARE` that outlive a
  transaction). Keep work inside TypeORM transactions / single queries.
  `statement_timeout=60s` is set on each connection.
- **WebSocket Authorization**: All client room handlers use `WsJwtGuard`.
  Personal room names come only from the verified JWT. Joining `job_<bookingId>`
  requires the JWT user to be that booking's customer or operator, and only the
  assigned operator may publish GPS to it. Never trust socket body `userId`.
- **Logging & Monitoring**: System logs and mobile client crash reports are processed in `backend/src/system-logs/` and monitored via `backend/src/system-metrics/`.
- **Database Entities Index (27 Tables)**: `User`, `Booking`, `WalletTransaction`, `WorkerProfile`, `WorkerStrike`, `RentalItem`, `RentalReservation`, `JobPost`, `JobApplication`, `HiringRequest`, `HiringInterest`, `JobPreference`, `Business`, `TalentProfile`, `ProfessionalSkill`, `MasterEntry`, `Message`, `Favourite`, `Address`, `City`, `SupportTicket`, `AdminStaff`, `OutboxEvent`, `SystemLog`, `PaymentOrder`, `JobCredit`, `CreditTransaction`.
- **Server Modules Index (25 Modules)**: `Users`, `Auth`, `WorkerEngine`, `Bookings`, `Wallets`, `Workers`, `Billing`, `Notifications`, `Redis`, `Rentals`, `Hiring`, `Businesses`, `Talent`, `MasterEntries`, `Messages`, `Payments`, `Favourites`, `Addresses`, `Cities`, `Support`, `AdminStaff`, `SystemLogs`, `SystemMetrics`, `Outbox`, `Uploads`.
- **Money Model (source of truth)**: See `backend/src/common/money-model.ts`.
  `WALLET_PAYMENTS_ENABLED` is **false**. Live money paths:
  (1) Job settlement = customer pays pro directly (cash/UPI) + dual-confirm
  `markPaid` — default `paymentMethod` is `CASH`, never invent `WALLET`;
  (2) Worker Go Live = job credits + period fee via **direct Razorpay**;
  (3) Late-cancel compensation = **direct Razorpay**. Wallet transfer /
  recharge / hiring `charge()` / welcome bonus stay dormant behind the flag —
  flip the constant (one place) when the wallet product returns. Do not add
  new wallet debits while the flag is off.
- **Booking Billing Rules**: Completion bills wall-clock work time (no pause). Instant Help also adds a **one-way petrol charge** — `acceptDistanceKm × instant_petrol_per_km` (Master Entries, default `10`) — frozen on the booking as `petrolDistanceKm` / `petrolRatePerKm` / `petrolAmount`. No accept distance means no petrol; non-Instant bookings are unaffected.
- **No Pause Workflow**: Pause/resume was retired. Do not add pause fields to
  booking entities, status payloads, outbox events, or payment UI. Migration
  `1754100000002-RemoveBookingPause` drops the former columns.
- **Cancel Rules**: Customer cancels are stage-gated (free while `REQUESTED` or within the 3-minute post-accept grace; then worker-approved cancel request or a late-cancel strike; no unilateral cancel after `ARRIVED`/`ACTIVE`). Three strikes block Instant Help until distance-based compensation is paid. A worker who is not making GPS progress unlocks a free cancel (`WORKER_NO_PROGRESS`).

### Super Admin Portal (`super-admin-web/src/`) — Angular & Nginx
- **Stack & Ports**: Served on port `80` via Docker Compose (`gixbee_admin`).
- **UI Architecture**: Standard Angular standalone components in `src/app/features/`. Maintain custom badge styling in `logs.component.ts` for distinct error visualization (e.g., pink `APP_CRASH` badges).
- **Admin Features Index (14 Modules in `src/app/features/`)**: `auth`, `bookings`, `businesses`, `cities`, `dashboard`, `disputes`, `infrastructure`, `logs`, `master-entries`, `staff`, `strikes`, `support`, `users`, `verifications`. `infrastructure` embeds Beszel, Dozzle, and pgAdmin (`/infra/pgadmin/`).

---

## 📦 2. How to Build & Publish Android APK

When building the release APK, **do NOT rely on `build_apk.bat`** if running in environments subject to terminal encoding or interactive prompt issues. Instead, run the Flutter build command directly with the required `--dart-define` environment flags:

```powershell
flutter build apk --release --dart-define=OLA_MAPS_API_KEY=Vr2MnNlJ6LrLXTrkPOe8mbNjXuEC30NmUy52rfi4 --dart-define=API_BASE_URL=http://13.233.60.215:3000 --dart-define=SOCKET_URL=http://13.233.60.215:3000
```

- **Output Location**: `build\app\outputs\flutter-apk\app-release.apk`
- **Fail-closed**: release/profile builds refuse to start if `API_BASE_URL` / `SOCKET_URL` are still loopback (`127.0.0.1` / `localhost` / `10.0.2.2`). Always pass the dart-defines above (or use `build_apk.bat`, which loads `gixbee_keys.bat`).
- **Dependency Warnings Notice**: When `flutter pub get` or APK builds output `"X packages have newer versions incompatible with dependency constraints"`, **do NOT automatically run `flutter pub upgrade`**. In production, keep dependency version constraints locked in `pubspec.yaml` to ensure build stability unless an upgrade is explicitly requested by the user.

---

## 🚀 3. How to Deploy / Publish Backend to AWS EC2

The production backend and database run via Docker Compose on AWS EC2 Amazon Linux 2023 (`13.233.60.215`).
- **EC2 Instance ID**: `i-0263e6862a2e32e59`
- **OS User**: `ec2-user`
- **Server Repository Directory**: `/home/ec2-user/gixbeesolutions`

### Step A: Push local changes to GitHub
```powershell
git add .
git commit -m "feat: description of changes"
git push origin main
```

### Step B: Automated Deployment via AWS EC2 Instance Connect
Once changes are pushed to `main`, use the AWS CLI with EC2 Instance Connect to temporarily authorize your public key and execute the pull and container rebuild directly in PowerShell:

```powershell
aws ec2-instance-connect send-ssh-public-key --instance-id i-0263e6862a2e32e59 --instance-os-user ec2-user --ssh-public-key file://C:\Users\gkv00\.ssh\gixbee-ec2.pub ; ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no ec2-user@13.233.60.215 "cd /home/ec2-user/gixbeesolutions && git pull origin main && docker compose up --build -d backend && docker compose ps"
```

### Manual Deployment on Server Terminal
If connecting manually over SSH as `ec2-user`, run:
```bash
cd /home/ec2-user/gixbeesolutions
git pull origin main
docker compose up --build -d backend
docker compose ps
docker compose logs -f --tail=50 backend
```

---

## 🛡️ 4. Coding Standards & Lints

- **Zero Analyze Issues**: Always ensure `flutter analyze` returns **0 issues** after making modifications. Do not leave unused imports, unused local variables, or deprecated widget parameters (e.g., use `activeThumbColor` instead of deprecated `activeColor` on `Switch` widgets).
- **Global Navigation (401 / Interceptors)**: When triggering navigation from outside widget contexts (such as in Dio interceptors upon `401 Unauthorized`), use `rootNavigatorKey` defined in `lib/core/navigator_key.dart` to push users to `/welcome`. Do NOT introduce circular Riverpod dependencies between `dioProvider` and auth state providers.
- **Client Crash Reporting**: All unhandled Flutter widget exceptions and async platform errors must be captured via `CrashReporter` (`lib/services/crash_reporter.dart`) and transmitted to `POST /client-logs` with type `APP_CRASH`.

---

## 5. Cloud Agent local development

Cloud Agents do not use Docker Compose. On boot, Postgres 16 and Redis 7 listen on localhost, the Nest API listens on port 3000, and the Angular admin dev server listens on port 4200. The gitignored `backend/.env` is created on boot when it is missing. Local database name is `gixbee_db` (user `postgres`, password `gixbee123`, matching Compose). Admin portal login is the `ADMIN_USERNAME` / `ADMIN_PASSWORD` pair in that file.

`npm run start:dev` currently fails typecheck in `backend/src/bookings/booking-cancel.service.ts` (`st !== 'IN_PROGRESS'` is not a `BookingStatus`). The boot script runs the API with `ts-node-dev --transpile-only` so schema sync and hot reload still work. `cd backend_rust && cargo build --bin gixbee-backend` is the Rust backend; it expects the Nest-synchronized schema. Flutter is on `PATH` (`flutter test`, `flutter analyze`). Do not run `flutter pub upgrade`.
