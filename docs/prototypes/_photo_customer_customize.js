/** Customer Customize Requirements — mirrors owner package/service wizard options. */

const CUST_PKG_OPTIONAL_FUNCTIONS = [
  'Reception',
  'Wedding Eve',
  'Engagement',
  'Pre-Wedding Shoot',
  'Post-Wedding Shoot',
  'Save-the-Date Shoot',
];

const CUST_FUNCTION_HINTS = {
  Reception: 'Separate reception function or evening event',
  'Wedding Eve': 'Pre-wedding night celebration',
  Engagement: 'Engagement or ring ceremony',
  'Pre-Wedding Shoot': 'Couple photoshoot before the wedding',
  'Post-Wedding Shoot': 'Couple photoshoot after the wedding',
  'Save-the-Date Shoot': 'Announcement shoot for save-the-date',
};

const CUST_NEED_PRESETS = [
  { id: '', label: 'Select a common need…' },
  { id: 'song', label: 'Song preference for highlight film' },
  { id: 'permissions', label: 'Church / venue photography permission' },
  { id: 'family', label: 'Special family portrait list' },
  { id: 'timeline', label: 'Detailed event timeline share' },
  { id: 'livestream', label: 'Family abroad — live stream priority' },
  { id: 'custom', label: 'Custom (type below)' },
];

const CUST_SERVICE_NEED_PRESETS = {
  funeral: [
    { id: '', label: 'Select…' },
    { id: 'stream', label: 'Live stream for relatives abroad' },
    { id: 'discreet', label: 'Extra-discreet coverage request' },
    { id: 'liaison', label: 'Family liaison contact on arrival' },
    { id: 'custom', label: 'Custom (type below)' },
  ],
  baptism: [
    { id: '', label: 'Select…' },
    { id: 'church', label: 'Church permission / priest coordination' },
    { id: 'groups', label: 'Family group portrait list' },
    { id: 'custom', label: 'Custom (type below)' },
  ],
  event: [
    { id: '', label: 'Select…' },
    { id: 'timeline', label: 'Event run-sheet / timeline' },
    { id: 'venue', label: 'Venue lighting limitations' },
    { id: 'custom', label: 'Custom (type below)' },
  ],
  portrait: [
    { id: '', label: 'Select…' },
    { id: 'outfit', label: 'Outfit / look preferences' },
    { id: 'location', label: 'Preferred outdoor location' },
    { id: 'custom', label: 'Custom (type below)' },
  ],
  corporate: [
    { id: '', label: 'Select…' },
    { id: 'headshots', label: 'Executive headshot list' },
    { id: 'billing', label: 'GST invoice / company billing' },
    { id: 'custom', label: 'Custom (type below)' },
  ],
};

function custNeedPresetsForService() {
  const key = state.serviceId || state.photoNeed || '';
  return CUST_SERVICE_NEED_PRESETS[key] || CUST_NEED_PRESETS;
}

const CUST_ALBUM_SIZES = ['10 x 12 inch', '12 x 30 inch', '12 x 36 inch', 'Custom'];
const CUST_ALBUM_PAGES = ['20', '25', '30', '40', '50', 'Custom'];
const CUST_ALBUM_PAPER = ['Matte', 'Lustre', 'Glossy', 'Custom'];
const CUST_ALBUM_COVER = ['Standard', 'Premium', 'Luxury', 'Custom'];

function custOptionalFunctionsForOwner(owner) {
  const inPkg = owner.functions || [];
  return CUST_PKG_OPTIONAL_FUNCTIONS.filter(function (fn) {
    return inPkg.indexOf(fn) < 0;
  });
}

function custExtraFunctionsSelectedList(c, optFns) {
  const list = (optFns || []).filter(function (fn) {
    return c.extraFunctions && c.extraFunctions[fn];
  });
  if (c.extraFunctionCustom && c.functionCustom && String(c.functionCustom).trim()) {
    list.push(String(c.functionCustom).trim());
  }
  return list;
}

function custExtraFunctionsButtonLabel(c, optFns) {
  const list = custExtraFunctionsSelectedList(c, optFns);
  if (!list.length) return 'Select functions…';
  if (list.length <= 2) return list.join(', ');
  return list.length + ' functions selected';
}

function custUpdateExtraFnMultiLabel(optFns) {
  const lbl = el('custFnMultiLbl');
  if (lbl) lbl.textContent = custExtraFunctionsButtonLabel(state.customize, optFns);
  const wrap = el('custFnCustomWrap');
  if (wrap) wrap.style.display = state.customize.extraFunctionCustom ? '' : 'none';
}

