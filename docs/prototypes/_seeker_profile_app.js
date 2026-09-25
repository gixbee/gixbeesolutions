const C = window.GIXBEE_HIRE_CATALOG;
const STORAGE_KEY = 'GIXBEE_JOB_PROFILES';
const SEEKER_BUILD = '2026-09-25-single';

function el(id) {
  return document.getElementById(id);
}
function readExpectedSalaryValue() {
  const primary = el('salExpected');
  if (primary) return primary.value;
  const smin = el('smin');
  if (smin) return smin.value;
  return '';
}
function writeExpectedSalaryValue(value) {
  const v = value ?? '';
  const primary = el('salExpected');
  if (primary) {
    primary.value = v;
    return;
  }
  const smin = el('smin');
  if (smin) smin.value = v;
}
function bindInput(id, fn) {
  const node = el(id);
  if (node) node.addEventListener('input', fn);
}
function bindClick(id, fn) {
  const node = el(id);
  if (node) node.onclick = fn;
}
if (!C || !C.employmentTypes) {
  document.body.innerHTML = '<p style="font:16px sans-serif;padding:24px">Catalogue missing. Regenerate with python3 docs/prototypes/_gen_seeker_profile_html.py</p>';
  throw new Error('GIXBEE_HIRE_CATALOG missing');
}

const state = {
  editId: null,
  emp: 'FT',
  sectorId: null,
  positionId: null,
  types: [],
  skills: [],
  skillDraft: [],
  specDraft: [],
  exp: 2,
  neg: true,
  relocate: false,
  posLimit: 8,
  skillFull: false,
  languages: ['English', 'Malayalam'],
  langDraft: [],
  availableToJoin: 'immediate',
  resume: null,
  locValue: 'Kochi, Kerala',
  salValue: '25000',
};
const LANG_QUICK = ['English', 'Malayalam', 'Hindi', 'Tamil'];
const LANGUAGE_LIST = [
  'English', 'Malayalam', 'Hindi', 'Tamil', 'Kannada', 'Telugu', 'Marathi', 'Bengali',
  'Gujarati', 'Punjabi', 'Odia', 'Assamese', 'Urdu', 'Arabic', 'Konkani', 'Tulu',
];
const ICONS = {
  bolt: '⚡', pipe: '🔧', broom: '🧹', roller: '🎨', hammer: '🔨', fan: '❄️', car: '🚗', box: '📦',
  chef: '🍳', shield: '🛡️', store: '🏪', briefcase: '💼', laptop: '💻', book: '📘', health: '💚',
  cal: '📅', dumbbell: '🏋️', lotus: '🌸',
};
const JOIN_AVAILABILITY = [
  { code: 'immediate', label: 'Immediately' },
  { code: 'd7', label: 'Within 7 days' },
  { code: 'd15', label: 'Within 15 days' },
  { code: 'd30', label: 'Within 30 days' },
  { code: 'd60', label: 'Within 60 days' },
  { code: 'd90', label: 'Within 90 days' },
];
const RESUME_DEMO_MAX_BYTES = 350000;

function uid() {
  return 'jp_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
}
function loadProfiles() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch (_err) {
    return [];
  }
}
function saveProfiles(list) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
}
function show(id) {
  document.querySelectorAll('.scr').forEach((s) => s.classList.toggle('on', s.id === id));
}
function toast(m) {
  const t = document.getElementById('toast');
  t.textContent = m;
  t.style.display = 'block';
  setTimeout(() => (t.style.display = 'none'), 2400);
}
function sector() {
  return C.sectors.find((s) => s.id === state.sectorId);
}
function position() {
  return sector()?.positions.find((p) => p.id === state.positionId);
}

function selectedCountLabel(base, count) {
  return `${base} (${count} selected)`;
}
function typeFieldLabel(p) {
  const options = p.types?.length || 0;
  const n = state.types.length;
  if (options <= 1) return p.typeLabel;
  if (n < 1) return p.typeLabel;
  return selectedCountLabel(p.typeLabel, n);
}
function ensureDefaultType(p) {
  if (!state.types.length && p.types && p.types.length) {
    state.types = [p.types[0]];
  }
}
function toggleType(t) {
  const p = position();
  if (!p) return;
  if (state.types.includes(t)) {
    if (state.types.length <= 1) {
      toast('Select at least one type or specialization.');
      return;
    }
    state.types = state.types.filter((x) => x !== t);
  } else {
    state.types = [...state.types, t];
  }
  renderS3();
}
function syncSheetOkLabels() {
  const sp = document.getElementById('spOk');
  if (sp) sp.textContent = state.specDraft.length ? `OK (${state.specDraft.length} selected)` : 'OK';
  const lg = document.getElementById('lgOk');
  if (lg) lg.textContent = state.langDraft.length ? `OK (${state.langDraft.length} selected)` : 'OK';
  const sk = document.getElementById('skOk');
  if (sk) sk.textContent = state.skillDraft.length ? `OK (${state.skillDraft.length} selected)` : 'OK';
}

