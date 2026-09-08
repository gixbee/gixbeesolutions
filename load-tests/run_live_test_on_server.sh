#!/usr/bin/env bash
set -euo pipefail

COUNT="${1:-100}"
TARGET="${2:-100}"
STEP="${3:-10}"

cd "$(dirname "$0")"
COMPOSE_DIR="${COMPOSE_DIR:-/home/ec2-user/gixbeesolutions}"

JWT_SECRET="$(docker exec gixbee-backend_rust-1 printenv JWT_SECRET 2>/dev/null || true)"
if [[ -z "$JWT_SECRET" ]]; then
  JWT_SECRET="$(docker exec gixbee-backend_rust-2 printenv JWT_SECRET 2>/dev/null || true)"
fi
if [[ -z "$JWT_SECRET" ]]; then
  echo "Could not read JWT_SECRET from backend_rust container"
  exit 1
fi

echo "Seeding $COUNT load-test workers..."
node seed_tokens.mjs --count "$COUNT" --jwt-secret "$JWT_SECRET"

PG_CONTAINER="$(docker ps --format '{{.Names}}' | grep postgres | head -1)"
docker exec -i "$PG_CONTAINER" psql -U postgres -d gixbee_db < seed_workers.sql

echo "Running live worker ramp to $TARGET..."
node go_live_test.js \
  --tokens-file tokens.json \
  --target "$TARGET" \
  --step "$STEP" \
  --delay 1500 \
  --duration 30 \
  --url http://127.0.0.1:3000

echo "Cleanup: marking load-test workers offline in DB..."
docker exec -i "$PG_CONTAINER" psql -U postgres -d gixbee_db < cleanup_workers.sql

GEO_COUNT="$(docker exec gixbee_redis redis-cli ZCARD workers:geo 2>/dev/null || echo '?')"
echo "Redis workers:geo count after cleanup: $GEO_COUNT"

bash "$(dirname "$0")/restart_backends.sh"
