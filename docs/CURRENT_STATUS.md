# Gixbee — Current Status

> **Single source of truth** for what is done vs still open.  
> Last updated: **2026-08-09**  
> Prefer this file over older archaeology in git history (April backlog docs were deleted from `docs/` on 2026-07-18).

---

## Stack (actual)

| Layer | Tech |
|---|---|
| App | Flutter + Riverpod + Dio + Socket.IO + MapLibre (Ola) + FCM |
| API | NestJS 11 + TypeORM + Postgres + Redis + Bull + JWT |
| Admin | Angular 19 (`super-admin-web/`) |
| Infra | Docker Compose · Nginx LB · PgBouncer · AWS EC2 `i-0263e6862a2e32e59` (`13.233.60.215`) · Beszel / Dozzle / pgAdmin |
| Themes | **Gixbee Dark** (violet shell) · **Grab Green** (light) via Profile → Appearance |

Theme tokens live in `lib/theme.dart` (`context.gx.*`). Auth/splash stay dark + brand-orange on purpose. Deploy via [`.agents/skills/gixbee_deploy/SKILL.md`](../.agents/skills/gixbee_deploy/SKILL.md).

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
- Admin page ACL + WS JWT hardening; throttler restored to sane defaults (2026-07)
- Socket rooms secured (2026-08-01): personal rooms derive identity from the
  verified JWT; job rooms require booking participation; only the assigned pro
  may publish GPS into a booking room.

### Product modules that exist in code

Every folder in `lib/features/` (17) is listed here, so a missing row means a missing flow.

| Flow (`lib/features/…`) | Status |
|---|---|
| `onboarding` splash / welcome, `auth` OTP login + registration | Done — Demo Skip Login **removed** (2026-07-18) |
| `home` (intent / service quad, offers, location) | Done |
| `booking` — Instant Help, broadcast, waiting, tracking, OTPs, pay | Done (+ late-cancel + petrol — see below) |
| `booking` — Plan an Event + `showGxCalendar` | Done |
| `rentals` catalog / detail / reserve (`showGxCalendar` + time picker) | Done |
| `worker` Go Live + incoming job queue | Done |
| `billing` job packs + credit history; period fee (Razorpay) | Done |
| `jobs` — Find a Job: board + **Smart Hiring** Job Types / Offers | Done (client wired 2026-08-09) |
| `business` list + **Hire Employee** Smart Hiring + classic board secondary | Done (client wired 2026-08-09) |
| `messages` (list + thread) | Done |
| `notifications` list + FCM push + badge | Done |
| `profile` / wallet / favourites / about / support | Done (menus wired 2026-07-18) |
| `search` → `worker_detail_screen` (pro profile from search results) | Done |
| `map` → `worker_directory_screen` (nearby pros); live tracking lives in `booking` | Done |
| `reels` → `worker_reels_screen` | Done — “Book Now” routes to Instant Request |
| `graph` → `skill_graph_screen` (skill relationship view) | Done |
| `common` shared shells and `gx_*` widgets | Done |
| Cities, addresses, favourites, support, payments module shells | Done |
| Dual theme (Gixbee Dark / Grab Green) | Done (2026-07-18) |
| Admin portal staff + page ACL | Done (2026-07-18) |
| Admin System Monitoring (Beszel + Dozzle + pgAdmin) | Done (2026-08-01) |
| Admin disputes / strikes / verifications / logs / master entries | Done |

### Shipped 2026-08-09 — Smart Hiring (Find a Job + Hire Employee)

| Area | What landed |
|---|---|
| **Candidate Job Types** | Flutter Job Types tab → `/hiring/match/preferences` (2 free; 3rd+ Razorpay ₹50; 7-day delete lock; immutable Job Type name) |
| **Offers** | Interested / Not Interested + Pending/Shortlisted/Rejected/Hired; FCM `hiring_offer` / `hiring_status` |
| **Employer Hire Employee** | Estimate slider, ₹49–399 Razorpay match fee, 24 h collecting, shortlist decisions, guarantee CREDIT (hiring credit balance) / REFUND (Razorpay) |
| **Gates** | VERIFIED HIRING business required to start matching; classic Post Job / board apps remain secondary |
| **Money model** | `HIRING_MATCH_FEE` + `EXTRA_JOB_TYPE_FEE` purposes; wallet stays OFF |

### Shipped 2026-07-18 → 2026-08-01 (live on EC2)

