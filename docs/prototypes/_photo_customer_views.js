/** Render owner-shaped package/service data for customer screens. */

function custEsc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function custInr(n) {
  return '₹ ' + Number(n || 0).toLocaleString('en-IN');
}

function custChips(items) {
  return (
    '<div class="area-tags">' +
    items
      .map(function (x) {
        return '<span>' + custEsc(x) + '</span>';
      })
      .join('') +
    '</div>'
  );
}

function custKvRows(rows) {
  return rows
    .map(function (r) {
      return '<div class="kv-row"><span>' + custEsc(r.k) + '</span><b>' + custEsc(r.v) + '</b></div>';
    })
    .join('');
}

function custTeamLines(types) {
  const lines = [];
  Object.keys(types || {}).forEach(function (label) {
    const t = types[label];
    if (t && t.on && t.qty > 0) lines.push(t.qty + '× ' + label);
  });
  return lines;
}

function custFnIsCoupleShoot(fnName) {
  return /shoot/i.test(String(fnName || ''));
}

function custRenderPkgBasics(pkg) {
  let html =
    '<p style="font-size:13px;font-weight:600;color:var(--mut);line-height:1.5;margin:0 0 12px">' +
    custEsc(pkg.desc) +
    '</p>';
  html += '<div class="cust-hd">Package level</div>' + custChips([pkg.level]);
  html += '<div class="cust-hd">Ceremony types</div>' + custChips(pkg.ceremonyTypes || []);
  html += '<div class="cust-hd">Functions covered</div>' + custChips(pkg.functions || []);
  if (pkg.equipmentNote) {
    html += '<div class="cust-hd">Equipment</div><p class="sub">' + custEsc(pkg.equipmentNote) + '</p>';
  }
  if (pkg.qualityNote) {
    html += '<div class="cust-hd">Quality</div><p class="sub">' + custEsc(pkg.qualityNote) + '</p>';
  }
  return html;
}

const CUST_SVC_CATEGORY_LABELS = {
  portrait: 'Portrait Photography',
  baby: 'Baby & Kids',
  maternity: 'Maternity',
  newborn: 'Newborn',
  couple: 'Couple',
  funeral: 'Funeral / Memorial',
  product: 'Product',
  corporate: 'Corporate',
  realestate: 'Real Estate',
  event: 'Event / Get-togethers',
  fashion: 'Fashion & Portfolio',
  food: 'Food',
  commercial: 'Commercial',
  drone: 'Drone / Helicam',
  reel: 'Reel & Short Video',
  production: 'Photo & Video Production',
};

function custServiceCategoryLabel(categoryId) {
  return CUST_SVC_CATEGORY_LABELS[categoryId] || categoryId || 'Service';
}

function custSvcPricingSummary(svc) {
  const type = svc.pricingType || 'fixed';
  if (type === 'fixed') return '';
  const labels = {
    from: 'Starting from',
    range: 'Price range',
    hour: 'Per hour',
    unit: 'Per item / unit',
  };
  let line = labels[type] || type;
  const base = svc.listPrice != null ? svc.listPrice : svc.price;
  if (type === 'range' && svc.listPriceMax) {
    line += ' · ' + custInr(base) + ' – ' + custInr(svc.listPriceMax);
  } else if (base) {
    line += ' · ' + custInr(base);
  }
  return line;
}

