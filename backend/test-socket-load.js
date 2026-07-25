/**
 * Gixbee High-Concurrency Socket.IO Load Tester
 *
 * Verifies real-time connection scalability against the live AWS EC2 Nginx / NestJS backend.
 * Uses websocket-only transport to bypass Docker DNS round-robin polling session traps.
 */
const { io } = require('socket.io-client');

const TARGET_URL = process.env.TARGET_URL || 'http://13.233.60.215:3000';
const MAX_CONNECTIONS = parseInt(process.env.MAX_CONNECTIONS || '5000', 10);
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || '100', 10);
const BATCH_DELAY_MS = parseInt(process.env.BATCH_DELAY_MS || '250', 10);
const HOLD_TIME_SEC = parseInt(process.env.HOLD_TIME_SEC || '15', 10);

console.log('================================================================================');
console.log('🚀 GIXBEE SOCKET.IO CONCURRENCY LOAD TESTER');
console.log(`🎯 Target URL      : ${TARGET_URL}`);
console.log(`👥 Target Sockets  : ${MAX_CONNECTIONS.toLocaleString()}`);
console.log(`⚡ Ramp-up Rate    : ${BATCH_SIZE} sockets every ${BATCH_DELAY_MS}ms (${Math.round((BATCH_SIZE / BATCH_DELAY_MS) * 1000)}/sec)`);
console.log(`⏱️ Steady Hold Time: ${HOLD_TIME_SEC} seconds at peak concurrency`);
console.log('================================================================================\n');

const sockets = [];
let attempted = 0;
let connected = 0;
let disconnected = 0;
let connectErrors = 0;
const latencies = [];
let startTime = Date.now();
let peakConnected = 0;
let testFinished = false;

// Print live status table every 2 seconds
const statusTimer = setInterval(() => {
  if (testFinished) return;
  const avgLatency = latencies.length > 0
    ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length)
    : 0;
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  console.log(
    `[${elapsed}s] Active: ${connected.toLocaleString().padStart(5)} / ${MAX_CONNECTIONS.toLocaleString()} | ` +
    `Attempted: ${attempted.toLocaleString().padStart(5)} | ` +
    `Errors: ${connectErrors.toString().padStart(4)} | ` +
    `Dropped: ${disconnected.toString().padStart(4)} | ` +
    `Avg Handshake: ${avgLatency}ms`
  );
}, 2000);

function createSocket(index) {
  attempted++;
  const t0 = Date.now();

  const socket = io(TARGET_URL, {
    transports: ['websocket'], // CRITICAL: Bypass Nginx round-robin polling trap
    forceNew: true,
    reconnection: false,
    timeout: 10000,
  });

  socket.on('connect', () => {
    const handshakeTime = Date.now() - t0;
    latencies.push(handshakeTime);
    connected++;
    if (connected > peakConnected) {
      peakConnected = connected;
    }
  });

  socket.on('disconnect', (reason) => {
    if (socket || (socket && socket.connected)) {
      disconnected++;
      connected = Math.max(0, connected - 1);
    }
  });

  socket.on('connect_error', (err) => {
    connectErrors++;
    // Only log first 5 errors to avoid spamming terminal
    if (connectErrors <= 5) {
      console.error(`   [!] Connect Error (#${index}): ${err.message}`);
    } else if (connectErrors === 6) {
      console.error(`   [!] Suppressing further connect_error logs...`);
    }
  });

  sockets.push(socket);
}

function startRampUp() {
  let currentBatch = 0;
  const totalBatches = Math.ceil(MAX_CONNECTIONS / BATCH_SIZE);

  const batchTimer = setInterval(() => {
    if (testFinished) {
      clearInterval(batchTimer);
      return;
    }

    const startIdx = currentBatch * BATCH_SIZE;
    const endIdx = Math.min(startIdx + BATCH_SIZE, MAX_CONNECTIONS);

    for (let i = startIdx; i < endIdx; i++) {
      createSocket(i + 1);
    }

    currentBatch++;

    if (currentBatch >= totalBatches) {
      clearInterval(batchTimer);
      console.log(`\n✅ Ramp-up dispatch complete (${attempted.toLocaleString()} sockets initiated). Holding for steady-state evaluation...`);
      
      // Wait for handshakes to settle and hold for HOLD_TIME_SEC
      setTimeout(() => {
        finishTest();
      }, HOLD_TIME_SEC * 1000);
    }
  }, BATCH_DELAY_MS);
}

function finishTest() {
  testFinished = true;
  clearInterval(statusTimer);

  console.log('\n================================================================================');
  console.log('🏁 LOAD TEST FINAL RESULTS');
  console.log('================================================================================');
  console.log(`👥 Target Concurrency   : ${MAX_CONNECTIONS.toLocaleString()}`);
  console.log(`🔥 Peak Active Sockets  : ${peakConnected.toLocaleString()} (${Math.round((peakConnected / MAX_CONNECTIONS) * 100)}% Success Rate)`);
  console.log(`❌ Connection Errors    : ${connectErrors.toLocaleString()}`);
  console.log(`📉 Dropped Connections  : ${disconnected.toLocaleString()}`);
  
  if (latencies.length > 0) {
    const minLat = Math.min(...latencies);
    const maxLat = Math.max(...latencies);
    const avgLat = Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length);
    console.log(`⏱️ Handshake Latency    : Avg = ${avgLat}ms | Min = ${minLat}ms | Max = ${maxLat}ms`);
  } else {
    console.log(`⏱️ Handshake Latency    : N/A (No successful handshakes)`);
  }
  console.log('================================================================================\n');

  console.log('🧹 Disconnecting all test sockets...');
  for (const s of sockets) {
    try { s.close(); } catch (e) {}
  }
  console.log('✨ Cleanup complete. Exiting.');
  process.exit(0);
}

// Handle Ctrl+C gracefully
process.on('SIGINT', () => {
  console.log('\n[!] Test interrupted by user.');
  finishTest();
});

startRampUp();
