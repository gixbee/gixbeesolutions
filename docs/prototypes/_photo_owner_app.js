const PHOTO_OWNER_BUILD = '2026-10-07-photo-owner-svc-deliverables-v1';
const STORAGE_KEY = 'GIXBEE_PHOTO_OWNER_V1';

const INDIAN_STATES = {
  Kerala: ['Thrissur', 'Ernakulam', 'Kozhikode', 'Kottayam', 'Palakkad', 'Malappuram', 'Thiruvananthapuram'],
  Karnataka: ['Bengaluru Urban', 'Mysuru', 'Mangalore', 'Udupi'],
  'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai'],
};

const PKG_LEVELS = ['Basic', 'Standard', 'Premium', 'Custom'];
const PKG_FUNCTIONS = [
  'Wedding & Reception',
  'Reception',
  'Wedding Eve',
  'Engagement',
  'Baptism',
  'First Communion',
  'Birthday',
  'Anniversary',
  'Baby Shower',
  'Naming Ceremony',
  'Housewarming',
  'Corporate Event',
  'Funeral / Memorial',
  'Other',
];
const FUNCTION_HINTS = {
  'Wedding & Reception': 'Wedding followed by reception on the same day',
  Reception: 'Separate reception function / day',
  'Wedding Eve': 'Pre-wedding night function',
  Engagement: 'Engagement ceremony / ring ceremony',
  Baptism: 'Baptism ceremony',
  'First Communion': 'First communion ceremony',
  Birthday: 'Birthday celebration',
  Anniversary: 'Anniversary celebration',
  'Baby Shower': 'Baby shower function',
  'Naming Ceremony': 'Naming ceremony',
  Housewarming: 'Housewarming ceremony',
  'Corporate Event': 'Corporate or official event',
  'Funeral / Memorial': 'Funeral or memorial service',
  Other: '',
};
const CEREMONY_TYPES = ['Christian', 'Hindu', 'Muslim', 'Sikh', 'Jain', 'Buddhist', 'Other'];
const SVC_CATEGORIES = [
  { id: 'wedding', label: 'Wedding Photography' },
  { id: 'portrait', label: 'Portrait Photography' },
  { id: 'baby', label: 'Baby & Kids' },
  { id: 'maternity', label: 'Maternity' },
  { id: 'newborn', label: 'Newborn' },
  { id: 'couple', label: 'Couple' },
  { id: 'funeral', label: 'Funeral / Memorial' },
  { id: 'product', label: 'Product' },
  { id: 'corporate', label: 'Corporate' },
  { id: 'realestate', label: 'Real Estate' },
  { id: 'event', label: 'Event Photography' },
  { id: 'fashion', label: 'Fashion & Portfolio' },
  { id: 'food', label: 'Food' },
  { id: 'commercial', label: 'Commercial' },
  { id: 'drone', label: 'Drone / Aerial' },
  { id: 'reel', label: 'Reel & Short Video' },
  { id: 'production', label: 'Photo & Video Production' },
];

const PKG_STEPS = [
  { title: 'Package basics', sub: 'Basic information about the package.' },
  { title: 'Select Functions', sub: '' },
  { title: 'Ceremony type', sub: 'Choose applicable ceremony types.' },
  { title: 'Coverage details', sub: 'Set coverage details for selected functions.' },
  { title: 'Deliverables', sub: 'Select photos, videos, albums and other deliverables included in this package.' },
  { title: 'Special services & extras', sub: 'Select additional services with price.' },
  { title: 'Delivery timeline', sub: 'Set delivery timeline for each deliverable.' },
  { title: 'Payment stages', sub: 'Set payment stages and policies.' },
  { title: 'Customer requirements', sub: 'Optional requirements from customer.' },
  { title: 'Review & publish', sub: 'Review all details and publish.' },
];

const SVC_STEPS = [
  { title: 'Select service category', sub: 'Choose the category for your photography service.' },
  { title: 'Service basics', sub: 'Add basic information about your service.' },
  { title: 'Pricing', sub: 'Set your service pricing.' },
  { title: 'Duration & coverage (optional)', sub: 'Add duration, team and coverage details.' },
  { title: "What's included", sub: 'Select deliverables included in this service.' },
  { title: 'Optional extras', sub: 'Add additional services (if available).' },
  { title: 'Delivery', sub: 'Set delivery timeline for each deliverable.' },
  { title: 'Policies, requirements & review', sub: 'Set policies, customer requirements and publish.' },
];

function defaultStore() {
  return {
    biz: {
      name: 'Archana Photography',
      loc: 'Sakthan Nagar, Thrissur',
      registeredState: 'Kerala',
      registeredDistrict: 'Thrissur',
      type: 'Photography',
      vertical: 'Service',
      phone: '+91 98765 43210',
      email: 'hello@archanaphoto.in',
      gstin: '—',
      verified: true,
      memberSince: '2024',
    },
    serviceAreas: {
      states: ['Kerala'],
      districts: { Kerala: ['Thrissur', 'Ernakulam'] },
    },
    packages: [
      {
        id: 'pkg-demo-1',
        name: 'Classic Wedding Package',
        level: 'Premium',
        functions: ['Wedding & Reception', 'Reception'],
        price: 150000,
        listPrice: 150000,
        discountYes: 'no',
        discountPct: 0,
        status: 'published',
        deliverables: '500 edited photos, wedding film 15 min',
        coverage: '2 photographers, 10 hours',
      },
      {
        id: 'pkg-demo-2',
        name: 'Engagement Standard',
        level: 'Standard',
        functions: ['Engagement'],
        price: 35000,
        listPrice: 40000,
        discountPct: 12,
        status: 'draft',
        deliverables: '150 edited photos',
        coverage: '1 photographer, 4 hours',
      },
    ],
    services: [
      {
        id: 'svc-demo-1',
        name: 'Candid Photography',
        category: 'event',
        price: 25000,
        listPrice: 28000,
        discountPct: 10,
        status: 'published',
        blurb: 'Natural moments across the event.',
      },
    ],
    pkgFilter: 'all',
    hubTab: 'packages',
    operators: [
      { id: 'op_owner', name: 'Archana K.', phone: '+91 94470 55566', role: 'owner' },
      { id: 'op_mgr1', name: 'Priya Nair', phone: '+91 98470 11223', role: 'manager' },
    ],
    deletedBusinesses: [
      {
        id: 'biz-del-1',
        name: 'Studio Nine Photography',
        type: 'Photography',
        loc: 'Kochi, Kerala',
        deletedAt: '2026-09-12',
      },
    ],
  };
}

