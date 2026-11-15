/** Decoration owner platform — calendar, service areas, operators (from catering parity). */
const INDIAN_STATES = {
  Kerala: ['Thrissur', 'Ernakulam', 'Kozhikode', 'Kottayam', 'Palakkad', 'Malappuram', 'Thiruvananthapuram'],
  Karnataka: ['Bengaluru Urban', 'Mysuru', 'Mangalore', 'Udupi'],
  'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai'],
};
const OPERATOR_ROLE_LABELS = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };
let saDraft = null;

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
      (b.type || 'Decoration') + ' · ' + (b.vertical || 'Service') + ' · ' + (b.loc || '—');
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
      ((store.decorationMenu && store.decorationMenu.catPackages) ? store.decorationMenu.catPackages.length : 0) +
      '</b><span>Packages &amp; services</span></div>' +
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
        profCell('🏷', 'Business type', b.type || 'Decoration')
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
    { id: 'hub', cls: 'pink', ico: '📦', label: 'Packages & Services' },
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
      if (dest === 'hub') openDecorHub('packages');
      else if (dest === 'photoOperators') {
        renderPhotoOperators();
        show(dest);
      } else if (dest === 'deletedBusiness') {
        renderDeletedBusinesses();
        show(dest);
      } else if (dest === 'calendar') {
        openPhotoCalendar();
      } else if (dest === 'photoBookSettings') {
        renderPhotoBookSettings();
        show(dest);
      } else if (dest === 'photoCalDay') {
        renderPhotoCalDay();
        show(dest);
      } else show(dest);
    };
  });
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

function bindDecorationPlatform() {
  document.querySelectorAll('.back[data-to]').forEach((btn) => {
    btn.onclick = () => navigatePhotoScreen(btn.getAttribute('data-to'));
  });
  document.querySelectorAll('.stub .btn[data-to], .btn[data-to]').forEach((btn) => {
    if (btn.id) return;
    const to = btn.getAttribute('data-to');
    if (to) btn.onclick = () => navigatePhotoScreen(to);
  });
  const lmbHome = el('lmbHomeBtn');
  if (lmbHome) lmbHome.onclick = () => show('lmbDashboard');
  const backLmb = el('backToLmb');
  if (backLmb) backLmb.onclick = () => show('lmbDashboard');
  const decDashBack = el('decDashBack');
  if (decDashBack) decDashBack.onclick = () => show('lmbDashboard');
  const profBtn = el('photoBizProfileBtn');
  if (profBtn) {
    profBtn.onclick = function () {
      renderPhotoBizProfile();
      show('photoBizProfile');
    };
  }
  const manageAreas = el('manageAreasLink');
  if (manageAreas) {
    manageAreas.onclick = (e) => {
      e.preventDefault();
      startSaDraft();
      el('saHeroIco').innerHTML = photoIcon('pin');
      el('saSearchIco').innerHTML = photoIcon('search');
      renderStateList();
      show('saStates');
    };
  }
  const saSkip = el('saSkip');
  if (saSkip) saSkip.onclick = () => show('photoDash');
  const saCont = el('saStatesContinue');
  if (saCont) {
    saCont.onclick = () => {
      if (!saDraft.states.length) {
        toast('Select at least one state.');
        return;
      }
      saActiveState = saDraft.states[0];
      show('saDistricts');
      renderStateSeg();
      renderDistList();
    };
  }
  const stateSearch = el('stateSearch');
  if (stateSearch) stateSearch.oninput = () => renderStateList();
  const distSearch = el('distSearch');
  if (distSearch) distSearch.oninput = () => renderDistList();
  const saDistCont = el('saDistContinue');
  if (saDistCont) {
    saDistCont.onclick = () => {
      show('saReview');
      el('saRevIco').innerHTML = photoIcon('pin');
      renderSaReview();
    };
  }
  const saSave = el('saSave');
  if (saSave) {
    saSave.onclick = () => {
      store.serviceAreas = JSON.parse(JSON.stringify(saDraft));
      ensureRegisteredDistrict();
      saveStore();
      renderPhotoDash();
      show('photoDash');
      toast('Service areas saved');
    };
  }
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

