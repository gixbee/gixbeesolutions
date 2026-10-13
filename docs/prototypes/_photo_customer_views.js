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

function custRenderPkgInclusions(pkg) {
  let html = '<h3 style="margin:0 0 8px;font-size:15px">Photos</h3><ul class="chk-list">';
  (pkg.deliverPhoto || []).forEach(function (name) {
    const det = (pkg.photoDetails || {})[name] || {};
    html +=
      '<li><b>' +
      custEsc(name) +
      '</b> — ' +
      (det.qty ? det.qty + ' · ' : '') +
      custEsc(det.format || '') +
      (det.delivery ? ' · ' + custEsc(det.delivery) : '') +
      '</li>';
  });
  html += '</ul>';
  if ((pkg.deliverVideo || []).length) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Videos</h3><ul class="chk-list">';
    (pkg.deliverVideo || []).forEach(function (name) {
      const det = (pkg.videoDetails || {})[name] || {};
      let extra = '';
      if (name === 'Live Streaming' && det.streamCameras) extra = ' · ' + det.streamCameras + ' camera(s)';
      html +=
        '<li><b>' +
        custEsc(name) +
        '</b> — ' +
        custEsc(det.duration || '') +
        ' · ' +
        custEsc(det.format || '') +
        extra +
        '</li>';
    });
    html += '</ul>';
  }
  if ((pkg.deliverDigital || []).length) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Digital delivery</h3><ul class="chk-list">';
    (pkg.deliverDigital || []).forEach(function (name) {
      html += '<li>' + custEsc(name) + '</li>';
    });
    html += '</ul>';
  }
  const ap = pkg.albumPrints || {};
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
      ' paper</li>';
    if (ap.Calendar && ap.Calendar.on) {
      html += '<li>Wall calendar · ' + custEsc(ap.Calendar.size) + ' × ' + (ap.Calendar.copies || 1) + '</li>';
    }
    html += '</ul>';
  }
  html += '<h3 style="margin:16px 0 8px;font-size:15px">Delivery timeline</h3>';
  html += custKvRows(
    Object.keys(pkg.deliveryMap || {}).map(function (k) {
      return { k: k, v: pkg.deliveryMap[k] };
    })
  );
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

function custRenderPolicies(pkg) {
  let html = '<div class="cust-hd">Payment stages</div>';
  html += (pkg.paymentStages || [])
    .map(function (ps) {
      return '<div class="kv-row"><span>' + custEsc(ps.label) + '</span><b>' + ps.pct + '%</b></div>';
    })
    .join('');
  if (pkg.cancelRules && pkg.cancelRules.length) {
    html += '<div class="cust-hd">Cancellation</div>';
    html += pkg.cancelRules
      .map(function (r) {
        return '<div class="kv-row"><span>' + custEsc(r.days) + '</span><b>' + r.pct + '% fee</b></div>';
      })
      .join('');
  }
  if (pkg.rescheduleRules && pkg.rescheduleRules.length) {
    html += '<div class="cust-hd">Rescheduling</div>';
    html += pkg.rescheduleRules
      .map(function (r) {
        return '<div class="kv-row"><span>' + custEsc(r.days) + '</span><b>' + (r.pct ? r.pct + '%' : 'Free') + '</b></div>';
      })
      .join('');
  }
  (pkg.policies || []).forEach(function (pol) {
    const pv = (pkg.policyValues || {})[pol];
    if (!pv) return;
    html += '<div class="cust-hd">' + custEsc(pol) + '</div>';
    if (pv.notes) html += '<p class="sub" style="margin:0 0 10px">' + custEsc(pv.notes) + '</p>';
    if (pv.noticeDays != null) {
      html += '<div class="kv-row"><span>Notice (days)</span><b>' + pv.noticeDays + '</b></div>';
    }
    if (pv.refundPct != null) {
      html += '<div class="kv-row"><span>Refund</span><b>' + pv.refundPct + '%</b></div>';
    }
    if (pv.days != null && pol.indexOf('Retention') >= 0) {
      html += '<div class="kv-row"><span>Retention</span><b>' + pv.days + ' days</b></div>';
    }
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
  let html = '<p class="sub" style="margin:0 0 12px">' + custEsc(svc.blurb) + '</p>';
  html += '<h3 style="margin:0 0 8px;font-size:15px">What\'s included</h3><ul class="chk-list">';
  (svc.deliverPhoto || []).forEach(function (name) {
    const det = (svc.photoDetails || {})[name] || {};
    html +=
      '<li><b>' +
      custEsc(name) +
      '</b>' +
      (det.qty ? ' — ' + det.qty + ' photos' : '') +
      (det.delivery ? ' · ' + custEsc(det.delivery) : '') +
      '</li>';
  });
  (svc.deliverVideo || []).forEach(function (name) {
    const det = (svc.videoDetails || {})[name] || {};
    html += '<li><b>' + custEsc(name) + '</b>';
    if (det.streamCameras) html += ' — ' + det.streamCameras + ' camera(s)';
    html += '</li>';
  });
  (svc.deliverDigital || []).forEach(function (name) {
    html += '<li>' + custEsc(name) + '</li>';
  });
  html += '</ul>';
  if (svc.deliveryMap) {
    html += '<h3 style="margin:16px 0 8px;font-size:15px">Delivery</h3>';
    html += custKvRows(
      Object.keys(svc.deliveryMap).map(function (k) {
        return { k: k, v: svc.deliveryMap[k] };
      })
    );
  }
  return html;
}

function custRenderSvcCoverage(svc) {
  const rows = [
    { k: 'Duration', v: svc.duration || '—' },
    { k: 'Extra hour', v: svc.extraHour ? custInr(svc.extraHour) : '—' },
  ];
  const photo = custTeamLines((svc.team || {}).photo).join(', ');
  const video = custTeamLines((svc.team || {}).video).join(', ');
  if (photo) rows.push({ k: 'Photo team', v: photo });
  if (video) rows.push({ k: 'Video team', v: video });
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
      out.push({ id: name, label: name, price: x.price || 0 });
    }
  });
  return out;
}

function custSummaryBulletsFromPkg(pkg) {
  const bullets = [];
  const ed = pkg.photoDetails && pkg.photoDetails['Edited Photos'];
  if (ed && ed.qty) bullets.push(ed.qty + ' edited photos');
  const fn = (pkg.functions || [])[0];
  if (fn) bullets.push(fn);
  if (pkg.ceremonyTypes && pkg.ceremonyTypes[0]) bullets.push(pkg.ceremonyTypes[0]);
  return bullets.slice(0, 4);
}
