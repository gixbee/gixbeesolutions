/** Gixbee catering customer flow. Plate price follows the guest count. */

const CC_BUILD = 'catering-customer-2';
const CC_BUDGET_CAP = 3000;
const CC_MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

function slabsFor(price) {
  return [
    { from: 1, to: 100, price: price + 80 },
    { from: 101, to: 250, price: price + 40 },
    { from: 251, to: 500, price: price },
    { from: 501, to: 2000, price: Math.max(80, price - 30) },
  ];
}

const SADHYA = [
  { name: 'Welcome Drinks', items: ['Lime juice'] },
  {
    name: 'Sadhya Items',
    items: ['Kerala matta rice', 'Parippu', 'Sambar', 'Avial', 'Thoran', 'Olan', 'Kichadi', 'Pachadi'],
  },
  { name: 'Curries & Gravies', items: ['Pulissery', 'Kaalan', 'Erissery', 'Theeyal'] },
  { name: 'Accompaniments', items: ['Pickle', 'Pappadam', 'Banana'] },
  { name: 'Desserts & Sweets', items: ['Palada payasam', 'Ada pradhaman', 'Semiya payasam', 'Banana'] },
];

function foodGroupLabel(id) {
  const hit = ccCustomerFoodGroups().filter(function (g) {
    return g.id === id;
  })[0];
  return hit ? hit.label : 'Other dishes';
}

const CC_WEDDING_MENU = ccPackageMenuFromModules(ccDemoWeddingMenuModules());

