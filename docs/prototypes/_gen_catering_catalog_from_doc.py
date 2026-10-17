#!/usr/bin/env python3
"""Generate _catering_menu_catalog.js seed data from gixbee-catering-almostfinal.docx."""
from __future__ import annotations

import json
import re
import zipfile
from pathlib import Path

DIR = Path(__file__).resolve().parent
DOCX = Path("/home/ubuntu/.cursor/projects/workspace/uploads/gixbee-catering-almostfinal_beb6.docx")
OUT = DIR / "_catering_menu_catalog.js"

MODULE_META = [
    ("m01", "Welcome Drinks", "🥤"),
    ("m02", "Starters & Snacks", "🥟"),
    ("m03", "Salads", "🥗"),
    ("m04", "Soups", "🍲"),
    ("m05", "Sadhya", "🍛"),
    ("m06", "Biriyani", "🍚"),
    ("m07", "Arabian", "🧆"),
    ("m08", "Main Course", "🍽️"),
    ("m09", "Curries & Gravies", "🥘"),
    ("m10", "Accompaniments", "🥙"),
    ("m11", "Special Live Counters", "🔥"),
    ("m12", "Breads & Rotis", "🫓"),
    ("m13", "Desserts & Sweets", "🍮"),
]

# Display order overrides (subcategory titles). Doc order kept elsewhere; UX may reorder.
MODULE_SUBCAT_ORDER: dict[str, list[str]] = {
    "m09": [
        "Vegetarian Curries",
        "Regional & Specialty",
        "Paneer & Egg",
        "Chicken & Meat",
        "Fish & Seafood",
    ],
}

GRADIENTS = [
    "linear-gradient(145deg,#0EA5E9,#0284C7)",
    "linear-gradient(145deg,#F97316,#EA580C)",
    "linear-gradient(145deg,#22C55E,#16A34A)",
    "linear-gradient(145deg,#EF4444,#DC2626)",
    "linear-gradient(145deg,#EAB308,#CA8A04)",
    "linear-gradient(145deg,#A855F7,#7C3AED)",
    "linear-gradient(145deg,#F43F5E,#E11D48)",
    "linear-gradient(145deg,#6366F1,#4F46E5)",
    "linear-gradient(145deg,#14B8A6,#0D9488)",
    "linear-gradient(145deg,#84CC16,#65A30D)",
    "linear-gradient(145deg,#FB923C,#F97316)",
    "linear-gradient(145deg,#D97706,#B45309)",
    "linear-gradient(145deg,#EC4899,#DB2777)",
]