const OPERATOR_ROLE_LABELS = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };

let store = defaultStore();
let saDraft = null;
let wiz = { mode: 'package', step: 0, draft: null, backTo: 'svcPkg', editId: null };

function needsCeremonyStep(functions) {
  const f = functions || [];
  return f.indexOf('Wedding & Reception') >= 0 || f.indexOf('Reception') >= 0 || f.indexOf('Engagement') >= 0;
}

function el(id) {
  return document.getElementById(id);
}
function showBootError(msg) {
  const box = el('bootError');
  if (!box) {
    alert(msg);
    return;
  }
  box.hidden = false;
  box.innerHTML =
    '<p style="color:#991B1B;font-weight:800;font-size:18px">Demo did not start</p><p style="line-height:1.5;color:#374151">' +
    esc(msg) +
    '</p><p style="margin-top:16px">Open <b>GIXBEE-PHOTO-OWNER-FINALFLOW.html</b> (full file with JavaScript inside).</p>';
}
function show(id) {
  document.querySelectorAll('.scr').forEach((s) => s.classList.toggle('on', s.id === id));
}
function openSvcPkgHub() {
  store.hubTab = 'packages';
  saveStore();
  renderSvcPkg();
  show('svcPkg');
}
function toast(m) {
  const t = el('toast');
  if (!t) return;
  t.textContent = m;
  t.style.display = 'block';
  setTimeout(() => (t.style.display = 'none'), 2600);
}
function inr(n) {
  return '₹ ' + Math.max(0, Math.round(+n || 0)).toLocaleString('en-IN');
}
function uid(prefix) {
  return prefix + '-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}
function levelClass(level) {
  return (level || 'Standard').toLowerCase();
}
function loadStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    store = Object.assign(defaultStore(), parsed);
    if (!store.packages) store.packages = defaultStore().packages;
    if (!store.services) store.services = defaultStore().services;
    if (!store.serviceAreas) store.serviceAreas = defaultStore().serviceAreas;
    if (!store.operators) store.operators = defaultStore().operators;
    if (!store.deletedBusinesses) store.deletedBusinesses = defaultStore().deletedBusinesses;
  } catch (_e) {
    store = defaultStore();
  }
}
function saveStore() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
}
function ensureRegisteredDistrict() {
  const st = store.biz.registeredState;
  const dist = store.biz.registeredDistrict;
  if (!store.serviceAreas.states.includes(st)) store.serviceAreas.states.push(st);
  if (!store.serviceAreas.districts[st]) store.serviceAreas.districts[st] = [];
  if (store.serviceAreas.districts[st].indexOf(dist) < 0) store.serviceAreas.districts[st].unshift(dist);
}

function areaSummaryText() {
  const sa = store.serviceAreas;
  if (!sa.states.length) return 'Set where you accept bookings.';
  const parts = sa.states.map((st) => {
    const ds = sa.districts[st] || [];
    return st + ' (' + ds.length + ' district' + (ds.length === 1 ? '' : 's') + ')';
  });
  return parts.join(' · ');
}

function operatorInitial(name) {
  const p = String(name || '?').trim().split(/\s+/);
  return (p[0][0] || '?').toUpperCase();
}

function ensureOperators() {
  if (!store.operators || !store.operators.length) {
    store.operators = defaultStore().operators.map(function (o) {
      return JSON.parse(JSON.stringify(o));
    });
  }
  return store.operators;
}

function renderPhotoOperators() {
  const sub = el('photoOperatorsSub');
  if (sub) sub.textContent = 'Who can manage · ' + store.biz.name;
  const list = el('photoOperatorsList');
  if (!list) return;
  const ops = ensureOperators();
  list.innerHTML = ops
    .map(function (op, idx) {
      const right =
        op.role === 'owner'
          ? '<span class="op-owner-tag">Owner</span>'
          : '<button type="button" class="op-remove" data-rm-photo-op="' +
            esc(op.id) +
            '">Remove</button>';
      return (
        '<div class="op-card"><div class="op-avatar a' +
        (idx % 4) +
        '">' +
        esc(operatorInitial(op.name)) +
        '</div><div class="op-meta"><b>' +
        esc(op.name) +
        '</b><span>' +
        esc(op.phone) +
        ' · ' +
        esc(OPERATOR_ROLE_LABELS[op.role] || 'Staff') +
        '</span></div><div class="op-actions">' +
        right +
        '</div></div>'
      );
    })
    .join('');
  list.querySelectorAll('[data-rm-photo-op]').forEach(function (btn) {
    btn.onclick = function () {
      const id = btn.getAttribute('data-rm-photo-op');
      const op = ops.find(function (x) {
        return x.id === id;
      });
      if (!op || !confirm('Remove ' + op.name + ' as an operator?')) return;
      store.operators = ops.filter(function (x) {
        return x.id !== id;
      });
      saveStore();
      renderPhotoOperators();
      toast('Operator removed');
    };
  });
}

