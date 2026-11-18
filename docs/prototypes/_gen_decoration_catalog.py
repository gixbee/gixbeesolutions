#!/usr/bin/env python3
"""Generate _decoration_catalog.js — India-wide decoration catalogue (mockup-aligned)."""
from pathlib import Path
import json

# Order matches owner Add Items mockup (Church + Car as own categories).
CATS = [
    ("d01", "Stage / Mandapam", "🎪"),
    ("d02", "Church Decoration", "⛪"),
    ("d03", "Entrance & Welcome", "🚪"),
    ("d04", "Pathway Decoration", "🛤️"),
    ("d05", "Floral Decoration", "💐"),
    ("d06", "Lighting & Sound", "💡"),
    ("d07", "Seating & Furniture", "🪑"),
    ("d08", "Car Decoration", "🚗"),
    ("d09", "Photo & Display", "📸"),
    ("d10", "Special Effects", "✨"),
    ("d11", "Personal Flowers & Garlands", "💮"),
    ("d12", "Traditional / Ceremony Setup", "🪔"),
    ("d13", "Dining & Table", "🍽️"),
    ("d14", "Other Items", "📦"),
]

# Three main package items per category (matches Add Items mockup screens 2–9).
ITEMS = {
    "d01": [
        "Wedding Stage Decoration",
        "Couple Sofa / Diwan",
        "Stage Carpet / Runners",
    ],
    "d02": [
        "Church Entrance Arch",
        "Church Flower Stand",
        "Pew / Aisle Flowers",
    ],
    "d03": [
        "Welcome Arch",
        "Welcome Board",
        "Name LED Board",
    ],
    "d04": [
        "Aisle Carpet / Runner",
        "Aisle Floral Stands",
        "LED Pathway Lights",
    ],
    "d05": [
        "Floral Backdrop",
        "Floral Ceiling",
        "Bridal Bouquet",
    ],
    "d06": [
        "Stage Lighting",
        "Fairy / String Lights",
        "Sound System",
    ],
    "d07": [
        "Guest Chairs",
        "Chair Covers & Bows",
        "VIP Sofa Seating",
    ],
    "d08": [
        "Wedding Car Decoration",
        "Car Bonnet Decoration",
        "Car Door Decoration",
    ],
    "d09": [
        "Photo Booth Backdrop",
        "Couple Portrait Backdrop",
        "Hashtag LED Board",
    ],
    "d10": [
        "Low-Lying Fog",
        "Confetti Blast",
        "Sparkler Entry Package",
    ],
    "d11": [
        "Boutonniere (Groom)",
        "Bridesmaid Bouquets",
        "Garland for Groom Entry",
    ],
    "d12": [
        "Traditional Mandapam Setup",
        "Pooja Backdrop (Traditional)",
        "Nikah Signing Table Setup",
    ],
    "d13": [
        "Buffet Table Skirting & Décor",
        "Table Centrepieces",
        "Cake Table Setup",
    ],
    "d14": [
        "Ceiling Draping (Full Hall)",
        "Pillar Wrapping",
        "Custom Theme Props",
    ],
}

# Categories shown in package wizard step 3 (mockup flow 1–9).
PACKAGE_WIZARD_MODULE_IDS = {c[0] for c in CATS[:10]}

