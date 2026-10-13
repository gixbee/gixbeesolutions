const PHOTO_CUSTOMER_BUILD = '2026-10-13-photo-customer-service-flow-v9';
const DEMO_FILE = 'GIXBEE-PHOTO-CUSTOMER-FINALFLOW.html';
const STORAGE_KEY = 'GIXBEE_PHOTO_CUSTOMER_INTERESTS_V2';

/** Kerala districts (14) — location search uses full list */
const KERALA_DISTRICTS = [
  'Thiruvananthapuram',
  'Kollam',
  'Pathanamthitta',
  'Alappuzha',
  'Kottayam',
  'Idukki',
  'Ernakulam',
  'Thrissur',
  'Palakkad',
  'Malappuram',
  'Kozhikode',
  'Wayanad',
  'Kannur',
  'Kasaragod',
];
const LOCATIONS = KERALA_DISTRICTS.map(function (d) {
  return d + ', Kerala';
});
const COMMUNITIES = [
  { id: 'all', label: 'All', icon: '☯' },
  { id: 'hindu', label: 'Hindu', icon: '🕉' },
  { id: 'muslim', label: 'Muslim', icon: '☪' },
  { id: 'christian', label: 'Christian', icon: '✝' },
  { id: 'other', label: 'Others', icon: '◆' },
];
const PKG_LEVELS = ['All', 'Basic', 'Standard', 'Premium'];
const SVC_BUDGET_MIN_OPTS = [
  { v: 5000, l: '₹ 5,000' },
  { v: 10000, l: '₹ 10,000' },
  { v: 15000, l: '₹ 15,000' },
];
const SVC_BUDGET_MAX_OPTS = [
  { v: 25000, l: '₹ 25,000' },
  { v: 50000, l: '₹ 50,000' },
  { v: 100000, l: '₹ 1,00,000' },
];
const SERVICE_SEARCH_HERO = {
  funeral: {
    title: 'Funeral & Memorial Photography',
    sub: 'Respectful coverage with clear deliverables. Compare studios and send interest in minutes.',
  },
  baptism: {
    title: 'Baptism & Naming Photography',
    sub: 'Church and family celebration coverage from trusted Kerala studios.',
  },
  event: {
    title: 'Event & Get-together Photography',
    sub: 'Birthdays, family events, and gatherings — see packages and add-ons upfront.',
  },
  portrait: {
    title: 'Portrait Photography',
    sub: 'Studio or outdoor sessions with transparent pricing and delivery timelines.',
  },
  corporate: {
    title: 'Corporate Photography',
    sub: 'Events, conferences, and team headshots from verified professionals.',
  },
};
/** packagePath: show Community + Package type (wedding packages). */
const PHOTO_NEEDS = [
  { id: '', label: 'Select…', packagePath: false },
  { id: 'wedding', label: 'Wedding / Marriage', packagePath: true },
  { id: 'engagement', label: 'Engagement', packagePath: true },
  { id: 'save-date', label: 'Save the Date', packagePath: true },
  { id: 'pre-wedding', label: 'Pre-Wedding Shoot', packagePath: true },
  { id: 'post-wedding', label: 'Post-Wedding Shoot', packagePath: true },
  { id: 'reception', label: 'Reception', packagePath: true },
  { id: 'wedding-eve', label: 'Wedding Eve', packagePath: true },
  { id: 'funeral', label: 'Funeral / Memorial', packagePath: false },
  { id: 'baptism', label: 'Baptism', packagePath: false },
  { id: 'event', label: 'Event Photography', packagePath: false },
  { id: 'portrait', label: 'Portrait', packagePath: false },
  { id: 'corporate', label: 'Corporate', packagePath: false },
];

const TIMELINE = [
  { key: 'sent', label: 'Interest Sent', sub: 'We notified the studio' },
  { key: 'review', label: 'Under Review', sub: 'Photographer will review' },
  { key: 'contact', label: 'Photographer Will Contact', sub: 'Usually within 24 hours' },
  { key: 'discuss', label: 'Discussion in Progress', sub: 'Finalize details together' },
  { key: 'confirmed', label: 'Confirmed', sub: 'After discussion' },
];

const state = {
  mode: 'wedding',
  photoNeed: '',
  serviceId: 'funeral',
  location: LOCATIONS[0],
  date: '2026-12-15',
  community: 'all',
  pkgLevel: 'All',
  budgetMin: 50000,
  budgetMax: 100000,
  svcBudgetMin: 5000,
  svcBudgetMax: 50000,
  studioId: 'blue',
  packageId: 'standard',
  detailTab: 'inclusions',
  profTab: 'overview',
  intTab: 'active',
  customize: {
    extras: {},
    duration: 'inc',
    albumSize: '12 x 30 inch',
    albumPages: '30',
    albumPaper: 'Matte',
    albumCover: 'Premium',
    albumSizeCustom: '',
    albumPagesCustom: '',
    albumPaperCustom: '',
    albumCoverCustom: '',
    functions: {},
    extraFunctions: {},
    extraFunctionCustom: false,
    functionCustom: '',
    customNeedPreset: '',
    customNeedText: '',
    reqAck: {},
    notes: '',
  },
  interests: [],
  activeInterestId: null,
  detailBack: 'catalog',
  backScreen: 'search',
  catalogFilterPanel: null,
  /** 'customize' = came via Customize Requirements; 'direct' = Initiate Interest from detail */
  reviewEntry: 'direct',
  reviewCalMonth: null,
  reviewCalPick: null,
};

function activeNeed() {
  return PHOTO_NEEDS.find(function (n) {
    return n.id === state.photoNeed;
  });
}

function showPackageFilters() {
  const n = activeNeed();
  return !!(n && n.packagePath);
}

function syncModeFromNeed() {
  if (showPackageFilters()) {
    state.mode = 'wedding';
    return;
  }
  if (state.photoNeed) {
    state.mode = 'service';
    state.serviceId = state.photoNeed;
  }
}

function needLabel() {
  const n = activeNeed();
  return n && n.id ? n.label : 'Photography';
}