function renderDeletedBusinesses() {
  const list = el('deletedBizList');
  if (!list) return;
  const items = store.deletedBusinesses || [];
  if (!items.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:0"><div class="hub-empty-ico">🗑</div><b>No deleted businesses</b><p>When you delete a listing, it appears here for 30 days so you can restore it.</p></div>';
    return;
  }
  list.innerHTML = items
    .map(function (b) {
      return (
        '<div class="del-biz-card" data-del-biz="' +
        esc(b.id) +
        '"><b>' +
        esc(b.name) +
        '</b><p class="sub">' +
        esc(b.type) +
        ' · ' +
        esc(b.loc) +
        '<br>Deleted ' +
        esc(b.deletedAt) +
        '</p><button type="button" class="btn-restore" data-restore-biz="' +
        esc(b.id) +
        '">Restore business</button></div>'
      );
    })
    .join('');
  list.querySelectorAll('[data-restore-biz]').forEach(function (btn) {
    btn.onclick = function () {
      const id = btn.getAttribute('data-restore-biz');
      const biz = (store.deletedBusinesses || []).find(function (x) {
        return x.id === id;
      });
      if (!biz) return;
      if (!confirm('Restore ' + biz.name + '? You can switch to it from List My Business.')) return;
      store.deletedBusinesses = store.deletedBusinesses.filter(function (x) {
        return x.id !== id;
      });
      saveStore();
      renderDeletedBusinesses();
      renderPhotoDash();
      toast('Business restored (demo)');
    };
  });
}

function renderLmb() {
  const wrap = el('lmbCards');
  if (!wrap) return;
  wrap.innerHTML =
    '<div class="biz-dash-card">' +
    '<div class="biz-row"><div class="biz-ico">📷</div><div style="flex:1">' +
    '<p class="biz-name">' +
    esc(store.biz.name) +
    '</p><p class="biz-type">Photography</p>' +
    '<p class="biz-meta"><span class="pill ok">Verified</span> · ' +
    esc(store.biz.loc) +
    '</p>' +
    '<div class="biz-badges"><span>3 new requests</span><span class="gy">Rs 2.1L this month</span></div>' +
    '<div class="biz-actions"><button type="button">Calendar</button><button type="button">Requests</button>' +
    '<button type="button" class="mgr-photo" id="dashPhotoManage">Manage</button></div>' +
    '</div></div></div>';
  el('dashPhotoManage').onclick = () => {
    renderPhotoDash();
    show('photoDash');
  };
}

function profCell(ico, label, value) {
  return (
    '<div class="prof-cell"><div class="prof-cell-ico">' +
    ico +
    '</div><div class="prof-cell-bd"><label>' +
    esc(label) +
    '</label><b>' +
    esc(value) +
    '</b></div></div>'
  );
}

function profGroup(title, icon, cellsHtml) {
  return (
    '<div class="prof-group"><div class="prof-group-hd"><span>' +
    icon +
    '</span>' +
    esc(title) +
    '</div>' +
    cellsHtml +
    '</div>'
  );
}

function renderPhotoBizProfile() {
  const b = store.biz;
  const nameEl = el('profBizName');
  if (nameEl) nameEl.textContent = b.name || '—';
  const tag = el('profBizTagline');
  if (tag) {
    tag.textContent =
      (b.type || 'Photography') + ' · ' + (b.vertical || 'Service') + ' · ' + (b.loc || '—');
  }
  const badges = el('profBadges');
  if (badges) {
    badges.innerHTML =
      (b.verified
        ? '<span class="prof-badge ver">✓ Verified</span>'
        : '<span class="prof-badge type">Verification pending</span>') +
      '<span class="prof-badge type">Gixbee LMB</span>';
  }
  const chips = el('profChips');
  if (chips) {
    const areaN = (store.serviceAreas.states || []).length;
    chips.innerHTML =
      '<div class="prof-chip"><b>' +
      esc(b.memberSince || '—') +
      '</b><span>Member since</span></div>' +
      '<div class="prof-chip"><b>' +
      store.packages.length +
      '</b><span>Packages</span></div>' +
      '<div class="prof-chip"><b>' +
      areaN +
      '</b><span>States</span></div>';
  }
  const groups = el('profDetailGroups');
  if (!groups) return;
  groups.innerHTML =
    profGroup(
      'Contact',
      '📞',
      profCell('📱', 'Phone', b.phone || '—') + profCell('✉️', 'Email', b.email || '—')
    ) +
    profGroup(
      'Location',
      '📍',
      profCell('🏠', 'Address / area', b.loc || '—') +
        profCell('🗺', 'Service areas', areaSummaryText())
    ) +
    profGroup(
      'Registration',
      '📋',
      profCell('🏛', 'Registered state', b.registeredState || '—') +
        profCell('📌', 'Registered district', b.registeredDistrict || '—') +
        profCell('🏷', 'Business type', b.type || 'Photography')
    ) +
    profGroup('Tax & billing', '💳', profCell('🧾', 'GSTIN', b.gstin && b.gstin !== '—' ? b.gstin : 'Not added'));
}