function custBindExtraFunctionMulti(optFns) {
  const btn = el('custFnMultiBtn');
  const panel = el('custFnMultiPanel');
  if (!btn || !panel) return;
  if (!panel._custBound) {
    panel._custBound = true;
    document.addEventListener('click', function (e) {
      if (panel.hidden) return;
      if (panel.contains(e.target) || btn.contains(e.target)) return;
      panel.hidden = true;
    });
  }
  btn.onclick = function (e) {
    e.stopPropagation();
    panel.hidden = !panel.hidden;
  };
  const c = state.customize;
  document.querySelectorAll('[data-extra-fn]').forEach(function (inp) {
    inp.onchange = function () {
      const fn = inp.getAttribute('data-extra-fn');
      if (!c.extraFunctions) c.extraFunctions = {};
      c.extraFunctions[fn] = inp.checked;
      inp.closest('.multi-drop-item').classList.toggle('on', inp.checked);
      custUpdateExtraFnMultiLabel(optFns);
    };
  });
  const customChk = el('custFnCustomChk');
  if (customChk) {
    customChk.onchange = function () {
      c.extraFunctionCustom = customChk.checked;
      customChk.closest('.multi-drop-item').classList.toggle('on', customChk.checked);
      custUpdateExtraFnMultiLabel(optFns);
    };
  }
  const fnCustom = el('custFnCustom');
  if (fnCustom) {
    fnCustom.oninput = function () {
      c.functionCustom = fnCustom.value;
      custUpdateExtraFnMultiLabel(optFns);
    };
  }
  custUpdateExtraFnMultiLabel(optFns);
}

function custAlbumHasPackage(owner) {
  const a = (owner.albumPrints || {})['Photo Album'];
  return a && a.on;
}

function custSelectOptions(values, selected, customVal, customKey) {
  return values
    .map(function (v) {
      const sel = selected === v ? ' selected' : '';
      return '<option value="' + custEsc(v) + '"' + sel + '>' + custEsc(v === 'Custom' ? 'Custom…' : v) + '</option>';
    })
    .join('');
}

