const OWNER_BUILD = '2026-09-28-hall-owner-v47';
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

const FACILITY_ICONS = {
  AC: '❄',
  'Generator / Power Backup': '⚡',
  'Chairs & Tables': '🪑',
  Stage: '🎭',
  'Sound System': '🔊',
  Restrooms: '🚻',
  Lift: '🛗',
};

const SLOT_TEMPLATES = [
  { id: 'morning', label: 'Morning', hallFrom: '10:00', hallTo: '15:00' },
  { id: 'evening', label: 'Evening', hallFrom: '17:00', hallTo: '23:00' },
  { id: 'fullday', label: 'Full Day', hallFrom: '09:00', hallTo: '21:00', acMode: 'limited', acLimitKind: 'flexible', acHours: 5 },
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
        acLimitKind: t.acLimitKind || 'flexible',
        acFrom: '',
        acTo: '',
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
      acLimitKind: 'flexible',
      acFrom: '',
      acTo: '',
      acHours: 0,
    });
  });
  state.slotOffers.forEach(function (o) {
    if (o.acMode == null) o.acMode = 'full';
    if (o.acHours == null) o.acHours = 0;
    if (!o.hallFrom) o.hallFrom = '09:00';
    if (!o.hallTo) o.hallTo = '17:00';
    if (o.acFrom == null) o.acFrom = '';
    if (o.acTo == null) o.acTo = '';
    if (o.acLimitKind === 'hours') o.acLimitKind = 'flexible';
    if (o.acLimitKind == null) {
      if (o.acFrom && o.acTo) o.acLimitKind = 'fixed';
      else o.acLimitKind = 'flexible';
    }
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
  if (o.acLimitKind === 'fixed' && o.acFrom && o.acTo) {
    return ' · ' + (o.acHours || '?') + 'h AC, fixed ' + formatTimeRange(o.acFrom, o.acTo);
  }
  if (o.acHours) return ' · ' + o.acHours + 'h AC included (timing with hall management)';
  return ' · AC limited';
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
  { id: 'calendar', title: 'Calendar', sub: 'Availability and blocked dates', icon: '📅', ico: 'cal' },
  { id: 'pkg1', title: 'Price & packages', sub: 'Slots, pricing, cancellation policy', icon: '₹', ico: 'pkg' },
  { id: 'ownerReq', title: 'Booking requests', sub: 'Accept or decline customer bookings', dot: true, icon: '💬', ico: 'req' },
  { id: 'operators', title: 'Operators', sub: 'Who can manage this hall', icon: '👥', ico: 'ops' },
  { id: 'hallPhotos', title: 'Photos', sub: 'Cover image and gallery for this hall', icon: '📷', ico: 'photo' },
  { id: 'deleteHall', title: 'Delete hall', sub: 'Remove this hall from the business', cls: 'danger', icon: '🗑', ico: 'del' },
];

const state = {
  businessName: 'Vijaya Convention Center',
  businessLocation: 'Kottayam, Kerala',
  useHallName: false,
  hallName: '',
  activeHallId: '',
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
  rescheduleRules: [
    { days: '30 days or more', pct: 10 },
    { days: '15 – 29 days', pct: 25 },
    { days: '7 – 14 days', pct: 50 },
    { days: '3 – 6 days', pct: 75 },
    { days: 'Less than 1 day', pct: 100 },
  ],
  cancelPolicyNote: '',
  reschedulePolicyNote: '',
  bookWindowMonths: 6,
  minNoticeDays: 3,
  calDay: 25,
};

let calPendingBlock = null;
let calPendingUnblock = null;
let pendingVenueHallCount = 1;

const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function inr(n) {
  return '₹ ' + (n || 0).toLocaleString('en-IN');
}

function calDateKey(y, m, d) {
  return y + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
}

function parseCalDateKey(key) {
  const p = String(key).split('-');
  return { y: +p[0], m: +p[1], d: +p[2] };
}

function getHallCalendar(h) {
  if (!h) return null;
  if (!h.calendar) {
    h.calendar = {
      viewYear: 2026,
      viewMonth: 12,
      selectedKey: '2026-12-25',
      days: {},
    };
    seedHallCalendarDemo(h.calendar);
  }
  if (!h.calendar.selectedKey) h.calendar.selectedKey = calDateKey(h.calendar.viewYear, h.calendar.viewMonth, 25);
  return h.calendar;
}

function seedHallCalendarDemo(cal) {
  if (Object.keys(cal.days).length) return;
  cal.days['2026-12-25'] = { morning: 'available', evening: 'booked_gixbee' };
  cal.days['2026-12-26'] = {
    morning: 'offline',
    evening: 'available',
    morningBlock: { reason: 'offline', notes: 'Phone booking' },
  };
  cal.days['2026-12-27'] = { morning: 'blocked', evening: 'available', morningBlock: { reason: 'temp', notes: '' } };
  cal.days['2026-12-28'] = { morning: 'available', evening: 'offline', eveningBlock: { reason: 'offline', notes: '' } };
  cal.days['2026-12-29'] = { morning: 'booked_gixbee', evening: 'booked_gixbee' };
}

function ensureDayRecord(cal, key) {
  if (!cal.days[key]) cal.days[key] = {};
  return cal.days[key];
}

function rawSlotStatus(cal, key, slotId) {
  const day = cal.days[key];
  if (!day || !day[slotId]) return 'available';
  return day[slotId];
}

function slotOfferById(id) {
  ensureSlotOffers();
  return state.slotOffers.find(function (o) {
    return o.id === id;
  });
}

/** Saved package slots for calendar (not in-progress wizard edits). */
function calendarSlotOffers(h) {
  if (h && h.packageSaved && h.package && h.package.slotOffers && h.package.slotOffers.length) {
    return h.package.slotOffers;
  }
  ensureSlotOffers();
  return state.slotOffers;
}

function calendarSlotOfferById(h, id) {
  return calendarSlotOffers(h).find(function (o) {
    return o.id === id;
  });
}

function offerEnabledInList(offers, id) {
  const o = offers.find(function (x) {
    return x.id === id;
  });
  return !!(o && o.enabled);
}

function clonePackageSlice(src) {
  const s = src || state;
  ensureSlotOffers();
  return {
    events: (s.events || []).slice(),
    facilities: (s.facilities || []).slice(),
    catering: JSON.parse(JSON.stringify(s.catering || {})),
    capacity: JSON.parse(JSON.stringify(s.capacity || {})),
    slotOffers: (s.slotOffers || state.slotOffers).map(function (o) {
      return JSON.parse(JSON.stringify(o));
    }),
    prices: JSON.parse(JSON.stringify(s.prices || {})),
    payment: JSON.parse(JSON.stringify(s.payment || {})),
    cancelRules: (s.cancelRules || []).map(function (r) {
      return JSON.parse(JSON.stringify(r));
    }),
    rescheduleRules: (s.rescheduleRules || []).map(function (r) {
      return JSON.parse(JSON.stringify(r));
    }),
    cancelPolicyNote: s.cancelPolicyNote || '',
    reschedulePolicyNote: s.reschedulePolicyNote || '',
    bookWindowMonths: s.bookWindowMonths != null ? s.bookWindowMonths : 6,
    minNoticeDays: s.minNoticeDays != null ? s.minNoticeDays : 3,
  };
}

function applyDefaultPackageToState() {
  state.events = ['wedding', 'reception', 'engagement', 'birthday', 'baptism', 'anniversary', 'religious'];
  state.facilities = ['AC', 'Generator / Power Backup', 'Chairs & Tables', 'Stage', 'Sound System', 'Restrooms'];
  state.catering = { inHouse: 'yes', outside: 'yes', decorHall: 'no', decorOutside: 'yes' };
  state.capacity = { seat: 700, dine: 550, car: 50, bike: 100, rooms: 2 };
  state.prices = {
    morning: { noAc: 55000, ac: 75000 },
    evening: { noAc: 55000, ac: 75000 },
    fullday: { noAc: 75000, ac: 90000 },
    extraNoAc: 5000,
    extraAc: 7000,
  };
  state.payment = { advanceType: 'fixed', advanceFixed: 20000, advancePct: 30, fullDueDays: 7 };
  state.cancelRules = POLICY_DEFAULTS.map(function (r) {
    return { days: r.days, pct: r.pct };
  });
  state.rescheduleRules = POLICY_DEFAULTS.map(function (r) {
    return { days: r.days, pct: r.pct };
  });
  state.cancelPolicyNote = '';
  state.reschedulePolicyNote = '';
  state.bookWindowMonths = 6;
  state.minNoticeDays = 3;
  state.slotOffers = null;
  ensureSlotOffers();
}

function applyPackageSlice(pkg) {
  if (!pkg) return;
  state.events = (pkg.events || []).slice();
  state.facilities = (pkg.facilities || []).slice();
  state.catering = JSON.parse(JSON.stringify(pkg.catering || {}));
  state.capacity = JSON.parse(JSON.stringify(pkg.capacity || {}));
  state.prices = JSON.parse(JSON.stringify(pkg.prices || {}));
  state.payment = JSON.parse(JSON.stringify(pkg.payment || {}));
  state.cancelRules = (pkg.cancelRules || []).map(function (r) {
    return JSON.parse(JSON.stringify(r));
  });
  state.rescheduleRules = (pkg.rescheduleRules || []).map(function (r) {
    return JSON.parse(JSON.stringify(r));
  });
  state.cancelPolicyNote = pkg.cancelPolicyNote || '';
  state.reschedulePolicyNote = pkg.reschedulePolicyNote || '';
  state.bookWindowMonths = pkg.bookWindowMonths != null ? pkg.bookWindowMonths : 6;
  state.minNoticeDays = pkg.minNoticeDays != null ? pkg.minNoticeDays : 3;
  state.slotOffers = (pkg.slotOffers || []).map(function (o) {
    return JSON.parse(JSON.stringify(o));
  });
  ensureSlotOffers();
}

function commitHallPackageFromState() {
  const h = activeHall();
  if (!h) return;
  capturePkg2();
  capturePkg3();
  capturePkg4();
  ensureSlotOffers();
  h.package = clonePackageSlice();
  h.packageSaved = true;
  h.packageRevision = (h.packageRevision || 0) + 1;
  reconcileCalendarAfterPackageChange(h);
  savePkg();
}

function reconcileCalendarAfterPackageChange(h) {
  const cal = getHallCalendar(h);
  if (!cal || !cal.days) return;
  const enabledIds = calendarSlotOffers(h)
    .filter(function (o) {
      return o.enabled;
    })
    .map(function (o) {
      return o.id;
    });
  const allIds = ['morning', 'evening', 'fullday'];
  Object.keys(cal.days).forEach(function (key) {
    const day = cal.days[key];
    allIds.forEach(function (sid) {
      if (enabledIds.indexOf(sid) === -1) {
        delete day[sid];
        delete day[sid + 'Block'];
      }
    });
  });
}

function statusToDotKind(st) {
  if (st === 'booked_gixbee') return 'bk';
  if (st === 'offline') return 'off';
  if (st === 'blocked') return 'blk';
  if (st === 'available') return 'av';
  return 'na';
}

function fulldayComputed(cal, key, h) {
  const offers = calendarSlotOffers(h);
  const morningOn = offerEnabledInList(offers, 'morning');
  const eveningOn = offerEnabledInList(offers, 'evening');
  const fulldayOn = offerEnabledInList(offers, 'fullday');
  const mOffer = offers.find(function (o) {
    return o.id === 'morning';
  });
  const eOffer = offers.find(function (o) {
    return o.id === 'evening';
  });
  const mName = mOffer ? mOffer.label : 'Morning';
  const eName = eOffer ? eOffer.label : 'Evening';

  if (fulldayOn && !morningOn && !eveningOn) {
    const st = rawSlotStatus(cal, key, 'fullday');
    if (st === 'available') return { status: 'available', reason: '' };
    if (st === 'booked_gixbee') return { status: 'unavailable', reason: 'Booked' };
    if (st === 'offline') return { status: 'unavailable', reason: 'Offline booked' };
    if (st === 'blocked') return { status: 'unavailable', reason: 'Blocked' };
    return { status: 'unavailable', reason: 'Not available' };
  }

  if (!fulldayOn) {
    return { status: 'unavailable', reason: 'Full day slot not offered' };
  }

  const m = morningOn ? rawSlotStatus(cal, key, 'morning') : 'available';
  const e = eveningOn ? rawSlotStatus(cal, key, 'evening') : 'available';
  const f = rawSlotStatus(cal, key, 'fullday');
  const mOk = m === 'available';
  const eOk = e === 'available';
  if (mOk && eOk) {
    if (f === 'available') return { status: 'available', reason: '' };
    if (f === 'booked_gixbee') return { status: 'unavailable', reason: 'Booked (full day)' };
    if (f === 'offline') return { status: 'unavailable', reason: 'Full day offline booked' };
    if (f === 'blocked') return { status: 'unavailable', reason: 'Full day blocked' };
    return { status: 'available', reason: '' };
  }
  if (!mOk && !eOk) {
    return { status: 'unavailable', reason: mName + ' and ' + eName + ' occupied' };
  }
  if (!eOk) return { status: 'unavailable', reason: eName + ' occupied' };
  return { status: 'unavailable', reason: mName + ' occupied' };
}

function dayDotKind(cal, key, h) {
  const offers = calendarSlotOffers(h).filter(function (o) {
    return o.enabled;
  });
  const rank = { av: 0, bk: 1, off: 2, blk: 3, na: 4 };
  let worst = 'av';
  offers.forEach(function (o) {
    let kind;
    if (o.id === 'fullday') {
      const fd = fulldayComputed(cal, key, h);
      if (fd.status === 'available') kind = 'av';
      else kind = 'na';
      const rawFd = rawSlotStatus(cal, key, 'fullday');
      if (!offerEnabledInList(offers, 'morning') && !offerEnabledInList(offers, 'evening')) {
        kind = statusToDotKind(rawFd);
      }
    } else {
      kind = statusToDotKind(rawSlotStatus(cal, key, o.id));
    }
    if (rank[kind] > rank[worst]) worst = kind;
  });
  return worst || 'av';
}

function monthLabel(y, m) {
  return MONTH_NAMES[m - 1] + ' ' + y;
}

function formatCalDayTitle(key) {
  const p = parseCalDateKey(key);
  const dt = new Date(p.y, p.m - 1, p.d);
  return p.d + ' ' + MONTH_NAMES[p.m - 1].slice(0, 3) + ' ' + p.y + ', ' + DAY_NAMES[dt.getDay()];
}

function daysInMonth(y, m) {
  return new Date(y, m, 0).getDate();
}

function openOverlay(id) {
  const o = el(id);
  if (o) {
    o.classList.add('on');
    o.setAttribute('aria-hidden', 'false');
  }
}

function closeOverlay(id) {
  const o = el(id);
  if (o) {
    o.classList.remove('on');
    o.setAttribute('aria-hidden', 'true');
  }
}

function persistCalendarDay(h, key, slotId, status, blockMeta) {
  const cal = getHallCalendar(h);
  const day = ensureDayRecord(cal, key);
  day[slotId] = status;
  const metaKey = slotId + 'Block';
  if (blockMeta) day[metaKey] = blockMeta;
  else delete day[metaKey];
  savePkg();
}

function renderCalendar() {
  const h = activeHall();
  const cal = getHallCalendar(h);
  if (!cal) return;
  const y = cal.viewYear;
  const m = cal.viewMonth;
  const ml = el('calMonthLabel');
  const mpl = el('calMonthPickLabel');
  if (ml) ml.textContent = monthLabel(y, m);
  if (mpl) mpl.textContent = monthLabel(y, m);
  const firstDow = new Date(y, m - 1, 1).getDay();
  const dim = daysInMonth(y, m);
  const cells = [];
  for (let i = 0; i < firstDow; i++) cells.push('<span class="cal-pad"></span>');
  for (let d = 1; d <= dim; d++) {
    const key = calDateKey(y, m, d);
    const dot = dayDotKind(cal, key, h);
    const on = cal.selectedKey === key ? ' on' : '';
    cells.push(
      '<button type="button" class="cal-day-cell' +
        on +
        '" data-cal-day="' +
        d +
        '" data-cal-key="' +
        key +
        '"><span>' +
        d +
        '</span><i class="cal-dot ' +
        dot +
        '"></i></button>',
    );
  }
  el('calGrid').innerHTML = cells.join('');
  el('calGrid').querySelectorAll('[data-cal-day]').forEach(function (btn) {
    btn.onclick = function () {
      cal.selectedKey = btn.getAttribute('data-cal-key');
      savePkg();
      renderCalDay();
      show('calDay');
    };
  });
}

function slotStatusLabel(status, slotId, cal, key, h) {
  if (slotId === 'fullday') {
    const rawFd = rawSlotStatus(cal, key, 'fullday');
    if (rawFd === 'offline') return { pill: 'off', text: 'Offline Booked' };
    if (rawFd === 'blocked') return { pill: 'blk', text: 'Blocked' };
    if (rawFd === 'booked_gixbee') return { pill: 'bad', text: 'Booked (Gixbee)' };
    const fd = fulldayComputed(cal, key, h);
    if (fd.status === 'available') return { pill: 'ok', text: 'Available' };
    return { pill: 'muted', text: 'Unavailable (' + fd.reason + ')' };
  }
  const st = rawSlotStatus(cal, key, slotId);
  if (st === 'available') return { pill: 'ok', text: 'Available' };
  if (st === 'booked_gixbee') return { pill: 'bad', text: 'Booked (Gixbee)' };
  if (st === 'offline') return { pill: 'off', text: 'Offline Booked' };
  if (st === 'blocked') return { pill: 'blk', text: 'Blocked' };
  return { pill: 'muted', text: 'Not Available' };
}

function renderSlotPriceChips(offer) {
  if (!offer || !offer.enabled) return '';
  let html = '<div class="price-chips">';
  if (offer.offerAc) html += '<span class="price-chip ac">With AC ' + inr(offer.priceAc) + '</span>';
  if (offer.offerNoAc) html += '<span class="price-chip noac">Without AC ' + inr(offer.priceNoAc) + '</span>';
  html += '</div>';
  return html;
}

function renderCalDay() {
  const h = activeHall();
  const cal = getHallCalendar(h);
  if (!cal) return;
  const key = cal.selectedKey;
  const title = el('calDayTitle');
  if (title) title.textContent = formatCalDayTitle(key);
  const order = { morning: 0, evening: 1, fullday: 2 };
  const offers = calendarSlotOffers(h)
    .filter(function (o) {
      return o.enabled;
    })
    .sort(function (a, b) {
      return (order[a.id] != null ? order[a.id] : 9) - (order[b.id] != null ? order[b.id] : 9);
    });
  const html = offers
    .map(function (offer) {
      const slotId = offer.id;
      const label = offer.label + ' (' + formatTimeRange(offer.hallFrom, offer.hallTo) + ')';
      const st = slotStatusLabel(null, slotId, cal, key, h);
      const rawFd = slotId === 'fullday' ? rawSlotStatus(cal, key, 'fullday') : null;
      const fd = slotId === 'fullday' ? fulldayComputed(cal, key, h) : null;
      let raw = slotId === 'fullday' ? rawFd : rawSlotStatus(cal, key, slotId);
      if (slotId === 'fullday' && raw === 'available' && fd && fd.status !== 'available') {
        raw = 'unavailable';
      }
      const fulldayCanBlock = slotId === 'fullday' && rawFd === 'available' && fd && fd.status === 'available';
      const disabled = slotId === 'fullday' && raw === 'unavailable';
      let actions = '';
      if (slotId === 'fullday') {
        if (fulldayCanBlock) {
          actions =
            '<div class="slot-actions"><button type="button" class="btn" data-cal-block="' +
            slotId +
            '">Block Slot</button></div>';
        } else if (rawFd === 'offline' || rawFd === 'blocked') {
          actions =
            '<div class="slot-actions"><button type="button" class="btn ghost" data-cal-unblock="' +
            slotId +
            '">Unblock</button></div>';
        } else if (rawFd === 'booked_gixbee') {
          actions =
            '<div class="slot-actions"><button type="button" class="btn ghost" data-cal-manage="' +
            slotId +
            '">Manage Booking</button></div>';
        } else if (raw === 'unavailable') {
          actions =
            '<p class="sub" style="margin:8px 0 0">Full day needs Morning and Evening free (or unblock them first).</p>';
        }
      } else if (raw === 'available') {
        actions =
          '<div class="slot-actions"><button type="button" class="btn" data-cal-block="' +
          slotId +
          '">Block Slot</button></div>';
      } else if (raw === 'offline' || raw === 'blocked') {
        actions =
          '<div class="slot-actions"><button type="button" class="btn ghost" data-cal-unblock="' +
          slotId +
          '">Unblock</button></div>';
      } else if (raw === 'booked_gixbee') {
        actions =
          '<div class="slot-actions"><button type="button" class="btn ghost" data-cal-manage="' +
          slotId +
          '">Manage Booking</button></div>';
      }
      return (
        '<div class="slot' +
        (disabled ? ' slot-disabled' : '') +
        '"><span class="pill ' +
        st.pill +
        '">' +
        esc(st.text) +
        '</span><h3>' +
        esc(label) +
        '</h3>' +
        renderSlotPriceChips(offer) +
        actions +
        '</div>'
      );
    })
    .join('');
  el('daySlots').innerHTML =
    html ||
    '<p class="sub">No time slots enabled — set slots in <b>Price &amp; packages</b> step 3 and tap <b>Save Package</b> on Review.</p>';
  el('daySlots').querySelectorAll('[data-cal-block]').forEach(function (btn) {
    btn.onclick = function () {
      openBlockSheet(btn.getAttribute('data-cal-block'));
    };
  });
  el('daySlots').querySelectorAll('[data-cal-unblock]').forEach(function (btn) {
    btn.onclick = function () {
      openUnblockModal(btn.getAttribute('data-cal-unblock'));
    };
  });
  el('daySlots').querySelectorAll('[data-cal-manage]').forEach(function () {
    btn.onclick = function () {
      toast('Open Booking requests to accept or manage this Gixbee booking.');
      renderOwnerReq();
      show('ownerReq');
    };
  });
}

function openBlockSheet(slotId) {
  const h = activeHall();
  const cal = getHallCalendar(h);
  const offer = calendarSlotOfferById(h, slotId);
  if (!offer) return;
  calPendingBlock = { slotId: slotId, reason: 'offline', notes: '' };
  const key = cal.selectedKey;
  const sum = el('blockSheetSummary');
  if (sum) {
    sum.innerHTML =
      '<b>' +
      esc(offer.label) +
      '</b><br>' +
      esc(formatTimeRange(offer.hallFrom, offer.hallTo)) +
      '<br>' +
      esc(formatCalDayTitle(key));
  }
  document.querySelectorAll('.block-reason').forEach(function (lab) {
    lab.classList.toggle('on', lab.getAttribute('data-block-reason') === 'offline');
    const inp = lab.querySelector('input');
    if (inp) inp.checked = lab.getAttribute('data-block-reason') === 'offline';
  });
  if (el('blockNotes')) el('blockNotes').value = '';
  openOverlay('blockSheetOverlay');
}

function openConfirmBlockModal() {
  if (!calPendingBlock) return;
  const h = activeHall();
  const offer = calendarSlotOfferById(h, calPendingBlock.slotId);
  const title = el('confirmBlockTitle');
  const body = el('confirmBlockBody');
  const reason = calPendingBlock.reason;
  const statusWord = reason === 'temp' ? 'Blocked' : 'Offline Booking';
  if (title) title.textContent = 'Block ' + (offer ? offer.label : 'Slot') + ' Slot?';
  if (body) {
    var extra =
      calPendingBlock.slotId === 'fullday'
        ? ' Blocking full day also marks Morning and Evening offline for this date (one full-day booking).'
        : ' Full Day slot will also become unavailable automatically.';
    body.textContent =
      'This will mark the ' +
      (offer ? offer.label : '') +
      ' slot as ' +
      statusWord +
      ' and it will be unavailable for customers.' +
      extra;
  }
  closeOverlay('blockSheetOverlay');
  openOverlay('confirmBlockOverlay');
}

function applyBlockConfirm() {
  if (!calPendingBlock) return;
  const h = activeHall();
  const cal = getHallCalendar(h);
  const key = cal.selectedKey;
  const slotId = calPendingBlock.slotId;
  const reason = calPendingBlock.reason;
  const status = reason === 'temp' ? 'blocked' : 'offline';
  const blockMeta = {
    reason: reason,
    notes: calPendingBlock.notes || '',
  };
  const offers = calendarSlotOffers(h);
  if (slotId === 'fullday') {
    persistCalendarDay(h, key, 'fullday', status, blockMeta);
    if (offerEnabledInList(offers, 'morning') && offerEnabledInList(offers, 'evening')) {
      const day = ensureDayRecord(cal, key);
      day.fullDayLinkedBlock = true;
      persistCalendarDay(h, key, 'morning', status, blockMeta);
      persistCalendarDay(h, key, 'evening', status, blockMeta);
    }
  } else {
    persistCalendarDay(h, key, slotId, status, blockMeta);
  }
  closeOverlay('confirmBlockOverlay');
  calPendingBlock = null;
  renderCalendar();
  renderCalDay();
  toast('Slot blocked.');
}

function openUnblockModal(slotId) {
  const h = activeHall();
  const offer = calendarSlotOfferById(h, slotId);
  const cal = getHallCalendar(h);
  calPendingUnblock = { slotId: slotId, key: cal.selectedKey };
  const sum = el('unblockSlotSum');
  if (sum && offer) {
    sum.textContent = offer.label + ' · ' + formatTimeRange(offer.hallFrom, offer.hallTo);
  }
  const body = el('unblockBody');
  if (body) {
    body.textContent =
      'Unblock ' +
      (offer ? offer.label : 'this') +
      ' slot? This will make it available to customers again. Full Day slot will be available if the other half-day slot is also free.';
  }
  openOverlay('unblockOverlay');
}

function applyUnblockConfirm() {
  if (!calPendingUnblock) return;
  const h = activeHall();
  const cal = getHallCalendar(h);
  const key = calPendingUnblock.key;
  const slotId = calPendingUnblock.slotId;
  const day = cal && cal.days ? cal.days[key] : null;
  if (slotId === 'fullday' && day && day.fullDayLinkedBlock) {
    persistCalendarDay(h, key, 'fullday', 'available', null);
    persistCalendarDay(h, key, 'morning', 'available', null);
    persistCalendarDay(h, key, 'evening', 'available', null);
    delete day.fullDayLinkedBlock;
  } else {
    persistCalendarDay(h, key, slotId, 'available', null);
  }
  closeOverlay('unblockOverlay');
  calPendingUnblock = null;
  renderCalendar();
  renderCalDay();
  toast('Slot unblocked.');
}

function bindCalendarUi() {
  const tabBs = el('tabBookSettings');
  if (tabBs) {
    tabBs.onclick = function () {
      renderBookSettings();
      show('bookSettings');
    };
  }
  const prevM = el('calPrevMonth');
  const nextM = el('calNextMonth');
  if (prevM) {
    prevM.onclick = function () {
      const h = activeHall();
      const cal = getHallCalendar(h);
      cal.viewMonth -= 1;
      if (cal.viewMonth < 1) {
        cal.viewMonth = 12;
        cal.viewYear -= 1;
      }
      savePkg();
      renderCalendar();
    };
  }
  if (nextM) {
    nextM.onclick = function () {
      const h = activeHall();
      const cal = getHallCalendar(h);
      cal.viewMonth += 1;
      if (cal.viewMonth > 12) {
        cal.viewMonth = 1;
        cal.viewYear += 1;
      }
      savePkg();
      renderCalendar();
    };
  }
  const openMp = el('openMonthPicker');
  if (openMp) {
    openMp.onclick = function () {
      renderMonthPickerList();
      openOverlay('monthPickerOverlay');
    };
  }
  ['closeMonthPicker', 'cancelMonthPicker'].forEach(function (id) {
    const b = el(id);
    if (b) b.onclick = function () { closeOverlay('monthPickerOverlay'); };
  });
  const backDay = el('backFromCalDay');
  if (backDay) {
    backDay.onclick = function () {
      renderCalendar();
      show('calendar');
    };
  }
  const prevD = el('calPrevDay');
  const nextD = el('calNextDay');
  if (prevD) {
    prevD.onclick = function () { shiftCalDay(-1); };
  }
  if (nextD) {
    nextD.onclick = function () { shiftCalDay(1); };
  }
  document.querySelectorAll('.block-reason').forEach(function (lab) {
    lab.onclick = function () {
      document.querySelectorAll('.block-reason').forEach(function (x) { x.classList.remove('on'); });
      lab.classList.add('on');
      const inp = lab.querySelector('input');
      if (inp) inp.checked = true;
      if (calPendingBlock) calPendingBlock.reason = lab.getAttribute('data-block-reason');
    };
  });
  const closeBs = el('closeBlockSheet');
  const cancelBs = el('cancelBlockSheet');
  if (closeBs) closeBs.onclick = function () { closeOverlay('blockSheetOverlay'); calPendingBlock = null; };
  if (cancelBs) cancelBs.onclick = function () { closeOverlay('blockSheetOverlay'); calPendingBlock = null; };
  const submitBs = el('submitBlockSheet');
  if (submitBs) {
    submitBs.onclick = function () {
      if (!calPendingBlock) return;
      const sel = document.querySelector('input[name=blockReason]:checked');
      calPendingBlock.reason = sel ? sel.value : 'offline';
      calPendingBlock.notes = el('blockNotes') ? el('blockNotes').value.trim() : '';
      openConfirmBlockModal();
    };
  }
  const cancelCb = el('cancelConfirmBlock');
  const doCb = el('doConfirmBlock');
  if (cancelCb) {
    cancelCb.onclick = function () {
      closeOverlay('confirmBlockOverlay');
      openBlockSheet(calPendingBlock ? calPendingBlock.slotId : 'morning');
    };
  }
  if (doCb) doCb.onclick = applyBlockConfirm;
  const cancelUb = el('cancelUnblock');
  const doUb = el('doUnblock');
  if (cancelUb) cancelUb.onclick = function () { closeOverlay('unblockOverlay'); calPendingUnblock = null; };
  if (doUb) doUb.onclick = applyUnblockConfirm;
}

function shiftCalDay(delta) {
  const h = activeHall();
  const cal = getHallCalendar(h);
  const p = parseCalDateKey(cal.selectedKey);
  const dt = new Date(p.y, p.m - 1, p.d + delta);
  cal.viewYear = dt.getFullYear();
  cal.viewMonth = dt.getMonth() + 1;
  cal.selectedKey = calDateKey(cal.viewYear, cal.viewMonth, dt.getDate());
  savePkg();
  renderCalDay();
}

function renderMonthPickerList() {
  const h = activeHall();
  const cal = getHallCalendar(h);
  const list = el('monthPickerList');
  if (!list) return;
  const items = [];
  for (let i = 0; i < 11; i++) {
    const dt = new Date(2026, 9 + i, 1);
    const y = dt.getFullYear();
    const m = dt.getMonth() + 1;
    const on = y === cal.viewYear && m === cal.viewMonth;
    items.push(
      '<button type="button" class="' +
        (on ? 'on' : '') +
        '" data-pick-y="' +
        y +
        '" data-pick-m="' +
        m +
        '">' +
        monthLabel(y, m) +
        '</button>',
    );
  }
  list.innerHTML = items.join('');
  list.querySelectorAll('[data-pick-y]').forEach(function (btn) {
    btn.onclick = function () {
      cal.viewYear = +btn.getAttribute('data-pick-y');
      cal.viewMonth = +btn.getAttribute('data-pick-m');
      savePkg();
      closeOverlay('monthPickerOverlay');
      renderCalendar();
    };
  });
}

function openCalendarFlow() {
  ensureSlotOffers();
  const h = activeHall();
  getHallCalendar(h);
  renderCalendar();
  show('calendar');
  syncHallInactiveLock();
}

let pkg4PolicyTab = 'cancel';
let manageNameSnapshot = { useHallName: false, hallName: '' };
let manageNameEditing = false;

const POLICY_DEFAULTS = [
  { days: '30 days or more', pct: 10 },
  { days: '15 – 29 days', pct: 25 },
  { days: '7 – 14 days', pct: 50 },
  { days: '3 – 6 days', pct: 75 },
  { days: 'Less than 1 day', pct: 100 },
];

function ensurePolicyRules() {
  if (!state.cancelRules || !state.cancelRules.length) {
    state.cancelRules = POLICY_DEFAULTS.map(function (r) {
      return { days: r.days, pct: r.pct };
    });
  }
  if (!state.rescheduleRules || !state.rescheduleRules.length) {
    state.rescheduleRules = state.cancelRules.map(function (r) {
      return { days: r.days, pct: r.pct };
    });
  }
  if (state.cancelPolicyNote == null) state.cancelPolicyNote = '';
  if (state.reschedulePolicyNote == null) state.reschedulePolicyNote = '';
}

function policyRulesHtml(kind) {
  const rules = kind === 'cancel' ? state.cancelRules : state.rescheduleRules;
  const rows = rules
    .map(function (r) {
      return (
        '<div class="policy-row">' +
        '<input type="text" class="policy-days-inp" data-field="days" value="' +
        esc(r.days) +
        '">' +
        '<span class="policy-pct-wrap"><input type="number" class="policy-pct-inp" min="0" max="100" data-field="pct" value="' +
        r.pct +
        '"> %</span>' +
        '<button type="button" class="policy-row-remove" title="Remove tier">✕</button></div>'
      );
    })
    .join('');
  return (
    '<div class="policy-rows" data-policy-kind="' +
    kind +
    '">' +
    rows +
    '</div>' +
    '<button type="button" class="btn ghost policy-add-tier" data-policy="' +
    kind +
    '" style="margin-top:10px;width:100%">+ Add tier</button>'
  );
}

function capturePolicyRulesFromDom() {
  if (!el('payPolicy')) return;
  const box = el('payPolicy').querySelector('.policy-rows[data-policy-kind]');
  if (box) {
    const kind = box.getAttribute('data-policy-kind');
    const rules = [];
    box.querySelectorAll('.policy-row').forEach(function (row) {
      const daysIn = row.querySelector('[data-field=days]');
      const pctIn = row.querySelector('[data-field=pct]');
      if (!daysIn || !pctIn) return;
      rules.push({
        days: daysIn.value.trim() || 'Days before event',
        pct: +pctIn.value || 0,
      });
    });
    if (kind === 'cancel') {
      state.cancelRules = rules.length ? rules : [{ days: 'Days before event', pct: 0 }];
    } else {
      state.rescheduleRules = rules.length ? rules : [{ days: 'Days before event', pct: 0 }];
    }
  }
  const cn = el('cancelPolicyNote');
  const rn = el('reschedulePolicyNote');
  if (cn) state.cancelPolicyNote = cn.value.trim();
  if (rn) state.reschedulePolicyNote = rn.value.trim();
}

function attachPolicyRowHandlers() {
  const root = el('payPolicy');
  if (!root) return;
  root.querySelectorAll('.policy-row-remove').forEach(function (btn) {
    btn.onclick = function () {
      capturePolicyRulesFromDom();
      capturePkg4PaymentOnly();
      const kind = pkg4PolicyTab === 'reschedule' ? 'reschedule' : 'cancel';
      const arr = kind === 'cancel' ? state.cancelRules : state.rescheduleRules;
      const row = btn.closest('.policy-row');
      const box = row && row.parentElement;
      if (!row || !box) return;
      const idx = Array.prototype.indexOf.call(box.querySelectorAll('.policy-row'), row);
      if (arr.length <= 1) {
        toast('Keep at least one tier in this policy.');
        return;
      }
      if (idx >= 0) arr.splice(idx, 1);
      renderPkg4();
    };
  });
  root.querySelectorAll('.policy-add-tier').forEach(function (btn) {
    btn.onclick = function () {
      capturePolicyRulesFromDom();
      capturePkg4PaymentOnly();
      const kind = btn.getAttribute('data-policy');
      const arr = kind === 'cancel' ? state.cancelRules : state.rescheduleRules;
      arr.push({ days: 'Days before event', pct: 10 });
      renderPkg4();
    };
  });
}

function policySummaryLines(rules, note) {
  const lines = rules.map(function (r) {
    return r.days + ': ' + r.pct + '%';
  });
  if (note) lines.push('Note: ' + note);
  return lines.join(' · ');
}

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
  ensurePolicyRules();
  normalizeHallRecords();
  state.parkingEditOpen = false;
}
function normalizeNames() {
  if (!state.businessName) state.businessName = 'Vijaya Convention Center';
  state.useHallName = true;
  state.hallName = String(state.hallName || '').trim();
}
function venueHasMultipleHalls() {
  return state.plannedHallCount > 1 || state.halls.length > 1;
}