function renderPhotoDash() {
  el('dashBizName').textContent = store.biz.name;
  el('dashLocTxt').textContent = store.biz.loc;
  el('dashLocIco').innerHTML = photoIcon('pin');
  el('areaCardIco').innerHTML = photoIcon('pin');
  el('areaSummary').textContent = areaSummaryText();
  const q = el('quickGrid');
  q.innerHTML = [
    { id: 'svcPkg', cls: 'pink', ico: '📦', label: 'Services & Packages' },
    { id: 'calendar', cls: 'blue', ico: '📅', label: 'Calendar' },
    { id: 'gallery', cls: 'blue', ico: '🖼', label: 'Photos & Gallery' },
    { id: 'requests', cls: 'orange', ico: '🔔', label: 'Booking Requests', badge: '3' },
    { id: 'photoOperators', cls: 'teal', ico: '👥', label: 'Operators' },
    {
      id: 'deletedBusiness',
      cls: 'gray',
      ico: '🗑',
      label: 'Deleted business',
      badge: store.deletedBusinesses.length ? String(store.deletedBusinesses.length) : '',
    },
  ]
    .map(
      (t) =>
        '<button type="button" class="qtile ' +
        t.cls +
        '" data-go="' +
        t.id +
        '">' +
        (t.badge ? '<span class="badge">' + t.badge + '</span>' : '') +
        '<div class="qi">' +
        t.ico +
        '</div><b>' +
        esc(t.label) +
        '</b></button>'
    )
    .join('');
  q.querySelectorAll('[data-go]').forEach((btn) => {
    btn.onclick = () => {
      const dest = btn.getAttribute('data-go');
      if (dest === 'svcPkg') openSvcPkgHub();
      else if (dest === 'photoOperators') {
        renderPhotoOperators();
        show(dest);
      } else if (dest === 'deletedBusiness') {
        renderDeletedBusinesses();
        show(dest);
      } else show(dest);
    };
  });
}

function esc(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/"/g, '&quot;');
}

function startSaDraft() {
  saDraft = JSON.parse(JSON.stringify(store.serviceAreas));
  ensureRegisteredDistrictInDraft();
}
function ensureRegisteredDistrictInDraft() {
  const st = store.biz.registeredState;
  const dist = store.biz.registeredDistrict;
  if (saDraft.states.indexOf(st) < 0) saDraft.states.push(st);
  if (!saDraft.districts[st]) saDraft.districts[st] = [];
  if (saDraft.districts[st].indexOf(dist) < 0) saDraft.districts[st].unshift(dist);
}

function renderStateList() {
  const q = (el('stateSearch').value || '').trim().toLowerCase();
  const list = el('stateList');
  const states = Object.keys(INDIAN_STATES).filter((s) => !q || s.toLowerCase().includes(q));
  list.innerHTML = states
    .map((st) => {
      const on = saDraft.states.indexOf(st) >= 0;
      const locked = st === store.biz.registeredState;
      return (
        '<div class="chk-row' +
        (on ? ' on' : '') +
        (locked ? ' locked' : '') +
        '" data-state="' +
        esc(st) +
        '">' +
        '<span class="chk-box">' +
        (on ? photoIcon('check') : locked ? '🔒' : '') +
        '</span><span>' +
        esc(st) +
        (locked ? ' <span style="font-size:11px;color:var(--mut)">(registered)</span>' : '') +
        '</span></div>'
      );
    })
    .join('');
  list.querySelectorAll('.chk-row').forEach((row) => {
    if (row.classList.contains('locked')) return;
    row.onclick = () => toggleState(row.getAttribute('data-state'));
  });
}
function toggleState(st) {
  const i = saDraft.states.indexOf(st);
  if (i >= 0) {
    if (st === store.biz.registeredState) return;
    saDraft.states.splice(i, 1);
    delete saDraft.districts[st];
  } else {
    saDraft.states.push(st);
    saDraft.districts[st] = saDraft.districts[st] || [];
  }
  renderStateList();
}

let saActiveState = 'Kerala';
function renderStateSeg() {
  const seg = el('stateSeg');
  seg.innerHTML = saDraft.states
    .map(
      (st) =>
        '<button type="button" class="' +
        (st === saActiveState ? 'on' : '') +
        '" data-st="' +
        esc(st) +
        '">' +
        esc(st) +
        '</button>'
    )
    .join('');
  seg.querySelectorAll('button').forEach((b) => {
    b.onclick = () => {
      saActiveState = b.getAttribute('data-st');
      renderStateSeg();
      renderDistList();
    };
  });
  if (saDraft.states.indexOf(saActiveState) < 0 && saDraft.states[0]) saActiveState = saDraft.states[0];
  el('distStateTitle').textContent = saActiveState;
}

function renderDistList() {
  el('distStateTitle').textContent = saActiveState;
  const q = (el('distSearch').value || '').trim().toLowerCase();
  const all = INDIAN_STATES[saActiveState] || [];
  const picked = saDraft.districts[saActiveState] || [];
  const list = el('distList');
  list.innerHTML = all
    .filter((d) => !q || d.toLowerCase().includes(q))
    .map((d) => {
      const on = picked.indexOf(d) >= 0;
      const locked = saActiveState === store.biz.registeredState && d === store.biz.registeredDistrict;
      return (
        '<div class="chk-row' +
        (on ? ' on' : '') +
        (locked ? ' locked' : '') +
        '" data-dist="' +
        esc(d) +
        '">' +
        '<span class="chk-box">' +
        (on ? photoIcon('check') : locked ? '🔒' : '') +
        '</span><span>' +
        esc(d) +
        '</span></div>'
      );
    })
    .join('');
  list.querySelectorAll('.chk-row').forEach((row) => {
    if (row.classList.contains('locked')) return;
    row.onclick = () => toggleDist(saActiveState, row.getAttribute('data-dist'));
  });
}
function toggleDist(st, dist) {
  if (!saDraft.districts[st]) saDraft.districts[st] = [];
  const arr = saDraft.districts[st];
  const i = arr.indexOf(dist);
  if (i >= 0) {
    if (st === store.biz.registeredState && dist === store.biz.registeredDistrict) return;
    arr.splice(i, 1);
  } else arr.push(dist);
  renderDistList();
}

