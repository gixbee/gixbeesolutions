/* Photography package wizard — V1 spec (11 steps) matching package creation board */

const PKG_EXTRA_DEFAULTS = [
  'Drone',
  'Heli Cam',
  'Live Streaming',
  'Jib Crane',
  'LED Wall',
  'LED TV',
  'Live Photo Printing',
  'Photo Booth',
  'Extra Photographer',
  'Extra Videographer',
];
const PHOTO_DELIVER = ['Edited Photos', 'Colour-Graded Photos', 'RAW Photos', 'Printed Photos'];
const VIDEO_DELIVER = [
  'Full-Length Video',
  'Highlight Video',
  'Cinematic Video',
  'Teaser',
  'Reel',
  'Save-the-Date Video',
  'Traditional Video',
];
const DIGITAL_DELIVER = [
  'Pen Drive',
  'Pen Drive Box',
  'Album Box',
  'Album Bag',
  'Google Drive',
  'Online Gallery',
  'Digital Wedding Invitation',
];
const COMPLIMENTARY_DEFAULTS = ['Edited Photos', 'Save-the-Date', 'Post-Wedding', 'Frames', 'Calendars'];
const POLICY_DEFAULTS = [
  'Cancellation',
  'Rescheduling',
  'Photo Selection Deadline',
  'Album Selection Deadline',
  'Revision Limit',
  'Song Selection',
  'Data Retention',
  'Additional Work',
  'Reprint Charges',
  'Delivery Conditions',
  'Other Policy',
];
const REQ_DEFAULTS = [
  'Customer provides hard disk / SSD',
  'Electricity / power at venue',
  'Customer selects album photos within specified time',
  'Customer provides song preference',
  'Required permissions/materials',
];
const DELIVERY_TIMELINES = [
  'Same Day',
  '1 Day',
  '2 Days',
  '3 Days',
  '5 Days',
  '7 Days',
  '15 Days',
  '25 Days',
  '30 Days',
  '45 Days',
  '45 Days (after selection)',
  'Custom',
];
const DURATION_OPTS = ['Up to 3 Hours', 'Up to 5 Hours', 'Up to 8 Hours', 'Up to 10 Hours', 'Full Day', 'Custom'];

function pkgExtraDefaults() {
  const o = {};
  PKG_EXTRA_DEFAULTS.forEach(function (name) {
    const hourly = name.indexOf('Photographer') >= 0 || name.indexOf('Videographer') >= 0;
    o[name] = {
      mode: name === 'Live Streaming' ? 'included' : 'extra',
      price: name === 'Heli Cam' ? 25000 : name === 'Drone' ? 10000 : hourly ? 5000 : 8000,
      basis: hourly ? 'Per Hour' : 'Per Event',
    };
  });
  return o;
}

function newPkgDraft() {
  return {
    level: 'Standard',
    name: 'Premium Wedding Package',
    desc: '',
    listPrice: 150000,
    discountYes: 'yes',
    discountPct: 10,
    price: 135000,
    coverUploaded: false,
    customFunctions: [],
    functions: ['Wedding & Reception', 'Reception'],
    customCeremonies: [],
    ceremonyTypes: ['Christian'],
    coverageFn: 'Wedding & Reception',
    coverageSide: 'both',
    photoRoles: { candid: 2, traditional: 2 },
    videoRoles: { candid: 2, traditional: 2 },
    duration: 'Up to 5 Hours',
    extraHour: 5000,
    extras: pkgExtraDefaults(),
    customExtras: [],
    deliverPhoto: ['Edited Photos', 'Colour-Graded Photos'],
    deliverVideo: ['Full-Length Video', 'Highlight Video', 'Cinematic Video'],
    deliverDigital: ['Google Drive', 'Online Gallery'],
    customDeliverPhoto: [],
    customDeliverVideo: [],
    customDeliverDigital: [],
    album: {
      include: true,
      qty: 2,
      leaves: 40,
      size: '12x18 inch',
      orient: 'Landscape',
      finish: 'Matte',
      maxPhotos: 100,
      extraLeaf: 500,
    },
    complimentary: ['Edited Photos', 'Save-the-Date', 'Post-Wedding'],
    customComplimentary: [],
    deliveryMap: {
      'Edited Photos': '5 Days',
      Reels: '5 Days',
      'Highlight Video': '15 Days',
      'Full-Length Video': '15 Days',
      Album: '45 Days (after selection)',
    },
    paymentStages: [
      { id: 'ps1', label: 'Booking Advance', pct: 30 },
      { id: 'ps2', label: 'Event Day', pct: 40 },
      { id: 'ps3', label: 'Before Album Printing', pct: 20 },
      { id: 'ps4', label: 'Final Payment', pct: 10 },
    ],
    policies: ['Cancellation', 'Rescheduling'],
    customPolicies: [],
    requirements: ['Customer provides hard disk / SSD'],
    customRequirements: [],
  };
}

