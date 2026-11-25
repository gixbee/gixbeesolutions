# Hire Employee / Find a Job — v2 delivery notes

**Status:** Source changes only. Tests, builds, migrations, catalogue import, and deployment were **not** run in this session.

## Catalogue reconciliation (130 positions)

| Source | Role |
|--------|------|
| `GIXBEE_hire-employee-skills-master_finalfix.html` | Authoritative structure: 18 sectors, 130 positions, skills/types, interaction defaults |
| `GIXBEE_Hire_Employee_Catalog_final.pdf` | Cross-check labels/types/skills (when present on disk) |
| Previous bundle (~324 positions) | Legacy IDs preserved via `backend/data/hiring-catalogue-legacy-map.json` |

**Version:** `skills-hire-final-master-130` in `backend/data/hiring-catalogue.json` (mirrored to `backend_rust/data/`).

**Ambulance Driver:** Same HTML `id` (`ambulance-driver`) in **Driving** and **Healthcare** with different skill sets → reconcile script keeps **separate** position ids: `driving--ambulance-driver` and `healthcare--ambulance-driver` (no overwrite).

**Shared roles:** e.g. Makeup Artist across sectors when skills overlap ≥50% → single shared position id.

**Gig:** HTML lists FT/PT/INTERN/CONTRACT only; **GIG** employment code retained in bundle for existing records.

**Regenerate (repeatable):**

```bash
python backend/scripts/reconcile-hiring-catalogue.py
```

Then admin **Import bundled catalogue** (Rust) on each environment.

## UI (Flutter) — screen summary

| Step | Changes |
|------|---------|
| 1 | Sector **card grid** (`hiring_sector_grid.dart`); employment pills unchanged |
| 2 | Position search loads sector pool; **8 visible** + “Show more”; full-sector search when typing |
| 3 | Multi-select **types** (incl. `typeChips`); first type default on new draft; 6 inline + sheet; **languages** (`hiring_language_picker.dart`, default en/ml); experience/vacancy **steppers**; stale detail/estimate guards |
| 4 | Location/salary/work mode/period unchanged; **distinct** backend estimate count |
| 5 | Production **vacancy fee + credit** (no demo ₹29/49/79 packages) |

**Find a Job:** Preference APIs accept `languageIds`; full form parity still shares catalogue pickers — extend `JobTypeFormScreen` with the same language/type rules when editing (language field wired on API; UI follow-up in same files as position/skills).

## Backend (Rust)

- `hiring_languages` master + import from bundle
- `languageIds` on hiring requests and job preferences (matching **ranking**, not hard exclusion)
- Estimate/matching: **distinct candidates** per user; specializations scoped to **preference row** only
- Admin: `POST/PATCH /hiring/catalogue/admin/languages`

## Migration / import order (you run)

1. Apply TypeORM migration `1756200000000-HiringLanguages.ts` (or `scripts/azure_hiring_migrations.sql` on MilesWeb).
2. Deploy Rust backend with new `hiring-catalogue.json`.
3. `POST /hiring/catalogue/admin/import` (admin) — upserts sectors/positions/skills/languages; does not delete custom admin rows unless deactivated manually.
4. Optional: review `backend/data/hiring-catalogue-legacy-map.json` **unresolved** entries before bulk remapping historical `positionId` values.

## Manual verification checklist

- [ ] Hire Employee step 1–5: back navigation keeps draft; sector change clears position/skills
- [ ] Ambulance Driver in Driving vs Healthcare resolves to **different** position ids in API detail
- [ ] Languages: employer requires ≥1; candidate with **no** languages still appears in estimate
- [ ] Estimate count changes when work mode / languages / specializations change; no flicker from stale requests
- [ ] Payment review shows tier fee (49–399), credit, Razorpay — not HTML demo packages
- [ ] Find a Job: save/edit preference with `languageIds`, clear arrays, `matchingPaused` per profile
- [ ] Admin: import reports version; languages visible in catalogue snapshot

## Deliberate adaptations / gaps

- Catalogue **version** comes from bundled JSON in API snapshot (no `system_settings` table).
- Import applies **legacy map** aliases and retires superseded position ids not in the new bundle.
- **Job board / post job** screens: catalogue ids already wired; confirm UI copy for salary period on manual pass.
- **Full pixel parity** with HTML phone chrome (notch, demo wallet) omitted by design.
- **Legacy 324→130 position remapping** on live rows: mapping file generated; **manual or scripted SQL** still required for ambiguous unresolved ids.

## Business decisions still open

- Bulk auto-remap of historical `positionId` / `specializationIds` for unresolved legacy rows (vs admin review queue).
- Whether candidate **must** pick ≥1 language on Find a Job (employer side requires ≥1 in UI; candidate optional for eligibility).
