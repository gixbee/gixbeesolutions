# Employee job profile HTML flow (seeker / worker)

**Build target (job seeker / employee):**

| File | Use |
| --- | --- |
| **`jobseeker-job-profile-master.html`** | Same as below — easy name for “jobseeker” |
| `seeker-job-profile-master.html` | Identical single-file demo |

One self-contained file (markup + inlined catalogue + inlined app). Download **either** file and open in a browser. No extra `.js`.

**Regenerate after edits:** `python3 docs/prototypes/_gen_seeker_profile_html.py` (runs `_gen_hire_catalog.py`, then inlines everything into `seeker-job-profile-master.html`).

Developer sources (not for end users): `seeker-job-profile-shell.html`, `_seeker_profile_app.js`.

### Troubleshooting (blank page or console error)

1. Open **`seeker-job-profile-master.html`** only — not `seeker-job-profile-shell.html` (shell has no catalogue/scripts until regenerated).
2. Hard refresh after pull (Ctrl+Shift+R) so step 4 shows **Expected salary (₹/month)** — not old Min/Max fields. Old HTML + new script causes `Cannot read properties of null (addEventListener)` on load.
3. In Cursor/IDE preview, prefer a local server: `cd docs/prototypes && python3 -m http.server 8765` then open `http://localhost:8765/seeker-job-profile-master.html` (avoids some `file://` iframe warnings).

## Purpose

When a **employee / job seeker** opens Gixbee Smart Hiring, they should pick the **same job type and 18-sector category** as an employer, then complete skills, languages, location, and pay expectations — and **save a job profile** (not post a vacancy or pay for leads).

This prototype mirrors `hire-employee-skills-master.html` with seeker copy and persistence.

## Flow (5 steps)

| Step | Screen | Seeker vs employer |
| --- | --- | --- |
| 1/5 | Job type pills + sector grid | Same catalogue as hire |
| 2/5 | Position in sector | Same positions (130 role-first rows) |
| 3/5 | Type, qualification, experience, skills, languages, bio | “Your” wording; languages = languages you speak |
| 4/5 | Primary + optional extra work locations, expected salary, available to join, resume (optional), salary negotiable | No “open roles” estimate; no relocate toggle |
| 5/5 | Review + profile name + **Save profile** | No Razorpay / interest packages |

After save:

- **Saved** confirmation with link to **My profiles**
- **My profiles** lists `localStorage` entries; Edit reloads wizard; Delete removes; **Copy all profiles (JSON)** for API shape tests

## Saved profile JSON (`GIXBEE_JOB_PROFILES`)

Each item includes:

- `id`, `schemaVersion`, `savedAt`, `displayName`
- `employmentType`, `sector`, `position`, `types[]`
- `qualification`, `experienceYears`, `skills[]`, `languages[]`, `bio`
- `location`, `salary` (`expectedMonthly`, `negotiable`), `openToRelocate`
- `availableToJoin` (`code`, `label`) — Immediately · Within 7 / 15 / 30 / 60 / 90 days
- `resume` (optional) — `fileName`, `sizeBytes`, `mimeType`; small files may include `dataUrl` in demo
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
