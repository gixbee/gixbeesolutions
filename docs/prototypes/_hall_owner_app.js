const OWNER_BUILD = '2026-09-28-hall-owner-v5';
const DEMO_FILE = 'hall-owner-lmb-master.html';
const PKG_KEY = 'GIXBEE_HALL_PACKAGE';

const EVENT_CATS = [
  { id: 'wedding', label: 'Wedding', icon: '💒' },
  { id: 'reception', label: 'Reception', icon: '🥂' },
  { id: 'engagement', label: 'Engagement', icon: '💍' },
  { id: 'birthday', label: 'Birthday', icon: '🎂' },
  { id: 'baptism', label: 'Baptism', icon: '⛪' },
  { id: 'anniversary', label: 'Anniversary', icon: '🎉' },
  { id: 'corporate', label: 'Corporate Event', icon: '🏢' },
  { id: 'conference', label: 'Conference', icon: '🎤' },
  { id: 'religious', label: 'Religious Function', icon: '🕯️' },
];

const FACILITIES = ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms', 'Lift'];

const SLOTS = [
  { id: 'morning', label: 'Morning', time: '10:00 AM – 3:00 PM' },
  { id: 'evening', label: 'Evening', time: '5:00 PM – 11:00 PM' },
  { id: 'fullday', label: 'Full Day', time: '9:00 AM – 5:00 PM' },
];

const MANAGE_MENU = [
  { id: 'calendar', title: 'Calendar & Availability', sub: 'Block dates and manage slots' },
  { id: 'ownerReq', title: 'Booking Requests', sub: 'Accept or decline customer requests', dot: true },
  { id: 'pkg1', title: 'Packages & Pricing', sub: 'Set slot prices and cancellation policy' },
  { id: 'placeholder', title: "Update Today's Prices", sub: 'Price window closed after 8:30 AM — opens tomorrow morning', cls: 'green muted' },
  { id: 'placeholder', title: 'Operators', sub: 'Who can manage this business' },
  { id: 'placeholder', title: 'Photos & Portfolio', sub: 'Add and manage business photos' },
  { id: 'placeholder', title: 'Edit Business Details', sub: 'Update name, description, location' },
  { id: 'placeholder', title: 'Delete Business', sub: 'Remove permanently from Gixbee', cls: 'danger' },
];

const state = {
  events: ['wedding', 'reception', 'engagement', 'birthday', 'baptism', 'anniversary', 'religious'],
  facilities: ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms'],
  catering: { inHouse: 'yes', outside: 'yes', decorHall: 'no', decorOutside: 'yes' },
  capacity: { seat: 700, dine: 550, car: 50, bike: 100, rooms: 2 },
  prices: {
    morning: { noAc: 55000, ac: 75000 },
    evening: { noAc: 55000, ac: 75000 },
    fullday: { noAc: 75000, ac: 90000 },
    extraNoAc: 5000,
    extraAc: 7000,
  },
  payment: { advanceType: 'fixed', advanceFixed: 20000, advancePct: 30, fullDueDays: 7 },
  cancelRules: [
    { days: '30 days or more', pct: 10 },
    { days: '15 – 29 days', pct: 25 },
    { days: '7 – 14 days', pct: 50 },
    { days: '3 – 6 days', pct: 75 },
    { days: 'Less than 1 day', pct: 100 },
  ],
  bookWindowMonths: 6,
  minNoticeDays: 3,
  calDay: 25,
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
  setTimeout(() => (t.style.display = 'none'), 2600);
}
function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
}
function loadPkg() {
  try {
    const raw = localStorage.getItem(PKG_KEY);
    if (raw) Object.assign(state, JSON.parse(raw));
  } catch (_e) {
    /* ignore */
  }
}
function savePkg() {
  localStorage.setItem(PKG_KEY, JSON.stringify(state));
}