function joinLabel(code) {
  return JOIN_AVAILABILITY.find((x) => x.code === code)?.label || code || '—';
}
function renderResumeUi() {
  const nameEl = document.getElementById('resumeName');
  const clearBtn = document.getElementById('resumeClear');
  const input = document.getElementById('resumeFile');
  if (!nameEl) return;
  if (state.resume?.fileName) {
    const kb = state.resume.sizeBytes ? ` (${Math.round(state.resume.sizeBytes / 1024)} KB)` : '';
    nameEl.textContent = state.resume.fileName + kb;
    if (clearBtn) clearBtn.hidden = false;
  } else {
    nameEl.textContent = 'No file chosen';
    if (clearBtn) clearBtn.hidden = true;
    if (input) input.value = '';
  }
}
function clearResume() {
  state.resume = null;
  renderResumeUi();
}
function setResumeFromFile(file) {
  if (!file) {
    clearResume();
    return;
  }
  const allowed = /\.(pdf|doc|docx)$/i.test(file.name) || file.type.startsWith('image/');
  if (!allowed) {
    toast('Use PDF, Word (.doc/.docx), or an image.');
    clearResume();
    return;
  }
  const base = {
    fileName: file.name,
    sizeBytes: file.size,
    mimeType: file.type || 'application/octet-stream',
    storedInline: false,
  };
  if (file.size > RESUME_DEMO_MAX_BYTES) {
    state.resume = base;
    renderResumeUi();
    toast('Resume saved as reference only (file too large for demo storage). Live app uploads to server.');
    return;
  }
  const reader = new FileReader();
  reader.onload = () => {
    state.resume = { ...base, storedInline: true, dataUrl: reader.result };
    renderResumeUi();
  };
  reader.onerror = () => {
    state.resume = base;
    renderResumeUi();
    toast('Could not read file — name saved for demo only.');
  };
  reader.readAsDataURL(file);
}

function defaultProfileName() {
  const p = position();
  const s = sector();
  if (!p || !s) return '';
  const t = state.types.length ? ' — ' + state.types.slice(0, 2).join(', ') : '';
  return `${p.label}${t} · ${s.label}`.slice(0, 80);
}

function buildPayload() {
  const s = sector();
  const p = position();
  const emp = C.employmentTypes.find((e) => e.code === state.emp);
  const salExpected = readExpectedSalaryValue();
  const loc = document.getElementById('loc').value.trim();
  const qual = document.getElementById('qual').value;
  const bio = document.getElementById('desc').value.trim();
  const nameInput = document.getElementById('profileName').value.trim();
  const name = nameInput || defaultProfileName();
  const joinCode = document.getElementById('joinAvail')?.value || state.availableToJoin || 'immediate';
  state.availableToJoin = joinCode;
  const resumeOut = state.resume
    ? {
        fileName: state.resume.fileName,
        sizeBytes: state.resume.sizeBytes,
        mimeType: state.resume.mimeType,
        storedInline: !!state.resume.storedInline,
        dataUrl: state.resume.storedInline ? state.resume.dataUrl : undefined,
      }
    : null;
  return {
    id: state.editId || uid(),
    schemaVersion: 2,
    savedAt: new Date().toISOString(),
    displayName: name,
    employmentType: { code: state.emp, label: emp?.label || state.emp },
    sector: s ? { id: s.id, label: s.label } : null,
    position: p ? { id: p.id, label: p.label, subtitle: p.subtitle || '' } : null,
    types: [...state.types],
    qualification: qual || null,
    experienceYears: state.exp,
    skills: [...state.skills],
    languages: [...state.languages],
    bio: bio || null,
    location: loc,
    salary: {
      expectedMonthly: salExpected ? Number(salExpected) : null,
      negotiable: state.neg,
    },
    openToRelocate: state.relocate,
    availableToJoin: { code: joinCode, label: joinLabel(joinCode) },
    resume: resumeOut,
    catalogueVersion: C.version,
  };
}