const CATERERS = [
  {
    id: 'archana',
    name: 'Archana Catering',
    area: 'Thrissur',
    serves: ['Thrissur', 'Pathanamthitta', 'Ernakulam', 'Pandalam'],
    rating: 4.9,
    reviews: 186,
    available: true,
    emoji: '🍽️',
    color: 'linear-gradient(145deg,#BE185D,#9D174D)',
    about:
      'Kerala wedding and reception catering with the same nine-group menu owners build on Gixbee — veg-only sadhya or mixed menus, buffet or table service.',
    specialities: ['Wedding packages', 'Live counters', 'Guest slab pricing'],
    photos: ['🍽️', '🍛', '🥗', '🍮'],
    reviewList: [
      { name: 'Sneha', stars: 5, text: 'Christian Wedding package matched the owner listing — clear per-plate offer for 300 guests.' },
      { name: 'Roy', stars: 5, text: 'Buffet and table service chips helped us pick the right package quickly.' },
    ],
    packages: [
      {
        id: 'arch-christian-wedding',
        name: 'Christian Wedding',
        level: 'Basic',
        category: 'wedding',
        dietType: 'mixed',
        serveStyle: 'buffet',
        popular: true,
        blurb: 'Full day wedding catering with Kerala dishes and live counters.',
        offerEnabled: true,
        discountPercent: 8,
        guestSlabs: ccGuestSlabsLikeOwner(300),
        menuModules: ccDemoWeddingMenuModules(),
        groups: CC_WEDDING_MENU,
      },
      {
        id: 'arch-royal-reception',
        name: 'Royal Reception',
        level: 'Premium',
        category: 'wedding',
        dietType: 'mixed',
        serveStyle: 'both',
        blurb: 'Premium reception spread with table sadhya and buffet counters.',
        offerEnabled: true,
        discountPercent: 8,
        guestSlabs: ccGuestSlabsLikeOwner(450),
        groups: CC_WEDDING_MENU,
      },
      {
        id: 'arch-veg-sadhya',
        name: 'Veg Sadhya Feast',
        level: 'Standard',
        category: 'wedding',
        dietType: 'veg',
        serveStyle: 'table',
        blurb: 'Vegetarian wedding sadhya served on plantain leaf.',
        guestSlabs: ccGuestSlabsLikeOwner(280),
        groups: ccPackageMenuFromModules([
          { moduleId: 'g01', items: ['Fresh Lime Juice', 'Sambharam / Spiced Buttermilk'] },
          { moduleId: 'g02', items: ['Vegetable Samosa', 'Banana Fritters', 'Unnakaya'] },
          { moduleId: 'g03', items: ['Kerala Matta Rice', 'Ghee Rice', 'Nei Choru'] },
          { moduleId: 'g05', items: ['Sambar', 'Avial', 'Pulissery', 'Kaalan'] },
          { moduleId: 'g06', items: ['Mixed Vegetable Thoran', 'Beans Thoran', 'Cabbage Thoran'] },
          { moduleId: 'g07', items: ['Pappadam', 'Pickle', 'Banana'] },
          { moduleId: 'g08', items: ['Palada Payasam', 'Ada Pradhaman'] },
        ]),
      },
    ],
    foods: [
      {
        id: 'arch-tea',
        name: 'Tea',
        moduleId: 'g01',
        group: 'g01',
        dietType: 'veg',
        emoji: '☕',
        description: 'Fresh tea — same catalogue item owners list individually.',
        slabs: [{ from: 1, to: 500, price: 15 }],
        rateMode: 'flat',
      },
      {
        id: 'arch-biri',
        name: 'Chicken Biriyani',
        moduleId: 'g03',
        group: 'g03',
        dietType: 'non_veg',
        emoji: '🍚',
        description: 'Malabar chicken biriyani with tiered guest pricing.',
        offerEnabled: true,
        discountPercent: 10,
        slabs: ccGuestSlabsLikeOwner(180),
      },
      {
        id: 'arch-dosa',
        name: 'Live Dosa (per plate)',
        moduleId: 'g09',
        group: 'g09',
        dietType: 'veg',
        emoji: '🥞',
        description: 'Counter-style dosa priced per guest plate.',
        slabs: ccGuestSlabsLikeOwner(90),
      },
    ],
  },
  {
    id: 'arya',
    name: 'Arya Catering',
    area: 'Pathanamthitta',
    serves: ['Pathanamthitta', 'Pandalam', 'Adoor'],
    rating: 4.8,
    reviews: 120,
    available: true,
    emoji: '🍛',
    color: 'linear-gradient(145deg,#166534,#CA8A04)',
    about:
      'Traditional and modern catering for all occasions. Quality ingredients, professional service and customised menus.',
    specialities: ['Live Counters', 'Other Functions'],
    photos: ['🍛', '🥗', '🍮', '🥥'],
    reviewList: [
      { name: 'Meera', stars: 5, text: 'The wedding sadhya was on time and the payasam was excellent.' },
      { name: 'Anand', stars: 4, text: 'Clear plate price for 300 guests. Easy to compare.' },
    ],
    packages: [
      {
        id: 'arya-trad',
        name: 'Traditional Wedding Menu',
        level: 'Basic',
        category: 'wedding',
        menuStyle: 'sadhya',
        dietType: 'veg',
        popular: true,
        blurb: 'Traditional Kerala wedding menu with authentic dishes, perfect for wedding functions.',
        guestSlabs: slabsFor(300),
        groups: SADHYA,
      },
      {
        id: 'arya-special',
        name: 'Wedding Special Menu',
        level: 'Standard',
        category: 'wedding',
        menuStyle: 'sadhya',
        dietType: 'mixed',
        blurb: 'Sadhya plus a non-veg main for reception and wedding lunch.',
        guestSlabs: slabsFor(380),
        groups: SADHYA.concat([{ name: 'Non-veg mains', items: ['Chicken roast', 'Fish curry'] }]),
      },
      {
        id: 'arya-premium',
        name: 'Premium Wedding Feast',
        level: 'Premium',
        category: 'wedding',
        menuStyle: 'buffet',
        dietType: 'mixed',
        blurb: 'Grand feast with live counters and an extended dessert selection.',
        guestSlabs: slabsFor(450),
        groups: SADHYA.concat([{ name: 'Live counters', items: ['Dosa counter', 'Chaat counter'] }]),
      },
      {
        id: 'arya-birthday',
        name: 'Birthday Sadhya',
        level: 'Basic',
        category: 'other',
        menuStyle: 'sadhya',
        dietType: 'veg',
        blurb: 'A shorter vegetarian sadhya for birthdays and housewarmings.',
        guestSlabs: slabsFor(250),
        groups: SADHYA.slice(0, 3),
      },
    ],
    foods: [
      {
        id: 'arya-tea',
        name: 'Tea',
        group: 'g01',
        dietType: 'veg',
        emoji: '☕',
        description: 'Fresh tea served with the meal.',
        slabs: [{ from: 1, to: 2000, price: 15 }],
        rateMode: 'flat',
      },
      {
        id: 'arya-avial',
        name: 'Avial',
        group: 'g05',
        dietType: 'veg',
        emoji: '🥗',
        description: 'Mixed vegetables in coconut and curd.',
        slabs: slabsFor(40),
      },
      {
        id: 'arya-biri',
        name: 'Chicken Biriyani',
        group: 'g03',
        dietType: 'non_veg',
        emoji: '🍚',
        description: 'Malabar chicken biriyani, priced per plate.',
        offerEnabled: true,
        discountPercent: 10,
        slabs: slabsFor(180),
      },
    ],
  },
  {
    id: 'sree',
    name: 'Sree Krishna Caters',
    area: 'Pandalam',
    serves: ['Pathanamthitta', 'Pandalam'],
    rating: 4.6,
    reviews: 78,
    available: true,
    emoji: '🍱',
    color: 'linear-gradient(145deg,#047857,#65A30D)',
    about: 'Family catering from Pandalam for weddings and temple functions.',
    specialities: ['Sadhya', 'Temple functions'],
    photos: ['🍱', '🥥'],
    reviewList: [{ name: 'Lakshmi', stars: 5, text: 'Neat service and a proper vegetarian sadhya.' }],
    packages: [
      {
        id: 'sree-veg',
        name: 'Temple Sadhya',
        level: 'Standard',
        category: 'wedding',
        menuStyle: 'sadhya',
        dietType: 'veg',
        blurb: 'Full vegetarian sadhya.',
        guestSlabs: slabsFor(350),
        groups: SADHYA,
      },
      {
        id: 'sree-mix',
        name: 'Feast with Chicken',
        level: 'Premium',
        category: 'wedding',
        menuStyle: 'buffet',
        dietType: 'mixed',
        blurb: 'Sadhya with a chicken main.',
        guestSlabs: slabsFor(550),
        groups: SADHYA,
      },
    ],
    foods: [
      {
        id: 'sree-payasam',
        name: 'Palada Payasam',
        group: 'g08',
        dietType: 'veg',
        emoji: '🍮',
        description: 'Classic palada payasam, priced per plate for your guest count.',
        slabs: slabsFor(45),
      },
      {
        id: 'sree-sambar',
        name: 'Sambar',
        group: 'g05',
        dietType: 'veg',
        emoji: '🥘',
        description: 'Traditional Kerala sambar served as an add-on dish.',
        slabs: [{ from: 1, to: 2000, price: 35 }],
        rateMode: 'flat',
      },
      {
        id: 'sree-chicken',
        name: 'Chicken Curry',
        group: 'g05',
        dietType: 'non_veg',
        emoji: '🍗',
        description: 'Homestyle chicken curry per plate.',
        slabs: slabsFor(120),
      },
    ],
  },
  {
    id: 'royal',
    name: 'Royal Feast Catering',
    area: 'Pathanamthitta',
    serves: ['Pathanamthitta', 'Adoor'],
    rating: 4.5,
    reviews: 76,
    available: true,
    emoji: '👑',
    color: 'linear-gradient(145deg,#B45309,#CA8A04)',
    about: 'Reception and wedding menus with live counters.',
    specialities: ['Live Counters'],
    photos: ['👑', '🍛'],
    reviewList: [{ name: 'Joseph', stars: 4, text: 'Good reception menu and polite staff.' }],
    packages: [
      {
        id: 'royal-basic',
        name: 'Reception Sadhya',
        level: 'Basic',
        category: 'wedding',
        menuStyle: 'sadhya',
        dietType: 'veg',
        blurb: 'Vegetarian reception menu.',
        guestSlabs: slabsFor(300),
        groups: SADHYA,
      },
      {
        id: 'royal-std',
        name: 'Royal Mixed Feast',
        level: 'Standard',
        category: 'wedding',
        menuStyle: 'buffet',
        dietType: 'mixed',
        blurb: 'Mixed reception feast.',
        guestSlabs: slabsFor(500),
        groups: SADHYA,
      },
      {
        id: 'royal-arab',
        name: 'Arabian Mandi Spread',
        level: 'Standard',
        category: 'wedding',
        menuStyle: 'arabian',
        dietType: 'mixed',
        blurb: 'Mandi, grill and bread for a reception.',
        guestSlabs: slabsFor(420),
        groups: [
          { name: 'Mandi and grills', items: ['Chicken mandi', 'Al faham chicken'] },
          { name: 'Breads', items: ['Kuboos', 'Rumali roti'] },
          { name: 'Payasam and desserts', items: ['Fresh fruit platter'] },
        ],
      },
    ],
    foods: [
      {
        id: 'royal-ghee',
        name: 'Ghee Rice',
        group: 'g03',
        dietType: 'veg',
        emoji: '🍚',
        description: 'Fragrant ghee rice, ideal as an add-on to reception menus.',
        slabs: slabsFor(55),
      },
      {
        id: 'royal-dosa',
        name: 'Live Dosa (per plate)',
        group: 'g09',
        dietType: 'veg',
        emoji: '🥞',
        description: 'Counter-style dosa service priced per guest plate.',
        offerEnabled: true,
        discountPercent: 8,
        slabs: slabsFor(90),
      },
      {
        id: 'royal-grill',
        name: 'Grilled Chicken',
        group: 'g03',
        dietType: 'non_veg',
        emoji: '🍖',
        description: 'Grilled chicken portion per plate.',
        slabs: slabsFor(160),
      },
    ],
  },
  {
    id: 'grace',
    name: 'Grace Catering',
    area: 'Pathanamthitta',
    serves: ['Pathanamthitta'],
    rating: 4.0,
    reviews: 64,
    available: false,
    emoji: '🍽️',
    color: 'linear-gradient(145deg,#64748B,#94A3B8)',
    about: 'Booked out for this date. You can still read the menu.',
    specialities: ['House functions'],
    photos: ['🍽️'],
    reviewList: [{ name: 'Anita', stars: 4, text: 'Polite team. Book early for December.' }],
    packages: [
      {
        id: 'grace-wedding-veg',
        name: 'Simple Wedding Sadhya',
        level: 'Basic',
        category: 'wedding',
        menuStyle: 'sadhya',
        dietType: 'veg',
        blurb: 'Compact vegetarian wedding sadhya when we have an open date.',
        guestSlabs: slabsFor(280),
        groups: SADHYA.slice(0, 4),
      },
      {
        id: 'grace-veg',
        name: 'House Sadhya',
        level: 'Basic',
        category: 'other',
        menuStyle: 'sadhya',
        dietType: 'veg',
        blurb: 'Home-function vegetarian menu.',
        guestSlabs: slabsFor(250),
        groups: SADHYA.slice(0, 4),
      },
      {
        id: 'grace-mix',
        name: 'House Feast',
        level: 'Standard',
        category: 'wedding',
        menuStyle: 'buffet',
        dietType: 'mixed',
        blurb: 'Mixed menu for a house wedding.',
        guestSlabs: slabsFor(450),
        groups: SADHYA,
      },
    ],
    foods: [
      {
        id: 'grace-tea',
        name: 'Tea',
        group: 'g01',
        dietType: 'veg',
        emoji: '☕',
        description: 'Hot tea service with meals.',
        slabs: [{ from: 1, to: 2000, price: 12 }],
        rateMode: 'flat',
      },
      {
        id: 'grace-avial',
        name: 'Avial',
        group: 'g05',
        dietType: 'veg',
        emoji: '🥗',
        description: 'Mixed vegetable avial per plate.',
        slabs: slabsFor(38),
      },
      {
        id: 'grace-fish',
        name: 'Fish Fry',
        group: 'g02',
        dietType: 'non_veg',
        emoji: '🐟',
        description: 'Crisp Kerala-style fish fry per plate.',
        slabs: slabsFor(140),
      },
    ],
  },
];