RUNTIME_JS = r"""
function decorTraditionKey(tag) {
  return String(tag || '')
    .toLowerCase()
    .replace(/[^a-z]/g, '');
}

function inferDecorationItemScopes(name) {
  const n = String(name || '').toLowerCase();
  const pkgScopes = [];
  const traditionScopes = [];
  const wedding =
    /\b(wedding|bridal|couple|mandap|mandapam|mehendi|mailanchi|haldi|sangeet|nikah|walima|engagement|reception|mala|throne|roka|chunni|pookalam|nilavilakku|couple name)\b/.test(
      n
    );
  const other =
    /\b(birthday|baby shower|corporate|housewarming|baptism|communion|navjote|festival|ganesh|onam|kids|inauguration|green room|repairs|balloon ceiling|balloon arch)\b/.test(
      n
    );
  if (wedding) pkgScopes.push('wedding');
  if (other) pkgScopes.push('other');
  if (!pkgScopes.length) pkgScopes.push('wedding', 'other');
  if (/\b(nikah|walima|islamic)\b/.test(n)) traditionScopes.push('muslim');
  if (/\b(church|baptism|communion|pew|altar|pulpit|lectern|cross)\b/.test(n)) traditionScopes.push('christian');
  if (
    /\b(mandap|mandapam|pookalam|haldi|mehendi|sangeet|marigold|nilavilakku|kalash|jasmine|malli|south indian|north indian|pooja|toran|thoranam|mango leaf|banana stem|garland for mala)\b/.test(
      n
    )
  )
    traditionScopes.push('hindu');
  if (/\b(anand karaj|gurdwara|jain|interfaith)\b/.test(n)) traditionScopes.push('others');
  if (
    /\b(corporate|minimal stage|balloon|kids|housewarming|weather|partition|ceiling draping|wall draping|pillar wrapping|direction|parking|registration|signage package|custom theme|garden|lawn tent|green room|repairs)\b/.test(
      n
    )
  ) {
    if (traditionScopes.indexOf('others') < 0) traditionScopes.push('others');
  }
  if (!traditionScopes.length) traditionScopes.push('hindu', 'muslim', 'christian', 'others');
  return { pkgScopes: pkgScopes, traditionScopes: traditionScopes };
}

function decorCatalogContextFromDraft(draft) {
  const d = draft || {};
  return {
    packageCategory: d.packageCategory || 'wedding',
    traditionTags: d.traditionTags || [],
  };
}

/** Categories only for selected communities (e.g. Church → Christian). */
const DECORATION_MODULE_TRADITIONS = {
  d02: ['christian'],
};

function decorModuleVisibleForPackage(mod, ctx) {
  if (!mod || !ctx) return true;
  const gate =
    typeof DECORATION_MODULE_TRADITIONS === 'object' ? DECORATION_MODULE_TRADITIONS[mod.id] : null;
  if (!gate || !gate.length) return true;
  const comm = ctx.traditionTags || [];
  if (!comm.length) return false;
  return comm.some(function (t) {
    return gate.indexOf(decorTraditionKey(t)) >= 0;
  });
}

/** Owner package wizard: list every main catalogue item per category (wedding/other only). */
function decorCatalogContextForOwnerPick(draft) {
  return Object.assign({}, decorCatalogContextFromDraft(draft), { ownerPick: true });
}

function decorItemVisibleForPackage(item, ctx) {
  if (ctx && ctx.showAll) return true;
  const scopes = {
    pkgScopes: item.pkgScopes || inferDecorationItemScopes(item.name).pkgScopes,
    traditionScopes: item.traditionScopes || inferDecorationItemScopes(item.name).traditionScopes,
  };
  const cat = ctx.packageCategory || 'wedding';
  const pkgOk =
    scopes.pkgScopes.indexOf('all') >= 0 ||
    scopes.pkgScopes.indexOf(cat) >= 0 ||
    (scopes.pkgScopes.indexOf('wedding') >= 0 && scopes.pkgScopes.indexOf('other') >= 0);
  if (!pkgOk) return false;
  if (ctx && ctx.ownerPick) return true;
  const comm = ctx.traditionTags || [];
  if (!comm.length) return true;
  return comm.some(function (t) {
    const key = decorTraditionKey(t);
    return scopes.traditionScopes.indexOf('all') >= 0 || scopes.traditionScopes.indexOf(key) >= 0;
  });
}

function decorFilteredModuleItems(mod, ctx, searchQ) {
  const q = (searchQ || '').trim().toLowerCase();
  return (mod.items || []).filter(function (it) {
    if (!decorItemVisibleForPackage(it, ctx)) return false;
    if (q && it.name.toLowerCase().indexOf(q) < 0) return false;
    return true;
  });
}

function decorModulesForPackage(ctx, searchQ) {
  const q = (searchQ || '').trim().toLowerCase();
  const pkgOnly = ctx && ctx.ownerPick;
  const allowIds = typeof DECORATION_PACKAGE_MODULE_IDS !== 'undefined' ? DECORATION_PACKAGE_MODULE_IDS : null;
  return DECORATION_MODULES.map(function (m) {
    if (pkgOnly && allowIds && allowIds.indexOf(m.id) < 0) return null;
    if (pkgOnly && !decorModuleVisibleForPackage(m, ctx)) return null;
    const nameHit = q && m.name.toLowerCase().indexOf(q) >= 0;
    const visible = decorFilteredModuleItems(m, ctx, nameHit ? '' : q);
    return { mod: m, visibleCount: visible.length, items: visible };
  })
    .filter(function (row) {
      return row && row.visibleCount > 0;
    });
}

function decorPackageCatalogSummary(ctx) {
  const cat = DECORATION_EVENT_CATEGORIES.filter(function (c) {
    return c.id === (ctx.packageCategory || 'wedding');
  })[0];
  const comm = (ctx.traditionTags || []).join(', ');
  const rows = decorModulesForPackage(ctx, '');
  let itemCount = 0;
  rows.forEach(function (r) {
    itemCount += r.visibleCount;
  });
  return {
    categories: rows.length,
    items: itemCount,
    label: (cat ? cat.label : 'Package') + (comm ? ' · ' + comm : ''),
  };
}

function buildDecorationModules() {
  return DECORATION_CATALOG_DEFS.map(function (m, idx) {
    const items = (m.items || []).map(function (name) {
      const scopes = inferDecorationItemScopes(name);
      return {
        id: m.id + '::' + String(name).toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 48),
        name: name,
        pkgScopes: scopes.pkgScopes,
        traditionScopes: scopes.traditionScopes,
      };
    });
    return { id: m.id, num: idx + 1, name: m.name, emoji: m.emoji, items: items };
  });
}
const DECORATION_MODULES = buildDecorationModules();

function findDecorationModule(moduleId) {
  return DECORATION_MODULES.find(function (m) { return m.id === moduleId; });
}

function defaultDecorationStore() {
  return {
    hubTab: 'packages',
    pkgFilter: 'all',
    pkgCategoryFilter: 'wedding',
    pkgSort: 'name',
    pkgSearch: '',
    catPackages: [],
    individualServices: [],
  };
}
"""


