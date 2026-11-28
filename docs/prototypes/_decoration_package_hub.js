/** Decoration packages hub + 5-step wizard (tier amounts: Basic / Standard / Premium). */

const DEC_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];

let decorPkgWizard = { editId: null, draft: null, itemsTab: 'included', activeModuleId: null };
let decorModulePickCtx = { moduleId: null, search: '' };
let decorItemPickCtx = { moduleId: null, configuringId: null, customName: '' };

function ensureDecorationStore() {
  if (!store.decorationMenu) store.decorationMenu = defaultDecorationStore();
  if (!store.decorationMenu.catPackages) store.decorationMenu.catPackages = [];
  if (!store.decorationMenu.individualServices) store.decorationMenu.individualServices = [];
  if (!store.decorationMenu.pkgCategoryFilter) store.decorationMenu.pkgCategoryFilter = 'wedding';
}

function decorLevelClass(level) {
  const lv = String(level || 'standard').toLowerCase();
  if (lv === 'basic' || lv === 'premium') return lv;
  return 'standard';
}

const DEC_PKG_MAX_IMAGES = 6;

function ensureDecorPkgImageSlots(d) {
  if (!d.images || !d.images.length) d.images = ['🎀'];
  if (!d.imageUploaded) d.imageUploaded = d.images.map(function () {
    return false;
  });
  while (d.imageUploaded.length < d.images.length) d.imageUploaded.push(false);
  while (d.images.length < d.imageUploaded.length) d.images.push('🖼️');
}

function decorPkgHasCoverPhoto(p) {
  return !!(p && p.imageUploaded && p.imageUploaded[0]);
}

function decorPkgThumbInner(p) {
  if (decorPkgHasCoverPhoto(p)) return '';
  return esc((p.images && p.images[0]) || '🎀');
}

function decorPkgHeroClass(d) {
  return decorPkgHasCoverPhoto(d) ? ' dec-preview-hero has-photo' : ' dec-preview-hero';
}

function normalizeDecorPackage(d) {
  if (!d) return;
  if (d.traditionTags && d.traditionTags.length > 1) d.traditionTags = [d.traditionTags[0]];
  ensureDecorPkgImageSlots(d);
  if (!d.level) {
    const t = d.tierPrices || {};
    if (+t.premium > 0) d.level = 'Premium';
    else if (+t.standard > 0) d.level = 'Standard';
    else if (+t.basic > 0) d.level = 'Basic';
    else d.level = 'Standard';
  }
  if (d.listPrice === '' || d.listPrice == null || !(+d.listPrice > 0)) {
    const key = decorLevelClass(d.level);
    const fromTier = Math.round(+((d.tierPrices || {})[key] || 0));
    if (fromTier > 0) d.listPrice = fromTier;
    else {
      const hit = decorPrimaryTierPrice(d);
      if (hit.amount > 0) d.listPrice = hit.amount;
      else d.listPrice = '';
    }
  }
}

function newDecorPkgDraft() {
  return {
    packageCategory: 'wedding',
    level: 'Standard',
    eventTypes: [],
    traditionTags: ['Hindu'],
    traditionOtherText: '',
    ceremonySetup: [],
    styles: [],
    name: '',
    description: '',
    images: ['🎀'],
    imageUploaded: [false],
    listPrice: '',
    tierPrices: { basic: '', standard: '', premium: '' },
    offerEnabled: false,
    discountPercent: '',
    gstTreatment: 'Included',
    items: [],
    status: 'live',
  };
}

function findDecorPackage(id) {
  return (store.decorationMenu.catPackages || []).find(function (p) {
    return p.id === id;
  });
}

function decorPkgCounts(d) {
  const items = d.items || [];
  let inc = 0;
  let extra = 0;
  items.forEach(function (it) {
    if (it.inclusionType === 'extra') extra++;
    else inc++;
  });
  return { total: items.length, included: inc, extra: extra };
}

function decorOfferPct(d) {
  if (!d || !d.offerEnabled) return 0;
  const n = Math.round(+d.discountPercent);
  return n >= 1 && n <= 90 ? n : 0;
}

function decorPriceAfterOffer(base, pct) {
  const b = Math.max(0, Math.round(+base || 0));
  if (!pct) return b;
  return Math.max(0, Math.round((b * (100 - pct)) / 100));
}

function decorPrimaryTierPrice(d) {
  if (+d.listPrice > 0) {
    return { tier: decorLevelClass(d.level), amount: Math.round(+d.listPrice) };
  }
  const t = d.tierPrices || {};
  const order = ['standard', 'basic', 'premium'];
  let i;
  for (i = 0; i < order.length; i++) {
    const v = Math.round(+(t[order[i]] || 0));
    if (v > 0) return { tier: order[i], amount: v };
  }
  return { tier: '', amount: 0 };
}

function decorPkgListPrice(d) {
  const hit = decorPrimaryTierPrice(d);
  const pct = decorOfferPct(d);
  return {
    base: hit.amount,
    offer: decorPriceAfterOffer(hit.amount, pct),
    pct: pct,
    tier: hit.tier,
  };
}

function decorationMenuOpenHub() {
  ensureDecorationStore();
  show('decorHub');
  renderDecorationHub();
}

function renderDecorationHub() {
  const tab = store.decorationMenu.hubTab || 'packages';
  el('decTabPackages').classList.toggle('on', tab === 'packages');
  el('decTabServices').classList.toggle('on', tab === 'services');
  el('decHubPkgPanel').hidden = tab !== 'packages';
  el('decHubSvcPanel').hidden = tab !== 'services';
  const head = el('decHubHead');
  if (head) head.innerHTML = '<em>Gixbee</em><span>|</span>Packages &amp; Services';
  if (tab === 'packages') {
    renderDecorPkgFilters();
    renderDecorPkgCategoryFilters();
    renderDecorPackageList();
  } else if (typeof renderDecorIndividualList === 'function') renderDecorIndividualList();
}

function renderDecorPkgCategoryFilters() {
  const row = el('decPkgCategoryFilters');
  if (!row) return;
  const sel = store.decorationMenu.pkgCategoryFilter || 'wedding';
  const ids = ['wedding', 'other'];
  row.innerHTML =
    '<div class="dec-pkg-ev-grid dec-hub-cat-row">' +
    ids
      .map(function (id) {
        const ui = decorEventCatUi(id);
        const on = sel === id;
        return (
          '<button type="button" class="dec-pkg-ev-card' +
          (on ? ' on' : '') +
          '" data-dec-ev="' +
          esc(id) +
          '"><span class="dec-pkg-ev-chk" aria-hidden="true">' +
          (on ? '✓' : '') +
          '</span><span class="dec-pkg-ev-ico" aria-hidden="true">' +
          ui.icon +
          '</span><b>' +
          esc(ui.title) +
          '</b><small>' +
          esc(ui.sub) +
          '</small></button>'
        );
      })
      .join('') +
    '</div>';
  row.querySelectorAll('[data-dec-ev]').forEach(function (btn) {
    btn.onclick = function () {
      const id = btn.getAttribute('data-dec-ev');
      const cur = store.decorationMenu.pkgCategoryFilter || 'all';
      store.decorationMenu.pkgCategoryFilter = cur === id ? 'all' : id;
      saveStore();
      renderDecorPkgCategoryFilters();
      renderDecorPackageList();
    };
  });
}

