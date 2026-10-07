/* Photography service wizard — Add Service flow (8 steps, Final V1) */

const SVC_PRICE_TYPES = [
  { id: 'fixed', label: 'Fixed price' },
  { id: 'from', label: 'Starting from' },
  { id: 'range', label: 'Price range' },
  { id: 'hour', label: 'Per hour' },
  { id: 'unit', label: 'Per item / unit' },
];
function svcPhotoDeliverOptions(d) {
  return PHOTO_DELIVER.concat(d.customInclPhoto || []);
}
function svcVideoDeliverOptions(d) {
  return VIDEO_DELIVER.concat(d.customInclVideo || []);
}
function svcDigitalDeliverOptions(d) {
  const base = DIGITAL_DELIVER.map(function (x) {
    return x.id;
  });
  return base.concat(d.customInclDigital || []);
}
function svcAlbumDeliverOptions() {
  return ALBUM_PRINT_TYPES.slice();
}

function normalizeSvcDeliverables(d) {
  if (!d.inclPhoto) d.inclPhoto = [];
  if (!d.inclVideo) d.inclVideo = [];
  if (!d.inclDigital) d.inclDigital = [];
  if (!d.inclAlbums) d.inclAlbums = [];
  if (!d.customInclPhoto) d.customInclPhoto = [];
  if (!d.customInclVideo) d.customInclVideo = [];
  if (!d.customInclDigital) d.customInclDigital = [];
  d.inclPhoto = d.inclPhoto.map(function (x) {
    if (x === 'High-Resolution Photos') return 'Colour-Graded Photos';
    return x;
  });
  const nextVideo = [];
  (d.inclVideo || []).forEach(function (x) {
    let mapped = x;
    if (x === 'Full Video') mapped = 'Full-Length Video';
    if (x === 'Reel (1 Minute)') mapped = 'Reel';
    if (VIDEO_DELIVER.indexOf(mapped) >= 0) nextVideo.push(mapped);
    else if (d.customInclVideo.indexOf(mapped) < 0) d.customInclVideo.push(mapped);
  });
  d.inclVideo = nextVideo;
  if (d.album && d.album.include && d.inclAlbums.indexOf('Photo Album') < 0) {
    d.inclAlbums.push('Photo Album');
  }
}
const SVC_EXTRA_DEFAULTS = [
  { name: 'Extra 10 Edited Photos', price: 500, unit: 'Per Set' },
  { name: 'Extra Hour', price: 1000, unit: 'Per Hour' },
  { name: 'Live Streaming', price: 5000, unit: 'Per Event' },
  { name: 'Drone Coverage', price: 5000, unit: 'Per Event' },
];
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
  return {
    category: 'funeral',
    name: 'Funeral / Memorial Photography & Live Streaming',
    blurb:
      'Respectful photo and video coverage for funeral and memorial services, with optional live streaming for remote family.',
    coverCount: 1,
    pricingType: 'fixed',
    listPrice: 55000,
    discountYes: 'yes',
    discountPct: 10,
    price: 49500,
    durEnabled: true,
    duration: 'Up to 4 Hours',
    extraHour: 1500,
    team: { photoCandid: 1, photoTraditional: 1, videoCandid: 1, videoTraditional: 0 },
    inclPhoto: ['Edited Photos', 'Colour-Graded Photos'],
    inclVideo: ['Highlight Video'],
    inclDigital: ['Google Drive Link', 'Online Gallery'],
    inclAlbums: [],
    customInclPhoto: [],
    customInclVideo: ['Live Streaming'],
    customInclDigital: [],
    album: { include: false, qty: 1, leaves: 20, size: '12 x 12 inch' },
    optionalExtras: JSON.parse(JSON.stringify(SVC_EXTRA_DEFAULTS)),
    customExtras: [],
    deliveryMap: {
      'Edited Photos': '5 Working Days',
      'Highlight Video': '7 Working Days',
      'Live Streaming': 'Same Day',
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
    album: Object.assign(base.album, m.album || {}),
    optionalExtras: m.optionalExtras || base.optionalExtras,
    deliveryMap: Object.assign(base.deliveryMap, m.deliveryMap || {}),
  });
  normalizeSvcDeliverables(merged);
  ensurePkgPolicyRules(merged);
  ensurePolicyValues(merged);
  return merged;
}