const state = {
  location: 'Pathanamthitta',
  date: '2026-12-15',
  guests: 300,
  functionType: 'wedding',
  budgetMin: 0,
  budgetMax: 300,
  menuDietFilter: 'all',
  catererId: null,
  profileTab: 'overview',
  saved: {},
  menuTab: 'packages',
  serveFilter: 'all',
  tier: 'all',
  openGroup: '',
  detailTab: 'menu',
  selection: null,
  selectedFoodIds: [],
  note: '',
  sent: false,
  showCustomRequirements: false,
  calViewYear: 2026,
  calViewMonth: 12,
  calPickDay: 15,
};

function el(id) {
  return document.getElementById(id);
}
function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
function show(id) {
  document.querySelectorAll('.scr').forEach(function (s) {
    s.classList.toggle('on', s.id === id);
  });
  const scr = el(id);
  if (scr) scr.scrollTop = 0;
}
function toast(m) {
  const t = el('ccToast');
  if (!t) return;
  t.textContent = m;
  t.style.display = 'block';
  clearTimeout(toast._t);
  toast._t = setTimeout(function () {
    t.style.display = 'none';
  }, 2400);
}
function inr(n) {
  return '₹' + Math.max(0, Math.round(+n || 0)).toLocaleString('en-IN');
}
function formatWhen(iso) {
  const d = new Date(String(iso) + 'T00:00:00');
  if (isNaN(d.getTime())) return '';
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}
function slabPrice(slabs, guests) {
  const c = +guests || 0;
  const list = slabs || [];
  let i;
  for (i = 0; i < list.length; i++) {
    if (c >= +list[i].from && c <= +list[i].to) return +list[i].price || 0;
  }
  if (!list.length) return 0;
  return +list[list.length - 1].price || 0;
}
function offerPct(item) {
  if (!item || !item.offerEnabled) return 0;
  const n = Math.round(+item.discountPercent);
  return n >= 1 && n <= 90 ? n : 0;
}
function priceAfterOffer(base, pct) {
  return Math.max(0, Math.round((base * (100 - pct)) / 100));
}
function pricingSlabs(item) {
  return item.guestSlabs || item.slabs || [];
}
function isTieredGuestPricing(slabs) {
  if (!slabs || slabs.length <= 1) return false;
  const p0 = +slabs[0].price;
  let i;
  for (i = 1; i < slabs.length; i++) {
    if (+slabs[i].price !== p0) return true;
  }
  return false;
}
function activeSlabIndex(slabs, guests) {
  const c = +guests || 0;
  let i;
  for (i = 0; i < (slabs || []).length; i++) {
    if (c >= +slabs[i].from && c <= +slabs[i].to) return i;
  }
  if (!slabs || !slabs.length) return -1;
  return slabs.length - 1;
}
function guestRangeLabel(s) {
  const to = +s.to;
  const from = +s.from;
  if (to >= 2000 || to >= 9999) return from.toLocaleString('en-IN') + '+ guests';
  return from.toLocaleString('en-IN') + ' – ' + to.toLocaleString('en-IN') + ' guests';
}
function slabQuoteFromBase(item, basePrice) {
  const pct = offerPct(item);
  const base = +basePrice || 0;
  const offer = pct ? priceAfterOffer(base, pct) : base;
  return { base: base, offer: offer, pct: pct };
}
function renderDetailSlabSection(item, guests) {
  const slabs = pricingSlabs(item);
  const q = plateOf(item, guests);
  if (!slabs.length) {
    return (
      '<div class="slab-box"><p class="slab-box-h">Per plate</p><p class="slab-yours">For your <b>' +
      guests +
      ' guests</b>: ' +
      priceHtml(q) +
      '</p></div>'
    );
  }
  if (!isTieredGuestPricing(slabs)) {
    const flat = slabQuoteFromBase(item, +slabs[0].price || q.base);
    return (
      '<div class="slab-box"><p class="slab-box-h">Per plate</p><p class="slab-yours"><b>' +
      priceHtml(flat) +
      '</b></p><p class="slab-note">Same rate for all guest counts.</p></div>'
    );
  }
  const active = activeSlabIndex(slabs, guests);
  let html = '<div class="slab-box"><p class="slab-box-h">Per plate by guest count</p><div class="slab-list">';
  slabs.forEach(function (s, i) {
    const sq = slabQuoteFromBase(item, s.price);
    html +=
      '<div class="slab-row' +
      (i === active ? ' on' : '') +
      '"><span>' +
      esc(guestRangeLabel(s)) +
      '</span><span>' +
      priceHtml(sq) +
      '</span></div>';
  });
  html += '</div><p class="slab-note">More guests often means a lower per plate rate.</p></div>';
  return html;
}
function plateOf(item, guests) {
  const base = slabPrice(item.guestSlabs || item.slabs, guests);
  const pct = offerPct(item);
  const offer = pct ? Math.max(0, Math.round((base * (100 - pct)) / 100)) : base;
  return { base: base, offer: offer, pct: pct };
}
function priceHtml(quote) {
  if (!quote.pct) return inr(quote.offer) + ' <small style="font-weight:700">per plate</small>';
  return (
    '<s class="was">' +
    inr(quote.base) +
    '</s>' +
    inr(quote.offer) +
    ' <small style="font-weight:700">per plate</small><span class="off-pill">' +
    quote.pct +
    '% off</span>'
  );
}
function dietHtml(diet) {
  if (diet === 'veg') {
    return '<span class="diet-line"><span class="diet-mark veg" aria-hidden="true"><i></i></span>Veg</span>';
  }
  if (diet === 'non_veg') {
    return '<span class="diet-line"><span class="diet-mark non" aria-hidden="true"><i></i></span>Non-veg</span>';
  }
  return '<span class="diet-line"><span class="diet-mark veg" aria-hidden="true"><i></i></span><span class="diet-mark non" aria-hidden="true"><i></i></span>Veg &amp; Non-veg</span>';
}
function catererById(id) {
  return CATERERS.filter(function (c) {
    return c.id === id;
  })[0];
}
function servesArea(c, location) {
  const q = String(location || '').trim().toLowerCase();
  if (!q) return false;
  return (c.serves || []).some(function (a) {
    return a.toLowerCase().indexOf(q) >= 0 || q.indexOf(a.toLowerCase()) >= 0;
  });
}
function packagesFor(c, opts) {
  opts = opts || {};
  const diet = opts.diet || 'all';
  return (c.packages || []).filter(function (p) {
    if (state.functionType === 'wedding' && p.category !== 'wedding') return false;
    if (state.functionType === 'other' && p.category !== 'other') return false;
    if (diet === 'veg' && p.dietType !== 'veg') return false;
    if (diet === 'mixed' && p.dietType !== 'mixed') return false;
    if (opts.serve && opts.serve !== 'all' && ccPackageServeStyle(p) !== opts.serve) return false;
    if (opts.tier && opts.tier !== 'all' && String(p.level).toLowerCase() !== opts.tier) return false;
    return true;
  });
}
function foodsFor(c) {
  return (c.foods || []).filter(function (f) {
    if (state.menuDietFilter === 'veg' && f.dietType !== 'veg') return false;
    if (state.menuDietFilter === 'non_veg' && f.dietType !== 'non_veg') return false;
    return true;
  });
}
function clearFoodSelection() {
  state.selectedFoodIds = [];
}
function isFoodSelected(id) {
  return (state.selectedFoodIds || []).indexOf(id) >= 0;
}
function toggleFoodSelection(id) {
  if (!id) return;
  if (!state.selectedFoodIds) state.selectedFoodIds = [];
  const i = state.selectedFoodIds.indexOf(id);
  if (i >= 0) state.selectedFoodIds.splice(i, 1);
  else state.selectedFoodIds.push(id);
}
function selectedFoodItemsForCaterer(c) {
  if (!c) return [];
  return (state.selectedFoodIds || [])
    .map(function (id) {
      return (c.foods || []).filter(function (f) {
        return f.id === id;
      })[0];
    })
    .filter(Boolean);
}
function foodSelectionGrandTotal(c) {
  let sum = 0;
  selectedFoodItemsForCaterer(c).forEach(function (f) {
    sum += plateOf(f, state.guests).offer * state.guests;
  });
  return sum;
}
function renderFoodSelectBar() {
  const menuScr = el('ccMenu');
  const bar = el('ccFoodSelectBar');
  if (!bar || !menuScr) return;
  const c = catererById(state.catererId);
  const n = (state.selectedFoodIds || []).length;
  const show = state.menuTab === 'food' && menuScr.classList.contains('on') && n > 0 && !!c;
  bar.hidden = !show;
  menuScr.classList.toggle('has-food-bar', show);
  if (!show) return;
  el('ccFoodSelectSummary').textContent =
    n + (n === 1 ? ' dish' : ' dishes') + ' · Est. for ' + state.guests + ' guests';
  el('ccFoodSelectTotal').textContent = inr(foodSelectionGrandTotal(c));
  const reviewBtn = el('ccFoodReviewBtn');
  if (reviewBtn) {
    reviewBtn.textContent = 'Continue with ' + n + (n === 1 ? ' dish' : ' dishes');
  }
}
function normalizeMenuDietFilterForTab() {
  if (state.menuTab === 'food') {
    if (state.menuDietFilter === 'mixed') state.menuDietFilter = 'all';
  } else if (state.menuDietFilter === 'non_veg') {
    state.menuDietFilter = 'all';
  }
}
function menuDietChipOptions() {
  if (state.menuTab === 'food') {
    return [
      { id: 'all', label: 'All' },
      { id: 'veg', label: 'Veg only' },
      { id: 'non_veg', label: 'Non veg only' },
    ];
  }
  return [
    { id: 'all', label: 'All' },
    { id: 'veg', label: 'Veg only' },
    { id: 'mixed', label: 'Veg & Non-veg' },
  ];
}
function packagesForResults(c) {
  return (c.packages || []).filter(function (p) {
    if (state.functionType === 'wedding' && p.category !== 'wedding') return false;
    if (state.functionType === 'other' && p.category !== 'other') return false;
    return true;
  });
}
function plateOffersFromPackages(packs) {
  return packs
    .map(function (p) {
      return plateOf(p, state.guests).offer;
    })
    .filter(function (n) {
      return n > 0;
    });
}
function fitsBudgetRange(c) {
  const offers = plateOffersFromPackages(packagesForResults(c));
  if (!offers.length) return false;
  const plateLo = Math.min.apply(null, offers);
  const plateHi = Math.max.apply(null, offers);
  return plateLo <= state.budgetMax && plateHi >= state.budgetMin;
}
function rangeLabelForResults(c) {
  const offers = plateOffersFromPackages(packagesForResults(c));
  if (!offers.length) return 'Ask for a menu';
  const lo = Math.min.apply(null, offers);
  const hi = Math.max.apply(null, offers);
  if (lo === hi) return inr(lo) + ' per plate';
  return inr(lo) + ' – ' + inr(hi) + ' per plate';
}
function matchingCaterers() {
  const list = CATERERS.filter(function (c) {
    if (!servesArea(c, state.location)) return false;
    if (!packagesForResults(c).length) return false;
    if (!fitsBudgetRange(c)) return false;
    return true;
  });
  list.sort(function (a, b) {
    if (a.available === b.available) return 0;
    return a.available ? -1 : 1;
  });
  return list;
}