function yesNoLabel(key, yes) {
  const labels = {
    inHouse: yes ? 'In-house catering offered (separate charge)' : 'No in-house catering',
    outside: yes ? 'Outside catering allowed' : 'Outside catering not allowed',
    decorHall: yes ? 'Hall decoration service offered (separate charge)' : 'No hall decoration service',
    decorOutside: yes ? 'Outside decorators allowed' : 'Outside decorators not allowed',
  };
  return labels[key] || (yes ? 'Yes' : 'No');
}

function cateringReviewLines() {
  const c = state.catering;
  return [
    yesNoLabel('inHouse', c.inHouse === 'yes'),
    yesNoLabel('outside', c.outside === 'yes'),
    yesNoLabel('decorHall', c.decorHall === 'yes'),
    yesNoLabel('decorOutside', c.decorOutside === 'yes'),
  ];
}

function renderManage() {
  el('manageMenu').innerHTML = MANAGE_MENU.map((m) => {
    const cls = m.cls ? ' ' + m.cls.split(' ').join(' ') : '';
    const dot = m.dot ? '<span class="dot"></span>' : '';
    return `<button type="button" class="mrow${cls}" data-go="${m.id}"><b>${esc(m.title)}${dot}</b><span>${esc(m.sub)}</span></button>`;
  }).join('');
  el('manageMenu').querySelectorAll('[data-go]').forEach((btn) => {
    btn.onclick = () => {
      const id = btn.getAttribute('data-go');
      if (id === 'placeholder') {
        el('phTitle').textContent = btn.querySelector('b').textContent.replace(/\u200b/g, '');
        show('placeholder');
        return;
      }
      show(id);
      if (id === 'pkg1') renderPkg1();
      if (id === 'calendar') renderCalendar();
      if (id === 'ownerReq') renderOwnerReq();
    };
  });
}

function renderPkgSteps(n) {
  const stepsEl = el('pkgSteps');
  if (!stepsEl) return;
  const steps = ['Event Categories', 'Venue Details', 'Pricing & Time Slots', 'Payment & Policies', 'Review & Save'];
  stepsEl.innerHTML = steps
    .map((s, i) => `<span class="step${i + 1 === n ? ' on' : ''}">${i + 1}. ${s}</span>`)
    .join('');
}

function renderPkg1() {
  renderPkgSteps(1);
  el('eventCats').innerHTML = EVENT_CATS.map(
    (c) =>
      `<label class="ev${state.events.includes(c.id) ? ' on' : ''}"><span>${c.icon}</span><span style="flex:1;font-weight:800">${esc(
        c.label,
      )}</span><input type="checkbox" data-ev="${c.id}"${state.events.includes(c.id) ? ' checked' : ''}></label>`,
  ).join('');
  el('eventCats').querySelectorAll('[data-ev]').forEach((cb) => {
    cb.onchange = () => {
      const id = cb.getAttribute('data-ev');
      if (cb.checked) {
        if (!state.events.includes(id)) state.events.push(id);
      } else state.events = state.events.filter((x) => x !== id);
      renderPkg1();
    };
  });
  el('pkg1Next').onclick = () => {
    if (!state.events.length) {
      toast('Select at least one event category.');
      return;
    }
    renderPkg2();
    show('pkg2');
  };
}