function applyPayload(profile) {
  state.editId = profile.id;
  state.emp = profile.employmentType?.code || 'FT';
  state.sectorId = profile.sector?.id || null;
  state.positionId = profile.position?.id || null;
  state.types = [...(profile.types || [])];
  state.skills = [...(profile.skills || [])];
  state.exp = profile.experienceYears ?? 2;
  state.neg = profile.salary?.negotiable !== false;
  state.relocate = !!profile.openToRelocate;
  state.languages = profile.languages?.length ? [...profile.languages] : ['English', 'Malayalam'];
  document.getElementById('qual').value = profile.qualification || '';
  document.getElementById('desc').value = profile.bio || '';
  state.locValue = profile.location || 'Kochi, Kerala';
  state.salValue = String(profile.salary?.expectedMonthly ?? profile.salary?.minMonthly ?? '25000');
  writeExpectedSalaryValue(state.salValue);
  document.getElementById('profileName').value = profile.displayName || '';
  document.getElementById('neg').classList.toggle('on', state.neg);
  document.getElementById('reloc').classList.toggle('on', state.relocate);
  const joinCode = profile.availableToJoin?.code || 'immediate';
  state.availableToJoin = joinCode;
  const joinSel = document.getElementById('joinAvail');
  if (joinSel) joinSel.value = joinCode;
  if (profile.resume?.fileName) {
    state.resume = {
      fileName: profile.resume.fileName,
      sizeBytes: profile.resume.sizeBytes,
      mimeType: profile.resume.mimeType,
      storedInline: !!profile.resume.storedInline,
      dataUrl: profile.resume.dataUrl,
    };
  } else {
    state.resume = null;
  }
  renderResumeUi();
  renderS4();
}

function resetWizard(keepEmp) {
  const emp = keepEmp ? state.emp : 'FT';
  state.editId = null;
  state.emp = emp;
  state.sectorId = null;
  state.positionId = null;
  state.types = [];
  state.skills = [];
  state.exp = 2;
  state.neg = true;
  state.relocate = false;
  state.languages = ['English', 'Malayalam'];
  state.availableToJoin = 'immediate';
  state.resume = null;
  state.posLimit = 8;
  document.getElementById('qual').value = '';
  document.getElementById('desc').value = '';
  state.locValue = 'Kochi, Kerala';
  state.salValue = '25000';
  writeExpectedSalaryValue('25000');
  document.getElementById('profileName').value = '';
  document.getElementById('posSearch').value = '';
  document.getElementById('neg').classList.add('on');
  document.getElementById('reloc').classList.remove('on');
  const joinSel = document.getElementById('joinAvail');
  if (joinSel) joinSel.value = 'immediate';
  renderResumeUi();
}