function ensureHallNumbers() {
  if (!state.halls || !state.halls.length) return;
  state.halls.forEach(function (h, i) {
    if (h.hallNumber == null || h.hallNumber < 1) {
      h.hallNumber = i + 1;
    }
  });
}

function nextHallNumber() {
  ensureHallNumbers();
  let max = 0;
  state.halls.forEach(function (h) {
    if (h.hallNumber > max) max = h.hallNumber;
  });
  return max + 1;
}

function defaultHallLabelForNumber(n) {
  return 'Hall ' + Math.max(1, +n || 1);
}

function resolvedHallName(h) {
  if (!h) return '';
  const trimmed = String(h.hallName || '').trim();
  if (trimmed) return trimmed;
  const n =
    h.hallNumber != null && h.hallNumber > 0
      ? h.hallNumber
      : Math.max(1, state.halls.indexOf(h) + 1);
  return defaultHallLabelForNumber(n);
}

function ensureHallNameOnRecord(h) {
  if (!h) return;
  if (!String(h.hallName || '').trim()) {
    const n =
      h.hallNumber != null && h.hallNumber > 0
        ? h.hallNumber
        : Math.max(1, state.halls.indexOf(h) + 1);
    h.hallName = defaultHallLabelForNumber(n);
  }
  h.useHallName = true;
}