function renderDecorPkgFilters() {
  const host = el('decPkgFilters');
  if (!host) return;
  const allowed = ['all'].concat(
    DEC_PKG_LEVELS.map(function (l) {
      return l.toLowerCase();
    })
  );
  if (allowed.indexOf(store.decorationMenu.pkgFilter) < 0) store.decorationMenu.pkgFilter = 'all';
  const filters = [{ id: 'all', label: 'All' }].concat(
    DEC_PKG_LEVELS.map(function (l) {
      return { id: l.toLowerCase(), label: l };
    })
  );
  host.innerHTML = filters
    .map(function (f) {
      return (
        '<button type="button"' +
        (store.decorationMenu.pkgFilter === f.id ? ' class="on"' : '') +
        ' data-dec-f="' +
        esc(f.id) +
        '">' +
        esc(f.label) +
        '</button>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dec-f]').forEach(function (btn) {
    btn.onclick = function () {
      store.decorationMenu.pkgFilter = btn.getAttribute('data-dec-f');
      saveStore();
      renderDecorPkgFilters();
      renderDecorPackageList();
    };
  });
}

function renderDecorPackageList() {
  const q = (el('decPkgSearch').value || '').trim().toLowerCase();
  const filter = store.decorationMenu.pkgFilter || 'all';
  const ev = store.decorationMenu.pkgCategoryFilter || 'all';
  let list = (store.decorationMenu.catPackages || []).slice();
  if (filter !== 'all') {
    list = list.filter(function (p) {
      return decorLevelClass(p.level) === filter;
    });
  }
  if (ev !== 'all') {
    list = list.filter(function (p) {
      return (p.packageCategory || 'wedding') === ev;
    });
  }
  if (q) {
    list = list.filter(function (p) {
      return String(p.name || '')
        .toLowerCase()
        .includes(q);
    });
  }
  const host = el('decPkgList');
  if (!host) return;
  el('decHubStat').textContent = list.length + ' package' + (list.length === 1 ? '' : 's');
  if (!list.length) {
    const filtered = filter !== 'all' || ev !== 'all' || q;
    host.innerHTML =
      '<div class="dec-empty"><div class="dec-empty-ico">🎀</div><b>' +
      (filtered ? 'No packages match these filters' : 'No packages yet') +
      '</b><p class="sub">' +
      (filtered
        ? 'Try another tier or category, or clear filters.'
        : 'Create your first decoration package and start getting enquiries.') +
      '</p></div>';
    return;
  }
  host.innerHTML = list
    .map(function (p) {
      const pr = decorPkgListPrice(p);
      const inc = decorPkgCounts(p);
      const priceHtml = pr.pct
        ? '<s style="color:#94A3B8;font-weight:700">' +
          inr(pr.base) +
          '</s> <b>' +
          inr(pr.offer) +
          '</b> <span class="dec-off">-' +
          pr.pct +
          '%</span>'
        : '<b>' + inr(pr.base) + '</b>';
      const lv = decorLevelClass(p.level);
      const levelLabel = p.level || 'Standard';
      return (
        '<article class="dec-pkg-card" data-dec-pkg="' +
        esc(p.id) +
        '"><div class="dec-pkg-thumb' +
        (decorPkgHasCoverPhoto(p) ? ' has-photo' : '') +
        '">' +
        decorPkgThumbInner(p) +
        '</div><div><div class="dec-pkg-chips"><span class="dec-pkg-level ' +
        lv +
        '">' +
        esc(levelLabel) +
        '</span></div><b>' +
        esc(p.name || 'Package') +
        '</b><p class="sub">' +
        esc(decorPkgSummaryLine(p)) +
        ' · ' +
        inc.included +
        ' included, ' +
        inc.extra +
        ' extra</p><div class="dec-pkg-price">' +
        priceHtml +
        '</div><div class="dec-pkg-meta"><span class="dec-pill ' +
        (p.status === 'live' ? 'live' : 'draft') +
        '">' +
        (p.status === 'live' ? 'Live' : 'Draft') +
        '</span></div><div class="dec-card-actions"><button type="button" data-dec-edit="' +
        esc(p.id) +
        '">Edit</button><button type="button" data-dec-del="' +
        esc(p.id) +
        '">Delete</button><button type="button" data-dec-share="' +
        esc(p.id) +
        '">Share</button></div></div></article>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dec-edit]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      startDecorPackageWizard(btn.getAttribute('data-dec-edit'));
    };
  });
  host.querySelectorAll('[data-dec-del]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      const id = btn.getAttribute('data-dec-del');
      if (!confirm('Delete this package?')) return;
      store.decorationMenu.catPackages = store.decorationMenu.catPackages.filter(function (x) {
        return x.id !== id;
      });
      saveStore();
      renderDecorPackageList();
      toast('Package deleted');
    };
  });
  host.querySelectorAll('[data-dec-share]').forEach(function (btn) {
    btn.onclick = function (e) {
      e.stopPropagation();
      toast('Share menu: WhatsApp, PDF, and link (prototype)');
    };
  });
}

function startDecorPackageWizard(editId) {
  decorPkgWizard.editId = editId || null;
  decorPkgWizard.itemsTab = 'included';
  decorPkgWizard.activeModuleId = null;
  const src = editId ? findDecorPackage(editId) : null;
  decorPkgWizard.draft = src ? JSON.parse(JSON.stringify(src)) : newDecorPkgDraft();
  if (!decorPkgWizard.draft.tierPrices) decorPkgWizard.draft.tierPrices = { basic: '', standard: '', premium: '' };
  normalizeDecorPackage(decorPkgWizard.draft);
  renderDecorPkgStep1();
  show('decorPkgStep1');
}

function setDecorWizProgress(step) {
  const active = document.querySelector('.scr.on .dec-progress');
  if (active) {
    let i;
    for (i = 0; i < 5; i++) {
      const dot = active.children[i];
      if (!dot) continue;
      dot.classList.remove('done', 'on');
      if (i < step - 1) dot.classList.add('done');
      else if (i === step - 1) dot.classList.add('on');
    }
  }
  document.querySelectorAll('.dec-wiz-step').forEach(function (lab) {
    if (lab.closest('.scr.on')) lab.textContent = 'Step ' + step + ' of 5';
  });
  const lab = el('decWizStepLabel');
  if (lab) lab.textContent = 'Step ' + step + ' of 5';
}

const DECORATION_EVENT_CAT_UI = {
  wedding: {
    icon: '💍',
    title: 'Wedding & Related',
    sub: 'Wedding, Engagement, Reception',
  },
  other: {
    icon: '📅',
    title: 'Other Functions',
    sub: 'Birthday, Noolukettu, Baptism, etc.',
  },
};

function decorEventCatUi(id) {
  const c = DECORATION_EVENT_CATEGORIES.filter(function (x) {
    return x.id === id;
  })[0];
  const ui = DECORATION_EVENT_CAT_UI[id] || {};
  return {
    icon: ui.icon || '🎀',
    title: ui.title || (c ? c.label : id),
    sub: ui.sub || (c ? c.hint : ''),
  };
}

function renderDecorPkgStep1() {
  setDecorWizProgress(1);
  const host = el('decPkgCatGrid');
  if (!host) return;
  const d = decorPkgWizard.draft;
  host.innerHTML = DECORATION_EVENT_CATEGORIES.map(function (c) {
    const on = d.packageCategory === c.id;
    const ui = decorEventCatUi(c.id);
    return (
      '<button type="button" class="dec-pkg-ev-card' +
      (on ? ' on' : '') +
      '" data-dec-cat="' +
      esc(c.id) +
      '"><span class="dec-pkg-ev-chk" aria-hidden="true">' +
      (on ? '✓' : '') +
      '</span><span class="dec-pkg-ev-ico" aria-hidden="true">' +
      ui.icon +
      '</span><b>' +
      esc(ui.title) +
      '</b><small>' +
      esc(ui.sub) +
      '</small></button>'
    );
  }).join('');
  host.querySelectorAll('[data-dec-cat]').forEach(function (btn) {
    btn.onclick = function () {
      decorPkgWizard.draft.packageCategory = btn.getAttribute('data-dec-cat');
      renderDecorPkgStep1();
    };
  });
}

function decorPkgCategoryMeta(id) {
  const c = DECORATION_EVENT_CATEGORIES.filter(function (x) {
    return x.id === id;
  })[0];
  if (!c) return null;
  const ui = decorEventCatUi(id);
  return {
    id: c.id,
    label: ui.title,
    hint: ui.sub,
  };
}

function syncDecorPkgEventTypesFromCategory(d) {
  if (!d || !d.packageCategory) return;
  d.eventTypes = (DECORATION_EVENT_TYPES[d.packageCategory] || []).slice();
}

function decorPkgSummaryLine(d) {
  const cat = decorPkgCategoryMeta(d.packageCategory);
  const comm = decorFormatTraditionTags(d.traditionTags, d.traditionOtherText);
  const parts = [];
  if (d.level) parts.push(d.level);
  if (cat) parts.push(cat.label);
  if (comm) parts.push(comm);
  return parts.join(' · ') || '—';
}

