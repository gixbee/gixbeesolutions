/** Catering owner — Menu & Packages hub (packages + food items). */

let menuPickCtx = { mode: 'catalog', selected: {}, moduleId: null, returnTo: 'menuPkg' };
let foodFormDraft = null;
let pkgWizard = { draft: null, editId: null, step: 1 };

const PKG_EVENT_CATEGORIES = [
  {
    id: 'wedding',
    label: 'Wedding & Related Functions',
    sub: 'Wedding, Engagement, Reception',
    icon: '💍',
  },
  {
    id: 'other',
    label: 'Other Functions',
    sub: 'Birthday, Noolukettu, Baptism, Nikah, Housewarming and more',
    icon: '📅',
  },
];

function pkgCategoryLabel(id) {
  let i;
  for (i = 0; i < PKG_EVENT_CATEGORIES.length; i++) {
    if (PKG_EVENT_CATEGORIES[i].id === id) return PKG_EVENT_CATEGORIES[i].label;
  }
  return PKG_EVENT_CATEGORIES[0].label;
}

function syncPkgDraftFromStep2Fields() {
  if (!pkgWizard.draft) return;
  const nameEl = el('catPkgName');
  const descEl = el('catPkgDesc');
  if (nameEl) pkgWizard.draft.name = (nameEl.value || '').trim();
  if (descEl) pkgWizard.draft.description = (descEl.value || '').trim();
  pkgWizard.draft.customerTitle =
    (pkgWizard.draft.level || 'Basic') + ' - ' + (pkgWizard.draft.name || 'Your package name');
}

function dietMarkHtml(kind, large) {
  return (
    '<span class="diet-mark ' +
    kind +
    (large ? ' lg' : '') +
    '" aria-hidden="true"><i></i></span>'
  );
}

function packageIsSadhya(dietType) {
  return dietType === 'veg' || dietType === 'nonveg_sadhya';
}

function packageDietChosen(dietType) {
  return dietType === 'veg' || dietType === 'nonveg_sadhya' || dietType === 'mixed';
}

function packageDietLeadHtml(dietType) {
  if (dietType === 'veg') {
    return '<span class="pkg-diet-lead">' + dietMarkHtml('veg', true) + '<span>Veg sadhya</span></span>';
  }
  if (dietType === 'nonveg_sadhya') {
    return (
      '<span class="pkg-diet-lead"><span class="diet-marks">' +
      dietMarkHtml('veg', true) +
      dietMarkHtml('non', true) +
      '</span><span>Non-veg sadhya</span></span>'
    );
  }
  if (dietType === 'mixed') {
    return (
      '<span class="pkg-diet-lead"><span class="diet-marks">' +
      dietMarkHtml('veg', true) +
      dietMarkHtml('non', true) +
      '</span><span>Veg and non-veg buffet</span></span>'
    );
  }
  return '<span class="pkg-diet-lead need"><span>Set menu type</span></span>';
}

function packageDietChipHtml(dietType) {
  if (packageDietChosen(dietType)) return packageDietLeadHtml(dietType);
  return '';
}

function applyPackageDiet(next) {
  const d = pkgWizard.draft;
  if (!d) return;
  const changed = d.dietType !== next;
  d.dietType = next;
  if (changed && packageIsSadhya(next)) {
    d.serveAtTable = true;
    d.serveAtCounter = false;
  } else if (changed && next === 'mixed') {
    d.serveAtTable = true;
    d.serveAtCounter = true;
  }
  dropDishesOutsidePackageDiet(d);
  renderCatPkgDietChoice();
  updatePkgCustomerPreview();
}

function vegSadhyaShowsDish(item) {
  if (!item) return false;
  if (item.custom || item.subcatId === 'custom') return true;
  const key = String(item.masterKey || '');
  const inRiceGroup = item.moduleId === 'g03' || key.indexOf('g03::') === 0;
  if (!inRiceGroup) return true;
  if (item.subcatId && item.subcatId !== 'rice') return false;
  if (!item.subcatId && key.indexOf('g03::') === 0 && key.indexOf('g03::rice::') !== 0) return false;
  if (/noodle/i.test(item.name || '')) return false;
  return true;
}

function dishAllowedOnPackage(item, dietType) {
  if (!item) return false;
  if (dietType === 'veg' && normalizeFoodDiet(item.diet) === 'non_veg') return false;
  if (dietType === 'veg' && !vegSadhyaShowsDish(item)) return false;
  return true;
}

function packageModuleLabel(mod, dietType) {
  if (mod && mod.id === 'g03' && dietType === 'veg') return 'Rice';
  return (mod && mod.name) || '';
}

function dropDishesOutsidePackageDiet(d) {
  if (!d || d.dietType !== 'veg') return;
  d.itemIds = (d.itemIds || []).filter(function (fid) {
    return dishAllowedOnPackage(findFoodItem(fid), d.dietType);
  });
}

function renderCatPkgDietChoice() {
  const host = el('catPkgDietChoice');
  const d = pkgWizard.draft;
  if (!host || !d) return;
  const options = [
    {
      id: 'veg',
      title: 'Veg sadhya',
      sub: 'Vegetarian sadhya, served at the table.',
    },
    {
      id: 'nonveg_sadhya',
      title: 'Non-veg sadhya',
      sub: 'Sadhya with fish, chicken or meat, served at the table.',
    },
    {
      id: 'mixed',
      title: 'Veg and non-veg buffet',
      sub: 'Serve at the table, at the buffet counter, or both.',
    },
  ];
  host.innerHTML =
    '<div class="cat-diet-choice">' +
    options
      .map(function (opt) {
        const on = d.dietType === opt.id;
        return (
          '<button type="button" class="cat-diet-card' +
          (on ? ' on' : '') +
          '" data-pkg-diet="' +
          opt.id +
          '"><span class="cat-diet-ico">' +
          (opt.id === 'veg'
            ? dietMarkHtml('veg', true)
            : dietMarkHtml('veg', true) + dietMarkHtml('non', true)) +
          '</span><span><b>' +
          esc(opt.title) +
          '</b><small>' +
          esc(opt.sub) +
          '</small></span><span class="cat-diet-tick" aria-hidden="true">✓</span></button>'
        );
      })
      .join('') +
    '</div>';
  host.querySelectorAll('[data-pkg-diet]').forEach(function (btn) {
    btn.onclick = function () {
      applyPackageDiet(btn.getAttribute('data-pkg-diet'));
    };
  });
}

function updatePkgCustomerPreview() {
  syncPkgDraftFromStep2Fields();
  const host = el('catPkgCustomerPreview');
  if (!host || !pkgWizard.draft) return;
  const diet = packageDietChipHtml(pkgWizard.draft.dietType);
  const title = esc(pkgWizard.draft.customerTitle || 'Basic - Your package name');
  host.innerHTML =
    (diet ? '<div class="cat-pkg-cust-diet">' + diet + '</div>' : '') +
    '<div class="cat-pkg-cust-name">' +
    title +
    '</div>';
}

function bindClick(id, handler) {
  const node = el(id);
  if (node) node.onclick = handler;
}

function bindOnInput(id, handler) {
  const node = el(id);
  if (node) node.oninput = handler;
}

function bindOnChange(id, handler) {
  const node = el(id);
  if (node) node.onchange = handler;
}
let individualPickMk = null;
let individualPickSearch = '';
let catalogModuleSearch = '';

function ensureCateringMenuStore() {
  if (!store.cateringMenu) store.cateringMenu = defaultCateringMenuStore();
  if (!store.cateringMenu.foodItems) store.cateringMenu.foodItems = [];
  if (!store.cateringMenu.catPackages) store.cateringMenu.catPackages = defaultCateringMenuStore().catPackages;
  if (!store.cateringMenu.hubTab) store.cateringMenu.hubTab = 'packages';
  if (store.cateringMenu.pkgFilter === 'custom') store.cateringMenu.pkgFilter = 'all';
  if (!store.cateringMenu.pkgCategoryFilter) store.cateringMenu.pkgCategoryFilter = 'wedding';
  migratePackageCategories();
  migrateLegacyCateringPackageLabels();
  migrateFoodDietsToVegNonVeg();
  migrateEarlyGuestSlabDefaults();
  migrateDemoPackageDiet();
}

function normalizeFoodDiet(diet) {
  return diet === 'non_veg' || diet === 'egg' ? 'non_veg' : 'veg';
}

function migrateFoodDietsToVegNonVeg() {
  (store.cateringMenu.foodItems || []).forEach(function (f) {
    f.diet = normalizeFoodDiet(f.diet);
  });
}

function migrateEarlyGuestSlabDefaults() {
  (store.cateringMenu.catPackages || []).forEach(function (p) {
    const slabs = p.guestSlabs || [];
    if (slabs.length === 5 && +slabs[0].from === 25 && +slabs[0].to === 50 && +slabs[4].from === 301) {
      const prices = slabs.map(function (s) {
        return s.price;
      });
      p.guestSlabs = defaultPackageGuestSlabs().map(function (s, i) {
        return { from: s.from, to: s.to, price: prices[i] != null ? prices[i] : s.price };
      });
    }
  });
  (store.cateringMenu.foodItems || []).forEach(function (f) {
    const slabs = f.slabs || [];
    if (!slabs.length) f.slabs = defaultItemSlabs();
  });
}

function migrateDemoPackageDiet() {
  const seeded = {
    'cpkg-demo-1': 'mixed',
    'cpkg-demo-2': 'mixed',
    'cpkg-demo-3': 'veg',
  };
  (store.cateringMenu.catPackages || []).forEach(function (p) {
    if (packageDietChosen(p.dietType)) return;
    if (seeded[p.id] && !(p.itemIds || []).length) p.dietType = seeded[p.id];
  });
}

function migratePackageCategories() {
  (store.cateringMenu.catPackages || []).forEach(function (p) {
    if (p.packageCategory !== 'wedding' && p.packageCategory !== 'other') {
      p.packageCategory = 'wedding';
    }
  });
}

function packageCategoryHubLabel(id) {
  if (id === 'other') return 'Other Functions';
  return 'Wedding & Related';
}

/** Older demos used photography-style names (e.g. "Wedding Premium"); rename in place. */
function migrateLegacyCateringPackageLabels() {
  const renames = {
    'Wedding Premium': 'Wedding Day Feast',
    'Engagement Standard': 'Engagement Day Menu',
    'Reception Basic': 'Reception Dinner Menu',
    'Classic Wedding Package': 'Wedding Day Feast',
  };
  (store.cateringMenu.catPackages || []).forEach(function (p) {
    if (renames[p.name]) p.name = renames[p.name];
    if (p.coverage && /photographer/i.test(String(p.coverage))) {
      p.subtitle = (p.level || 'Package') + ' tier · catering · per person';
      delete p.coverage;
    }
  });
}

function cateringMenuOpenHub() {
  ensureCateringMenuStore();
  show('menuPkg');
  renderCateringMenuHub();
}

function catLevelClass(level) {
  return String(level || 'Standard').toLowerCase();
}

function findFoodItem(id) {
  return (store.cateringMenu.foodItems || []).find(function (f) {
    return f.id === id;
  });
}

function findCatPackage(id) {
  return (store.cateringMenu.catPackages || []).find(function (p) {
    return p.id === id;
  });
}

function ownerHasMasterKey(masterKey) {
  return (store.cateringMenu.foodItems || []).some(function (f) {
    return f.masterKey === masterKey;
  });
}

function countItemsInModule(moduleId) {
  return (store.cateringMenu.foodItems || []).filter(function (f) {
    return f.moduleId === moduleId && f.status !== 'archived' && !f.custom;
  }).length;
}

