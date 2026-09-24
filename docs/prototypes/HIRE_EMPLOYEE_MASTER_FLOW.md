# Hire Employee HTML flow — analysis of SkillsHire master PDF + mock screens

Source: `GIXBEE_SkillsHire_FinalMaster.pdf` (18 pages) plus the Hire Employee mock screenshots. Existing repo HTML (`docs/prototypes/gixbee_v147_lmb_hire_live.html`) is the **old dark 4-step post**. It is not this flow. No new HTML file was in the upload; the mocks are the visual spec.

**Build target:** one light/green phone HTML prototype that is driven by the PDF catalogue: Sector → Position → Type / Specialization → Skills → Qualification → Experience → Description → Location/Pay → Review/Pay.

## 1. What the PDF is

The PDF is not a screen. It is the **taxonomy**. Every row is:

| Column | Meaning in the HTML |
| --- | --- |
| Sector (page title, 18 of them) | Step 1 grid tile |
| Position | Step 2 list row |
| Type / Specialization | Step 3 chips, or a “Show more” multi-select sheet when the list is long |
| Suggested Skills | Step 3 “Add skills” sheet: first page = these skills; “Show more skills” = same list plus any extras |

Employment type (Full Time / Part Time / Intern / Contract) is **not** in the PDF. It is a filter on Step 1, same for every sector.

Qualification and experience are **not** in the PDF. They are form fields on Step 3 (optional qualification dropdown, numeric experience).

## 2. Screen flow to build (from the mocks)

Use the **5-step** path in the last mock, not the 4-step bar in the first frame.

```
Step 1/5  Job type + Sector
    → Continue (sector required)
Step 2/5  Position in that sector
    → Continue (position required)
Step 3/5  Type / specialization + qualification + experience + skills + description
    → overlays 3A/3B as needed
Step 4/5  Location, salary range, negotiable, vacancies, live match count
Step 5/5  Review & publish + interest package + pay
```

**Change position:** header chip `Healthcare › Nurse` has **Change**. That returns to Step 2 in the same sector (does not wipe job type). After a new position, Step 3 fields rebuild from the catalogue (Nurse types vs Doctor specializations).

**Back:** Step 1 back leaves Hire Employee. Later backs go to the previous step and keep draft state.

### Step 1 — Select Job Type + Sector

- Pills: Full Time (default in mock) · Part Time · Intern · Contract. Single select.
- 18 sector tiles, same labels and order as the PDF (and the mock):

1. Electrical & Electronics  
2. Plumbing  
3. Cleaning & Housekeeping  
4. Painting  
5. Construction, Carpentry & Woodwork  
6. Mechanical, HVAC & Appliances  
7. Driving  
8. Delivery & Logistics  
9. Cooking & Hospitality  
10. Security  
11. Retail & Sales  
12. Office & Administration  
13. Technology & IT  
14. Teaching & Education  
15. Healthcare  
16. Events & Wedding  
17. Fitness & Wellness  
18. Beauty & Personal Care  

- “See all” is only needed if the grid is collapsed; in HTML show all 18.
- Continue disabled until one sector is selected.

### Step 2 — Select Position

- Title: sector name + one-line subtitle (example: Healthcare → “Medical and wellness professionals for hospitals, clinics and home care”).
- Search positions in **this sector only**.
- List every **Position** row from that PDF page.
- “Show more positions” if the first viewport is truncated; HTML can show the full list with sticky Continue.
- One position selected. Continue enabled.

Healthcare positions in the mock (subset of the PDF): Doctor, Nurse, Pharmacist, Lab Technician, Radiology Technician, Physiotherapist, Dentist, Caregiver, plus “Show more positions” for the rest of page 15.

### Step 3 — fields depend on the position

This is the important HTML rule. **Do not** use one static Step 3. Read `fieldPattern` from the catalogue row.

| Pattern | When (from PDF) | UI from mock |
| --- | --- | --- |
| `typeChips` | Type / Specialization has a short list (about ≤8), e.g. Nurse, Plumber, AC Technician | Horizontal chips, single select unless the product later says multi. Nurse mock: General Nurse, ICU Nurse, OT Nurse, Emergency Nurse, Pediatric Nurse, Maternity Nurse, Home Care Nurse |
| `specializationMulti` | Long specialty list, e.g. Doctor, several Engineers | 4–6 chips on the page + **Show more** → full searchable checklist → OK (N selected) → chips return to the page |
| `skillsOnly` | Type column is almost the same as the position (rare) | Skip type row; skills + qualification + experience only |

