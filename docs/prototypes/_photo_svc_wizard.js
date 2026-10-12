/* Photography service wizard — Add Service flow (8 steps, Final V1) */

const SVC_PRICE_TYPES = [
  { id: 'fixed', label: 'Fixed price' },
  { id: 'from', label: 'Starting from' },
  { id: 'range', label: 'Price range' },
  { id: 'hour', label: 'Per hour' },
  { id: 'unit', label: 'Per item / unit' },
];
const SVC_ONLY_EXTRA_DEFAULTS = [
  { name: 'Extra 10 Edited Photos', price: 500, unit: 'Per Set' },
  { name: 'Extra Hour', price: 1000, unit: 'Per Hour' },
];

function svcPresetExtraNames() {
  return SVC_ONLY_EXTRA_DEFAULTS.map(function (x) {
    return x.name;
  }).concat(PKG_EXTRA_DEFAULTS);
}

function svcExtraDefaults() {
  const o = typeof pkgExtraDefaults === 'function' ? pkgExtraDefaults() : {};
  SVC_ONLY_EXTRA_DEFAULTS.forEach(function (row) {
    o[row.name] = {
      mode: 'extra',
      price: row.price != null ? row.price : 0,
      basis: row.unit === 'Per Hour' ? 'Per Hour' : 'Per Event',
    };
  });
  return o;
}

function allSvcExtrasNames(d) {
  const excluded = d.excludedExtras || [];
  return svcPresetExtraNames()
    .concat((d.customExtras || []).map(function (x) {
      return x.name;
    }))
    .filter(function (name) {
      return excluded.indexOf(name) < 0;
    });
}

function svcExtraUnitToBasis(unit) {
  return unit === 'Per Hour' ? 'Per Hour' : 'Per Event';
}

function ensureSvcExtrasModel(d) {
  if (typeof migrateDroneHelicamExtra === 'function') migrateDroneHelicamExtra(d);
  if (!d.extras) d.extras = {};
  if (!d.customExtras) d.customExtras = [];
  if (!d.excludedExtras) d.excludedExtras = [];
  const defaults = svcExtraDefaults();
  Object.keys(defaults).forEach(function (name) {
    if (!d.extras[name] && d.excludedExtras.indexOf(name) < 0) {
      d.extras[name] = defaults[name];
    }
  });
  const legacy = d.optionalExtras;
  if (legacy && legacy.length) {
    legacy.forEach(function (row) {
      const name = (row.name || '').trim();
      if (!name) return;
      const preset = svcPresetExtraNames().indexOf(name) >= 0;
      if (
        !preset &&
        !d.customExtras.some(function (x) {
          return x.name === name;
        })
      ) {
        d.customExtras.push({ name: name });
      }
      if (!d.extras[name]) {
        d.extras[name] = {
          mode: 'extra',
          price: row.price != null ? row.price : 0,
          basis: svcExtraUnitToBasis(row.unit),
        };
      }
    });
    delete d.optionalExtras;
  }
}
const SVC_POLICY_DEFAULTS = [
  'Cancellation Policy',
  'Rescheduling Policy',
  'Revision Limit',
  'Data Retention',
  'Delivery Conditions',
];
const SVC_REQ_DEFAULTS = [
  'Customer provides outfit / preparation',
  'Electricity / power at venue',
  'Travel charges may apply for outside locations',
  'Required permissions / materials',
];
const SVC_DUR_OPTS = ['Up to 2 Hours', 'Up to 4 Hours', 'Up to 6 Hours', 'Up to 8 Hours', 'Full Day', 'Custom'];