function packageItemIdsForModule(pkg, moduleId) {
  const ids = pkg.itemIds || [];
  return ids.filter(function (fid) {
    const it = findFoodItem(fid);
    return it && it.moduleId === moduleId;
  });
}

function countPkgItemsInModule(pkg, moduleId) {
  return packageItemIdsForModule(pkg, moduleId).length;
}

function lowestGuestPrice(pkg) {
  const slabs = pkg.guestSlabs || [];
  if (!slabs.length) return pkg.price || 0;
  let min = Infinity;
  slabs.forEach(function (s) {
    min = Math.min(min, +s.price || 0);
  });
  return min === Infinity ? pkg.price || 0 : min;
}

function formatInrCompact(n) {
  const v = Math.max(0, Math.round(+n || 0));
  return '₹' + v.toLocaleString('en-IN');
}

function formatInrFull(n) {
  return Math.max(0, Math.round(+n || 0)).toLocaleString('en-IN');
}

function offerPercentOf(pkg) {
  if (!pkg || !pkg.offerEnabled) return 0;
  const n = Math.round(+pkg.discountPercent);
  if (n >= 1 && n <= 90) return n;
  return 0;
}

function priceAfterOffer(base, percent) {
  const b = Math.max(0, Math.round(+base || 0));
  if (!percent) return b;
  return Math.max(0, Math.round((b * (100 - percent)) / 100));
}

function offerBadgeHtml(percent) {
  return (
    '<span class="cat-offer-badge"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M21.4 11.6 12.4 2.6A2 2 0 0 0 11 2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 .6 1.4l9 9a2 2 0 0 0 2.8 0l7-7a2 2 0 0 0 0-2.8zM7.2 8.5a1.5 1.5 0 1 1 1.5-1.5 1.5 1.5 0 0 1-1.5 1.5z"/></svg>' +
    percent +
    '% off</span>'
  );
}

function offerPriceBitsHtml(base, percent) {
  return (
    '<s>₹' +
    formatInrFull(base) +
    '</s><b>₹' +
    formatInrFull(priceAfterOffer(base, percent)) +
    '</b>' +
    offerBadgeHtml(percent)
  );
}

function guestSlabPriceForCount(slabs, guestCount) {
  const c = +guestCount || 0;
  let i;
  for (i = 0; i < (slabs || []).length; i++) {
    const s = slabs[i];
    if (c >= +s.from && c <= +s.to) return +s.price || 0;
  }
  if (slabs && slabs.length) return +slabs[slabs.length - 1].price || 0;
  return 0;
}

function exampleGuestCountForSlabs(slabs) {
  const list = slabs || [];
  if (!list.length) return 100;
  let i;
  for (i = 0; i < list.length; i++) {
    const s = list[i];
    if (100 >= +s.from && 100 <= +s.to) return 100;
  }
  const mid = list[Math.floor(list.length / 2)];
  return Math.round((+mid.from + +mid.to) / 2) || +mid.from || 100;
}

function renderPkgGuestPricingExample(slabs) {
  const host = el('catPkgPricingExample');
  if (!host) return;
  const s = slabs || (pkgWizard.draft && pkgWizard.draft.guestSlabs) || [];
  if (!s.length) {
    host.innerHTML = '';
    return;
  }
  const guests = exampleGuestCountForSlabs(s);
  const base = guestSlabPriceForCount(s, guests);
  const pct = pkgWizard.draft ? offerPercentOf(pkgWizard.draft) : 0;
  const per = priceAfterOffer(base, pct);
  const total = guests * per;
  host.innerHTML =
    '<span class="cat-pkg-example-ico" aria-hidden="true">🧮</span><div><b>Example Calculation</b><p>' +
    guests +
    ' guests × ₹' +
    formatInrFull(per) +
    ' = ₹ ' +
    formatInrFull(total) +
    ' (approx).' +
    (pct ? ' Offer price, ' + pct + '% off ₹' + formatInrFull(base) + ' / plate.' : '') +
    '</p></div>';
}

function renderCateringMenuHub() {
  ensureCateringMenuStore();
  const hub = el('menuPkg');
  const isPkg = store.cateringMenu.hubTab !== 'food';
  if (hub) {
    hub.classList.toggle('hub-mode-packages', isPkg);
    hub.classList.toggle('hub-mode-services', !isPkg);
  }
  const tabPkg = el('catTabPackages');
  const tabFood = el('catTabFoodItems');
  if (tabPkg) tabPkg.classList.toggle('on', isPkg);
  if (tabFood) tabFood.classList.toggle('on', !isPkg);

  const hubTitle = el('catHubTitle');
  if (hubTitle) hubTitle.textContent = isPkg ? 'Menu & Packages' : 'Individual Food Items';

  const intro = el('catHubIntro');
  if (intro && !isPkg) {
    intro.textContent = '';
  }

  const stat = el('catHubStat');
  if (stat) {
    if (isPkg) {
      const n = filteredCatPackages().length;
      stat.innerHTML = '<span class="cat-hub-count"><b>' + n + '</b>Packages</span>';
    } else {
      const foods = (store.cateringMenu.foodItems || []).filter(function (f) {
        return f.status === 'active';
      }).length;
      stat.innerHTML =
        '<span class="cat-stat-pill blue"><b>' +
        individualFoodItems().length +
        '</b> INDIVIDUAL ITEMS</span><span class="cat-stat-pill live"><b>' +
        foods +
        '</b> LIVE</span>';
    }
  }

  renderCatPkgFilters();
  renderCatPkgCategoryFilters();
  renderCatPkgList();
  renderCatIndividualFoodList();
  bindCateringMenuHubUi();
}

function individualFoodItems() {
  return (store.cateringMenu.foodItems || []).filter(function (f) {
    if (f.status === 'archived') return false;
    return f.individualListing !== false;
  });
}

function foodDietLeadHtml(diet) {
  const non = normalizeFoodDiet(diet) === 'non_veg';
  return (
    '<span class="pkg-diet-lead food-diet-lead">' +
    dietMarkHtml(non ? 'non' : 'veg', false) +
    '<span>' +
    (non ? 'Non-veg' : 'Veg') +
    '</span></span>'
  );
}

function foodItemFromPrice(f) {
  const slabs = f.slabs || [];
  if (!slabs.length) return '—';
  const min = Math.min.apply(
    null,
    slabs.map(function (s) {
      return +s.price || 0;
    })
  );
  const unit = 'plate';
  if (f.rateMode === 'flat') return formatInrCompact(min) + ' / ' + unit;
  return formatInrCompact(min) + ' / ' + unit + '+';
}

function foodPriceHtml(f) {
  const plain = foodItemFromPrice(f);
  const pct = offerPercentOf(f);
  if (plain === '—' || !pct) return esc(plain);
  const slabs = f.slabs || [];
  const min = Math.min.apply(
    null,
    slabs.map(function (s) {
      return +s.price || 0;
    })
  );
  const suffix = f.rateMode === 'flat' ? ' / plate' : ' / plate+';
  return (
    '<span class="pkg-offer"><s>' +
    formatInrCompact(min) +
    '</s><b>' +
    formatInrCompact(priceAfterOffer(min, pct)) +
    esc(suffix) +
    '</b>' +
    offerBadgeHtml(pct) +
    '</span>'
  );
}

function renderCatPkgFilters() {
  const row = el('catPkgFilters');
  if (!row) return;
  const filters = [{ id: 'all', label: 'All' }].concat(
    CAT_PKG_LEVELS.map(function (l) {
      return { id: l.toLowerCase(), label: l };
    })
  );
  row.innerHTML = filters
    .map(function (f) {
      return (
        '<button type="button" class="fchip' +
        (store.cateringMenu.pkgFilter === f.id ? ' on' : '') +
        '" data-cat-f="' +
        esc(f.id) +
        '">' +
        esc(f.label) +
        '</button>'
      );
    })
    .join('');
}

function packageFromPersonLabel(p) {
  const from = lowestGuestPrice(p) || p.price || 0;
  if (p.rateMode === 'flat') return '₹' + formatInrFull(from) + ' / person';
  return 'From ₹' + formatInrFull(from) + ' / person';
}

function packagePriceHtml(p) {
  const base = lowestGuestPrice(p) || +p.price || 0;
  const pct = offerPercentOf(p);
  const prefix = p.rateMode === 'flat' ? '' : 'From ';
  if (!pct) return esc(prefix + '₹' + formatInrFull(base) + ' / person');
  return (
    '<span class="pkg-offer"><s>₹' +
    formatInrFull(base) +
    '</s><span class="row"><b>' +
    esc(prefix) +
    '₹' +
    formatInrFull(priceAfterOffer(base, pct)) +
    ' / person</b>' +
    offerBadgeHtml(pct) +
    '</span></span>'
  );
}

function renderCatPkgCategoryFilters() {
  const row = el('catPkgCategoryFilters');
  if (!row) return;
  const sel = store.cateringMenu.pkgCategoryFilter || 'all';
  const cards = [
    {
      id: 'wedding',
      title: 'Wedding & Related',
      sub: 'Wedding, Engagement, Reception',
    },
    {
      id: 'other',
      title: 'Other Functions',
      sub: 'Birthday, Noolukettu, Baptism, etc.',
    },
  ];
  row.innerHTML =
    '<div class="hub-cat-filter-grid">' +
    cards
      .map(function (c) {
        return (
          '<button type="button" class="hub-cat-card' +
          (sel === c.id ? ' on' : '') +
          '" data-cat-ev="' +
          esc(c.id) +
          '"><b>' +
          esc(c.title) +
          '</b><small>' +
          esc(c.sub) +
          '</small></button>'
        );
      })
      .join('') +
    '</div>';
}

function filteredCatPackages() {
  let list = (store.cateringMenu.catPackages || []).slice();
  const f = store.cateringMenu.pkgFilter || 'all';
  if (f !== 'all') {
    list = list.filter(function (p) {
      return catLevelClass(p.level) === f;
    });
  }
  const ev = store.cateringMenu.pkgCategoryFilter || 'all';
  if (ev !== 'all') {
    list = list.filter(function (p) {
      return (p.packageCategory || 'wedding') === ev;
    });
  }
  const q = (store.cateringMenu.pkgSearch || '').trim().toLowerCase();
  if (q) {
    list = list.filter(function (p) {
      return (
        String(p.name || '').toLowerCase().includes(q) ||
        String(p.level || '').toLowerCase().includes(q) ||
        packageCategoryHubLabel(p.packageCategory || 'wedding').toLowerCase().includes(q)
      );
    });
  }
  const sort = store.cateringMenu.pkgSort || 'name';
  list.sort(function (a, b) {
    if (sort === 'price') return (a.price || 0) - (b.price || 0);
    if (sort === 'status') return String(a.status).localeCompare(String(b.status));
    return String(a.name || '').localeCompare(String(b.name || ''));
  });
  return list;
}