function renderSaReview() {
  const wrap = el('saReviewCards');
  wrap.innerHTML = saDraft.states
    .map((st) => {
      const ds = saDraft.districts[st] || [];
      return (
        '<div class="review-card"><div class="review-card-hd"><b>' +
        esc(st) +
        '</b><button type="button" class="link" style="border:0;background:none;font:inherit;color:var(--blue);cursor:pointer" data-edit-st="' +
        esc(st) +
        '">' +
        photoIcon('edit') +
        ' Edit</button></div><div class="chips">' +
        ds.map((d) => '<span class="chip-district">' + esc(d) + '</span>').join('') +
        '</div></div>'
      );
    })
    .join('');
  wrap.querySelectorAll('[data-edit-st]').forEach((btn) => {
    btn.onclick = () => {
      saActiveState = btn.getAttribute('data-edit-st');
      show('saDistricts');
      renderStateSeg();
      renderDistList();
    };
  });
}

function renderPkgFilters() {
  const filters = [{ id: 'all', label: 'All' }].concat(PKG_LEVELS.map((l) => ({ id: l.toLowerCase(), label: l })));
  const row = el('pkgFilters');
  row.innerHTML = filters
    .map(
      (f) =>
        '<button type="button" class="fchip' +
        (store.pkgFilter === f.id ? ' on' : '') +
        '" data-f="' +
        f.id +
        '">' +
        f.label +
        '</button>'
    )
    .join('');
  row.querySelectorAll('.fchip').forEach((b) => {
    b.onclick = () => {
      store.pkgFilter = b.getAttribute('data-f');
      saveStore();
      renderPkgList();
      renderPkgFilters();
    };
  });
}

function filteredPackages() {
  if (store.pkgFilter === 'all') return store.packages;
  return store.packages.filter((p) => levelClass(p.level) === store.pkgFilter);
}

function deletePackage(id) {
  const p = findPackage(id);
  if (!p) return;
  if (!confirm('Delete package "' + p.name + '"? This cannot be undone.')) return;
  store.packages = store.packages.filter(function (x) {
    return x.id !== id;
  });
  saveStore();
  renderSvcPkg();
  toast('Package deleted');
}

function deleteService(id) {
  const s = findService(id);
  if (!s) return;
  if (!confirm('Delete service "' + s.name + '"? This cannot be undone.')) return;
  store.services = store.services.filter(function (x) {
    return x.id !== id;
  });
  saveStore();
  renderSvcPkg();
  toast('Service deleted');
}

function bindHubCatalogActions(root) {
  if (!root) return;
  root.querySelectorAll('[data-hub-edit-pkg]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      startWizard('package', btn.getAttribute('data-hub-edit-pkg'));
    };
  });
  root.querySelectorAll('[data-hub-del-pkg]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      deletePackage(btn.getAttribute('data-hub-del-pkg'));
    };
  });
  root.querySelectorAll('[data-hub-edit-svc]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      startWizard('service', btn.getAttribute('data-hub-edit-svc'));
    };
  });
  root.querySelectorAll('[data-hub-del-svc]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      deleteService(btn.getAttribute('data-hub-del-svc'));
    };
  });
  root.querySelectorAll('.pkg-card-tap').forEach(function (card) {
    card.onclick = function (e) {
      if (e.target.closest('.hub-act')) return;
      startWizard('package', card.getAttribute('data-pkg-id'));
    };
  });
  root.querySelectorAll('.svc-row-wrap').forEach(function (row) {
    row.onclick = function (e) {
      if (e.target.closest('.hub-act')) return;
      startWizard('service', row.getAttribute('data-svc-id'));
    };
  });
}

function renderPkgList() {
  const list = el('pkgList');
  const pkgs = filteredPackages();
  if (!pkgs.length) {
    list.innerHTML =
      '<div class="hub-empty">' +
      '<div class="hub-empty-ico">' +
      photoIcon('pkg') +
      '</div><b>No packages yet</b><p>Build your first wedding or event package with deliverables, pricing, and policies in a guided flow.</p></div>';
    return;
  }
  list.innerHTML = pkgs
    .map((p) => {
      const lv = levelClass(p.level);
      const disc =
        p.discountPct > 0 && p.listPrice > p.price
          ? '<span class="was" style="text-decoration:line-through;color:#9CA3AF;font-size:12px;font-weight:700;margin-left:6px">' +
            inr(p.listPrice) +
            '</span>'
          : '';
      return (
        '<div class="pkg-card pkg-card-tap" data-pkg-id="' +
        esc(p.id) +
        '"><div class="pkg-thumb lv-' +
        lv +
        '">' +
        photoIcon('pkg') +
        '</div><div class="pkg-bd"><div class="pkg-top-row"><span class="pkg-level ' +
        lv +
        '">' +
        esc(p.level) +
        '</span></div><b>' +
        esc(p.name) +
        '</b><div class="pkg-price">' +
        inr(p.price) +
        disc +
        '</div><div class="pkg-sub">' +
        esc(p.coverage || 'Tap card to edit coverage & deliverables') +
        '</div><div class="pkg-foot"><span class="status ' +
        (p.status === 'published' ? 'pub' : 'draft') +
        '">' +
        (p.status === 'published' ? '● Live' : '○ Draft') +
        '</span></div><div class="hub-card-actions">' +
        '<button type="button" class="hub-act hub-act-edit" data-hub-edit-pkg="' +
        esc(p.id) +
        '">' +
        photoIcon('edit') +
        ' Edit</button>' +
        '<button type="button" class="hub-act hub-act-del" data-hub-del-pkg="' +
        esc(p.id) +
        '">Delete</button></div></div></div>'
      );
    })
    .join('');
  bindHubCatalogActions(list);
}

