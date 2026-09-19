#!/bin/bash
set -euo pipefail
LOGIN=$(curl -sS -X POST http://127.0.0.1:3000/auth/admin-login \
  -H 'Content-Type: application/json' \
  -d '{"username":"gixbee-admin","password":"gixbee-admin-2026"}')
TOKEN=$(printf '%s' "$LOGIN" | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')
echo "LOGIN_OK token_len=${#TOKEN}"
curl -sS -w '\nHTTP=%{http_code}\n' \
  'http://127.0.0.1:3000/workers/admin/verification-queue?status=PENDING' \
  -H "Authorization: Bearer $TOKEN"