function updateDecorPkgNamePreview() {
  const d = decorPkgWizard.draft;
  const prev = el('decPkgTitlePreview');
  if (!prev) return;
  const name = (el('decPkgName') && el('decPkgName').value) || d.name || 'Your package name';
  prev.textContent = (d.level || 'Standard') + ' – ' + name;
}

function renderDecorPkgTypeSeg(level) {
  const host = el('decPkgTypeSeg');
  if (!host) return;
  const hints = typeof DECORATION_PKG_LEVEL_HINTS === 'object' ? DECORATION_PKG_LEVEL_HINTS : {};
  host.innerHTML = DEC_PKG_LEVELS.map(function (l) {
    const hint = hints[l] || '';
    return (
      '<button type="button" class="dec-pkg-type-btn' +
      (l === level ? ' on' : '') +
      '" data-dec-lvl="' +
      esc(l) +
      '">' +
      esc(l) +
      (hint ? '<small>' + esc(hint) + '</small>' : '') +
      '</button>'
    );
  }).join('');
  host.querySelectorAll('[data-dec-lvl]').forEach(function (btn) {
    btn.onclick = function () {
      decorPkgWizard.draft.level = btn.getAttribute('data-dec-lvl');
      renderDecorPkgTypeSeg(decorPkgWizard.draft.level);
      updateDecorPkgNamePreview();
    };
  });
}

function renderDecorPkgStep2() {
  setDecorWizProgress(2);
  const d = decorPkgWizard.draft;
  syncDecorPkgEventTypesFromCategory(d);
  const cat = decorPkgCategoryMeta(d.packageCategory);
  el('decPkgCatBanner').textContent = cat ? cat.label : '';
  const hint = el('decPkgCategoryHint');
  if (hint) {
    hint.textContent = cat
      ? cat.hint || 'Function type is set from step 1 — you do not pick individual events here.'
      : 'Pick a category in step 1 first.';
  }
  const commBlock = el('decCommunityBlock');
  const isWedding = d.packageCategory === 'wedding';
  if (commBlock) commBlock.hidden = !isWedding;
  if (!isWedding) {
    d.traditionTags = [];
    d.traditionOtherText = '';
  } else if (!(d.traditionTags || []).length) {
    d.traditionTags = ['Hindu'];
  } else if (d.traditionTags.length > 1) {
    d.traditionTags = [d.traditionTags[0]];
  }
  const sel = (d.traditionTags || [])[0] || '';
  el('decTraditionChips').innerHTML = DECORATION_TRADITIONS.map(function (t) {
    const on = sel === t;
    return '<button type="button" class="dec-chip sm' + (on ? ' on' : '') + '" data-trad="' + esc(t) + '">' + esc(t) + '</button>';
  }).join('');
  renderDecorPkgTypeSeg(d.level || 'Standard');
  el('decPkgName').value = d.name || '';
  el('decPkgDesc').value = d.description || '';
  updateDecorPkgNamePreview();
  const otherWrap = el('decTraditionOtherWrap');
  const otherInp = el('decTraditionOther');
  const hasOthers = decorHasOthersTradition(d.traditionTags);
  if (otherWrap) otherWrap.hidden = !hasOthers;
  if (otherInp) {
    otherInp.value = d.traditionOtherText || '';
    otherInp.oninput = function () {
      decorPkgWizard.draft.traditionOtherText = otherInp.value;
    };
  }
  el('decTraditionChips').querySelectorAll('[data-trad]').forEach(function (btn) {
    btn.onclick = function () {
      const val = btn.getAttribute('data-trad');
      if (decorPkgWizard.draft.traditionTags[0] === val) return;
      decorPkgWizard.draft.traditionTags = [val];
      if (decorTraditionKey(val) !== 'others') decorPkgWizard.draft.traditionOtherText = '';
      renderDecorPkgStep2();
    };
  });
  renderDecorPkgImages();
}

function renderDecorPkgImages() {
  const d = decorPkgWizard.draft;
  ensureDecorPkgImageSlots(d);
  const hasCover = !!d.imageUploaded[0];
  const coverBtn = el('decPkgCoverUpload');
  if (coverBtn) {
    coverBtn.classList.toggle('has-image', hasCover);
  }
  const coverTitle = el('decPkgCoverTitle');
  const coverSub = el('decPkgCoverSub');
  if (coverTitle) coverTitle.textContent = hasCover ? 'Cover photo added' : 'Upload cover photo';
  if (coverSub) coverSub.textContent = hasCover ? 'Tap to change cover' : 'JPG or PNG · demo upload';
  const row = el('decPkgImageRow');
  if (row) {
  let html = '';
  let i;
  for (i = 1; i < d.images.length; i++) {
    const on = !!d.imageUploaded[i];
    html +=
      '<button type="button" class="cover-thumb' +
      (on ? ' on' : '') +
      '" data-dec-img="' +
      i +
      '" aria-label="' +
      (on ? 'Change photo ' + (i + 1) : 'Add photo ' + (i + 1)) +
      '">' +
      (on ? '📷' : '+') +
      '</button>';
  }
    row.innerHTML = html;
    row.querySelectorAll('[data-dec-img]').forEach(function (btn) {
      btn.onclick = function () {
        const idx = +btn.getAttribute('data-dec-img');
        toggleDecorPkgImageSlot(idx);
      };
    });
  }
  const addBtn = el('decPkgAddImage');
  if (addBtn) addBtn.hidden = d.images.length >= DEC_PKG_MAX_IMAGES;
}

function toggleDecorPkgImageSlot(idx) {
  const d = decorPkgWizard.draft;
  ensureDecorPkgImageSlots(d);
  d.imageUploaded[idx] = !d.imageUploaded[idx];
  if (d.imageUploaded[idx] && (!d.images[idx] || d.images[idx] === '🎀')) d.images[idx] = '🖼️';
  renderDecorPkgImages();
  toast(d.imageUploaded[idx] ? 'Photo added (demo).' : 'Photo removed.');
}

function addDecorPkgImageSlot() {
  const d = decorPkgWizard.draft;
  ensureDecorPkgImageSlots(d);
  if (d.images.length >= DEC_PKG_MAX_IMAGES) {
    toast('Up to ' + DEC_PKG_MAX_IMAGES + ' photos per package');
    return;
  }
  d.images.push('🖼️');
  d.imageUploaded.push(false);
  renderDecorPkgImages();
}

function decorSelectedInModule(moduleId) {
  return (decorPkgWizard.draft.items || []).filter(function (it) {
    return it.moduleId === moduleId;
  });
}

function decorModuleItemCounts(moduleId) {
  const items = decorSelectedInModule(moduleId);
  let included = 0;
  let extra = 0;
  items.forEach(function (it) {
    if (it.inclusionType === 'extra') extra++;
    else included++;
  });
  return { total: items.length, included: included, extra: extra };
}

function decorPkgItemsTab() {
  return decorPkgWizard.itemsTab === 'extra' ? 'extra' : 'included';
}

function decOpenOverlay(id) {
  const o = el(id);
  if (!o) return;
  o.classList.add('on');
  o.setAttribute('aria-hidden', 'false');
}

function decCloseOverlay(id) {
  const o = el(id);
  if (!o) return;
  o.classList.remove('on');
  o.setAttribute('aria-hidden', 'true');
}

function decorCategorySearchQuery() {
  const inp = el('decModSearch');
  return inp ? (inp.value || '').trim().toLowerCase() : '';
}

function refreshDecorPkgItemsUi() {
  if (decorModulePickCtx.moduleId) {
    renderDecorModulePick();
  } else {
    renderDecorPkgStep3();
  }
}

