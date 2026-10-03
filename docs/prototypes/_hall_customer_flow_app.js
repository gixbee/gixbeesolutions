const CUSTOMER_BUILD = '2026-10-03-hall-customer-flow-v17-no-discount-labels';
const DEMO_FILE = 'GIXBEE-HALL-CUSTOMER-WORKING.html';
const OWNER_PKG_KEY = 'GIXBEE_HALL_PACKAGE';
/* IMG_DATA_START — replaced at build with base64 embedded photos */
const IMG_DATA = {};
/* IMG_DATA_END */
function assetUrl(file) {
  if (file && IMG_DATA[file]) return IMG_DATA[file];
  if (IMG_DATA['hall-detail.jpg']) return IMG_DATA['hall-detail.jpg'];
  return '';
}
const MOCK_RESULT_IDS = ['royal', 'grand', 'garden', 'grace'];

function dummyKoinoniaSlots() {
  return [
    {
      id: 'morning',
      label: 'Morning',
      hallFrom: '10:00',
      hallTo: '15:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: 55000,
      priceAc: 75000,
      listPriceNoAc: 55000,
      listPriceAc: 75000,
      discountNoAc: 'no',
      discountAc: 'no',
      discountNoAcPct: 0,
      discountAcPct: 0,
    },
    {
      id: 'evening',
      label: 'Evening',
      hallFrom: '17:00',
      hallTo: '23:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: 55000,
      priceAc: 75000,
      listPriceNoAc: 55000,
      listPriceAc: 75000,
      discountNoAc: 'no',
      discountAc: 'no',
      discountNoAcPct: 0,
      discountAcPct: 0,
    },
    {
      id: 'fullday',
      label: 'Full Day',
      hallFrom: '09:00',
      hallTo: '23:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: 90000,
      priceAc: 120000,
      listPriceNoAc: 90000,
      listPriceAc: 120000,
      discountNoAc: 'no',
      discountAc: 'no',
      discountNoAcPct: 0,
      discountAcPct: 0,
    },
  ];
}

function dummyStandardSlots(priceNo, priceAc) {
  return [
    {
      id: 'morning',
      label: 'Morning',
      hallFrom: '10:00',
      hallTo: '15:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: priceNo,
      priceAc: priceAc,
    },
    {
      id: 'evening',
      label: 'Evening',
      hallFrom: '17:00',
      hallTo: '23:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: priceNo,
      priceAc: priceAc,
    },
    {
      id: 'fullday',
      label: 'Full Day',
      hallFrom: '09:00',
      hallTo: '23:00',
      enabled: true,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: priceNo + 15000,
      priceAc: priceAc + 12000,
    },
  ];
}

function dummyOutdoorSlots(price) {
  return [
    {
      id: 'morning',
      label: 'Morning',
      hallFrom: '10:00',
      hallTo: '15:00',
      enabled: true,
      offerNoAc: true,
      offerAc: false,
      priceNoAc: price,
      priceAc: price,
    },
    {
      id: 'evening',
      label: 'Evening',
      hallFrom: '17:00',
      hallTo: '23:00',
      enabled: true,
      offerNoAc: true,
      offerAc: false,
      priceNoAc: price,
      priceAc: price,
    },
  ];
}

const DUMMY_PAYMENT = {
  advanceType: 'fixed',
  advanceFixed: 20000,
  fullDueDays: 3,
};
const DUMMY_CANCEL = [
  { days: '30+ days before event', pct: 10 },
  { days: '15–29 days', pct: 25 },
  { days: '7–14 days', pct: 50 },
  { days: 'Under 7 days', pct: 100 },
];
const DUMMY_RESCHED = [
  { days: 'Reschedule once, 15+ days before', pct: 0 },
  { days: 'Within 14 days', pct: 15 },
];
const DUMMY_EXTRA = { extraAc: 7000, extraNoAc: 5000 };

