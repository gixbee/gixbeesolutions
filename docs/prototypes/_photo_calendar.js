/* Photography owner — calendar & bookings (ERP-style, multi-shoot per day) */

const PHOTO_MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const PHOTO_DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

let photoPendingBook = null;
let photoPendingBookDateKey = null;
let photoAuditBookingId = null;

function photoCalDateKey(y, m, d) {
  return y + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
}

function photoParseCalDateKey(key) {
  const p = String(key).split('-');
  return { y: +p[0], m: +p[1], d: +p[2] };
}

function photoDaysInMonth(y, m) {
  return new Date(y, m, 0).getDate();
}

function photoMonthLabel(y, m) {
  return PHOTO_MONTH_NAMES[m - 1] + ' ' + y;
}

function photoFormatCalDayTitle(key) {
  const p = photoParseCalDateKey(key);
  const dt = new Date(p.y, p.m - 1, p.d);
  return p.d + ' ' + PHOTO_MONTH_NAMES[p.m - 1].slice(0, 3) + ' ' + p.y + ', ' + PHOTO_DAY_NAMES[dt.getDay()];
}

function defaultPhotoCalendar() {
  const now = new Date(2026, 9, 8);
  return {
    viewYear: now.getFullYear(),
    viewMonth: now.getMonth() + 1,
    selectedKey: photoCalDateKey(now.getFullYear(), now.getMonth() + 1, now.getDate()),
    activeTab: 'grid',
    sessionOperatorId: 'op_owner',
    settings: {
      maxBookingsPerDay: 3,
      bookWindowMonths: 6,
      minNoticeDays: 2,
    },
    days: {},
  };
}

function ensurePhotoCalendar() {
  if (!store.calendar) store.calendar = defaultPhotoCalendar();
  const cal = store.calendar;
  if (!cal.settings) cal.settings = defaultPhotoCalendar().settings;
  if (!cal.days) cal.days = {};
  if (!cal.selectedKey) {
    cal.selectedKey = photoCalDateKey(cal.viewYear, cal.viewMonth, 1);
  }
  seedPhotoCalendarDemo(cal);
  Object.keys(cal.days).forEach(function (key) {
    (cal.days[key].bookings || []).forEach(photoEnsureBookingShape);
  });
  return cal;
}

function seedPhotoCalendarDemo(cal) {
  if (cal._demoSeeded) return;
  if (Object.keys(cal.days).length > 3) {
    cal._demoSeeded = true;
    return;
  }
  cal.days['2026-10-10'] = {
    bookings: [
      photoNewBookingRecord({
        id: 'bk-demo-1',
        client: 'Anjali & Rohit',
        phone: '+91 98470 11220',
        event: 'Engagement',
        time: '10:00 AM – 2:00 PM',
        source: 'gixbee',
        notes: 'Outdoor at Sakthan Nagar park',
        operatorId: 'op_owner',
      }),
      photoNewBookingRecord({
        id: 'bk-demo-2',
        client: 'Thomas Family',
        phone: '+91 94470 55661',
        event: 'Portrait',
        time: '4:00 PM – 5:30 PM',
        source: 'offline',
        notes: 'Studio slot',
        operatorId: 'op_mgr1',
      }),
    ],
  };
  cal.days['2026-10-12'] = {
    dayStatus: 'disabled',
    dayNote: 'Team on wedding travel — not taking new bookings',
    bookings: [],
  };
  cal.days['2026-10-15'] = {
    dayStatus: 'full',
    dayNote: 'Festival week — capacity reached',
    bookings: [
      photoNewBookingRecord({
        id: 'bk-demo-3',
        client: 'Memorial Service',
        phone: '+91 98765 00011',
        event: 'Funeral / Memorial',
        time: '9:00 AM – 1:00 PM',
        source: 'offline',
        notes: '',
        operatorId: 'op_owner',
      }),
    ],
  };
  cal._demoSeeded = true;
}

function photoOperatorName(operatorId) {
  ensureOperators();
  const op = store.operators.find(function (o) {
    return o.id === operatorId;
  });
  return op ? op.name : 'Unknown';
}

function photoSessionOperatorId() {
  const cal = ensurePhotoCalendar();
  if (cal.sessionOperatorId) return cal.sessionOperatorId;
  ensureOperators();
  const owner = store.operators.find(function (o) {
    return o.role === 'owner';
  });
  return owner ? owner.id : store.operators[0] ? store.operators[0].id : 'op_owner';
}

function photoNowIso() {
  return new Date().toISOString();
}

function photoNewBookingRecord(partial) {
  const opId = partial.operatorId || photoSessionOperatorId();
  const rec = {
    id: partial.id || null,
    client: partial.client || '',
    phone: partial.phone || '',
    event: partial.event || 'Event',
    time: partial.time || 'TBD',
    source: partial.source || 'offline',
    notes: partial.notes || '',
    status: partial.status || 'confirmed',
    operatorId: opId,
    operatorName: photoOperatorName(opId),
    createdAt: partial.createdAt || photoNowIso(),
    createdBy: partial.createdBy || opId,
    auditLog: partial.auditLog || [],
  };
  if (!rec.auditLog.length) {
    rec.auditLog.push({
      at: rec.createdAt,
      by: rec.createdBy,
      byName: photoOperatorName(rec.createdBy),
      action: 'created',
      changes: {},
    });
  }
  return rec;
}

