#!/usr/bin/env python3
"""Generate PDF master catalogue from the same data as hire-employee HTML (18 sectors)."""
from __future__ import annotations

import importlib.util
from datetime import date
from pathlib import Path

from fpdf import FPDF

HERE = Path(__file__).resolve().parent
OUT_PDF = HERE / "GIXBEE_Hire_Employee_Catalog_18_Sectors.pdf"


def load_catalog():
    spec = importlib.util.spec_from_file_location("gen", HERE / "_gen_hire_catalog.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    # Apply same enrichment as main()
    for s in gen.SECTORS:
        pool = gen.SECTOR_MORE_SKILLS.get(s["id"], [])
        for p in s["positions"]:
            gen._merge_more_skills(p, pool)
            if not p.get("subtitle"):
                p["subtitle"] = p["types"][0] if p["types"] else ""
    return {
        "version": "hire-catalog-v2-role-first",
        "employmentTypes": [
            {"code": "FT", "label": "Full Time"},
            {"code": "PT", "label": "Part Time"},
            {"code": "INTERN", "label": "Intern"},
            {"code": "CONTRACT", "label": "Contract"},
        ],
        "sectors": gen.SECTORS,
    }


class CatalogPDF(FPDF):
    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(100, 100, 100)
        self.cell(0, 10, f"Gixbee Hire Employee Catalogue  |  Page {self.page_no()}", align="C")


def _safe(text: str) -> str:
    """Replace chars that core PDF fonts handle poorly."""
    return (
        text.replace("\u2013", "-")
        .replace("\u2014", "-")
        .replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u2022", "-")
    )


def build_pdf(catalog: dict) -> None:
    pdf = CatalogPDF()
    pdf.set_auto_page_break(auto=True, margin=18)
    w = pdf.epw
    pdf.add_page()

    sectors = catalog["sectors"]
    npos = sum(len(s["positions"]) for s in sectors)

    pdf.set_font("Helvetica", "B", 20)
    pdf.multi_cell(w, 10, _safe("Gixbee Hire Employee - Master Catalogue"))
    pdf.ln(2)
    pdf.set_font("Helvetica", "", 11)
    pdf.multi_cell(
        0,
        6,
        _safe(
            f"18 sectors / categories, {npos} positions (role-first UX aligned with "
            "hire-employee-skills-master.html). Each position lists step-3 types, "
            "suggested skills, and additional skills for the Add Skills sheet."
        ),
    )
    pdf.ln(2)
    pdf.set_font("Helvetica", "I", 9)
    pdf.cell(0, 6, f"Generated: {date.today().isoformat()}  |  Source: _catalog_sectors.py + _gen_hire_catalog.py")
    pdf.ln(8)

    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "Step 1 - Employment types (all sectors)")
    pdf.ln(6)
    pdf.set_font("Helvetica", "", 10)
    for e in catalog["employmentTypes"]:
        pdf.cell(0, 5, _safe(f"  - {e['label']} ({e['code']})"))
        pdf.ln(5)
    pdf.ln(4)

    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "Sector index")
    pdf.ln(6)
    pdf.set_font("Helvetica", "", 10)
    for i, s in enumerate(sectors, 1):
        pdf.cell(0, 5, _safe(f"  {i}. {s['label']} ({len(s['positions'])} positions) - {s['subtitle']}"))
        pdf.ln(5)
    pdf.ln(6)

    for i, s in enumerate(sectors, 1):
        pdf.add_page()
        pdf.set_font("Helvetica", "B", 16)
        pdf.set_text_color(30, 30, 30)
        pdf.multi_cell(w, 8, _safe(f"{i}. {s['label']}"))
        pdf.set_font("Helvetica", "I", 10)
        pdf.set_text_color(80, 80, 80)
        pdf.multi_cell(w, 5, _safe(s["subtitle"]))
        pdf.ln(3)
        pdf.set_text_color(0, 0, 0)
        pdf.set_font("Helvetica", "", 9)
        pdf.cell(0, 5, _safe(f"Sector ID: {s['id']}  |  Positions: {len(s['positions'])}"))
        pdf.ln(7)

        for j, p in enumerate(s["positions"], 1):
            if pdf.get_y() > 250:
                pdf.add_page()
                pdf.set_font("Helvetica", "B", 12)
                pdf.cell(0, 7, _safe(f"{s['label']} (continued)"))
                pdf.ln(8)

            pdf.set_font("Helvetica", "B", 11)
            pdf.multi_cell(w, 6, _safe(f"{j}. {p['label']}"))
            pdf.set_font("Helvetica", "", 9)
            if p.get("subtitle"):
                pdf.multi_cell(w, 4, _safe(f"Subtitle: {p['subtitle']}"))
            pdf.cell(0, 4, _safe(f"Position ID: {p['id']}"))
            pdf.ln(5)
            pdf.multi_cell(
                0,
                4,
                _safe(
                    f"Step 3 field: {p.get('typeLabel', 'Type')}  |  "
                    f"Pattern: {p.get('fieldPattern', 'typeChips')}  |  "
                    f"Types ({len(p['types'])}):"
                ),
            )
            pdf.ln(1)
            types_line = "; ".join(p["types"])
            pdf.set_font("Helvetica", "", 8)
            pdf.multi_cell(w, 3.5, _safe(types_line))
            pdf.ln(2)
            pdf.set_font("Helvetica", "B", 9)
            pdf.cell(0, 4, "Suggested skills:")
            pdf.ln(4)
            pdf.set_font("Helvetica", "", 8)
            pdf.multi_cell(w, 3.5, _safe("; ".join(p["suggestedSkills"])))
            if p.get("moreSkills"):
                pdf.ln(2)
                pdf.set_font("Helvetica", "B", 9)
                pdf.cell(0, 4, "Additional skills (Add Skills sheet):")
                pdf.ln(4)
                pdf.set_font("Helvetica", "", 8)
                pdf.multi_cell(w, 3.5, _safe("; ".join(p["moreSkills"])))
            pdf.ln(5)
            pdf.set_draw_color(220, 220, 220)
            pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
            pdf.ln(4)

    pdf.add_page()
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 8, "HTML wizard mapping (reference)")
    pdf.ln(8)
    pdf.set_font("Helvetica", "", 9)
    ref = [
        "Step 1: Employment type + sector (this PDF sections 1-18).",
        "Step 2: One position from the sector list.",
        "Step 3: Type/specialization chips (multi-select where shown); qualification;",
        "        experience; skills; languages; job description.",
        "Step 4: Location, salary, vacancies.",
        "Step 5: Review, package, pay (prototype).",
        "",
        "Demo file: docs/prototypes/hire-employee-skills-master.html",
        "Regenerate data: python3 docs/prototypes/_gen_hire_catalog.py",
        "Regenerate PDF: python3 docs/prototypes/_gen_hire_catalog_pdf.py",
    ]
    for line in ref:
        pdf.multi_cell(w, 4.5, _safe(line))
        pdf.ln(1)

    pdf.output(str(OUT_PDF))


def main() -> None:
    catalog = load_catalog()
    build_pdf(catalog)
    print(f"Wrote {OUT_PDF.name} ({OUT_PDF.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