function custRenderDeliverablesInclusions(entity) {
  const dm = entity.deliveryMap || {};
  let html = '';
  if ((entity.deliverPhoto || []).length) {
    html += '<h3 style="margin:0 0 8px;font-size:15px">Photos</h3><ul class="chk-list">';
    (entity.deliverPhoto || []).forEach(function (name) {
      const det = (entity.photoDetails || {})[name] || {};
      const parts = [];
      if (det.qty) parts.push(String(det.qty) + (name.indexOf('Photo') >= 0 ? ' photos' : ''));
      if (det.format) parts.push(det.format);
      if (det.delivery) parts.push(det.delivery);
      else if (dm[name]) parts.push(dm[name]);
      html += '<li><b>' + custEsc(name) + '</b>' + (parts.length ? ' — ' + custEsc(parts.join(' · ')) : '') + '</li>';
    });
    html += '</ul>';
  }
  if ((entity.deliverVideo || []).length) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Videos & live</h3><ul class="chk-list">';
    (entity.deliverVideo || []).forEach(function (name) {
      const det = (entity.videoDetails || {})[name] || {};
      const parts = [];
      if (det.duration) parts.push(det.duration);
      if (det.format) parts.push(det.format);
      if (name === 'Live Streaming' && det.streamCameras) parts.push(det.streamCameras + ' camera(s)');
      if (det.delivery) parts.push(det.delivery);
      else if (dm[name]) parts.push(dm[name]);
      html += '<li><b>' + custEsc(name) + '</b>' + (parts.length ? ' — ' + custEsc(parts.join(' · ')) : '') + '</li>';
    });
    html += '</ul>';
  }
  if ((entity.deliverDigital || []).length) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Digital delivery</h3><ul class="chk-list">';
    (entity.deliverDigital || []).forEach(function (name) {
      const timeline = dm[name];
      html += '<li>' + custEsc(name) + (timeline ? ' — ' + custEsc(timeline) : '') + '</li>';
    });
    html += '</ul>';
  }
  const ap = entity.albumPrints || {};
  const album = ap['Photo Album'];
  if (album && album.on) {
    html +=
      '<h3 style="margin:16px 0 8px;font-size:15px">Album & prints</h3><ul class="chk-list"><li><b>Photo Album</b> — ' +
      custEsc(album.size) +
      ' · ' +
      album.pages +
      ' pages · ' +
      custEsc(album.cover) +
      ' cover · ' +
      custEsc(album.paper) +
      ' paper' +
      (album.copies > 1 ? ' · ' + album.copies + ' copies' : '') +
      '</li>';
    if (ap.Calendar && ap.Calendar.on) {
      html += '<li>Wall calendar · ' + custEsc(ap.Calendar.size) + ' × ' + (ap.Calendar.copies || 1) + '</li>';
    }
    if (ap['Photo Frame'] && ap['Photo Frame'].on) {
      html += '<li>Photo frame · ' + custEsc(ap['Photo Frame'].size || 'Included') + '</li>';
    }
    html += '</ul>';
  }
  const timelineKeys = Object.keys(dm);
  if (timelineKeys.length) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Delivery timeline</h3>';
    html += custKvRows(
      timelineKeys.map(function (k) {
        return { k: k, v: dm[k] };
      })
    );
  }
  return html;
}

function custRenderPkgInclusions(pkg) {
  return custRenderDeliverablesInclusions(pkg);
}

function custRenderSvcOverviewInclusions(svc) {
  let html =
    '<p style="font-size:13px;font-weight:600;color:var(--mut);line-height:1.5;margin:0 0 12px">' +
    custEsc(svc.blurb) +
    '</p>';
  html += '<div class="cust-hd">Service category</div>' + custChips([custServiceCategoryLabel(svc.category)]);
  const priceNote = custSvcPricingSummary(svc);
  if (priceNote) {
    html += '<div class="cust-hd">How pricing works</div><p class="sub" style="margin:0 0 4px">' + custEsc(priceNote) + '</p>';
  }
  if (svc.discountYes === 'yes' && svc.discountPct && svc.listPrice > (svc.price || 0)) {
    html +=
      '<p class="sub" style="margin:0 0 12px">List price ' +
      custInr(svc.listPrice) +
      ' · <b style="color:#BE185D">' +
      svc.discountPct +
      '% off</b> · You pay ' +
      custInr(svc.price) +
      '</p>';
  }
  html += '<div class="cust-hd" style="margin-top:4px">What\'s included</div>';
  html += custRenderDeliverablesInclusions(svc);
  return html;
}

function custRenderPkgCoverage(pkg) {
  const blocks = pkg.coverageByFunction || {};
  const ordered = (pkg.functions && pkg.functions.length ? pkg.functions.slice() : Object.keys(blocks)).filter(function (fn) {
    return blocks[fn];
  });
  Object.keys(blocks).forEach(function (fn) {
    if (ordered.indexOf(fn) < 0) ordered.push(fn);
  });
  return ordered
    .map(function (fn) {
      const b = blocks[fn];
      const photos = custTeamLines(b.photoTypes).join(', ') || '—';
      const videos = custTeamLines(b.videoTypes).join(', ') || '—';
      const rows = [];
      if (!custFnIsCoupleShoot(fn)) {
        rows.push({
          k: 'Coverage side',
          v: b.coverageSide === 'both' ? 'Both sides' : b.coverageSide === 'single' ? 'Single side' : b.coverageSide || '—',
        });
      }
      rows.push(
        { k: 'Duration', v: b.duration || '—' },
        { k: 'Extra hour', v: custInr(b.extraHour) },
        { k: 'Photo team', v: photos },
        { k: 'Video team', v: videos }
      );
      return (
        '<div style="margin-bottom:12px;padding:12px;border:1px solid #E2E8F0;border-radius:12px">' +
        '<b style="display:block;color:var(--navy);margin-bottom:8px">' +
        custEsc(fn) +
        '</b>' +
        custKvRows(rows) +
        '</div>'
      );
    })
    .join('');
}

