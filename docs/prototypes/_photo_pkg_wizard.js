/* Photography package wizard — mobile Create Package flow (10 steps) */

const PKG_AERIAL_EXTRA = 'Drone / Helicam';

const PKG_EXTRA_DEFAULTS = [
  PKG_AERIAL_EXTRA,
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
const ALBUM_MAIN_TYPES = ['Photo Album'];
const COMPLIMENTARY_PRINT_TYPES = ['Calendar', 'Mini Album', 'Photo Frame'];
const ALBUM_PRINT_TYPES = ALBUM_MAIN_TYPES.concat(COMPLIMENTARY_PRINT_TYPES);
const ALBUM_PAGE_FINISHES = ['Matte', 'Glossy', 'Lustre', 'Silk', 'Metallic'];
const ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT = ['Matte', 'Glossy'];
const DIGITAL_DELIVER = [
  { id: 'Google Drive Link', icon: '📁', desc: 'Share high-resolution files via Google Drive.' },
  { id: 'Online Gallery', icon: '🔗', desc: 'Private online gallery for easy access.' },
  { id: 'Photo Selection App', icon: '📲', desc: 'App for customers to select photos for albums.' },
  { id: 'Guest Gallery & Face AI', icon: '🤳', desc: 'Guests find and download their photos with face search.' },
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
  if (!d.cancelReschedTab) d.cancelReschedTab = 'cancel';
}

function activeCancelReschedTab(d) {
  return d.cancelReschedTab === 'reschedule' ? 'reschedule' : 'cancel';
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
        '<button type="button" class="policy-row-remove" data-action="cr-policy-del-tier" title="Remove tier" aria-label="Remove tier">✕</button></div>'
      );
    })
    .join('');
  return (
    '<div class="policy-rows" id="pkgPolicyTierRows" data-policy-kind="' +
    kind +
    '">' +
    rows +
    '</div>' +
    '<button type="button" class="policy-add-tier" data-action="cr-policy-add-tier" data-policy="' +
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

function onCrPolicyTab(d, readFields, tab) {
  readFields(d);
  d.cancelReschedTab = tab === 'reschedule' ? 'reschedule' : 'cancel';
  renderWizardBody();
}

function onCrPolicyAddTier(d, readFields, kind) {
  readFields(d);
  ensurePkgPolicyRules(d);
  const arr = kind === 'reschedule' ? d.rescheduleRules : d.cancelRules;
  arr.push({ days: 'Days before event', pct: 10 });
  renderWizardBody();
}

function onCrPolicyDelTier(d, readFields, btn) {
  readFields(d);
  ensurePkgPolicyRules(d);
  const kind = activeCancelReschedTab(d);
  const arr = kind === 'reschedule' ? d.rescheduleRules : d.cancelRules;
  const row = btn.closest('.policy-row');
  const box = row && row.parentElement;
  if (!row || !box) return;
  const idx = Array.prototype.indexOf.call(box.querySelectorAll('.policy-row'), row);
  if (arr.length <= 1) {
    toast('Keep at least one tier in this policy.');
    return;
  }
  if (idx >= 0) arr.splice(idx, 1);
  renderWizardBody();
}

function renderCancelReschedBlock(d) {
  ensurePkgPolicyRules(d);
  const cancelOn = activeCancelReschedTab(d) === 'cancel';
  return (
    '<section class="policy-section" aria-label="Cancellation and rescheduling">' +
    '<h2 class="policy-section-hd">Cancellation &amp; rescheduling</h2>' +
    '<p class="policy-section-lead">Set how much of the <b>advance</b> you keep when the customer cancels or moves the date. Use the tabs for each case. Tap <b>+ Add tier</b> for more ranges, or ✕ to remove one.</p>' +
    '<div class="policy-tabs" role="tablist">' +
    '<button type="button" role="tab" aria-selected="' +
    (cancelOn ? 'true' : 'false') +
    '" class="' +
    (cancelOn ? 'on' : '') +
    '" data-action="cr-policy-tab" data-tab="cancel">Cancellation</button>' +
    '<button type="button" role="tab" aria-selected="' +
    (!cancelOn ? 'true' : 'false') +
    '" class="' +
    (!cancelOn ? 'on' : '') +
    '" data-action="cr-policy-tab" data-tab="reschedule">Rescheduling</button></div>' +
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
    renderCancelReschedBlock(d) +
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
/** Included deliverables that are not post-event timelines (omit from Delivery step). */
const DELIVERY_TIMELINE_SKIP = ['Live Streaming'];

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

function coverageDurationHelp(duration) {
  const d = duration || 'Full Day';
  if (d === 'Full Day') {
    return 'Included wedding-day coverage (use your policy or customer requirements to state exact hours, e.g. 10–12 hours).';
  }
  if (d === 'Custom') return 'Describe exact hours in package description or customer requirements.';
  return 'Included coverage up to this limit for the function(s) in this package.';
}

function extraHourChargeHelp(duration) {
  if (duration === 'Full Day') {
    return 'Recommended for weddings: per-hour rate if the event runs past your full-day limit. Set ₹0 if you never charge overtime.';
  }
  return 'Per-hour rate beyond the duration above. Set ₹0 if extra hours are not offered.';
}
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
      price: name === PKG_AERIAL_EXTRA ? 10000 : hourly ? 5000 : 8000,
      basis: hourly ? 'Per Hour' : 'Per Event',
      hourlyLimit: false,
      includedHours: 4,
      extraHour: 2000,
    };
    if (name === 'Live Streaming') {
      o[name].hourlyLimit = true;
      o[name].includedHours = 4;
      o[name].extraHour = 2000;
    }
  });
  return o;
}

function extraIncludedHourlyFields(x) {
  const hourlyLimit = !!x.hourlyLimit;
  const incl = x.includedHours != null ? x.includedHours : 4;
  const extra = x.extraHour != null ? x.extraHour : 0;
  return (
    '<div class="extra-included-block">' +
    '<label class="extra-hourly-chk"><input type="checkbox" data-extra-hourly-on ' +
    (hourlyLimit ? 'checked' : '') +
    '> Limit included hours</label>' +
    '<p class="hint" style="margin:4px 0 8px">For example: 4 hours live stream included, then paid per extra hour.</p>' +
    '<div class="extra-hourly-fields">' +
    '<div class="fld"><label>Hours included</label><input type="number" min="0" step="1" data-extra-included-hours value="' +
    incl +
    '"></div>' +
    '<div class="fld"><label>Extra hour (₹)</label><input type="number" min="0" step="500" data-extra-hour-after value="' +
    extra +
    '"><span class="hint"> per hour after that</span></div></div></div>'
  );
}