function renderSvcList() {
  el('svcCount').textContent = String(store.services.length);
  el('svcSecIco').innerHTML = photoIcon('cam');
  const tabPkgIco = el('tabPkgIco');
  const tabSvcIco = el('tabSvcIco');
  if (tabPkgIco) tabPkgIco.innerHTML = photoIcon('pkg');
  if (tabSvcIco) tabSvcIco.innerHTML = photoIcon('cam');
  const list = el('svcList');
  if (!store.services.length) {
    list.innerHTML =
      '<div class="hub-empty" style="margin:8px 16px 16px">' +
      '<div class="hub-empty-ico">' +
      photoIcon('cam') +
      '</div><b>No services yet</b><p>Add standalone offerings like portraits, product shoots, or funeral coverage.</p></div>';
    return;
  }
  list.innerHTML = store.services
    .map(
      (s) =>
        '<div class="svc-row-wrap" data-svc-id="' +
        esc(s.id) +
        '"><div class="svc-row"><div class="svc-thumb">' +
        photoIcon('cam') +
        '</div><div class="svc-bd"><b>' +
        esc(s.name) +
        '</b><div class="svc-meta"><span class="svc-price-tag">' +
        inr(s.price) +
        '</span><span class="status ' +
        (s.status === 'published' ? 'pub' : 'draft') +
        '" style="margin:0;padding:4px 8px">' +
        (s.status === 'published' ? 'Live' : 'Draft') +
        '</span></div></div></div><div class="hub-card-actions">' +
        '<button type="button" class="hub-act hub-act-edit" data-hub-edit-svc="' +
        esc(s.id) +
        '">' +
        photoIcon('edit') +
        ' Edit</button>' +
        '<button type="button" class="hub-act hub-act-del" data-hub-del-svc="' +
        esc(s.id) +
        '">Delete</button></div></div>'
    )
    .join('');
  bindHubCatalogActions(list);
}

function applyHubTab() {
  const isPkg = store.hubTab === 'packages';
  const hub = el('svcPkg');
  if (hub) {
    hub.classList.toggle('hub-mode-packages', isPkg);
    hub.classList.toggle('hub-mode-services', !isPkg);
  }
  el('tabPackages').classList.toggle('on', isPkg);
  el('tabServices').classList.toggle('on', !isPkg);
  el('hubIntro').textContent = isPkg
    ? 'Create full-event packages with coverage, deliverables, and payment stages.'
    : 'Standalone services customers book without a full package.';
  const stat = el('hubStat');
  if (stat) {
    const pubPkg = store.packages.filter((p) => p.status === 'published').length;
    const pubSvc = store.services.filter((s) => s.status === 'published').length;
    stat.innerHTML = isPkg
      ? '<div class="hub-stat-chip pink" style="flex:1;min-width:100%"><b>' +
        store.packages.length +
        '</b><span>Packages · ' +
        pubPkg +
        ' live</span></div>'
      : '<div class="hub-stat-chip blue" style="flex:1;min-width:100%"><b>' +
        store.services.length +
        '</b><span>Services · ' +
        pubSvc +
        ' live</span></div>';
  }
}

function renderSvcPkg() {
  renderPkgFilters();
  renderPkgList();
  renderSvcList();
  applyHubTab();
}

function findPackage(id) {
  return store.packages.find(function (p) {
    return p.id === id;
  });
}
function findService(id) {
  return store.services.find(function (s) {
    return s.id === id;
  });
}

function startWizard(mode, editId) {
  wiz.mode = mode;
  wiz.step = 0;
  wiz.editId = editId || null;
  wiz.backTo = 'svcPkg';
  if (mode === 'package') {
    const src = editId ? findPackage(editId) : null;
    wiz.draft = src ? recordToPkgDraft(src) : newPkgDraft();
  } else {
    const src = editId ? findService(editId) : null;
    wiz.draft = src ? recordToSvcDraft(src) : newSvcDraft();
  }
  const wSec = el('wizard');
  if (wSec) {
    wSec.classList.toggle('wiz-create', mode === 'package');
    wSec.classList.toggle('wiz-svc-create', mode === 'service');
  }
  const pkgBrand = el('wizPkgBrand');
  if (pkgBrand) {
    const sub = pkgBrand.querySelector('span');
    if (sub) sub.textContent = wiz.editId && mode === 'package' ? 'Edit Package' : 'Create Package';
  }
  const svcBrand = el('wizSvcBrand');
  if (svcBrand) {
    const sub = svcBrand.querySelector('span');
    if (sub) sub.textContent = wiz.editId && mode === 'service' ? 'Edit Service' : 'Create Service';
  }
  el('wizTitle').textContent = mode === 'package' ? 'Create Package' : 'Add Service';
  show('wizard');
  renderWizard();
}

function syncPkgPrice(d) {
  const base = Math.max(0, +d.listPrice || 0);
  const pct =
    d.discountYes === 'yes' ? Math.min(100, Math.max(0, +d.discountPct || 0)) : 0;
  d.price = pct > 0 ? Math.round(base * (1 - pct / 100)) : base;
}
function syncSvcPrice(d) {
  syncPkgPrice(d);
}

