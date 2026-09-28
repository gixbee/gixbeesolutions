const OWNER_BUILD = '2026-09-28-hall-owner-v11';
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
  { id: 'placeholder', title: 'Edit Business Details', sub: 'Description, location (business name is fixed at listing)' },
  { id: 'placeholder', title: 'Delete Business', sub: 'Remove permanently from Gixbee', cls: 'danger' },
];

const state = {
  businessName: 'Vijaya Convention Center',
  useHallName: true,
  hallName: 'Tiffle',
  activeHallId: 'h1',
  hallSetupComplete: false,
  plannedHallCount: 2,
  parkingEditOpen: false,
  commonParking: { car: 80, bike: 120 },
  halls: [],
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
  normalizeNames();
}
function normalizeNames() {
  if (!state.businessName) state.businessName = 'Vijaya Convention Center';
  state.useHallName = !!state.useHallName;
  if (!state.useHallName) {
    state.hallName = '';
    return;
  }
  state.hallName = String(state.hallName || '').trim();
}
function customerHallName() {
  if (!state.useHallName || !state.hallName) return '';
  return state.hallName;
}
function syncHallNameUi() {
  const show = !!state.useHallName;
  ['manageHallNameWrap', 'hallNamePkgWrap'].forEach(function (id) {
    const w = el(id);
    if (w) w.style.display = show ? 'block' : 'none';
  });
  ['manageUseHallName', 'useHallNamePkg'].forEach(function (id) {
    const cb = el(id);
    if (cb) cb.checked = show;
  });
  const hallIn = el('manageHallName');
  if (hallIn && document.activeElement !== hallIn) hallIn.value = state.hallName;
  const pkgIn = el('hallNameInput');
  if (pkgIn && document.activeElement !== pkgIn) pkgIn.value = state.hallName;
}
function captureNameFields() {
  const manageCb = el('manageUseHallName');
  const pkgCb = el('useHallNamePkg');
  if (manageCb && document.activeElement === manageCb) {
    state.useHallName = manageCb.checked;
  } else if (pkgCb && document.activeElement === pkgCb) {
    state.useHallName = pkgCb.checked;
  } else if (manageCb) {
    state.useHallName = manageCb.checked;
  } else if (pkgCb) {
    state.useHallName = pkgCb.checked;
  }
  if (!state.useHallName) {
    state.hallName = '';
    syncHallNameUi();
    return;
  }
  const hallIn = el('hallNameInput');
  const manageIn = el('manageHallName');
  if (hallIn && (el('pkg2').classList.contains('on') || document.activeElement === hallIn)) {
    state.hallName = hallIn.value.trim();
  } else if (manageIn) {
    state.hallName = manageIn.value.trim();
  }
  syncHallNameUi();
}
function renderManageHeader() {
  const sub = el('manageSubLine');
  if (sub) {
    var hallPart = customerHallName();
    sub.textContent = hallPart
      ? state.businessName + ' · Hall: ' + hallPart + ' · Service · Hall'
      : state.businessName + ' · Service · Hall';
  }
  const bizRo = el('bizNameRo');
  if (bizRo) bizRo.value = state.businessName;
  const bizPkg = el('bizNamePkg');
  if (bizPkg) bizPkg.value = state.businessName;
  syncHallNameUi();
}
function savePkg() {
  localStorage.setItem(PKG_KEY, JSON.stringify(state));
  syncActiveHallFromState();
}

function activeHall() {
  return state.halls.find(function (h) { return h.id === state.activeHallId; }) || state.halls[0];
}

function loadActiveHallIntoState() {
  const h = activeHall();
  if (!h) return;
  state.useHallName = !!h.useHallName;
  state.hallName = h.useHallName ? String(h.hallName || '').trim() : '';
}

function syncActiveHallFromState() {
  const h = activeHall();
  if (!h) return;
  h.useHallName = !!state.useHallName;
  h.hallName = state.useHallName ? String(state.hallName || '').trim() : '';
}

