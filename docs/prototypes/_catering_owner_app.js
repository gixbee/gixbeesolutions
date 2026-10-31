/** Catering owner app core (dashboard, areas, calendar) + menu hub in _catering_menu_*.js */
const CATERING_OWNER_FLOW_LOCKED = false;
const CATERING_OWNER_BUILD = '2026-10-17-catering-pkg-card-actions-v1';

function cateringOwnerDemoFileName() {
  try {
    const path = String(location.pathname || location.href || '').toLowerCase();
    if (path.indexOf('finalflow5') >= 0) return 'GIXBEE-CATERING-OWNER-FINALFLOW5.html';
  } catch (e) {
    /* ignore */
  }
  return 'GIXBEE-CATERING-OWNER-FINALFLOW.html';
}
const STORAGE_KEY = 'GIXBEE_CATERING_OWNER_V5';

const INDIAN_STATES = {
  Kerala: ['Thrissur', 'Ernakulam', 'Kozhikode', 'Kottayam', 'Palakkad', 'Malappuram', 'Thiruvananthapuram'],
  Karnataka: ['Bengaluru Urban', 'Mysuru', 'Mangalore', 'Udupi'],
  'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai'],
};
function defaultStore() {
  return {
    biz: {
      name: 'Archana Catering',
      loc: 'Sakthan Nagar, Thrissur',
      registeredState: 'Kerala',
      registeredDistrict: 'Thrissur',
      type: 'Catering',
      vertical: 'Service',
      phone: '+91 98765 43210',
      email: 'hello@archanacatering.in',
      gstin: '—',
      verified: true,
      memberSince: '2024',
    },
    serviceAreas: {
      states: ['Kerala'],
      districts: { Kerala: ['Thrissur', 'Ernakulam'] },
    },
    cateringMenu: defaultCateringMenuStore(),
    operators: [
      { id: 'op_owner', name: 'Archana K.', phone: '+91 94470 55566', role: 'owner' },
      { id: 'op_mgr1', name: 'Priya Nair', phone: '+91 98470 11223', role: 'manager' },
    ],
    deletedBusinesses: [
      {
        id: 'biz-del-1',
        name: 'Studio Nine Photography',
        type: 'Catering',
        loc: 'Kochi, Kerala',
        deletedAt: '2026-09-12',
      },
    ],
  };
}

const OPERATOR_ROLE_LABELS = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };

let store = defaultStore();
let saDraft = null;
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
    '</p><p style="margin-top:16px">Open <b>' +
    cateringOwnerDemoFileName() +
    '</b> (full file with JavaScript inside).</p>';
}
function photoShowScreen(id) {
  document.querySelectorAll('.scr').forEach((s) => s.classList.toggle('on', s.id === id));
}

function show(id) {
  photoShowScreen(id);
  if (id === 'calendar' && typeof syncPhotoCalendarUi === 'function') {
    syncPhotoCalendarUi();
  }
  if (id === 'photoCalDay' && typeof renderPhotoCalDay === 'function') renderPhotoCalDay();
  if (id === 'photoBookSettings' && typeof renderPhotoBookSettings === 'function') renderPhotoBookSettings();
}

function navigatePhotoScreen(id) {
  if (!id) return;
  if (id === 'calendar') {
    if (typeof openPhotoCalendar === 'function') openPhotoCalendar();
    else show('calendar');
  } else if (id === 'photoBookSettings') {
    renderPhotoBookSettings();
    show(id);
  } else if (id === 'photoCalDay') {
    renderPhotoCalDay();
    show(id);
  } else show(id);
}
function openMenuPkgHub() {
  if (typeof cateringMenuOpenHub === 'function') cateringMenuOpenHub();
  else show('menuPkg');
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
function loadStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      ensureCateringMenuStore();
      return;
    }
    const parsed = JSON.parse(raw);
    store = Object.assign(defaultStore(), parsed);
    if (!store.serviceAreas) store.serviceAreas = defaultStore().serviceAreas;
    if (!store.operators) store.operators = defaultStore().operators;
    if (!store.deletedBusinesses) store.deletedBusinesses = defaultStore().deletedBusinesses;
    if (!store.calendar || typeof store.calendar !== 'object') store.calendar = defaultPhotoCalendar();
    ensureCateringMenuStore();
    if (!store.cateringMenu.foodItems.length && typeof seedDemoFoodItems === 'function') {
      store.cateringMenu.foodItems = seedDemoFoodItems();
    }
  } catch (_e) {
    store = defaultStore();
    ensureCateringMenuStore();
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch (_e2) {
      /* ignore */
    }
  }
}
function saveStore() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
  } catch (_e) {
    try {
      if (store.calendar) store.calendar = defaultPhotoCalendar();
      localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
    } catch (_e2) {
      /* demo still runs without persisting */
    }
  }
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
    '<div class="biz-row"><div class="biz-ico catering">🍽️</div><div style="flex:1">' +
    '<p class="biz-name">' +
    esc(store.biz.name) +
    '</p><p class="biz-type">' + esc(store.biz.type || 'Catering') + '</p>' +
    '<p class="biz-meta"><span class="pill ok">Verified</span> · ' +
    esc(store.biz.loc) +
    '</p>' +
    '<div class="biz-badges"><span class="gy">Rs 2.1L this month</span></div>' +
    '<div class="biz-actions"><button type="button" class="mgr-catering" id="dashPhotoManage">Manage</button></div>' +
    '</div></div></div>';
  const manage = el('dashPhotoManage');
  if (manage) {
    manage.onclick = () => {
      renderPhotoDash();
      show('photoDash');
    };
  }
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
      (b.type || 'Catering') + ' · ' + (b.vertical || 'Service') + ' · ' + (b.loc || '—');
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
      (store.cateringMenu && store.cateringMenu.catPackages ? store.cateringMenu.catPackages.length : 0) +
      '</b><span>Menu &amp; packages</span></div>' +
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
        profCell('🏷', 'Business type', b.type || 'Catering')
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
    { id: 'menuPkg', cls: 'pink span', ico: '📦', label: 'Menu & Packages' },
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
      if (dest === 'menuPkg') openMenuPkgHub();
      else show(dest);
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

function bindGlobal() {
  document.querySelectorAll('.back[data-to]').forEach((btn) => {
    btn.onclick = () => navigatePhotoScreen(btn.getAttribute('data-to'));
  });
  document.querySelectorAll('.stub .btn[data-to], .btn[data-to]').forEach((btn) => {
    if (btn.id) return;
    const to = btn.getAttribute('data-to');
    if (to) btn.onclick = () => navigatePhotoScreen(to);
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

}

function boot() {
  try {
    if (!el('quickGrid')) {
      throw new Error('Missing dashboard — open ' + cateringOwnerDemoFileName() + ' (full file).');
    }
    loadStore();
    ensureCateringMenuStore();
    if (!store.cateringMenu.foodItems.length && typeof seedDemoFoodItems === 'function') {
      store.cateringMenu.foodItems = seedDemoFoodItems();
    }
    ensureRegisteredDistrict();
    saveStore();
    renderLmb();
    renderPhotoDash();
    bindGlobal();
    if (typeof bindCateringMenuAll === 'function') bindCateringMenuAll();
    bindPhotoCalendarUi();
    ensurePhotoCalendar();
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