function hallDisplayNameForRecord(h) {
  if (!h) return state.businessName || 'Your hall';
  return resolvedHallName(h) || state.businessName || 'Your hall';
}

function customerHallName() {
  const h = activeHall();
  return h ? resolvedHallName(h) : '';
}

function validateHallNameRequired() {
  captureNameFields();
  if (!String(state.hallName || '').trim()) {
    toast('Enter a hall name (e.g. Hall 1 or Koinonia).');
    return false;
  }
  return true;
}
function syncHallNameUi() {
  const pkgIn = el('hallNameInput');
  if (pkgIn && document.activeElement !== pkgIn) {
    pkgIn.value = state.hallName || resolvedHallName(activeHall());
  }
  renderManageNameMode();
}

function renderManageNameMode() {
  const inp = el('manageHallNameInput');
  const listingOn = hallListingOn(activeHall());
  const h = activeHall();
  const isAdd = !!state.openedFromAddHall;
  if (inp) {
    inp.disabled = !listingOn && !isAdd;
    if (document.activeElement !== inp) {
      inp.value = state.hallName || (h ? resolvedHallName(h) : '');
    }
  }
  manageNameEditing = false;
  const manageScr = el('manage');
  if (manageScr) manageScr.classList.remove('manage-name-editing');
}

