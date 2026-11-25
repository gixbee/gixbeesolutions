#!/usr/bin/env bash
# Full live E2E: 2 users (customer + worker), Instant Help, businesses,
# image upload, rentals, events, hiring, messages. Runs ON MilesWeb host.
# Creates throwaway users, then cleans them up on exit.

set -uo pipefail

API="http://localhost:3000"
PSQL=(docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -tA)
REDIS=(docker exec gixbee_redis redis-cli)

EPOCH=$(date +%s)
L8=${EPOCH: -8}
PHONE_CUST="+9170${L8}"
PHONE_WORK="+9160${L8}"
LAT=17.385000
LNG=78.486700
SKILL="Electrician"

PASS=0
FAIL=0
NOTES=()
TMPDIR=$(mktemp -d /tmp/e2e_full.XXXXXX)

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; NOTES+=("$1"); }
check(){ if [ "$2" = "$1" ]; then ok "$3 ($2)"; else bad "$3 (want $1 got $2)"; fi; }
check_ok(){ case "$1" in 200|201) ok "$2 ($1)";; *) bad "$2 (want 2xx got $1)";; esac; }

jval(){
  python3 -c "import json,sys
try:
    d=json.load(open('$1'))
    v=d
    for k in sys.argv[1:]:
        if isinstance(v,dict) and k in v: v=v[k]
        elif isinstance(v,list): v=v[int(k)]
        else: v=v[k]
    if isinstance(v,(dict,list)): print(json.dumps(v))
    elif v is None: print('')
    else: print(v)
except Exception:
    print('')" "${@:2}"
}

curl_json(){
  local method="$1" path="$2" token="$3" body="$4" out="$5"
  local args=(-s -o "$out" -w '%{http_code}' -X "$method" "$API$path" -H 'content-type: application/json')
  [ "$token" != "-" ] && args+=(-H "authorization: Bearer $token")
  [ "$body" != "-" ]  && args+=(-d "$body")
  curl "${args[@]}"
}

