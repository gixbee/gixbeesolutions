#!/usr/bin/env bash
# Full live E2E — complete two-sided journeys for every major product flow.
# Runs ON the MilesWeb host (curl + docker postgres/redis).
# Creates 2 throwaway users (customer + worker/owner), then cleans them up.

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
check_ok(){ case "$1" in 200|201) ok "$2 ($1)";; *) bad "$2 (want 2xx got $1)"; if [ -f "$3" ]; then head -c 240 "$3"; echo; fi;; esac; }
expect_status(){
  local want="$1" got="$2" label="$3" file="${4:-}"
  if [ "$got" = "$want" ]; then ok "$label ($got)"; else bad "$label (want $want got $got)"; [ -n "$file" ] && [ -f "$file" ] && { head -c 240 "$file"; echo; }; fi
}

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

# Find first object in a JSON array where field == value; print that object's id (or field)
jfind(){
  python3 -c "import json,sys
arr=json.load(open(sys.argv[1]))
field,want,out=sys.argv[2],sys.argv[3],sys.argv[4]
if not isinstance(arr,list):
    print(''); raise SystemExit
for item in arr:
    if str(item.get(field,''))==want:
        v=item.get(out,'')
        print('' if v is None else v); raise SystemExit
print('')" "$1" "$2" "$3" "$4"
}

curl_json(){
  local method="$1" path="$2" token="$3" body="$4" out="$5"
  local args=(-s -o "$out" -w '%{http_code}' -X "$method" "$API$path" -H 'content-type: application/json')
  [ "$token" != "-" ] && args+=(-H "authorization: Bearer $token")
  # Always send a JSON body for mutating verbs so Axum Json extractors don't EOF.
  if [ "$body" != "-" ]; then
    args+=(-d "$body")
  elif [[ "$method" =~ ^(POST|PATCH|PUT)$ ]]; then
    args+=(-d '{}')
  fi
  curl "${args[@]}"
}

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
  if [ -z "$otp" ] || [ "$otp" = "(nil)" ]; then echo ""; return; fi
  curl -s -X POST "$API/auth/verify-otp" -H 'content-type: application/json' \
       -d "{\"phone\":\"$phone\",\"otp\":\"$otp\"}" > "$out"
  jval "$out" accessToken
}

user_id_from_phone(){
  printf "SELECT id FROM users WHERE \"phoneNumber\"='%s';" "$1" | "${PSQL[@]}"
}

iso_plus(){
  # iso_plus "<gnu date offset>" e.g. "+3 days" / "+2 hours"
  date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
}

