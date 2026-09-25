#!/bin/bash
set -euo pipefail
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/auth/admin-login \
  -H 'Content-Type: application/json' \
  -d '{"username":"gixbee-admin","password":"gixbee-admin-2026"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['accessToken'])")
curl -s -X POST http://127.0.0.1:3000/hiring/catalogue/admin/import \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{}'
echo
echo IMPORT_DONE