function readSearch() {
  state.location = (el('ccLocation').value || '').trim();
  state.date = el('ccDate').value || state.date;
  state.guests = Math.max(1, Math.round(+el('ccGuests').value || 0));
  syncBudgetFromInputs(false);
}
function todayIso() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}
function budgetHiLabel(n) {
  return inr(n);
}
function paintBudgetTrack() {
  const fill = el('ccBudgetFill');
  const minEl = el('ccBudgetMin');
  const maxEl = el('ccBudgetMax');
  if (!fill || !minEl || !maxEl) return;
  const cap = +maxEl.max || CC_BUDGET_CAP;
  const loPct = (Math.min(+minEl.value, +maxEl.value) / cap) * 100;
  const hiPct = (Math.max(+minEl.value, +maxEl.value) / cap) * 100;
  fill.style.left = loPct + '%';
  fill.style.width = hiPct - loPct + '%';
}
function paintBudgetRange() {
  const host = el('ccBudgetRangeVal');
  if (!host) return;
  host.textContent = inr(state.budgetMin) + ' to ' + budgetHiLabel(state.budgetMax) + ' per plate';
  paintBudgetTrack();
}
function syncBudgetFromInputs(fromUi) {
  const minEl = el('ccBudgetMin');
  const maxEl = el('ccBudgetMax');
  if (!minEl || !maxEl) return;
  let lo = Math.min(CC_BUDGET_CAP, Math.max(0, Math.round(+minEl.value || 0)));
  let hi = Math.min(CC_BUDGET_CAP, Math.max(0, Math.round(+maxEl.value || 0)));
  if (fromUi !== false) {
    if (lo > hi) {
      if (document.activeElement === minEl) hi = lo;
      else lo = hi;
    }
    minEl.value = lo;
    maxEl.value = hi;
    if (document.activeElement === minEl) {
      minEl.style.zIndex = 4;
      maxEl.style.zIndex = 3;
    } else if (document.activeElement === maxEl) {
      maxEl.style.zIndex = 4;
      minEl.style.zIndex = 3;
    }
  } else {
    lo = state.budgetMin;
    hi = state.budgetMax;
    if (lo > hi) hi = lo;
    minEl.value = lo;
    maxEl.value = hi;
    maxEl.style.zIndex = 4;
    minEl.style.zIndex = 3;
  }
  state.budgetMin = lo;
  state.budgetMax = hi;
  paintBudgetRange();
}
function isoFromParts(y, m, d) {
  return y + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
}
function syncDateEverywhere() {
  paintDate();
  const inp = el('ccDate');
  if (inp) {
    inp.value = state.date;
    inp.min = todayIso();
  }
  const when = el('ccWhenLabel');
  if (when) when.textContent = formatWhen(state.date) + ' · ' + state.guests + ' guests';
  if (el('ccResults') && el('ccResults').classList.contains('on')) renderResults();
  if (el('ccMenu') && el('ccMenu').classList.contains('on')) renderMenu();
  if (el('ccProfile') && el('ccProfile').classList.contains('on') && state.catererId) renderProfile();
}
function openCustomerCalendar() {
  const base = state.date || todayIso();
  const p = base.split('-');
  state.calViewYear = +p[0] || 2026;
  state.calViewMonth = +p[1] || 12;
  state.calPickDay = +p[2] || 15;
  const ov = el('ccCalOverlay');
  if (!ov) return;
  ov.hidden = false;
  ov.setAttribute('aria-hidden', 'false');
  ov.classList.add('on');
  renderCustomerCalendar();
}
function closeCustomerCalendar() {
  const ov = el('ccCalOverlay');
  if (!ov) return;
  ov.classList.remove('on');
  ov.hidden = true;
  ov.setAttribute('aria-hidden', 'true');
}
function renderCustomerCalendar() {
  const grid = el('ccCalGrid');
  const monthLab = el('ccCalMonth');
  if (!grid) return;
  const y = state.calViewYear;
  const m = state.calViewMonth;
  if (monthLab) monthLab.textContent = CC_MONTH_NAMES[m - 1] + ' ' + y;
  const minDay = todayIso();
  const first = new Date(y, m - 1, 1);
  const daysInMonth = new Date(y, m, 0).getDate();
  const start = first.getDay();
  let html =
    '<div class="h">S</div><div class="h">M</div><div class="h">T</div><div class="h">W</div><div class="h">T</div><div class="h">F</div><div class="h">S</div>';
  let i;
  for (i = 0; i < start; i++) html += '<div class="d off"></div>';
  for (i = 1; i <= daysInMonth; i++) {
    const iso = isoFromParts(y, m, i);
    const past = iso < minDay;
    const on = i === state.calPickDay;
    html +=
      '<button type="button" class="d' +
      (past ? ' past' : '') +
      (on ? ' on' : '') +
      '" data-day="' +
      i +
      '">' +
      i +
      '</button>';
  }
  grid.innerHTML = html;
  grid.querySelectorAll('.d[data-day]').forEach(function (btn) {
    btn.onclick = function () {
      state.calPickDay = +btn.getAttribute('data-day');
      renderCustomerCalendar();
    };
  });
}
function shiftCalMonth(delta) {
  let y = state.calViewYear;
  let m = state.calViewMonth + delta;
  if (m < 1) {
    m = 12;
    y -= 1;
  }
  if (m > 12) {
    m = 1;
    y += 1;
  }
  state.calViewYear = y;
  state.calViewMonth = m;
  const dim = new Date(y, m, 0).getDate();
  if (state.calPickDay > dim) state.calPickDay = dim;
  renderCustomerCalendar();
}
function applyCustomerCalendar() {
  const iso = isoFromParts(state.calViewYear, state.calViewMonth, state.calPickDay);
  if (iso < todayIso()) {
    toast('Choose today or a future date');
    return;
  }
  state.date = iso;
  closeCustomerCalendar();
  syncDateEverywhere();
}
function initSearchDate() {
  const inp = el('ccDate');
  if (!inp) return;
  const minDay = todayIso();
  inp.min = minDay;
  if (!inp.value || inp.value < minDay) {
    inp.value = state.date >= minDay ? state.date : minDay;
  }
  state.date = inp.value;
  syncDateEverywhere();
}
function renderFunctions() {
  const host = el('ccFunctions');
  if (!host) return;
  const opts = [
    { id: 'wedding', icon: '💍', title: 'Wedding & Related', sub: 'Wedding, Engagement, Reception' },
    { id: 'other', icon: '🎉', title: 'Other Functions', sub: 'Birthday, Noolukettu, Baptism, etc.' },
  ];
  host.innerHTML = opts
    .map(function (o) {
      const on = state.functionType === o.id;
      return (
        '<button type="button" class="fn-card' +
        (on ? ' on' : '') +
        '" data-fn="' +
        o.id +
        '"><span class="fn-ico">' +
        o.icon +
        '</span><span><b>' +
        esc(o.title) +
        '</b><small>' +
        esc(o.sub) +
        '</small></span><span class="fn-tick">✓</span></button>'
      );
    })
    .join('');
  host.querySelectorAll('[data-fn]').forEach(function (btn) {
    btn.onclick = function () {
      state.functionType = btn.getAttribute('data-fn');
      renderFunctions();
    };
  });
}
function paintDate() {
  const label = el('ccDateLabel');
  const value = (el('ccDate') && el('ccDate').value) || state.date;
  if (label) label.textContent = formatWhen(value);
}
function renderSearchBits() {
  initSearchDate();
  syncBudgetFromInputs(false);
  renderFunctions();
}