| Area | What landed |
|---|---|
| **Late-cancel protection** | Free cancel only while `REQUESTED` or within 3 min after accept. After grace: cancel request to worker, or force-cancel = late-cancel strike. After `ARRIVED`/`ACTIVE`: customer cannot cancel alone. 3 strikes → Instant Help blocked until distance-based travel compensation paid (Razorpay; ₹10/km, min ₹49 max ₹299; frozen on ban; recorded for worker payout — not an in-app wallet). |
| **Worker no-progress free cancel** | Progress GPS checks replace blanket GPS forfeit; if the pro is not making progress, customer may cancel free (`WORKER_NO_PROGRESS`). Migration `1754100000000-WorkerProgressGps`. |
| **Instant petrol billing** | Instant Help only: one-way ₹/km from `acceptDistanceKm`; rate from Master Entries `instant_petrol_per_km` (default **10**); frozen on booking as `petrolDistanceKm` / `petrolRatePerKm` / `petrolAmount`; work + petrol breakdown on collect/pay/OTP screens. Missing accept distance → petrol ₹0. Non-Instant unchanged. Migration `1754100000001-InstantPetrolBilling`. Deployed `f13db57`. |
| **Job pause removed** | Active-job pause/resume removed end-to-end; entity/API/outbox/payment remnants dropped; wall-clock billing only. Migration `1754100000002-RemoveBookingPause`. |
| **Realtime consolidation** | Socket.IO + FCM are primary; one shared 5s `bookingStatusProvider` remains as the Redis-backed status fallback. Payment screens no longer run extra 30s fetches; incoming jobs and `MainWrapper` use one HTTP reconciliation at startup/resume instead of 4s/5s periodic polling. |
| **Theme debt reduction** | Theme-sensitive shell accents, text, borders and surfaces in booking, jobs, worker, search and notification flows use `context.gx`; fixed colors remain only for semantic/category/brand meaning. |
| **Replica-safe schedulers** | With `replicas: 2` the outbox poller was already deduped by Bull (constant `jobId` + interval), but a changed interval/id would orphan the old repeatable in Redis forever — `OutboxDispatcher` now prunes non-matching repeatables at boot. The `system_logs` retention sweep, which really did run on both replicas, elects one runner via `RedisService.acquireLock()`. |
| **No blocking Redis `KEYS`** | Cache invalidation already used `SCAN`; the admin key browser's `KEYS *` is now a capped `SCAN` (default 1000) that reports `truncated` so the monitoring page can no longer stall production Redis. |
| **Redis / Socket.IO fail-closed** | Compose sets `REDIS_ALLOW_MEMORY_FALLBACK=false`. RedisService and Socket.IO refuse process-local memory when Redis is down (boot exits if the IO adapter cannot connect). Local single-process dev keeps the fallback when the flag is unset and `NODE_ENV != production`. |
| **Bounded admin lists** | Users + support tickets paginate (`page`/`limit`, shared `parsePagination`); master-entries cache miss hard-capped at 2000. |
| **Stable requestTimeout jobId** | Direct Instant booking timeout enqueue uses `jobId: requestTimeout:{bookingId}` (matches broadcast outbox path). |
| **PgBouncer contract** | TypeORM sets `statement_timeout=60s` + `application_name`; compose documents transaction-mode bans (LISTEN/NOTIFY / session locks / long-lived PREPARE) and `SERVER_RESET_QUERY=DISCARD ALL`. |
| **Money model source of truth** | `backend/src/common/money-model.ts` — wallet OFF; defaults to `CASH`; recharge/hiring charges gated; live paths are dual-confirm job pay + Razorpay period fee / late-cancel. |
| **Aadhaar preference** | Pro verify UI + talent stub prefer Aadhaar OTP/eKYC over DigiLocker (still credential-blocked until KYC keys). |
| **Go Live hardening** | Verification gate, credits/period fee, force offline at limits, location gate, skills editing. |
| **pgAdmin** | Embedded under `/infra/pgadmin/` in admin monitoring (path/SCRIPT_NAME + healthcheck fixes). |
| **Ops** | EC2 disk prune (~80% free after cleanup); backend replicas healthy after petrol deploy. |

---

## Still open — prioritized

### P0 — Production blockers