function decorCatalogItemBlurb(name) {
  const n = String(name || '').toLowerCase();
  if (n.indexOf('car') >= 0) return 'Artificial floral vehicle décor for the day.';
  if (n.indexOf('stage') >= 0 || n.indexOf('mandap') >= 0) return 'Stage setup with backdrop, trim, and artificial florals.';
  if (n.indexOf('church') >= 0 || n.indexOf('altar') >= 0 || n.indexOf('pew') >= 0) {
    return 'Ceremony styling with artificial florals only.';
  }
  if (n.indexOf('entrance') >= 0 || n.indexOf('welcome') >= 0 || n.indexOf('arch') >= 0) {
    return 'Entrance arch and welcome décor with artificial florals.';
  }
  if (n.indexOf('light') >= 0 || n.indexOf('sound') >= 0) return 'Lighting and ambience for the venue.';
  if (n.indexOf('seat') >= 0 || n.indexOf('chair') >= 0) return 'Seating arrangement and furniture styling.';
  if (n.indexOf('photo') >= 0 || n.indexOf('display') >= 0) return 'Photo walls and display corners.';
  if (n.indexOf('floral') >= 0 || n.indexOf('flower') >= 0 || n.indexOf('bouquet') >= 0 || n.indexOf('garland') >= 0) {
    return 'Artificial floral accents for this area.';
  }
  if (n.indexOf('path') >= 0 || n.indexOf('aisle') >= 0) return 'Walkway and aisle décor with artificial florals.';
  return 'Artificial décor for this part of your event.';
}

function decorFindDraftItemIdx(catalogueId) {
  const items = decorPkgWizard.draft.items || [];
  let i;
  for (i = 0; i < items.length; i++) {
    if (items[i].catalogueId === catalogueId) return i;
  }
  return -1;
}

function ensureDecorPkgActiveModule(moduleRows) {
  if (!moduleRows || !moduleRows.length) {
    decorPkgWizard.activeModuleId = null;
    return null;
  }
  const active = decorPkgWizard.activeModuleId;
  const ok = moduleRows.some(function (r) {
    return r.mod.id === active;
  });
  if (!ok) decorPkgWizard.activeModuleId = moduleRows[0].mod.id;
  return findDecorationModule(decorPkgWizard.activeModuleId);
}

function renderDecorPkgStep3Banner() {
  const d = decorPkgWizard.draft;
  const host = el('decPkgStep3Banner');
  if (!host) return;
  const name = d.name || 'Your package';
  const tags = decorPkgSummaryLine(d);
  host.innerHTML =
    '<div class="body"><b>' +
    esc(name) +
    '</b><div class="tags">' +
    esc(tags) +
    '</div></div><button type="button" id="decPkgStep3Change">Change</button>';
}

function renderDecorItemsTabSeg(opts) {
  opts = opts || {};
  const host = el(opts.host || 'decItemsTabSeg');
  if (!host) return;
  const tab = decorPkgItemsTab();
  const counts = decorPkgCounts(decorPkgWizard.draft);
  host.innerHTML =
    '<button type="button" data-dec-items-tab="included"' +
    (tab === 'included' ? ' class="on"' : '') +
    '><b>Include in Package</b><small>(' +
    counts.included +
    ')</small></button><button type="button" data-dec-items-tab="extra"' +
    (tab === 'extra' ? ' class="on"' : '') +
    '><b>Extra Add-ons</b><small>(' +
    counts.extra +
    ')</small></button>';
  host.querySelectorAll('[data-dec-items-tab]').forEach(function (btn) {
    btn.onclick = function () {
      decorPkgWizard.itemsTab = btn.getAttribute('data-dec-items-tab');
      if (typeof opts.after === 'function') opts.after();
      else renderDecorPkgStep3();
    };
  });
  const hint = el(opts.hint || 'decItemsTabHint');
  if (hint) {
    hint.textContent =
      tab === 'extra'
        ? 'Optional add-ons — customer pays the item price on top of the package.'
        : 'Covered by your package price — customer does not pay extra for these.';
  }
}

function decorRenderCategoryModRows(rows) {
  return rows
    .map(function (row) {
      const m = row.mod;
      const stats = decorModuleItemCounts(m.id);
      let sub;
      if (stats.total) {
        sub = stats.included + ' included' + (stats.extra ? ', ' + stats.extra + ' extra' : '');
      } else {
        sub = row.visibleCount + ' items for this package';
      }
      return (
        '<button type="button" class="dec-mod-row" data-dec-mod="' +
        esc(m.id) +
        '"><span class="dec-mod-ico">' +
        m.emoji +
        '</span><span style="flex:1;min-width:0"><b>' +
        esc(m.name) +
        '</b><small>' +
        esc(sub) +
        '</small></span><span class="dec-chev">›</span></button>'
      );
    })
    .join('');
}

function renderDecorCategoryList(ctx, q) {
  const host = el('decModList');
  if (!host) return;
  const grouped = decorModulesGroupedForPackage(ctx, q);
  const d = decorPkgWizard.draft;
  if (!grouped.all.length) {
    host.innerHTML =
      '<div class="dec-items-empty" style="margin:12px 16px">No categories match. Try another search or update package type / community in step 2.</div>';
    return;
  }
  let html = '';
  if (d.packageCategory === 'wedding' && grouped.community.length) {
    html +=
      '<p class="dec-cat-sec-h">Community-specific categories (' +
      grouped.community.length +
      ')</p>' +
      decorRenderCategoryModRows(grouped.community);
  }
  if (grouped.common.length) {
    html +=
      '<p class="dec-cat-sec-h">' +
      (d.packageCategory === 'wedding' ? 'Common wedding categories (' + grouped.common.length + ')' : 'Categories (' + grouped.common.length + ')') +
      '</p>' +
      decorRenderCategoryModRows(grouped.common);
  }
  host.innerHTML = html;
  host.querySelectorAll('[data-dec-mod]').forEach(function (row) {
    row.onclick = function () {
      openDecorModulePick(row.getAttribute('data-dec-mod'));
    };
  });
}

function renderDecorItemCard(it, mod, tab) {
  const idx = decorFindDraftItemIdx(it.id);
  const row = idx >= 0 ? decorPkgWizard.draft.items[idx] : null;
  const isInc = row && row.inclusionType !== 'extra';
  const isExt = row && row.inclusionType === 'extra';
  const incOn = tab === 'included' && isInc;
  const extOn = tab === 'extra' && isExt;
  const qty = row ? Math.max(1, +row.quantity || 1) : 1;
  const showQty = incOn || extOn;
  let extraLbl = 'Extra';
  if (extOn && row.extraPrice) extraLbl += '<span class="pr">' + inr(row.extraPrice) + ' / ' + esc(row.unit || 'Per Event') + '</span>';
  else if (tab === 'extra') extraLbl += '<span class="pr">Set add-on price</span>';
  const qtyHtml = showQty
    ? '<div class="dec-qty" data-dec-qty-wrap="' +
      esc(it.id) +
      '"><button type="button" data-dec-qty="' +
      esc(it.id) +
      '" data-delta="-1" aria-label="Decrease">−</button><span>' +
      qty +
      '</span><button type="button" data-dec-qty="' +
      esc(it.id) +
      '" data-delta="1" aria-label="Increase">+</button></div>'
    : '';
  return (
    '<div class="dec-item-card"><div class="dec-item-thumb" aria-hidden="true">' +
    mod.emoji +
    '</div><div class="dec-item-card-body"><b>' +
    esc(it.name) +
    '</b><div class="blurb">' +
    esc(decorCatalogItemBlurb(it.name)) +
    '</div><div class="dec-item-actions">' +
    qtyHtml +
    (tab === 'included'
      ? '<button type="button" class="dec-act-inc' +
        (incOn ? ' on' : '') +
        '" data-dec-toggle="include" data-cat-id="' +
        esc(it.id) +
        '">' +
        (incOn ? '✓ Include' : 'Include') +
        '</button>'
      : '') +
    (tab === 'extra'
      ? '<button type="button" class="dec-act-extra' +
        (extOn ? ' on' : '') +
        '" data-dec-toggle="extra" data-cat-id="' +
        esc(it.id) +
        '">' +
        extraLbl +
        '</button>'
      : '') +
    (row && ((tab === 'included' && isExt) || (tab === 'extra' && isInc))
      ? '<button type="button" class="dec-link" data-dec-edit-item="' +
        idx +
        '">Edit</button>'
      : '') +
    '</div></div></div>'
  );
}

