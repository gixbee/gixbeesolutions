#!/usr/bin/env bash
# Ramp live workers until the server fails or target is reached.
set -euo pipefail

cd "$(dirname "$0")"
COMPOSE_DIR="${COMPOSE_DIR:-/home/ec2-user/gixbeesolutions}"
LOG="${LOG:-/tmp/stress_test.log}"

COUNT="${1:-12000}"
TARGET="${2:-12000}"
STEP="${3:-200}"
DELAY_MS="${4:-1000}"
HOLD_SEC="${5:-60}"

run_node() {
  docker run --rm \
    -v /home/ec2-user/gixbeesolutions/load-tests:/app \
    -w /app \
    --network host \
    node:20-alpine \
    sh -c "npm install --omit=dev --silent && $1"
}

exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo "STRESS TEST $(date -Is)"
echo "  seed/target : ${COUNT} / ${TARGET}"
echo "  ramp        : +${STEP} every ${DELAY_MS}ms"
echo "  hold        : ${HOLD_SEC}s at peak"
echo "  log         : ${LOG}"
echo "============================================================"

JWT_SECRET="$(docker exec gixbee-backend_rust-1 printenv JWT_SECRET 2>/dev/null || docker exec gixbee-backend_rust-2 printenv JWT_SECRET)"

echo "[$(date +%T)] Seeding ${COUNT} workers..."
run_node "node seed_tokens.mjs --count ${COUNT} --jwt-secret '${JWT_SECRET}'"

echo "[$(date +%T)] Loading workers into Postgres..."
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db < seed_workers.sql

echo "[$(date +%T)] Memory before test:"
free -h

echo "[$(date +%T)] Starting go_live ramp..."
run_node "node go_live_test.js --tokens-file tokens.json --target ${TARGET} --step ${STEP} --delay ${DELAY_MS} --duration ${HOLD_SEC} --url http://127.0.0.1:3000" \
  || echo "[$(date +%T)] go_live_test exited with code $?"

echo "[$(date +%T)] Memory after test:"
free -h

echo "[$(date +%T)] Cleanup DB..."
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db < cleanup_workers.sql || true
GEO="$(docker exec gixbee_redis redis-cli ZCARD workers:geo 2>/dev/null || echo '?')"
echo "[$(date +%T)] workers:geo = ${GEO}"

if docker ps --filter name=backend_rust --format '{{.Status}}' | grep -q healthy; then
  bash "$(dirname "$0")/restart_backends.sh" || true
else
  echo "[$(date +%T)] Backends unhealthy — attempting compose up..."
  cd "${COMPOSE_DIR}"
  docker compose up -d backend_rust || true
fi

echo "[$(date +%T)] STRESS TEST DONE"
echo "============================================================"
