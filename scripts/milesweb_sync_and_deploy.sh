#!/bin/bash
set -euo pipefail
ROOT=/root/gixbeesolutions
ARCHIVE=/tmp/gixbee-milesweb.tgz
BACKUP_ENV=/tmp/gixbee_backend.env.bak
BACKUP_FB=/tmp/gixbee_firebase.json.bak
BACKUP_ROOT_ENV=/tmp/gixbee_root.env.bak

if [[ -f "$ROOT/deploy/.env" ]]; then cp "$ROOT/deploy/.env" "$BACKUP_ENV";
elif [[ -f "$ROOT/backend/.env" ]]; then cp "$ROOT/backend/.env" "$BACKUP_ENV"; fi
if [[ -f "$ROOT/deploy/firebase-service-account.json" ]]; then cp "$ROOT/deploy/firebase-service-account.json" "$BACKUP_FB";
elif [[ -f "$ROOT/backend/firebase-service-account.json" ]]; then cp "$ROOT/backend/firebase-service-account.json" "$BACKUP_FB"; fi
if [[ -f "$ROOT/.env" ]]; then cp "$ROOT/.env" "$BACKUP_ROOT_ENV"; fi

rm -rf /root/gixbeesolutions_new
mkdir -p /root/gixbeesolutions_new
tar -xzf "$ARCHIVE" -C /root/gixbeesolutions_new

mkdir -p /root/gixbeesolutions_new/deploy
if [[ -f "$BACKUP_ENV" ]]; then cp "$BACKUP_ENV" /root/gixbeesolutions_new/deploy/.env; fi
if [[ -f "$BACKUP_FB" ]]; then cp "$BACKUP_FB" /root/gixbeesolutions_new/deploy/firebase-service-account.json; fi
if [[ -f "$BACKUP_ROOT_ENV" ]]; then cp "$BACKUP_ROOT_ENV" /root/gixbeesolutions_new/.env; fi

if [[ -d "$ROOT" ]]; then mv "$ROOT" "/root/gixbeesolutions.bak.$(date +%s)"; fi
mv /root/gixbeesolutions_new "$ROOT"
cd "$ROOT"

sed -i 's/\r$//' scripts/milesweb_sync_and_deploy.sh scripts/azure_hiring_migrations.sql scripts/cache_versions.sql scripts/master_data_audit.sql scripts/azure_hall_migrations.sql scripts/availability_intervals.sql scripts/azure_event_quote_milestones.sql scripts/azure_event_delivery_payments.sql scripts/event_catalogue_service_types.sql scripts/v147_gaps.sql 2>/dev/null || true
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/azure_hiring_migrations.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/cache_versions.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/master_data_audit.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/azure_hall_migrations.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/availability_intervals.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/azure_event_quote_milestones.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/azure_event_delivery_payments.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/event_catalogue_service_types.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/v147_gaps.sql
echo SCHEMA_OK

if ! grep -q CARGO_BUILD_JOBS "$ROOT/backend_rust/Dockerfile"; then
  sed -i 's/FROM rust:bookworm AS builder/FROM rust:bookworm AS builder\nENV CARGO_BUILD_JOBS=1 CARGO_INCREMENTAL=0/' "$ROOT/backend_rust/Dockerfile"
fi

docker compose build backend_rust admin
docker compose up -d --scale backend_rust=2 backend_rust admin api_balancer
docker image prune -f
docker compose ps
echo DEPLOY_OK
