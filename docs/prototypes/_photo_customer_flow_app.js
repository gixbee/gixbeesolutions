const PHOTO_CUSTOMER_BUILD = '2026-10-13-photo-customer-owner-mirror-v6b';
const DEMO_FILE = 'GIXBEE-PHOTO-CUSTOMER-FINALFLOW.html';
const STORAGE_KEY = 'GIXBEE_PHOTO_CUSTOMER_INTERESTS_V2';

const LOCATIONS = ['Pathanamthitta, Kerala', 'Kottayam, Kerala', 'Kochi, Kerala'];
const COMMUNITIES = [
  { id: 'all', label: 'All', icon: '☯' },
  { id: 'hindu', label: 'Hindu', icon: '🕉' },
  { id: 'muslim', label: 'Muslim', icon: '☪' },
  { id: 'christian', label: 'Christian', icon: '✝' },
  { id: 'other', label: 'Others', icon: '◆' },
];
const PKG_LEVELS = ['All', 'Basic', 'Standard', 'Premium'];
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
  customize: { extras: {}, duration: 'inc', albumSize: '12×12', albumPages: '30', functions: {}, notes: '' },
  interests: [],
  activeInterestId: null,
  detailBack: 'catalog',
  backScreen: 'search',
  catalogFilterPanel: null,
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
    Object.keys(state.customize.functions || {}).forEach(function (fn) {
      if (state.customize.functions[fn]) lines.push('Also cover: ' + fn);
    });
    if (state.customize.albumSize) lines.push('Album ' + state.customize.albumSize + ' · ' + state.customize.albumPages + ' pages');
  } else {
    const svc = activeService();
    (svc.durationOptions || []).forEach(function (d) {
      if (d.id === state.customize.duration) lines.push('Duration: ' + d.label);
    });
    serviceExtras().forEach(function (ex) {
      if (state.customize.extras[ex.id]) lines.push(ex.label + ' — ' + inr(ex.price));
    });
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

function renderSearchForm() {
  const hero = el('searchHero');
  const form = el('searchForm');
  if (!hero || !form) return;
  hero.innerHTML =
    '<div class="hero-wed"><h2>Find Your Wedding Photographer</h2><p>Compare packages, coverage, and deliverables from trusted studios.</p></div>';
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
    '<div class="fld"><label>Budget Range (Optional)</label><div class="budget-row">' +
    '<div class="sel-box"><select id="fBudMin">' +
    [
      { v: 50000, l: '₹ 50,000' },
      { v: 75000, l: '₹ 75,000' },
      { v: 100000, l: '₹ 1,00,000' },
    ].map(function (o) {
      return (
        '<option value="' +
        o.v +
        '"' +
        (state.budgetMin === o.v ? ' selected' : '') +
        '>' +
        o.l +
        '</option>'
      );
    }).join('') +
    '</select></div>' +
    '<div class="sel-box"><select id="fBudMax">' +
    [
      { v: 100000, l: '₹ 1,00,000' },
      { v: 150000, l: '₹ 1,50,000' },
      { v: 200000, l: '₹ 2,00,000' },
    ].map(function (o) {
      return (
        '<option value="' +
        o.v +
        '"' +
        (state.budgetMax === o.v ? ' selected' : '') +
        '>' +
        o.l +
        '</option>'
      );
    }).join('') +
    '</select></div></div></div>';
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
  list.innerHTML = studioList().map(function (s) {
    const from = state.mode === 'wedding' ? s.weddingFrom : s.serviceFrom;
    const tag =
      state.mode === 'wedding'
        ? '<span class="ph-tag">Christian</span><span class="ph-tag">Standard</span>'
        : '<span class="ph-tag">' + esc(needLabel()) + '</span>';
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
      inr(from) +
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

function renderCatalog() {
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
      return (
        '<button type="button" class="pkg-card" data-pkg="' +
        p.id +
        '"><div class="thumb"></div><div><b>' +
        esc(p.name) +
        '</b><div class="price">' +
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
}

function renderCustomize() {
  const sum = el('custSummary');
  const body = el('custBody');
  const title = offerTitle();
  const price = state.mode === 'wedding' ? activePackage().price : activeService().price;
  if (sum) {
    sum.innerHTML =
      '<div class="review-summary"><div class="thumb"></div><div><b style="font-size:14px;color:var(--navy)">' +
      esc(title) +
      '</b><div style="font-size:15px;font-weight:900;color:var(--blue2);margin-top:4px">' +
      inr(price) +
      '</div></div></div>';
  }
  if (!body) return;
  if (state.mode === 'wedding') {
    const pkg = activePackage();
    const owner = activePackageOwner();
    const optFns = activePackage().optionalFunctions || owner.functions || ['Engagement', 'Reception'];
    body.innerHTML =
      '<div class="cust-hd">Additional Services (Optional)</div>' +
      packageExtras().map(function (ex) {
        return (
          '<label class="extra-line"><span><input type="checkbox" data-wex="' +
          ex.id +
          '"' +
          (state.customize.extras[ex.id] ? ' checked' : '') +
          '> ' +
          esc(ex.label) +
          '</span><span style="font-weight:900">' +
          inr(ex.price) +
          '</span></label>'
        );
      }).join('') +
      '<div class="cust-hd">Album Preferences</div>' +
      '<div class="budget-row"><div class="fld"><label>Album Size</label><div class="sel-box"><select id="albSize"><option' +
      (state.customize.albumSize === '12×12' ? ' selected' : '') +
      '>12×12</option><option' +
      (state.customize.albumSize === '10×10' ? ' selected' : '') +
      '>10×10</option></select></div></div>' +
      '<div class="fld"><label>Album Pages</label><div class="sel-box"><select id="albPages"><option' +
      (state.customize.albumPages === '30' ? ' selected' : '') +
      '>30</option><option' +
      (state.customize.albumPages === '40' ? ' selected' : '') +
      '>40</option></select></div></div></div>' +
      '<div class="cust-hd">Other Functions to Cover</div>' +
      optFns
        .map(function (fn) {
          return (
            '<label class="extra-line"><span><input type="checkbox" data-fn="' +
            esc(fn) +
            '"' +
            (state.customize.functions[fn] ? ' checked' : '') +
            '> ' +
            esc(fn) +
            '</span></label>'
          );
        })
        .join('') +
      '<div class="cust-hd">Additional Notes</div><textarea class="notes" id="custNotes" maxlength="500" placeholder="Any special requests…">' +
      esc(state.customize.notes) +
      '</textarea><div class="notes-count"><span id="noteCt">0</span>/500</div>';
    const goRev = el('goReview');
    if (goRev) goRev.textContent = 'Next: Review Interest';
  } else {
    body.innerHTML =
      '<div class="cust-hd">Coverage Duration</div>' +
      (activeService().durationOptions || activeServiceOwner().durationOptions || []).map(function (d) {
        return (
          '<label class="radio-card' +
          (state.customize.duration === d.id ? ' on' : '') +
          '"><input type="radio" name="dur" value="' +
          d.id +
          '"' +
          (state.customize.duration === d.id ? ' checked' : '') +
          '> ' +
          esc(d.label) +
          (d.add ? ' · +' + inr(d.add) : '') +
          '</label>'
        );
      }).join('') +
      '<div class="cust-hd">Additional Services</div>' +
      serviceExtras().map(function (ex) {
        return (
          '<label class="extra-line"><span><input type="checkbox" data-sex="' +
          ex.id +
          '"' +
          (state.customize.extras[ex.id] ? ' checked' : '') +
          '> ' +
          esc(ex.label) +
          '</span><span style="font-weight:900">' +
          inr(ex.price) +
          '</span></label>'
        );
      }).join('') +
      '<div class="cust-hd">Additional Notes</div><textarea class="notes" id="custNotes" maxlength="500">' +
      esc(state.customize.notes) +
      '</textarea><div class="notes-count"><span id="noteCt">0</span>/500</div>';
    const goRev = el('goReview');
    if (goRev) goRev.textContent = 'Continue';
  }
  bindCustomize();
}

function bindCustomize() {
  document.querySelectorAll('[data-wex]').forEach(function (inp) {
    inp.onchange = function () {
      state.customize.extras[inp.getAttribute('data-wex')] = inp.checked;
    };
  });
  document.querySelectorAll('[data-sex]').forEach(function (inp) {
    inp.onchange = function () {
      state.customize.extras[inp.getAttribute('data-sex')] = inp.checked;
    };
  });
  document.querySelectorAll('[name=dur]').forEach(function (inp) {
    inp.onchange = function () {
      state.customize.duration = inp.value;
      renderCustomize();
    };
  });
  document.querySelectorAll('[data-fn]').forEach(function (inp) {
    inp.onchange = function () {
      state.customize.functions[inp.getAttribute('data-fn')] = inp.checked;
    };
  });
  const albSize = el('albSize');
  const albPages = el('albPages');
  if (albSize) albSize.onchange = function () {
    state.customize.albumSize = albSize.value;
  };
  if (albPages) albPages.onchange = function () {
    state.customize.albumPages = albPages.value;
  };
  const notes = el('custNotes');
  const ct = el('noteCt');
  if (notes) {
    const upd = function () {
      state.customize.notes = notes.value;
      if (ct) ct.textContent = String(notes.value.length);
    };
    notes.oninput = upd;
    upd();
  }
}

function renderReview() {
  const body = el('reviewBody');
  if (!body) return;
  const s = studio();
  body.innerHTML =
    '<div class="review-summary"><div class="thumb"></div><div style="flex:1"><b>' +
    esc(offerTitle()) +
    '</b><div style="font-weight:900;color:var(--blue2);margin-top:4px">' +
    inr(offerPrice()) +
    '</div></div><button type="button" class="btn sm outline" data-to="customize">Edit</button></div>' +
    '<div class="cust-hd">Event Details</div>' +
    '<div class="kv-row"><span>Studio</span><b>' +
    esc(s.name) +
    '</b></div>' +
    '<div class="kv-row"><span>Date</span><b>' +
    formatDate(state.date) +
    '</b></div>' +
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
      : '') +
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
      state.detailTab = 'overview';
      state.detailBack = 'profile';
      renderDetail();
      show('detail', 'profile');
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
  ['goCustomize', 'goCustomize2'].forEach(function (id) {
    const n = el(id);
    if (n) n.onclick = function () {
      renderCustomize();
      show('customize', 'detail');
    };
  });
  el('goReview').onclick = function () {
    renderReview();
    show('review', 'customize');
  };
  el('sendInterest').onclick = submitInterest;
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
