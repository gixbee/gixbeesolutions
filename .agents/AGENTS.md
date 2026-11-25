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

### Backend API (`backend_rust/`) — Axum, PostgreSQL & Redis
- **Stack & Ports**: Rust API on port `3000` via Docker Compose (`backend_rust`, network alias `api`). PostgreSQL 18 + PgBouncer + Redis 7.
- **Config**: `deploy/.env` and `deploy/firebase-service-account.json` (see `deploy/.env.example`).
- **Schema**: SQL bundles under `scripts/` (not TypeORM). Apply on deploy before/restart API containers.
- **Replicas**: Scale `backend_rust` to 2; background jobs and Redis locks must be idempotent (`REDIS_ALLOW_MEMORY_FALLBACK=false` in compose).
- **WebSockets**: JWT-scoped Socket.IO rooms; never trust client-supplied user ids for room membership.
- **PgBouncer**: Transaction pooling only — no session-scoped Postgres features across transactions.
- **Product rules**: Wallet settlement OFF; dual-confirm job pay; Razorpay for platform charges; no pause workflow; petrol on Instant Help; stage-gated cancel + strikes.
- **Reference**: `backend_rust/README.md`, `docs/architecture/rust-nest-parity.md`.

### Super Admin Portal (`super-admin-web/src/`) — Angular & Nginx
- **Stack & Ports**: Served on port `80` via Docker Compose (`gixbee_admin`).
- **UI Architecture**: Standard Angular standalone components in `src/app/features/`. Maintain custom badge styling in `logs.component.ts` for distinct error visualization (e.g., pink `APP_CRASH` badges).
- **Admin Features Index (14 Modules in `src/app/features/`)**: `auth`, `bookings`, `businesses`, `cities`, `dashboard`, `disputes`, `infrastructure`, `logs`, `master-entries`, `staff`, `strikes`, `support`, `users`, `verifications`. `infrastructure` embeds Beszel, Dozzle, and pgAdmin (`/infra/pgadmin/`).

---

## 📦 2. How to Build & Publish Android APK

When building the release APK, **do NOT rely on `build_apk.bat`** if running in environments subject to terminal encoding or interactive prompt issues. Instead, run the Flutter build command directly with the required `--dart-define` environment flags:

```powershell
flutter build apk --release --dart-define=OLA_MAPS_API_KEY=Vr2MnNlJ6LrLXTrkPOe8mbNjXuEC30NmUy52rfi4 --dart-define=API_BASE_URL=http://103.102.234.152:3000 --dart-define=SOCKET_URL=http://103.102.234.152:3000
```

- **Output Location**: `build\app\outputs\flutter-apk\app-release.apk`
- **Fail-closed**: release/profile builds refuse to start if `API_BASE_URL` / `SOCKET_URL` are still loopback (`127.0.0.1` / `localhost` / `10.0.2.2`). Always pass the dart-defines above (or use `build_apk.bat`, which loads `gixbee_keys.bat`).
- **Dependency Warnings Notice**: When `flutter pub get` or APK builds output `"X packages have newer versions incompatible with dependency constraints"`, **do NOT automatically run `flutter pub upgrade`**. In production, keep dependency version constraints locked in `pubspec.yaml` to ensure build stability unless an upgrade is explicitly requested by the user.

---

## 🚀 3. How to Deploy / Publish Backend to MilesWeb

Production is the MilesWeb VPS only. Follow [`.agents/skills/gixbee_deploy/SKILL.md`](skills/gixbee_deploy/SKILL.md).

- **Host**: `103.102.234.152`
- **SSH user**: `root`
- **App directory**: `/root/gixbeesolutions`
- **API**: `http://103.102.234.152:3000`
- **Admin**: `http://103.102.234.152/`
- **Deploy script**: `scripts/milesweb_sync_and_deploy.sh`

Do not deploy to Azure or AWS.

---

## 🛡️ 4. Coding Standards & Lints

- **Zero Analyze Issues**: Always ensure `flutter analyze` returns **0 issues** after making modifications. Do not leave unused imports, unused local variables, or deprecated widget parameters (e.g., use `activeThumbColor` instead of deprecated `activeColor` on `Switch` widgets).
- **Global Navigation (401 / Interceptors)**: When triggering navigation from outside widget contexts (such as in Dio interceptors upon `401 Unauthorized`), use `rootNavigatorKey` defined in `lib/core/navigator_key.dart` to push users to `/welcome`. Do NOT introduce circular Riverpod dependencies between `dioProvider` and auth state providers.
- **Client Crash Reporting**: All unhandled Flutter widget exceptions and async platform errors must be captured via `CrashReporter` (`lib/services/crash_reporter.dart`) and transmitted to `POST /client-logs` with type `APP_CRASH`.
