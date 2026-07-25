/**
 * Gixbee App Active User Concurrency & Traffic Simulator
 *
 * Simulates real-world active mobile app users browsing and searching the platform.
 * Each virtual user cycles through typical app screens (cities, services, worker search, rentals, jobs)
 * with realistic reading pauses between requests.
 *
 * Runs natively in Node.js >= 18 using built-in fetch (zero dependencies required).
 */

const TARGET_URL = (process.env.TARGET_URL || 'http://13.233.60.215:3000').replace(/\/$/, '');
const CONCURRENT_USERS = parseInt(process.env.CONCURRENT_USERS || '1000', 10);
const TEST_DURATION_SEC = parseInt(process.env.TEST_DURATION_SEC || '20', 10);
const RAMP_UP_SEC = parseInt(process.env.RAMP_UP_SEC || '5', 10);
const MIN_THINK_TIME_MS = parseInt(process.env.MIN_THINK_TIME_MS || '500', 10);
const MAX_THINK_TIME_MS = parseInt(process.env.MAX_THINK_TIME_MS || '2000', 10);

console.log('================================================================================');
console.log('📱 GIXBEE ACTIVE APP USER CONCURRENCY SIMULATOR');
console.log(`🎯 Target API Base : ${TARGET_URL}`);
console.log(`👥 Virtual Users   : ${CONCURRENT_USERS.toLocaleString()} concurrent users`);
console.log(`⚡ Ramp-Up Period  : ${RAMP_UP_SEC} seconds (${Math.round(CONCURRENT_USERS / RAMP_UP_SEC)} new users/sec)`);
console.log(`⏱️ Test Duration   : ${TEST_DURATION_SEC} seconds`);
console.log(`🧠 User Think Time : ${MIN_THINK_TIME_MS}ms - ${MAX_THINK_TIME_MS}ms between screen taps`);
console.log('================================================================================\n');

const ENDPOINTS = [
  { name: 'Browse Cities (PostgreSQL Query)', path: '/cities' },
  { name: 'Browse Service Categories (PostgreSQL Query)', path: '/master-entries' }
];

let activeUsers = 0;
let totalRequests = 0;
let success2xx = 0;
let rateLimit429 = 0;
let clientError4xx = 0;
let serverError5xx = 0;
let networkErrors = 0;
const latencies = [];
let startTime = Date.now();
let testRunning = true;

// Helper for random user pause between taps
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const getRandomThinkTime = () => Math.floor(Math.random() * (MAX_THINK_TIME_MS - MIN_THINK_TIME_MS + 1)) + MIN_THINK_TIME_MS;

// Virtual User Session Loop
async function runVirtualUser(userId) {
  activeUsers++;
  let stepIdx = Math.floor(Math.random() * ENDPOINTS.length); // Start at random screen

  while (testRunning) {
    const endpoint = ENDPOINTS[stepIdx % ENDPOINTS.length];
    stepIdx++;

    const t0 = Date.now();
    totalRequests++;

    try {
      const res = await fetch(`${TARGET_URL}${endpoint.path}`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'User-Agent': `GixbeeMobileApp/1.0.0 (VirtualUser/${userId})`
        }
      });

      const duration = Date.now() - t0;
      latencies.push(duration);

      if (res.status >= 200 && res.status < 300) {
        success2xx++;
      } else if (res.status === 429) {
        rateLimit429++;
      } else if (res.status >= 400 && res.status < 500) {
        clientError4xx++;
      } else if (res.status >= 500) {
        serverError5xx++;
      }

      // Consume body to free socket cleanly
      await res.text().catch(() => {});
    } catch (err) {
      networkErrors++;
    }

    if (!testRunning) break;
    await sleep(getRandomThinkTime());
  }

  activeUsers--;
}

// Live Status Logger
const statusTimer = setInterval(() => {
  if (!testRunning) return;
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  const rps = Math.round(totalRequests / (elapsed || 1));
  const avgLat = latencies.length > 0 ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length) : 0;
  
  console.log(
    `[${elapsed}s] Active Users: ${activeUsers.toLocaleString().padStart(5)} / ${CONCURRENT_USERS.toLocaleString()} | ` +
    `Throughput: ${rps.toString().padStart(4)} req/s | ` +
    `2xx OK: ${success2xx.toLocaleString()} | ` +
    `429 RateLimit: ${rateLimit429} | ` +
    `5xx Err: ${serverError5xx} | ` +
    `Avg Latency: ${avgLat}ms`
  );
}, 2000);

// Ramp up virtual users smoothly
function startSimulation() {
  startTime = Date.now();
  const delayBetweenUsersMs = (RAMP_UP_SEC * 1000) / CONCURRENT_USERS;
  
  for (let i = 0; i < CONCURRENT_USERS; i++) {
    setTimeout(() => {
      if (testRunning) {
        runVirtualUser(i + 1);
      }
    }, i * delayBetweenUsersMs);
  }

  // Schedule Test Completion
  setTimeout(() => {
    finishTest();
  }, (RAMP_UP_SEC + TEST_DURATION_SEC) * 1000);
}

function finishTest() {
  testRunning = false;
  clearInterval(statusTimer);

  const totalDurationSec = Math.round((Date.now() - startTime) / 1000);
  const rps = Math.round(totalRequests / (totalDurationSec || 1));
  const successRate = totalRequests > 0 ? Math.round((success2xx / totalRequests) * 100) : 0;

  latencies.sort((a, b) => a - b);
  const minLat = latencies[0] || 0;
  const maxLat = latencies[latencies.length - 1] || 0;
  const avgLat = latencies.length > 0 ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length) : 0;
  const p50 = latencies[Math.floor(latencies.length * 0.50)] || 0;
  const p90 = latencies[Math.floor(latencies.length * 0.90)] || 0;
  const p99 = latencies[Math.floor(latencies.length * 0.99)] || 0;

  console.log('\n================================================================================');
  console.log('🏁 ACTIVE APP USER CONCURRENCY TEST RESULTS');
  console.log('================================================================================');
  console.log(`👥 Peak Active Users    : ${activeUsers.toLocaleString()} concurrent users`);
  console.log(`⏱️ Total Test Duration  : ${totalDurationSec} seconds`);
  console.log(`📡 Total API Requests   : ${totalRequests.toLocaleString()} (${rps.toLocaleString()} req/sec average)`);
  console.log(`✅ Success Rate (2xx)   : ${success2xx.toLocaleString()} (${successRate}%)`);
  console.log(`⚠️ Rate Limited (429)   : ${rateLimit429.toLocaleString()}`);
  console.log(`❌ Client Errors (4xx)  : ${clientError4xx.toLocaleString()}`);
  console.log(`💥 Server Errors (5xx)  : ${serverError5xx.toLocaleString()}`);
  console.log(`🔌 Network Timeouts/Err : ${networkErrors.toLocaleString()}`);
  console.log('--------------------------------------------------------------------------------');
  console.log(`📊 Response Latency Distribution:`);
  console.log(`   Avg = ${avgLat}ms | Min = ${minLat}ms | Max = ${maxLat}ms`);
  console.log(`   p50 (Median) = ${p50}ms`);
  console.log(`   p90          = ${p90}ms`);
  console.log(`   p99 (Tail)   = ${p99}ms`);
  console.log('================================================================================\n');

  process.exit(0);
}

process.on('SIGINT', () => {
  console.log('\n[!] Simulation interrupted by user.');
  finishTest();
});

startSimulation();
