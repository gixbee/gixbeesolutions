const CUSTOMER_BUILD = '2026-09-28-hall-customer-v12';
const DEMO_FILE = 'hall-customer-book-master.html';
const OWNER_PKG_KEY = 'GIXBEE_HALL_PACKAGE';

const EVENT_LABEL_BY_ID = {
  wedding: 'Wedding',
  reception: 'Reception',
  engagement: 'Engagement',
  birthday: 'Birthday',
  baptism: 'Baptism',
  anniversary: 'Anniversary',
  corporate: 'Corporate Event',
  conference: 'Conference',
  religious: 'Religious Function',
};

const DEMO_HALLS = [
  {
    id: 'royal',
    businessName: 'Vijaya Convention Center',
    useHallName: true,
    hallName: 'Tiffle',
    area: 'Kottayam, Kerala',
    spaceType: 'indoor',
    rating: 4.8,
    reviews: 120,
    seat: 700,
    dine: 550,
    park: 50,
    eventIds: [],
    tags: ['Baptism', 'Wedding', 'Reception'],
    priceFrom: 55000,
    priceAc: 75000,
    facilities: [],
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
    eventIds: [],
    tags: ['Baptism', 'Birthday'],
    priceFrom: 45000,
    priceAc: 65000,
    facilities: [],
    services: {
      inHouseCatering: true,
      outsideCatering: true,
      hallDecoration: true,
      outsideDecorators: true,
    },
  },
];

const HALLS = DEMO_HALLS.map(function (h) {
  return JSON.parse(JSON.stringify(h));
});