const HALLS = [
  {
    id: 'royal',
    businessName: 'Vijaya Convention Center',
    useHallName: true,
    hallName: 'Koinonia',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.8,
    reviews: 120,
    seat: 700,
    dine: 550,
    park: 50,
    bike: 100,
    rooms: 2,
    facilities: ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Lift', 'Security in Parking Area'],
    tags: ['Baptism', 'Wedding', 'Reception'],
    priceFrom: 75000,
    listFrom: 75000,
    priceAc: 75000,
    cardImage: 'hall-card-koinonia.jpg',
    heroImage: 'hall-detail.jpg',
    imgCount: '1/12',
    verified: true,
    slotOffers: dummyKoinoniaSlots(),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    rescheduleRules: DUMMY_RESCHED,
    extraPrices: DUMMY_EXTRA,
    services: {
      inHouseCatering: true,
      outsideCatering: true,
      hallDecoration: false,
      outsideDecorators: true,
    },
  },
  {
    id: 'grand',
    businessName: 'Vijaya Convention Center',
    useHallName: true,
    hallName: 'Grand',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.7,
    reviews: 86,
    seat: 500,
    dine: 400,
    park: 40,
    bike: 60,
    rooms: 2,
    facilities: ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Lift'],
    priceFrom: 55000,
    listFrom: 55000,
    priceAc: 65000,
    cardImage: 'hall-card-grand.jpg',
    heroImage: 'hall-detail.jpg',
    imgCount: '1/10',
    slotOffers: dummyStandardSlots(55000, 65000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: DUMMY_EXTRA,
    services: { inHouseCatering: true, outsideCatering: true, hallDecoration: true, outsideDecorators: true },
  },
  {
    id: 'garden',
    businessName: 'Vijaya Convention Center',
    useHallName: true,
    hallName: 'Garden',
    area: 'Kottayam, Kerala',
    spaceType: 'outdoor',
    rating: 4.5,
    reviews: 72,
    seat: 1000,
    dine: 700,
    park: 120,
    bike: 200,
    rooms: 0,
    facilities: ['Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Generator / Power Backup', 'Security in Parking Area'],
    priceFrom: 60000,
    listFrom: 60000,
    priceAc: 60000,
    cardImage: 'hall-card-garden.jpg',
    heroImage: 'hall-card-garden.jpg',
    imgCount: '1/8',
    slotOffers: dummyOutdoorSlots(60000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraNoAc: 5000 },
    services: { inHouseCatering: false, outsideCatering: true, hallDecoration: false, outsideDecorators: true },
  },
  {
    id: 'grace',
    businessName: 'Grace Auditorium',
    useHallName: true,
    hallName: 'Main',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.6,
    reviews: 98,
    seat: 500,
    dine: 400,
    park: 30,
    bike: 40,
    rooms: 1,
    facilities: ['AC', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Generator / Power Backup'],
    tags: ['Baptism', 'Birthday'],
    priceFrom: 50000,
    listFrom: 50000,
    priceAc: 60000,
    cardImage: 'hall-card-grace.jpg',
    heroImage: 'hall-detail.jpg',
    imgCount: '1/9',
    slotOffers: dummyStandardSlots(50000, 60000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraAc: 6000, extraNoAc: 4500 },
    services: {
      inHouseCatering: true,
      outsideCatering: true,
      hallDecoration: true,
      outsideDecorators: true,
    },
  },
  {
    id: 'marina',
    businessName: 'Marina Banquet Hall',
    useHallName: false,
    hallName: '',
    area: 'Kochi, Kerala',
    spaceType: 'indoor',
    rating: 4.7,
    reviews: 210,
    seat: 600,
    dine: 480,
    park: 40,
    bike: 60,
    rooms: 2,
    facilities: ['AC', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Lift', 'Generator / Power Backup'],
    priceFrom: 68000,
    listFrom: 68000,
    cardImage: 'hall-card-grace.jpg',
    heroImage: 'hall-detail.jpg',
    slotOffers: dummyStandardSlots(68000, 92000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraAc: 8500, extraNoAc: 6000 },
    services: { inHouseCatering: true, outsideCatering: false, hallDecoration: true, outsideDecorators: false },
  },
];

const state = {
  loc: 'Kottayam, Kerala',
  event: 'Baptism',
  date: '2026-12-25',
  guests: '200',
  ac: 'any',
  venueType: 'any',
  priceMax: 200000,
  hallId: 'royal',
  slot: 'morning',
  acChoice: 'ac',
};

function el(id) {
  return document.getElementById(id);
}
function show(id) {
  if (id !== 'slots') closeCalendar();
  if (id !== 'detail') closeFacilitiesAll();
  document.querySelectorAll('.scr').forEach((s) => s.classList.toggle('on', s.id === id));
}
function toast(m) {
  const t = el('toast');
  t.textContent = m;
  t.style.display = 'block';
  setTimeout(() => (t.style.display = 'none'), 2400);
}
function displayTitle(h) {
  const biz = businessLabel(h);
  const hn = String(h.hallName || '').trim();
  if (hn && h.useHallName !== false) return biz + ' ' + hn + ' Hall';
  return biz;
}
function formatDateLong(iso) {
  try {
    return new Date(iso + 'T12:00:00').toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      weekday: 'short',
    });
  } catch (_e) {
    return formatDate(iso);
  }
}
function hallIsOutdoor(h) {
  return h && h.spaceType === 'outdoor';
}
function hallHasAc(h) {
  const fac = h.facilities || [];
  return fac.indexOf('AC') >= 0;
}
function festivePromoActive() {
  return state.date === '2026-12-25';
}
function slotWithPromo(sl) {
  if (!festivePromoActive() || sl.id !== 'morning') return sl;
  const o = Object.assign({}, sl);
  if (o.offerAc) {
    o.listPriceAc = o.listPriceAc != null ? o.listPriceAc : o.priceAc;
    o.priceAc = Math.round(o.listPriceAc * 0.7);
    o.discountAc = 'yes';
    o.discountAcPct = 30;
  }
  if (o.offerNoAc) {
    o.listPriceNoAc = o.listPriceNoAc != null ? o.listPriceNoAc : o.priceNoAc;
    o.priceNoAc = Math.round(o.listPriceNoAc * 0.7);
    o.discountNoAc = 'yes';
    o.discountNoAcPct = 30;
  }
  return o;
}
function hallMetaPills(h) {
  const typeCls = hallIsOutdoor(h) ? 'outdoor' : 'indoor';
  const typeTxt = hallIsOutdoor(h) ? svgIcon('tree') + ' Outdoor' : svgIcon('house') + ' Indoor';
  const acCls = hallHasAc(h) ? 'ac' : 'noac';
  const acTxt = hallHasAc(h) ? '❄ With AC' : 'Non-AC';
  return (
    '<span class="pill ' +
    typeCls +
    '">' +
    typeTxt +
    '</span><span class="pill ' +
    acCls +
    '">' +
    acTxt +
    '</span>'
  );
}
function minSlotPrice(h) {
  const offers = enabledSlotOffers(h);
  let min = h.priceFrom;
  offers.forEach(function (o) {
    if (o.offerNoAc && o.priceNoAc != null) min = min == null ? o.priceNoAc : Math.min(min, o.priceNoAc);
    if (o.offerAc && o.priceAc != null) min = min == null ? o.priceAc : Math.min(min, o.priceAc);
  });
  return min != null ? min : h.priceFrom || 0;
}
function hallMatchesFilters(h) {
  if (h.area !== state.loc) return false;
  if (state.venueType === 'indoor' && hallIsOutdoor(h)) return false;
  if (state.venueType === 'outdoor' && !hallIsOutdoor(h)) return false;
  if (state.ac === 'ac' && !hallHasAc(h)) return false;
  if (minSlotPrice(h) > state.priceMax) return false;
  return true;
}
function acHoursNote(slotId) {
  if (slotId === 'fullday') return 'AC included: 5 hours';
  return 'AC included: 3 hours';
}
function slotPeriodIcon(slotId) {
  if (slotId === 'evening') {
    return '<span class="slot-ico moon">' + svgIcon('moon') + '</span>';
  }
  return '<span class="slot-ico sun">' + svgIcon('sun') + '</span>';
}
function priceTileHtml(o, kind, selected) {
  const isNo = kind === 'noac';
  const price = isNo ? o.priceNoAc : o.priceAc;
  const listRaw = isNo ? o.listPriceNoAc : o.listPriceAc;
  const list = listRaw != null ? listRaw : price;
  const disc = isNo ? o.discountNoAc : o.discountAc;
  const pct = isNo ? o.discountNoAcPct : o.discountAcPct;
  const title = isNo ? 'Without AC' : 'With AC';
  const ico = isNo ? svgIcon('fan') : svgIcon('snow');
  const acNote = isNo ? '' : '<div class="ac-inc">' + acHoursNote(o.id) + '</div>';
  let priceBlock =
    '<div class="price-main">₹ ' + price.toLocaleString('en-IN') + '</div>';
  if (disc === 'yes' && list > price && pct > 0) {
    priceBlock =
      '<div class="strike">₹ ' +
      list.toLocaleString('en-IN') +
      '</div><div class="price-main">₹ ' +
      price.toLocaleString('en-IN') +
      '</div>';
  }
  return (
    '<div class="ac-tile' +
    (selected ? ' on' : '') +
    '" data-ac="' +
    kind +
    '"><div class="radio"></div><div class="tile-ico">' +
    ico +
    '</div><div class="tile-lbl">' +
    title +
    '</div>' +
    acNote +
    priceBlock +
    '</div>'
  );
}
function slotTimeRange(o) {
  if (!o || !o.hallFrom) return '';
  return o.label + ' · ' + (o.hallFrom && o.hallTo ? o.hallFrom + ' – ' + o.hallTo : '');
}
function hall() {
  return HALLS.find((h) => h.id === state.hallId) || HALLS[0];
}
function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
}
function businessLabel(h) {
  return h.businessName || h.name || '';
}
function hallLabel(h) {
  if (h.useHallName === false) return businessLabel(h);
  const n = String(h.hallName || '').trim();
  if (n) return n;
  return businessLabel(h);
}
function showHallSubline(h) {
  return !!(h.useHallName && String(h.hallName || '').trim());
}
function hallRowTitleHtml(h) {
  let html = '<div class="hall-row-titles"><span class="hall-row-biz">' + esc(businessLabel(h)) + '</span>';
  if (showHallSubline(h)) {
    html += '<span class="hall-row-hall">' + esc(hallLabel(h)) + ' Hall</span>';
  }
  html += '</div>';
  return html;
}
function syncFromOwnerPackage() {
  try {
    const raw = localStorage.getItem(OWNER_PKG_KEY);
    if (!raw) return;
    const pkg = JSON.parse(raw);
    const h = HALLS.find((x) => x.id === 'royal');
    if (!h) return;
    if (pkg.businessName) h.businessName = pkg.businessName;
    if (typeof pkg.useHallName === 'boolean') h.useHallName = pkg.useHallName;
    if (pkg.useHallName && pkg.hallName) h.hallName = String(pkg.hallName).trim();
    else if (!pkg.useHallName) h.hallName = '';
    if (pkg.slotOffers && pkg.slotOffers.length) {
      h.slotOffers = pkg.slotOffers;
      const offers = enabledSlotOffers(h);
      let min = null;
      offers.forEach(function (o) {
        if (o.offerNoAc) min = min == null ? o.priceNoAc : Math.min(min, o.priceNoAc);
        if (o.offerAc) min = min == null ? o.priceAc : Math.min(min, o.priceAc);
      });
      if (min != null) h.priceFrom = min;
    }
    if (pkg.capacity) {
      h.seat = pkg.capacity.seat != null ? pkg.capacity.seat : h.seat;
      h.dine = pkg.capacity.dine != null ? pkg.capacity.dine : h.dine;
      h.park = pkg.capacity.car != null ? pkg.capacity.car : h.park;
      h.bike = pkg.capacity.bike != null ? pkg.capacity.bike : h.bike;
      h.rooms = pkg.capacity.rooms != null ? pkg.capacity.rooms : h.rooms;
    }
    if (pkg.facilities && pkg.facilities.length) h.facilities = pkg.facilities.slice();
    if (pkg.spaceType) h.spaceType = pkg.spaceType;
    if (pkg.payment) h.payment = JSON.parse(JSON.stringify(pkg.payment));
    if (pkg.prices) h.extraPrices = JSON.parse(JSON.stringify(pkg.prices));
    if (pkg.cancelRules) h.cancelRules = pkg.cancelRules;
    if (pkg.rescheduleRules) h.rescheduleRules = pkg.rescheduleRules;
  } catch (_e) {
    /* ignore */
  }
}
function enabledSlotOffers(h) {
  const list =
    h.slotOffers && h.slotOffers.length
      ? h.slotOffers
      : [
          { id: 'morning', label: 'Morning', hallFrom: '10:00', hallTo: '15:00', enabled: true, offerNoAc: true, offerAc: true, priceNoAc: h.priceFrom, priceAc: h.priceAc },
          { id: 'evening', label: 'Evening', hallFrom: '17:00', hallTo: '23:00', enabled: true, offerNoAc: true, offerAc: true, priceNoAc: h.priceFrom, priceAc: h.priceAc },
          { id: 'fullday', label: 'Full Day', hallFrom: '09:00', hallTo: '23:00', enabled: true, offerNoAc: true, offerAc: true, priceNoAc: h.priceFrom + 20000, priceAc: h.priceAc + 15000 },
        ];
  return list.filter(function (o) {
    return o.enabled !== false;
  });
}
function selectedSlotOffer(h) {
  const offers = enabledSlotOffers(h).map(slotWithPromo);
  return (
    offers.find(function (o) {
      return o.id === state.slot;
    }) || offers[0]
  );
}
function displayListPrice(h) {
  const o = selectedSlotOffer(h);
  if (!o) return priceForHall(h, state.acChoice);
  if (state.acChoice === 'ac') return o.listPriceAc != null ? o.listPriceAc : o.priceAc;
  return o.listPriceNoAc != null ? o.listPriceNoAc : o.priceNoAc;
}
function applyStandaloneAssets() {
  /* Photos removed from cards and hero — layout-only demo */
}
function injectChromeIcons() {
  const map = {
    brandLogo: svgIcon('logo'),
    brandLogo2: svgIcon('logo'),
    hdBell: svgIcon('bell'),
    hdBell2: svgIcon('bell'),
    hdMenu: svgIcon('menu'),
    hdSearch: svgIcon('search'),
    hdHeart: svgIcon('heart'),
    icoLoc: svgIcon('pin'),
    icoEvent: svgIcon('cal'),
    icoDateHome: svgIcon('cal'),
    icoGuests: svgIcon('people'),
    chevLoc: svgIcon('chev'),
    icoSearchBtn: svgIcon('search'),
    resLocIco: svgIcon('pin'),
    fabHeart: svgIcon('heart'),
    fabShare: svgIcon('share'),
    dateChev: svgIcon('chev'),
    dateIcoWrap: svgIcon('cal'),
    gstInfo: svgIcon('info'),
    icoPlane: svgIcon('plane'),
    navSearch: svgIcon('search'),
    navSaved: svgIcon('heart'),
    navBook: svgIcon('cal'),
    navProfile: svgIcon('people'),
  };
  Object.keys(map).forEach(function (id) {
    const n = el(id);
    if (n) n.innerHTML = map[id];
  });
  const li = el('lblLoc');
  if (li) li.innerHTML = svgIcon('pin') + ' Location';
  const le = el('lblEvent');
  if (le) le.innerHTML = svgIcon('cal') + ' Event Type';
  const ld = el('lblDate');
  if (ld) ld.innerHTML = svgIcon('cal') + ' Event Date';
  const lg = el('lblGuests');
  if (lg) lg.innerHTML = svgIcon('people') + ' Number of Guests';
  const la = el('lblAc');
  if (la) la.innerHTML = svgIcon('snow') + ' AC Preference';
  const lv = el('lblVenue');
  if (lv) lv.innerHTML = svgIcon('house') + ' Venue Type';
  const lp = el('lblPrice');
  if (lp) lp.innerHTML = svgIcon('pin') + ' Price Range (per time slot)';
  document.querySelectorAll('.seg-ico-indoor').forEach(function (n) {
    n.innerHTML = svgIcon('house');
  });
  document.querySelectorAll('.seg-ico-outdoor').forEach(function (n) {
    n.innerHTML = svgIcon('tree');
  });
}
function syncDateDisplay() {
  const fd = el('fDate');
  const disp = el('fDateDisplay');
  if (fd && disp) disp.value = formatDateLong(fd.value);
  if (fd) state.date = fd.value;
}
function openCalendar() {
  const ov = el('calOverlay');
  const slotsScr = el('slots');
  if (!ov) return;
  if (slotsScr) slotsScr.scrollTop = 0;
  ov.hidden = false;
  ov.setAttribute('aria-hidden', 'false');
  ov.classList.add('on');
  renderCalendarGrid();
}
function closeCalendar() {
  const ov = el('calOverlay');
  if (!ov) return;
  ov.classList.remove('on');
  ov.hidden = true;
  ov.setAttribute('aria-hidden', 'true');
}
function renderCalendarGrid() {
  const grid = el('calGrid');
  if (!grid) return;
  const parts = state.date.split('-');
  const y = +parts[0] || 2026;
  const m = (+parts[1] || 12) - 1;
  const sel = +parts[2] || 25;
  const first = new Date(y, m, 1);
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const start = first.getDay();
  let html = '<div class="d off">S</div><div class="d off">M</div><div class="d off">T</div><div class="d off">W</div><div class="d off">T</div><div class="d off">F</div><div class="d off">S</div>';
  for (let i = 0; i < start; i++) html += '<div class="d off"></div>';
  for (let d = 1; d <= daysInMonth; d++) {
    html += '<div class="d' + (d === sel ? ' on' : '') + '" data-day="' + d + '">' + d + '</div>';
  }
  grid.innerHTML = html;
  grid.querySelectorAll('.d[data-day]').forEach(function (cell) {
    cell.onclick = function () {
      grid.querySelectorAll('.d').forEach(function (x) {
        x.classList.remove('on');
      });
      cell.classList.add('on');
      state._calDay = +cell.getAttribute('data-day');
    };
  });
}
function applyCalendar() {
  const d = state._calDay || +state.date.split('-')[2] || 25;
  const parts = state.date.split('-');
  const iso = parts[0] + '-' + parts[1] + '-' + String(d).padStart(2, '0');
  state.date = iso;
  const fd = el('fDate');
  const fds = el('fDateSlots');
  if (fd) fd.value = iso;
  if (fds) fds.value = iso;
  syncDateDisplay();
  const dr = el('dateRowVal');
  if (dr) dr.textContent = formatDateLong(iso);
  closeCalendar();
  renderSlots();
}
function customerPriceLine(o, kind) {
  const isNo = kind === 'noac';
  const price = isNo ? o.priceNoAc : o.priceAc;
  const listRaw = isNo ? o.listPriceNoAc : o.listPriceAc;
  const list = listRaw != null ? listRaw : price;
  const disc = isNo ? o.discountNoAc : o.discountAc;
  const pct = isNo ? o.discountNoAcPct : o.discountAcPct;
  const label = isNo ? 'Without AC' : 'With AC';
  if (disc === 'yes' && pct > 0 && list > 0 && price < list) {
    return (
      label +
      ' — <span style="text-decoration:line-through;color:#9CA3AF;font-weight:700">₹ ' +
      list.toLocaleString('en-IN') +
      '</span> → <b style="color:#065F46">₹ ' +
      price.toLocaleString('en-IN') +
      '</b>'
    );
  }
  return label + ' — <b>₹ ' + price.toLocaleString('en-IN') + '</b>';
}
function priceForHall(h, acChoice) {
  const o = selectedSlotOffer(h);
  if (o) {
    if (acChoice === 'ac' && o.offerAc) return o.priceAc;
    if (acChoice === 'noac' && o.offerNoAc) return o.priceNoAc;
    if (o.offerAc) return o.priceAc;
    if (o.offerNoAc) return o.priceNoAc;
  }
  if (acChoice === 'ac') return h.priceAc;
  return h.priceFrom;
}
function formatDate(iso) {
  try {
    return new Date(iso + 'T12:00:00').toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
  } catch (_e) {
    return iso;
  }
}
function acLabel() {
  if (state.ac === 'ac') return 'With AC';
  if (state.ac === 'noac') return 'Without AC';
  return 'Any';
}

