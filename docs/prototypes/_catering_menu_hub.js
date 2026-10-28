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

function updatePkgCustomerPreview() {
  syncPkgDraftFromStep2Fields();
  const host = el('catPkgCustomerPreview');
  if (!host || !pkgWizard.draft) return;
  host.textContent = pkgWizard.draft.customerTitle || 'Basic - Your package name';
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
    return f.moduleId === moduleId && f.status !== 'archived';
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
  const per = guestSlabPriceForCount(s, guests);
  const total = guests * per;
  host.innerHTML =
    '<span class="cat-pkg-example-ico" aria-hidden="true">🧮</span><div><b>Example Calculation</b><p>' +
    guests +
    ' guests × ₹' +
    formatInrFull(per) +
    ' = ₹ ' +
    formatInrFull(total) +
    ' (approx)</p></div>';
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

function foodItemFromPrice(f) {
  const slabs = f.slabs || [];
  if (!slabs.length) return f.quoteOnly ? 'Quote' : '—';
  const min = Math.min.apply(
    null,
    slabs.map(function (s) {
      return +s.price || 0;
    })
  );
  const unit = f.pricingMode === 'per_unit' ? f.unitLabel || 'unit' : 'plate';
  return formatInrCompact(min) + ' / ' + unit + '+';
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
  return 'From ₹' + formatInrFull(from) + ' / person';
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
        : 'Create your first catering package with items from all 13 modules.') +
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
        '" aria-label="Package options">⋮</button></div><b>' +
        esc(p.name) +
        '</b><div class="pkg-price">' +
        esc(packageFromPersonLabel(p)) +
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
        '</span></div><div class="svc-bd"><b>' +
        esc(f.name) +
        '</b><div class="svc-meta"><span class="svc-price-tag">' +
        foodItemFromPrice(f) +
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
  if (diet === 'non_veg') return { cls: 'non_veg', text: 'NV' };
  if (diet === 'egg') return { cls: 'egg', text: 'Egg' };
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
  el('catModuleTitle').textContent = mod.name;
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
      return modulePickMatchesSearch(it.name, q);
    });
    if (!visibleItems.length) return;
    visible += visibleItems.length;
    html +=
      '<div class="cat-pick-section" data-sc-idx="' +
      scIdx +
      '"><div class="cat-pick-section-hd"><b>' +
      esc(sc.name) +
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
  if (!html) {
    html = '<div class="cat-pick-empty">No dishes match your search.</div>';
  }
  body.innerHTML = html;
  if (meta) {
    const pending = countModulePickPending();
    meta.textContent =
      total +
      ' dishes in catalogue' +
      (q ? ' · ' + visible + ' shown' : '') +
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

function isIndividualFoodForm(d) {
  if (!d) return false;
  if (d.individualListing === false) return false;
  return true;
}

function applyFoodFormPricingUi(d) {
  const individualOnly = isIndividualFoodForm(d);
  const choices = el('catFoodPriceTypeChoices');
  const hint = el('catFoodPriceIndividualHint');
  const unitWrap = el('catFoodUnitWrap');
  if (individualOnly) {
    d.pricingMode = 'per_person';
    if (choices) choices.hidden = true;
    if (hint) hint.hidden = false;
    if (unitWrap) unitWrap.style.display = 'none';
    if (el('catFoodPricePerson')) el('catFoodPricePerson').checked = true;
    if (el('catFoodPriceUnit')) el('catFoodPriceUnit').checked = false;
  } else {
    if (choices) choices.hidden = false;
    if (hint) hint.hidden = true;
    if (el('catFoodPricePerson')) el('catFoodPricePerson').checked = d.pricingMode !== 'per_unit';
    if (el('catFoodPriceUnit')) el('catFoodPriceUnit').checked = d.pricingMode === 'per_unit';
    if (unitWrap) unitWrap.style.display = d.pricingMode === 'per_unit' ? 'block' : 'none';
  }
}

function renderFoodItemForm() {
  const d = foodFormDraft;
  if (!d) return;
  const mod = findFoodModule(d.moduleId);
  el('catFoodFormTitle').textContent = d.id && findFoodItem(d.id) ? 'Edit Food Item' : 'Add Food Item';
  el('catFoodImgEmoji').textContent = d.imageEmoji || (mod && mod.emoji) || '🍽️';
  el('catFoodName').value = d.name || '';
  ensureFoodFormCatalogMeta();
  const modAfter = findFoodModule(d.moduleId);
  if (modAfter) el('catFoodImgEmoji').textContent = d.imageEmoji || modAfter.emoji || '🍽️';
  el('catFoodDesc').value = d.description || '';
  el('catFoodDietVeg').checked = d.diet === 'veg';
  el('catFoodDietEgg').checked = d.diet === 'egg';
  el('catFoodDietNon').checked = d.diet === 'non_veg';
  el('catFoodQuoteOnly').checked = !!d.quoteOnly;
  el('catFoodUnitLabel').value = d.unitLabel || 'bowl';
  applyFoodFormPricingUi(d);
  renderSlabTable('catFoodSlabs', d.slabs || defaultItemSlabs(), function (slabs) {
    foodFormDraft.slabs = slabs;
  });
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
  const priceHdr = tableOpts.priceHeader || 'Price (₹)';
  const rows = (slabs || []).map(function (s, idx) {
    return (
      '<div class="cat-slab-row" data-idx="' +
      idx +
      '"><input type="number" class="slab-from" value="' +
      esc(s.from) +
      '" min="1" aria-label="From guests"><input type="number" class="slab-to" value="' +
      esc(s.to) +
      '" min="1" aria-label="To guests"><div class="cat-slab-price-wrap"><span class="cat-slab-inr" aria-hidden="true">₹</span><input type="number" class="slab-price" value="' +
      esc(s.price) +
      '" min="0" aria-label="Price per person"></div><button type="button" class="cat-slab-rm" data-rm="' +
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
  bindOnChange('catFoodPricePerson', function () {
    if (!foodFormDraft || isIndividualFoodForm(foodFormDraft)) return;
    foodFormDraft.pricingMode = 'per_person';
    applyFoodFormPricingUi(foodFormDraft);
  });
  bindOnChange('catFoodPriceUnit', function () {
    if (!foodFormDraft || isIndividualFoodForm(foodFormDraft)) return;
    foodFormDraft.pricingMode = 'per_unit';
    applyFoodFormPricingUi(foodFormDraft);
  });
  bindClick('catFoodAddSlab', function () {
    const slabs = foodFormDraft.slabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 1;
    slabs.push({ from: from, to: from + 24, price: last ? last.price : 50 });
    foodFormDraft.slabs = slabs;
    renderSlabTable('catFoodSlabs', slabs, function (s) {
      foodFormDraft.slabs = s;
    });
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
}

function saveFoodItemForm(status) {
  if (!foodFormDraft) return;
  foodFormDraft.name = (el('catFoodName').value || '').trim();
  if (!foodFormDraft.name) {
    toast('Food item name is required');
    return;
  }
  if (el('catFoodDietNon').checked) foodFormDraft.diet = 'non_veg';
  else if (el('catFoodDietEgg').checked) foodFormDraft.diet = 'egg';
  else foodFormDraft.diet = 'veg';
  foodFormDraft.description = (el('catFoodDesc').value || '').trim();
  foodFormDraft.quoteOnly = el('catFoodQuoteOnly').checked;
  if (isIndividualFoodForm(foodFormDraft)) foodFormDraft.pricingMode = 'per_person';
  foodFormDraft.unitLabel = (el('catFoodUnitLabel').value || 'plate').trim();
  ensureFoodFormCatalogMeta();
  if (foodFormDraft.individualListing === undefined && !(store.cateringMenu.foodItems || []).some(function (f) {
    return f.id === foodFormDraft.id;
  })) {
    foodFormDraft.individualListing = true;
  }
  if (foodFormDraft.quoteOnly) foodFormDraft.status = status === 'active' ? 'active' : 'draft';
  else if (!foodFormDraft.slabs || !foodFormDraft.slabs.length) {
    toast('Add at least one pricing slab or enable quote-only');
    return;
  } else foodFormDraft.status = status;
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
    guestSlabs: defaultPackageGuestSlabs(),
    itemIds: [],
    imageEmoji: '🍽️',
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
  const nameEl = el('catPkgName');
  const descEl = el('catPkgDesc');
  if (nameEl) nameEl.value = d.name || '';
  if (descEl) descEl.value = d.description || '';
  updatePkgCustomerPreview();
}

function renderCatPkgStep3Menu() {
  const d = pkgWizard.draft;
  if (!d) return;
  const q = (el('catPkgItemSearch') && el('catPkgItemSearch').value || '').trim().toLowerCase();
  const list = el('catPkgModulePick');
  if (!list) return;
  list.innerHTML = FOOD_MODULES.filter(function (m) {
    if (!q) return true;
    return m.name.toLowerCase().includes(q);
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
        esc(m.name) +
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
    goCatPkgStep(3);
  });
  bindClick('catPkgStep3TopBack', function () {
    goCatPkgStep(2);
  });
  bindClick('catPkgStep3Next', function () {
    if (!(pkgWizard.draft.itemIds || []).length) {
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

function renderCatPkgPricing() {
  const d = pkgWizard.draft;
  d.guestSlabs = normalizePackageGuestSlabs(d.guestSlabs);
  renderSlabTable(
    'catPkgSlabs',
    d.guestSlabs,
    function (slabs) {
      pkgWizard.draft.guestSlabs = slabs;
    },
    {
      priceHeader: 'Price per person (₹)',
      afterChange: renderPkgGuestPricingExample,
    }
  );
  renderPkgGuestPricingExample(d.guestSlabs);
}

function renderCatPkgPreview() {
  const d = pkgWizard.draft;
  const sum = el('catPkgSummary');
  if (sum) {
    let html = '';
    FOOD_MODULES.forEach(function (m) {
      const n = countPkgItemsInModule(d, m.id);
      if (!n) return;
      html += '<div class="cat-sum-row">✓ ' + esc(m.name) + ' (' + n + ' items)</div>';
    });
    sum.innerHTML = html || '<p class="sub">No modules selected</p>';
  }
  const pr = el('catPkgPreviewPricing');
  if (pr) {
    const slabs = d.guestSlabs || [];
    if (!slabs.length) pr.textContent = 'No guest slabs set';
    else {
      pr.innerHTML = slabs
        .map(function (s) {
          return (
            esc(String(s.from)) +
            '–' +
            esc(String(s.to)) +
            ' guests: ₹' +
            formatInrFull(s.price) +
            ' / person'
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
    const slabs = pkgWizard.draft.guestSlabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 25;
    slabs.push({ from: from, to: from + 49, price: last ? Math.max(50, last.price - 50) : 500 });
    pkgWizard.draft.guestSlabs = slabs;
    renderCatPkgPricing();
  });
  bindClick('catPkgNextPreview', function () {
    const slabs = pkgWizard.draft.guestSlabs || [];
    if (!slabs.length) {
      toast('Add at least one guest pricing slab');
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
    if (!d.quoteOnly && !slabs.length && d.status === 'live') {
      toast('Add guest pricing slabs');
      return;
    }
    d.price = slabs.length ? Math.min.apply(null, slabs.map(function (s) { return +s.price; })) : 0;
    d.listPrice = d.listPrice || d.price;
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