# Minimal 1x1 PNG
make_png(){
  python3 - "$1" <<'PY'
import struct,zlib,sys
def chunk(t,d):
    return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
raw=b'\x00'+b'\x00\x00\x00'
open(sys.argv[1],'wb').write(
  b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+
  chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
PY
}

get_token(){
  local phone="$1" out="$2"
  curl -s -X POST "$API/auth/request-otp" -H 'content-type: application/json' \
       -d "{\"phone\":\"$phone\"}" >/dev/null
  local otp; otp=$("${REDIS[@]}" get "otp:$phone" | tr -d '\r"')
  if [ -z "$otp" ] || [ "$otp" = "(nil)" ]; then
    echo ""
    return
  fi
  curl -s -X POST "$API/auth/verify-otp" -H 'content-type: application/json' \
       -d "{\"phone\":\"$phone\",\"otp\":\"$otp\"}" > "$out"
  jval "$out" accessToken
}

user_id_from_phone(){
  printf "SELECT id FROM users WHERE \"phoneNumber\"='%s';" "$1" | "${PSQL[@]}"
}

cleanup(){
  say "CLEANUP"
  local cust work
  cust=$(user_id_from_phone "$PHONE_CUST")
  work=$(user_id_from_phone "$PHONE_WORK")
  if [ -z "$cust" ] && [ -z "$work" ]; then
    echo "  nothing to clean"
    rm -rf "$TMPDIR"
    return
  fi
  # Best-effort cascade for throwaway fixtures
  "${PSQL[@]}" >/dev/null <<SQL
DO \$\$
DECLARE
  cust uuid := NULLIF('$cust','')::uuid;
  work uuid := NULLIF('$work','')::uuid;
BEGIN
  IF cust IS NOT NULL OR work IS NOT NULL THEN
    DELETE FROM messages WHERE "senderId" IN (cust, work) OR "recipientId" IN (cust, work);
    DELETE FROM rental_reservations WHERE "renterId" IN (cust, work)
       OR "itemId" IN (SELECT id FROM rental_items WHERE "ownerId" IN (cust, work));
    DELETE FROM rental_items WHERE "ownerId" IN (cust, work);
    DELETE FROM shop_offers WHERE "businessId" IN (SELECT id FROM businesses WHERE "ownerId" IN (cust, work));
    DELETE FROM event_quotes WHERE "planId" IN (SELECT id FROM event_plans WHERE "customerId" IN (cust, work));
    DELETE FROM outbox_events WHERE "aggregateId" IN (SELECT id FROM event_plans WHERE "customerId" IN (cust, work));
    DELETE FROM event_plans WHERE "customerId" IN (cust, work);
    DELETE FROM job_preferences WHERE "userId" IN (cust, work);
    DELETE FROM credit_transactions WHERE "userId" IN (cust, work);
    DELETE FROM job_credits WHERE "userId" IN (cust, work);
    DELETE FROM seeker_resume_uploads WHERE "userId" IN (cust, work);
    DELETE FROM addresses WHERE "userId" IN (cust, work);
    DELETE FROM favourites WHERE "userId" IN (cust, work);
    DELETE FROM bookings WHERE "customerId" IN (cust, work) OR "operatorId" IN (cust, work);
    DELETE FROM worker_profiles WHERE "userId" IN (cust, work);
    DELETE FROM businesses WHERE "ownerId" IN (cust, work);
    DELETE FROM wallet_transactions WHERE "userId" IN (cust, work);
    DELETE FROM users WHERE id IN (cust, work);
  END IF;
END \$\$;
SQL
  echo "  removed test users and related data"
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ── AUTH: 2 users ──────────────────────────────────────────────────────────
say "AUTH (2 users)"
CUST_TOK=$(get_token "$PHONE_CUST" "$TMPDIR/cust_auth.json")
WORK_TOK=$(get_token "$PHONE_WORK" "$TMPDIR/work_auth.json")
[ -n "$CUST_TOK" ] && ok "customer login ($PHONE_CUST)" || bad "customer login"
[ -n "$WORK_TOK" ] && ok "worker login ($PHONE_WORK)" || bad "worker login"
CUST_ID=$(user_id_from_phone "$PHONE_CUST")
WORK_ID=$(user_id_from_phone "$PHONE_WORK")
[ -n "$CUST_ID" ] && ok "customer id $CUST_ID" || bad "customer id missing"
[ -n "$WORK_ID" ] && ok "worker id $WORK_ID" || bad "worker id missing"

# Profile names
code=$(curl_json PATCH "/admin-user-list/$CUST_ID" "$CUST_TOK" \
  '{"name":"E2E Customer"}' "$TMPDIR/cust_name.json")
check_ok "$code" "PATCH customer name"
code=$(curl_json PATCH "/admin-user-list/$WORK_ID" "$WORK_TOK" \
  '{"name":"E2E Worker"}' "$TMPDIR/work_name.json")
check_ok "$code" "PATCH worker name"

code=$(curl_json GET /auth/profile "$CUST_TOK" - "$TMPDIR/cust_prof.json")
check 200 "$code" "GET /auth/profile (customer)"

# ── IMAGE UPLOAD ───────────────────────────────────────────────────────────
say "IMAGE UPLOAD"
PNG="$TMPDIR/dot.png"
make_png "$PNG"
code=$(curl -s -o "$TMPDIR/up_img.json" -w '%{http_code}' -X POST "$API/uploads/image" \
  -H "authorization: Bearer $CUST_TOK" \
  -F "file=@$PNG;type=image/png;filename=e2e-dot.png")
check 200 "$code" "POST /uploads/image"
IMG_URL=$(jval "$TMPDIR/up_img.json" url)
[ -n "$IMG_URL" ] && ok "image url $IMG_URL" || bad "image url empty"

# Attach as profile photo
code=$(curl_json PATCH "/admin-user-list/$CUST_ID" "$CUST_TOK" \
  "{\"profileImageUrl\":\"$IMG_URL\"}" "$TMPDIR/cust_photo.json")
check_ok "$code" "set customer profileImageUrl"

# Reject SVG / bad ext
code=$(curl -s -o "$TMPDIR/up_bad.json" -w '%{http_code}' -X POST "$API/uploads/image" \
  -H "authorization: Bearer $CUST_TOK" \
  -F "file=@$PNG;type=image/svg+xml;filename=evil.svg")
# expect 400
if [ "$code" = "400" ]; then ok "reject .svg upload ($code)"; else bad "reject .svg (want 400 got $code)"; fi

# Resume PDF magic
PDF="$TMPDIR/blank.pdf"
printf '%%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%%%EOF\n' > "$PDF"
code=$(curl -s -o "$TMPDIR/up_res.json" -w '%{http_code}' -X POST "$API/uploads/resume" \
  -H "authorization: Bearer $WORK_TOK" \
  -F "file=@$PDF;type=application/pdf;filename=e2e-cv.pdf")
check 200 "$code" "POST /uploads/resume"

# ── WORKER ONBOARD + GO LIVE ───────────────────────────────────────────────
say "WORKER PROFILE + GO LIVE"
code=$(curl_json POST /workers/register "$WORK_TOK" \
  "{\"skills\":[\"$SKILL\"],\"hourlyRate\":250,\"bio\":\"E2E pro\",\"title\":\"E2E Electrician\"}" \
  "$TMPDIR/wreg.json")
check_ok "$code" "POST /workers/register"

code=$(curl_json PATCH /workers/me/languages "$WORK_TOK" \
  '{"languages":["English","Telugu"]}' "$TMPDIR/wlang.json")
check_ok "$code" "PATCH /workers/me/languages"

code=$(curl_json PATCH /workers/me/service-radius "$WORK_TOK" \
  '{"serviceRadiusKm":15}' "$TMPDIR/wrad.json")
check_ok "$code" "PATCH /workers/me/service-radius"

code=$(curl_json PATCH /workers/me/active-skills "$WORK_TOK" \
  "{\"skills\":[\"$SKILL\"]}" "$TMPDIR/wsk.json")
check_ok "$code" "PATCH /workers/me/active-skills"

# Ops gates: verify + approve + seed credits (Razorpay not exercised here).
# job_credits has no UNIQUE(userId) on this DB — delete then insert.
printf "UPDATE worker_profiles SET \"verificationStatus\"='VERIFIED', \"activeSkills\"='%s', skills='%s', languages='English,Telugu', \"serviceRadiusKm\"=15 WHERE \"userId\"='%s';
UPDATE users SET \"approvalStatus\"='APPROVED', \"hasWorkerProfile\"=true WHERE id='%s';
DELETE FROM job_credits WHERE \"userId\"='%s';
INSERT INTO job_credits (id, \"userId\", balance) VALUES (gen_random_uuid(), '%s', 45);
" "$SKILL" "$SKILL" "$WORK_ID" "$WORK_ID" "$WORK_ID" "$WORK_ID" | "${PSQL[@]}" >/dev/null
ok "DB: worker VERIFIED + APPROVED + 45 credits"

code=$(curl_json GET /billing/credits/balance "$WORK_TOK" - "$TMPDIR/bal.json")
check 200 "$code" "GET /billing/credits/balance"
BAL=$(jval "$TMPDIR/bal.json" balance)
[ "$BAL" = "45" ] && ok "credit balance 45" || bad "credit balance ($BAL)"

code=$(curl_json POST /workers/live-toggle "$WORK_TOK" \
  "{\"active\":true,\"lat\":$LAT,\"lng\":$LNG}" "$TMPDIR/live.json")
check_ok "$code" "POST /workers/live-toggle (go live)"
IS_ACTIVE=$(jval "$TMPDIR/live.json" isActive)
[ "$IS_ACTIVE" = "True" ] || [ "$IS_ACTIVE" = "true" ] && ok "worker isActive=true" || bad "worker isActive ($IS_ACTIVE)"

code=$(curl_json GET /workers/me/dashboard "$WORK_TOK" - "$TMPDIR/wdash.json")
check 200 "$code" "GET /workers/me/dashboard"

# ── INSTANT HELP FULL FLOW ─────────────────────────────────────────────────
say "INSTANT HELP (customer ↔ worker)"
code=$(curl_json POST /bookings/instant "$CUST_TOK" \
  "{\"skill\":\"$SKILL\",\"serviceLocation\":\"E2E Test Street Hyderabad\",\"serviceLat\":$LAT,\"serviceLng\":$LNG,\"amount\":200,\"description\":\"E2E fuse board check\",\"preferredLanguages\":[\"English\"],\"paymentMethod\":\"CASH\"}" \
  "$TMPDIR/inst.json")
check_ok "$code" "POST /bookings/instant"
BOOK=$(jval "$TMPDIR/inst.json" booking id)
[ -z "$BOOK" ] && BOOK=$(jval "$TMPDIR/inst.json" id)
NOTIFIED=$(jval "$TMPDIR/inst.json" notified)
[ -n "$BOOK" ] && ok "booking id $BOOK (notified=$NOTIFIED)" || bad "booking id missing"

# Ensure worker can accept even if geo index missed (seed pending)
if [ -n "$BOOK" ] && [ -n "$WORK_ID" ]; then
  SCORE=$(date +%s%3N)
  "${REDIS[@]}" zadd "worker:pending:$WORK_ID" "$SCORE" "$BOOK" >/dev/null
  "${REDIS[@]}" expire "worker:pending:$WORK_ID" 120 >/dev/null
  ok "seeded redis pending offer for worker"
fi

code=$(curl_json GET /bookings/pending "$WORK_TOK" - "$TMPDIR/pending.json")
check 200 "$code" "GET /bookings/pending"

code=$(curl_json PATCH "/bookings/$BOOK/accept" "$WORK_TOK" - "$TMPDIR/acc.json")
check_ok "$code" "PATCH /bookings/:id/accept"

# Customer reads arrival OTP from status
code=$(curl_json GET "/bookings/$BOOK/status" "$CUST_TOK" - "$TMPDIR/st1.json")
check 200 "$code" "GET /bookings/:id/status (customer)"
ARR_OTP=$(jval "$TMPDIR/st1.json" arrivalOtp)
[ -n "$ARR_OTP" ] && ok "arrival OTP present" || {
  ARR_OTP=$(printf "SELECT \"arrivalOtp\" FROM bookings WHERE id='%s';" "$BOOK" | "${PSQL[@]}")
  [ -n "$ARR_OTP" ] && ok "arrival OTP from db" || bad "arrival OTP missing"
}

code=$(curl_json PATCH "/bookings/$BOOK/arrive" "$WORK_TOK" - "$TMPDIR/arr.json")
check_ok "$code" "PATCH /bookings/:id/arrive"

code=$(curl_json POST "/bookings/$BOOK/arrival" "$WORK_TOK" \
  "{\"otp\":\"$ARR_OTP\"}" "$TMPDIR/arr_otp.json")
check_ok "$code" "POST /bookings/:id/arrival (OTP → ACTIVE)"

# Completion OTP from DB (customer-facing; worker shouldn't get it via status)
COMP_OTP=$(printf "SELECT \"completionOtp\" FROM bookings WHERE id='%s';" "$BOOK" | "${PSQL[@]}")
[ -n "$COMP_OTP" ] && ok "completion OTP present" || bad "completion OTP missing"

code=$(curl_json PATCH "/bookings/$BOOK/complete" "$WORK_TOK" - "$TMPDIR/comp.json")
check_ok "$code" "PATCH /bookings/:id/complete (notify)"

code=$(curl_json POST "/bookings/$BOOK/completion" "$CUST_TOK" \
  "{\"otp\":\"$COMP_OTP\"}" "$TMPDIR/comp_otp.json")
check_ok "$code" "POST /bookings/:id/completion (OTP → COMPLETED)"

code=$(curl_json PATCH "/bookings/$BOOK/mark-paid" "$CUST_TOK" \
  '{"collectionMethod":"CASH","safetyCheck":"SAFE"}' "$TMPDIR/pay_c.json")
check_ok "$code" "PATCH mark-paid (customer)"

code=$(curl_json PATCH "/bookings/$BOOK/mark-paid" "$WORK_TOK" \
  '{"honestyCheck":"HONEST"}' "$TMPDIR/pay_w.json")
check_ok "$code" "PATCH mark-paid (worker)"
IS_PAID=$(jval "$TMPDIR/pay_w.json" isPaid)
[ "$IS_PAID" = "True" ] || [ "$IS_PAID" = "true" ] && ok "isPaid=true after dual confirm" || bad "isPaid ($IS_PAID)"

code=$(curl_json POST "/bookings/$BOOK/rating" "$CUST_TOK" \
  '{"rating":5}' "$TMPDIR/rate_w.json")
check_ok "$code" "POST /bookings/:id/rating (customer→worker)"

code=$(curl_json POST "/bookings/$BOOK/rate-customer" "$WORK_TOK" \
  '{"rating":5}' "$TMPDIR/rate_c.json")
check_ok "$code" "POST /bookings/:id/rate-customer"

code=$(curl_json POST /messages "$CUST_TOK" \
  "{\"recipientId\":\"$WORK_ID\",\"body\":\"E2E thanks for the job\",\"bookingId\":\"$BOOK\"}" \
  "$TMPDIR/msg.json")
check_ok "$code" "POST /messages (booking chat)"

code=$(curl_json GET /bookings/my "$CUST_TOK" - "$TMPDIR/myb.json")
check 200 "$code" "GET /bookings/my"

# ── BUSINESSES ─────────────────────────────────────────────────────────────
say "BUSINESSES (SERVICE / RENTAL / SHOP / HIRING)"
code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Event Hall","type":"SERVICE","address":"E2E Street","serviceType":"HALL","eventServices":["HALL"],"phone":"9998887770"}' \
  "$TMPDIR/bsvc.json")
check_ok "$code" "POST /businesses SERVICE"
BSVC=$(jval "$TMPDIR/bsvc.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Rental Unit","type":"RENTAL","address":"E2E Depot","phone":"9998887771"}' \
  "$TMPDIR/brent.json")
check_ok "$code" "POST /businesses RENTAL"
BRENT=$(jval "$TMPDIR/brent.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Hardware Shop","type":"SHOP","address":"E2E Market","phone":"9998887772","hiringProfile":{"shopCategory":"Hardware"}}' \
  "$TMPDIR/bshop.json")
check_ok "$code" "POST /businesses SHOP"
BSHOP=$(jval "$TMPDIR/bshop.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Hire Co","type":"HIRING","address":"E2E HR Lane","phone":"9998887773"}' \
  "$TMPDIR/bhire.json")
check_ok "$code" "POST /businesses HIRING"
BHIRE=$(jval "$TMPDIR/bhire.json" id)

code=$(curl_json GET /businesses/my "$WORK_TOK" - "$TMPDIR/bmy.json")
check 200 "$code" "GET /businesses/my"

# Verify rental + shop for public paths; attach city for rental geo
CITY=$(printf "SELECT id FROM cities WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")
if [ -n "$BRENT" ]; then
  IDS="'$BRENT'"
  [ -n "$BSHOP" ] && IDS="$IDS,'$BSHOP'"
  [ -n "$BHIRE" ] && IDS="$IDS,'$BHIRE'"
  if [ -n "$CITY" ]; then
    printf "UPDATE businesses SET status='VERIFIED', \"cityId\"=COALESCE(\"cityId\",'%s') WHERE id IN (%s);" \
      "$CITY" "$IDS" | "${PSQL[@]}" >/dev/null
  else
    printf "UPDATE businesses SET status='VERIFIED' WHERE id IN (%s);" "$IDS" | "${PSQL[@]}" >/dev/null
  fi
  ok "DB verified rental/shop/hiring businesses"
fi

# Shop offer with image
if [ -n "$BSHOP" ]; then
  code=$(curl_json POST "/businesses/$BSHOP/offers" "$WORK_TOK" \
    '{"kind":"NORMAL","title":"E2E Drill Offer","code":"E2EDRILL","discount":"10%","category":"Hardware"}' \
    "$TMPDIR/offer.json")
  check_ok "$code" "POST /businesses/:id/offers"
  code=$(curl_json GET "/businesses/shop-offers?category=Hardware" "$CUST_TOK" - "$TMPDIR/soff.json")
  check 200 "$code" "GET /businesses/shop-offers"
fi

# ── RENTALS ────────────────────────────────────────────────────────────────
say "RENTALS"
code=$(curl_json GET /rentals - - "$TMPDIR/rent_pub.json")
check 200 "$code" "GET /rentals (public)"

if [ -n "$BRENT" ]; then
  code=$(curl_json POST /rentals "$WORK_TOK" \
    "{\"name\":\"E2E Camera\",\"hourlyRate\":100,\"dailyRate\":1000,\"minHoursToRent\":2,\"businessId\":\"$BRENT\",\"pickupAddress\":\"E2E Depot\",\"quantity\":2,\"imageUrl\":\"$IMG_URL\",\"pickupLat\":$LAT,\"pickupLng\":$LNG,\"category\":\"ELECTRONICS\",\"condition\":\"GOOD\",\"cancellationPolicy\":\"FLEXIBLE\"}" \
    "$TMPDIR/item.json")
  check_ok "$code" "POST /rentals (create item)"
  ITEM=$(jval "$TMPDIR/item.json" id)

  code=$(curl_json "GET" "/rentals/my-items?businessId=$BRENT" "$WORK_TOK" - "$TMPDIR/myitems.json")
  check 200 "$code" "GET /rentals/my-items"

  if [ -n "$ITEM" ]; then
    START=$(date -u -d "now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+0H +%Y-%m-%dT%H:%M:%SZ)
    END=$(date -u -d "+49 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+49H +%Y-%m-%dT%H:%M:%SZ)
    code=$(curl_json POST "/rentals/$ITEM/reserve" "$CUST_TOK" \
      "{\"startTime\":\"$START\",\"endTime\":\"$END\",\"quantity\":1,\"fulfillment\":\"PICKUP\"}" \
      "$TMPDIR/res.json")
    check_ok "$code" "POST /rentals/:id/reserve"
    RES=$(jval "$TMPDIR/res.json" id)

    if [ -n "$RES" ]; then
      # With Razorpay live, reserve starts as TEMP_HOLD until advance is paid.
      # Simulate captured advance so owner confirm/handover can be exercised.
      RSTAT=$(jval "$TMPDIR/res.json" status)
      if [ "$RSTAT" = "TEMP_HOLD" ] || [ "$RSTAT" = "PAYMENT_PENDING" ]; then
        printf "UPDATE rental_reservations SET status='PENDING_OWNER_CONFIRMATION', \"paymentStatus\"='PAID', \"holdExpiresAt\"=NULL WHERE id='%s';" \
          "$RES" | "${PSQL[@]}" >/dev/null
        ok "DB: simulate rental advance paid ($RSTAT → PENDING_OWNER_CONFIRMATION)"
      else
        ok "rental status after reserve: $RSTAT"
      fi
      code=$(curl_json PATCH "/rentals/reservations/$RES/confirm" "$WORK_TOK" - "$TMPDIR/rconf.json")
      check_ok "$code" "PATCH reserve/confirm"
      code=$(curl_json PATCH "/rentals/reservations/$RES/start" "$WORK_TOK" - "$TMPDIR/rho1.json")
      check_ok "$code" "PATCH reserve/start (owner)"
      code=$(curl_json PATCH "/rentals/reservations/$RES/ack/handover" "$CUST_TOK" - "$TMPDIR/rho2.json")
      check_ok "$code" "PATCH reserve/ack handover (renter)"
    fi
  fi
fi

# ── EVENTS ─────────────────────────────────────────────────────────────────
say "EVENTS"
CITY=$(printf "SELECT id FROM cities WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")
if [ -n "$CITY" ]; then
  ESTART=$(date -u -d "+3 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+3d +%Y-%m-%dT%H:%M:%SZ)
  EEND=$(date -u -d "+3 days 3 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+3d -v+3H +%Y-%m-%dT%H:%M:%SZ)
  code=$(curl_json POST /events "$CUST_TOK" \
    "{\"eventType\":\"Wedding\",\"startTime\":\"$ESTART\",\"endTime\":\"$EEND\",\"guestCount\":100,\"location\":\"E2E Venue\",\"cityId\":\"$CITY\",\"services\":[\"HALL\"]}" \
    "$TMPDIR/plan.json")
  check_ok "$code" "POST /events"
  code=$(curl_json GET /events "$CUST_TOK" - "$TMPDIR/plans.json")
  check 200 "$code" "GET /events"
else
  bad "no active city for event test"
fi

# ── HIRING ─────────────────────────────────────────────────────────────────
say "HIRING"
code=$(curl_json POST /hiring/match/preferences "$CUST_TOK" \
  '{"jobType":"Electrician","skills":["Wiring"],"expectedSalary":20000,"preferredLocation":"E2E City","employmentType":"FULL_TIME","experienceYears":3,"noticePeriod":"DAYS_30"}' \
  "$TMPDIR/pref.json")
check_ok "$code" "POST /hiring/match/preferences"
code=$(curl_json GET /hiring/jobs "$CUST_TOK" - "$TMPDIR/jobs.json")
check 200 "$code" "GET /hiring/jobs"
code=$(curl_json GET /hiring/catalogue "$CUST_TOK" - "$TMPDIR/jt.json")
check 200 "$code" "GET /hiring/catalogue"

# ── ADDRESSES / WORKER DIRECTORY ───────────────────────────────────────────
say "PROFILE EXTRAS"
# Addresses previously panicked decoding NUMERIC lat/lng as f64 (502). Fixed in
# addresses::address_json — this asserts the create+list path stays healthy.
code=$(curl_json POST /addresses "$CUST_TOK" \
  "{\"label\":\"Home\",\"line\":\"E2E Lane Hyderabad\",\"lat\":$LAT,\"lng\":$LNG}" \
  "$TMPDIR/addr.json")
check_ok "$code" "POST /addresses"
if [ "$(jval "$TMPDIR/addr.json" id)" != "" ]; then
  code=$(curl_json GET /addresses "$CUST_TOK" - "$TMPDIR/addr_list.json")
  check 200 "$code" "GET /addresses"
fi

code=$(curl_json GET "/workers/nearby?skill=$SKILL&lat=$LAT&lng=$LNG" "$CUST_TOK" - "$TMPDIR/near.json")
check 200 "$code" "GET /workers/nearby"

code=$(curl_json GET /notifications/health "$CUST_TOK" - "$TMPDIR/nhealth.json")
check 200 "$code" "GET /notifications/health"

# ── SUMMARY ────────────────────────────────────────────────────────────────
say "SUMMARY"
printf '  Customer: %s (%s)\n' "$PHONE_CUST" "$CUST_ID"
printf '  Worker:   %s (%s)\n' "$PHONE_WORK" "$WORK_ID"
printf '  Booking:  %s\n' "${BOOK:-none}"
printf '  PASSED: %d   FAILED: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  Failures:\n'
  for n in "${NOTES[@]}"; do printf '   - %s\n' "$n"; done
  exit 1
fi
exit 0