def slug(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")[:48] or "misc"


def extract_paragraphs(docx: Path) -> list[str]:
    from xml.etree import ElementTree as ET

    W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
    with zipfile.ZipFile(docx) as z:
        root = ET.fromstring(z.read("word/document.xml"))
    paras: list[str] = []
    for p_el in root.iter(W + "p"):
        parts: list[str] = []
        for t in p_el.iter(W + "t"):
            if t.text:
                parts.append(t.text)
            if t.tail:
                parts.append(t.tail)
        line = "".join(parts).strip()
        if line:
            paras.append(line)
    return paras


def is_custom_catalog_item(name: str) -> bool:
    n = (name or "").strip()
    return n == "Custom" or n.startswith("Custom ")


def strip_custom_catalog_entries(modules: list[dict]) -> list[dict]:
    for mod in modules:
        next_subcats = []
        for sc in mod["subcats"]:
            items = [it for it in sc.get("items", []) if not is_custom_catalog_item(it)]
            if not items:
                continue
            next_subcats.append({"name": sc["name"], "items": items})
        mod["subcats"] = next_subcats
    return modules


def parse_modules(paras: list[str]) -> list[dict]:
    modules: list[dict] = []
    cur_mod: dict | None = None
    cur_sub: dict | None = None
    skip_prefixes = (
        "Owners select",
        "Note:",
        "Live counter pricing",
        "GIXBEE",
        "13-Module",
        "Purpose:",
        "How the catalogue",
        "Food Items",
        "Packages:",
        "Keep item",
        "Allow owner",
        "Support pricing",
        "Use tags",
        "Treat repeated",
        "Keep customer",
        "Owner item",
        "Required",
        "Optional",
        "Pricing",
        "Package name",
    )
    for line in paras:
        if line.startswith("Customer-facing") or line.startswith("Quality checks"):
            break
        m = re.match(r"^(\d+)\.\s+(.+)$", line)
        if m and int(m.group(1)) <= 13:
            cur_mod = {"num": int(m.group(1)), "name": m.group(2).strip(), "subcats": []}
            modules.append(cur_mod)
            cur_sub = None
            continue
        if cur_mod is None:
            continue
        if any(line.startswith(p) for p in skip_prefixes):
            continue
        if line.startswith("☐ "):
            item = line[2:].strip()
            if cur_sub is None:
                cur_sub = {"name": "General", "items": []}
                cur_mod["subcats"].append(cur_sub)
            cur_sub["items"].append(item)
            continue
        if re.match(r"^\d+\.", line):
            continue
        cur_sub = {"name": line, "items": []}
        cur_mod["subcats"].append(cur_sub)
    return modules


def infer_diet(subcat_name: str, item_name: str) -> str:
    sc = subcat_name.lower()
    nm = item_name.lower()
    if "egg" in nm and "vegetable" not in nm:
        if re.search(r"\begg\b", nm) or nm.startswith("egg "):
            return "egg"
    nonveg_markers = (
        "non-vegetarian",
        "non vegetarian",
        "chicken",
        "mutton",
        "beef",
        "fish",
        "prawn",
        "chemmeen",
        "seafood",
        "crab",
        "lobster",
        "squid",
        "mussels",
        "kallumakkaya",
        "meat",
        "alfaham",
        "shawarma",
        "mandi",
        "kabsa",
        "madhbi",
        "madfoon",
    )
    if any(x in sc for x in ("non-vegetarian", "non vegetarian", "chicken & meat", "chicken dishes", "mutton", "beef", "fish & seafood", "seafood", "grill")):
        return "non_veg"
    if any(re.search(r"\b" + re.escape(w) + r"\b", nm) for w in ("chicken", "mutton", "beef", "prawn", "fish", "crab", "lobster", "squid", "seafood")):
        return "non_veg"
    if "paneer & egg" in sc or sc.endswith("egg"):
        if "egg" in nm:
            return "egg"
    if "vegetarian" in sc or "veg " in sc:
        return "veg"
    if "vegan" in nm:
        return "veg"
    return "veg"


def attach_ids(parsed: list[dict]) -> list[dict]:
    out = []
    for mod in parsed:
        mid = MODULE_META[mod["num"] - 1][0]
        used: dict[str, int] = {}
        subcats = []
        for sc in mod["subcats"]:
            base = slug(sc["name"])
            n = used.get(base, 0)
            used[base] = n + 1
            sid = base if n == 0 else f"{base}-{n + 1}"
            subcats.append({"id": sid, "name": sc["name"], "items": sc["items"]})
        order = MODULE_SUBCAT_ORDER.get(mid)
        if order:
            by_name = {sc["name"]: sc for sc in subcats}
            ordered = [by_name[n] for n in order if n in by_name]
            for sc in subcats:
                if sc["name"] not in order:
                    ordered.append(sc)
            subcats = ordered
        meta = MODULE_META[mod["num"] - 1]
        out.append(
            {
                "id": mid,
                "num": mod["num"],
                "name": meta[1],
                "emoji": meta[2],
                "subcats": subcats,
            }
        )
    return out


def js_string(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def emit_catalog_js(defs: list[dict]) -> str:
    lines = [
        "/** Fixed 13-module catering catalogue — generated from gixbee-catering-almostfinal.docx */",
        "const CAT_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];",
        "",
        "const FOOD_MODULE_GRADIENTS = " + json.dumps(GRADIENTS) + ";",
        "",
        "function foodMasterKey(moduleId, subcatId, name) {",
        "  return moduleId + '::' + subcatId + '::' + String(name || '').toLowerCase().replace(/\\s+/g, '-');",
        "}",
        "",
        "function inferCatalogDiet(subcatName, itemName) {",
        "  const sc = String(subcatName || '').toLowerCase();",
        "  const nm = String(itemName || '').toLowerCase();",
        "  if (/\\begg\\b/.test(nm) && !/vegetable/.test(nm)) {",
        "    if (/\\begg\\b/.test(nm) && !/vegetable/.test(nm)) return 'egg';",
        "  }",
        "  if (",
        "    sc.indexOf('non-vegetarian') >= 0 ||",
        "    sc.indexOf('non vegetarian') >= 0 ||",
        "    sc.indexOf('chicken & meat') >= 0 ||",
        "    sc.indexOf('chicken dishes') >= 0 ||",
        "    sc.indexOf('mutton') >= 0 ||",
        "    sc.indexOf('beef') >= 0 ||",
        "    sc.indexOf('fish & seafood') >= 0 ||",
        "    sc.indexOf('seafood') >= 0 ||",
        "    sc.indexOf('grill') >= 0",
        "  ) {",
        "    return 'non_veg';",
        "  }",
        "  if (/\\b(chicken|mutton|beef|prawn|fish|crab|lobster|squid|seafood|chemmeen)\\b/.test(nm)) return 'non_veg';",
        "  if (sc.indexOf('paneer & egg') >= 0 && /\\begg\\b/.test(nm)) return 'egg';",
        "  if (sc.indexOf('vegetarian') >= 0) return 'veg';",
        "  return 'veg';",
        "}",
        "",
        "/** @type {Array<{id:string,name:string,emoji:string,subcats:Array<{id:string,name:string,items:string[]}>}>} */",
        "const CATERING_CATALOG_DEFS = ",
    ]
    # compact JSON for defs
    compact_defs = []
    for m in defs:
        compact_defs.append(
            {
                "id": m["id"],
                "name": m["name"],
                "emoji": m["emoji"],
                "subcats": m["subcats"],
            }
        )
    lines.append(json.dumps(compact_defs, ensure_ascii=False, indent=2) + ";")
    lines.extend(
        [
            "",
            "function buildFoodModules() {",
            "  return CATERING_CATALOG_DEFS.map(function (m, idx) {",
            "    const subcats = (m.subcats || []).map(function (sc) {",
            "      const items = (sc.items || []).map(function (name) {",
            "        const diet = inferCatalogDiet(sc.name, name);",
            "        return {",
            "          masterKey: foodMasterKey(m.id, sc.id, name),",
            "          name: name,",
            "          subcatId: sc.id,",
            "          subcatName: sc.name,",
            "          diet: diet,",
            "        };",
            "      });",
            "      return { id: sc.id, name: sc.name, items: items };",
            "    });",
            "    return {",
            "      id: m.id,",
            "      num: idx + 1,",
            "      name: m.name,",
            "      emoji: m.emoji,",
            "      gradient: FOOD_MODULE_GRADIENTS[idx] || FOOD_MODULE_GRADIENTS[0],",
            "      subcats: subcats,",
            "    };",
            "  });",
            "}",
            "",
            "const FOOD_MODULES = buildFoodModules();",
            "",
            "function findFoodModule(moduleId) {",
            "  return FOOD_MODULES.find(function (m) {",
            "    return m.id === moduleId;",
            "  });",
            "}",
            "",
            "function findMasterItem(masterKey) {",
            "  for (let mi = 0; mi < FOOD_MODULES.length; mi++) {",
            "    const mod = FOOD_MODULES[mi];",
            "    for (let si = 0; si < mod.subcats.length; si++) {",
            "      const sc = mod.subcats[si];",
            "      for (let ii = 0; ii < sc.items.length; ii++) {",
            "        if (sc.items[ii].masterKey === masterKey) return { module: mod, subcat: sc, item: sc.items[ii] };",
            "      }",
            "    }",
            "  }",
            "  return null;",
            "}",
            "",
            "function defaultItemSlabs() {",
            "  return [",
            "    { from: 1, to: 25, price: 70 },",
            "    { from: 26, to: 50, price: 60 },",
            "    { from: 51, to: 100, price: 55 },",
            "    { from: 101, to: 200, price: 50 },",
            "    { from: 201, to: 500, price: 45 },",
            "  ];",
            "}",
            "",
            "function defaultPackageGuestSlabs() {",
            "  return [",
            "    { from: 25, to: 50, price: 300 },",
            "    { from: 51, to: 100, price: 280 },",
            "    { from: 101, to: 200, price: 260 },",
            "    { from: 201, to: 300, price: 240 },",
            "    { from: 301, to: 500, price: 220 },",
            "  ];",
            "}",
            "",
            "function defaultCateringMenuStore() {",
            "  return {",
            "    hubTab: 'packages',",
            "    pkgFilter: 'all',",
            "    pkgSort: 'name',",
            "    pkgSearch: '',",
            "    foodSearch: '',",
            "    foodItems: [],",
            "    catPackages: [",
            "      {",
            "        id: 'cpkg-demo-1',",
            "        name: 'Engagement Day Menu',",
            "        level: 'Standard',",
            "        description:",
            "          'Balanced spread for engagement functions with welcome drinks, starters, mains and dessert.',",
            "        subtitle: 'Standard tier · ~120 guests · per person',",
            "        listPrice: 40000,",
            "        price: 35000,",
            "        status: 'live',",
            "        pricingMode: 'per_person',",
            "        guestSlabs: defaultPackageGuestSlabs(),",
            "        itemIds: [],",
            "        imageEmoji: '🍽️',",
            "      },",
            "      {",
            "        id: 'cpkg-demo-2',",
            "        name: 'Wedding Day Feast',",
            "        level: 'Premium',",
            "        description:",
            "          'Full-day premium wedding catering with live counters and extended dessert selection.',",
            "        subtitle: 'Premium tier · full day · per person',",
            "        listPrice: 75000,",
            "        price: 75000,",
            "        status: 'live',",
            "        pricingMode: 'per_person',",
            "        guestSlabs: defaultPackageGuestSlabs(),",
            "        itemIds: [],",
            "        imageEmoji: '🍽️',",
            "      },",
            "      {",
            "        id: 'cpkg-demo-3',",
            "        name: 'Reception Dinner Menu',",
            "        level: 'Basic',",
            "        description: 'Essential reception menu — starters, one main and dessert.',",
            "        subtitle: 'Basic tier · reception essentials · per person',",
            "        listPrice: 25000,",
            "        price: 25000,",
            "        status: 'draft',",
            "        pricingMode: 'per_person',",
            "        guestSlabs: defaultPackageGuestSlabs(),",
            "        itemIds: [],",
            "        imageEmoji: '🎉',",
            "      },",
            "    ],",
            "  };",
            "}",
            "",
            "function seedDemoFoodItems() {",
            "  const specs = [",
            "    {",
            "      key: foodMasterKey('m06', 'chicken-meat', 'Chicken Biriyani'),",
            "      slabs: [",
            "        { from: 1, to: 25, price: 200 },",
            "        { from: 26, to: 50, price: 180 },",
            "        { from: 51, to: 100, price: 165 },",
            "      ],",
            "    },",
            "    {",
            "      key: foodMasterKey('m07', 'grilled-roasted', 'Al Faham Chicken'),",
            "      slabs: [",
            "        { from: 1, to: 25, price: 220 },",
            "        { from: 26, to: 50, price: 200 },",
            "      ],",
            "    },",
            "    {",
            "      key: foodMasterKey('m01', 'traditional-dairy-drinks', 'Tea'),",
            "      slabs: [{ from: 1, to: 25, price: 15 }],",
            "    },",
            "    {",
            "      key: foodMasterKey('m01', 'traditional-dairy-drinks', 'Coffee'),",
            "      slabs: [{ from: 1, to: 25, price: 20 }],",
            "    },",
            "  ];",
            "  return specs",
            "    .map(function (spec) {",
            "      const hit = findMasterItem(spec.key);",
            "      if (!hit) return null;",
            "      return {",
            "        id: 'food-' + spec.key.replace(/::/g, '-'),",
            "        masterKey: spec.key,",
            "        name: hit.item.name,",
            "        moduleId: hit.module.id,",
            "        subcatId: hit.subcat.id,",
            "        subcatName: hit.subcat.name,",
            "        description: '',",
            "        diet: hit.item.diet,",
            "        pricingMode: 'per_person',",
            "        unitLabel: 'plate',",
            "        quoteOnly: false,",
            "        status: 'active',",
            "        individualListing: true,",
            "        slabs: spec.slabs || defaultItemSlabs(),",
            "        imageEmoji: hit.module.emoji,",
            "      };",
            "    })",
            "    .filter(Boolean);",
            "}",
            "",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    if not DOCX.is_file():
        raise SystemExit(f"Missing docx: {DOCX}")
    paras = extract_paragraphs(DOCX)
    parsed = strip_custom_catalog_entries(parse_modules(paras))
    if len(parsed) != 13:
        raise SystemExit(f"Expected 13 modules, got {len(parsed)}")
    total = sum(len(sc["items"]) for m in parsed for sc in m["subcats"])
    defs = attach_ids(parsed)
    OUT.write_text(emit_catalog_js(defs), encoding="utf-8")
    print(f"Wrote {OUT} — {total} catalogue items across 13 modules")


if __name__ == "__main__":
    main()