function wizSteps() {
  return wiz.mode === 'package' ? PKG_STEPS : SVC_STEPS;
}
function wizTotal() {
  return wizSteps().length;
}

function renderStepper() {
  const steps = wizSteps();
  const pkg = wiz.mode === 'package';
  const svc = wiz.mode === 'service';
  el('stepper').innerHTML = steps
    .map((_, i) => {
      let cls = 'step-dot';
      if (i === wiz.step) cls += ' on';
      else if (!pkg && !svc && i < wiz.step) cls += ' done';
      const label = pkg || svc || i >= wiz.step ? i + 1 : '✓';
      return '<div class="' + cls + '">' + label + '</div>';
    })
    .join('');
  const meta = steps[wiz.step];
  el('wizStepTitle').textContent = meta.title;
  const sub = el('wizStepSub');
  if (sub) sub.textContent = pkg ? '' : meta.sub;
}

function renderWizardBody() {
  const body = el('wizBody');
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    body.innerHTML = renderPkgStep(wiz.step, d);
  } else {
    body.innerHTML = renderSvcStep(wiz.step, d);
  }
  bindWizardFields();
}

function readWizardFields() {
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    readPkgWizardFields(d);
  } else {
    readSvcWizardFields(d);
  }
}

function bindWizardFields() {
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    bindPkgWizard(d);
  } else {
    bindSvcWizard(d);
  }
}

function validateStep() {
  readWizardFields();
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    if (wiz.step === 0 && (!d.name || !d.listPrice)) {
      toast('Enter package name and price.');
      return false;
    }
    if (wiz.step === 1 && !d.functions.length) {
      toast('Select at least one function.');
      return false;
    }
    if (wiz.step === 2 && needsCeremonyStep(d.functions) && !(d.ceremonyTypes || []).length) {
      toast('Select at least one ceremony type (or go back and change functions).');
      return false;
    }
    if (wiz.step === 4 && !selectedDeliverableKeys(d).length) {
      toast('Select at least one deliverable (photo, video, album, or digital).');
      return false;
    }
    if (wiz.step === 6 && !pkgDeliveryKeys(d).length) {
      toast('Add deliverables before setting delivery timelines.');
      return false;
    }
    if (wiz.step === 7) {
      const total = payStagesTotalPct(d);
      if (total !== 100) {
        toast('Payment stages must total 100% (currently ' + total + '%).');
        return false;
      }
      ensurePkgPolicyRules(d);
      if (!d.cancelRules || !d.cancelRules.length) {
        toast('Add at least one cancellation policy tier.');
        return false;
      }
      if (!d.rescheduleRules || !d.rescheduleRules.length) {
        toast('Add at least one rescheduling policy tier.');
        return false;
      }
    }
  } else {
    if (wiz.step === 0 && !d.category) {
      toast('Pick a service category.');
      return false;
    }
    if (wiz.step === 1 && (!d.name || !d.blurb)) {
      toast('Enter service name and description.');
      return false;
    }
    if (wiz.step === 2 && !d.listPrice) {
      toast('Enter service price.');
      return false;
    }
    if (wiz.step === 4 && !svcSelectedDeliverableKeys(d).length) {
      toast("Select at least one included item (photo, video, album, or digital).");
      return false;
    }
    if (wiz.step === 6 && !svcDeliveryKeys(d).length) {
      toast("Add included items before setting delivery timelines.");
      return false;
    }
  }
  return true;
}

function finishWizard(publish) {
  readWizardFields();
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    if (!d.name) {
      toast('Package name required.');
      return;
    }
    const payload = JSON.parse(JSON.stringify(d));
    payload.id = wiz.editId || uid('pkg');
    payload.status = publish ? 'published' : 'draft';
    if (wiz.editId) {
      const i = store.packages.findIndex(function (p) {
        return p.id === wiz.editId;
      });
      if (i >= 0) store.packages[i] = payload;
      else store.packages.unshift(payload);
      toast(publish ? 'Package updated & published' : 'Package saved');
    } else {
      store.packages.unshift(payload);
      toast(publish ? 'Package published' : 'Package saved as draft');
    }
  } else {
    if (!d.name || !d.category) {
      toast('Complete service basics.');
      return;
    }
    const payload = JSON.parse(JSON.stringify(d));
    payload.id = wiz.editId || uid('svc');
    if (publish) payload.status = 'published';
    else payload.status = 'draft';
    if (wiz.editId) {
      const i = store.services.findIndex(function (s) {
        return s.id === wiz.editId;
      });
      if (i >= 0) store.services[i] = payload;
      else store.services.unshift(payload);
      toast(publish ? 'Service updated & published' : 'Service saved');
    } else {
      store.services.unshift(payload);
      toast(publish ? 'Service published' : 'Service saved as draft');
    }
  }
  wiz.editId = null;
  store.hubTab = wiz.mode === 'service' ? 'services' : 'packages';
  saveStore();
  show('svcPkg');
  renderSvcPkg();
}

function renderWizard() {
  renderStepper();
  renderWizardBody();
  const total = wizTotal();
  const stepNum = wiz.step + 1;
  const pct = Math.round((stepNum / total) * 100);
  const chip = el('wizStepChip');
  const frac = el('wizFrac');
  const bar = el('wizProgBar');
  if (chip) chip.textContent = stepNum + '/' + total;
  if (frac) frac.textContent = stepNum + '/' + total;
  if (bar) bar.style.width = pct + '%';
  const last = wiz.step >= wizTotal() - 1;
  const pkgReview = wiz.mode === 'package' && wiz.step === wizTotal() - 1;
  const svcReview = wiz.mode === 'service' && wiz.step === wizTotal() - 1;
  el('wizPrev').style.visibility = wiz.step === 0 ? 'hidden' : 'visible';
  el('wizNext').hidden = pkgReview || svcReview;
  if (wiz.mode === 'service' && wiz.step === wizTotal() - 2) {
    el('wizNext').textContent = 'Review →';
  } else if (last && !pkgReview && !svcReview) {
    el('wizNext').textContent = 'Publish →';
  } else {
    el('wizNext').textContent = 'Next →';
  }
  el('wizNext').className =
    last && !pkgReview && !svcReview ? 'btn btn-green' : 'btn btn-blue';
  const draftBtn = el('wizDraft');
  if (draftBtn) {
    draftBtn.hidden = true;
  }
}

