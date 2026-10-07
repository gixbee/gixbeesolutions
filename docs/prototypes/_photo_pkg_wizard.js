/* Photography package wizard — mobile Create Package flow (10 steps) */

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
  'Teaser Video',
  'Reel',
  'Traditional Video',
];
const ALBUM_PRINT_TYPES = ['Photo Album', 'Calendar', 'Mini Album', 'Photo Frame'];
const DIGITAL_DELIVER = [
  { id: 'Google Drive Link', icon: '📁', desc: 'Share high-resolution files via Google Drive.' },
  { id: 'Online Gallery', icon: '🔗', desc: 'Private online gallery for easy access.' },
  { id: 'Pen Drive', icon: '💾', desc: 'Physical pen drive with all files.' },
  { id: 'Pen Drive Box', icon: '📦', desc: 'Premium pen drive box with branding.' },
  { id: 'Email Delivery', icon: '✉️', desc: 'Files delivered via email.' },
];
const PHOTO_TYPE_DEFAULTS = [
  'Candid Photographer',
  'Traditional Photographer',
  'Candid + Traditional Photographer',
];
const VIDEO_TYPE_DEFAULTS = ['Candid Videographer', 'Traditional Videographer', 'Cinematic Videographer'];
const PHOTO_FORMATS = ['JPG (High Resolution)', 'JPG + RAW', 'PNG'];
const VIDEO_DURATIONS = ['Full Event', '3-5 Minutes', '5-10 Minutes', '1-2 Minutes', 'Custom'];
const VIDEO_FORMATS = ['MP4 (Full HD)', 'MP4 (4K)', 'MOV (4K)'];
const POLICY_DEFAULTS = [
  'Cancellation Policy',
  'Rescheduling Policy',
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
const POLICY_META = {
  'Cancellation Policy': {
    help: 'Set refund rules when the customer cancels the booking.',
    fields: [
      { key: 'noticeDays', label: 'If cancelled at least (days before event)', type: 'number', placeholder: '30' },
      { key: 'refundPct', label: 'Refund % of amount paid', type: 'number', placeholder: '50' },
      { key: 'notes', label: 'Customer-facing policy text', type: 'textarea', placeholder: 'Advance is non-refundable if cancelled within 7 days of the event.' },
    ],
  },
  'Rescheduling Policy': {
    help: 'Notice period and fees for rescheduling.',
    fields: [
      { key: 'noticeDays', label: 'Free reschedule when notice is (days)', type: 'number', placeholder: '14' },
      { key: 'fee', label: 'Reschedule fee (₹)', type: 'number', placeholder: '0' },
      { key: 'notes', label: 'Customer-facing policy text', type: 'textarea', placeholder: 'One free reschedule with sufficient notice.' },
    ],
  },
  'Photo Selection Deadline': {
    help: 'How long the customer has to select photos.',
    fields: [
      { key: 'days', label: 'Deadline (days after delivery)', type: 'number', placeholder: '45' },
      { key: 'notes', label: 'Details for customer', type: 'textarea', placeholder: '' },
    ],
  },
  'Album Selection Deadline': {
    help: 'Album design / photo selection timeline.',
    fields: [
      { key: 'days', label: 'Deadline (days)', type: 'number', placeholder: '60' },
      { key: 'notes', label: 'Details for customer', type: 'textarea', placeholder: '' },
    ],
  },
  'Revision Limit': {
    help: 'Number of included revision rounds.',
    fields: [
      { key: 'limit', label: 'Included revisions', type: 'number', placeholder: '2' },
      { key: 'notes', label: 'Extra revision charges (optional)', type: 'textarea', placeholder: '' },
    ],
  },
  'Song Selection': {
    fields: [{ key: 'days', label: 'Submit songs before (days)', type: 'number', placeholder: '7' }, { key: 'notes', type: 'textarea', label: 'Notes' }],
  },
  'Data Retention': {
    fields: [{ key: 'days', label: 'Files stored for (days)', type: 'number', placeholder: '365' }, { key: 'notes', type: 'textarea', label: 'Notes' }],
  },
  'Additional Work': {
    fields: [{ key: 'notes', label: 'Policy text', type: 'textarea', placeholder: 'Out-of-scope work billed separately.' }],
  },
  'Reprint Charges': {
    fields: [{ key: 'fee', label: 'Reprint fee from (₹)', type: 'number', placeholder: '500' }, { key: 'notes', type: 'textarea', label: 'Notes' }],
  },
  'Delivery Conditions': {
    fields: [{ key: 'notes', label: 'Delivery conditions', type: 'textarea', placeholder: '' }],
  },
  'Other Policy': {
    fields: [{ key: 'notes', label: 'Policy text', type: 'textarea', placeholder: '' }],
  },
};

function defaultPolicyValue(name) {
  const seed = {
    'Cancellation Policy': { noticeDays: 30, refundPct: 50, notes: 'Advance is non-refundable if cancelled within 7 days of the event.' },
    'Rescheduling Policy': { noticeDays: 14, fee: 0, notes: 'One free reschedule with at least 14 days notice.' },
    'Photo Selection Deadline': { days: 45, notes: 'Selections after the deadline may incur extra charges.' },
    'Album Selection Deadline': { days: 60, notes: '' },
    'Revision Limit': { limit: 2, notes: 'Additional revisions charged per package rate.' },
    'Data Retention': { days: 365, notes: 'Raw files may be deleted after retention period.' },
  };
  return Object.assign({ noticeDays: '', refundPct: '', fee: '', days: '', limit: '', notes: '' }, seed[name] || {});
}

function ensurePolicyValues(d) {
  if (!d.policyValues) d.policyValues = {};
  (d.policies || []).forEach(function (name) {
    if (!d.policyValues[name]) d.policyValues[name] = defaultPolicyValue(name);
  });
}

function payStagesTotalPct(d) {
  return (d.paymentStages || []).reduce(function (sum, s) {
    return sum + (+s.pct || 0);
  }, 0);
}

const DEFAULT_PAYMENT_STAGES = [
  { label: 'Booking Advance', pct: 30 },
  { label: 'Event Day', pct: 40 },
  { label: 'Before Album Printing', pct: 20 },
  { label: 'Final Payment', pct: 10 },
];

function cloneDefaultPaymentStages() {
  return DEFAULT_PAYMENT_STAGES.map(function (s) {
    return { id: uid('ps'), label: s.label, pct: s.pct };
  });
}

function ensureDefaultPaymentStages(d) {
  if (!d.paymentStages || !d.paymentStages.length) {
    d.paymentStages = cloneDefaultPaymentStages();
  }
}

const PKG_POLICY_TIER_DEFAULTS = [
  { days: '30 days or more', pct: 10 },
  { days: '15 – 29 days', pct: 25 },
  { days: '7 – 14 days', pct: 50 },
  { days: '3 – 6 days', pct: 75 },
  { days: 'Less than 1 day', pct: 100 },
];

let pkgWizPolicyTab = 'cancel';

function clonePkgPolicyTierDefaults() {
  return PKG_POLICY_TIER_DEFAULTS.map(function (r) {
    return { days: r.days, pct: r.pct };
  });
}

function ensurePkgPolicyRules(d) {
  if (!d.cancelRules || !d.cancelRules.length) {
    d.cancelRules = clonePkgPolicyTierDefaults();
  }
  if (!d.rescheduleRules || !d.rescheduleRules.length) {
    d.rescheduleRules = d.cancelRules.map(function (r) {
      return { days: r.days, pct: r.pct };
    });
  }
  if (d.cancelPolicyNote == null) {
    const old = d.policyValues && d.policyValues['Cancellation Policy'];
    d.cancelPolicyNote = (old && old.notes) || '';
  }
  if (d.reschedulePolicyNote == null) {
    const old = d.policyValues && d.policyValues['Rescheduling Policy'];
    d.reschedulePolicyNote = (old && old.notes) || '';
  }
  if (!d.policies) d.policies = [];
  if (d.policies.indexOf('Cancellation Policy') < 0) d.policies.push('Cancellation Policy');
  if (d.policies.indexOf('Rescheduling Policy') < 0) d.policies.push('Rescheduling Policy');
}

function pkgPolicyRulesRowsHtml(rules, kind) {
  const rows = (rules || [])
    .map(function (r) {
      return (
        '<div class="policy-row">' +
        '<input type="text" class="policy-days-inp" data-field="days" value="' +
        esc(r.days) +
        '" aria-label="Days before event">' +
        '<span class="policy-pct-wrap"><span class="policy-tier-lbl">Deduct</span><input type="number" class="policy-pct-inp" inputmode="numeric" min="0" max="100" data-field="pct" value="' +
        r.pct +
        '" aria-label="Deduction percent"><span class="policy-pct-unit">%</span></span>' +
        '<button type="button" class="policy-row-remove" data-action="pkg-policy-del-tier" title="Remove tier" aria-label="Remove tier">✕</button></div>'
      );
    })
    .join('');
  return (
    '<div class="policy-rows" id="pkgPolicyTierRows" data-policy-kind="' +
    kind +
    '">' +
    rows +
    '</div>' +
    '<button type="button" class="policy-add-tier" data-action="pkg-policy-add-tier" data-policy="' +
    kind +
    '">+ Add tier</button>'
  );
}

function readPkgPolicyTiersFromDom(d) {
  const box = el('pkgPolicyTierRows');
  if (box) {
    const kind = box.getAttribute('data-policy-kind');
    const rules = [];
    box.querySelectorAll('.policy-row').forEach(function (row) {
      const daysIn = row.querySelector('[data-field=days]');
      const pctIn = row.querySelector('[data-field=pct]');
      if (!daysIn || !pctIn) return;
      rules.push({
        days: daysIn.value.trim() || 'Days before event',
        pct: +pctIn.value || 0,
      });
    });
    if (kind === 'cancel') {
      d.cancelRules = rules.length ? rules : [{ days: 'Days before event', pct: 0 }];
    } else if (kind === 'reschedule') {
      d.rescheduleRules = rules.length ? rules : [{ days: 'Days before event', pct: 0 }];
    }
  }
  const cn = el('cancelPolicyNote');
  const rn = el('reschedulePolicyNote');
  if (cn) d.cancelPolicyNote = cn.value.trim();
  if (rn) d.reschedulePolicyNote = rn.value.trim();
  ensurePolicyValues(d);
  if (d.policyValues['Cancellation Policy']) {
    d.policyValues['Cancellation Policy'].notes = d.cancelPolicyNote || '';
  }
  if (d.policyValues['Rescheduling Policy']) {
    d.policyValues['Rescheduling Policy'].notes = d.reschedulePolicyNote || '';
  }
}

function renderPkgCancelReschedBlock(d) {
  ensurePkgPolicyRules(d);
  const cancelOn = pkgWizPolicyTab !== 'reschedule';
  return (
    '<section class="policy-section" aria-label="Cancellation and rescheduling">' +
    '<h2 class="policy-section-hd">Cancellation &amp; rescheduling</h2>' +
    '<p class="policy-section-lead">Set how much of the <b>advance</b> you keep when the customer cancels or moves the date. Use the tabs for each case. Tap <b>+ Add tier</b> for more ranges, or ✕ to remove one.</p>' +
    '<div class="policy-tabs" role="tablist">' +
    '<button type="button" role="tab" aria-selected="' +
    (cancelOn ? 'true' : 'false') +
    '" class="' +
    (cancelOn ? 'on' : '') +
    '" data-action="pkg-policy-tab" data-tab="cancel">Cancellation</button>' +
    '<button type="button" role="tab" aria-selected="' +
    (!cancelOn ? 'true' : 'false') +
    '" class="' +
    (!cancelOn ? 'on' : '') +
    '" data-action="pkg-policy-tab" data-tab="reschedule">Rescheduling</button></div>' +
    (cancelOn
      ? '<div class="policy-banner cancel" role="note"><span aria-hidden="true">ℹ️</span><span>Deduction % for <b>cancellations</b> — taken from the advance already paid.</span></div>' +
        pkgPolicyRulesRowsHtml(d.cancelRules, 'cancel') +
        '<div class="fld policy-notes" style="margin-top:14px"><label>Notes for customers (optional)</label>' +
        '<textarea id="cancelPolicyNote" rows="3" placeholder="e.g. Remaining balance refunded within 7 working days after deduction.">' +
        esc(d.cancelPolicyNote || '') +
        '</textarea></div>'
      : '<div class="policy-banner resched" role="note"><span aria-hidden="true">ℹ️</span><span>Deduction % for <b>rescheduling</b> — taken from the advance already paid.</span></div>' +
        pkgPolicyRulesRowsHtml(d.rescheduleRules, 'reschedule') +
        '<div class="fld policy-notes" style="margin-top:14px"><label>Notes for customers (optional)</label>' +
        '<textarea id="reschedulePolicyNote" rows="3" placeholder="e.g. New date within 6 months; one free reschedule with 30+ days notice.">' +
        esc(d.reschedulePolicyNote || '') +
        '</textarea></div>') +
    '</section>'
  );
}

function renderPolicyCard(name, d) {
  ensurePolicyValues(d);
  const on = d.policies.indexOf(name) >= 0;
  const meta = POLICY_META[name] || { fields: [{ key: 'notes', label: 'Policy text', type: 'textarea' }] };
  const vals = d.policyValues[name] || defaultPolicyValue(name);
  if (on && !d.policyValues[name]) d.policyValues[name] = vals;
  let fieldsHtml = '';
  if (on) {
    fieldsHtml =
      (meta.help ? '<p class="policy-help">' + esc(meta.help) + '</p>' : '') +
      meta.fields
        .map(function (f) {
          const v = vals[f.key] != null ? vals[f.key] : '';
          if (f.type === 'textarea') {
            return (
              '<div class="fld"><label>' +
              esc(f.label) +
              '</label><textarea data-pol-val data-pol-key="' +
              esc(name) +
              '" data-pol-field="' +
              f.key +
              '" placeholder="' +
              esc(f.placeholder || '') +
              '">' +
              esc(String(v)) +
              '</textarea></div>'
            );
          }
          return (
            '<div class="fld"><label>' +
            esc(f.label) +
            '</label><input type="number" data-pol-val data-pol-key="' +
            esc(name) +
            '" data-pol-field="' +
            f.key +
            '" value="' +
            esc(String(v)) +
            '" placeholder="' +
            esc(f.placeholder || '') +
            '"></div>'
          );
        })
        .join('');
  }
  return (
    '<div class="policy-card' +
    (on ? ' on' : '') +
    '"><label class="policy-card-hd"><input type="checkbox" data-pol="' +
    esc(name) +
    '" ' +
    (on ? 'checked' : '') +
    '> <b>' +
    esc(name) +
    '</b></label>' +
    (on ? '<div class="policy-fields">' + fieldsHtml + '</div>' : '') +
    '</div>'
  );
}

function renderPayPoliciesStep(d) {
  ensureDefaultPaymentStages(d);
  syncPkgPrice(d);
  const totalPct = payStagesTotalPct(d);
  const totalOk = totalPct === 100;
  const base = Math.max(0, +d.price || +d.listPrice || 0);
  return (
    '<p class="sub">Split payments across milestones. Total must equal <b>100%</b>. Default stages load for new packages — edit names and % as needed.</p>' +
    '<div class="pay-stage-section"><p class="lbl">Payment Stages</p>' +
    '<div id="f_payStages" class="pay-stage-list">' +
    d.paymentStages
      .map(function (s, i) {
        const amt = Math.round(base * ((+s.pct || 0) / 100));
        return (
          '<div class="pay-stage-wrap pay-stage-card" data-pay-idx="' +
          i +
          '"><div class="pay-stage-row">' +
          '<input type="text" class="pay-stage-label" data-pay-label value="' +
          esc(s.label) +
          '" placeholder="Stage name" aria-label="Payment stage name">' +
          '<span class="pay-stage-pct-wrap"><input type="number" class="pay-stage-pct" data-pay-pct value="' +
          s.pct +
          '" inputmode="numeric" min="0" max="100" aria-label="Percent of package price"><span class="pay-pct-suffix" aria-hidden="true">%</span></span>' +
          (d.paymentStages.length > 1
            ? '<button type="button" class="pay-del" data-action="del-stage" data-idx="' +
              i +
              '" title="Remove stage" aria-label="Remove stage">🗑</button>'
            : '<span class="pay-stage-del-spacer" aria-hidden="true"></span>') +
          '</div><p class="pay-stage-sub">Customer pays <b>' +
          inr(amt) +
          '</b></p></div>'
        );
      })
      .join('') +
    '</div>' +
    '<div class="pay-total-bar' +
    (totalOk ? ' ok' : ' warn') +
    '"><span>Total</span><b>' +
    totalPct +
    '%</b>' +
    (totalOk ? '' : ' <span class="sub">— adjust stages to reach 100%</span>') +
    '</div>' +
    '<button type="button" class="btn-add-stage" data-action="add-stage">+ Add Custom Stage</button></div>' +
    renderPkgCancelReschedBlock(d) +
    '<p class="lbl" style="margin-top:20px">Other policies (optional)</p>' +
    '<p class="sub" style="margin:0 0 10px">Select additional policies customers will see on your package.</p>' +
    POLICY_DEFAULTS.concat(d.customPolicies || [])
      .filter(function (item) {
        return item !== 'Cancellation Policy' && item !== 'Rescheduling Policy';
      })
      .map(function (item) {
        return renderPolicyCard(item, d);
      })
      .join('') +
    linkAdd('add-policy', 'Add new policy')
  );
}
const REQ_DEFAULTS = [
  'Customer provides SSD / Hard Disk',
  'Electricity / Power at venue',
  'Customer selects album photos within specified time',
  'Customer provides song preference',
  'Required permissions / materials',
];
const DELIVERY_TIMELINES = [
  'Same Day',
  '1 Day',
  '2 Days',
  '3 Days',
  '5 Days',
  '5 Working Days',
  '7 Days',
  '7 Working Days',
  '15 Days',
  '15 Working Days',
  '25 Days',
  '30 Days',
  '45 Days',
  '45 Days (after selection)',
  'Custom',
];
const DURATION_OPTS = ['Up to 3 Hours', 'Up to 5 Hours', 'Up to 8 Hours', 'Up to 10 Hours', 'Full Day', 'Custom'];
const PHOTO_DELIVER_HINTS = {
  'Edited Photos': 'Professionally edited high-resolution photos.',
  'Colour-Graded Photos': 'Colour corrected and graded photos.',
  'RAW Photos': 'Unedited RAW files from the shoot.',
  'Printed Photos': 'Physical printed photo sets.',
};
const VIDEO_DELIVER_HINTS = {
  'Full-Length Video': 'Complete event video with all moments.',
  'Highlight Video': 'Short cinematic highlight video.',
  'Cinematic Video': 'Cinematic style video with creative edits.',
  'Teaser Video': 'Short teaser for social media.',
  Reel: 'Short vertical reel for social media.',
  'Traditional Video': 'Traditional full-length coverage style.',
};

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

function defaultPhotoDetails() {
  const o = {};
  PHOTO_DELIVER.forEach(function (name) {
    o[name] = {
      qty: name === 'Edited Photos' ? 500 : name === 'Colour-Graded Photos' ? 300 : 0,
      format: 'JPG (High Resolution)',
      delivery: name === 'RAW Photos' ? '7 Working Days' : '5 Working Days',
    };
  });
  return o;
}

function defaultVideoDetails() {
  const o = {};
  VIDEO_DELIVER.forEach(function (name) {
    o[name] = {
      duration:
        name === 'Full-Length Video'
          ? 'Full Event'
          : name === 'Highlight Video'
            ? '3-5 Minutes'
            : name === 'Cinematic Video'
              ? '5-10 Minutes'
              : '1-2 Minutes',
      format: 'MP4 (Full HD)',
      delivery: '15 Working Days',
    };
  });
  return o;
}

function defaultAlbumPrints() {
  return {
    'Photo Album': { on: true, pages: 40, size: '12 x 18 inch', cover: 'Premium' },
    Calendar: { on: true, qty: 1, size: 'A3', type: 'Wall Calendar' },
    'Mini Album': { on: true, qty: 1, size: '6 x 6 inch', cover: 'Standard' },
    'Photo Frame': { on: false, qty: 1, size: '12 x 18 inch', type: 'Acrylic' },
  };
}

function defaultCoverageTypes(defaults, seed) {
  const o = {};
  defaults.forEach(function (label, i) {
    const s = seed[label] || { on: i < 2, qty: i < 2 ? 1 : 0 };
    o[label] = { on: !!s.on, qty: +s.qty || 0 };
  });
  return o;
}

function newPkgDraft() {
  return {
    level: 'Premium',
    name: 'Premium Wedding Package',
    desc: 'Complete wedding & reception photography and videography with premium deliverables.',
    listPrice: 150000,
    discountYes: 'yes',
    discountPct: 10,
    price: 135000,
    coverUploaded: false,
    customFunctions: [],
    functions: ['Wedding & Reception', 'Reception', 'Wedding Eve'],
    customCeremonies: [],
    ceremonyTypes: ['Hindu'],
    coverageFn: 'Wedding & Reception',
    coverageSide: 'both',
    photoTypes: defaultCoverageTypes(PHOTO_TYPE_DEFAULTS, {
      'Candid Photographer': { on: true, qty: 1 },
      'Traditional Photographer': { on: true, qty: 1 },
      'Candid + Traditional Photographer': { on: false, qty: 0 },
    }),
    customPhotoTypes: [],
    videoTypes: defaultCoverageTypes(VIDEO_TYPE_DEFAULTS, {
      'Candid Videographer': { on: true, qty: 1 },
      'Traditional Videographer': { on: true, qty: 1 },
      'Cinematic Videographer': { on: true, qty: 1 },
    }),
    customVideoTypes: [],
    duration: 'Up to 5 Hours',
    extraHour: 5000,
    deliverTab: 'photos',
    extras: pkgExtraDefaults(),
    customExtras: [],
    excludedExtras: [],
    deliverPhoto: ['Edited Photos', 'Colour-Graded Photos'],
    deliverVideo: ['Full-Length Video', 'Highlight Video', 'Cinematic Video'],
    deliverDigital: ['Google Drive Link', 'Online Gallery'],
    customDeliverPhoto: [],
    customDeliverVideo: [],
    customDeliverDigital: [],
    photoDetails: defaultPhotoDetails(),
    videoDetails: defaultVideoDetails(),
    albumPrints: defaultAlbumPrints(),
    deliveryMap: {},
    paymentStages: cloneDefaultPaymentStages(),
    policies: ['Cancellation Policy', 'Rescheduling Policy'],
    cancelRules: clonePkgPolicyTierDefaults(),
    rescheduleRules: clonePkgPolicyTierDefaults(),
    cancelPolicyNote: '',
    reschedulePolicyNote: '',
    policyValues: {
      'Cancellation Policy': defaultPolicyValue('Cancellation Policy'),
      'Rescheduling Policy': defaultPolicyValue('Rescheduling Policy'),
    },
    customPolicies: [],
    requirements: ['Customer provides SSD / Hard Disk', 'Electricity / Power at venue'],
    customRequirements: [],
  };
}

function allPkgFunctions(d) {
  return PKG_FUNCTIONS.concat(d.customFunctions || []);
}
function allCeremonyTypes(d) {
  return CEREMONY_TYPES.concat(d.customCeremonies || []);
}
function applyExtraRowMode(row, mode) {
  if (!row) return;
  row.classList.remove('mode-included', 'mode-extra');
  row.classList.add(mode === 'included' ? 'mode-included' : 'mode-extra');
}

function syncAllExtraRowModes() {
  document.querySelectorAll('.extra-row').forEach(function (row) {
    const sel = row.querySelector('[data-extra-mode]');
    if (sel) applyExtraRowMode(row, sel.value);
  });
}

function allExtrasNames(d) {
  const excluded = d.excludedExtras || [];
  return PKG_EXTRA_DEFAULTS.concat((d.customExtras || []).map(function (x) {
    return x.name;
  })).filter(function (name) {
    return excluded.indexOf(name) < 0;
  });
}
function allPhotoTypes(d) {
  return PHOTO_TYPE_DEFAULTS.concat(d.customPhotoTypes || []);
}
function allVideoTypes(d) {
  return VIDEO_TYPE_DEFAULTS.concat(d.customVideoTypes || []);
}

function qtyStepper(field, val, disabled) {
  val = Math.max(0, +val || 0);
  return (
    '<div class="qty-step' +
    (disabled ? ' off' : '') +
    '" data-qty-field="' +
    field +
    '"><button type="button" data-qty-d="-1"' +
    (disabled ? ' disabled' : '') +
    '>−</button><span>' +
    val +
    '</span><button type="button" data-qty-d="1"' +
    (disabled ? ' disabled' : '') +
    '>+</button></div>'
  );
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

function fnCheckList(d) {
  return (
    '<div class="fn-list" id="f_funcs">' +
    allPkgFunctions(d)
      .map(function (item) {
        const on = d.functions.indexOf(item) >= 0;
        const hint = FUNCTION_HINTS[item];
        return (
          '<label class="fn-pick' +
          (on ? ' on' : '') +
          '"><input type="checkbox" data-fn="' +
          esc(item) +
          '" ' +
          (on ? 'checked' : '') +
          '><span class="fn-pick-txt"><strong>' +
          esc(item) +
          '</strong>' +
          (hint ? ' <em>(' + esc(hint) + ')</em>' : '') +
          '</span></label>'
        );
      })
      .join('') +
    '</div>'
  );
}

function renderDelTabs(active) {
  const tabs = [
    { id: 'photos', label: '📷 Photos' },
    { id: 'videos', label: '🎬 Videos' },
    { id: 'albums', label: '📚 Albums' },
    { id: 'digital', label: '☁ Digital' },
  ];
  return (
    '<div class="del-tabs">' +
    tabs
      .map(function (t) {
        return (
          '<button type="button" class="del-tab' +
          (active === t.id ? ' on' : '') +
          '" data-del-tab="' +
          t.id +
          '">' +
          t.label +
          '</button>'
        );
      })
      .join('') +
    '</div>'
  );
}

function renderPhotoDeliverTab(d) {
  const items = PHOTO_DELIVER.concat(d.customDeliverPhoto || []);
  return (
    '<p class="del-sec-title">Photography deliverables</p><p class="sub">Select the types of photos to be delivered.</p>' +
    items
      .map(function (name) {
        const on = d.deliverPhoto.indexOf(name) >= 0;
        const det = d.photoDetails[name] || { qty: 0, format: PHOTO_FORMATS[0], delivery: '5 Working Days' };
        if (!d.photoDetails[name]) d.photoDetails[name] = det;
        return (
          '<div class="del-card' +
          (on ? ' on' : '') +
          '"><div class="del-card-hd"><label class="del-chk"><input type="checkbox" data-dphoto="' +
          esc(name) +
          '" ' +
          (on ? 'checked' : '') +
          '></label><div class="del-thumb">🖼</div><div class="del-meta"><b>' +
          esc(name) +
          '</b><p class="sub">' +
          esc(PHOTO_DELIVER_HINTS[name] || '') +
          '</p></div></div>' +
          (on
            ? '<div class="del-fields">' +
              '<div class="fld"><label>Quantity</label><input type="number" data-photo-qty="' +
              esc(name) +
              '" value="' +
              det.qty +
              '"></div>' +
              '<div class="fld"><label>Format</label><select data-photo-fmt="' +
              esc(name) +
              '">' +
              PHOTO_FORMATS.map(function (f) {
                return (
                  '<option' +
                  (det.format === f ? ' selected' : '') +
                  '>' +
                  f +
                  '</option>'
                );
              }).join('') +
              '</select></div>' +
              '<div class="fld"><label>Delivery</label><select data-photo-del="' +
              esc(name) +
              '">' +
              DELIVERY_TIMELINES.map(function (t) {
                return (
                  '<option' +
                  (det.delivery === t ? ' selected' : '') +
                  '>' +
                  t +
                  '</option>'
                );
              }).join('') +
              '</select></div></div>'
            : '') +
          '</div>'
        );
      })
      .join('') +
    linkAdd('add-dphoto', 'Add Custom Photo Type')
  );
}

function renderVideoDeliverTab(d) {
  const items = VIDEO_DELIVER.concat(d.customDeliverVideo || []);
  return (
    '<p class="del-sec-title">Video deliverables</p><p class="sub">Select the types of videos to be delivered.</p>' +
    items
      .map(function (name) {
        const on = d.deliverVideo.indexOf(name) >= 0;
        const det = d.videoDetails[name] || {
          duration: VIDEO_DURATIONS[0],
          format: VIDEO_FORMATS[0],
          delivery: '15 Working Days',
        };
        if (!d.videoDetails[name]) d.videoDetails[name] = det;
        return (
          '<div class="del-card' +
          (on ? ' on' : '') +
          '"><div class="del-card-hd"><label class="del-chk"><input type="checkbox" data-dvideo="' +
          esc(name) +
          '" ' +
          (on ? 'checked' : '') +
          '></label><div class="del-thumb">▶</div><div class="del-meta"><b>' +
          esc(name) +
          '</b><p class="sub">' +
          esc(VIDEO_DELIVER_HINTS[name] || '') +
          '</p></div></div>' +
          (on
            ? '<div class="del-fields">' +
              '<div class="fld"><label>Duration</label><select data-video-dur="' +
              esc(name) +
              '">' +
              VIDEO_DURATIONS.map(function (v) {
                return (
                  '<option' +
                  (det.duration === v ? ' selected' : '') +
                  '>' +
                  v +
                  '</option>'
                );
              }).join('') +
              '</select></div>' +
              '<div class="fld"><label>Format</label><select data-video-fmt="' +
              esc(name) +
              '">' +
              VIDEO_FORMATS.map(function (f) {
                return (
                  '<option' +
                  (det.format === f ? ' selected' : '') +
                  '>' +
                  f +
                  '</option>'
                );
              }).join('') +
              '</select></div></div>'
            : '') +
          '</div>'
        );
      })
      .join('') +
    linkAdd('add-dvideo', 'Add Custom Video Type')
  );
}

function renderAlbumDeliverTab(d) {
  if (!d.albumPrints) d.albumPrints = defaultAlbumPrints();
  return (
    '<p class="del-sec-title">Albums &amp; prints</p><p class="sub">Select albums and printed materials.</p>' +
    ALBUM_PRINT_TYPES.map(function (name) {
      const row = d.albumPrints[name] || { on: false };
      const on = !!row.on;
      if (name === 'Photo Album') {
        return (
          '<div class="del-card' +
          (on ? ' on' : '') +
          '"><label class="del-card-hd"><input type="checkbox" data-album-type="' +
          esc(name) +
          '" ' +
          (on ? 'checked' : '') +
          '><div class="del-thumb">📕</div><div class="del-meta"><b>' +
          esc(name) +
          '</b></div></label>' +
          (on
            ? '<div class="del-fields">' +
              '<div class="fld"><label>Pages</label><input type="number" data-album-pages value="' +
              (row.pages || 40) +
              '"></div>' +
              '<div class="fld"><label>Size</label><select data-album-size><option' +
              ((row.size || '').indexOf('12') >= 0 ? ' selected' : '') +
              '>12 x 18 inch</option><option>10 x 12 inch</option></select></div>' +
              '<div class="fld"><label>Cover type</label><select data-album-cover><option' +
              (row.cover === 'Premium' ? ' selected' : '') +
              '>Premium</option><option>Standard</option></select></div></div>'
            : '') +
          '</div>'
        );
      }
      return (
        '<div class="del-card' +
        (on ? ' on' : '') +
        '"><label class="del-card-hd"><input type="checkbox" data-album-type="' +
        esc(name) +
        '" ' +
        (on ? 'checked' : '') +
        '><div class="del-thumb">🖼</div><div class="del-meta"><b>' +
        esc(name) +
        '</b></div></label>' +
        (on
          ? '<div class="del-fields">' +
            '<div class="fld"><label>Quantity</label><input type="number" data-album-qty value="' +
            (row.qty || 1) +
            '"></div>' +
            '<div class="fld"><label>Size</label><select data-album-size-' +
            esc(name) +
            '><option>A3</option><option>A4</option><option>6 x 6 inch</option><option>12 x 18 inch</option></select></div>' +
            '<div class="fld"><label>Type</label><select data-album-type-opt><option>Wall Calendar</option><option>Desk Calendar</option><option>Acrylic</option><option>Standard</option></select></div></div>'
          : '') +
        '</div>'
      );
    }).join('') +
    linkAdd('add-album-print', 'Add Custom Album/Print')
  );
}

function renderDigitalDeliverTab(d) {
  const custom = (d.customDeliverDigital || []).map(function (name) {
    return { id: name, icon: '➕', desc: 'Custom delivery option.' };
  });
  return (
    '<p class="del-sec-title">Digital delivery</p><p class="sub">Select how customers will receive their files.</p>' +
    DIGITAL_DELIVER.concat(custom)
      .map(function (item) {
        const on = d.deliverDigital.indexOf(item.id) >= 0;
        return (
          '<label class="dig-row' +
          (on ? ' on' : '') +
          '"><input type="checkbox" data-ddigital="' +
          esc(item.id) +
          '" ' +
          (on ? 'checked' : '') +
          '><span class="dig-ico">' +
          item.icon +
          '</span><span><b>' +
          esc(item.id) +
          '</b><span class="dig-desc">' +
          esc(item.desc) +
          '</span></span></label>'
        );
      })
      .join('') +
    linkAdd('add-ddigital', 'Add Custom Delivery Option')
  );
}

function renderCoverageTypes(types, obj, prefix, customKey) {
  return types
    .map(function (label) {
      const row = obj[label] || { on: false, qty: 0 };
      obj[label] = row;
      const field = prefix + '.' + label;
      return (
        '<div class="cov-type' +
        (!row.on ? ' disabled' : '') +
        '"><label><input type="checkbox" data-cov-type="' +
        esc(field) +
        '" ' +
        (row.on ? 'checked' : '') +
        '> ' +
        esc(label) +
        '</label>' +
        qtyStepper(field, row.qty, !row.on) +
        '</div>'
      );
    })
    .join('');
}

function renderPkgStep(step, d) {
  syncPkgPrice(d);
  switch (step) {
    case 0:
      return (
        '<div class="fld"><label>Package name *</label><input id="f_name" value="' +
        esc(d.name) +
        '"></div>' +
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
        '<div class="price-panel">' +
        '<div class="fld"><label>Package price (₹) *</label><input type="number" id="f_listPrice" value="' +
        d.listPrice +
        '"><p class="hint">Including GST</p></div>' +
        '<div class="fld"><label>Offer discount on this price?</label><div class="radio-row">' +
        '<label><input type="radio" name="discYes" value="no" ' +
        (d.discountYes !== 'yes' ? 'checked' : '') +
        '> No</label>' +
        '<label><input type="radio" name="discYes" value="yes" ' +
        (d.discountYes === 'yes' ? 'checked' : '') +
        '> Yes, give discount</label></div></div>' +
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
        '<div class="fld"><label>Short description *</label><textarea id="f_desc">' +
        esc(d.desc) +
        '</textarea></div>'
      );
    case 1:
      return fnCheckList(d) + linkAdd('add-function', 'Add New Function');
    case 2:
      if (!needsCeremonyStep(d.functions)) {
        return (
          '<p class="sub">Not required for selected functions. Continue to coverage.</p>' +
          '<div class="warn-box">Ceremony type applies to Wedding &amp; Reception, Reception, or Engagement.</div>'
        );
      }
      return (
        '<div id="f_ceremony">' +
        allCeremonyTypes(d)
          .map(function (item) {
            const on = d.ceremonyTypes.indexOf(item) >= 0;
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-cer="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> ' +
              esc(item) +
              '</label>'
            );
          })
          .join('') +
        '</div>' +
        linkAdd('add-ceremony', 'Add New') +
        '<div class="warn-box">This helps customers identify packages based on their ceremony type.</div>'
      );
    case 3: {
      const fns = d.functions.length ? d.functions : ['Wedding & Reception'];
      if (d.functions.indexOf(d.coverageFn) < 0) d.coverageFn = fns[0];
      return (
        '<div class="fld"><label>Coverage side</label><div class="seg seg-full" id="f_covSide">' +
        '<button type="button" class="' +
        (d.coverageSide === 'single' ? 'on' : '') +
        '" data-side="single">Single side</button>' +
        '<button type="button" class="' +
        (d.coverageSide === 'both' ? 'on' : '') +
        '" data-side="both">Both sides</button></div></div>' +
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
        '"><span class="hint"> / Hour</span></div>' +
        '<p class="lbl">Photography coverage</p>' +
        renderCoverageTypes(allPhotoTypes(d), d.photoTypes, 'photo', 'customPhotoTypes') +
        linkAdd('add-photo-type', 'Add New Photography Type') +
        '<p class="lbl">Videography coverage</p>' +
        renderCoverageTypes(allVideoTypes(d), d.videoTypes, 'video', 'customVideoTypes') +
        linkAdd('add-video-type', 'Add New Videography Type')
      );
    }
    case 4: {
      const tab = d.deliverTab || 'photos';
      let body = '';
      if (tab === 'photos') body = renderPhotoDeliverTab(d);
      else if (tab === 'videos') body = renderVideoDeliverTab(d);
      else if (tab === 'albums') body = renderAlbumDeliverTab(d);
      else body = renderDigitalDeliverTab(d);
      return renderDelTabs(tab) + body;
    }
    case 5:
      return (
        '<div id="f_extraRows">' +
        allExtrasNames(d)
          .map(function (name) {
            const x = d.extras[name] || { mode: 'extra', price: 0, basis: 'Per Event' };
            const modeCls = x.mode === 'included' ? 'mode-included' : 'mode-extra';
            return (
              '<div class="extra-row ' +
              modeCls +
              '" data-extra-name="' +
              esc(name) +
              '"><span class="extra-ico">✦</span><b class="extra-name">' +
              esc(name) +
              '</b>' +
              '<select data-extra-mode><option value="included"' +
              (x.mode === 'included' ? ' selected' : '') +
              '>Included</option><option value="extra"' +
              (x.mode === 'extra' ? ' selected' : '') +
              '>Extra</option></select>' +
              '<div class="extra-pay-fields">' +
              '<input type="number" data-extra-price value="' +
              (x.price != null ? x.price : 0) +
              '" placeholder="₹" min="0">' +
              '<select data-extra-basis><option' +
              (x.basis === 'Per Event' ? ' selected' : '') +
              '>Per Event</option><option' +
              (x.basis === 'Per Hour' ? ' selected' : '') +
              '>Per Hour</option></select></div>' +
              '<button type="button" class="pay-del" data-action="remove-extra" data-extra-name="' +
              esc(name) +
              '" title="Remove service" aria-label="Remove service">🗑</button></div>'
            );
          })
          .join('') +
        '</div>' +
        linkAdd('add-extra', 'Add New Service')
      );
    case 6: {
      const keys = pkgDeliveryKeys(d);
      if (!keys.length) {
        return (
          '<div class="hub-empty" style="margin:0">' +
          '<div class="hub-empty-ico">📦</div><b>No deliverables selected</b>' +
          '<p>Go back to the <b>Deliverables</b> step and check at least one photo, video, album, or digital option.</p></div>' +
          '<button type="button" class="btn btn-ghost" data-goto-step="4" style="margin-top:12px;width:100%">← Back to deliverables</button>'
        );
      }
      return (
        '<p class="sub">Set delivery timeline for each deliverable you selected (photos, videos, albums, digital).</p>' +
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
        '<div class="warn-box">Delivery timelines can be different for each deliverable.</div>'
      );
    }
    case 7:
      return renderPayPoliciesStep(d);
    case 8:
      return (
        REQ_DEFAULTS.concat(d.customRequirements || [])
          .map(function (item) {
            const on = d.requirements.indexOf(item) >= 0;
            return (
              '<label class="chk-row' +
              (on ? ' on' : '') +
              '"><input type="checkbox" data-req="' +
              esc(item) +
              '" ' +
              (on ? 'checked' : '') +
              '> ' +
              esc(item) +
              '</label>'
            );
          })
          .join('') + linkAdd('add-req', 'Add New Requirement')
      );
    case 9:
      return (
        PKG_STEPS.slice(0, 9)
          .map(function (s, i) {
            return (
              '<button type="button" class="review-jump" data-goto-step="' +
              i +
              '"><span>' +
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

function selectedDeliverableKeys(d) {
  const keys = [];
  (d.deliverPhoto || []).forEach(function (x) {
    keys.push(x);
  });
  (d.deliverVideo || []).forEach(function (x) {
    keys.push(x);
  });
  if (d.albumPrints) {
    Object.keys(d.albumPrints).forEach(function (name) {
      if (d.albumPrints[name] && d.albumPrints[name].on) keys.push(name);
    });
  }
  (d.deliverDigital || []).forEach(function (x) {
    keys.push(x);
  });
  return keys;
}

function pruneDeliveryMap(d) {
  if (!d.deliveryMap) d.deliveryMap = {};
  const allowed = {};
  selectedDeliverableKeys(d).forEach(function (k) {
    allowed[k] = true;
  });
  Object.keys(d.deliveryMap).forEach(function (k) {
    if (!allowed[k]) delete d.deliveryMap[k];
  });
}

function syncDeliveryMap(d) {
  if (!d.deliveryMap) d.deliveryMap = {};
  (d.deliverPhoto || []).forEach(function (name) {
    const det = d.photoDetails[name];
    if (det && det.delivery) d.deliveryMap[name] = det.delivery;
    else if (!d.deliveryMap[name]) d.deliveryMap[name] = '5 Working Days';
  });
  (d.deliverVideo || []).forEach(function (name) {
    const det = d.videoDetails[name];
    if (det && det.delivery) d.deliveryMap[name] = det.delivery;
    else if (!d.deliveryMap[name]) d.deliveryMap[name] = '15 Working Days';
  });
  if (d.albumPrints) {
    Object.keys(d.albumPrints).forEach(function (name) {
      if (d.albumPrints[name] && d.albumPrints[name].on) {
        if (!d.deliveryMap[name]) {
          d.deliveryMap[name] =
            name === 'Photo Album' ? '45 Days (after selection)' : '30 Working Days';
        }
      }
    });
  }
  (d.deliverDigital || []).forEach(function (name) {
    if (!d.deliveryMap[name]) d.deliveryMap[name] = '5 Working Days';
  });
  pruneDeliveryMap(d);
}

function pkgDeliveryKeys(d) {
  syncDeliveryMap(d);
  return selectedDeliverableKeys(d);
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
  if (g('f_duration')) d.duration = g('f_duration').value;
  if (g('f_extraHour')) d.extraHour = +g('f_extraHour').value || 0;
  document.querySelectorAll('.extra-row').forEach(function (row) {
    const name = row.getAttribute('data-extra-name');
    if (!name) return;
    const mode = row.querySelector('[data-extra-mode]').value;
    const priceEl = row.querySelector('[data-extra-price]');
    const basisEl = row.querySelector('[data-extra-basis]');
    const prev = d.extras[name] || {};
    if (mode === 'included') {
      const price =
        priceEl && priceEl.value !== '' ? +(priceEl.value || 0) : prev.price != null ? prev.price : 0;
      const basis = basisEl && basisEl.value ? basisEl.value : prev.basis || 'Per Event';
      d.extras[name] = { mode: 'included', price: price, basis: basis };
    } else {
      d.extras[name] = {
        mode: 'extra',
        price: +(priceEl && priceEl.value !== '' ? priceEl.value : prev.price != null ? prev.price : 0),
        basis: basisEl && basisEl.value ? basisEl.value : prev.basis || 'Per Event',
      };
    }
  });
  document.querySelectorAll('[data-photo-qty]').forEach(function (inp) {
    const k = inp.getAttribute('data-photo-qty');
    if (!d.photoDetails[k]) d.photoDetails[k] = {};
    d.photoDetails[k].qty = +inp.value || 0;
  });
  document.querySelectorAll('[data-photo-fmt]').forEach(function (sel) {
    const k = sel.getAttribute('data-photo-fmt');
    if (!d.photoDetails[k]) d.photoDetails[k] = {};
    d.photoDetails[k].format = sel.value;
  });
  document.querySelectorAll('[data-photo-del]').forEach(function (sel) {
    const k = sel.getAttribute('data-photo-del');
    if (!d.photoDetails[k]) d.photoDetails[k] = {};
    d.photoDetails[k].delivery = sel.value;
  });
  document.querySelectorAll('[data-video-dur]').forEach(function (sel) {
    const k = sel.getAttribute('data-video-dur');
    if (!d.videoDetails[k]) d.videoDetails[k] = {};
    d.videoDetails[k].duration = sel.value;
  });
  document.querySelectorAll('[data-video-fmt]').forEach(function (sel) {
    const k = sel.getAttribute('data-video-fmt');
    if (!d.videoDetails[k]) d.videoDetails[k] = {};
    d.videoDetails[k].format = sel.value;
  });
  document.querySelectorAll('[data-del-key]').forEach(function (sel) {
    const k = sel.getAttribute('data-del-key');
    if (!k) return;
    d.deliveryMap[k] = sel.value;
    if ((d.deliverPhoto || []).indexOf(k) >= 0) {
      if (!d.photoDetails[k]) d.photoDetails[k] = {};
      d.photoDetails[k].delivery = sel.value;
    }
    if ((d.deliverVideo || []).indexOf(k) >= 0) {
      if (!d.videoDetails[k]) d.videoDetails[k] = {};
      d.videoDetails[k].delivery = sel.value;
    }
  });
  pruneDeliveryMap(d);
  readPkgPolicyTiersFromDom(d);
  d.paymentStages = [];
  document.querySelectorAll('.pay-stage-card').forEach(function (row) {
    d.paymentStages.push({
      id: uid('ps'),
      label: row.querySelector('[data-pay-label]').value.trim() || 'Stage',
      pct: +(row.querySelector('[data-pay-pct]').value || 0),
    });
  });
  if (!d.policyValues) d.policyValues = {};
  document.querySelectorAll('[data-pol-val]').forEach(function (inp) {
    const pol = inp.getAttribute('data-pol-key');
    const field = inp.getAttribute('data-pol-field');
    if (!pol || !field) return;
    if (!d.policyValues[pol]) d.policyValues[pol] = defaultPolicyValue(pol);
    d.policyValues[pol][field] = inp.type === 'number' ? +inp.value || 0 : inp.value;
  });
  syncPkgPrice(d);
  d.coverage = pkgCoverageSummary(d);
  d.deliverables = pkgDeliverSummary(d);
}

function pkgCoverageSummary(d) {
  const photo = [];
  Object.keys(d.photoTypes || {}).forEach(function (k) {
    const r = d.photoTypes[k];
    if (r.on && r.qty) photo.push(k.split(' ')[0] + '×' + r.qty);
  });
  const video = [];
  Object.keys(d.videoTypes || {}).forEach(function (k) {
    const r = d.videoTypes[k];
    if (r.on && r.qty) video.push(k.split(' ')[0] + '×' + r.qty);
  });
  return (
    (d.coverageSide === 'both' ? 'Both sides' : 'Single side') +
    ' · Photo: ' +
    (photo.join(', ') || '—') +
    ' · Video: ' +
    (video.join(', ') || '—') +
    ' · ' +
    d.duration +
    ' · Extra hr ' +
    inr(d.extraHour)
  );
}

function pkgDeliverSummary(d) {
  const albums = [];
  if (d.albumPrints) {
    ALBUM_PRINT_TYPES.forEach(function (name) {
      if (d.albumPrints[name] && d.albumPrints[name].on) albums.push(name);
    });
  }
  return (
    (d.deliverPhoto || []).join(', ') +
    ' | Video: ' +
    (d.deliverVideo || []).join(', ') +
    (albums.length ? ' | ' + albums.join(', ') : '') +
    ' | Digital: ' +
    (d.deliverDigital || []).join(', ')
  );
}

function setCovTypeField(d, field, on, qty) {
  const parts = field.split('.');
  const kind = parts[0];
  const label = parts.slice(1).join('.');
  const bucket = kind === 'photo' ? d.photoTypes : d.videoTypes;
  if (!bucket[label]) bucket[label] = { on: false, qty: 0 };
  bucket[label].on = on;
  bucket[label].qty = qty;
}

function bindPkgWizard(d) {
  const body = el('wizBody');
  if (!body) return;
  body.onclick = function (e) {
    const tabBtn = e.target.closest('[data-del-tab]');
    if (tabBtn) {
      readPkgWizardFields(d);
      d.deliverTab = tabBtn.getAttribute('data-del-tab');
      renderWizardBody();
      return;
    }
    const t = e.target.closest('[data-action],[data-goto-step],[data-qty-d],[data-side],[data-lvl]');
    if (t) {
      if (t.getAttribute('data-goto-step') != null) {
        readPkgWizardFields(d);
        wiz.step = +t.getAttribute('data-goto-step');
        renderWizard();
        return;
      }
      const act = t.getAttribute('data-action');
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
      if (act === 'add-photo-type') {
        const name = prompt('Photography type');
        if (name && d.customPhotoTypes.indexOf(name) < 0) {
          d.customPhotoTypes.push(name.trim());
          d.photoTypes[name.trim()] = { on: true, qty: 1 };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-video-type') {
        const name = prompt('Videography type');
        if (name && d.customVideoTypes.indexOf(name) < 0) {
          d.customVideoTypes.push(name.trim());
          d.videoTypes[name.trim()] = { on: true, qty: 1 };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-extra') {
        const name = prompt('Service name');
        if (name) {
          const trimmed = name.trim();
          if (!trimmed) return;
          d.customExtras.push({ name: trimmed });
          d.extras[trimmed] = { mode: 'extra', price: 5000, basis: 'Per Event' };
          if (d.excludedExtras) {
            d.excludedExtras = d.excludedExtras.filter(function (x) {
              return x !== trimmed;
            });
          }
          renderWizardBody();
        }
        return;
      }
      if (act === 'remove-extra') {
        const extraName = t.getAttribute('data-extra-name');
        if (!extraName) return;
        readPkgWizardFields(d);
        delete d.extras[extraName];
        d.customExtras = (d.customExtras || []).filter(function (x) {
          return x.name !== extraName;
        });
        if (!d.excludedExtras) d.excludedExtras = [];
        if (PKG_EXTRA_DEFAULTS.indexOf(extraName) >= 0 && d.excludedExtras.indexOf(extraName) < 0) {
          d.excludedExtras.push(extraName);
        }
        renderWizardBody();
        return;
      }
      if (act === 'add-dphoto') {
        const name = prompt('Photo deliverable name');
        if (name) {
          d.customDeliverPhoto.push(name.trim());
          d.photoDetails[name.trim()] = { qty: 100, format: PHOTO_FORMATS[0], delivery: '5 Working Days' };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-dvideo') {
        const name = prompt('Video deliverable name');
        if (name) {
          d.customDeliverVideo.push(name.trim());
          d.videoDetails[name.trim()] = {
            duration: VIDEO_DURATIONS[0],
            format: VIDEO_FORMATS[0],
            delivery: '15 Working Days',
          };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-ddigital') {
        const name = prompt('Delivery option');
        if (name) {
          d.customDeliverDigital.push(name.trim());
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-album-print') {
        const name = prompt('Album / print type');
        if (name && !d.albumPrints[name]) {
          d.albumPrints[name] = { on: true, qty: 1, size: 'A4', type: 'Custom' };
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-stage') {
        readPkgWizardFields(d);
        d.paymentStages.push({ id: uid('ps'), label: 'Custom Stage', pct: 0 });
        renderWizardBody();
        return;
      }
      if (act === 'add-policy') {
        const name = prompt('Policy name');
        if (name) {
          d.customPolicies.push(name.trim());
          if (!d.policyValues) d.policyValues = {};
          d.policyValues[name.trim()] = defaultPolicyValue(name.trim());
          if (d.policies.indexOf(name.trim()) < 0) d.policies.push(name.trim());
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
        if (d.paymentStages.length <= 1) return;
        const i = +t.getAttribute('data-idx');
        d.paymentStages.splice(i, 1);
        renderWizardBody();
        return;
      }
      if (act === 'pkg-policy-tab') {
        readPkgWizardFields(d);
        pkgWizPolicyTab = t.getAttribute('data-tab') === 'reschedule' ? 'reschedule' : 'cancel';
        renderWizardBody();
        return;
      }
      if (act === 'pkg-policy-add-tier') {
        readPkgWizardFields(d);
        const kind = t.getAttribute('data-policy');
        const arr = kind === 'reschedule' ? d.rescheduleRules : d.cancelRules;
        arr.push({ days: 'Days before event', pct: 10 });
        renderWizardBody();
        return;
      }
      if (act === 'pkg-policy-del-tier') {
        readPkgWizardFields(d);
        const kind = pkgWizPolicyTab === 'reschedule' ? 'reschedule' : 'cancel';
        const arr = kind === 'reschedule' ? d.rescheduleRules : d.cancelRules;
        const row = t.closest('.policy-row');
        const box = row && row.parentElement;
        if (!row || !box) return;
        const idx = Array.prototype.indexOf.call(box.querySelectorAll('.policy-row'), row);
        if (arr.length <= 1) {
          toast('Keep at least one tier in this policy.');
          return;
        }
        if (idx >= 0) arr.splice(idx, 1);
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
      if (wrap.classList.contains('off')) return;
      const field = wrap.getAttribute('data-qty-field');
      const delta = +qtyBtn.getAttribute('data-qty-d');
      const span = wrap.querySelector('span');
      let v = +span.textContent + delta;
      v = Math.max(0, Math.min(20, v));
      span.textContent = v;
      const parts = field.split('.');
      setCovTypeField(d, field, true, v);
      return;
    }
  };
  body.onchange = function (e) {
    const t = e.target;
    if (t.matches('[data-fn]')) {
      const fn = t.getAttribute('data-fn');
      if (t.checked) {
        if (d.functions.indexOf(fn) < 0) d.functions.push(fn);
      } else {
        d.functions = d.functions.filter(function (x) {
          return x !== fn;
        });
      }
      if (!needsCeremonyStep(d.functions)) d.ceremonyTypes = [];
      renderWizardBody();
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
    if (t.matches('[data-cov-type]')) {
      const field = t.getAttribute('data-cov-type');
      const parts = field.split('.');
      const label = parts.slice(1).join('.');
      const bucket = parts[0] === 'photo' ? d.photoTypes : d.videoTypes;
      bucket[label].on = t.checked;
      if (t.checked && !bucket[label].qty) bucket[label].qty = 1;
      renderWizardBody();
      return;
    }
    if (t.matches('[data-dphoto]')) {
      const val = t.getAttribute('data-dphoto');
      if (t.checked) {
        if (d.deliverPhoto.indexOf(val) < 0) d.deliverPhoto.push(val);
      } else {
        d.deliverPhoto = d.deliverPhoto.filter(function (x) {
          return x !== val;
        });
        if (d.deliveryMap) delete d.deliveryMap[val];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-dvideo]')) {
      const val = t.getAttribute('data-dvideo');
      if (t.checked) {
        if (d.deliverVideo.indexOf(val) < 0) d.deliverVideo.push(val);
      } else {
        d.deliverVideo = d.deliverVideo.filter(function (x) {
          return x !== val;
        });
        if (d.deliveryMap) delete d.deliveryMap[val];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-ddigital]')) {
      const val = t.getAttribute('data-ddigital');
      if (t.checked) {
        if (d.deliverDigital.indexOf(val) < 0) d.deliverDigital.push(val);
      } else {
        d.deliverDigital = d.deliverDigital.filter(function (x) {
          return x !== val;
        });
        if (d.deliveryMap) delete d.deliveryMap[val];
      }
      renderWizardBody();
      return;
    }
    if (t.matches('[data-album-type]')) {
      const name = t.getAttribute('data-album-type');
      if (!d.albumPrints[name]) d.albumPrints[name] = defaultAlbumPrints()[name] || { on: false };
      d.albumPrints[name].on = t.checked;
      if (!t.checked && d.deliveryMap) delete d.deliveryMap[name];
      renderWizardBody();
      return;
    }
    ['data-pol', 'data-req'].forEach(function (attr) {
      if (!t.matches('[' + attr + ']')) return;
      const val = t.getAttribute(attr);
      const arr = attr === 'data-pol' ? 'policies' : 'requirements';
      if (t.checked) {
        if (d[arr].indexOf(val) < 0) d[arr].push(val);
        if (attr === 'data-pol') {
          if (!d.policyValues) d.policyValues = {};
          if (!d.policyValues[val]) d.policyValues[val] = defaultPolicyValue(val);
        }
      } else d[arr] = d[arr].filter(function (x) {
        return x !== val;
      });
      if (attr === 'data-pol') renderWizardBody();
    });
  };
  document.querySelectorAll('[data-pay-pct],[data-pay-label]').forEach(function (node) {
    node.oninput = function () {
      readPkgWizardFields(d);
      if (wiz.step === 7) renderWizardBody();
    };
  });
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
  body.onchange = function (e) {
    if (!e.target.matches('[data-extra-mode]')) return;
    const row = e.target.closest('.extra-row');
    const mode = e.target.value;
    const name = row.getAttribute('data-extra-name');
    if (!name) return;
    const priceEl = row.querySelector('[data-extra-price]');
    const basisEl = row.querySelector('[data-extra-basis]');
    const prev = d.extras[name] || {};
    if (mode === 'included') {
      d.extras[name] = {
        mode: 'included',
        price: priceEl ? +(priceEl.value || 0) : prev.price != null ? prev.price : 0,
        basis: basisEl ? basisEl.value : prev.basis || 'Per Event',
      };
    } else {
      const price = prev.price != null ? prev.price : +(priceEl && priceEl.value ? priceEl.value : 0);
      const basis = prev.basis || (basisEl ? basisEl.value : 'Per Event');
      d.extras[name] = { mode: 'extra', price: price, basis: basis };
      if (priceEl) priceEl.value = String(price);
      if (basisEl) basisEl.value = basis;
    }
    applyExtraRowMode(row, mode);
  };
  if (wiz.step === 5) syncAllExtraRowModes();
}