function parkingDisplay() {
  const multi = state.plannedHallCount > 1 || state.halls.length > 1;
  if (multi) {
    return { title: 'Common parking (shared by all halls)', car: state.commonParking.car, bike: state.commonParking.bike, common: true };
  }
  return { title: 'Parking (this hall)', car: state.capacity.car, bike: state.capacity.bike, common: false };
}

function setHallBizDisabled(disabled) {
  state.parkingEditOpen = !!disabled;
  const zone = el('hallBizDisabledZone');
  if (zone) zone.classList.toggle('biz-home-disabled', !!disabled);
  const addBtn = el('addHallBtn');
  if (addBtn) addBtn.disabled = !!disabled;
}

function renderSetupScreen() {
  const t = el('setupBizTitle');
  if (t) t.textContent = state.businessName;
  const countIn = el('hallCountInput');
  if (countIn) countIn.value = state.plannedHallCount || 2;
  const sec = el('setupParkingSection');
  const saveBtn = el('setupSave');
  if (sec) sec.hidden = true;
  if (saveBtn) saveBtn.disabled = true;
}

function revealSetupParking() {
  const count = Math.max(1, +(el('hallCountInput') && el('hallCountInput').value) || 1);
  state.plannedHallCount = count;
  const sec = el('setupParkingSection');
  const lbl = el('setupParkingLbl');
  const hint = el('setupParkingHint');
  if (sec) sec.hidden = false;
  if (lbl) lbl.textContent = count > 1 ? 'COMMON PARKING' : 'PARKING (SINGLE HALL)';
  if (hint) {
    hint.textContent =
      count > 1
        ? 'One shared car and bike count for all ' + count + ' halls.'
        : 'Fixed parking for this hall only (not shared).';
  }
  if (count > 1) {
    if (el('setupParkCar')) el('setupParkCar').value = state.commonParking.car;
    if (el('setupParkBike')) el('setupParkBike').value = state.commonParking.bike;
  } else {
    if (el('setupParkCar')) el('setupParkCar').value = state.capacity.car;
    if (el('setupParkBike')) el('setupParkBike').value = state.capacity.bike;
  }
  if (el('setupSave')) el('setupSave').disabled = false;
}

function initHallsFromSetup(count) {
  state.halls = [];
  for (var i = 0; i < count; i++) {
    state.halls.push({
      id: 'h' + (i + 1),
      useHallName: i === 0 && state.useHallName,
      hallName: i === 0 ? state.hallName : '',
      requests: i === 0 ? 2 : 0,
    });
  }
  state.activeHallId = state.halls[0].id;
  loadActiveHallIntoState();
}

function openHallFromDashboard() {
  state.businessName = 'Vijaya Convention Center';
  if (state.hallSetupComplete && state.halls.length) {
    renderHallBizHome();
    show('hallBizHome');
    return;
  }
  renderSetupScreen();
  show('hallSetup');
}

function renderParkingSummary() {
  const p = parkingDisplay();
  const title = el('parkingSummaryTitle');
  const text = el('parkingSummaryText');
  if (title) title.textContent = p.title;
  if (text) text.textContent = '🚗 Cars: ' + p.car + ' · 🏍 Bikes: ' + p.bike;
  const editWrap = el('parkingEditWrap');
  if (editWrap && editWrap.hidden) {
    const carIn = el('editParkCar');
    const bikeIn = el('editParkBike');
    if (carIn) carIn.value = p.car;
    if (bikeIn) bikeIn.value = p.bike;
  }
  setHallBizDisabled(editWrap && !editWrap.hidden);
}

