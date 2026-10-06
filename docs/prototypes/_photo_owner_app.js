const PHOTO_OWNER_BUILD = '2026-10-06-photo-owner-mobile-v1-fix1';
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
  'Wedding & Reception': 'Full wedding day and reception coverage',
  Reception: 'Reception-only coverage',
  'Wedding Eve': 'Pre-wedding / wedding eve events',
  Engagement: 'Engagement ceremony coverage',
  Baptism: 'Baptism ceremony',
  'First Communion': 'First communion ceremony',
  Birthday: 'Birthday celebrations',
  Anniversary: 'Anniversary events',
  'Baby Shower': 'Baby shower events',
  'Naming Ceremony': 'Naming ceremony',
  Housewarming: 'Housewarming events',
  'Corporate Event': 'Corporate functions and events',
  'Funeral / Memorial': 'Memorial and funeral services',
  Other: 'Custom event type',
};
const CEREMONY_TYPES = ['Christian', 'Hindu', 'Muslim', 'Sikh', 'Jain', 'Buddhist', 'Other'];
const SVC_CATEGORIES = [
  { id: 'event', label: 'Event Photography' },
  { id: 'portrait', label: 'Portrait Photography' },
  { id: 'baby', label: 'Baby & Kids' },
  { id: 'maternity', label: 'Maternity' },
  { id: 'newborn', label: 'Newborn' },
  { id: 'couple', label: 'Couple' },
  { id: 'funeral', label: 'Funeral / Memorial' },
  { id: 'product', label: 'Product' },
  { id: 'corporate', label: 'Corporate' },
  { id: 'fashion', label: 'Fashion & Portfolio' },
  { id: 'realestate', label: 'Real Estate' },
  { id: 'food', label: 'Food' },
  { id: 'commercial', label: 'Commercial' },
  { id: 'drone', label: 'Drone / Aerial' },
  { id: 'reel', label: 'Reel & Short Video' },
  { id: 'production', label: 'Photo & Video Production' },
];

const PKG_STEPS = [
  { title: 'Package basics', sub: 'Basic information about the package.' },
  { title: 'Select functions', sub: 'Select functions covered in this package.' },
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
  { title: 'Select service category', sub: 'Visual grid — pick the photography type.' },
  { title: 'Service basics', sub: 'Name, category, short description.' },
  { title: 'Service pricing', sub: 'Fixed price or other V1 types; optional discount.' },
  { title: 'Duration & coverage', sub: 'Optional hours and team.' },
  { title: "What's included", sub: 'Deliverables included in this service.' },
  { title: 'Optional extras', sub: 'Paid add-ons with price basis.' },
  { title: 'Delivery', sub: 'Timeline per deliverable.' },
  { title: 'Policies & review', sub: 'Policies, requirements, publish.' },
];