function custRenderExtrasBlock(extras) {
  const inc = [];
  const paid = [];
  Object.keys(extras || {}).forEach(function (name) {
    const x = extras[name];
    if (!x) return;
    if (x.mode === 'included') {
      let line = name;
      if (name === 'Live Streaming' && x.includedCameras) line += ' · ' + x.includedCameras + ' cameras included';
      if (x.hourlyLimit) line += ' · ' + (x.includedHours || 0) + ' hrs incl., then ' + custInr(x.extraHour) + '/hr';
      inc.push(line);
    } else {
      paid.push({ name: name, price: x.price, basis: x.basis });
    }
  });
  let html = '';
  if (inc.length) {
    html += '<div class="cust-hd">Included in package</div><ul class="chk-list">';
    inc.forEach(function (l) {
      html += '<li>' + custEsc(l) + '</li>';
    });
    html += '</ul>';
  }
  if (paid.length) {
    html += '<div class="cust-hd">Optional add-ons</div>';
    paid.forEach(function (p) {
      html +=
        '<div class="extra-line"><span>' +
        custEsc(p.name) +
        '</span><span style="font-weight:900;color:var(--blue)">' +
        custInr(p.price) +
        (p.basis ? ' <span style="font-size:10px;color:var(--mut)">/ ' + custEsc(p.basis) + '</span>' : '') +
        '</span></div>';
    });
  }
  return html;
}

function custRenderPolicyDetailBlock(pol, pv) {
  let html = '<div class="cust-hd">' + custEsc(pol) + '</div>';
  if (pv.notes) html += '<p class="sub" style="margin:0 0 10px">' + custEsc(pv.notes) + '</p>';
  if (pv.noticeDays != null) {
    html += '<div class="kv-row"><span>Notice (days)</span><b>' + pv.noticeDays + '</b></div>';
  }
  if (pv.refundPct != null) {
    html += '<div class="kv-row"><span>Refund</span><b>' + pv.refundPct + '%</b></div>';
  }
  if (pv.fee != null && pol.indexOf('Rescheduling') >= 0) {
    html += '<div class="kv-row"><span>Reschedule fee</span><b>' + (pv.fee ? custInr(pv.fee) : 'Free') + '</b></div>';
  }
  if (pv.days != null) {
    if (pol.indexOf('Retention') >= 0) {
      html += '<div class="kv-row"><span>Retention</span><b>' + pv.days + ' days</b></div>';
    } else if (pol.indexOf('Selection') >= 0) {
      html += '<div class="kv-row"><span>Selection deadline</span><b>' + pv.days + ' days</b></div>';
    }
  }
  return html;
}

function custRenderPolicies(pkg) {
  const pv = pkg.policyValues || {};
  let html = '';
  if ((pkg.paymentStages || []).length) {
    html += '<div class="cust-hd">Payment stages</div>';
    html += pkg.paymentStages
      .map(function (ps) {
        return '<div class="kv-row"><span>' + custEsc(ps.label) + '</span><b>' + ps.pct + '%</b></div>';
      })
      .join('');
  }
  const hasCancelTiers = pkg.cancelRules && pkg.cancelRules.length;
  const hasReschedTiers = pkg.rescheduleRules && pkg.rescheduleRules.length;
  if (hasCancelTiers) {
    html += '<div class="cust-hd">Cancellation</div>';
    html += pkg.cancelRules
      .map(function (r) {
        return '<div class="kv-row"><span>' + custEsc(r.days) + '</span><b>' + r.pct + '% fee</b></div>';
      })
      .join('');
    if (pv['Cancellation Policy'] && pv['Cancellation Policy'].notes) {
      html +=
        '<p class="sub" style="margin:8px 0 0">' + custEsc(pv['Cancellation Policy'].notes) + '</p>';
    }
  }
  if (hasReschedTiers) {
    html += '<div class="cust-hd">Rescheduling</div>';
    html += pkg.rescheduleRules
      .map(function (r) {
        return '<div class="kv-row"><span>' + custEsc(r.days) + '</span><b>' + (r.pct ? r.pct + '%' : 'Free') + '</b></div>';
      })
      .join('');
    if (pv['Rescheduling Policy'] && pv['Rescheduling Policy'].notes) {
      html +=
        '<p class="sub" style="margin:8px 0 0">' + custEsc(pv['Rescheduling Policy'].notes) + '</p>';
    }
  }
  (pkg.policies || []).forEach(function (pol) {
    const block = pv[pol];
    if (!block) return;
    if (pol === 'Cancellation Policy' && hasCancelTiers) return;
    if (pol === 'Rescheduling Policy' && hasReschedTiers) return;
    html += custRenderPolicyDetailBlock(pol, block);
  });
  if ((pkg.requirements || []).length) {
    html += '<div class="cust-hd">Customer requirements</div><ul class="chk-list">';
    pkg.requirements.forEach(function (r) {
      html += '<li>' + custEsc(r) + '</li>';
    });
    html += '</ul>';
  }
  return html;
}