function snapshotManageNameFromHall() {
  const h = activeHall();
  manageNameSnapshot = {
    useHallName: true,
    hallName: h ? resolvedHallName(h) : String(state.hallName || '').trim(),
  };
}

function applyManageNameSnapshot() {
  state.useHallName = true;
  state.hallName = manageNameSnapshot.hallName;
  manageNameEditing = false;
  syncHallNameUi();
}

function finishManageNameEdit() {
  manageNameEditing = false;
  snapshotManageNameFromHall();
  renderManageNameMode();
}
function captureNameFields() {
  state.useHallName = true;
  const hallIn = el('hallNameInput');
  const manageIn = el('manageHallNameInput');
  if (hallIn && (el('pkg2') && el('pkg2').classList.contains('on') || document.activeElement === hallIn)) {
    state.hallName = hallIn.value.trim();
  } else if (
    manageIn &&
    (state.openedFromAddHall || (el('manage') && el('manage').classList.contains('on')))
  ) {
    state.hallName = manageIn.value.trim();
  } else if (hallIn && el('pkg2') && el('pkg2').classList.contains('on')) {
    state.hallName = hallIn.value.trim();
  }
  syncHallNameUi();
}
function renderManageHeader() {
  const sub = el('manageSubLine');
  if (sub) {
    var hallPart = customerHallName();
    if (hallPart) {
      sub.textContent = state.businessName + ' · Hall: ' + hallPart + ' · Service · Hall';
    } else {
      sub.textContent = state.businessName + ' · Service · Hall';
    }
  }
  const bizRo = el('bizNameRo');
  if (bizRo) bizRo.value = state.businessName;
  const bizDisplay = el('manageBizNameDisplay');
  if (bizDisplay) bizDisplay.textContent = state.businessName;
  const bizPkg = el('bizNamePkg');
  if (bizPkg) bizPkg.value = state.businessName;
  const pkg2Title = el('pkg2BizTitle');
  if (pkg2Title) pkg2Title.textContent = state.businessName;
  const pkg2Loc = el('pkg2BizLoc');
  if (pkg2Loc) pkg2Loc.textContent = state.businessLocation || 'Kottayam, Kerala';
  syncHallNameUi();
  const banner = el('hallInactiveBanner');
  if (banner) banner.hidden = hallListingOn(activeHall());
  syncHallInactiveLock();
}
function savePkg() {
  syncActiveHallFromState();
  const payload = Object.assign({}, state, { parkingEditOpen: false });
  localStorage.setItem(PKG_KEY, JSON.stringify(payload));
}