function bindDecorItemsPane(host, mod) {
  if (!host || !mod) return;
  host.querySelectorAll('[data-dec-toggle]').forEach(function (btn) {
    btn.onclick = function () {
      const catId = btn.getAttribute('data-cat-id');
      const mode = btn.getAttribute('data-dec-toggle');
      const hit = mod.items.filter(function (x) {
        return x.id === catId;
      })[0];
      if (!hit) return;
      toggleDecorCatalogInclusion(hit, mod, mode);
    };
  });
  host.querySelectorAll('[data-dec-qty]').forEach(function (btn) {
    btn.onclick = function () {
      const catId = btn.getAttribute('data-dec-qty');
      const delta = +btn.getAttribute('data-delta');
      bumpDecorCatalogQty(catId, delta);
    };
  });
  host.querySelectorAll('[data-dec-edit-item]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-edit-item');
      decorItemPickCtx.configuringId = idx;
      const it = decorPkgWizard.draft.items[idx];
      if (it && it.moduleId) decorModulePickCtx.moduleId = it.moduleId;
      renderDecorItemConfig();
      show('decorItemConfig');
    };
  });
}

function toggleDecorCatalogInclusion(catalogueItem, mod, mode) {
  const items = decorPkgWizard.draft.items || [];
  const idx = decorFindDraftItemIdx(catalogueItem.id);
  const wantExtra = mode === 'extra';
  if (idx >= 0) {
    const row = items[idx];
    const sameType = wantExtra ? row.inclusionType === 'extra' : row.inclusionType !== 'extra';
    if (sameType) {
      items.splice(idx, 1);
      decorPkgWizard.draft.items = items;
      refreshDecorPkgItemsUi();
      return;
    }
    toast('This item is already in the other list — open Edit to switch.');
    return;
  }
  const type = wantExtra ? 'extra' : 'included';
  items.push({
    moduleId: mod.id,
    catalogueId: catalogueItem.id,
    name: catalogueItem.name,
    inclusionType: type,
    quantity: 1,
    unit: 'Per Event',
    extraPrice: '',
    description: '',
  });
  decorPkgWizard.draft.items = items;
  decorItemPickCtx.configuringId = items.length - 1;
  if (type === 'extra') {
    renderDecorItemConfig();
    show('decorItemConfig');
    return;
  }
  refreshDecorPkgItemsUi();
}

function bumpDecorCatalogQty(catalogueId, delta) {
  const idx = decorFindDraftItemIdx(catalogueId);
  if (idx < 0) return;
  const it = decorPkgWizard.draft.items[idx];
  it.quantity = Math.max(1, Math.round(+(it.quantity || 1)) + delta);
  refreshDecorPkgItemsUi();
}

function decorIsCustomPackageItem(it) {
  return !!(it && !it.catalogueId);
}

function decorCustomItemsForModule(modId, tab, searchQ) {
  const q = (searchQ || '').trim().toLowerCase();
  const items = decorPkgWizard.draft.items || [];
  const rows = [];
  let idx;
  for (idx = 0; idx < items.length; idx++) {
    const it = items[idx];
    if (!decorIsCustomPackageItem(it) || it.moduleId !== modId) continue;
    const isExtra = it.inclusionType === 'extra';
    if (tab === 'extra' ? !isExtra : isExtra) continue;
    const label = (it.customName || it.name || '').toLowerCase();
    if (q && label.indexOf(q) < 0) continue;
    rows.push({ it: it, idx: idx });
  }
  return rows;
}

function renderDecorCustomItemCard(row, mod, tab) {
  const it = row.it;
  const idx = row.idx;
  const isExtra = it.inclusionType === 'extra';
  const qty = Math.max(1, +it.quantity || 1);
  let extraLbl = 'Extra';
  if (isExtra && it.extraPrice) {
    extraLbl += '<span class="pr">' + inr(it.extraPrice) + ' / ' + esc(it.unit || 'Per Event') + '</span>';
  }
  const blurb = it.description || 'Custom requirement you added for this package.';
  return (
    '<div class="dec-item-card dec-item-custom" data-custom-idx="' +
    idx +
    '"><div class="dec-item-thumb" aria-hidden="true">✨</div><div class="dec-item-card-body"><b>' +
    esc(it.customName || it.name) +
    '<span class="dec-tag-custom">Custom</span></b><div class="blurb">' +
    esc(blurb) +
    '</div><div class="dec-item-actions"><div class="dec-qty"><button type="button" data-dec-custom-qty="' +
    idx +
    '" data-delta="-1" aria-label="Decrease">−</button><span>' +
    qty +
    '</span><button type="button" data-dec-custom-qty="' +
    idx +
    '" data-delta="1" aria-label="Increase">+</button></div>' +
    (tab === 'included'
      ? '<button type="button" class="dec-act-inc on">✓ Include</button>'
      : '<button type="button" class="dec-act-extra on">' +
        extraLbl +
        '</button>') +
    '<button type="button" class="dec-link" data-dec-edit-item="' +
    idx +
    '">Edit</button><button type="button" class="dec-link" data-dec-remove-item="' +
    idx +
    '">Remove</button></div></div></div>'
  );
}

function bindDecorCustomItemCards(host) {
  if (!host) return;
  host.querySelectorAll('[data-dec-custom-qty]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-custom-qty');
      const delta = +btn.getAttribute('data-delta');
      const it = decorPkgWizard.draft.items[idx];
      if (!it) return;
      it.quantity = Math.max(1, Math.round(+(it.quantity || 1)) + delta);
      refreshDecorPkgItemsUi();
    };
  });
  host.querySelectorAll('[data-dec-remove-item]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-remove-item');
      const items = decorPkgWizard.draft.items || [];
      if (idx < 0 || idx >= items.length) return;
      items.splice(idx, 1);
      decorPkgWizard.draft.items = items;
      refreshDecorPkgItemsUi();
      toast('Item removed');
    };
  });
  host.querySelectorAll('[data-dec-edit-item]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-edit-item');
      const it = decorPkgWizard.draft.items[idx];
      if (!it) return;
      decorItemPickCtx.configuringId = idx;
      if (it.moduleId) decorModulePickCtx.moduleId = it.moduleId;
      renderDecorItemConfig();
      show('decorItemConfig');
    };
  });
}

function renderDecorItemSummaryBanner() {
  const host = el('decItemSummaryBanner');
  if (!host) return;
  const counts = decorPkgCounts(decorPkgWizard.draft);
  host.innerHTML =
    '<div class="dec-stat-pill inc"><b>' +
    counts.included +
    '</b>Included</div><div class="dec-stat-pill extra"><b>' +
    counts.extra +
    '</b>Extra</div>';
}

function decorRenderSelItemRow(it, idx) {
  const label = it.customName || it.name;
  const isExtra = it.inclusionType === 'extra';
  const tag = isExtra ? 'Extra' : 'Included';
  const custom = decorIsCustomPackageItem(it) ? ' <span class="dec-tag-custom">Custom</span>' : '';
  const price = isExtra
    ? it.extraPrice
      ? ' — <b>' + inr(it.extraPrice) + '</b> / ' + esc(it.unit || 'Per Event')
      : ' — <span style="color:#BE185D">add price</span>'
    : '';
  const qty = +it.quantity > 1 ? ' · Qty ' + it.quantity : '';
  return (
    '<div class="dec-sel-row"><span><b>' +
    esc(label) +
    '</b>' +
    custom +
    ' <span class="dec-tag ' +
    (isExtra ? 'extra' : 'inc') +
    '">' +
    tag +
    '</span>' +
    price +
    qty +
    '</span><button type="button" class="dec-link" data-dec-edit-item="' +
    idx +
    '">Configure</button></div>'
  );
}

function bindDecorSelItemRows(host) {
  if (!host) return;
  host.querySelectorAll('[data-dec-edit-item]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-edit-item');
      const it = decorPkgWizard.draft.items[idx];
      if (!it) return;
      decorItemPickCtx.configuringId = idx;
      decorItemPickCtx.moduleId = it.moduleId || decorModulePickCtx.moduleId;
      renderDecorItemConfig();
      show('decorItemConfig');
    };
  });
}

function renderDecorPkgStep3() {
  setDecorWizProgress(3);
  const d = decorPkgWizard.draft;
  decorModulePickCtx.moduleId = null;
  renderDecorPkgStep3Banner();
  renderDecorItemsTabSeg();
  const ctx = decorCatalogContextForOwnerPick(d);
  const q = decorCategorySearchQuery();
  renderDecorCategoryList(ctx, q);
  renderDecorSelectedItemsSummary(false);
}