function renderS1() {
  document.getElementById('empTypes').innerHTML = C.employmentTypes
    .map(
      (e) =>
        `<button class="pill ${state.emp === e.code ? 'on' : ''}" data-e="${e.code}">${state.emp === e.code ? '✓ ' : ''}${e.label}</button>`,
    )
    .join('');
  document.getElementById('sectors').innerHTML = C.sectors
    .map(
      (s) =>
        `<button class="tile ${state.sectorId === s.id ? 'on' : ''}" data-s="${s.id}">
      <div class="ico" style="background:${s.color}22">${ICONS[s.icon] || '•'}</div><b>${s.label}</b>
    </button>`,
    )
    .join('');
  document.getElementById('c1').disabled = !state.sectorId;
}
function renderS2() {
  const s = sector();
  if (!s) return;
  document.getElementById('s2sec').textContent = s.label;
  document.getElementById('s2sub').textContent = s.subtitle;
  document.getElementById('s2ico').textContent = ICONS[s.icon] || '•';
  const q = document.getElementById('posSearch').value.trim().toLowerCase();
  let list = s.positions.filter(
    (p) => !q || p.label.toLowerCase().includes(q) || (p.subtitle || '').toLowerCase().includes(q),
  );
  const more = document.getElementById('morePos');
  more.style.display = !q && list.length > state.posLimit ? 'inline' : 'none';
  if (!q) list = list.slice(0, state.posLimit);
  document.getElementById('posList').innerHTML = list
    .map(
      (p) =>
        `<div class="prow ${state.positionId === p.id ? 'on' : ''}" data-p="${p.id}">
      <div class="pdot">${ICONS[s.icon] || '•'}</div>
      <div><div class="t">${p.label}</div><div class="s">${p.subtitle || p.types.slice(0, 2).join(', ')}</div></div>
    </div>`,
    )
    .join('');
  document.getElementById('c2').disabled = !state.positionId;
}
function visibleTypes(p) {
  const maxVisible = 6;
  if (!p.types || p.types.length <= maxVisible) return p.types || [];
  return p.types.slice(0, maxVisible);
}
function ensureDefaultLanguages() {
  if (!state.languages.length) state.languages = ['English', 'Malayalam'];
}
function renderS3() {
  const s = sector();
  const p = position();
  if (!p) return;
  ensureDefaultLanguages();
  ensureDefaultType(p);
  document.getElementById('s3crumb').textContent = s.label + ' › ' + p.label;
  document.getElementById('s3sub').textContent = p.subtitle || '';
  document.getElementById('s3ico').textContent = ICONS[s.icon] || '•';
  document.getElementById('typeLbl').textContent = typeFieldLabel(p);
  document.getElementById('skillLbl').textContent = selectedCountLabel('Skills', state.skills.length);
  document.getElementById('langLbl').textContent = selectedCountLabel('Languages you speak', state.languages.length);
  const vis = visibleTypes(p);
  document.getElementById('typeChips').innerHTML = vis
    .map(
      (t) =>
        `<button type="button" class="chip ${state.types.includes(t) ? 'on' : ''}" data-t="${t.replace(/"/g, '&quot;')}">${t}</button>`,
    )
    .join('');
  document.getElementById('typeExtra').innerHTML = state.types
    .filter((t) => !vis.includes(t))
    .map(
      (t) =>
        `<span class="chip on">${t}<button type="button" class="chip-x" data-tx="${t.replace(/"/g, '&quot;')}">×</button></span>`,
    )
    .join('');
  const more = document.getElementById('moreTypes');
  more.hidden = p.types.length <= vis.length;
  document.getElementById('skillChips').innerHTML = state.skills
    .map((sk) => `<span class="chip sk">${sk}<button type="button" data-x="${sk}">×</button></span>`)
    .join('');
  document.getElementById('langQuick').innerHTML = LANG_QUICK.map(
    (l) =>
      `<button type="button" class="chip lang ${state.languages.includes(l) ? 'on' : ''}" data-lq="${l}">${l}</button>`,
  ).join('');
  document.getElementById('langChips').innerHTML = state.languages
    .filter((l) => !LANG_QUICK.includes(l))
    .map(
      (l) =>
        `<span class="chip lang sk">${l}<button type="button" aria-label="Remove ${l}" data-lx="${l}">×</button></span>`,
    )
    .join('');
  document.getElementById('expV').textContent = state.exp;
}

function captureS4Draft() {
  const loc = el('loc');
  if (loc) state.locValue = loc.value;
  const sal = readExpectedSalaryValue();
  if (sal !== '') state.salValue = sal;
  const join = el('joinAvail');
  if (join) state.availableToJoin = join.value;
}

function bindStep4Events() {
  const body = el('s4Body');
  if (!body || body.dataset.bound === '1') return;
  body.dataset.bound = '1';
  body.addEventListener('input', (e) => {
    if (e.target.id === 'loc' || e.target.id === 'salExpected') matchCount();
  });
  body.addEventListener('change', (e) => {
    if (e.target.id === 'joinAvail') state.availableToJoin = e.target.value;
    if (e.target.id === 'resumeFile' && e.target.files && e.target.files[0]) {
      setResumeFromFile(e.target.files[0]);
    }
  });
  body.addEventListener('click', (e) => {
    const negBtn = e.target.closest('#neg');
    if (negBtn) {
      state.neg = !state.neg;
      negBtn.classList.toggle('on', state.neg);
      return;
    }
    const relocBtn = e.target.closest('#reloc');
    if (relocBtn) {
      state.relocate = !state.relocate;
      relocBtn.classList.toggle('on', state.relocate);
      return;
    }
    if (e.target.id === 'clrLoc') {
      const loc = el('loc');
      if (loc) loc.value = '';
      state.locValue = '';
      matchCount();
      return;
    }
    if (e.target.id === 'resumeClear') clearResume();
  });
}

