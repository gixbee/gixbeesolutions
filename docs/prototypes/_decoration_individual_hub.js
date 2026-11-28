/** Individual decoration services — one price per service (not package tiers). */

const DEC_SVC_SETUP = ['Included', 'Extra', 'Not applicable'];
const DEC_SVC_TRANSPORT = ['Included', 'Extra', 'Not applicable'];

let decorSvcWizard = { editId: null, draft: null, catSearch: '' };

function newDecorServiceDraft() {
  return {
    categoryId: 'd08',
    name: '',
    description: '',
    traditionTags: [],
    traditionOtherText: '',
    designs: [{ id: 'dsg-1', name: 'Design 1', note: '' }],
    price: '',
    priceUnit: 'Per Event',
    offerEnabled: false,
    discountPercent: '',
    gstTreatment: 'Included',
    setupIncluded: 'Included',
    transport: 'Extra',
    status: 'live',
  };
}

function decorSvcResolvedPrice(s) {
  if (!s) return { base: 0, offer: 0, pct: 0, unit: 'Per Event' };
  let base = Math.round(+(s.price || 0));
  if (!base && s.tierPrices) {
    const t = s.tierPrices;
    base = Math.round(+(t.standard || t.basic || t.premium || 0));
  }
  const pct = s.offerEnabled ? Math.min(90, Math.max(0, Math.round(+s.discountPercent || 0))) : 0;
  const offer = pct ? Math.max(0, Math.round((base * (100 - pct)) / 100)) : base;
  return { base: base, offer: offer, pct: pct, unit: s.priceUnit || 'Per Event' };
}

function findDecorService(id) {
  return (store.decorationMenu.individualServices || []).find(function (s) {
    return s.id === id;
  });
}

function setDecorSvcProgress(step) {
  const active = document.querySelector('.scr.on .dec-svc-progress');
  if (active) {
    let i;
    for (i = 0; i < 4; i++) {
      const dot = active.children[i];
      if (!dot) continue;
      dot.classList.remove('done', 'on');
      if (i < step - 1) dot.classList.add('done');
      else if (i === step - 1) dot.classList.add('on');
    }
  }
  const lab = document.querySelector('.scr.on .dec-svc-step');
  if (lab) lab.textContent = 'Step ' + step + ' of 4';
}

function startDecorServiceWizard(editId) {
  decorSvcWizard.editId = editId || null;
  decorSvcWizard.catSearch = '';
  const src = editId ? findDecorService(editId) : null;
  decorSvcWizard.draft = src ? JSON.parse(JSON.stringify(src)) : newDecorServiceDraft();
  if (decorSvcWizard.draft.tierPrices && !decorSvcWizard.draft.price) {
    const t = decorSvcWizard.draft.tierPrices;
    decorSvcWizard.draft.price = Math.round(+(t.standard || t.basic || t.premium || 0)) || '';
    delete decorSvcWizard.draft.tierPrices;
  }
  if (!decorSvcWizard.draft.priceUnit) decorSvcWizard.draft.priceUnit = 'Per Event';
  renderDecorSvcStep1();
  show('decorSvcStep1');
}

function renderDecorIndividualList() {
  const list = store.decorationMenu.individualServices || [];
  const host = el('decSvcList');
  if (!host) return;
  if (!list.length) {
    host.innerHTML =
      '<div class="dec-empty"><div class="dec-empty-ico">✨</div><b>No individual services yet</b><p class="sub">Sell one service at one rate — car flowers, entrance arch, stage carpet, and more.</p></div>';
    return;
  }
  host.innerHTML = list
    .map(function (s) {
      const mod = findDecorationModule(s.categoryId);
      const pr = decorSvcResolvedPrice(s);
      const priceLine = pr.pct
        ? '<span class="dec-pkg-price"><s>' + inr(pr.base) + '</s> ' + inr(pr.offer) + ' <span class="dec-off">-' + pr.pct + '%</span></span>'
        : '<span class="dec-pkg-price">' + inr(pr.base) + '</span>';
      return (
        '<article class="dec-pkg-card"><div class="dec-pkg-thumb">' +
        (mod ? mod.emoji : '✨') +
        '</div><div><b>' +
        esc(s.name) +
        '</b><p class="sub">' +
        esc(mod ? mod.name : '') +
        ' · ' +
        esc(pr.unit) +
        '</p>' +
        priceLine +
        '<div class="dec-card-actions"><button type="button" data-svc-edit="' +
        esc(s.id) +
        '">Edit</button></div></div></article>'
      );
    })
    .join('');
  host.querySelectorAll('[data-svc-edit]').forEach(function (btn) {
    btn.onclick = function () {
      startDecorServiceWizard(btn.getAttribute('data-svc-edit'));
    };
  });
}

