/** Decoration owner — LMB, dashboard, stubs; packages in _decoration_*_hub.js */
const DECORATION_OWNER_BUILD = 'decoration-owner-dash-catering-v4';
const STORAGE_KEY = 'GIXBEE_DECORATION_OWNER_V1';

function defaultStore() {
  return {
    biz: {
      name: 'Decor Mart',
      loc: 'Sakthan Nagar, Thrissur',
      type: 'Decoration',
      verified: true,
    },
    serviceAreas: {
      states: ['Kerala'],
      districts: { Kerala: ['Thrissur', 'Ernakulam'] },
    },
    decorationMenu: defaultDecorationStore(),
  };
}

function decorAreaSummaryText() {
  const sa = store.serviceAreas;
  if (!sa || !sa.states || !sa.states.length) return 'Set where you accept decoration bookings.';
  const parts = [];
  sa.states.forEach(function (st) {
    const dists = (sa.districts && sa.districts[st]) || [];
    if (dists.length) parts.push(st + ': ' + dists.join(', '));
    else parts.push(st);
  });
  return parts.join(' · ') || 'Set where you accept decoration bookings.';
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
  syncDecBottomNav(id);
}
function syncDecBottomNav(id) {
  const nav = el('decBottomNav');
  if (!nav) return;
  const showNav = id === 'decorDash' || id === 'decorStubEnq' || id === 'decorStubCal' || id === 'decorStubProf';
  nav.hidden = !showNav;
  nav.querySelectorAll('button').forEach(function (btn) {
    btn.classList.toggle('on', btn.getAttribute('data-nav') === id);
  });
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
    if (parsed && parsed.biz) store = Object.assign(defaultStore(), parsed);
    if (!store.decorationMenu) store.decorationMenu = defaultDecorationStore();
  } catch (e) {
    /* ignore */
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
  const host = el('lmbCards');
  if (!host) return;
  host.innerHTML =
    '<button type="button" class="biz-card" id="openDecorBiz"><div class="row"><div class="biz-ico">🎀</div><div><b>' +
    esc(store.biz.name) +
    '</b><span class="type">Decoration · Service</span><div class="biz-meta"><span class="pill pill-ver">Verified</span></div><div class="biz-actions"><button type="button" class="primary" style="background:var(--decor)">Manage</button></div></div></div></button>';
  bindClick('openDecorBiz', function () {
    show('decorDash');
    renderDecorDash();
  });
}

function renderDecorDash() {
  el('decDashHello').textContent = 'Hello, ' + store.biz.name + ' 👋';
  el('decDashLoc').textContent = store.biz.loc;
  if (el('decAreaSummary')) el('decAreaSummary').textContent = decorAreaSummaryText();
  const q = el('decQuickGrid');
  if (q) {
    q.innerHTML = [
      { dest: 'hub', cls: 'pink', ico: '📦', label: 'Packages & Services' },
      { dest: 'decorStubCal', cls: 'blue', ico: '📅', label: 'Calendar' },
      { dest: 'decorStubGal', cls: 'blue', ico: '🖼', label: 'Photos & Gallery' },
      { dest: 'decorStubEnq', cls: 'orange', ico: '💬', label: 'Enquiries', badge: '12' },
      { dest: 'decorStubOps', cls: 'teal', ico: '👥', label: 'Operators' },
    ]
      .map(function (t) {
        return (
          '<button type="button" class="qtile ' +
          t.cls +
          '" data-dec-go="' +
          esc(t.dest) +
          '">' +
          (t.badge ? '<span class="badge">' + t.badge + '</span>' : '') +
          '<div class="qi">' +
          t.ico +
          '</div><b>' +
          esc(t.label) +
          '</b></button>'
        );
      })
      .join('');
    q.querySelectorAll('[data-dec-go]').forEach(function (btn) {
      btn.onclick = function () {
        const dest = btn.getAttribute('data-dec-go');
        if (dest === 'hub') openDecorHub('packages');
        else show(dest);
      };
    });
  }
  syncDecBottomNav('decorDash');
}
function openDecorHub(tab) {
  ensureDecorationStore();
  store.decorationMenu.hubTab = tab || 'packages';
  decorationMenuOpenHub();
}

function bootDecoration() {
  loadStore();
  ensureDecorationStore();
  renderLmb();
  bindDecorationPackageUi();
  bindDecorationIndividualUi();
  bindClick('decDashBack', function () {
    show('lmbDashboard');
  });
  bindClick('decBizProfileBtn', function () {
    show('decorStubProf');
  });
  bindClick('decManageAreasLink', function (e) {
    if (e && e.preventDefault) e.preventDefault();
    toast('Service areas flow (prototype — same as catering)');
  });
  document.querySelectorAll('#decBottomNav button').forEach(function (btn) {
    btn.onclick = function () {
      const dest = btn.getAttribute('data-nav');
      if (dest) show(dest);
    };
  });
  bindOnInput('decPkgSearch', function () {
    renderDecorPackageList();
  });
  show('lmbDashboard');
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bootDecoration);
else bootDecoration();