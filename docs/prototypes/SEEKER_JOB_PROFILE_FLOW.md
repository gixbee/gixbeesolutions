# Employee job profile HTML flow (seeker / worker)

**Build target:** `docs/prototypes/seeker-job-profile-master.html` — single self-contained file (catalogue + app JS inlined). Open in a browser; no server required.

**Regenerate:** `python3 docs/prototypes/_gen_seeker_profile_html.py` (runs `_gen_hire_catalog.py` first so taxonomy matches Hire Employee).

## Purpose

When a **employee / job seeker** opens Gixbee Smart Hiring, they should pick the **same job type and 18-sector category** as an employer, then complete skills, languages, location, and pay expectations — and **save a job profile** (not post a vacancy or pay for leads).

This prototype mirrors `hire-employee-skills-master.html` with seeker copy and persistence.

## Flow (5 steps)

| Step | Screen | Seeker vs employer |
| --- | --- | --- |
| 1/5 | Job type pills + sector grid | Same catalogue as hire |
| 2/5 | Position in sector | Same positions (130 role-first rows) |
| 3/5 | Type, qualification, experience, skills, languages, bio | “Your” wording; languages = languages you speak |
| 4/5 | Location + expected salary + negotiable + relocate | No vacancies; demo “open roles” estimate |
| 5/5 | Review + profile name + **Save profile** | No Razorpay / interest packages |

After save:

- **Saved** confirmation with link to **My profiles**
- **My profiles** lists `localStorage` entries; Edit reloads wizard; Delete removes; **Copy all profiles (JSON)** for API shape tests

## Saved profile JSON (`GIXBEE_JOB_PROFILES`)

Each item includes:

- `id`, `schemaVersion`, `savedAt`, `displayName`
- `employmentType`, `sector`, `position`, `types[]`
- `qualification`, `experienceYears`, `skills[]`, `languages[]`, `bio`
- `location`, `salary` (`minMonthly`, `maxMonthly`, `negotiable`), `openToRelocate`
- `catalogueVersion` (matches hire catalogue)

## Source files

| File | Role |
| --- | --- |
| `seeker-job-profile-shell.html` | Markup + CSS (no catalogue) |
| `_seeker_profile_app.js` | Wizard + localStorage logic |
| `_gen_seeker_profile_html.py` | Inlines catalogue from `_gen_hire_catalog.py` |
| `hire-employee-skills-catalog.js` | Shared data (regenerated with hire script) |

## Related

- Employer flow: `HIRE_EMPLOYEE_MASTER_FLOW.md`, `hire-employee-skills-master.html`
- Flutter (production): `lib/features/jobs/seeker_profile_wizard.dart` — different UX today; this HTML is the target parity spec for nested catalogue + save.