function renderDecorSvcStep1() {
  setDecorSvcProgress(1);
  const q = (decorSvcWizard.catSearch || '').trim().toLowerCase();
  const host = el('decSvcCatList');
  const mod = findDecorationModule(decorSvcWizard.draft.categoryId);
  const hint = el('decSvcCatHint');
  if (hint) hint.textContent = mod ? 'Selected: ' + mod.name : 'Pick what you offer — customers book this as a standalone service.';
  host.innerHTML = DECORATION_MODULES.filter(function (m) {
    return !q || m.name.toLowerCase().indexOf(q) >= 0;
  })
    .map(function (m) {
      const on = decorSvcWizard.draft.categoryId === m.id;
      return (
        '<button type="button" class="dec-mod-row' +
        (on ? ' on' : '') +
        '" data-svc-cat="' +
        esc(m.id) +
        '"><span class="dec-mod-ico">' +
        m.emoji +
        '</span><span style="flex:1;min-width:0"><b>' +
        esc(m.name) +
        '</b><small>' +
        (m.items ? m.items.length : 0) +
        ' catalogue items</small></span></button>'
      );
    })
    .join('');
  host.querySelectorAll('[data-svc-cat]').forEach(function (btn) {
    btn.onclick = function () {
      decorSvcWizard.draft.categoryId = btn.getAttribute('data-svc-cat');
      renderDecorSvcStep1();
    };
  });
  if (el('decSvcCatSearch')) el('decSvcCatSearch').value = decorSvcWizard.catSearch || '';
}

function renderDecorSvcStep2() {
  setDecorSvcProgress(2);
  const d = decorSvcWizard.draft;
  const mod = findDecorationModule(d.categoryId);
  el('decSvcCatBanner').textContent = mod ? mod.name : '—';
  el('decSvcName').value = d.name || '';
  el('decSvcDesc').value = d.description || '';
  el('decSvcCommunityChips').innerHTML = DECORATION_TRADITIONS.map(function (t) {
    const on = (d.traditionTags || []).indexOf(t) >= 0;
    return (
      '<button type="button" class="dec-chip sm' +
      (on ? ' on' : '') +
      '" data-svc-comm="' +
      esc(t) +
      '">' +
      esc(t) +
      '</button>'
    );
  }).join('');
  const svcOtherWrap = el('decSvcTraditionOtherWrap');
  const svcOtherInp = el('decSvcTraditionOther');
  const svcHasOthers = decorHasOthersTradition(d.traditionTags);
  if (svcOtherWrap) svcOtherWrap.hidden = !svcHasOthers;
  if (svcOtherInp) {
    svcOtherInp.value = d.traditionOtherText || '';
    svcOtherInp.oninput = function () {
      decorSvcWizard.draft.traditionOtherText = svcOtherInp.value;
    };
  }
  el('decSvcCommunityChips').querySelectorAll('[data-svc-comm]').forEach(function (btn) {
    btn.onclick = function () {
      const val = btn.getAttribute('data-svc-comm');
      const arr = decorSvcWizard.draft.traditionTags || [];
      const i = arr.indexOf(val);
      if (i >= 0) {
        arr.splice(i, 1);
        if (decorTraditionKey(val) === 'others') decorSvcWizard.draft.traditionOtherText = '';
      } else arr.push(val);
      decorSvcWizard.draft.traditionTags = arr;
      renderDecorSvcStep2();
    };
  });
}