const PACKAGE_NOTE =
  'Hall price is venue hire only (time slot + facilities). Catering and decoration are separate unless you agree a bundled quote with the hall owner.';

function serviceLines(h) {
  const s = h.services || {};
  const rows = [];
  if (s.inHouseCatering) {
    rows.push('In-house catering available — quoted separately (not in hall package)');
  } else {
    rows.push('No in-house catering from hall');
  }
  if (s.outsideCatering) {
    rows.push('Outside catering allowed');
  } else {
    rows.push('Outside catering not allowed');
  }
  if (s.hallDecoration) {
    rows.push('Hall decoration service available — quoted separately (not in hall package)');
  } else {
    rows.push('Hall does not provide decoration service');
  }
  if (s.outsideDecorators) {
    rows.push('Outside decorators allowed');
  } else {
    rows.push('Outside decorators not allowed');
  }
  return rows;
}

const HALL_FAC_ICONS = {
  AC: '❄',
  'Generator / Power Backup': '⚡',
  'Chairs & Tables': '🪑',
  Stage: '🎭',
  'Sound System': '🔊',
  Restrooms: '🚻',
  Lift: '🛗',
  'Security in Parking Area': '🛡',
  CCTV: '📹',
  WiFi: '📶',
  Kitchen: '🍳',
  Greenroom: '🚪',
};

