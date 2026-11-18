/** Decoration owner app — dashboard/platform parity with catering + decoration hub. */
const DECORATION_OWNER_BUILD = 'decoration-owner-church-christian-v23';
const STORAGE_KEY = 'GIXBEE_DECORATION_OWNER_V1';

function defaultStore() {
  return {
    biz: {
      name: 'Decor Mart',
      loc: 'Sakthan Nagar, Thrissur',
      registeredState: 'Kerala',
      registeredDistrict: 'Thrissur',
      type: 'Decoration',
      vertical: 'Service',
      phone: '+91 98765 43210',
      email: 'hello@decormart.in',
      gstin: '—',
      verified: true,
      memberSince: '2024',
    },
    serviceAreas: {
      states: ['Kerala'],
      districts: { Kerala: ['Thrissur', 'Ernakulam'] },
    },
    decorationMenu: defaultDecorationStore(),
    operators: [
      { id: 'op_owner', name: 'Riya V.', phone: '+91 94470 55566', role: 'owner' },
      { id: 'op_mgr1', name: 'Anil K.', phone: '+91 98470 11223', role: 'manager' },
    ],
    deletedBusinesses: [
      {
        id: 'biz-del-1',
        name: 'Studio Bloom Decor',
        type: 'Decoration',
        loc: 'Kochi, Kerala',
        deletedAt: '2026-09-12',
      },
    ],
    calendar: typeof defaultPhotoCalendar === 'function' ? defaultPhotoCalendar() : { bookings: [] },
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
function show(id) {
  document.querySelectorAll('.scr').forEach(function (s) {
    s.classList.toggle('on', s.id === id);
  });
  const scr = el(id);
  if (scr) scr.scrollTop = 0;
  if (id === 'calendar' && typeof syncPhotoCalendarUi === 'function') syncPhotoCalendarUi();
  if (id === 'photoCalDay' && typeof renderPhotoCalDay === 'function') renderPhotoCalDay();
  if (id === 'photoBookSettings' && typeof renderPhotoBookSettings === 'function') renderPhotoBookSettings();
}
function toast(m) {
  const t = el('toast');
  if (!t) return;
  t.textContent = m;
  t.style.display = 'block';
  setTimeout(function () {
    t.style.display = 'none';
  }, 2600);
}
function inr(n) {
  return '₹' + Math.max(0, Math.round(+n || 0)).toLocaleString('en-IN');
}
function uid(prefix) {
  return prefix + '-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}
function saveStore() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
  } catch (e) {
    /* ignore */
  }
}
function loadStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    store = Object.assign(defaultStore(), parsed);
    if (!store.decorationMenu) store.decorationMenu = defaultDecorationStore();
    if (!store.serviceAreas) store.serviceAreas = defaultStore().serviceAreas;
    if (!store.operators) store.operators = defaultStore().operators;
    if (!store.deletedBusinesses) store.deletedBusinesses = defaultStore().deletedBusinesses;
    if (!store.calendar || typeof store.calendar !== 'object') {
      store.calendar = typeof defaultPhotoCalendar === 'function' ? defaultPhotoCalendar() : { bookings: [] };
    }
  } catch (e) {
    store = defaultStore();
  }
}

function bindClick(id, fn) {
  const node = el(id);
  if (node) node.onclick = fn;
}
function bindOnInput(id, fn) {
  const node = el(id);
  if (node) node.oninput = fn;
}

function renderLmb() {
  const wrap = el('lmbCards');
  if (!wrap) return;
  wrap.innerHTML =
    '<div class="biz-dash-card">' +
    '<div class="biz-row"><div class="biz-ico decoration">🎀</div><div style="flex:1">' +
    '<p class="biz-name">' +
    esc(store.biz.name) +
    '</p><p class="biz-type">' +
    esc(store.biz.type || 'Decoration') +
    '</p>' +
    '<p class="biz-meta"><span class="pill ok">Verified</span> · ' +
    esc(store.biz.loc) +
    '</p>' +
    '<div class="biz-badges"><span>3 new requests</span><span class="gy">Rs 2.1L this month</span></div>' +
    '<div class="biz-actions"><button type="button" id="lmbCalBtn">Calendar</button><button type="button" id="lmbReqBtn">Requests</button>' +
    '<button type="button" class="mgr-decoration" id="dashDecorManage">Manage</button></div>' +
    '</div></div></div>';
  const manage = el('dashDecorManage');
  if (manage) {
    manage.onclick = function () {
      renderPhotoDash();
      show('photoDash');
    };
  }
  const lmbCal = el('lmbCalBtn');
  if (lmbCal) lmbCal.onclick = function () {
    if (typeof openPhotoCalendar === 'function') openPhotoCalendar();
    else show('calendar');
  };
  const lmbReq = el('lmbReqBtn');
  if (lmbReq) lmbReq.onclick = function () {
    show('requests');
  };
}

function openDecorHub(tab) {
  ensureDecorationStore();
  store.decorationMenu.hubTab = tab || 'packages';
  decorationMenuOpenHub();
}

function bootDecoration() {
  try {
    if (!el('quickGrid')) throw new Error('Open GIXBEE-DECORATION-OWNER-FINALFLOW5.html');
    loadStore();
    ensureDecorationStore();
    if (typeof ensureRegisteredDistrict === 'function') ensureRegisteredDistrict();
    saveStore();
    renderLmb();
    renderPhotoDash();
    bindDecorationPlatform();
    bindDecorationPackageUi();
    bindDecorationIndividualUi();
    if (typeof bindPhotoCalendarUi === 'function') bindPhotoCalendarUi();
    if (typeof ensurePhotoCalendar === 'function') ensurePhotoCalendar();
    bindClick('decHubBack', function () {
      renderPhotoDash();
      show('photoDash');
    });
    bindOnInput('decPkgSearch', function () {
      renderDecorPackageList();
    });
    show('lmbDashboard');
  } catch (err) {
    console.error(err);
    toast(err.message || String(err));
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bootDecoration);
else bootDecoration();