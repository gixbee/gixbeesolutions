#!/usr/bin/env bash
# Restart API backends after a load test to release retained heap and Tokio pools.
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/home/ec2-user/gixbeesolutions}"
cd "$COMPOSE_DIR"

SERVICE=""
PROFILE=""

if docker ps --format '{{.Names}}' | grep -q 'backend_rust'; then
  SERVICE="backend_rust"
  PROFILE="rust"
elif docker ps --format '{{.Names}}' | grep -qE 'gixbee_backend|backend-1'; then
  SERVICE="backend"
  PROFILE="nest"
else
  echo "restart_backends: no running backend container found"
  exit 1
fi

REPLICAS="$(docker ps --filter "name=${SERVICE}" --format '{{.Names}}' | wc -l | tr -d ' ')"

echo "Memory before backend restart:"
free -h | awk '/^Mem:/{print "  used=" $3 "  available=" $7}'

echo "Restarting ${SERVICE} (${REPLICAS} replica(s), profile=${PROFILE})..."
COMPOSE_PROFILES="${PROFILE}" docker compose --profile "${PROFILE}" restart "${SERVICE}"

echo "Waiting for healthy backends..."
for _ in $(seq 1 45); do
  HEALTHY="$(docker ps --filter "name=${SERVICE}" --format '{{.Status}}' | grep -c healthy || true)"
  if [[ "${HEALTHY}" -ge "${REPLICAS}" ]]; then
    break
  fi
  sleep 2
done

HEALTHY="$(docker ps --filter "name=${SERVICE}" --format '{{.Status}}' | grep -c healthy || true)"
if [[ "${HEALTHY}" -lt "${REPLICAS}" ]]; then
  echo "Warning: only ${HEALTHY}/${REPLICAS} backend replicas report healthy"
  docker ps --filter "name=${SERVICE}"
  exit 1
fi

echo "Memory after backend restart:"
free -h | awk '/^Mem:/{print "  used=" $3 "  available=" $7}'
docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}}' | grep "${SERVICE}" || true

echo "Backend restart complete."
