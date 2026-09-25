#!/usr/bin/env python3
"""Build hire-employee-skills-catalog.js from the SkillsHire master PDF rows."""
from __future__ import annotations

import json
from pathlib import Path

OUT_JS = Path(__file__).with_name("hire-employee-skills-catalog.js")
OUT_HTML = Path(__file__).with_name("hire-employee-skills-master.html")


def split_semi(s: str) -> list[str]:
    parts = []
    for raw in s.replace("\n", " ").split(";"):
        t = " ".join(raw.split()).strip(" ,")
        if t:
            parts.append(t)
    seen, out = set(), []
    for p in parts:
        k = p.lower()
        if k not in seen:
            seen.add(k)
            out.append(p)
    return out


def pos(label, types, skills, subtitle=""):
    t = split_semi(types)
    sk = split_semi(skills)
    pattern = "specializationMulti" if len(t) > 8 else "typeChips"
    type_label = "Specialization" if pattern == "specializationMulti" else "Type"
    if label == "Nurse":
        pattern, type_label = "typeChips", "Nursing Type"
        t = [
            "General Nurse",
            "ICU Nurse",
            "OT Nurse",
            "Emergency Nurse",
            "Pediatric Nurse",
            "Maternity Nurse",
            "Home Care Nurse",
            "NICU Nurse",
            "Dialysis Nurse",
            "Psychiatric Nurse",
            "Community Nurse",
        ]
    if label == "Doctor":
        pattern, type_label = "specializationMulti", "Specialization"
    return {
        "id": label.lower().replace(" ", "-").replace("/", "-").replace("&", "and"),
        "label": label,
        "subtitle": subtitle,
        "fieldPattern": pattern,
        "typeLabel": type_label,
        "types": t,
        "suggestedSkills": sk,
        "moreSkills": [],
    }


def teach_pos(label, types, skills, subtitle="", type_label="Type"):
    """Role-first positions with explicit subtitles and type field labels."""
    p = pos(label, types, skills, subtitle)
    p["typeLabel"] = type_label
    if len(p["types"]) > 8:
        p["fieldPattern"] = "specializationMulti"
    return p


role_pos = teach_pos


# Shared lists for Teaching & Education (level + subject on step 3)
_SCHOOL_LEVELS = "Primary (LP–UKG); Secondary (8–10); Higher Secondary (+1/+2)"
_SCHOOL_SUBJECTS = (
    "All subjects (primary); English; Malayalam; Hindi; Mathematics; Science; Social Science; "
    "Physics; Chemistry; Biology; Computer Science; Commerce; Accountancy; Economics; "
    "History; Geography; Arabic; Sanskrit; Informatics Practices"
)
_COLLEGE_STREAMS = "Arts; Science; Commerce; Law; Management"
_COLLEGE_SUBJECTS = (
    "English; Malayalam; Hindi; Economics; History; Political Science; Sociology; "
    "Physics; Chemistry; Mathematics; Botany; Zoology; Commerce; Accountancy; "
    "Business Administration; Computer Applications"
)
_ENGINEERING = (
    "Engineering college; Polytechnic; Computer Science; Electronics; Electrical; "
    "Mechanical; Civil; Mathematics; Physics; Chemistry; Information Technology"
)
_ITI_TRADES = (
    "Electrician; Fitter; Welder; Mechanic (Motor Vehicle); COPA; Draughtsman; "
    "Plumber; Refrigeration; NCVT; SCVT"
)
_TUTOR_MODES = "Home tuition; Online tuition; Tuition centre"
_TUTOR_LEVELS = "Primary; Class 8–10; Plus One; Plus Two; Degree; Entrance exam prep"
_TUTOR_SUBJECTS = (
    "Mathematics; Science; Physics; Chemistry; Biology; English; Malayalam; Hindi; "
    "Computer Science; Commerce; Accountancy; Economics; Social Science"
)

from _catalog_sectors import build_sectors

_TEACH = {
    "school_levels": _SCHOOL_LEVELS,
    "school_subjects": _SCHOOL_SUBJECTS,
    "college_streams": _COLLEGE_STREAMS,
    "college_subjects": _COLLEGE_SUBJECTS,
    "engineering": _ENGINEERING,
    "iti": _ITI_TRADES,
    "tutor_modes": _TUTOR_MODES,
    "tutor_levels": _TUTOR_LEVELS,
    "tutor_subjects": _TUTOR_SUBJECTS,
}

SECTORS = build_sectors(role_pos, _TEACH)


