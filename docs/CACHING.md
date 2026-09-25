# Gixbee caching (Rust release backend + Flutter app)

Source implementation only — not runtime-verified in this pass.

## Overview

Caching extends the existing **Redis** layer (`backend_rust/src/redis.rs`) with a **cache-aside** module (`backend_rust/src/cache/`). Correctness mechanisms (OTP consume, worker geo indexes, booking pending sets, rate-limit locks) are unchanged and still require Redis; read-cache failures fall back to PostgreSQL.

**Persisted invalidation** uses table `cache_versions` (domain → monotonic `version`). Redis keys embed the current version so admin edits never rely on bundled catalogue JSON alone.

Public read responses may include **ETag** + short **Cache-Control**; clients may send **If-None-Match** for `304 Not Modified`.

---

## Domains and TTLs

| Domain | Postgres key | Default TTL | Env override |
|--------|----------------|------------|--------------|
| `hiring_master` | `hiring_master` | 24h | `CACHE_HIRING_MASTER_TTL_SECS` (default 86400) |
| `location_master` | `location_master` | 24h (empty search 5m) | `CACHE_LOCATION_SEARCH_TTL_SECS`, `CACHE_LOCATION_EMPTY_TTL_SECS` |
| `service_master` | `service_master` | 6h (1–24h) | `CACHE_SERVICE_MASTER_TTL_HOURS` |
| `public_listings` | `public_listings` | 2m (1–5m) | `CACHE_PUBLIC_LISTING_TTL_MINUTES` |

TTLs use ±10% jitter on write. Hiring estimate (display only): `CACHE_HIRING_ESTIMATE_TTL_SECS` (15–30s, default 20).

---

## Redis key shape

```
gx:v1:{domain}:{version}:{fnv1a64(key_suffix)}
```

Envelope value: `{"v": <version>, "body": <json>}`.

Write-after-load compares DB version at start vs end; if version changed, **skip Redis write** (prevents stale repopulation).

**Coalescing:** `lock:gx:v1:…` via existing `RedisStore::acquire_lock` (NX, 8s).

**Ephemeral (no domain version):** `gx:v1:est:{userId}:{hash}` for hiring match estimates.

**User-scoped (preferences):** `gx:v1:user:{userId}:prefs` — invalidated on profile create/update; cleared on logout in Flutter.

---

## Cached HTTP endpoints

### Hiring master (active vs inactive separated in key suffix)

- `GET /hiring/catalogue` — `snapshot:active` / `snapshot:inactive`; response includes `cacheVersion` + `bundledVersion`
- `GET /hiring/catalogue/positions` — sector, query, limit, offset, include_inactive
- `GET /hiring/catalogue/positions/:id`

### Location search

- `GET /hiring/locations/search` — normalized query, limit, offset, location-master version (query max 80 chars; limit max 40)

### Service master

- `GET /cities?isActive=…`
- `GET /master-entries?type&isActive&category&cityId`

### Public listings (display only)

- `GET /rentals?cityId&lat&lng&radiusKm&businessId` — list/catalog only

**Not cached:** `GET /rentals/:id` (reservations/availability), authenticated business/event/plan routes, payments, hiring match offers, talent/contact, booking status.

### Version probe

- `GET /cache/versions` — all domain counters (for app refresh)

---

## Invalidation triggers

| Trigger | Domain bumped |
|---------|----------------|
| Hiring catalogue import (in TX) | `hiring_master` |
| Hiring admin CRUD (sectors, positions, specs, skills, qualifications, languages, aliases, employment, position-skills) | `hiring_master` — **same DB transaction** as the mutation (`commit_hiring_cache_tx`) |
| Location admin create/patch/alias | `location_master` — **same DB transaction** (`commit_location_cache_tx`) |
| GeoNames import script | `location_master` (end of `import-hiring-locations.py` transaction) |
| Cities CRUD | `service_master` |
| Master entries CRUD | `service_master` |
| Rental item create/update (owner) | `public_listings` |

After location **SQL backfill/import** scripts that change `hiring_locations` or aliases, run admin location patch/import **or** manually:

```sql
UPDATE cache_versions SET version = version + 1, "updatedAt" = NOW()
WHERE domain IN ('location_master');
```

(same pattern for other domains if data changed outside the API).

---

## Failure behaviour