function renderResults() {
  el('ccResultsTitle').textContent = 'Catering Services in ' + (state.location || 'your area');
  el('ccResultsCtx').textContent =
    formatWhen(state.date) +
    ' · ' +
    state.guests +
    ' Guests · ' +
    inr(state.budgetMin) +
    ' – ' +
    inr(state.budgetMax) +
    ' per plate';
  const list = matchingCaterers();
  if (!list.length) {
    el('ccResultList').innerHTML =
      '<div class="empty">No caterers in this budget range. Widen the budget on the search page or try another area.</div>';
    return;
  }
  el('ccResultList').innerHTML = list
    .map(function (c) {
      return (
        '<button type="button" class="caterer' +
        (c.available ? '' : ' unavail') +
        '" data-id="' +
        esc(c.id) +
        '"><span class="thumb" style="background:' +
        c.color +
        '">' +
        c.emoji +
        '</span><span><b>' +
        esc(c.name) +
        '</b><div class="meta"><span class="stars">★ ' +
        c.rating +
        '</span> (' +
        c.reviews +
        ' reviews)<br>' +
        esc(c.area) +
        '</div><div class="price">' +
        esc(rangeLabelForResults(c)) +
        '</div><span class="badge ' +
        (c.available ? 'ok' : 'wait') +
        '">' +
        (c.available ? 'Available' : 'Unavailable on this date') +
        '</span></span></button>'
      );
    })
    .join('');
  el('ccResultList').querySelectorAll('[data-id]').forEach(function (btn) {
    btn.onclick = function () {
      openProfile(btn.getAttribute('data-id'));
    };
  });
}

function openProfile(id) {
  if (state.catererId !== id) clearFoodSelection();
  state.catererId = id;
  state.profileTab = 'overview';
  renderProfile();
  show('ccProfile');
}
function renderProfile() {
  const c = catererById(state.catererId);
  if (!c) return;
  el('ccProfileTitle').textContent = c.name;
  const save = el('ccSave');
  save.textContent = state.saved[c.id] ? '♥' : '♡';
  save.classList.toggle('on', !!state.saved[c.id]);
  let body = '<div class="hero" style="background:' + c.color + '">' + c.emoji + '</div>';
  body +=
    '<div class="rate-line"><span class="stars">★ ' +
    c.rating +
    '</span> (' +
    c.reviews +
    ' reviews) <span class="serves">Serves in your area</span></div>';
  body += '<p class="ctx" style="margin-top:0">' + esc(c.area) + '</p>';
  body +=
    '<div class="tabs"><button type="button" data-pt="overview"' +
    (state.profileTab === 'overview' ? ' class="on"' : '') +
    '>Overview</button><button type="button" data-pt="photos"' +
    (state.profileTab === 'photos' ? ' class="on"' : '') +
    '>Photos</button><button type="button" data-pt="reviews"' +
    (state.profileTab === 'reviews' ? ' class="on"' : '') +
    '>Reviews</button></div>';
  if (state.profileTab === 'photos') {
    body +=
      '<div class="photo-grid">' +
      c.photos
        .map(function (p, i) {
          return '<div style="background:' + c.color + '">' + p + '</div>';
        })
        .join('') +
      '</div>';
  } else if (state.profileTab === 'reviews') {
    body += c.reviewList
      .map(function (r) {
        return '<div class="review"><b>' + esc(r.name) + ' · ★ ' + r.stars + '</b><p>' + esc(r.text) + '</p></div>';
      })
      .join('');
  } else {
    body += '<div class="about"><h3>About Us</h3>' + esc(c.about) + '</div>';
    body +=
      '<div class="about" style="padding-top:0"><h3>Our Specialities</h3></div><div class="spec">' +
      c.specialities
        .map(function (s) {
          return '<span>' + esc(s) + '</span>';
        })
        .join('') +
      '</div>';
    if (!c.available) {
      body += '<div class="sent">This caterer is unavailable on ' + esc(formatWhen(state.date)) + '. You can still view the menu.</div>';
    }
  }
  el('ccProfileBody').innerHTML = body;
  el('ccProfileBody').querySelectorAll('[data-pt]').forEach(function (btn) {
    btn.onclick = function () {
      state.profileTab = btn.getAttribute('data-pt');
      renderProfile();
    };
  });
}