function activeHall() {
  return state.halls.find(function (h) { return h.id === state.activeHallId; }) || state.halls[0];
}

function hallListingOn(h) {
  if (!h) return true;
  return h.hallActive !== false;
}

function hallPackageSaved(h) {
  return !!(h && h.packageSaved);
}


function showPackageRequiredModal() {
  openOverlay('packageRequiredOverlay');
}

function requireHallPackageSaved(h) {
  if (hallPackageSaved(h)) return true;
  showPackageRequiredModal();
  return false;
}

function bindPackageRequiredUi() {
  const ok = el('pkgRequiredOk');
  if (ok) {
    ok.onclick = function () {
      closeOverlay('packageRequiredOverlay');
    };
  }
  const overlay = el('packageRequiredOverlay');
  if (overlay) {
    overlay.onclick = function (e) {
      if (e.target === overlay) closeOverlay('packageRequiredOverlay');
    };
  }
}

function showVenueEditStep(step) {
  const s1 = el('venueEditStep1');
  const s2 = el('venueEditStep2');
  if (s1) s1.hidden = step !== 1;
  if (s2) s2.hidden = step !== 2;
}

function closeVenueEditOverlay() {
  closeOverlay('venueEditOverlay');
  state.parkingEditOpen = false;
  if (el('editParkingBtn')) el('editParkingBtn').disabled = false;
  setHallBizDisabled(false);
  showVenueEditStep(1);
}

function openVenueEditOverlay() {
  if (state.parkingEditOpen) return;
  const added = state.halls.length;
  const startCount = Math.max(state.plannedHallCount || 1, added || 1);
  pendingVenueHallCount = startCount;
  const inp = el('editHallCountInput');
  if (inp) inp.value = startCount;
  const hint = el('editHallCountHint');
  if (hint) {
    hint.textContent = added
      ? 'You have ' + added + ' hall' + (added === 1 ? '' : 's') + ' added. Count cannot be less than that.'
      : 'Set how many halls you plan to list, then enter parking.';
  }
  showVenueEditStep(1);
  openOverlay('venueEditOverlay');
  state.parkingEditOpen = true;
  if (el('editParkingBtn')) el('editParkingBtn').disabled = true;
  setHallBizDisabled(true);
}

function applyVenueEditStep2Labels(count) {
  const labels = parkingLabelsForHallCount(count);
  const title = el('editParkingStepTitle');
  const hint = el('editParkingHint');
  if (title) title.textContent = labels.title;
  if (hint) hint.textContent = labels.hint;
  if (el('editParkCar')) el('editParkCar').value = state.commonParking.car;
  if (el('editParkBike')) el('editParkBike').value = state.commonParking.bike;
}

function saveVenueSetupFromEdit() {
  const count = pendingVenueHallCount;
  const car = +(el('editParkCar') && el('editParkCar').value) || 0;
  const bike = +(el('editParkBike') && el('editParkBike').value) || 0;
  state.plannedHallCount = count;
  state.commonParking = { car: car, bike: bike };
  closeVenueEditOverlay();
  savePkg();
  renderParkingSummary();
  renderHallBizHome();
  toast(count > 1 ? 'Venue updated — common parking saved.' : 'Venue updated — parking saved.');
}

function bindVenueEditUi() {
  const editPark = el('editParkingBtn');
  if (editPark) {
    editPark.onclick = function () {
      openVenueEditOverlay();
    };
  }
  const ok1 = el('venueEditStep1Ok');
  if (ok1) {
    ok1.onclick = function () {
      const count = Math.max(1, +(el('editHallCountInput') && el('editHallCountInput').value) || 1);
      const added = state.halls.length;
      if (count < added) {
        toast('You already have ' + added + ' hall' + (added === 1 ? '' : 's') + '. Delete a hall first or set count to at least ' + added + '.');
        return;
      }
      pendingVenueHallCount = count;
      applyVenueEditStep2Labels(count);
      showVenueEditStep(2);
    };
  }
  const back = el('venueEditBack');
  if (back) {
    back.onclick = function () {
      showVenueEditStep(1);
    };
  }
  const save = el('venueEditSave');
  if (save) {
    save.onclick = function () {
      saveVenueSetupFromEdit();
    };
  }
  ['venueEditCancel1', 'venueEditCancel2'].forEach(function (id) {
    const b = el(id);
    if (b) b.onclick = function () {
      closeVenueEditOverlay();
    };
  });
  const overlay = el('venueEditOverlay');
  if (overlay) {
    overlay.onclick = function (e) {
      if (e.target === overlay) closeVenueEditOverlay();
    };
  }
}

function normalizeHallRecords() {
  if (!state.halls) state.halls = [];
  state.halls.forEach(function (h) {
    if (h.hallActive == null) h.hallActive = true;
    if (h.packageSaved == null) h.packageSaved = false;
    if (h.packageSaved && !h.package && state.halls.length === 1) {
      h.package = clonePackageSlice();
    }
  });
  ensureHallNumbers();
  state.halls.forEach(function (h) {
    ensureHallNameOnRecord(h);
  });
}

function syncHallInactiveLock() {
  const locked = activeHall() && !hallListingOn(activeHall());
  ['manage', 'pkg1', 'pkg2', 'pkg3', 'pkg4', 'pkg5', 'calendar', 'calDay', 'ownerReq', 'bookSettings', 'operators', 'hallMedia', 'placeholder'].forEach(
    function (id) {
      const scr = el(id);
      if (scr) scr.classList.toggle('hall-inactive-lock', !!locked);
    },
  );
  const banner = el('hallInactiveBanner');
  if (banner) banner.hidden = !locked;
}

function loadActiveHallIntoState() {
  const h = activeHall();
  if (!h) return;
  ensureHallNameOnRecord(h);
  state.useHallName = true;
  state.hallName = String(h.hallName || '').trim();
  if (h.package) {
    applyPackageSlice(h.package);
  } else {
    applyDefaultPackageToState();
  }
}

function syncActiveHallFromState() {
  const h = activeHall();
  if (!h) return;
  h.useHallName = true;
  h.hallName = String(state.hallName || '').trim() || resolvedHallName(h);
}

function parkingLabelsForHallCount(count) {
  const n = Math.max(1, +count || 1);
  if (n <= 1) {
    return {
      title: 'Parking',
      setupLbl: 'PARKING',
      hint: 'Car and bike parking for your hall (shown to customers).',
    };
  }
  return {
    title: 'Common parking (shared by ' + n + ' halls)',
    setupLbl: 'COMMON PARKING (SHARED)',
    hint: 'One shared car and bike count for all ' + n + ' halls.',
  };
}

function parkingDisplay() {
  const multi = state.plannedHallCount > 1 || state.halls.length > 1;
  const labelCount = multi ? Math.max(state.plannedHallCount || 1, state.halls.length) : 1;
  const labels = parkingLabelsForHallCount(labelCount);
  return {
    title: labels.title,
    car: state.commonParking.car,
    bike: state.commonParking.bike,
    common: true,
  };
}

function hallCardDisplayName(h) {
  return hallDisplayNameForRecord(h);
}

function hallCardGuestCount(h) {
  const cap = h && h.package && h.package.capacity;
  if (cap && cap.seat != null) return cap.seat;
  return 700;
}

function hallCardHasAc(h) {
  const fac = h && h.package && h.package.facilities;
  if (fac && fac.length) return fac.indexOf('AC') >= 0;
  return true;
}

function hallCardMinPrice(h) {
  if (!h || !h.package || !h.package.slotOffers) return null;
  let min = null;
  h.package.slotOffers.forEach(function (o) {
    if (!o.enabled) return;
    if (o.offerNoAc && o.priceNoAc != null) {
      min = min == null ? o.priceNoAc : Math.min(min, o.priceNoAc);
    }
    if (o.offerAc && o.priceAc != null) {
      min = min == null ? o.priceAc : Math.min(min, o.priceAc);
    }
  });
  return min;
}

function updateAddHallButtonState() {
  const addBtn = el('addHallBtn');
  if (!addBtn) return;
  const planned = Math.max(1, state.plannedHallCount || 1);
  const atLimit = state.hallSetupComplete && state.halls.length >= planned;
  addBtn.disabled = !!state.parkingEditOpen || atLimit;
}

function setHallBizDisabled(disabled) {
  state.parkingEditOpen = !!disabled;
  const zone = el('hallBizDisabledZone');
  if (zone) zone.classList.toggle('biz-home-disabled', !!disabled);
  updateAddHallButtonState();
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
  const labels = parkingLabelsForHallCount(count);
  if (lbl) lbl.textContent = labels.setupLbl;
  if (hint) hint.textContent = labels.hint;
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
  if (text) {
    text.innerHTML =
      '<span>🚗 Cars: ' +
      esc(String(p.car)) +
      '</span><span>🏍 Bikes: ' +
      esc(String(p.bike)) +
      '</span>';
  }
}