function el(id) {
  return document.getElementById(id);
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function inr(n) {
  return '₹ ' + Number(n).toLocaleString('en-IN');
}

function formatDate(iso) {
  if (!iso) return '—';
  const d = new Date(iso + 'T12:00:00');
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

function formatReviewDateLong(iso) {
  if (!iso) return 'Pick a date';
  const d = new Date(iso + 'T12:00:00');
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}

/** Demo: dates photographer has marked full (availability check before Send Interest). */
const STUDIO_FULL_DATES = {
  blue: ['2026-12-23', '2026-11-20'],
  archana: ['2026-11-20', '2026-12-24'],
};

function photographerDateUnavailable(studioId, isoDate) {
  if (!isoDate) return true;
  const list = STUDIO_FULL_DATES[studioId] || STUDIO_FULL_DATES.blue;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const pick = new Date(isoDate + 'T12:00:00');
  if (pick < today) return true;
  return list.indexOf(isoDate) >= 0;
}

function isoDateParts(y, m, day) {
  return y + '-' + String(m).padStart(2, '0') + '-' + String(day).padStart(2, '0');
}

function shiftReviewCalMonth(delta) {
  const base = state.reviewCalMonth || (state.date || '2026-12-15').slice(0, 7);
  const p = base.split('-');
  const d = new Date(+p[0], +p[1] - 1 + delta, 1);
  state.reviewCalMonth = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
  renderReviewCalendar();
}

function renderReviewCalendar() {
  const body = el('reviewCalBody');
  if (!body) return;
  const base = state.reviewCalMonth || (state.date || '2026-12-15').slice(0, 7);
  const p = base.split('-');
  const y = +p[0];
  const m = +p[1];
  const first = new Date(y, m - 1, 1);
  const monthName = first.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
  const startDow = first.getDay();
  const daysInMonth = new Date(y, m, 0).getDate();
  const pick = state.reviewCalPick || state.date;
  let html =
    '<div class="cal-nav"><button type="button" data-cal-prev aria-label="Previous month">‹</button><span>' +
    esc(monthName) +
    '</span><button type="button" data-cal-next aria-label="Next month">›</button></div><div class="cal-grid">';
  ['S', 'M', 'T', 'W', 'T', 'F', 'S'].forEach(function (d) {
    html += '<span class="dow">' + d + '</span>';
  });
  let cell = 0;
  for (let i = 0; i < startDow; i++) {
    html += '<span></span>';
    cell++;
  }
  for (let day = 1; day <= daysInMonth; day++) {
    const iso = isoDateParts(y, m, day);
    const full = photographerDateUnavailable(state.studioId, iso);
    const on = pick === iso;
    let cls = 'cal-day';
    if (full) cls += ' full';
    else if (on) cls += ' on';
    html +=
      '<button type="button" class="' +
      cls +
      '" data-cal-day="' +
      iso +
      '"' +
      (full ? ' disabled' : '') +
      '>' +
      day +
      '</button>';
    cell++;
  }
  html += '</div>';
  body.innerHTML = html;
  body.querySelector('[data-cal-prev]').onclick = function () {
    shiftReviewCalMonth(-1);
  };
  body.querySelector('[data-cal-next]').onclick = function () {
    shiftReviewCalMonth(1);
  };
  body.querySelectorAll('[data-cal-day]').forEach(function (btn) {
    if (btn.disabled) return;
    btn.onclick = function () {
      state.reviewCalPick = btn.getAttribute('data-cal-day');
      renderReviewCalendar();
    };
  });
}

function updateReviewDateLabels() {
  const long = formatReviewDateLong(state.date);
  document.querySelectorAll('[data-event-date-lbl]').forEach(function (node) {
    node.textContent = long;
  });
  const row = el('reviewEventDate');
  if (row) row.textContent = formatDate(state.date);
}

function openReviewDateModal() {
  state.reviewCalPick = state.date;
  state.reviewCalMonth = (state.date || '2026-12-15').slice(0, 7);
  const modal = el('reviewDateModal');
  if (modal) modal.hidden = false;
  renderReviewCalendar();
}

function closeReviewDateModal() {
  const modal = el('reviewDateModal');
  if (modal) modal.hidden = true;
}

function showDateFullModal() {
  const lbl = el('dateFullLbl');
  if (lbl) lbl.textContent = formatReviewDateLong(state.date);
  const modal = el('dateFullModal');
  if (modal) modal.hidden = false;
}

function closeDateFullModal() {
  const modal = el('dateFullModal');
  if (modal) modal.hidden = true;
}

function eventDatePickHtml() {
  return (
    '<button type="button" class="review-date-pick" data-open-date-pick>' +
    '<span class="review-date-ico" aria-hidden="true">📅</span>' +
    '<span class="review-date-txt"><span class="lbl">Select Date</span><b data-event-date-lbl>' +
    esc(formatReviewDateLong(state.date)) +
    '</b></span>' +
    '<span class="review-date-chev" aria-hidden="true">›</span></button>'
  );
}

function bindDatePickButtons(root) {
  if (!root) return;
  root.querySelectorAll('[data-open-date-pick]').forEach(function (btn) {
    btn.onclick = openReviewDateModal;
  });
}

function catalogDatePrompt() {
  return state.mode === 'service'
    ? 'Confirm your event date before choosing a service'
    : 'Confirm your event date before choosing a package';
}

function renderCatalogDateBar() {
  const bar = el('catalogDateBar');
  if (!bar) return;
  bar.innerHTML =
    '<p class="sub" style="margin:0 0 8px;font-size:11px;font-weight:700">' +
    esc(catalogDatePrompt()) +
    '</p>' +
    eventDatePickHtml();
  bindDatePickButtons(bar);
  if (photographerDateUnavailable(state.studioId, state.date)) {
    bar.innerHTML +=
      '<p class="sub" style="margin:8px 0 0;font-size:11px;font-weight:700;color:#B45309">This date looks fully booked — tap to pick another day.</p>';
  }
}

function renderDetailDateBar() {
  const bar = el('detailDateBar');
  if (!bar) return;
  if (state.mode !== 'service') {
    bar.hidden = true;
    bar.innerHTML = '';
    return;
  }
  bar.hidden = false;
  bar.innerHTML =
    '<p class="sub" style="margin:0 0 8px;font-size:11px;font-weight:700">Event date</p>' +
    eventDatePickHtml();
  bindDatePickButtons(bar);
  updateReviewDateLabels();
  if (photographerDateUnavailable(state.studioId, state.date)) {
    bar.innerHTML +=
      '<p class="sub" style="margin:8px 0 0;font-size:11px;font-weight:700;color:#B45309">This date looks fully booked — choose another day.</p>';
  }
}

function ensureEventDateForInterest() {
  if (!state.date) {
    toast('Please select an event date');
    openReviewDateModal();
    return false;
  }
  if (photographerDateUnavailable(state.studioId, state.date)) {
    showDateFullModal();
    return false;
  }
  return true;
}

function renderReviewDateBar() {
  const bar = el('reviewDateBar');
  if (!bar) return;
  bar.hidden = true;
  bar.innerHTML = '';
}

function toast(msg) {
  const t = el('toast');
  if (!t) return;
  t.textContent = msg;
  t.style.display = 'block';
  clearTimeout(toast._tm);
  toast._tm = setTimeout(function () {
    t.style.display = 'none';
  }, 2200);
}

function studio() {
  return catalogStudio(state.studioId);
}

function activePackage() {
  const list = packagesForStudio(state.studioId, {
    level: state.pkgLevel,
    community: state.community,
  });
  const found = list.find(function (p) {
    return p.id === state.packageId;
  });
  return found || list[0] || packagesForStudio(state.studioId, {})[0];
}

function activePackageOwner() {
  const card = activePackage();
  if (card && card.owner) return card.owner;
  return ownerPayloadForPackage(state.studioId, state.packageId);
}

function activeService() {
  const key = state.serviceId || state.photoNeed || 'funeral';
  return serviceForStudio(state.studioId, key);
}

function activeServiceOwner() {
  const card = activeService();
  if (card && card.owner) return card.owner;
  return ownerPayloadForService(state.studioId, state.serviceId || state.photoNeed);
}

function packageExtras() {
  return custPackageExtrasList(activePackageOwner());
}

function serviceExtras() {
  return custServiceExtrasList(activeServiceOwner());
}

function offerTitle() {
  if (state.mode === 'wedding') return activePackage().name;
  return activeService().name;
}

function offerPrice() {
  if (state.mode === 'wedding') {
    let p = activePackage().price;
    packageExtras().forEach(function (ex) {
      if (state.customize.extras[ex.id]) p += ex.price;
    });
    return p;
  }
  const svc = activeService();
  let p = svc.price || 0;
  (svc.durationOptions || []).forEach(function (d) {
    if (d.id === state.customize.duration) p += d.add || 0;
  });
  serviceExtras().forEach(function (ex) {
    if (state.customize.extras[ex.id]) p += ex.price;
  });
  return p;
}

function selectedRequirementsLines() {
  const lines = [];
  if (state.mode === 'wedding') {
    packageExtras().forEach(function (ex) {
      if (state.customize.extras[ex.id]) lines.push(ex.label + ' — ' + inr(ex.price));
    });
    lines = lines.concat(custCustomizeRequirementLines(state, activePackageOwner()));
  } else {
    const svc = activeService();
    (svc.durationOptions || []).forEach(function (d) {
      if (d.id === state.customize.duration) lines.push('Duration: ' + d.label + (d.add ? ' — +' + inr(d.add) : ''));
    });
    serviceExtras().forEach(function (ex) {
      if (state.customize.extras[ex.id]) lines.push(ex.label + ' — ' + inr(ex.price));
    });
    lines = lines.concat(custCustomizeRequirementLines(state, activeServiceOwner()));
  }
  return lines;
}

function activeScreenId() {
  const on = document.querySelector('.scr.on');
  return on ? on.id : 'search';
}

function show(id, backTo) {
  if (backTo !== undefined) state.backScreen = backTo;
  document.querySelectorAll('.scr').forEach(function (s) {
    s.classList.toggle('on', s.id === id);
  });
  const nav = el('bottomNav');
  if (nav) {
    nav.style.display =
      ['results', 'profile', 'detail', 'catalog', 'customize', 'review', 'interestDetail', 'sent'].indexOf(id) >= 0
        ? 'none'
        : '';
  }
  document.querySelectorAll('[data-nav]').forEach(function (b) {
    const n = b.getAttribute('data-nav');
    b.classList.toggle(
      'on',
      ((n === 'home' || n === 'search') && id === 'search') ||
        (n === 'interests' && (id === 'interests' || id === 'interestDetail'))
    );
  });
}

function goBack() {
  const cur = activeScreenId();
  let target;
  if (cur === 'detail') {
    target = state.detailBack || 'catalog';
  } else {
    target = state.backScreen || 'search';
  }
  show(target);
  if (target === 'catalog') state.backScreen = 'profile';
  else if (target === 'profile') state.backScreen = 'results';
  else if (target === 'results') state.backScreen = 'search';
  else if (target === 'detail') state.backScreen = 'detail';
  else if (target === 'customize') state.backScreen = 'detail';
  else if (target === 'review') state.backScreen = 'customize';
  else if (target === 'interests') state.backScreen = 'search';
}

function loadInterests() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) state.interests = JSON.parse(raw);
  } catch (e) {
    state.interests = [];
  }
  ensureSeedInterests();
}