function custRenderCustomizeWedding(owner, packageExtras, state) {
  const c = state.customize;
  const optFns = custOptionalFunctionsForOwner(owner);
  const hasAlbum = custAlbumHasPackage(owner);
  let html =
    '<p class="cust-lead">Add optional services and tell the studio what you need. Package inclusions stay as listed — only your choices below are sent with the interest.</p>';

  html += '<div class="cust-hd">Optional add-ons</div>';
  const paidExtras = packageExtras.filter(function (ex) {
    return ex.price > 0;
  });
  if (paidExtras.length) {
    paidExtras.forEach(function (ex) {
      html +=
        '<label class="extra-line"><span><input type="checkbox" data-wex="' +
        custEsc(ex.id) +
        '"' +
        (c.extras[ex.id] ? ' checked' : '') +
        '> ' +
        custEsc(ex.label) +
        (ex.basis ? ' <span class="cust-muted">(' + custEsc(ex.basis) + ')</span>' : '') +
        '</span><span class="cust-price">' +
        custInr(ex.price) +
        '</span></label>';
    });
  } else {
    html += '<p class="sub">No paid add-ons for this package.</p>';
  }

  html += '<div class="cust-hd">Extra events to cover</div>';
  html += '<div class="fld"><label>Add function</label>';
  html += '<div class="multi-drop" id="custFnMulti">';
  html +=
    '<button type="button" class="multi-drop-btn" id="custFnMultiBtn"><span id="custFnMultiLbl">' +
    custEsc(custExtraFunctionsButtonLabel(c, optFns)) +
    '</span><span class="multi-drop-chev" aria-hidden="true">▾</span></button>';
  html += '<div class="multi-drop-panel" id="custFnMultiPanel" hidden>';
  optFns.forEach(function (fn) {
    const on = c.extraFunctions && c.extraFunctions[fn];
    html +=
      '<label class="multi-drop-item' +
      (on ? ' on' : '') +
      '"><input type="checkbox" data-extra-fn="' +
      custEsc(fn) +
      '"' +
      (on ? ' checked' : '') +
      '> <span><b>' +
      custEsc(fn) +
      '</b>' +
      (CUST_FUNCTION_HINTS[fn] ? '<span class="cust-muted">' + custEsc(CUST_FUNCTION_HINTS[fn]) + '</span>' : '') +
      '</span></label>';
  });
  html +=
    '<label class="multi-drop-item' +
    (c.extraFunctionCustom ? ' on' : '') +
    '"><input type="checkbox" id="custFnCustomChk"' +
    (c.extraFunctionCustom ? ' checked' : '') +
    '> <span><b>Custom function…</b><span class="cust-muted">Type your own event name below</span></span></label>';
  html += '</div></div></div>';
  html +=
    '<div class="fld" id="custFnCustomWrap" style="' +
    (c.extraFunctionCustom ? '' : 'display:none') +
    '"><label>Describe custom function</label><div class="sel-box"><input type="text" id="custFnCustom" maxlength="120" placeholder="e.g. Wedding eve at home, 4 hours" value="' +
    custEsc(c.functionCustom || '') +
    '"></div></div>';
  if (optFns.length) {
    html += '<p class="cust-hint">You can select more than one. Already in package: ' + custEsc((owner.functions || []).join(', ')) + '</p>';
  }

  if (hasAlbum) {
    const def = (owner.albumPrints || {})['Photo Album'];
    html += '<div class="cust-hd">Album preferences</div>';
    html +=
      '<p class="cust-hint">Package includes <b>' +
      custEsc(def.size) +
      '</b> · ' +
      def.pages +
      ' pages · ' +
      custEsc(def.cover) +
      ' cover. Adjust if you need changes (subject to studio confirmation).</p>';
    html += '<div class="budget-row">';
    html +=
      '<div class="fld"><label>Album size</label><div class="sel-box"><select id="albSize">' +
      custSelectOptions(CUST_ALBUM_SIZES, c.albumSize || def.size, c.albumSizeCustom, 'albumSizeCustom') +
      '</select></div></div>';
    html +=
      '<div class="fld"><label>Pages</label><div class="sel-box"><select id="albPages">' +
      custSelectOptions(CUST_ALBUM_PAGES, String(c.albumPages || def.pages), c.albumPagesCustom, 'albumPagesCustom') +
      '</select></div></div>';
    html += '</div><div class="budget-row">';
    html +=
      '<div class="fld"><label>Paper</label><div class="sel-box"><select id="albPaper">' +
      custSelectOptions(CUST_ALBUM_PAPER, c.albumPaper || def.paper || 'Matte', c.albumPaperCustom) +
      '</select></div></div>';
    html +=
      '<div class="fld"><label>Cover</label><div class="sel-box"><select id="albCover">' +
      custSelectOptions(CUST_ALBUM_COVER, c.albumCover || def.cover || 'Premium', c.albumCoverCustom) +
      '</select></div></div>';
    html += '</div>';
    html +=
      '<div class="fld" id="albSizeCustomWrap" style="' +
      (c.albumSize === 'Custom' ? '' : 'display:none') +
      '"><label>Custom album size</label><div class="sel-box"><input type="text" id="albSizeCustom" placeholder="e.g. 14 x 30 inch" value="' +
      custEsc(c.albumSizeCustom || '') +
      '"></div></div>';
    html +=
      '<div class="fld" id="albPagesCustomWrap" style="' +
      (c.albumPages === 'Custom' || String(c.albumPages) === 'Custom' ? '' : 'display:none') +
      '"><label>Custom page count</label><div class="sel-box"><input type="number" id="albPagesCustom" min="10" max="80" placeholder="e.g. 35" value="' +
      custEsc(c.albumPagesCustom || '') +
      '"></div></div>';
  }

  html += '<div class="cust-hd">Your specific needs</div>';
  html +=
    '<div class="fld"><label>What should we know?</label><div class="sel-box"><select id="custNeedPreset">' +
    CUST_NEED_PRESETS.map(function (p) {
      return (
        '<option value="' +
        custEsc(p.id) +
        '"' +
        (c.customNeedPreset === p.id ? ' selected' : '') +
        '>' +
        custEsc(p.label) +
        '</option>'
      );
    }).join('') +
    '</select></div></div>';
  html +=
    '<div class="fld"><label>Details (optional)</label><div class="sel-box"><input type="text" id="custNeedText" maxlength="200" placeholder="Type your requirement — e.g. drone only during entry" value="' +
    custEsc(c.customNeedText || '') +
    '"></div></div>';

  const reqs = owner.requirements || [];
  if (reqs.length) {
    html += '<div class="cust-hd">Studio requirements</div><p class="cust-hint">Please confirm you can meet these (from the photographer\'s package).</p>';
    reqs.forEach(function (r, i) {
      const key = 'req_' + i;
      html +=
        '<label class="chk-row' +
        (c.reqAck[key] ? ' on' : '') +
        '"><input type="checkbox" data-req-ack="' +
        custEsc(key) +
        '"' +
        (c.reqAck[key] ? ' checked' : '') +
        '> ' +
        custEsc(r) +
        '</label>';
    });
  }

  html += '<div class="cust-hd">Additional notes</div><textarea class="notes" id="custNotes" maxlength="500" placeholder="Anything else for the studio — venues, second shooter, language preference…">' + custEsc(c.notes) + '</textarea><div class="notes-count"><span id="noteCt">0</span>/500</div>';

  return html;
}

