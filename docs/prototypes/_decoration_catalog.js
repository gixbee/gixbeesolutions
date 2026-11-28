/** Decoration package catalogue — community + common wedding categories. */
const DECORATION_PACKAGE_MODULE_IDS = ["c01", "c02", "c03", "c04", "c05", "h01", "h02", "h03", "h04", "h05", "m01", "m02", "m03", "m04", "m05", "w01", "w02", "w03", "w04", "w05", "w06", "w07", "w08", "w09", "w10", "w11", "w12"];
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
    "id": "h01",
    "name": "Stage / Mandapam",
    "emoji": "\ud83c\udfaa",
    "scope": "community",
    "traditions": ["hindu"],
    "items": [
          "Traditional Mandapam",
          "Floral Mandapam",
          "Wooden Mandapam"
    ]
  },
  {
    "id": "h02",
    "name": "Traditional Ritual Decoration",
    "emoji": "\ud83e\ude94",
    "scope": "community",
    "traditions": ["hindu"],
    "items": [
          "Pooja Area Setup",
          "Homam / Havan Setup",
          "Kalash Arrangement"
    ]
  },
  {
    "id": "h03",
    "name": "Nilavilakku Decoration",
    "emoji": "\ud83e\ude94",
    "scope": "community",
    "traditions": ["hindu"],
    "items": [
          "Brass Nilavilakku",
          "Traditional Lamp Arrangement",
          "Decorative Lamp Setup"
    ]
  },
  {
    "id": "h04",
    "name": "Traditional Entrance Decoration",
    "emoji": "\ud83d\udeaa",
    "scope": "community",
    "traditions": ["hindu"],
    "items": [
          "Banana Stem Decoration",
          "Thoranam",
          "Traditional Welcome Arch"
    ]
  },
  {
    "id": "h05",
    "name": "Pookalam & Rangoli",
    "emoji": "\ud83c\udf38",
    "scope": "community",
    "traditions": ["hindu"],
    "items": [
          "Pookalam",
          "Floral Rangoli",
          "Kolam"
    ]
  },
  {
    "id": "c01",
    "name": "Stage / Wedding Backdrop",
    "emoji": "\ud83c\udfaa",
    "scope": "community",
    "traditions": ["christian"],
    "items": [
          "Wedding Stage",
          "Floral Stage",
          "Couple Backdrop"
    ]
  },
  {
    "id": "c02",
    "name": "Church Decoration",
    "emoji": "\u26ea",
    "scope": "community",
    "traditions": ["christian"],
    "items": [
          "Altar Floral Decoration",
          "Church Aisle Decoration",
          "Church Entrance Arch"
    ]
  },
  {
    "id": "c03",
    "name": "Church Seating Decoration",
    "emoji": "\ud83e\ude91",
    "scope": "community",
    "traditions": ["christian"],
    "items": [
          "Pew / Bench Floral Decoration",
          "Reserved Family Seating",
          "Chair Decoration"
    ]
  },
  {
    "id": "c04",
    "name": "Wedding Ceremony Decoration",
    "emoji": "\u271d\ufe0f",
    "scope": "community",
    "traditions": ["christian"],
    "items": [
          "Ceremony Backdrop",
          "Cross Backdrop (if requested)",
          "Prayer Area Decoration"
    ]
  },
  {
    "id": "c05",
    "name": "Church Floral Decoration",
    "emoji": "\ud83d\udc90",
    "scope": "community",
    "traditions": ["christian"],
    "items": [
          "White Rose Arrangement",
          "Lily Arrangement",
          "Orchid Arrangement"
    ]
  },
  {
    "id": "m01",
    "name": "Stage / Nikah Stage",
    "emoji": "\ud83c\udfaa",
    "scope": "community",
    "traditions": ["muslim"],
    "items": [
          "Nikah Stage",
          "Floral Nikah Stage",
          "Traditional Nikah Backdrop"
    ]
  },
  {
    "id": "m02",
    "name": "Nikah Ceremony Decoration",
    "emoji": "\ud83d\udcdc",
    "scope": "community",
    "traditions": ["muslim"],
    "items": [
          "Nikah Seating Setup",
          "Nikah Signing Table",
          "Ceremony Area Setup"
    ]
  },
  {
    "id": "m03",
    "name": "Nikah Backdrop Decoration",
    "emoji": "\ud83d\uddbc\ufe0f",
    "scope": "community",
    "traditions": ["muslim"],
    "items": [
          "Floral Nikah Backdrop",
          "Fabric Backdrop",
          "Personalised Nikah Backdrop"
    ]
  },
  {
    "id": "m04",
    "name": "Family Seating Decoration",
    "emoji": "\ud83e\ude91",
    "scope": "community",
    "traditions": ["muslim"],
    "items": [
          "Family Seating Setup",
          "Separate Seating Arrangement (if requested)",
          "VIP Family Seating"
    ]
  },
  {
    "id": "m05",
    "name": "Nikah Welcome Decoration",
    "emoji": "\ud83d\udeaa",
    "scope": "community",
    "traditions": ["muslim"],
    "items": [
          "Nikah Welcome Board",
          "Personalised Nikah Signage",
          "Ceremony Welcome Setup"
    ]
  },
  {
    "id": "w01",
    "name": "Entrance & Welcome",
    "emoji": "\ud83d\udeaa",
    "scope": "common",
    "traditions": [],
    "items": [
          "Floral Welcome Arch",
          "Grand Entrance",
          "Welcome Board"
    ]
  },
  {
    "id": "w02",
    "name": "Pathway Decoration",
    "emoji": "\ud83d\udee4\ufe0f",
    "scope": "common",
    "traditions": [],
    "items": [
          "Floral Pathway",
          "Flower Carpet",
          "Petal Decoration"
    ]
  },
  {
    "id": "w03",
    "name": "Floral Decoration",
    "emoji": "\ud83d\udc90",
    "scope": "common",
    "traditions": [],
    "items": [
          "Rose Decoration",
          "Jasmine Decoration",
          "Orchid Decoration"
    ]
  },
  {
    "id": "w04",
    "name": "Lighting & Sound",
    "emoji": "\ud83d\udca1",
    "scope": "common",
    "traditions": [],
    "items": [
          "Decorative Lighting",
          "Stage Lighting",
          "Sound System"
    ]
  },
  {
    "id": "w05",
    "name": "Seating & Furniture",
    "emoji": "\ud83e\ude91",
    "scope": "common",
    "traditions": [],
    "items": [
          "Couple Sofa",
          "Guest Chairs",
          "VIP Seating"
    ]
  },
  {
    "id": "w06",
    "name": "Car Decoration",
    "emoji": "\ud83d\ude97",
    "scope": "common",
    "traditions": [],
    "items": [
          "Wedding Car Floral Decoration",
          "Ribbon Decoration",
          "Car Bonnet Floral"
    ]
  },
  {
    "id": "w07",
    "name": "Photo & Display",
    "emoji": "\ud83d\udcf8",
    "scope": "common",
    "traditions": [],
    "items": [
          "Couple Photo Display",
          "Family Photo Display",
          "Direction Board"
    ]
  },
  {
    "id": "w08",
    "name": "Special Effects",
    "emoji": "\u2728",
    "scope": "common",
    "traditions": [],
    "items": [
          "Flower Shower",
          "Cold Pyro",
          "Confetti"
    ]
  },
  {
    "id": "w09",
    "name": "Ceiling & Hanging Decoration",
    "emoji": "\ud83c\udf80",
    "scope": "common",
    "traditions": [],
    "items": [
          "Floral Ceiling",
          "Hanging Flowers",
          "Fabric Draping"
    ]
  },
  {
    "id": "w10",
    "name": "Dining & Table Decoration",
    "emoji": "\ud83c\udf7d\ufe0f",
    "scope": "common",
    "traditions": [],
    "items": [
          "Table Centrepieces",
          "Dining Area Decoration",
          "Buffet Counter Decoration"
    ]
  },
  {
    "id": "w11",
    "name": "Photo Booth & Guest Experience",
    "emoji": "\ud83e\udd33",
    "scope": "common",
    "traditions": [],
    "items": [
          "Selfie Booth",
          "Couple Photo Booth",
          "Guest Welcome Area"
    ]
  },
  {
    "id": "w12",
    "name": "Outdoor & Venue Decoration",
    "emoji": "\ud83c\udf33",
    "scope": "common",
    "traditions": [],
    "items": [
          "Garden Decoration",
          "Lawn Decoration",
          "Building Exterior Decoration"
    ]
  },
];
function decorTraditionKey(tag) {
  return String(tag || '')
    .toLowerCase()
    .replace(/[^a-z]/g, '');
}