function renderCatPkgList() {
  const list = el('catPkgList');
  if (!list) return;
  const pkgs = filteredCatPackages();
  if (!pkgs.length) {
    const ev = store.cateringMenu.pkgCategoryFilter || 'all';
    const tier = store.cateringMenu.pkgFilter || 'all';
    const filtered =
      ev !== 'all' || tier !== 'all' || (store.cateringMenu.pkgSearch || '').trim();
    list.innerHTML =
      '<div class="hub-empty"><div class="hub-empty-ico">📦</div><b>' +
      (filtered ? 'No packages match these filters' : 'No packages yet') +
      '</b><p>' +
      (filtered
        ? 'Try another category or tier, or create a new package.'
        : 'Create a veg sadhya or a non-veg sadhya for table service, or a veg and non-veg buffet served at the table, the counter, or both.') +
      '</p></div>';
    return;
  }
  list.innerHTML = pkgs
    .map(function (p) {
      const lv = catLevelClass(p.level);
      const catId = p.packageCategory || 'wedding';
      return (
        '<div class="pkg-card pkg-card-tap" data-cpkg-id="' +
        esc(p.id) +
        '"><div class="pkg-thumb lv-' +
        lv +
        '"><span style="font-size:32px;z-index:1;position:relative">' +
        esc(p.imageEmoji || '🍽️') +
        '</span></div><div class="pkg-bd"><div class="pkg-top-row"><div class="pkg-chips"><span class="pkg-level ' +
        lv +
        '">' +
        esc(p.level) +
        '</span><span class="pkg-meta-chip ceremony">' +
        esc(packageCategoryHubLabel(catId)) +
        '</span></div><button type="button" class="pkg-card-menu" data-cpkg-menu="' +
        esc(p.id) +
        '" aria-label="Package options">⋮</button></div>' +
        (packageDietChipHtml(p.dietType) || '<span class="pkg-diet-lead need"><span>Set menu type</span></span>') +
        '<b>' +
        esc(p.name) +
        '</b><div class="pkg-sub">' +
        esc(packageServiceLabel(p)) +
        '</div><div class="pkg-price">' +
        packagePriceHtml(p) +
        '</div><div class="pkg-sub">' +
        esc(p.subtitle || p.description || '') +
        '</div><div class="pkg-foot"><span class="status ' +
        (p.status === 'live' ? 'pub' : 'draft') +
        '">' +
        (p.status === 'live' ? '● Live' : '○ Draft') +
        '</span></div><div class="hub-card-actions">' +
        '<button type="button" class="hub-act hub-act-edit hub-act-sm" data-cpkg-edit="' +
        esc(p.id) +
        '">' +
        photoIcon('edit') +
        ' Edit</button>' +
        '<button type="button" class="hub-act hub-act-del hub-act-sm" data-cpkg-del="' +
        esc(p.id) +
        '">Delete</button></div></div></div>'
      );
    })
    .join('');
  bindCatPkgListUi();
}

function bindCatPkgListUi() {
  const list = el('catPkgList');
  if (!list) return;
  list.querySelectorAll('[data-cpkg-id]').forEach(function (card) {
    card.onclick = function (e) {
      if (e.target.closest('.hub-act')) return;
      startCatPackageWizard(card.getAttribute('data-cpkg-id'));
    };
  });
  list.querySelectorAll('[data-cpkg-edit]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      startCatPackageWizard(btn.getAttribute('data-cpkg-edit'));
    };
  });
  list.querySelectorAll('[data-cpkg-del]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      deleteCatPackage(btn.getAttribute('data-cpkg-del'));
    };
  });
  list.querySelectorAll('[data-cpkg-menu]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      const id = btn.getAttribute('data-cpkg-menu');
      if (confirm('Duplicate this package as a draft?')) duplicateCatPackage(id);
    };
  });
}

function renderCatIndividualFoodList() {
  const host = el('catIndividualFoodList');
  if (!host) return;
  const q = (store.cateringMenu.foodSearch || '').trim().toLowerCase();
  const items = individualFoodItems().filter(function (f) {
    if (!q) return true;
    return (
      String(f.name).toLowerCase().includes(q) ||
      String(f.subcatName || '').toLowerCase().includes(q)
    );
  });
  if (!items.length) {
    host.innerHTML =
      '<div class="hub-empty" style="margin:8px 16px"><div class="hub-empty-ico">🍽️</div><b>No individual items yet</b><p>Add biriyani, alfam, curries, appam, tea, coffee, and set per-plate rates.</p></div>';
    return;
  }
  host.innerHTML = items
    .map(function (f) {
      const mod = findFoodModule(f.moduleId);
      const emoji = f.imageEmoji || (mod && mod.emoji) || '🍽️';
      return (
        '<div class="svc-row-wrap" data-food-id="' +
        esc(f.id) +
        '"><div class="svc-row"><div class="svc-thumb" style="background:linear-gradient(145deg,#F97316,#EA580C)"><span style="font-size:22px">' +
        emoji +
        '</span></div><div class="svc-bd">' +
        foodDietLeadHtml(f.diet) +
        '<b>' +
        esc(f.name) +
        '</b><div class="svc-meta"><span class="svc-price-tag">' +
        foodPriceHtml(f) +
        '</span><span class="status ' +
        (f.status === 'active' ? 'pub' : 'draft') +
        '" style="margin:0;padding:4px 8px">' +
        (f.status === 'active' ? 'Live' : 'Draft') +
        '</span></div></div></div><div class="hub-card-actions">' +
        '<button type="button" class="hub-act hub-act-edit hub-act-sm" data-food-edit="' +
        esc(f.id) +
        '">' +
        photoIcon('edit') +
        ' Edit</button>' +
        '<button type="button" class="hub-act hub-act-del hub-act-sm" data-food-del="' +
        esc(f.id) +
        '">Delete</button></div></div>'
      );
    })
    .join('');
}

function renderCatFoodModuleList() {
  const host = el('catFoodModuleList');
  if (!host) return;
  const q = (catalogModuleSearch || '').trim().toLowerCase();
  host.innerHTML = FOOD_MODULES
    .filter(function (m) {
      if (!q) return true;
      if (m.name.toLowerCase().includes(q)) return true;
      return (store.cateringMenu.foodItems || []).some(function (f) {
        return f.moduleId === m.id && String(f.name).toLowerCase().includes(q);
      });
    })
    .map(function (m) {
      const n = countItemsInModule(m.id);
      return (
        '<button type="button" class="cat-mod-row" data-mod="' +
        esc(m.id) +
        '"><span class="cat-mod-thumb" style="background:' +
        m.gradient +
        '">' +
        m.emoji +
        '</span><span class="cat-mod-num">' +
        m.num +
        '</span><span class="cat-mod-name">' +
        esc(m.name) +
        (n ? '<small>' + n + ' on menu</small>' : '') +
        '</span><span class="cat-mod-chev">›</span></button>'
      );
    })
    .join('');
}

function bindCateringMenuHubUi() {
  const tabPkg = el('catTabPackages');
  const tabFood = el('catTabFoodItems');
  if (tabPkg) {
    tabPkg.onclick = function () {
      store.cateringMenu.hubTab = 'packages';
      saveStore();
      renderCateringMenuHub();
    };
  }
  if (tabFood) {
    tabFood.onclick = function () {
      store.cateringMenu.hubTab = 'food';
      saveStore();
      renderCateringMenuHub();
    };
  }
  const pkgSearch = el('catPkgSearch');
  if (pkgSearch) {
    pkgSearch.value = store.cateringMenu.pkgSearch || '';
    pkgSearch.oninput = function () {
      store.cateringMenu.pkgSearch = pkgSearch.value;
      renderCatPkgList();
    };
  }
  const foodSearch = el('catFoodSearch');
  if (foodSearch) {
    foodSearch.value = store.cateringMenu.foodSearch || '';
    foodSearch.oninput = function () {
      store.cateringMenu.foodSearch = foodSearch.value;
      renderCatIndividualFoodList();
    };
  }
  const addInd = el('catAddIndividualFoodBtn');
  if (addInd) {
    addInd.onclick = function () {
      openPickIndividualItem();
    };
  }
  const openCat = el('catOpenFullMenuCatalog');
  if (openCat) {
    openCat.onclick = function () {
      catalogModuleSearch = '';
      const si = el('catCatalogModuleSearch');
      if (si) si.value = '';
      renderCatFoodModuleList();
      show('catFullMenuCatalog');
    };
  }
  const indList = el('catIndividualFoodList');
  if (indList) {
    indList.querySelectorAll('[data-food-edit]').forEach(function (btn) {
      btn.onclick = function (e) {
        e.stopPropagation();
        openFoodItemForm(btn.getAttribute('data-food-edit'), null);
      };
    });
    indList.querySelectorAll('[data-food-del]').forEach(function (btn) {
      btn.onclick = function (e) {
        e.stopPropagation();
        deleteFoodItem(btn.getAttribute('data-food-del'));
      };
    });
    indList.querySelectorAll('.svc-row-wrap').forEach(function (row) {
      row.onclick = function (e) {
        if (e.target.closest('.hub-act')) return;
        openFoodItemForm(row.getAttribute('data-food-id'), null);
      };
    });
  }
  const sortBtn = el('catPkgSortBtn');
  if (sortBtn) {
    sortBtn.onclick = function () {
      const order = ['name', 'price', 'status'];
      const i = order.indexOf(store.cateringMenu.pkgSort || 'name');
      store.cateringMenu.pkgSort = order[(i + 1) % order.length];
      toast('Sort: ' + store.cateringMenu.pkgSort);
      saveStore();
      renderCatPkgList();
    };
  }
  const filters = el('catPkgFilters');
  if (filters) {
    filters.querySelectorAll('[data-cat-f]').forEach(function (btn) {
      btn.onclick = function () {
        store.cateringMenu.pkgFilter = btn.getAttribute('data-cat-f');
        saveStore();
        renderCateringMenuHub();
      };
    });
  }
  const catEv = el('catPkgCategoryFilters');
  if (catEv) {
    catEv.querySelectorAll('[data-cat-ev]').forEach(function (btn) {
      btn.onclick = function () {
        const id = btn.getAttribute('data-cat-ev');
        const cur = store.cateringMenu.pkgCategoryFilter || 'all';
        store.cateringMenu.pkgCategoryFilter = cur === id ? 'all' : id;
        saveStore();
        renderCateringMenuHub();
      };
    });
  }
  const hubMore = el('catHubMoreBtn');
  if (hubMore) {
    hubMore.onclick = function () {
      toast('Hub menu (demo)');
    };
  }
  const addPkg = el('catAddPackageBtn');
  if (addPkg) {
    addPkg.onclick = function () {
      startCatPackageWizard(null);
    };
  }
  bindCatPkgListUi();
  const modList = el('catFoodModuleList');
  if (modList) {
    modList.querySelectorAll('[data-mod]').forEach(function (row) {
      row.onclick = function () {
        openModulePicker(row.getAttribute('data-mod'), 'catalog');
      };
    });
  }
}

function deleteFoodItem(id) {
  const f = findFoodItem(id);
  if (!f) return;
  if (!confirm('Remove "' + f.name + '" from your individual menu?')) return;
  store.cateringMenu.foodItems = store.cateringMenu.foodItems.filter(function (x) {
    return x.id !== id;
  });
  saveStore();
  renderCateringMenuHub();
  toast('Item removed');
}

function openPickIndividualItem() {
  individualPickMk = null;
  individualPickSearch = '';
  const si = el('catPickIndividualSearch');
  if (si) si.value = '';
  renderPickIndividualBody();
  show('catPickIndividualItem');
}

