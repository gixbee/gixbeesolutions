# Gixbee — Major Fallbacks Report

> Cross-layer analysis: Flutter + NestJS backend read together.
> These are architectural and security issues, not UI bugs.

---

## 🔴 CRITICAL — Security Vulnerabilities

---

### 1. OTP is NEVER sent via SMS — returned in every API response

**`backend/src/auth/auth.service.ts` — `requestOtp()`**

```typescript
async requestOtp(phoneNumber: string) {
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  await this.redisService.saveOtp(`otp:${phoneNumber}`, otp);
  // await this.smsService.send(phoneNumber, ...);  ← COMMENTED OUT — never sent
  console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
  return { message: 'OTP sent successfully', devOtp: otp };  // ← returned to ALL callers
}
```

The SMS send line is commented out. The OTP is **never delivered to the user's phone**.
`devOtp` is returned in the JSON response for **every request in every environment**.

Real-world impact:
- No user can actually receive an OTP via SMS
- Any attacker with network access (proxy, MITM, packet sniffer) reads the OTP directly from the HTTP response
- The entire phone-number-based identity verification is bypassed

**Fix:**
```typescript
// 1. Integrate a real SMS provider (Twilio, MSG91, AWS SNS)
await this.twilioClient.messages.create({
  body: `Your Gixbee OTP is ${otp}. Valid for 5 minutes.`,
  from: process.env.TWILIO_PHONE_NUMBER,
  to: phoneNumber,
});

// 2. Never return devOtp in production
return process.env.NODE_ENV !== 'production'
  ? { message: 'OTP sent', devOtp: otp }
  : { message: 'OTP sent' };
```

---

### 2. Master OTP `123456` bypasses authentication for any account

**`backend/src/auth/auth.service.ts` — `verifyOtp()`**

```typescript
async verifyOtp(phoneNumber: string, otp: string) {
  const isMasterOtp = otp === '123456';  // ← hardcoded backdoor

  const storedOtp = await this.redisService.getOtp(`otp:${phoneNumber}`);

  if (!isMasterOtp && (!storedOtp || storedOtp !== otp)) {
    throw new UnauthorizedException('Invalid or expired OTP');
  }
  // If isMasterOtp is true → verification skipped entirely
```

Anyone who knows `123456` can log into **any phone number** — including
existing users' accounts, worker accounts, and admin-level accounts.
There is no rate limit, no IP check, no second factor. This is a full
authentication bypass.

**Fix:** Remove unconditionally. If needed for automated testing:
```typescript
const isMasterOtp = process.env.NODE_ENV === 'test' && otp === process.env.TEST_MASTER_OTP;
```

---

### 3. Admin panel login is `admin` / `admin` — hardcoded in source code

**`backend/src/auth/auth.service.ts` — `adminLogin()`**

```typescript
async adminLogin(username: string, password: string) {
  if (username !== 'admin' || password !== 'admin') {
    throw new UnauthorizedException('Invalid admin credentials');
  }
  // mints a valid JWT with ADMIN role
}
```

The super-admin panel (which manages all users, bookings, workers, and
financials) is accessible with publicly known credentials committed to
source code. Anyone who reads the repository can access the full
admin panel in production.

**Fix:**
```typescript
// Store hashed password in DB or env var — never in source code
const adminUser = await this.usersRepository.findOne({ where: { role: UserRole.ADMIN } });
const isValid = await bcrypt.compare(password, adminUser.passwordHash);
if (!isValid) throw new UnauthorizedException();
```

---

## 🔴 CRITICAL — Architectural Mismatch

---

### 4. Notification architecture is split — Firebase on Flutter, OneSignal on backend

**Flutter — `notification_service.dart`:**
```dart
// Gets Firebase FCM device token
final token = await _messaging.getToken();  // ← FCM token
// Sends to backend via PATCH /auth/fcm-token
await _dio.patch('/auth/fcm-token', data: {'fcmToken': token});
```

**Backend — `notifications.service.ts`:**
```typescript
// sendToUser() uses OneSignal external_id — NOT FCM token
await axios.post('https://onesignal.com/api/v1/notifications', {
  include_aliases: { external_id: [userId] },  // ← OneSignal user ID
  ...
});
```

