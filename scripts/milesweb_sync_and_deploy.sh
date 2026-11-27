#!/bin/bash
set -euo pipefail
ROOT=/root/gixbeesolutions
ARCHIVE=/tmp/gixbee-milesweb.tgz

rm -rf /root/gixbeesolutions_new
mkdir -p /root/gixbeesolutions_new
tar -xzf "$ARCHIVE" -C /root/gixbeesolutions_new

mkdir -p /root/gixbeesolutions_new/deploy
if [[ -f "$ROOT/deploy/.env" ]]; then cp -p "$ROOT/deploy/.env" /root/gixbeesolutions_new/deploy/.env;
elif [[ -f "$ROOT/backend/.env" ]]; then cp -p "$ROOT/backend/.env" /root/gixbeesolutions_new/deploy/.env; fi
if [[ -f "$ROOT/deploy/firebase-service-account.json" ]]; then cp -p "$ROOT/deploy/firebase-service-account.json" /root/gixbeesolutions_new/deploy/firebase-service-account.json;
elif [[ -f "$ROOT/backend/firebase-service-account.json" ]]; then cp -p "$ROOT/backend/firebase-service-account.json" /root/gixbeesolutions_new/deploy/firebase-service-account.json; fi
if [[ -f "$ROOT/.env" ]]; then cp -p "$ROOT/.env" /root/gixbeesolutions_new/.env; fi

# HTTPS production overlay only when TLS + runtime DB secrets are ready.
# Otherwise keep HTTP :3000 so MilesWeb stays deployable before cutover.
ROOT_ENV_CANDIDATE=/root/gixbeesolutions_new/.env
use_tls=0
if [[ -f "$ROOT_ENV_CANDIDATE" ]] \
  && grep -qE '^GIXBEE_API_HOST=[^[:space:]]+' "$ROOT_ENV_CANDIDATE" \
  && grep -qE '^GIXBEE_ADMIN_HOST=[^[:space:]]+' "$ROOT_ENV_CANDIDATE" \
  && grep -qE '^GIXBEE_TLS_CERT_DIR=[^[:space:]]+' "$ROOT_ENV_CANDIDATE" \
  && grep -qE '^GIXBEE_APP_DATABASE_URL=[^[:space:]]+' "$ROOT_ENV_CANDIDATE" \
  && grep -qE '^GIXBEE_APP_DB_PASSWORD=[^[:space:]]+' "$ROOT_ENV_CANDIDATE" \
  && grep -qE '^GIXBEE_DB_ADMIN_PASSWORD=[^[:space:]]+' "$ROOT_ENV_CANDIDATE"; then
  cert_dir=$(sed -n 's/^GIXBEE_TLS_CERT_DIR=//p' "$ROOT_ENV_CANDIDATE" | head -1 | tr -d '\r')
  if [[ "$cert_dir" == /* && -s "$cert_dir/fullchain.pem" && -s "$cert_dir/privkey.pem" ]] \
    && openssl x509 -in "$cert_dir/fullchain.pem" -checkend 0 -noout; then
    cert_key=$(openssl x509 -in "$cert_dir/fullchain.pem" -pubkey -noout)
    private_key=$(openssl pkey -in "$cert_dir/privkey.pem" -pubout)
    if [[ "$cert_key" == "$private_key" ]]; then
      use_tls=1
    fi
  fi
fi

if [[ "$use_tls" -eq 1 ]]; then
  echo "Deploy mode: HTTPS production overlay"
  staged=(docker compose --project-name gixbeesolutions --env-file "$ROOT_ENV_CANDIDATE"
    -f /root/gixbeesolutions_new/docker-compose.yml -f /root/gixbeesolutions_new/docker-compose.production.yml)
  "${staged[@]}" config --quiet
  if ! grep -q CARGO_BUILD_JOBS /root/gixbeesolutions_new/backend_rust/Dockerfile; then
    sed -i 's/FROM rust:bookworm AS builder/FROM rust:bookworm AS builder\nENV CARGO_BUILD_JOBS=1 CARGO_INCREMENTAL=0/' /root/gixbeesolutions_new/backend_rust/Dockerfile
  fi
  docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 \
    -f - < /root/gixbeesolutions_new/scripts/runtime_database_role.sql
  "${staged[@]}" build backend_rust admin
  "${staged[@]}" run --rm --no-deps -T backend_rust /app/gixbee-backend --check-config
else
  echo "Deploy mode: HTTP base compose (TLS/DB role env not ready)"
  docker compose -f /root/gixbeesolutions_new/docker-compose.yml config --quiet
fi

if [[ -d "$ROOT" ]]; then mv "$ROOT" "/root/gixbeesolutions.bak.$(date +%s)"; fi
mv /root/gixbeesolutions_new "$ROOT"
cd "$ROOT"
if [[ "$use_tls" -eq 1 ]]; then
  compose=(docker compose --project-name gixbeesolutions -f docker-compose.yml -f docker-compose.production.yml)
else
  compose=(docker compose --project-name gixbeesolutions -f docker-compose.yml)
fi

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
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/platform_payment_plans.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/account_profile_setup.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/hiring_no_response_credit.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/booking_offer_recipients.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/outbox_leases.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/arch_fixes_v1.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/booking_delivery_guards.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/booking_maintenance.sql
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/hiring_checkout_expiry.sql
if [[ "$use_tls" -eq 1 ]]; then
  docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/runtime_database_role.sql
fi
echo SCHEMA_OK

if ! grep -q CARGO_BUILD_JOBS "$ROOT/backend_rust/Dockerfile"; then
  sed -i 's/FROM rust:bookworm AS builder/FROM rust:bookworm AS builder\nENV CARGO_BUILD_JOBS=1 CARGO_INCREMENTAL=0/' "$ROOT/backend_rust/Dockerfile"
fi

if [[ "$use_tls" -ne 1 ]]; then
  "${compose[@]}" build backend_rust admin
fi
"${compose[@]}" up -d --wait --wait-timeout 180 --scale backend_rust=2 backend_rust admin api_balancer

if [[ "$use_tls" -eq 1 ]]; then
  api_host=$("${compose[@]}" exec -T api_balancer printenv GIXBEE_API_HOST)
  admin_host=$("${compose[@]}" exec -T api_balancer printenv GIXBEE_ADMIN_HOST)
  check_https() {
    local host="$1" path="$2" status attempt
    for attempt in 1 2 3 4 5; do
      if status=$(curl --silent --show-error --max-time 10 \
        --resolve "$host:443:127.0.0.1" --output /dev/null --write-out '%{http_code}' "https://$host$path") &&
        [[ "$status" == 200 ]]; then
        return 0
      fi
      if [[ "$attempt" != 5 ]]; then sleep 2; fi
    done
    echo "HTTPS check failed for $host$path (HTTP $status)" >&2
    return 1
  }
  check_https "$api_host" /readyz
  check_https "$admin_host" /
  check_https "$api_host" '/socket.io/?EIO=4&transport=polling'
else
  for attempt in 1 2 3 4 5; do
    if curl --silent --show-error --max-time 10 --output /dev/null --write-out '%{http_code}' \
      http://127.0.0.1:3000/readyz | grep -q '^200$'; then
      break
    fi
    if [[ "$attempt" == 5 ]]; then
      echo "HTTP /readyz check failed on :3000" >&2
      exit 1
    fi
    sleep 2
  done
fi
"${compose[@]}" ps
echo DEPLOY_OK
