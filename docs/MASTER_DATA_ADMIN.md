# Gixbee master data admin

Source-level documentation for the Angular `super-admin-web` portal, Rust release backend (`backend_rust`), Nest migrations (`backend/src/migrations`), and cache invalidation. Not runtime-verified in this pass.

## Architecture trace

```
super-admin-web → /api/* (proxy) → backend_rust handlers
  → PostgreSQL mutation + master_data_audit row + cache_versions bump (one transaction)
  → Redis cache-aside keys versioned on next read
  → Flutter app: GET /cache/versions + TTL / resume refresh
```

Public catalogue reads stay on existing GET routes with ETags (`docs/CACHING.md`).

---

## Sections

| Section | Admin route | Permission | Primary tables / source | Cache domain |
|--------|-------------|------------|------------------------|--------------|
| Hiring catalogue | `/hiring-catalogue` | `master-entries` | `hiring_*` tables, bundled JSON import | `hiring_master` |
| Service catalogue | `/service-catalogue` | `master-entries` | `master_entries` (PRO_TRADE, PRO_SUB_SKILL, CATEGORY, SERVICE, ROLE) | `service_master` |
| Location master | `/location-master` | `master-entries` | `hiring_locations`, `hiring_location_aliases` | `location_master` |
| Serviceable areas | `/cities` | `cities` | `cities` (UUID IDs for businesses/events/rentals) | `service_master` |
| Rental catalogue | `/rental-catalogue` | `master-entries` | Rust enums in `rentals/listing.rs`; items on operational rentals screens | `service_master` (labels via master entries) |
| Event catalogue | `/event-catalogue` | `master-entries` | `events::SERVICES` const; plans/quotes operational | — (read-only meta) |
| Pricing & policies | `/pricing-policies` | `pricing-policies` or SUPER_ADMIN | `master_entries` CONFIGURATION keys | `service_master` |
| Operational settings | `/operational-settings` | `operational-settings` or SUPER_ADMIN | `master_entries` CONFIGURATION keys | `service_master` |
| Content & reasons | `/content-reasons` | `master-entries` | `master_entries` BANNER, DEAL, CONFIGURATION copy | `service_master` |
| All entries | `/master-entries` | `master-entries` | `master_entries` | `service_master` |

Audit history: `GET /api/master-admin/audit?section=&limit=&offset=` (requires `master-entries`).

---

## Hiring catalogue

**API:** `/api/hiring/catalogue/*`, `/api/hiring/catalogue/admin/*`, import `POST …/admin/import`.

**Relationships:** sector↔position (`hiring_sector_positions`), position↔specialization/skill/qualification (qualification is global list + single `qualificationId` on profiles/requests; no position–qualification junction table).

**Rules:** Stable string IDs; bundled import idempotent; legacy map read-only via `GET …/admin/legacy-map`; deactivation via `isActive` (no hard delete of referenced positions). Shared positions preserved via `shared` flag and import logic.

**Validation:** Required ids/labels on create; admin permission on all mutations.

---

## Service catalogue

Managed primarily through **Master Entries** with types PRO_TRADE / PRO_SUB_SKILL / CATEGORY / SERVICE / ROLE. Paginated admin browse: `GET /api/master-entries/admin/list`.

**Deletes:** `DELETE /master-entries/:id` deactivates (`isActive=false`), does not remove rows.

---

## Location master

**Search (app):** `GET /api/hiring/locations/search` — paginated, fuzzy match returns `needsConfirmation` for suggestions.

**Admin list:** `GET /api/hiring/locations/admin/list` — no full India preload in browser.

**Mutations:** `POST/PATCH /api/hiring/locations/admin…`, aliases `POST …/aliases`. Import script bumps `location_master` in TX.

---

## Serviceable areas

**API:** `/api/cities` (cached GET); admin CRUD with `cities` permission.

**Distinction:** `cities.id` (UUID) is coverage for services/rentals/events. `hiring_locations.id` (string) is geographic master for hiring/job location pickers. Importing a place does **not** create a serviceable city.

**Deletes:** Admin remove deactivates city (`isActive=false`).

---

## Rental / event catalogues

**Rental:** Category, condition, cancellation policy, hourly/daily billing validated in `listing.rs`. Admin meta: `GET /api/master-admin/rental-catalogue-meta`. Inventory and availability remain on rental item screens.

**Event:** Vendor services fixed in code (`SERVICES` array). Event type on plans is free text. Meta: `GET /api/master-admin/event-catalogue-meta`.

---

## Pricing & operational settings

**API:** `GET/PATCH /api/master-admin/settings/pricing` and `…/operational` with server-side min/max.

**Backed keys (CONFIGURATION `label` = key, `value` = number):**