function photoEnsureBookingShape(b) {
  if (!b.auditLog) b.auditLog = [];
  if (!b.operatorId) b.operatorId = photoSessionOperatorId();
  if (!b.operatorName) b.operatorName = photoOperatorName(b.operatorId);
  if (!b.createdAt) b.createdAt = photoNowIso();
  return b;
}

function photoAppendBookingAudit(booking, action, changes) {
  photoEnsureBookingShape(booking);
  const by = photoSessionOperatorId();
  booking.auditLog.push({
    at: photoNowIso(),
    by: by,
    byName: photoOperatorName(by),
    action: action,
    changes: changes || {},
  });
}

function photoBookingFieldLabels() {
  return {
    client: 'Client',
    phone: 'Phone',
    event: 'Event',
    time: 'Time',
    source: 'Source',
    notes: 'Notes',
    operatorId: 'Operator',
  };
}

function photoDiffBooking(prev, next) {
  const labels = photoBookingFieldLabels();
  const changes = {};
  Object.keys(labels).forEach(function (k) {
    const a = prev[k] != null ? String(prev[k]) : '';
    const b = next[k] != null ? String(next[k]) : '';
    if (a !== b) {
      changes[k] = {
        label: labels[k],
        from: k === 'operatorId' ? photoOperatorName(a) || a : a,
        to: k === 'operatorId' ? photoOperatorName(b) || b : b,
      };
    }
  });
  return changes;
}

function photoFindBooking(bookingId) {
  const cal = ensurePhotoCalendar();
  let found = null;
  Object.keys(cal.days).forEach(function (key) {
    const day = cal.days[key];
    (day.bookings || []).forEach(function (b) {
      if (b.id === bookingId) found = { key: key, booking: b };
    });
  });
  return found;
}

function photoBookingsInMonth(y, m) {
  const cal = ensurePhotoCalendar();
  const dim = photoDaysInMonth(y, m);
  const rows = [];
  for (let d = 1; d <= dim; d++) {
    const key = photoCalDateKey(y, m, d);
    const day = cal.days[key];
    if (!day || !day.bookings) continue;
    photoActiveBookings(day).forEach(function (b) {
      photoEnsureBookingShape(b);
      rows.push({ dateKey: key, booking: b });
    });
  }
  rows.sort(function (a, b) {
    if (a.dateKey !== b.dateKey) return a.dateKey < b.dateKey ? -1 : 1;
    return (a.booking.time || '').localeCompare(b.booking.time || '');
  });
  return rows;
}

function photoSetCalTab(tab) {
  const cal = ensurePhotoCalendar();
  cal.activeTab = tab;
  const grid = el('photoCalPanelGrid');
  const list = el('photoCalPanelList');
  const tabMain = el('photoTabCalMain');
  const tabList = el('photoTabBookList');
  const tabSet = el('photoTabBookSettings');
  if (tabMain) tabMain.classList.toggle('on', tab === 'grid');
  if (tabList) tabList.classList.toggle('on', tab === 'list');
  if (tabSet) tabSet.classList.toggle('on', tab === 'settings');
  if (grid) grid.hidden = tab !== 'grid';
  if (list) list.hidden = tab !== 'list';
}

function photoEnsureDay(cal, key) {
  if (!cal.days[key]) cal.days[key] = { bookings: [] };
  if (!cal.days[key].bookings) cal.days[key].bookings = [];
  return cal.days[key];
}

function photoActiveBookings(day) {
  return (day.bookings || []).filter(function (b) {
    return b.status !== 'cancelled';
  });
}

function photoDayCapacityUsed(cal, key) {
  const day = cal.days[key];
  if (!day) return 0;
  return photoActiveBookings(day).length;
}

function photoDayIsFull(cal, key) {
  const day = cal.days[key];
  if (day && day.dayStatus === 'full') return true;
  const max = cal.settings.maxBookingsPerDay || 1;
  return photoDayCapacityUsed(cal, key) >= max;
}

function photoDayDotKind(cal, key) {
  const day = cal.days[key];
  if (!day) return 'av';
  if (day.dayStatus === 'disabled') return 'na';
  if (day.dayStatus === 'full' || photoDayIsFull(cal, key)) return 'bk';
  const active = photoActiveBookings(day);
  if (!active.length) return 'av';
  if (active.some(function (b) {
    return b.source === 'gixbee';
  }))
    return 'bk';
  return 'off';
}

function photoOpenOverlay(id) {
  const o = el(id);
  if (o) {
    o.classList.add('on');
    o.setAttribute('aria-hidden', 'false');
  }
}

function photoCloseOverlay(id) {
  const o = el(id);
  if (o) {
    o.classList.remove('on');
    o.setAttribute('aria-hidden', 'true');
  }
}