function facilityEmoji(name) {
  return HALL_FAC_ICONS[name] || '✓';
}

function parkingSecurityAvailable(h) {
  const fac = h.facilities || [];
  return fac.some(function (f) {
    return String(f).toLowerCase().indexOf('security') >= 0;
  });
}

function serviceDetailRows(h) {
  const s = h.services || {};
  return [
    {
      label: 'In-house catering',
      ok: !!s.inHouseCatering,
      yes: 'Available — quoted separately (not in hall package)',
      no: 'Not available from the hall',
    },
    {
      label: 'Outside catering',
      ok: !!s.outsideCatering,
      yes: 'Outside catering allowed',
      no: 'Outside catering not allowed',
    },
    {
      label: 'Hall decoration',
      ok: !!s.hallDecoration,
      yes: 'Hall decoration service available — quoted separately',
      no: 'Hall does not provide decoration service',
    },
    {
      label: 'Outside decorators',
      ok: !!s.outsideDecorators,
      yes: 'Outside decorators allowed',
      no: 'Outside decorators not allowed',
    },
    {
      label: 'Parking security',
      ok: parkingSecurityAvailable(h),
      yes: 'Security available in parking area',
      no: 'Parking security not listed for this hall',
    },
  ];
}

function facAllListRow(icoHtml, title, detail) {
  return (
    '<li><span class="fac-all-ico">' +
    icoHtml +
    '</span><span><b style="color:var(--blue)">' +
    esc(title) +
    '</b>' +
    (detail ? '<br><span style="font-size:12px;font-weight:600;color:var(--mut)">' + esc(detail) + '</span>' : '') +
    '</span></li>'
  );
}