function renderPickIndividualBody() {
  const body = el('catPickIndividualBody');
  const btn = el('catPickIndividualContinue');
  if (!body) return;
  const q = (individualPickSearch || '').trim().toLowerCase();
  const rows = buildIndividualPickerRows().filter(function (r) {
    if (!q) return true;
    return r.name.toLowerCase().includes(q) || r.section.toLowerCase().includes(q);
  });
  let html = '';
  let lastSec = '';
  rows.forEach(function (r) {
    if (r.section !== lastSec) {
      lastSec = r.section;
      html += '<p class="cat-indiv-sec">' + esc(r.section) + '</p>';
    }
    const on = individualPickMk === (r.masterKey || r.name);
    const onMenu = r.masterKey && isItemOnOwnerMenu(r.masterKey);
    html +=
      '<label class="cat-indiv-row' +
      (on ? ' on' : '') +
      '"><input type="radio" name="indivPick" value="' +
      esc(r.masterKey || r.name) +
      '"' +
      (on ? ' checked' : '') +
      '><span><b>' +
      esc(r.name) +
      '</b>' +
      (onMenu ? '<small>Already on menu — edit from list</small>' : '<small>Single item · set plate rates next</small>') +
      '</span></label>';
  });
  if (!html) html = '<div class="cat-pick-empty">No dishes match your search.</div>';
  body.innerHTML = html;
  if (btn) {
    btn.disabled = !individualPickMk;
    btn.style.opacity = individualPickMk ? '1' : '0.55';
  }
  body.querySelectorAll('input[name=indivPick]').forEach(function (inp) {
    inp.onchange = function () {
      individualPickMk = inp.value;
      renderPickIndividualBody();
    };
  });
}

function duplicateCatPackage(id) {
  const src = findCatPackage(id);
  if (!src) return;
  const copy = JSON.parse(JSON.stringify(src));
  copy.id = uid('cpkg');
  copy.name = src.name + ' (copy)';
  copy.status = 'draft';
  store.cateringMenu.catPackages.unshift(copy);
  saveStore();
  renderCateringMenuHub();
  toast('Package duplicated as draft');
}

function deleteCatPackage(id) {
  const p = findCatPackage(id);
  if (!p) return;
  if (!confirm('Delete package "' + p.name + '"?')) return;
  store.cateringMenu.catPackages = store.cateringMenu.catPackages.filter(function (x) {
    return x.id !== id;
  });
  saveStore();
  renderCateringMenuHub();
  toast('Package deleted');
}

function moduleCatalogItemCount(mod) {
  let n = 0;
  (mod.subcats || []).forEach(function (sc) {
    n += (sc.items || []).length;
  });
  return n;
}

function isItemOnOwnerMenu(masterKey) {
  return ownerHasMasterKey(masterKey);
}

function pickDietLabel(diet) {
  if (normalizeFoodDiet(diet) === 'non_veg') return { cls: 'non_veg', text: 'NV' };
  return { cls: 'veg', text: 'V' };
}

function modulePickMatchesSearch(itemName, query) {
  if (!query) return true;
  return String(itemName || '').toLowerCase().indexOf(query) >= 0;
}

function countModulePickPending() {
  return Object.keys(menuPickCtx.selected).filter(function (k) {
    if (!menuPickCtx.selected[k]) return false;
    if (menuPickCtx.mode === 'package') return true;
    return !isItemOnOwnerMenu(k);
  }).length;
}

function toggleModulePickKey(masterKey) {
  if (menuPickCtx.mode === 'catalog' && isItemOnOwnerMenu(masterKey)) {
    const existing = (store.cateringMenu.foodItems || []).find(function (f) {
      return f.masterKey === masterKey;
    });
    if (existing) openFoodItemForm(existing.id, masterKey);
    return;
  }
  if (menuPickCtx.selected[masterKey]) delete menuPickCtx.selected[masterKey];
  else menuPickCtx.selected[masterKey] = true;
  renderModulePickerBody();
}

function openModulePicker(moduleId, mode) {
  menuPickCtx = {
    mode: mode || 'catalog',
    moduleId: moduleId,
    selected: {},
    search: '',
    returnTo: mode === 'package' ? 'catPkgStep3' : 'menuPkg',
  };
  const mod = findFoodModule(moduleId);
  if (!mod) return;
  if (mode === 'package' && pkgWizard.draft) {
    (pkgWizard.draft.itemIds || []).forEach(function (fid) {
      const it = findFoodItem(fid);
      if (it && it.moduleId === moduleId && it.masterKey) menuPickCtx.selected[it.masterKey] = true;
    });
  }
  el('catModuleTitle').textContent =
    menuPickCtx.mode === 'package'
      ? packageModuleLabel(mod, pkgWizard.draft && pkgWizard.draft.dietType)
      : mod.name;
  const searchWrap = el('catModulePickSearchWrap');
  const searchInp = el('catModulePickSearch');
  const showSearch = moduleCatalogItemCount(mod) > 18;
  if (searchWrap) searchWrap.hidden = !showSearch;
  if (searchInp) {
    searchInp.value = '';
    searchInp.oninput = function () {
      menuPickCtx.search = (searchInp.value || '').trim().toLowerCase();
      renderModulePickerBody();
    };
  }
  renderModulePickerBody();
  show('catModulePick');
}

function ownerCustomDishesForModule(moduleId) {
  return (store.cateringMenu.foodItems || []).filter(function (f) {
    return f && f.custom && f.moduleId === moduleId && f.status !== 'archived';
  });
}

function findCatalogDishInModule(mod, name) {
  const q = String(name || '').trim().toLowerCase();
  if (!mod || !q) return null;
  let found = null;
  (mod.subcats || []).forEach(function (sc) {
    (sc.items || []).forEach(function (it) {
      if (!found && String(it.name || '').trim().toLowerCase() === q) found = it;
    });
  });
  return found;
}

function addOwnerCustomDish(mod, name, diet) {
  const clean = String(name || '').trim().replace(/\s+/g, ' ');
  if (!clean) {
    toast('Type the dish name');
    return;
  }
  const dietType = pkgWizard.draft && pkgWizard.draft.dietType;
  const want = diet === 'non_veg' ? 'non_veg' : 'veg';
  if (dietType === 'veg' && want === 'non_veg') {
    toast('A veg sadhya can add only a vegetarian dish');
    return;
  }
  const catalog = findCatalogDishInModule(mod, clean);
  if (catalog) {
    if (!dishAllowedOnPackage(catalog, dietType)) {
      toast('That dish is not part of this package');
      return;
    }
    menuPickCtx.selected[catalog.masterKey] = true;
    toast('Already in the list');
    renderModulePickerBody();
    return;
  }
  const existing = ownerCustomDishesForModule(mod.id).find(function (f) {
    return String(f.name || '').trim().toLowerCase() === clean.toLowerCase();
  });
  if (existing) {
    if (!dishAllowedOnPackage(existing, dietType)) {
      toast('That dish is not part of this package');
      return;
    }
    menuPickCtx.selected[existing.masterKey] = true;
    toast('Already in your dishes');
    renderModulePickerBody();
    return;
  }
  const slug = clean.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'dish';
  const item = {
    id: uid('food'),
    masterKey: 'custom::' + mod.id + '::' + slug + '-' + String(uid('d')).slice(-4),
    name: clean,
    moduleId: mod.id,
    subcatId: 'custom',
    subcatName: 'Your dishes',
    description: '',
    diet: want,
    custom: true,
    individualListing: false,
    pricingMode: 'per_person',
    unitLabel: 'plate',
    quoteOnly: false,
    status: 'draft',
    offerEnabled: false,
    discountPercent: '',
    slabs: defaultItemSlabs(),
    imageEmoji: mod.emoji || '🍽️',
  };
  store.cateringMenu.foodItems.push(item);
  menuPickCtx.selected[item.masterKey] = true;
  menuPickCtx.ownDiet = 'veg';
  saveStore();
  renderModulePickerBody();
  toast(clean + ' added');
}

function renderPackageOwnSection(mod, q) {
  if (menuPickCtx.mode !== 'package' || !pkgWizard.draft) return '';
  const dietType = pkgWizard.draft.dietType;
  const vegOnly = dietType === 'veg';
  if (!menuPickCtx.ownDiet) menuPickCtx.ownDiet = 'veg';
  if (vegOnly) menuPickCtx.ownDiet = 'veg';
  const custom = ownerCustomDishesForModule(mod.id).filter(function (it) {
    if (!dishAllowedOnPackage(it, dietType)) return false;
    return modulePickMatchesSearch(it.name, q);
  });
  let cells = custom
    .map(function (it) {
      const picked = !!menuPickCtx.selected[it.masterKey];
      const diet = pickDietLabel(it.diet);
      return (
        '<button type="button" class="cat-pick-cell' +
        (picked ? ' on' : '') +
        '" data-mk="' +
        esc(it.masterKey) +
        '"><span class="cat-pick-chk" aria-hidden="true">' +
        (picked ? '✓' : '') +
        '</span><span class="cat-pick-label"><span>' +
        esc(it.name) +
        '</span><span class="cat-pick-diet ' +
        diet.cls +
        '">' +
        diet.text +
        '</span></span></button>'
      );
    })
    .join('');
  const diets = vegOnly
    ? ''
    : '<div class="cat-own-diets"><button type="button" data-own-diet="veg"' +
      (menuPickCtx.ownDiet !== 'non_veg' ? ' class="on"' : '') +
      '>Veg</button><button type="button" data-own-diet="non_veg"' +
      (menuPickCtx.ownDiet === 'non_veg' ? ' class="on"' : '') +
      '>Non-veg</button></div>';
  return (
    '<div class="cat-pick-own"><div class="cat-pick-section-hd"><b>Add your own</b></div><p class="cat-pkg-name-hint">Not in the list? Add it to this group.</p>' +
    (cells ? '<div class="cat-pick-grid">' + cells + '</div>' : '') +
    diets +
    '<div class="cat-own-row"><input id="catOwnDishName" type="text" maxlength="60" placeholder="Dish name" autocomplete="off"><button type="button" class="cat-own-add" id="catOwnDishAdd">Add</button></div></div>'
  );
}

