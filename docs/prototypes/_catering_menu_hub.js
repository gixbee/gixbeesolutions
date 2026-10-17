/** Catering owner — Menu & Packages hub (packages + food items). */

let menuPickCtx = { mode: 'catalog', selected: {}, moduleId: null, returnTo: 'menuPkg' };
let foodFormDraft = null;
let pkgWizard = { draft: null, editId: null };

function ensureCateringMenuStore() {
  if (!store.cateringMenu) store.cateringMenu = defaultCateringMenuStore();
  if (!store.cateringMenu.foodItems) store.cateringMenu.foodItems = [];
  if (!store.cateringMenu.catPackages) store.cateringMenu.catPackages = defaultCateringMenuStore().catPackages;
  if (!store.cateringMenu.hubTab) store.cateringMenu.hubTab = 'packages';
  if (store.cateringMenu.pkgFilter === 'custom') store.cateringMenu.pkgFilter = 'all';
  migrateLegacyCateringPackageLabels();
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
  if (hubTitle) hubTitle.textContent = isPkg ? 'Menu & Packages' : 'Food Menu';

  const intro = el('catHubIntro');
  if (intro) {
    intro.textContent = isPkg
      ? 'Catering packages with per-person slabs. Filter by tier and publish when ready.'
      : 'Browse the 13 modules and add dishes you offer to your live menu.';
  }

  const stat = el('catHubStat');
  if (stat) {
    const pkgs = store.cateringMenu.catPackages || [];
    const live = pkgs.filter(function (p) {
      return p.status === 'live';
    }).length;
    const foods = (store.cateringMenu.foodItems || []).filter(function (f) {
      return f.status === 'active';
    }).length;
    stat.innerHTML = isPkg
      ? '<span class="cat-stat-pill"><b>' +
        pkgs.length +
        '</b> PACKAGES</span><span class="cat-stat-pill live"><b>' +
        live +
        '</b> LIVE</span>'
      : '<span class="cat-stat-pill blue"><b>' +
        foods +
        '</b> ACTIVE ITEMS</span><span class="cat-stat-pill"><b>13</b> MODULES</span>';
  }

  renderCatPkgFilters();
  renderCatPkgList();
  renderCatFoodModuleList();
  bindCateringMenuHubUi();
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

function filteredCatPackages() {
  let list = (store.cateringMenu.catPackages || []).slice();
  const f = store.cateringMenu.pkgFilter || 'all';
  if (f !== 'all') {
    list = list.filter(function (p) {
      return catLevelClass(p.level) === f;
    });
  }
  const q = (store.cateringMenu.pkgSearch || '').trim().toLowerCase();
  if (q) {
    list = list.filter(function (p) {
      return (
        String(p.name || '').toLowerCase().includes(q) ||
        String(p.level || '').toLowerCase().includes(q)
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
    list.innerHTML =
      '<div class="hub-empty"><div class="hub-empty-ico">📦</div><b>No packages yet</b><p>Create your first catering package with items from all 13 modules.</p></div>';
    return;
  }
  list.innerHTML = pkgs
    .map(function (p) {
      const lv = catLevelClass(p.level);
      const disc =
        p.listPrice > p.price
          ? '<span class="was" style="text-decoration:line-through;color:#9CA3AF;font-size:12px;font-weight:700;margin-left:6px">' +
            formatInrCompact(p.listPrice) +
            '</span>'
          : '';
      const thumbStyle = 'background:' + (p.thumbGradient || 'linear-gradient(145deg,#F97316,#EA580C)');
      return (
        '<div class="pkg-card pkg-card-tap" data-cpkg-id="' +
        esc(p.id) +
        '"><div class="pkg-thumb lv-' +
        lv +
        '" style="' +
        thumbStyle +
        '"><span style="font-size:28px;z-index:1;position:relative">' +
        esc(p.imageEmoji || '🍽️') +
        '</span></div><div class="pkg-bd"><div class="pkg-top-row"><div class="pkg-chips"><span class="pkg-level ' +
        lv +
        '">' +
        esc(p.level) +
        '</span></div></div><b>' +
        esc(p.name) +
        '</b><div class="pkg-price">' +
        formatInrCompact(p.price || lowestGuestPrice(p)) +
        disc +
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
}

function renderCatFoodModuleList() {
  const host = el('catFoodModuleList');
  if (!host) return;
  const q = (store.cateringMenu.foodSearch || '').trim().toLowerCase();
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
      renderCatFoodModuleList();
    };
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
  const addPkg = el('catAddPackageBtn');
  if (addPkg) {
    addPkg.onclick = function () {
      startCatPackageWizard(null);
    };
  }
  const list = el('catPkgList');
  if (list) {
    list.querySelectorAll('[data-cpkg-id]').forEach(function (card) {
      card.onclick = function (e) {
        if (e.target.closest('.cat-pkg-more')) return;
        startCatPackageWizard(card.getAttribute('data-cpkg-id'));
      };
    });
    list.querySelectorAll('[data-cpkg-menu]').forEach(function (btn) {
      btn.onclick = function (e) {
        e.stopPropagation();
        const id = btn.getAttribute('data-cpkg-menu');
        const action = prompt('Package options:\n1 = Edit\n2 = Duplicate\n3 = Delete\n\nEnter 1, 2 or 3');
        if (action === '1') startCatPackageWizard(id);
        else if (action === '2') duplicateCatPackage(id);
        else if (action === '3') deleteCatPackage(id);
      };
    });
  }
  const modList = el('catFoodModuleList');
  if (modList) {
    modList.querySelectorAll('[data-mod]').forEach(function (row) {
      row.onclick = function () {
        openModulePicker(row.getAttribute('data-mod'), 'catalog');
      };
    });
  }
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
    returnTo: mode === 'package' ? 'catPkgCreate' : 'menuPkg',
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
    show('catPkgCreate');
    renderCatPkgCreate();
    toast('Module items updated');
    return;
  }
  let added = 0;
  keys.forEach(function (mk) {
    if (ownerHasMasterKey(mk)) return;
    const item = createFoodItemFromMaster(mk, 'draft');
    store.cateringMenu.foodItems.push(item);
    added += 1;
  });
  saveStore();
  show(menuPickCtx.returnTo || 'menuPkg');
  store.cateringMenu.hubTab = 'food';
  renderCateringMenuHub();
  toast(added ? added + ' item(s) added — set pricing to go live' : 'No new items selected');
}

function createFoodItemFromMaster(masterKey, status) {
  const hit = findMasterItem(masterKey);
  if (!hit) {
    return {
      id: uid('food'),
      masterKey: masterKey,
      name: 'Custom item',
      moduleId: menuPickCtx.moduleId,
      subcatId: 'custom',
      subcatName: 'Custom',
      description: '',
      diet: 'veg',
      pricingMode: 'per_person',
      unitLabel: 'plate',
      quoteOnly: false,
      status: status || 'draft',
      slabs: defaultItemSlabs(),
      imageEmoji: '🍽️',
    };
  }
  return {
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
}

function defaultFoodDescription(name, diet) {
  if (/soup/i.test(name)) {
    return diet === 'non_veg' ? 'Mild and flavorful ' + name.toLowerCase() + '.' : 'Comforting vegetarian ' + name.toLowerCase() + '.';
  }
  return '';
}

function openFoodItemForm(foodId, masterKey) {
  let item = foodId ? findFoodItem(foodId) : null;
  if (!item && masterKey) {
    item = (store.cateringMenu.foodItems || []).find(function (f) {
      return f.masterKey === masterKey;
    });
  }
  if (!item && masterKey) {
    item = createFoodItemFromMaster(masterKey, 'draft');
  }
  if (!item) {
    toast('Select an item first');
    return;
  }
  foodFormDraft = JSON.parse(JSON.stringify(item));
  renderFoodItemForm();
  show('catFoodItemForm');
}

function renderFoodItemForm() {
  const d = foodFormDraft;
  if (!d) return;
  const mod = findFoodModule(d.moduleId);
  el('catFoodFormTitle').textContent = d.id && findFoodItem(d.id) ? 'Edit Food Item' : 'Add Food Item';
  el('catFoodImgEmoji').textContent = d.imageEmoji || (mod && mod.emoji) || '🍽️';
  el('catFoodName').value = d.name || '';
  el('catFoodModule').value = mod ? mod.num + '. ' + mod.name : d.moduleId;
  el('catFoodSubcat').value = d.subcatName || d.subcatId || '';
  el('catFoodDesc').value = d.description || '';
  el('catFoodDietVeg').checked = d.diet === 'veg';
  el('catFoodDietEgg').checked = d.diet === 'egg';
  el('catFoodDietNon').checked = d.diet === 'non_veg';
  el('catFoodQuoteOnly').checked = !!d.quoteOnly;
  el('catFoodPricePerson').checked = d.pricingMode !== 'per_unit';
  el('catFoodPriceUnit').checked = d.pricingMode === 'per_unit';
  el('catFoodUnitLabel').value = d.unitLabel || 'bowl';
  el('catFoodUnitWrap').style.display = d.pricingMode === 'per_unit' ? 'block' : 'none';
  renderSlabTable('catFoodSlabs', d.slabs || defaultItemSlabs(), function (slabs) {
    foodFormDraft.slabs = slabs;
  });
}

function renderSlabTable(hostId, slabs, onChange) {
  const host = el(hostId);
  if (!host) return;
  const rows = (slabs || []).map(function (s, idx) {
    return (
      '<div class="cat-slab-row" data-idx="' +
      idx +
      '"><input type="number" class="slab-from" value="' +
      esc(s.from) +
      '" min="1"><span>–</span><input type="number" class="slab-to" value="' +
      esc(s.to) +
      '" min="1"><input type="number" class="slab-price" value="' +
      esc(s.price) +
      '" min="0"><button type="button" class="cat-slab-rm" data-rm="' +
      idx +
      '">🗑</button></div>'
    );
  });
  host.innerHTML =
    '<div class="cat-slab-hd"><span>From</span><span>To</span><span>Price (₹)</span><span></span></div>' + rows.join('');
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
      renderSlabTable(hostId, next, onChange);
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
  el('catFoodPricePerson').onchange = function () {
    foodFormDraft.pricingMode = 'per_person';
    el('catFoodUnitWrap').style.display = 'none';
  };
  el('catFoodPriceUnit').onchange = function () {
    foodFormDraft.pricingMode = 'per_unit';
    el('catFoodUnitWrap').style.display = 'block';
  };
  el('catFoodAddSlab').onclick = function () {
    const slabs = foodFormDraft.slabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 1;
    slabs.push({ from: from, to: from + 24, price: last ? last.price : 50 });
    foodFormDraft.slabs = slabs;
    renderSlabTable('catFoodSlabs', slabs, function (s) {
      foodFormDraft.slabs = s;
    });
  };
  el('catFoodSaveDraft').onclick = function () {
    saveFoodItemForm('draft');
  };
  el('catFoodSave').onclick = function () {
    saveFoodItemForm('active');
  };
  el('catFoodBack').onclick = function () {
    show('menuPkg');
    renderCateringMenuHub();
  };
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
  foodFormDraft.unitLabel = (el('catFoodUnitLabel').value || 'plate').trim();
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
  renderCatPkgCreate();
  show('catPkgCreate');
}

function renderCatPkgCreate() {
  const d = pkgWizard.draft;
  if (!d) return;
  el('catPkgName').value = d.name || '';
  el('catPkgDesc').value = d.description || '';
  renderCatPkgLevelSeg(d.level);
  const q = (el('catPkgItemSearch').value || '').trim().toLowerCase();
  const list = el('catPkgModulePick');
  list.innerHTML = FOOD_MODULES
    .filter(function (m) {
      if (!q) return true;
      return m.name.toLowerCase().includes(q);
    })
    .map(function (m) {
      const n = countPkgItemsInModule(d, m.id);
      const checked = n > 0;
      return (
        '<button type="button" class="cat-pkg-mod-row" data-pkg-mod="' +
        esc(m.id) +
        '"><span class="cat-pkg-mod-chk' +
        (checked ? ' on' : '') +
        '">' +
        (checked ? '✓' : '') +
        '</span><span class="cat-mod-thumb sm" style="background:' +
        m.gradient +
        '">' +
        m.emoji +
        '</span><span class="cat-pkg-mod-txt"><b>' +
        esc(m.name) +
        '</b><small>(' +
        n +
        ' items selected)</small></span><span class="cat-mod-chev">›</span></button>'
      );
    })
    .join('');
  list.querySelectorAll('[data-pkg-mod]').forEach(function (row) {
    row.onclick = function () {
      openModulePicker(row.getAttribute('data-pkg-mod'), 'package');
    };
  });
}

function renderCatPkgLevelSeg(level) {
  const host = el('catPkgLevelSeg');
  if (!host) return;
  host.innerHTML = CAT_PKG_LEVELS
    .map(function (l) {
      return (
        '<button type="button" class="cat-lvl-btn' +
        (l === level ? ' on' : '') +
        '" data-lvl="' +
        esc(l) +
        '">' +
        esc(l) +
        '</button>'
      );
    })
    .join('');
  host.querySelectorAll('.cat-lvl-btn').forEach(function (btn) {
    btn.onclick = function () {
      pkgWizard.draft.level = btn.getAttribute('data-lvl');
      renderCatPkgLevelSeg(pkgWizard.draft.level);
    };
  });
}

function bindCatPkgCreateUi() {
  el('catPkgCreateBack').onclick = function () {
    show('menuPkg');
    renderCateringMenuHub();
  };
  el('catPkgNextPricing').onclick = function () {
    pkgWizard.draft.name = (el('catPkgName').value || '').trim();
    pkgWizard.draft.description = (el('catPkgDesc').value || '').trim();
    if (!pkgWizard.draft.name) {
      toast('Package name is required');
      return;
    }
    if (!(pkgWizard.draft.itemIds || []).length) {
      toast('Select at least one food item from the modules');
      return;
    }
    renderCatPkgPricing();
    show('catPkgPricing');
  };
  el('catPkgItemSearch').oninput = function () {
    renderCatPkgCreate();
  };
}

function renderCatPkgPricing() {
  const d = pkgWizard.draft;
  renderSlabTable('catPkgSlabs', d.guestSlabs || defaultPackageGuestSlabs(), function (slabs) {
    pkgWizard.draft.guestSlabs = slabs;
  });
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
  el('catPkgStatusLive').checked = d.status !== 'draft';
  el('catPkgStatusDraft').checked = d.status === 'draft';
}

function bindCatPkgPricingUi() {
  el('catPkgPricingBack').onclick = function () {
    show('catPkgCreate');
    renderCatPkgCreate();
  };
  el('catPkgAddSlab').onclick = function () {
    const slabs = pkgWizard.draft.guestSlabs || [];
    const last = slabs[slabs.length - 1];
    const from = last ? last.to + 1 : 25;
    slabs.push({ from: from, to: from + 24, price: last ? last.price - 10 : 300 });
    pkgWizard.draft.guestSlabs = slabs;
    renderCatPkgPricing();
  };
  el('catPkgSave').onclick = function () {
    const d = pkgWizard.draft;
    d.status = el('catPkgStatusDraft').checked ? 'draft' : 'live';
    const slabs = d.guestSlabs || [];
    if (!d.quoteOnly && !slabs.length && d.status === 'live') {
      toast('Add guest pricing slabs');
      return;
    }
    d.price = slabs.length ? Math.min.apply(null, slabs.map(function (s) { return +s.price; })) : 0;
    d.listPrice = d.listPrice || d.price;
    d.subtitle = d.subtitle || moduleCountSubtitle(d);
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
  };
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
  el('catModulePickBack').onclick = function () {
    if (menuPickCtx.mode === 'package') show('catPkgCreate');
    else {
      show('menuPkg');
      store.cateringMenu.hubTab = 'food';
      renderCateringMenuHub();
    }
  };
  el('catModulePickSave').onclick = function () {
    if (countModulePickPending() === 0) {
      toast(menuPickCtx.mode === 'package' ? 'Select at least one item' : 'Select items to add');
      return;
    }
    commitModulePicker();
  };
}

function bindCateringMenuAll() {
  bindFoodItemFormUi();
  bindCatPkgCreateUi();
  bindCatPkgPricingUi();
  bindCatModulePickUi();
}