function renderHallCards() {
  const root = el('hallListCards');
  if (!root) return;
  root.innerHTML = state.halls
    .map(function (h) {
      const sub = h.useHallName && h.hallName ? esc(h.hallName) : esc(state.businessName);
      const req = h.requests
        ? '<span class="pill bad" style="margin-left:6px">' + h.requests + ' requests</span>'
        : '';
      return (
        '<div class="hall-card">' +
        '<b>' +
        esc(state.businessName) +
        '</b>' +
        '<div class="hall-sub">Hall: ' +
        sub +
        req +
        '</div>' +
        '<div class="hall-actions">' +
        '<button type="button" class="pick" data-hall-act="cal" data-hid="' +
        h.id +
        '">Calendar</button>' +
        '<button type="button" class="pick" data-hall-act="req" data-hid="' +
        h.id +
        '">Requests</button>' +
        '<button type="button" class="pick on" data-hall-act="mgr" data-hid="' +
        h.id +
        '">Manage</button>' +
        '</div></div>'
      );
    })
    .join('');
  root.querySelectorAll('[data-hall-act]').forEach(function (btn) {
    btn.onclick = function () {
      if (state.parkingEditOpen) return;
      state.activeHallId = btn.getAttribute('data-hid');
      loadActiveHallIntoState();
      const act = btn.getAttribute('data-hall-act');
      if (act === 'mgr') {
        renderManageHeader();
        renderManage();
        show('manage');
        return;
      }
      if (act === 'cal') {
        renderCalendar();
        show('calendar');
        return;
      }
      if (act === 'req') {
        renderOwnerReq();
        show('ownerReq');
      }
    };
  });
}