**Always on Step 3 (every position):**

- Qualification (optional) dropdown — values are **not** in the PDF. HTML can use a small generic list (10th / 12th / Diploma / ITI / B.Sc / B.Tech / MBBS / MD / Other) and later specialize per sector.
- Minimum experience (years) stepper, default 0 or 2 as in mock.
- Skills: chips already chosen + **+ Add skills**.
- Job description optional textarea.

**Add skills overlay (mock 3A/3B):**

1. Open sheet titled Add Skills / All Skills.  
2. First view: **suggested skills for that position** from the PDF (and, if a type is selected, prefer skills for that type). No subheadings.  
3. **Show more skills** → full checklist (suggested + remaining). Search box (`Patient care, ICU, ECG`).  
4. OK → selected skills become dismissible chips on Step 3.

Doctor mock: “Show more” is on **specialization**, not skills. Skills still use + Add skills separately.

### Step 4 — Location & Compensation

Independent of the PDF.

- Work location (city / area / pincode + GPS).
- Salary min / max ₹ per month; max optional.
- Salary negotiable toggle.
- Vacancies stepper.
- Live matching count (prototype can fake a number from selected sector/position).
- Continue.

### Step 5 — Review & Publish

- Job summary: job type, sector, position, type/specialization, experience, skills, location, salary, vacancies. Edit returns to the right step.
- Interest packages from the mock: 5 / ₹29, 10 / ₹49, 20 / ₹79.
- Pay CTA.

**Wallet on this mock:** the screenshot shows wallet balance and “use from wallet.” Shipped product has `WALLET_PAYMENTS_ENABLED=false`. HTML may show the mock wallet for design parity, but Flutter/API must keep Razorpay / hiring credit — do not treat wallet as a build requirement for production.

## 3. HTML data shape (load the PDF into JS)

One `catalog` object. Screens only read this; they must not hardcode Nurse vs Doctor layouts except via `fieldPattern`.

```js
{
  employmentTypes: [
    { code: "FT", label: "Full Time" },
    { code: "PT", label: "Part Time" },
    { code: "INTERN", label: "Intern" },
    { code: "CONTRACT", label: "Contract" }
  ],
  sectors: [
    {
      id: "healthcare",
      label: "Healthcare",
      icon: "health",
      subtitle: "Medical and wellness professionals for hospitals, clinics and home care",
      positions: [
        {
          id: "nurse",
          label: "Nurse",
          subtitle: "Nursing and patient care",
          fieldPattern: "typeChips",
          typeLabel: "Nursing Type",
          types: [
            "General Nurse",
            "ICU Nurse",
            "OT Nurse",
            "Emergency Nurse",
            "Pediatric Nurse",
            "Maternity Nurse",
            "Home Care Nurse"
          ],
          /* PDF also lists: Neonatal/NICU, Dialysis, Psychiatric, Community */
          suggestedSkills: [
            "Patient care",
            "Vital signs monitoring",
            "Medication administration",
            "Infection control",
            "Emergency response",
            "Basic life support (BLS)",
            "Patient documentation",
            "Catheter care",
            "IV therapy",
            "Incharge management"
          ]
        },
        {
          id: "doctor",
          label: "Doctor",
          subtitle: "Medical doctors and specialists",
          fieldPattern: "specializationMulti",
          typeLabel: "Specialization",
          types: [
            "General Medicine",
            "Cardiology",
            "Pediatrics",
            "Dermatology",
            "Orthopedics",
            "Obstetrics & Gynecology",
            "ENT",
            "Ophthalmology",
            "Psychiatry",
            "Anesthesiology",
            "Radiology",
            "Pathology",
            "General Surgery",
            "Emergency Medicine",
            "Neurology",
            "Nephrology",
            "Gastroenterology",
            "Pulmonology",
            "Endocrinology",
            "Oncology",
            "Urology",
            "Rheumatology",
            "Geriatrics"
          ],
          suggestedSkills: [
            "Clinical assessment",
            "Diagnosis",
            "Treatment",
            "Preventive care",
            "Patient counseling",
            "Patient diagnosis",
            "Cardiac assessment",
            "ECG interpretation",
            "Patient management"
          ]
        }
      ]
    }
  ]
}
```

Split PDF “Type / Specialization” on `;`. Split “Suggested Skills” on `;`. Trim. Deduplicate.

**Nurse types in the mock** rename PDF tokens (`General/Staff` → `General Nurse`, `ICU/Critical Care` → `ICU Nurse`). HTML should use the **mock labels** where they exist, and PDF labels for every other position.

