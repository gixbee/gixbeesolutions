#!/bin/bash
set -euo pipefail
ROOT=/home/azureuser/gixbeesolutions
sed -i 's/\r$//' /tmp/mod.rs /tmp/hiring_needs_changes.sql /tmp/businesses.component.ts /tmp/admin-ops.service.ts
cp /tmp/mod.rs "$ROOT/backend_rust/src/businesses/mod.rs"
cp /tmp/hiring_needs_changes.sql "$ROOT/scripts/hiring_needs_changes.sql"
cp /tmp/businesses.component.ts "$ROOT/super-admin-web/src/app/features/businesses/businesses.component.ts"
cp /tmp/admin-ops.service.ts "$ROOT/super-admin-web/src/app/core/services/admin-ops.service.ts"
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -c "ALTER TYPE \"businesses_status_enum\" ADD VALUE IF NOT EXISTS 'NEEDS_CHANGES';"
echo SQL_OK
cd "$ROOT"
export COMPOSE_PROFILES=rust
docker compose up -d --scale backend_rust=1 backend_rust
nohup bash -c 'export COMPOSE_PROFILES=rust; cd /home/azureuser/gixbeesolutions; docker compose build backend_rust && docker compose up -d --scale backend_rust=2 backend_rust && docker compose build admin && docker compose up -d admin && docker image prune -f && echo HIRING_VERIFY_UP' > /tmp/hiring-verify-rebuild.log 2>&1 &
echo BUILD_PID=$!
echo BUILD_STARTED