function ensureSeedInterests() {
  if (state.interests.length) return;
  state.interests = [
    {
      id: 'demo-seed-1',
      mode: 'wedding',
      studioId: 'archana',
      studioName: 'Archana Photography',
      offerName: 'Classic Wedding Package',
      needLabel: 'Wedding / Marriage',
      date: '2026-11-20',
      location: 'Pathanamthitta, Kerala',
      community: 'Hindu',
      pkgLevel: 'Standard',
      price: 95000,
      statusLabel: 'Under Review',
      status: 'active',
      sentAt: '2026-10-01',
      requirements: ['Drone — ₹ 9,000', 'Also cover: Engagement'],
      notes: 'Church morning + hall evening on same day.',
      paymentSummary: 'Advance 30% · Balance 70%',
      coverageSummary: 'Wedding & Reception · 9 hrs · Both sides · Candid + Traditional',
      deliverySummary: 'Gallery in 14 days',
    },
    {
      id: 'demo-seed-past',
      mode: 'service',
      studioId: 'blue',
      studioName: 'Blue Lens Studio',
      offerName: 'Funeral / Memorial Photography',
      needLabel: 'Funeral / Memorial',
      date: '2026-09-08',
      location: 'Kottayam, Kerala',
      price: 8000,
      statusLabel: 'Accepted',
      status: 'past',
      sentAt: '2026-09-01',
      requirements: ['Duration: 3–5 hours', 'Live streaming for family abroad — ₹ 2,000'],
      notes: '',
      paymentSummary: 'Paid in full after gallery',
      coverageSummary: '2–3 hours included · 1 photographer',
      deliverySummary: 'Gallery in 3–5 days',
    },
  ];
  saveInterests();
}

function interestById(id) {
  return state.interests.find(function (x) {
    return x.id === id;
  });
}

function saveInterests() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state.interests));
  } catch (e) {
    /* ignore */
  }
}

function searchHeroHtml() {
  if (showPackageFilters()) {
    return (
      '<div class="hero-wed"><h2>Find Your Wedding Photographer</h2><p>Compare packages, coverage, and deliverables from trusted studios.</p></div>'
    );
  }
  const id = state.photoNeed || '';
  const preset =
    SERVICE_SEARCH_HERO[id] || {
      title: 'Find Photography Services',
      sub: 'Browse individual services, coverage, and deliverables from verified studios.',
    };
  return (
    '<div class="hero-wed hero-svc"><h2>' +
    esc(preset.title) +
    '</h2><p>' +
    esc(preset.sub) +
    '</p></div>'
  );
}

function studiosForResults() {
  if (state.mode === 'wedding') return studioList();
  const key = state.photoNeed || state.serviceId;
  return studioList().filter(function (s) {
    return studioOffersService(s.id, key);
  });
}

function renderSearchForm() {
  const hero = el('searchHero');
  const form = el('searchForm');
  if (!hero || !form) return;
  hero.innerHTML = searchHeroHtml();
  const pkgBlock = showPackageFilters()
    ? '<div class="fld"><label>Community / Religion</label><div class="comm-row" id="fComm">' +
      COMMUNITIES.map(function (c) {
        return (
          '<button type="button" class="comm-btn' +
          (state.community === c.id ? ' on' : '') +
          '" data-comm="' +
          c.id +
          '"><div class="c-ico">' +
          c.icon +
          '</div><span>' +
          esc(c.label) +
          '</span></button>'
        );
      }).join('') +
      '</div></div>' +
      '<div class="fld"><label>Package Type</label><div class="pkg-type-row" id="fPkg">' +
      PKG_LEVELS.map(function (p) {
        return (
          '<button type="button" class="pkg-type-btn' +
          (state.pkgLevel === p ? ' on' : '') +
          '" data-pkg="' +
          esc(p) +
          '"><b>' +
          esc(p) +
          '</b></button>'
        );
      }).join('') +
      '</div></div>'
    : '';
  form.innerHTML =
    '<div class="fld"><label>Location</label><div class="sel-box"><select id="fLoc">' +
    LOCATIONS.map(function (l) {
      return '<option' + (l === state.location ? ' selected' : '') + '>' + esc(l) + '</option>';
    }).join('') +
    '</select></div></div>' +
    '<div class="fld"><label>Event Date</label><div class="sel-box"><input type="date" id="fDate" value="' +
    esc(state.date) +
    '"></div></div>' +
    '<div class="fld"><label>What do you need photography for?</label><div class="sel-box"><select id="fNeed">' +
    '<option value=""' +
    (state.photoNeed === '' ? ' selected' : '') +
    '>Select…</option>' +
    PHOTO_NEEDS.filter(function (n) {
      return n.id;
    }).map(function (n) {
      return (
        '<option value="' +
        esc(n.id) +
        '"' +
        (state.photoNeed === n.id ? ' selected' : '') +
        '>' +
        esc(n.label) +
        '</option>'
      );
    }).join('') +
    '</select></div></div>' +
    pkgBlock +
    (showPackageFilters()
      ? '<div class="fld"><label>Budget Range (Optional)</label><div class="budget-row">' +
        '<div class="sel-box"><select id="fBudMin">' +
        [
          { v: 50000, l: '₹ 50,000' },
          { v: 75000, l: '₹ 75,000' },
          { v: 100000, l: '₹ 1,00,000' },
        ]
          .map(function (o) {
            return (
              '<option value="' +
              o.v +
              '"' +
              (state.budgetMin === o.v ? ' selected' : '') +
              '>' +
              o.l +
              '</option>'
            );
          })
          .join('') +
        '</select></div>' +
        '<div class="sel-box"><select id="fBudMax">' +
        [
          { v: 100000, l: '₹ 1,00,000' },
          { v: 150000, l: '₹ 1,50,000' },
          { v: 200000, l: '₹ 2,00,000' },
        ]
          .map(function (o) {
            return (
              '<option value="' +
              o.v +
              '"' +
              (state.budgetMax === o.v ? ' selected' : '') +
              '>' +
              o.l +
              '</option>'
            );
          })
          .join('') +
        '</select></div></div></div>'
      : '<div class="fld"><label>Service Budget (Optional)</label><div class="budget-row">' +
        '<div class="sel-box"><select id="fSvcBudMin">' +
        SVC_BUDGET_MIN_OPTS.map(function (o) {
          return (
            '<option value="' +
            o.v +
            '"' +
            (state.svcBudgetMin === o.v ? ' selected' : '') +
            '>' +
            o.l +
            '</option>'
          );
        }).join('') +
        '</select></div>' +
        '<div class="sel-box"><select id="fSvcBudMax">' +
        SVC_BUDGET_MAX_OPTS.map(function (o) {
          return (
            '<option value="' +
            o.v +
            '"' +
            (state.svcBudgetMax === o.v ? ' selected' : '') +
            '>' +
            o.l +
            '</option>'
          );
        }).join('') +
        '</select></div></div></div>');
  bindSearchForm();
}

