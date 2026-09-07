# Find a Job — Module Status

> **Module PM:** Kelly (`kelly-mtg2wmci`)  
> **Last updated:** 2026-08-30  
> **Shipped truth:** [CURRENT_STATUS.md](../CURRENT_STATUS.md) · **v147 study:** [PROTOTYPE_v147_HIRING_FLOWS.md](../architecture/PROTOTYPE_v147_HIRING_FLOWS.md) · **Direction:** [ADR-008](../architecture/adr/008-v147-profiles-alerts-ux.md)

---

## 1. Scope

**Find a Job** is the seeker/talent vertical: browse the classic job board, manage Smart Hiring career profiles (Job Types), receive and respond to match offers, and track applications.

| Layer | Owned paths |
|---|---|
| **Flutter** | `lib/features/jobs/` (14 screens) |
| **Repositories** | `matching_repository.dart` (Smart Hiring), `hiring_repository.dart` (classic board), `talent_repository.dart` (seeker profile + Register Pro) |
| **Backend** | `backend/src/hiring/` (board + `matching/`), `backend/src/talent/` |

**Out of scope (this module):** Employer Hire Employee UX (`lib/features/business/`) — owned by Jan; coordinate only on Smart Hiring ↔ Hire Employee matching contract (salary range, negotiable, shared taxonomy).

**Two parallel pipelines (intentional):**

| Path | Flutter | API | Prototype analogue |
|---|---|---|---|
| **Smart Hiring** | Job Types → Offers → Interested | `/hiring/match/*` | Profiles → Alerts → Status |
| **Classic board** | Jobs tab → Apps tracker | `/hiring/posts`, `/hiring/applications` | De-emphasized in v147 |

Do not merge DB tables or repositories across paths ([PROTOTYPE §8](../architecture/PROTOTYPE_v147_HIRING_FLOWS.md)).

---

## 2. Screen map

### 2.1 Module shell (`find_job_module.dart`)

Bottom nav (shipped): **Jobs · Offers · Job Types · Apps**

| Tab | Screen | File | v147 target (ADR-008) |
|---|---|---|---|
| 0 Jobs | Classic job board browse/apply | `job_alerts_screen.dart` | **Board** (not smart alerts — naming gap V147-01) |
| 1 Offers | Smart match offers + status filters | `hiring_offers_screen.dart` | **Alerts** |
| 2 Job Types | Career profile slots (2 free + paid) | `job_types_screen.dart` | **Profiles** |
| 3 Apps | Classic application tracker | `application_tracker_screen.dart` | Apps (unchanged) |

**First-run gate:** incomplete `TalentProfile` → `seeker_profile_wizard.dart` (classic path). Job Types nudged separately on Offers / Job Types empty states.

### 2.2 Other screens (`lib/features/jobs/`)

| Screen | File | Purpose |
|---|---|---|
| Seeker wizard | `seeker_profile_wizard.dart` | Classic `TalentProfile` (roles, salary, location) |
| Talent profile | `talent_profile_screen.dart` | View/edit seeker resume path |
| Register Pro | `register_pro_screen.dart` | Pro onboarding + Aadhaar eKYC |
| Post job (secondary) | `post_job_screen.dart` | Classic employer board from seeker module |
| Pro skills | `pro_skill_taxonomy.dart`, `pro_skill_provider.dart` | Skill taxonomy helpers |
| Legacy / adjacent | `offers_screen.dart`, `my_bookings_screen.dart`, `booking_detail_screen.dart` | Non–Smart Hiring or shared booking chrome |

### 2.3 Backend surfaces

| Module | Prefix | Role |
|---|---|---|
| Smart Hiring (seeker) | `/hiring/match/preferences` | Job Types CRUD (maps to `JobPreference`) |
| Smart Hiring (seeker) | `/hiring/match/offers`, `.../respond` | Alerts + Interested gate |
| Smart Hiring (payments) | `/payments/extra-job-type/order` | ₹50/mo 3rd+ slot (`EXTRA_JOB_TYPE_FEE`) |
| Classic board | `/hiring/posts`, `/hiring/applications` | Board browse + apply |
| Talent | `/talent/profile`, `/talent/aadhaar/*` | Seeker profile + Register Pro eKYC |