function openPhotoCalendar() {
  ensurePhotoCalendar();
  const cal = store.calendar;
  const chip = el('calBuildChip');
  if (chip && typeof PHOTO_OWNER_BUILD !== 'undefined') chip.textContent = 'Cal ' + PHOTO_OWNER_BUILD.split('-').pop();
  if (cal.activeTab === 'list') {
    photoSetCalTab('list');
    renderPhotoBookingRegister();
  } else {
    photoSetCalTab('grid');
    renderPhotoCalendar();
  }
  show('calendar');
}

function renderPhotoCalendar() {
  const cal = ensurePhotoCalendar();
  const y = cal.viewYear;
  const m = cal.viewMonth;
  const ml = el('photoCalMonthLabel');
  const mpl = el('photoCalMonthPickLabel');
  if (ml) ml.textContent = photoMonthLabel(y, m);
  if (mpl) mpl.textContent = photoMonthLabel(y, m);
  const firstDow = new Date(y, m - 1, 1).getDay();
  const dim = photoDaysInMonth(y, m);
  const cells = [];
  for (let i = 0; i < firstDow; i++) cells.push('<span class="cal-pad"></span>');
  const max = cal.settings.maxBookingsPerDay || 3;
  for (let d = 1; d <= dim; d++) {
    const key = photoCalDateKey(y, m, d);
    const dot = photoDayDotKind(cal, key);
    const cnt = photoDayCapacityUsed(cal, key);
    const on = cal.selectedKey === key ? ' on' : '';
    const countHtml =
      cnt > 0 ? '<span class="cal-day-count">' + cnt + '/' + max + '</span>' : '<span class="cal-day-count empty"></span>';
    cells.push(
      '<button type="button" class="cal-day-cell' +
        on +
        '" data-photo-cal-day="' +
        d +
        '" data-photo-cal-key="' +
        key +
        '"><span>' +
        d +
        '</span>' +
        countHtml +
        '<i class="cal-dot ' +
        dot +
        '"></i></button>'
    );
  }
  const grid = el('photoCalGrid');
  if (!grid) return;
  grid.innerHTML = cells.join('');
  grid.querySelectorAll('[data-photo-cal-key]').forEach(function (btn) {
    btn.onclick = function () {
      cal.selectedKey = btn.getAttribute('data-photo-cal-key');
      saveStore();
      renderPhotoCalDay();
      show('photoCalDay');
    };
  });
  photoSetCalTab(store.calendar.activeTab || 'grid');
}

function renderPhotoBookingRegister() {
  const cal = ensurePhotoCalendar();
  const y = cal.viewYear;
  const m = cal.viewMonth;
  const ml = el('photoCalMonthLabel');
  const mpl = el('photoCalMonthPickLabel');
  const mpl2 = el('photoCalMonthPickLabelList');
  const label = photoMonthLabel(y, m);
  if (ml) ml.textContent = label;
  if (mpl) mpl.textContent = label;
  if (mpl2) mpl2.textContent = label;
  const rows = photoBookingsInMonth(y, m);
  const stats = el('photoBkRegisterStats');
  if (stats) {
    const daysWith = {};
    rows.forEach(function (r) {
      daysWith[r.dateKey] = true;
    });
    stats.innerHTML =
      '<div class="photo-reg-stat"><b>' +
      rows.length +
      '</b><span>Bookings this month</span></div>' +
      '<div class="photo-reg-stat"><b>' +
      Object.keys(daysWith).length +
      '</b><span>Days with shoots</span></div>';
  }
  const list = el('photoBkRegisterList');
  if (!list) return;
  if (!rows.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:12px 0"><div class="hub-empty-ico">📋</div><b>No bookings</b><p class="sub">No active shoots in ' +
      esc(label) +
      '. Add from Calendar or open a day schedule.</p></div>';
    return;
  }
  let html = '';
  let lastKey = '';
  rows.forEach(function (row) {
    if (row.dateKey !== lastKey) {
      lastKey = row.dateKey;
      const cnt = rows.filter(function (x) {
        return x.dateKey === row.dateKey;
      }).length;
      html +=
        '<p class="photo-bk-register-date">' +
        esc(photoFormatCalDayTitle(row.dateKey)) +
        ' · ' +
        cnt +
        ' booking' +
        (cnt === 1 ? '' : 's') +
        '</p>';
    }
    const b = row.booking;
    html +=
      '<button type="button" class="photo-bk-register-row" data-photo-reg-key="' +
      esc(row.dateKey) +
      '" data-photo-reg-id="' +
      esc(b.id) +
      '"><span class="bk-time">' +
      esc((b.time || '').split('–')[0].trim() || '—') +
      '</span><span class="bk-meta"><b>' +
      esc(b.client) +
      '</b><span>' +
      esc(b.event) +
      ' · ' +
      (b.source === 'gixbee' ? 'Gixbee' : 'Offline') +
      (b.auditLog && b.auditLog.length > 1 ? ' · edited' : '') +
      '</span></span><span class="bk-op">' +
      esc(b.operatorName || '—') +
      '</span></button>';
  });
  list.innerHTML = html;
  list.querySelectorAll('.photo-bk-register-row').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoBookingDetail(btn.getAttribute('data-photo-reg-key'), btn.getAttribute('data-photo-reg-id'));
    };
  });
  photoSetCalTab('list');
}