function custRenderSvcInclusions(svc) {
  return custRenderSvcOverviewInclusions(svc);
}

function custRenderSvcCoverage(svc) {
  if (svc.durEnabled === false) {
    return (
      '<p class="sub" style="margin:0 0 12px">This service is priced as a fixed package. Duration and crew size are agreed when you confirm the booking.</p>' +
      custKvRows([{ k: 'Typical coverage', v: svc.duration || 'As per studio schedule' }])
    );
  }
  const dur =
    svc.duration === 'Custom' && svc.durationCustom
      ? svc.durationCustom
      : svc.duration || '—';
  const rows = [
    { k: 'Duration included', v: dur },
    { k: 'Extra hour', v: svc.extraHour ? custInr(svc.extraHour) : '—' },
  ];
  const photo = custTeamLines((svc.team || {}).photo).join(', ');
  const video = custTeamLines((svc.team || {}).video).join(', ');
  rows.push({ k: 'Photo team', v: photo || '—' });
  rows.push({ k: 'Video team', v: video || '—' });
  return custKvRows(rows);
}

function custPackageExtrasList(pkg) {
  const out = [];
  Object.keys(pkg.extras || {}).forEach(function (name) {
    const x = pkg.extras[name];
    if (x && x.mode === 'extra') {
      out.push({ id: name, label: name, price: x.price || 0, basis: x.basis });
    }
  });
  return out;
}

function custServiceExtrasList(svc) {
  const out = [];
  Object.keys(svc.extras || {}).forEach(function (name) {
    const x = svc.extras[name];
    if (x && x.mode === 'extra') {
      out.push({ id: name, label: name, price: x.price || 0, basis: x.basis });
    }
  });
  return out;
}

function custPkgLevelClass(level) {
  const l = String(level || '').toLowerCase();
  if (l === 'basic') return 'tier-basic';
  if (l === 'premium') return 'tier-premium';
  return 'tier-standard';
}

function custPkgCoverageSideSummary(pkg) {
  const blocks = pkg.coverageByFunction || {};
  const fns = pkg.functions && pkg.functions.length ? pkg.functions : Object.keys(blocks);
  let hasBoth = false;
  let hasSingle = false;
  fns.forEach(function (fn) {
    if (custFnIsCoupleShoot(fn)) return;
    const b = blocks[fn];
    if (!b || !b.coverageSide) return;
    if (b.coverageSide === 'both') hasBoth = true;
    else if (b.coverageSide === 'single') hasSingle = true;
  });
  if (!hasBoth && !hasSingle) return '';
  if (hasBoth && !hasSingle) return 'Both sides';
  return 'Single side';
}

function custSummaryBulletsFromPkg(pkg) {
  const bullets = [];
  const ed = pkg.photoDetails && pkg.photoDetails['Edited Photos'];
  if (ed && ed.qty) bullets.push(ed.qty + ' edited photos');
  const fnCount = (pkg.functions || []).length;
  if (fnCount > 1) bullets.push(fnCount + ' events covered');
  else if ((pkg.functions || [])[0]) bullets.push((pkg.functions || [])[0]);
  if (pkg.ceremonyTypes && pkg.ceremonyTypes[0]) bullets.push(pkg.ceremonyTypes[0]);
  return bullets.slice(0, 4);
}

function custPkgCardMetaHtml(pkg) {
  const level = pkg.level || 'Standard';
  const side = custPkgCoverageSideSummary(pkg);
  let html =
    '<div class="pkg-meta"><span class="pkg-tier ' +
    custPkgLevelClass(level) +
    '">' +
    custEsc(level) +
    '</span>';
  if (side) {
    html += '<span class="pkg-side-pill">' + custEsc(side) + '</span>';
  }
  html += '</div>';
  return html;
}
