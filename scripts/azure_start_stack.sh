#!/bin/bash
set -euo pipefail
cd /home/azureuser
rm -rf gixbeesolutions
mkdir -p gixbeesolutions
tar -xzf /tmp/gixbee-slim.tgz -C gixbeesolutions
mkdir -p /home/azureuser/gixbeesolutions/backend
cp /tmp/azure_backend.env /home/azureuser/gixbeesolutions/backend/.env
cp /tmp/azure_firebase.json /home/azureuser/gixbeesolutions/backend/firebase-service-account.json
# Keep the Rust compile from OOM-killing this 4GB box.
if ! grep -q CARGO_BUILD_JOBS /home/azureuser/gixbeesolutions/backend_rust/Dockerfile; then
  sed -i 's/FROM rust:bookworm AS builder/FROM rust:bookworm AS builder\nENV CARGO_BUILD_JOBS=1 CARGO_INCREMENTAL=0/' /home/azureuser/gixbeesolutions/backend_rust/Dockerfile
fi
cd /home/azureuser/gixbeesolutions
echo BACKEND_IMPL=rust > .env
export COMPOSE_PROFILES=rust
docker compose build backend_rust
docker compose up -d postgres redis pgbouncer
docker compose up -d --scale backend_rust=1 backend_rust api_balancer
docker compose ps
echo STACK_UP