function renderMenuDietChips() {
  const host = el('ccMenuDietChips');
  const label = el('ccMenuDietLabel');
  if (!host) return;
  normalizeMenuDietFilterForTab();
  const opts = menuDietChipOptions();
  host.innerHTML = opts
    .map(function (o) {
      return (
        '<button type="button" class="chip' +
        (state.menuDietFilter === o.id ? ' on' : '') +
        '" data-menu-diet="' +
        o.id +
        '">' +
        esc(o.label) +
        '</button>'
      );
    })
    .join('');
  host.querySelectorAll('[data-menu-diet]').forEach(function (btn) {
    btn.onclick = function () {
      state.menuDietFilter = btn.getAttribute('data-menu-diet');
      renderMenu();
    };
  });
  if (label) label.style.display = 'block';
}
function openMenu() {
  state.menuTab = state.menuTab || 'packages';
  if (state.menuTab !== 'food' && state.menuTab !== 'packages') state.menuTab = 'packages';
  state.tier = 'all';
  state.serveFilter = 'all';
  state.menuDietFilter = 'all';
  state.openGroup = '';
  renderMenu();
  show('ccMenu');
}
function renderMenu() {
  const c = catererById(state.catererId);
  if (!c) return;
  el('ccMenuTitle').textContent = c.name;
  const foodTotal = (c.foods || []).length;
  const selN = (state.selectedFoodIds || []).length;
  let foodTabLabel =
    foodTotal > 0 ? 'Individual Food Items (' + foodTotal + ')' : 'Individual Food Items';
  if (selN > 0) foodTabLabel = 'Individual Food Items · ' + selN + ' selected';
  el('ccTabPackages').classList.toggle('on', state.menuTab === 'packages');
  el('ccTabFood').classList.toggle('on', state.menuTab === 'food');
  el('ccTabFood').textContent = foodTabLabel;
  const foodHint = el('ccMenuFoodHint');
  const pkgHint = el('ccMenuPackageHint');
  if (foodHint) foodHint.hidden = state.menuTab !== 'food';
  if (pkgHint) pkgHint.hidden = state.menuTab !== 'packages';
  if (foodHint && state.menuTab === 'food') {
    foodHint.innerHTML =
      'Dishes follow the caterer library (drinks, rice, curries, and so on). Tick <b>+</b> to add <b>more than one</b>. A full menu is one <b>Package</b>. Prices are <b>per plate × ' +
      state.guests +
      ' guests</b> (estimate only).';
  }
  if (pkgHint && state.menuTab === 'packages') {
    pkgHint.innerHTML =
      'Choose <b>one</b> package (table service, buffet, or both). Packages are not combined. Extra dishes go under <b>Individual Food Items</b>.';
  }
  el('ccWhenLabel').textContent = formatWhen(state.date) + ' · ' + state.guests + ' guests';
  const fnLabel = state.functionType === 'other' ? 'Other Functions' : state.functionType === 'wedding' ? 'Wedding & Related' : 'all functions';
  renderMenuDietChips();
  const serveBlock = el('ccServeFilterBlock');
  if (serveBlock) serveBlock.hidden = state.menuTab !== 'packages';
  if (state.menuTab === 'food') {
    el('ccMenuChips').innerHTML = '';
    const foods = foodsFor(c);
    const dietNote =
      state.menuDietFilter === 'veg'
        ? ' · Veg only'
        : state.menuDietFilter === 'non_veg'
          ? ' · Non veg only'
          : '';
    el('ccMenuCount').textContent = foods.length + ' dishes' + dietNote;
    el('ccMenuList').innerHTML = foods.length
      ? ccCustomerFoodGroups().map(function (g) {
          const rows = foods.filter(function (f) {
            return ccFoodModuleId(f) === g.id;
          });
          if (!rows.length) return '';
          return (
            '<p class="food-group-h">' +
            esc(g.label) +
            '</p>' +
            rows
              .map(function (f) {
                const q = plateOf(f, state.guests);
                const picked = isFoodSelected(f.id);
                return (
                  '<div class="pkg food-row' +
                  (picked ? ' on' : '') +
                  '"><button type="button" class="food-check' +
                  (picked ? ' on' : '') +
                  '" data-toggle-food="' +
                  esc(f.id) +
                  '" aria-pressed="' +
                  picked +
                  '" aria-label="' +
                  (picked ? 'Remove' : 'Select') +
                  ' ' +
                  esc(f.name) +
                  '">' +
                  (picked ? '✓' : '+') +
                  '</button><button type="button" class="food-body" data-food="' +
                  esc(f.id) +
                  '"><span class="thumb" style="background:' +
                  c.color +
                  '">' +
                  f.emoji +
                  '</span><span><b>' +
                  esc(f.name) +
                  '</b>' +
                  dietHtml(f.dietType) +
                  '<p class="meta" style="margin-top:4px">' +
                  esc(f.description || '') +
                  '</p><div class="price">' +
                  priceHtml(q) +
                  '</div></span></button></div>'
                );
              })
              .join('')
          );
        }).join('')
      : '<div class="empty">No individual dishes match this diet filter. Try <b>All</b> or check the Packages tab.</div>';
  } else {
    el('ccMenuChips').innerHTML = CC_SERVE_FILTERS.map(function (s) {
      return (
        '<button type="button" class="serve-opt' +
        (state.serveFilter === s.id ? ' on' : '') +
        '" data-serve="' +
        esc(s.id) +
        '" aria-pressed="' +
        (state.serveFilter === s.id) +
        '"><b>' +
        esc(s.label) +
        '</b><small>' +
        esc(s.hint || '') +
        '</small></button>'
      );
    }).join('');
    const packs = packagesFor(c, { serve: state.serveFilter, diet: state.menuDietFilter });
    const dietNote =
      state.menuDietFilter === 'veg'
        ? ' · Veg only'
        : state.menuDietFilter === 'mixed'
          ? ' · Veg & Non-veg'
          : '';
    const styleNote = state.serveFilter === 'all' ? '' : ' · ' + ccServeFilterLabel(state.serveFilter);
    el('ccMenuCount').textContent = 'Showing ' + packs.length + ' packages for ' + fnLabel + styleNote + dietNote;
    el('ccMenuList').innerHTML = packs.length
      ? packs
          .map(function (p) {
            const q = plateOf(p, state.guests);
            return (
              '<button type="button" class="pkg" data-pkg="' +
              esc(p.id) +
              '"><span class="thumb" style="background:' +
              c.color +
              '">🍛</span><span><span class="pkg-top"><span class="lv ' +
              esc(p.level.toLowerCase()) +
              '">' +
              esc(p.level) +
              '</span><span class="cat-chip">' +
              esc(ccServeStyleLabel(ccPackageServeStyle(p)) || 'Service') +
              '</span><span class="cat-chip">' +
              (p.category === 'wedding' ? 'Wedding & Related' : 'Other Functions') +
              '</span>' +
              (p.popular ? '<span class="pop">Most Popular</span>' : '') +
              '</span><b>' +
              esc(p.name) +
              '</b>' +
              dietHtml(p.dietType) +
              '<div class="price">' +
              priceHtml(q) +
              '</div></span></button>'
            );
          })
          .join('')
      : '<div class="empty">No packages for this filter.</div>';
  }
  renderFoodSelectBar();
  el('ccMenuChips').querySelectorAll('[data-serve]').forEach(function (btn) {
    btn.onclick = function () {
      state.serveFilter = btn.getAttribute('data-serve') || 'all';
      renderMenu();
    };
  });
  el('ccMenuList').querySelectorAll('[data-pkg]').forEach(function (btn) {
    btn.onclick = function () {
      openDetail('package', btn.getAttribute('data-pkg'));
    };
  });
  el('ccMenuList').querySelectorAll('[data-toggle-food]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.preventDefault();
      e.stopPropagation();
      toggleFoodSelection(btn.getAttribute('data-toggle-food'));
      renderMenu();
    };
  });
  el('ccMenuList').querySelectorAll('[data-food]').forEach(function (btn) {
    btn.onclick = function () {
      openDetail('food', btn.getAttribute('data-food'));
    };
  });
}