function renderPkg2() {
  renderPkgSteps(2);
  el('seatCap').value = state.capacity.seat;
  el('dineCap').value = state.capacity.dine;
  el('parkCar').value = state.capacity.car;
  el('parkBike').value = state.capacity.bike;
  el('rooms').value = state.capacity.rooms;
  el('facGrid').innerHTML = FACILITIES.map(
    (f) =>
      `<label class="${state.facilities.includes(f) ? 'on' : ''}"><input type="checkbox" data-fac="${esc(f)}"${
        state.facilities.includes(f) ? ' checked' : ''
      }> ${esc(f)}</label>`,
  ).join('');
  el('facGrid').querySelectorAll('[data-fac]').forEach((cb) => {
    cb.onchange = () => {
      const f = cb.getAttribute('data-fac');
      if (cb.checked) {
        if (!state.facilities.includes(f)) state.facilities.push(f);
      } else state.facilities = state.facilities.filter((x) => x !== f);
      renderPkg2();
    };
  });
  const q = (key, label, hint) =>
    `<div style="margin:12px 0 8px"><p style="font-weight:800;font-size:13px;margin:0 0 4px">${label}</p>` +
    (hint ? `<p class="sub" style="margin:0 0 6px">${hint}</p>` : '') +
    ['yes', 'no']
      .map(
        (v) =>
          `<label class="radio-row"><input type="radio" name="${key}" value="${v}"${
            state.catering[key] === v ? ' checked' : ''
          }> ${v === 'yes' ? 'Yes' : 'No'}</label>`,
      )
      .join('') +
    '</div>';
  el('caterDec').innerHTML =
    q(
      'inHouse',
      'In-house catering available?',
      'If Yes, customers see that you can arrange catering. Price is quoted separately — not part of the hall package in step 3.',
    ) +
    q('outside', 'Outside catering allowed?', 'If Yes, customers may bring their own caterer.') +
    q(
      'decorHall',
      'Decoration provided by hall?',
      'If Yes, customers see that you offer décor help. Decoration is an add-on — not included in hall rent.',
    ) +
    q('decorOutside', 'Outside decorators allowed?', 'If Yes, customers may hire their own decorators.');
  el('caterDec').querySelectorAll('input[type=radio]').forEach((r) => {
    r.onchange = () => {
      state.catering[r.name] = r.value;
    };
  });
}

function renderPkg3() {
  renderPkgSteps(3);
  el('slotPricing').innerHTML =
    SLOTS.map((sl) => {
      const p = state.prices[sl.id];
      return `<div class="slot"><h3>${esc(sl.label)} <span style="font-weight:600;color:var(--mut);font-size:12px">(${esc(
        sl.time,
      )})</span></h3><div class="two">
      <div class="fld"><label>Without AC (₹)</label><input type="number" data-slot="${sl.id}" data-ac="noAc" value="${p.noAc}"></div>
      <div class="fld"><label>With AC (₹)</label><input type="number" data-slot="${sl.id}" data-ac="ac" value="${p.ac}"></div></div></div>`;
    }).join('') +
    `<div class="slot"><h3>Additional Hours Charge</h3><div class="two">
      <div class="fld"><label>Without AC / hour</label><input type="number" id="extraNoAc" value="${state.prices.extraNoAc}"></div>
      <div class="fld"><label>With AC / hour</label><input type="number" id="extraAc" value="${state.prices.extraAc}"></div></div></div>`;
}

function capturePkg3() {
  el('slotPricing').querySelectorAll('[data-slot]').forEach((inp) => {
    state.prices[inp.getAttribute('data-slot')][inp.getAttribute('data-ac')] = +inp.value || 0;
  });
  state.prices.extraNoAc = +(el('extraNoAc') && el('extraNoAc').value) || 0;
  state.prices.extraAc = +(el('extraAc') && el('extraAc').value) || 0;
}

function renderPkg4() {
  renderPkgSteps(4);
  const p = state.payment;
  el('payPolicy').innerHTML = `
    <p class="lbl">ADVANCE PAYMENT</p>
    <label class="radio-row"><input type="radio" name="adv" value="fixed"${p.advanceType === 'fixed' ? ' checked' : ''}> Fixed amount</label>
    <div class="fld"><input type="number" id="advFixed" value="${p.advanceFixed}"></div>
    <label class="radio-row"><input type="radio" name="adv" value="pct"${p.advanceType === 'pct' ? ' checked' : ''}> Percentage of total</label>
    <div class="fld"><input type="number" id="advPct" value="${p.advancePct}"> %</div>
    <p class="lbl">FULL PAYMENT DUE</p>
    <div class="fld"><label>Days before event</label><input type="number" id="fullDue" value="${p.fullDueDays}"></div>
    <p class="lbl">CANCELLATION POLICY</p>
    <table class="cancel-table"><tr><th>If cancelled before</th><th>Deduct</th></tr>
    ${state.cancelRules.map((r) => `<tr><td>${esc(r.days)}</td><td>${r.pct}%</td></tr>`).join('')}
    </table>`;
}