function openPhotoBookingDetail(dateKey, bookingId) {
  const cal = ensurePhotoCalendar();
  cal.selectedKey = dateKey;
  cal.detailReturnTab = cal.activeTab || 'list';
  saveStore();
  renderPhotoBookingDetail(bookingId);
  show('photoBookingDetail');
}

function renderPhotoBookingDetail(bookingId) {
  const hit = photoFindBooking(bookingId);
  const body = el('photoBookingDetailBody');
  if (!body || !hit) {
    if (body) body.innerHTML = '<p class="sub">Booking not found.</p>';
    return;
  }
  const b = photoEnsureBookingShape(hit.booking);
  const key = hit.key;
  const edits = (b.auditLog || []).filter(function (e) {
    return e.action === 'updated' || e.action === 'cancelled';
  }).length;
  const auditCls = edits > 0 || (b.auditLog && b.auditLog.length > 1) ? ' has-changes' : '';
  body.innerHTML =
    '<p class="sub" style="margin:0 0 12px">' +
    esc(photoFormatCalDayTitle(key)) +
    '</p>' +
    '<span class="pill ' +
    (b.source === 'gixbee' ? 'bad' : 'off') +
    '">' +
    (b.source === 'gixbee' ? 'Gixbee' : 'Offline') +
    '</span>' +
    '<dl class="photo-detail-dl">' +
    '<dt>Client</dt><dd>' +
    esc(b.client) +
    '</dd>' +
    '<dt>Event</dt><dd>' +
    esc(b.event) +
    '</dd>' +
    '<dt>Time</dt><dd>' +
    esc(b.time) +
    '</dd>' +
    '<dt>Phone</dt><dd>' +
    esc(b.phone || '—') +
    '</dd>' +
    '<dt>Operator</dt><dd>' +
    esc(b.operatorName) +
    '</dd>' +
    '<dt>Notes</dt><dd style="font-weight:600;font-size:14px;line-height:1.45">' +
    esc(b.notes || '—') +
    '</dd></dl>' +
    '<button type="button" class="btn-audit-link' +
    auditCls +
    '" id="photoOpenAuditBtn">Change history (' +
    (b.auditLog ? b.auditLog.length : 0) +
    ')</button>' +
    '<div class="slot-actions" style="margin-top:20px">' +
    '<button type="button" class="btn btn-ghost" id="photoDetailEditBtn">Edit booking</button>' +
    '<button type="button" class="btn btn-ghost" style="color:#B91C1C;border-color:#FECACA" id="photoDetailCancelBtn">Cancel</button></div>';
  const auditBtn = el('photoOpenAuditBtn');
  if (auditBtn) {
    auditBtn.onclick = function () {
      openPhotoAuditLog(bookingId);
    };
  }
  el('photoDetailEditBtn').onclick = function () {
    const cal = ensurePhotoCalendar();
    cal.selectedKey = key;
    openPhotoBookSheet(bookingId, key);
  };
  el('photoDetailCancelBtn').onclick = function () {
    const cal = ensurePhotoCalendar();
    cal.selectedKey = key;
    cancelPhotoBooking(bookingId, true);
    renderPhotoBookingDetail(bookingId);
  };
}

function openPhotoAuditLog(bookingId) {
  const hit = photoFindBooking(bookingId);
  if (!hit) return;
  photoAuditBookingId = bookingId;
  const b = hit.booking;
  const sub = el('photoAuditSubtitle');
  if (sub) sub.textContent = b.client + ' · ' + photoFormatCalDayTitle(hit.key);
  const list = el('photoAuditList');
  if (!list) return;
  const entries = (b.auditLog || []).slice().reverse();
  list.innerHTML = entries
    .map(function (e) {
      let ch = '';
      if (e.changes && Object.keys(e.changes).length) {
        ch =
          '<div class="audit-changes">' +
          Object.keys(e.changes)
            .map(function (k) {
              const c = e.changes[k];
              return esc(c.label || k) + ': ' + esc(c.from || '—') + ' → ' + esc(c.to || '—');
            })
            .join('<br>') +
          '</div>';
      }
      const actionLabel =
        e.action === 'created'
          ? 'Created'
          : e.action === 'updated'
            ? 'Updated'
            : e.action === 'cancelled'
              ? 'Cancelled'
              : e.action;
      return (
        '<li class="photo-audit-item"><b>' +
        esc(actionLabel) +
        '</b> · ' +
        esc(e.byName || '—') +
        '<br><span class="hint">' +
        esc(new Date(e.at).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })) +
        '</span>' +
        ch +
        '</li>'
      );
    })
    .join('');
  photoOpenOverlay('photoAuditOverlay');
}