function buildFacilitiesAllHtml(h) {
  const fac = h.facilities || [];
  let cap =
    '<div class="fac-all-sec"><div class="fac-all-hd">Capacity &amp; parking</div><ul class="fac-all-list">' +
    facAllListRow(svgIcon('seat'), h.seat + ' seating', 'Maximum seated guests') +
    facAllListRow(svgIcon('dine'), h.dine + ' dining', 'Dining / buffet capacity') +
    facAllListRow(svgIcon('car'), h.park + ' car parking', 'On-site parking (cars)') +
    facAllListRow(svgIcon('bike'), (h.bike || 0) + ' bike parking', 'Two-wheeler parking') +
    '</ul></div>';

  if (h.rooms) {
    cap +=
      '<div class="fac-all-sec"><div class="fac-all-hd">Rooms</div><ul class="fac-all-list">' +
      facAllListRow('🛏', h.rooms + ' private / changing rooms', 'For bridal / family use') +
      '</ul></div>';
  }

  const facGrid =
    '<div class="fac-all-sec"><div class="fac-all-hd">Hall facilities</div><div class="fac-grid fac-grid-all">' +
    fac
      .map(function (f) {
        return (
          '<div class="fac-cell"><span class="ic">' + facilityEmoji(f) + '</span>' + esc(f) + '</div>'
        );
      })
      .join('') +
    (fac.length ? '' : '<p class="sub">No facilities listed yet.</p>') +
    '</div></div>';

  const svcRows = serviceDetailRows(h)
    .map(function (r) {
      return (
        '<li><span class="fac-all-ico">' +
        (r.ok ? '✅' : '⛔') +
        '</span><span><b style="color:var(--blue)">' +
        esc(r.label) +
        '</b><span class="' +
        (r.ok ? 'fac-svc-yes' : 'fac-svc-no') +
        '">' +
        esc(r.ok ? r.yes : r.no) +
        '</span></span></li>'
      );
    })
    .join('');

  const svc =
    '<div class="fac-all-sec"><div class="fac-all-hd">Catering, decoration &amp; policies</div><ul class="fac-all-list">' +
    svcRows +
    '</ul><p class="fac-all-note">' +
    esc(PACKAGE_NOTE) +
    '</p></div>';

  return cap + facGrid + svc;
}

function openFacilitiesAll() {
  const ov = el('facOverlay');
  const body = el('facAllBody');
  if (!ov || !body) return;
  body.innerHTML = buildFacilitiesAllHtml(hall());
  ov.setAttribute('aria-hidden', 'false');
  ov.classList.add('on');
}

function closeFacilitiesAll() {
  const ov = el('facOverlay');
  if (!ov) return;
  ov.classList.remove('on');
  ov.setAttribute('aria-hidden', 'true');
}

function bindFacilitiesOverlayEvents() {
  const facClose = el('facClose');
  if (facClose && facClose.dataset.bound !== '1') {
    facClose.dataset.bound = '1';
    facClose.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      closeFacilitiesAll();
    });
  }
  const facOv = el('facOverlay');
  if (!facOv || facOv.dataset.bound === '1') return;
  facOv.dataset.bound = '1';
  facOv.addEventListener('click', function (e) {
    if (e.target === facOv || e.target.closest('#facClose')) {
      e.preventDefault();
      e.stopPropagation();
      closeFacilitiesAll();
    }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && facOv.classList.contains('on')) closeFacilitiesAll();
  });
}

