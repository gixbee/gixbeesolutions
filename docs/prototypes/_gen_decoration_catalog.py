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

ITEMS = {
    "d01": [
        "Wedding Stage Decoration (Full Setup)",
        "Wedding Stage Backdrop (Fabric)",
        "Wedding Stage Backdrop (LED)",
        "Traditional Wooden Mandapam",
        "Floral Mandapam",
        "Crystal / Acrylic Stage Arch",
        "Stage Carpet / Runners",
        "Stage Steps with Floral Trim",
        "Couple Throne / Stage Seating",
        "Couple Sofa / Diwan (Stage)",
        "Name Board / LED Monogram",
        "Reception Stage (Full Setup)",
        "Engagement Stage",
        "Nikah Stage & Seating",
        "Sangeet / Mehendi Stage",
        "Haldi Ceremony Stage Setup",
        "Minimal Stage (Corporate)",
        "Outdoor Stage Canopy Frame",
        "Stage Side Pillars (Floral)",
        "LED Wall Backdrop",
        "Photo-Frame Stage Panel",
    ],
    "d02": [
        "Church Entrance Floral Arch",
        "Church Flower Stand",
        "Pew / Aisle Flowers",
        "Church Altar Flowers",
        "Church Pew Ends & Altar Florals",
        "Church Floral Altar Backdrop",
        "Pulpit / Lectern Floral Arrangement",
        "Communion Table Floral",
        "Church Side Entrance Décor",
        "Church Window / Ledge Florals",
        "Cross & Candle Altar Display",
        "Baptism / Communion Backdrop",
    ],
    "d03": [
        "Welcome Arch (Floral)",
        "Floral Entrance Arch",
        "Balloon Entrance Arch",
        "Fabric Drape Entrance",
        "Welcome Board (Printed)",
        "LED Welcome Sign",
        "Couple Name Entrance Board",
        "Name LED Board",
        "Direction / Parking Signage",
        "Floral Entrance Pillars (Pair)",
        "Welcome Table Arrangement",
        "Entrance Red Carpet",
        "Traditional Toran / Main Door Décor",
        "Nikah Entrance Arch",
        "Gate / Compound Entrance Draping",
        "Photo Welcome Stand",
        "Guest Registration Desk Décor",
        "Entrance Fairy Light Tunnel",
        "Marquee Entrance Framing",
    ],
    "d04": [
        "Aisle Carpet / Runner",
        "Central Aisle Red Carpet",
        "White / Ivory Aisle Carpet",
        "Floral Aisle Markers",
        "Aisle Floral Stands",
        "Petal Pathway",
        "Candle Aisle (Indoor)",
        "Outdoor Walkway Lanterns",
        "Garden Pathway Urns",
        "Mandapam Walkway Draping",
        "Reception Entry Path Lights",
        "LED Pathway Lights",
        "Bridal Entry Path (Traditional)",
        "Royal Carpet with Borders",
        "Mirror / Reflective Aisle Panels",
        "Outdoor Tent Walkway",
    ],
    "d05": [
        "Floral Backdrop",
        "Floral Ceiling",
        "Fresh Flower Ceiling Hangings",
        "Artificial Flower Ceiling",
        "Marigold Garlands (Bulk)",
        "Jasmine / Malli Strings",
        "Rose Floral Walls",
        "Mixed South Indian Flower Arrangements",
        "North Indian Floral Backdrop",
        "Orchid & Exotic Flower Décor",
        "Pooja Room Floral Setup",
        "Centre Table Floral (Reception)",
        "Haldi Marigold Setup",
        "Garland for Mala / Exchange",
        "Floral Pillars (Indoor)",
        "Wedding Eve Floral Installations",
        "Hanging Floral Chandeliers",
        "Bridal Bouquet (Hand-Tied)",
        "Tropical Flower Theme (Goa / Coastal)",
    ],
    "d06": [
        "Stage Lighting (Par / Focus)",
        "Fairy / String Lights (Warm)",
        "LED Strip Lighting",
        "Moving Head Lights",
        "Uplighters (Wall Wash)",
        "Outdoor Flood Lights",
        "Chandeliers (Rental)",
        "Pathway Bollard Lights",
        "Sound System (Basic PA)",
        "Sound System (Reception / DJ Ready)",
        "Wireless Microphones",
        "LED Dance Floor Lighting",
        "Name GOBO Projection",
        "Stage Truss Lighting",
        "Emergency Backup Lighting",
        "Generator / Power Distribution (Decorator)",
    ],
    "d07": [
        "Guest Chairs (Banquet)",
        "Chair Covers & Bows / Sashes",
        "Couple Sofa (White)",
        "Couple Diwan / Traditional Seating",
        "VIP Sofa Seating",
        "Royal Chairs (Pair)",
        "Chiavari Chairs",
        "Cushions & Covers",
        "VIP Seating Section",
        "Mehendi Low Seating",
        "Sangeet Stage Seating",
        "Bridal Green Room Sofa",
        "Bench Seating (Outdoor)",
        "Traditional Wooden Chairs",
        "Hospitality Counter Table",
        "Side Tables (Stage)",
    ],
    "d08": [
        "Wedding Car Decoration (Full)",
        "Wedding Car Bonnet Garland",
        "Car Door Floral Handles",
        "Car Door Decoration (Per Door)",
        "Car Ribbon & Bow Package",
        "Luxury Car Décor (Premium Flowers)",
        "Vintage Car Flower Drape",
        "Reception Car Send-Off Décor",
    ],
    "d09": [
        "Photo Booth Backdrop",
        "Selfie Point / Ring Light",
        "Couple Portrait Backdrop",
        "Family Photo Wall",
        "Polaroid / Guest Message Wall",
        "Hashtag LED Board",
        "Memory Lane Photo Line",
        "Instagram Frame Prop",
        "360° Spin Booth Space Décor",
        "Baby Shower Photo Corner",
        "Corporate Step-and-Repeat",
        "Gift Display Table",
    ],
    "d10": [
        "Cold Pyro / Cold Fire (Permit Required)",
        "Low-Lying Fog",
        "Smoke Machine",
        "Confetti Blast",
        "CO₂ Jet Effects",
        "Bubble Machine",
        "Projection Mapping (Basic)",
        "Sparkler Entry Package",
        "Indoor Safe Confetti",
        "Fireworks Synchronization (Where Permitted)",
        "Drone Show Coordination (Third Party)",
    ],
    "d11": [
        "Bridal Bouquet (Cascading)",
        "Christian Bridal Bouquet (White Roses)",
        "Bridesmaid Bouquets",
        "Boutonniere (Groom)",
        "Boutonniere (Groomsmen Set)",
        "Mother / Family Corsage",
        "Flower Basket (Petal Shower)",
        "Garland for Groom Entry",
        "Muslim Groom Flower Pin",
        "Marigold Car Toran",
        "Corporate Guest Welcome Bouquet",
        "Housewarming Door Flower Hangings",
    ],
    "d12": [
        "Banana Stem Traditional Mandapam Elements",
        "Mango Leaf Thoranam",
        "Coconut Leaf Toran",
        "Nilavilakku / Brass Lamps (Set)",
        "Kalash & Traditional Vessels",
        "Pooja Backdrop (Traditional)",
        "Pookalam / Rangoli Support Décor",
        "Haldi Plate & Seating Corner",
        "Mehendi / Mailanchi Seating Décor",
        "Nikah Signing Table Setup",
        "Islamic Geometric Backdrop Panel",
        "Walima Stage Floral (Green / Gold Theme)",
        "Anand Karaj Floral (Gurdwara Approved)",
        "Navjote Traditional Setup Elements",
        "Roka / Engagement Traditional Platform",
        "Chunni Ceremony Seating",
        "Jain Minimal Mandap Elements",
        "Interfaith Neutral Ceremony Backdrop",
    ],
    "d13": [
        "Buffet Table Skirting & Décor",
        "Dessert Counter Décor",
        "Cake Table Setup",
        "Welcome Drink Counter",
        "Table Centrepieces",
        "Table Runners & Linen",
        "Menu Display Board",
        "Live Counter Framing",
        "Corporate Buffet Branding",
        "South Indian Banana Leaf Station Décor",
        "High-Tea Table Styling",
    ],
    "d14": [
        "Ceiling Draping (Full Hall)",
        "Wall Draping / Masking",
        "Pillar Wrapping",
        "Partition Screens",
        "Home Décor (Housewarming)",
        "Garden / Lawn Tent Décor",
        "Weather Protection Sidewalls",
        "Green Room Makeover",
        "Signage Package (Event)",
        "Custom Theme Props",
        "Balloon Ceiling",
        "Kids Birthday Balloon Arch",
        "Corporate Stage Branding",
        "Festival Ganesh / Onam Installations",
        "Repairs & Touch-Up Kit (Day Of)",
    ],
}

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
  return DECORATION_MODULES.map(function (m) {
    const nameHit = q && m.name.toLowerCase().indexOf(q) >= 0;
    const visible = decorFilteredModuleItems(m, ctx, nameHit ? '' : q);
    return { mod: m, visibleCount: visible.length, items: visible };
  }).filter(function (row) {
    return row.visibleCount > 0;
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
        "/** All-India decoration catalogue — 14 categories (mockup-aligned sub-items per category). */",
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