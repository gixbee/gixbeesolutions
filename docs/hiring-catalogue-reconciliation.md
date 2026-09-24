# Hiring catalogue reconciliation

Reviewed against both references:

- 18 sectors and 324 positions are taken from the HTML catalogue, which is the structured source.
- Makeup Artist and Mehndi Artist are shared across Events and Beauty because their skills match.
- Ambulance Driver stays as two positions (`driving` and `healthcare`) because the skill lists differ.
- PDF line wraps made some titles look missing (Recruiter/Talent Acquisition Executive, Health Information/Medical Records Executive, Nurse specializations). Those roles are in both documents.
- HTML Electrician types are Domestic and Residential Wiring. The PDF collapses that to Domestic/Residential. The catalogue keeps the HTML types.
- HTML includes Commercial Refrigeration Technician as well as Refrigerator Technician. The PDF table shows Refrigerator Technician.
- Gig is not in the HTML employment list. The existing GIG code is kept so current profiles still load.
- Demo prices ₹29/₹49/₹79 are not imported. Hire Employee still uses the vacancy fee (₹49 to ₹399) and hiring credit.

Parser notes from the automatic compare follow. Several of those lines are PDF line-wrap artifacts, not missing roles.

# Hiring catalogue reconciliation

Sources:

- `hire-employee-skills-master.html` (`window.GIXBEE_HIRE_CATALOG`, version `skills-hire-final-master`).
- `GIXBEE_SkillsHire_FinalMaster.pdf` (18-sector Final Master Job Positions Catalogue).

The bundled file is `backend/data/hiring-catalogue.json` (copied into `backend_rust/data` for the API import).
HTML ids are kept when a role appears once. A repeated label is one shared position when suggested skills overlap at least half; otherwise each sector keeps `sector--position`.
Suggested skills come from the HTML list. PDF skill wording that does not overlap is recorded below and also kept when it only exists on one side via the HTML `suggestedSkills` and `moreSkills` lists.
Deactivating a row later does not delete profiles that already stored its id.

Sectors: 18. Positions: 324. Shared positions: 2.

## Discrepancies

- Electrical & Electronics / Electrician types differ. HTML only: ['domestic', 'residential wiring']. PDF only: ['domestic residential'].
- Electrical & Electronics / Solar Technician types differ. HTML only: ['o m']. PDF only: ['o'].
- Electrical & Electronics / Solar Technician suggested skills differ substantially (overlap 0%). Catalogue keeps both lists.
- Electrical & Electronics / Generator Technician types differ. HTML only: ['generator o m']. PDF only: ['generator o'].
- Electrical & Electronics / Generator Technician suggested skills differ substantially (overlap 0%). Catalogue keeps both lists.
- Electrical & Electronics / Electronics Engineer types differ. HTML only: ['analog electronics', 'consumer electronics', 'industrial electronics', 'iot embedded', 'pcb design']. PDF only: ['analog'].
- Electrical & Electronics / Instrumentation Engineer types differ. HTML only: ['calibration testing', 'control instrumentation']. PDF only: —.
- Construction, Carpentry & Woodwork / Environmental Engineer types differ. HTML only: ['waste management']. PDF only: ['waste'].
- PDF section 'Mechanical, HVAC & Appliances' does not contain HTML position 'Commercial Refrigeration Technician'.
- PDF section 'Office & Administration' does not contain HTML position 'Recruiter/Talent Acquisition Executive'.
- Teaching & Education / English Teacher types differ. HTML only: ['higher secondary']. PDF only: ['higher'].
- Healthcare / Doctor types differ. HTML only: ['anesthesiology', 'dermatology', 'emergency medicine', 'endocrinology', 'ent', 'gastroenterology', 'general surgery', 'geriatrics', 'nephrology', 'neurology', 'obstetrics gynecology', 'oncology', 'ophthalmology', 'orthopedics', 'pathology', 'pediatrics', 'psychiatry', 'pulmonology', 'radiology', 'rheumatology', 'urology']. PDF only: —.
- Healthcare / Nurse types differ. HTML only: ['community nurse', 'dialysis nurse', 'emergency nurse', 'general nurse', 'home care nurse', 'icu nurse', 'maternity nurse', 'nicu nurse', 'ot nurse', 'pediatric nurse', 'psychiatric nurse']. PDF only: ['general staff', 'icu critical care'].
- Healthcare / Pharmacist types differ. HTML only: ['regulatory qa']. PDF only: —.
- PDF section 'Healthcare' does not contain HTML position 'Health Information/Medical Records Executive'.
- Role 'Ambulance Driver' appears in Driving, Healthcare with different skills, so each sector keeps its own position id.
- HTML employment types omit Gig. Kept the existing GIG code so current profiles still load.
