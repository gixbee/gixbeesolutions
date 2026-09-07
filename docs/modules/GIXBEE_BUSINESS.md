# Gixbee for Business — Module Status

> **Module PM:** Jan (`jan-mtg2wjo4`)  
> **Last updated:** 2026-08-30  
> **Shipped truth:** [CURRENT_STATUS.md](../CURRENT_STATUS.md) · **v147 study:** [PROTOTYPE_v147_HIRING_FLOWS.md](../architecture/PROTOTYPE_v147_HIRING_FLOWS.md) · **Direction:** [ADR-008](../architecture/adr/008-v147-profiles-alerts-ux.md)

---

## 1. Scope

**Gixbee for Business** (List My Business / LMB) is the employer/operator vertical: register and manage business units, run Smart Hiring from the employer side, and operate SERVICE / HIRING / RENTAL dashboards.

| Layer | Owned paths |
|---|---|
| **Flutter** | `lib/features/business/` (7 screens), `lib/features/rentals/` (4 screens) |
| **Repositories** | `business_repository.dart`, `rentals_repository.dart`, `matching_repository.dart` (employer methods) |
| **Backend** | `backend/src/businesses/`, `backend/src/rentals/`, `backend/src/hiring/matching/` (employer pipeline) |

**Out of scope (this module):** Find a Job seeker UX (`lib/features/jobs/`) — owned by Kelly; coordinate only on Smart Hiring ↔ Hire Employee matching contract (salary range, negotiable, taxonomy).

**Intentionally deferred:** SHOP business type + flash offers (v147 `s1–s8`) — backend has SERVICE / HIRING / RENTAL only.

---

## 2. Screen map

### 2.1 Business (`lib/features/business/`)

| Screen | File | Purpose |
|---|---|---|
| Type picker | `list_business_type_screen.dart` | SERVICE · HIRING · RENTAL (no Shop) |
| Registration | `list_business_details_screen.dart` | Name, docs, `serviceType` (Hall/Catering/Decor/Photo) |
| Unit dashboard | `business_unit_dashboard.dart` | Per-type hub: calendar (SERVICE), Hire Employee (HIRING), rentals link (RENTAL) |
| **Hire Employee** | `hire_employee_screen.dart` | Smart Hiring form → estimate → Razorpay/credit → `POST /hiring/match/requests` |
| Match review | `hiring_requests_screen.dart` | Interests list + shortlist / reject / hire |
| Classic pipeline | `hiring_pipeline_screen.dart` | Board posts (secondary path) |
| Candidate view | `candidate_profile_screen.dart` | Profile after candidate responds Interested |

### 2.2 Rentals (`lib/features/rentals/`)

| Screen | File | Purpose |
|---|---|---|
| Catalog | `rentals_catalog_screen.dart` | Customer browse + reserve |
| Item detail | `rental_item_detail_screen.dart` | `showGxCalendar` + time picker, overlap blocking |
| My rentals | `my_rentals_screen.dart` | Customer reservations |
| Owner mode | `owner_rentals_screen.dart` | List items, manage reservations |

### 2.3 Backend surfaces

| Module | Prefix | Notes |
|---|---|---|
| Businesses | `/businesses` | Register, `/my`, operators, SERVICE offline calendar |
| Rentals | `/rentals` | Catalog, items, reservations, overlap checks |
| Smart Hiring (employer) | `/hiring/match` | `estimate`, `requests`, `interests`, `decision`, guarantee resolve |
| Payments | `/payments/hiring-match/order` | Match fee ₹49–399 (`HIRING_MATCH_FEE`) |

---

## 3. Shipped flows (2026-08-17 baseline)

| Flow | Status | Entry |
|---|---|---|
| Register SERVICE / HIRING / RENTAL unit | Done | Profile → List My Business |
| SERVICE offline calendar | Done | Unit dashboard → add/remove offline days |
| RENTAL owner catalog | Done | Unit dashboard → Owner rentals |
| **Hire Employee** Smart Hiring | Done | VERIFIED HIRING unit → Hire Employee |
| Live candidate estimate | Done | Debounced `GET /hiring/match/estimate` on salary/job type |
| Match fee + hiring credit | Done | Razorpay or credit balance; 24 h collecting window |
| Shortlist / hire pipeline | Done | `hiring_requests_screen` + FCM `hiring_status` |
| Classic Post Job board | Done (secondary) | `hiring_pipeline_screen` / `post_job_screen` |
| Rentals customer reserve | Done | Home intent → Rentals catalog |
| Loop UX copy (Find a Job ↔ Hire Employee) | Done | Cross-links in empty states |

**Gates:** Smart match requires **VERIFIED HIRING** business. Wallet stays OFF; match fee via Razorpay only.

---

## 4. Smoke path (module QA)

Use when Docker stack is up (`http://localhost:3000/health`). Dwight owns execution; this is the canonical checklist.

### 4.1 Business registration

1. Profile → **List My Business** → pick **HIRING** (repeat SERVICE / RENTAL separately).
2. Fill details + upload doc → submit → lands on **My Businesses** dashboard.
3. **SERVICE:** add offline day on calendar → refresh → day shows blocked.
4. **RENTAL:** open Owner rentals → add item with daily rate → appears in owner list.