function renderS4() {
  captureS4Draft();
  const body = el('s4Body');
  if (!body) return;
  const locValue = escapeHtml(state.locValue || 'Kochi, Kerala');
  const salValue = escapeHtml(String(state.salValue ?? '25000'));
  const joinOpts = JOIN_AVAILABILITY.map(
    (o) =>
      `<option value="${o.code}"${state.availableToJoin === o.code ? ' selected' : ''}>${o.label}</option>`,
  ).join('');
  const negOn = state.neg ? ' on' : '';
  const relocOn = state.relocate ? ' on' : '';
  body.innerHTML = `
        <div class="fld">
          <label>Preferred work location</label>
          <div class="loc">📍 <input id="loc" value="${locValue}"><button type="button" id="clrLoc" style="border:0;background:none;cursor:pointer">✕</button></div>
        </div>
        <div class="fld">
          <label>Expected salary (₹/month)</label>
          <input id="salExpected" type="number" value="${salValue}" placeholder="e.g. 25000">
        </div>
        <div class="fld">
          <label>Available to join</label>
          <select id="joinAvail">${joinOpts}</select>
        </div>
        <div class="fld">
          <label>Resume (optional)</label>
          <p class="hint">PDF or Word — live app uploads to secure storage; demo keeps small files in this browser.</p>
          <div class="upload">
            <div class="up-row">
              <label class="up-btn" for="resumeFile">Upload resume</label>
              <input type="file" id="resumeFile" accept=".pdf,.doc,.docx,application/pdf,application/msword,image/*">
              <span class="fname" id="resumeName">No file chosen</span>
              <button type="button" class="rm" id="resumeClear" hidden>Remove</button>
            </div>
          </div>
        </div>
        <div class="tog"><div><b>Salary negotiable</b><div class="s">You are open to discuss pay for the right role.</div></div><button class="sw${negOn}" type="button" id="neg"><i></i></button></div>
        <div class="tog"><div><b>Open to relocate</b><div class="s">Within Kerala or nearby districts.</div></div><button class="sw${relocOn}" type="button" id="reloc"><i></i></button></div>
        <div class="match">
          <div class="pdot">💼</div>
          <div><div class="n" id="matchN">38</div><div class="s">open roles may match this profile (demo estimate)</div></div>
        </div>`;
  bindStep4Events();
  renderResumeUi();
  matchCount();
}

function renderS5() {
  const s = sector();
  const p = position();
  const emp = C.employmentTypes.find((e) => e.code === state.emp)?.label;
  const salExpected = readExpectedSalaryValue();
  const loc = document.getElementById('loc').value;
  const qual = document.getElementById('qual').value;
  const bio = document.getElementById('desc').value.trim();
  if (!document.getElementById('profileName').value.trim()) {
    document.getElementById('profileName').placeholder = defaultProfileName();
  }
  document.getElementById('summary').innerHTML = [
    ['Job type', emp],
    ['Sector', s?.label],
    ['Position', p?.label + (state.types.length ? ' (' + state.types.join(', ') + ')' : '')],
    ['Qualification', qual || '—'],
    ['Experience', state.exp + ' years'],
    ['Skills', state.skills.join(', ') || '—'],
    ['Languages', state.languages.join(', ') || '—'],
    ['Bio', bio || '—'],
    ['Location', loc || '—'],
    ['Expected salary', (salExpected ? '₹' + salExpected : '—') + (state.neg ? ' (Negotiable)' : '')],
    ['Relocate', state.relocate ? 'Yes' : 'No'],
    ['Available to join', joinLabel(document.getElementById('joinAvail')?.value || state.availableToJoin)],
    ['Resume', state.resume?.fileName || '—'],
  ]
    .map(([k, v]) => `<div class="line"><span>${k}</span><b>${v}</b></div>`)
    .join('');
}
function matchCount() {
  const loc = document.getElementById('loc').value.length;
  const n = 10 + state.skills.length * 3 + state.types.length * 2 + state.languages.length * 2 + Math.min(18, loc);
  document.getElementById('matchN').textContent = n;
}