function defaultStore() {
  return {
    biz: {
      name: 'Archana Photography',
      loc: 'Sakthan Nagar, Thrissur',
      registeredState: 'Kerala',
      registeredDistrict: 'Thrissur',
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
  };
}

let store = defaultStore();
let saDraft = null;
let wiz = { mode: 'package', step: 0, draft: null, backTo: 'svcPkg' };

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
    btn.onclick = () => show(btn.getAttribute('data-go'));
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

function renderPkgList() {
  const list = el('pkgList');
  const pkgs = filteredPackages();
  if (!pkgs.length) {
    list.innerHTML = '<p class="sub" style="padding:8px 16px 16px">No packages yet. Tap <b>+ Add Package</b> to create one.</p>';
    return;
  }
  list.innerHTML = pkgs
    .map((p) => {
      const disc =
        p.discountPct > 0 && p.listPrice > p.price
          ? '<span class="was" style="text-decoration:line-through;color:#9CA3AF;font-size:11px;margin-left:6px">' +
            inr(p.listPrice) +
            '</span>'
          : '';
      return (
        '<button type="button" class="pkg-card" data-pkg="' +
        esc(p.id) +
        '"><div class="pkg-thumb"></div><div class="pkg-bd">' +
        '<span class="pkg-level ' +
        levelClass(p.level) +
        '">' +
        esc(p.level) +
        '</span>' +
        '<span class="pkg-menu">' +
        photoIcon('menu') +
        '</span><b>' +
        esc(p.name) +
        '</b><div class="pkg-price">' +
        inr(p.price) +
        disc +
        '</div><div class="pkg-sub">' +
        esc(p.coverage || '') +
        '</div><span class="status ' +
        (p.status === 'published' ? 'pub' : 'draft') +
        '">' +
        (p.status === 'published' ? '● Published' : '○ Draft') +
        '</span></div></button>'
      );
    })
    .join('');
  list.querySelectorAll('.pkg-card').forEach((btn) => {
    btn.onclick = () => toast('Package detail editor comes in a later sprint.');
  });
}

function renderSvcList() {
  el('svcCount').textContent = String(store.services.length);
  el('svcSecIco').innerHTML = photoIcon('cam');
  const list = el('svcList');
  if (!store.services.length) {
    list.innerHTML = '<p class="sub" style="padding:8px 14px 14px">No services yet.</p>';
    return;
  }
  list.innerHTML = store.services
    .map(
      (s) =>
        '<button type="button" class="svc-row" data-svc="' +
        esc(s.id) +
        '"><div class="svc-thumb"></div><div style="flex:1;min-width:0"><b style="font-size:13px;color:var(--navy)">' +
        esc(s.name) +
        '</b><div class="sub">' +
        inr(s.price) +
        ' · <span class="status ' +
        (s.status === 'published' ? 'pub' : 'draft') +
        '" style="margin:0">' +
        (s.status === 'published' ? 'Published' : 'Draft') +
        '</span></div></div><span style="color:var(--mut)">›</span></button>'
    )
    .join('');
}

function applyHubTab() {
  const isPkg = store.hubTab === 'packages';
  el('tabPackages').classList.toggle('on', isPkg);
  el('tabServices').classList.toggle('on', !isPkg);
  el('hubIntro').textContent = isPkg
    ? 'Create packages for full events (wedding, reception, etc.). Filter cards by level.'
    : 'Individual services customers book separately (funeral, product, portrait, etc.).';
  const stat = el('hubStat');
  if (stat) {
    stat.textContent =
      'Packages (' + store.packages.length + ') · Services (' + store.services.length + ')';
  }
  el('pkgFilters').style.display = isPkg ? '' : 'none';
  el('addPackageBtn').closest('.cta').style.display = isPkg ? '' : 'none';
  el('pkgList').style.display = isPkg ? '' : 'none';
  const sec = el('svcSecToggle').closest('.svc-sec');
  if (sec) sec.style.display = isPkg ? '' : 'block';
  if (!isPkg) {
    el('pkgList').style.display = 'none';
    el('addServiceBtn').closest('.cta').style.display = '';
  }
}

function renderSvcPkg() {
  renderPkgFilters();
  renderPkgList();
  renderSvcList();
  applyHubTab();
}

function newSvcDraft() {
  return {
    category: '',
    name: '',
    blurb: '',
    pricingType: 'fixed',
    listPrice: 25000,
    discountYes: 'no',
    discountPct: 0,
    price: 25000,
    duration: 'Up to 4 hours',
    coverage: '1 candid photographer',
    included: '100 edited photos · Online gallery',
    extras: 'Extra hour ₹5,000 · Drone ₹8,000',
    delivery: 'Edited photos 5 days · Reel 3 days',
    policies: 'Cancellation · Data retention 1 year',
    requirements: 'Customer provides venue access',
    status: 'draft',
  };
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

function startWizard(mode) {
  wiz.mode = mode;
  wiz.step = 0;
  wiz.backTo = 'svcPkg';
  wiz.draft = mode === 'package' ? newPkgDraft() : newSvcDraft();
  el('wizTitle').textContent = mode === 'package' ? 'Create Package' : 'Add Service';
  const wSec = el('wizard');
  if (wSec) wSec.classList.toggle('wiz-create', mode === 'package');
  show('wizard');
  renderWizard();
}

function wizSteps() {
  return wiz.mode === 'package' ? PKG_STEPS : SVC_STEPS;
}
function wizTotal() {
  return wizSteps().length;
}

function renderStepper() {
  const steps = wizSteps();
  el('stepper').innerHTML = steps
    .map((_, i) => {
      let cls = 'step-dot';
      if (i === wiz.step) cls += ' on';
      else if (i < wiz.step) cls += ' done';
      return '<div class="' + cls + '">' + (i < wiz.step ? '✓' : i + 1) + '</div>';
    })
    .join('');
  const meta = steps[wiz.step];
  el('wizStepTitle').textContent = meta.title;
  el('wizStepSub').textContent = meta.sub;
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

function renderSvcStep(step, d) {
  switch (step) {
    case 0:
      return (
        '<div class="sa-search" style="margin:0 0 12px"><span>' +
        photoIcon('search') +
        '</span><input type="search" id="catSearch" placeholder="Search categories"></div>' +
        '<div class="cat-grid" id="f_cats">' +
        SVC_CATEGORIES.map(
          (c) =>
            '<button type="button" class="cat-card' +
            (d.category === c.id ? ' on' : '') +
            '" data-cat="' +
            c.id +
            '" data-lbl="' +
            esc(c.label) +
            '"><span class="tick">✓</span><div class="ph"></div>' +
            c.label +
            '</button>'
        ).join('') +
        '</div>'
      );
    case 1:
      return (
        '<div class="fld"><label>Service name *</label><input id="f_svcName" value="' +
        esc(d.name) +
        '"></div>' +
        '<div class="fld"><label>Category</label><input readonly value="' +
        esc(SVC_CATEGORIES.find((c) => c.id === d.category)?.label || '—') +
        '"></div>' +
        '<div class="fld"><label>Short description *</label><textarea id="f_blurb">' +
        esc(d.blurb) +
        '</textarea></div>'
      );
    case 2:
      syncSvcPrice(d);
      return (
        '<div class="fld"><label>Pricing type</label><select id="f_priceType"><option value="fixed">Fixed price</option><option value="from">Starting from</option><option value="hour">Per hour</option></select></div>' +
        '<div class="fld"><label>Price (₹)</label><input type="number" id="f_listPrice" value="' +
        d.listPrice +
        '"></div>' +
        '<div class="fld"><label>Discount % (optional)</label><input type="number" id="f_discountPct" value="' +
        d.discountPct +
        '"></div>' +
        '<div class="preview-green"><b>' +
        inr(d.price) +
        '</b> — includes deliverables listed in this service.</div>'
      );
    case 3:
      return (
        '<label class="manage-check-row"><input type="checkbox" id="f_durOn" checked> Enable duration &amp; coverage</label>' +
        '<div class="fld"><label>Duration</label><input id="f_duration" value="' +
        esc(d.duration) +
        '"></div>' +
        '<div class="fld"><label>Coverage / team</label><input id="f_cov" value="' +
        esc(d.coverage) +
        '"></div>'
      );
    case 4:
      return '<div class="fld"><label>What\'s included</label><textarea id="f_included">' + esc(d.included) + '</textarea></div>';
    case 5:
      return '<div class="fld"><label>Optional extras</label><textarea id="f_extras">' + esc(d.extras) + '</textarea></div>';
    case 6:
      return '<div class="fld"><label>Delivery</label><textarea id="f_delivery">' + esc(d.delivery) + '</textarea></div>';
    case 7:
      syncSvcPrice(d);
      return (
        '<div class="fld"><label>Policies</label><textarea id="f_policies">' +
        esc(d.policies) +
        '</textarea></div>' +
        '<div class="fld"><label>Customer requirements</label><textarea id="f_requirements">' +
        esc(d.requirements) +
        '</textarea></div>' +
        '<div class="review-card"><b>' +
        esc(d.name || 'Untitled service') +
        '</b><p class="sub">' +
        inr(d.price) +
        ' · ' +
        esc(SVC_CATEGORIES.find((c) => c.id === d.category)?.label || '') +
        '</p></div>'
      );
    default:
      return '';
  }
}

function readWizardFields() {
  const d = wiz.draft;
  const g = (id) => el(id);
  if (wiz.mode === 'package') {
    readPkgWizardFields(d);
  } else {
    if (g('f_svcName')) d.name = g('f_svcName').value.trim();
    if (g('f_blurb')) d.blurb = g('f_blurb').value.trim();
    if (g('f_priceType')) d.pricingType = g('f_priceType').value;
    if (g('f_listPrice')) d.listPrice = +g('f_listPrice').value || 0;
    if (g('f_discountPct')) d.discountPct = +g('f_discountPct').value || 0;
    if (g('f_duration')) d.duration = g('f_duration').value.trim();
    if (g('f_cov')) d.coverage = g('f_cov').value.trim();
    if (g('f_included')) d.included = g('f_included').value.trim();
    if (g('f_extras')) d.extras = g('f_extras').value.trim();
    if (g('f_delivery')) d.delivery = g('f_delivery').value.trim();
    if (g('f_policies')) d.policies = g('f_policies').value.trim();
    if (g('f_requirements')) d.requirements = g('f_requirements').value.trim();
    syncSvcPrice(d);
  }
}

function bindWizardFields() {
  const d = wiz.draft;
  if (wiz.mode === 'package') {
    bindPkgWizard(d);
    return;
  }
  document.querySelectorAll('#f_cats .cat-card').forEach((b) => {
    b.onclick = () => {
      d.category = b.getAttribute('data-cat');
      renderWizardBody();
    };
  });
  document.querySelectorAll('#f_ceremonyBtns button').forEach((b) => {
    b.onclick = () => {
      d.ceremonyType = b.getAttribute('data-cer');
      renderWizardBody();
    };
  });
  const catSearch = el('catSearch');
  if (catSearch) {
    catSearch.oninput = () => {
      const q = catSearch.value.trim().toLowerCase();
      document.querySelectorAll('#f_cats .cat-card').forEach((card) => {
        const lbl = (card.getAttribute('data-lbl') || card.textContent || '').toLowerCase();
        card.style.display = !q || lbl.includes(q) ? '' : 'none';
      });
    };
  }
  ['f_listPrice', 'f_discountPct', 'f_discYes'].forEach((id) => {
    const node = el(id);
    if (node) node.oninput = () => {
      readWizardFields();
      renderWizardBody();
    };
  });
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
  } else {
    if (wiz.step === 0 && !d.category) {
      toast('Pick a service category.');
      return false;
    }
    if (wiz.step === 1 && !d.name) {
      toast('Enter a service name.');
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
    const rec = Object.assign({ id: uid('pkg') }, JSON.parse(JSON.stringify(d)), {
      status: publish ? 'published' : 'draft',
    });
    store.packages.unshift(rec);
    toast(publish ? 'Package published' : 'Package saved as draft');
  } else {
    if (!d.name || !d.category) {
      toast('Complete service basics.');
      return;
    }
    const rec = Object.assign({ id: uid('svc') }, d, { status: publish ? 'published' : 'draft' });
    store.services.unshift(rec);
    toast(publish ? 'Service published' : 'Service saved');
  }
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
  el('wizPrev').style.visibility = wiz.step === 0 ? 'hidden' : 'visible';
  el('wizNext').hidden = pkgReview;
  el('wizNext').textContent = last && !pkgReview ? 'Publish →' : 'Next →';
  el('wizNext').className = last && !pkgReview ? 'btn btn-green' : 'btn btn-blue';
  const draftBtn = el('wizDraft');
  if (draftBtn) {
    draftBtn.hidden =
      wiz.mode === 'package' ? true : pkgReview || !last;
  }
}

function wizNext() {
  if (!validateStep()) return;
  if (wiz.mode === 'package' && wiz.step === wizTotal() - 1) return;
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
  el('addPackageBtn').onclick = () => startWizard('package');
  el('addServiceBtn').onclick = () => startWizard('service');
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