function photoFillOperatorSelect(selectedId) {
  const sel = el('photoBkOperator');
  if (!sel) return;
  ensureOperators();
  sel.innerHTML = store.operators
    .map(function (op) {
      return (
        '<option value="' +
        esc(op.id) +
        '"' +
        (op.id === selectedId ? ' selected' : '') +
        '>' +
        esc(op.name) +
        (op.role === 'owner' ? ' (Owner)' : '') +
        '</option>'
      );
    })
    .join('');
}

function photoDayStatusLabel(cal, key) {
  const day = cal.days[key];
  if (day && day.dayStatus === 'disabled') {
    return { pill: 'muted', text: 'Not available to customers' };
  }
  if (day && day.dayStatus === 'full') return { pill: 'bad', text: 'Marked full' };
  if (photoDayIsFull(cal, key)) return { pill: 'bad', text: 'Capacity reached' };
  const used = photoDayCapacityUsed(cal, key);
  const max = cal.settings.maxBookingsPerDay || 3;
  return { pill: 'ok', text: used + ' of ' + max + ' bookings' };
}

function renderPhotoCalDay() {
  const cal = ensurePhotoCalendar();
  const key = cal.selectedKey;
  const title = el('photoCalDayTitle');
  if (title) title.textContent = photoFormatCalDayTitle(key);
  const day = photoEnsureDay(cal, key);
  const st = photoDayStatusLabel(cal, key);
  const slots = el('photoDayBookings');
  if (!slots) return;

  let head =
    '<div class="photo-cal-day-sum"><span class="pill ' +
    st.pill +
    '">' +
    esc(st.text) +
    '</span>';
  if (day.dayNote) {
    head += '<p class="sub" style="margin:8px 0 0">' + esc(day.dayNote) + '</p>';
  }
  head += '</div>';

  const active = photoActiveBookings(day);
  const cards = active
    .map(function (b) {
      photoEnsureBookingShape(b);
      const srcPill = b.source === 'gixbee' ? '<span class="pill bad">Gixbee</span>' : '<span class="pill off">Offline</span>';
      return (
        '<div class="slot photo-bk-card" data-bk-id="' +
        esc(b.id) +
        '">' +
        srcPill +
        '<h3>' +
        esc(b.client) +
        '</h3>' +
        '<p class="sub" style="margin:4px 0"><b>' +
        esc(b.event) +
        '</b> · ' +
        esc(b.time) +
        '</p>' +
        '<p class="hint" style="margin:0">Operator: ' +
        esc(b.operatorName || '—') +
        '</p>' +
        (b.phone ? '<p class="hint" style="margin:0">' + esc(b.phone) + '</p>' : '') +
        (b.notes ? '<p class="photo-bk-notes">' + esc(b.notes) + '</p>' : '') +
        '<div class="slot-actions">' +
        '<button type="button" class="btn btn-ghost" data-photo-view-bk="' +
        esc(b.id) +
        '">Details</button>' +
        '<button type="button" class="btn btn-ghost" data-photo-edit-bk="' +
        esc(b.id) +
        '">Edit</button>' +
        '<button type="button" class="btn btn-ghost" style="color:#B91C1C;border-color:#FECACA" data-photo-cancel-bk="' +
        esc(b.id) +
        '">Cancel</button></div></div>'
      );
    })
    .join('');

  const canAdd = !photoDayIsFull(cal, key);
  const dayActions =
    '<div class="photo-day-actions">' +
    '<button type="button" class="btn btn-blue" data-photo-add-bk' +
    (canAdd ? '' : ' disabled') +
    '>+ Add booking</button>' +
    '<button type="button" class="btn btn-ghost" data-photo-day-status>Day availability</button></div>';

  slots.innerHTML =
    head + (cards || '<p class="sub" style="margin:12px 0">No shoots on this date yet.</p>') + dayActions;

  slots.querySelectorAll('[data-photo-add-bk]').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoBookSheet(null);
    };
  });
  slots.querySelectorAll('[data-photo-day-status]').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoDaySheet();
    };
  });
  slots.querySelectorAll('[data-photo-view-bk]').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoBookingDetail(key, btn.getAttribute('data-photo-view-bk'));
    };
  });
  slots.querySelectorAll('[data-photo-edit-bk]').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoBookSheet(btn.getAttribute('data-photo-edit-bk'), key);
    };
  });
  slots.querySelectorAll('[data-photo-cancel-bk]').forEach(function (btn) {
    btn.onclick = function () {
      cancelPhotoBooking(btn.getAttribute('data-photo-cancel-bk'));
    };
  });
}

