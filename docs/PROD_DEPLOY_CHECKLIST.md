# Gixbee — Production deploy readiness checklist

> **Purpose:** Pre-flight checklist before turning on live gateways on EC2.  
> **Do not paste real secrets into git, Slack, or chat** — set values only in  
> `/home/ec2-user/gixbeesolutions/backend/.env` on the server (or via a secure vault).  
> Last updated: **2026-08-28** (P0 wiring: MSG91, Razorpay, Surepass Aadhaar).

See also: [HOSTING_GUIDE.md](./HOSTING_GUIDE.md) · [AWS_DEPLOYMENT.md](./AWS_DEPLOYMENT.md) · [SECURITY_2026-07-13.md](./SECURITY_2026-07-13.md) · [gixbee_deploy skill](../.agents/skills/gixbee_deploy/SKILL.md).

---

## Quick status

| Item | Code | Ops action |
|---|---|---|
| MSG91 login OTP | Done (`SmsService`) | Set `MSG91_*` on EC2 |
| Razorpay payments | Done (`isRealSecret` guards) | Set `RAZORPAY_*` on EC2 + webhook |
| Aadhaar eKYC | Done (`AadhaarKycService`) | Set `AADHAAR_*` + run migration |
| `NODE_ENV=production` | **Wrong in compose today** | Change `docker-compose.yml` (below) |
| Release APK Razorpay | Flutter `AppConfig.razorpayKey` | Rebuild via `gixbee_keys.bat` |

---

## 1. Fix `NODE_ENV` in Docker Compose

**Problem:** `docker-compose.yml` hard-codes `NODE_ENV: development` on the backend service (line ~207). That disables:

- TypeORM `migrationsRun` (migrations only auto-run when `NODE_ENV=production`)
- Production boot guards in `main.ts` (weak JWT/admin/MSG91/Razorpay checks)
- OTP echo protection semantics tied to production mode

**Fix on EC2** (after pulling latest `main`):

```yaml
# docker-compose.yml → backend.environment
NODE_ENV: production
```

Also ensure `backend/.env` does **not** override `NODE_ENV` back to `development`.

**Verify after restart:**

```bash
docker compose exec backend printenv NODE_ENV
# expect: production

docker compose logs backend --tail 50
# expect: no [FATAL] insecure config; migrations should run at boot
```

---

## 2. Run migration `1754600000000-WorkerMaskedAadhaar`

Adds `maskedAadhaar` to `worker_profiles` (masked UID reference after Surepass eKYC).

**Automatic path** (preferred once `NODE_ENV=production`):

- TypeORM `migrationsRun: true` in `app.module.ts` runs all pending migrations on backend boot.

**Manual path** (if boot fails before migrations run):

```bash
cd /home/ec2-user/gixbeesolutions/backend
docker compose exec backend npm run migration:run
# or, from host with DB access:
# psql … -c 'ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "maskedAadhaar" varchar;'
```

