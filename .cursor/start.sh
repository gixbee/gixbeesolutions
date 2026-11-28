#!/usr/bin/env bash
#
# Gixbee Cloud Agent — per-boot service startup.
#
# Brings up the infrastructure the backend needs (PostgreSQL + Redis). It is
# idempotent: it tolerates services already running, ensures the dev role /
# database exist, waits for readiness, and then returns. The backend API
# itself runs as a long-lived terminal (see .cursor/environment.json).
set -euo pipefail

echo "== PostgreSQL =="
# Detect the installed cluster version (16 on Ubuntu 24.04) so this keeps
# working if the base image ships a different major version.
PGVER="$(ls /etc/postgresql 2>/dev/null | sort -n | tail -1 || true)"
if [ -n "$PGVER" ]; then
  sudo pg_ctlcluster "$PGVER" main start 2>/dev/null || true
fi

for _ in $(seq 1 30); do
  if sudo -u postgres pg_isready -q 2>/dev/null; then break; fi
  sleep 1
done

# Ensure the dev password + database exist (idempotent).
sudo -u postgres psql -tAc "ALTER USER postgres PASSWORD 'postgres';" >/dev/null
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='gixbee'" | grep -q 1; then
  sudo -u postgres createdb gixbee
fi
echo "  PostgreSQL: $(sudo -u postgres pg_isready 2>/dev/null || echo 'not ready')"

echo "== Redis =="
if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
  # --dir keeps the RDB dump out of the checked-out repo.
  sudo mkdir -p /var/lib/redis
  sudo redis-server --daemonize yes --port 6379 --dir /var/lib/redis
fi
for _ in $(seq 1 15); do
  if redis-cli -p 6379 ping >/dev/null 2>&1; then break; fi
  sleep 1
done
echo "  Redis: $(redis-cli -p 6379 ping 2>/dev/null || echo 'not ready')"

echo ""
echo "Infrastructure ready. The 'backend' terminal serves the API on http://localhost:3000."