function bindSearchForm() {
  const loc = el('fLoc');
  if (loc) loc.onchange = function () {
    state.location = loc.value;
  };
  const dt = el('fDate');
  if (dt) dt.onchange = function () {
    state.date = dt.value;
  };
  const comm = el('fComm');
  if (comm) {
    comm.querySelectorAll('[data-comm]').forEach(function (btn) {
      btn.onclick = function () {
        state.community = btn.getAttribute('data-comm');
        renderSearchForm();
      };
    });
  }
  const pkg = el('fPkg');
  if (pkg) {
    pkg.querySelectorAll('[data-pkg]').forEach(function (btn) {
      btn.onclick = function () {
        state.pkgLevel = btn.getAttribute('data-pkg');
        renderSearchForm();
      };
    });
  }
  const need = el('fNeed');
  if (need) {
    need.onchange = function () {
      state.photoNeed = need.value || '';
      syncModeFromNeed();
      renderSearchForm();
    };
  }
  const bmin = el('fBudMin');
  const bmax = el('fBudMax');
  if (bmin) bmin.onchange = function () {
    state.budgetMin = +bmin.value;
  };
  if (bmax) bmax.onchange = function () {
    state.budgetMax = +bmax.value;
  };
  const sbmin = el('fSvcBudMin');
  const sbmax = el('fSvcBudMax');
  if (sbmin) sbmin.onchange = function () {
    state.svcBudgetMin = +sbmin.value;
  };
  if (sbmax) sbmax.onchange = function () {
    state.svcBudgetMax = +sbmax.value;
  };
}

function renderResults() {
  const title = el('resTitle');
  const sub = el('resSub');
  const count = el('resCount');
  const list = el('resList');
  if (state.mode === 'wedding') {
    if (title) title.textContent = 'Wedding Photographers';
    if (sub) sub.textContent = state.location + ' · ' + formatDate(state.date);
    if (count) count.textContent = '24 photographers found';
  } else {
    if (title) title.textContent = needLabel();
    if (sub) sub.textContent = state.location + ' · ' + formatDate(state.date);
    if (count) count.textContent = '8 photographers found';
  }
  if (!list) return;
  const rows = studiosForResults();
  if (state.mode === 'service' && count) {
    count.textContent = rows.length + (rows.length === 1 ? ' studio found' : ' studios found');
  }
  if (!rows.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:16px"><div class="hub-empty-ico">🔍</div><b>No studios for this service yet</b><p>Try another district or a different photography need.</p></div>';
    return;
  }
  list.innerHTML = rows.map(function (s) {
    const from = state.mode === 'wedding' ? s.weddingFrom : s.serviceFrom;
    const svcCard = state.mode === 'service' ? serviceForStudio(s.id, state.photoNeed) : null;
    const fromPrice = state.mode === 'service' && svcCard && svcCard.price ? svcCard.price : from;
    const tag =
      state.mode === 'wedding'
        ? '<span class="ph-tag">Christian</span><span class="ph-tag">Standard</span>'
        : '<span class="ph-tag">' + esc(needLabel()) + '</span><span class="ph-tag">Verified</span>';
    return (
      '<button type="button" class="ph-row" data-studio="' +
      s.id +
      '"><div class="ph-thumb"><span class="heart">♡</span></div><div class="ph-bd"><b>' +
      esc(s.name) +
      '</b><div class="ph-rating"><span class="star">★</span> ' +
      s.rating +
      ' (' +
      s.reviews +
      ') · ' +
      s.km +
      ' km</div><div class="ph-price">' +
      inr(fromPrice) +
      (state.mode === 'wedding' ? ' onwards' : '') +
      '</div><div class="ph-tags">' +
      tag +
      '</div></div></button>'
    );
  }).join('');
  list.querySelectorAll('[data-studio]').forEach(function (btn) {
    btn.onclick = function () {
      state.studioId = btn.getAttribute('data-studio');
      state.packageId = defaultPackageId(state.studioId);
      state.profTab = 'overview';
      renderProfile();
      show('profile', 'results');
    };
  });
}

function renderProfile() {
  const s = studio();
  el('profName').textContent = s.name;
  el('profMeta').innerHTML =
    '<span class="star" style="color:#F59E0B">★ ' +
    s.rating +
    ' (' +
    s.reviews +
    ')</span> · ' +
    esc(state.location.split(',')[0]) +
    ' · ' +
    s.km +
    ' km';
  el('profStats').innerHTML =
    '<div class="stat-cell"><div class="ic">📅</div>' +
    s.years +
    '<br>Years Experience</div><div class="stat-cell"><div class="ic">📷</div>' +
    s.events +
    '<br>' +
    (state.mode === 'wedding' ? 'Weddings' : 'Events') +
    '</div><div class="stat-cell"><div class="ic">👥</div>' +
    esc(s.team) +
    '</div>';
  const primary = el('profPrimary');
  if (primary) primary.textContent = state.mode === 'wedding' ? 'View Packages' : 'View Service';
  renderProfPanel();
}

function renderProfPanel() {
  const s = studio();
  const panel = el('profPanel');
  if (!panel) return;
  if (state.profTab === 'overview') {
    panel.innerHTML =
      '<h3>About Us</h3><p style="margin:0 0 14px;font-weight:600;color:var(--mut)">' +
      esc(s.about) +
      '</p><h3>Service Areas</h3><div class="area-tags">' +
      s.areas.map(function (a) {
        return '<span>' + esc(a) + '</span>';
      }).join('') +
      '</div>';
  } else if (state.profTab === 'portfolio') {
    panel.innerHTML = '<p class="sub">Portfolio grid — demo placeholders.</p><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' + [1, 2, 3, 4].map(function () {
      return '<div style="height:80px;border-radius:10px;background:linear-gradient(145deg,#CBD5E1,#64748B)"></div>';
    }).join('') + '</div>';
  } else {
    panel.innerHTML = renderReviewsHtml();
  }
}

function renderReviewsHtml() {
  return (
    '<div class="stars-bar"><b>4.8</b><div class="bar-dist">★★★★★<br>56 reviews</div></div>' +
    '<div class="rev-item"><div class="who">Anitha K. · Dec 2025</div><div class="star">★★★★★</div>Beautiful photos and very professional team.</div>' +
    '<div class="rev-item"><div class="who">Rahul M. · Nov 2025</div><div class="star">★★★★☆</div>Great coverage and fast delivery.</div>'
  );
}

function catalogCommunityLabel() {
  const c = COMMUNITIES.find(function (x) {
    return x.id === state.community;
  });
  return c ? c.label : 'All';
}