function allPkgFunctions(d) {
  return PKG_FUNCTIONS.concat(d.customFunctions || []);
}
function allCeremonyTypes(d) {
  return CEREMONY_TYPES.concat(d.customCeremonies || []);
}
function allExtrasNames(d) {
  return PKG_EXTRA_DEFAULTS.concat((d.customExtras || []).map(function (x) {
    return x.name;
  }));
}

function qtyStepper(field, val) {
  val = Math.max(0, +val || 0);
  return (
    '<div class="qty-step" data-qty-field="' +
    field +
    '"><button type="button" data-qty-d="-1">−</button><span>' +
    val +
    '</span><button type="button" data-qty-d="1">+</button></div>'
  );
}

function chkList(items, selected, dataAttr) {
  return items
    .map(function (item) {
      const on = selected.indexOf(item) >= 0;
      return (
        '<label class="chk-row' +
        (on ? ' on' : '') +
        '"><input type="checkbox" ' +
        dataAttr +
        '="' +
        esc(item) +
        '" ' +
        (on ? 'checked' : '') +
        '> ' +
        esc(item) +
        '</label>'
      );
    })
    .join('');
}

function linkAdd(action, label) {
  return (
    '<button type="button" class="link-add" data-action="' +
    action +
    '">+ ' +
    esc(label) +
    '</button>'
  );
}