function openPhotoBookSheet(bookingId, dateKey) {
  const cal = ensurePhotoCalendar();
  if (dateKey) cal.selectedKey = dateKey;
  const key = cal.selectedKey;
  photoPendingBookDateKey = key;
  const day = photoEnsureDay(cal, key);
  if (!bookingId) {
    photoPendingBook = photoNewBookingRecord({
      id: null,
      client: '',
      phone: '',
      event: 'Wedding',
      time: '10:00 AM – 6:00 PM',
      source: 'offline',
      notes: '',
      operatorId: photoSessionOperatorId(),
    });
  } else {
    const found = (day.bookings || []).find(function (b) {
      return b.id === bookingId;
    });
    photoPendingBook = found ? JSON.parse(JSON.stringify(found)) : null;
  }
  if (!photoPendingBook) return;
  photoFillOperatorSelect(photoPendingBook.operatorId || photoSessionOperatorId());
  const sum = el('photoBookSheetSum');
  if (sum) sum.textContent = photoFormatCalDayTitle(key);
  if (el('photoBkClient')) el('photoBkClient').value = photoPendingBook.client;
  if (el('photoBkPhone')) el('photoBkPhone').value = photoPendingBook.phone || '';
  if (el('photoBkEvent')) el('photoBkEvent').value = photoPendingBook.event;
  if (el('photoBkTime')) el('photoBkTime').value = photoPendingBook.time;
  if (el('photoBkNotes')) el('photoBkNotes').value = photoPendingBook.notes || '';
  document.querySelectorAll('[name=photoBkSource]').forEach(function (r) {
    r.checked = r.value === photoPendingBook.source;
  });
  const h2 = el('photoBookSheetTitle');
  if (h2) h2.textContent = bookingId ? 'Edit booking' : 'Add booking';
  photoOpenOverlay('photoBookSheetOverlay');
}

function savePhotoBookSheet() {
  if (!photoPendingBook) return;
  const cal = ensurePhotoCalendar();
  const key = cal.selectedKey;
  const day = photoEnsureDay(cal, key);
  photoPendingBook.client = el('photoBkClient').value.trim();
  photoPendingBook.phone = el('photoBkPhone').value.trim();
  photoPendingBook.event = el('photoBkEvent').value.trim() || 'Event';
  photoPendingBook.time = el('photoBkTime').value.trim() || 'TBD';
  photoPendingBook.notes = el('photoBkNotes').value.trim();
  const src = document.querySelector('input[name=photoBkSource]:checked');
  photoPendingBook.source = src ? src.value : 'offline';
  const opSel = el('photoBkOperator');
  if (opSel) {
    photoPendingBook.operatorId = opSel.value;
    photoPendingBook.operatorName = photoOperatorName(opSel.value);
  }
  if (!photoPendingBook.client) {
    toast('Enter client name.');
    return;
  }
  if (!photoPendingBook.id) {
    if (photoDayIsFull(cal, key)) {
      toast('Day is at capacity. Increase limit in Booking Settings or mark another day.');
      return;
    }
    photoPendingBook.id = uid('bk');
    photoPendingBook.status = 'confirmed';
    photoPendingBook.createdBy = photoSessionOperatorId();
    day.bookings.push(photoPendingBook);
  } else {
    const i = day.bookings.findIndex(function (b) {
      return b.id === photoPendingBook.id;
    });
    if (i >= 0) {
      const prev = JSON.parse(JSON.stringify(day.bookings[i]));
      const changes = photoDiffBooking(prev, photoPendingBook);
      if (Object.keys(changes).length) {
        photoAppendBookingAudit(photoPendingBook, 'updated', changes);
      }
      day.bookings[i] = photoPendingBook;
    }
  }
  const savedId = photoPendingBook.id;
  saveStore();
  photoCloseOverlay('photoBookSheetOverlay');
  photoPendingBook = null;
  photoPendingBookDateKey = null;
  renderPhotoCalendar();
  renderPhotoCalDay();
  renderPhotoBookingRegister();
  const detailScr = el('photoBookingDetail');
  if (detailScr && detailScr.classList.contains('on') && savedId) {
    renderPhotoBookingDetail(savedId);
  }
  toast('Booking saved.');
}

function cancelPhotoBooking(id, skipConfirm) {
  if (!skipConfirm && !confirm('Cancel this booking? It will be removed from the active day schedule.')) return;
  const cal = ensurePhotoCalendar();
  const day = photoEnsureDay(cal, cal.selectedKey);
  const b = day.bookings.find(function (x) {
    return x.id === id;
  });
  if (b) {
    b.status = 'cancelled';
    photoAppendBookingAudit(b, 'cancelled', { status: { label: 'Status', from: 'confirmed', to: 'cancelled' } });
  }
  saveStore();
  renderPhotoCalendar();
  renderPhotoCalDay();
  renderPhotoBookingRegister();
  toast('Booking cancelled.');
}

function openPhotoDaySheet() {
  const cal = ensurePhotoCalendar();
  const day = photoEnsureDay(cal, cal.selectedKey);
  const status = day.dayStatus || 'open';
  document.querySelectorAll('[name=photoDayStatus]').forEach(function (r) {
    r.checked = r.value === status;
  });
  if (el('photoDayNote')) el('photoDayNote').value = day.dayNote || '';
  photoOpenOverlay('photoDaySheetOverlay');
}

