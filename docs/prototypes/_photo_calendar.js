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
      {
        id: 'bk-demo-1',
        client: 'Anjali & Rohit',
        phone: '+91 98470 11220',
        event: 'Engagement',
        time: '10:00 AM – 2:00 PM',
        source: 'gixbee',
        notes: 'Outdoor at Sakthan Nagar park',
        status: 'confirmed',
      },
      {
        id: 'bk-demo-2',
        client: 'Thomas Family',
        phone: '+91 94470 55661',
        event: 'Portrait',
        time: '4:00 PM – 5:30 PM',
        source: 'offline',
        notes: 'Studio slot',
        status: 'confirmed',
      },
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
      {
        id: 'bk-demo-3',
        client: 'Memorial Service',
        phone: '+91 98765 00011',
        event: 'Funeral / Memorial',
        time: '9:00 AM – 1:00 PM',
        source: 'offline',
        notes: '',
        status: 'confirmed',
      },
    ],
  };
  cal._demoSeeded = true;
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
  renderPhotoCalendar();
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
  const tabMain = el('photoTabCalMain');
  const tabSet = el('photoTabBookSettings');
  if (tabMain) tabMain.classList.add('on');
  if (tabSet) tabSet.classList.remove('on');
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
        (b.phone ? '<p class="hint" style="margin:0">' + esc(b.phone) + '</p>' : '') +
        (b.notes ? '<p class="photo-bk-notes">' + esc(b.notes) + '</p>' : '') +
        '<div class="slot-actions">' +
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
  slots.querySelectorAll('[data-photo-edit-bk]').forEach(function (btn) {
    btn.onclick = function () {
      openPhotoBookSheet(btn.getAttribute('data-photo-edit-bk'));
    };
  });
  slots.querySelectorAll('[data-photo-cancel-bk]').forEach(function (btn) {
    btn.onclick = function () {
      cancelPhotoBooking(btn.getAttribute('data-photo-cancel-bk'));
    };
  });
}

function openPhotoBookSheet(bookingId) {
  const cal = ensurePhotoCalendar();
  const key = cal.selectedKey;
  const day = photoEnsureDay(cal, key);
  if (!bookingId) {
    photoPendingBook = {
      id: null,
      client: '',
      phone: '',
      event: 'Wedding',
      time: '10:00 AM – 6:00 PM',
      source: 'offline',
      notes: '',
      status: 'confirmed',
    };
  } else {
    const found = (day.bookings || []).find(function (b) {
      return b.id === bookingId;
    });
    photoPendingBook = found ? JSON.parse(JSON.stringify(found)) : null;
  }
  if (!photoPendingBook) return;
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
    day.bookings.push(photoPendingBook);
  } else {
    const i = day.bookings.findIndex(function (b) {
      return b.id === photoPendingBook.id;
    });
    if (i >= 0) day.bookings[i] = photoPendingBook;
  }
  saveStore();
  photoCloseOverlay('photoBookSheetOverlay');
  photoPendingBook = null;
  renderPhotoCalendar();
  renderPhotoCalDay();
  toast('Booking saved.');
}

function cancelPhotoBooking(id) {
  if (!confirm('Cancel this booking? It will be removed from the active day schedule.')) return;
  const cal = ensurePhotoCalendar();
  const day = photoEnsureDay(cal, cal.selectedKey);
  const b = day.bookings.find(function (x) {
    return x.id === id;
  });
  if (b) b.status = 'cancelled';
  saveStore();
  renderPhotoCalendar();
  renderPhotoCalDay();
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
  renderPhotoCalendar();
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
      renderPhotoCalendar();
    };
  });
}

function bindPhotoCalendarUi() {
  const tabSet = el('photoTabBookSettings');
  if (tabSet) {
    tabSet.onclick = function () {
      renderPhotoBookSettings();
      show('photoBookSettings');
    };
  }
  const tabMain = el('photoTabCalMain');
  if (tabMain) {
    tabMain.onclick = function () {
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