**Backend — `auth.service.ts`:**
```typescript
// Comment says "stores OneSignal push subscription ID now"
user.fcmToken = token;  // field named fcmToken but used for OneSignal ID
```

The full chain is broken:
- Flutter registers an **FCM token** (e.g. `fVX3...long string`)
- Backend stores it in `user.fcmToken`
- `notificationsService.sendToUser(userId)` sends via **OneSignal external_id**
- OneSignal has never been configured with these users' devices
- **No push notification ever reaches the user**

**Fix — pick one architecture and use it end to end:**

Option A (Firebase Admin SDK — matches Flutter):
```typescript
// Look up FCM token from DB/Redis and use Firebase Admin SDK
const user = await this.usersRepository.findOne({ where: { id: userId } });
await this.messaging.send({
  token: user.fcmToken,  // the actual FCM token
  notification: { title, body },
  data,
});
```

Option B (OneSignal — requires Flutter to use OneSignal SDK too):
```typescript
// Flutter registers OneSignal subscriptionId, not FCM token
// Backend uses OneSignal external_id (user ID)
```

---

### 5. Both OTPs generated at booking creation — Flutter's `markArrived()` flow is architecturally wrong

**`backend/src/bookings/bookings.service.ts` — `createBooking()`:**
```typescript
const arrivalOtp = this.generateOtp();
const completionOtp = this.generateOtp();
const booking = this.bookingsRepository.create({
  ...bookingData,
  arrivalOtp,    // ← generated NOW, at booking creation
  completionOtp, // ← generated NOW, at booking creation
});
```

**Flutter — `arrival_otp_screen.dart`:**
```dart
// Worker taps "I've Arrived" → calls markArrived() believing this generates the OTP
await ref.read(bookingRepositoryProvider).markArrived(widget.bookingId);
// PATCH /bookings/:id/arrive
```

The OTPs exist in the database **from the moment the booking is created**,
not when the worker marks arrival. The Flutter flow assumes `markArrived()`
triggers OTP generation and sends it to the customer — but the backend
already generated both OTPs upfront.

This also means:
- The customer's `arrivalOtp` is already in the `WaitingForWorkerScreen`
  polling response — available immediately after the worker accepts
- The customer sees it before the worker even starts travelling
- There is no security in the OTP timing

**Fix — choose one design:**

Design A (OTP at creation — current backend): Remove `markArrived()` from Flutter. Show the customer's OTP immediately after acceptance. Worker just types what customer says.

Design B (OTP at event — secure): Backend generates `arrivalOtp` only when worker calls `PATCH /arrive`, not at booking creation. OTP is sent to customer only at that moment.

---

## 🟠 WRONG BEHAVIOUR — Functional Failures

---

### 6. All new users created as `OPERATOR` (worker) — no customer role ever assigned

**`backend/src/auth/auth.service.ts`:**
```typescript
user = this.usersRepository.create({
  phoneNumber,
  name: `User ${phoneNumber.slice(-4)}`,
  role: UserRole.OPERATOR,  // ← every new user is a worker
  isVerified: true,
  walletBalance: 100,
});
```

Every new user who signs up is assigned `role: OPERATOR` (worker).
There is no `UserRole.CUSTOMER` being assigned to anyone.

Consequences:
- `user.isWorker` is always `true` for all users
- `_maybeStartWorkerPoll()` starts the job request poll for every user
- Every customer sees incoming job popups
- Worker-only features are accessible to everyone

**Fix:**
```typescript
// Add role selection to the registration flow, or default to CUSTOMER:
role: UserRole.CUSTOMER,  // default to customer — workers register separately via /register-pro
```

---

### 7. `findAllByUser` silently drops multi-status filter

**`backend/src/bookings/bookings.service.ts`:**
```typescript
if (status) {
  const statuses = status.split(',').map(s => s.trim().toUpperCase());
  if (statuses.length === 1) {
    where.status = statuses[0] as BookingStatus;
  }
  // ← if statuses.length > 1, filter is silently ignored — returns ALL bookings
}
```

Calling `GET /bookings/my?status=CANCELLED,REJECTED` returns all
bookings, not just cancelled and rejected ones. Multi-status filtering
is documented/expected but silently broken.