function renderDecorSvcStep3() {
  setDecorSvcProgress(3);
  const d = decorSvcWizard.draft;
  const host = el('decSvcDesigns');
  host.innerHTML = (d.designs || [])
    .map(function (dg, i) {
      return (
        '<div class="dec-design-card"><div class="fld"><label>Design name</label><input data-dgn="' +
        i +
        '" value="' +
        esc(dg.name) +
        '"></div><div class="fld"><label>Note for customer (optional)</label><input data-dgn-note="' +
        i +
        '" value="' +
        esc(dg.note || '') +
        '" placeholder="e.g. Roses with marigold border"></div></div>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dgn]').forEach(function (inp) {
    inp.oninput = function () {
      const i = +inp.getAttribute('data-dgn');
      decorSvcWizard.draft.designs[i].name = inp.value;
    };
  });
  host.querySelectorAll('[data-dgn-note]').forEach(function (inp) {
    inp.oninput = function () {
      const i = +inp.getAttribute('data-dgn-note');
      decorSvcWizard.draft.designs[i].note = inp.value;
    };
  });
}

function paintDecorSvcPricePreview() {
  const d = decorSvcWizard.draft;
  const base = Math.round(+(el('decSvcPrice').value || d.price || 0));
  d.price = el('decSvcPrice').value === '' ? '' : base;
  d.priceUnit = el('decSvcPriceUnit').value || 'Per Event';
  d.offerEnabled = !!el('decSvcOfferOn').checked;
  if (d.offerEnabled) d.discountPercent = el('decSvcOfferPct').value === '' ? '' : Math.round(+el('decSvcOfferPct').value);
  const pr = decorSvcResolvedPrice(d);
  const host = el('decSvcPricePreview');
  if (!host) return;
  if (!pr.base) {
    host.innerHTML = '<p class="sub">Enter your service price above — customers see one clear rate.</p>';
    return;
  }
  host.innerHTML =
    '<div class="dec-tier-row"><span>Customer sees</span><span>' +
    (pr.pct ? '<s>' + inr(pr.base) + '</s> <b>' + inr(pr.offer) + '</b>' : '<b>' + inr(pr.base) + '</b>') +
    ' / ' +
    esc(d.priceUnit) +
    '</span></div>';
}

function renderDecorSvcStep4() {
  setDecorSvcProgress(4);
  const d = decorSvcWizard.draft;
  el('decSvcPrice').value = d.price === '' || d.price == null ? '' : d.price;
  el('decSvcPriceUnit').innerHTML = DECORATION_UNITS.map(function (u) {
    return '<option' + (d.priceUnit === u ? ' selected' : '') + '>' + esc(u) + '</option>';
  }).join('');
  el('decSvcOfferOn').checked = !!d.offerEnabled;
  el('decSvcOfferFields').hidden = !d.offerEnabled;
  el('decSvcOfferPct').value = d.discountPercent === '' || d.discountPercent == null ? '' : d.discountPercent;
  el('decSvcGstChips').innerHTML = DECORATION_GST.map(function (g) {
    return (
      '<button type="button" class="dec-chip sm' +
      (d.gstTreatment === g ? ' on' : '') +
      '" data-svc-gst="' +
      esc(g) +
      '">' +
      esc(g) +
      '</button>'
    );
  }).join('');
  el('decSvcSetupChips').innerHTML = DEC_SVC_SETUP.map(function (g) {
    return (
      '<button type="button" class="dec-chip sm' +
      (d.setupIncluded === g ? ' on' : '') +
      '" data-svc-setup="' +
      esc(g) +
      '">' +
      esc(g) +
      '</button>'
    );
  }).join('');
  el('decSvcTransportChips').innerHTML = DEC_SVC_TRANSPORT.map(function (g) {
    return (
      '<button type="button" class="dec-chip sm' +
      (d.transport === g ? ' on' : '') +
      '" data-svc-tr="' +
      esc(g) +
      '">' +
      esc(g) +
      '</button>'
    );
  }).join('');
  function bindChip(sel, attr, key) {
    el(sel).querySelectorAll('[data-' + attr + ']').forEach(function (btn) {
      btn.onclick = function () {
        decorSvcWizard.draft[key] = btn.getAttribute('data-' + attr);
        renderDecorSvcStep4();
      };
    });
  }
  bindChip('decSvcGstChips', 'svc-gst', 'gstTreatment');
  bindChip('decSvcSetupChips', 'svc-setup', 'setupIncluded');
  bindChip('decSvcTransportChips', 'svc-tr', 'transport');
  paintDecorSvcPricePreview();
}

function syncDecorSvcFromStep4() {
  const d = decorSvcWizard.draft;
  d.price = el('decSvcPrice').value === '' ? '' : Math.round(+el('decSvcPrice').value);
  d.priceUnit = el('decSvcPriceUnit').value;
  d.offerEnabled = !!el('decSvcOfferOn').checked;
  if (d.offerEnabled) {
    const n = Math.round(+el('decSvcOfferPct').value || 0);
    d.discountPercent = el('decSvcOfferPct').value === '' ? '' : n;
  } else d.discountPercent = '';
  paintDecorSvcPricePreview();
}

function validateDecorSvcPricing() {
  syncDecorSvcFromStep4();
  const d = decorSvcWizard.draft;
  if (!(+d.price > 0)) {
    toast('Enter your service price (₹)');
    return false;
  }
  if (d.offerEnabled) {
    const n = Math.round(+d.discountPercent);
    if (!(n >= 1 && n <= 90)) {
      toast('Discount must be 1–90%');
      return false;
    }
  }
  return true;
}

function saveDecorService(status) {
  if (el('decSvcPrice')) syncDecorSvcFromStep4();
  const d = decorSvcWizard.draft;
  d.name = (d.name || el('decSvcName') && el('decSvcName').value || '').trim();
  if (!d.name) {
    toast('Service name is required');
    return;
  }
  if (status !== 'draft' && !validateDecorSvcPricing()) return;
  d.status = status || 'live';
  if (!d.id) d.id = uid('dsvc');
  delete d.tierPrices;
  const i = store.decorationMenu.individualServices.findIndex(function (s) {
    return s.id === d.id;
  });
  const copy = JSON.parse(JSON.stringify(d));
  if (i >= 0) store.decorationMenu.individualServices[i] = copy;
  else store.decorationMenu.individualServices.unshift(copy);
  saveStore();
  if (status === 'draft') {
    toast('Draft saved');
  } else {
    el('decSvcSuccessTitle').textContent = copy.name;
    el('decSvcSuccessBody').innerHTML =
      '<b>' + esc(copy.name) + '</b><p class="sub">' + inr(decorSvcResolvedPrice(copy).offer) + ' / ' + esc(copy.priceUnit) + '</p>';
    show('decorSvcSuccess');
    return;
  }
  store.decorationMenu.hubTab = 'services';
  decorationMenuOpenHub();
}

function bindDecorationIndividualUi() {
  bindClick('decAddServiceBtn', function () {
    startDecorServiceWizard(null);
  });
  bindClick('decSvcWizardBack', function () {
    decorationMenuOpenHub();
  });
  bindClick('decSvcStep1Next', function () {
    if (!decorSvcWizard.draft.categoryId) {
      toast('Select a category');
      return;
    }
    renderDecorSvcStep2();
    show('decorSvcStep2');
  });
  bindOnInput('decSvcCatSearch', function () {
    decorSvcWizard.catSearch = el('decSvcCatSearch').value;
    renderDecorSvcStep1();
  });
  bindClick('decSvcChangeCat', function () {
    show('decorSvcStep1');
  });
  bindClick('decSvcStep2Back', function () {
    show('decorSvcStep1');
  });
  bindClick('decSvcStep2TopBack', function () {
    show('decorSvcStep1');
  });
  bindClick('decSvcStep2Next', function () {
    decorSvcWizard.draft.name = (el('decSvcName').value || '').trim();
    decorSvcWizard.draft.description = (el('decSvcDesc').value || '').trim();
    if (!decorSvcWizard.draft.name) {
      toast('Give this service a clear name');
      return;
    }
    if (!(decorSvcWizard.draft.traditionTags || []).length) {
      toast('Select at least one community');
      return;
    }
    const svcD = decorSvcWizard.draft;
    if (el('decSvcTraditionOther')) svcD.traditionOtherText = el('decSvcTraditionOther').value;
    if (decorHasOthersTradition(svcD.traditionTags) && !(svcD.traditionOtherText || '').trim()) {
      toast('Specify other community');
      return;
    }
    if (decorHasOthersTradition(svcD.traditionTags)) {
      svcD.traditionOtherText = (svcD.traditionOtherText || '').trim();
    } else {
      svcD.traditionOtherText = '';
    }
    renderDecorSvcStep3();
    show('decorSvcStep3');
  });
  bindClick('decSvcStep3TopBack', function () {
    show('decorSvcStep2');
  });
  bindClick('decSvcSkipDesigns', function () {
    decorSvcWizard.draft.designs = [];
    renderDecorSvcStep4();
    show('decorSvcStep4');
  });
  bindClick('decSvcAddDesign', function () {
    decorSvcWizard.draft.designs.push({ id: uid('dsg'), name: 'Design ' + (decorSvcWizard.draft.designs.length + 1), note: '' });
    renderDecorSvcStep3();
  });
  bindClick('decSvcStep3Next', function () {
    renderDecorSvcStep4();
    show('decorSvcStep4');
  });
  bindClick('decSvcStep4TopBack', function () {
    show('decorSvcStep3');
  });
  bindClick('decSvcStep4Back', function () {
    show('decorSvcStep3');
  });
  bindOnInput('decSvcPrice', syncDecorSvcFromStep4);
  bindOnInput('decSvcOfferPct', syncDecorSvcFromStep4);
  bindClick('decSvcOfferOn', function () {
    el('decSvcOfferFields').hidden = !el('decSvcOfferOn').checked;
    syncDecorSvcFromStep4();
  });
  bindClick('decSvcPublish', function () {
    saveDecorService('live');
  });
  bindClick('decSvcSaveDraft', function () {
    decorSvcWizard.draft.name = (el('decSvcName').value || decorSvcWizard.draft.name || '').trim();
    saveDecorService('draft');
  });
  bindClick('decSvcSuccessDone', function () {
    store.decorationMenu.hubTab = 'services';
    decorationMenuOpenHub();
  });
}