/**
 * Gixbee Combined 10,000 Concurrency Stress Tester (Sockets + Active App Users)
 *
 * Simulates the ultimate production stress test:
 * 1. Phase 1: Smoothly connects 10,000 real-time Socket.IO WebSocket clients.
 * 2. Phase 2: While 10,000 sockets hold steady, ramps up 10,000 active mobile app users executing PostgreSQL database queries.
 * 3. Phase 3: Evaluates peak steady-state performance under 20,000 simultaneous network clients on the AWS EC2 server.
 */
const { io } = require('socket.io-client');

const TARGET_URL = (process.env.TARGET_URL || 'http://api_balancer:3000').replace(/\/$/, '');
const TARGET_SOCKETS = parseInt(process.env.TARGET_SOCKETS || '10000', 10);
const TARGET_HTTP_USERS = parseInt(process.env.TARGET_HTTP_USERS || '10000', 10);
const HOLD_TIME_SEC = parseInt(process.env.HOLD_TIME_SEC || '15', 10);

// Socket Ramp-up Settings: 200 sockets every 250ms (800/sec) -> ~12.5s ramp-up
const SOCKET_BATCH_SIZE = 200;
const SOCKET_BATCH_DELAY_MS = 250;

// HTTP Ramp-up Settings: Ramp over 10 seconds
const HTTP_RAMP_UP_SEC = 10;
const MIN_THINK_TIME_MS = 1000;
const MAX_THINK_TIME_MS = 3000;

console.log('================================================================================');
console.log('🚀 GIXBEE COMBINED 20,000 CONCURRENCY STRESS TEST (10k Sockets + 10k HTTP Users)');
console.log(`🎯 Target Endpoint     : ${TARGET_URL}`);
console.log(`🔌 Target Sockets      : ${TARGET_SOCKETS.toLocaleString()} real-time WebSocket connections`);
console.log(`📱 Target Active Users : ${TARGET_HTTP_USERS.toLocaleString()} concurrent HTTP database users`);
console.log(`⏱️ Peak Hold Duration  : ${HOLD_TIME_SEC} seconds under combined 20k client load`);
console.log('================================================================================\n');

// --- Socket.IO Metrics ---
const sockets = [];
let socketAttempted = 0;
let socketConnected = 0;
let socketDisconnected = 0;
let socketErrors = 0;
const socketLatencies = [];
let peakSockets = 0;

// --- HTTP API Metrics ---
const ENDPOINTS = [
  { name: 'Browse Cities (PostgreSQL Query)', path: '/cities' },
  { name: 'Browse Service Categories (PostgreSQL Query)', path: '/master-entries' }
];
let httpActiveUsers = 0;
let httpTotalRequests = 0;
let http2xx = 0;
let http429 = 0;
let http4xx = 0;
let http5xx = 0;
let httpNetworkErrors = 0;
const httpLatencies = [];

let startTime = Date.now();
let testPhase = 'PHASE 1: SOCKET RAMP-UP (10k Sockets)';
let testRunning = true;

// Helper for HTTP think time
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const getRandomThinkTime = () => Math.floor(Math.random() * (MAX_THINK_TIME_MS - MIN_THINK_TIME_MS + 1)) + MIN_THINK_TIME_MS;

// Unified Live Monitor
const statusTimer = setInterval(() => {
  if (!testRunning) return;
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  const rps = Math.round(httpTotalRequests / (elapsed || 1));
  const avgHttpLat = httpLatencies.length > 0 ? Math.round(httpLatencies.reduce((a, b) => a + b, 0) / httpLatencies.length) : 0;
  const avgSocketLat = socketLatencies.length > 0 ? Math.round(socketLatencies.reduce((a, b) => a + b, 0) / socketLatencies.length) : 0;

  console.log(`\n--- [${elapsed}s] ${testPhase} ---`);
  console.log(
    `🔌 SOCKETS  : ${socketConnected.toLocaleString().padStart(5)} / ${TARGET_SOCKETS.toLocaleString()} Active | ` +
    `Attempted: ${socketAttempted.toLocaleString().padStart(5)} | ` +
    `Dropped: ${socketDisconnected.toString().padStart(4)} | ` +
    `Errors: ${socketErrors.toString().padStart(4)} | ` +
    `Avg Handshake: ${avgSocketLat}ms`
  );
  console.log(
    `📱 HTTP API : ${httpActiveUsers.toLocaleString().padStart(5)} / ${TARGET_HTTP_USERS.toLocaleString()} Users  | ` +
    `Throughput: ${rps.toString().padStart(4)} req/s | ` +
    `2xx OK: ${http2xx.toLocaleString().padStart(5)} | ` +
    `5xx Err: ${http5xx.toString().padStart(3)} | ` +
    `Avg DB Latency: ${avgHttpLat}ms`
  );
}, 3000);