function renderCatalogFilterPanel() {
  const panel = el('catFilterPanel');
  if (!panel) return;
  if (!state.catalogFilterPanel) {
    panel.hidden = true;
    panel.innerHTML = '';
    return;
  }
  panel.hidden = false;
  if (state.catalogFilterPanel === 'community') {
    panel.innerHTML =
      '<p class="lbl">Select community / religion</p><div class="comm-row" id="catCommPick">' +
      COMMUNITIES.map(function (c) {
        return (
          '<button type="button" class="comm-btn' +
          (state.community === c.id ? ' on' : '') +
          '" data-cat-comm="' +
          c.id +
          '"><div class="c-ico">' +
          c.icon +
          '</div><span>' +
          esc(c.label) +
          '</span></button>'
        );
      }).join('') +
      '</div>';
    panel.querySelectorAll('[data-cat-comm]').forEach(function (btn) {
      btn.onclick = function () {
        state.community = btn.getAttribute('data-cat-comm');
        state.catalogFilterPanel = null;
        renderCatalog();
      };
    });
  } else if (state.catalogFilterPanel === 'pkg') {
    panel.innerHTML =
      '<p class="lbl">Select package type</p><div class="pkg-type-row" id="catPkgPick">' +
      PKG_LEVELS.map(function (p) {
        return (
          '<button type="button" class="pkg-type-btn' +
          (state.pkgLevel === p ? ' on' : '') +
          '" data-cat-pkg="' +
          esc(p) +
          '"><b>' +
          esc(p) +
          '</b></button>'
        );
      }).join('') +
      '</div>';
    panel.querySelectorAll('[data-cat-pkg]').forEach(function (btn) {
      btn.onclick = function () {
        state.pkgLevel = btn.getAttribute('data-cat-pkg');
        state.catalogFilterPanel = null;
        renderCatalog();
      };
    });
  }
}

function renderServiceCatalog() {
  const title = el('catTitle');
  if (title) title.textContent = studio().name + ' · Services';
  const filters = el('catFilters');
  if (filters) filters.innerHTML = '';
  const panel = el('catFilterPanel');
  if (panel) {
    panel.hidden = true;
    panel.innerHTML = '';
  }
  state.catalogFilterPanel = null;
  renderCatalogDateBar();
  const list = el('catList');
  const countEl = el('catCount');
  const svcs = servicesForStudio(state.studioId, state.photoNeed);
  if (countEl) {
    countEl.textContent =
      svcs.length === 1 ? 'Showing 1 service for ' + needLabel() : 'Showing ' + svcs.length + ' services';
  }
  if (!list) return;
  if (!svcs.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:16px"><div class="hub-empty-ico">📷</div><b>Service not listed</b><p>This studio has not published <b>' +
      esc(needLabel()) +
      '</b> yet. Try another photographer from results.</p></div>';
    return;
  }
  list.innerHTML = svcs
    .map(function (svc) {
      const bullets = svc.cardBullets || svc.inclusions || [];
      let priceHtml = inr(svc.price);
      if (svc.listPrice > svc.price) {
        priceHtml +=
          ' <span style="font-size:11px;color:var(--mut);text-decoration:line-through">' + inr(svc.listPrice) + '</span>';
      }
      return (
        '<button type="button" class="pkg-card" data-svc="' +
        esc(svc.serviceKey) +
        '"><div class="thumb"></div><div><b>' +
        esc(svc.name) +
        '</b><div class="price">' +
        priceHtml +
        (svc.discountPct ? ' <span style="font-size:10px;color:#BE185D">' + svc.discountPct + '% OFF</span>' : '') +
        '</div><ul>' +
        bullets
          .slice(0, 4)
          .map(function (b) {
            return '<li>' + esc(b) + '</li>';
          })
          .join('') +
        '</ul><span class="link">View Service ›</span></div></button>'
      );
    })
    .join('');
  list.querySelectorAll('[data-svc]').forEach(function (btn) {
    btn.onclick = function () {
      state.serviceId = btn.getAttribute('data-svc');
      state.customize.duration = 'inc';
      state.detailTab = 'overview';
      state.detailBack = 'catalog';
      renderDetail();
      show('detail', 'catalog');
    };
  });
}

function renderCatalog() {
  if (state.mode === 'service') {
    renderServiceCatalog();
    return;
  }
  el('catTitle').textContent = studio().name;
  const filters = el('catFilters');
  if (filters) {
    filters.innerHTML =
      '<button type="button" class="fchip' +
      (state.catalogFilterPanel === 'community' ? ' on' : '') +
      '" data-cat-filter="community">Community: ' +
      esc(catalogCommunityLabel()) +
      ' ▾</button>' +
      '<button type="button" class="fchip' +
      (state.catalogFilterPanel === 'pkg' ? ' on' : '') +
      '" data-cat-filter="pkg">Package: ' +
      esc(state.pkgLevel || 'All') +
      ' ▾</button>';
    filters.querySelectorAll('[data-cat-filter]').forEach(function (btn) {
      btn.onclick = function () {
        const key = btn.getAttribute('data-cat-filter');
        state.catalogFilterPanel = state.catalogFilterPanel === key ? null : key;
        renderCatalog();
      };
    });
  }
  renderCatalogFilterPanel();
  renderCatalogDateBar();
  const list = el('catList');
  const countEl = el('catCount');
  if (!list) return;
  const pkgs = packagesForStudio(state.studioId, {
    level: state.pkgLevel,
    community: state.community,
  });
  if (countEl) {
    countEl.textContent =
      pkgs.length === 1 ? 'Showing 1 package' : 'Showing ' + pkgs.length + ' packages';
  }
  if (!pkgs.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:16px"><div class="hub-empty-ico">📦</div><b>No packages match</b><p>Try <b>All</b> community or a different package type.</p></div>';
    return;
  }
  list.innerHTML = pkgs
    .map(function (p) {
      const bullets = p.cardBullets || p.inclusions || [];
      let priceHtml = inr(p.price);
      if (p.listPrice > p.price) {
        priceHtml +=
          ' <span style="font-size:11px;color:var(--mut);text-decoration:line-through">' + inr(p.listPrice) + '</span>';
      }
      const ownerPkg = p.owner || ownerPayloadForPackage(state.studioId, p.id);
      return (
        '<button type="button" class="pkg-card" data-pkg="' +
        p.id +
        '"><div class="thumb"></div><div><b>' +
        esc(p.name) +
        '</b>' +
        custPkgCardMetaHtml(ownerPkg) +
        '<div class="price">' +
        priceHtml +
        (p.discountPct ? ' <span style="font-size:10px;color:#BE185D">' + p.discountPct + '% OFF</span>' : '') +
        '</div><ul>' +
        bullets
          .slice(0, 4)
          .map(function (b) {
            return '<li>' + esc(b) + '</li>';
          })
          .join('') +
        '</ul><span class="link">View Details ›</span></div></button>'
      );
    })
    .join('');
  list.querySelectorAll('[data-pkg]').forEach(function (btn) {
    btn.onclick = function () {
      state.packageId = btn.getAttribute('data-pkg');
      state.detailTab = 'overview';
      state.detailBack = 'catalog';
      renderDetail();
      show('detail', 'catalog');
    };
  });
}

