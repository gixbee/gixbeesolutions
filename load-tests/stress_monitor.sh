#!/usr/bin/env bash
# Sample host memory/cpu while stress test runs.
LOG="${1:-/tmp/stress_test.log}"
INTERVAL="${2:-10}"

while pgrep -f 'go_live_test.js' >/dev/null 2>&1 || pgrep -f 'stress_to_failure' >/dev/null 2>&1; do
  TS="$(date +%T)"
  MEM="$(free -m | awk '/^Mem:/{printf "used=%sMB avail=%sMB", $3, $7}')"
  SWAP="$(free -m | awk '/^Swap:/{printf "swap=%sMB", $3}')"
  GEO="$(docker exec gixbee_redis redis-cli ZCARD workers:geo 2>/dev/null || echo '?')"
  HEALTH="$(docker ps --filter name=backend_rust --format '{{.Names}}:{{.Status}}' 2>/dev/null | tr '\n' ' ')"
  echo "[$TS] $MEM $SWAP geo=$GEO | $HEALTH" | tee -a "${LOG}.monitor"
  sleep "$INTERVAL"
done

echo "[$(date +%T)] Monitor stopped" | tee -a "${LOG}.monitor"
