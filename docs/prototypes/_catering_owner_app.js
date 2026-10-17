const CATERING_OWNER_BUILD = '2026-10-17-catering-owner-lmb-v1';
const STORAGE_KEY = 'GIXBEE_CATERING_OWNER_V1';

function cateringOwnerDemoFile() {
  try {
    const path = String(location.pathname || location.href || '').toLowerCase();
    if (path.indexOf('finalflow5') >= 0) return 'GIXBEE-CATERING-OWNER-FINALFLOW5.html';
  } catch (e) {
    /* ignore */
  }
  return 'GIXBEE-CATERING-OWNER-FINALFLOW.html';
}

function defaultStore() {
  return {
    biz: {
      name: 'Archana Catering',
      loc: 'Sakthan Nagar, Thrissur',
      type: 'Catering',
      vertical: 'Service',
      verified: true,
    },
    serviceAreas: {
      states: ['Kerala'],
      districts: { Kerala: ['Thrissur', 'Ernakulam'] },
    },
    stats: { newRequests: 3, revenueLabel: 'Rs 2.1L this month' },
  };
}

let store = defaultStore();

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

function loadStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) store = Object.assign(defaultStore(), JSON.parse(raw));
  } catch (e) {
    store = defaultStore();
  }
}

function saveStore() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
  } catch (e) {
    /* ignore */
  }
}

function show(id) {
  document.querySelectorAll('.scr').forEach(function (s) {
    s.classList.toggle('on', s.id === id);
  });
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

function areaSummaryText() {
  const sa = store.serviceAreas;
  if (!sa.states.length) return 'Set where you accept bookings.';
  return sa.states
    .map(function (st) {
      const ds = sa.districts[st] || [];
      return st + ' (' + ds.length + ' district' + (ds.length === 1 ? '' : 's') + ')';
    })
    .join(' · ');
}

function renderLmb() {
  const wrap = el('lmbCards');
  if (!wrap) return;
  const b = store.biz;
  wrap.innerHTML =
    '<div class="biz-dash-card">' +
    '<div class="biz-row"><div class="biz-ico catering">🍽️</div><div style="flex:1">' +
    '<p class="biz-name">' +
    esc(b.name) +
    '</p><p class="biz-type">' +
    esc(b.type || 'Catering') +
    '</p>' +
    '<p class="biz-meta"><span class="pill ok">Verified</span> · ' +
    esc(b.loc) +
    '</p>' +
    '<div class="biz-badges"><span>' +
    store.stats.newRequests +
    ' new requests</span><span class="gy">' +
    esc(store.stats.revenueLabel) +
    '</span></div>' +
    '<div class="biz-actions"><button type="button" id="lmbCalBtn">Calendar</button><button type="button" id="lmbReqBtn">Requests</button>' +
    '<button type="button" class="mgr-catering" id="dashCateringManage">Manage</button></div>' +
    '</div></div></div>';
  el('dashCateringManage').onclick = function () {
    renderCateringDash();
    show('cateringDash');
  };
  const lmbCal = el('lmbCalBtn');
  if (lmbCal) lmbCal.onclick = function () {
    toast('Calendar — coming in next catering screens');
  };
  const lmbReq = el('lmbReqBtn');
  if (lmbReq) lmbReq.onclick = function () {
    toast('Booking requests — coming in next catering screens');
  };
}

function renderCateringDash() {
  const b = store.biz;
  el('dashBizName').textContent = b.name;
  el('dashLocTxt').textContent = b.loc;
  el('dashLocIco').innerHTML = cateringIcon('pin');
  el('areaCardIco').innerHTML = cateringIcon('pin');
  el('areaSummary').textContent = areaSummaryText();
  const q = el('quickGrid');
  if (!q) return;
  q.innerHTML = [
    { id: 'menuPkg', cls: 'pink', ico: '🍽️', label: 'Menu & Packages' },
    { id: 'calendar', cls: 'blue', ico: '📅', label: 'Calendar' },
    { id: 'gallery', cls: 'blue', ico: '🖼', label: 'Photos & Gallery' },
    { id: 'requests', cls: 'orange', ico: '🔔', label: 'Booking Requests', badge: String(store.stats.newRequests) },
    { id: 'operators', cls: 'teal', ico: '👥', label: 'Operators' },
    { id: 'deletedBusiness', cls: 'gray', ico: '🗑', label: 'Deleted business' },
  ]
    .map(function (t) {
      return (
        '<button type="button" class="qtile ' +
        t.cls +
        '" data-go="' +
        t.id +
        '">' +
        (t.badge ? '<span class="badge">' + esc(t.badge) + '</span>' : '') +
        '<div class="qi">' +
        t.ico +
        '</div><b>' +
        esc(t.label) +
        '</b></button>'
      );
    })
    .join('');
  q.querySelectorAll('[data-go]').forEach(function (btn) {
    btn.onclick = function () {
      const dest = btn.getAttribute('data-go');
      if (dest === 'menuPkg') {
        toast('Menu & packages hub — share page 3+ screens to build next');
        return;
      }
      toast('Coming in next catering owner screens');
    };
  });
}

function bindEvents() {
  const home = el('lmbHomeBtn');
  if (home) home.onclick = function () {
    show('lmbDashboard');
  };
  const back = el('backToLmb');
  if (back) back.onclick = function () {
    show('lmbDashboard');
  };
  const prof = el('cateringBizProfileBtn');
  if (prof) {
    prof.onclick = function () {
      toast('Business profile — coming in next catering screens');
    };
  }
  const areas = el('manageAreasLink');
  if (areas) {
    areas.onclick = function (e) {
      e.preventDefault();
      toast('Service areas — coming in next catering screens');
    };
  }
}

function showBootError(msg) {
  const box = el('bootError');
  if (!box) return;
  box.hidden = false;
  box.innerHTML = '<b>Could not start catering owner demo</b><p style="margin:12px 0">' + esc(msg) + '</p>';
}

function boot() {
  try {
    if (!el('quickGrid')) {
      throw new Error('Open ' + cateringOwnerDemoFile() + ' (full bundled file).');
    }
    loadStore();
    saveStore();
    renderLmb();
    renderCateringDash();
    bindEvents();
    const err = el('bootError');
    if (err) err.hidden = true;
    const tag = el('buildTag');
    if (tag) tag.textContent = 'Catering owner · ' + CATERING_OWNER_BUILD;
    show('lmbDashboard');
  } catch (err) {
    console.error(err);
    showBootError(err.message || String(err));
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