function renderDetail() {
  const name = el('detailName');
  const priceTag = el('detailPriceTag');
  const tabs = el('detailTabs');
  const panel = el('detailPanel');
  const isWed = state.mode === 'wedding';
  const pkg = activePackageOwner();
  const svc = activeServiceOwner();
  const card = isWed ? activePackage() : activeService();
  const price = card.price;
  if (name) name.textContent = isWed ? pkg.name : svc.name;
  if (priceTag) {
    let ph =
      '<b>' +
      inr(price) +
      '</b><span>' +
      (isWed ? 'Package price' : 'Service price') +
      '</span>';
    if (card.listPrice > price) {
      ph +=
        '<span style="display:block;font-size:12px;text-decoration:line-through;opacity:.85">' +
        inr(card.listPrice) +
        (card.discountPct ? ' · ' + card.discountPct + '% OFF' : '') +
        '</span>';
    }
    priceTag.innerHTML = ph;
  }
  if (!isWed && state.detailTab === 'inclusions') state.detailTab = 'overview';
  const tabIds = isWed
    ? ['overview', 'inclusions', 'coverage', 'extras', 'policies', 'reviews']
    : ['overview', 'coverage', 'extras', 'policies', 'reviews'];
  const tabLbl = isWed
    ? ['Overview', 'Inclusions', 'Coverage', 'Extras', 'Policies', 'Reviews']
    : ['Overview / Inclusions', 'Coverage', 'Extras', 'Policies', 'Reviews'];
  if (tabs) {
    tabs.innerHTML = tabIds
      .map(function (id, i) {
        return (
          '<button type="button" class="' +
          (state.detailTab === id ? 'on' : '') +
          '" data-dtab="' +
          id +
          '">' +
          tabLbl[i] +
          '</button>'
        );
      })
      .join('');
    tabs.querySelectorAll('[data-dtab]').forEach(function (btn) {
      btn.onclick = function () {
        state.detailTab = btn.getAttribute('data-dtab');
        renderDetail();
      };
    });
  }
  if (!panel) return;
  if (state.detailTab === 'overview') {
    panel.innerHTML = isWed ? custRenderPkgBasics(pkg) : custRenderSvcOverviewInclusions(svc);
  } else if (state.detailTab === 'inclusions') {
    panel.innerHTML = custRenderPkgInclusions(pkg);
  } else if (state.detailTab === 'coverage') {
    panel.innerHTML = isWed ? custRenderPkgCoverage(pkg) : custRenderSvcCoverage(svc);
  } else if (state.detailTab === 'extras') {
    panel.innerHTML = custRenderExtrasBlock(isWed ? pkg.extras : svc.extras);
  } else if (state.detailTab === 'policies') {
    panel.innerHTML = custRenderPolicies(isWed ? pkg : svc);
  } else {
    panel.innerHTML = renderReviewsHtml();
  }
  renderDetailDateBar();
}

function renderCustomize() {
  const sum = el('custSummary');
  const body = el('custBody');
  const title = offerTitle();
  const price = state.mode === 'wedding' ? activePackage().price : activeService().price;
  if (sum) {
    sum.innerHTML =
      '<div class="review-summary"><div class="thumb"></div><div style="flex:1"><b style="font-size:14px;color:var(--navy)">' +
      esc(title) +
      '</b><div style="font-size:12px;color:var(--mut);font-weight:700;margin-top:2px">' +
      esc(studio().name) +
      ' · ' +
      esc(formatDate(state.date)) +
      '</div><div style="font-size:15px;font-weight:900;color:var(--blue2);margin-top:6px">Est. ' +
      inr(offerPrice()) +
      '</div></div></div>';
  }
  if (!body) return;
  if (state.mode === 'wedding') {
    body.innerHTML = custRenderCustomizeWedding(activePackageOwner(), packageExtras(), state);
    const goRev = el('goReview');
    if (goRev) goRev.textContent = 'Next: Review Interest';
  } else {
    const svcO = activeServiceOwner();
    body.innerHTML = custRenderCustomizeService(
      svcO,
      serviceExtras(),
      activeService().durationOptions || svcO.durationOptions || [],
      state
    );
    const goRev = el('goReview');
    if (goRev) goRev.textContent = 'Next: Review Interest';
  }
  bindCustomize();
  if (state.mode === 'wedding') {
    custBindExtraFunctionMulti(custOptionalFunctionsForOwner(activePackageOwner()));
  }
}

function bindCustomize() {
  const c = state.customize;
  document.querySelectorAll('[data-wex]').forEach(function (inp) {
    inp.onchange = function () {
      c.extras[inp.getAttribute('data-wex')] = inp.checked;
      renderCustomize();
    };
  });
  document.querySelectorAll('[data-sex]').forEach(function (inp) {
    inp.onchange = function () {
      c.extras[inp.getAttribute('data-sex')] = inp.checked;
      renderCustomize();
    };
  });
  document.querySelectorAll('[name=dur]').forEach(function (inp) {
    inp.onchange = function () {
      c.duration = inp.value;
      renderCustomize();
    };
  });
  document.querySelectorAll('[data-req-ack]').forEach(function (inp) {
    inp.onchange = function () {
      const key = inp.getAttribute('data-req-ack');
      c.reqAck[key] = inp.checked;
      inp.closest('.chk-row').classList.toggle('on', inp.checked);
    };
  });
  const needPreset = el('custNeedPreset');
  if (needPreset) {
    needPreset.onchange = function () {
      c.customNeedPreset = needPreset.value;
    };
  }
  const needText = el('custNeedText');
  if (needText) {
    needText.oninput = function () {
      c.customNeedText = needText.value;
    };
  }
  const albSize = el('albSize');
  if (albSize) {
    albSize.onchange = function () {
      c.albumSize = albSize.value;
      renderCustomize();
    };
  }
  const albPages = el('albPages');
  if (albPages) {
    albPages.onchange = function () {
      c.albumPages = albPages.value;
      renderCustomize();
    };
  }
  const albPaper = el('albPaper');
  if (albPaper) {
    albPaper.onchange = function () {
      c.albumPaper = albPaper.value;
      renderCustomize();
    };
  }
  const albCover = el('albCover');
  if (albCover) {
    albCover.onchange = function () {
      c.albumCover = albCover.value;
      renderCustomize();
    };
  }
  const albSizeCustom = el('albSizeCustom');
  if (albSizeCustom) albSizeCustom.oninput = function () {
    c.albumSizeCustom = albSizeCustom.value;
  };
  const albPagesCustom = el('albPagesCustom');
  if (albPagesCustom) albPagesCustom.oninput = function () {
    c.albumPagesCustom = albPagesCustom.value;
  };
  const notes = el('custNotes');
  const ct = el('noteCt');
  if (notes) {
    const upd = function () {
      c.notes = notes.value;
      if (ct) ct.textContent = String(notes.value.length);
    };
    notes.oninput = upd;
    upd();
  }
}

function renderReviewFooter() {
  const foot = el('reviewFoot');
  if (!foot) return;
  const viaCustomize = state.reviewEntry === 'customize';
  if (viaCustomize) {
    foot.style.gridTemplateColumns = '1fr 1fr';
    foot.innerHTML =
      '<button type="button" class="btn outline" data-to="customize">Edit Requirements</button>' +
      '<button type="button" class="btn" id="sendInterest">Send Interest</button>';
  } else {
    foot.style.gridTemplateColumns = '1fr 1fr';
    foot.innerHTML =
      '<button type="button" class="btn outline" data-back>← Back</button>' +
      '<button type="button" class="btn" id="sendInterest">Send Interest</button>';
  }
  const send = el('sendInterest');
  if (send) send.onclick = submitInterest;
}

