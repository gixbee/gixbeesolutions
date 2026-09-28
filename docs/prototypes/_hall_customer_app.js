const CUSTOMER_BUILD = '2026-09-28-hall-customer-v11';
const DEMO_FILE = 'hall-customer-book-master.html';
const OWNER_PKG_KEY = 'GIXBEE_HALL_PACKAGE';

const HALLS = [
  {
    id: 'royal',
    businessName: 'Vijaya Convention Center',
    useHallName: true,
    hallName: 'Tiffle',
    area: 'Kottayam, Kerala',
    rating: 4.8,
    reviews: 120,
    seat: 700,
    dine: 550,
    park: 50,
    tags: ['Baptism', 'Wedding', 'Reception'],
    priceFrom: 55000,
    priceAc: 75000,
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
    rating: 4.6,
    reviews: 98,
    seat: 500,
    dine: 400,
    park: 30,
    tags: ['Baptism', 'Birthday'],
    priceFrom: 45000,
    priceAc: 65000,
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
  hallId: 'royal',
  slot: 'morning',
  acChoice: 'noac',
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
    if (pkg.slotOffers && pkg.slotOffers.length) h.slotOffers = pkg.slotOffers;
    const offers = enabledSlotOffers(h);
    let min = null;
    offers.forEach(function (o) {
      if (o.offerNoAc) min = min == null ? o.priceNoAc : Math.min(min, o.priceNoAc);
      if (o.offerAc) min = min == null ? o.priceAc : Math.min(min, o.priceAc);
    });
    if (min != null) h.priceFrom = min;
    if (pkg.cancelRules && pkg.cancelRules.length) state.cancelRules = pkg.cancelRules;
    if (pkg.rescheduleRules && pkg.rescheduleRules.length) state.rescheduleRules = pkg.rescheduleRules;
    if (pkg.cancelPolicyNote != null) state.cancelPolicyNote = String(pkg.cancelPolicyNote);
    if (pkg.reschedulePolicyNote != null) state.reschedulePolicyNote = String(pkg.reschedulePolicyNote);
  } catch (_e) {
    /* ignore */
  }
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
      offerAc: true,
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
      offerAc: true,
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
      offerAc: true,
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

function defaultPolicyRules() {
  return [
    { days: '30 days or more', pct: 10 },
    { days: '15 – 29 days', pct: 25 },
    { days: '7 – 14 days', pct: 50 },
    { days: '3 – 6 days', pct: 75 },
    { days: 'Less than 1 day', pct: 100 },
  ];
}
function policyRulesForDisplay() {
  return state.cancelRules && state.cancelRules.length ? state.cancelRules : defaultPolicyRules();
}
function rescheduleRulesForDisplay() {
  return state.rescheduleRules && state.rescheduleRules.length ? state.rescheduleRules : defaultPolicyRules();
}
function policyBlockHtml(title, rules, note) {
  const lines = rules.map(function (r) {
    return esc(r.days) + ': ' + r.pct + '%';
  });
  let html = '<div class="box am"><b>' + esc(title) + '</b> (deducted from advance)<br>' + lines.join(' · ');
  if (note) html += '<br><span class="sub">' + esc(note) + '</span>';
  return html + '</div>';
}

function captureFilters() {
  state.loc = el('fLoc').value;
  state.event = el('fEvent').value;
  state.date = el('fDate').value;
  state.guests = el('fGuests').value;
}

function renderResults() {
  syncFromOwnerPackage();
  captureFilters();
  el('resTitle').textContent = 'Halls in ' + state.loc.split(',')[0];
  el('resChips').innerHTML = [
    state.event,
    formatDate(state.date),
    state.guests + ' guests',
    acLabel(),
  ]
    .map((c) => `<span class="chip">${c}</span>`)
    .join('');
  const list = HALLS.filter((h) => h.area === state.loc || state.loc.startsWith('Kottayam'));
  el('resCount').textContent = list.length + ' halls found';
  el('resList').innerHTML = list
    .map((h) => {
      const biz = esc(businessLabel(h));
      const hallLine = showHallSubline(h)
          ? `<div class="meta">Hall: ${esc(h.hallName)}</div>`
          : '';
      return `<article class="card" data-hall="${h.id}">
      <div style="height:140px;background:linear-gradient(135deg,#A7F3D0,#BFDBFE);display:grid;place-items:center;font-size:40px">🏛️</div>
      <div class="bd"><span class="badge">Verified Business</span><b>${biz}</b>
      ${hallLine}
      <div class="meta">${h.area} · ★ ${h.rating} (${h.reviews})</div>
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
    <p class="sub">${esc(businessLabel(h))} · ${h.area} · ★ ${h.rating} (${h.reviews} reviews)</p>
    <div class="chips">${h.tags.map((t) => `<span class="chip">${t}</span>`).join('')}</div>
    <p class="sub" style="margin-top:12px">Spacious hall with stage, green room, and ample parking. Ideal for ${state.event.toLowerCase()} events in Kottayam.</p>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px;font-size:12px;font-weight:800">
      <div>🪑 ${h.seat} Seating</div><div>🍽 ${h.dine} Dining</div>
      <div>🅿 ${h.park} Cars</div><div>${hallAcProfileLine(h)}</div>
    </div>
    <div class="box bl" style="margin-top:14px"><b>Included in hall package</b><br>Venue hire for your time slot, standard facilities (stage, restrooms, parking as listed). Price on next steps is hall rent only.</div>
    <div class="box am" style="margin-top:10px"><b>Catering &amp; decoration</b> (not included in hall rent)<br>${serviceLines(h).join('<br>')}</div>
    <p class="sub" style="margin-top:10px">${PACKAGE_NOTE}</p>`;
}

function renderSlots() {
  const h = hall();
  let slots = enabledSlotOffers(h);
  if (state.ac === 'ac') {
    slots = slots.filter(function (o) {
      return o.offerAc;
    });
  } else if (state.ac === 'noac') {
    slots = slots.filter(function (o) {
      return o.offerNoAc;
    });
  }
  if (!slots.length) {
    el('slotPick').innerHTML = '<p class="sub">No slots match your AC filter. Change AC on search or ask the hall owner.</p>';
    return;
  }
  if (!slots.find(function (o) { return o.id === state.slot; })) {
    state.slot = slots[0].id;
    state.acChoice = slots[0].offerAc && state.ac !== 'noac' ? 'ac' : 'noac';
  }
  el('slotPick').innerHTML = slots
    .map(function (sl) {
      const on = state.slot === sl.id;
      const title = sl.label + ' (' + formatTimeRange(sl.hallFrom, sl.hallTo) + ')';
      const acNote = acUsageCustomerLine(sl);
      let opts = '';
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
  const h = hall();
  const o = selectedSlotOffer(h);
  const total = priceForHall(h, state.acChoice);
  const advance = 20000;
  const acExtra = o && state.acChoice === 'ac' ? acUsageCustomerLine(o) : '';
  el('enquiryBody').innerHTML = `
    <div class="card" style="cursor:default"><div class="bd"><b>${esc(hallLabel(h))}</b><div class="meta">${esc(businessLabel(h))} · ${h.area}</div></div></div>
    <div class="kv"><span>Event Type</span><b>${state.event}</b></div>
    <div class="kv"><span>Event Date</span><b>${formatDate(state.date)}</b></div>
    <div class="kv"><span>Time Slot</span><b>${slotLabel()}</b></div>
    <div class="kv"><span>AC Option</span><b>${state.acChoice === 'ac' ? 'With AC' : 'Without AC'}</b></div>
    ${acExtra ? '<div class="kv"><span>AC (hall rules)</span><b>' + esc(acExtra) + '</b></div>' : ''}
    <div class="kv"><span>Guests</span><b>${state.guests}</b></div>
    <div class="box gn"><b>Hall charge (venue only): ₹ ${total.toLocaleString('en-IN')}</b><br><span class="sub">GST included · Catering &amp; decoration not included — arrange separately with the hall if needed.</span></div>
    <div class="box pk"><b>Advance payment: ₹ ${advance.toLocaleString('en-IN')}</b><br>Paid directly to hall owner after acceptance.</div>
    <div class="box bl"><b>Full payment</b> due 7 days before the event.</div>
    ${policyBlockHtml('Cancellation policy', policyRulesForDisplay(), state.cancelPolicyNote)}
    ${policyBlockHtml('Rescheduling policy', rescheduleRulesForDisplay(), state.reschedulePolicyNote)}
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
    bindCustomerEvents();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Working demo ' + CUSTOMER_BUILD + ' — if Search fails, use Chrome or: python3 -m http.server 8765';
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