const state = {
  loc: 'Kottayam, Kerala',
  event: 'Baptism',
  date: '2026-12-25',
  guests: '200',
  ac: 'any',
  hallId: 'royal',
  slot: 'morning',
  acChoice: 'noac',
  ownerLinked: false,
  cancelRules: null,
  rescheduleRules: null,
  cancelPolicyNote: '',
  reschedulePolicyNote: '',
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
function hallIsOutdoor(h) {
  return !!(h && h.spaceType === 'outdoor');
}
function eventLabelToId(label) {
  const key = String(label || '').toLowerCase();
  const ids = Object.keys(EVENT_LABEL_BY_ID);
  for (let i = 0; i < ids.length; i++) {
    if (EVENT_LABEL_BY_ID[ids[i]].toLowerCase() === key) return ids[i];
  }
  return key.replace(/\s+/g, '');
}
function eventIdsToTags(ids) {
  if (!ids || !ids.length) return ['Wedding', 'Reception', 'Baptism'];
  return ids.map(function (id) {
    return EVENT_LABEL_BY_ID[id] || id;
  });
}
function hallSupportsEvent(h, eventLabel) {
  const ids = h.eventIds;
  if (!ids || !ids.length) return true;
  const want = eventLabelToId(eventLabel);
  return ids.indexOf(want) >= 0;
}
function cateringToServices(c) {
  c = c || {};
  return {
    inHouseCatering: c.inHouse === 'yes',
    outsideCatering: c.outside === 'yes',
    hallDecoration: c.decorHall === 'yes',
    outsideDecorators: c.decorOutside === 'yes',
  };
}
function normalizeSlotOffersForVenue(offers, spaceType) {
  const list = (offers || []).map(function (o) {
    return JSON.parse(JSON.stringify(o));
  });
  if (spaceType !== 'outdoor') return list;
  list.forEach(function (o) {
    o.offerAc = false;
    o.offerNoAc = true;
    o.acMode = 'full';
    o.acHours = 0;
  });
  return list;
}
function minPriceFromOffers(offers) {
  let min = null;
  let maxAc = null;
  offers.forEach(function (o) {
    if (o.enabled === false) return;
    if (o.offerNoAc && o.priceNoAc != null) {
      min = min == null ? o.priceNoAc : Math.min(min, o.priceNoAc);
    }
    if (o.offerAc && o.priceAc != null) {
      min = min == null ? o.priceAc : Math.min(min, o.priceAc);
      maxAc = maxAc == null ? o.priceAc : Math.min(maxAc, o.priceAc);
    }
  });
  return { min: min != null ? min : 55000, priceAc: maxAc != null ? maxAc : 75000 };
}
function resetHallsFromDemo() {
  HALLS.length = 0;
  DEMO_HALLS.forEach(function (h) {
    HALLS.push(JSON.parse(JSON.stringify(h)));
  });
}
function applyOwnerTopLevelToHall(h, pkg) {
  if (pkg.businessName) h.businessName = pkg.businessName;
  if (pkg.businessLocation) h.area = pkg.businessLocation;
  h.useHallName = true;
  if (pkg.hallName) h.hallName = String(pkg.hallName).trim();
  if (pkg.spaceType) h.spaceType = pkg.spaceType === 'outdoor' ? 'outdoor' : 'indoor';
  if (pkg.capacity) {
    h.seat = pkg.capacity.seat != null ? pkg.capacity.seat : h.seat;
    h.dine = pkg.capacity.dine != null ? pkg.capacity.dine : h.dine;
    h.park = pkg.capacity.car != null ? pkg.capacity.car : h.park;
  }
  if (pkg.events && pkg.events.length) {
    h.eventIds = pkg.events.slice();
    h.tags = eventIdsToTags(h.eventIds);
  }
  if (pkg.facilities && pkg.facilities.length) h.facilities = pkg.facilities.slice();
  if (pkg.catering) h.services = cateringToServices(pkg.catering);
  if (pkg.slotOffers && pkg.slotOffers.length) {
    h.slotOffers = normalizeSlotOffersForVenue(pkg.slotOffers, h.spaceType);
  }
  const priced = minPriceFromOffers(h.slotOffers || []);
  h.priceFrom = priced.min;
  h.priceAc = priced.priceAc;
  h.payment = pkg.payment ? JSON.parse(JSON.stringify(pkg.payment)) : h.payment;
  h.cancelRules = (pkg.cancelRules || []).map(function (r) {
    return JSON.parse(JSON.stringify(r));
  });
  h.rescheduleRules = (pkg.rescheduleRules || []).map(function (r) {
    return JSON.parse(JSON.stringify(r));
  });
  h.cancelPolicyNote = pkg.cancelPolicyNote || '';
  h.reschedulePolicyNote = pkg.reschedulePolicyNote || '';
}
function mapOwnerHallRecord(hr, pkg) {
  const p = hr.package || {};
  const spaceType = hr.spaceType === 'outdoor' ? 'outdoor' : 'indoor';
  const slotOffers = normalizeSlotOffersForVenue(p.slotOffers, spaceType);
  const priced = minPriceFromOffers(slotOffers);
  const cap = p.capacity || pkg.capacity || {};
  return {
    id: hr.id || 'hall-' + (hr.hallNumber || 1),
    businessName: pkg.businessName || 'Venue',
    useHallName: true,
    hallName: String(hr.hallName || '').trim() || 'Hall ' + (hr.hallNumber || 1),
    area: pkg.businessLocation || 'Kottayam, Kerala',
    spaceType: spaceType,
    rating: 4.8,
    reviews: 120,
    seat: cap.seat != null ? cap.seat : 700,
    dine: cap.dine != null ? cap.dine : 550,
    park: cap.car != null ? cap.car : 50,
    eventIds: (p.events || []).slice(),
    tags: eventIdsToTags(p.events),
    slotOffers: slotOffers,
    priceFrom: priced.min,
    priceAc: priced.priceAc,
    facilities: (p.facilities || []).slice(),
    services: cateringToServices(p.catering),
    payment: p.payment ? JSON.parse(JSON.stringify(p.payment)) : null,
    cancelRules: (p.cancelRules || []).map(function (r) {
      return JSON.parse(JSON.stringify(r));
    }),
    rescheduleRules: (p.rescheduleRules || []).map(function (r) {
      return JSON.parse(JSON.stringify(r));
    }),
    cancelPolicyNote: p.cancelPolicyNote || '',
    reschedulePolicyNote: p.reschedulePolicyNote || '',
  };
}
function ensureLocationOption(loc) {
  const sel = el('fLoc');
  if (!sel || !loc) return;
  const opts = Array.from(sel.options).map(function (o) {
    return o.value;
  });
  if (opts.indexOf(loc) < 0) {
    const opt = document.createElement('option');
    opt.value = loc;
    opt.textContent = loc;
    sel.appendChild(opt);
  }
  sel.value = loc;
  state.loc = loc;
}
function syncFromOwnerPackage() {
  state.ownerLinked = false;
  try {
    const raw = localStorage.getItem(OWNER_PKG_KEY);
    if (!raw) {
      resetHallsFromDemo();
      return;
    }
    const pkg = JSON.parse(raw);
    state.ownerLinked = true;
    if (pkg.businessLocation) ensureLocationOption(pkg.businessLocation);
    const bookable = (pkg.halls || []).filter(function (hr) {
      return hr.packageSaved && hr.hallActive !== false;
    });
    if (bookable.length) {
      HALLS.length = 0;
      bookable.forEach(function (hr) {
        HALLS.push(mapOwnerHallRecord(hr, pkg));
      });
    } else {
      resetHallsFromDemo();
      const h = HALLS.find(function (x) {
        return x.id === 'royal';
      });
      if (h) applyOwnerTopLevelToHall(h, pkg);
      if (HALLS.length > 1 && state.ownerLinked) {
        HALLS.splice(1);
      }
    }
    if (!HALLS.find(function (x) {
      return x.id === state.hallId;
    })) {
      state.hallId = HALLS[0].id;
    }
    if (pkg.cancelRules && pkg.cancelRules.length) state.cancelRules = pkg.cancelRules;
    if (pkg.rescheduleRules && pkg.rescheduleRules.length) state.rescheduleRules = pkg.rescheduleRules;
    if (pkg.cancelPolicyNote != null) state.cancelPolicyNote = String(pkg.cancelPolicyNote);
    if (pkg.reschedulePolicyNote != null) state.reschedulePolicyNote = String(pkg.reschedulePolicyNote);
  } catch (_e) {
    resetHallsFromDemo();
  }
}
function priceForHall(h, acChoice) {
  const o = selectedSlotOffer(h);
  if (hallIsOutdoor(h)) acChoice = 'noac';
  if (o) {
    if (acChoice === 'ac' && o.offerAc) return o.priceAc;
    if (acChoice === 'noac' && o.offerNoAc) return o.priceNoAc;
    if (o.offerAc) return o.priceAc;
    if (o.offerNoAc) return o.priceNoAc;
  }
  if (acChoice === 'ac') return h.priceAc;
  return h.priceFrom;
}
function slotLabel() {
  const o = selectedSlotOffer(hall());
  if (!o) return '';
  return o.label + ' (' + formatTimeRange(o.hallFrom, o.hallTo) + ')';
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
function facilitiesSummary(h) {
  const f = h.facilities || [];
  if (!f.length) return 'Stage, restrooms, and parking as configured by the hall owner.';
  return f.join(' · ');
}
function hallCardPillsHtml(h) {
  if (hallIsOutdoor(h)) {
    return '<div class="pills"><span class="pill out">Outdoor space</span></div>';
  }
  const fac = h.facilities || [];
  const hasAc = fac.indexOf('AC') >= 0;
  let html = '<div class="pills"><span class="pill">Indoor</span>';
  if (hasAc) html += '<span class="pill ac">AC available</span>';
  html += '</div>';
  return html;
}
function formatTime12(hhmm) {
  if (!hhmm) return '';
  const parts = String(hhmm).split(':');
  const h = +parts[0] || 0;
  const m = +parts[1] || 0;
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return h12 + ':' + String(m).padStart(2, '0') + ' ' + ampm;
}
function formatTimeRange(from, to) {
  return formatTime12(from) + ' – ' + formatTime12(to);
}
function defaultSlotOffers(h) {
  return [
    {
      id: 'morning',
      label: 'Morning',
      enabled: true,
      hallFrom: '10:00',
      hallTo: '15:00',
      offerNoAc: true,
      offerAc: !hallIsOutdoor(h),
      priceNoAc: h.priceFrom,
      priceAc: h.priceAc,
      acMode: 'full',
      acHours: 0,
    },
    {
      id: 'evening',
      label: 'Evening',
      enabled: true,
      hallFrom: '17:00',
      hallTo: '23:00',
      offerNoAc: true,
      offerAc: !hallIsOutdoor(h),
      priceNoAc: h.priceFrom,
      priceAc: h.priceAc,
      acMode: 'full',
      acHours: 0,
    },
    {
      id: 'fullday',
      label: 'Full Day',
      enabled: true,
      hallFrom: '09:00',
      hallTo: '21:00',
      offerNoAc: true,
      offerAc: !hallIsOutdoor(h),
      priceNoAc: h.priceFrom + 20000,
      priceAc: h.priceAc + 15000,
      acMode: 'limited',
      acLimitKind: 'flexible',
      acHours: 5,
      acFrom: '',
      acTo: '',
    },
  ];
}
function enabledSlotOffers(h) {
  const list = h.slotOffers && h.slotOffers.length ? h.slotOffers : defaultSlotOffers(h);
  return list.filter(function (o) {
    return o.enabled !== false;
  });
}
function selectedSlotOffer(h) {
  const offers = enabledSlotOffers(h);
  const pick = offers.find(function (o) {
    return o.id === state.slot;
  });
  return pick || offers[0];
}
function acUsageCustomerLine(o) {
  if (!o || !o.offerAc || o.acMode === 'full') return '';
  if (o.acLimitKind === 'hours') o.acLimitKind = 'flexible';
  if (o.acLimitKind === 'fixed' && o.acFrom && o.acTo) {
    return (
      'Includes ' +
      o.acHours +
      ' hours of AC, fixed schedule ' +
      formatTimeRange(o.acFrom, o.acTo) +
      ' (set by hall).'
    );
  }
  if (o.acHours) {
    return (
      'Includes ' +
      o.acHours +
      ' hours of AC in this slot. Confirm when AC will run with hall management (not chosen in the app).'
    );
  }
  return '';
}
function hallAcProfileLine(h) {
  if (hallIsOutdoor(h)) return '🌳 Outdoor space';
  const offers = enabledSlotOffers(h);
  const anyNoAc = offers.some(function (o) {
    return o.offerNoAc;
  });
  const anyAc = offers.some(function (o) {
    return o.offerAc;
  });
  if (anyAc && !anyNoAc) return '❄️ AC hall packages only';
  if (anyAc && anyNoAc) return '❄️ With or without AC';
  if (anyAc) return '❄️ AC available';
  return '🌬 Non-AC packages';
}
function advanceAmount(h, total) {
  const pay = h.payment || {};
  if (pay.advanceType === 'pct' && pay.advancePct != null) {
    return Math.round((total * pay.advancePct) / 100);
  }
  if (pay.advanceFixed != null) return pay.advanceFixed;
  return 20000;
}
function fullDueDays(h) {
  const pay = h.payment || {};
  return pay.fullDueDays != null ? pay.fullDueDays : 7;
}

function defaultPolicyRules() {
  return [
    { days: '30 days or more', pct: 10 },
    { days: '15 – 29 days', pct: 25 },
    { days: '7 – 14 days', pct: 50 },
    { days: '3 – 6 days', pct: 75 },
    { days: 'Less than 1 day', pct: 100 },
  ];
}
function policyRulesForHall(h, kind) {
  if (kind === 'reschedule') {
    if (h.rescheduleRules && h.rescheduleRules.length) return h.rescheduleRules;
    if (state.rescheduleRules && state.rescheduleRules.length) return state.rescheduleRules;
  } else {
    if (h.cancelRules && h.cancelRules.length) return h.cancelRules;
    if (state.cancelRules && state.cancelRules.length) return state.cancelRules;
  }
  return defaultPolicyRules();
}
function policyNoteForHall(h, kind) {
  if (kind === 'reschedule') {
    return h.reschedulePolicyNote || state.reschedulePolicyNote || '';
  }
  return h.cancelPolicyNote || state.cancelPolicyNote || '';
}
function policyBlockHtml(title, rules, note) {
  const lines = rules.map(function (r) {
    return esc(r.days) + ': ' + r.pct + '%';
  });
  let html = '<div class="box am"><b>' + esc(title) + '</b> (deducted from advance)<br>' + lines.join(' · ');
  if (note) html += '<br><span class="sub">' + esc(note) + '</span>';
  return html + '</div>';
}
function syncAcFilterVisibility() {
  const wrap = el('fAcWrap');
  if (!wrap) return;
  const allOutdoor =
    HALLS.length > 0 &&
    HALLS.every(function (h) {
      return hallIsOutdoor(h);
    });
  wrap.style.display = allOutdoor ? 'none' : '';
  if (allOutdoor) state.ac = 'any';
}
function venueBlurb(h) {
  if (hallIsOutdoor(h)) {
    return 'Open-air venue with natural setting. Ideal for ' + state.event.toLowerCase() + ' celebrations.';
  }
  return 'Spacious hall with stage, green room, and ample parking. Ideal for ' + state.event.toLowerCase() + ' events.';
}

function captureFilters() {
  state.loc = el('fLoc').value;
  state.event = el('fEvent').value;
  state.date = el('fDate').value;
  state.guests = el('fGuests').value;
}

function renderResults() {
  syncFromOwnerPackage();
  syncAcFilterVisibility();
  captureFilters();
  el('resTitle').textContent = 'Halls in ' + state.loc.split(',')[0];
  const chips = [state.event, formatDate(state.date), state.guests + ' guests'];
  if (!HALLS.every(hallIsOutdoor)) chips.push(acLabel());
  el('resChips').innerHTML = chips.map((c) => `<span class="chip">${c}</span>`).join('');
  const list = HALLS.filter(function (h) {
    const locOk = h.area === state.loc || state.loc.startsWith('Kottayam') || h.area === state.loc;
    return locOk && hallSupportsEvent(h, state.event);
  });
  el('resCount').textContent = list.length + ' halls found';
  if (!list.length) {
    el('resList').innerHTML =
      '<p class="sub">No halls match this search. Try another event type or complete Price &amp; packages on the owner demo for this venue.</p>';
    return;
  }
  el('resList').innerHTML = list
    .map((h) => {
      const biz = esc(businessLabel(h));
      const hallLine = showHallSubline(h)
        ? `<div class="meta">Hall: ${esc(h.hallName)}</div>`
        : '';
      const emoji = hallIsOutdoor(h) ? '🌳' : '🏛️';
      return `<article class="card" data-hall="${h.id}">
      <div style="height:140px;background:linear-gradient(135deg,#A7F3D0,#BFDBFE);display:grid;place-items:center;font-size:40px">${emoji}</div>
      <div class="bd"><span class="badge">Verified Business</span><b>${biz}</b>
      ${hallLine}
      ${hallCardPillsHtml(h)}
      <div class="meta">${esc(h.area)} · ★ ${h.rating} (${h.reviews})</div>
      <div class="meta">👥 ${h.seat} seat · 🍽 ${h.dine} dine · 🅿 ${h.park} cars</div>
      <div class="price">From ₹ ${h.priceFrom.toLocaleString('en-IN')} hall rent (GST incl.)</div>
      <div class="meta" style="margin-top:4px">Catering &amp; decoration quoted separately</div></div></article>`;
    })
    .join('');
  el('resList').querySelectorAll('[data-hall]').forEach((c) => {
    c.onclick = () => {
      state.hallId = c.getAttribute('data-hall');
      renderDetail();
      show('detail');
    };
  });
}

function renderDetail() {
  const h = hall();
  el('detailBody').innerHTML = `
    <h2 style="margin:8px 0 4px">${esc(hallLabel(h))}</h2>
    <p class="sub">${esc(businessLabel(h))} · ${esc(h.area)} · ★ ${h.rating} (${h.reviews} reviews)</p>
    <div class="chips">${h.tags.map((t) => `<span class="chip">${esc(t)}</span>`).join('')}</div>
    <p class="sub" style="margin-top:12px">${esc(venueBlurb(h))}</p>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px;font-size:12px;font-weight:800">
      <div>🪑 ${h.seat} Seating</div><div>🍽 ${h.dine} Dining</div>
      <div>🅿 ${h.park} Cars</div><div>${hallAcProfileLine(h)}</div>
    </div>
    <div class="box bl" style="margin-top:14px"><b>Facilities</b><br>${esc(facilitiesSummary(h))}</div>
    <div class="box bl" style="margin-top:10px"><b>Included in hall package</b><br>Venue hire for your time slot and listed facilities. Price on next steps is hall rent only.</div>
    <div class="box am" style="margin-top:10px"><b>Catering &amp; decoration</b> (not included in hall rent)<br>${serviceLines(h).join('<br>')}</div>
    <p class="sub" style="margin-top:10px">${PACKAGE_NOTE}</p>`;
}

function renderSlots() {
  const h = hall();
  const hint = el('slotDateHint');
  if (hint) {
    hint.textContent =
      formatDate(state.date) +
      (hallIsOutdoor(h) ? ' — choose a time slot (outdoor venue)' : ' — tap a slot and AC option');
  }
  let slots = enabledSlotOffers(h);
  if (!hallIsOutdoor(h)) {
    if (state.ac === 'ac') {
      slots = slots.filter(function (o) {
        return o.offerAc;
      });
    } else if (state.ac === 'noac') {
      slots = slots.filter(function (o) {
        return o.offerNoAc;
      });
    }
  }
  if (!slots.length) {
    el('slotPick').innerHTML = '<p class="sub">No slots match your filters. Change AC on search or ask the hall owner.</p>';
    return;
  }
  if (!slots.find(function (o) {
    return o.id === state.slot;
  })) {
    state.slot = slots[0].id;
    state.acChoice = hallIsOutdoor(h) ? 'noac' : slots[0].offerAc && state.ac !== 'noac' ? 'ac' : 'noac';
  }
  el('slotPick').innerHTML = slots
    .map(function (sl) {
      const on = state.slot === sl.id;
      const title = sl.label + ' (' + formatTimeRange(sl.hallFrom, sl.hallTo) + ')';
      const acNote = hallIsOutdoor(h) ? '' : acUsageCustomerLine(sl);
      let opts = '';
      if (hallIsOutdoor(h)) {
        opts =
          '<p class="sub" style="margin:4px 0 0"><b>Hall rent — ₹ ' +
          sl.priceNoAc.toLocaleString('en-IN') +
          '</b> (GST incl.)</p>';
      } else {
        if (sl.offerNoAc && state.ac !== 'ac') {
          opts +=
            '<label class="sub"><input type="radio" name="ac' +
            sl.id +
            '" value="noac"' +
            (state.slot === sl.id && state.acChoice === 'noac' ? ' checked' : '') +
            '> Without AC — ₹ ' +
            sl.priceNoAc.toLocaleString('en-IN') +
            '</label>';
        }
        if (sl.offerAc && state.ac !== 'noac') {
          opts +=
            '<label class="sub"><input type="radio" name="ac' +
            sl.id +
            '" value="ac"' +
            (state.slot === sl.id && state.acChoice === 'ac' ? ' checked' : '') +
            '> With AC — ₹ ' +
            sl.priceAc.toLocaleString('en-IN') +
            '</label>';
        }
      }
      return (
        '<div class="slot-opt' +
        (on ? ' on' : '') +
        '" data-slot="' +
        sl.id +
        '"><b>' +
        esc(title) +
        '</b>' +
        (acNote ? '<p class="sub" style="margin:4px 0 6px">' + esc(acNote) + '</p>' : '') +
        opts +
        '</div>'
      );
    })
    .join('');
  el('slotPick').querySelectorAll('.slot-opt').forEach((row) => {
    row.onclick = (e) => {
      if (e.target.tagName === 'INPUT') return;
      state.slot = row.getAttribute('data-slot');
      if (hallIsOutdoor(h)) state.acChoice = 'noac';
      renderSlots();
    };
    row.querySelectorAll('input[type=radio]').forEach((r) => {
      r.onchange = () => {
        state.slot = row.getAttribute('data-slot');
        state.acChoice = r.value;
        renderSlots();
      };
    });
  });
}

function renderEnquiry() {
  syncFromOwnerPackage();
  const h = hall();
  if (hallIsOutdoor(h)) state.acChoice = 'noac';
  const o = selectedSlotOffer(h);
  const total = priceForHall(h, state.acChoice);
  const advance = advanceAmount(h, total);
  const dueDays = fullDueDays(h);
  const acExtra = o && state.acChoice === 'ac' && !hallIsOutdoor(h) ? acUsageCustomerLine(o) : '';
  const acRow = hallIsOutdoor(h)
    ? ''
    : '<div class="kv"><span>AC Option</span><b>' +
      (state.acChoice === 'ac' ? 'With AC' : 'Without AC') +
      '</b></div>';
  el('enquiryBody').innerHTML = `
    <div class="card" style="cursor:default"><div class="bd"><b>${esc(hallLabel(h))}</b><div class="meta">${esc(businessLabel(h))} · ${esc(h.area)}</div></div></div>
    <div class="kv"><span>Event Type</span><b>${esc(state.event)}</b></div>
    <div class="kv"><span>Event Date</span><b>${formatDate(state.date)}</b></div>
    <div class="kv"><span>Time Slot</span><b>${esc(slotLabel())}</b></div>
    ${acRow}
    ${acExtra ? '<div class="kv"><span>AC (hall rules)</span><b>' + esc(acExtra) + '</b></div>' : ''}
    <div class="kv"><span>Guests</span><b>${esc(state.guests)}</b></div>
    <div class="box gn"><b>Hall charge (venue only): ₹ ${total.toLocaleString('en-IN')}</b><br><span class="sub">GST included · Catering &amp; decoration not included — arrange separately with the hall if needed.</span></div>
    <div class="box pk"><b>Advance payment: ₹ ${advance.toLocaleString('en-IN')}</b><br>Paid directly to hall owner after acceptance.</div>
    <div class="box bl"><b>Full payment</b> due ${dueDays} days before the event.</div>
    ${policyBlockHtml('Cancellation policy', policyRulesForHall(h, 'cancel'), policyNoteForHall(h, 'cancel'))}
    ${policyBlockHtml('Rescheduling policy', policyRulesForHall(h, 'reschedule'), policyNoteForHall(h, 'reschedule'))}
    <p class="sub">1. Request → 2. Hall accepts → 3. Pay advance (24h) → 4. Booked</p>`;
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
    go.onclick = () => {
      renderResults();
      show('results');
    };
  }
  document.querySelectorAll('[data-to]').forEach((b) => {
    b.addEventListener('click', () => {
      const id = b.getAttribute('data-to');
      if (id === 'slots') renderSlots();
      if (id === 'enquiry') renderEnquiry();
      show(id);
    });
  });
  const fac = el('fAc');
  if (fac) {
    fac.querySelectorAll('button').forEach((btn) => {
      btn.onclick = () => {
        fac.querySelectorAll('button').forEach((x) => x.classList.remove('on'));
        btn.classList.add('on');
        state.ac = btn.getAttribute('data-ac');
      };
    });
  }
  const req = el('reqBook');
  if (req) req.onclick = () => show('sent');
}

function bootCustomer() {
  try {
    if (!el('goSearch')) {
      throw new Error('Missing search screen — open ' + DEMO_FILE + ', not the empty shell file.');
    }
    syncFromOwnerPackage();
    syncAcFilterVisibility();
    bindCustomerEvents();
    const tag = el('buildTag');
    if (tag) {
      let line =
        'Working demo ' +
        CUSTOMER_BUILD +
        ' — open owner demo first to sync packages (same browser).';
      if (state.ownerLinked) line += ' Linked to owner package.';
      tag.textContent = line;
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