function newSvcDraft() {
  const photoDetails = defaultPhotoDetails();
  const videoDetails = defaultVideoDetails();
  return {
    category: 'funeral',
    name: 'Funeral / Memorial Photography & Live Streaming',
    blurb:
      'Respectful photo and video coverage for funeral and memorial services, with optional live streaming for remote family.',
    coverUploaded: true,
    pricingType: 'fixed',
    listPrice: 55000,
    discountYes: 'yes',
    discountPct: 10,
    price: 49500,
    durEnabled: true,
    duration: 'Up to 4 Hours',
    durationCustom: '',
    extraHour: 1500,
    team: { photoCandid: 1, photoTraditional: 1, videoCandid: 1, videoTraditional: 0 },
    deliverTab: 'photos',
    deliverPhoto: ['Edited Photos', 'Colour-Graded Photos'],
    deliverVideo: ['Highlight Video', 'Live Streaming'],
    deliverDigital: ['Google Drive Link', 'Online Gallery'],
    customDeliverPhoto: [],
    customDeliverVideo: ['Live Streaming'],
    customDeliverDigital: [],
    photoDetails: photoDetails,
    videoDetails: videoDetails,
    albumPrints: albumPrintsAllOff(),
    extras: svcExtraDefaults(),
    customExtras: [],
    excludedExtras: [],
    deliveryMap: {
      'Edited Photos': '5 Working Days',
      'Highlight Video': '7 Working Days',
    },
    policies: ['Cancellation Policy', 'Rescheduling Policy'],
    cancelRules: clonePkgPolicyTierDefaults(),
    rescheduleRules: clonePkgPolicyTierDefaults(),
    cancelPolicyNote: '',
    reschedulePolicyNote: '',
    cancelReschedTab: 'cancel',
    policyValues: {
      'Cancellation Policy': defaultPolicyValue('Cancellation Policy'),
      'Rescheduling Policy': defaultPolicyValue('Rescheduling Policy'),
    },
    customPolicies: [],
    requirements: ['Travel charges may apply for outside locations'],
    customRequirements: [],
    showAllCats: false,
    status: 'draft',
  };
}

function recordToSvcDraft(rec) {
  const base = newSvcDraft();
  const m = JSON.parse(JSON.stringify(rec || {}));
  const merged = Object.assign(base, m, {
    team: Object.assign(base.team, m.team || {}),
    deliveryMap: Object.assign(base.deliveryMap, m.deliveryMap || {}),
    photoDetails: Object.assign(base.photoDetails, m.photoDetails || {}),
    videoDetails: Object.assign(base.videoDetails, m.videoDetails || {}),
    albumPrints: Object.assign(base.albumPrints, m.albumPrints || {}),
  });
  merged.extras = Object.assign({}, base.extras, m.extras || {});
  merged.customExtras = m.customExtras || base.customExtras;
  merged.excludedExtras = m.excludedExtras || base.excludedExtras;
  ensureSvcExtrasModel(merged);
  ensureServiceDeliverableModel(merged);
  ensurePkgPolicyRules(merged);
  ensurePolicyValues(merged);
  return merged;
}

function recordToPkgDraft(rec) {
  const base = newPkgDraft();
  const m = JSON.parse(JSON.stringify(rec || {}));
  const merged = Object.assign(base, m);
  migrateDroneHelicamExtra(merged);
  migrateLegacyPkgCoverage(merged);
  ensurePkgMarketingFields(merged);
  merged.photoDetails = Object.assign({}, base.photoDetails, m.photoDetails || {});
  merged.videoDetails = Object.assign({}, base.videoDetails, m.videoDetails || {});
  merged.albumPrints = Object.assign({}, base.albumPrints, m.albumPrints || {});
  merged.extras = Object.assign({}, base.extras, m.extras || {});
  merged.deliveryMap = Object.assign({}, base.deliveryMap, m.deliveryMap || {});
  ensureDefaultPaymentStages(merged);
  ensurePolicyValues(merged);
  ensurePkgPolicyRules(merged);
  if (!merged.policyValues) merged.policyValues = {};
  (merged.policies || []).forEach(function (name) {
    if (!merged.policyValues[name]) merged.policyValues[name] = defaultPolicyValue(name);
  });
  return merged;
}

function svcCatLabel(id) {
  const c = SVC_CATEGORIES.find(function (x) {
    return x.id === id;
  });
  return c ? c.label : '—';
}

function svcQtyStep(field, val) {
  val = Math.max(0, +val || 0);
  return (
    '<div class="qty-step" data-svc-qty="' +
    field +
    '"><button type="button" data-qty-d="-1">−</button><span>' +
    val +
    '</span><button type="button" data-qty-d="1">+</button></div>'
  );
}

function svcSelectedDeliverableKeys(d) {
  ensureServiceDeliverableModel(d);
  return selectedDeliverableKeys(d);
}