function custRenderCustomizeService(svcOwner, serviceExtras, durationOptions, state) {
  const c = state.customize;
  let html =
    '<p class="cust-lead">Adjust coverage and add-ons for this service. The studio will confirm availability and final price.</p>';

  html += '<div class="cust-hd">Coverage duration</div>';
  (durationOptions || []).forEach(function (d) {
    html +=
      '<label class="radio-card' +
      (c.duration === d.id ? ' on' : '') +
      '"><input type="radio" name="dur" value="' +
      custEsc(d.id) +
      '"' +
      (c.duration === d.id ? ' checked' : '') +
      '> <span><b>' +
      custEsc(d.label) +
      '</b>' +
      (d.add ? '<span class="cust-muted"> +' + custInr(d.add) + '</span>' : '') +
      '</span></label>';
  });

  html += '<div class="cust-hd">Optional add-ons</div>';
  if (serviceExtras.length) {
    serviceExtras.forEach(function (ex) {
      html +=
        '<label class="extra-line"><span><input type="checkbox" data-sex="' +
        custEsc(ex.id) +
        '"' +
        (c.extras[ex.id] ? ' checked' : '') +
        '> ' +
        custEsc(ex.label) +
        (ex.basis ? ' <span class="cust-muted">(' + custEsc(ex.basis) + ')</span>' : '') +
        '</span><span class="cust-price">' +
        custInr(ex.price) +
        '</span></label>';
    });
  } else {
    html += '<p class="sub">No add-ons listed for this service.</p>';
  }

  html += '<div class="cust-hd">Your specific needs</div>';
  html +=
    '<div class="fld"><label>What should we know?</label><div class="sel-box"><select id="custNeedPreset">' +
    custNeedPresetsForService().map(function (p) {
      return (
        '<option value="' +
        custEsc(p.id) +
        '"' +
        (c.customNeedPreset === p.id ? ' selected' : '') +
        '>' +
        custEsc(p.label) +
        '</option>'
      );
    }).join('') +
    '</select></div></div>';
  html +=
    '<div class="fld"><label>Details (optional)</label><div class="sel-box"><input type="text" id="custNeedText" maxlength="200" placeholder="e.g. indoor church + hall, need live stream link" value="' +
    custEsc(c.customNeedText || '') +
    '"></div></div>';

  const reqs = svcOwner.requirements || [];
  if (reqs.length) {
    html += '<div class="cust-hd">Studio requirements</div>';
    reqs.forEach(function (r, i) {
      const key = 'req_' + i;
      html +=
        '<label class="chk-row' +
        (c.reqAck[key] ? ' on' : '') +
        '"><input type="checkbox" data-req-ack="' +
        custEsc(key) +
        '"' +
        (c.reqAck[key] ? ' checked' : '') +
        '> ' +
        custEsc(r) +
        '</label>';
    });
  }

  html += '<div class="cust-hd">Additional notes</div><textarea class="notes" id="custNotes" maxlength="500" placeholder="Respectful coverage notes, family contacts, preferred delivery…">' + custEsc(c.notes) + '</textarea><div class="notes-count"><span id="noteCt">0</span>/500</div>';

  return html;
}

function custCustomizeRequirementLines(state, owner) {
  const c = state.customize;
  const lines = [];
  const optFns = custOptionalFunctionsForOwner(owner);
  custExtraFunctionsSelectedList(c, optFns).forEach(function (fn) {
    lines.push('Also cover: ' + fn);
  });
  Object.keys(c.functions || {}).forEach(function (fn) {
    if (c.functions[fn]) lines.push('Also cover: ' + fn);
  });
  if (c.albumSize || c.albumPages) {
    let alb = 'Album';
    if (c.albumSize === 'Custom' && c.albumSizeCustom) alb += ' ' + c.albumSizeCustom;
    else if (c.albumSize) alb += ' ' + c.albumSize;
    if (c.albumPages === 'Custom' && c.albumPagesCustom) alb += ' · ' + c.albumPagesCustom + ' pages';
    else if (c.albumPages) alb += ' · ' + c.albumPages + ' pages';
    if (c.albumPaper) alb += ' · ' + (c.albumPaper === 'Custom' && c.albumPaperCustom ? c.albumPaperCustom : c.albumPaper) + ' paper';
    lines.push(alb);
  }
  if (c.customNeedPreset || c.customNeedText) {
    const presets = state.mode === 'service' ? custNeedPresetsForService() : CUST_NEED_PRESETS;
    const preset = presets.find(function (p) {
      return p.id === c.customNeedPreset;
    });
    if (preset && preset.id && preset.id !== 'custom') lines.push(preset.label);
    if (c.customNeedText) lines.push(c.customNeedText);
  }
  (owner.requirements || []).forEach(function (r, i) {
    if (c.reqAck['req_' + i]) lines.push('Confirmed: ' + r);
  });
  return lines;
}