function slotLabel() {
  const o = selectedSlotOffer(hall());
  if (!o) {
    return state.slot === 'morning'
      ? 'Morning (10:00 AM – 3:00 PM)'
      : state.slot === 'evening'
        ? 'Evening (5:00 PM – 11:00 PM)'
        : 'Full Day (9:00 AM – 5:00 PM)';
  }
  const ranges = {
    morning: '10:00 AM – 3:00 PM',
    evening: '5:00 PM – 11:00 PM',
    fullday: '9:00 AM – 9:00 PM',
  };
  return o.label + ' (' + (ranges[o.id] || o.label) + ')';
}

function captureFilters() {
  state.loc = el('fLoc').value;
  state.event = el('fEvent').value;
  state.date = el('fDate').value;
  state.guests = el('fGuests').value;
  const ds = el('fDateSlots');
  if (ds && ds.value) state.date = ds.value;
  const pm = el('fPriceMax');
  if (pm) state.priceMax = +pm.value || 200000;
}

function renderResults() {
  syncFromOwnerPackage();
  captureFilters();
  const locTxt = el('resLocTxt');
  if (locTxt) locTxt.textContent = state.loc;
  let list = HALLS.filter(hallMatchesFilters);
  if (state.loc === 'Kottayam, Kerala') {
    list = list.filter(function (h) {
      return MOCK_RESULT_IDS.indexOf(h.id) >= 0;
    });
  }
  const show24 = state.loc === 'Kottayam, Kerala' && state.venueType === 'any' && state.ac === 'any';
  el('resCount').textContent = (show24 ? '24' : list.length) + ' halls found';
  el('resList').innerHTML = list
    .map(function (h) {
      const from = h.listFrom != null ? h.listFrom : minSlotPrice(h);
      const cnt = h.imgCount || '1/12';
      const vb = h.verified
        ? '<span class="vb">' + svgIcon('check', 'flow-ico-xs') + ' Verified Business</span>'
        : '';
      return (
        '<button type="button" class="hall-row" data-hall="' +
        h.id +
        '"><div class="hall-row-img"><span class="save" type="button">' +
        svgIcon('heart') +
        '</span>' +
        vb +
        '<span class="cnt">' +
        esc(cnt) +
        '</span></div><div class="hall-row-bd">' +
        hallRowTitleHtml(h) +
        '<div class="loc">' +
        svgIcon('pinBlue') +
        ' ' +
        esc(h.area) +
        '</div><div class="pills">' +
        hallMetaPills(h) +
        '</div><div class="cap2"><span>' +
        svgIcon('seat') +
        ' ' +
        h.seat +
        ' Seating</span><span>' +
        svgIcon('dine') +
        ' ' +
        h.dine +
        ' Dining</span></div><div class="from">From ₹' +
        from.toLocaleString('en-IN') +
        ' <small>(GST included)</small></div></div></button>'
      );
    })
    .join('');
  el('resList').querySelectorAll('[data-hall]').forEach(function (c) {
    c.onclick = function () {
      state.hallId = c.getAttribute('data-hall');
      renderDetail();
      show('detail');
    };
  });
  el('resList').querySelectorAll('.save').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      toast('Saved to favourites (demo)');
    };
  });
}

function capGridCell(ico, num, lbl) {
  return (
    '<div class="cap-cell"><span class="ic">' +
    svgIcon(ico) +
    '</span><span class="cap-num">' +
    num +
    '</span><span class="cap-lbl">' +
    lbl +
    '</span></div>'
  );
}
function renderDetail() {
  const h = hall();
  const t = el('detailTitle');
  const hl = el('detailHallLine');
  const meta = el('detailMeta');
  if (t) t.textContent = businessLabel(h);
  if (hl) hl.textContent = showHallSubline(h) ? hallLabel(h) + ' Hall' : '';
  if (meta) {
    meta.innerHTML =
      svgIcon('pin') +
      ' ' +
      esc(h.area) +
      ' · ' +
      svgIcon('star') +
      ' ' +
      h.rating +
      ' (' +
      h.reviews +
      ' reviews)';
  }
  const thumbs = el('detailThumbs');
  if (thumbs) {
    thumbs.innerHTML = ['Photos (12)', 'Video (1)', 'Virtual Tour', 'Map']
      .map(function (x) {
        return '<div class="thumb"><span>' + esc(x) + '</span></div>';
      })
      .join('');
  }
  const fac = (h.facilities || []).slice(0, 6);
  const facIcons = HALL_FAC_ICONS;
  el('detailBody').innerHTML =
    '<div class="sec-hd">Capacity &amp; Parking</div><div class="cap-grid">' +
    capGridCell('seat', h.seat, 'Seating') +
    capGridCell('dine', h.dine, 'Dining') +
    capGridCell('car', h.park, 'Cars') +
    capGridCell('bike', h.bike || 0, 'Bikes') +
    '</div>' +
    (h.rooms
      ? '<div class="sec-hd">Rooms</div><div class="rooms-row"><span class="rooms-ico" aria-hidden="true">🛏</span><div><b>' +
        h.rooms +
        '</b> Private / changing rooms</div></div>'
      : '') +
    '<div class="sec-hd"><span>Facilities</span><button type="button" class="see" id="btnFacSeeAll">See all</button></div><div class="fac-grid">' +
    fac
      .map(function (f) {
        return '<div class="fac-cell"><span class="ic">' + (facIcons[f] || facilityEmoji(f)) + '</span>' + esc(f) + '</div>';
      })
      .join('') +
    '</div><div class="sec-hd">Location</div><p class="sub" style="color:#2563EB;font-weight:700">' +
    svgIcon('pin') +
    ' ' +
    esc(displayTitle(h)) +
    ', ' +
    esc(h.area) +
    '</p><p class="sub"><a href="#">Open in Google Maps</a></p>';
  const seeAll = el('btnFacSeeAll');
  if (seeAll) {
    seeAll.onclick = function (e) {
      e.preventDefault();
      e.stopPropagation();
      openFacilitiesAll();
    };
  }
}