function readExtraHourlyFieldsFromRow(row, target, prev) {
  const hourlyOn = row.querySelector('[data-extra-hourly-on]');
  const inclH = row.querySelector('[data-extra-included-hours]');
  const extraH = row.querySelector('[data-extra-hour-after]');
  if (hourlyOn) target.hourlyLimit = hourlyOn.checked;
  else if (prev.hourlyLimit != null) target.hourlyLimit = prev.hourlyLimit;
  if (inclH) target.includedHours = +inclH.value || 0;
  else if (prev.includedHours != null) target.includedHours = prev.includedHours;
  if (extraH) target.extraHour = +extraH.value || 0;
  else if (prev.extraHour != null) target.extraHour = prev.extraHour;
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
      qty: 1,
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

function videoDeliverQty(d, name) {
  const det = d.videoDetails && d.videoDetails[name];
  const q = det && det.qty != null ? +det.qty : 1;
  return q > 0 ? q : 1;
}

function deliverableTimelineLabel(d, key) {
  if ((d.deliverVideo || []).indexOf(key) >= 0 && videoDeliverQty(d, key) > 1) {
    return key + ' (×' + videoDeliverQty(d, key) + ')';
  }
  return key;
}

function formatVideoDeliverSummary(d) {
  return (d.deliverVideo || [])
    .map(function (name) {
      const q = videoDeliverQty(d, name);
      return q > 1 ? name + ' ×' + q : name;
    })
    .join(', ');
}

function migrateComplimentaryDeliverables(d) {
  if (!d) return;
  if (!d.albumPrints) d.albumPrints = albumPrintsAllOff();
  const legacy = d.complimentary;
  if (legacy && legacy.length) {
    legacy.forEach(function (item) {
      if (/save the date/i.test(String(item || ''))) return;
      const name = item;
      if (!d.albumPrints[name]) d.albumPrints[name] = { on: false, qty: 1 };
      d.albumPrints[name].on = true;
      d.albumPrints[name].complimentary = true;
    });
  }
  (d.customComplimentary || []).forEach(function (x) {
    const name = (typeof x === 'string' ? x : x.name || '').trim();
    if (!name) return;
    if (!d.albumPrints[name]) d.albumPrints[name] = { on: false, qty: 1 };
    d.albumPrints[name].on = true;
    d.albumPrints[name].complimentary = true;
  });
  delete d.complimentary;
  delete d.customComplimentary;
}

function ensurePkgMarketingFields(d) {
  if (!d) return;
  migrateComplimentaryDeliverables(d);
  if (d.shootUnlimitedClicks == null) d.shootUnlimitedClicks = false;
  if (d.equipmentNote == null) d.equipmentNote = '';
  if (d.qualityNote == null) d.qualityNote = '';
  if (d.albumPrints) {
    Object.keys(d.albumPrints).forEach(function (k) {
      if (d.albumPrints[k].complimentary == null) d.albumPrints[k].complimentary = false;
    });
  }
}

function albumComplimentaryField(row) {
  return (
    '<label class="del-complimentary-chk"><input type="checkbox" data-album-complimentary ' +
    (row.complimentary ? 'checked' : '') +
    '> Complimentary deliverables</label>'
  );
}

function normalizeAlbumFinishRow(row) {
  if (!row) return;
  if (row.pageFinishPolicy !== 'customer') row.pageFinishPolicy = 'studio';
  if (!row.pageFinishCustomerOptions || !row.pageFinishCustomerOptions.length) {
    row.pageFinishCustomerOptions = ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT.slice();
  }
  row.pageFinishCustomerOptions = row.pageFinishCustomerOptions.filter(function (x) {
    return ALBUM_PAGE_FINISHES.indexOf(x) >= 0;
  });
  if (!row.pageFinishCustomerOptions.length) {
    row.pageFinishCustomerOptions = ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT.slice();
  }
}

function albumPageFinishValue(row) {
  const f = row && row.pageFinish;
  if (f && ALBUM_PAGE_FINISHES.indexOf(f) >= 0) return f;
  return 'Matte';
}

function albumPageFinishSummaryText(row) {
  normalizeAlbumFinishRow(row);
  if (row.pageFinishPolicy === 'customer') {
    const use = row.pageFinishCustomerOptions.slice();
    return 'customer chooses paper: ' + use.join(', ');
  }
  return albumPageFinishValue(row) + ' paper';
}

function readAlbumFinishFromCard(card, row) {
  if (!card || !row) return;
  normalizeAlbumFinishRow(row);
  const policySel = card.querySelector('[data-album-finish-policy]');
  if (policySel) row.pageFinishPolicy = policySel.value === 'customer' ? 'customer' : 'studio';
  const finishSel = card.querySelector('[data-album-page-finish]');
  if (finishSel) row.pageFinish = finishSel.value;
  const offered = [];
  card.querySelectorAll('[data-album-finish-offered]:checked').forEach(function (chk) {
    if (chk.value) offered.push(chk.value);
  });
  if (row.pageFinishPolicy === 'customer') {
    row.pageFinishCustomerOptions = offered.length ? offered : ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT.slice();
  }
}

function renderAlbumPageFinishField(row) {
  normalizeAlbumFinishRow(row);
  const policy = row.pageFinishPolicy;
  const val = albumPageFinishValue(row);
  const offered = row.pageFinishCustomerOptions;
  return (
    '<div class="fld album-page-finish-fld"><label>Album paper</label>' +
    '<p class="hint album-finish-hint">Paper inside the album (not cover).</p>' +
    '<div class="fld album-finish-policy-fld"><label>Paper on package</label><select data-album-finish-policy>' +
    '<option value="studio"' +
    (policy === 'studio' ? ' selected' : '') +
    '>Album paper we provide</option>' +
    '<option value="customer"' +
    (policy === 'customer' ? ' selected' : '') +
    '>Customer chooses</option></select></div>' +
    '<div class="album-finish-panel album-finish-studio"' +
    (policy === 'studio' ? '' : ' hidden') +
    '><div class="fld"><label>Paper</label><select data-album-page-finish>' +
    ALBUM_PAGE_FINISHES.map(function (opt) {
      return '<option' + (val === opt ? ' selected' : '') + '>' + opt + '</option>';
    }).join('') +
    '</select></div></div>' +
    '<div class="album-finish-panel album-finish-customer"' +
    (policy === 'customer' ? '' : ' hidden') +
    '><p class="hint album-finish-customer-hint">Tick papers you allow. Customer picks one later.</p>' +
    '<div class="album-finish-choices">' +
    ALBUM_PAGE_FINISHES.map(function (opt) {
      const on = offered.indexOf(opt) >= 0;
      return (
        '<label class="chk-row album-finish-opt' +
        (on ? ' on' : '') +
        '"><input type="checkbox" data-album-finish-offered value="' +
        esc(opt) +
        '" ' +
        (on ? 'checked' : '') +
        '> ' +
        esc(opt) +
        '</label>'
      );
    }).join('') +
    '</div></div></div>'
  );
}

function defaultAlbumPrints() {
  return {
    'Photo Album': {
      on: true,
      pages: 40,
      size: '12 x 18 inch',
      cover: 'Premium',
      pageFinish: 'Matte',
      pageFinishPolicy: 'studio',
      pageFinishCustomerOptions: ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT.slice(),
    },
    Calendar: { on: false, qty: 1, size: 'A3', type: 'Wall Calendar', complimentary: true },
    'Mini Album': {
      on: false,
      qty: 1,
      size: '6 x 6 inch',
      cover: 'Standard',
      pageFinish: 'Matte',
      pageFinishPolicy: 'studio',
      pageFinishCustomerOptions: ALBUM_PAGE_FINISH_CUSTOMER_DEFAULT.slice(),
      complimentary: true,
    },
    'Photo Frame': { on: false, qty: 1, size: '12 x 18 inch', type: 'Acrylic', complimentary: true },
  };
}

function albumPrintsAllOff() {
  const a = defaultAlbumPrints();
  Object.keys(a).forEach(function (name) {
    a[name].on = false;
  });
  return a;
}

function defaultCoverageTypes(defaults, seed) {
  const o = {};
  defaults.forEach(function (label, i) {
    const s = seed[label] || { on: i < 2, qty: i < 2 ? 1 : 0 };
    o[label] = { on: !!s.on, qty: +s.qty || 0 };
  });
  return o;
}

function fnIsCoupleShoot(fnName) {
  return /shoot/i.test(String(fnName || ''));
}

function fnShowsCoverageSide(fnName) {
  return !fnIsCoupleShoot(fnName);
}

function pkgNeedsCoverageSideUi(d) {
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  return fns.some(fnShowsCoverageSide);
}

function resolvePkgCoverageSide(d) {
  if (d.coverageSide === 'single' || d.coverageSide === 'both') return d.coverageSide;
  ensurePkgCoverageByFunction(d);
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  for (let i = 0; i < fns.length; i++) {
    if (!fnShowsCoverageSide(fns[i])) continue;
    const block = d.coverageByFunction[fns[i]];
    if (block && (block.coverageSide === 'single' || block.coverageSide === 'both')) {
      return block.coverageSide;
    }
  }
  return 'both';
}

function applyPkgCoverageSide(d, side) {
  if (side !== 'single' && side !== 'both') return;
  d.coverageSide = side;
  ensurePkgCoverageByFunction(d);
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  fns.forEach(function (fn) {
    if (fnShowsCoverageSide(fn)) d.coverageByFunction[fn].coverageSide = side;
    else d.coverageByFunction[fn].coverageSide = 'single';
  });
}

function defaultFnCoverage(fnName, fromTemplate) {
  if (fromTemplate) {
    return JSON.parse(JSON.stringify(fromTemplate));
  }
  const shoot = fnIsCoupleShoot(fnName);
  return {
    coverageSide: shoot ? 'single' : 'both',
    duration: shoot ? 'Up to 5 Hours' : 'Full Day',
    extraHour: shoot ? 3000 : 5000,
    photoTypes: defaultCoverageTypes(
      PHOTO_TYPE_DEFAULTS,
      shoot
        ? {
            'Candid Photographer': { on: true, qty: 1 },
            'Traditional Photographer': { on: false, qty: 0 },
            'Candid + Traditional Photographer': { on: false, qty: 0 },
          }
        : {
            'Candid Photographer': { on: true, qty: 1 },
            'Traditional Photographer': { on: true, qty: 1 },
            'Candid + Traditional Photographer': { on: false, qty: 0 },
          }
    ),
    videoTypes: defaultCoverageTypes(
      VIDEO_TYPE_DEFAULTS,
      shoot
        ? {
            'Candid Videographer': { on: false, qty: 0 },
            'Traditional Videographer': { on: false, qty: 0 },
            'Cinematic Videographer': { on: true, qty: 1 },
          }
        : {
            'Candid Videographer': { on: true, qty: 1 },
            'Traditional Videographer': { on: true, qty: 1 },
            'Cinematic Videographer': { on: true, qty: 1 },
          }
    ),
  };
}

const AERIAL_EXTRA_LEGACY = ['Drone', 'Heli Cam', 'Drone Coverage'];

function migrateDroneHelicamExtra(d) {
  if (!d) return;
  const LEGACY = AERIAL_EXTRA_LEGACY;
  if (!d.extras) d.extras = {};
  const hadLegacy = LEGACY.some(function (k) {
    return d.extras[k];
  });
  const ex = d.excludedExtras || [];
  const legacyExcluded = LEGACY.filter(function (k) {
    return ex.indexOf(k) >= 0;
  });
  if (!hadLegacy && !legacyExcluded.length) return;
  if (!d.extras[PKG_AERIAL_EXTRA] && hadLegacy) {
    const merged = { mode: 'extra', price: 10000, basis: 'Per Event' };
    LEGACY.forEach(function (k) {
      const x = d.extras[k];
      if (!x) return;
      if (x.mode === 'included') merged.mode = 'included';
      if (+x.price > merged.price) merged.price = +x.price;
      if (x.basis) merged.basis = x.basis;
    });
    d.extras[PKG_AERIAL_EXTRA] = merged;
  }
  LEGACY.forEach(function (k) {
    delete d.extras[k];
  });
  if (d.excludedExtras) {
    const next = d.excludedExtras.filter(function (k) {
      return LEGACY.indexOf(k) < 0;
    });
    if (legacyExcluded.length === LEGACY.length && next.indexOf(PKG_AERIAL_EXTRA) < 0) {
      next.push(PKG_AERIAL_EXTRA);
    }
    d.excludedExtras = next;
  }
}

function migrateLegacyPkgCoverage(d) {
  if (!d) return;
  if (d.coverageByFunction && Object.keys(d.coverageByFunction).length) {
    ensurePkgCoverageByFunction(d);
    return;
  }
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  const template = {
    coverageSide: d.coverageSide || 'both',
    duration: d.duration || 'Full Day',
    extraHour: d.extraHour != null ? d.extraHour : 5000,
    photoTypes: d.photoTypes
      ? JSON.parse(JSON.stringify(d.photoTypes))
      : defaultFnCoverage(fns[0]).photoTypes,
    videoTypes: d.videoTypes
      ? JSON.parse(JSON.stringify(d.videoTypes))
      : defaultFnCoverage(fns[0]).videoTypes,
  };
  d.coverageByFunction = {};
  fns.forEach(function (fn) {
    d.coverageByFunction[fn] = defaultFnCoverage(fn, template);
    if (fnIsCoupleShoot(fn)) {
      d.coverageByFunction[fn].duration = 'Up to 5 Hours';
      d.coverageByFunction[fn].coverageSide = 'single';
    }
  });
}

function ensurePkgCoverageByFunction(d) {
  if (!d.coverageByFunction) d.coverageByFunction = {};
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  fns.forEach(function (fn) {
    if (!d.coverageByFunction[fn]) d.coverageByFunction[fn] = defaultFnCoverage(fn);
    const block = d.coverageByFunction[fn];
    allPhotoTypes(d).forEach(function (label) {
      if (!block.photoTypes[label]) block.photoTypes[label] = { on: false, qty: 0 };
    });
    allVideoTypes(d).forEach(function (label) {
      if (!block.videoTypes[label]) block.videoTypes[label] = { on: false, qty: 0 };
    });
  });
  Object.keys(d.coverageByFunction).forEach(function (fn) {
    if (fns.indexOf(fn) < 0) delete d.coverageByFunction[fn];
  });
}

function pkgFnCoverage(d, fnName) {
  ensurePkgCoverageByFunction(d);
  return d.coverageByFunction[fnName];
}

function newPkgDraftFinalize(d) {
  if (!d.coverageByFunction) d.coverageByFunction = {};
  (d.functions || []).forEach(function (fn) {
    if (!d.coverageByFunction[fn]) d.coverageByFunction[fn] = defaultFnCoverage(fn);
  });
  return d;
}

function newPkgDraft() {
  const d = {
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
    coverageSide: 'both',
    customCeremonies: [],
    ceremonyTypes: ['Hindu'],
    customPhotoTypes: [],
    customVideoTypes: [],
    coverageByFunction: {},
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
    albumPrints: albumPrintsAllOff(),
    deliveryMap: {},
    paymentStages: cloneDefaultPaymentStages(),
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
    requirements: ['Customer provides SSD / Hard Disk', 'Electricity / Power at venue'],
    customRequirements: [],
    shootUnlimitedClicks: false,
    equipmentNote: '',
    qualityNote: '',
  };
  newPkgDraftFinalize(d);
  ensurePkgMarketingFields(d);
  return d;
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

function readExtrasFieldsFromDom(d) {
  if (!d.extras) d.extras = {};
  document.querySelectorAll('.extra-row').forEach(function (row) {
    const name = row.getAttribute('data-extra-name');
    if (!name) return;
    const modeEl = row.querySelector('[data-extra-mode]');
    if (!modeEl) return;
    const mode = modeEl.value;
    const priceEl = row.querySelector('[data-extra-price]');
    const basisEl = row.querySelector('[data-extra-basis]');
    const prev = d.extras[name] || {};
    if (mode === 'included') {
      const price =
        priceEl && priceEl.value !== '' ? +(priceEl.value || 0) : prev.price != null ? prev.price : 0;
      const basis = basisEl && basisEl.value ? basisEl.value : prev.basis || 'Per Event';
      const rowData = { mode: 'included', price: price, basis: basis };
      readExtraHourlyFieldsFromRow(row, rowData, prev);
      d.extras[name] = rowData;
    } else {
      const rowData = {
        mode: 'extra',
        price: +(priceEl && priceEl.value !== '' ? priceEl.value : prev.price != null ? prev.price : 0),
        basis: basisEl && basisEl.value ? basisEl.value : prev.basis || 'Per Event',
      };
      readExtraHourlyFieldsFromRow(row, rowData, prev);
      d.extras[name] = rowData;
    }
  });
}

function renderWizardExtrasStep(d, namesFn, addLinkLabel) {
  if (!d.extras) d.extras = {};
  return (
    '<div id="f_extraRows">' +
    namesFn(d)
      .map(function (name) {
        const x = d.extras[name] || {
          mode: 'extra',
          price: 0,
          basis: 'Per Event',
          hourlyLimit: false,
          includedHours: 4,
          extraHour: 0,
        };
        const modeCls = x.mode === 'included' ? 'mode-included' : 'mode-extra';
        const hourlyCls = x.mode === 'included' && x.hourlyLimit ? ' hourly-on' : '';
        return (
          '<div class="extra-row ' +
          modeCls +
          hourlyCls +
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
          '" title="Remove service" aria-label="Remove service">🗑</button>' +
          extraIncludedHourlyFields(x) +
          '</div>'
        );
      })
      .join('') +
    '</div>' +
    linkAdd('add-extra', addLinkLabel || 'Add New Service')
  );
}

function handleExtraModeSelectChange(e, d) {
  const t = e.target;
  if (!t.matches('[data-extra-mode]')) return false;
  const row = t.closest('.extra-row');
  if (!row) return false;
  const mode = t.value;
  const name = row.getAttribute('data-extra-name');
  if (!name) return false;
  if (!d.extras) d.extras = {};
  const priceEl = row.querySelector('[data-extra-price]');
  const basisEl = row.querySelector('[data-extra-basis]');
  const prev = d.extras[name] || {};
  if (mode === 'included') {
    d.extras[name] = {
      mode: 'included',
      price: priceEl ? +(priceEl.value || 0) : prev.price != null ? prev.price : 0,
      basis: basisEl ? basisEl.value : prev.basis || 'Per Event',
      hourlyLimit: prev.hourlyLimit != null ? prev.hourlyLimit : false,
      includedHours: prev.includedHours != null ? prev.includedHours : 4,
      extraHour: prev.extraHour != null ? prev.extraHour : 0,
    };
    readExtraHourlyFieldsFromRow(row, d.extras[name], prev);
  } else {
    const price = prev.price != null ? prev.price : +(priceEl && priceEl.value ? priceEl.value : 0);
    const basis = prev.basis || (basisEl ? basisEl.value : 'Per Event');
    d.extras[name] = {
      mode: 'extra',
      price: price,
      basis: basis,
      hourlyLimit: prev.hourlyLimit,
      includedHours: prev.includedHours,
      extraHour: prev.extraHour,
    };
    if (priceEl) priceEl.value = String(price);
    if (basisEl) basisEl.value = basis;
  }
  applyExtraRowMode(row, mode);
  row.classList.toggle('hourly-on', mode === 'included' && d.extras[name].hourlyLimit);
  return true;
}

function handleExtraHourlyCheckboxChange(e) {
  const t = e.target;
  if (!t.matches('[data-extra-hourly-on]')) return false;
  const row = t.closest('.extra-row');
  if (row) row.classList.toggle('hourly-on', t.checked);
  return true;
}

function runExtraWizardAction(act, t, d, readFields, presetNames) {
  const presets = presetNames || [];
  if (act === 'add-extra') {
    const name = prompt('Service name');
    if (name) {
      const trimmed = name.trim();
      if (!trimmed) return true;
      if (!d.customExtras) d.customExtras = [];
      if (!d.extras) d.extras = {};
      d.customExtras.push({ name: trimmed });
      d.extras[trimmed] = {
        mode: 'extra',
        price: 5000,
        basis: 'Per Event',
        hourlyLimit: false,
        includedHours: 4,
        extraHour: 0,
      };
      if (d.excludedExtras) {
        d.excludedExtras = d.excludedExtras.filter(function (x) {
          return x !== trimmed;
        });
      }
      renderWizardBody();
    }
    return true;
  }
  if (act === 'remove-extra') {
    const extraName = t.getAttribute('data-extra-name');
    if (!extraName) return true;
    readFields(d);
    delete d.extras[extraName];
    d.customExtras = (d.customExtras || []).filter(function (x) {
      return x.name !== extraName;
    });
    if (!d.excludedExtras) d.excludedExtras = [];
    if (presets.indexOf(extraName) >= 0 && d.excludedExtras.indexOf(extraName) < 0) {
      d.excludedExtras.push(extraName);
    }
    renderWizardBody();
    return true;
  }
  return false;
}
function allPhotoTypes(d) {
  return PHOTO_TYPE_DEFAULTS.concat(d.customPhotoTypes || []);
}
function allVideoTypes(d) {
  return VIDEO_TYPE_DEFAULTS.concat(d.customVideoTypes || []);
}

function qtyStepper(field, val, disabled, covFn) {
  val = Math.max(0, +val || 0);
  return (
    '<div class="qty-step' +
    (disabled ? ' off' : '') +
    '" data-qty-field="' +
    field +
    '"' +
    (covFn ? ' data-cov-fn="' + esc(covFn) + '"' : '') +
    '><button type="button" data-qty-d="-1"' +
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

function customDeliverableDelBtn(action, name) {
  return (
    '<button type="button" class="del-card-remove" data-action="' +
    action +
    '" data-del-name="' +
    esc(name) +
    '" title="Remove custom type" aria-label="Remove">🗑</button>'
  );
}

function isCustomPhotoDeliverable(d, name) {
  return (d.customDeliverPhoto || []).indexOf(name) >= 0;
}

function isCustomVideoDeliverable(d, name) {
  return (d.customDeliverVideo || []).indexOf(name) >= 0;
}

function isCustomDigitalDeliverable(d, id) {
  return (d.customDeliverDigital || []).indexOf(id) >= 0;
}

function isCustomAlbumPrint(d, name) {
  return ALBUM_PRINT_TYPES.indexOf(name) < 0;
}

function removeCustomDeliverable(d, kind, name) {
  if (!name) return;
  if (kind === 'photo') {
    d.customDeliverPhoto = (d.customDeliverPhoto || []).filter(function (x) {
      return x !== name;
    });
    d.deliverPhoto = (d.deliverPhoto || []).filter(function (x) {
      return x !== name;
    });
    if (d.photoDetails) delete d.photoDetails[name];
    if (d.deliveryMap) delete d.deliveryMap[name];
  } else if (kind === 'video') {
    d.customDeliverVideo = (d.customDeliverVideo || []).filter(function (x) {
      return x !== name;
    });
    d.deliverVideo = (d.deliverVideo || []).filter(function (x) {
      return x !== name;
    });
    if (d.videoDetails) delete d.videoDetails[name];
    if (d.deliveryMap) delete d.deliveryMap[name];
  } else if (kind === 'digital') {
    d.customDeliverDigital = (d.customDeliverDigital || []).filter(function (x) {
      return x !== name;
    });
    d.deliverDigital = (d.deliverDigital || []).filter(function (x) {
      return x !== name;
    });
    if (d.deliveryMap) delete d.deliveryMap[name];
  } else if (kind === 'album') {
    if (d.albumPrints) delete d.albumPrints[name];
    if (d.deliveryMap) delete d.deliveryMap[name];
  }
}

function renderPhotoDeliverTab(d) {
  ensurePkgMarketingFields(d);
  const items = PHOTO_DELIVER.concat(d.customDeliverPhoto || []);
  return (
    '<p class="del-sec-title">Photography deliverables</p><p class="sub">Select the types of photos to be delivered.</p>' +
    '<label class="chk-row' +
    (d.shootUnlimitedClicks ? ' on' : '') +
    '" style="margin-bottom:12px"><input type="checkbox" id="f_unlimitedClicks" ' +
    (d.shootUnlimitedClicks ? 'checked' : '') +
    '> Unlimited clicks during shoot</label>' +
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
          '</p></div>' +
          (isCustomPhotoDeliverable(d, name) ? customDeliverableDelBtn('remove-del-photo', name) : '') +
          '</div>' +
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
          qty: 1,
          duration: VIDEO_DURATIONS[0],
          format: VIDEO_FORMATS[0],
          delivery: '15 Working Days',
        };
        if (det.qty == null || det.qty < 1) det.qty = 1;
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
          '</p></div>' +
          (isCustomVideoDeliverable(d, name) ? customDeliverableDelBtn('remove-del-video', name) : '') +
          '</div>' +
          (on
            ? '<div class="del-fields">' +
              '<div class="fld"><label>Quantity</label><input type="number" min="1" data-video-qty="' +
              esc(name) +
              '" value="' +
              det.qty +
              '"></div>' +
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

function albumPrintThumbIcon(name) {
  if (name === 'Photo Album') return '📕';
  if (name === 'Calendar') return '🗓️';
  if (name === 'Mini Album') return '📔';
  if (name === 'Photo Frame') return '🖼️';
  return '🖼️';
}

function renderAlbumPrintCard(name, d) {
  if (!d.albumPrints) d.albumPrints = defaultAlbumPrints();
  const row = d.albumPrints[name] || { on: false };
  const on = !!row.on;
  const isComplimentaryType = COMPLIMENTARY_PRINT_TYPES.indexOf(name) >= 0;
  if (isComplimentaryType && row.complimentary == null) row.complimentary = true;
  let fields = '';
  if (on && name === 'Photo Album') {
    fields =
      '<div class="del-fields">' +
      '<div class="fld"><label>Pages</label><input type="number" data-album-pages value="' +
      (row.pages || 40) +
      '"></div>' +
      '<div class="fld"><label>Size</label><select data-album-size><option' +
      ((row.size || '').indexOf('12') >= 0 ? ' selected' : '') +
      '>12 x 18 inch</option><option>10 x 12 inch</option></select></div>' +
      '<div class="fld"><label>Cover type</label><select data-album-cover><option' +
      (row.cover === 'Premium' ? ' selected' : '') +
      '>Premium</option><option>Standard</option></select></div>' +
      renderAlbumPageFinishField(row) +
      '</div>';
  } else if (on) {
    fields =
      '<div class="del-fields">' +
      '<div class="fld"><label>Quantity</label><input type="number" data-album-qty value="' +
      (row.qty || 1) +
      '"></div>' +
      '<div class="fld"><label>Size</label><select data-album-size-' +
      esc(name) +
      '><option>A3</option><option>A4</option><option>6 x 6 inch</option><option>12 x 18 inch</option></select></div>' +
      '<div class="fld"><label>Type</label><select data-album-type-opt><option>Wall Calendar</option><option>Desk Calendar</option><option>Acrylic</option><option>Standard</option></select></div>' +
      (name === 'Mini Album' ? renderAlbumPageFinishField(row) : '') +
      (isComplimentaryType ? albumComplimentaryField(row) : '') +
      '</div>';
  }
  return (
    '<div class="del-card' +
    (on ? ' on' : '') +
    '"><div class="del-card-hd"><label class="del-chk"><input type="checkbox" data-album-type="' +
    esc(name) +
    '" ' +
    (on ? 'checked' : '') +
    '></label><div class="del-thumb">' +
    albumPrintThumbIcon(name) +
    '</div><div class="del-meta"><b>' +
    esc(name) +
    '</b></div>' +
    (isCustomAlbumPrint(d, name) ? customDeliverableDelBtn('remove-del-album', name) : '') +
    '</div>' +
    fields +
    '</div>'
  );
}

function renderAlbumsPrintsTab(d) {
  if (!d.albumPrints) d.albumPrints = defaultAlbumPrints();
  const custom = Object.keys(d.albumPrints).filter(function (name) {
    return ALBUM_PRINT_TYPES.indexOf(name) < 0;
  });
  const items = ALBUM_PRINT_TYPES.concat(custom);
  return (
    '<p class="del-sec-title">Albums &amp; prints</p><p class="sub">Select albums and printed materials.</p>' +
    '<div class="del-album-list">' +
    items
      .map(function (name) {
        return renderAlbumPrintCard(name, d);
      })
      .join('') +
    '</div>' +
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
        const row =
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
          '</span></span></label>';
        if (!isCustomDigitalDeliverable(d, item.id)) return row;
        return (
          '<div class="dig-row-wrap">' +
          row +
          customDeliverableDelBtn('remove-del-digital', item.id) +
          '</div>'
        );
      })
      .join('') +
    linkAdd('add-ddigital', 'Add Custom Delivery Option')
  );
}

function ensureDeliverableDraft(d) {
  if (d.deliverTab === 'complimentary') d.deliverTab = 'albums';
  if (!d.deliverTab) d.deliverTab = 'photos';
  if (!d.deliverPhoto) d.deliverPhoto = [];
  if (!d.deliverVideo) d.deliverVideo = [];
  if (!d.deliverDigital) d.deliverDigital = [];
  if (!d.customDeliverPhoto) d.customDeliverPhoto = [];
  if (!d.customDeliverVideo) d.customDeliverVideo = [];
  if (!d.customDeliverDigital) d.customDeliverDigital = [];
  if (!d.photoDetails) d.photoDetails = defaultPhotoDetails();
  if (!d.videoDetails) d.videoDetails = defaultVideoDetails();
  if (!d.albumPrints) d.albumPrints = defaultAlbumPrints();
  if (!d.deliveryMap) d.deliveryMap = {};
}

function ensureServiceDeliverableModel(d) {
  if (d.inclPhoto || d.inclVideo || d.inclDigital || (d.inclAlbums && d.inclAlbums.length)) {
    d.deliverTab = d.deliverTab || 'photos';
    d.deliverPhoto = (d.inclPhoto || []).map(function (x) {
      return x === 'High-Resolution Photos' ? 'Colour-Graded Photos' : x;
    });
    d.deliverVideo = [];
    (d.inclVideo || []).forEach(function (x) {
      let mapped = x;
      if (x === 'Full Video') mapped = 'Full-Length Video';
      if (x === 'Reel (1 Minute)') mapped = 'Reel';
      if (VIDEO_DELIVER.indexOf(mapped) >= 0) d.deliverVideo.push(mapped);
      else {
        if (!d.customDeliverVideo) d.customDeliverVideo = [];
        if (d.customDeliverVideo.indexOf(mapped) < 0) d.customDeliverVideo.push(mapped);
        if (d.deliverVideo.indexOf(mapped) < 0) d.deliverVideo.push(mapped);
      }
    });
    d.deliverDigital = (d.inclDigital || []).slice();
    d.customDeliverPhoto = (d.customInclPhoto || []).slice();
    if (!d.customDeliverVideo) d.customDeliverVideo = [];
    (d.customInclVideo || []).forEach(function (x) {
      if (d.customDeliverVideo.indexOf(x) < 0) d.customDeliverVideo.push(x);
      if (d.deliverVideo.indexOf(x) < 0) d.deliverVideo.push(x);
    });
    d.customDeliverDigital = (d.customInclDigital || []).slice();
    d.photoDetails = Object.assign(defaultPhotoDetails(), d.photoDetails || {});
    d.videoDetails = Object.assign(defaultVideoDetails(), d.videoDetails || {});
    d.albumPrints = Object.assign(defaultAlbumPrints(), d.albumPrints || {});
    (d.inclAlbums || []).forEach(function (name) {
      if (!d.albumPrints[name]) d.albumPrints[name] = defaultAlbumPrints()[name] || { on: false };
      d.albumPrints[name].on = true;
    });
    delete d.inclPhoto;
    delete d.inclVideo;
    delete d.inclDigital;
    delete d.inclAlbums;
    delete d.customInclPhoto;
    delete d.customInclVideo;
    delete d.customInclDigital;
  }
  ensureDeliverableDraft(d);
}

function renderDeliverablesCoverageHint(d) {
  if (typeof wiz !== 'undefined' && wiz.mode && wiz.mode !== 'package') return '';
  if (!pkgNeedsCoverageSideUi(d)) return '';
  const side = resolvePkgCoverageSide(d);
  const label = side === 'both' ? 'Both sides' : 'Single side';
  const msg =
    side === 'both'
      ? 'The same deliverables listed below (photos, albums, calendars, digital, etc.) are shared with both families.'
      : 'Deliverables apply to the one side / family covered by this package.';
  return (
    '<div class="warn-box deliverables-coverage-hint" style="margin-bottom:12px"><b>Deliverables (' +
    esc(label) +
    ')</b><p class="sub" style="margin:6px 0 0;line-height:1.45">' +
    esc(msg) +
    '</p></div>'
  );
}

function renderDeliverablesStep(d) {
  ensureDeliverableDraft(d);
  const tab = d.deliverTab || 'photos';
  let body = '';
  if (tab === 'photos') body = renderPhotoDeliverTab(d);
  else if (tab === 'videos') body = renderVideoDeliverTab(d);
  else if (tab === 'albums') body = renderAlbumsPrintsTab(d);
  else body = renderDigitalDeliverTab(d);
  return renderDeliverablesCoverageHint(d) + renderDelTabs(tab) + body;
}

function readAlbumFieldsFromDom(d) {
  if (!d.albumPrints) d.albumPrints = defaultAlbumPrints();
  document.querySelectorAll('input[data-album-type]').forEach(function (chk) {
    const name = chk.getAttribute('data-album-type');
    if (!name) return;
    if (!d.albumPrints[name]) d.albumPrints[name] = defaultAlbumPrints()[name] || { on: false };
    d.albumPrints[name].on = chk.checked;
    const card = chk.closest('.del-card');
    if (!card) return;
    if (name === 'Photo Album') {
      const pages = card.querySelector('[data-album-pages]');
      const sizeSel = card.querySelector('[data-album-size]');
      const coverSel = card.querySelector('[data-album-cover]');
      if (pages) d.albumPrints[name].pages = +pages.value || 40;
      if (sizeSel) d.albumPrints[name].size = sizeSel.value;
      if (coverSel) d.albumPrints[name].cover = coverSel.value;
      readAlbumFinishFromCard(card, d.albumPrints[name]);
      const compA = card.querySelector('[data-album-complimentary]');
      if (compA) d.albumPrints[name].complimentary = compA.checked;
    } else {
      const qty = card.querySelector('[data-album-qty]');
      if (qty) d.albumPrints[name].qty = +qty.value || 1;
      const selects = card.querySelectorAll('.del-fields select');
      if (selects[0]) d.albumPrints[name].size = selects[0].value;
      if (selects[1]) d.albumPrints[name].type = selects[1].value;
      readAlbumFinishFromCard(card, d.albumPrints[name]);
      const compB = card.querySelector('[data-album-complimentary]');
      if (compB) d.albumPrints[name].complimentary = compB.checked;
    }
  });
}

function readDeliverableFieldsFromDom(d) {
  ensureDeliverableDraft(d);
  const unlimited = el('f_unlimitedClicks');
  if (unlimited) d.shootUnlimitedClicks = unlimited.checked;
  readAlbumFieldsFromDom(d);
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
    d.deliveryMap[k] = sel.value;
  });
  document.querySelectorAll('[data-video-qty]').forEach(function (inp) {
    const k = inp.getAttribute('data-video-qty');
    if (!d.videoDetails[k]) d.videoDetails[k] = {};
    d.videoDetails[k].qty = Math.max(1, +inp.value || 1);
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
}

function deliverableCheckboxChange(t, d) {
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
    return true;
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
    return true;
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
    return true;
  }
  if (t.matches('[data-album-type]')) {
    const name = t.getAttribute('data-album-type');
    if (!d.albumPrints[name]) d.albumPrints[name] = defaultAlbumPrints()[name] || { on: false };
    d.albumPrints[name].on = t.checked;
    if (!t.checked && d.deliveryMap) delete d.deliveryMap[name];
    renderWizardBody();
    return true;
  }
  return false;
}

function runDeliverableWizardAction(act, t, d, readFields) {
  ensureDeliverableDraft(d);
  if (act === 'add-dphoto') {
    const name = prompt('Photo deliverable name');
    if (name) {
      d.customDeliverPhoto.push(name.trim());
      d.photoDetails[name.trim()] = { qty: 100, format: PHOTO_FORMATS[0], delivery: '5 Working Days' };
      renderWizardBody();
    }
    return true;
  }
  if (act === 'add-dvideo') {
    const name = prompt('Video deliverable name');
    if (name) {
      d.customDeliverVideo.push(name.trim());
      d.videoDetails[name.trim()] = {
        qty: 1,
        duration: VIDEO_DURATIONS[0],
        format: VIDEO_FORMATS[0],
        delivery: '15 Working Days',
      };
      renderWizardBody();
    }
    return true;
  }
  if (act === 'add-ddigital') {
    const name = prompt('Delivery option');
    if (name) {
      d.customDeliverDigital.push(name.trim());
      renderWizardBody();
    }
    return true;
  }
  if (act === 'add-album-print') {
    const name = prompt('Album / print type');
    if (name && !d.albumPrints[name]) {
      d.albumPrints[name] = { on: true, qty: 1, size: 'A4', type: 'Custom' };
      renderWizardBody();
    }
    return true;
  }
  if (act === 'remove-del-photo') {
    readFields(d);
    removeCustomDeliverable(d, 'photo', t.getAttribute('data-del-name'));
    renderWizardBody();
    return true;
  }
  if (act === 'remove-del-video') {
    readFields(d);
    removeCustomDeliverable(d, 'video', t.getAttribute('data-del-name'));
    renderWizardBody();
    return true;
  }
  if (act === 'remove-del-digital') {
    readFields(d);
    removeCustomDeliverable(d, 'digital', t.getAttribute('data-del-name'));
    renderWizardBody();
    return true;
  }
  if (act === 'remove-del-album') {
    readFields(d);
    removeCustomDeliverable(d, 'album', t.getAttribute('data-del-name'));
    renderWizardBody();
    return true;
  }
  return false;
}

function renderCoverageTypes(types, obj, prefix, fnName) {
  return types
    .map(function (label) {
      const row = obj[label] || { on: false, qty: 0 };
      obj[label] = row;
      const field = prefix + '.' + label;
      return (
        '<div class="cov-type' +
        (!row.on ? ' disabled' : '') +
        '"><label><input type="checkbox" data-cov-fn="' +
        esc(fnName) +
        '" data-cov-type="' +
        esc(field) +
        '" ' +
        (row.on ? 'checked' : '') +
        '> ' +
        esc(label) +
        '</label>' +
        qtyStepper(field, row.qty, !row.on, fnName) +
        '</div>'
      );
    })
    .join('');
}

function renderFnCoverageStep(d) {
  ensurePkgCoverageByFunction(d);
  const fns = d.functions.length ? d.functions : ['Wedding & Reception'];
  if (!d.coverageUiOpen) d.coverageUiOpen = {};
  let html =
    '<div class="fn-cov-stack">' +
    '<div class="fn-cov-toolbar">' +
    '<p class="sub"><b>' +
    fns.length +
    '</b> function' +
    (fns.length === 1 ? '' : 's') +
    ' — open each card, fill all fields, then tap Next</p>' +
    '<div class="fn-cov-toolbar-actions">' +
    '<button type="button" data-action="fn-cov-expand-all">Expand all</button>' +
    '<button type="button" data-action="fn-cov-collapse-all">Collapse all</button>' +
    '</div></div>';
  if (pkgNeedsCoverageSideUi(d)) {
    const pkgSide = resolvePkgCoverageSide(d);
    html +=
      '<div class="fld fn-cov-pkg-side"><label>Coverage side</label><p class="hint" style="margin:-2px 0 8px">Both sides: you cover both families; the same deliverables (album, calendar, photos, etc.) are for both parties.</p><div class="seg seg-full">' +
      '<button type="button" class="' +
      (pkgSide === 'single' ? 'on' : '') +
      '" data-pkg-cov-side="single">Single side</button>' +
      '<button type="button" class="' +
      (pkgSide === 'both' ? 'on' : '') +
      '" data-pkg-cov-side="both">Both sides</button></div></div>';
  }
  fns.forEach(function (fn, idx) {
    const c = pkgFnCoverage(d, fn);
    const open = d.coverageUiOpen[fn] === true;
    const hint = pkgFnHint(fn);
    const incomplete =
      d.coverageValidateHighlight && d.coverageValidateHighlight.indexOf(fn) >= 0;
    html +=
      '<div class="fn-cov-card' +
      (open ? '' : ' collapsed') +
      (incomplete ? ' fn-cov-incomplete' : '') +
      '" data-fn-name="' +
      esc(fn) +
      '">';
    html +=
      '<button type="button" class="fn-cov-toggle" data-action="toggle-fn-cov" aria-expanded="' +
      (open ? 'true' : 'false') +
      '">' +
      '<span class="fn-cov-idx">' +
      (idx + 1) +
      '</span>' +
      '<span class="fn-cov-titles"><b class="fn-cov-fn-title">' +
      esc(fn) +
      (hint ? ' <span class="fn-cov-desc">(' + esc(hint) + ')</span>' : '') +
      '</b><span class="fn-cov-summary">' +
      esc(fnCoverageChipSummary(c)) +
      '</span></span>' +
      '<span class="sec-chev" aria-hidden="true">›</span></button>';
    html += '<div class="fn-cov-body">';
    if (idx > 0) {
      html +=
        '<div class="fn-cov-actions"><button type="button" class="link-inline" data-action="copy-cov-from-prev" data-cov-fn="' +
        esc(fn) +
        '">Same coverage as ' +
        esc(fns[idx - 1]) +
        '</button></div>';
    }
    html +=
      '<div class="fld"><label>Coverage duration</label><select data-fn-duration>' +
      DURATION_OPTS.map(function (o) {
        return '<option' + (c.duration === o ? ' selected' : '') + '>' + o + '</option>';
      }).join('') +
      '</select></div>' +
      '<p class="hint fn-duration-hint" style="margin:-4px 0 12px">' +
      esc(coverageDurationHelp(c.duration)) +
      '</p>' +
      '<div class="fld"><label>Additional hour charge (₹) *</label><input type="number" data-fn-extra-hour min="0" step="500" required value="' +
      (c.extraHour != null && c.extraHour !== '' ? c.extraHour : '') +
      '"><span class="hint"> / hour beyond included duration (enter 0 if not offered)</span>' +
      '<p class="hint fn-extra-hint" style="margin:8px 0 0">' +
      esc(extraHourChargeHelp(c.duration)) +
      '</p></div>' +
      '<p class="lbl">Photography coverage</p>' +
      renderCoverageTypes(allPhotoTypes(d), c.photoTypes, 'photo', fn) +
      linkAdd('add-photo-type', 'Add New Photography Type') +
      '<p class="lbl">Videography coverage</p>' +
      renderCoverageTypes(allVideoTypes(d), c.videoTypes, 'video', fn) +
      linkAdd('add-video-type', 'Add New Videography Type') +
      '</div></div>';
  });
  html += '</div>';
  return html;
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
        '</textarea></div>' +
        '<details class="pkg-optional-details"><summary>Customer showcase (optional)</summary>' +
        '<p class="sub">Gear, editing, or quality notes shown on your public package page.</p>' +
        '<div class="fld"><label>Equipment &amp; gear</label><textarea id="f_equipmentNote" rows="3" placeholder="e.g. Sony A7 IV, GM lenses, Godox flashes…">' +
        esc(d.equipmentNote || '') +
        '</textarea></div>' +
        '<div class="fld"><label>Quality &amp; editing</label><textarea id="f_qualityNote" rows="3" placeholder="e.g. Colour grading on calibrated monitors, selection app…">' +
        esc(d.qualityNote || '') +
        '</textarea></div></details>'
      );
    case 1:
      return fnCheckList(d) + linkAdd('add-function', 'Add New Function');
    case 2:
      if (!needsCeremonyStep(d.functions)) {
        return (
          '<p class="sub">Not required for selected functions. Continue to coverage.</p>' +
          '<div class="warn-box">Ceremony type applies to Wedding &amp; Reception, Reception, or Engagement only (not couple shoots).</div>'
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
    case 3:
      return renderFnCoverageStep(d);
    case 4:
      return renderDeliverablesStep(d);
    case 5:
      return renderWizardExtrasStep(d, allExtrasNames);
    case 6: {
      const included = selectedDeliverableKeys(d);
      const keys = pkgDeliveryKeys(d);
      if (!included.length) {
        return (
          '<div class="hub-empty" style="margin:0">' +
          '<div class="hub-empty-ico">📦</div><b>No deliverables selected</b>' +
          '<p>Go back to the <b>Deliverables</b> step and check at least one photo, video, album, or digital option.</p></div>' +
          '<button type="button" class="btn btn-ghost" data-goto-step="4" style="margin-top:12px;width:100%">← Back to deliverables</button>'
        );
      }
      if (!keys.length) {
        return (
          '<p class="sub">Items such as <b>Live Streaming</b> are provided during the event. They stay in your package but do not need a post-event delivery timeline here.</p>' +
          '<div class="warn-box" style="margin-top:12px">Tap <b>Next</b> to continue.</div>'
        );
      }
      return (
        '<p class="sub">Set delivery timeline for each deliverable you selected (photos, videos, albums, digital).</p>' +
        keys
          .map(function (k) {
            return (
              '<div class="fld del-row"><label>' +
              esc(deliverableTimelineLabel(d, k)) +
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

function deliverablesForDeliveryStep(d) {
  return selectedDeliverableKeys(d).filter(function (k) {
    return DELIVERY_TIMELINE_SKIP.indexOf(k) < 0;
  });
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
  DELIVERY_TIMELINE_SKIP.forEach(function (k) {
    delete d.deliveryMap[k];
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
    if (DELIVERY_TIMELINE_SKIP.indexOf(name) >= 0) return;
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
  return deliverablesForDeliveryStep(d);
}

function readPkgWizardFields(d) {
  const g = function (id) {
    return el(id);
  };
  if (g('f_name')) d.name = g('f_name').value.trim();
  if (g('f_desc')) d.desc = g('f_desc').value.trim();
  if (g('f_equipmentNote')) d.equipmentNote = g('f_equipmentNote').value.trim();
  if (g('f_qualityNote')) d.qualityNote = g('f_qualityNote').value.trim();
  if (g('f_listPrice')) d.listPrice = +g('f_listPrice').value || 0;
  if (g('f_discountPct')) d.discountPct = +g('f_discountPct').value || 0;
  const discRad = document.querySelector('input[name="discYes"]:checked');
  if (discRad) d.discountYes = discRad.value;
  readPkgCoverageFieldsFromDom(d);
  readExtrasFieldsFromDom(d);
  readDeliverableFieldsFromDom(d);
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
  if (document.querySelector('.pay-stage-card')) {
    d.paymentStages = [];
    document.querySelectorAll('.pay-stage-card').forEach(function (row) {
      d.paymentStages.push({
        id: uid('ps'),
        label: row.querySelector('[data-pay-label]').value.trim() || 'Stage',
        pct: +(row.querySelector('[data-pay-pct]').value || 0),
      });
    });
  }
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

function pkgFnHint(fnName) {
  if (typeof FUNCTION_HINTS === 'undefined') return '';
  return FUNCTION_HINTS[fnName] || '';
}

function pkgCoverageTeamCounts(block) {
  let photo = 0;
  let video = 0;
  Object.keys(block.photoTypes || {}).forEach(function (k) {
    const r = block.photoTypes[k];
    if (r.on && r.qty) photo += r.qty;
  });
  Object.keys(block.videoTypes || {}).forEach(function (k) {
    const r = block.videoTypes[k];
    if (r.on && r.qty) video += r.qty;
  });
  return { photo: photo, video: video };
}

function pkgCoverageFnIsComplete(block) {
  if (!block || !block.duration) return false;
  if (block.extraHour === '' || block.extraHour == null || isNaN(+block.extraHour)) return false;
  const team = pkgCoverageTeamCounts(block);
  if (team.photo < 1 && team.video < 1) return false;
  return true;
}

function pkgCoverageMissingFunctions(d) {
  ensurePkgCoverageByFunction(d);
  const fns = d.functions && d.functions.length ? d.functions : [];
  const missing = [];
  fns.forEach(function (fn) {
    if (!pkgCoverageFnIsComplete(d.coverageByFunction[fn])) missing.push(fn);
  });
  return missing;
}

function fnCoverageChipSummary(block) {
  let photo = 0;
  let video = 0;
  Object.keys(block.photoTypes || {}).forEach(function (k) {
    const r = block.photoTypes[k];
    if (r.on && r.qty) photo += r.qty;
  });
  Object.keys(block.videoTypes || {}).forEach(function (k) {
    const r = block.videoTypes[k];
    if (r.on && r.qty) video += r.qty;
  });
  const parts = [block.duration || '—'];
  if (block.extraHour > 0) parts.push('+' + inr(block.extraHour) + '/hr');
  else parts.push('no extra hr');
  parts.push(photo + ' photographer' + (photo === 1 ? '' : 's'));
  parts.push(video + ' video');
  return parts.join(' · ');
}

function readFnCoverageUiOpen(d) {
  if (!d.coverageUiOpen) d.coverageUiOpen = {};
  document.querySelectorAll('.fn-cov-card').forEach(function (card) {
    const fn = card.getAttribute('data-fn-name');
    if (!fn) return;
    d.coverageUiOpen[fn] = !card.classList.contains('collapsed');
  });
}

function readPkgCoverageFieldsFromDom(d) {
  readFnCoverageUiOpen(d);
  const pkgSideOn = document.querySelector('.fn-cov-pkg-side [data-pkg-cov-side].on');
  if (pkgSideOn) applyPkgCoverageSide(d, pkgSideOn.getAttribute('data-pkg-cov-side'));
  document.querySelectorAll('.fn-cov-card').forEach(function (card) {
    const fn = card.getAttribute('data-fn-name');
    if (!fn) return;
    const block = pkgFnCoverage(d, fn);
    const dur = card.querySelector('[data-fn-duration]');
    if (dur) block.duration = dur.value;
    const ex = card.querySelector('[data-fn-extra-hour]');
    if (ex) block.extraHour = +ex.value || 0;
  });
}

function refreshFnCoverageCardSummary(card, d) {
  if (!card) return;
  const fn = card.getAttribute('data-fn-name');
  if (!fn) return;
  readPkgCoverageFieldsFromDom(d);
  const block = pkgFnCoverage(d, fn);
  const sum = card.querySelector('.fn-cov-summary');
  if (sum) sum.textContent = fnCoverageChipSummary(block);
}

function pkgCoverageFnSummary(block) {
  const photo = [];
  Object.keys(block.photoTypes || {}).forEach(function (k) {
    const r = block.photoTypes[k];
    if (r.on && r.qty) photo.push(k.split(' ')[0] + '×' + r.qty);
  });
  const video = [];
  Object.keys(block.videoTypes || {}).forEach(function (k) {
    const r = block.videoTypes[k];
    if (r.on && r.qty) video.push(k.split(' ')[0] + '×' + r.qty);
  });
  return (
    block.duration +
    (block.extraHour > 0 ? ' · extra hr ' + inr(block.extraHour) : '') +
    ' · P:' +
    (photo.join(',') || '—') +
    ' · V:' +
    (video.join(',') || '—')
  );
}

function pkgCoverageSummary(d) {
  migrateLegacyPkgCoverage(d);
  ensurePkgCoverageByFunction(d);
  const fns = d.functions && d.functions.length ? d.functions : ['Wedding & Reception'];
  const parts = fns.map(function (fn) {
    const block = d.coverageByFunction[fn];
    if (!block) return fn + ': —';
    const shortFn = fn.length > 22 ? fn.slice(0, 20) + '…' : fn;
    return shortFn + ': ' + pkgCoverageFnSummary(block);
  });
  return parts.join(' | ');
}

function pkgDeliverSummary(d) {
  ensurePkgMarketingFields(d);
  const albums = [];
  if (d.albumPrints) {
    ALBUM_PRINT_TYPES.forEach(function (name) {
      if (d.albumPrints[name] && d.albumPrints[name].on) {
        if (name === 'Photo Album' && d.albumPrints[name].pages) {
          albums.push(
            d.albumPrints[name].pages + 'pg album (' + albumPageFinishSummaryText(d.albumPrints[name]) + ')'
          );
        } else if (name === 'Mini Album') {
          albums.push(name + ' (' + albumPageFinishSummaryText(d.albumPrints[name]) + ')');
        } else albums.push(name);
      }
    });
  }
  let s =
    (d.deliverPhoto || []).join(', ') +
    ' | Video: ' +
    formatVideoDeliverSummary(d) +
    (albums.length ? ' | ' + albums.join(', ') : '') +
    ' | Digital: ' +
    (d.deliverDigital || []).join(', ');
  if (d.shootUnlimitedClicks) s += ' | Unlimited clicks';
  const complimentary = [];
  if (d.albumPrints) {
    ALBUM_PRINT_TYPES.forEach(function (name) {
      const row = d.albumPrints[name];
      if (row && row.on && row.complimentary) complimentary.push(name);
    });
  }
  if (complimentary.length) s += ' | Complimentary: ' + complimentary.join(', ');
  return s;
}

function setCovTypeField(d, covFn, field, on, qty) {
  const parts = field.split('.');
  const kind = parts[0];
  const label = parts.slice(1).join('.');
  const block = pkgFnCoverage(d, covFn);
  const bucket = kind === 'photo' ? block.photoTypes : block.videoTypes;
  if (!bucket[label]) bucket[label] = { on: false, qty: 0 };
  bucket[label].on = on;
  bucket[label].qty = qty;
}

function updateFnCoverageHints(card, d) {
  if (!card) return;
  const dur = card.querySelector('[data-fn-duration]');
  const dh = card.querySelector('.fn-duration-hint');
  const eh = card.querySelector('.fn-extra-hint');
  const val = dur ? dur.value : 'Full Day';
  if (dh) dh.textContent = coverageDurationHelp(val);
  if (eh) eh.textContent = extraHourChargeHelp(val);
  if (d) refreshFnCoverageCardSummary(card, d);
}

function syncAllFnCoverageHints(d) {
  document.querySelectorAll('.fn-cov-card').forEach(function (card) {
    updateFnCoverageHints(card, d);
  });
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
      if (act === 'toggle-fn-cov') {
        const card = t.closest('.fn-cov-card');
        if (!card) return;
        readPkgCoverageFieldsFromDom(d);
        const fn = card.getAttribute('data-fn-name');
        const willOpen = card.classList.contains('collapsed');
        if (!d.coverageUiOpen) d.coverageUiOpen = {};
        d.coverageUiOpen[fn] = willOpen;
        card.classList.toggle('collapsed', !willOpen);
        const btn = card.querySelector('.fn-cov-toggle');
        if (btn) btn.setAttribute('aria-expanded', willOpen ? 'true' : 'false');
        refreshFnCoverageCardSummary(card, d);
        return;
      }
      if (act === 'fn-cov-expand-all') {
        readPkgCoverageFieldsFromDom(d);
        if (!d.coverageUiOpen) d.coverageUiOpen = {};
        (d.functions.length ? d.functions : ['Wedding & Reception']).forEach(function (fn) {
          d.coverageUiOpen[fn] = true;
        });
        renderWizardBody();
        return;
      }
      if (act === 'fn-cov-collapse-all') {
        readPkgCoverageFieldsFromDom(d);
        if (!d.coverageUiOpen) d.coverageUiOpen = {};
        (d.functions.length ? d.functions : ['Wedding & Reception']).forEach(function (fn) {
          d.coverageUiOpen[fn] = false;
        });
        renderWizardBody();
        return;
      }
      if (act === 'copy-cov-from-prev') {
        readPkgCoverageFieldsFromDom(d);
        const fn = t.getAttribute('data-cov-fn');
        const fns = d.functions.length ? d.functions : ['Wedding & Reception'];
        const idx = fns.indexOf(fn);
        if (idx > 0 && d.coverageByFunction[fns[idx - 1]]) {
          d.coverageByFunction[fn] = JSON.parse(JSON.stringify(d.coverageByFunction[fns[idx - 1]]));
          if (!d.coverageUiOpen) d.coverageUiOpen = {};
          d.coverageUiOpen[fn] = true;
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-photo-type') {
        const name = prompt('Photography type');
        if (name && d.customPhotoTypes.indexOf(name) < 0) {
          const label = name.trim();
          d.customPhotoTypes.push(label);
          ensurePkgCoverageByFunction(d);
          Object.keys(d.coverageByFunction).forEach(function (fn) {
            d.coverageByFunction[fn].photoTypes[label] = { on: true, qty: 1 };
          });
          renderWizardBody();
        }
        return;
      }
      if (act === 'add-video-type') {
        const name = prompt('Videography type');
        if (name && d.customVideoTypes.indexOf(name) < 0) {
          const label = name.trim();
          d.customVideoTypes.push(label);
          ensurePkgCoverageByFunction(d);
          Object.keys(d.coverageByFunction).forEach(function (fn) {
            d.coverageByFunction[fn].videoTypes[label] = { on: true, qty: 1 };
          });
          renderWizardBody();
        }
        return;
      }
      if (runExtraWizardAction(act, t, d, readPkgWizardFields, PKG_EXTRA_DEFAULTS)) return;
      if (runDeliverableWizardAction(act, t, d, readPkgWizardFields)) return;
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
      if (act === 'cr-policy-tab') {
        onCrPolicyTab(d, readPkgWizardFields, t.getAttribute('data-tab'));
        return;
      }
      if (act === 'cr-policy-add-tier') {
        onCrPolicyAddTier(d, readPkgWizardFields, t.getAttribute('data-policy'));
        return;
      }
      if (act === 'cr-policy-del-tier') {
        onCrPolicyDelTier(d, readPkgWizardFields, t);
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
    const pkgSideBtn = e.target.closest('[data-pkg-cov-side]');
    if (pkgSideBtn) {
      applyPkgCoverageSide(d, pkgSideBtn.getAttribute('data-pkg-cov-side'));
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
      const covFn = wrap.getAttribute('data-cov-fn');
      if (!covFn) return;
      setCovTypeField(d, covFn, field, true, v);
      refreshFnCoverageCardSummary(wrap.closest('.fn-cov-card'), d);
      return;
    }
  };
  body.onchange = function (e) {
    const t = e.target;
    if (t.matches('[data-album-finish-policy]')) {
      readPkgWizardFields(d);
      renderWizardBody();
      return;
    }
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
      ensurePkgCoverageByFunction(d);
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
      const covFn = t.getAttribute('data-cov-fn');
      if (!covFn) return;
      const parts = field.split('.');
      const label = parts.slice(1).join('.');
      const block = pkgFnCoverage(d, covFn);
      const bucket = parts[0] === 'photo' ? block.photoTypes : block.videoTypes;
      if (!bucket[label]) bucket[label] = { on: false, qty: 0 };
      bucket[label].on = t.checked;
      if (t.checked && !bucket[label].qty) bucket[label].qty = 1;
      refreshFnCoverageCardSummary(t.closest('.fn-cov-card'), d);
      renderWizardBody();
      return;
    }
    if (t.matches('[data-fn-duration]')) {
      updateFnCoverageHints(t.closest('.fn-cov-card'), d);
      return;
    }
    if (t.matches('[data-fn-extra-hour]')) {
      refreshFnCoverageCardSummary(t.closest('.fn-cov-card'), d);
      return;
    }
    if (deliverableCheckboxChange(t, d)) return;
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
    if (handleExtraModeSelectChange(e, d)) return;
    if (handleExtraHourlyCheckboxChange(e)) return;
  };
  document.querySelectorAll('[data-fn-duration]').forEach(function (sel) {
    sel.onchange = function () {
      updateFnCoverageHints(sel.closest('.fn-cov-card'), d);
    };
  });
  document.querySelectorAll('[data-fn-extra-hour]').forEach(function (inp) {
    inp.oninput = function () {
      refreshFnCoverageCardSummary(inp.closest('.fn-cov-card'), d);
    };
  });
  syncAllFnCoverageHints(d);
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
  if (wiz.step === 5) syncAllExtraRowModes();
}