# Sector-specific Add Skills sheet (no generic filler on every row).
SECTOR_MORE_SKILLS: dict[str, list[str]] = {
    "electrical": [
        "Kerala wireman licence",
        "Electrical safety (LOTO)",
        "Megger / insulation testing",
        "Single-line diagram reading",
        "BIS wiring practices",
        "Solar net-metering basics",
    ],
    "plumbing": [
        "CPVC / UPVC piping",
        "Pump troubleshooting",
        "Blueprint reading",
        "Pressure testing procedures",
    ],
    "cleaning": [
        "Chemical handling (MSDS)",
        "Infection-control cleaning",
        "Equipment operation (scrubber/extractor)",
        "Guest privacy standards",
    ],
    "painting": [
        "Putty and surface prep",
        "Spray booth safety",
        "Colour matching",
        "Scaffolding safety",
    ],
    "construction": [
        "AutoCAD / Revit basics",
        "Site safety (PPE)",
        "Measurement and marking",
        "Formwork alignment",
        "BOQ / quantity basics",
    ],
    "hvac": [
        "F-gas / refrigerant handling",
        "Vacuum and leak testing",
        "Copper flaring and brazing",
        "VRF commissioning basics",
        "Appliance PCB diagnosis",
    ],
    "driving": [
        "Valid LMV driving licence",
        "Valid HMV / heavy licence",
        "Commercial permit / badge (if applicable)",
        "Defensive driving",
        "Local route knowledge",
        "Vehicle pre-trip inspection",
    ],
    "delivery": [
        "Valid two-wheeler licence",
        "Valid LMV licence",
        "GPS / map navigation apps",
        "Cold chain handling (pharmacy/grocery)",
        "Proof-of-delivery apps",
    ],
    "cooking": [
        "FSSAI hygiene practices",
        "Knife skills",
        "Bulk quantity estimation",
        "HACCP basics",
        "Kitchen inventory",
    ],
    "security": [
        "PSARA / guard training certificate",
        "Fire extinguisher use",
        "First aid basics",
        "Incident report writing",
        "Access control SOP",
    ],
    "retail": [
        "POS / billing software",
        "Upselling techniques",
        "Stock replenishment",
        "Visual merchandising",
        "CRM / lead tracking",
    ],
    "office": [
        "MS Office / Google Workspace",
        "Email and calendar management",
        "Tally / accounting software",
        "Documentation and filing",
        "Customer phone etiquette",
    ],
    "tech": [
        "Git / version control",
        "Agile / Scrum basics",
        "REST API design",
        "Cloud certification (AWS/Azure)",
        "Technical documentation",
    ],
    "teaching": [
        "Kerala state syllabus",
        "CBSE / ICSE experience",
        "Smart classroom tools",
        "Exam evaluation (SSLC/plus two)",
        "Parent-teacher communication",
        "Spoken English support",
    ],
    "healthcare": [
        "Kerala nursing council registration",
        "Medical council registration (doctors)",
        "Pharmacy council registration",
        "BLS certification",
        "ACLS (where applicable)",
        "Infection control bundle",
        "NABH awareness",
        "Medical coding (ICD)",
    ],
    "events": [
        "Vendor coordination",
        "Timeline / run-sheet planning",
        "Stage safety",
        "Client briefing",
    ],
    "fitness": [
        "CPR / first aid",
        "Fitness assessment",
        "Injury prevention",
        "Gym equipment maintenance basics",
    ],
    "beauty": [
        "Salon hygiene and sterilization",
        "Skin type consultation",
        "Product allergy patch test",
        "Bridal trial consultation",
    ],
}


def _merge_more_skills(position: dict, pool: list[str]) -> None:
    have = {k.lower() for k in position["suggestedSkills"]}
    position["moreSkills"] = [x for x in pool if x.lower() not in have]


def main() -> None:
    for s in SECTORS:
        pool = SECTOR_MORE_SKILLS.get(s["id"], [])
        for p in s["positions"]:
            _merge_more_skills(p, pool)
            if not p.get("subtitle"):
                p["subtitle"] = p["types"][0] if p["types"] else ""
    catalog = {
        "version": "skills-hire-final-master",
        "employmentTypes": [
            {"code": "FT", "label": "Full Time"},
            {"code": "PT", "label": "Part Time"},
            {"code": "INTERN", "label": "Intern"},
            {"code": "CONTRACT", "label": "Contract"},
        ],
        "sectors": SECTORS,
    }
    npos = sum(len(s["positions"]) for s in SECTORS)
    js = "window.GIXBEE_HIRE_CATALOG = " + json.dumps(catalog, ensure_ascii=False, indent=2) + ";\n"
    OUT_JS.write_text(js, encoding="utf-8")
    html = OUT_HTML.read_text(encoding="utf-8")
    start, end = "<!-- CATALOG_START -->", "<!-- CATALOG_END -->"
    i, j = html.find(start), html.find(end)
    if i < 0 or j < 0:
        raise SystemExit("HTML missing CATALOG_START/END markers")
    injected = (
        start
        + "\n<script>\n/* Inlined catalogue: this HTML is self-contained for file:// */\n"
        + js
        + "</script>\n"
        + end
    )
    OUT_HTML.write_text(html[:i] + injected + html[j + len(end) :], encoding="utf-8")
    print(f"Wrote {OUT_JS.name} and inlined into {OUT_HTML.name}: {len(SECTORS)} sectors, {npos} positions")


if __name__ == "__main__":
    main()
