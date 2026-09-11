#!/usr/bin/env bash
# Guarded live E2E smoke test for Gixbee marketplace flows.
# Runs ON the EC2 host (needs curl + docker access to gixbee_redis / gixbee_postgres).
# Creates throwaway users + data, exercises the flows, then cleans everything up.

set -uo pipefail

API="http://localhost:3000"
PSQL=(docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -tA)
REDIS=(docker exec gixbee_redis redis-cli)

EPOCH=$(date +%s)
L8=${EPOCH: -8}
PHONE_OWNER="+9190${L8}"
PHONE_RENTER="+9180${L8}"

PASS=0
FAIL=0
NOTES=()

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; NOTES+=("$1"); }
# check <expected_http> <actual_http> <label>
check(){ if [ "$2" = "$1" ]; then ok "$3 ($2)"; else bad "$3 (want $1 got $2)"; fi; }

jval(){ python3 -c "import json,sys
try:
    d=json.load(open('$1'))
    v=d
    for k in sys.argv[1:]:
        v=v[int(k)] if isinstance(v,list) else v[k]
    print(v)
except Exception:
    print('')" "${@:2}"; }

# curl_json <METHOD> <PATH> <TOKEN|-> <BODY|-> <OUTFILE>  -> echoes HTTP code
curl_json(){
  local method="$1" path="$2" token="$3" body="$4" out="$5"
  local args=(-s -o "$out" -w '%{http_code}' -X "$method" "$API$path" -H 'content-type: application/json')
  [ "$token" != "-" ] && args+=(-H "authorization: Bearer $token")
  [ "$body" != "-" ]  && args+=(-d "$body")
  curl "${args[@]}"
}

get_token(){
  local phone="$1"
  curl -s -X POST "$API/auth/request-otp" -H 'content-type: application/json' \
       -d "{\"phone\":\"$phone\"}" >/dev/null
  local otp; otp=$("${REDIS[@]}" get "otp:$phone" | tr -d '\r"')
  curl -s -X POST "$API/auth/verify-otp" -H 'content-type: application/json' \
       -d "{\"phone\":\"$phone\",\"otp\":\"$otp\"}" > /tmp/e2e_tok.json
  jval /tmp/e2e_tok.json accessToken
}

cleanup(){
  say "CLEANUP"
  local ownr rentr
  ownr=$(printf "SELECT id FROM users WHERE \"phoneNumber\"='%s';" "$PHONE_OWNER"  | "${PSQL[@]}")
  rentr=$(printf "SELECT id FROM users WHERE \"phoneNumber\"='%s';" "$PHONE_RENTER" | "${PSQL[@]}")
  [ -z "$ownr" ] && { echo "  nothing to clean"; return; }
  "${PSQL[@]}" >/dev/null <<SQL
DELETE FROM rental_reservations WHERE "renterId" IN ('$ownr','${rentr:-$ownr}')
   OR "itemId" IN (SELECT id FROM rental_items WHERE "ownerId"='$ownr');
DELETE FROM rental_items WHERE "ownerId"='$ownr';
DELETE FROM outbox_events WHERE "aggregateId" IN (SELECT id FROM event_plans WHERE "customerId"='$ownr');
DELETE FROM event_quotes WHERE "planId" IN (SELECT id FROM event_plans WHERE "customerId"='$ownr');
DELETE FROM event_plans WHERE "customerId"='$ownr';
DELETE FROM job_preferences WHERE "userId" IN ('$ownr','${rentr:-$ownr}');
DELETE FROM businesses WHERE "ownerId"='$ownr';
DELETE FROM wallet_transactions WHERE "userId" IN ('$ownr','${rentr:-$ownr}');
DELETE FROM job_credits WHERE "userId" IN ('$ownr','${rentr:-$ownr}');
DELETE FROM users WHERE id IN ('$ownr','${rentr:-$ownr}');
SQL
  echo "  removed test users and their data"
}
trap cleanup EXIT

say "AUTH"
OWNER=$(get_token "$PHONE_OWNER")
RENTER=$(get_token "$PHONE_RENTER")
[ -n "$OWNER" ]  && ok "owner login"  || bad "owner login"
[ -n "$RENTER" ] && ok "renter login" || bad "renter login"

say "RENTALS - public listing (was 500)"
code=$(curl_json GET /rentals - - /tmp/e2e_rentals.json)
check 200 "$code" "GET /rentals"

say "BUSINESSES - create SERVICE with eventServices (was 500)"
code=$(curl_json POST /businesses "$OWNER" \
  '{"name":"E2E Event Hall","type":"SERVICE","address":"E2E Street","serviceType":"HALL","eventServices":["HALL"],"phone":"9998887770"}' \
  /tmp/e2e_bsvc.json)
check 200 "$code" "POST /businesses SERVICE"
BSVC=$(jval /tmp/e2e_bsvc.json id)

say "BUSINESSES - create RENTAL"
code=$(curl_json POST /businesses "$OWNER" \
  '{"name":"E2E Rental Unit","type":"RENTAL","address":"E2E Depot","phone":"9998887771"}' \
  /tmp/e2e_brent.json)
check 200 "$code" "POST /businesses RENTAL"
BRENT=$(jval /tmp/e2e_brent.json id)

say "BUSINESSES - list mine"
code=$(curl_json GET /businesses/my "$OWNER" - /tmp/e2e_bmy.json)
check 200 "$code" "GET /businesses/my"

# Verify the rental business so item creation + public listing work.
if [ -n "$BRENT" ]; then
  printf "UPDATE businesses SET status='VERIFIED' WHERE id='%s';" "$BRENT" | "${PSQL[@]}" >/dev/null
  ok "verified rental business (via db)"
else
  bad "no rental business id"
fi

say "RENTALS - create item under verified business"
code=$(curl_json POST /rentals "$OWNER" \
  "{\"name\":\"E2E Camera\",\"hourlyRate\":100,\"dailyRate\":1000,\"minHoursToRent\":2,\"businessId\":\"$BRENT\",\"pickupAddress\":\"E2E Depot\",\"quantity\":2}" \
  /tmp/e2e_item.json)
check 200 "$code" "POST /rentals (create item)"
ITEM=$(jval /tmp/e2e_item.json id)

say "RENTALS - owner my-items"
code=$(curl_json "GET" "/rentals/my-items?businessId=$BRENT" "$OWNER" - /tmp/e2e_myitems.json)
check 200 "$code" "GET /rentals/my-items"

say "RENTALS - reserve (renter) -> confirm; handover/return are time-gated"
# Window starts now so owner+renter can acknowledge handover within it.
START=$(date -u -d "now" +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u -d "+49 hours" +%Y-%m-%dT%H:%M:%SZ)
code=$(curl_json POST "/rentals/$ITEM/reserve" "$RENTER" \
  "{\"startTime\":\"$START\",\"endTime\":\"$END\",\"quantity\":1,\"fulfillment\":\"PICKUP\"}" \
  /tmp/e2e_res.json)
check 200 "$code" "POST /rentals/:id/reserve"
RES=$(jval /tmp/e2e_res.json id)
PRICE=$(jval /tmp/e2e_res.json totalPrice)
{ [ "$PRICE" = "3000" ] || [ "$PRICE" = "3000.00" ]; } && ok "reservation price 3000 ($PRICE)" || bad "reservation price ($PRICE)"

code=$(curl_json PATCH "/rentals/reservations/$RES/confirm" "$OWNER" - /tmp/e2e_conf.json)
check 200 "$code" "PATCH reserve/confirm"
# handover: both sides acknowledge within the window -> reservation goes ACTIVE
code=$(curl_json PATCH "/rentals/reservations/$RES/start" "$OWNER" - /tmp/e2e_ho1.json)
check 200 "$code" "PATCH reserve/start (owner handover)"
code=$(curl_json PATCH "/rentals/reservations/$RES/ack/handover" "$RENTER" - /tmp/e2e_ho2.json)
check 200 "$code" "PATCH reserve/ack handover (renter)"

say "EVENTS - create plan"
CITY=$(printf "SELECT id FROM cities WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")
if [ -n "$CITY" ]; then
  ESTART=$(date -u -d "+3 days" +%Y-%m-%dT%H:%M:%SZ)
  EEND=$(date -u -d "+3 days 3 hours" +%Y-%m-%dT%H:%M:%SZ)
  code=$(curl_json POST /events "$OWNER" \
    "{\"eventType\":\"Wedding\",\"startTime\":\"$ESTART\",\"endTime\":\"$EEND\",\"guestCount\":100,\"location\":\"E2E Venue\",\"cityId\":\"$CITY\",\"services\":[\"HALL\"]}" \
    /tmp/e2e_plan.json)
  check 200 "$code" "POST /events (create plan)"
  code=$(curl_json GET /events "$OWNER" - /tmp/e2e_plans.json)
  check 200 "$code" "GET /events (my plans)"
else
  bad "no active city for event test"
fi

say "HIRING - career preference + job board"
code=$(curl_json POST /hiring/match/preferences "$RENTER" \
  '{"jobType":"Electrician","skills":["Wiring"],"expectedSalary":20000,"preferredLocation":"E2E City","employmentType":"FULL_TIME","experienceYears":3,"noticePeriod":"DAYS_30"}' \
  /tmp/e2e_pref.json)
check 200 "$code" "POST /hiring/match/preferences"
code=$(curl_json GET /hiring/jobs "$RENTER" - /tmp/e2e_jobs.json)
check 200 "$code" "GET /hiring/jobs (job board)"

say "SUMMARY"
printf '  PASSED: %d   FAILED: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  Failures:\n'
  for n in "${NOTES[@]}"; do printf '   - %s\n' "$n"; done
fi
