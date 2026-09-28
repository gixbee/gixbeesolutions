const CUSTOMER_BUILD = '2026-09-28-hall-customer-v2';
const DEMO_FILE = 'hall-customer-book-master.html';

const HALLS = [
  {
    id: 'royal',
    name: 'Royal Convention Centre',
    area: 'Kottayam, Kerala',
    rating: 4.8,
    reviews: 120,
    seat: 700,
    dine: 550,
    park: 50,
    tags: ['Baptism', 'Wedding', 'Reception'],
    priceFrom: 55000,
    priceAc: 75000,
  },
  {
    id: 'grace',
    name: 'Grace Auditorium',
    area: 'Kottayam, Kerala',
    rating: 4.6,
    reviews: 98,
    seat: 500,
    dine: 400,
    park: 30,
    tags: ['Baptism', 'Birthday'],
    priceFrom: 45000,
    priceAc: 65000,
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
    .map(
      (h) => `<article class="card" data-hall="${h.id}">
      <div style="height:140px;background:linear-gradient(135deg,#A7F3D0,#BFDBFE);display:grid;place-items:center;font-size:40px">🏛️</div>
      <div class="bd"><span class="badge">Verified Business</span><b>${h.name}</b>
      <div class="meta">${h.area} · ★ ${h.rating} (${h.reviews})</div>
      <div class="meta">👥 ${h.seat} seat · 🍽 ${h.dine} dine · 🅿 ${h.park} cars</div>
      <div class="price">From ₹ ${h.priceFrom.toLocaleString('en-IN')} (GST incl.)</div></div></article>`,
    )
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
    <h2 style="margin:8px 0 4px">${h.name}</h2>
    <p class="sub">${h.area} · ★ ${h.rating} (${h.reviews} reviews)</p>
    <div class="chips">${h.tags.map((t) => `<span class="chip">${t}</span>`).join('')}</div>
    <p class="sub" style="margin-top:12px">Spacious hall with stage, green room, and ample parking. Ideal for ${state.event.toLowerCase()} events in Kottayam.</p>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px;font-size:12px;font-weight:800">
      <div>🪑 ${h.seat} Seating</div><div>🍽 ${h.dine} Dining</div>
      <div>🅿 ${h.park} Cars</div><div>❄️ AC & Non-AC</div>
    </div>`;
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
    <div class="card" style="cursor:default"><div class="bd"><b>${h.name}</b><div class="meta">${h.area}</div></div></div>
    <div class="kv"><span>Event Type</span><b>${state.event}</b></div>
    <div class="kv"><span>Event Date</span><b>${formatDate(state.date)}</b></div>
    <div class="kv"><span>Time Slot</span><b>${slotLabel()}</b></div>
    <div class="kv"><span>AC Option</span><b>${state.acChoice === 'ac' ? 'With AC' : 'Without AC'}</b></div>
    <div class="kv"><span>Guests</span><b>${state.guests}</b></div>
    <div class="box gn"><b>Hall charge: ₹ ${total.toLocaleString('en-IN')}</b> (GST included)</div>
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
    bindCustomerEvents();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Hall customer demo ' + CUSTOMER_BUILD + ' — JS is inside this HTML file (no .js needed).';
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