function renderModulePickerBody() {
  const mod = findFoodModule(menuPickCtx.moduleId);
  const body = el('catModulePickBody');
  const meta = el('catModulePickMeta');
  if (!mod || !body) return;
  const q = menuPickCtx.search || '';
  const total = moduleCatalogItemCount(mod);
  let visible = 0;
  let html = '';
  mod.subcats.forEach(function (sc, scIdx) {
    const visibleItems = (sc.items || []).filter(function (it) {
      if (
        menuPickCtx.mode === 'package' &&
        !dishAllowedOnPackage(it, pkgWizard.draft && pkgWizard.draft.dietType)
      ) {
        return false;
      }
      return modulePickMatchesSearch(it.name, q);
    });
    if (!visibleItems.length) return;
    visible += visibleItems.length;
    const sectionName =
      menuPickCtx.mode === 'package' &&
      pkgWizard.draft &&
      pkgWizard.draft.dietType === 'veg' &&
      mod.id === 'g03' &&
      sc.id === 'rice'
        ? 'Rice'
        : sc.name;
    html +=
      '<div class="cat-pick-section" data-sc-idx="' +
      scIdx +
      '"><div class="cat-pick-section-hd"><b>' +
      esc(sectionName) +
      '</b><div class="cat-pick-section-actions">' +
      '<button type="button" data-pick-all="' +
      scIdx +
      '">Select all</button>' +
      '<button type="button" data-pick-none="' +
      scIdx +
      '">Clear</button></div></div><div class="cat-pick-grid">';
    visibleItems.forEach(function (it) {
      const onMenuItem = isItemOnOwnerMenu(it.masterKey);
      const picked =
        menuPickCtx.mode === 'package'
          ? !!menuPickCtx.selected[it.masterKey]
          : onMenuItem || !!menuPickCtx.selected[it.masterKey];
      const diet = pickDietLabel(it.diet);
      html +=
        '<button type="button" class="cat-pick-cell' +
        (picked ? ' on' : '') +
        (onMenuItem && menuPickCtx.mode === 'catalog' ? ' on-menu' : '') +
        '" data-mk="' +
        esc(it.masterKey) +
        '"><span class="cat-pick-chk" aria-hidden="true">' +
        (picked ? '✓' : '') +
        '</span><span class="cat-pick-label"><span>' +
        esc(it.name) +
        '</span>' +
        (onMenuItem && menuPickCtx.mode === 'catalog' ? '<small>On menu · tap to edit</small>' : '') +
        '<span class="cat-pick-diet ' +
        diet.cls +
        '">' +
        diet.text +
        '</span></span></button>';
    });
    html += '</div></div>';
  });
  const vegOnly =
    menuPickCtx.mode === 'package' && pkgWizard.draft && pkgWizard.draft.dietType === 'veg';
  if (!html && q) {
    html = '<div class="cat-pick-empty">No dishes match your search.</div>';
  } else if (!html && vegOnly) {
    html = '<div class="cat-pick-empty">No vegetarian dishes in this group.</div>';
  }
  html += renderPackageOwnSection(mod, q);
  body.innerHTML = html;
  if (meta) {
    const pending = countModulePickPending();
    const lead = vegOnly
      ? visible + ' vegetarian dishes' + (q ? ' shown' : '')
      : total + ' dishes in catalogue' + (q ? ' · ' + visible + ' shown' : '');
    meta.textContent =
      lead +
      (menuPickCtx.mode === 'catalog' ? ' · ' + pending + ' to add' : ' · ' + pending + ' selected');
  }
  syncModulePickCount();
  body.querySelectorAll('.cat-pick-cell').forEach(function (cell) {
    cell.onclick = function () {
      toggleModulePickKey(cell.getAttribute('data-mk'));
    };
  });
  body.querySelectorAll('[data-pick-all]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      const idx = +btn.getAttribute('data-pick-all');
      const sc = mod.subcats[idx];
      if (!sc) return;
      (sc.items || []).forEach(function (it) {
        if (
          menuPickCtx.mode === 'package' &&
          !dishAllowedOnPackage(it, pkgWizard.draft && pkgWizard.draft.dietType)
        ) {
          return;
        }
        if (!modulePickMatchesSearch(it.name, q)) return;
        if (menuPickCtx.mode === 'catalog' && isItemOnOwnerMenu(it.masterKey)) return;
        menuPickCtx.selected[it.masterKey] = true;
      });
      renderModulePickerBody();
    };
  });
  body.querySelectorAll('[data-pick-none]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      const idx = +btn.getAttribute('data-pick-none');
      const sc = mod.subcats[idx];
      if (!sc) return;
      (sc.items || []).forEach(function (it) {
        delete menuPickCtx.selected[it.masterKey];
      });
      renderModulePickerBody();
    };
  });
  body.querySelectorAll('[data-own-diet]').forEach(function (btn) {
    btn.onclick = function () {
      menuPickCtx.ownDiet = btn.getAttribute('data-own-diet') === 'non_veg' ? 'non_veg' : 'veg';
      const typed = el('catOwnDishName');
      const keep = typed ? typed.value : '';
      renderModulePickerBody();
      const again = el('catOwnDishName');
      if (again) {
        again.value = keep;
        again.focus();
      }
    };
  });
  const ownAdd = el('catOwnDishAdd');
  if (ownAdd) {
    ownAdd.onclick = function () {
      const input = el('catOwnDishName');
      addOwnerCustomDish(mod, input ? input.value : '', menuPickCtx.ownDiet || 'veg');
    };
  }
  const ownName = el('catOwnDishName');
  if (ownName) {
    ownName.onkeydown = function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        addOwnerCustomDish(mod, ownName.value, menuPickCtx.ownDiet || 'veg');
      }
    };
  }
}

function syncModulePickCount() {
  const n = countModulePickPending();
  const btn = el('catModulePickSave');
  if (!btn) return;
  if (menuPickCtx.mode === 'package') btn.textContent = 'Apply (' + n + ')';
  else btn.textContent = 'Add Selected Items (' + n + ')';
  btn.disabled = n === 0;
  btn.style.opacity = n === 0 ? '0.55' : '1';
}

function commitModulePicker() {
  const mod = findFoodModule(menuPickCtx.moduleId);
  if (!mod) return;
  const keys = Object.keys(menuPickCtx.selected).filter(function (k) {
    return menuPickCtx.selected[k];
  });
  if (menuPickCtx.mode === 'package') {
    if (!pkgWizard.draft) return;
    const existing = pkgWizard.draft.itemIds || [];
    const keepOther = existing.filter(function (fid) {
      const it = findFoodItem(fid);
      return it && it.moduleId !== menuPickCtx.moduleId;
    });
    const newIds = [];
    keys.forEach(function (mk) {
      let item = (store.cateringMenu.foodItems || []).find(function (f) {
        return f.masterKey === mk;
      });
      const master = findMasterItem(mk);
      const candidate = master ? master.item : item;
      if (candidate && !dishAllowedOnPackage(candidate, pkgWizard.draft.dietType)) return;
      if (!item && !master) return;
      if (!item) {
        item = createFoodItemFromMaster(mk, 'draft');
        store.cateringMenu.foodItems.push(item);
      }
      if (newIds.indexOf(item.id) < 0) newIds.push(item.id);
    });
    pkgWizard.draft.itemIds = keepOther.concat(newIds);
    saveStore();
    show('catPkgStep3');
    renderCatPkgStep3Menu();
    toast('Module items updated');
    return;
  }
  let added = 0;
  keys.forEach(function (mk) {
    if (ownerHasMasterKey(mk)) return;
    const item = createFoodItemFromMaster(mk, 'draft', false);
    store.cateringMenu.foodItems.push(item);
    added += 1;
  });
  saveStore();
  show(menuPickCtx.returnTo || 'menuPkg');
  store.cateringMenu.hubTab = 'food';
  renderCateringMenuHub();
  toast(added ? added + ' item(s) added — set pricing to go live' : 'No new items selected');
}

function createFoodItemFromMaster(masterKey, status, individualListing) {
  let hit = findMasterItem(masterKey);
  if (!hit && masterKey) {
    const named = findCatalogItemByName(masterKey);
    if (named) hit = named;
  }
  if (!hit) {
    const row = buildIndividualPickerRows().find(function (r) {
      return r.masterKey === masterKey || r.name === masterKey;
    });
    const out = {
      id: uid('food'),
      masterKey: masterKey,
      name: row ? row.name : 'Custom item',
      moduleId: row ? row.moduleId : menuPickCtx.moduleId,
      subcatId: 'custom',
      subcatName: 'Custom',
      description: '',
      diet: row ? row.diet : 'veg',
      pricingMode: 'per_person',
      unitLabel: 'plate',
      quoteOnly: false,
      status: status || 'draft',
      offerEnabled: false,
      discountPercent: '',
      slabs: defaultItemSlabs(),
      imageEmoji: '🍽️',
    };
    if (individualListing === true) out.individualListing = true;
    else if (individualListing === false) out.individualListing = false;
    return out;
  }
  const out = {
    id: uid('food'),
    masterKey: masterKey,
    name: hit.item.name,
    moduleId: hit.module.id,
    subcatId: hit.subcat.id,
    subcatName: hit.subcat.name,
    description: defaultFoodDescription(hit.item.name, hit.item.diet),
    diet: hit.item.diet,
    pricingMode: 'per_person',
    unitLabel: 'plate',
    quoteOnly: false,
    status: status || 'draft',
    offerEnabled: false,
    discountPercent: '',
    slabs: defaultItemSlabs(),
    imageEmoji: hit.module.emoji,
  };
  if (individualListing === true) out.individualListing = true;
  else if (individualListing === false) out.individualListing = false;
  return out;
}

function continueIndividualPick() {
  if (!individualPickMk) return;
  const pickKey = individualPickMk;
  let existing = (store.cateringMenu.foodItems || []).find(function (f) {
    return f.masterKey === pickKey;
  });
  if (!existing) {
    const byName = buildIndividualPickerRows().find(function (r) {
      return (r.masterKey || r.name) === pickKey;
    });
    if (byName) {
      existing = (store.cateringMenu.foodItems || []).find(function (f) {
        return String(f.name).toLowerCase() === String(byName.name).toLowerCase();
      });
    }
  }
  if (existing) {
    openFoodItemForm(existing.id, null);
    return;
  }
  openFoodItemForm(null, pickKey, { individual: true });
}

function defaultFoodDescription(name, diet) {
  if (/soup/i.test(name)) {
    return diet === 'non_veg' ? 'Mild and flavorful ' + name.toLowerCase() + '.' : 'Comforting vegetarian ' + name.toLowerCase() + '.';
  }
  return '';
}

function openFoodItemForm(foodId, masterKey, opts) {
  opts = opts || {};
  let item = foodId ? findFoodItem(foodId) : null;
  if (!item && masterKey) {
    item = (store.cateringMenu.foodItems || []).find(function (f) {
      return f.masterKey === masterKey;
    });
  }
  if (!item && masterKey) {
    item = createFoodItemFromMaster(masterKey, 'draft', opts.individual ? true : undefined);
    if (opts.individual) item.individualListing = true;
  }
  if (!item) {
    toast('Select an item first');
    return;
  }
  foodFormDraft = JSON.parse(JSON.stringify(item));
  renderFoodItemForm();
  show('catFoodItemForm');
}

/** Keep catalogue module/subcat on the record (packages, search) without showing them on the form. */
function ensureFoodFormCatalogMeta() {
  const d = foodFormDraft;
  if (!d) return;
  if (d.masterKey) {
    const hit = findMasterItem(d.masterKey);
    if (hit) {
      d.moduleId = hit.module.id;
      d.subcatId = hit.subcat.id;
      d.subcatName = hit.subcat.name;
      if (!d.diet) d.diet = hit.item.diet;
      return;
    }
  }
  const named = findCatalogItemByName(d.name);
  if (named) {
    d.moduleId = named.module.id;
    d.subcatId = named.subcat.id;
    d.subcatName = named.subcat.name;
    if (named.item.masterKey) d.masterKey = d.masterKey || named.item.masterKey;
    if (!d.diet) d.diet = named.item.diet;
  }
}

function resolveRateMode(record, slabKey) {
  if (!record) return 'tiered';
  if (record.rateMode === 'flat' || record.rateMode === 'tiered') return record.rateMode;
  const slabs = record[slabKey] || [];
  return slabs.length === 1 ? 'flat' : 'tiered';
}

function applyRateMode(record, slabKey, mode, defaultSlabsFn) {
  const slabs = record[slabKey] || [];
  if (mode === 'flat') {
    if (slabs.length > 1) record._tieredBackup = JSON.parse(JSON.stringify(slabs));
    const price = slabs.length ? +slabs[0].price || 0 : 0;
    record.rateMode = 'flat';
    record[slabKey] = [{ from: 1, to: 500, price: price }];
    return;
  }
  record.rateMode = 'tiered';
  if (record._tieredBackup && record._tieredBackup.length > 1) {
    record[slabKey] = JSON.parse(JSON.stringify(record._tieredBackup));
    return;
  }
  if (slabs.length > 1) return;
  const defs = defaultSlabsFn();
  if (slabs.length === 1 && +slabs[0].price) defs[0].price = +slabs[0].price;
  record[slabKey] = defs;
}

function clearRateModeBackup(record) {
  if (record) delete record._tieredBackup;
}