function renderProfiles() {
  const list = loadProfiles().sort((a, b) => (b.savedAt || '').localeCompare(a.savedAt || ''));
  const el = document.getElementById('profileList');
  if (!list.length) {
    el.innerHTML = '<div class="empty">No saved profiles yet.<br>Complete the wizard and tap Save profile.</div>';
    return;
  }
  el.innerHTML = list
    .map((pr) => {
      const when = pr.savedAt ? new Date(pr.savedAt).toLocaleString() : '';
      const sal = pr.salary?.expectedMonthly ?? pr.salary?.minMonthly;
      const salLine = sal ? '<br>Expected: ₹' + escapeHtml(String(sal)) + '/mo' : '';
      return `<div class="prof-card" data-id="${pr.id}">
        <b>${escapeHtml(pr.displayName || 'Untitled')}</b>
        <div class="meta">${escapeHtml(pr.position?.label || '')} · ${escapeHtml(pr.sector?.label || '')}<br>${escapeHtml(pr.employmentType?.label || '')} · ${escapeHtml(pr.location || '')}${salLine}${pr.availableToJoin?.label ? '<br>Join: ' + escapeHtml(pr.availableToJoin.label) : ''}${pr.resume?.fileName ? '<br>Resume: ' + escapeHtml(pr.resume.fileName) : ''}<br><small>Saved ${escapeHtml(when)}</small></div>
        <div class="acts">
          <button type="button" data-open="${pr.id}">Edit</button>
          <button type="button" class="del" data-del="${pr.id}">Delete</button>
        </div>
      </div>`;
    })
    .join('');
}
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function persistProfile() {
  const payload = buildPayload();
  if (!payload.sector?.id || !payload.position?.id) {
    toast('Complete sector and position before saving.');
    return;
  }
  if (!payload.languages.length) {
    toast('Select at least one language.');
    return;
  }
  const list = loadProfiles();
  const idx = list.findIndex((x) => x.id === payload.id);
  if (idx >= 0) list[idx] = payload;
  else list.push(payload);
  saveProfiles(list);
  state.editId = payload.id;
  const sal = payload.salary?.expectedMonthly;
  document.getElementById('doneTxt').textContent =
    'Saved “' +
    payload.displayName +
    '” · ' +
    payload.position.label +
    ' in ' +
    payload.sector.label +
    (sal ? ' · ₹' + sal + '/mo expected' : '') +
    (payload.availableToJoin?.label ? ' · Join: ' + payload.availableToJoin.label : '') +
    (payload.resume?.fileName ? ' · Resume: ' + payload.resume.fileName : '') +
    '.';
  show('s6');
}

function openSkills() {
  state.skillDraft = [...state.skills];
  state.skillFull = false;
  document.getElementById('skTitle').textContent = 'Add Skills';
  drawSkills();
  document.getElementById('skillSheet').classList.add('on');
}
function skillUniverse(full) {
  const p = position();
  const all = full ? [...p.suggestedSkills, ...p.moreSkills] : p.suggestedSkills;
  const q = document.getElementById('skSearch').value.trim().toLowerCase();
  return all.filter((x) => !q || x.toLowerCase().includes(q));
}
function drawSkills() {
  const full = state.skillFull;
  document.getElementById('skTitle').textContent = full ? 'All Skills' : 'Add Skills';
  document.getElementById('skMore').style.display = full ? 'none' : 'inline';
  const list = skillUniverse(full);
  document.getElementById('skList').innerHTML =
    list
      .map(
        (x) =>
          `<label class="ck"><input type="checkbox" ${state.skillDraft.includes(x) ? 'checked' : ''} data-sk="${x}"> ${x}</label>`,
      )
      .join('') || '<p class="sub">No skills match.</p>';
  syncSheetOkLabels();
}
function openSpec() {
  state.specDraft = [...state.types];
  drawSpec();
  document.getElementById('specSheet').classList.add('on');
}
function drawSpec() {
  const p = position();
  const q = document.getElementById('spSearch').value.trim().toLowerCase();
  const list = p.types.filter((t) => !q || t.toLowerCase().includes(q));
  document.getElementById('spList').innerHTML = list
    .map(
      (t) =>
        `<label class="ck"><input type="checkbox" ${state.specDraft.includes(t) ? 'checked' : ''} data-sp="${t}"> ${t}</label>`,
    )
    .join('');
  syncSheetOkLabels();
}
function openLangs() {
  state.langDraft = [...state.languages];
  drawLangs();
  document.getElementById('langSheet').classList.add('on');
}
function drawLangs() {
  const q = document.getElementById('lgSearch').value.trim().toLowerCase();
  const list = LANGUAGE_LIST.filter((l) => !q || l.toLowerCase().includes(q));
  document.getElementById('lgList').innerHTML =
    list
      .map(
        (l) =>
          `<label class="ck"><input type="checkbox" ${state.langDraft.includes(l) ? 'checked' : ''} data-lg="${l}"> ${l}</label>`,
      )
      .join('') || '<p class="sub">No language match.</p>';
  syncSheetOkLabels();
}
function toggleLang(l) {
  if (state.languages.includes(l)) state.languages = state.languages.filter((x) => x !== l);
  else state.languages = [...state.languages, l];
  renderS3();
}

