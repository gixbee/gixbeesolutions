#!/usr/bin/env bash
set -euo pipefail
cd /home/ec2-user/gixbeesolutions/load-tests

COUNT="${1:-120}"
TARGET="${2:-120}"
STEP="${3:-10}"

JWT_SECRET="$(docker exec gixbee-backend_rust-1 printenv JWT_SECRET)"

docker run --rm \
  -v /home/ec2-user/gixbeesolutions/load-tests:/app \
  -w /app \
  --network host \
  node:20-alpine \
  sh -c "npm install --omit=dev && node seed_tokens.mjs --count ${COUNT} --jwt-secret '${JWT_SECRET}'"

docker exec -i gixbee_postgres psql -U postgres -d gixbee_db < seed_workers.sql

docker run --rm \
  -v /home/ec2-user/gixbeesolutions/load-tests:/app \
  -w /app \
  --network host \
  node:20-alpine \
  sh -c "npm install --omit=dev && node go_live_test.js --tokens-file tokens.json --target ${TARGET} --step ${STEP} --delay 1500 --duration 30 --url http://127.0.0.1:3000"

docker exec -i gixbee_postgres psql -U postgres -d gixbee_db < cleanup_workers.sql
GEO="$(docker exec gixbee_redis redis-cli ZCARD workers:geo)"
echo "workers:geo after cleanup = ${GEO}"

bash "$(dirname "$0")/restart_backends.sh"