### 4.2 Hire Employee (Smart Hiring)

**Precondition:** VERIFIED HIRING business (admin verification or test seed).

1. Unit dashboard → **Hire Employee**.
2. Enter job type, location, salary, skills → confirm **candidate estimate** updates (debounce ~400 ms).
3. Submit → pay match fee (Razorpay test or hiring credit) → success navigates to requests.
4. **Seeker side** (Kelly path): Job Type + Offers → Interested on matching offer.
5. Employer: **Hiring requests** → see interest → **Shortlist** → **Hire** (or Reject).
6. After 24 h with no hire: guarantee **CREDIT** or **REFUND** choice appears.

### 4.3 Rentals (customer)

1. Home → Rentals intent → catalog loads.
2. Open item → pick dates via `showGxCalendar` → reserve → **My rentals** shows booking.
3. Owner: confirm / handover / complete reservation states.

### 4.4 Negative / edge

| Case | Expected |
|---|---|
| Unverified HIRING unit → Hire Employee | Blocked with verification message |
| Empty job type / salary on estimate | Estimate cleared; no API spam |
| Rental overlap dates | Reserve rejected (backend overlap check) |
| Operator picker search &lt; 3 chars | Empty results (ARCH-002 privacy) |

---

## 5. Open gaps (prioritized)

Sourced from Jim v147 study ([GAPS.md](../architecture/GAPS.md) V147-03–07) + module audit.

### P1 — UX / contract (this module)

| ID | Gap | Owner | Notes |
|---|---|---|---|
| **V147-04** | Prototype `hj1–hj4` wizard vs single scroll `hire_employee_screen`; missing preview (`hj4`) | **Pam** | Same `POST /hiring/match/requests` body — UI split only per ADR-008 |
| **V147-03** | Employer salary **range** + negotiable (`hj3`); API has single `salaryOffered` ceiling | **Oscar** (+ Kelly seeker fields) | Matcher needs range overlap; cross-module contract |
| **V147-07** | Ranked `mc-*` match cards (% match, skill diff) vs flat interest list | **Pam** | P2 polish; backend may expose score later |

### P2 — Ops / polish

| ID | Gap | Owner | Notes |
|---|---|---|---|
| **L18** | Daily price update 8:30 AM (prototype service vendor ops) | **Pam** or defer | Not in Flutter |
| **L7** | Master multi-business hub vs list in `business_unit_dashboard` | **Pam** | Partial — low priority |
| **V147-06** | Shop + flash offers | **N/A** | No SHOP enum — product defer |

### P0 — Ops blockers (not module code)

SMS OTP, Razorpay live keys, eKYC, EC2 deploy — see [CURRENT_STATUS.md](../CURRENT_STATUS.md) P0. Hire Employee payment path is code-complete; blocked on live gateway creds.

### Cross-module (coordinate with Kelly)

| Topic | Rule |
|---|---|
| Smart vs classic hiring | `matching_repository` only for Smart; `hiring_repository` for board — do not merge tables |
| Salary negotiable on seeker | `JobPreference` field缺失 — Kelly + Oscar before matcher change |
| Tab rename (Profiles/Alerts) | Kelly owns Find a Job IA; employer copy already cross-linked |

---

## 6. Backlog (proposed — PM queue)

| Priority | Task | Assignee | Deps |
|---|---|---|---|
| **1** | Split `hire_employee_screen` into `hj1–hj4` routes + preview step; keep existing API payload | Pam | — |
| **2** | API: `salaryMin`/`salaryMax` + `salaryNegotiable` on `HiringRequest`; matcher range overlap | Oscar | Align with Kelly on `JobPreference` |
| **3** | Module smoke checklist execution + report (`GIXBEE_BUSINESS.md` §4) | Dwight | Local stack optional |
| 4 | Ranked match cards on `hiring_requests_screen` (score UI) | Pam | Optional backend score field |
| 5 | SERVICE daily price reminder UI (`l18`) | Pam / defer | Product call |

---

## 7. Coordination

| Agent | When |
|---|---|
| **Kelly** (`kelly-mtg2wmci`) | Salary negotiable, employment type, shared taxonomy — Smart Hiring contract edge only |
| **Pam** | All Flutter in `business/` + `rentals/` |
| **Oscar / Ryan** | `businesses`, `rentals`, `hiring/matching` backend |
| **Dwight** | Module smoke (§4) |
| **Jim / Creed** | ARCH/security escalations via god |
| **god** | Task dispatch, board updates, human creds |

---

## 8. References

| Doc | Role |
|---|---|
| [PROTOTYPE_v147_HIRING_FLOWS.md](../architecture/PROTOTYPE_v147_HIRING_FLOWS.md) | v147 vs shipped gap table (§6.2) |
| [ADR-008](../architecture/adr/008-v147-profiles-alerts-ux.md) | Extend UX on existing Smart Hiring API |
| [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) | System map |
| [GAPS.md](../architecture/GAPS.md) | V147-03–07 register |