function openMyProfiles() {
  renderProfiles();
  show('s7');
}

document.getElementById('empTypes').addEventListener('click', (e) => {
  const b = e.target.closest('[data-e]');
  if (!b) return;
  state.emp = b.dataset.e;
  renderS1();
});
document.getElementById('sectors').addEventListener('click', (e) => {
  const b = e.target.closest('[data-s]');
  if (!b) return;
  state.sectorId = b.dataset.s;
  state.positionId = null;
  state.types = [];
  state.skills = [];
  state.posLimit = 8;
  renderS1();
});
document.getElementById('c1').onclick = () => {
  show('s2');
  renderS2();
};
document.getElementById('posList').addEventListener('click', (e) => {
  const b = e.target.closest('[data-p]');
  if (!b) return;
  state.positionId = b.dataset.p;
  state.types = [];
  state.skills = [];
  renderS2();
});
document.getElementById('posSearch').oninput = () => {
  state.posLimit = 99;
  renderS2();
};
document.getElementById('morePos').onclick = () => {
  state.posLimit = 99;
  renderS2();
};
document.getElementById('c2').onclick = () => {
  show('s3');
  renderS3();
};
document.getElementById('typeChips').addEventListener('click', (e) => {
  const b = e.target.closest('[data-t]');
  if (!b) return;
  toggleType(b.getAttribute('data-t'));
});
document.getElementById('typeExtra').addEventListener('click', (e) => {
  const x = e.target.closest('[data-tx]');
  if (!x) return;
  toggleType(x.getAttribute('data-tx'));
});
document.getElementById('moreTypes').onclick = openSpec;
document.getElementById('expM').onclick = () => {
  state.exp = Math.max(0, state.exp - 1);
  renderS3();
};
document.getElementById('expP').onclick = () => {
  state.exp = Math.min(40, state.exp + 1);
  renderS3();
};
document.getElementById('addSkills').onclick = openSkills;
document.getElementById('langQuick').addEventListener('click', (e) => {
  const b = e.target.closest('[data-lq]');
  if (!b) return;
  toggleLang(b.dataset.lq);
});
document.getElementById('langChips').addEventListener('click', (e) => {
  const btn = e.target.closest('[data-lx]');
  if (!btn) return;
  toggleLang(btn.getAttribute('data-lx'));
});
document.getElementById('addLangs').onclick = openLangs;
document.getElementById('skillChips').addEventListener('click', (e) => {
  const x = e.target.dataset.x;
  if (!x) return;
  state.skills = state.skills.filter((s) => s !== x);
  renderS3();
});
document.getElementById('c3').onclick = () => {
  const p = position();
  if (p?.types?.length && !state.types.length) {
    toast('Select at least one type or specialization.');
    return;
  }
  if (!state.languages.length) {
    toast('Select at least one language.');
    return;
  }
  renderS4();
  show('s4');
};
bindClick('c4', () => {
  captureS4Draft();
  state.availableToJoin = el('joinAvail')?.value || state.availableToJoin || 'immediate';
  show('s5');
  renderS5();
});
document.getElementById('c5').onclick = () => persistProfile();