def main() -> None:
    out = Path(__file__).resolve().parent / "_decoration_catalog.js"
    lines = [
        "/** Decoration package catalogue — 3 main items per category; custom item for the rest. */",
        f"const DECORATION_PACKAGE_MODULE_IDS = {json.dumps(sorted(PACKAGE_WIZARD_MODULE_IDS))};",
        "const DECORATION_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];",
        "const DECORATION_PKG_LEVEL_HINTS = {",
        "  Basic: 'Essential décor for the function',",
        "  Standard: 'Popular look with balanced inclusions',",
        "  Premium: 'Grand setup with richer detailing',",
        "};",
        "const DECORATION_EVENT_CATEGORIES = [",
        "  { id: 'wedding', label: 'Wedding & Related Functions', hint: 'All wedding-related functions you offer in one package' },",
        "  { id: 'other', label: 'Other Functions', hint: 'Birthdays, baptisms, housewarming, corporate events, and more' },",
        "];",
        "const DECORATION_EVENT_TYPES = {",
        "  wedding: ['Wedding & related functions'],",
        "  other: ['Other functions'],",
        "};",
        "const DECORATION_TRADITIONS = ['Hindu','Muslim','Christian','Others'];",
        "const DECORATION_STYLES = ['Traditional','Modern','Floral','Royal','Minimal','Luxury','Theme Based','Custom'];",
        "const DECORATION_CEREMONY_SETUP = ['Traditional Mandapam','Church Ceremony Setup','Nikah Setup','Reception Stage','Engagement Stage','General Stage','Custom'];",
        "const DECORATION_UNITS = ['Per Event','Per Set','Per Unit','Per Item','Per Hour','Custom Quotation'];",
        "const DECORATION_GST = ['Included','Additional','Not Applicable'];",
        "",
        "const DECORATION_CATALOG_DEFS = [",
    ]
    for cid, name, emoji in CATS:
        items = ITEMS.get(cid, [])
        lines.append("  {")
        lines.append(f'    "id": "{cid}",')
        lines.append(f'    "name": {json.dumps(name)},')
        lines.append(f'    "emoji": {json.dumps(emoji)},')
        lines.append("    \"items\": " + json.dumps(items, ensure_ascii=False, indent=6).replace("\n", "\n    ") + ",")
        lines.append("  },")
    lines.append("];")
    lines.append(RUNTIME_JS.strip())
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    n = sum(len(ITEMS.get(c[0], [])) for c in CATS)
    print(f"wrote {out.name} — {len(CATS)} categories, {n} items")


if __name__ == "__main__":
    main()