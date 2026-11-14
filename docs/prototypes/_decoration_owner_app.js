/** Decoration owner — LMB, dashboard, stubs; packages in _decoration_*_hub.js */
const DECORATION_OWNER_BUILD = 'decoration-owner-svc-price-v3';
const STORAGE_KEY = 'GIXBEE_DECORATION_OWNER_V1';

function defaultStore() {
  return {
    biz: {
      name: 'Decor Mart',
      loc: 'Sakthan Nagar, Thrissur',
      type: 'Decoration',
      verified: true,
    },
    decorationMenu: defaultDecorationStore(),
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
  document.querySelectorAll('[data-dec-dash]').forEach(function (btn) {
    btn.onclick = function () {
      const dest = btn.getAttribute('data-dec-dash');
      if (dest === 'hub-pkg') openDecorHub('packages');
      else if (dest === 'hub-svc') openDecorHub('services');
      else if (dest === 'enquiries') show('decorStubEnq');
      else if (dest === 'calendar') show('decorStubCal');
      else if (dest === 'gallery') show('decorStubGal');
      else if (dest === 'profile') show('decorStubProf');
    };
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