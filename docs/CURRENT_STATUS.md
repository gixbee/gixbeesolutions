# Gixbee — Current Status

> **Single source of truth** for what is done vs still open.  
> Last updated: **2026-07-18**  
> Prefer this file over older archaeology in git history (April backlog dumps were deleted from `docs/` on 2026-07-18).

---

## Stack (actual)

| Layer | Tech |
|---|---|
| App | Flutter + Riverpod + Dio + Socket.IO + MapLibre (Ola) + FCM |
| API | NestJS 11 + TypeORM + Postgres + Redis + Bull + JWT |
| Admin | Angular 19 (`super-admin-web/`) |
| Themes | **Gixbee Dark** (violet shell) · **Grab Green** (light) via Profile → Appearance |

Theme tokens live in `lib/theme.dart` (`context.gx.*`). Auth/splash stay dark + brand-orange on purpose.

---

## Done (do not re-open)

### Security / correctness (July 2026)

See [AUDIT_2026-07-13.md](./AUDIT_2026-07-13.md) and [SECURITY_2026-07-13.md](./SECURITY_2026-07-13.md). Highlights:

- User PII / `fcmToken` / wallet stripped from API responses
- Wallet double-settle + lost-update races fixed (row locks)
- Unauthenticated hiring / business / applicant / OTP-leak / FCM-hijack endpoints fixed
- OTP echo only with explicit `ALLOW_OTP_ECHO` (blocked in production boot)
- Upload extension whitelist anchored; SVG excluded
- Redis OTP storage + verify (not “any 6 digits”)
- Firebase initialized in Flutter; FCM token registration on login path
- TypeORM `synchronize: !isProduction`

### Product modules that exist in code

| Area | Status |
|---|---|
| Home (intent / service quad, offers, location) | Done |
| Instant Help + broadcast request + waiting / tracking / OTPs | Done |
| Plan an Event + `showGxCalendar` | Done |
| Rentals catalog / detail / reserve (`showGxCalendar` + time picker) | Done |
| Go Live + incoming job queue | Done |
| Find a Job / talent / post job (full form) / hiring pipeline | Done |
| Business list + unit dashboard + hiring pipeline | Done |
| Messages (list + thread) | Done |
| Profile / wallet / favourites / about / support | Done (menus wired 2026-07-18) |
| Cities, addresses, favourites, support, payments module shells | Done |
| Dual theme (Gixbee Dark / Grab Green) surface + shell accents | Done (2026-07-18) |
| Demo Skip Login on welcome | **Removed** (2026-07-18) |
| Admin portal staff + page ACL | **Done** (2026-07-18) — create staff, map pages, role-based login |

---

## Still open — prioritized

### P0 — Production blockers

| Item | Notes |
|---|---|
| **SMS OTP** | MSG91/Twilio not wired — OTP only logged server-side without a provider |
| **Payments** | PhonePe/UPI/Razorpay return `needsApiKey` until credentials are set |
| **Aadhaar eKYC** | Pro ID verification still “coming soon” (Aadhaar OTP preferred over DigiLocker) |
| **Secrets ops** | Rotate weak local JWT/admin if any env is shared; never commit Firebase admin JSON |

### P1 — Backend residual (from July audit, still open)

| Item | Notes |
|---|---|
| `GET /bookings/my` | **Fixed** (2026-07-18) — single OR query + pagination |
| Rental overlap | **Fixed** (2026-07-18) — item row `pessimistic_write` + overlap check inside transaction |
| OTP verify | **Fixed** (2026-07-18) — atomic Redis GETDEL via `consumeOtp` |
| Unbounded `find()` | **Fixed** (2026-07-18) — `take` / `?page=&limit=` on rentals, wallets, disputes, applications; recommended talent capped + skill-prefilter |
| Rating average | **Fixed** (2026-07-18) — booking + profile `pessimistic_write` in transaction; re-rate idempotent |
| Serial FCM fan-out | **Fixed** (2026-07-18) — broadcast / job-match / accept-cancel / dispute use `sendToUsers` + `Promise.all` |
| `.gitignore` | Prefer `*firebase-adminsdk*.json` pattern at repo root |

### P2 — Product polish (partially addressed 2026-07-18)

| Item | Status |
|---|---|
| Dead profile menus / fake stats | **Fixed** — menus wired; real stats |
| Reels “Book Now” no-op | **Fixed** → Instant Request for role |
| Rental Material date picker | **Fixed** → `showGxCalendar` / `showGxTimePicker` |
| Silent empty catches | **Fixed** — `debugPrint` |
| Aggressive 3s poll | **Fixed** — 5s via `AppConfig` |
| Image decode size | **Improved** — `cacheWidth` on key screens |
| Full `cached_network_image` package | Optional follow-up |
| Remaining dark-hex screens outside migrated set | Gradual `context.gx` migration |

### P3 — Docs / process

| Item | Status |
|---|---|
| This file as status source of truth | **Done** |
| April backlog / extract dumps under `docs/` | **Removed** 2026-07-18 (recoverable via git) |

---

## Doc map

| Doc | Role |
|---|---|
| **This file** | Current open/closed truth |
| [AUDIT_2026-07-13.md](./AUDIT_2026-07-13.md) | July perf / race / leak audit |
| [SECURITY_2026-07-13.md](./SECURITY_2026-07-13.md) | July security audit + ops secret actions |
| [HOSTING_GUIDE.md](./HOSTING_GUIDE.md) | Hosting setup |
| [AWS_DEPLOYMENT.md](./AWS_DEPLOYMENT.md) | AWS deploy notes |
| [.README.md](../.README.md) | Product overview + setup |

April-era backlog / gap / extract dumps were removed from `docs/` (2026-07-18). Use git history if you need them.

---

## Quick verify

```bat
run_analyze2.bat
run_tsc.bat
```

Toggle Profile → Appearance (Gixbee Dark ↔ Grab Green) on Home / Bookings / Messages / Profile / Go Live.
