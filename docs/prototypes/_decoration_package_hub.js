/** Decoration packages hub + 5-step wizard (tier amounts: Basic / Standard / Premium). */

const DEC_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];

let decorPkgWizard = { editId: null, draft: null };
let decorModulePickCtx = { moduleId: null, search: '' };
let decorItemPickCtx = { moduleId: null, configuringId: null, customName: '' };

function ensureDecorationStore() {
  if (!store.decorationMenu) store.decorationMenu = defaultDecorationStore();
  if (!store.decorationMenu.catPackages) store.decorationMenu.catPackages = [];
  if (!store.decorationMenu.individualServices) store.decorationMenu.individualServices = [];
}

function newDecorPkgDraft() {
  return {
    packageCategory: 'wedding',
    eventTypes: [],
    traditionTags: [],
    ceremonySetup: [],
    styles: [],
    name: '',
    description: '',
    images: ['🎀'],
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
  if (tab === 'packages') renderDecorPackageList();
  else if (typeof renderDecorIndividualList === 'function') renderDecorIndividualList();
}

function renderDecorPackageList() {
  const q = (el('decPkgSearch').value || '').trim().toLowerCase();
  const filter = store.decorationMenu.pkgFilter || 'all';
  let list = (store.decorationMenu.catPackages || []).slice();
  if (filter !== 'all') {
    list = list.filter(function (p) {
      return String(p.packageCategory || '') === filter || String(p.level || '').toLowerCase() === filter.toLowerCase();
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
    host.innerHTML =
      '<div class="dec-empty"><div class="dec-empty-ico">🎀</div><b>No packages yet</b><p class="sub">Create your first decoration package and start getting enquiries.</p></div>';
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
      return (
        '<article class="dec-pkg-card" data-dec-pkg="' +
        esc(p.id) +
        '"><div class="dec-pkg-thumb">' +
        (p.images && p.images[0] ? p.images[0] : '🎀') +
        '</div><div><b>' +
        esc(p.name || 'Package') +
        '</b><p class="sub">' +
        esc((p.eventTypes || []).slice(0, 2).join(', ') || '—') +
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
  const src = editId ? findDecorPackage(editId) : null;
  decorPkgWizard.draft = src ? JSON.parse(JSON.stringify(src)) : newDecorPkgDraft();
  if (!decorPkgWizard.draft.tierPrices) decorPkgWizard.draft.tierPrices = { basic: '', standard: '', premium: '' };
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

function renderDecorPkgStep1() {
  setDecorWizProgress(1);
  const host = el('decPkgCatGrid');
  if (!host) return;
  const d = decorPkgWizard.draft;
  host.innerHTML = DECORATION_EVENT_CATEGORIES.map(function (c) {
    const on = d.packageCategory === c.id;
    return (
      '<button type="button" class="dec-cat-card' +
      (on ? ' on' : '') +
      '" data-dec-cat="' +
      esc(c.id) +
      '"><b>' +
      esc(c.label) +
      '</b><small>' +
      esc(c.hint) +
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

function renderDecorPkgStep2() {
  setDecorWizProgress(2);
  const d = decorPkgWizard.draft;
  const cat = DECORATION_EVENT_CATEGORIES.filter(function (c) {
    return c.id === d.packageCategory;
  })[0];
  el('decPkgCatBanner').textContent = cat ? cat.label : '';
  const types = DECORATION_EVENT_TYPES[d.packageCategory] || [];
  el('decEventTypeChips').innerHTML = types
    .map(function (t) {
      const on = (d.eventTypes || []).indexOf(t) >= 0;
      return '<button type="button" class="dec-chip' + (on ? ' on' : '') + '" data-ev="' + esc(t) + '">' + esc(t) + '</button>';
    })
    .join('');
  el('decTraditionChips').innerHTML = DECORATION_TRADITIONS.map(function (t) {
    const on = (d.traditionTags || []).indexOf(t) >= 0;
    return '<button type="button" class="dec-chip sm' + (on ? ' on' : '') + '" data-trad="' + esc(t) + '">' + esc(t) + '</button>';
  }).join('');
  el('decStyleChips').innerHTML = DECORATION_STYLES.map(function (t) {
    const on = (d.styles || []).indexOf(t) >= 0;
    return '<button type="button" class="dec-chip sm' + (on ? ' on' : '') + '" data-style="' + esc(t) + '">' + esc(t) + '</button>';
  }).join('');
  el('decPkgName').value = d.name || '';
  el('decPkgDesc').value = d.description || '';
  el('decPkgTitlePreview').textContent = d.name || 'Your package name';
  function bindChip(sel, attr, arrKey) {
    el(sel).querySelectorAll('[data-' + attr + ']').forEach(function (btn) {
      btn.onclick = function () {
        const val = btn.getAttribute('data-' + attr);
        const arr = decorPkgWizard.draft[arrKey] || [];
        const i = arr.indexOf(val);
        if (i >= 0) arr.splice(i, 1);
        else arr.push(val);
        decorPkgWizard.draft[arrKey] = arr;
        renderDecorPkgStep2();
      };
    });
  }
  bindChip('decEventTypeChips', 'ev', 'eventTypes');
  bindChip('decTraditionChips', 'trad', 'traditionTags');
  bindChip('decStyleChips', 'style', 'styles');
}

function decorSelectedInModule(moduleId) {
  return (decorPkgWizard.draft.items || []).filter(function (it) {
    return it.moduleId === moduleId;
  });
}

function renderDecorPkgStep3() {
  setDecorWizProgress(3);
  const d = decorPkgWizard.draft;
  const counts = decorPkgCounts(d);
  el('decItemSummaryBanner').textContent =
    counts.total + ' items (' + counts.included + ' included, ' + counts.extra + ' extra)';
  const q = (el('decModSearch').value || '').trim().toLowerCase();
  const host = el('decModList');
  host.innerHTML = DECORATION_MODULES.filter(function (m) {
    if (!q) return true;
    return m.name.toLowerCase().indexOf(q) >= 0;
  })
    .map(function (m) {
      const sel = decorSelectedInModule(m.id).length;
      return (
        '<button type="button" class="dec-mod-row" data-dec-mod="' +
        esc(m.id) +
        '"><span class="dec-mod-ico">' +
        m.emoji +
        '</span><span style="flex:1;min-width:0"><b>' +
        esc(m.name) +
        '</b><small>' +
        sel +
        ' selected</small></span><span class="dec-chev">›</span></button>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dec-mod]').forEach(function (row) {
    row.onclick = function () {
      openDecorModulePick(row.getAttribute('data-dec-mod'));
    };
  });
  renderDecorSelectedItemsSummary(false);
}

function renderDecorSelectedItemsSummary(full) {
  const d = decorPkgWizard.draft;
  const host = el(full ? 'decSelectedItemsFull' : 'decSelectedItemsCompact');
  if (!host) return;
  const items = d.items || [];
  if (!items.length) {
    host.innerHTML = '<p class="sub">No items yet. Open a category above.</p>';
    return;
  }
  host.innerHTML = items
    .map(function (it, idx) {
      const label = it.customName || it.name;
      const tag = it.inclusionType === 'extra' ? 'Extra' : 'Included';
      const price = it.inclusionType === 'extra' && it.extraPrice ? ' · ' + inr(it.extraPrice) + ' / ' + esc(it.unit || 'Per Event') : '';
      return (
        '<div class="dec-sel-row"><span><b>' +
        esc(label) +
        '</b> <span class="dec-tag ' +
        (it.inclusionType === 'extra' ? 'extra' : 'inc') +
        '">' +
        tag +
        '</span>' +
        price +
        '</span><button type="button" class="dec-link" data-dec-edit-item="' +
        idx +
        '">Edit</button></div>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dec-edit-item]').forEach(function (btn) {
    btn.onclick = function () {
      const idx = +btn.getAttribute('data-dec-edit-item');
      const it = decorPkgWizard.draft.items[idx];
      if (!it) return;
      decorItemPickCtx.configuringId = idx;
      renderDecorItemConfig();
      show('decorItemConfig');
    };
  });
}

function openDecorModulePick(moduleId) {
  decorModulePickCtx = { moduleId: moduleId, search: '' };
  renderDecorModulePick();
  show('decorModPick');
}

function renderDecorModulePick() {
  const mod = findDecorationModule(decorModulePickCtx.moduleId);
  if (!mod) return;
  el('decPickModTitle').textContent = mod.name;
  const q = (decorModulePickCtx.search || '').trim().toLowerCase();
  const picked = decorSelectedInModule(mod.id);
  el('decPickModCount').textContent = picked.length + ' selected';
  const list = mod.items.filter(function (it) {
    return !q || it.name.toLowerCase().indexOf(q) >= 0;
  });
  const host = el('decPickModList');
  host.innerHTML = list
    .map(function (it) {
      const row = (decorPkgWizard.draft.items || []).find(function (x) {
        return x.catalogueId === it.id;
      });
      const on = !!row;
      const tag = row ? (row.inclusionType === 'extra' ? 'Extra' : 'Included') : '';
      return (
        '<label class="dec-pick-row' +
        (on ? ' on' : '') +
        '"><input type="checkbox" data-pick-id="' +
        esc(it.id) +
        '"' +
        (on ? ' checked' : '') +
        '><span><b>' +
        esc(it.name) +
        '</b>' +
        (tag ? ' <span class="dec-tag ' + (row.inclusionType === 'extra' ? 'extra' : 'inc') + '">' + tag + '</span>' : '') +
        '</span></label>'
      );
    })
    .join('');
  host.querySelectorAll('input[type=checkbox]').forEach(function (cb) {
    cb.onchange = function () {
      const id = cb.getAttribute('data-pick-id');
      const hit = mod.items.filter(function (x) {
        return x.id === id;
      })[0];
      if (!hit) return;
      let items = decorPkgWizard.draft.items || [];
      const i = items.findIndex(function (x) {
        return x.catalogueId === id;
      });
      if (cb.checked) {
        if (i < 0) {
          items.push({
            moduleId: mod.id,
            catalogueId: id,
            name: hit.name,
            inclusionType: 'included',
            quantity: 1,
            unit: 'Per Event',
            extraPrice: '',
            description: '',
          });
        }
      } else if (i >= 0) items.splice(i, 1);
      decorPkgWizard.draft.items = items;
      renderDecorModulePick();
      renderDecorPkgStep3();
    };
  });
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
  show(decorModulePickCtx.moduleId ? 'decorModPick' : 'decorPkgStep3');
  renderDecorModulePick();
  renderDecorPkgStep3();
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
  decorPkgWizard.draft.items.push({
    moduleId: mod.id,
    catalogueId: '',
    customName: name,
    name: name,
    inclusionType: 'included',
    quantity: 1,
    unit: 'Per Event',
    extraPrice: '',
    description: '',
  });
  el('decCustomItemName').value = '';
  decorItemPickCtx.configuringId = decorPkgWizard.draft.items.length - 1;
  renderDecorItemConfig();
  show('decorItemConfig');
}

function renderDecorPkgStep4() {
  setDecorWizProgress(4);
  const d = decorPkgWizard.draft;
  const t = d.tierPrices || {};
  el('decPriceBasic').value = t.basic === '' || t.basic == null ? '' : t.basic;
  el('decPriceStandard').value = t.standard === '' || t.standard == null ? '' : t.standard;
  el('decPricePremium').value = t.premium === '' || t.premium == null ? '' : t.premium;
  el('decOfferOn').checked = !!d.offerEnabled;
  el('decOfferFields').hidden = !d.offerEnabled;
  el('decOfferPct').value = d.discountPercent === '' || d.discountPercent == null ? '' : d.discountPercent;
  el('decGstChips').innerHTML = DECORATION_GST.map(function (g) {
    return (
      '<button type="button" class="dec-chip sm' +
      (d.gstTreatment === g ? ' on' : '') +
      '" data-gst="' +
      esc(g) +
      '">' +
      esc(g) +
      '</button>'
    );
  }).join('');
  paintDecorTierPreview();
  el('decGstChips').querySelectorAll('[data-gst]').forEach(function (btn) {
    btn.onclick = function () {
      decorPkgWizard.draft.gstTreatment = btn.getAttribute('data-gst');
      renderDecorPkgStep4();
    };
  });
}

function paintDecorTierPreview() {
  const d = decorPkgWizard.draft;
  const pct = decorOfferPct(d);
  const host = el('decTierPreview');
  if (!host) return;
  let html = '';
  DEC_PKG_LEVELS.forEach(function (lv) {
    const key = lv.toLowerCase();
    const base = Math.round(+((d.tierPrices || {})[key] || 0));
    if (!base) return;
    const off = decorPriceAfterOffer(base, pct);
    html +=
      '<div class="dec-tier-row"><span>' +
      lv +
      '</span><span>' +
      (pct ? '<s>' + inr(base) + '</s> <b>' + inr(off) + '</b>' : '<b>' + inr(base) + '</b>') +
      '</span></div>';
  });
  host.innerHTML = html || '<p class="sub">Enter at least one package amount for Basic, Standard or Premium.</p>';
}

function syncDecorTierFromInputs() {
  const d = decorPkgWizard.draft;
  d.tierPrices = {
    basic: el('decPriceBasic').value === '' ? '' : Math.round(+el('decPriceBasic').value),
    standard: el('decPriceStandard').value === '' ? '' : Math.round(+el('decPriceStandard').value),
    premium: el('decPricePremium').value === '' ? '' : Math.round(+el('decPricePremium').value),
  };
  d.offerEnabled = !!el('decOfferOn').checked;
  if (d.offerEnabled) {
    const raw = el('decOfferPct').value;
    d.discountPercent = raw === '' ? '' : Math.round(+raw);
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
    '<div class="dec-preview-hero">' +
    (d.images && d.images[0] ? d.images[0] : '🎀') +
    '</div><h2 style="margin:8px 0;font-size:18px;color:var(--decor-navy)">' +
    esc(d.name) +
    '</h2><p class="sub">' +
    esc((d.eventTypes || []).join(', ')) +
    '</p><div class="dec-preview-price">' +
    (pr.pct
      ? '<s>' + inr(pr.base) + '</s> <b>' + inr(pr.offer) + '</b> <span class="dec-off">-' + pr.pct + '%</span>'
      : '<b>' + inr(pr.base) + '</b>') +
    '</div>';
  html += '<p class="dec-sec-h">Package amounts</p>';
  DEC_PKG_LEVELS.forEach(function (lv) {
    const key = lv.toLowerCase();
    const base = Math.round(+((d.tierPrices || {})[key] || 0));
    if (!base) return;
    html += '<div class="dec-tier-row"><span>' + lv + '</span><b>' + inr(decorPriceAfterOffer(base, pr.pct)) + '</b></div>';
  });
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
  html += '</ul><p class="sub">GST: ' + esc(d.gstTreatment || 'Included') + '</p>';
  el('decPkgPreviewBody').innerHTML = html;
}

function validateDecorPkgStep(step) {
  const d = decorPkgWizard.draft;
  if (step === 1 && !d.packageCategory) {
    toast('Select a package category');
    return false;
  }
  if (step === 2) {
    if (!(d.eventTypes || []).length) {
      toast('Select at least one event type');
      return false;
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
    const t = d.tierPrices || {};
    if (!(+t.basic > 0 || +t.standard > 0 || +t.premium > 0)) {
      toast('Enter package amount for Basic, Standard or Premium');
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
    '<b>' + esc(pkg.name) + '</b><p class="sub">' + esc((pkg.eventTypes || []).slice(0, 2).join(', ')) + '</p>';
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
    if (!validateDecorPkgStep(2)) return;
    renderDecorPkgStep3();
    show('decorPkgStep3');
  });
  bindOnInput('decPkgName', function () {
    el('decPkgTitlePreview').textContent = el('decPkgName').value || 'Your package name';
  });
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
  bindOnInput('decModSearch', function () {
    renderDecorPkgStep3();
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
    show('decorModPick');
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
  bindOnInput('decPriceBasic', syncDecorTierFromInputs);
  bindOnInput('decPriceStandard', syncDecorTierFromInputs);
  bindOnInput('decPricePremium', syncDecorTierFromInputs);
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