function renderSlots() {
  syncFromOwnerPackage();
  captureFilters();
  const h = hall();
  const sv = el('slotsVenue');
  if (sv) {
    sv.innerHTML =
      '<div class="venue-panel"><div class="hero-img ph-photo" aria-hidden="true"></div><div class="bd"><b style="font-size:13px;color:var(--blue)">' +
      esc(displayTitle(h)) +
      '</b><div class="sub" style="display:flex;align-items:center;gap:4px;margin-top:4px">' +
      svgIcon('pin') +
      ' ' +
      esc(h.area) +
      '</div><div class="pills" style="margin-top:8px">' +
      hallMetaPills(h) +
      '</div></div></div>';
  }
  const dr = el('dateRowVal');
  if (dr) {
    dr.textContent = state.date ? formatDateLong(state.date) : 'Select a date';
    dr.style.color = state.date ? '#2563EB' : '#64748B';
  }
  const ds = el('fDateSlots');
  if (ds) ds.value = state.date;
  const slots = enabledSlotOffers(h).map(slotWithPromo);
  if (!slots.length) {
    el('slotPick').innerHTML = '<p class="sub pad">No slots from owner package yet.</p>';
    return;
  }
  if (!slots.find(function (o) {
    return o.id === state.slot;
  })) {
    state.slot = slots[0].id;
    state.acChoice = slots[0].offerAc ? 'ac' : 'noac';
  }
  el('slotPick').innerHTML = slots
    .map(function (sl) {
      const on = state.slot === sl.id;
      let tiles = '';
      if (sl.offerAc && state.ac !== 'noac') {
        tiles += priceTileHtml(sl, 'ac', on && state.acChoice === 'ac');
      }
      if (sl.offerNoAc && state.ac !== 'ac') {
        tiles += priceTileHtml(sl, 'noac', on && state.acChoice === 'noac');
      }
      return (
        '<div class="slot-block' +
        (on ? ' slot-picked' : '') +
        '" data-slot="' +
        sl.id +
        '"><div class="slot-hd"><div class="slot-title">' +
        slotPeriodIcon(sl.id) +
        '<div><div class="slot-name">' +
        esc(sl.label) +
        '</div><div class="slot-time">' +
        esc(formatTimeRange(sl.hallFrom, sl.hallTo)) +
        '</div></div></div>' +
        '</div><div class="ac-tiles">' +
        tiles +
        '</div></div>'
      );
    })
    .join('');
  const ex = h.extraPrices || {};
  const eh = el('extraHours');
  if (eh) {
    eh.innerHTML =
      '<div class="extra-card"><div class="extra-hd"><span class="extra-clock">🕐</span><b>Additional Hour Charges (if needed)</b><span class="extra-info">' +
      svgIcon('info') +
      '</span></div><div class="extra-split"><div>' +
      svgIcon('snow') +
      ' With AC<br><strong>₹ ' +
      (ex.extraAc || 7000).toLocaleString('en-IN') +
      ' per hour</strong></div><div>' +
      svgIcon('fan') +
      ' Without AC<br><strong>₹ ' +
      (ex.extraNoAc || 5000).toLocaleString('en-IN') +
      ' per hour</strong></div></div></div>';
  }
  el('slotPick').querySelectorAll('.slot-block').forEach(function (row) {
    row.onclick = function (e) {
      if (e.target.closest('.ac-tile')) return;
      state.slot = row.getAttribute('data-slot');
      renderSlots();
    };
    row.querySelectorAll('.ac-tile').forEach(function (tile) {
      tile.onclick = function (e) {
        e.stopPropagation();
        state.slot = row.getAttribute('data-slot');
        state.acChoice = tile.getAttribute('data-ac');
        renderSlots();
      };
    });
  });
}

function formatTimeRange(from, to) {
  function t12(hhmm) {
    if (!hhmm) return '';
    const p = String(hhmm).split(':');
    const hr = +p[0] || 0;
    const ampm = hr >= 12 ? 'PM' : 'AM';
    const h12 = hr % 12 || 12;
    return h12 + ':' + String(+p[1] || 0).padStart(2, '0') + ' ' + ampm;
  }
  return t12(from) + ' – ' + t12(to);
}