**Entity mapping (v147 → shipped):** prototype career profile = `JobPreference`; alert = `HiringInterest` + FCM `hiring_offer`; Interested = `respond(INTERESTED)`.

---

## 3. Shipped flows (2026-08-17 baseline)

| Flow | Status | Entry |
|---|---|---|
| Module shell (4 tabs) | Done | Home intent → Find a Job |
| Job Types CRUD (2 free, 3rd+ ₹50 Razorpay) | Done | Tab Job Types |
| Smart offers + Interested / Not Interested | Done | Tab Offers |
| Employer decision filters (Pending/Shortlisted/Rejected/Hired) | Done | Offers tab filters |
| FCM `hiring_offer` / `hiring_status` | Done | Push → Offers |
| Classic board browse + apply | Done | Tab Jobs |
| Application tracker (classic) | Done | Tab Apps |
| Seeker first-run wizard | Done | Gate on module open |
| Loop UX copy (↔ Hire Employee) | Done | Empty states cross-link |
| Register Pro + Aadhaar OTP sheet | Done (code) | Blocked on EC2 Surepass creds |
| `jobAlertsEnabled` field fix | Done | Job Types form |

**Gates:** Smart match requires seeker `JobPreference` rows; employers need VERIFIED HIRING business (Jan path). Wallet stays OFF.

---

## 4. Smoke path (module QA)

Use when Docker stack is up (`http://localhost:3000/health`). Dwight owns execution; this is the canonical checklist.

### 4.1 Talent profile + wizard

1. Fresh seeker account → open **Find a Job** → seeker wizard prompts if `TalentProfile` empty.
2. Complete wizard (roles, salary, location) → profile saved via `talent_repository`.
3. **Register Pro** (optional): Aadhaar OTP flow — requires Surepass keys on backend.

### 4.2 Smart Hiring loop (primary)

**Precondition:** VERIFIED HIRING employer has posted via Hire Employee (Jan path §4.2).

1. **Job Types:** create preference (job type name, skills, expected salary, location) → appears in list.
2. Attempt 3rd profile → Razorpay ₹50 flow (or skip if test env gates payment).
3. **Offers:** matching offer appears (or seed via employer match run) → tap **Interested**.
4. Confirm status filter updates; FCM `hiring_status` on employer shortlist/hire (device optional).
5. **Privacy:** before Interested, employer sees limited offer data only.

### 4.3 Classic board (secondary)

1. **Jobs** tab → browse posts → apply to one.
2. **Apps** tab → application shows with status.
3. Withdraw application if supported → status updates.

### 4.4 Negative / edge

| Case | Expected |
|---|---|
| No Job Types → Offers empty | Empty state nudges Job Types tab |
| Delete Job Type within 7-day lock | Blocked with message |
| Job Type name edit after create | Immutable (FRD) |
| Respond Not Interested | Offer removed from active list |
| ARCH-009 Aadhaar generate-otp burst | Global 120/min only — no per-route throttle |

### 4.5 Cross-module handoff (with Jan)

Employer **Hire Employee** → seeker **Offers** Interested → employer **Hiring requests** shortlist/hire. Full E2E needs both modules + payment path.

---

## 5. Open gaps (prioritized)

Sourced from Jim v147 study ([GAPS.md](../architecture/GAPS.md) V147-01–07) + module audit.

### P1 — UX / IA (this module)

| ID | Gap | Owner | Notes |
|---|---|---|---|
| **V147-01** | Tab IA: prototype Profiles/Alerts/Status vs shipped Jobs/Offers/Job Types; **Jobs tab is classic board, not alerts** | **Pam** | ADR-008 phase 1: rename Board / Alerts / Profiles — no API change |
| **V147-02** | No FT/PT/Intern/Contract or shared category catalog (prototype `cat` vs free-text Job Type name) | **Pam** + **Oscar** | Taxonomy picker UI + `employmentType` on `JobPreference` |
| **V147-03** | Salary negotiable toggle (seeker) — no API field on `JobPreference` | **Oscar** (+ Jan employer range) | Matcher cannot widen salary rule until contract extended |
| **V147-05** | Prototype ₹299 unlimited profiles vs shipped ₹50/extra slot | **god** (product) | Money model ADR-001/006 review before change |