function capturePkg2() {
  state.capacity = {
    seat: +el('seatCap').value || 0,
    dine: +el('dineCap').value || 0,
    car: +el('parkCar').value || 0,
    bike: +el('parkBike').value || 0,
    rooms: +el('rooms').value || 0,
  };
}

function capturePkg4() {
  const adv = document.querySelector('input[name=adv]:checked');
  state.payment.advanceType = adv && adv.value ? adv.value : 'fixed';
  state.payment.advanceFixed = +el('advFixed').value || 0;
  state.payment.advancePct = +el('advPct').value || 0;
  state.payment.fullDueDays = +el('fullDue').value || 7;
}

function renderPkg5() {
  renderPkgSteps(5);
  capturePkg2();
  capturePkg3();
  capturePkg4();
  const tags = state.events.map(function (id) {
    var c = EVENT_CATS.find(function (x) { return x.id === id; });
    return c ? c.label : id;
  });
  el('pkgReview').innerHTML = `
    <div class="sum"><div class="hd"><b>Event Categories</b><button type="button" class="see" data-to="pkg1">Edit</button></div><div class="tags">${tags
      .map((t) => `<span class="tag">${esc(t)}</span>`)
      .join('')}</div></div>
    <div class="sum"><div class="hd"><b>Venue Details</b><button type="button" class="see" data-to="pkg2">Edit</button></div>
      <p class="sub">Seating ${state.capacity.seat} · Dining ${state.capacity.dine} · Parking ${state.capacity.car} cars</p>
      <p class="sub" style="margin-top:8px"><b>Catering &amp; decoration (shown to customers — not in hall package):</b><br>${cateringReviewLines()
        .map((line) => esc(line))
        .join('<br>')}</p></div>
    <div class="sum"><div class="hd"><b>Pricing &amp; Time Slots</b><button type="button" class="see" data-to="pkg3">Edit</button></div>
      <p class="sub">Morning ₹${state.prices.morning.noAc.toLocaleString('en-IN')} / ₹${state.prices.morning.ac.toLocaleString(
    'en-IN',
  )} (AC)</p></div>
    <div class="sum"><div class="hd"><b>Payment &amp; Cancellation</b><button type="button" class="see" data-to="pkg4">Edit</button></div>
      <p class="sub">Advance ₹${state.payment.advanceFixed.toLocaleString('en-IN')} · Full due ${state.payment.fullDueDays} days before</p></div>`;
  el('pkgReview').querySelectorAll('[data-to]').forEach((b) => {
    b.onclick = () => {
      show(b.getAttribute('data-to'));
      if (b.getAttribute('data-to') === 'pkg1') renderPkg1();
      if (b.getAttribute('data-to') === 'pkg2') renderPkg2();
      if (b.getAttribute('data-to') === 'pkg3') renderPkg3();
      if (b.getAttribute('data-to') === 'pkg4') renderPkg4();
    };
  });
  el('savePkg').onclick = () => {
    savePkg();
    toast('Package saved on this device.');
    show('manage');
  };
}

function renderCalendar() {
  const days = [];
  for (let d = 1; d <= 31; d++) days.push(d);
  el('calGrid').innerHTML = days
    .map(
      (d) =>
        `<button type="button" class="${d === state.calDay ? 'on' : ''}" data-day="${d}">${d}</button>`,
    )
    .join('');
  el('calGrid').querySelectorAll('[data-day]').forEach((b) => {
    b.onclick = () => {
      state.calDay = +b.getAttribute('data-day');
      renderCalendar();
    };
  });
  el('daySlots').innerHTML = `
    <h2>${state.calDay} Dec 2026</h2>
    <div class="slot"><span class="pill ok">Available</span><h3>Morning (10:00 AM – 3:00 PM)</h3>
      <p class="sub">With AC ₹75,000 · Without AC ₹55,000</p><button class="btn ghost" type="button">Block Slot</button></div>
    <div class="slot"><span class="pill bad">Booked (Gixbee)</span><h3>Evening (5:00 PM – 11:00 PM)</h3>
      <p class="sub">Manage booking in Requests</p></div>`;
}