// --- Phase 1: Socket Creator ---
function createSocket(index) {
  socketAttempted++;
  const t0 = Date.now();

  const socket = io(TARGET_URL, {
    transports: ['websocket'],
    forceNew: true,
    reconnection: false,
    timeout: 10000,
  });

  socket.on('connect', () => {
    const handshakeTime = Date.now() - t0;
    socketLatencies.push(handshakeTime);
    socketConnected++;
    if (socketConnected > peakSockets) {
      peakSockets = socketConnected;
    }
  });

  socket.on('disconnect', () => {
    if (socket || (socket && socket.connected)) {
      socketDisconnected++;
      socketConnected = Math.max(0, socketConnected - 1);
    }
  });

  socket.on('connect_error', (err) => {
    socketErrors++;
    if (socketErrors <= 3) {
      console.error(`   [!] Socket Connect Error (#${index}): ${err.message}`);
    } else if (socketErrors === 4) {
      console.error(`   [!] Suppressing further socket connect_error logs...`);
    }
  });

  sockets.push(socket);
}

function startSocketRampUp() {
  let currentBatch = 0;
  const totalBatches = Math.ceil(TARGET_SOCKETS / SOCKET_BATCH_SIZE);

  const batchTimer = setInterval(() => {
    if (!testRunning) {
      clearInterval(batchTimer);
      return;
    }

    const startIdx = currentBatch * SOCKET_BATCH_SIZE;
    const endIdx = Math.min(startIdx + SOCKET_BATCH_SIZE, TARGET_SOCKETS);

    for (let i = startIdx; i < endIdx; i++) {
      createSocket(i + 1);
    }

    currentBatch++;

    if (currentBatch >= totalBatches) {
      clearInterval(batchTimer);
      console.log(`\n✅ Phase 1 Complete: 10,000 sockets initiated. Transitioning to Phase 2 (Ramping up 10k Active HTTP Users)...`);
      
      // Let sockets settle for 3 seconds before hitting database with HTTP users
      setTimeout(() => {
        startHttpRampUp();
      }, 3000);
    }
  }, SOCKET_BATCH_DELAY_MS);
}

// --- Phase 2: HTTP Virtual User ---
async function runVirtualUser(userId) {
  httpActiveUsers++;
  let stepIdx = Math.floor(Math.random() * ENDPOINTS.length);

  while (testRunning) {
    const endpoint = ENDPOINTS[stepIdx % ENDPOINTS.length];
    stepIdx++;

    const t0 = Date.now();
    httpTotalRequests++;

    try {
      const res = await fetch(`${TARGET_URL}${endpoint.path}`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'User-Agent': `GixbeeCombinedTester/1.0 (User/${userId})`
        }
      });

      const duration = Date.now() - t0;
      httpLatencies.push(duration);

      if (res.status >= 200 && res.status < 300) {
        http2xx++;
      } else if (res.status === 429) {
        http429++;
      } else if (res.status >= 400 && res.status < 500) {
        http4xx++;
      } else if (res.status >= 500) {
        http5xx++;
      }

      await res.text().catch(() => {});
    } catch (err) {
      httpNetworkErrors++;
    }

    if (!testRunning) break;
    await sleep(getRandomThinkTime());
  }

  httpActiveUsers--;
}