function renderEnquiry() {
  syncFromOwnerPackage();
  captureFilters();
  const h = hall();
  const chargeDisplay = displayListPrice(h);
  const pay = h.payment || { advanceFixed: 20000, fullDueDays: 3, advanceType: 'fixed' };
  const advance = pay.advanceType === 'pct' ? Math.round((chargeDisplay * pay.advancePct) / 100) : pay.advanceFixed || 20000;
  const cancel = h.cancelRules || [{ days: '30+ days', pct: 10 }];
  const resched = h.rescheduleRules || cancel;
  const cancelHtml = cancel
    .map(function (r) {
      return esc(r.days) + ': ' + r.pct + '% refund';
    })
    .join('<br>');
  const reschedHtml = resched
    .map(function (r) {
      return esc(r.days) + (r.pct ? ': ' + r.pct + '% fee' : '');
    })
    .join('<br>');
  el('enquiryBody').innerHTML =
    '<div class="ev-card"><div class="thumb ph-photo" aria-hidden="true"></div><div><b style="color:var(--blue);font-size:14px">' +
    esc(businessLabel(h)) +
    '</b><div class="subname">' +
    esc(hallLabel(h)) +
    ' Hall</div><div class="sub" style="display:flex;align-items:center;gap:4px;margin-top:4px">' +
    svgIcon('pin') +
    ' ' +
    esc(h.area) +
    '</div><div class="pills" style="margin-top:6px">' +
    hallMetaPills(h) +
    '</div></div></div>' +
    '<div class="sec-hd"><span>Event Details</span><button type="button" class="see" data-to="home">✎ Edit</button></div>' +
    '<div class="ev-list">' +
    '<div class="kv"><span>' +
    svgIcon('cal') +
    ' Event Type</span><b>' +
    esc(state.event) +
    '</b></div>' +
    '<div class="kv"><span>' +
    svgIcon('cal') +
    ' Event Date</span><b>' +
    esc(formatDateLong(state.date)) +
    '</b></div>' +
    '<div class="kv"><span>' +
    svgIcon('cal') +
    ' Time Slot</span><b>' +
    esc(slotLabel()) +
    '</b></div>' +
    '<div class="kv"><span>' +
    svgIcon('snow') +
    ' AC Option</span><b>' +
    (state.acChoice === 'ac' ? 'With AC' : 'Without AC') +
    '</b></div>' +
    '<div class="kv"><span>' +
    svgIcon('people') +
    ' Guests</span><b>' +
    esc(state.guests) +
    '</b></div></div>' +
    '<div class="charge-bar"><span>Hall Charge (GST included)</span><b>₹ ' +
    chargeDisplay.toLocaleString('en-IN') +
    '</b></div>' +
    '<div class="box-adv"><div class="rupee">₹</div><div><b style="color:#B91C1C">Advance Payment (To Hall Directly) — ₹ ' +
    advance.toLocaleString('en-IN') +
    (pay.advanceType === 'fixed' ? ' (Fixed)' : '') +
    '</b><br>• Pay the hall directly after they accept.<br>• Gixbee does not collect payment in this demo.<br>• Advance confirms your booking window.</div></div>' +
    '<div class="box-full"><span style="font-size:20px">' +
    svgIcon('cal') +
    '</span><div><b>Full Payment (To Hall Directly)</b><br>Pay the remaining amount at least ' +
    (pay.fullDueDays || 3) +
    ' days before the event.</div></div>' +
    '<div class="acc acc-cancel" id="accCancel"><button type="button" class="acc-hd">' +
    svgIcon('warn') +
    ' Cancellation Policy <span>▾</span></button><div class="acc-bd">' +
    cancelHtml +
    '</div></div>' +
    '<div class="acc acc-resched" id="accResched"><button type="button" class="acc-hd">' +
    svgIcon('cal') +
    ' Rescheduling Policy <span>▾</span></button><div class="acc-bd">' +
    reschedHtml +
    '</div></div>' +
    '<div class="flow-hd">How Booking Works</div>' +
    '<div class="steps">' +
    '<div><div class="step-n">1</div><div class="step-ico">🛏</div>Request booking</div>' +
    '<div><div class="step-n">2</div><div class="step-ico">✓</div>Hall accepts</div>' +
    '<div><div class="step-n">3</div><div class="step-ico">⏱</div>Pay advance (24h)</div>' +
    '<div><div class="step-n">4</div><div class="step-ico">📅</div>Booked</div></div>';
  document.querySelectorAll('.acc-hd').forEach(function (btn) {
    btn.onclick = function () {
      btn.parentElement.classList.toggle('open');
    };
  });
}

function showBootError(msg) {
  const box = el('bootError');
  if (!box) {
    alert(msg);
    return;
  }
  box.hidden = false;
  box.innerHTML =
    '<h1 style="color:#DC2626">Demo did not start</h1><p>' +
    String(msg).replace(/</g, '&lt;') +
    '</p><p>Open <b>' +
    DEMO_FILE +
    '</b>. Hard refresh Ctrl+Shift+R.</p>';
}

function bindCustomerEvents() {
  const go = el('goSearch');
  if (go) {
    go.onclick = function () {
      renderResults();
      show('results');
    };
  }
  const phone = document.querySelector('.phone');
  if (phone) {
    phone.addEventListener('click', function (e) {
      const btn = e.target.closest('[data-to]');
      if (!btn) return;
      const id = btn.getAttribute('data-to');
      if (id === 'results') renderResults();
      if (id === 'slots') renderSlots();
      if (id === 'enquiry') renderEnquiry();
      if (id === 'home') captureFilters();
      show(id);
    });
  }
  bindFacilitiesOverlayEvents();
  const fac = el('fAc');
  if (fac) {
    fac.querySelectorAll('button').forEach(function (btn) {
      btn.onclick = function () {
        fac.querySelectorAll('button').forEach(function (x) {
          x.classList.remove('on');
        });
        btn.classList.add('on');
        state.ac = btn.getAttribute('data-ac');
      };
    });
  }
  const fv = el('fVenue');
  if (fv) {
    fv.querySelectorAll('button').forEach(function (btn) {
      btn.onclick = function () {
        fv.querySelectorAll('button').forEach(function (x) {
          x.classList.remove('on');
        });
        btn.classList.add('on');
        state.venueType = btn.getAttribute('data-venue');
      };
    });
  }
  const pm = el('fPriceMax');
  const pl = el('priceMaxLbl');
  if (pm) {
    pm.oninput = function () {
      state.priceMax = +pm.value || 200000;
      if (pl) pl.textContent = '₹' + state.priceMax.toLocaleString('en-IN') + (state.priceMax >= 200000 ? '+' : '');
    };
  }
  const dateRow = el('dateRow');
  if (dateRow) {
    dateRow.onclick = function () {
      openCalendar();
    };
  }
  const calCancel = el('calCancel');
  const calDone = el('calDone');
  if (calCancel) calCancel.onclick = closeCalendar;
  if (calDone) calDone.onclick = applyCalendar;
  const fdHome = el('fDate');
  if (fdHome) {
    fdHome.onchange = function () {
      syncDateDisplay();
      state.date = fdHome.value;
    };
  }
  const req = el('reqBook');
  if (req) req.onclick = function () {
    show('sent');
  };
  document.querySelectorAll('[data-nav]').forEach(function (btn) {
    btn.onclick = function () {
      const nav = btn.getAttribute('data-nav');
      if (nav === 'home') show('home');
      else toast('Demo: ' + nav + ' coming soon');
    };
  });
}

function bootCustomer() {
  try {
    if (!el('goSearch')) {
      throw new Error('Missing search screen — open ' + DEMO_FILE + ', not the empty shell file.');
    }
    applyStandaloneAssets();
    injectChromeIcons();
    syncDateDisplay();
    syncFromOwnerPackage();
    bindCustomerEvents();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent = 'No hall photos on cards · ' + CUSTOMER_BUILD + ' · Tap Search Halls';
    }
    const err = el('bootError');
    if (err) err.hidden = true;
  } catch (err) {
    console.error(err);
    showBootError(err.message || String(err));
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootCustomer);
} else {
  bootCustomer();
}