function renderBookSettings() {
  const windows = [3, 6, 9, 12, 18, 24];
  const notices = [
    { v: 0, l: 'Same Day' },
    { v: 1, l: '1 Day' },
    { v: 2, l: '2 Days' },
    { v: 3, l: '3 Days' },
    { v: 7, l: '7 Days' },
  ];
  el('bookWindow').innerHTML = windows
    .map((m) => `<button type="button" class="pick${state.bookWindowMonths === m ? ' on' : ''}" data-win="${m}">${m} Months</button>`)
    .join('');
  el('minNotice').innerHTML = notices
    .map((n) => `<button type="button" class="pick${state.minNoticeDays === n.v ? ' on' : ''}" data-notice="${n.v}">${n.l}</button>`)
    .join('');
  el('windowInfo').textContent = `Customers can book up to ${state.bookWindowMonths} months ahead from today.`;
  el('noticeInfo').textContent = `Customers can book at least ${state.minNoticeDays} day(s) before the event date.`;
  el('bookWindow').querySelectorAll('[data-win]').forEach((b) => {
    b.onclick = () => {
      state.bookWindowMonths = +b.getAttribute('data-win');
      renderBookSettings();
    };
  });
  el('minNotice').querySelectorAll('[data-notice]').forEach((b) => {
    b.onclick = () => {
      state.minNoticeDays = +b.getAttribute('data-notice');
      renderBookSettings();
    };
  });
}

function renderOwnerReq() {
  el('ownerReqBody').innerHTML = `
    <div class="sum"><b>Baptism · 25 Dec 2026</b><p class="sub">Morning · Without AC · 200 guests</p><p style="font-weight:900;font-size:18px;margin:8px 0">₹ 55,000</p></div>
    <p class="lbl">CUSTOMER</p>
    <p><b>Arun Kumar</b><br><span class="sub">+91 98765 43210</span></p>
    <p class="sub">Accept starts 24h advance payment window for the customer.</p>`;
  el('acceptReq').onclick = () => toast('Request accepted — customer sees Pending (pay advance).');
  el('rejectReq').onclick = () => toast('Request rejected.');
}

function showBootError(msg) {
  const box = el('bootError');
  if (!box) {
    alert(msg);
    return;
  }
  box.hidden = false;
  box.innerHTML =
    '<h1 style="color:#DC2626;font-size:20px">Demo did not start</h1><p>' +
    esc(msg) +
    '</p><p>Open <b>' +
    DEMO_FILE +
    '</b> (full file with JavaScript inside). Hard refresh Ctrl+Shift+R.</p>';
}

function bindOwnerEvents() {
  document.querySelectorAll('[data-to]').forEach((b) => {
    b.addEventListener('click', () => {
      const id = b.getAttribute('data-to');
      if (id === 'pkg2') renderPkg2();
      if (id === 'pkg3') {
        capturePkg2();
        renderPkg3();
      }
      if (id === 'pkg4') {
        capturePkg3();
        renderPkg4();
      }
      if (id === 'pkg5') {
        capturePkg4();
        renderPkg5();
      }
      if (id === 'bookSettings') renderBookSettings();
      show(id);
    });
  });
  const saveBs = el('saveBookSettings');
  if (saveBs) {
    saveBs.onclick = () => {
      savePkg();
      toast('Booking settings saved.');
      show('manage');
    };
  }
}

function boot() {
  try {
    if (!el('manageMenu')) {
      throw new Error('Missing #manageMenu — download DOWNLOAD-gixbee-hall-owner.html (full file).');
    }
    loadPkg();
    renderManage();
    bindOwnerEvents();
    var tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Working demo ' + OWNER_BUILD + ' — if menu is empty, open via Chrome or run: python3 -m http.server 8765';
    }
    var err = el('bootError');
    if (err) err.hidden = true;
  } catch (err) {
    console.error(err);
    showBootError(err.message || String(err));
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