document.getElementById('skMore').onclick = () => {
  state.skillFull = true;
  drawSkills();
};
document.getElementById('skSearch').oninput = drawSkills;
document.getElementById('skList').addEventListener('change', (e) => {
  const sk = e.target.dataset.sk;
  if (!sk) return;
  if (e.target.checked) {
    if (!state.skillDraft.includes(sk)) state.skillDraft.push(sk);
  } else state.skillDraft = state.skillDraft.filter((x) => x !== sk);
  syncSheetOkLabels();
});
document.getElementById('skOk').onclick = () => {
  state.skills = [...state.skillDraft];
  document.getElementById('skillSheet').classList.remove('on');
  renderS3();
};
document.getElementById('skClose').onclick = () => document.getElementById('skillSheet').classList.remove('on');
document.getElementById('spSearch').oninput = drawSpec;
document.getElementById('spList').addEventListener('change', (e) => {
  const sp = e.target.dataset.sp;
  if (!sp) return;
  if (e.target.checked) {
    if (!state.specDraft.includes(sp)) state.specDraft.push(sp);
  } else state.specDraft = state.specDraft.filter((x) => x !== sp);
  syncSheetOkLabels();
});
document.getElementById('spOk').onclick = () => {
  if (!state.specDraft.length) {
    toast('Select at least one type or specialization.');
    return;
  }
  state.types = [...state.specDraft];
  document.getElementById('specSheet').classList.remove('on');
  renderS3();
};
document.getElementById('spClose').onclick = () => document.getElementById('specSheet').classList.remove('on');
document.getElementById('lgSearch').oninput = drawLangs;
document.getElementById('lgList').addEventListener('change', (e) => {
  const lg = e.target.dataset.lg;
  if (!lg) return;
  if (e.target.checked) {
    if (!state.langDraft.includes(lg)) state.langDraft.push(lg);
  } else state.langDraft = state.langDraft.filter((x) => x !== lg);
  syncSheetOkLabels();
});
document.getElementById('lgOk').onclick = () => {
  state.languages = [...state.langDraft];
  ensureDefaultLanguages();
  document.getElementById('langSheet').classList.remove('on');
  renderS3();
};
document.getElementById('lgClose').onclick = () => document.getElementById('langSheet').classList.remove('on');

document.querySelectorAll('[data-to]').forEach((b) =>
  b.addEventListener('click', () => {
    const id = b.getAttribute('data-to');
    show(id);
    if (id === 's1') renderS1();
    if (id === 's2') renderS2();
    if (id === 's3') renderS3();
    if (id === 's4') renderS4();
    if (id === 's5') renderS5();
  }),
);

['myProfiles', 'myProfiles2', 'myProfiles3', 'myProfiles4', 'myProfiles5'].forEach((id) => {
  const el = document.getElementById(id);
  if (el) el.onclick = openMyProfiles;
});
document.getElementById('viewSaved').onclick = openMyProfiles;
document.getElementById('another').onclick = () => {
  resetWizard(true);
  show('s1');
  renderS1();
};
document.getElementById('s1Back').onclick = () => toast('In the app this returns to Home / Jobs tab.');
document.getElementById('profileList').addEventListener('click', (e) => {
  const del = e.target.closest('[data-del]');
  if (del) {
    const id = del.getAttribute('data-del');
    saveProfiles(loadProfiles().filter((x) => x.id !== id));
    renderProfiles();
    toast('Profile deleted.');
    return;
  }
  const open = e.target.closest('[data-open]');
  if (!open) return;
  const pr = loadProfiles().find((x) => x.id === open.getAttribute('data-open'));
  if (!pr) return;
  applyPayload(pr);
  show('s1');
  renderS1();
  toast('Profile loaded — review steps or save again to update.');
});
document.getElementById('exportProfiles').onclick = () => {
  const json = JSON.stringify(loadProfiles(), null, 2);
  const done = () => toast('Copied ' + loadProfiles().length + ' profile(s) to clipboard.');
  const fail = () =>
    toast(json.slice(0, 120) + '… (clipboard blocked — use devtools Application → localStorage)');
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(json).then(done).catch(fail);
  } else {
    fail();
  }
};

function boot() {
  try {
    if (!el('sectors') || !el('empTypes')) {
      throw new Error(
        'Open seeker-job-profile-master.html (full file). If you edited the shell only, run: python3 docs/prototypes/_gen_seeker_profile_html.py',
      );
    }
    renderS4();
    renderS1();
    const tag = el('buildTag');
    if (tag) {
      tag.textContent =
        'Single-file demo ' +
        SEEKER_BUILD +
        ' — catalogue + app JS are inside this .html (no extra .js file).';
    }
  } catch (err) {
    console.error('[Gixbee seeker profile]', err);
    toast(err.message || String(err));
  }
}
boot();