function renderHallCards() {
  const root = el('hallListCards');
  if (!root) return;
  if (!state.halls.length) {
    root.innerHTML =
      '<p class="sub" style="margin:8px 0 12px;padding:12px;border:1px dashed var(--line);border-radius:12px;text-align:center">No halls yet. Tap <b>Add Hall</b> to create your first hall.</p>';
    return;
  }
  root.innerHTML = state.halls
    .map(function (h) {
      const on = hallListingOn(h);
      const title = hallCardDisplayName(h);
      const guests = hallCardGuestCount(h);
      const hasAc = hallCardHasAc(h);
      const minPrice = hallCardMinPrice(h);
      const reqBadge = h.requests
        ? ' · <span style="color:var(--rd)">' + esc(String(h.requests)) + ' requests</span>'
        : '';
      const priceHtml = minPrice != null ? '<div class="hall-rich-price">' + inr(minPrice) + ' onwards</div>' : '';
      const calDisabled = !on;
      const reqDisabled = !on;
      return (
        '<div class="hall-card-rich' +
        (on ? '' : ' inactive') +
        '" data-hid="' +
        esc(h.id) +
        '">' +
        '<div class="hall-rich-top">' +
        '<div class="hall-thumb" aria-hidden="true"></div>' +
        '<div class="hall-rich-meta">' +
        '<b>' +
        esc(title) +
        '</b>' +
        '<div class="hall-rich-tags">' +
        '<span>👥 ' +
        esc(String(guests)) +
        ' guests</span>' +
        (hasAc ? '<span>❄ AC</span>' : '<span>No AC</span>') +
        reqBadge +
        '</div>' +
        priceHtml +
        '</div>' +
        '<label class="hall-rich-toggle hall-toggle" title="When off, this hall cannot be edited or booked">' +
        '<input type="checkbox" data-hall-toggle data-hid="' +
        esc(h.id) +
        '"' +
        (on ? ' checked' : '') +
        '><span class="hall-toggle-ui"></span>' +
        '<span class="hall-status-badge ' +
        (on ? 'on' : 'off') +
        '">' +
        (on ? 'Active' : 'Inactive') +
        '</span></label></div>' +
        '<div class="hall-actions-rich">' +
        '<button type="button" class="hall-act-btn" data-hall-act="cal" data-hid="' +
        esc(h.id) +
        '"' +
        (calDisabled ? ' disabled' : '') +
        '><span class="ico" aria-hidden="true">📅</span>Calendar</button>' +
        '<button type="button" class="hall-act-btn" data-hall-act="req" data-hid="' +
        esc(h.id) +
        '"' +
        (reqDisabled ? ' disabled' : '') +
        '><span class="ico" aria-hidden="true">📋</span>Requests</button>' +
        '<button type="button" class="hall-act-btn manage" data-hall-act="mgr" data-hid="' +
        esc(h.id) +
        '"><span class="ico" aria-hidden="true">⚙</span>Manage<span class="chev" aria-hidden="true">›</span></button>' +
        '</div></div>'
      );
    })
    .join('');
  root.querySelectorAll('[data-hall-toggle]').forEach(function (inp) {
    inp.onchange = function (e) {
      e.stopPropagation();
      const id = inp.getAttribute('data-hid');
      const h = state.halls.find(function (x) {
        return x.id === id;
      });
      if (!h) return;
      h.hallActive = !!inp.checked;
      savePkg();
      renderHallCards();
      if (state.activeHallId === id) syncHallInactiveLock();
    };
  });
  root.querySelectorAll('[data-hall-act]').forEach(function (btn) {
    btn.onclick = function () {
      if (state.parkingEditOpen) return;
      const hid = btn.getAttribute('data-hid');
      const h = state.halls.find(function (x) {
        return x.id === hid;
      });
      const act = btn.getAttribute('data-hall-act');
      if (!hallListingOn(h)) {
        if (act !== 'mgr') {
          toast('Turn this hall On using the toggle to use Calendar or Requests.');
          return;
        }
      }
      state.activeHallId = hid;
      loadActiveHallIntoState();
      if (act === 'mgr') {
        openManageScreen(false);
        return;
      }
      if (act === 'cal' || act === 'req') {
        if (!requireHallPackageSaved(h)) return;
      }
      if (act === 'cal') {
        openCalendarFlow();
        return;
      }
      if (act === 'req') {
        renderOwnerReq();
        show('ownerReq');
        syncHallInactiveLock();
      }
    };
  });
}

function renderHallBizHome() {
  const bizTitle = el('bizHomeTitle');
  if (bizTitle) bizTitle.textContent = state.businessName;
  const heroTitle = el('venueHeroTitle');
  if (heroTitle) heroTitle.textContent = state.businessName;
  const countLbl = el('hallCountLbl');
  if (countLbl) {
    const added = state.halls.length;
    const planned = Math.max(1, state.plannedHallCount || 1);
    if (planned > 1 && added !== planned) {
      countLbl.textContent = '(' + added + ' of ' + planned + ')';
    } else {
      countLbl.textContent = '(' + added + ')';
    }
  }
  const parkWrap = el('parkingBlockWrap');
  if (parkWrap) parkWrap.hidden = !state.hallSetupComplete;
  renderParkingSummary();
  renderHallCards();
  updateAddHallButtonState();
}

function openManageScreen(fromAddHall) {
  state.openedFromAddHall = !!fromAddHall;
  manageNameEditing = false;
  loadActiveHallIntoState();
  snapshotManageNameFromHall();
  renderManageHeader();
  renderManage();
  show('manage');
  syncHallInactiveLock();
}

function renderManageFooter() {
  const foot = el('manageSaveFooter');
  if (foot) foot.hidden = false;
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
    const mDot = m.dot ? '<span class="m-dot"></span>' : '';
    const ico = m.ico || 'cal';
    return (
      '<button type="button" class="mrow mrow-rich' +
      cls +
      '" data-go="' +
      m.id +
      '">' +
      '<span class="mico mico-' +
      ico +
      '">' +
      esc(m.icon || '•') +
      mDot +
      '</span>' +
      '<span class="mrow-text"><b>' +
      esc(m.title) +
      dot +
      '</b><span>' +
      esc(m.sub) +
      '</span></span>' +
      '<span class="mrow-chev" aria-hidden="true">›</span></button>'
    );
  }).join('');
  el('manageMenu').querySelectorAll('[data-go]').forEach((btn) => {
    btn.onclick = () => {
      if (!hallListingOn(activeHall())) {
        toast('This hall is Off. Turn it On from the Halls list to edit.');
        return;
      }
      const id = btn.getAttribute('data-go');
      if ((id === 'calendar' || id === 'operators') && !requireHallPackageSaved(activeHall())) {
        return;
      }
      if (id === 'ownerReq' && !requireHallPackageSaved(activeHall())) {
        return;
      }
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
      if (id === 'operators') {
        openOperatorsScreen();
        return;
      }
      if (id === 'hallPhotos') {
        openHallMediaScreen();
        return;
      }
      if (id === 'placeholder') {
        el('phTitle').textContent = btn.querySelector('b').textContent.replace(/\u200b/g, '');
        show('placeholder');
        syncHallInactiveLock();
        return;
      }
      if (id === 'calendar') {
        openCalendarFlow();
        return;
      }
      show(id);
      if (id === 'pkg1') renderPkg1();
      if (id === 'ownerReq') renderOwnerReq();
      syncHallInactiveLock();
    };
  });
  syncHallInactiveLock();
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
  syncHallNameUi();
  el('facGrid').innerHTML = FACILITIES.map(function (f) {
    const on = state.facilities.includes(f);
    const icon = FACILITY_ICONS[f] || '•';
    return (
      '<label class="fac-tile' +
      (on ? ' on' : '') +
      '"><input type="checkbox" data-fac="' +
      esc(f) +
      '"' +
      (on ? ' checked' : '') +
      '><span class="fac-ico" aria-hidden="true">' +
      icon +
      '</span><span>' +
      esc(f) +
      '</span></label>'
    );
  }).join('');
  el('facGrid').querySelectorAll('[data-fac]').forEach((cb) => {
    cb.onchange = () => {
      const f = cb.getAttribute('data-fac');
      if (cb.checked) {
        if (!state.facilities.includes(f)) state.facilities.push(f);
      } else state.facilities = state.facilities.filter((x) => x !== f);
      renderPkg2();
    };
  });
  const q = function (key, label) {
    const yesOn = state.catering[key] === 'yes';
    const noOn = state.catering[key] === 'no';
    return (
      '<div class="cater-q"><p>' +
      esc(label) +
      '</p><div class="cater-yn">' +
      '<label class="' +
      (yesOn ? 'on' : '') +
      '"><input type="radio" name="' +
      key +
      '" value="yes"' +
      (yesOn ? ' checked' : '') +
      '> Yes</label>' +
      '<label class="' +
      (noOn ? 'on' : '') +
      '"><input type="radio" name="' +
      key +
      '" value="no"' +
      (noOn ? ' checked' : '') +
      '> No</label></div></div>'
    );
  };
  el('caterDec').innerHTML =
    q('inHouse', 'In-house catering available?') +
    q('outside', 'Outside catering allowed?') +
    q('decorHall', 'Decoration provided by hall?') +
    q('decorOutside', 'Outside decorators allowed?');
  el('caterDec').querySelectorAll('input[type=radio]').forEach((r) => {
    r.onchange = () => {
      state.catering[r.name] = r.value;
      renderPkg2();
    };
  });
}