function wizNext() {
  if (!validateStep()) return;
  if (wiz.mode === 'package' && wiz.step === wizTotal() - 1) return;
  if (wiz.mode === 'service' && wiz.step === wizTotal() - 1) return;
  if (wiz.step >= wizTotal() - 1) {
    finishWizard(true);
    return;
  }
  wiz.step += 1;
  if (wiz.mode === 'package' && wiz.step === 2 && !needsCeremonyStep(wiz.draft.functions)) {
    wiz.step = 3;
  }
  renderWizard();
}

function wizPrev() {
  if (wiz.step <= 0) {
    show(wiz.backTo);
    return;
  }
  readWizardFields();
  wiz.step -= 1;
  if (wiz.mode === 'package' && wiz.step === 2 && !needsCeremonyStep(wiz.draft.functions)) {
    wiz.step = 1;
  }
  renderWizard();
}

function bindGlobal() {
  document.querySelectorAll('.back[data-to]').forEach((btn) => {
    btn.onclick = () => show(btn.getAttribute('data-to'));
  });
  document.querySelectorAll('.stub .btn[data-to], .btn[data-to]').forEach((btn) => {
    if (btn.id) return;
    const to = btn.getAttribute('data-to');
    if (to) btn.onclick = () => show(to);
  });
  el('lmbHomeBtn').onclick = () => show('lmbDashboard');
  const backLmb = el('backToLmb');
  if (backLmb) backLmb.onclick = () => show('lmbDashboard');
  const profBtn = el('photoBizProfileBtn');
  if (profBtn) {
    profBtn.onclick = function () {
      renderPhotoBizProfile();
      show('photoBizProfile');
    };
  }
  el('manageAreasLink').onclick = (e) => {
    e.preventDefault();
    startSaDraft();
    el('saHeroIco').innerHTML = photoIcon('pin');
    el('saSearchIco').innerHTML = photoIcon('search');
    renderStateList();
    show('saStates');
  };
  el('saSkip').onclick = () => show('photoDash');
  el('saStatesContinue').onclick = () => {
    if (!saDraft.states.length) {
      toast('Select at least one state.');
      return;
    }
    saActiveState = saDraft.states[0];
    show('saDistricts');
    renderStateSeg();
    renderDistList();
  };
  el('stateSearch').oninput = () => renderStateList();
  el('distSearch').oninput = () => renderDistList();
  el('saDistContinue').onclick = () => {
    show('saReview');
    el('saRevIco').innerHTML = photoIcon('pin');
    renderSaReview();
  };
  el('saSave').onclick = () => {
    store.serviceAreas = JSON.parse(JSON.stringify(saDraft));
    ensureRegisteredDistrict();
    saveStore();
    renderPhotoDash();
    show('photoDash');
    toast('Service areas saved');
  };
  el('tabPackages').onclick = () => {
    store.hubTab = 'packages';
    saveStore();
    applyHubTab();
  };
  el('tabServices').onclick = () => {
    store.hubTab = 'services';
    saveStore();
    applyHubTab();
  };
  const svcToggle = el('svcSecToggle');
  if (svcToggle) {
    svcToggle.onclick = () => {
      const sec = svcToggle.closest('.svc-sec');
      if (sec && el('svcPkg').classList.contains('hub-mode-packages')) {
        sec.classList.toggle('collapsed');
      }
    };
  }
  el('addPackageBtn').onclick = () => startWizard('package');
  el('addServiceBtn').onclick = () => startWizard('service');
  const addOp = el('photoAddOperatorBtn');
  if (addOp) {
    addOp.onclick = function () {
      const name = prompt('Operator full name');
      if (!name || !name.trim()) return;
      const phone = prompt('Mobile number', '+91 ');
      if (!phone || !phone.trim()) return;
      ensureOperators();
      store.operators.push({
        id: uid('op'),
        name: name.trim(),
        phone: phone.trim(),
        role: 'staff',
      });
      saveStore();
      renderPhotoOperators();
      toast('Operator added');
    };
  }
  el('wizBack').onclick = () => wizPrev();
  el('wizPrev').onclick = () => wizPrev();
  el('wizNext').onclick = () => wizNext();
  const wizDraft = el('wizDraft');
  if (wizDraft) wizDraft.onclick = () => finishWizard(false);
}

function boot() {
  try {
    if (!el('quickGrid')) {
      throw new Error('Missing dashboard — open GIXBEE-PHOTO-OWNER-FINALFLOW.html (full file).');
    }
    loadStore();
    ensureRegisteredDistrict();
    saveStore();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Working demo ' + PHOTO_OWNER_BUILD + ' — List My Business → Archana Photography → Manage';
    }
    renderLmb();
    renderPhotoDash();
    renderSvcPkg();
    bindGlobal();
    const err = el('bootError');
    if (err) err.hidden = true;
    show('lmbDashboard');
  } catch (err) {
    console.error(err);
    showBootError(err.message || String(err));
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