function findSelection(kind, id) {
  const c = catererById(state.catererId);
  if (!c) return null;
  const list = kind === 'food' ? c.foods : c.packages;
  const item = (list || []).filter(function (x) {
    return x.id === id;
  })[0];
  return item ? { caterer: c, kind: kind, item: item } : null;
}
function openDetail(kind, id) {
  state.selection = findSelection(kind, id);
  state.openGroup = '';
  state.detailTab = 'menu';
  if (!state.selection) return;
  renderDetail();
  show('ccDetail');
}
function renderDetail() {
  const sel = state.selection;
  if (!sel) return;
  const item = sel.item;
  const q = plateOf(item, state.guests);
  const total = q.offer * state.guests;
  el('ccDetailTitle').textContent = item.name;
  let html = '<div class="hero" style="background:' + sel.caterer.color + '">' + (item.emoji || '🍛') + '</div>';
  html += '<div class="pad"><span class="pkg-top"><span class="lv ' + esc(String(item.level || 'basic').toLowerCase()) + '">' + esc(item.level || 'Dish') + '</span>';
  if (item.category) {
    html += '<span class="cat-chip">' + esc(ccServeStyleLabel(ccPackageServeStyle(item)) || 'Service') + '</span>';
    html += '<span class="cat-chip">' + (item.category === 'wedding' ? 'Wedding & Related' : 'Other Functions') + '</span>';
  }
  html += '</span><h2 style="margin:8px 0 0;font-size:20px;color:#14532D">' + esc(item.name) + '</h2>';
  html += dietHtml(item.dietType);
  html += '<p class="meta">' + esc(item.blurb || item.description || '') + '</p></div>';
  html +=
    '<div class="detail-price"><div><span>Price for ' +
    state.guests +
    ' guests</span><b>' +
    priceHtml(q) +
    '</b></div><div style="text-align:right"><span>Estimated total</span><b>' +
    inr(total) +
    '</b></div></div>';
  const menuGroups = sel.kind === 'package' ? ccMenuGroupsForPackage(item) : item.groups || [];
  const hasMenuGroups = !!(menuGroups && menuGroups.length);
  html +=
    '<div class="tabs detail-tabs"><button type="button" data-dtab="menu"' +
    (state.detailTab === 'menu' ? ' class="on"' : '') +
    '>' +
    (hasMenuGroups ? 'Menu inclusions' : 'About') +
    '</button><button type="button" data-dtab="pricing"' +
    (state.detailTab === 'pricing' ? ' class="on"' : '') +
    '>Per plate pricing</button></div>';
  html += '<div class="detail-tab-body">';
  if (state.detailTab === 'pricing') {
    html += renderDetailSlabSection(item, state.guests);
  } else if (hasMenuGroups) {
    html += '<p class="menu-inc-h">What&apos;s included <span class="inc-tag">Included in per plate price</span></p>';
    html += menuGroups
      .map(function (g) {
        const open = state.openGroup === g.name;
        return (
          '<button type="button" class="inc" data-g="' +
          esc(g.name) +
          '"><b>' +
          esc(g.name) +
          '</b><small> (' +
          g.items.length +
          ')</small>' +
          (open ? '<ul>' + g.items.map(function (d) { return '<li>' + esc(d) + '</li>'; }).join('') + '</ul>' : '') +
          '</button>'
        );
      })
      .join('');
  } else if (sel.kind === 'food') {
    html +=
      '<div class="detail-about pad" style="padding-top:12px"><p class="meta" style="margin:0;line-height:1.5">' +
      esc(item.description || item.blurb || 'Single dish pricing — see the Per plate pricing tab for your guest count.') +
      '</p></div>';
  } else {
    html += '<p class="empty" style="margin-top:16px">No menu breakdown for this item.</p>';
  }
  html += '</div>';
  if (sel.kind === 'food') {
    const n = (state.selectedFoodIds || []).length;
    html +=
      '<p class="detail-hint">' +
      (isFoodSelected(item.id)
        ? 'This dish is in your selection. Tap <b>Added</b> to remove, or continue with all selected dishes below.'
        : n
          ? 'Tap <b>Add to selection</b>, or review your ' + n + ' selected dish' + (n === 1 ? '' : 'es') + ' from the menu bar.'
          : 'Tap <b>Add to selection</b>, or tick <b>+</b> on the list. Prices use your guest count from search.') +
      '</p>';
  }
  el('ccDetailBody').innerHTML = html;
  el('ccDetailBody').querySelectorAll('[data-dtab]').forEach(function (btn) {
    btn.onclick = function () {
      state.detailTab = btn.getAttribute('data-dtab') || 'menu';
      renderDetail();
    };
  });
  el('ccDetailBody').querySelectorAll('[data-g]').forEach(function (btn) {
    btn.onclick = function () {
      const name = btn.getAttribute('data-g');
      state.openGroup = state.openGroup === name ? '' : name;
      renderDetail();
    };
  });
  updateDetailActions();
}
function updateDetailActions() {
  const sel = state.selection;
  const init = el('ccInitiate');
  const cust = el('ccCustomise');
  if (!init || !cust || !sel) return;
  if (sel.kind === 'food') {
    const on = isFoodSelected(sel.item.id);
    const n = (state.selectedFoodIds || []).length;
    init.textContent = on ? 'Added · Tap to remove' : 'Add to selection';
    init.classList.toggle('on', on);
    cust.textContent = n ? 'Continue with ' + n + (n === 1 ? ' dish' : ' dishes') : '';
    cust.style.display = n ? '' : 'none';
  } else {
    init.textContent = 'Initiate Interest';
    init.classList.remove('on');
    cust.textContent = 'Customise Requirement';
    cust.style.display = '';
  }
}

function openFoodMultiInterest(fromCustomise) {
  const c = catererById(state.catererId);
  if (!c) return;
  const items = selectedFoodItemsForCaterer(c);
  if (!items.length) {
    toast('Select at least one dish');
    return;
  }
  if (!c.available) {
    toast('This caterer is unavailable on ' + formatWhen(state.date));
    return;
  }
  state.selection = { caterer: c, kind: 'food_multi', items: items };
  state.showCustomRequirements = true;
  if (!fromCustomise) state.note = '';
  state.sent = false;
  renderInterest();
  show('ccInterest');
  if (fromCustomise) {
    const note = el('ccNote');
    if (note) note.focus();
  }
}

