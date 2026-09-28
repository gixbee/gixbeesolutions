const CUSTOMER_BUILD = '2026-09-28-hall-customer-v6';
const DEMO_FILE = 'hall-customer-book-master.html';
const OWNER_PKG_KEY = 'GIXBEE_HALL_PACKAGE';

const HALLS = [
  {
    id: 'royal',
    businessName: 'Vijaya Convention Center',
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
    hallName: 'Main Hall',
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
  return h.hallName || h.businessName || h.name || '';
}
function syncFromOwnerPackage() {
  try {
    const raw = localStorage.getItem(OWNER_PKG_KEY);
    if (!raw) return;
    const pkg = JSON.parse(raw);
    const h = HALLS.find((x) => x.id === 'royal');
    if (!h) return;
    if (pkg.businessName) h.businessName = pkg.businessName;
    if (pkg.hallName) h.hallName = pkg.hallName;
  } catch (_e) {
    /* ignore */
  }
}
function priceForHall(h, acChoice) {
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
  return state.slot === 'morning'
    ? 'Morning (10:00 AM – 3:00 PM)'
    : state.slot === 'evening'
      ? 'Evening (5:00 PM – 11:00 PM)'
      : 'Full Day (9:00 AM – 5:00 PM)';
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
      const hallLine =
        hallLabel(h) !== businessLabel(h)
          ? `<div class="meta">Hall: ${esc(hallLabel(h))}</div>`
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
      <div>🅿 ${h.park} Cars</div><div>❄️ AC & Non-AC</div>
    </div>
    <div class="box bl" style="margin-top:14px"><b>Included in hall package</b><br>Venue hire for your time slot, standard facilities (stage, restrooms, parking as listed). Price on next steps is hall rent only.</div>
    <div class="box am" style="margin-top:10px"><b>Catering &amp; decoration</b> (not included in hall rent)<br>${serviceLines(h).join('<br>')}</div>
    <p class="sub" style="margin-top:10px">${PACKAGE_NOTE}</p>`;
}

function renderSlots() {
  const h = hall();
  const slots = [
    { id: 'morning', label: 'Morning (10:00 AM – 3:00 PM)', no: h.priceFrom, ac: h.priceAc },
    { id: 'evening', label: 'Evening (5:00 PM – 11:00 PM)', no: h.priceFrom, ac: h.priceAc },
    { id: 'fullday', label: 'Full Day (9:00 AM – 5:00 PM)', no: h.priceFrom + 20000, ac: h.priceAc + 15000 },
  ];
  el('slotPick').innerHTML = slots
    .map((sl) => {
      const on = state.slot === sl.id;
      return `<div class="slot-opt${on ? ' on' : ''}" data-slot="${sl.id}">
        <b>${sl.label}</b>
        <label class="sub"><input type="radio" name="ac${sl.id}" value="noac"${state.slot === sl.id && state.acChoice === 'noac' ? ' checked' : ''}> Without AC — ₹ ${sl.no.toLocaleString('en-IN')}</label>
        <label class="sub"><input type="radio" name="ac${sl.id}" value="ac"${state.slot === sl.id && state.acChoice === 'ac' ? ' checked' : ''}> With AC — ₹ ${sl.ac.toLocaleString('en-IN')}</label>
      </div>`;
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
  const total = priceForHall(h, state.acChoice);
  const advance = 20000;
  el('enquiryBody').innerHTML = `
    <div class="card" style="cursor:default"><div class="bd"><b>${esc(hallLabel(h))}</b><div class="meta">${esc(businessLabel(h))} · ${h.area}</div></div></div>
    <div class="kv"><span>Event Type</span><b>${state.event}</b></div>
    <div class="kv"><span>Event Date</span><b>${formatDate(state.date)}</b></div>
    <div class="kv"><span>Time Slot</span><b>${slotLabel()}</b></div>
    <div class="kv"><span>AC Option</span><b>${state.acChoice === 'ac' ? 'With AC' : 'Without AC'}</b></div>
    <div class="kv"><span>Guests</span><b>${state.guests}</b></div>
    <div class="box gn"><b>Hall charge (venue only): ₹ ${total.toLocaleString('en-IN')}</b><br><span class="sub">GST included · Catering &amp; decoration not included — arrange separately with the hall if needed.</span></div>
    <div class="box pk"><b>Advance payment: ₹ ${advance.toLocaleString('en-IN')}</b><br>Paid directly to hall owner after acceptance.</div>
    <div class="box bl"><b>Full payment</b> due 7 days before the event.</div>
    <div class="box am"><b>Cancellation policy</b><br>30+ days: 10% · 15–29 days: 25% · 7–14 days: 50% · &lt;1 day: 100%</div>
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