| Key | Consumer (Rust) |
|-----|-----------------|
| `job_credit_per_accept` | `billing/credits.rs` |
| `go_live_period_fee`, `go_live_jobs_per_payment`, `go_live_daily_limit` | `payments/mod.rs`, `workers/mod.rs` |
| `instant_petrol_per_km` | `bookings/settlement.rs`, `bookings/mod.rs` |
| `late_cancel_compensation_*` | `bookings/cancel.rs` |

**Read-only in UI:** Smart Hiring tier fees (`fee_for_vacancies` in `matching/mod.rs`) — not CONFIGURATION-backed yet.

**Orders:** Payment/booking rows retain stored amounts; config changes affect new quotes only.

---

## Permissions

| Page slug | Typical use |
|-----------|-------------|
| `master-entries` | Catalogues, location master, content |
| `cities` | Serviceable areas |
| `pricing-policies` | Restricted pricing |
| `operational-settings` | Go-live / limits |
| SUPER_ADMIN | All pages |

Assign new slugs in **Admin staff** when creating OPERATOR users.

---

## Migrations

| File | Purpose |
|------|---------|
| `1755900000000-HiringCatalogue.ts` | Hiring + location schema |
| `1756200000000-HiringLanguages.ts` | Languages |
| `1756300000000-CacheVersions.ts` | Cache domains |
| `1756400000000-MasterDataAudit.ts` | `master_data_audit` table |

Run via your existing Nest migration process **or** Azure SQL bundle (see below).

### Azure (production path)

On the VM as `azureuser`, after uploading a tarball to `/tmp/gixbee-azure.tgz`:

```bash
bash /home/azureuser/gixbeesolutions/scripts/azure_sync_and_deploy.sh
```

That script applies `scripts/azure_hiring_migrations.sql`, `scripts/cache_versions.sql`, and `scripts/master_data_audit.sql` into `gixbee_postgres`, then rebuilds **Rust** (`COMPOSE_PROFILES=rust`) plus **admin** and **api_balancer**.

Optional post-deploy (on VM):

```bash
bash scripts/azure_import_catalogue.sh   # bundled hiring catalogue
bash scripts/azure_import_locations.sh # if refreshing location master
```

Do **not** use the AWS EC2 deploy skill (`gixbee_deploy`) for Azure hosts.

---

## Compatibility / existing records

- **Hiring / location IDs:** Unchanged; legacy map aliases old specialization ids.
- **Master entries:** Deactivate instead of delete; historical references still resolve on read paths that include inactive (admin snapshot uses `includeInactive`).
- **Cities:** Deactivate instead of delete; businesses keep `cityId` FK.
- **Pricing:** Existing `payment_orders`, `hiring_requests.feeAmount`, booking snapshots unchanged.

---

## Manual checklist

1. **CRUD:** Each section — create, edit label, deactivate, confirm list refresh.
2. **Permissions:** OPERATOR without slug gets 403; SUPER_ADMIN passes.
3. **Import:** Bundled hiring import + GeoNames location import; confirm `cache_versions` increments.
4. **Cache:** After mutation, `GET /cache/versions` changes; app refetches after resume/TTL (Flutter providers).
5. **Audit:** Row appears in `master_data_audit` / admin audit API for each mutation.
6. **Preservation:** Old job/hiring selections with inactive catalogue ids still display; new picks exclude inactive on public APIs (`isActive` filters).

---

## Implemented vs open decisions

**Implemented (source):**

- Master-data nav sections in Angular; hiring/location/service/pricing/ops/content screens.
- Rust `master_audit` + `master_admin` modules; audit in same TX as cache bump for hiring, locations, master entries, cities, validated settings patches.
- `GET /master-entries/admin/list`, `GET /hiring/locations/admin/list`, legacy map endpoint.
- Soft deactivation for master entries and cities admin remove.

**Unresolved (needs product decision before extending):**

1. **Smart Hiring vacancy fee tiers** — hardcoded in `fee_for_vacancies`; expose via CONFIGURATION or dedicated table?
2. **Extra job-profile / preference fees** — no backend consumer found; do not add fees until rule defined.
3. **Position–qualification matrix** — not in schema; qualifications remain global + single selection.
4. **Dedicated cancellation/report reason enums** — use CONFIGURATION or new type; no isolated table wired to booking cancel UI yet.
5. **Notification template placeholder registry** — validate placeholders in admin before save (not implemented).
6. **Effective-dated pricing rows** — audit stores point-in-time JSON; no `effectiveFrom` column yet.
7. **Business service-category coverage** — still on `businesses` operational fields, not a separate master grid.

---

## Honest status

Implementation is **source-complete for the scoped portal and APIs above** but **not build-tested, migration-run, or production-certified** in this environment.