function recordToPkgDraft(rec) {
  const base = newPkgDraft();
  const m = JSON.parse(JSON.stringify(rec || {}));
  const merged = Object.assign(base, m);
  merged.photoTypes = Object.assign({}, base.photoTypes, m.photoTypes || {});
  merged.videoTypes = Object.assign({}, base.videoTypes, m.videoTypes || {});
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
  const keys = [];
  (d.inclPhoto || []).forEach(function (x) {
    keys.push(x);
  });
  (d.inclVideo || []).forEach(function (x) {
    keys.push(x);
  });
  (d.inclAlbums || []).forEach(function (x) {
    keys.push(x);
  });
  (d.inclDigital || []).forEach(function (x) {
    keys.push(x);
  });
  return keys;
}

function pruneSvcDeliveryMap(d) {
  if (!d.deliveryMap) d.deliveryMap = {};
  const allowed = {};
  svcSelectedDeliverableKeys(d).forEach(function (k) {
    allowed[k] = true;
  });
  Object.keys(d.deliveryMap).forEach(function (k) {
    if (!allowed[k]) delete d.deliveryMap[k];
  });
}

function svcDeliveryKeys(d) {
  pruneSvcDeliveryMap(d);
  return svcSelectedDeliverableKeys(d);
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
      return (
        '<div class="fld"><label>Service name *</label><input id="f_svcName" value="' +
        esc(d.name) +
        '"></div>' +
        '<div class="fld"><label>Short description *</label><textarea id="f_blurb" maxlength="300">' +
        esc(d.blurb) +
        '</textarea><p class="hint" id="blurbCount">' +
        (d.blurb || '').length +
        '/300</p></div>' +
        '<div class="fld"><label>Service category</label><div class="cat-pill">' +
        esc(svcCatLabel(d.category)) +
        ' <button type="button" class="link-inline" data-action="svc-change-cat">Change</button></div></div>' +
        '<div class="fld"><label>Cover image *</label><div class="cover-row">' +
        '<div class="cover-thumb on">🖼</div><button type="button" class="btn btn-ghost" data-action="svc-cover-edit" style="flex:1;padding:10px">Edit</button></div>' +
        '<div class="cover-row" style="margin-top:8px">' +
        '<div class="cover-thumb"></div><div class="cover-thumb"></div><div class="cover-thumb"></div>' +
        '<button type="button" class="btn btn-ghost" data-action="svc-cover-more" style="flex:1;padding:10px">+ Add more</button></div>'
      );
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
            '><span>' +
            esc(t.label) +
            '</span></label>'
          );
        }).join('') +
        '</div></div>' +
        '<div class="fld"><label>Price (₹) *</label><input type="number" id="f_listPrice" value="' +
        d.listPrice +
        '"></div>' +
        '<div class="fld"><label>Offer discount on this price?</label><div class="radio-disc">' +
        '<label><input type="radio" name="svcDiscYes" value="no" ' +
        (d.discountYes !== 'yes' ? 'checked' : '') +
        '> No</label>' +
        '<label><input type="radio" name="svcDiscYes" value="yes" ' +
        (d.discountYes === 'yes' ? 'checked' : '') +
        '> Yes, give discount</label></div></div>' +
        '<div class="fld"><label>Discount %</label><input type="number" id="f_discountPct" value="' +
        d.discountPct +
        '" min="0" max="100"></div>' +
        '<div class="preview-green price-preview"><span class="sub" style="display:block;margin-bottom:4px">Customer will see:</span>' +
        '<div class="amount-row"><b class="price-amt">' +
        inr(d.price) +
        '</b>' +
        (d.discountYes === 'yes' && d.discountPct > 0
          ? '<span class="was">' +
            inr(d.listPrice) +
            '</span><span class="off-pill">' +
            d.discountPct +
            '% OFF</span>'
          : '') +
        '</div></div></div>'
      );
    case 3:
      return (
        '<label class="manage-check-row"><input type="checkbox" id="f_durOn" ' +
        (d.durEnabled ? 'checked' : '') +
        '> Enable duration &amp; coverage for this service</label>' +
        (d.durEnabled
          ? '<div class="fld"><label>Service duration</label><select id="f_duration">' +
            SVC_DUR_OPTS.map(function (o) {
              return (
                '<option' +
                (d.duration === o ? ' selected' : '') +
                '>' +
                o +
                '</option>'
              );
            }).join('') +
            '</select></div>' +
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
      normalizeSvcDeliverables(d);
      return (
        '<p class="sub" style="margin:0 0 12px">Same deliverable options as <b>packages</b> — tick what this service includes. Details like quantity and format are set on packages; here you choose the items only.</p>' +
        '<p class="lbl">Photography</p>' +
        svcPhotoDeliverOptions(d)
          .map(function (item) {
            const on = d.inclPhoto.indexOf(item) >= 0;
            const hint = PHOTO_DELIVER_HINTS[item] || '';
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-sincl-photo="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> <span>' +
              esc(item) +
              (hint ? '<em class="chk-hint">' + esc(hint) + '</em>' : '') +
              '</span></label>'
            );
          })
          .join('') +
        '<button type="button" class="link-add" data-action="svc-add-incl-photo">+ Add custom photo type</button>' +
        '<p class="lbl">Video</p>' +
        svcVideoDeliverOptions(d)
          .map(function (item) {
            const on = d.inclVideo.indexOf(item) >= 0;
            const hint = VIDEO_DELIVER_HINTS[item] || '';
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-sincl-video="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> <span>' +
              esc(item) +
              (hint ? '<em class="chk-hint">' + esc(hint) + '</em>' : '') +
              '</span></label>'
            );
          })
          .join('') +
        '<button type="button" class="link-add" data-action="svc-add-incl-video">+ Add custom video type</button>' +
        '<p class="lbl">Albums &amp; prints</p>' +
        svcAlbumDeliverOptions()
          .map(function (item) {
            const on = d.inclAlbums.indexOf(item) >= 0;
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-sincl-album="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> ' +
              esc(item) +
              '</label>'
            );
          })
          .join('') +
        '<p class="lbl">Digital delivery</p>' +
        svcDigitalDeliverOptions(d)
          .map(function (item) {
            const on = d.inclDigital.indexOf(item) >= 0;
            const meta = DIGITAL_DELIVER.find(function (x) {
              return x.id === item;
            });
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-sincl-digital="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> <span>' +
              (meta ? meta.icon + ' ' : '') +
              esc(item) +
              (meta && meta.desc ? '<em class="chk-hint">' + esc(meta.desc) + '</em>' : '') +
              '</span></label>'
            );
          })
          .join('') +
        '<button type="button" class="link-add" data-action="svc-add-incl-digital">+ Add custom digital option</button>'
      );
    case 5:
      return (
        '<div id="f_svcExtras">' +
        (d.optionalExtras || [])
          .map(function (row, i) {
            return (
              '<div class="extra-row svc-extra" data-svc-extra-idx="' +
              i +
              '"><span class="extra-ico">✦</span><input type="text" data-svc-extra-name value="' +
              esc(row.name) +
              '"><input type="number" data-svc-extra-price value="' +
              (row.price || 0) +
              '"><select data-svc-extra-unit><option' +
              (row.unit === 'Per Set' ? ' selected' : '') +
              '>Per Set</option><option' +
              (row.unit === 'Per Hour' ? ' selected' : '') +
              '>Per Hour</option><option' +
              (row.unit === 'Per Event' ? ' selected' : '') +
              '>Per Event</option></select>' +
              '<button type="button" class="pay-del" data-action="svc-del-extra" data-idx="' +
              i +
              '">🗑</button></div>'
            );
          })
          .join('') +
        '</div>' +
        '<button type="button" class="link-add" data-action="svc-add-extra">+ Add new extra</button>'
      );
    case 6: {
      const keys = svcDeliveryKeys(d);
      if (!keys.length) {
        return (
          '<div class="hub-empty" style="margin:0">' +
          '<div class="hub-empty-ico">📦</div><b>No deliverables selected</b>' +
          '<p>Go back to <b>What\'s included</b> and check at least one photo, video, album, or digital option.</p></div>' +
          '<button type="button" class="btn btn-ghost" data-goto-step="4" style="margin-top:12px;width:100%">← Back to what\'s included</button>'
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
  if (g('f_duration')) d.duration = g('f_duration').value;
  if (g('f_extraHour')) d.extraHour = +g('f_extraHour').value || 0;
  document.querySelectorAll('.svc-extra').forEach(function (row, i) {
    if (!d.optionalExtras[i]) d.optionalExtras[i] = {};
    d.optionalExtras[i].name = row.querySelector('[data-svc-extra-name]').value.trim();
    d.optionalExtras[i].price = +(row.querySelector('[data-svc-extra-price]').value || 0);
    d.optionalExtras[i].unit = row.querySelector('[data-svc-extra-unit]').value;
  });
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
      if (act === 'svc-cover-edit' || act === 'svc-cover-more') {
        d.coverCount = (d.coverCount || 1) + 1;
        toast('Cover image updated (demo).');
        return;
      }
      if (act === 'svc-add-extra') {
        d.optionalExtras.push({ name: 'Custom extra', price: 1000, unit: 'Per Event' });
        renderWizardBody();
        return;
      }
      if (act === 'svc-del-extra') {
        d.optionalExtras.splice(+t.getAttribute('data-idx'), 1);
        renderWizardBody();
        return;
      }
      if (act === 'svc-add-incl-photo') {
        const n = prompt('Included item');
        if (n) {
          d.customInclPhoto.push(n.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'svc-add-incl-video') {
        const n = prompt('Video item');
        if (n) {
          d.customInclVideo.push(n.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'svc-add-incl-digital') {
        const n = prompt('Digital delivery option');
        if (n) {
          if (!d.customInclDigital) d.customInclDigital = [];
          d.customInclDigital.push(n.trim());
          renderWizardBody();
        }
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
      if (field === 'albumQty') d.album.qty = v;
      else if (d.team[field] != null) d.team[field] = v;
      return;
    }
  };
  body.onchange = function (e) {
    const t = e.target;
    if (t.matches('[data-sincl-photo]')) {
      const v = t.getAttribute('data-sincl-photo');
      if (t.checked) {
        if (d.inclPhoto.indexOf(v) < 0) d.inclPhoto.push(v);
      } else {
        d.inclPhoto = d.inclPhoto.filter(function (x) {
          return x !== v;
        });
        if (d.deliveryMap) delete d.deliveryMap[v];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-sincl-video]')) {
      const v = t.getAttribute('data-sincl-video');
      if (t.checked) {
        if (d.inclVideo.indexOf(v) < 0) d.inclVideo.push(v);
      } else {
        d.inclVideo = d.inclVideo.filter(function (x) {
          return x !== v;
        });
        if (d.deliveryMap) delete d.deliveryMap[v];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-sincl-digital]')) {
      const v = t.getAttribute('data-sincl-digital');
      if (t.checked) {
        if (d.inclDigital.indexOf(v) < 0) d.inclDigital.push(v);
      } else {
        d.inclDigital = d.inclDigital.filter(function (x) {
          return x !== v;
        });
        if (d.deliveryMap) delete d.deliveryMap[v];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-sincl-album]')) {
      if (!d.inclAlbums) d.inclAlbums = [];
      const v = t.getAttribute('data-sincl-album');
      if (t.checked) {
        if (d.inclAlbums.indexOf(v) < 0) d.inclAlbums.push(v);
      } else {
        d.inclAlbums = d.inclAlbums.filter(function (x) {
          return x !== v;
        });
        if (d.deliveryMap) delete d.deliveryMap[v];
      }
      renderWizardBody();
      return;
    }
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
}