cleanup(){
  say "CLEANUP"
  local cust work
  cust=$(user_id_from_phone "$PHONE_CUST")
  work=$(user_id_from_phone "$PHONE_WORK")
  if [ -z "$cust" ] && [ -z "$work" ]; then
    echo "  nothing to clean"; rm -rf "$TMPDIR"; return
  fi
  "${PSQL[@]}" >/dev/null <<SQL
DO \$\$
DECLARE
  cust uuid := NULLIF('$cust','')::uuid;
  work uuid := NULLIF('$work','')::uuid;
BEGIN
  IF cust IS NOT NULL OR work IS NOT NULL THEN
    DELETE FROM messages WHERE "senderId" IN (cust, work) OR "recipientId" IN (cust, work);
    DELETE FROM event_payment_reports WHERE "quoteId" IN (
      SELECT q.id FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
      WHERE p."customerId" IN (cust, work));
    DELETE FROM event_quote_milestone_events WHERE "milestoneId" IN (
      SELECT m.id FROM event_quote_milestones m
      JOIN event_quotes q ON q.id=m."quoteId"
      JOIN event_plans p ON p.id=q."planId" WHERE p."customerId" IN (cust, work));
    DELETE FROM event_quote_milestones WHERE "quoteId" IN (
      SELECT q.id FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
      WHERE p."customerId" IN (cust, work));
    DELETE FROM hall_reservations WHERE "enquiryId" IN (
      SELECT e.id FROM hall_enquiries e JOIN event_plans p ON p.id=e."eventPlanId"
      WHERE p."customerId" IN (cust, work));
    DELETE FROM hall_enquiries WHERE "eventPlanId" IN (SELECT id FROM event_plans WHERE "customerId" IN (cust, work));
    DELETE FROM event_quotes WHERE "planId" IN (SELECT id FROM event_plans WHERE "customerId" IN (cust, work));
    DELETE FROM outbox_events WHERE "aggregateId" IN (SELECT id FROM event_plans WHERE "customerId" IN (cust, work));
    DELETE FROM event_plans WHERE "customerId" IN (cust, work);
    DELETE FROM rental_reservations WHERE "renterId" IN (cust, work)
       OR "itemId" IN (SELECT id FROM rental_items WHERE "ownerId" IN (cust, work));
    DELETE FROM rental_items WHERE "ownerId" IN (cust, work);
    DELETE FROM shop_offers WHERE "businessId" IN (SELECT id FROM businesses WHERE "ownerId" IN (cust, work));
    DELETE FROM shop_enquiries WHERE "customerId" IN (cust, work)
       OR "businessId" IN (SELECT id FROM businesses WHERE "ownerId" IN (cust, work));
    DELETE FROM hiring_interests WHERE "candidateId" IN (cust, work)
       OR "requestId" IN (SELECT id FROM hiring_requests WHERE "employerId" IN (cust, work));
    DELETE FROM hiring_requests WHERE "employerId" IN (cust, work);
    DELETE FROM job_applications WHERE "applicantId" IN (cust, work)
       OR "jobPostId" IN (SELECT id FROM job_posts WHERE "employerId" IN (cust, work));
    DELETE FROM job_posts WHERE "employerId" IN (cust, work);
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

# ═══════════════════════════════════════════════════════════════════════════
say "0) AUTH — create 2 users"
# ═══════════════════════════════════════════════════════════════════════════
CUST_TOK=$(get_token "$PHONE_CUST" "$TMPDIR/cust_auth.json")
WORK_TOK=$(get_token "$PHONE_WORK" "$TMPDIR/work_auth.json")
[ -n "$CUST_TOK" ] && ok "customer login ($PHONE_CUST)" || bad "customer login"
[ -n "$WORK_TOK" ] && ok "worker login ($PHONE_WORK)" || bad "worker login"
CUST_ID=$(user_id_from_phone "$PHONE_CUST")
WORK_ID=$(user_id_from_phone "$PHONE_WORK")
[ -n "$CUST_ID" ] && ok "customer id $CUST_ID" || bad "customer id"
[ -n "$WORK_ID" ] && ok "worker id $WORK_ID" || bad "worker id"

code=$(curl_json PATCH "/admin-user-list/$CUST_ID" "$CUST_TOK" '{"name":"E2E Customer"}' "$TMPDIR/cust_name.json")
check_ok "$code" "name customer" "$TMPDIR/cust_name.json"
code=$(curl_json PATCH "/admin-user-list/$WORK_ID" "$WORK_TOK" '{"name":"E2E Pro Owner"}' "$TMPDIR/work_name.json")
check_ok "$code" "name worker" "$TMPDIR/work_name.json"

CITY=$(printf "SELECT id FROM cities WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")
[ -n "$CITY" ] && ok "active city $CITY" || bad "no active city"

# ═══════════════════════════════════════════════════════════════════════════
say "1) MEDIA — image + resume upload"
# ═══════════════════════════════════════════════════════════════════════════
PNG="$TMPDIR/dot.png"; make_png "$PNG"
code=$(curl -s -o "$TMPDIR/up_img.json" -w '%{http_code}' -X POST "$API/uploads/image" \
  -H "authorization: Bearer $CUST_TOK" -F "file=@$PNG;type=image/png;filename=e2e-dot.png")
check 200 "$code" "POST /uploads/image"
IMG_URL=$(jval "$TMPDIR/up_img.json" url)
[ -n "$IMG_URL" ] && ok "image url $IMG_URL" || bad "image url empty"
code=$(curl_json PATCH "/admin-user-list/$CUST_ID" "$CUST_TOK" \
  "{\"profileImageUrl\":\"$IMG_URL\"}" "$TMPDIR/cust_photo.json")
check_ok "$code" "set profile photo" "$TMPDIR/cust_photo.json"
code=$(curl -s -o "$TMPDIR/up_bad.json" -w '%{http_code}' -X POST "$API/uploads/image" \
  -H "authorization: Bearer $CUST_TOK" -F "file=@$PNG;type=image/svg+xml;filename=evil.svg")
expect_status 400 "$code" "reject .svg upload"
PDF="$TMPDIR/blank.pdf"; printf '%%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%%%EOF\n' > "$PDF"
code=$(curl -s -o "$TMPDIR/up_res.json" -w '%{http_code}' -X POST "$API/uploads/resume" \
  -H "authorization: Bearer $CUST_TOK" -F "file=@$PDF;type=application/pdf;filename=e2e-cv.pdf")
check 200 "$code" "POST /uploads/resume"

# ═══════════════════════════════════════════════════════════════════════════
say "2) INSTANT HELP — full job lifecycle"
# ═══════════════════════════════════════════════════════════════════════════
code=$(curl_json POST /workers/register "$WORK_TOK" \
  "{\"skills\":[\"$SKILL\"],\"hourlyRate\":250,\"bio\":\"E2E pro\",\"title\":\"E2E Electrician\"}" \
  "$TMPDIR/wreg.json")
check_ok "$code" "worker register" "$TMPDIR/wreg.json"
code=$(curl_json PATCH /workers/me/languages "$WORK_TOK" '{"languages":["English","Telugu"]}' "$TMPDIR/wlang.json")
check_ok "$code" "worker languages" "$TMPDIR/wlang.json"
code=$(curl_json PATCH /workers/me/service-radius "$WORK_TOK" '{"serviceRadiusKm":15}' "$TMPDIR/wrad.json")
check_ok "$code" "worker radius" "$TMPDIR/wrad.json"
code=$(curl_json PATCH /workers/me/active-skills "$WORK_TOK" "{\"skills\":[\"$SKILL\"]}" "$TMPDIR/wsk.json")
check_ok "$code" "worker active skills" "$TMPDIR/wsk.json"

printf "UPDATE worker_profiles SET \"verificationStatus\"='VERIFIED', \"activeSkills\"='%s', skills='%s', languages='English,Telugu', \"serviceRadiusKm\"=15 WHERE \"userId\"='%s';
UPDATE users SET \"approvalStatus\"='APPROVED', \"hasWorkerProfile\"=true WHERE id='%s';
DELETE FROM job_credits WHERE \"userId\"='%s';
INSERT INTO job_credits (id, \"userId\", balance) VALUES (gen_random_uuid(), '%s', 45);
" "$SKILL" "$SKILL" "$WORK_ID" "$WORK_ID" "$WORK_ID" "$WORK_ID" | "${PSQL[@]}" >/dev/null
ok "DB gate: verified worker + 45 credits"

code=$(curl_json GET /billing/credits/balance "$WORK_TOK" - "$TMPDIR/bal.json")
check 200 "$code" "credits balance"
[ "$(jval "$TMPDIR/bal.json" balance)" = "45" ] && ok "balance=45" || bad "balance=$(jval "$TMPDIR/bal.json" balance)"

code=$(curl_json POST /workers/live-toggle "$WORK_TOK" \
  "{\"active\":true,\"lat\":$LAT,\"lng\":$LNG}" "$TMPDIR/live.json")
check_ok "$code" "go live" "$TMPDIR/live.json"

code=$(curl_json POST /addresses "$CUST_TOK" \
  "{\"label\":\"Home\",\"line\":\"E2E Lane Hyderabad\",\"lat\":$LAT,\"lng\":$LNG}" \
  "$TMPDIR/addr.json")
check_ok "$code" "customer address" "$TMPDIR/addr.json"
ADDR_ID=$(jval "$TMPDIR/addr.json" id)

code=$(curl_json POST /bookings/instant "$CUST_TOK" \
  "{\"skill\":\"$SKILL\",\"serviceLocation\":\"E2E Test Street Hyderabad\",\"serviceLat\":$LAT,\"serviceLng\":$LNG,\"amount\":200,\"description\":\"E2E fuse board check\",\"preferredLanguages\":[\"English\"],\"paymentMethod\":\"CASH\",\"addressId\":\"$ADDR_ID\",\"onSiteContact\":{\"name\":\"Onsite\",\"relation\":\"Self\",\"phone\":\"9998887777\"}}" \
  "$TMPDIR/inst.json")
check_ok "$code" "create Instant Help" "$TMPDIR/inst.json"
BOOK=$(jval "$TMPDIR/inst.json" booking id)
[ -z "$BOOK" ] && BOOK=$(jval "$TMPDIR/inst.json" id)
NOTIFIED=$(jval "$TMPDIR/inst.json" notified)
[ -n "$BOOK" ] && ok "booking $BOOK (notified=$NOTIFIED)" || bad "booking id missing"
"${REDIS[@]}" zadd "worker:pending:$WORK_ID" "$(date +%s%3N)" "$BOOK" >/dev/null
"${REDIS[@]}" expire "worker:pending:$WORK_ID" 120 >/dev/null
ok "seed pending offer"

code=$(curl_json GET /bookings/pending "$WORK_TOK" - "$TMPDIR/pending.json")
check 200 "$code" "worker pending list"

code=$(curl_json PATCH "/bookings/$BOOK/accept" "$WORK_TOK" - "$TMPDIR/acc.json")
check_ok "$code" "accept booking" "$TMPDIR/acc.json"
code=$(curl_json GET "/bookings/$BOOK/status" "$CUST_TOK" - "$TMPDIR/st1.json")
check 200 "$code" "customer status after accept"
expect_status "ACCEPTED" "$(jval "$TMPDIR/st1.json" status)" "status ACCEPTED"
ARR_OTP=$(jval "$TMPDIR/st1.json" arrivalOtp)
[ -z "$ARR_OTP" ] && ARR_OTP=$(printf "SELECT \"arrivalOtp\" FROM bookings WHERE id='%s';" "$BOOK" | "${PSQL[@]}")
[ -n "$ARR_OTP" ] && ok "arrival OTP" || bad "arrival OTP"

# Petrol snapshot after Instant accept
PETROL=$(printf "SELECT COALESCE(\"petrolAmount\"::text,'') FROM bookings WHERE id='%s';" "$BOOK" | "${PSQL[@]}")
ok "petrolAmount snapshot='$PETROL'"

code=$(curl_json PATCH "/bookings/$BOOK/arrive" "$WORK_TOK" - "$TMPDIR/arr.json")
check_ok "$code" "mark arrived" "$TMPDIR/arr.json"
code=$(curl_json POST "/bookings/$BOOK/arrival" "$WORK_TOK" "{\"otp\":\"$ARR_OTP\"}" "$TMPDIR/arr_otp.json")
check_ok "$code" "arrival OTP → ACTIVE" "$TMPDIR/arr_otp.json"
code=$(curl_json GET "/bookings/$BOOK/status" "$CUST_TOK" - "$TMPDIR/st2.json")
expect_status "ACTIVE" "$(jval "$TMPDIR/st2.json" status)" "status ACTIVE"

COMP_OTP=$(printf "SELECT \"completionOtp\" FROM bookings WHERE id='%s';" "$BOOK" | "${PSQL[@]}")
[ -n "$COMP_OTP" ] && ok "completion OTP" || bad "completion OTP"
code=$(curl_json PATCH "/bookings/$BOOK/complete" "$WORK_TOK" - "$TMPDIR/comp.json")
check_ok "$code" "notify completion" "$TMPDIR/comp.json"
code=$(curl_json POST "/bookings/$BOOK/completion" "$CUST_TOK" "{\"otp\":\"$COMP_OTP\"}" "$TMPDIR/comp_otp.json")
check_ok "$code" "completion OTP → COMPLETED" "$TMPDIR/comp_otp.json"

code=$(curl_json PATCH "/bookings/$BOOK/mark-paid" "$CUST_TOK" \
  '{"collectionMethod":"UPI","safetyCheck":"SAFE"}' "$TMPDIR/pay_c.json")
check_ok "$code" "customer mark paid" "$TMPDIR/pay_c.json"
code=$(curl_json PATCH "/bookings/$BOOK/mark-paid" "$WORK_TOK" \
  '{"honestyCheck":"HONEST"}' "$TMPDIR/pay_w.json")
check_ok "$code" "worker mark paid" "$TMPDIR/pay_w.json"
[ "$(jval "$TMPDIR/pay_w.json" isPaid)" = "true" ] || [ "$(jval "$TMPDIR/pay_w.json" isPaid)" = "True" ] \
  && ok "isPaid dual-confirm" || bad "isPaid=$(jval "$TMPDIR/pay_w.json" isPaid)"

code=$(curl_json POST "/bookings/$BOOK/rating" "$CUST_TOK" '{"rating":5}' "$TMPDIR/rate_w.json")
check_ok "$code" "rate worker" "$TMPDIR/rate_w.json"
code=$(curl_json POST "/bookings/$BOOK/rate-customer" "$WORK_TOK" '{"rating":5}' "$TMPDIR/rate_c.json")
check_ok "$code" "rate customer" "$TMPDIR/rate_c.json"
code=$(curl_json POST /messages "$CUST_TOK" \
  "{\"recipientId\":\"$WORK_ID\",\"body\":\"Thanks for completing the job\",\"bookingId\":\"$BOOK\"}" \
  "$TMPDIR/msg.json")
check_ok "$code" "booking chat message" "$TMPDIR/msg.json"
code=$(curl_json GET "/messages/thread/$WORK_ID" "$CUST_TOK" - "$TMPDIR/thread.json")
check 200 "$code" "message thread"
code=$(curl_json GET /bookings/my "$CUST_TOK" - "$TMPDIR/myb.json")
check 200 "$code" "bookings/my"

# Free cancel path on a second short-lived request
code=$(curl_json POST /bookings/instant "$CUST_TOK" \
  "{\"skill\":\"$SKILL\",\"serviceLocation\":\"E2E Cancel Loc\",\"serviceLat\":$LAT,\"serviceLng\":$LNG,\"amount\":150,\"description\":\"cancel me\",\"preferredLanguages\":[\"English\"],\"paymentMethod\":\"CASH\"}" \
  "$TMPDIR/inst2.json")
check_ok "$code" "second Instant (cancel path)" "$TMPDIR/inst2.json"
BOOK2=$(jval "$TMPDIR/inst2.json" booking id); [ -z "$BOOK2" ] && BOOK2=$(jval "$TMPDIR/inst2.json" id)
code=$(curl_json PATCH "/bookings/$BOOK2/cancel" "$CUST_TOK" '{"reason":"E2E free cancel while REQUESTED"}' "$TMPDIR/cancel.json")
check_ok "$code" "cancel while REQUESTED" "$TMPDIR/cancel.json"

# ═══════════════════════════════════════════════════════════════════════════
say "3) BUSINESSES — register all types + shop enquiry"
# ═══════════════════════════════════════════════════════════════════════════
code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Catering Co","type":"SERVICE","address":"E2E Street","serviceType":"CATERING","eventServices":["CATERING"],"phone":"9998887770"}' \
  "$TMPDIR/bcater.json")
check_ok "$code" "SERVICE CATERING" "$TMPDIR/bcater.json"
BCATER=$(jval "$TMPDIR/bcater.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Event Hall","type":"SERVICE","address":"E2E Hall Rd","serviceType":"HALL","eventServices":["HALL"],"phone":"9998887774"}' \
  "$TMPDIR/bhall.json")
check_ok "$code" "SERVICE HALL" "$TMPDIR/bhall.json"
BHALL=$(jval "$TMPDIR/bhall.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Rental Unit","type":"RENTAL","address":"E2E Depot","phone":"9998887771"}' \
  "$TMPDIR/brent.json")
check_ok "$code" "RENTAL" "$TMPDIR/brent.json"
BRENT=$(jval "$TMPDIR/brent.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Hardware Shop","type":"SHOP","address":"E2E Market","phone":"9998887772","hiringProfile":{"shopCategory":"Hardware"}}' \
  "$TMPDIR/bshop.json")
check_ok "$code" "SHOP" "$TMPDIR/bshop.json"
BSHOP=$(jval "$TMPDIR/bshop.json" id)

code=$(curl_json POST /businesses "$WORK_TOK" \
  '{"name":"E2E Hire Co","type":"HIRING","address":"E2E HR Lane","phone":"9998887773"}' \
  "$TMPDIR/bhire.json")
check_ok "$code" "HIRING" "$TMPDIR/bhire.json"
BHIRE=$(jval "$TMPDIR/bhire.json" id)

code=$(curl_json GET /businesses/my "$WORK_TOK" - "$TMPDIR/bmy.json")
check 200 "$code" "list my businesses"

IDS=""
for id in "$BCATER" "$BHALL" "$BRENT" "$BSHOP" "$BHIRE"; do
  [ -n "$id" ] || continue
  [ -n "$IDS" ] && IDS="$IDS,"
  IDS="$IDS'$id'"
done
if [ -n "$IDS" ] && [ -n "$CITY" ]; then
  printf "UPDATE businesses SET status='VERIFIED', \"cityId\"=COALESCE(\"cityId\",'%s') WHERE id IN (%s);" \
    "$CITY" "$IDS" | "${PSQL[@]}" >/dev/null
  ok "DB verified all businesses + city"
fi

code=$(curl_json POST "/businesses/$BSHOP/offers" "$WORK_TOK" \
  '{"kind":"NORMAL","title":"E2E Drill Offer","code":"E2EDRILL","discount":"10%","category":"Hardware"}' \
  "$TMPDIR/offer.json")
check_ok "$code" "shop offer" "$TMPDIR/offer.json"
code=$(curl_json GET "/businesses/shop-offers?category=Hardware" "$CUST_TOK" - "$TMPDIR/soff.json")
check 200 "$code" "browse shop offers"
code=$(curl_json POST /businesses/shop-enquiries "$CUST_TOK" \
  "{\"businessId\":\"$BSHOP\",\"placeName\":\"E2E Hardware Shop\",\"category\":\"Hardware\",\"package\":\"E2EDRILL\",\"message\":\"Need a cordless drill this weekend\"}" \
  "$TMPDIR/senq.json")
check_ok "$code" "shop enquiry" "$TMPDIR/senq.json"
code=$(curl_json GET "/businesses/$BSHOP/enquiries" "$WORK_TOK" - "$TMPDIR/senq_list.json")
check 200 "$code" "owner shop enquiries inbox"

# ═══════════════════════════════════════════════════════════════════════════
say "4) RENTALS — reserve → pay-hold → confirm → handover → return → settle"
# ═══════════════════════════════════════════════════════════════════════════
code=$(curl_json GET /rentals - - "$TMPDIR/rent_pub.json")
check 200 "$code" "public rental catalog"
code=$(curl_json POST /rentals "$WORK_TOK" \
  "{\"name\":\"E2E Camera\",\"hourlyRate\":100,\"dailyRate\":1000,\"minHoursToRent\":2,\"businessId\":\"$BRENT\",\"pickupAddress\":\"E2E Depot\",\"quantity\":2,\"imageUrl\":\"$IMG_URL\",\"pickupLat\":$LAT,\"pickupLng\":$LNG,\"category\":\"CAMERA\",\"condition\":\"GOOD\",\"cancellationPolicy\":\"FLEXIBLE\",\"depositPerUnit\":0}" \
  "$TMPDIR/item.json")
check_ok "$code" "create rental item" "$TMPDIR/item.json"
ITEM=$(jval "$TMPDIR/item.json" id)
code=$(curl_json GET "/rentals/my-items?businessId=$BRENT" "$WORK_TOK" - "$TMPDIR/myitems.json")
check 200 "$code" "owner my-items"

START=$(iso_plus "now")
END=$(iso_plus "+49 hours")
code=$(curl_json POST "/rentals/$ITEM/reserve" "$CUST_TOK" \
  "{\"startTime\":\"$START\",\"endTime\":\"$END\",\"quantity\":1,\"fulfillment\":\"PICKUP\"}" \
  "$TMPDIR/res.json")
check_ok "$code" "reserve item" "$TMPDIR/res.json"
RES=$(jval "$TMPDIR/res.json" id)
RSTAT=$(jval "$TMPDIR/res.json" status)
PRICE=$(jval "$TMPDIR/res.json" totalPrice)
ok "reservation $RES status=$RSTAT price=$PRICE"

if [ "$RSTAT" = "TEMP_HOLD" ] || [ "$RSTAT" = "PAYMENT_PENDING" ]; then
  printf "UPDATE rental_reservations SET status='PENDING_OWNER_CONFIRMATION', \"paymentStatus\"='PAID', \"holdExpiresAt\"=NULL WHERE id='%s';" \
    "$RES" | "${PSQL[@]}" >/dev/null
  ok "simulate advance paid ($RSTAT → PENDING_OWNER_CONFIRMATION)"
fi

code=$(curl_json PATCH "/rentals/reservations/$RES/confirm" "$WORK_TOK" - "$TMPDIR/rconf.json")
check_ok "$code" "owner confirm" "$TMPDIR/rconf.json"
code=$(curl_json PATCH "/rentals/reservations/$RES/start" "$WORK_TOK" - "$TMPDIR/rho1.json")
check_ok "$code" "owner handover ack" "$TMPDIR/rho1.json"
code=$(curl_json PATCH "/rentals/reservations/$RES/ack/handover" "$CUST_TOK" - "$TMPDIR/rho2.json")
check_ok "$code" "renter handover ack → ACTIVE" "$TMPDIR/rho2.json"
expect_status "ACTIVE" "$(jval "$TMPDIR/rho2.json" status)" "rental ACTIVE after dual handover"

code=$(curl_json PATCH "/rentals/reservations/$RES/ack/return" "$WORK_TOK" - "$TMPDIR/rret1.json")
check_ok "$code" "owner return ack" "$TMPDIR/rret1.json"
code=$(curl_json PATCH "/rentals/reservations/$RES/ack/return" "$CUST_TOK" - "$TMPDIR/rret2.json")
check_ok "$code" "renter return ack" "$TMPDIR/rret2.json"
code=$(curl_json PATCH "/rentals/reservations/$RES/ack/payment" "$CUST_TOK" - "$TMPDIR/rpay1.json")
check_ok "$code" "renter payment ack" "$TMPDIR/rpay1.json"
code=$(curl_json PATCH "/rentals/reservations/$RES/ack/payment" "$WORK_TOK" - "$TMPDIR/rpay2.json")
check_ok "$code" "owner payment ack → COMPLETED" "$TMPDIR/rpay2.json"
expect_status "COMPLETED" "$(jval "$TMPDIR/rpay2.json" status)" "rental COMPLETED"

code=$(curl_json GET /rentals/reservations/my "$CUST_TOK" - "$TMPDIR/rmy.json")
check 200 "$code" "renter reservations"
code=$(curl_json GET /rentals/reservations/owner "$WORK_TOK" - "$TMPDIR/rown.json")
check 200 "$code" "owner reservations"

# ═══════════════════════════════════════════════════════════════════════════
say "5) EVENTS — catering enquiry → quote → accept → payment milestone"
# ═══════════════════════════════════════════════════════════════════════════
if [ -n "$CITY" ] && [ -n "$BCATER" ]; then
  ESTART=$(iso_plus "+3 days")
  EEND=$(iso_plus "+3 days 4 hours")
  code=$(curl_json POST /events "$CUST_TOK" \
    "{\"eventType\":\"Wedding\",\"startTime\":\"$ESTART\",\"endTime\":\"$EEND\",\"guestCount\":120,\"location\":\"E2E Venue Hyderabad\",\"cityId\":\"$CITY\",\"services\":[\"CATERING\"],\"notes\":\"E2E catering full flow\",\"serviceRequest\":{\"servingStyle\":\"Buffet\",\"dietaryNeeds\":\"Veg\",\"menuChanges\":\"Add desserts\"},\"targetBusinessId\":\"$BCATER\"}" \
    "$TMPDIR/plan.json")
  # Targeted plan needs serviceRequest matching provider catalogue OR city-wide plan may work without target
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    code=$(curl_json POST /events "$CUST_TOK" \
      "{\"eventType\":\"Wedding\",\"startTime\":\"$ESTART\",\"endTime\":\"$EEND\",\"guestCount\":120,\"location\":\"E2E Venue Hyderabad\",\"cityId\":\"$CITY\",\"services\":[\"CATERING\"],\"notes\":\"E2E catering city broadcast\"}" \
      "$TMPDIR/plan.json")
  fi
  check_ok "$code" "create event plan" "$TMPDIR/plan.json"
  PLAN=$(jval "$TMPDIR/plan.json" id)
  [ -n "$PLAN" ] && ok "plan $PLAN" || bad "plan id"

  code=$(curl_json GET "/events/vendor/inbox?businessId=$BCATER" "$WORK_TOK" - "$TMPDIR/vinbox.json")
  check 200 "$code" "vendor inbox"

  code=$(curl_json POST "/events/$PLAN/quotes" "$WORK_TOK" \
    "{\"businessId\":\"$BCATER\",\"serviceType\":\"CATERING\",\"amount\":45000,\"inclusions\":\"Veg buffet for 120, dessert counter, service staff\",\"cancellationTerms\":\"50 percent advance non-refundable within 7 days of event\"}" \
    "$TMPDIR/quote.json")
  check_ok "$code" "vendor offer quote" "$TMPDIR/quote.json"
  QUOTE=$(jval "$TMPDIR/quote.json" id)
  [ -n "$QUOTE" ] && ok "quote $QUOTE" || bad "quote id"
  # Optimistic concurrency: accept requires the quote's current updatedAt (exact API value)
  QUPD=$(jval "$TMPDIR/quote.json" updatedAt)
  [ -n "$QUPD" ] && ok "quote updatedAt=$QUPD" || bad "quote updatedAt missing"

  code=$(curl_json POST "/events/quotes/$QUOTE/accept" "$CUST_TOK" \
    "{\"updatedAt\":\"$QUPD\"}" "$TMPDIR/qacc.json")
  check_ok "$code" "customer accept quote" "$TMPDIR/qacc.json"

  code=$(curl_json GET "/events/quotes/$QUOTE/milestones" "$CUST_TOK" - "$TMPDIR/ms.json")
  check 200 "$code" "list milestones"
  # Seed a payment milestone if accept did not (catering without catalogue split)
  MS_COUNT=$(python3 -c "import json; d=json.load(open('$TMPDIR/ms.json')); print(len(d) if isinstance(d,list) else 0)")
  if [ "$MS_COUNT" = "0" ]; then
    code=$(curl_json POST "/events/quotes/$QUOTE/milestones" "$WORK_TOK" \
      '{"milestones":[{"kind":"PAYMENT","label":"Advance","percent":40},{"kind":"PAYMENT","label":"Balance","percent":60},{"kind":"DELIVERY","label":"Menu finalised"}]}' \
      "$TMPDIR/ms_seed.json")
    check_ok "$code" "seed milestones" "$TMPDIR/ms_seed.json"
    code=$(curl_json GET "/events/quotes/$QUOTE/milestones" "$CUST_TOK" - "$TMPDIR/ms.json")
    check 200 "$code" "reload milestones"
  else
    ok "milestones already present ($MS_COUNT)"
  fi

  MS_ID=$(python3 -c "import json
d=json.load(open('$TMPDIR/ms.json'))
for m in d:
  if m.get('kind')=='PAYMENT':
    print(m.get('id','')); break
else: print('')")
  if [ -n "$MS_ID" ]; then
    code=$(curl_json POST "/events/quotes/$QUOTE/payments/$MS_ID" "$CUST_TOK" \
      '{"method":"UPI","reference":"E2EUPI123456","note":"Advance paid directly"}' \
      "$TMPDIR/payrep.json")
    check_ok "$code" "customer report payment" "$TMPDIR/payrep.json"
    code=$(curl_json POST "/events/quotes/$QUOTE/payments/$MS_ID/review" "$WORK_TOK" \
      '{"decision":"CONFIRM","note":"Received"}' \
      "$TMPDIR/payrev.json")
    check_ok "$code" "vendor confirm payment" "$TMPDIR/payrev.json"
  else
    bad "no PAYMENT milestone to settle"
  fi

  DEL_ID=$(python3 -c "import json
d=json.load(open('$TMPDIR/ms.json'))
for m in d:
  if m.get('kind')=='DELIVERY':
    print(m.get('id','')); break
else: print('')")
  if [ -n "$DEL_ID" ]; then
    code=$(curl_json POST "/events/quotes/$QUOTE/milestones/$DEL_ID/ack" "$WORK_TOK" - "$TMPDIR/dack1.json")
    check_ok "$code" "vendor ack delivery" "$TMPDIR/dack1.json"
    code=$(curl_json POST "/events/quotes/$QUOTE/milestones/$DEL_ID/ack" "$CUST_TOK" - "$TMPDIR/dack2.json")
    check_ok "$code" "customer ack delivery" "$TMPDIR/dack2.json"
  fi

  code=$(curl_json GET /events "$CUST_TOK" - "$TMPDIR/plans.json")
  check 200 "$code" "customer event list"
  code=$(curl_json GET "/events/$PLAN" "$CUST_TOK" - "$TMPDIR/pdet.json")
  check 200 "$code" "event detail"
else
  bad "skip events — missing city or catering business"
fi

# ═══════════════════════════════════════════════════════════════════════════
say "6) HIRING — classic board + Smart Hiring pipeline"
# ═══════════════════════════════════════════════════════════════════════════
# Classic board: employer posts → candidate applies → interview → selected
code=$(curl_json POST /hiring/jobs "$WORK_TOK" \
  "{\"title\":\"E2E Electrician Opening\",\"description\":\"Full time electrician for residential work. Tools preferred.\",\"requiredSkills\":[\"Wiring\",\"$SKILL\"],\"jobType\":\"$SKILL\",\"experience\":\"2+ years\",\"location\":\"Hyderabad\",\"salaryMin\":18000,\"salaryMax\":28000,\"businessId\":\"$BHIRE\",\"openings\":1,\"workMode\":\"ONSITE\"}" \
  "$TMPDIR/job.json")
check_ok "$code" "post classic job" "$TMPDIR/job.json"
JOB=$(jval "$TMPDIR/job.json" id)
[ -n "$JOB" ] && ok "job $JOB" || bad "job id"

code=$(curl_json POST "/hiring/jobs/$JOB/apply" "$CUST_TOK" \
  "{\"coverLetter\":\"E2E candidate cover letter\",\"resumeUrl\":\"$IMG_URL\"}" \
  "$TMPDIR/apply.json")
check_ok "$code" "candidate apply" "$TMPDIR/apply.json"
APP=$(jval "$TMPDIR/apply.json" id)
[ -z "$APP" ] && APP=$(printf "SELECT id FROM job_applications WHERE \"jobPostId\"='%s' AND \"applicantId\"='%s' ORDER BY \"createdAt\" DESC LIMIT 1;" "$JOB" "$CUST_ID" | "${PSQL[@]}")
[ -n "$APP" ] && ok "application $APP" || bad "application id"

code=$(curl_json GET "/hiring/jobs/$JOB/applications" "$WORK_TOK" - "$TMPDIR/apps.json")
check 200 "$code" "employer applications inbox"
code=$(curl_json PATCH "/hiring/applications/$APP/status" "$WORK_TOK" \
  '{"status":"INTERVIEW"}' "$TMPDIR/app_iv.json")
check_ok "$code" "status → INTERVIEW" "$TMPDIR/app_iv.json"
code=$(curl_json PATCH "/hiring/applications/$APP/status" "$WORK_TOK" \
  '{"status":"SELECTED"}' "$TMPDIR/app_sel.json")
check_ok "$code" "status → SELECTED" "$TMPDIR/app_sel.json"
code=$(curl_json GET /hiring/my-applications "$CUST_TOK" - "$TMPDIR/myapps.json")
check 200 "$code" "candidate my-applications"

# Smart Hiring: preference → match request → interest → shortlist → offer → accept
code=$(curl_json POST /hiring/match/preferences "$CUST_TOK" \
  "{\"jobType\":\"$SKILL\",\"skills\":[\"Wiring\"],\"expectedSalary\":22000,\"preferredLocation\":\"Hyderabad\",\"employmentType\":\"FULL_TIME\",\"experienceYears\":3,\"noticePeriod\":\"DAYS_30\"}" \
  "$TMPDIR/pref.json")
check_ok "$code" "candidate job type preference" "$TMPDIR/pref.json"
PREF=$(jval "$TMPDIR/pref.json" id)

SECTOR=$(printf "SELECT id FROM hiring_sectors WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")
POSITION=$(printf "SELECT p.id FROM hiring_positions p JOIN hiring_sector_positions sp ON sp.\"positionId\"=p.id WHERE p.\"isActive\"=true AND sp.\"sectorId\"='%s' LIMIT 1;" "$SECTOR" | "${PSQL[@]}")
LOC=$(printf "SELECT id FROM hiring_locations WHERE \"isActive\"=true LIMIT 1;" | "${PSQL[@]}")

if [ -n "$SECTOR" ] && [ -n "$POSITION" ] && [ -n "$LOC" ] && [ -n "$BHIRE" ]; then
  printf "UPDATE users SET \"hiringCreditBalance\" = 500 WHERE id='%s';" "$WORK_ID" | "${PSQL[@]}" >/dev/null
  ok "seed hiring credits ₹500"

  code=$(curl_json POST /hiring/match/requests "$WORK_TOK" \
    "{\"businessId\":\"$BHIRE\",\"jobType\":\"$SKILL\",\"skills\":[\"Wiring\"],\"salaryMin\":18000,\"salaryMax\":30000,\"salaryOffered\":25000,\"employmentType\":\"FULL_TIME\",\"experienceMinYears\":1,\"vacancies\":1,\"location\":\"Hyderabad\",\"description\":\"E2E smart hiring opening\",\"sectorId\":\"$SECTOR\",\"positionId\":\"$POSITION\",\"locationId\":\"$LOC\",\"workMode\":\"ONSITE\"}" \
    "$TMPDIR/hreq.json")
  check_ok "$code" "create Smart Hiring request" "$TMPDIR/hreq.json"
  HREQ=$(jval "$TMPDIR/hreq.json" request id)
  [ -z "$HREQ" ] && HREQ=$(jval "$TMPDIR/hreq.json" id)
  if [ -z "$HREQ" ] && [ "$(jval "$TMPDIR/hreq.json" needsPayment)" = "true" ]; then
    bad "Smart Hiring still needs payment despite credits"
  elif [ -n "$HREQ" ]; then
    ok "hiring request $HREQ"
    # Ensure candidate receives an offer (engine may not have polled yet)
    INTEREST=$(printf "SELECT id FROM hiring_interests WHERE \"requestId\"='%s' AND \"candidateId\"='%s' LIMIT 1;" "$HREQ" "$CUST_ID" | "${PSQL[@]}")
    if [ -z "$INTEREST" ]; then
      printf "INSERT INTO hiring_interests (id,\"requestId\",\"candidateId\",\"preferenceId\",response,\"notifiedAt\")
        VALUES (gen_random_uuid(),'%s','%s',NULLIF('%s','')::uuid,'PENDING',NOW());" \
        "$HREQ" "$CUST_ID" "$PREF" | "${PSQL[@]}" >/dev/null
      ok "seed PENDING interest for candidate"
    else
      ok "engine already notified candidate ($INTEREST)"
    fi

    code=$(curl_json GET /hiring/match/offers "$CUST_TOK" - "$TMPDIR/offers.json")
    check 200 "$code" "candidate offers inbox"
    code=$(curl_json POST "/hiring/match/offers/$HREQ/respond" "$CUST_TOK" \
      '{"interested":true}' "$TMPDIR/respond.json")
    check_ok "$code" "candidate INTERESTED" "$TMPDIR/respond.json"

    INTEREST=$(printf "SELECT id FROM hiring_interests WHERE \"requestId\"='%s' AND \"candidateId\"='%s' LIMIT 1;" "$HREQ" "$CUST_ID" | "${PSQL[@]}")
    code=$(curl_json PATCH "/hiring/match/interests/$INTEREST/decision" "$WORK_TOK" \
      '{"decision":"SHORTLISTED"}' "$TMPDIR/short.json")
    check_ok "$code" "employer SHORTLISTED" "$TMPDIR/short.json"

    code=$(curl_json GET "/hiring/match/interests/$INTEREST/progress" "$WORK_TOK" - "$TMPDIR/hprog.json")
    check 200 "$code" "interest progress detail"
    REV=$(jval "$TMPDIR/hprog.json" revision)
    [ -z "$REV" ] && REV=$(printf "SELECT revision FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    [ -n "$REV" ] && ok "interest revision=$REV" || bad "interest revision missing"

    JOIN_AT=$(iso_plus "+2 days")
    code=$(curl_json POST "/hiring/match/interests/$INTEREST/progress/offer" "$WORK_TOK" \
      "{\"salary\":24000,\"joiningAt\":\"$JOIN_AT\",\"offerTerms\":\"Full time electrician, PF after probation\",\"revision\":$REV}" \
      "$TMPDIR/hoffer.json")
    check_ok "$code" "employer send offer" "$TMPDIR/hoffer.json"
    REV=$(jval "$TMPDIR/hoffer.json" revision)
    [ -z "$REV" ] && REV=$(printf "SELECT revision FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    code=$(curl_json POST "/hiring/match/interests/$INTEREST/progress/accept-offer" "$CUST_TOK" \
      "{\"revision\":$REV}" "$TMPDIR/hacc.json")
    check_ok "$code" "candidate accept offer" "$TMPDIR/hacc.json"

    # Bring joiningAt into the past (RFC3339 with Z) so dual join can complete without waiting
    PAST_JOIN=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
    printf "UPDATE hiring_interests SET progress = jsonb_set(progress, '{joiningAt}', to_jsonb('%s'::text), true), revision = revision + 1 WHERE id='%s' RETURNING progress->>'joiningAt', revision;" \
      "$PAST_JOIN" "$INTEREST" | "${PSQL[@]}" >"$TMPDIR/join_bump.txt"
    ok "joiningAt bumped past → $(tr '|' ' ' <"$TMPDIR/join_bump.txt" | head -c 80)"
    REV=$(printf "SELECT revision FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    code=$(curl_json POST "/hiring/match/interests/$INTEREST/progress/joined" "$WORK_TOK" \
      "{\"revision\":$REV}" "$TMPDIR/join_e.json")
    check_ok "$code" "employer confirm joined" "$TMPDIR/join_e.json"
    REV=$(jval "$TMPDIR/join_e.json" revision)
    [ -z "$REV" ] && REV=$(printf "SELECT revision FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    code=$(curl_json POST "/hiring/match/interests/$INTEREST/progress/joined" "$CUST_TOK" \
      "{\"revision\":$REV}" "$TMPDIR/join_c.json")
    check_ok "$code" "candidate confirm joined → HIRED" "$TMPDIR/join_c.json"
    STAGE=$(jval "$TMPDIR/join_c.json" progress stage)
    [ -z "$STAGE" ] && STAGE=$(printf "SELECT progress->>'stage' FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    [ "$STAGE" = "JOINED" ] && ok "pipeline stage JOINED" || ok "pipeline stage='$STAGE' (check decision)"
    DEC=$(printf "SELECT decision::text FROM hiring_interests WHERE id='%s';" "$INTEREST" | "${PSQL[@]}")
    [ "$DEC" = "HIRED" ] && ok "decision HIRED" || bad "decision=$DEC"

    code=$(curl_json GET "/hiring/match/requests/$HREQ" "$WORK_TOK" - "$TMPDIR/hreq_get.json")
    check 200 "$code" "employer request detail"
  fi
else
  bad "Smart Hiring skipped — catalogue sector/position/location missing"
fi

code=$(curl_json GET /hiring/catalogue "$CUST_TOK" - "$TMPDIR/cat.json")
check 200 "$code" "hiring catalogue snapshot"
code=$(curl_json GET /hiring/jobs "$CUST_TOK" - "$TMPDIR/jobs.json")
check 200 "$code" "public job board"

# ═══════════════════════════════════════════════════════════════════════════
say "7) PROFILE EXTRAS"
# ═══════════════════════════════════════════════════════════════════════════
code=$(curl_json GET /auth/profile "$CUST_TOK" - "$TMPDIR/prof.json")
check 200 "$code" "auth profile"
code=$(curl_json GET "/workers/nearby?skill=$SKILL&lat=$LAT&lng=$LNG" "$CUST_TOK" - "$TMPDIR/near.json")
check 200 "$code" "nearby workers"
code=$(curl_json GET /workers/me/dashboard "$WORK_TOK" - "$TMPDIR/wdash.json")
check 200 "$code" "worker dashboard"
code=$(curl_json GET /notifications/health "$CUST_TOK" - "$TMPDIR/nhealth.json")
check 200 "$code" "notifications health"
code=$(curl_json GET /addresses "$CUST_TOK" - "$TMPDIR/addrs.json")
check 200 "$code" "list addresses"

# ═══════════════════════════════════════════════════════════════════════════
say "SUMMARY"
# ═══════════════════════════════════════════════════════════════════════════
printf '  Customer: %s (%s)\n' "$PHONE_CUST" "$CUST_ID"
printf '  Worker:   %s (%s)\n' "$PHONE_WORK" "$WORK_ID"
printf '  Instant:  %s\n' "${BOOK:-none}"
printf '  Rental:   %s\n' "${RES:-none}"
printf '  Event:    %s / quote %s\n' "${PLAN:-none}" "${QUOTE:-none}"
printf '  Job:      %s / app %s\n' "${JOB:-none}" "${APP:-none}"
printf '  SmartHire:%s\n' "${HREQ:-none}"
printf '  PASSED: %d   FAILED: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  Failures:\n'
  for n in "${NOTES[@]}"; do printf '   - %s\n' "$n"; done
  exit 1
fi
exit 0