function pruneSvcDeliveryMap(d) {
  ensureServiceDeliverableModel(d);
  pruneDeliveryMap(d);
}

function svcDeliveryKeys(d) {
  ensureServiceDeliverableModel(d);
  syncDeliveryMap(d);
  return deliverablesForDeliveryStep(d);
}

function renderSvcBasicsStep(d) {
  const hasCover = !!d.coverUploaded;
  return (
    '<p class="svc-basics-lead">This is what customers see on your service listing — keep the name clear and the description short.</p>' +
    '<div class="svc-basics-cat"><span class="svc-basics-cat-lbl">Category</span>' +
    '<div class="cat-pill"><span>' +
    esc(svcCatLabel(d.category)) +
    '</span><button type="button" class="link-inline" data-action="svc-change-cat">Change</button></div></div>' +
    '<div class="fld"><label>Service name *</label><input id="f_svcName" value="' +
    esc(d.name) +
    '" placeholder="e.g. Baptism photography coverage" autocomplete="off"></div>' +
    '<div class="fld"><label>Short description *</label><textarea id="f_blurb" maxlength="300" placeholder="What is included, who it is for, and what makes your service stand out.">' +
    esc(d.blurb) +
    '</textarea><p class="hint" id="blurbCount">' +
    (d.blurb || '').length +
    '/300 characters</p></div>' +
    '<div class="fld"><label>Cover photo *</label>' +
    '<p class="hint" style="margin:0 0 10px">Main image on search and booking — one photo is enough to start.</p>' +
    '<button type="button" class="svc-cover-upload' +
    (hasCover ? ' has-image' : '') +
    '" data-action="svc-cover-upload">' +
    '<span class="svc-cover-upload-ico" aria-hidden="true">📷</span>' +
    '<span class="svc-cover-upload-txt"><b>' +
    (hasCover ? 'Cover photo added' : 'Upload cover photo') +
    '</b><span class="sub">' +
    (hasCover ? 'Tap to change photo' : 'JPG or PNG · demo upload') +
    '</span></span></button></div>'
  );
}