function decorHasOthersTradition(tags) {
  return (tags || []).some(function (t) {
    return decorTraditionKey(t) === 'others';
  });
}

function decorFormatTraditionTags(tags, otherText) {
  const other = (otherText || '').trim();
  return (tags || [])
    .map(function (t) {
      if (decorTraditionKey(t) === 'others' && other) return other;
      return t;
    })
    .join(', ');
}

function decorPrimaryCommunityKey(ctx) {
  const comm = (ctx && ctx.traditionTags) || [];
  if (!comm.length) return '';
  return decorTraditionKey(comm[0]);
}

function inferDecorationItemScopes(name) {
  const n = String(name || '').toLowerCase();
  const pkgScopes = ['wedding', 'other'];
  const traditionScopes = ['hindu', 'muslim', 'christian', 'others'];
  return { pkgScopes: pkgScopes, traditionScopes: traditionScopes };
}

function decorCatalogContextFromDraft(draft) {
  const d = draft || {};
  const tags = (d.traditionTags || []).slice(0, 1);
  return {
    packageCategory: d.packageCategory || 'wedding',
    traditionTags: tags,
  };
}

function decorModuleVisibleForPackage(mod, ctx) {
  if (!mod || !ctx) return true;
  const pkgCat = ctx.packageCategory || 'wedding';
  const scope = mod.moduleScope || 'common';
  if (scope === 'common') return pkgCat === 'wedding' || pkgCat === 'other';
  if (pkgCat !== 'wedding') return false;
  const gates = mod.moduleTraditions || [];
  if (!gates.length) return false;
  const key = decorPrimaryCommunityKey(ctx);
  if (!key) return false;
  if (key === 'others') return false;
  return gates.indexOf(key) >= 0;
}

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
  const key = decorTraditionKey(comm[0]);
  return scopes.traditionScopes.indexOf('all') >= 0 || scopes.traditionScopes.indexOf(key) >= 0;
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
  }).filter(function (row) {
    return row && row.visibleCount > 0;
  });
}

function decorModulesGroupedForPackage(ctx, searchQ) {
  const rows = decorModulesForPackage(ctx, searchQ);
  const community = [];
  const common = [];
  rows.forEach(function (row) {
    if ((row.mod.moduleScope || 'common') === 'community') community.push(row);
    else common.push(row);
  });
  return { community: community, common: common, all: rows };
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
    return {
      id: m.id,
      num: idx + 1,
      name: m.name,
      emoji: m.emoji,
      moduleScope: m.scope || 'common',
      moduleTraditions: m.traditions || [],
      items: items,
    };
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
