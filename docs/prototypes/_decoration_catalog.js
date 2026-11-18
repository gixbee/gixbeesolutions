/** Decoration package catalogue — 3 main items per category; custom item for the rest. */
const DECORATION_PACKAGE_MODULE_IDS = ["d01", "d02", "d03", "d04", "d05", "d06", "d07", "d08", "d09", "d10"];
const DECORATION_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];
const DECORATION_PKG_LEVEL_HINTS = {
  Basic: 'Essential décor for the function',
  Standard: 'Popular look with balanced inclusions',
  Premium: 'Grand setup with richer detailing',
};
const DECORATION_EVENT_CATEGORIES = [
  { id: 'wedding', label: 'Wedding & Related Functions', hint: 'All wedding-related functions you offer in one package' },
  { id: 'other', label: 'Other Functions', hint: 'Birthdays, baptisms, housewarming, corporate events, and more' },
];
const DECORATION_EVENT_TYPES = {
  wedding: ['Wedding & related functions'],
  other: ['Other functions'],
};
const DECORATION_TRADITIONS = ['Hindu','Muslim','Christian','Others'];
const DECORATION_STYLES = ['Traditional','Modern','Floral','Royal','Minimal','Luxury','Theme Based','Custom'];
const DECORATION_CEREMONY_SETUP = ['Traditional Mandapam','Church Ceremony Setup','Nikah Setup','Reception Stage','Engagement Stage','General Stage','Custom'];
const DECORATION_UNITS = ['Per Event','Per Set','Per Unit','Per Item','Per Hour','Custom Quotation'];
const DECORATION_GST = ['Included','Additional','Not Applicable'];

const DECORATION_CATALOG_DEFS = [
  {
    "id": "d01",
    "name": "Stage / Mandapam",
    "emoji": "\ud83c\udfaa",
    "items": [
          "Wedding Stage Decoration",
          "Couple Sofa / Diwan",
          "Stage Carpet / Runners"
    ],
  },
  {
    "id": "d02",
    "name": "Church Decoration",
    "emoji": "\u26ea",
    "items": [
          "Church Entrance Arch",
          "Church Flower Stand",
          "Pew / Aisle Flowers"
    ],
  },
  {
    "id": "d03",
    "name": "Entrance & Welcome",
    "emoji": "\ud83d\udeaa",
    "items": [
          "Welcome Arch",
          "Welcome Board",
          "Name LED Board"
    ],
  },
  {
    "id": "d04",
    "name": "Pathway Decoration",
    "emoji": "\ud83d\udee4\ufe0f",
    "items": [
          "Aisle Carpet / Runner",
          "Aisle Floral Stands",
          "LED Pathway Lights"
    ],
  },
  {
    "id": "d05",
    "name": "Floral Decoration",
    "emoji": "\ud83d\udc90",
    "items": [
          "Floral Backdrop",
          "Floral Ceiling",
          "Bridal Bouquet"
    ],
  },
  {
    "id": "d06",
    "name": "Lighting & Sound",
    "emoji": "\ud83d\udca1",
    "items": [
          "Stage Lighting",
          "Fairy / String Lights",
          "Sound System"
    ],
  },
  {
    "id": "d07",
    "name": "Seating & Furniture",
    "emoji": "\ud83e\ude91",
    "items": [
          "Guest Chairs",
          "Chair Covers & Bows",
          "VIP Sofa Seating"
    ],
  },
  {
    "id": "d08",
    "name": "Car Decoration",
    "emoji": "\ud83d\ude97",
    "items": [
          "Wedding Car Decoration",
          "Car Bonnet Decoration",
          "Car Door Decoration"
    ],
  },
  {
    "id": "d09",
    "name": "Photo & Display",
    "emoji": "\ud83d\udcf8",
    "items": [
          "Photo Booth Backdrop",
          "Couple Portrait Backdrop",
          "Hashtag LED Board"
    ],
  },
  {
    "id": "d10",
    "name": "Special Effects",
    "emoji": "\u2728",
    "items": [
          "Low-Lying Fog",
          "Confetti Blast",
          "Sparkler Entry Package"
    ],
  },
  {
    "id": "d11",
    "name": "Personal Flowers & Garlands",
    "emoji": "\ud83d\udcae",
    "items": [
          "Boutonniere (Groom)",
          "Bridesmaid Bouquets",
          "Garland for Groom Entry"
    ],
  },
  {
    "id": "d12",
    "name": "Traditional / Ceremony Setup",
    "emoji": "\ud83e\ude94",
    "items": [
          "Traditional Mandapam Setup",
          "Pooja Backdrop (Traditional)",
          "Nikah Signing Table Setup"
    ],
  },
  {
    "id": "d13",
    "name": "Dining & Table",
    "emoji": "\ud83c\udf7d\ufe0f",
    "items": [
          "Buffet Table Skirting & Décor",
          "Table Centrepieces",
          "Cake Table Setup"
    ],
  },
  {
    "id": "d14",
    "name": "Other Items",
    "emoji": "\ud83d\udce6",
    "items": [
          "Ceiling Draping (Full Hall)",
          "Pillar Wrapping",
          "Custom Theme Props"
    ],
  },
];
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