function savePhotoDaySheet() {
  const cal = ensurePhotoCalendar();
  const day = photoEnsureDay(cal, cal.selectedKey);
  const sel = document.querySelector('input[name=photoDayStatus]:checked');
  const status = sel ? sel.value : 'open';
  day.dayStatus = status === 'open' ? undefined : status;
  if (status === 'open') delete day.dayStatus;
  day.dayNote = el('photoDayNote') ? el('photoDayNote').value.trim() : '';
  if (!day.dayNote) delete day.dayNote;
  saveStore();
  photoCloseOverlay('photoDaySheetOverlay');
  renderPhotoCalendar();
  renderPhotoCalDay();
  toast(status === 'disabled' ? 'Day hidden from customers.' : status === 'full' ? 'Day marked full.' : 'Day reopened.');
}

function renderPhotoBookSettings() {
  const cal = ensurePhotoCalendar();
  const s = cal.settings;
  const maxOpts = [1, 2, 3, 4, 5, 6];
  const win = el('photoBookWindow');
  if (win) {
    win.innerHTML = [3, 6, 9, 12]
      .map(function (m) {
        return (
          '<button type="button" class="pick' +
          (s.bookWindowMonths === m ? ' on' : '') +
          '" data-photo-win="' +
          m +
          '">' +
          m +
          ' mo</button>'
        );
      })
      .join('');
    win.querySelectorAll('[data-photo-win]').forEach(function (btn) {
      btn.onclick = function () {
        s.bookWindowMonths = +btn.getAttribute('data-photo-win');
        saveStore();
        renderPhotoBookSettings();
      };
    });
  }
  const notice = el('photoMinNotice');
  if (notice) {
    notice.innerHTML = [0, 1, 2, 3, 7]
      .map(function (d) {
        return (
          '<button type="button" class="pick' +
          (s.minNoticeDays === d ? ' on' : '') +
          '" data-photo-notice="' +
          d +
          '">' +
          (d === 0 ? 'Same day' : d + ' day' + (d > 1 ? 's' : '')) +
          '</button>'
        );
      })
      .join('');
    notice.querySelectorAll('[data-photo-notice]').forEach(function (btn) {
      btn.onclick = function () {
        s.minNoticeDays = +btn.getAttribute('data-photo-notice');
        saveStore();
        renderPhotoBookSettings();
      };
    });
  }
  const cap = el('photoMaxPerDay');
  if (cap) {
    cap.innerHTML = maxOpts
      .map(function (n) {
        return (
          '<button type="button" class="pick' +
          (s.maxBookingsPerDay === n ? ' on' : '') +
          '" data-photo-max="' +
          n +
          '">' +
          n +
          '</button>'
        );
      })
      .join('');
    cap.querySelectorAll('[data-photo-max]').forEach(function (btn) {
      btn.onclick = function () {
        s.maxBookingsPerDay = +btn.getAttribute('data-photo-max');
        saveStore();
        renderPhotoBookSettings();
      };
    });
  }
  const wi = el('photoWindowInfo');
  if (wi) wi.textContent = 'Customers can book up to ' + s.bookWindowMonths + ' months ahead.';
  const ni = el('photoNoticeInfo');
  if (ni) {
    ni.textContent =
      s.minNoticeDays === 0
        ? 'Same-day booking is allowed (subject to capacity).'
        : 'Customers need at least ' + s.minNoticeDays + ' day(s) notice before the shoot date.';
  }
  const mi = el('photoMaxInfo');
  if (mi) {
    mi.textContent =
      'You can add up to ' + s.maxBookingsPerDay + ' active booking(s) per day. Calendar shows count on each date.';
  }
}

function photoShiftCalDay(delta) {
  const cal = ensurePhotoCalendar();
  const p = photoParseCalDateKey(cal.selectedKey);
  const dt = new Date(p.y, p.m - 1, p.d + delta);
  cal.viewYear = dt.getFullYear();
  cal.viewMonth = dt.getMonth() + 1;
  cal.selectedKey = photoCalDateKey(cal.viewYear, cal.viewMonth, dt.getDate());
  saveStore();
  renderPhotoCalDay();
}

function photoShiftCalMonth(delta) {
  const cal = ensurePhotoCalendar();
  let m = cal.viewMonth + delta;
  let y = cal.viewYear;
  if (m < 1) {
    m = 12;
    y--;
  }
  if (m > 12) {
    m = 1;
    y++;
  }
  cal.viewMonth = m;
  cal.viewYear = y;
  saveStore();
  if (cal.activeTab === 'list') renderPhotoBookingRegister();
  else renderPhotoCalendar();
}

function renderPhotoMonthPickerList() {
  const cal = ensurePhotoCalendar();
  const list = el('photoMonthPickerList');
  if (!list) return;
  const items = [];
  const start = new Date(2026, 0, 1);
  for (let i = 0; i < 18; i++) {
    const dt = new Date(start.getFullYear(), start.getMonth() + i, 1);
    const y = dt.getFullYear();
    const m = dt.getMonth() + 1;
    const on = y === cal.viewYear && m === cal.viewMonth;
    items.push(
      '<button type="button" class="pick' +
        (on ? ' on' : '') +
        '" data-photo-pick-y="' +
        y +
        '" data-photo-pick-m="' +
        m +
        '">' +
        photoMonthLabel(y, m) +
        '</button>'
    );
  }
  list.innerHTML = items.join('');
  list.querySelectorAll('[data-photo-pick-y]').forEach(function (btn) {
    btn.onclick = function () {
      cal.viewYear = +btn.getAttribute('data-photo-pick-y');
      cal.viewMonth = +btn.getAttribute('data-photo-pick-m');
      saveStore();
      photoCloseOverlay('photoMonthPickerOverlay');
      if (cal.activeTab === 'list') renderPhotoBookingRegister();
      else renderPhotoCalendar();
    };
  });
}