function renderReview() {
  const body = el('reviewBody');
  if (!body) return;
  const s = studio();
  const showEditChip = state.reviewEntry === 'customize';
  body.innerHTML =
    '<div class="review-summary"><div class="thumb"></div><div style="flex:1"><b>' +
    esc(offerTitle()) +
    '</b><div style="font-weight:900;color:var(--blue2);margin-top:4px">' +
    inr(offerPrice()) +
    '</div></div>' +
    (showEditChip ? '<button type="button" class="btn sm outline" data-to="customize">Edit</button>' : '') +
    '</div>' +
    '<div class="cust-hd">Event Details</div>' +
    '<div class="kv-row"><span>Studio</span><b>' +
    esc(s.name) +
    '</b></div>' +
    '<div class="kv-row review-date-kv"><span>Date</span><b id="reviewEventDate">' +
    formatDate(state.date) +
    '</b></div>' +
    (state.mode === 'service'
      ? '<div class="pad16" style="padding-top:0;padding-bottom:8px">' + eventDatePickHtml() + '</div>'
      : '') +
    '<div class="kv-row"><span>Location</span><b>' +
    esc(state.location) +
    '</b></div>' +
    '<div class="kv-row"><span>Photography for</span><b>' +
    esc(needLabel()) +
    '</b></div>' +
    (state.mode === 'wedding' && state.community !== 'all'
      ? '<div class="kv-row"><span>Community</span><b>' +
        esc(
          (COMMUNITIES.find(function (c) {
            return c.id === state.community;
          }) || {}).label || state.community
        ) +
        '</b></div>'
      : '') +
    (state.mode === 'wedding'
      ? '<div class="kv-row"><span>Package level</span><b>' +
        esc(state.pkgLevel) +
        '</b></div><div class="kv-row"><span>Budget (search)</span><b>' +
        inr(state.budgetMin) +
        ' – ' +
        inr(state.budgetMax) +
        '</b></div>'
      : '<div class="kv-row"><span>Budget (search)</span><b>' +
        inr(state.svcBudgetMin) +
        ' – ' +
        inr(state.svcBudgetMax) +
        '</b></div>') +
    '<div class="cust-hd">Selected Requirements</div>' +
    '<div id="revReqs"></div>' +
    (state.mode === 'wedding'
      ? '<div class="cust-hd">Policies & payment</div>' + custRenderPolicies(activePackageOwner())
      : '<div class="cust-hd">Policies</div>' + custRenderPolicies(activeServiceOwner())) +
    (state.customize.notes
      ? '<div class="cust-hd">Additional Notes</div><p style="font-size:13px;font-weight:600;color:var(--mut)">' +
        esc(state.customize.notes) +
        '</p>'
      : '');
  const reqs = el('revReqs');
  if (reqs) {
    const lines = selectedRequirementsLines();
    reqs.innerHTML = lines.length
      ? lines.map(function (l) {
          return '<div class="kv-row"><span>•</span><b style="text-align:left">' + esc(l) + '</b></div>';
        }).join('')
      : '<p class="sub">No add-ons selected</p>';
  }
  bindDatePickButtons(body);
  updateReviewDateLabels();
  renderReviewDateBar();
  renderReviewFooter();
}

function renderSentTimeline() {
  const box = el('sentTimeline');
  if (!box) return;
  box.innerHTML = TIMELINE.map(function (step, i) {
    const cls = i === 0 ? 'done' : i === 1 ? 'cur' : '';
    return (
      '<div class="tl-item ' +
      cls +
      '"><div class="tl-dot">' +
      (i === 0 ? '✓' : '') +
      '</div><div class="tl-bd"><b>' +
      esc(step.label) +
      '</b><span>' +
      esc(step.sub) +
      '</span></div></div>'
    );
  }).join('');
}

function renderInterests() {
  const list = el('intList');
  if (!list) return;
  const items = state.intTab === 'active' ? state.interests.filter(function (x) {
    return x.status !== 'past';
  }) : state.interests.filter(function (x) {
    return x.status === 'past';
  });
  if (!items.length) {
    list.innerHTML =
      '<p style="text-align:center;padding:32px 16px;color:var(--mut);font-weight:600">No interests yet. Send one from a package or service.</p>';
    return;
  }
  list.innerHTML = items.map(function (it) {
    return (
      '<button type="button" class="int-card" data-int-id="' +
      esc(it.id) +
      '"><b>' +
      esc(it.studioName) +
      '</b><div style="font-size:12px;color:var(--mut);font-weight:700;margin-top:4px">' +
      esc(it.offerName) +
      ' · ' +
      formatDate(it.date) +
      '</div><span class="status ' +
      (it.statusLabel === 'Accepted' ? 'ok' : 'review') +
      '">' +
      esc(it.statusLabel) +
      '</span><div style="font-size:12px;font-weight:800;color:var(--blue2);margin-top:8px">View Details ›</div></button>'
    );
  }).join('');
  list.querySelectorAll('[data-int-id]').forEach(function (btn) {
    btn.onclick = function () {
      state.activeInterestId = btn.getAttribute('data-int-id');
      renderInterestDetail();
      show('interestDetail', 'interests');
    };
  });
}

function renderInterestDetail() {
  const it = interestById(state.activeInterestId);
  if (!it) return;
  el('intDetailHead').innerHTML =
    '<div class="review-summary"><div class="thumb"></div><div><b>' +
    esc(it.studioName) +
    '</b><div style="font-size:12px;color:var(--mut);font-weight:700">' +
    esc(it.offerName) +
    '</div><span class="status review">' +
    esc(it.statusLabel) +
    '</span></div></div>';
  el('intDetailBody').innerHTML =
    '<div class="cust-hd">Event Details</div>' +
    '<div class="kv-row"><span>Date</span><b>' +
    formatDate(it.date) +
    '</b></div>' +
    '<div class="kv-row"><span>Location</span><b>' +
    esc(it.location) +
    '</b></div>' +
    '<div class="kv-row"><span>Photography for</span><b>' +
    esc(it.needLabel || '—') +
    '</b></div>' +
    '<div class="kv-row"><span>Price (est.)</span><b>' +
    inr(it.price) +
    '</b></div>' +
    (it.coverageSummary
      ? '<div class="cust-hd">Coverage</div><p style="font-size:13px;font-weight:600;color:var(--mut);margin:0 0 12px">' +
        esc(it.coverageSummary) +
        '</p>'
      : '') +
    (it.requirements && it.requirements.length
      ? '<div class="cust-hd">Requested requirements</div>' +
        it.requirements
          .map(function (r) {
            return '<div class="kv-row"><span>•</span><b style="text-align:left">' + esc(r) + '</b></div>';
          })
          .join('')
      : '') +
    (it.notes
      ? '<div class="cust-hd">Notes</div><p style="font-size:13px;font-weight:600;color:var(--mut)">' + esc(it.notes) + '</p>'
      : '') +
    (it.paymentSummary
      ? '<div class="kv-row"><span>Payment</span><b>' + esc(it.paymentSummary) + '</b></div>'
      : '') +
    (it.deliverySummary
      ? '<div class="kv-row"><span>Delivery</span><b style="font-size:12px">' + esc(it.deliverySummary) + '</b></div>'
      : '') +
    (it.requirementsOwner && it.requirementsOwner.length
      ? '<div class="cust-hd">Studio requirements</div><ul class="chk-list">' +
        it.requirementsOwner
          .map(function (r) {
            return '<li>' + esc(r) + '</li>';
          })
          .join('') +
        '</ul>'
      : '') +
    '<div class="cust-hd">Status Timeline</div>' +
    '<div class="timeline">' +
    TIMELINE.map(function (step, i) {
      const cls = i === 0 ? 'done' : i === 1 ? 'cur' : '';
      return (
        '<div class="tl-item ' +
        cls +
        '"><div class="tl-dot">' +
        (i === 0 ? '✓' : '') +
        '</div><div class="tl-bd"><b>' +
        esc(step.label) +
        '</b><span>' +
        (i === 1 ? formatDate(it.sentAt) + ' · 10:30 AM' : esc(step.sub)) +
        '</span></div></div>'
      );
    }).join('') +
    '</div>';
}