function renderHallBizHome() {
  const bizTitle = el('bizHomeTitle');
  if (bizTitle) bizTitle.textContent = state.businessName;
  renderParkingSummary();
  renderHallCards();
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
  renderManageHeader();
  renderHallCards();
  renderParkingSummary();
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
  renderManageHeader();
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
      'If Yes, customers see that you offer catering. Catering is an add-on — not included in hall rent.',
    ) +
    q('outside', 'Outside catering allowed?', 'If Yes, customers may bring their own caterer.') +
    q(
      'decorHall',
      'Decoration provided by hall?',
      'If Yes, customers see that you offer decoration. Decoration is an add-on — not included in hall rent.',
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
  captureNameFields();
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
      <p class="sub"><b>${esc(state.businessName)}</b>${
        customerHallName()
          ? ' · Hall: <b>' + esc(customerHallName()) + '</b>'
          : ' · <span class="sub">No separate hall name</span>'
      }</p>
      <p class="sub">Seating ${state.capacity.seat} · Dining ${state.capacity.dine} · Parking ${state.capacity.car} cars</p>
      <p class="sub" style="margin-top:8px"><b>Catering &amp; decoration (on your profile — add-ons, not in hall slot rent):</b><br>${cateringReviewLines()
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
    capturePkg2();
    savePkg();
    renderManageHeader();
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
  const saveHall = el('saveHallName');
  if (saveHall) {
    saveHall.onclick = () => {
      captureNameFields();
      syncActiveHallFromState();
      savePkg();
      renderManageHeader();
      renderHallCards();
      toast('Saved — customers see business name' + (customerHallName() ? ' and hall name ' + customerHallName() : ' only') + '.');
    };
  }
  const editPark = el('editParkingBtn');
  if (editPark) {
    editPark.onclick = function () {
      const wrap = el('parkingEditWrap');
      if (!wrap || state.parkingEditOpen) return;
      wrap.hidden = false;
      const p = parkingDisplay();
      if (el('editParkCar')) el('editParkCar').value = p.car;
      if (el('editParkBike')) el('editParkBike').value = p.bike;
      editPark.disabled = true;
      setHallBizDisabled(true);
    };
  }
  const savePark = el('saveParkingBtn');
  if (savePark) {
    savePark.onclick = function () {
      const car = +(el('editParkCar') && el('editParkCar').value) || 0;
      const bike = +(el('editParkBike') && el('editParkBike').value) || 0;
      const p = parkingDisplay();
      if (p.common) {
        state.commonParking.car = car;
        state.commonParking.bike = bike;
      } else {
        state.capacity.car = car;
        state.capacity.bike = bike;
      }
      savePkg();
      if (el('parkingEditWrap')) el('parkingEditWrap').hidden = true;
      if (el('editParkingBtn')) el('editParkingBtn').disabled = false;
      setHallBizDisabled(false);
      renderParkingSummary();
      renderHallBizHome();
      toast('Parking updated.');
    };
  }
  const cancelPark = el('cancelParkingBtn');
  if (cancelPark) {
    cancelPark.onclick = function () {
      if (el('parkingEditWrap')) el('parkingEditWrap').hidden = true;
      if (el('editParkingBtn')) el('editParkingBtn').disabled = false;
      setHallBizDisabled(false);
      renderParkingSummary();
    };
  }
  const addHall = el('addHallBtn');
  if (addHall) {
    addHall.onclick = function () {
      if (state.parkingEditOpen) return;
      state.halls.push({
        id: 'h' + Date.now(),
        useHallName: false,
        hallName: '',
        requests: 0,
      });
      state.plannedHallCount = state.halls.length;
      savePkg();
      renderHallBizHome();
      toast('Hall added — open Manage to set pricing.');
    };
  }
  const dashHall = el('dashHallManage');
  if (dashHall) dashHall.onclick = function () { openHallFromDashboard(); };
  const dashCat = el('dashCatManage');
  if (dashCat) dashCat.onclick = function () { toast('Catering manage — separate module in full app.'); };
  const dashRent = el('dashRentManage');
  if (dashRent) dashRent.onclick = function () { toast('Rental manage — separate module in full app.'); };
  const hallCountOk = el('hallCountOk');
  if (hallCountOk) hallCountOk.onclick = function () { revealSetupParking(); };
  const setupCancel = el('setupCancel');
  if (setupCancel) setupCancel.onclick = function () { show('lmbDashboard'); };
  const setupBack = el('setupBackDash');
  if (setupBack) setupBack.onclick = function () { show('lmbDashboard'); };
  const setupSave = el('setupSave');
  if (setupSave) {
    setupSave.onclick = function () {
      const count = Math.max(1, +(el('hallCountInput') && el('hallCountInput').value) || 1);
      const car = +(el('setupParkCar') && el('setupParkCar').value) || 0;
      const bike = +(el('setupParkBike') && el('setupParkBike').value) || 0;
      state.plannedHallCount = count;
      if (count > 1) {
        state.commonParking = { car: car, bike: bike };
      } else {
        state.capacity.car = car;
        state.capacity.bike = bike;
      }
      initHallsFromSetup(count);
      state.hallSetupComplete = true;
      savePkg();
      renderHallBizHome();
      show('hallBizHome');
      toast('Saved — add hall names and open Manage on each hall.');
    };
  }
  const bizHomeToDash = el('bizHomeToDash');
  if (bizHomeToDash) bizHomeToDash.onclick = function () { show('lmbDashboard'); };
  const backBiz = el('backToBizHalls');
  if (backBiz) {
    backBiz.onclick = function () {
      captureNameFields();
      syncActiveHallFromState();
      savePkg();
      renderHallBizHome();
      show('hallBizHome');
    };
  }
  ['manageUseHallName', 'useHallNamePkg'].forEach(function (id) {
    const cb = el(id);
    if (!cb) return;
    cb.onchange = function () {
      state.useHallName = cb.checked;
      if (!state.useHallName) state.hallName = '';
      syncHallNameUi();
      var other = id === 'manageUseHallName' ? el('useHallNamePkg') : el('manageUseHallName');
      if (other) other.checked = state.useHallName;
    };
  });
}

function boot() {
  try {
    if (!el('manageMenu')) {
      throw new Error('Missing #manageMenu — download DOWNLOAD-gixbee-hall-owner.html (full file).');
    }
    loadPkg();
    if (!state.commonParking) state.commonParking = { car: 80, bike: 120 };
    if (state.hallSetupComplete && (!state.halls || !state.halls.length)) {
      initHallsFromSetup(state.plannedHallCount || 2);
    }
    if (!state.halls) state.halls = [];
    if (!state.activeHallId && state.halls[0]) state.activeHallId = state.halls[0].id;
    if (state.halls.length) loadActiveHallIntoState();
    renderSetupScreen();
    renderHallBizHome();
    renderManage();
    bindOwnerEvents();
    show('lmbDashboard');
    var tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Working demo ' + OWNER_BUILD + ' — tap Vijaya Convention Center → Manage';
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