function bindPhotoCalendarUi() {
  const tabSet = el('photoTabBookSettings');
  if (tabSet) {
    tabSet.onclick = function () {
      const cal = ensurePhotoCalendar();
      cal.activeTab = 'settings';
      renderPhotoBookSettings();
      show('photoBookSettings');
    };
  }
  const tabList = el('photoTabBookList');
  if (tabList) {
    tabList.onclick = function () {
      const cal = ensurePhotoCalendar();
      cal.activeTab = 'list';
      saveStore();
      renderPhotoBookingRegister();
      show('calendar');
    };
  }
  const tabMain = el('photoTabCalMain');
  if (tabMain) {
    tabMain.onclick = function () {
      const cal = ensurePhotoCalendar();
      cal.activeTab = 'grid';
      saveStore();
      renderPhotoCalendar();
      show('calendar');
    };
  }
  const prevM = el('photoCalPrevMonth');
  const nextM = el('photoCalNextMonth');
  if (prevM) prevM.onclick = function () {
    photoShiftCalMonth(-1);
  };
  if (nextM) nextM.onclick = function () {
    photoShiftCalMonth(1);
  };
  const prevD = el('photoCalPrevDay');
  const nextD = el('photoCalNextDay');
  if (prevD) prevD.onclick = function () {
    photoShiftCalDay(-1);
  };
  if (nextD) nextD.onclick = function () {
    photoShiftCalDay(1);
  };
  const backDay = el('photoBackFromCalDay');
  if (backDay) {
    backDay.onclick = function () {
      renderPhotoCalendar();
      show('calendar');
    };
  }
  const openMp = el('photoOpenMonthPicker');
  if (openMp) {
    openMp.onclick = function () {
      renderPhotoMonthPickerList();
      photoOpenOverlay('photoMonthPickerOverlay');
    };
  }
  const openMpList = el('photoOpenMonthPickerList');
  if (openMpList) {
    openMpList.onclick = function () {
      renderPhotoMonthPickerList();
      photoOpenOverlay('photoMonthPickerOverlay');
    };
  }
  const backDet = el('photoBackFromBkDetail');
  if (backDet) {
    backDet.onclick = function () {
      const cal = ensurePhotoCalendar();
      const tab = cal.detailReturnTab || 'list';
      cal.activeTab = tab;
      saveStore();
      if (tab === 'list') {
        renderPhotoBookingRegister();
        show('calendar');
      } else {
        renderPhotoCalendar();
        show('calendar');
      }
    };
  }
  const closeAudit = el('photoCloseAudit');
  const closeAuditBtn = el('photoCloseAuditBtn');
  if (closeAudit) closeAudit.onclick = function () {
    photoCloseOverlay('photoAuditOverlay');
  };
  if (closeAuditBtn) closeAuditBtn.onclick = function () {
    photoCloseOverlay('photoAuditOverlay');
  };
  const saveBs = el('photoSaveBookSettings');
  if (saveBs) {
    saveBs.onclick = function () {
      saveStore();
      toast('Booking settings saved.');
      renderPhotoCalendar();
      show('calendar');
    };
  }
  const closeBk = el('photoCloseBookSheet');
  if (closeBk) closeBk.onclick = function () {
    photoCloseOverlay('photoBookSheetOverlay');
    photoPendingBook = null;
  };
  const cancelBk = el('photoCancelBookSheet');
  if (cancelBk) cancelBk.onclick = function () {
    photoCloseOverlay('photoBookSheetOverlay');
    photoPendingBook = null;
  };
  const saveBk = el('photoSaveBookSheet');
  if (saveBk) saveBk.onclick = savePhotoBookSheet;
  const closeDay = el('photoCloseDaySheet');
  if (closeDay) closeDay.onclick = function () {
    photoCloseOverlay('photoDaySheetOverlay');
  };
  const saveDay = el('photoSaveDaySheet');
  if (saveDay) saveDay.onclick = savePhotoDaySheet;
  const closeMp = el('photoCloseMonthPicker');
  if (closeMp) closeMp.onclick = function () {
    photoCloseOverlay('photoMonthPickerOverlay');
  };
  document.querySelectorAll('.block-reason').forEach(function (lab) {
    lab.onclick = function () {
      document.querySelectorAll('.block-reason').forEach(function (x) {
        x.classList.remove('on');
      });
      lab.classList.add('on');
      const inp = lab.querySelector('input');
      if (inp) inp.checked = true;
    };
  });
}