function submitInterest() {
  if (!state.date) {
    toast('Please select an event date');
    openReviewDateModal();
    return;
  }
  if (photographerDateUnavailable(state.studioId, state.date)) {
    showDateFullModal();
    return;
  }
  const pkgO = state.mode === 'wedding' ? activePackageOwner() : null;
  const svcO = state.mode === 'service' ? activeServiceOwner() : null;
  let cov = '';
  if (pkgO && pkgO.coverageByFunction) {
    const fns = pkgO.functions && pkgO.functions.length ? pkgO.functions : Object.keys(pkgO.coverageByFunction);
    cov = fns
      .filter(function (fn) {
        return pkgO.coverageByFunction[fn];
      })
      .map(function (fn) {
        const b = pkgO.coverageByFunction[fn];
        return fn + ' · ' + (b.duration || '');
      })
      .join('; ');
  } else if (svcO) {
    cov = (svcO.duration || '') + (svcO.team ? ' · photo team assigned' : '');
  }
  const paySrc = pkgO || svcO;
  const pay =
    paySrc && paySrc.paymentStages
      ? paySrc.paymentStages.map(function (p) {
          return p.label + ' ' + p.pct + '%';
        }).join(' · ')
      : '';
  const rec = {
    id: 'int_' + Date.now(),
    mode: state.mode,
    studioId: state.studioId,
    studioName: studio().name,
    offerName: offerTitle(),
    needLabel: needLabel(),
    date: state.date,
    location: state.location,
    community: state.community,
    pkgLevel: state.pkgLevel,
    price: offerPrice(),
    requirements: selectedRequirementsLines(),
    notes: state.customize.notes || '',
    paymentSummary: pay,
    coverageSummary: cov,
    deliverySummary:
      pkgO && pkgO.deliveryMap
        ? Object.keys(pkgO.deliveryMap)
            .slice(0, 2)
            .map(function (k) {
              return k + ' · ' + pkgO.deliveryMap[k];
            })
            .join('; ')
        : svcO && svcO.deliveryMap
          ? Object.keys(svcO.deliveryMap)[0] + ' · ' + svcO.deliveryMap[Object.keys(svcO.deliveryMap)[0]]
          : '',
    requirementsOwner: (pkgO || svcO || {}).requirements || [],
    policiesSummary: (pkgO || svcO || {}).policies || [],
    statusLabel: 'Under Review',
    status: 'active',
    sentAt: new Date().toISOString().slice(0, 10),
  };
  state.interests.unshift(rec);
  saveInterests();
  renderSentTimeline();
  show('sent', 'interests');
}

function injectChrome() {
  const logo = svgIcon ? svgIcon('logo') : '';
  if (el('brandIcoSearch')) el('brandIcoSearch').innerHTML = logo;
  if (el('navHomeIco')) el('navHomeIco').innerHTML = svgIcon('house');
  if (el('navSearchIco')) el('navSearchIco').innerHTML = svgIcon('search');
  if (el('navIntIco')) el('navIntIco').innerHTML = svgIcon('heart', 'flow-ico-sm');
  if (el('navProfIco')) el('navProfIco').innerHTML = svgIcon('people', 'flow-ico-sm');
}

function bindEvents() {
  el('goResults').onclick = function () {
    if (!state.photoNeed) {
      toast('Select what you need photography for');
      return;
    }
    syncModeFromNeed();
    renderResults();
    show('results', 'search');
  };
  document.querySelector('.phone').addEventListener('click', function (e) {
    if (e.target.closest('[data-back]')) {
      goBack();
      return;
    }
    const to = e.target.closest('[data-to]');
    if (to) {
      const id = to.getAttribute('data-to');
      if (id === 'customize') {
        renderCustomize();
        show('customize', 'detail');
      } else if (id === 'interests') {
        renderInterests();
        show('interests', 'search');
      } else if (id === 'review') {
        state.reviewEntry = 'customize';
        renderReview();
        show('review', 'customize');
      } else show(id);
      return;
    }
  });
  el('profPrimary').onclick = function () {
    if (state.mode === 'wedding') {
      renderCatalog();
      show('catalog', 'profile');
    } else {
      if (!studioOffersService(state.studioId, state.photoNeed)) {
        toast('This studio does not list ' + needLabel());
        return;
      }
      state.serviceId = state.photoNeed;
      renderServiceCatalog();
      show('catalog', 'profile');
    }
  };
  el('profMessage').onclick = function () {
    toast('Messaging opens in full app');
  };
  document.querySelectorAll('[data-ptab]').forEach(function (btn) {
    btn.onclick = function () {
      state.profTab = btn.getAttribute('data-ptab');
      document.querySelectorAll('[data-ptab]').forEach(function (b) {
        b.classList.toggle('on', b === btn);
      });
      renderProfPanel();
    };
  });
  const goCust = el('goCustomize');
  if (goCust) {
    goCust.onclick = function () {
      if (!ensureEventDateForInterest()) return;
      renderCustomize();
      show('customize', 'detail');
    };
  }
  const goInterest = el('goCustomize2');
  if (goInterest) {
    goInterest.onclick = function () {
      if (!ensureEventDateForInterest()) return;
      state.reviewEntry = 'direct';
      renderReview();
      show('review', 'detail');
    };
  }
  el('goReview').onclick = function () {
    if (!ensureEventDateForInterest()) return;
    state.reviewEntry = 'customize';
    renderReview();
    show('review', 'customize');
  };
  document.querySelectorAll('[data-intab]').forEach(function (btn) {
    btn.onclick = function () {
      state.intTab = btn.getAttribute('data-intab');
      document.querySelectorAll('[data-intab]').forEach(function (b) {
        b.classList.toggle('on', b === btn);
      });
      renderInterests();
    };
  });
  document.querySelectorAll('[data-nav]').forEach(function (btn) {
    btn.onclick = function () {
      const nav = btn.getAttribute('data-nav');
      if (nav === 'home' || nav === 'search') {
        renderSearchForm();
        show('search', 'search');
      } else if (nav === 'interests') {
        renderInterests();
        show('interests', 'search');
      } else toast('Profile — demo');
    };
  });
  el('msgPhotographer').onclick = function () {
    toast('Open chat with photographer');
  };
  const reviewDateModal = el('reviewDateModal');
  if (reviewDateModal && !reviewDateModal._bound) {
    reviewDateModal._bound = true;
    reviewDateModal.querySelector('[data-cal-cancel]').onclick = closeReviewDateModal;
    reviewDateModal.querySelector('[data-cal-done]').onclick = function () {
      const pick = state.reviewCalPick;
      if (!pick) {
        toast('Please select a date');
        return;
      }
      if (photographerDateUnavailable(state.studioId, pick)) {
        toast('That date is fully booked — choose another');
        return;
      }
      state.date = pick;
      const searchDt = el('fDate');
      if (searchDt) searchDt.value = state.date;
      updateReviewDateLabels();
      if (state.mode === 'service') {
        renderDetailDateBar();
        if (activeScreenId() === 'catalog') renderCatalogDateBar();
      }
      closeReviewDateModal();
    };
  }
  const dateFullChange = el('dateFullChange');
  if (dateFullChange && !dateFullChange._bound) {
    dateFullChange._bound = true;
    dateFullChange.onclick = function () {
      closeDateFullModal();
      openReviewDateModal();
    };
  }
  const dateFullModal = el('dateFullModal');
  if (dateFullModal && !dateFullModal._bound) {
    dateFullModal._bound = true;
    dateFullModal.addEventListener('click', function (e) {
      if (e.target === dateFullModal) closeDateFullModal();
    });
  }
}

function bootPhotoCustomer() {
  try {
    if (!el('goResults')) throw new Error('Open ' + DEMO_FILE + ', not the shell.');
    loadInterests();
    injectChrome();
    renderSearchForm();
    bindEvents();
    const tag = el('buildTag');
    if (tag) tag.textContent = PHOTO_CUSTOMER_BUILD + ' · Default home search';
    if (el('bootError')) el('bootError').hidden = true;
  } catch (err) {
    console.error(err);
    const box = el('bootError');
    if (box) {
      box.hidden = false;
      box.innerHTML = '<h1 style="color:#DC2626">Demo did not start</h1><p>' + esc(err.message) + '</p>';
    }
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootPhotoCustomer);
} else {
  bootPhotoCustomer();
}
