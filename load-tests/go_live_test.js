import { readFileSync } from 'fs';
import { io } from 'socket.io-client';

const args = process.argv.slice(2);
function getArg(name, defaultValue) {
  const eq = args.find((a) => a.startsWith(`--${name}=`));
  if (eq) return eq.split('=').slice(1).join('=');
  const index = args.indexOf(`--${name}`);
  if (index === -1) return defaultValue;
  const next = args[index + 1];
  if (next === undefined || next.startsWith('--')) return defaultValue;
  return next;
}

const TARGET_USERS = Number(getArg('target', 50));
const STEP_SIZE = Number(getArg('step', 5));
const STEP_DELAY_MS = Number(getArg('delay', 2000));
const BASE_URL = getArg('url', 'http://13.233.60.215:3000');
const HOLD_SEC = Number(getArg('duration', 45));
const TOKENS_FILE = getArg('tokens-file', 'tokens.json');
const LOCATION_INTERVAL_MS = Number(getArg('location-interval', 5000));

let workers = [];
try {
  workers = JSON.parse(readFileSync(TOKENS_FILE, 'utf8'));
} catch (e) {
  console.error(`Failed to read tokens file: ${TOKENS_FILE}`);
  console.error('Run: node seed_tokens.mjs --count N --jwt-secret <secret> first');
  process.exit(1);
}

if (workers.length < TARGET_USERS) {
  console.warn(`Warning: only ${workers.length} tokens available, capping target at that.`);
}

const effectiveTarget = Math.min(TARGET_USERS, workers.length);

console.log('\nGIXBEE LIVE WORKER CONCURRENCY TEST');
console.log('====================================================');
console.log(`Target live workers : ${effectiveTarget}`);
console.log(`Step                : +${STEP_SIZE} every ${STEP_DELAY_MS / 1000}s`);
console.log(`Server              : ${BASE_URL}`);
console.log(`Hold at peak        : ${HOLD_SEC}s`);
console.log('====================================================\n');

let active = 0;
let liveOk = 0;
let liveFail = 0;
let socketsConnected = 0;
let peakSocketsConnected = 0;
let socketErrors = 0;
let locationOk = 0;
let locationFail = 0;

const sessions = [];
let shuttingDown = false;

function baseLat(id) {
  return 21.1458 + ((id % 20) - 10) * 0.002;
}

function baseLng(id) {
  return 79.0882 + ((id % 20) - 10) * 0.002;
}

async function goLive(worker, index) {
  const lat = baseLat(index);
  const lng = baseLng(index);
  const res = await fetch(`${BASE_URL}/workers/live-toggle`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${worker.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ active: true, lat, lng }),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`live-toggle ${res.status}: ${text.slice(0, 120)}`);
  }
  return { lat, lng };
}

async function goOffline(worker) {
  try {
    await fetch(`${BASE_URL}/workers/live-toggle`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${worker.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ active: false }),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    // best effort cleanup
  }
}

async function spawnWorker(worker, index) {
  active++;
  let coords = { lat: baseLat(index), lng: baseLng(index) };

  try {
    coords = await goLive(worker, index);
    liveOk++;
  } catch {
    liveFail++;
    active--;
    return;
  }

  const socket = io(BASE_URL, {
    transports: ['websocket'],
    auth: { token: worker.token },
    reconnection: false,
    timeout: 10000,
  });

  const session = { worker, socket, locationTimer: null, index };

  socket.on('connect', () => {
    socketsConnected++;
    peakSocketsConnected = Math.max(peakSocketsConnected, socketsConnected);
    socket.emit('joinUserRoom', {}, (ack) => {
      if (ack?.error) socketErrors++;
    });
  });

  socket.on('connect_error', () => {
    socketErrors++;
  });

  socket.on('disconnect', () => {
    socketsConnected = Math.max(0, socketsConnected - 1);
  });

  session.locationTimer = setInterval(() => {
    if (!socket.connected || shuttingDown) return;
    socket.emit('updateLocation', {
      lat: coords.lat + (Math.random() - 0.5) * 0.0005,
      lng: coords.lng + (Math.random() - 0.5) * 0.0005,
    });
    locationOk++;
  }, LOCATION_INTERVAL_MS + (index % 1000));

  sessions.push(session);
}

const reporter = setInterval(() => {
  process.stdout.write(
    `\rActive: ${active.toString().padStart(4)}/${effectiveTarget} | ` +
      `Live OK: ${liveOk} Fail: ${liveFail} | ` +
      `Sockets: ${socketsConnected} err ${socketErrors} | ` +
      `GPS: ${locationOk}   `
  );
}, 1000);

let current = 0;
const stepTimer = setInterval(() => {
  if (current >= effectiveTarget) {
    clearInterval(stepTimer);
    console.log(`\n\nReached peak (${effectiveTarget} live workers). Holding ${HOLD_SEC}s...`);
    setTimeout(shutdown, HOLD_SEC * 1000);
    return;
  }
  const batch = Math.min(STEP_SIZE, effectiveTarget - current);
  for (let i = 0; i < batch; i++) {
    current++;
    spawnWorker(workers[current - 1], current);
  }
}, STEP_DELAY_MS);

async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  clearInterval(reporter);
  clearInterval(stepTimer);
  console.log('\n\nShutting down: taking workers offline...');

  for (const s of sessions) {
    clearInterval(s.locationTimer);
    s.socket.disconnect();
    await goOffline(s.worker);
  }

  const liveSuccessRate = liveOk + liveFail > 0 ? ((liveOk / (liveOk + liveFail)) * 100).toFixed(1) : '0';
  console.log('\nFinal results');
  console.log(`  Peak attempted       : ${current}`);
  console.log(`  Live toggle success  : ${liveOk}`);
  console.log(`  Live toggle failed   : ${liveFail}`);
  console.log(`  Live success rate    : ${liveSuccessRate}%`);
  console.log(`  Sockets connected    : ${peakSocketsConnected} (peak)`);
  console.log(`  Socket errors        : ${socketErrors}`);
  console.log(`  Location updates sent: ${locationOk}`);

  if (liveFail === 0 && peakSocketsConnected >= liveOk * 0.9) {
    console.log(`\nServer handled ${liveOk} concurrent LIVE workers with working sockets.`);
  } else if (liveOk > 0 && peakSocketsConnected === 0) {
    console.log(`\nLive toggle OK (${liveOk}) but sockets failed — check Socket.IO namespace/auth.`);
  } else if (liveFail > 0) {
    console.log(`\nCapacity limit near ${liveOk} live workers (${liveFail} live-toggle failures).`);
  } else {
    console.log(`\nPartial: ${liveOk} live, ${peakSocketsConnected} sockets at peak.`);
  }

  process.exit(liveFail > 0 && liveOk === 0 ? 1 : 0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