**Verify:**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'worker_profiles' AND column_name = 'maskedAadhaar';
```

---

## 3. EC2 secret rotation & gateway env vars

**File:** `/home/ec2-user/gixbeesolutions/backend/.env`  
**Loaded by:** `docker-compose.yml` → `backend.env_file`

### 3.1 Core secrets (rotate if ever shared or default)

| Variable | Requirement | How to generate |
|---|---|---|
| `JWT_SECRET` | ≥ 32 chars, not default | `openssl rand -base64 48` |
| `ADMIN_USERNAME` | Not `admin` | Choose a non-obvious username |
| `ADMIN_PASSWORD` | ≥ 12 chars, not `admin` | Password manager |
| `DATABASE_PASSWORD` | Strong, unique | Rotate if bootstrap default used |
| Firebase service account | `firebase-service-account.json` on host | Regenerate in Firebase console |

**Boot guard:** With `NODE_ENV=production`, backend **refuses to start** if JWT/admin defaults or `ALLOW_OTP_ECHO=true` are set (`main.ts`).

### 3.2 MSG91 (login OTP SMS)

| Variable | Notes |
|---|---|
| `MSG91_AUTH_KEY` | Dashboard auth key |
| `MSG91_TEMPLATE_ID` | DLT-approved template with OTP variable (`{#var#}` or `##OTP##`) |
| `MSG91_SENDER_ID` | Optional; default `GIXBEE` |

**Smoke:** `POST /auth/request-otp` with a real phone → SMS received (no `devOtp` in response).

### 3.3 Razorpay (server)

| Variable | Notes |
|---|---|
| `RAZORPAY_KEY_ID` | Live: `rzp_live_*` (not `placeholder_*`) |
| `RAZORPAY_KEY_SECRET` | Live secret from dashboard |
| `RAZORPAY_WEBHOOK_SECRET` | From Razorpay webhook settings |

**Webhook URL:** `https://<your-api-host>/payments/webhook` → events: `payment.captured` (and `order.paid` if enabled).

**Smoke:** `GET /payments/gateway-status` → `razorpay.available: true`, `needsApiKey: false`.

### 3.4 Surepass Aadhaar eKYC

| Variable | Notes |
|---|---|
| `AADHAAR_CLIENT_ID` | Surepass client id |
| `AADHAAR_CLIENT_SECRET` | Surepass bearer token |
| `AADHAAR_API_BASE` | Omit in prod (auto: `https://kyc-api.surepass.app`) |

**Smoke:** `GET /talent/verification/status` (JWT) → `available: true`; complete generate/submit OTP flow on Register Pro.

### 3.5 Rotation procedure (any secret)

1. Generate new value in provider console.
2. Update `backend/.env` on EC2 (single writer).
3. `docker compose up -d --build backend` (see deploy skill).
4. Revoke old key in provider console after smoke passes.
5. For `JWT_SECRET` rotation: all existing refresh tokens invalidate — users re-login once.

---

## 4. Release APK — `RAZORPAY_KEY` rebuild

The Flutter app bakes the **publishable** Razorpay key at compile time (`AppConfig.razorpayKey`). The backend uses `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` separately.

**Local file (not in git):** `gixbee_keys.bat`

```bat
set RAZORPAY_KEY=rzp_live_XXXXXXXXXXXX
```

`gixbee_keys.bat` appends `--dart-define=RAZORPAY_KEY=…` to `GX_DEFINES` used by `build_apk.bat`.

**Rebuild steps:**

1. Set `RAZORPAY_KEY` in `gixbee_keys.bat` (must match live key id from Razorpay dashboard).
2. Confirm `API_BASE_URL` / `SOCKET_URL` point at production (not loopback).
3. Run `build_apk.bat`.
4. Distribute `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
5. Install: `adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`

**Note:** Unset/placeholder `RAZORPAY_KEY` does **not** block app boot (warns only); period-fee / job-pack checkouts fail until rebuilt with live key.

**iOS:** see `ios/BUILD.md` for equivalent `--dart-define=RAZORPAY_KEY=rzp_live_…`.

---

## 5. Deploy sequence (recommended order)

- [ ] Pull latest `main` on EC2 (`7bb7fda` or later — P0 backend commit)
- [ ] Set `NODE_ENV: production` in `docker-compose.yml`
- [ ] Rotate/set all secrets in `backend/.env` (section 3)
- [ ] `docker compose up --build -d backend` + `docker image prune -f`
- [ ] Confirm backend healthy + migration applied (sections 1–2)
- [ ] Configure Razorpay webhook → `/payments/webhook`
- [ ] Backend smoke: login OTP SMS, gateway-status, Aadhaar status endpoint
- [ ] Rebuild release APK with `RAZORPAY_KEY` (section 4)
- [ ] Device smoke: login → Register Pro Aadhaar → period-fee checkout (Dwight checklist)

---

## 6. Rollback

- Revert `docker-compose.yml` `NODE_ENV` change and redeploy previous image tag.
- DB migration `1754600000000` is additive (`ADD COLUMN IF NOT EXISTS`) — safe to leave in place on rollback.
- Revoke newly issued API keys in provider consoles if deploy is aborted mid-rotation.

---

## Doc map update

| Doc | Role |
|---|---|
| **This file** | Prod credential + NODE_ENV + migration + APK checklist |
| [CURRENT_STATUS.md](./CURRENT_STATUS.md) | Feature open/closed truth |
| [SECURITY_2026-07-13.md](./SECURITY_2026-07-13.md) | Why JWT/admin rotation matters |