function renderSvcStep(step, d) {
  syncSvcPrice(d);
  switch (step) {
    case 0: {
      const q = d.catQuery || '';
      const visible = SVC_CATEGORIES.filter(function (c, i) {
        if (!d.showAllCats && i >= 10) return false;
        if (!q) return true;
        return c.label.toLowerCase().indexOf(q.toLowerCase()) >= 0;
      });
      return (
        '<div class="sa-search" style="margin:0 0 12px"><span>' +
        photoIcon('search') +
        '</span><input type="search" id="catSearch" placeholder="Search categories…" value="' +
        esc(q) +
        '"></div>' +
        '<div class="cat-grid" id="f_cats">' +
        visible
          .map(function (c) {
            return (
              '<button type="button" class="cat-card' +
              (d.category === c.id ? ' on' : '') +
              '" data-cat="' +
              c.id +
              '" data-lbl="' +
              esc(c.label) +
              '"><span class="tick">✓</span><div class="ph"></div>' +
              esc(c.label) +
              '</button>'
            );
          })
          .join('') +
        '</div>' +
        (SVC_CATEGORIES.length > 10
          ? '<button type="button" class="link-add" data-action="svc-more-cats">' +
            (d.showAllCats ? 'Show fewer categories' : 'Show more categories ↓') +
            '</button>'
          : '')
      );
    }
    case 1:
      return renderSvcBasicsStep(d);
    case 2:
      return (
        '<div class="pricing-step">' +
        '<div class="fld"><label>Pricing type</label><div class="radio-col" id="f_priceTypes">' +
        SVC_PRICE_TYPES.map(function (t) {
          return (
            '<label class="radio-line"><input type="radio" name="svcPriceType" value="' +
            t.id +
            '" ' +
            (d.pricingType === t.id ? 'checked' : '') +
            '> ' +
            esc(t.label) +
            '</label>'
          );
        }).join('') +
        '</div></div>' +
        '<div class="fld"><label>List price (₹) *</label><input type="number" id="f_listPrice" value="' +
        d.listPrice +
        '"></div>' +
        '<div class="fld"><label>Discount</label><div class="radio-row">' +
        '<label><input type="radio" name="svcDiscYes" value="yes" ' +
        (d.discountYes === 'yes' ? 'checked' : '') +
        '> Yes</label>' +
        '<label><input type="radio" name="svcDiscYes" value="no" ' +
        (d.discountYes === 'no' ? 'checked' : '') +
        '> No</label></div></div>' +
        (d.discountYes === 'yes'
          ? '<div class="fld"><label>Discount %</label><input type="number" id="f_discountPct" value="' +
            d.discountPct +
            '"></div>' +
            '<div class="price-panel"><b>Customer pays ' +
            inr(d.price) +
            '</b></div>'
          : '') +
        '</div>'
      );
    case 3:
      return (
        '<label class="chk-row' +
        (d.durEnabled ? ' on' : '') +
        '" style="margin-bottom:12px"><input type="checkbox" id="f_durOn" ' +
        (d.durEnabled ? 'checked' : '') +
        '> Add duration &amp; team coverage</label>' +
        (d.durEnabled
          ? (function () {
              normalizeCustomOption(d, 'duration', 'durationCustom', SVC_DUR_OPTS, 'Up to 4 Hours');
              let h =
                '<div class="fld"><label>Duration</label><select id="f_duration">' +
                buildSelectOptionsHtml(SVC_DUR_OPTS, d.duration) +
                '</select></div>';
              if (d.duration === 'Custom') {
                h += renderCustomTextInput(
                  'id="f_durationCustom"',
                  d.durationCustom,
                  'Describe duration',
                  'e.g. 5 hours on location'
                );
              }
              return h;
            })() +
            '<div class="fld"><label>Additional hour charge (₹)</label><input type="number" id="f_extraHour" value="' +
            d.extraHour +
            '"><span class="hint"> Per hour</span></div>' +
            '<p class="lbl">Photographers</p>' +
            '<div class="role-row"><span>Candid photographer</span>' +
            svcQtyStep('photoCandid', d.team.photoCandid) +
            '</div>' +
            '<div class="role-row"><span>Traditional photographer</span>' +
            svcQtyStep('photoTraditional', d.team.photoTraditional) +
            '</div>' +
            '<p class="lbl">Videographers</p>' +
            '<div class="role-row"><span>Candid videographer</span>' +
            svcQtyStep('videoCandid', d.team.videoCandid) +
            '</div>' +
            '<div class="role-row"><span>Traditional videographer</span>' +
            svcQtyStep('videoTraditional', d.team.videoTraditional) +
            '</div>'
          : '<p class="sub">Duration and team details are optional for this service.</p>')
      );
    case 4:
      ensureServiceDeliverableModel(d);
      return renderDeliverablesStep(d);
    case 5:
      ensureSvcExtrasModel(d);
      return renderWizardExtrasStep(d, allSvcExtrasNames, 'Add new extra');
    case 6: {
      const included = svcSelectedDeliverableKeys(d);
      const keys = svcDeliveryKeys(d);
      if (!included.length) {
        return (
          '<div class="hub-empty" style="margin:0">' +
          '<div class="hub-empty-ico">📦</div><b>No deliverables selected</b>' +
          '<p>Go back to <b>What\'s included</b> and check at least one photo, video, album, or digital option.</p></div>' +
          '<button type="button" class="btn btn-ghost" data-goto-step="4" style="margin-top:12px;width:100%">← Back to what\'s included</button>'
        );
      }
      if (!keys.length) {
        return (
          '<p class="sub">Items such as <b>Live Streaming</b> are provided during the event. They stay in your service but do not need a post-event delivery timeline here.</p>' +
          '<div class="warn-box" style="margin-top:12px">Tap <b>Next</b> to continue.</div>'
        );
      }
      keys.forEach(function (k) {
        if (!d.deliveryMap[k]) d.deliveryMap[k] = '5 Working Days';
      });
      return (
        '<p class="sub">Set delivery timeline for each item you included on the previous step.</p>' +
        keys
          .map(function (k) {
            return (
              '<div class="fld del-row"><label>' +
              esc(k) +
              '</label><select data-svc-del="' +
              esc(k) +
              '">' +
              DELIVERY_TIMELINES.map(function (t) {
                return (
                  '<option' +
                  (d.deliveryMap[k] === t ? ' selected' : '') +
                  '>' +
                  t +
                  '</option>'
                );
              }).join('') +
              '</select></div>'
            );
          })
          .join('') +
        '<div class="warn-box">Delivery timelines can be different for each deliverable.</div>'
      );
    }
    case 7:
      return (
        renderCancelReschedBlock(d) +
        '<p class="lbl" style="margin-top:20px">Other policies (optional)</p>' +
        SVC_POLICY_DEFAULTS.concat(d.customPolicies || [])
          .filter(function (item) {
            return item !== 'Cancellation Policy' && item !== 'Rescheduling Policy';
          })
          .map(function (item) {
            const on = d.policies.indexOf(item) >= 0;
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-svc-pol="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> ' +
              esc(item) +
              '</label>'
            );
          })
          .join('') +
        '<button type="button" class="link-add" data-action="svc-add-pol">+ Add new policy</button>' +
        '<p class="lbl">Customer requirements</p>' +
        SVC_REQ_DEFAULTS.concat(d.customRequirements || [])
          .map(function (item) {
            const on = d.requirements.indexOf(item) >= 0;
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-svc-req="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> ' +
              esc(item) +
              '</label>'
            );
          })
          .join('') +
        '<button type="button" class="link-add" data-action="svc-add-req">+ Add new requirement</button>' +
        '<div class="review-summary" style="margin-top:16px"><b>' +
        esc(d.name) +
        '</b><br><span class="sub">' +
        inr(d.price) +
        ' · ' +
        esc(svcCatLabel(d.category)) +
        '</span></div>' +
        '<div class="cta two-col" style="margin-top:12px">' +
        '<button type="button" class="btn btn-ghost" data-action="svc-publish-draft">Save as draft</button>' +
        '<button type="button" class="btn btn-blue" data-action="svc-publish-now">Publish service</button></div>'
      );
    default:
      return '';
  }
}