function openInterest(fromCustomise) {
  if (!state.selection) return;
  const c = state.selection.caterer;
  if (!c.available) {
    toast('This caterer is unavailable on ' + formatWhen(state.date));
    return;
  }
  state.showCustomRequirements = !!fromCustomise;
  if (!fromCustomise) state.note = '';
  state.sent = false;
  renderInterest();
  show('ccInterest');
  if (fromCustomise) {
    const note = el('ccNote');
    if (note) note.focus();
  }
}
function renderInterest() {
  const sel = state.selection;
  if (!sel) return;
  let html = '';
  if (sel.kind === 'food_multi') {
    const items = sel.items || [];
    html +=
      '<p class="ctx" style="margin-top:8px">Individual dishes · ' +
      items.length +
      ' selected for ' +
      state.guests +
      ' guests</p><div class="interest-lines">';
    let grand = 0;
    items.forEach(function (item) {
      const q = plateOf(item, state.guests);
      const line = q.offer * state.guests;
      grand += line;
      html +=
        '<div class="interest-line"><span><b>' +
        esc(item.emoji || '🍽') +
        ' ' +
        esc(item.name) +
        '</b><br>' +
        priceHtml(q) +
        '</span><span>Line total<br><b style="color:#15803D">' +
        inr(line) +
        '</b></span></div>';
    });
    html +=
      '</div><div class="kv"><div><span>Event Date</span><b>' +
      esc(formatWhen(state.date)) +
      '</b></div><div><span>Number of Guests</span><b>' +
      state.guests +
      '</b></div><div><span>Event Location</span><b>' +
      esc(state.location) +
      '</b></div><div><span>Estimated total</span><b>' +
      inr(grand) +
      '</b></div></div>';
    html +=
      '<p class="estimate-note">This total adds each selected dish at its per-plate rate for ' +
      state.guests +
      ' guests. The caterer confirms the final quote — sending interest does not book the event.</p>';
    html +=
      '<p class="pad" style="font-weight:800;color:#14532D;margin-bottom:8px">Additional Requirements (Optional)</p>' +
      '<textarea class="note" id="ccNote" maxlength="500" placeholder="Eg. service time, quantity tweaks, combo with a package, etc.">' +
      esc(state.note) +
      '</textarea>';
  } else {
  const item = sel.item;
  const q = plateOf(item, state.guests);
  const cat = item.category === 'other' ? 'Other Functions' : item.category === 'wedding' ? 'Wedding & Related' : 'Individual dish';
  html =
    '<div class="sum-card"><span class="thumb" style="background:' +
    sel.caterer.color +
    '">' +
    (item.emoji || '🍛') +
    '</span><span><b>' +
    esc(item.name) +
    '</b><div class="meta">' +
    esc(item.level || 'Dish') +
    ' · ' +
    cat +
    '</div><div class="price">' +
    priceHtml(q) +
    '</div></span></div>' +
    '<div class="kv"><div><span>Event Date</span><b>' +
    esc(formatWhen(state.date)) +
    '</b></div><div><span>Number of Guests</span><b>' +
    state.guests +
    '</b></div><div><span>Event Location</span><b>' +
    esc(state.location) +
    '</b></div><div><span>Estimated total</span><b>' +
    inr(q.offer * state.guests) +
    '</b></div></div>';
  if (state.showCustomRequirements) {
    html +=
      '<p class="pad" style="font-weight:800;color:#14532D;margin-bottom:8px">Additional Requirements (Optional)</p>' +
      '<textarea class="note" id="ccNote" maxlength="500" placeholder="Eg. Live counter, special menu, service time, etc.">' +
      esc(state.note) +
      '</textarea>';
  }
  }
  if (state.sent) {
    html +=
      '<div class="sent">Interest sent to ' +
      esc(sel.caterer.name) +
      '. They will reply to discuss the menu. This does not confirm the booking.</div>';
  }
  el('ccInterestBody').innerHTML = html;
  const note = el('ccNote');
  if (note) {
    note.oninput = function () {
      state.note = note.value;
    };
  }
  const send = el('ccSend');
  if (send) {
    send.disabled = state.sent;
    send.textContent = state.sent ? 'Interest sent' : 'Send Interest';
  }
}

function bootCustomer() {
  renderSearchBits();
  const minEl = el('ccBudgetMin');
  const maxEl = el('ccBudgetMax');
  if (minEl) {
    minEl.oninput = function () {
      syncBudgetFromInputs(true);
    };
    minEl.onchange = minEl.oninput;
  }
  if (maxEl) {
    maxEl.oninput = function () {
      syncBudgetFromInputs(true);
    };
    maxEl.onchange = maxEl.oninput;
  }
  const dateBox = el('ccDateBox');
  const dateOpen = el('ccDateOpen');
  if (dateBox) {
    dateBox.onclick = function (e) {
      if (e.target === dateOpen || (dateOpen && dateOpen.contains(e.target))) return;
      openCustomerCalendar();
    };
  }
  if (dateOpen) {
    dateOpen.onclick = function (e) {
      e.stopPropagation();
      openCustomerCalendar();
    };
  }
  const calCancel = el('ccCalCancel');
  const calDone = el('ccCalDone');
  const calPrev = el('ccCalPrev');
  const calNext = el('ccCalNext');
  const calOverlay = el('ccCalOverlay');
  if (calCancel) calCancel.onclick = closeCustomerCalendar;
  if (calDone) calDone.onclick = applyCustomerCalendar;
  if (calPrev) calPrev.onclick = function () {
    shiftCalMonth(-1);
  };
  if (calNext) calNext.onclick = function () {
    shiftCalMonth(1);
  };
  if (calOverlay) {
    calOverlay.onclick = function (e) {
      if (e.target === calOverlay) closeCustomerCalendar();
    };
    const sheet = calOverlay.querySelector('.cal-sheet');
    if (sheet) {
      sheet.onclick = function (e) {
        e.stopPropagation();
      };
    }
  }
  const dateConfirm = el('ccDateConfirm');
  if (dateConfirm) {
    dateConfirm.onclick = function () {
      openCustomerCalendar();
    };
  }
  el('ccSearchBtn').onclick = function () {
    readSearch();
    if (!state.location) {
      toast('Enter a location');
      return;
    }
    if (!state.date) {
      toast('Choose the event date');
      return;
    }
    if (!state.guests) {
      toast('Enter the number of guests');
      return;
    }
    state.menuDietFilter = 'all';
    clearFoodSelection();
    renderResults();
    show('ccResults');
  };
  el('ccResultsBack').onclick = function () {
    show('ccSearch');
  };
  el('ccProfileBack').onclick = function () {
    show('ccResults');
  };
  el('ccSave').onclick = function () {
    if (!state.catererId) return;
    state.saved[state.catererId] = !state.saved[state.catererId];
    renderProfile();
  };
  el('ccShowMenu').onclick = function () {
    openMenu();
  };
  el('ccMenuBack').onclick = function () {
    show('ccProfile');
  };
  el('ccTabPackages').onclick = function () {
    state.menuTab = 'packages';
    normalizeMenuDietFilterForTab();
    renderMenu();
  };
  el('ccTabFood').onclick = function () {
    state.menuTab = 'food';
    normalizeMenuDietFilterForTab();
    renderMenu();
  };
  el('ccChangeDate').onclick = function (e) {
    e.stopPropagation();
    openCustomerCalendar();
  };
  el('ccDetailBack').onclick = function () {
    renderMenu();
    show('ccMenu');
  };
  el('ccCustomise').onclick = function () {
    const sel = state.selection;
    if (sel && sel.kind === 'food') {
      openFoodMultiInterest(true);
      return;
    }
    openInterest(true);
  };
  el('ccInitiate').onclick = function () {
    const sel = state.selection;
    if (sel && sel.kind === 'food') {
      toggleFoodSelection(sel.item.id);
      updateDetailActions();
      return;
    }
    openInterest(false);
  };
  el('ccInterestBack').onclick = function () {
    if (state.selection && state.selection.kind === 'food_multi') {
      renderMenu();
      show('ccMenu');
    } else show('ccDetail');
  };
  const foodReviewBtn = el('ccFoodReviewBtn');
  if (foodReviewBtn) {
    foodReviewBtn.onclick = function () {
      openFoodMultiInterest(false);
    };
  }
  const foodClearBtn = el('ccFoodClearBtn');
  if (foodClearBtn) {
    foodClearBtn.onclick = function () {
      clearFoodSelection();
      renderMenu();
      toast('Selection cleared');
    };
  }
  el('ccSend').onclick = function () {
    if (!state.selection || state.sent) return;
    if (!state.selection.caterer.available) {
      toast('This caterer is unavailable on this date');
      return;
    }
    const note = el('ccNote');
    state.note = note ? note.value : state.showCustomRequirements ? state.note : '';
    state.sent = true;
    const wasMulti = state.selection.kind === 'food_multi';
    renderInterest();
    if (wasMulti) clearFoodSelection();
    toast(wasMulti ? 'Interest sent · selection cleared' : 'Interest sent');
  };
  show('ccSearch');
}

function startCustomer() {
  if (startCustomer.done || !document.getElementById('ccSearchBtn')) return;
  startCustomer.done = true;
  bootCustomer();
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', startCustomer);
startCustomer();
