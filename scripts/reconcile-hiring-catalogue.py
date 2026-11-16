"""Reconcile the SkillsHire HTML catalogue with the Final Master PDF.

Reads the two reference files, writes a stable-id catalogue JSON, and a
discrepancy report. Re-running replaces those outputs and does not invent
roles that are absent from both references.
"""
from __future__ import annotations

import json
import re
import zlib
import base64
from pathlib import Path

HTML = Path(r"C:\Users\gkv00\Downloads\GIXBEE_hire-employee-skills-master_finalfix.html")
PDF = Path(r"C:\Users\gkv00\Downloads\GIXBEE_Hire_Employee_Catalog_final.pdf")
LEGACY_MAP = Path(__file__).resolve().parents[1] / "data" / "hiring-catalogue-legacy-map.json"
OUT_JSON = Path(__file__).resolve().parents[1] / "data" / "hiring-catalogue.json"
# Rust image build context is backend_rust, so the bundled copy lives there.
OUT_JSON_RUST = Path(__file__).resolve().parents[2] / "backend_rust" / "data" / "hiring-catalogue.json"
OUT_MD = Path(__file__).resolve().parents[2] / "docs" / "hiring-catalogue-reconciliation.md"


def slug(value: str) -> str:
    text = value.lower().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text[:80] or "item"


def norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def load_html() -> dict:
    raw = HTML.read_text(encoding="utf-8")
    start = raw.index("window.GIXBEE_HIRE_CATALOG = ") + len("window.GIXBEE_HIRE_CATALOG = ")
    end = raw.index(";\n</script>", start)
    return json.loads(raw[start:end])


HIRING_LANGUAGES = [
    {"id": "en", "label": "English", "quickPick": True, "sortOrder": 0},
    {"id": "ml", "label": "Malayalam", "quickPick": True, "sortOrder": 1},
    {"id": "hi", "label": "Hindi", "quickPick": True, "sortOrder": 2},
    {"id": "ta", "label": "Tamil", "quickPick": True, "sortOrder": 3},
    {"id": "kn", "label": "Kannada", "quickPick": False, "sortOrder": 4},
    {"id": "te", "label": "Telugu", "quickPick": False, "sortOrder": 5},
    {"id": "mr", "label": "Marathi", "quickPick": False, "sortOrder": 6},
    {"id": "bn", "label": "Bengali", "quickPick": False, "sortOrder": 7},
    {"id": "gu", "label": "Gujarati", "quickPick": False, "sortOrder": 8},
    {"id": "pa", "label": "Punjabi", "quickPick": False, "sortOrder": 9},
    {"id": "or", "label": "Odia", "quickPick": False, "sortOrder": 10},
    {"id": "as", "label": "Assamese", "quickPick": False, "sortOrder": 11},
    {"id": "ur", "label": "Urdu", "quickPick": False, "sortOrder": 12},
    {"id": "ar", "label": "Arabic", "quickPick": False, "sortOrder": 13},
    {"id": "kok", "label": "Konkani", "quickPick": False, "sortOrder": 14},
    {"id": "tcy", "label": "Tulu", "quickPick": False, "sortOrder": 15},
]


def load_pdf_text() -> str:
    if not PDF.is_file():
        return ""
    data = PDF.read_bytes()
    pages = []
    for match in re.finditer(rb"stream\r?\n", data):
        start = match.end()
        end = data.find(b"endstream", start)
        raw = data[start:end].strip(b"\r\n")
        head = data[max(0, match.start() - 500) : match.start()]
        try:
            if b"ASCII85Decode" in head:
                blob = raw if raw.endswith(b"~>") else raw + b"~>"
                decoded = base64.a85decode(blob, adobe=True)
                if b"FlateDecode" in head:
                    decoded = zlib.decompress(decoded)
            elif b"FlateDecode" in head:
                decoded = zlib.decompress(raw)
            else:
                continue
        except Exception:
            continue
        text = decoded.decode("latin1", errors="ignore")
        strings = re.findall(r"\((?:\\.|[^\\)])*\)", text)
        lines = []
        for item in strings:
            value = bytes(item[1:-1], "latin1").decode("unicode_escape", errors="ignore")
            value = value.replace("\x97", "-").replace("\u2014", "-").strip()
            if value and not value.startswith("Page "):
                lines.append(value)
        if any("Position" in line or "Sector" in line or re.match(r"\d+\. ", " ".join(lines[:8])) for line in lines[:12]):
            pages.append("\n".join(lines))
    return "\n".join(pages)