function renderDecorSelectedItemsSummary(full) {
  const d = decorPkgWizard.draft;
  const host = el(full ? 'decSelectedItemsFull' : 'decSelectedItemsCompact');
  if (!host) return;
  const items = d.items || [];
  const tab = full ? 'all' : decorPkgItemsTab();
  const included = [];
  const extra = [];
  let idx;
  for (idx = 0; idx < items.length; idx++) {
    const it = items[idx];
    if (it.inclusionType === 'extra') extra.push({ it: it, idx: idx });
    else included.push({ it: it, idx: idx });
  }
  let rows = tab === 'all' ? included.concat(extra) : tab === 'extra' ? extra : included;
  if (tab === 'all') {
    let html = '';
    if (included.length) {
      html +=
        '<div class="dec-sel-sec"><div class="dec-sel-sec-hd inc">Included</div>' +
        included
          .map(function (row) {
            return decorRenderSelItemRow(row.it, row.idx);
          })
          .join('') +
        '</div>';
    }
    if (extra.length) {
      html +=
        '<div class="dec-sel-sec"><div class="dec-sel-sec-hd extra">Extra</div>' +
        extra
          .map(function (row) {
            return decorRenderSelItemRow(row.it, row.idx);
          })
          .join('') +
        '</div>';
    }
    host.innerHTML = html || '<p class="sub">No items yet.</p>';
    bindDecorSelItemRows(host);
    return;
  }
  if (!rows.length) {
    host.hidden = true;
    host.innerHTML = '';
    return;
  }
  host.hidden = false;
  const title = tab === 'extra' ? 'Your extra add-ons' : 'Added to package';
  host.innerHTML =
    '<div class="dec-sel-sec"><div class="dec-sel-sec-hd ' +
    tab +
    '">' +
    title +
    '</div>' +
    rows
      .map(function (row) {
        return decorRenderSelItemRow(row.it, row.idx);
      })
      .join('') +
    '</div>';
  bindDecorSelItemRows(host);
}

function openDecorModulePick(moduleId) {
  decorPkgWizard.activeModuleId = moduleId;
  decorModulePickCtx = { moduleId: moduleId, search: '', pickMode: decorPkgItemsTab() };
  renderDecorModulePick();
  show('decorModPick');
}

function decorDefaultInclusionType() {
  if (decorModulePickCtx && decorModulePickCtx.pickMode === 'extra') return 'extra';
  if (decorPkgItemsTab() === 'extra') return 'extra';
  return 'included';
}

function renderDecorModulePick() {
  setDecorWizProgress(3);
  renderDecorItemsTabSeg({
    host: 'decPickItemsTabSeg',
    hint: 'decPickItemsTabHint',
    after: function () {
      renderDecorModulePick();
    },
  });
  const mod = findDecorationModule(decorModulePickCtx.moduleId);
  if (!mod) return;
  const title = el('decPickModTitle');
  if (title) title.textContent = mod.name;
  const q = (decorModulePickCtx.search || '').trim().toLowerCase();
  const picked = decorSelectedInModule(mod.id);
  const tab = decorPkgItemsTab();
  const pickedTab = picked.filter(function (it) {
    return tab === 'extra' ? it.inclusionType === 'extra' : it.inclusionType !== 'extra';
  }).length;
  const ctx = decorCatalogContextForOwnerPick(decorPkgWizard.draft);
  const list = decorFilteredModuleItems(mod, ctx, q);
  el('decPickModCount').textContent =
    pickedTab +
    ' in this tab · ' +
    list.length +
    ' items shown';
  const host = el('decPickModList');
  const customRows = decorCustomItemsForModule(mod.id, tab, q);
  let html = list
    .map(function (it) {
      return renderDecorItemCard(it, mod, tab);
    })
    .join('');
  if (customRows.length) {
    html +=
      '<p class="dec-custom-sec-hd">Your custom items</p>' +
      customRows
        .map(function (row) {
          return renderDecorCustomItemCard(row, mod, tab);
        })
        .join('');
  }
  if (!html) {
    host.innerHTML =
      '<p class="dec-items-empty">No items here for your package. Add a custom item below.</p>';
  } else {
    host.innerHTML = html;
    bindDecorItemsPane(host, mod);
    bindDecorCustomItemCards(host);
  }
  el('decPickModSearch').value = decorModulePickCtx.search || '';
}

function renderDecorItemConfig() {
  const idx = decorItemPickCtx.configuringId;
  const it = idx != null ? decorPkgWizard.draft.items[idx] : null;
  if (!it) return;
  el('decItemCfgTitle').textContent = it.customName || it.name || 'Item';
  el('decIncIncluded').checked = it.inclusionType !== 'extra';
  el('decIncExtra').checked = it.inclusionType === 'extra';
  el('decExtraPriceWrap').hidden = it.inclusionType !== 'extra';
  el('decItemExtraPrice').value = it.extraPrice === '' || it.extraPrice == null ? '' : it.extraPrice;
  el('decItemUnit').innerHTML = DECORATION_UNITS.map(function (u) {
    return '<option' + (it.unit === u ? ' selected' : '') + '>' + esc(u) + '</option>';
  }).join('');
  el('decItemQty').value = it.quantity || 1;
  el('decItemNote').value = it.description || '';
}

function saveDecorItemConfig() {
  const idx = decorItemPickCtx.configuringId;
  const it = decorPkgWizard.draft.items[idx];
  if (!it) return;
  it.inclusionType = el('decIncExtra').checked ? 'extra' : 'included';
  if (it.inclusionType === 'extra') {
    const p = Math.round(+el('decItemExtraPrice').value || 0);
    if (!p) {
      toast('Extra price is required for add-ons');
      return;
    }
    it.extraPrice = p;
    it.unit = el('decItemUnit').value;
  } else {
    it.extraPrice = '';
  }
  it.quantity = Math.max(1, Math.round(+el('decItemQty').value || 1));
  it.description = (el('decItemNote').value || '').trim();
  if (decorModulePickCtx.moduleId) {
    show('decorModPick');
    renderDecorModulePick();
  } else {
    show('decorPkgStep3');
  }
  renderDecorPkgStep3();
}

function renderDecorCustomSheetFields() {
  const ctx = decorCatalogContextForOwnerPick(decorPkgWizard.draft);
  const rows = decorModulesForPackage(ctx, '');
  const sel = el('decCustomSheetCategory');
  if (sel) {
    const active = decorPkgWizard.activeModuleId;
    sel.innerHTML = rows
      .map(function (row) {
        return (
          '<option value="' +
          esc(row.mod.id) +
          '"' +
          (row.mod.id === active ? ' selected' : '') +
          '>' +
          row.mod.emoji +
          ' ' +
          esc(row.mod.name) +
          '</option>'
        );
      })
      .join('');
  }
  const unitSel = el('decCustomSheetUnit');
  if (unitSel) {
    unitSel.innerHTML = DECORATION_UNITS.map(function (u) {
      return '<option>' + esc(u) + '</option>';
    }).join('');
  }
  const inc = decorPkgItemsTab() !== 'extra';
  if (el('decCustomSheetInc')) el('decCustomSheetInc').checked = inc;
  if (el('decCustomSheetExtra')) el('decCustomSheetExtra').checked = !inc;
  if (el('decCustomExtraWrap')) el('decCustomExtraWrap').hidden = inc;
}

function openDecorCustomItemSheet() {
  renderDecorCustomSheetFields();
  if (el('decCustomSheetName')) el('decCustomSheetName').value = '';
  if (el('decCustomSheetLocation')) el('decCustomSheetLocation').value = '';
  if (el('decCustomSheetQty')) el('decCustomSheetQty').value = '1';
  if (el('decCustomSheetExtraPrice')) el('decCustomSheetExtraPrice').value = '';
  if (el('decCustomSheetNote')) el('decCustomSheetNote').value = '';
  decOpenOverlay('decCustomItemOverlay');
}