function readSvcWizardFields(d) {
  const g = function (id) {
    return el(id);
  };
  if (g('f_svcName')) d.name = g('f_svcName').value.trim();
  if (g('f_blurb')) d.blurb = g('f_blurb').value.trim();
  if (g('catSearch')) d.catQuery = g('catSearch').value.trim();
  const pt = document.querySelector('input[name="svcPriceType"]:checked');
  if (pt) d.pricingType = pt.value;
  if (g('f_listPrice')) d.listPrice = +g('f_listPrice').value || 0;
  const dy = document.querySelector('input[name="svcDiscYes"]:checked');
  if (dy) d.discountYes = dy.value;
  if (g('f_discountPct')) d.discountPct = +g('f_discountPct').value || 0;
  if (g('f_durOn')) d.durEnabled = g('f_durOn').checked;
  if (g('f_duration')) {
    d.duration = g('f_duration').value;
    if (d.duration !== 'Custom') d.durationCustom = '';
  }
  if (g('f_durationCustom')) d.durationCustom = g('f_durationCustom').value.trim();
  if (g('f_extraHour')) d.extraHour = +g('f_extraHour').value || 0;
  readDeliverableFieldsFromDom(d);
  readExtrasFieldsFromDom(d);
  document.querySelectorAll('[data-svc-del]').forEach(function (sel) {
    d.deliveryMap[sel.getAttribute('data-svc-del')] = sel.value;
  });
  pruneSvcDeliveryMap(d);
  readPkgPolicyTiersFromDom(d);
  syncSvcPrice(d);
}