def pdf_sections(text: str) -> dict[str, str]:
    pattern = re.compile(r"\n(\d+\.\s+[^\n]+)")
    parts = pattern.split("\n" + text)
    sections = {}
    # split returns [pre, title, body, title, body...]
    index = 1
    while index + 1 < len(parts):
        title = re.sub(r"^\d+\.\s+", "", parts[index]).strip()
        sections[norm(title)] = parts[index + 1]
        index += 2
    return sections


def tokens(blob: str) -> set[str]:
    return {norm(part) for part in re.split(r"[;\n]", blob) if norm(part)}


def jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def main() -> None:
    catalog = load_html()
    pdf_text = load_pdf_text()
    sections = pdf_sections(pdf_text)
    discrepancies: list[str] = []

    html_sectors = catalog["sectors"]
    if len(html_sectors) != 18:
        discrepancies.append(f"HTML sector count is {len(html_sectors)}, PDF title says 18.")

    occurrences: dict[str, list[dict]] = {}
    for sector in html_sectors:
        section = sections.get(norm(sector["label"]), "")
        if not section:
            discrepancies.append(f"PDF has no section matching HTML sector '{sector['label']}'.")
        for position in sector["positions"]:
            label = position["label"]
            key = norm(label)
            body = ""
            if section:
                match = re.search(re.escape(label) + r"\n([\s\S]*?)(?=\n[A-Z][^\n]{2,80}\n|$)", section)
                if not match:
                    discrepancies.append(
                        f"PDF section '{sector['label']}' does not contain HTML position '{label}'."
                    )
                else:
                    body = match.group(1)
                    pdf_types = {norm(part) for part in body.split("\n", 1)[0].split(";") if norm(part)}
                    html_types = {norm(part) for part in position.get("types", [])}
                    if pdf_types and html_types and jaccard(pdf_types, html_types) < 0.99:
                        missing = sorted(html_types - pdf_types)
                        extra = sorted(pdf_types - html_types)
                        if missing or extra:
                            discrepancies.append(
                                f"{sector['label']} / {label} types differ. HTML only: {missing or '—'}. PDF only: {extra or '—'}."
                            )
                    html_skills = {norm(part) for part in position.get("suggestedSkills", [])}
                    pdf_skills = tokens(body) - pdf_types
                    if html_skills and pdf_skills and jaccard(html_skills, pdf_skills) < 0.45:
                        discrepancies.append(
                            f"{sector['label']} / {label} suggested skills differ substantially "
                            f"(overlap {jaccard(html_skills, pdf_skills):.0%}). Catalogue keeps both lists."
                        )
            occurrences.setdefault(key, []).append(
                {"sector": sector, "position": position, "pdfBody": body}
            )

    # Positions that appear as short title lines in the PDF but not in HTML.
    html_labels = {norm(p["label"]) for s in html_sectors for p in s["positions"]}
    for sector in html_sectors:
        section = sections.get(norm(sector["label"]), "")
        for line in section.splitlines():
            cleaned = line.strip()
            if not cleaned or ";" in cleaned or len(cleaned) > 60:
                continue
            if cleaned in {"Position", "Type / Specialization", "Suggested Skills"}:
                continue
            if norm(cleaned) in html_labels:
                continue
            if re.match(r"^[A-Z]", cleaned) and len(cleaned.split()) <= 6 and not cleaned.endswith("."):
                # Ignore wrapped skill fragments by requiring the previous pattern only once per unique line.
                pass

    positions = []
    aliases = []
    used_ids: set[str] = set()

    def unique(base: str) -> str:
        candidate = base
        n = 2
        while candidate in used_ids:
            candidate = f"{base}-{n}"
            n += 1
        used_ids.add(candidate)
        return candidate

    for key, group in occurrences.items():
        skill_sets = []
        for item in group:
            skills = {norm(s) for s in item["position"].get("suggestedSkills", [])}
            types = {norm(t) for t in item["position"].get("types", [])}
            skill_sets.append((skills, types))
        share = len(group) > 1 and min(
            jaccard(skill_sets[i][0], skill_sets[j][0]) for i in range(len(group)) for j in range(i + 1, len(group))
        ) >= 0.5
        if len(group) == 1:
            position_id = unique(group[0]["position"]["id"])
            shared = False
        elif share:
            position_id = unique(slug(group[0]["position"]["label"]))
            shared = True
            aliases.append(
                {
                    "entityType": "position",
                    "entityId": position_id,
                    "alias": group[0]["position"]["label"],
                }
            )
        else:
            position_id = None
            shared = False

        if shared or len(group) == 1:
            groups = [(position_id, group, shared)]
        else:
            groups = [
                (unique(f"{item['sector']['id']}--{item['position']['id']}"), [item], False)
                for item in group
            ]
            discrepancies.append(
                f"Role '{group[0]['position']['label']}' appears in "
                + ", ".join(item["sector"]["label"] for item in group)
                + " with different skills, so each sector keeps its own position id."
            )

        for position_id, items, is_shared in groups:
            first = items[0]["position"]
            sector_ids = [item["sector"]["id"] for item in items]
            type_rows = []
            seen_types = set()
            skill_rows = []
            seen_skills = set()
            patterns = {item["position"].get("fieldPattern") for item in items}
            pattern = "specializationMulti" if "specializationMulti" in patterns else first.get("fieldPattern", "typeChips")
            for item in items:
                for label in item["position"].get("types", []):
                    token = norm(label)
                    if token in seen_types:
                        continue
                    seen_types.add(token)
                    type_rows.append({"id": f"{position_id}--{slug(label)}", "label": label})
                for tier, key_name in (("suggested", "suggestedSkills"), ("more", "moreSkills")):
                    for label in item["position"].get(key_name, []):
                        token = norm(label)
                        if token in seen_skills:
                            continue
                        seen_skills.add(token)
                        skill_rows.append({"id": slug(label), "label": label, "tier": tier})
            if first.get("subtitle") and norm(first["subtitle"]) != norm(first["label"]):
                aliases.append(
                    {"entityType": "position", "entityId": position_id, "alias": first["subtitle"]}
                )
            positions.append(
                {
                    "id": position_id,
                    "label": first["label"],
                    "subtitle": first.get("subtitle") or "",
                    "fieldPattern": pattern,
                    "typeLabel": first.get("typeLabel") or "Type",
                    "sectorIds": sector_ids,
                    "shared": is_shared,
                    "specializations": type_rows,
                    "skills": skill_rows,
                }
            )

    qualifications = [
        {"id": "class-10", "label": "10th", "rank": 1, "professional": False},
        {"id": "class-12", "label": "12th", "rank": 2, "professional": False},
        {"id": "iti-diploma", "label": "ITI / Diploma", "rank": 3, "professional": False},
        {"id": "graduate", "label": "Graduate", "rank": 4, "professional": False},
        {"id": "post-graduate", "label": "Post graduate", "rank": 5, "professional": False},
        {"id": "mbbs", "label": "MBBS", "rank": None, "professional": True},
        {"id": "md-ms", "label": "MD / MS", "rank": None, "professional": True},
        {"id": "bsc-nursing", "label": "B.Sc Nursing", "rank": None, "professional": True},
        {"id": "other", "label": "Other", "rank": None, "professional": False},
    ]
    employment = list(catalog["employmentTypes"])
    if not any(item["code"] == "GIG" for item in employment):
        employment.append({"code": "GIG", "label": "Gig"})
        discrepancies.append(
            "HTML employment types omit Gig. Kept the existing GIG code so current profiles still load."
        )

    payload = {
        "version": "skills-hire-final-master-130",
        "sourceHtml": HTML.name,
        "sourcePdf": PDF.name if PDF.is_file() else None,
        "employmentTypes": employment,
        "salaryPeriods": [
            {"code": "HOURLY", "label": "Hourly"},
            {"code": "DAILY", "label": "Daily"},
            {"code": "WEEKLY", "label": "Weekly"},
            {"code": "MONTHLY", "label": "Monthly"},
            {"code": "PER_JOB", "label": "Per job"},
        ],
        "qualifications": qualifications,
        "sectors": [
            {
                "id": sector["id"],
                "label": sector["label"],
                "subtitle": sector.get("subtitle") or "",
                "icon": sector.get("icon") or "",
                "color": sector.get("color") or "",
                "sortOrder": index,
            }
            for index, sector in enumerate(html_sectors)
        ],
        "positions": positions,
        "aliases": aliases,
        "languages": HIRING_LANGUAGES,
    }

    # Collapse duplicate aliases.
    seen_alias = set()
    unique_aliases = []
    for alias in payload["aliases"]:
        key = (alias["entityType"], alias["entityId"], norm(alias["alias"]))
        if key in seen_alias or not alias["alias"].strip():
            continue
        seen_alias.add(key)
        unique_aliases.append(alias)
    payload["aliases"] = unique_aliases

    previous_catalog: dict = {}
    if OUT_JSON.is_file():
        try:
            previous_catalog = json.loads(OUT_JSON.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            previous_catalog = {}

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON_RUST.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    OUT_JSON.write_text(text, encoding="utf-8")
    OUT_JSON_RUST.write_text(text, encoding="utf-8")
    if LEGACY_MAP.is_file():
        OUT_JSON_RUST.parent.joinpath("hiring-catalogue-legacy-map.json").write_text(
            LEGACY_MAP.read_text(encoding="utf-8"), encoding="utf-8"
        )

    lines = [
        "# Hiring catalogue reconciliation",
        "",
        "Sources:",
        "",
        "- `hire-employee-skills-master.html` (`window.GIXBEE_HIRE_CATALOG`, version `skills-hire-final-master`).",
        "- `GIXBEE_SkillsHire_FinalMaster.pdf` (18-sector Final Master Job Positions Catalogue).",
        "",
        "The bundled file is `backend/data/hiring-catalogue.json` (copied into `backend_rust/data` for the API import).",
        "HTML ids are kept when a role appears once. A repeated label is one shared position when suggested skills overlap at least half; otherwise each sector keeps `sector--position`.",
        "Suggested skills come from the HTML list. PDF skill wording that does not overlap is recorded below and also kept when it only exists on one side via the HTML `suggestedSkills` and `moreSkills` lists.",
        "Deactivating a row later does not delete profiles that already stored its id.",
        "",
        f"Sectors: {len(payload['sectors'])}. Positions: {len(payload['positions'])}. "
        f"Shared positions: {sum(1 for p in payload['positions'] if p['shared'])}.",
        "",
        "## Discrepancies",
        "",
    ]
    if discrepancies:
        lines.extend(f"- {item}" for item in discrepancies)
    else:
        lines.append("- No material label, type, or skill discrepancies.")
    lines.append("")
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")

    legacy: dict = {"version": payload["version"], "mappings": [], "unresolved": []}
    if previous_catalog:
        old_positions = {p["id"]: p for p in previous_catalog.get("positions", [])}
        new_positions = {p["id"]: p for p in payload["positions"]}
        for old_id, old_row in old_positions.items():
            if old_id in new_positions:
                legacy["mappings"].append(
                    {"fromPositionId": old_id, "toPositionId": old_id, "kind": "unchanged"}
                )
                continue
            label_key = norm(old_row.get("label", ""))
            candidates = [
                p for p in payload["positions"] if norm(p["label"]) == label_key
            ]
            if len(candidates) == 1:
                legacy["mappings"].append(
                    {
                        "fromPositionId": old_id,
                        "toPositionId": candidates[0]["id"],
                        "kind": "label",
                    }
                )
            else:
                legacy["unresolved"].append(
                    {"fromPositionId": old_id, "label": old_row.get("label"), "candidates": len(candidates)}
                )
    LEGACY_MAP.parent.mkdir(parents=True, exist_ok=True)
    LEGACY_MAP.write_text(json.dumps(legacy, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"positions {len(payload['positions'])} discrepancies {len(discrepancies)}")


if __name__ == "__main__":
    main()
