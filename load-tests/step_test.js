import { io } from 'socket.io-client';

// Parse command-line arguments
const args = process.argv.slice(2);
function getArg(name, defaultValue) {
  const index = args.findIndex(a => a.startsWith(`--${name}=`) || a === `--${name}`);
  if (index === -1) return defaultValue;
  if (args[index].includes('=')) return Number(args[index].split('=')[1]);
  return Number(args[index + 1]) || defaultValue;
}

const TARGET_USERS = getArg('target', 100);       // Max concurrent users to reach
const STEP_SIZE = getArg('step', 5);             // Number of users to add per batch
const STEP_DELAY_MS = getArg('delay', 1500);     // Milliseconds between adding batches
const BASE_URL = getArg('url', 'http://13.233.60.215:3000');
const TEST_DURATION_SEC = getArg('duration', 60); // How many seconds to run after reaching target

console.log(`\n🚀 GIXBEE STEP-BY-STEP LOAD TESTER`);
console.log(`====================================================`);
console.log(`🎯 Target Concurrency : ${TARGET_USERS} users`);
console.log(`📈 Step Increase      : +${STEP_SIZE} users every ${STEP_DELAY_MS / 1000}s`);
console.log(`🌐 Server Base URL    : ${BASE_URL}`);
console.log(`⏱️ Hold Peak Duration : ${TEST_DURATION_SEC}s after reaching target`);
console.log(`====================================================\n`);

// Stats tracking
let activeUsers = 0;
let connectedSockets = 0;
let httpRequests = 0;
let httpErrors = 0;
let socketErrors = 0;
let totalLatencyMs = 0;

const users = [];
let isShuttingDown = false;

// Function to simulate a single user's behavior
function spawnUser(id) {
  activeUsers++;

  // 1. Establish Socket.IO real-time connection
  const socket = io(BASE_URL, {
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionAttempts: 3,
    timeout: 5000,
  });

  socket.on('connect', () => {
    connectedSockets++;
    // Simulate joining a job room for tracking
    socket.emit('joinJobRoom', { jobId: `load-test-job-${id % 50}` });
  });

  socket.on('connect_error', (err) => {
    socketErrors++;
  });

  socket.on('disconnect', () => {
    connectedSockets = Math.max(0, connectedSockets - 1);
  });

  // 2. Simulate periodic GPS coordinate emissions (if even user ID, act as worker)
  const isWorker = id % 2 === 0;
  const gpsInterval = setInterval(() => {
    if (!socket.connected || isShuttingDown) return;
    if (isWorker) {
      socket.emit('updateLocation', {
        userId: `worker-${id}`,
        lat: 21.1458 + (Math.random() - 0.5) * 0.01,
        lng: 79.0882 + (Math.random() - 0.5) * 0.01,
        jobId: `load-test-job-${id % 50}`,
      });
    }
  }, 4000 + (id % 2000)); // Stagger GPS emissions between 4s and 6s

  // 3. Simulate periodic HTTP API requests (browsing deals, cities, home)
  const httpInterval = setInterval(async () => {
    if (isShuttingDown) return;
    const endpoints = [
      '/',
      '/master-entries?type=DEAL&isActive=true',
      '/cities',
    ];
    const targetEndpoint = endpoints[id % endpoints.length];
    const start = Date.now();
    try {
      const res = await fetch(`${BASE_URL}${targetEndpoint}`, { signal: AbortSignal.timeout(5000) });
      const duration = Date.now() - start;
      if (res.ok) {
        httpRequests++;
        totalLatencyMs += duration;
      } else {
        httpErrors++;
      }
    } catch (e) {
      httpErrors++;
    }
  }, 3000 + (id % 2000)); // Stagger HTTP requests between 3s and 5s

  users.push({ id, socket, gpsInterval, httpInterval });
}

// Console dashboard reporter
const reporter = setInterval(() => {
  const avgLatency = httpRequests > 0 ? (totalLatencyMs / httpRequests).toFixed(1) : '0.0';
  process.stdout.write(
    `\r⏱️ Active VUs: ${activeUsers.toString().padStart(4)} / ${TARGET_USERS} | ` +
    `🔌 Sockets: ${connectedSockets.toString().padStart(4)} | ` +
    `📡 HTTP Req: ${httpRequests.toString().padStart(6)} (Avg: ${avgLatency}ms) | ` +
    `❌ HTTP Err: ${httpErrors} | 💥 Socket Err: ${socketErrors}   `
  );
}, 1000);

// Step up loop
let currentCount = 0;
const stepTimer = setInterval(() => {
  if (currentCount >= TARGET_USERS) {
    clearInterval(stepTimer);
    console.log(`\n\n✅ Reached peak concurrency (${TARGET_USERS} users)! Holding for ${TEST_DURATION_SEC} seconds...`);
    setTimeout(shutdown, TEST_DURATION_SEC * 1000);
    return;
  }

  const toAdd = Math.min(STEP_SIZE, TARGET_USERS - currentCount);
  for (let i = 0; i < toAdd; i++) {
    currentCount++;
    spawnUser(currentCount);
  }
}, STEP_DELAY_MS);

function shutdown() {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log(`\n\n🛑 Test completed! Shutting down virtual users and disconnecting sockets...`);
  clearInterval(reporter);
  clearInterval(stepTimer);
  users.forEach(u => {
    clearInterval(u.gpsInterval);
    clearInterval(u.httpInterval);
    u.socket.disconnect();
  });
  console.log(`📊 Final Results:`);
  console.log(`   - Peak Users Reached : ${activeUsers}`);
  console.log(`   - Successful HTTP Req: ${httpRequests}`);
  console.log(`   - Failed HTTP Req    : ${httpErrors}`);
  console.log(`   - Socket Conn Errors : ${socketErrors}`);
  console.log(`   - Avg HTTP Latency   : ${httpRequests > 0 ? (totalLatencyMs / httpRequests).toFixed(1) : 0} ms`);
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