**Fix:**
```typescript
import { In } from 'typeorm';
if (statuses.length > 0) {
  where.status = statuses.length === 1 ? statuses[0] : In(statuses) as any;
}
```

---

### 8. `sendToUser(userId)` receives a userId but needs an FCM token

**`backend/src/bookings/bookings.service.ts`:**
```typescript
await this.notificationsService.sendToUser(bookingData.operator.id, {
  title: 'New Job Request',
  ...
});
```

`sendToUser` receives the operator's **database user ID** (UUID).
If `notificationsService` uses Firebase Admin SDK, it needs the device's
FCM token string — not a UUID. The UUID will cause Firebase to return
`messaging/registration-token-not-registered` for every notification.

**Fix:**
```typescript
// Look up FCM token first, then send
const user = await this.usersRepository.findOne({ where: { id: operatorId } });
if (user?.fcmToken) {
  await this.notificationsService.sendToDevice(user.fcmToken, { title, body, data });
}
```

---

### 9. `main.dart` — Supabase is fully removed but OTP calls `POST /auth/verify-otp`

The backend now handles OTP natively (no Supabase). Removing Supabase
from Flutter is correct. However `main.dart` comments say `// Removed Supabase dependency`
with no replacement for session management. The JWT from
`/auth/verify-otp` is stored in `flutter_secure_storage`, which is
correct. But `authStateProvider` depends on `hasToken()` — if the JWT
expires, there is no silent refresh mechanism. The user sees a 401 and is
logged out (handled by the Dio interceptor), but there is no token refresh
endpoint on the backend either.

**Gap:** No JWT refresh flow. Long-term sessions will silently fail after
token expiry.

---

## 🟡 MISSING — Features with No Implementation

---

### 10. Payment flow: wallet deducted from worker, never from customer

**`bookings.service.ts` — `acceptBooking()`:**
```typescript
// Deduct platform fee from worker wallet
await this.walletsService.deductBookingFee(workerId);
```

When a booking is accepted, the **worker** pays a platform fee.
The **customer's wallet is never charged** for the service. There is no
`deductServiceAmount(customerId, amount)` call anywhere in the booking
lifecycle. Customers can book unlimited services for free.

---

### 11. GPS strike logic never triggers for `IN_PROGRESS` or `ACTIVE` bookings in real time

The `tenMinuteGpsCheck` Bull job checks worker location at 10 minutes.
But there is no continuous location monitoring — one check at 10 minutes,
then nothing. A worker can accept a job and never move. After 10 minutes
they get 1 strike. They then have no further checks until the job is
manually cancelled or completed. 3 strikes require 3 separate 10-minute
intervals (30 minutes) to auto-cancel a fraudulent booking.

---

### 12. `walletBalance: 100` free credits given to every new user

```typescript
walletBalance: 100, // Give new users Rs. 100 starting balance
```

Every new account gets ₹100. With phone number verification broken
(issue #1), anyone can create unlimited phone number accounts and
collect ₹100 each. This is a financial exploit.

---

## Priority fix order

| # | Severity | Issue | Effort |
|---|---|---|---|
| 1 | 🔴 | SMS never sent — OTP in API response | Medium (integrate Twilio) |
| 2 | 🔴 | Master OTP `123456` backdoor | 1 min (delete 2 lines) |
| 3 | 🔴 | Admin login `admin/admin` | Low (env var + bcrypt) |
| 4 | 🔴 | Notification split: Firebase Flutter vs OneSignal backend | Medium |
| 5 | 🔴 | OTP timing mismatch — Flutter markArrived() vs backend upfront | Medium |
| 6 | 🟠 | All users created as OPERATOR — no customer role | Low |
| 7 | 🟠 | Multi-status filter silently dropped | 5 min |
| 8 | 🟠 | sendToUser(userId) but Firebase needs FCM token | Low |
| 9 | 🟠 | No JWT refresh — long sessions silently fail | Medium |
| 10 | 🟡 | Customer wallet never charged for service | High |
| 11 | 🟡 | GPS strike only fires once at 10min | High |
| 12 | 🟡 | Free ₹100 exploitable without real OTP | Low (fix after #1) |
