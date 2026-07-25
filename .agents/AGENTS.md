# Gixbee Project Rules, Architecture & Publishing Guide

This document defines mandatory operational procedures, system architecture, deployment instructions, and coding standards for all AI agents working on the Gixbee repository.

---

## 🏗️ 1. Codebase Architecture & Directory Map

Gixbee is an on-demand service platform consisting of three containerized/native ecosystems:

### Mobile Client (`lib/`) — Flutter & Riverpod
- **State Management**: Always use Riverpod (`flutter_riverpod`) for state and dependency injection.
- **Navigation Guardrail**: For out-of-context navigation (e.g., Dio HTTP interceptor redirecting to `/welcome` on `401 Unauthorized`), use the global `rootNavigatorKey` defined in `lib/core/navigator_key.dart`. Do NOT create circular dependencies between `dioProvider` and auth state.
- **Real-Time GPS & Maps**: Live tracking (`lib/features/booking/live_tracking_map_screen.dart`) relies on bi-directional Socket.IO streams (`lib/services/socket_service.dart`) and Google/Ola Maps services (`lib/services/ola_maps_style_service.dart`).
- **Crash Reporting**: Keep `CrashReporter` (`lib/services/crash_reporter.dart`) initialized in `main.dart` to transmit unhandled widget/platform exceptions to `POST /client-logs` as `APP_CRASH`.

### Backend API (`backend/src/`) — NestJS, PostgreSQL & Redis
- **Stack & Ports**: Runs on port `3000` via Docker Compose (`gixbee_backend`). Connects to PostgreSQL 16 (`gixbee_postgres:5432`) and Redis 7 (`gixbee_redis:6379`).
- **Transactional Outbox Pattern**: All booking lifecycle state changes MUST emit events via `OutboxService` (`backend/src/outbox/`). The `OutboxDispatcher` handles reliable WebSocket notifications and background tasks.
- **WebSocket Scaling**: Uses `RedisIoAdapter` (`backend/src/redis/`) for real-time worker GPS broadcasting and instant job matching (`backend/src/worker-engine/`).
- **Logging & Monitoring**: System logs and mobile client crash reports are processed in `backend/src/system-logs/` and monitored via `backend/src/system-metrics/`.

### Super Admin Portal (`super-admin-web/src/`) — Angular & Nginx
- **Stack & Ports**: Served on port `80` via Docker Compose (`gixbee_admin`).
- **UI Architecture**: Standard Angular standalone components in `src/app/features/`. Maintain custom badge styling in `logs.component.ts` for distinct error visualization (e.g., pink `APP_CRASH` badges).

---

## 📦 2. How to Build & Publish Android APK

When building the release APK, **do NOT rely on `build_apk.bat`** if running in environments subject to terminal encoding or interactive prompt issues. Instead, run the Flutter build command directly with the required `--dart-define` environment flags:

```powershell
flutter build apk --release --dart-define=OLA_MAPS_API_KEY=Vr2MnNlJ6LrLXTrkPOe8mbNjXuEC30NmUy52rfi4 --dart-define=API_BASE_URL=http://13.233.60.215:3000 --dart-define=SOCKET_URL=http://13.233.60.215:3000
```

- **Output Location**: `build\app\outputs\flutter-apk\app-release.apk`
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