| Item | Notes |
|---|---|
| **SMS OTP** | MSG91/Twilio not wired — OTP only logged server-side without a provider |
| **Payments** | PhonePe/UPI/Razorpay return `needsApiKey` until credentials are set (period fee + late-cancel compensation need live Razorpay keys) |
| **Aadhaar eKYC** | Pro ID verification still “coming soon” (Aadhaar OTP preferred over DigiLocker) |
| **Secrets ops** | Rotate weak JWT/admin/DB/pgAdmin defaults if any env is shared; never commit Firebase admin JSON |

### P1 — Ops / infra follow-ups

| Item | Notes |
|---|---|
| **Grow EBS volume** | Disk was tight; prune helped — still prefer larger root volume for image builds |
| **Rotate default passwords** | pgAdmin / DB defaults used for bootstrap — rotate in prod |
| **Flutter APK rollout** | Petrol + late-cancel UI need new APK install on devices (backend already live) |

### P1 — Known product bugs

| Item | Notes |
|---|---|
| **Call button** | **Fixed** — live tracking dials role-aware `counterpartPhone` (status API + booking fetch fallback); detail screen reads `phoneNumber` |
| **Busy worker still offered jobs** | **Fixed** — Instant Help fan-out uses live `worker:status` (not stale snapshot); accept/arrived/active all count as busy; targeted book blocked for those too |
| **Release APK loopback default** | **Fixed** — release/profile boot asserts non-loopback `API_BASE_URL` / `SOCKET_URL` (`AppConfig.assertReleaseNetworkConfig`) |

### P1 — Backend residual (from July audit)

| Item | Notes |
|---|---|
| `GET /bookings/my` | **Fixed** (2026-07-18) — single OR query + pagination |
| Rental overlap | **Fixed** (2026-07-18) |
| OTP verify | **Fixed** (2026-07-18) — atomic Redis GETDEL via `consumeOtp` |
| Unbounded `find()` | **Fixed** (2026-07-18) |
| Rating average | **Fixed** (2026-07-18) |
| Serial FCM fan-out | **Fixed** (2026-07-18) |
| Redis `KEYS` | **Fixed** — `SCAN` everywhere; admin browser capped at 1000 keys |
| Duplicate schedulers | **Fixed** — Bull repeatables pruned at boot; log purge behind a Redis lock |
| Redis / Socket.IO memory split | **Fixed** — fail-closed when `REDIS_ALLOW_MEMORY_FALLBACK=false` |
| Unbounded admin reads | **Fixed** — users/support paginated; master-entries capped at 2000 |
| requestTimeout without jobId | **Fixed** — stable `jobId` on direct Instant create |
| PgBouncer session caveats | **Documented + guarded** — statement_timeout; no LISTEN/NOTIFY in codebase |
| **Stale backend specs** | Several suites still fail against current code (e.g. `auth/jwt.strategy` predates admin `pages`/`staffRole`; `payments.service` methods renamed). Unrelated to shipped behaviour — the specs need rewriting to match. |
| `.gitignore` | Prefer `*firebase-adminsdk*.json` pattern at repo root |

### P2 — Product polish

| Item | Status |
|---|---|
| Dead profile menus / fake stats | **Fixed** — menus wired; real stats |
| Reels “Book Now” no-op | **Fixed** → Instant Request for role |
| Rental Material date picker | **Fixed** → `showGxCalendar` / `showGxTimePicker` |
| Silent empty catches | **Fixed** — `debugPrint` |
| Duplicate polling | **Fixed** — socket/FCM primary; one shared 5s booking fallback; pending queue reconciles only at startup/resume |
| Image decode size | **Improved** — `cacheWidth` on key screens |
| Full `cached_network_image` package | Optional follow-up |
| Remaining fixed colors | Booking shell chrome on `context.gx` (live track / waiting / incoming / OTP / cancel / rate). Left intentional: Plan Event category colors + pink brand, map pin shadows, success `accentGreen`, Material `colorScheme.error` |
| Soft-fail empty booking lists | **Fixed** — `getMyBookings` / `getPendingBookings` rethrow; Active tab + home card show retry on API error |

### P3 — Docs / process

| Item | Status |
|---|---|
| This file as status source of truth | **Done** — refresh on each shipped feature set |
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
| [gixbee_deploy skill](../.agents/skills/gixbee_deploy/SKILL.md) | EC2 Instance Connect deploy command |

April-era backlog / gap / extract dumps were removed from `docs/` (2026-07-18). Use git history if you need them.

---

## Quick verify

```bat
run_analyze2.bat
run_tsc.bat
```

Toggle Profile → Appearance (Gixbee Dark ↔ Grab Green) on Home / Bookings / Messages / Profile / Go Live.