function startHttpRampUp() {
  testPhase = 'PHASE 2: HTTP USER RAMP-UP (10k Sockets + Ramping HTTP Users)';
  const delayBetweenUsersMs = (HTTP_RAMP_UP_SEC * 1000) / TARGET_HTTP_USERS;

  for (let i = 0; i < TARGET_HTTP_USERS; i++) {
    setTimeout(() => {
      if (testRunning) {
        runVirtualUser(i + 1);
      }
    }, i * delayBetweenUsersMs);
  }

  // Schedule Phase 3 (Steady State Hold)
  setTimeout(() => {
    testPhase = 'PHASE 3: PEAK STEADY STATE (10k Sockets + 10k Active Users)';
    console.log(`\n🔥 Phase 2 Complete: All 20,000 clients active! Holding steady state for ${HOLD_TIME_SEC} seconds...`);

    setTimeout(() => {
      finishTest();
    }, HOLD_TIME_SEC * 1000);
  }, HTTP_RAMP_UP_SEC * 1000);
}

function finishTest() {
  testRunning = false;
  clearInterval(statusTimer);

  const totalDurationSec = Math.round((Date.now() - startTime) / 1000);
  const rps = Math.round(httpTotalRequests / (totalDurationSec || 1));
  const httpSuccessRate = httpTotalRequests > 0 ? Math.round((http2xx / httpTotalRequests) * 100) : 0;
  const socketSuccessRate = Math.round((peakSockets / TARGET_SOCKETS) * 100);

  httpLatencies.sort((a, b) => a - b);
  const minHttpLat = httpLatencies[0] || 0;
  const maxHttpLat = httpLatencies[httpLatencies.length - 1] || 0;
  const avgHttpLat = httpLatencies.length > 0 ? Math.round(httpLatencies.reduce((a, b) => a + b, 0) / httpLatencies.length) : 0;
  const p50Http = httpLatencies[Math.floor(httpLatencies.length * 0.50)] || 0;
  const p90Http = httpLatencies[Math.floor(httpLatencies.length * 0.90)] || 0;
  const p99Http = httpLatencies[Math.floor(httpLatencies.length * 0.99)] || 0;

  console.log('\n================================================================================');
  console.log('🏁 COMBINED 20,000 CONCURRENCY STRESS TEST FINAL RESULTS');
  console.log('================================================================================');
  console.log('🔌 1. REAL-TIME SOCKET.IO WEBSOCKET SCALABILITY (Target: 10,000)');
  console.log(`   🔥 Peak Active Sockets  : ${peakSockets.toLocaleString()} (${socketSuccessRate}% Success Rate)`);
  console.log(`   📉 Dropped Sockets      : ${socketDisconnected.toLocaleString()} (Steady-state churn)`);
  console.log(`   ❌ Connection Errors    : ${socketErrors.toLocaleString()}`);
  console.log('--------------------------------------------------------------------------------');
  console.log('📱 2. ACTIVE APP USER DATABASE QUERY SCALABILITY (Target: 10,000)');
  console.log(`   👥 Peak Active Users    : ${httpActiveUsers.toLocaleString()} concurrent users`);
  console.log(`   📡 Total API Requests   : ${httpTotalRequests.toLocaleString()} (${rps.toLocaleString()} req/sec average)`);
  console.log(`   ✅ Success Rate (200 OK): ${http2xx.toLocaleString()} (${httpSuccessRate}%)`);
  console.log(`   ⚠️ Rate Limited (429)   : ${http429.toLocaleString()}`);
  console.log(`   ❌ Client Errors (4xx)  : ${http4xx.toLocaleString()}`);
  console.log(`   💥 Server Errors (5xx)  : ${http5xx.toLocaleString()} (Database/Server Crashes)`);
  console.log(`   🔌 Network Timeouts/Err : ${httpNetworkErrors.toLocaleString()}`);
  console.log('--------------------------------------------------------------------------------');
  console.log('📊 3. DATABASE QUERY LATENCY DISTRIBUTION (Under 20,000 Client Stress):');
  console.log(`   Avg = ${avgHttpLat}ms | Min = ${minHttpLat}ms | Max = ${maxHttpLat}ms`);
  console.log(`   p50 (Median) = ${p50Http}ms`);
  console.log(`   p90          = ${p90Http}ms`);
  console.log(`   p99 (Tail)   = ${p99Http}ms`);
  console.log('================================================================================\n');

  console.log('🧹 Closing all sockets and cleaning up...');
  for (const s of sockets) {
    try { s.close(); } catch (e) {}
  }
  console.log('✨ Cleanup complete. Exiting.');
  process.exit(0);
}

process.on('SIGINT', () => {
  console.log('\n[!] Test interrupted by user.');
  finishTest();
});

startSocketRampUp();