## 4. Sector → position inventory (PDF)

Counts are PDF rows (one position each). HTML Step 2 must list all of them, not only the mock’s first eight healthcare rows.

| # | Sector (HTML tile) | Positions (approx.) | Step 3 pattern notes |
| --- | --- | --- | --- |
| 1 | Electrical & Electronics | 21 | Short types for Electrician; `specializationMulti` for Electronics Engineer, Instrumentation Engineer |
| 2 | Plumbing | 11 | `typeChips` (Domestic, Residential, Building, …) |
| 3 | Cleaning & Housekeeping | 11 | `typeChips` (Home, Hotel, Hospital, …) |
| 4 | Painting | 11 | `typeChips` (Interior, Exterior, …) |
| 5 | Construction, Carpentry & Woodwork | 22 | Trades = type chips; Civil/Structural/Architect = specialization lists |
| 6 | Mechanical, HVAC & Appliances | 19 | AC Technician: Split / Window / Inverter chips |
| 7 | Driving | 12 | `typeChips` (Personal, Taxi, HMV, …) |
| 8 | Delivery & Logistics | 12 | `typeChips` |
| 9 | Cooking & Hospitality | 16 | Cuisine as types (South Indian, Tandoor, …) |
| 10 | Security | 13 | `typeChips` |
| 11 | Retail & Sales | 17 | `typeChips` (Retail, B2B, Field, …) |
| 12 | Office & Administration | 20 | `typeChips` |
| 13 | Technology & IT | ~27 | Developers/engineers: `specializationMulti` (Web, Backend, AWS, …) |
| 14 | Teaching & Education | ~36 | Subject + level: mix of type chips and Show more |
| 15 | Healthcare | ~40 | Nurse `typeChips`; Doctor `specializationMulti`; others usually type chips |
| 16 | Events & Wedding | 19 | `typeChips` |
| 17 | Fitness & Wellness | 14 | `typeChips` |
| 18 | Beauty & Personal Care | 17 | `typeChips` |

Rule of thumb for HTML: if `types.length > 8`, use `specializationMulti` (Show more sheet). Else `typeChips` on the page.

## 5. Gap vs what is already in the repo

| Surface | What it has today | vs this HTML/PDF |
| --- | --- | --- |
| Flutter `hire_employee_screen.dart` | 4 steps Role / Details / Compensation / Preview; category is a **flat 18-name list**; skills are free-typed chips | Missing Position, Type/Specialization, Add-skills sheet, live packages UI |
| `JOB_CATEGORY_CATALOG` / `HiringCatalog.fallback` | Short labels (`Electrician`, `AC & Appliances`, `Beauty`) | Must rename to PDF/mock labels and nest positions |
| `gixbee_v147_lmb_hire_live.html` | Dark theme; Step 1 is a **job icon grid**, not 18 sectors; no position/specialization layer; ₹29/49/79 packages already exist | Keep package math; replace taxonomy and light UI |
| Smart Hiring API | `jobType` string, skills[], salary, employment type, location | HTML can stay front-end only. Later map `sector + position + types` into `jobType` + `skills` without a second matcher |

Seeker Job Types (`lib/features/jobs`) must eventually use the **same catalogue**. Do not invent a second tree.

## 6. What HTML to produce next (when building)

Single file under `docs/prototypes/hire-employee-skills-master.html`:

- Light background, green primary, 430px phone frame (match mocks).
- In-page `CATALOG` constant: all 18 sectors, every PDF position, types[], suggestedSkills[].
- Wizard state object: `{ employmentType, sectorId, positionId, typesSelected[], skills[], qualification, experience, description, location, salaryMin, salaryMax, negotiable, vacancies, package }`.
- Overlays: Add Skills, Select Specialization, Change Position.
- Fake match count: function of sector + location length (prototype only).
- No backend.

Do not implement Flutter in this HTML pass.

## 7. Copy rules (same as Instant Help honesty, hiring version)

- Packages charge for **interested candidates**, not for alerts sent (already in the old HTML).
- No “42 candidates will apply” as a guarantee. Label it **matching candidates (live count)** as in the mock, prototype-only.
- Wallet line on Step 5 is mock-only until product turns wallet on.

## 8. Blocked on

The SkillsHire **HTML file itself was not uploaded** — only the PDF and PNG/JPG mocks. This document is the analysis and the contract for that HTML. Next step is to encode the full 18-page catalogue into `CATALOG` and wire the 5 screens + two overlays.
