/** Individual decoration services — designs/variants + tier amounts. */

let decorSvcWizard = { editId: null, draft: null };

function newDecorServiceDraft() {
  return {
    categoryId: 'd01',
    name: '',
    description: '',
    eventTypes: [],
    designs: [{ id: 'dsg-1', name: 'Design 1', note: '' }],
    tierPrices: { basic: '', standard: '', premium: '' },
    offerEnabled: false,
    discountPercent: '',
    gstTreatment: 'Included',
    setupIncluded: 'Included',
    transport: 'Extra',
    status: 'live',
  };
}

function findDecorService(id) {
  return (store.decorationMenu.individualServices || []).find(function (s) {
    return s.id === id;
  });
}

function startDecorServiceWizard(editId) {
  decorSvcWizard.editId = editId || null;
  const src = editId ? findDecorService(editId) : null;
  decorSvcWizard.draft = src ? JSON.parse(JSON.stringify(src)) : newDecorServiceDraft();
  renderDecorSvcStep1();
  show('decorSvcStep1');
}

function renderDecorIndividualList() {
  const list = store.decorationMenu.individualServices || [];
  const host = el('decSvcList');
  if (!host) return;
  if (!list.length) {
    host.innerHTML =
      '<div class="dec-empty"><div class="dec-empty-ico">✨</div><b>No individual services yet</b><p class="sub">List stage, arch, car flowers, lighting and more as standalone services.</p></div>';
    return;
  }
  host.innerHTML = list
    .map(function (s) {
      const mod = findDecorationModule(s.categoryId);
      const pr = decorPrimaryTierPrice(s);
      return (
        '<article class="dec-pkg-card"><div class="dec-pkg-thumb">' +
        (mod ? mod.emoji : '✨') +
        '</div><div><b>' +
        esc(s.name) +
        '</b><p class="sub">' +
        esc(mod ? mod.name : '') +
        ' · ' +
        (s.designs || []).length +
        ' design(s)</p><b>' +
        inr(pr.amount) +
        '</b><div class="dec-card-actions"><button type="button" data-svc-edit="' +
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
  const host = el('decSvcCatList');
  host.innerHTML = DECORATION_MODULES.map(function (m) {
    const on = decorSvcWizard.draft.categoryId === m.id;
    return (
      '<button type="button" class="dec-mod-row' +
      (on ? ' on' : '') +
      '" data-svc-cat="' +
      esc(m.id) +
      '"><span class="dec-mod-ico">' +
      m.emoji +
      '</span><b>' +
      esc(m.name) +
      '</b></button>'
    );
  }).join('');
  host.querySelectorAll('[data-svc-cat]').forEach(function (btn) {
    btn.onclick = function () {
      decorSvcWizard.draft.categoryId = btn.getAttribute('data-svc-cat');
      renderDecorSvcStep1();
    };
  });
}

function renderDecorSvcStep2() {
  const d = decorSvcWizard.draft;
  el('decSvcName').value = d.name || '';
  el('decSvcDesc').value = d.description || '';
  const types = DECORATION_EVENT_TYPES.wedding.concat(DECORATION_EVENT_TYPES.other);
  el('decSvcEventChips').innerHTML = types
    .slice(0, 24)
    .map(function (t) {
      const on = (d.eventTypes || []).indexOf(t) >= 0;
      return '<button type="button" class="dec-chip sm' + (on ? ' on' : '') + '" data-sv-ev="' + esc(t) + '">' + esc(t) + '</button>';
    })
    .join('');
  el('decSvcEventChips').querySelectorAll('[data-sv-ev]').forEach(function (btn) {
    btn.onclick = function () {
      const val = btn.getAttribute('data-sv-ev');
      const arr = decorSvcWizard.draft.eventTypes || [];
      const i = arr.indexOf(val);
      if (i >= 0) arr.splice(i, 1);
      else arr.push(val);
      decorSvcWizard.draft.eventTypes = arr;
      renderDecorSvcStep2();
    };
  });
}

function renderDecorSvcStep3() {
  const d = decorSvcWizard.draft;
  const host = el('decSvcDesigns');
  host.innerHTML = (d.designs || [])
    .map(function (dg, i) {
      return (
        '<div class="fld"><label>Design ' +
        (i + 1) +
        '</label><input data-dgn="' +
        i +
        '" value="' +
        esc(dg.name) +
        '"><input data-dgn-note="' +
        i +
        '" placeholder="Short note" value="' +
        esc(dg.note || '') +
        '"></div>'
      );
    })
    .join('');
  host.querySelectorAll('[data-dgn]').forEach(function (inp) {
    inp.oninput = function () {
      const i = +inp.getAttribute('data-dgn');
      decorSvcWizard.draft.designs[i].name = inp.value;
    };
  });
}

function renderDecorSvcStep4() {
  const d = decorSvcWizard.draft;
  const t = d.tierPrices || {};
  el('decSvcPriceBasic').value = t.basic || '';
  el('decSvcPriceStandard').value = t.standard || '';
  el('decSvcPricePremium').value = t.premium || '';
  el('decSvcOfferOn').checked = !!d.offerEnabled;
  el('decSvcOfferFields').hidden = !d.offerEnabled;
  el('decSvcOfferPct').value = d.discountPercent === '' ? '' : d.discountPercent;
}

function saveDecorService() {
  const d = decorSvcWizard.draft;
  d.name = (el('decSvcName').value || '').trim();
  if (!d.name) {
    toast('Service name required');
    return;
  }
  d.tierPrices = {
    basic: el('decSvcPriceBasic').value === '' ? '' : Math.round(+el('decSvcPriceBasic').value),
    standard: el('decSvcPriceStandard').value === '' ? '' : Math.round(+el('decSvcPriceStandard').value),
    premium: el('decSvcPricePremium').value === '' ? '' : Math.round(+el('decSvcPricePremium').value),
  };
  if (!(+d.tierPrices.basic > 0 || +d.tierPrices.standard > 0 || +d.tierPrices.premium > 0)) {
    toast('Enter Basic, Standard or Premium amount');
    return;
  }
  if (!d.id) d.id = uid('dsvc');
  const i = store.decorationMenu.individualServices.findIndex(function (s) {
    return s.id === d.id;
  });
  const copy = JSON.parse(JSON.stringify(d));
  if (i >= 0) store.decorationMenu.individualServices[i] = copy;
  else store.decorationMenu.individualServices.unshift(copy);
  saveStore();
  toast('Service published');
  store.decorationMenu.hubTab = 'services';
  decorationMenuOpenHub();
}

function bindDecorationIndividualUi() {
  bindClick('decAddServiceBtn', function () {
    startDecorServiceWizard(null);
  });
  bindClick('decSvcStep1Next', function () {
    renderDecorSvcStep2();
    show('decorSvcStep2');
  });
  bindClick('decSvcStep2Back', function () {
    show('decorSvcStep1');
  });
  bindClick('decSvcStep2Next', function () {
    decorSvcWizard.draft.name = (el('decSvcName').value || '').trim();
    decorSvcWizard.draft.description = (el('decSvcDesc').value || '').trim();
    if (!decorSvcWizard.draft.name) {
      toast('Service name required');
      return;
    }
    renderDecorSvcStep3();
    show('decorSvcStep3');
  });
  bindClick('decSvcAddDesign', function () {
    decorSvcWizard.draft.designs.push({ id: uid('dsg'), name: 'Design ' + (decorSvcWizard.draft.designs.length + 1), note: '' });
    renderDecorSvcStep3();
  });
  bindClick('decSvcStep3Next', function () {
    renderDecorSvcStep4();
    show('decorSvcStep4');
  });
  bindClick('decSvcStep4Back', function () {
    show('decorSvcStep3');
  });
  bindClick('decSvcPublish', saveDecorService);
  bindClick('decSvcWizardBack', function () {
    decorationMenuOpenHub();
  });
}