function renderPkgStep(step, d) {
  syncPkgPrice(d);
  switch (step) {
    case 0:
      return (
        '<div class="step-num">1. Package basics</div>' +
        '<div class="fld"><label>Package level</label><div class="levels seg-full" id="f_levels">' +
        PKG_LEVELS.map(function (l) {
          return (
            '<button type="button" class="' +
            (d.level === l ? 'on' : '') +
            '" data-lvl="' +
            l +
            '">' +
            l +
            '</button>'
          );
        }).join('') +
        '</div></div>' +
        '<div class="fld"><label>Package name *</label><input id="f_name" value="' +
        esc(d.name) +
        '"></div>' +
        '<div class="price-panel">' +
        '<div class="fld"><label>Package price (₹) *</label><input type="number" id="f_listPrice" value="' +
        d.listPrice +
        '"></div>' +
        '<div class="fld"><label>Offer discount on this price?</label><div class="radio-row">' +
        '<label><input type="radio" name="discYes" value="no" ' +
        (d.discountYes !== 'yes' ? 'checked' : '') +
        '> No</label>' +
        '<label><input type="radio" name="discYes" value="yes" ' +
        (d.discountYes === 'yes' ? 'checked' : '') +
        '> Yes</label></div></div>' +
        '<div class="fld"><label>Discount %</label><input type="number" id="f_discountPct" value="' +
        d.discountPct +
        '" min="0" max="100"></div>' +
        '<div class="preview-green"><span class="sub" style="display:block;margin-bottom:4px">Customer will see:</span><b style="font-size:20px">' +
        inr(d.price) +
        '</b>' +
        (d.discountYes === 'yes' && d.discountPct > 0
          ? ' <span class="was">' +
            inr(d.listPrice) +
            '</span> <span class="off-pill">' +
            d.discountPct +
            '% OFF</span>'
          : '') +
        '</div></div>' +
        '<div class="fld"><label>Short description</label><textarea id="f_desc">' +
        esc(d.desc) +
        '</textarea></div>' +
        '<div class="fld"><label>Cover image (optional)</label><div class="cover-row">' +
        '<div class="cover-thumb' +
        (d.coverUploaded ? ' on' : '') +
        '">' +
        (d.coverUploaded ? '🖼' : '') +
        '</div><button type="button" class="btn btn-ghost" data-action="upload-cover" style="flex:1;padding:10px">Upload image</button></div></div>'
      );
    case 1:
      return (
        '<div class="step-num">2. Functions included</div><p class="sub">No booking date or venue on this step.</p><div id="f_funcs">' +
        chkList(allPkgFunctions(d), d.functions, 'data-fn') +
        '</div>' +
        linkAdd('add-function', 'Add New Function')
      );
    case 2:
      if (!needsCeremonyStep(d.functions)) {
        return (
          '<div class="step-num">3. Ceremony type</div><p class="sub">Not required for selected functions. Continue to coverage.</p>' +
          '<div class="warn-box">Ceremony type is shown only for Wedding &amp; Reception, Reception, or Engagement.</div>'
        );
      }
      return (
        '<div class="step-num">3. Ceremony type</div><p class="sub">Select tradition(s) for wedding-related functions.</p><div id="f_ceremony">' +
        chkList(allCeremonyTypes(d), d.ceremonyTypes, 'data-cer') +
        '</div>' +
        linkAdd('add-ceremony', 'Add New') +
        '<div class="warn-box">Describes ceremony style, not the photographer\'s religion.</div>'
      );
    case 3: {
      const fns = d.functions.length ? d.functions : ['Wedding & Reception'];
      if (d.functions.indexOf(d.coverageFn) < 0) d.coverageFn = fns[0];
      return (
        '<div class="step-num">4. Function coverage</div>' +
        '<div class="fld"><label>Select function</label><select id="f_covFn">' +
        fns
          .map(function (f) {
            return (
              '<option value="' +
              esc(f) +
              '"' +
              (d.coverageFn === f ? ' selected' : '') +
              '>' +
              esc(f) +
              '</option>'
            );
          })
          .join('') +
        '</select></div>' +
        '<div class="fld"><label>Coverage side</label><div class="seg seg-full" id="f_covSide">' +
        '<button type="button" class="' +
        (d.coverageSide === 'single' ? 'on' : '') +
        '" data-side="single">Single side</button>' +
        '<button type="button" class="' +
        (d.coverageSide === 'both' ? 'on' : '') +
        '" data-side="both">Both sides</button></div></div>' +
        '<p class="lbl">Photographers</p>' +
        '<div class="role-row"><span>Candid</span>' +
        qtyStepper('photo.candid', d.photoRoles.candid) +
        '</div>' +
        '<div class="role-row"><span>Traditional</span>' +
        qtyStepper('photo.traditional', d.photoRoles.traditional) +
        '</div>' +
        '<p class="lbl">Videographers</p>' +
        '<div class="role-row"><span>Candid</span>' +
        qtyStepper('video.candid', d.videoRoles.candid) +
        '</div>' +
        '<div class="role-row"><span>Traditional</span>' +
        qtyStepper('video.traditional', d.videoRoles.traditional) +
        '</div>' +
        '<div class="fld"><label>Coverage duration</label><select id="f_duration">' +
        DURATION_OPTS.map(function (o) {
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
        '"></div>'
      );
    }
    case 4:
      return (
        '<div class="step-num">5. Special services &amp; extras</div>' +
        '<div id="f_extraRows">' +
        allExtrasNames(d)
          .map(function (name) {
            const x = d.extras[name] || { mode: 'extra', price: 0, basis: 'Per Event' };
            return (
              '<div class="extra-row" data-extra-name="' +
              esc(name) +
              '"><span class="extra-ico">✦</span><b class="extra-name">' +
              esc(name) +
              '</b>' +
              '<select data-extra-mode><option value="included"' +
              (x.mode === 'included' ? ' selected' : '') +
              '>Included</option><option value="extra"' +
              (x.mode === 'extra' ? ' selected' : '') +
              '>Extra</option></select>' +
              '<input type="number" data-extra-price value="' +
              (x.price || 0) +
              '" placeholder="₹">' +
              '<select data-extra-basis><option' +
              (x.basis === 'Per Event' ? ' selected' : '') +
              '>Per Event</option><option' +
              (x.basis === 'Per Hour' ? ' selected' : '') +
              '>Per Hour</option></select></div>'
            );
          })
          .join('') +
        '</div>' +
        linkAdd('add-extra', 'Add New Service')
      );
    case 5:
      return (
        '<div class="step-num">6. Deliverables</div>' +
        '<p class="lbl">Photography</p>' +
        chkList(
          PHOTO_DELIVER.concat(d.customDeliverPhoto || []),
          d.deliverPhoto,
          'data-dphoto'
        ) +
        linkAdd('add-dphoto', 'Add New') +
        '<p class="lbl">Video</p>' +
        chkList(VIDEO_DELIVER.concat(d.customDeliverVideo || []), d.deliverVideo, 'data-dvideo') +
        linkAdd('add-dvideo', 'Add New') +
        '<p class="lbl">Albums &amp; prints</p>' +
        '<label class="chk-row' +
        (d.album.include ? ' on' : '') +
        '"><input type="checkbox" id="f_albumOn" ' +
        (d.album.include ? 'checked' : '') +
        '> Include album</label>' +
        (d.album.include
          ? '<div class="album-grid">' +
            '<div class="fld"><label>Quantity</label>' +
            qtyStepper('album.qty', d.album.qty) +
            '</div>' +
            '<div class="fld"><label>Pages / leaves</label><input type="number" id="f_albumLeaves" value="' +
            d.album.leaves +
            '"></div>' +
            '<div class="fld"><label>Size</label><select id="f_albumSize"><option>12x18 inch</option><option>10x12 inch</option></select></div>' +
            '<div class="fld"><label>Orientation</label><select id="f_albumOrient"><option>Landscape</option><option>Portrait</option></select></div>' +
            '<div class="fld"><label>Finish</label><select id="f_albumFinish"><option>Matte</option><option>Glossy</option></select></div>' +
            '<div class="fld"><label>Max photos</label><input type="number" id="f_albumMax" value="' +
            d.album.maxPhotos +
            '"></div>' +
            '<div class="fld"><label>Extra leaf charge (₹)</label><input type="number" id="f_albumExtraLeaf" value="' +
            d.album.extraLeaf +
            '"></div></div>'
          : '') +
        '<p class="lbl">Digital delivery</p>' +
        chkList(
          DIGITAL_DELIVER.concat(d.customDeliverDigital || []),
          d.deliverDigital,
          'data-ddigital'
        ) +
        linkAdd('add-ddigital', 'Add New')
      );
    case 6:
      return (
        '<div class="step-num">7. Complimentary items</div>' +
        chkList(
          COMPLIMENTARY_DEFAULTS.concat(d.customComplimentary || []),
          d.complimentary,
          'data-comp'
        ) +
        linkAdd('add-comp', 'Add New Complimentary Item')
      );
    case 7: {
      const keys = pkgDeliveryKeys(d);
      keys.forEach(function (k) {
        if (!d.deliveryMap[k]) d.deliveryMap[k] = '5 Days';
      });
      return (
        '<div class="step-num">8. Delivery</div><p class="sub">Set timeline per deliverable.</p>' +
        keys
          .map(function (k) {
            return (
              '<div class="fld del-row"><label>' +
              esc(k) +
              '</label><select data-del-key="' +
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
        '<div class="warn-box">Timelines can differ per item (e.g. album after photo selection).</div>'
      );
    }
    case 8:
      return (
        '<div class="step-num">9. Payment &amp; policies</div>' +
        '<p class="sub">Customer pays you directly in V1.</p>' +
        '<div id="f_payStages">' +
        d.paymentStages
          .map(function (s, i) {
            return (
              '<div class="pay-row" data-pay-idx="' +
              i +
              '"><input type="text" data-pay-label value="' +
              esc(s.label) +
              '"><input type="number" data-pay-pct value="' +
              s.pct +
              '" min="0" max="100"><span>%</span>' +
              (d.paymentStages.length > 1
                ? '<button type="button" class="pay-del" data-action="del-stage" data-idx="' +
                  i +
                  '">🗑</button>'
                : '') +
              '</div>'
            );
          })
          .join('') +
        '</div>' +
        linkAdd('add-stage', 'Add Custom Stage') +
        '<p class="lbl">Policies (optional)</p>' +
        chkList(POLICY_DEFAULTS.concat(d.customPolicies || []), d.policies, 'data-pol') +
        linkAdd('add-policy', 'Add New Policy')
      );
    case 9:
      return (
        '<div class="step-num">10. Customer requirements</div>' +
        chkList(REQ_DEFAULTS.concat(d.customRequirements || []), d.requirements, 'data-req') +
        linkAdd('add-req', 'Add Requirement')
      );
    case 10:
      return (
        '<div class="step-num">11. Review &amp; publish</div>' +
        PKG_STEPS.slice(0, 10)
          .map(function (s, i) {
            return (
              '<button type="button" class="review-jump" data-goto-step="' +
              i +
              '"><span>' +
              (i + 1) +
              '. ' +
              esc(s.title) +
              '</span><span>›</span></button>'
            );
          })
          .join('') +
        '<div class="review-summary">' +
        '<b>' +
        esc(d.name) +
        '</b> · ' +
        esc(d.level) +
        ' · ' +
        inr(d.price) +
        '</div>' +
        '<div class="cta two-col">' +
        '<button type="button" class="btn btn-ghost" data-action="publish-draft">Save as draft</button>' +
        '<button type="button" class="btn btn-blue" data-action="publish-now">Publish package</button></div>'
      );
    default:
      return '';
  }
}

function pkgDeliveryKeys(d) {
  const keys = [];
  (d.deliverPhoto || []).forEach(function (x) {
    keys.push(x);
  });
  (d.deliverVideo || []).forEach(function (x) {
    keys.push(x);
  });
  if (d.album && d.album.include) keys.push('Album');
  (d.deliverDigital || []).forEach(function (x) {
    keys.push(x);
  });
  if (!keys.length) keys.push('Edited Photos');
  return keys;
}

function readPkgWizardFields(d) {
  const g = function (id) {
    return el(id);
  };
  if (g('f_name')) d.name = g('f_name').value.trim();
  if (g('f_desc')) d.desc = g('f_desc').value.trim();
  if (g('f_listPrice')) d.listPrice = +g('f_listPrice').value || 0;
  if (g('f_discountPct')) d.discountPct = +g('f_discountPct').value || 0;
  const discRad = document.querySelector('input[name="discYes"]:checked');
  if (discRad) d.discountYes = discRad.value;
  if (g('f_covFn')) d.coverageFn = g('f_covFn').value;
  if (g('f_duration')) d.duration = g('f_duration').value;
  if (g('f_extraHour')) d.extraHour = +g('f_extraHour').value || 0;
  if (g('f_albumOn')) d.album.include = g('f_albumOn').checked;
  if (g('f_albumLeaves')) d.album.leaves = +g('f_albumLeaves').value || 0;
  if (g('f_albumMax')) d.album.maxPhotos = +g('f_albumMax').value || 0;
  if (g('f_albumExtraLeaf')) d.album.extraLeaf = +g('f_albumExtraLeaf').value || 0;
  document.querySelectorAll('.extra-row').forEach(function (row) {
    const name = row.getAttribute('data-extra-name');
    if (!name) return;
    d.extras[name] = {
      mode: row.querySelector('[data-extra-mode]').value,
      price: +(row.querySelector('[data-extra-price]').value || 0),
      basis: row.querySelector('[data-extra-basis]').value,
    };
  });
  document.querySelectorAll('[data-del-key]').forEach(function (sel) {
    d.deliveryMap[sel.getAttribute('data-del-key')] = sel.value;
  });
  d.paymentStages = [];
  document.querySelectorAll('.pay-row').forEach(function (row) {
    d.paymentStages.push({
      id: uid('ps'),
      label: row.querySelector('[data-pay-label]').value.trim() || 'Stage',
      pct: +(row.querySelector('[data-pay-pct]').value || 0),
    });
  });
  syncPkgPrice(d);
  d.coverage = pkgCoverageSummary(d);
  d.deliverables = pkgDeliverSummary(d);
}

function pkgCoverageSummary(d) {
  return (
    d.coverageFn +
    ' · ' +
    (d.coverageSide === 'both' ? 'Both sides' : 'Single side') +
    ' · Photo C' +
    d.photoRoles.candid +
    '/T' +
    d.photoRoles.traditional +
    ' · Video C' +
    d.videoRoles.candid +
    '/T' +
    d.videoRoles.traditional +
    ' · ' +
    d.duration +
    ' · Extra hr ' +
    inr(d.extraHour)
  );
}
function pkgDeliverSummary(d) {
  return (
    (d.deliverPhoto || []).join(', ') +
    ' | Video: ' +
    (d.deliverVideo || []).join(', ') +
    (d.album.include ? ' | Album ×' + d.album.qty : '')
  );
}

function bindPkgWizard(d) {
  const body = el('wizBody');
  if (!body) return;
  body.onclick = function (e) {
    const t = e.target.closest('[data-action],[data-goto-step],[data-qty-d],[data-side],[data-lvl]');
    if (t) {
      if (t.getAttribute('data-goto-step') != null) {
        readPkgWizardFields(d);
        wiz.step = +t.getAttribute('data-goto-step');
        renderWizard();
        return;
      }
      const act = t.getAttribute('data-action');
      if (act === 'upload-cover') {
        d.coverUploaded = true;
        toast('Cover image added (demo).');
        renderWizardBody();
        return;
      }
      if (act === 'add-function') {
        const name = prompt('New function name');
        if (name && d.customFunctions.indexOf(name) < 0) {
          d.customFunctions.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-ceremony') {
        const name = prompt('Ceremony type');
        if (name && d.customCeremonies.indexOf(name) < 0) {
          d.customCeremonies.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-extra') {
        const name = prompt('Service name');
        if (name) {
          d.customExtras.push({ name: name.trim() });
          d.extras[name.trim()] = { mode: 'extra', price: 5000, basis: 'Per Event' };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-dphoto') {
        const name = prompt('Deliverable');
        if (name) {
          d.customDeliverPhoto.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-dvideo') {
        const name = prompt('Video deliverable');
        if (name) {
          d.customDeliverVideo.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-ddigital') {
        const name = prompt('Digital deliverable');
        if (name) {
          d.customDeliverDigital.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-comp') {
        const name = prompt('Complimentary item');
        if (name) {
          d.customComplimentary.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-stage') {
        d.paymentStages.push({ id: uid('ps'), label: 'Custom Stage', pct: 0 });
        renderWizardBody();
        return;
      }
      if (act === 'add-policy') {
        const name = prompt('Policy name');
        if (name) {
          d.customPolicies.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-req') {
        const name = prompt('Requirement');
        if (name) {
          d.customRequirements.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'del-stage') {
        const i = +t.getAttribute('data-idx');
        d.paymentStages.splice(i, 1);
        renderWizardBody();
        return;
      }
      if (act === 'publish-draft') {
        readPkgWizardFields(d);
        finishWizard(false);
        return;
      }
      if (act === 'publish-now') {
        readPkgWizardFields(d);
        finishWizard(true);
        return;
      }
    }
    const side = e.target.closest('[data-side]');
    if (side) {
      d.coverageSide = side.getAttribute('data-side');
      renderWizardBody();
      return;
    }
    const lvl = e.target.closest('#f_levels button');
    if (lvl) {
      d.level = lvl.getAttribute('data-lvl');
      renderWizardBody();
      return;
    }
    const qtyBtn = e.target.closest('[data-qty-d]');
    if (qtyBtn) {
      const wrap = qtyBtn.closest('.qty-step');
      const field = wrap.getAttribute('data-qty-field');
      const delta = +qtyBtn.getAttribute('data-qty-d');
      const span = wrap.querySelector('span');
      let v = +span.textContent + delta;
      v = Math.max(0, Math.min(20, v));
      span.textContent = v;
      if (field.indexOf('photo.') === 0) d.photoRoles[field.split('.')[1]] = v;
      else if (field.indexOf('video.') === 0) d.videoRoles[field.split('.')[1]] = v;
      else if (field === 'album.qty') d.album.qty = v;
      return;
    }
  };
  body.onchange = function (e) {
    const t = e.target;
    if (t.matches('[data-fn]')) {
      const fn = t.getAttribute('data-fn');
      if (t.checked) {
        if (d.functions.indexOf(fn) < 0) d.functions.push(fn);
      } else d.functions = d.functions.filter(function (x) {
        return x !== fn;
      });
      return;
    }
    if (t.matches('[data-cer]')) {
      const c = t.getAttribute('data-cer');
      if (t.checked) {
        if (d.ceremonyTypes.indexOf(c) < 0) d.ceremonyTypes.push(c);
      } else
        d.ceremonyTypes = d.ceremonyTypes.filter(function (x) {
          return x !== c;
        });
      return;
    }
    ['data-dphoto', 'data-dvideo', 'data-ddigital', 'data-comp', 'data-pol', 'data-req'].forEach(function (
      attr
    ) {
      if (!t.matches('[' + attr + ']')) return;
      const val = t.getAttribute(attr);
      const arr =
        attr === 'data-dphoto'
          ? 'deliverPhoto'
          : attr === 'data-dvideo'
            ? 'deliverVideo'
            : attr === 'data-ddigital'
              ? 'deliverDigital'
              : attr === 'data-comp'
                ? 'complimentary'
                : attr === 'data-pol'
                  ? 'policies'
                  : 'requirements';
      if (t.checked) {
        if (d[arr].indexOf(val) < 0) d[arr].push(val);
      } else d[arr] = d[arr].filter(function (x) {
        return x !== val;
      });
    });
    if (t.id === 'f_albumOn') {
      d.album.include = t.checked;
      renderWizardBody();
    }
    if (t.id === 'f_discYes' || t.id === 'f_listPrice' || t.id === 'f_discountPct') {
      readPkgWizardFields(d);
      renderWizardBody();
    }
  };
  document.querySelectorAll('input[name="discYes"]').forEach(function (r) {
    r.onchange = function () {
      readPkgWizardFields(d);
      renderWizardBody();
    };
  });
  ['f_listPrice', 'f_discountPct'].forEach(function (id) {
    const node = el(id);
    if (node)
      node.oninput = function () {
        readPkgWizardFields(d);
        renderWizardBody();
      };
  });
}
