#!/bin/bash
set -euo pipefail
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/auth/admin-login \
  -H 'Content-Type: application/json' \
  -d '{"username":"gixbee-admin","password":"gixbee-admin-2026"}' \
  | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
  echo IMPORT_LOGIN_FAILED
  exit 1
fi
curl -s -X POST http://127.0.0.1:3000/hiring/catalogue/admin/import \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{}'
echo
echo IMPORT_DONE