function renderSlotOfferRow(o) {
  const acFull = o.acMode !== 'limited';
  const isFlexible = o.acLimitKind !== 'fixed';
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
    '<p class="sub" style="margin:0 0 8px">Type how many AC hours are included in your price. Customers do not enter this number — they see what you set.</p>' +
    '<label class="radio-row"><input type="radio" name="acMode_' +
    esc(o.id) +
    '" value="full"' +
    (acFull ? ' checked' : '') +
    '> AC for full hall window</label>' +
    '<label class="radio-row"><input type="radio" name="acMode_' +
    esc(o.id) +
    '" value="limited"' +
    (!acFull ? ' checked' : '') +
    '> AC for part of the hall window</label>' +
    '<div class="ac-limited-fields"' +
    (acFull || !o.offerAc ? ' hidden' : '') +
    '>' +
    '<div class="fld ac-hours-shared"><label>AC hours included in With AC price</label><input type="number" data-field="acHours" min="0" step="0.5" value="' +
    (o.acHours || '') +
    '" placeholder="e.g. 5"><small class="sub">Example: 5 hours AC in a 12-hour hall hire — you type the included hours here.</small></div>' +
    '<label class="radio-row" style="margin-top:10px"><input type="radio" name="acLimit_' +
    esc(o.id) +
    '" value="flexible"' +
    (isFlexible ? ' checked' : '') +
    '> <b>Flexible timing</b><br><span class="sub" style="font-weight:600">Customer sees included hours only. They consult your hall management to agree when AC runs (not chosen in the app).</span></label>' +
    '<label class="radio-row" style="margin-top:8px"><input type="radio" name="acLimit_' +
    esc(o.id) +
    '" value="fixed"' +
    (!isFlexible ? ' checked' : '') +
    '> <b>Fixed AC schedule</b><br><span class="sub" style="font-weight:600">Same included hours above, plus exact clock times when your hall always runs AC.</span></label>' +
    '<div class="ac-fixed-fields"' +
    (isFlexible ? ' hidden' : '') +
    '><p class="lbl" style="margin:10px 0 6px">Exact AC clock times (with hours included above)</p>' +
    '<div class="two">' +
    '<div class="fld"><label>AC from</label><input type="time" data-field="acFrom" value="' +
    esc(o.acFrom || '') +
    '"></div>' +
    '<div class="fld"><label>AC to</label><input type="time" data-field="acTo" value="' +
    esc(o.acTo || '') +
    '"></div></div></div></div></div></div></div>'
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
      const limitFixed = row.querySelector('input[name=acLimit_' + id + '][value=fixed]');
      const fixedWrap = row.querySelector('.ac-fixed-fields');
      const useFixed = limitFixed && limitFixed.checked;
      if (fixedWrap) fixedWrap.hidden = !offerAc || !limited || !limited.checked || !useFixed;
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
    if (o.offerAc && o.acMode === 'limited') {
      if (!o.acHours) {
        toast(o.label + ': enter AC hours included in the With AC price (e.g. 5).');
        return false;
      }
      if (o.acLimitKind === 'fixed' && (!o.acFrom || !o.acTo)) {
        toast(o.label + ': fixed schedule needs AC from and AC to times as well as included hours.');
        return false;
      }
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
    const limitEl = row.querySelector('input[name=acLimit_' + id + ']:checked');
    o.acLimitKind = limitEl && limitEl.value === 'fixed' ? 'fixed' : 'flexible';
    o.acHours = +row.querySelector('[data-field=acHours]').value || 0;
    if (o.acLimitKind === 'fixed') {
      o.acFrom = row.querySelector('[data-field=acFrom]').value || '';
      o.acTo = row.querySelector('[data-field=acTo]').value || '';
    } else {
      o.acFrom = '';
      o.acTo = '';
    }
    if (!state.prices[o.id]) state.prices[o.id] = {};
    state.prices[o.id].noAc = o.priceNoAc;
    state.prices[o.id].ac = o.priceAc;
  });
  state.prices.extraNoAc = +(el('extraNoAc') && el('extraNoAc').value) || 0;
  state.prices.extraAc = +(el('extraAc') && el('extraAc').value) || 0;
}

function renderPkg4() {
  renderPkgSteps(4);
  ensurePolicyRules();
  const p = state.payment;
  const tab = pkg4PolicyTab === 'reschedule' ? 'reschedule' : 'cancel';
  const cancelOn = tab === 'cancel';
  el('payPolicy').innerHTML =
    '<p class="lbl">ADVANCE PAYMENT</p>' +
    '<label class="radio-row"><input type="radio" name="adv" value="fixed"' +
    (p.advanceType === 'fixed' ? ' checked' : '') +
    '> Fixed amount</label>' +
    '<div class="fld"><input type="number" id="advFixed" value="' +
    p.advanceFixed +
    '"></div>' +
    '<label class="radio-row"><input type="radio" name="adv" value="pct"' +
    (p.advanceType === 'pct' ? ' checked' : '') +
    '> Percentage of total</label>' +
    '<div class="fld"><input type="number" id="advPct" value="' +
    p.advancePct +
    '"> %</div>' +
    '<p class="lbl">FULL PAYMENT DUE</p>' +
    '<div class="fld"><label>Days before event</label><input type="number" id="fullDue" value="' +
    p.fullDueDays +
    '"></div>' +
    '<hr style="border:0;border-top:1px solid var(--line);margin:20px 0">' +
    '<h2 style="margin:0 0 4px;font-size:17px">Cancellation &amp; Rescheduling Policy</h2>' +
    '<p class="sub" style="margin:0 0 12px">Set deduction % by days before the event (from advance). Default tiers shown — remove ✕ or use + Add tier. Cancellation and rescheduling lists are separate.</p>' +
    '<div class="policy-tabs">' +
    '<button type="button" class="' +
    (cancelOn ? 'on' : '') +
    '" id="policyTabCancel">Cancellation Policy</button>' +
    '<button type="button" class="' +
    (!cancelOn ? 'on' : '') +
    '" id="policyTabResched">Rescheduling Policy</button></div>' +
    (cancelOn
      ? '<div class="policy-banner cancel"><span aria-hidden="true">ℹ️</span><span>Enter the deduction percentage for <b>cancellations</b>. This will be deducted from the advance amount.</span></div>' +
        policyRulesHtml('cancel') +
        '<div class="fld" style="margin-top:14px"><label>Additional notes (shown to customers)</label>' +
        '<textarea id="cancelPolicyNote" rows="3" placeholder="e.g. Refund balance after deduction within 7 working days.">' +
        esc(state.cancelPolicyNote) +
        '</textarea></div>'
      : '<div class="policy-banner resched"><span aria-hidden="true">ℹ️</span><span>Enter the deduction percentage for <b>rescheduling</b>. This will be deducted from the advance amount.</span></div>' +
        policyRulesHtml('reschedule') +
        '<div class="fld" style="margin-top:14px"><label>Additional notes (shown to customers)</label>' +
        '<textarea id="reschedulePolicyNote" rows="3" placeholder="e.g. New date must be within 6 months; one free reschedule if 30+ days notice.">' +
        esc(state.reschedulePolicyNote) +
        '</textarea></div>');
  attachPolicyRowHandlers();
  const tc = el('policyTabCancel');
  const tr = el('policyTabResched');
  if (tc) {
    tc.onclick = function () {
      capturePolicyRulesFromDom();
      capturePkg4PaymentOnly();
      pkg4PolicyTab = 'cancel';
      renderPkg4();
    };
  }
  if (tr) {
    tr.onclick = function () {
      capturePolicyRulesFromDom();
      capturePkg4PaymentOnly();
      pkg4PolicyTab = 'reschedule';
      renderPkg4();
    };
  }
}