function renderFoodItemForm() {
  const d = foodFormDraft;
  if (!d) return;
  d.pricingMode = 'per_person';
  d.unitLabel = 'plate';
  d.diet = normalizeFoodDiet(d.diet);
  const mod = findFoodModule(d.moduleId);
  el('catFoodFormTitle').textContent = d.id && findFoodItem(d.id) ? 'Edit Food Item' : 'Add Food Item';
  el('catFoodImgEmoji').textContent = d.imageEmoji || (mod && mod.emoji) || '🍽️';
  el('catFoodName').value = d.name || '';
  ensureFoodFormCatalogMeta();
  const modAfter = findFoodModule(d.moduleId);
  if (modAfter) el('catFoodImgEmoji').textContent = d.imageEmoji || modAfter.emoji || '🍽️';
  el('catFoodDesc').value = d.description || '';
  el('catFoodDietVeg').checked = d.diet === 'veg';
  el('catFoodDietNon').checked = d.diet === 'non_veg';
  renderFoodPricing();
}

function renderFoodOffer() {
  const d = foodFormDraft;
  if (!d) return;
  const box = el('catFoodOfferBox');
  const on = el('catFoodOfferOn');
  const fields = el('catFoodOfferFields');
  const pct = el('catFoodOfferPercent');
  if (on) on.checked = !!d.offerEnabled;
  if (box) box.classList.toggle('on', !!d.offerEnabled);
  if (fields) fields.hidden = !d.offerEnabled;
  if (pct && document.activeElement !== pct) {
    const v = d.discountPercent;
    pct.value = v === '' || v == null ? '' : v;
  }
  paintFoodOfferPrices();
}

function paintFoodOfferPrices() {
  const d = foodFormDraft;
  const pct = d ? offerPercentOf(d) : 0;
  document.querySelectorAll('#catFoodSlabs .cat-slab-offer').forEach(function (slot) {
    const row = slot.closest('.cat-slab-row');
    const priceEl = row && row.querySelector('.slab-price');
    const price = priceEl ? +priceEl.value || 0 : 0;
    slot.innerHTML = pct ? offerPriceBitsHtml(price, pct) : '';
  });
  const flatSlot = el('catFoodFlatOffer');
  if (flatSlot) {
    const priceEl = el('catFoodFlatPrice');
    const show = !!(pct && d && d.rateMode === 'flat');
    flatSlot.hidden = !show;
    flatSlot.innerHTML = show ? offerPriceBitsHtml(priceEl ? +priceEl.value || 0 : 0, pct) : '';
  }
}

function renderFoodPricing() {
  const d = foodFormDraft;
  if (!d) return;
  if (!d.slabs || !d.slabs.length) d.slabs = defaultItemSlabs();
  if (!d.rateMode) d.rateMode = resolveRateMode(d, 'slabs');
  const flat = d.rateMode === 'flat';
  const flatRadio = el('catFoodRateFlat');
  const tierRadio = el('catFoodRateTiered');
  if (flatRadio) flatRadio.checked = flat;
  if (tierRadio) tierRadio.checked = !flat;
  const flatWrap = el('catFoodFlatWrap');
  const tierWrap = el('catFoodTieredWrap');
  if (flatWrap) flatWrap.hidden = !flat;
  if (tierWrap) tierWrap.hidden = flat;
  if (flat) {
    if (d.slabs.length !== 1) {
      d.slabs = [{ from: 1, to: 500, price: +d.slabs[0].price || 0 }];
    }
    const price = el('catFoodFlatPrice');
    if (price) price.value = d.slabs[0].price;
    renderFoodOffer();
    return;
  }
  renderSlabTable(
    'catFoodSlabs',
    d.slabs,
    function (slabs) {
      foodFormDraft.slabs = slabs;
    },
    {
      priceHeader: 'Price per plate (₹)',
      afterChange: function () {
        paintFoodOfferPrices();
      },
    }
  );
  renderFoodOffer();
}

function normalizePackageGuestSlabs(slabs) {
  const defs = defaultPackageGuestSlabs();
  if (!slabs || !slabs.length) return defs.slice();
  return slabs.map(function (s, i) {
    const d = defs[i] || defs[defs.length - 1];
    return {
      from: +s.from > 0 ? +s.from : d.from,
      to: +s.to > 0 ? +s.to : d.to,
      price: +s.price >= 0 && s.price !== '' ? +s.price : d.price,
    };
  });
}

function renderSlabTable(hostId, slabs, onChange, tableOpts) {
  tableOpts = tableOpts || {};
  const host = el(hostId);
  if (!host) return;
  const priceHdr = tableOpts.priceHeader || 'Price per plate (₹)';
  const rows = (slabs || []).map(function (s, idx) {
    return (
      '<div class="cat-slab-row" data-idx="' +
      idx +
      '"><label class="cat-slab-count"><input type="number" class="slab-from" value="' +
      esc(s.from) +
      '" min="1" aria-label="From guests"><span>guests</span></label><label class="cat-slab-count"><input type="number" class="slab-to" value="' +
      esc(s.to) +
      '" min="1" aria-label="To guests"><span>guests</span></label><div class="cat-slab-price-col"><div class="cat-slab-price-wrap"><span class="cat-slab-inr" aria-hidden="true">₹</span><input type="number" class="slab-price" value="' +
      esc(s.price) +
      '" min="0" aria-label="Price per plate"></div><div class="cat-slab-offer"></div></div><button type="button" class="cat-slab-rm" data-rm="' +
      idx +
      '">🗑</button></div>'
    );
  });
  host.innerHTML =
    '<div class="cat-slab-hd"><span>From</span><span>To</span><span>' +
    esc(priceHdr) +
    '</span><span></span></div>' +
    rows.join('');
  function read() {
    const next = [];
    host.querySelectorAll('.cat-slab-row').forEach(function (row) {
      next.push({
        from: +row.querySelector('.slab-from').value || 0,
        to: +row.querySelector('.slab-to').value || 0,
        price: +row.querySelector('.slab-price').value || 0,
      });
    });
    onChange(next);
    if (tableOpts.afterChange) tableOpts.afterChange(next);
  }
  host.querySelectorAll('input').forEach(function (inp) {
    inp.oninput = read;
  });
  host.querySelectorAll('.cat-slab-rm').forEach(function (btn) {
    btn.onclick = function () {
      const i = +btn.getAttribute('data-rm');
      const next = (slabs || []).slice();
      next.splice(i, 1);
      onChange(next);
      renderSlabTable(hostId, next, onChange, tableOpts);
    };
  });
}

function bindFoodItemFormUi() {
  const chImg = el('catFoodChangeImg');
  if (chImg) {
    chImg.onclick = function () {
      const emojis = ['🍲', '🥗', '🍛', '🍚', '🥤', '🍮', '🫓', '🥘'];
      const i = Math.floor(Math.random() * emojis.length);
      foodFormDraft.imageEmoji = emojis[i];
      el('catFoodImgEmoji').textContent = emojis[i];
      toast('Image updated (demo)');
    };
  }
  bindClick('catFoodAddSlab', function () {
    if (!foodFormDraft || foodFormDraft.rateMode === 'flat') return;
    const slabs = foodFormDraft.slabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 1;
    slabs.push({ from: from, to: from + 24, price: last ? last.price : 50 });
    foodFormDraft.slabs = slabs;
    foodFormDraft.rateMode = 'tiered';
    renderFoodPricing();
  });
  bindClick('catFoodSaveDraft', function () {
    saveFoodItemForm('draft');
  });
  bindClick('catFoodSave', function () {
    saveFoodItemForm('active');
  });
  bindClick('catFoodBack', function () {
    show('menuPkg');
    renderCateringMenuHub();
  });
  bindOnChange('catFoodRateFlat', function () {
    if (!foodFormDraft) return;
    applyRateMode(foodFormDraft, 'slabs', 'flat', defaultItemSlabs);
    renderFoodPricing();
  });
  bindOnChange('catFoodRateTiered', function () {
    if (!foodFormDraft) return;
    applyRateMode(foodFormDraft, 'slabs', 'tiered', defaultItemSlabs);
    renderFoodPricing();
  });
  bindOnInput('catFoodFlatPrice', function () {
    if (!foodFormDraft) return;
    const price = el('catFoodFlatPrice');
    foodFormDraft.rateMode = 'flat';
    foodFormDraft.slabs = [{ from: 1, to: 500, price: price ? +price.value || 0 : 0 }];
    paintFoodOfferPrices();
  });
  bindOnChange('catFoodOfferOn', function () {
    if (!foodFormDraft) return;
    const on = el('catFoodOfferOn');
    foodFormDraft.offerEnabled = !!(on && on.checked);
    renderFoodOffer();
    if (foodFormDraft.offerEnabled) {
      const pct = el('catFoodOfferPercent');
      if (pct) pct.focus();
    }
  });
  bindOnInput('catFoodOfferPercent', function () {
    if (!foodFormDraft) return;
    const pct = el('catFoodOfferPercent');
    const raw = pct ? pct.value : '';
    foodFormDraft.offerEnabled = true;
    foodFormDraft.discountPercent = raw === '' ? '' : Math.round(+raw);
    paintFoodOfferPrices();
  });
}

function saveFoodItemForm(status) {
  if (!foodFormDraft) return;
  foodFormDraft.name = (el('catFoodName').value || '').trim();
  if (!foodFormDraft.name) {
    toast('Food item name is required');
    return;
  }
  if (el('catFoodDietNon').checked) foodFormDraft.diet = 'non_veg';
  else foodFormDraft.diet = 'veg';
  foodFormDraft.description = (el('catFoodDesc').value || '').trim();
  foodFormDraft.quoteOnly = false;
  foodFormDraft.pricingMode = 'per_person';
  foodFormDraft.unitLabel = 'plate';
  ensureFoodFormCatalogMeta();
  if (foodFormDraft.individualListing === undefined && !(store.cateringMenu.foodItems || []).some(function (f) {
    return f.id === foodFormDraft.id;
  })) {
    foodFormDraft.individualListing = true;
  }
  if (!foodFormDraft.slabs || !foodFormDraft.slabs.length) {
    toast('Add at least one pricing slab');
    return;
  }
  const offerOn = el('catFoodOfferOn');
  const offerPct = el('catFoodOfferPercent');
  if (offerOn) foodFormDraft.offerEnabled = !!offerOn.checked;
  if (foodFormDraft.offerEnabled && offerPct) {
    foodFormDraft.discountPercent = offerPct.value === '' ? '' : Math.round(+offerPct.value);
  }
  if (foodFormDraft.offerEnabled && !offerPercentOf(foodFormDraft)) {
    toast('Enter a discount from 1 to 90 percent');
    return;
  }
  const pct = offerPercentOf(foodFormDraft);
  foodFormDraft.discountPercent = pct || '';
  if (!pct) foodFormDraft.offerEnabled = false;
  clearRateModeBackup(foodFormDraft);
  foodFormDraft.status = status;
  const idx = (store.cateringMenu.foodItems || []).findIndex(function (f) {
    return f.id === foodFormDraft.id || (foodFormDraft.masterKey && f.masterKey === foodFormDraft.masterKey);
  });
  if (idx >= 0) store.cateringMenu.foodItems[idx] = JSON.parse(JSON.stringify(foodFormDraft));
  else store.cateringMenu.foodItems.push(JSON.parse(JSON.stringify(foodFormDraft)));
  saveStore();
  toast(status === 'active' ? 'Food item saved' : 'Saved as draft');
  show('menuPkg');
  store.cateringMenu.hubTab = 'food';
  renderCateringMenuHub();
}