function saveDecorCustomItemFromSheet() {
  const name = (el('decCustomSheetName').value || '').trim();
  if (!name) {
    toast('Enter item name');
    return;
  }
  const modId = el('decCustomSheetCategory').value;
  const mod = findDecorationModule(modId);
  if (!mod) {
    toast('Pick a category');
    return;
  }
  const isExtra = el('decCustomSheetExtra').checked;
  const placement = (el('decCustomSheetLocation').value || '').trim();
  const note = (el('decCustomSheetNote').value || '').trim();
  let extraPrice = '';
  if (isExtra) {
    const p = Math.round(+el('decCustomSheetExtraPrice').value || 0);
    if (!p) {
      toast('Extra price is required');
      return;
    }
    extraPrice = p;
  }
  decorPkgWizard.draft.items = decorPkgWizard.draft.items || [];
  const descParts = [];
  if (placement) descParts.push('Placement: ' + placement);
  if (note) descParts.push(note);
  decorPkgWizard.draft.items.push({
    moduleId: mod.id,
    catalogueId: '',
    customName: name,
    name: name,
    inclusionType: isExtra ? 'extra' : 'included',
    quantity: Math.max(1, Math.round(+el('decCustomSheetQty').value || 1)),
    unit: el('decCustomSheetUnit').value || 'Per Event',
    extraPrice: extraPrice,
    description: descParts.join(' · '),
  });
  decCloseOverlay('decCustomItemOverlay');
  refreshDecorPkgItemsUi();
  toast('Custom item added');
}

function addDecorCustomItem() {
  const name = (el('decCustomItemName').value || '').trim();
  if (!name) {
    toast('Enter custom item name');
    return;
  }
  const mod = findDecorationModule(decorModulePickCtx.moduleId);
  if (!mod) return;
  decorPkgWizard.draft.items = decorPkgWizard.draft.items || [];
  const type = decorDefaultInclusionType();
  decorPkgWizard.draft.items.push({
    moduleId: mod.id,
    catalogueId: '',
    customName: name,
    name: name,
    inclusionType: type,
    quantity: 1,
    unit: 'Per Event',
    extraPrice: '',
    description: '',
  });
  el('decCustomItemName').value = '';
  decorItemPickCtx.configuringId = decorPkgWizard.draft.items.length - 1;
  renderDecorItemConfig();
  show('decorItemConfig');
  if (type !== 'extra') {
    el('decIncIncluded').checked = true;
    el('decIncExtra').checked = false;
    el('decExtraPriceWrap').hidden = true;
  } else {
    el('decIncIncluded').checked = false;
    el('decIncExtra').checked = true;
    el('decExtraPriceWrap').hidden = false;
  }
}

function renderDecorPkgStep4() {
  setDecorWizProgress(4);
  const d = decorPkgWizard.draft;
  const lvl = d.level || 'Standard';
  const priceLab = el('decPkgPriceLabel');
  if (priceLab) priceLab.textContent = lvl + ' package amount (₹) *';
  const intro = el('decPkgPriceIntro');
  if (intro) {
    intro.textContent =
      'Price for this ' + lvl + ' package. Add a separate package card for each level (Basic, Standard, Premium).';
  }
  const lp = d.listPrice;
  el('decPkgListPrice').value = lp === '' || lp == null ? '' : lp;
  el('decOfferOn').checked = !!d.offerEnabled;
  el('decOfferFields').hidden = !d.offerEnabled;
  el('decOfferPct').value = d.discountPercent === '' || d.discountPercent == null ? '' : d.discountPercent;
  if (!d.gstTreatment) d.gstTreatment = 'Included';
  paintDecorTierPreview();
}

function decorOfferPctFromUi(draft) {
  const d = draft || decorPkgWizard.draft || {};
  const offerOn = el('decOfferOn') ? el('decOfferOn').checked : !!d.offerEnabled;
  if (!offerOn) return 0;
  const raw = el('decOfferPct') ? el('decOfferPct').value : d.discountPercent;
  const n = Math.round(+raw);
  return n >= 1 && n <= 90 ? n : 0;
}

function decorBasePriceFromUi(draft) {
  const d = draft || decorPkgWizard.draft || {};
  const raw = el('decPkgListPrice') ? el('decPkgListPrice').value : d.listPrice;
  return Math.round(+raw || 0);
}

function paintDecorTierPreview() {
  const d = decorPkgWizard.draft;
  const base = decorBasePriceFromUi(d);
  const pct = decorOfferPctFromUi(d);
  const offerOn = el('decOfferOn') ? el('decOfferOn').checked : !!d.offerEnabled;
  const live = el('decOfferLivePreview');
  if (live) {
    if (!offerOn) {
      live.hidden = true;
      live.innerHTML = '';
    } else if (!base) {
      live.hidden = false;
      live.innerHTML = '<p class="sub" style="margin:0">Enter the package amount above first.</p>';
    } else if (!pct) {
      live.hidden = false;
      live.innerHTML = '<p class="sub" style="margin:0">Type discount % — original and offer price will show here.</p>';
    } else {
      const off = decorPriceAfterOffer(base, pct);
      live.hidden = false;
      live.innerHTML =
        '<p class="lbl">Customer sees</p><div class="dec-offer-price"><s>' +
        inr(base) +
        '</s><b>' +
        inr(off) +
        '</b><span class="dec-off">-' +
        pct +
        '%</span></div>';
    }
  }
  const host = el('decTierPreview');
  if (!host) return;
  if (!base) {
    host.innerHTML = '<p class="sub">Enter the package amount above.</p>';
    return;
  }
  const off = decorPriceAfterOffer(base, pct);
  host.innerHTML =
    '<p class="lbl" style="margin:0 0 8px">Summary</p><div class="dec-tier-row"><span>' +
    esc(d.level || 'Standard') +
    ' package</span><span class="dec-offer-price">' +
    (pct
      ? '<s>' + inr(base) + '</s> <b>' + inr(off) + '</b> <span class="dec-off">-' + pct + '%</span>'
      : '<b>' + inr(base) + '</b>') +
    '</span></div>';
}

function syncDecorTierFromInputs() {
  const d = decorPkgWizard.draft;
  const raw = el('decPkgListPrice') ? el('decPkgListPrice').value : '';
  d.listPrice = raw === '' ? '' : Math.round(+raw);
  const key = decorLevelClass(d.level);
  d.tierPrices = { basic: '', standard: '', premium: '' };
  if (+d.listPrice > 0) d.tierPrices[key] = d.listPrice;
  d.offerEnabled = !!el('decOfferOn').checked;
  if (d.offerEnabled) {
    const offerRaw = el('decOfferPct').value;
    d.discountPercent = offerRaw === '' ? '' : Math.round(+offerRaw);
  } else {
    d.discountPercent = '';
  }
  paintDecorTierPreview();
}

function renderDecorPkgStep5() {
  setDecorWizProgress(5);
  const d = decorPkgWizard.draft;
  const pr = decorPkgListPrice(d);
  const counts = decorPkgCounts(d);
  const inc = (d.items || []).filter(function (it) {
    return it.inclusionType !== 'extra';
  });
  const extra = (d.items || []).filter(function (it) {
    return it.inclusionType === 'extra';
  });
  let html =
    '<div class="' +
    decorPkgHeroClass(d).trim() +
    '">' +
    (decorPkgHasCoverPhoto(d) ? '' : d.images && d.images[0] ? d.images[0] : '🎀') +
    '</div><h2 style="margin:8px 0;font-size:18px;color:var(--decor-navy)">' +
    esc(d.name) +
    '</h2><p class="sub">' +
    esc(decorPkgSummaryLine(d)) +
    '</p><div class="dec-preview-price">' +
    (pr.pct
      ? '<s>' + inr(pr.base) + '</s> <b>' + inr(pr.offer) + '</b> <span class="dec-off">-' + pr.pct + '%</span>'
      : '<b>' + inr(pr.base) + '</b>') +
    '</div>';
  html +=
    '<p class="dec-sec-h">Package price</p><div class="dec-tier-row"><span>' +
    esc(d.level || 'Standard') +
    '</span><span class="dec-offer-price">' +
    (pr.pct
      ? '<s>' + inr(pr.base) + '</s> <b>' + inr(pr.offer) + '</b> <span class="dec-off">-' + pr.pct + '%</span>'
      : '<b>' + inr(pr.base) + '</b>') +
    '</span></div>';
  html += '<p class="dec-sec-h">Inclusions (' + inc.length + ')</p><ul class="dec-ul">';
  inc.forEach(function (it) {
    html += '<li>' + esc(it.customName || it.name) + '</li>';
  });
  html += '</ul><p class="dec-sec-h">Optional / Extra (' + extra.length + ')</p><ul class="dec-ul">';
  extra.forEach(function (it) {
    html +=
      '<li>' +
      esc(it.customName || it.name) +
      ' — ' +
      inr(it.extraPrice) +
      ' / ' +
      esc(it.unit || 'Per Event') +
      '</li>';
  });
  el('decPkgPreviewBody').innerHTML = html;
}