function capturePkg4PaymentOnly() {
  const adv = document.querySelector('input[name=adv]:checked');
  state.payment.advanceType = adv && adv.value ? adv.value : 'fixed';
  if (el('advFixed')) state.payment.advanceFixed = +el('advFixed').value || 0;
  if (el('advPct')) state.payment.advancePct = +el('advPct').value || 0;
  if (el('fullDue')) state.payment.fullDueDays = +el('fullDue').value || 7;
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
  capturePolicyRulesFromDom();
  capturePkg4PaymentOnly();
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
    <div class="sum"><div class="hd"><b>Payment &amp; Policies</b><button type="button" class="see" data-to="pkg4">Edit</button></div>
      <p class="sub">Advance ₹${state.payment.advanceFixed.toLocaleString('en-IN')} · Full due ${state.payment.fullDueDays} days before</p>
      <p class="sub" style="margin-top:8px"><b>Cancellation</b> (from advance)<br>${esc(policySummaryLines(state.cancelRules, state.cancelPolicyNote))}</p>
      <p class="sub" style="margin-top:8px"><b>Rescheduling</b> (from advance)<br>${esc(policySummaryLines(state.rescheduleRules, state.reschedulePolicyNote))}</p></div>`;
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
    const h = activeHall();
    const wasSaved = h && h.packageSaved;
    commitHallPackageFromState();
    renderManageHeader();
    renderHallCards();
    toast(wasSaved ? 'Package updated — calendar uses your new slot times.' : 'Package saved on this device.');
    show('manage');
  };
}

let pendingRemoveOperatorId = null;

const OPERATOR_ROLE_LABELS = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };

function defaultOperatorsForHall() {
  return [
    { id: 'op_owner', name: 'Thomas Mathew', phone: '+91 94470 55566', role: 'owner' },
    { id: 'op_mgr1', name: 'John Kurian', phone: '+91 98765 12345', role: 'manager' },
  ];
}

function getHallOperators(h) {
  if (!h) return [];
  if (!h.operators || !h.operators.length) {
    h.operators = defaultOperatorsForHall().map(function (o) {
      return JSON.parse(JSON.stringify(o));
    });
  }
  return h.operators;
}

function defaultHallGallery() {
  return [
    { id: 'g1', label: 'Main hall' },
    { id: 'g2', label: 'Stage & lighting' },
  ];
}

function getHallGallery(h) {
  if (!h) return [];
  if (!h.hallGallery || !h.hallGallery.length) {
    h.hallGallery = defaultHallGallery().map(function (p) {
      return JSON.parse(JSON.stringify(p));
    });
  }
  return h.hallGallery;
}

function renderHallMedia() {
  const h = activeHall();
  const sub = el('hallMediaSub');
  const hallLabel = customerHallName() || state.businessName;
  if (sub) {
    sub.textContent = hallLabel + ' — photos customers see before they book';
  }
  const grid = el('hallPhotoGrid');
  const gallery = getHallGallery(h);
  if (grid) {
    grid.innerHTML =
      gallery
        .map(function (p) {
          return (
            '<div class="photo-tile" data-photo-id="' +
            esc(p.id) +
            '"><span class="tile-cap">' +
            esc(p.label) +
            '</span></div>'
          );
        })
        .join('') + '<button type="button" class="photo-tile add" id="addGalleryTile">+ Add photo</button>';
    const addTile = el('addGalleryTile');
    if (addTile) {
      addTile.onclick = function () {
        if (!hallListingOn(h)) {
          toast('Turn this hall On to add photos.');
          return;
        }
        const id = 'g' + Date.now();
        gallery.push({ id: id, label: 'New photo' });
        savePkg();
        renderHallMedia();
        toast('Photo added (demo — upload in full app).');
      };
    }
  }
}

function openHallMediaScreen() {
  renderHallMedia();
  show('hallMedia');
  syncHallInactiveLock();
}

function bindHallMediaUi() {
  const back = el('backFromHallMedia');
  if (back) {
    back.onclick = function () {
      show('manage');
      syncHallInactiveLock();
    };
  }
  const changeCover = el('changeCoverBtn');
  if (changeCover) {
    changeCover.onclick = function () {
      if (!hallListingOn(activeHall())) {
        toast('Turn this hall On to change the cover photo.');
        return;
      }
      toast('Cover photo picker — camera / gallery in full app.');
    };
  }
  const addBtn = el('hallMediaAddBtn');
  if (addBtn) {
    addBtn.onclick = function () {
      const h = activeHall();
      if (!hallListingOn(h)) {
        toast('Turn this hall On to add photos.');
        return;
      }
      const gallery = getHallGallery(h);
      gallery.push({ id: 'g' + Date.now(), label: 'New photo' });
      savePkg();
      renderHallMedia();
      toast('Photo added (demo).');
    };
  }
}

function operatorInitial(name) {
  const p = String(name || '?').trim().split(/\s+/);
  return (p[0][0] || '?').toUpperCase();
}

function formatOperatorRole(role) {
  return OPERATOR_ROLE_LABELS[role] || 'Staff';
}

function renderOperators() {
  const h = activeHall();
  const list = el('operatorsList');
  const sub = el('operatorsSub');
  if (sub) {
    sub.textContent = state.businessName
      ? 'Who can manage this business · ' + state.businessName
      : 'Who can manage this business';
  }
  if (!list) return;
  const ops = getHallOperators(h);
  if (!ops.length) {
    list.innerHTML = '<p class="sub">No operators yet. Add someone to help manage calendar and requests.</p>';
    return;
  }
  list.innerHTML = ops
    .map(function (op, idx) {
      const avClass = 'a' + (idx % 4);
      const roleLabel = formatOperatorRole(op.role);
      const right =
        op.role === 'owner'
          ? '<span class="op-owner-tag">Owner</span>'
          : '<button type="button" class="op-remove" data-rm-op="' + esc(op.id) + '">Remove</button>';
      return (
        '<div class="op-card">' +
        '<div class="op-avatar ' +
        avClass +
        '">' +
        esc(operatorInitial(op.name)) +
        '</div>' +
        '<div class="op-meta"><b>' +
        esc(op.name) +
        '</b><span>' +
        esc(op.phone) +
        ' · ' +
        esc(roleLabel) +
        '</span></div>' +
        '<div class="op-actions">' +
        right +
        '</div></div>'
      );
    })
    .join('');
  list.querySelectorAll('[data-rm-op]').forEach(function (btn) {
    btn.onclick = function () {
      if (!hallListingOn(h)) {
        toast('Turn this hall On to manage operators.');
        return;
      }
      pendingRemoveOperatorId = btn.getAttribute('data-rm-op');
      const op = ops.find(function (x) {
        return x.id === pendingRemoveOperatorId;
      });
      const body = el('removeOperatorBody');
      if (body && op) {
        body.textContent =
          'Remove ' + op.name + '? They will no longer manage bookings or calendar for this hall.';
      }
      openOverlay('removeOperatorOverlay');
    };
  });
}

function openOperatorsScreen() {
  renderOperators();
  show('operators');
  syncHallInactiveLock();
}

function bindOperatorsUi() {
  const back = el('backFromOperators');
  if (back) {
    back.onclick = function () {
      show('manage');
      syncHallInactiveLock();
    };
  }
  const addBtn = el('addOperatorBtn');
  if (addBtn) {
    addBtn.onclick = function () {
      if (!hallListingOn(activeHall())) {
        toast('Turn this hall On to add operators.');
        return;
      }
      if (el('addOpName')) el('addOpName').value = '';
      if (el('addOpPhone')) el('addOpPhone').value = '';
      if (el('addOpRole')) el('addOpRole').value = 'manager';
      openOverlay('addOperatorOverlay');
    };
  }
  ['closeAddOperator', 'cancelAddOperator'].forEach(function (id) {
    const b = el(id);
    if (b) b.onclick = function () { closeOverlay('addOperatorOverlay'); };
  });
  const saveAdd = el('saveAddOperator');
  if (saveAdd) {
    saveAdd.onclick = function () {
      const name = el('addOpName') ? el('addOpName').value.trim() : '';
      const phone = el('addOpPhone') ? el('addOpPhone').value.trim() : '';
      const role = el('addOpRole') ? el('addOpRole').value : 'manager';
      if (!name) {
        toast('Enter the operator name.');
        return;
      }
      if (!phone) {
        toast('Enter a mobile number.');
        return;
      }
      const h = activeHall();
      const ops = getHallOperators(h);
      ops.push({
        id: 'op_' + Date.now(),
        name: name,
        phone: phone,
        role: role === 'staff' ? 'staff' : 'manager',
      });
      savePkg();
      closeOverlay('addOperatorOverlay');
      renderOperators();
      toast('Operator added.');
    };
  }
  const cancelRm = el('cancelRemoveOperator');
  const confirmRm = el('confirmRemoveOperator');
  if (cancelRm) {
    cancelRm.onclick = function () {
      pendingRemoveOperatorId = null;
      closeOverlay('removeOperatorOverlay');
    };
  }
  if (confirmRm) {
    confirmRm.onclick = function () {
      if (!pendingRemoveOperatorId) return;
      const h = activeHall();
      const ops = getHallOperators(h);
      const target = ops.find(function (o) {
        return o.id === pendingRemoveOperatorId;
      });
      if (target && target.role === 'owner') {
        toast('Owner cannot be removed here.');
        closeOverlay('removeOperatorOverlay');
        pendingRemoveOperatorId = null;
        return;
      }
      h.operators = ops.filter(function (o) {
        return o.id !== pendingRemoveOperatorId;
      });
      pendingRemoveOperatorId = null;
      savePkg();
      closeOverlay('removeOperatorOverlay');
      renderOperators();
      toast('Operator removed.');
    };
  }
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
        if (!String(state.hallName || '').trim()) {
          toast('Enter a hall name (e.g. Hall 1 or Koinonia).');
          return;
        }
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
      if (id === 'calendar') renderCalendar();
      if (id === 'calDay') renderCalDay();
      show(id);
    });
  });
  const saveBs = el('saveBookSettings');
  if (saveBs) {
    saveBs.onclick = () => {
      savePkg();
      toast('Booking settings saved.');
      renderCalendar();
      show('calendar');
    };
  }
  bindCalendarUi();
  bindOperatorsUi();
  bindHallMediaUi();
  bindPackageRequiredUi();
  bindVenueEditUi();
  const addHall = el('addHallBtn');
  if (addHall) {
    addHall.onclick = function () {
      if (state.parkingEditOpen) return;
      const planned = Math.max(1, state.plannedHallCount || 1);
      if (state.halls.length >= planned) {
        toast('All ' + planned + ' halls are added. Use Edit on parking to add more hall slots.');
        return;
      }
      const id = 'h' + Date.now();
      const hallNum = nextHallNumber();
      const defaultName = defaultHallLabelForNumber(hallNum);
      state.halls.push({
        id: id,
        hallNumber: hallNum,
        useHallName: true,
        hallName: defaultName,
        requests: 0,
        hallActive: true,
        packageSaved: false,
      });
      state.activeHallId = id;
      state.useHallName = true;
      state.hallName = defaultName;
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
      if (!validateHallNameRequired()) return;
      syncActiveHallFromState();
      const fromAdd = state.openedFromAddHall;
      state.openedFromAddHall = false;
      savePkg();
      renderManageFooter();
      renderHallBizHome();
      renderManageNameMode();
      renderManageHeader();
      if (fromAdd) {
        show('hallBizHome');
      }
      const planned = Math.max(1, state.plannedHallCount || 1);
      if (fromAdd && state.halls.length >= planned && planned > 1) {
        toast('Hall saved. All ' + planned + ' halls are added for this venue.');
      } else {
        toast('Hall saved.');
      }
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
  const manageNameIn = el('manageHallNameInput');
  if (manageNameIn) {
    manageNameIn.oninput = function () {
      state.useHallName = true;
      state.hallName = manageNameIn.value;
    };
  }
  const hallNameIn = el('hallNameInput');
  if (hallNameIn) {
    hallNameIn.oninput = function () {
      state.useHallName = true;
      state.hallName = hallNameIn.value;
    };
  }
}

function boot() {
  try {
    if (!el('manageMenu')) {
      throw new Error('Missing #manageMenu — download DOWNLOAD-gixbee-hall-owner.html (full file).');
    }
    loadPkg();
    ensureSlotOffers();
    ensurePolicyRules();
    if (!state.commonParking) state.commonParking = { car: 80, bike: 120 };
    if (state.hallSetupComplete && (!state.halls || !state.halls.length)) {
      /* halls stay empty until owner uses + Add hall */
    }
    if (!state.halls) state.halls = [];
    normalizeHallRecords();
    if (!state.activeHallId && state.halls[0]) state.activeHallId = state.halls[0].id;
    if (state.activeHallId && !state.halls.find(function (h) { return h.id === state.activeHallId; })) {
      state.activeHallId = state.halls[0] ? state.halls[0].id : '';
    }
    if (state.halls.length) loadActiveHallIntoState();
    renderSetupScreen();
    renderHallBizHome();
    renderManage();
    bindOwnerEvents();
    setHallBizDisabled(false);
    closeOverlay('venueEditOverlay');
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