| Scenario | Behaviour |
|----------|-----------|
| Redis timeout (~250ms) or error on **get** | DB load; `CacheOutcome::Fallback`; request succeeds |
| Redis error on **set** | Response still returned; no cache populate |
| Malformed cache JSON | Treated as miss |
| Redis unavailable with `REDIS_ALLOW_MEMORY_FALLBACK=false` | Locks/OTP/geo still fail as today; read cache falls back to DB where implemented |
| Redis unavailable with fallback enabled | In-memory KV for cache keys only within single process |

Observability: `tracing` target `cache` at **debug** (hit/miss/fallback/stale_version/skip_write) — no raw search text or PII in logs.

---

## Flutter app caching

| Data | Mechanism |
|------|-----------|
| Hiring snapshot | `hiringCatalogueSnapshotProvider` — keepAlive 24h; invalidates on `cacheVersion` change |
| Pro trades / master entries | Existing `proTradesProvider` keepAlive 10m; cities `citiesProvider` keepAlive 6h |
| Location search pages | `AppDataCache` LRU (max 32 keys); stale UI guard remains in `HiringLocationSearch` |
| Logout / forced logout | `AppDataCache.clearAll()` |

Form drafts remain in widget state / existing flows — not stored in shared master cache.

---

## Preserved dynamic caches (unchanged semantics)

- **Nearby worker counts** — `nearby:counts:{lat}:{lng}` ~45s (`workers/mod.rs`)
- **Booking status** — Redis + outbox; delayed updates must not regress terminal states (`bookings/progress.rs`)
- **FCM token** — Redis user key
- **Matching config** — optional Redis read in match engine

**Authoritative paths (never read cache for decisions):** payment verification/webhooks, hiring credit balance, paid entitlement, rental reservation holds, booking state transitions, final candidate notify batch (DB query at send time), catalogue validation on submit.

---

## Environment variables

```
CACHE_HIRING_MASTER_TTL_SECS=86400
CACHE_SERVICE_MASTER_TTL_HOURS=6
CACHE_LOCATION_SEARCH_TTL_SECS=86400
CACHE_LOCATION_EMPTY_TTL_SECS=300
CACHE_PUBLIC_LISTING_TTL_MINUTES=2
CACHE_HIRING_ESTIMATE_TTL_SECS=20
```

Existing: `REDIS_URL`, `REDIS_ALLOW_MEMORY_FALLBACK`.

---

## Deployment steps (manual)

1. Run migration `1756300000000-CacheVersions.ts` **or** `scripts/cache_versions.sql` on PostgreSQL.
2. Deploy Rust backend (includes `ensure_table` bootstrap if migration pending).
3. Deploy Flutter app (optional; backward compatible with uncached responses).
4. After bulk location catalogue import/backfill, bump `location_master` version (admin API or SQL above).

---

## Manual verification checklist

- [ ] Admin edits hiring sector → `GET /cache/versions` hiring_master increments; app snapshot refreshes after version change
- [ ] Active vs inactive hiring snapshot keys differ (`include_inactive`)
- [ ] Location search: fast typing / selection still correct; cached pages respect version bump
- [ ] Account switch / logout clears app master cache; preferences refetch per user
- [ ] Stop Redis: public catalogue endpoints still load from DB; OTP/booking locks still fail closed in production config
- [ ] Rental list cache expires within configured minutes; edit listing bumps version
- [ ] Payment / booking / hire notify still use live DB (no cache in authorize path)
- [ ] Hiring estimate may repeat for ~20s per user+query — not used for billing

---

## Implemented vs not / limitations

**Implemented:** Redis cache-aside for hiring/service masters, location search, cities, master entries, rental catalog list; persisted versions + ETags; coalescing + stale-write guard; short hiring estimate cache; Flutter LRU + catalogue provider; logout cache clear; profile user-scope invalidation hook.

**Not cached:** Rental detail/availability, business GET (auth-filtered), events, messages, hiring offers/interests, worker directory, payments, NestJS-only routes if not proxied to Rust.

**Limitations:** No CDN; no Redis key SCAN/prefix purge (version bump only); in-memory fallback not shared across replicas; `GET /master-entries` without filters still cacheable but heavy — admin should avoid unfiltered polling; renamed specializations still need explicit legacy map entries; runtime behaviour not validated in CI here.