function bindSvcWizard(d) {
  const body = el('wizBody');
  if (!body) return;
  body.onclick = function (e) {
    const tabBtn = e.target.closest('[data-del-tab]');
    if (tabBtn) {
      readSvcWizardFields(d);
      d.deliverTab = tabBtn.getAttribute('data-del-tab');
      renderWizardBody();
      return;
    }
    const t = e.target.closest('[data-action],[data-goto-step],[data-qty-d],[data-cat]');
    if (t) {
      if (t.getAttribute('data-goto-step') != null) {
        readSvcWizardFields(d);
        wiz.step = +t.getAttribute('data-goto-step');
        renderWizard();
        return;
      }
      if (t.getAttribute('data-cat')) {
        d.category = t.getAttribute('data-cat');
        renderWizardBody();
        return;
      }
      const act = t.getAttribute('data-action');
      if (
        runExtraWizardAction(
          act,
          t,
          d,
          readSvcWizardFields,
          svcPresetExtraNames()
        )
      )
        return;
      if (runDeliverableWizardAction(act, t, d, readSvcWizardFields)) return;
      if (act === 'svc-more-cats') {
        d.showAllCats = !d.showAllCats;
        renderWizardBody();
        return;
      }
      if (act === 'svc-change-cat') {
        wiz.step = 0;
        renderWizard();
        return;
      }
      if (act === 'svc-cover-upload') {
        d.coverUploaded = true;
        toast('Cover photo updated (demo).');
        renderWizardBody();
        return;
      }
      if (act === 'svc-add-pol') {
        const n = prompt('Policy');
        if (n) {
          d.customPolicies.push(n.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'svc-add-req') {
        const n = prompt('Requirement');
        if (n) {
          d.customRequirements.push(n.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'cr-policy-tab') {
        onCrPolicyTab(d, readSvcWizardFields, t.getAttribute('data-tab'));
        return;
      }
      if (act === 'cr-policy-add-tier') {
        onCrPolicyAddTier(d, readSvcWizardFields, t.getAttribute('data-policy'));
        return;
      }
      if (act === 'cr-policy-del-tier') {
        onCrPolicyDelTier(d, readSvcWizardFields, t);
        return;
      }
      if (act === 'svc-publish-draft') {
        readSvcWizardFields(d);
        finishWizard(false);
        return;
      }
      if (act === 'svc-publish-now') {
        readSvcWizardFields(d);
        finishWizard(true);
        return;
      }
    }
    const qtyBtn = e.target.closest('[data-qty-d]');
    if (qtyBtn) {
      const wrap = qtyBtn.closest('[data-svc-qty]');
      if (!wrap) return;
      const field = wrap.getAttribute('data-svc-qty');
      const delta = +qtyBtn.getAttribute('data-qty-d');
      const span = wrap.querySelector('span');
      let v = +span.textContent + delta;
      v = Math.max(0, Math.min(20, v));
      span.textContent = v;
      if (d.team[field] != null) d.team[field] = v;
      return;
    }
    if (handleExtraHourlyCheckboxChange(e)) return;
  };
  body.onchange = function (e) {
    const t = e.target;
    if (handleExtraModeSelectChange(e, d)) return;
    if (handleExtraHourlyCheckboxChange(e)) return;
    if (deliverableCheckboxChange(t, d)) return;
    if (t.matches('[data-svc-pol]')) {
      const v = t.getAttribute('data-svc-pol');
      if (t.checked) {
        if (d.policies.indexOf(v) < 0) d.policies.push(v);
      } else d.policies = d.policies.filter(function (x) {
        return x !== v;
      });
      return;
    }
    if (t.matches('[data-svc-req]')) {
      const v = t.getAttribute('data-svc-req');
      if (t.checked) {
        if (d.requirements.indexOf(v) < 0) d.requirements.push(v);
      } else d.requirements = d.requirements.filter(function (x) {
        return x !== v;
      });
      return;
    }
    if (t.id === 'f_durOn') {
      d.durEnabled = t.checked;
      renderWizardBody();
    }
    if (t.id === 'f_duration') {
      readSvcWizardFields(d);
      renderWizardBody();
    }
  };
  const cs = el('catSearch');
  if (cs)
    cs.oninput = function () {
      d.catQuery = cs.value.trim();
      renderWizardBody();
    };
  const bl = el('f_blurb');
  if (bl)
    bl.oninput = function () {
      d.blurb = bl.value;
      const c = el('blurbCount');
      if (c) c.textContent = bl.value.length + '/300';
    };
  ['f_listPrice', 'f_discountPct'].forEach(function (id) {
    const node = el(id);
    if (node)
      node.oninput = function () {
        readSvcWizardFields(d);
        renderWizardBody();
      };
  });
  document.querySelectorAll('input[name="svcDiscYes"],input[name="svcPriceType"]').forEach(function (r) {
    r.onchange = function () {
      readSvcWizardFields(d);
      renderWizardBody();
    };
  });
  if (wiz.step === 5) syncAllExtraRowModes();
}
