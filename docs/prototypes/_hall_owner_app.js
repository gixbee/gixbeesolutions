const OWNER_BUILD = '2026-09-28-hall-owner-v17';
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

const SLOT_TEMPLATES = [
  { id: 'morning', label: 'Morning', hallFrom: '10:00', hallTo: '15:00' },
  { id: 'evening', label: 'Evening', hallFrom: '17:00', hallTo: '23:00' },
  { id: 'fullday', label: 'Full Day', hallFrom: '09:00', hallTo: '21:00', acMode: 'limited', acHours: 5, acFrom: '12:00', acTo: '17:00' },
];

function ensureSlotOffers() {
  const prices = state.prices || {};
  if (!state.slotOffers || !state.slotOffers.length) {
    state.slotOffers = SLOT_TEMPLATES.map(function (t) {
      const p = prices[t.id] || {};
      return {
        id: t.id,
        label: t.label,
        enabled: true,
        hallFrom: t.hallFrom,
        hallTo: t.hallTo,
        offerNoAc: true,
        offerAc: true,
        priceNoAc: p.noAc != null ? p.noAc : 55000,
        priceAc: p.ac != null ? p.ac : t.id === 'fullday' ? 200000 : 75000,
        acMode: t.acMode || 'full',
        acFrom: t.acFrom || t.hallFrom,
        acTo: t.acTo || t.hallTo,
        acHours: t.acHours || 0,
      };
    });
  }
  SLOT_TEMPLATES.forEach(function (t) {
    if (
      state.slotOffers.find(function (o) {
        return o.id === t.id;
      })
    ) {
      return;
    }
    const p = prices[t.id] || {};
    state.slotOffers.push({
      id: t.id,
      label: t.label,
      enabled: false,
      hallFrom: t.hallFrom,
      hallTo: t.hallTo,
      offerNoAc: true,
      offerAc: true,
      priceNoAc: p.noAc || 55000,
      priceAc: p.ac || 75000,
      acMode: 'full',
      acFrom: t.hallFrom,
      acTo: t.hallTo,
      acHours: 0,
    });
  });
  state.slotOffers.forEach(function (o) {
    if (o.acMode == null) o.acMode = 'full';
    if (o.acHours == null) o.acHours = 0;
    if (!o.hallFrom) o.hallFrom = '09:00';
    if (!o.hallTo) o.hallTo = '17:00';
    if (!o.acFrom) o.acFrom = o.hallFrom;
    if (!o.acTo) o.acTo = o.hallTo;
    if (o.offerNoAc == null) o.offerNoAc = true;
    if (o.offerAc == null) o.offerAc = true;
    if (o.enabled == null) o.enabled = true;
  });
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

function acUsageSummary(o) {
  if (!o.offerAc) return '';
  if (o.acMode === 'full') return ' · AC for full hall window';
  if (o.acHours) return ' · AC ' + o.acHours + ' hours in window';
  if (o.acFrom && o.acTo) return ' · AC ' + formatTimeRange(o.acFrom, o.acTo);
  return ' · AC limited hours';
}

function slotReviewLines() {
  ensureSlotOffers();
  return state.slotOffers
    .filter(function (o) {
      return o.enabled;
    })
    .map(function (o) {
      const win = formatTimeRange(o.hallFrom, o.hallTo);
      const parts = [];
      if (o.offerNoAc) parts.push('Without AC ₹' + o.priceNoAc.toLocaleString('en-IN'));
      if (o.offerAc) parts.push('With AC ₹' + o.priceAc.toLocaleString('en-IN') + acUsageSummary(o));
      return o.label + ' (' + win + '): ' + parts.join(' · ');
    });
}

const MANAGE_MENU = [
  { id: 'calendar', title: 'Calendar', sub: 'Availability and blocked dates' },
  { id: 'pkg1', title: 'Price & packages', sub: 'Slots, pricing, cancellation policy' },
  { id: 'ownerReq', title: 'Booking requests', sub: 'Accept or decline customer bookings', dot: true },
  { id: 'placeholder', title: 'Operators', sub: 'Who can manage this hall' },
  { id: 'deleteHall', title: 'Delete hall', sub: 'Remove this hall from the business', cls: 'danger' },
];

const state = {
  businessName: 'Vijaya Convention Center',
  useHallName: true,
  hallName: 'Tiffle',
  activeHallId: 'h1',
  hallSetupComplete: false,
  plannedHallCount: 2,
  parkingEditOpen: false,
  openedFromAddHall: false,
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
  ensureSlotOffers();
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
  if (state.hallSetupComplete) {
    return {
      title: multi ? 'Common parking (shared by all halls)' : 'Shared parking',
      car: state.commonParking.car,
      bike: state.commonParking.bike,
      common: true,
    };
  }
  return {
    title: multi ? 'Common parking (shared by all halls)' : 'Shared parking',
    car: state.commonParking.car,
    bike: state.commonParking.bike,
    common: true,
  };
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
  const countBlock = el('setupHallCountBlock');
  const intro = el('setupIntroSub');
  const sec = el('setupParkingSection');
  const actions = el('setupActionsWrap');
  if (countBlock) countBlock.hidden = false;
  if (intro) intro.hidden = false;
  if (sec) sec.hidden = true;
  if (actions) {
    actions.hidden = true;
    actions.style.display = 'none';
  }
}

function revealSetupParking() {
  const count = Math.max(1, +(el('hallCountInput') && el('hallCountInput').value) || 1);
  state.plannedHallCount = count;
  const countBlock = el('setupHallCountBlock');
  const intro = el('setupIntroSub');
  if (countBlock) countBlock.hidden = true;
  if (intro) intro.hidden = true;
  const sec = el('setupParkingSection');
  const lbl = el('setupParkingLbl');
  const hint = el('setupParkingHint');
  if (sec) sec.hidden = false;
  if (count > 1) {
    if (lbl) lbl.textContent = 'COMMON PARKING (SHARED)';
    if (hint) hint.textContent = 'One shared car and bike count for all ' + count + ' halls.';
  } else {
    if (lbl) lbl.textContent = 'SHARED PARKING';
    if (hint) hint.textContent = 'Car and bike parking for your hall (shown to customers).';
  }
  if (el('setupParkCar')) el('setupParkCar').value = state.commonParking.car;
  if (el('setupParkBike')) el('setupParkBike').value = state.commonParking.bike;
  const actions = el('setupActionsWrap');
  if (actions) {
    actions.hidden = false;
    actions.style.display = 'grid';
  }
}

function initHallsFromSetup(count) {
  state.plannedHallCount = count;
  state.halls = [];
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
        openManageScreen(false);
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
  const parkWrap = el('parkingBlockWrap');
  if (parkWrap) parkWrap.hidden = !state.hallSetupComplete;
  renderParkingSummary();
  renderHallCards();
}

function openManageScreen(fromAddHall) {
  state.openedFromAddHall = !!fromAddHall;
  renderManageHeader();
  renderManage();
  show('manage');
}

function renderManageFooter() {
  const foot = el('manageSaveFooter');
  if (foot) foot.hidden = !state.openedFromAddHall;
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
  renderManageFooter();
  el('manageMenu').innerHTML = MANAGE_MENU.map((m) => {
    const cls = m.cls ? ' ' + m.cls.split(' ').join(' ') : '';
    const dot = m.dot ? '<span class="dot"></span>' : '';
    return `<button type="button" class="mrow${cls}" data-go="${m.id}"><b>${esc(m.title)}${dot}</b><span>${esc(m.sub)}</span></button>`;
  }).join('');
  el('manageMenu').querySelectorAll('[data-go]').forEach((btn) => {
    btn.onclick = () => {
      const id = btn.getAttribute('data-go');
      if (id === 'deleteHall') {
        if (state.halls.length <= 1) {
          toast('Keep at least one hall on this business.');
          return;
        }
        state.halls = state.halls.filter(function (h) { return h.id !== state.activeHallId; });
        state.activeHallId = state.halls[0].id;
        loadActiveHallIntoState();
        state.openedFromAddHall = false;
        savePkg();
        renderHallBizHome();
        show('hallBizHome');
        toast('Hall deleted.');
        return;
      }
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

function renderSlotOfferRow(o) {
  const acFull = o.acMode !== 'limited';
  return (
    '<div class="slot' +
    (o.enabled ? '' : ' slot-disabled') +
    '" data-offer-id="' +
    esc(o.id) +
    '">' +
    '<label class="radio-row" style="margin:0"><input type="checkbox" data-field="enabled"' +
    (o.enabled ? ' checked' : '') +
    '> <b>Offer ' +
    esc(o.label) +
    ' slot</b></label>' +
    '<div class="slot-body"' +
    (o.enabled ? '' : ' style="display:none"') +
    '>' +
    '<p class="lbl" style="margin-top:10px">Hall booking window</p>' +
    '<div class="two">' +
    '<div class="fld"><label>From</label><input type="time" data-field="hallFrom" value="' +
    esc(o.hallFrom) +
    '"></div>' +
    '<div class="fld"><label>To</label><input type="time" data-field="hallTo" value="' +
    esc(o.hallTo) +
    '"></div></div>' +
    '<p class="lbl">Pricing options for customers</p>' +
    '<div class="price-row"><label><input type="checkbox" data-field="offerNoAc"' +
    (o.offerNoAc ? ' checked' : '') +
    '> Without AC ₹</label><input type="number" data-field="priceNoAc" min="0" value="' +
    o.priceNoAc +
    '"' +
    (o.offerNoAc ? '' : ' disabled') +
    '></div>' +
    '<div class="price-row"><label><input type="checkbox" data-field="offerAc"' +
    (o.offerAc ? ' checked' : '') +
    '> With AC ₹</label><input type="number" data-field="priceAc" min="0" value="' +
    o.priceAc +
    '"' +
    (o.offerAc ? '' : ' disabled') +
    '></div>' +
    '<div class="ac-usage"' +
    (o.offerAc ? '' : ' hidden') +
    '>' +
    '<p class="lbl" style="margin-top:0">AC usage (With AC package)</p>' +
    '<p class="sub" style="margin:0 0 8px">Example: full-day hall 12 hours, AC only 5 hours — set hours or exact AC window below.</p>' +
    '<label class="radio-row"><input type="radio" name="acMode_' +
    esc(o.id) +
    '" value="full"' +
    (acFull ? ' checked' : '') +
    '> AC for full hall window</label>' +
    '<label class="radio-row"><input type="radio" name="acMode_' +
    esc(o.id) +
    '" value="limited"' +
    (!acFull ? ' checked' : '') +
    '> AC for limited time only</label>' +
    '<div class="ac-limited-fields"' +
    (acFull || !o.offerAc ? ' hidden' : '') +
    '>' +
    '<div class="fld"><label>AC hours included</label><input type="number" data-field="acHours" min="0" step="0.5" value="' +
    (o.acHours || '') +
    '" placeholder="e.g. 5"><small class="sub">Hours of AC in this booking window</small></div>' +
    '<p class="sub" style="margin:8px 0 4px">Optional exact AC window (within hall hours):</p>' +
    '<div class="two">' +
    '<div class="fld"><label>AC from</label><input type="time" data-field="acFrom" value="' +
    esc(o.acFrom) +
    '"></div>' +
    '<div class="fld"><label>AC to</label><input type="time" data-field="acTo" value="' +
    esc(o.acTo) +
    '"></div></div></div></div></div></div>'
  );
}

function attachSlotPricingHandlers() {
  const root = el('slotPricing');
  if (!root) return;
  root.querySelectorAll('.slot[data-offer-id]').forEach(function (row) {
    const id = row.getAttribute('data-offer-id');
    function refresh() {
      const enabled = row.querySelector('[data-field=enabled]').checked;
      row.classList.toggle('slot-disabled', !enabled);
      const body = row.querySelector('.slot-body');
      if (body) body.style.display = enabled ? 'block' : 'none';
      const offerAc = row.querySelector('[data-field=offerAc]').checked;
      const offerNoAc = row.querySelector('[data-field=offerNoAc]').checked;
      const acWrap = row.querySelector('.ac-usage');
      if (acWrap) acWrap.hidden = !offerAc;
      const noIn = row.querySelector('[data-field=priceNoAc]');
      const acIn = row.querySelector('[data-field=priceAc]');
      if (noIn) noIn.disabled = !offerNoAc;
      if (acIn) acIn.disabled = !offerAc;
      const limited = row.querySelector('input[name=acMode_' + id + '][value=limited]');
      const limWrap = row.querySelector('.ac-limited-fields');
      if (limWrap && limited) limWrap.hidden = !offerAc || !limited.checked;
    }
    row.querySelectorAll('input').forEach(function (inp) {
      inp.addEventListener('change', refresh);
    });
    refresh();
  });
}

function validateSlotOffers() {
  ensureSlotOffers();
  const enabled = state.slotOffers.filter(function (o) {
    return o.enabled;
  });
  if (!enabled.length) {
    toast('Enable at least one time slot (Morning, Evening, or Full Day).');
    return false;
  }
  for (let i = 0; i < enabled.length; i++) {
    const o = enabled[i];
    if (!o.offerNoAc && !o.offerAc) {
      toast(o.label + ': turn on Without AC and/or With AC pricing.');
      return false;
    }
    if (o.offerAc && o.acMode === 'limited' && !o.acHours && !(o.acFrom && o.acTo)) {
      toast(o.label + ': set AC hours or AC from/to for limited AC usage.');
      return false;
    }
  }
  return true;
}

function renderPkg3() {
  renderPkgSteps(3);
  ensureSlotOffers();
  el('slotPricing').innerHTML =
    state.slotOffers.map(renderSlotOfferRow).join('') +
    '<div class="slot"><h3>Additional hours charge</h3><p class="sub" style="margin:0 0 10px">If a booking runs longer than the slot window.</p><div class="two">' +
    '<div class="fld"><label>Without AC / hour</label><input type="number" id="extraNoAc" value="' +
    (state.prices.extraNoAc || 0) +
    '"></div>' +
    '<div class="fld"><label>With AC / hour</label><input type="number" id="extraAc" value="' +
    (state.prices.extraAc || 0) +
    '"></div></div></div>';
  attachSlotPricingHandlers();
}

function capturePkg3() {
  ensureSlotOffers();
  const root = el('slotPricing');
  if (!root) return;
  root.querySelectorAll('.slot[data-offer-id]').forEach(function (row) {
    const id = row.getAttribute('data-offer-id');
    const o = state.slotOffers.find(function (x) {
      return x.id === id;
    });
    if (!o) return;
    o.enabled = !!row.querySelector('[data-field=enabled]').checked;
    o.hallFrom = row.querySelector('[data-field=hallFrom]').value || '09:00';
    o.hallTo = row.querySelector('[data-field=hallTo]').value || '17:00';
    o.offerNoAc = !!row.querySelector('[data-field=offerNoAc]').checked;
    o.offerAc = !!row.querySelector('[data-field=offerAc]').checked;
    o.priceNoAc = +row.querySelector('[data-field=priceNoAc]').value || 0;
    o.priceAc = +row.querySelector('[data-field=priceAc]').value || 0;
    const modeEl = row.querySelector('input[name=acMode_' + id + ']:checked');
    o.acMode = modeEl && modeEl.value === 'limited' ? 'limited' : 'full';
    o.acFrom = row.querySelector('[data-field=acFrom]').value || o.hallFrom;
    o.acTo = row.querySelector('[data-field=acTo]').value || o.hallTo;
    o.acHours = +row.querySelector('[data-field=acHours]').value || 0;
    if (!state.prices[o.id]) state.prices[o.id] = {};
    state.prices[o.id].noAc = o.priceNoAc;
    state.prices[o.id].ac = o.priceAc;
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
    car: state.capacity.car,
    bike: state.capacity.bike,
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
      <p class="sub">Seating ${state.capacity.seat} · Dining ${state.capacity.dine}</p>
      <p class="sub">Parking: 🚗 ${state.commonParking.car} cars · 🏍 ${state.commonParking.bike} bikes (shared — edit on Halls page)</p>
      <p class="sub" style="margin-top:8px"><b>Catering &amp; decoration (on your profile — add-ons, not in hall slot rent):</b><br>${cateringReviewLines()
        .map((line) => esc(line))
        .join('<br>')}</p></div>
    <div class="sum"><div class="hd"><b>Pricing &amp; Time Slots</b><button type="button" class="see" data-to="pkg3">Edit</button></div>
      ${slotReviewLines()
        .map(function (line) {
          return '<p class="sub">' + esc(line) + '</p>';
        })
        .join('')}</div>
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
        if (!validateSlotOffers()) return;
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
      const id = 'h' + Date.now();
      state.halls.push({
        id: id,
        useHallName: false,
        hallName: '',
        requests: 0,
      });
      state.activeHallId = id;
      state.useHallName = false;
      state.hallName = '';
      loadActiveHallIntoState();
      openManageScreen(true);
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
      state.plannedHallCount = count;
      state.commonParking = {
        car: +(el('setupParkCar') && el('setupParkCar').value) || 0,
        bike: +(el('setupParkBike') && el('setupParkBike').value) || 0,
      };
      initHallsFromSetup(count);
      state.hallSetupComplete = true;
      savePkg();
      renderHallBizHome();
      show('hallBizHome');
      toast(count > 1 ? 'Saved — common parking set. Use + Add hall for each hall.' : 'Saved — use + Add hall to set up your hall.');
    };
  }
  const saveNewHall = el('saveNewHallBtn');
  if (saveNewHall) {
    saveNewHall.onclick = function () {
      captureNameFields();
      syncActiveHallFromState();
      state.openedFromAddHall = false;
      savePkg();
      renderManageFooter();
      renderHallBizHome();
      show('hallBizHome');
      toast('Hall saved.');
    };
  }
  const bizHomeToDash = el('bizHomeToDash');
  if (bizHomeToDash) bizHomeToDash.onclick = function () { show('lmbDashboard'); };
  const backBiz = el('backToBizHalls');
  if (backBiz) {
    backBiz.onclick = function () {
      captureNameFields();
      syncActiveHallFromState();
      state.openedFromAddHall = false;
      savePkg();
      renderManageFooter();
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
    ensureSlotOffers();
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