function newPkgDraft() {
  return {
    name: '',
    level: 'Basic',
    packageCategory: 'wedding',
    customerTitle: '',
    description: '',
    status: 'live',
    pricingMode: 'per_person',
    rateMode: 'tiered',
    guestSlabs: defaultPackageGuestSlabs(),
    itemIds: [],
    imageEmoji: '🍽️',
    dietType: '',
    serveAtTable: true,
    serveAtCounter: false,
    offerEnabled: false,
    discountPercent: '',
    listPrice: 0,
    price: 0,
    subtitle: '',
  };
}

function startCatPackageWizard(editId) {
  pkgWizard.editId = editId || null;
  const src = editId ? findCatPackage(editId) : null;
  pkgWizard.draft = src ? JSON.parse(JSON.stringify(src)) : newPkgDraft();
  if (!pkgWizard.draft.packageCategory) pkgWizard.draft.packageCategory = 'wedding';
  normalizePackageMenu(pkgWizard.draft);
  pkgWizard.step = 1;
  renderCatPkgStep1();
  show('catPkgStep1');
}

function renderCatPkgStep1() {
  const d = pkgWizard.draft;
  if (!d) return;
  const cat = d.packageCategory || 'wedding';
  const grid = el('catPkgEventCatGrid');
  if (!grid) return;
  grid.innerHTML = PKG_EVENT_CATEGORIES.map(function (c) {
    const on = cat === c.id;
    return (
      '<button type="button" class="cat-pkg-ev-card' +
      (on ? ' on' : '') +
      '" data-ev-cat="' +
      esc(c.id) +
      '"><span class="cat-pkg-ev-chk">' +
      (on ? '✓' : '') +
      '</span><span class="cat-pkg-ev-ico" aria-hidden="true">' +
      c.icon +
      '</span><b>' +
      esc(c.label) +
      '</b><small>' +
      esc(c.sub) +
      '</small></button>'
    );
  }).join('');
  grid.querySelectorAll('[data-ev-cat]').forEach(function (btn) {
    btn.onclick = function () {
      pkgWizard.draft.packageCategory = btn.getAttribute('data-ev-cat');
      renderCatPkgStep1();
    };
  });
}

function renderCatPkgTypeSeg(level) {
  const host = el('catPkgTypeSeg');
  if (!host) return;
  host.innerHTML = CAT_PKG_LEVELS.map(function (l) {
    return (
      '<button type="button" class="cat-pkg-type-btn' +
      (l === level ? ' on' : '') +
      '" data-lvl="' +
      esc(l) +
      '">' +
      esc(l) +
      '</button>'
    );
  }).join('');
  host.querySelectorAll('.cat-pkg-type-btn').forEach(function (btn) {
    btn.onclick = function () {
      pkgWizard.draft.level = btn.getAttribute('data-lvl');
      renderCatPkgTypeSeg(pkgWizard.draft.level);
      updatePkgCustomerPreview();
    };
  });
}

function renderCatPkgStep2() {
  const d = pkgWizard.draft;
  if (!d) return;
  const banner = el('catPkgCatBannerLabel');
  if (banner) banner.textContent = pkgCategoryLabel(d.packageCategory);
  renderCatPkgTypeSeg(d.level || 'Basic');
  renderCatPkgDietChoice();
  const nameEl = el('catPkgName');
  const descEl = el('catPkgDesc');
  if (nameEl) nameEl.value = d.name || '';
  if (descEl) descEl.value = d.description || '';
  updatePkgCustomerPreview();
}

function normalizePackageMenu(d) {
  if (!d) return;
  delete d.menuTemplate;
  delete d.serveTouched;
  if (packageIsSadhya(d.dietType)) {
    d.serveAtTable = true;
    d.serveAtCounter = false;
  } else if (d.dietType === 'mixed') {
    if (!d.serveAtTable && !d.serveAtCounter) {
      d.serveAtTable = true;
      d.serveAtCounter = true;
    }
  } else if (!d.serveAtTable && !d.serveAtCounter) {
    d.serveAtTable = true;
    d.serveAtCounter = false;
  }
  dropDishesOutsidePackageDiet(d);
}
function packageServiceLabel(d) {
  d = d || {};
  const table = !!d.serveAtTable;
  const counter = !!d.serveAtCounter;
  if (table && counter) return 'Buffet counter and served at the table';
  if (counter) return 'Buffet counter';
  return 'Served at the table';
}
function moduleMatchesPackageSearch(mod, q) {
  if (!q) return true;
  const dietType = pkgWizard.draft && pkgWizard.draft.dietType;
  if (packageModuleLabel(mod, dietType).toLowerCase().indexOf(q) >= 0) return true;
  let hit = false;
  ownerCustomDishesForModule(mod.id).forEach(function (it) {
    if (hit || !dishAllowedOnPackage(it, dietType)) return;
    if (String(it.name || '').toLowerCase().indexOf(q) >= 0) hit = true;
  });
  if (hit) return true;
  (mod.subcats || []).forEach(function (sc) {
    (sc.items || []).forEach(function (it) {
      if (hit || !dishAllowedOnPackage(it, dietType)) return;
      if (String(it.name || '').toLowerCase().indexOf(q) >= 0) hit = true;
    });
  });
  return hit;
}
function moduleHasAllowedPackageDishes(mod) {
  const dietType = pkgWizard.draft && pkgWizard.draft.dietType;
  let ok = false;
  (mod.subcats || []).forEach(function (sc) {
    (sc.items || []).forEach(function (it) {
      if (dishAllowedOnPackage(it, dietType)) ok = true;
    });
  });
  return ok;
}
function renderCatPkgStep3Menu() {
  const d = pkgWizard.draft;
  if (!d) return;
  normalizePackageMenu(d);
  const q = (el('catPkgItemSearch') && el('catPkgItemSearch').value || '').trim().toLowerCase();
  const list = el('catPkgModulePick');
  if (!list) return;
  const sadhya = packageIsSadhya(d.dietType);
  const menuHint = el('catPkgMenuHint');
  const serveHint = el('catPkgServeHint');
  if (menuHint) {
    if (d.dietType === 'veg') {
      menuHint.textContent =
        'Vegetarian dishes only. Kerala curries, thoran, rice, sides and payasam are the sadhya dishes.';
    } else if (d.dietType === 'nonveg_sadhya') {
      menuHint.textContent = 'Sadhya dishes, plus fish, chicken, beef and egg. Served at the table.';
    } else {
      menuHint.textContent = 'Pick vegetarian and non-veg dishes for the buffet.';
    }
  }
  if (serveHint) {
    serveHint.textContent = sadhya
      ? 'Served at the table.'
      : 'How is this food served? Select one or both.';
  }
  const serveHost = el('catPkgServeChips');
  if (serveHost) {
    serveHost.hidden = sadhya;
    if (sadhya) serveHost.innerHTML = '';
    if (!sadhya) {
      const options = [
        { id: 'counter', label: 'Buffet counter', on: !!d.serveAtCounter },
        { id: 'table', label: 'Served at the table', on: !!d.serveAtTable },
      ];
      serveHost.innerHTML = options
        .map(function (o) {
          return (
            '<button type="button" class="cat-pkg-type-btn' +
            (o.on ? ' on' : '') +
            '" data-serve="' +
            o.id +
            '">' +
            esc(o.label) +
            '</button>'
          );
        })
        .join('');
      serveHost.querySelectorAll('[data-serve]').forEach(function (btn) {
        btn.onclick = function () {
          const which = btn.getAttribute('data-serve');
          if (which === 'counter') pkgWizard.draft.serveAtCounter = !pkgWizard.draft.serveAtCounter;
          else pkgWizard.draft.serveAtTable = !pkgWizard.draft.serveAtTable;
          if (!pkgWizard.draft.serveAtCounter && !pkgWizard.draft.serveAtTable) {
            if (which === 'counter') pkgWizard.draft.serveAtCounter = true;
            else pkgWizard.draft.serveAtTable = true;
            toast('Choose at least one way to serve');
          }
          renderCatPkgStep3Menu();
        };
      });
    }
  }
  const summary = el('catPkgDietSummary');
  const selected = (d.itemIds || []).length;
  if (summary) {
    const chip = packageDietChipHtml(d.dietType);
    summary.innerHTML = chip ? chip + ' <span>' + selected + ' dishes selected</span>' : '';
  }
  list.innerHTML = FOOD_MODULES.filter(function (m) {
    if (!moduleHasAllowedPackageDishes(m)) return false;
    return moduleMatchesPackageSearch(m, q);
  })
    .map(function (m) {
      const n = countPkgItemsInModule(d, m.id);
      return (
        '<button type="button" class="cat-menu-step-row' +
        (n > 0 ? ' has-items' : '') +
        '" data-pkg-mod="' +
        esc(m.id) +
        '"><span class="cat-mod-thumb sm" style="background:' +
        m.gradient +
        '">' +
        m.emoji +
        '</span><span><b>' +
        esc(packageModuleLabel(m, d.dietType)) +
        '</b> <span class="cat-mod-count">(' +
        n +
        ')</span></span><span class="cat-mod-chev">›</span></button>'
      );
    })
    .join('');
  list.querySelectorAll('[data-pkg-mod]').forEach(function (row) {
    row.onclick = function () {
      openModulePicker(row.getAttribute('data-pkg-mod'), 'package');
    };
  });
}

function goCatPkgStep(step) {
  pkgWizard.step = step;
  if (step === 1) {
    renderCatPkgStep1();
    show('catPkgStep1');
  } else if (step === 2) {
    renderCatPkgStep2();
    show('catPkgStep2');
  } else if (step === 3) {
    renderCatPkgStep3Menu();
    show('catPkgStep3');
  }
}

function bindCatPkgCreateUi() {
  bindClick('catPkgStep1Back', function () {
    show('menuPkg');
    renderCateringMenuHub();
  });
  bindClick('catPkgStep1Next', function () {
    if (!pkgWizard.draft.packageCategory) {
      toast('Select a package category');
      return;
    }
    goCatPkgStep(2);
  });
  bindClick('catPkgStep2TopBack', function () {
    goCatPkgStep(1);
  });
  bindClick('catPkgStep2Back', function () {
    goCatPkgStep(1);
  });
  bindClick('catPkgChangeCategory', function () {
    goCatPkgStep(1);
  });
  bindClick('catPkgStep2Next', function () {
    syncPkgDraftFromStep2Fields();
    if (!pkgWizard.draft.name) {
      toast('Package name is required');
      return;
    }
    if (!packageDietChosen(pkgWizard.draft.dietType)) {
      toast('Choose veg sadhya, non-veg sadhya, or veg and non-veg buffet');
      return;
    }
    goCatPkgStep(3);
  });
  bindClick('catPkgStep3TopBack', function () {
    goCatPkgStep(2);
  });
  bindClick('catPkgStep3Next', function () {
    const ids = pkgWizard.draft.itemIds || [];
    if (!ids.length) {
      toast('Add at least one menu item from the categories');
      return;
    }
    renderCatPkgPricing();
    show('catPkgPricing');
  });
  bindOnInput('catPkgName', function () {
    updatePkgCustomerPreview();
  });
  bindOnInput('catPkgItemSearch', function () {
    renderCatPkgStep3Menu();
  });
}

function renderCatPkgOffer() {
  const d = pkgWizard.draft;
  if (!d) return;
  const box = el('catPkgOfferBox');
  const on = el('catPkgOfferOn');
  const fields = el('catPkgOfferFields');
  const pct = el('catPkgOfferPercent');
  if (on) on.checked = !!d.offerEnabled;
  if (box) box.classList.toggle('on', !!d.offerEnabled);
  if (fields) fields.hidden = !d.offerEnabled;
  if (pct && document.activeElement !== pct) {
    const v = d.discountPercent;
    pct.value = v === '' || v == null ? '' : v;
  }
  paintPackageOfferPrices();
}

