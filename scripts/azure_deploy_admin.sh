#!/bin/bash
set -euo pipefail
cd /home/azureuser/gixbeesolutions
tar -xzf /tmp/gixbee-admin.tgz
sed -i 's/\r$//' /tmp/azure_admin_staff.sql || true
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -f - < /tmp/azure_admin_staff.sql
docker compose build admin
docker compose up -d admin
docker compose ps admin
echo ADMIN_UP
