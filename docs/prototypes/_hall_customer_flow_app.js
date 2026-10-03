const CUSTOMER_BUILD = '2026-10-03-hall-customer-flow-v2-dummy';
const DEMO_FILE = 'GIXBEE-HALL-CUSTOMER-FlowHtml.html';
const OWNER_PKG_KEY = 'GIXBEE_HALL_PACKAGE';

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
      priceAc: 52500,
      listPriceNoAc: 55000,
      listPriceAc: 75000,
      discountNoAc: 'no',
      discountAc: 'yes',
      discountNoAcPct: 0,
      discountAcPct: 30,
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
      priceNoAc: 75000,
      priceAc: 90000,
      listPriceNoAc: 75000,
      listPriceAc: 90000,
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
    priceFrom: 52500,
    priceAc: 75000,
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
    id: 'grace',
    businessName: 'Grace Auditorium',
    useHallName: false,
    hallName: '',
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
    priceFrom: 45000,
    priceAc: 65000,
    slotOffers: dummyStandardSlots(45000, 65000),
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
    id: 'lakeside',
    businessName: 'Lakeview Gardens',
    useHallName: true,
    hallName: 'Open Lawn',
    area: 'Kottayam, Kerala',
    spaceType: 'outdoor',
    rating: 4.5,
    reviews: 64,
    seat: 400,
    dine: 300,
    park: 80,
    bike: 120,
    rooms: 0,
    facilities: ['Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Generator / Power Backup', 'Security in Parking Area'],
    tags: ['Wedding', 'Reception'],
    priceFrom: 38000,
    priceAc: 38000,
    slotOffers: dummyOutdoorSlots(38000),
    payment: { advanceType: 'pct', advancePct: 25, fullDueDays: 5 },
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraNoAc: 3500 },
    services: {
      inHouseCatering: false,
      outsideCatering: true,
      hallDecoration: false,
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
    tags: ['Wedding', 'Corporate'],
    priceFrom: 68000,
    priceAc: 92000,
    slotOffers: dummyStandardSlots(68000, 92000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraAc: 8500, extraNoAc: 6000 },
    services: {
      inHouseCatering: true,
      outsideCatering: false,
      hallDecoration: true,
      outsideDecorators: false,
    },
  },
  {
    id: 'stthomas',
    businessName: 'St. Thomas Community Hall',
    useHallName: false,
    hallName: '',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.4,
    reviews: 45,
    seat: 350,
    dine: 280,
    park: 25,
    bike: 50,
    rooms: 1,
    facilities: ['AC', 'Chairs & Tables', 'Sound System', 'Restrooms'],
    tags: ['Baptism', 'Birthday'],
    priceFrom: 32000,
    priceAc: 48000,
    slotOffers: dummyStandardSlots(32000, 48000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: DUMMY_EXTRA,
    services: {
      inHouseCatering: false,
      outsideCatering: true,
      hallDecoration: false,
      outsideDecorators: true,
    },
  },
  {
    id: 'palm',
    businessName: 'Palm Grove Convention',
    useHallName: true,
    hallName: 'Crystal',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.9,
    reviews: 188,
    seat: 850,
    dine: 650,
    park: 60,
    bike: 90,
    rooms: 3,
    facilities: ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Lift', 'Security in Parking Area'],
    tags: ['Wedding', 'Reception', 'Corporate'],
    priceFrom: 85000,
    priceAc: 110000,
    slotOffers: dummyStandardSlots(85000, 110000),
    payment: DUMMY_PAYMENT,
    cancelRules: DUMMY_CANCEL,
    extraPrices: { extraAc: 9000, extraNoAc: 6500 },
    services: {
      inHouseCatering: true,
      outsideCatering: true,
      hallDecoration: true,
      outsideDecorators: true,
    },
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
function hallMetaPills(h) {
  const type = hallIsOutdoor(h) ? '🌳 Outdoor' : '🏠 Indoor';
  const ac = hallHasAc(h) ? '❄ With AC' : '🌬 Non-AC';
  return '<span class="pill">' + type + '</span><span class="pill">' + ac + '</span>';
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
function priceTileHtml(o, kind, selected) {
  const isNo = kind === 'noac';
  const price = isNo ? o.priceNoAc : o.priceAc;
  const list = isNo ? o.listPriceNoAc : o.listPriceAc;
  const disc = isNo ? o.discountNoAc : o.discountAc;
  const pct = isNo ? o.discountNoAcPct : o.discountAcPct;
  const label = isNo ? '🌬 Without AC' : '❄ With AC';
  let inner = label + '<span class="price">₹ ' + price.toLocaleString('en-IN') + '</span>';
  if (disc === 'yes' && list > price && pct > 0) {
    inner =
      label +
      '<span class="strike">₹ ' +
      list.toLocaleString('en-IN') +
      '</span><span class="price">₹ ' +
      price.toLocaleString('en-IN') +
      '</span><span class="sub" style="color:var(--gn2);font-weight:800">' +
      pct +
      '% off</span>';
  }
  return '<div class="ac-tile' + (selected ? ' on' : '') + '" data-ac="' + kind + '">' + inner + '</div>';
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
  const offers = enabledSlotOffers(h);
  return (
    offers.find(function (o) {
      return o.id === state.slot;
    }) || offers[0]
  );
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
      '</span> <span style="color:#B45309;font-weight:800">' +
      pct +
      '% off</span> → <b style="color:#065F46">₹ ' +
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
  const list = HALLS.filter(hallMatchesFilters);
  el('resCount').textContent = list.length + ' halls found';
  el('resList').innerHTML = list
    .map(function (h) {
      const from = minSlotPrice(h);
      return (
        '<button type="button" class="hall-row" data-hall="' +
        h.id +
        '"><div class="hall-row-img"><span class="vb">✓ Verified</span><span class="cnt">1/12</span></div><div class="hall-row-bd"><b>' +
        esc(displayTitle(h)) +
        '</b><div class="loc">📍 ' +
        esc(h.area) +
        '</div><div class="pills">' +
        hallMetaPills(h) +
        '</div><div class="cap2"><span>👥 ' +
        h.seat +
        ' Seating</span><span>🍽 ' +
        h.dine +
        ' Dining</span></div><div class="from">From ₹' +
        from.toLocaleString('en-IN') +
        ' <span class="sub">(GST included)</span></div></div></button>'
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
}

function renderDetail() {
  const h = hall();
  const t = el('detailTitle');
  const s = el('detailSub');
  if (t) t.textContent = businessLabel(h);
  if (s) s.innerHTML = esc(hallLabel(h)) + ' · 📍 ' + esc(h.area) + ' · ★ ' + h.rating + ' (' + h.reviews + ' reviews)';
  const thumbs = el('detailThumbs');
  if (thumbs) {
    thumbs.innerHTML = ['Photos (12)', 'Video (1)', 'Virtual Tour', 'Map']
      .map(function (x) {
        return '<div class="thumb">' + esc(x) + '</div>';
      })
      .join('');
  }
  const fac = (h.facilities || []).slice(0, 8);
  const facIcons = { AC: '❄', 'Generator / Power Backup': '⚡', 'Chairs & Tables': '🪑', Stage: '🎭', 'Sound System': '🔊', Restrooms: '🚻', Lift: '🛗', 'Security in Parking Area': '🛡' };
  el('detailBody').innerHTML =
    '<div class="sec-hd">Capacity &amp; Parking</div><div class="cap-grid">' +
    '<div class="cap-cell"><span>👥</span>' +
    h.seat +
    '<br>Seating</div><div class="cap-cell"><span>🍽</span>' +
    h.dine +
    '<br>Dining</div><div class="cap-cell"><span>🚗</span>' +
    h.park +
    '<br>Cars</div><div class="cap-cell"><span>🏍</span>' +
    (h.bike || 0) +
    '<br>Bikes</div></div>' +
    (h.rooms
      ? '<div class="sec-hd">Rooms</div><div class="cap-cell" style="text-align:left;padding:12px;margin-bottom:12px"><span style="display:inline">🛏</span> <b>' +
        h.rooms +
        '</b> Private / changing rooms</div>'
      : '') +
    '<div class="sec-hd"><span>Facilities</span><button type="button" class="see">See all</button></div><div class="fac-grid">' +
    fac
      .map(function (f) {
        return '<div class="fac-cell"><span>' + (facIcons[f] || '✓') + '</span>' + esc(f) + '</div>';
      })
      .join('') +
    '</div><div class="sec-hd">Location</div><p class="sub">📍 ' +
    esc(displayTitle(h)) +
    ', ' +
    esc(h.area) +
    '</p><p class="sub"><a href="#">Open in Google Maps</a></p>';
}

function renderSlots() {
  syncFromOwnerPackage();
  captureFilters();
  const h = hall();
  const sv = el('slotsVenue');
  if (sv) {
    sv.innerHTML =
      '<div class="venue-strip"><div class="thumb"></div><div><b style="font-size:13px;color:var(--navy)">' +
      esc(displayTitle(h)) +
      '</b><div class="sub">📍 ' +
      esc(h.area) +
      '</div><div class="pills">' +
      hallMetaPills(h) +
      '</div></div></div>';
  }
  const dr = el('dateRowVal');
  if (dr) dr.textContent = formatDateLong(state.date);
  const ds = el('fDateSlots');
  if (ds) ds.value = state.date;
  const slots = enabledSlotOffers(h);
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
      const pct = sl.discountAc === 'yes' ? sl.discountAcPct : sl.discountNoAc === 'yes' ? sl.discountNoAcPct : 0;
      const badge = pct > 0 ? '<span class="disc-badge">' + pct + '% Off</span>' : '';
      let tiles = '';
      if (sl.offerAc && state.ac !== 'noac') {
        tiles += priceTileHtml(sl, 'ac', on && state.acChoice === 'ac');
      }
      if (sl.offerNoAc && state.ac !== 'ac') {
        tiles += priceTileHtml(sl, 'noac', on && state.acChoice === 'noac');
      }
      return (
        '<div class="slot-block' +
        (on ? ' on' : '') +
        '" data-slot="' +
        sl.id +
        '"><div class="slot-hd"><div><b>' +
        esc(sl.label) +
        '</b><div class="sub">' +
        esc(formatTimeRange(sl.hallFrom, sl.hallTo)) +
        '</div></div>' +
        badge +
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
      '<div class="extra-card"><b>⏱ Additional Hour Charges (if needed)</b><div class="extra-split"><div>❄ With AC<br>₹ ' +
      (ex.extraAc || 7000).toLocaleString('en-IN') +
      '/hr</div><div>🌬 Without AC<br>₹ ' +
      (ex.extraNoAc || 5000).toLocaleString('en-IN') +
      '/hr</div></div></div>';
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
  const total = priceForHall(h, state.acChoice);
  const pay = h.payment || { advanceFixed: 20000, fullDueDays: 7, advanceType: 'fixed' };
  const advance = pay.advanceType === 'pct' ? Math.round((total * pay.advancePct) / 100) : pay.advanceFixed || 20000;
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
    '<div class="ev-card"><div class="thumb"></div><div><b style="color:var(--navy)">' +
    esc(displayTitle(h)) +
    '</b><div class="sub">📍 ' +
    esc(h.area) +
    '</div><div class="pills">' +
    hallMetaPills(h) +
    '</div></div></div>' +
    '<div class="sec-hd"><span>Event Details</span><button type="button" class="see" data-to="home">Edit</button></div>' +
    '<div class="ev-list">' +
    '<div class="kv"><span>📅 Event Type</span><b>' +
    esc(state.event) +
    '</b></div>' +
    '<div class="kv"><span>📅 Event Date</span><b>' +
    esc(formatDateLong(state.date)) +
    '</b></div>' +
    '<div class="kv"><span>🕐 Time Slot</span><b>' +
    esc(slotLabel()) +
    '</b></div>' +
    '<div class="kv"><span>❄ AC Option</span><b>' +
    (state.acChoice === 'ac' ? 'With AC' : 'Without AC') +
    '</b></div>' +
    '<div class="kv"><span>👥 Guests</span><b>' +
    esc(state.guests) +
    '</b></div></div>' +
    '<div class="charge-bar"><span>Hall Charge (GST included)</span><b>₹ ' +
    total.toLocaleString('en-IN') +
    '</b></div>' +
    '<div class="box-adv"><b>Advance Payment (To Hall Directly) — ₹ ' +
    advance.toLocaleString('en-IN') +
    (pay.advanceType === 'fixed' ? ' (Fixed)' : '') +
    '</b><br>• Pay the hall directly after they accept.<br>• Gixbee does not collect payment in this demo.<br>• Advance confirms your booking window.</div>' +
    '<div class="box-full"><b>📅 Full Payment (To Hall Directly)</b><br>Pay the remaining amount at least ' +
    (pay.fullDueDays || 7) +
    ' days before the event.</div>' +
    '<div class="acc" id="accCancel"><button type="button" class="acc-hd">⚠ Cancellation Policy <span>▾</span></button><div class="acc-bd">' +
    cancelHtml +
    '</div></div>' +
    '<div class="acc" id="accResched"><button type="button" class="acc-hd">📅 Rescheduling Policy <span>▾</span></button><div class="acc-bd">' +
    reschedHtml +
    '</div></div>' +
    '<div class="flow-hd">How Booking Works</div>' +
    '<div class="steps"><div><div class="step-n">1</div>Request</div><div><div class="step-n">2</div>Accept</div><div><div class="step-n">3</div>Pay advance</div><div><div class="step-n">4</div>Booked</div></div>';
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
  const fds = el('fDateSlots');
  if (dateRow && fds) {
    dateRow.onclick = function () {
      fds.showPicker ? fds.showPicker() : fds.click();
    };
    fds.onchange = function () {
      state.date = fds.value;
      const dr = el('dateRowVal');
      if (dr) dr.textContent = formatDateLong(state.date);
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
    syncFromOwnerPackage();
    bindCustomerEvents();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Dummy data demo · ' +
        HALLS.length +
        ' sample halls · ' +
        CUSTOMER_BUILD +
        ' (optional: owner package overrides Koinonia in same browser)';
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