### P2 — Polish

| ID | Gap | Owner | Notes |
|---|---|---|---|
| — | No v147-style profile dashboard (strength score, per-profile alert toggle cards) | **Pam** | ADR-008 phase 2 on existing `JobPreference` rows |
| — | No dedicated status timeline (`status-detail`) | **Pam** | Offers filters partial substitute |
| — | Unified Settings/edit screen | **Pam** | Inline edit on Job Types today |
| **V147-07** | Ranked match % on seeker offer cards | **Pam** | Employer side in Jan module; optional backend score |

### P0 — Ops blockers (not module code)

SMS OTP, Razorpay live keys, eKYC, EC2 deploy — see [CURRENT_STATUS.md](../CURRENT_STATUS.md) P0. Extra Job Type fee and match responses are code-complete; blocked on live gateway creds.

### Cross-module (coordinate with Jan + Oscar)

| Topic | Rule |
|---|---|
| Salary range on employer post | Jan task `task-gixbee-biz-salary-range` (Oscar): `salaryMin`/`salaryMax`/`salaryNegotiable` on `HiringRequest` |
| **Seeker fields (same PR)** | Kelly spec for `JobPreference`: `salaryNegotiable boolean` (default false); keep `expectedSalary` as seeker ask. Matcher: overlap when `expectedSalary <= salaryMax` AND (`salaryNegotiable` OR `expectedSalary >= salaryMin`). |
| Employment type + taxonomy | `employmentType` enum `FT\|PT\|INTERN\|CONTRACT` on `JobPreference` + `HiringRequest`; hard-filter in matcher when both set (V147-02) |
| Tab rename | Seeker IA owned here; employer copy already cross-linked (2026-08-17) |

### ARCH items touching this module

| ID | Notes | Owner |
|---|---|---|
| ARCH-009 | Aadhaar `generate-otp` — global throttle only | Oscar |
| ARCH-003/006 | Payment gateway parse / wallet orphan — tangential to Job Type Razorpay | Pam |

---

## 6. Backlog (queued — god accepted 2026-08-30)

| Task ID | Priority | Work | Assignee | Status |
|---|---|---|---|---|
| `task-find-job-v147-ia` | **1** | V147-01: Rename tabs Board / Alerts / Profiles / Apps + empty states (ADR-008 phase 1) | Pam | doing |
| `task-find-job-v147-taxonomy` | **2** | V147-02: `employmentType` + category catalog; bundle `salaryNegotiable` with Oscar salary-range PR | Oscar + Pam | doing |
| `task-find-job-smoke` | **3** | Module smoke per §4 | Dwight | doing |

**Deferred:** Profiles home cards (Pam, after #1); V147-05 monetization (god / ADR-001/006).

---

## 7. Coordination

| Agent | When |
|---|---|
| **Jan** (`jan-mtg2wjo4`) | Salary range, negotiable flags, shared taxonomy — Smart Hiring contract edge only |
| **Pam** | All Flutter in `lib/features/jobs/` |
| **Oscar / Ryan** | `hiring/matching`, `talent` backend |
| **Dwight** | Module smoke (§4) |
| **Jim / Creed** | ARCH/security escalations via god |
| **god** | Task dispatch, board updates, V147-05 product call, human creds |

---

## 8. References

| Doc | Role |
|---|---|
| [PROTOTYPE_v147_HIRING_FLOWS.md](../architecture/PROTOTYPE_v147_HIRING_FLOWS.md) | v147 vs shipped gap table (§6.1) |
| [ADR-008](../architecture/adr/008-v147-profiles-alerts-ux.md) | Profiles + Alerts UX on existing API |
| [GIXBEE_BUSINESS.md](./GIXBEE_BUSINESS.md) | Employer mirror module (Hire Employee smoke §4.2) |
| [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) | System map |
| [GAPS.md](../architecture/GAPS.md) | V147-01–07 register |