function validateDecorPkgStep(step) {
  const d = decorPkgWizard.draft;
  if (step === 1 && !d.packageCategory) {
    toast('Select a package category');
    return false;
  }
  if (step === 2) {
    syncDecorPkgEventTypesFromCategory(d);
    if (!d.level || DEC_PKG_LEVELS.indexOf(d.level) < 0) {
      toast('Select package level (Basic, Standard or Premium)');
      return false;
    }
    if (d.packageCategory === 'wedding') {
      if (!(d.traditionTags || []).length) {
        toast('Select one community for this wedding package');
        return false;
      }
      if (d.traditionTags.length > 1) d.traditionTags = [d.traditionTags[0]];
      if (decorHasOthersTradition(d.traditionTags) && !(d.traditionOtherText || '').trim()) {
        toast('Specify other community');
        return false;
      }
      if (decorHasOthersTradition(d.traditionTags)) {
        d.traditionOtherText = (d.traditionOtherText || '').trim();
      } else {
        d.traditionOtherText = '';
      }
    } else {
      d.traditionTags = [];
      d.traditionOtherText = '';
    }
    if (!(d.name || '').trim()) {
      toast('Package name is required');
      return false;
    }
    d.name = d.name.trim();
  }
  if (step === 3 && !(d.items || []).length) {
    toast('Add at least one decoration item');
    return false;
  }
  if (step === 4) {
    syncDecorTierFromInputs();
    if (!(+d.listPrice > 0)) {
      toast('Enter package amount (₹)');
      return false;
    }
    if (d.offerEnabled) {
      const n = Math.round(+d.discountPercent);
      if (!(n >= 1 && n <= 90)) {
        toast('Discount must be 1–90%');
        return false;
      }
    }
  }
  return true;
}

function saveDecorPackage(status) {
  const d = decorPkgWizard.draft;
  d.status = status || 'live';
  if (!d.id) d.id = uid('dpkg');
  const i = store.decorationMenu.catPackages.findIndex(function (p) {
    return p.id === d.id;
  });
  const copy = JSON.parse(JSON.stringify(d));
  if (i >= 0) store.decorationMenu.catPackages[i] = copy;
  else store.decorationMenu.catPackages.unshift(copy);
  saveStore();
  if (status === 'live') {
    renderDecorPkgSuccess(copy);
    show('decorPkgSuccess');
  } else {
    toast('Draft saved');
    decorationMenuOpenHub();
  }
}

function renderDecorPkgSuccess(pkg) {
  el('decSuccessCard').innerHTML =
    '<b>' + esc(pkg.name) + '</b><p class="sub">' + esc(decorPkgSummaryLine(pkg)) + '</p>';
}

function bindDecorationPackageUi() {
  bindClick('decAddPackageBtn', function () {
    startDecorPackageWizard(null);
  });
  bindClick('decTabPackages', function () {
    store.decorationMenu.hubTab = 'packages';
    renderDecorationHub();
  });
  bindClick('decTabServices', function () {
    store.decorationMenu.hubTab = 'services';
    renderDecorationHub();
  });
  bindClick('decPkgStep1Next', function () {
    if (!validateDecorPkgStep(1)) return;
    renderDecorPkgStep2();
    show('decorPkgStep2');
  });
  bindClick('decPkgStep1Back', function () {
    decorationMenuOpenHub();
  });
  bindClick('decPkgChangeCategory', function () {
    show('decorPkgStep1');
  });
  bindClick('decPkgStep2Back', function () {
    renderDecorPkgStep1();
    show('decorPkgStep1');
  });
  bindClick('decPkgStep2Back2', function () {
    renderDecorPkgStep1();
    show('decorPkgStep1');
  });
  bindClick('decPkgStep2Next', function () {
    decorPkgWizard.draft.name = (el('decPkgName').value || '').trim();
    decorPkgWizard.draft.description = (el('decPkgDesc').value || '').trim();
    if (el('decTraditionOther')) decorPkgWizard.draft.traditionOtherText = el('decTraditionOther').value;
    if (!validateDecorPkgStep(2)) return;
    renderDecorPkgStep3();
    show('decorPkgStep3');
  });
  bindOnInput('decPkgName', updateDecorPkgNamePreview);
  bindClick('decPkgCoverUpload', function () {
    toggleDecorPkgImageSlot(0);
  });
  bindClick('decPkgAddImage', addDecorPkgImageSlot);
  bindClick('decPkgStep3Back', function () {
    renderDecorPkgStep2();
    show('decorPkgStep2');
  });
  bindClick('decPkgStep3BackFoot', function () {
    renderDecorPkgStep2();
    show('decorPkgStep2');
  });
  bindClick('decPkgStep3Next', function () {
    if (!validateDecorPkgStep(3)) return;
    renderDecorPkgStep4();
    show('decorPkgStep4');
  });
  bindClick('decPkgStep3Change', function () {
    renderDecorPkgStep2();
    show('decorPkgStep2');
  });
  bindOnInput('decModSearch', function () {
    renderDecorPkgStep3();
  });
  bindClick('decOpenCustomItem', openDecorCustomItemSheet);
  bindClick('decPickOpenCustom', openDecorCustomItemSheet);
  bindClick('decCustomClose', function () {
    decCloseOverlay('decCustomItemOverlay');
  });
  bindClick('decCustomSave', saveDecorCustomItemFromSheet);
  bindClick('decCustomSheetInc', function () {
    el('decCustomSheetExtra').checked = false;
    el('decCustomExtraWrap').hidden = true;
  });
  bindClick('decCustomSheetExtra', function () {
    el('decCustomSheetInc').checked = false;
    el('decCustomExtraWrap').hidden = false;
  });
  bindClick('decModPickBack', function () {
    show('decorPkgStep3');
    renderDecorPkgStep3();
  });
  bindClick('decModPickDone', function () {
    show('decorPkgStep3');
    renderDecorPkgStep3();
  });
  bindOnInput('decPickModSearch', function () {
    decorModulePickCtx.search = el('decPickModSearch').value;
    renderDecorModulePick();
  });
  bindClick('decCustomItemAdd', addDecorCustomItem);
  bindClick('decItemCfgBack', function () {
    if (decorModulePickCtx.moduleId) show('decorModPick');
    else show('decorPkgStep3');
  });
  bindClick('decItemCfgSave', saveDecorItemConfig);
  bindClick('decIncIncluded', function () {
    el('decIncExtra').checked = false;
    el('decExtraPriceWrap').hidden = true;
  });
  bindClick('decIncExtra', function () {
    el('decIncIncluded').checked = false;
    el('decExtraPriceWrap').hidden = false;
  });
  bindClick('decPkgStep4Back', function () {
    renderDecorPkgStep3();
    show('decorPkgStep3');
  });
  bindClick('decPkgStep4Back2', function () {
    renderDecorPkgStep3();
    show('decorPkgStep3');
  });
  bindClick('decPkgStep4Next', function () {
    if (!validateDecorPkgStep(4)) return;
    renderDecorPkgStep5();
    show('decorPkgStep5');
  });
  bindOnInput('decPkgListPrice', syncDecorTierFromInputs);
  bindOnInput('decOfferPct', syncDecorTierFromInputs);
  bindClick('decOfferOn', function () {
    el('decOfferFields').hidden = !el('decOfferOn').checked;
    syncDecorTierFromInputs();
  });
  bindClick('decPkgStep5Back', function () {
    renderDecorPkgStep4();
    show('decorPkgStep4');
  });
  bindClick('decPkgPublish', function () {
    if (!validateDecorPkgStep(4)) return;
    saveDecorPackage('live');
  });
  bindClick('decPkgSaveDraft', function () {
    saveDecorPackage('draft');
  });
  bindClick('decorPkgSuccessDone', function () {
    decorationMenuOpenHub();
  });
  bindClick('decHubBack', function () {
    show('decorDash');
  });
}