function paintPackageOfferPrices() {
  const d = pkgWizard.draft;
  const pct = d ? offerPercentOf(d) : 0;
  document.querySelectorAll('#catPkgSlabs .cat-slab-offer').forEach(function (slot) {
    const row = slot.closest('.cat-slab-row');
    const priceEl = row && row.querySelector('.slab-price');
    const price = priceEl ? +priceEl.value || 0 : 0;
    slot.innerHTML = pct ? offerPriceBitsHtml(price, pct) : '';
  });
  const flatSlot = el('catPkgFlatOffer');
  if (flatSlot) {
    const priceEl = el('catPkgFlatPrice');
    const show = !!(pct && d && d.rateMode === 'flat');
    flatSlot.hidden = !show;
    flatSlot.innerHTML = show ? offerPriceBitsHtml(priceEl ? +priceEl.value || 0 : 0, pct) : '';
  }
}

function renderCatPkgPricing() {
  const d = pkgWizard.draft;
  if (!d) return;
  if (!d.guestSlabs || !d.guestSlabs.length) d.guestSlabs = defaultPackageGuestSlabs();
  if (!d.rateMode) d.rateMode = resolveRateMode(d, 'guestSlabs');
  const flat = d.rateMode === 'flat';
  const flatRadio = el('catPkgRateFlat');
  const tierRadio = el('catPkgRateTiered');
  if (flatRadio) flatRadio.checked = flat;
  if (tierRadio) tierRadio.checked = !flat;
  const flatWrap = el('catPkgFlatWrap');
  const tierWrap = el('catPkgTieredWrap');
  if (flatWrap) flatWrap.hidden = !flat;
  if (tierWrap) tierWrap.hidden = flat;
  if (flat) {
    if (d.guestSlabs.length !== 1) {
      d.guestSlabs = [{ from: 1, to: 500, price: +d.guestSlabs[0].price || 0 }];
    }
    const price = el('catPkgFlatPrice');
    if (price) price.value = d.guestSlabs[0].price;
    renderCatPkgOffer();
    renderPkgGuestPricingExample(d.guestSlabs);
    return;
  }
  d.guestSlabs = normalizePackageGuestSlabs(d.guestSlabs);
  renderSlabTable(
    'catPkgSlabs',
    d.guestSlabs,
    function (slabs) {
      pkgWizard.draft.guestSlabs = slabs;
    },
    {
      priceHeader: 'Price per plate (₹)',
      afterChange: function (slabs) {
        renderPkgGuestPricingExample(slabs);
        paintPackageOfferPrices();
      },
    }
  );
  renderCatPkgOffer();
  renderPkgGuestPricingExample(d.guestSlabs);
}

function renderCatPkgPreview() {
  const d = pkgWizard.draft;
  const sum = el('catPkgSummary');
  if (sum) {
    let html = packageDietChipHtml(d.dietType);
    if (html) html = '<div class="cat-sum-row">' + html + '</div>';
    html += '<div class="cat-sum-row">' + esc(packageServiceLabel(d)) + '</div>';
    FOOD_MODULES.forEach(function (m) {
      const n = countPkgItemsInModule(d, m.id);
      if (!n) return;
      html += '<div class="cat-sum-row">✓ ' + esc(packageModuleLabel(m, d.dietType)) + ' (' + n + ' items)</div>';
    });
    sum.innerHTML = html || '<p class="sub">No modules selected</p>';
  }
  const pr = el('catPkgPreviewPricing');
  if (pr) {
    const slabs = d.guestSlabs || [];
    const pct = offerPercentOf(d);
    if (!slabs.length) pr.textContent = 'No guest slabs set';
    else {
      pr.innerHTML = slabs
        .map(function (s) {
          const range =
            d.rateMode === 'flat' ? 'All guests' : esc(String(s.from)) + '–' + esc(String(s.to)) + ' guests';
          if (!pct) return range + ': ₹' + formatInrFull(s.price) + ' / plate';
          return (
            '<span class="cat-preview-offer">' +
            range +
            ': ' +
            offerPriceBitsHtml(s.price, pct) +
            ' / plate</span>'
          );
        })
        .join('<br>');
    }
  }
  const live = el('catPkgStatusLive');
  const draft = el('catPkgStatusDraft');
  if (live) live.checked = d.status !== 'draft';
  if (draft) draft.checked = d.status === 'draft';
}

function bindCatPkgPricingUi() {
  bindClick('catPkgPricingBack', function () {
    goCatPkgStep(3);
  });
  bindClick('catPkgAddSlab', function () {
    if (!pkgWizard.draft || pkgWizard.draft.rateMode === 'flat') return;
    const slabs = pkgWizard.draft.guestSlabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 1;
    slabs.push({ from: from, to: from + 24, price: last ? Math.max(50, last.price - 50) : 500 });
    pkgWizard.draft.guestSlabs = slabs;
    renderCatPkgPricing();
  });
  bindOnChange('catPkgRateFlat', function () {
    if (!pkgWizard.draft) return;
    applyRateMode(pkgWizard.draft, 'guestSlabs', 'flat', defaultPackageGuestSlabs);
    renderCatPkgPricing();
  });
  bindOnChange('catPkgRateTiered', function () {
    if (!pkgWizard.draft) return;
    applyRateMode(pkgWizard.draft, 'guestSlabs', 'tiered', defaultPackageGuestSlabs);
    renderCatPkgPricing();
  });
  bindOnInput('catPkgFlatPrice', function () {
    if (!pkgWizard.draft) return;
    const price = el('catPkgFlatPrice');
    pkgWizard.draft.rateMode = 'flat';
    pkgWizard.draft.guestSlabs = [{ from: 1, to: 500, price: price ? +price.value || 0 : 0 }];
    paintPackageOfferPrices();
    renderPkgGuestPricingExample(pkgWizard.draft.guestSlabs);
  });
  bindOnChange('catPkgOfferOn', function () {
    if (!pkgWizard.draft) return;
    const on = el('catPkgOfferOn');
    pkgWizard.draft.offerEnabled = !!(on && on.checked);
    renderCatPkgOffer();
    renderPkgGuestPricingExample(pkgWizard.draft.guestSlabs);
    if (pkgWizard.draft.offerEnabled) {
      const pct = el('catPkgOfferPercent');
      if (pct) pct.focus();
    }
  });
  bindOnInput('catPkgOfferPercent', function () {
    if (!pkgWizard.draft) return;
    const pct = el('catPkgOfferPercent');
    const raw = pct ? pct.value : '';
    pkgWizard.draft.offerEnabled = true;
    pkgWizard.draft.discountPercent = raw === '' ? '' : Math.round(+raw);
    paintPackageOfferPrices();
    renderPkgGuestPricingExample(pkgWizard.draft.guestSlabs);
  });
  bindClick('catPkgNextPreview', function () {
    const slabs = pkgWizard.draft.guestSlabs || [];
    const onEl = el('catPkgOfferOn');
    const pctEl = el('catPkgOfferPercent');
    if (onEl) pkgWizard.draft.offerEnabled = !!onEl.checked;
    if (pkgWizard.draft.offerEnabled && pctEl) {
      pkgWizard.draft.discountPercent = pctEl.value === '' ? '' : Math.round(+pctEl.value);
    }
    if (!slabs.length) {
      toast('Add at least one guest pricing slab');
      return;
    }
    if (pkgWizard.draft.offerEnabled && !offerPercentOf(pkgWizard.draft)) {
      toast('Enter a discount from 1 to 90 percent');
      return;
    }
    renderCatPkgPreview();
    show('catPkgPreview');
  });
  bindClick('catPkgPreviewBack', function () {
    show('catPkgPricing');
    renderCatPkgPricing();
  });
  bindClick('catPkgSave', function () {
    const d = pkgWizard.draft;
    d.status = el('catPkgStatusDraft') && el('catPkgStatusDraft').checked ? 'draft' : 'live';
    const slabs = d.guestSlabs || [];
    if (!slabs.length && d.status === 'live') {
      toast('Add guest pricing slabs');
      return;
    }
    if (!packageDietChosen(d.dietType)) {
      toast('Choose veg sadhya, non-veg sadhya, or veg and non-veg buffet');
      return;
    }
    if (d.offerEnabled && !offerPercentOf(d)) {
      toast('Enter a discount from 1 to 90 percent');
      return;
    }
    const baseMin = slabs.length
      ? Math.min.apply(
          null,
          slabs.map(function (s) {
            return +s.price || 0;
          })
        )
      : 0;
    const pct = offerPercentOf(d);
    d.discountPercent = pct || '';
    if (!pct) d.offerEnabled = false;
    d.price = priceAfterOffer(baseMin, pct);
    d.listPrice = baseMin;
    clearRateModeBackup(d);
    d.subtitle = d.subtitle || d.customerTitle || moduleCountSubtitle(d);
    d.id = pkgWizard.editId || uid('cpkg');
    const i = (store.cateringMenu.catPackages || []).findIndex(function (p) {
      return p.id === d.id;
    });
    if (i >= 0) store.cateringMenu.catPackages[i] = JSON.parse(JSON.stringify(d));
    else store.cateringMenu.catPackages.unshift(JSON.parse(JSON.stringify(d)));
    pkgWizard.editId = null;
    saveStore();
    toast(d.status === 'live' ? 'Package saved & live' : 'Package saved as draft');
    show('menuPkg');
    store.cateringMenu.hubTab = 'packages';
    renderCateringMenuHub();
  });
}

function moduleCountSubtitle(pkg) {
  let mods = 0;
  FOOD_MODULES.forEach(function (m) {
    if (countPkgItemsInModule(pkg, m.id) > 0) mods += 1;
  });
  const ids = pkg.itemIds || [];
  return '~' + ids.length + ' dishes · ' + mods + ' modules · per person';
}

function bindCatModulePickUi() {
  bindClick('catModulePickBack', function () {
    if (menuPickCtx.mode === 'package') {
      show('catPkgStep3');
      renderCatPkgStep3Menu();
    } else {
      show('menuPkg');
      store.cateringMenu.hubTab = 'food';
      renderCateringMenuHub();
    }
  });
  bindClick('catModulePickSave', function () {
    if (countModulePickPending() === 0) {
      toast(menuPickCtx.mode === 'package' ? 'Select at least one item' : 'Select items to add');
      return;
    }
    commitModulePicker();
  });
}

function bindPickIndividualUi() {
  const back = el('catPickIndividualBack');
  if (back) {
    back.onclick = function () {
      show('menuPkg');
    };
  }
  const cont = el('catPickIndividualContinue');
  if (cont) {
    cont.onclick = function () {
      continueIndividualPick();
    };
  }
  const search = el('catPickIndividualSearch');
  if (search) {
    search.oninput = function () {
      individualPickSearch = search.value;
      renderPickIndividualBody();
    };
  }
}

function bindFullMenuCatalogUi() {
  const back = el('catFullMenuBack');
  if (back) {
    back.onclick = function () {
      show('menuPkg');
    };
  }
  const search = el('catCatalogModuleSearch');
  if (search) {
    search.oninput = function () {
      catalogModuleSearch = search.value;
      renderCatFoodModuleList();
    };
  }
}

function bindCateringMenuAll() {
  bindFoodItemFormUi();
  bindCatPkgCreateUi();
  bindCatPkgPricingUi();
  bindCatModulePickUi();
  bindPickIndividualUi();
  bindFullMenuCatalogUi();
}
