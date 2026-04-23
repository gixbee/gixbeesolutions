# Gixbee — Complete Business Logic & Missing Issues

> Deep audit of every backend module, service, and controller.
> Documents what each piece of logic does, what is broken, and exactly what code is missing.

---

## Table of Contents

1. [Auth Module](#1-auth-module)
2. [Wallets Module](#2-wallets-module)
3. [Bookings Module](#3-bookings-module)
4. [Bookings Processor (Background Jobs)](#4-bookings-processor-background-jobs)
5. [Workers Module](#5-workers-module)
6. [Worker Engine (WebSocket Gateway)](#6-worker-engine-websocket-gateway)
7. [Redis Module](#7-redis-module)
8. [Notifications Module (FCM)](#8-notifications-module-fcm)
9. [Businesses Module](#9-businesses-module)
10. [Talent Module](#10-talent-module)
11. [Hiring Module](#11-hiring-module)
12. [Rentals Module](#12-rentals-module)
13. [Cross-Module Wiring Issues](#13-cross-module-wiring-issues)
14. [Entity Field Gaps](#14-entity-field-gaps)
15. [Flutter Data Layer Issues](#15-flutter-data-layer-issues)
16. [Master Issue Checklist](#16-master-issue-checklist)

---

## 1. Auth Module

### What it does
- `requestOtp(phone)` — generates a random 6-digit OTP, saves it to Redis with 5-minute TTL, logs it to console (SMS not yet sent)
- `verifyOtp(phone, otp)` — fetches OTP from Redis, compares, deletes after match, creates user if new, returns JWT
- `getProfile(userId)` — returns user's id, phone, name, email (null), avatar

### What is working
- Redis is injected and wired — `saveOtp`, `getOtp`, `deleteOtp` all called correctly
- New user auto-created on first OTP verify with Rs.100 starting balance
- JWT signed and returned correctly

### Issues

**Issue 1 — SMS not sent**
`requestOtp` only logs the OTP to console. No SMS is delivered to the user's phone.

```typescript
// MISSING: Replace this console.log line
console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);

// WITH: MSG91 integration
const response = await axios.post('https://api.msg91.com/api/v5/otp', {
  authkey: process.env.MSG91_AUTH_KEY,
  mobile: phoneNumber,
  otp,
  template_id: process.env.MSG91_TEMPLATE_ID,
});
```

**Issue 2 — Auth module does not import RedisModule**
`RedisService` is injected into `AuthService` but `RedisModule` is likely not in `AuthModule`'s imports. This will cause a NestJS dependency injection error at runtime.

```typescript
// In auth.module.ts — ADD RedisModule to imports:
@Module({
  imports: [
    TypeOrmModule.forFeature([User]),
    JwtModule.register({ ... }),
    RedisModule,   // <-- ADD THIS
  ],
  ...
})
```

**Issue 3 — No FCM token saved after login**
After OTP verification, the user's device FCM token is never sent to the server. Push notifications will silently fail because `user.fcmToken` is always null.

```typescript
// MISSING endpoint in users.controller.ts:
@UseGuards(JwtAuthGuard)
@Patch('fcm-token')
async updateFcmToken(@Req() req: any, @Body('fcmToken') token: string) {
  return this.usersService.updateFcmToken(req.user.userId, token);
}

// MISSING method in users.service.ts:
async updateFcmToken(userId: string, token: string): Promise<void> {
  await this.usersRepository.update(userId, { fcmToken: token });
}
```

**Issue 4 — No rate limiting on OTP requests**
A bot can call `POST /auth/request-otp` thousands of times per minute.

```typescript
// In app.module.ts — ADD ThrottlerModule:
ThrottlerModule.forRoot([{ ttl: 60000, limit: 5 }])

// In auth.controller.ts — ADD guard:
@UseGuards(ThrottlerGuard)
@Post('request-otp')
async requestOtp(@Body('phoneNumber') phoneNumber: string) { ... }
```

---

## 2. Wallets Module

### What it does
- `getBalance(userId)` — returns wallet balance from User entity
- `deductBookingFee(userId)` — deducts Rs.12, throws if insufficient, creates DEBIT transaction record
- `addFunds(userId, amount)` — adds funds, creates CREDIT transaction record

### What is working
- Balance check and deduction work correctly
- Transaction log is written for every operation

### Issues

**Issue 5 — Wallet deduction fires at wrong point**
`deductBookingFee` is called inside `BookingsService.createBooking()`. This means Rs.12 is taken from the customer the moment they send a request — before a worker accepts.

**Correct flow:**
- Deduct Rs.12 when **worker accepts** the job, not when booking is created
- Refund if job is auto-cancelled (no movement) or worker rejects

```typescript
// In bookings.service.ts — REMOVE deduction from createBooking:
// DELETE: await this.walletsService.deductBookingFee(bookingData.customer.id);

// ADD deduction in a new acceptBooking() method:
async acceptBooking(bookingId: string, workerId: string): Promise<Booking> {
  const booking = await this.bookingsRepository.findOne({
    where: { id: bookingId },
    relations: ['customer'],
  });
  if (!booking) throw new NotFoundException('Booking not found');
  await this.walletsService.deductBookingFee(booking.customer.id);
  booking.status = BookingStatus.ACCEPTED;
  booking.operator = { id: workerId } as User;
  return this.bookingsRepository.save(booking);
}
```

**Issue 6 — No wallet refund on auto-cancel**
When GPS movement check auto-cancels a booking, the Rs.12 is not refunded.

```typescript
// In bookings.processor.ts — ADD after auto-cancel:
await this.walletsService.addFunds(booking.customer.id, 12);
// Log description: 'Refund — worker auto-cancelled (no movement)'
```

**Issue 7 — No wallet top-up endpoint exposed**
`addFunds` exists in service but there is no controller endpoint for it. The Flutter `wallet_screen.dart` has no API to call for Razorpay top-up.

```typescript
// MISSING in wallets.controller.ts:
@UseGuards(JwtAuthGuard)
@Post('add-funds')
async addFunds(@Req() req: any, @Body('amount') amount: number) {
  if (!amount || amount <= 0) throw new BadRequestException('Invalid amount');
  return this.walletsService.addFunds(req.user.userId, amount);
}

@UseGuards(JwtAuthGuard)
@Get('balance')
async getBalance(@Req() req: any) {
  return { balance: await this.walletsService.getBalance(req.user.userId) };
}
```

---

## 3. Bookings Module

### What it does
- `createBooking(data)` — creates booking, generates both OTPs, schedules Bull queue jobs (7-min reminder, 10-min GPS)
- `updateStatus(id, status)` — generic status update
- `verifyArrivalOtp(bookingId, otp)` — validates arrival OTP, transitions ACCEPTED → ACTIVE, records start time
- `verifyCompletionOtp(bookingId, otp)` — validates completion OTP, calculates billing hours (min 1), transitions ACTIVE → COMPLETED

### Issues

**Issue 8 — `getMyBookings` returns empty array**
`GET /bookings/my` always returns `[]`. No DB query implemented.

```typescript
// In bookings.controller.ts — REPLACE:
@UseGuards(JwtAuthGuard)
@Get('my')
async getMyBookings(@Req() req: any) {
  return this.bookingsService.getMyBookings(req.user.userId);
}

// In bookings.service.ts — ADD:
async getMyBookings(userId: string): Promise<Booking[]> {
  return this.bookingsRepository.find({
    where: [
      { customer: { id: userId } },
      { operator: { id: userId } },
    ],
    relations: ['customer', 'operator'],
    order: { createdAt: 'DESC' },
  });
}
```

**Issue 9 — `createBooking` controller doesn't pass customer or worker**
The controller body only accepts `workerId`, `scheduledAt`, `amount`. The JWT user (customer) is never attached.

```typescript
// In bookings.controller.ts — REPLACE create():
@UseGuards(JwtAuthGuard)
@Post()
async create(
  @Req() req: any,
  @Body() body: {
    workerId?: string;
    scheduledAt?: string;
    amount: number;
    type: string;
    skill?: string;
    serviceLocation?: string;
    onSiteContact?: object;
  }
) {
  return this.bookingsService.createBooking({
    customer: { id: req.user.userId } as User,
    operator: body.workerId ? { id: body.workerId } as User : undefined,
    scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : undefined,
    amount: body.amount,
    type: body.type as BookingType,
    skill: body.skill,
    serviceLocation: body.serviceLocation,
    onSiteContact: body.onSiteContact as any,
  });
}
```

**Issue 10 — OTPs generated at booking creation, not at arrival/completion**
Both OTPs are generated when booking is first created and stored in the DB. This means:
- The arrival OTP sits in the DB for potentially hours before it's needed
- Anyone who reads the DB can see the completion OTP before the job even starts

**Correct flow:**
- Generate arrival OTP when worker taps "Arrived" — store in Redis with 10-min TTL
- Generate completion OTP when worker taps "Finish" — store in Redis with 10-min TTL
- Do not store OTPs in the Booking entity at all

```typescript
// In bookings.service.ts — REPLACE verifyArrivalOtp() preamble:
async sendArrivalOtp(bookingId: string): Promise<void> {
  const otp = this.generateOtp();
  await this.redisService.saveOtp(`otp:arrival:${bookingId}`, otp);
  // Send SMS to onSiteContact.phone or customer.phoneNumber
}

async verifyArrivalOtp(bookingId: string, otp: string) {
  const stored = await this.redisService.getOtp(`otp:arrival:${bookingId}`);
  if (!stored || stored !== otp) throw new BadRequestException('Invalid OTP');
  await this.redisService.deleteOtp(`otp:arrival:${bookingId}`);
  // ... transition to ACTIVE
}
```

**Issue 11 — `markArrived` and `markComplete` endpoints are empty**
`PATCH /bookings/:id/arrive` and `PATCH /bookings/:id/complete` return placeholder messages and do nothing.

```typescript
// In bookings.controller.ts — REPLACE:
@UseGuards(JwtAuthGuard)
@Patch(':id/arrive')
async markArrived(@Param('id') id: string) {
  return this.bookingsService.sendArrivalOtp(id);
}

@UseGuards(JwtAuthGuard)
@Patch(':id/complete')
async markComplete(@Param('id') id: string) {
  return this.bookingsService.sendCompletionOtp(id);
}
```

**Issue 12 — No `workerId` passed to GPS check queue job**
The Bull queue job `tenMinuteGpsCheck` only receives `bookingId`. The processor then does a DB lookup for `booking.operator`. But if the operator isn't loaded as a relation this will be `null`.

```typescript
// In bookings.service.ts — FIX queue job payload:
await this.bookingsQueue.add(
  'tenMinuteGpsCheck',
  { bookingId: savedBooking.id, workerId: bookingData.operator?.id },
  { delay: 10 * 60 * 1000 },
);
```

---

## 4. Bookings Processor (Background Jobs)

### What it does
- `sevenMinuteReminder` — supposed to send a reminder notification. Currently stub.
- `tenMinuteGpsCheck` — fetches booking from DB, checks Redis for worker location freshness, auto-cancels if stale, sends FCM to customer and worker

### What is working
- GPS check logic is structurally correct — Redis location age check is right
- Notification calls are made to `NotificationsService.sendToDevice()`

### Issues

**Issue 13 — `sevenMinuteReminder` is still a stub**
The 7-minute reminder processor does nothing. It should send a push to the worker reminding them to start moving.

```typescript
@Process('sevenMinuteReminder')
async handleSevenMinuteReminder(job: Job) {
  const { bookingId } = job.data;
  const booking = await this.bookingsService.getBookingById(bookingId);
  if (!booking || booking.status !== BookingStatus.ACCEPTED) return;

  if (booking.operator?.fcmToken) {
    await this.notificationsService.sendToDevice({
      token: booking.operator.fcmToken,
      title: 'Reminder — Job Starting Soon',
      body: 'Your job starts in 7 minutes. Please start heading to the customer location.',
    });
  }
}
```

**Issue 14 — Processor uses mock FCM tokens**
The GPS check sends notifications using `customer_${id}_token` and `worker_${id}_token` — these are not real FCM tokens. FCM will reject them silently.

```typescript
// WRONG:
token: `customer_${booking.customer.id}_token`

// CORRECT — load real fcmToken from User entity:
const customerUser = await this.usersRepo.findOne({ where: { id: booking.customer.id } });
if (customerUser?.fcmToken) {
  await this.notificationsService.sendToDevice({
    token: customerUser.fcmToken,
    title: '...',
    body: '...',
  });
}
```

**Issue 15 — Strike count not incremented on auto-cancel**
When a worker is auto-cancelled for no movement, `workerProfile.strikeCount` is never incremented. A notification is sent but the strike is never recorded in the database.

```typescript
// In bookings.processor.ts — ADD after auto-cancel:
const workerProfile = await this.workerProfileRepo.findOne({
  where: { user: { id: workerId } },
});
if (workerProfile) {
  workerProfile.strikeCount += 1;
  if (workerProfile.strikeCount >= 3) {
    workerProfile.isActive = false; // Suspend after 3 strikes
  }
  await this.workerProfileRepo.save(workerProfile);
}
```

---

## 5. Workers Module

### What it does
- `getAll()` — returns all active verified workers from DB (DB-backed, no longer hardcoded)
- `getById(id)` — looks up by profile ID or user ID
- `toggleGoLive(id)` — flips `isActive`, enforces 2 toggle/day rate limit, resets counter daily

### What is working
- DB query fully replaces the old hardcoded array
- Rate limit logic is correctly implemented with date comparison
- `mapToDto()` correctly shapes the DB entity to match Flutter's `Worker.fromMap()`

### Issues

**Issue 16 — `goLiveToggleDate` and `goLiveToggleCountToday` not in WorkerProfile entity**
`workers.service.ts` references `profile.goLiveToggleDate` and `profile.goLiveToggleCountToday` but these fields are not in `worker-profile.entity.ts`. TypeORM will not persist them.

```typescript
// In worker-profile.entity.ts — ADD:
@Column({ nullable: true })
goLiveToggleDate: string;  // YYYY-MM-DD string

@Column({ type: 'int', default: 0 })
goLiveToggleCountToday: number;
```

**Issue 17 — `toggleGoLive` endpoint uses URL param id, not authenticated user**
`POST /workers/:id/live-toggle` takes the worker ID from the URL. Any authenticated user could toggle any worker's live status.

```typescript
// In workers.controller.ts — REPLACE:
@UseGuards(JwtAuthGuard)
@Post('live-toggle')
async toggleGoLive(@Req() req: any) {
  return this.workersService.toggleGoLive(req.user.userId);
}
```

**Issue 18 — No location-based worker search**
`GET /workers` returns all active workers globally. For Instant Help, the system needs to find workers within a radius of the service location.

```typescript
// MISSING in workers.service.ts:
async getNearby(lat: number, lng: number, skill: string, radiusKm = 10): Promise<WorkerProfile[]> {
  // Option 1: Use Redis GEO (already scaffolded in redis.service.ts)
  // Option 2: Use PostGIS extension with raw TypeORM query
  // Option 3: Haversine formula in JS (acceptable for small datasets)
  const allActive = await this.workersRepository.find({
    where: { isActive: true },
    relations: ['user'],
  });
  return allActive.filter(w => {
    const skillMatch = (w.skills || []).some(s => s.toLowerCase() === skill.toLowerCase());
    // TODO: filter by distance once lat/lng stored on WorkerProfile
    return skillMatch;
  });
}

// MISSING endpoint in workers.controller.ts:
@Get('nearby')
async getNearby(
  @Query('lat') lat: number,
  @Query('lng') lng: number,
  @Query('skill') skill: string,
) {
  return this.workersService.getNearby(lat, lng, skill);
}
```

**Issue 19 — No skill verification endpoint**
`WorkerProfile.verificationStatus` exists but there is no endpoint for a worker to submit for verification or for admin to approve/reject.

```
MISSING endpoints:
POST /workers/register      — Submit skills for admin verification
PATCH /workers/:id/verify   — Admin approves/rejects (admin-only)
```

**Issue 20 — No-show count never incremented**
`WorkerProfile.noShowCount` exists but nothing ever increments it. No-show penalty for the hiring module is also not implemented.

---

## 6. Worker Engine (WebSocket Gateway)

### What it does
- `handleConnection` — logs connection
- `handleDisconnect` — logs disconnection
- `updateLocation` — if `jobId` provided, emits to job room only; else echoes back to sender only
- `joinJobRoom` — client joins `job_{jobId}` room

### What is working
- Location broadcast scoped to job room (privacy fix applied)
- `joinJobRoom` works correctly

### Issues

**Issue 21 — `@UseGuards(JwtAuthGuard)` on WebSocket gateway does not work**
HTTP guards cannot be applied to WebSocket gateways with `@UseGuards`. The JwtAuthGuard uses `ExecutionContext.switchToHttp()` which returns `null` in a WebSocket context, causing the guard to crash or silently fail.

```typescript
// REMOVE @UseGuards(JwtAuthGuard) from the class decorator

// INSTEAD — verify JWT manually in handleConnection:
import { JwtService } from '@nestjs/jwt';

handleConnection(client: Socket) {
  const token = client.handshake.auth?.token
    || client.handshake.headers?.authorization?.split(' ')[1];
  try {
    const payload = this.jwtService.verify(token, { secret: process.env.JWT_SECRET });
    client.data.userId = payload.sub;
    this.logger.log(`Client connected: ${client.id} (user: ${payload.sub})`);
  } catch {
    this.logger.warn(`Unauthorized WS connection: ${client.id}`);
    client.disconnect(true);
  }
}
```

**Issue 22 — Worker location not saved to Redis from gateway**
When a worker sends `updateLocation`, the gateway broadcasts it to the job room but never calls `redisService.updateWorkerLocation()`. The GPS movement check in the processor then finds no Redis cache and incorrectly auto-cancels the booking.

```typescript
// In worker.gateway.ts — ADD Redis update inside handleLocationUpdate:
// Inject RedisService in constructor first
this.redisService.updateWorkerLocation(data.userId, data.lat, data.lng);
// Also update GEO index for nearby search:
this.redisService.updateWorkerGeoLocation(data.userId, data.lat, data.lng);
```

---

## 7. Redis Module

### What it does
- Connects to Redis on module init, disconnects on destroy
- `saveOtp(key, otp)` — stores with 5-min TTL
- `getOtp(key)` / `deleteOtp(key)` — retrieve and remove
- `updateWorkerLocation(workerId, lat, lng)` — stores JSON with 1-hour TTL
- `getWorkerLocation(workerId)` — retrieves parsed location cache
- `updateWorkerGeoLocation(workerId, lat, lng)` — adds to Redis GEO sorted set

### What is working
- Full Redis client setup with error handling
- OTP methods work correctly — called from `auth.service.ts`
- Location cache methods are correctly defined

### Issues

**Issue 23 — Redis connection failure is silent**
If Redis is unavailable (e.g. not running), the module logs an error but the app continues. OTP verification will then always fail with "Invalid or expired OTP" because `getOtp` returns `null` when Redis is down. Users cannot log in.

No health check or fallback is implemented.

**Issue 24 — `updateWorkerLocation` never called from anywhere**
The method exists and is correct but nothing calls it. The WebSocket gateway needs to call it on every location update (see Issue 22).

---

## 8. Notifications Module (FCM)

### What it does
- `onModuleInit` — initializes Firebase Admin SDK using env vars
- `sendToDevice(payload)` — sends FCM notification to a single device token
- `sendToMultipleDevices(payload)` — sends to multiple tokens via multicast
- `sendToTopic(topic, title, body)` — sends to a FCM topic subscription

### What is working
- Firebase Admin SDK initialization is correct
- Mock mode when env vars are missing
- Both single and multicast send are implemented
- Android and APNS config included

### Issues

**Issue 25 — NotificationsService never called from any business event**
This is the most widespread wiring gap. The service is fully built but nothing calls it. Every status change that should trigger a push notification is silent.

Events that must call `NotificationsService`:

| Event | Where to call | Recipient |
|---|---|---|
| New booking request received | `BookingsService.createBooking` | Vendor / Worker |
| Booking approved by vendor | `BookingsService.updateStatus` | Customer |
| Booking rejected by vendor | `BookingsService.updateStatus` | Customer |
| Worker accepted job | `BookingsService.acceptBooking` | Customer |
| Arrival OTP sent | `BookingsService.sendArrivalOtp` | On-site contact |
| Completion OTP sent | `BookingsService.sendCompletionOtp` | Customer |
| Job auto-cancelled (no movement) | `BookingsProcessor.tenMinuteGpsCheck` | Customer + Worker |
| 7-min reminder | `BookingsProcessor.sevenMinuteReminder` | Worker |
| New job post matching talent | `HiringService.createJobPost` | Matched talent |
| Application status changed | `HiringService.updateApplicationStatus` | Talent |
| Wallet balance low | `WalletsService.deductBookingFee` | Worker |

**Issue 26 — Firebase initialized with `projectId` only in mock mode**
When `clientEmail` or `privateKey` are missing, `admin.initializeApp({ projectId })` is called. This initializes Firebase but FCM `send()` will throw `403 Forbidden` because no credentials are provided. The error is caught and `false` is returned silently.

---

## 9. Businesses Module

### What it does
- `create(ownerId, data)` — creates a new business unit with PENDING status
- `getMyBusinesses(ownerId)` — lists all businesses owned by user
- `getById(id)` — fetches single business with owner relation
- `addOperator(businessId, userId)` — appends userId to `operatorIds[]`
- `addOfflineDay(businessId, dateIsoString)` — appends date to `offlineDays[]`

### Issues

**Issue 27 — `operatorIds` and `offlineDays` not in Business entity**
`businesses.service.ts` references `business.operatorIds` and `business.offlineDays` but these columns are not defined in `business.entity.ts`.

```typescript
// In business.entity.ts — ADD:
@Column('simple-array', { nullable: true })
operatorIds: string[];

@Column('simple-array', { nullable: true })
offlineDays: string[];
```

**Issue 28 — No ownership transfer logic**
The Gixbee architecture requires a 24-hour hold OTP-based ownership transfer. No endpoint or logic exists for this.

```
MISSING:
POST /businesses/:id/transfer-request   — Initiate transfer, OTP sent to both parties
POST /businesses/:id/transfer-confirm   — Both confirm with OTPs, 24-hr hold set
POST /businesses/:id/transfer-finalize  — Cron runs after 24hrs to complete transfer
```

**Issue 29 — No business calendar endpoint**
The frontend booking flow needs to fetch blocked dates for a vendor's business. No calendar endpoint exists.

```
MISSING:
GET /businesses/:id/calendar   — Returns array of booked, pending, available dates
```

**Issue 30 — Operator auth not enforced**
Any authenticated user can call `POST /businesses/:id/operators` to add anyone as an operator. There is no check that the caller is the business owner.

```typescript
// In businesses.controller.ts — ADD owner check:
@UseGuards(JwtAuthGuard)
@Post(':id/operators')
async addOperator(@Param('id') id: string, @Body('userId') userId: string, @Req() req: any) {
  const business = await this.val.getById(id);
  if (business.owner.id !== req.user.userId) {
    throw new ForbiddenException('Only the business owner can add operators');
  }
  return this.val.addOperator(id, userId);
}
```

---

## 10. Talent Module

### What it does
- `getProfile(userId)` — fetches talent profile, auto-creates default if first time
- `updateProfile(userId, data)` — updates any fields on the profile
- `toggleAlerts(userId, enabled)` — sets `jobAlertsEnabled`

### What is working
- Basic CRUD works — profile creation and update are correct
- Controller correctly guards all routes with JWT

### Issues

**Issue 31 — `TalentProfile` entity has no `user` FK properly typed**
`talentRepo.findOne({ where: { user: { id: userId } } as any })` uses `as any` cast. This means TypeScript type safety is bypassed and could fail silently in strict TypeORM configs.

```typescript
// In talent-profile.entity.ts — ensure:
@OneToOne(() => User)
@JoinColumn()
user: User;

// In talent.service.ts — CORRECT query:
const profile = await this.talentRepo.findOne({
  where: { user: { id: userId } },
  relations: ['user'],
});
```

**Issue 32 — No `preferredLocations` or `skills` search query endpoint**
Talent profiles are saved with `preferredLocations` and `skills` but there's no endpoint for employers to search talent by these fields.

```
MISSING:
GET /talent/search?skill=Nurse&location=Kochi  — Employer searches talent pool
```

**Issue 33 — No-show count never incremented**
`TalentProfile.noShowCount` and `searchRank` exist but no logic updates them when a talent accepts an interview and doesn't attend.

```typescript
// MISSING in hiring.service.ts or talent.service.ts:
async recordNoShow(talentId: string): Promise<void> {
  const profile = await this.talentRepo.findOne({ where: { user: { id: talentId } } });
  if (profile) {
    profile.noShowCount += 1;
    // Apply search rank penalty: deduct 5 points per no-show, floor at 0
    profile.searchRank = Math.max(0, profile.searchRank - 5);
    await this.talentRepo.save(profile);
  }
}
```

---

## 11. Hiring Module

### What it does
- `createJobPost(employerId, data)` — creates job post with employer relation
- `getActiveJobs()` — lists all active jobs
- `getJobById(id)` — fetches single job with employer
- `applyForJob(jobId, applicantId, coverLetter)` — creates application, prevents duplicates
- `updateApplicationStatus(applicationId, newStatus)` — moves pipeline state
- `getApplicationsForJob(jobId)` — lists all applicants for a job
- `getRecommendedTalent(jobId)` — scores workers by skill overlap, returns sorted matches

### What is working
- Job post creation, application flow, and pipeline state updates are all functional
- Talent matching algorithm correctly scores by skill overlap
- Duplicate application check prevents applying twice

### Issues

**Issue 34 — `getMyApplications` called in controller but missing from service**
`HiringController` has `GET /hiring/my-applications` which calls `this.hiringService.getMyApplications(req.user.userId)`. This method does not exist in `HiringService`. The app will throw a runtime error.

```typescript
// In hiring.service.ts — ADD:
async getMyApplications(userId: string): Promise<JobApplication[]> {
  return this.applicationRepo.find({
    where: { applicant: { id: userId } },
    relations: ['jobPost', 'jobPost.employer'],
    order: { createdAt: 'DESC' },
  });
}
```

**Issue 35 — Talent not notified when job is posted**
`createJobPost` saves the job but never calls `notifyMatchingTalent`. Job alerts are silently not sent.

```typescript
// In hiring.service.ts — ADD after save:
async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
  const job = this.jobPostRepo.create({ ...data, employer: { id: employerId } as User });
  const saved = await this.jobPostRepo.save(job);
  await this.notifyMatchingTalent(saved);  // ADD THIS
  return saved;
}

private async notifyMatchingTalent(job: JobPost): Promise<void> {
  // Query talent profiles where jobAlertsEnabled=true and skills overlap
  const matched = await this.talentRepo
    .createQueryBuilder('tp')
    .innerJoinAndSelect('tp.user', 'user')
    .where('tp.jobAlertsEnabled = :enabled', { enabled: true })
    .getMany();

  const tokens = matched
    .filter(t => t.user?.fcmToken)
    .map(t => t.user.fcmToken);

  if (tokens.length > 0) {
    await this.notificationsService.sendToMultipleDevices({
      tokens,
      title: `New Job: ${job.title}`,
      body: `A new position matching your profile is available. Apply now.`,
      data: { jobId: job.id, type: 'JOB_ALERT' },
    });
  }
}
```

**Issue 36 — Application status change doesn't notify talent**
When HR moves a candidate from APPLIED to INTERVIEW or SELECTED, the talent receives no push notification.

```typescript
// In hiring.service.ts — ADD after status save:
async updateApplicationStatus(applicationId: string, newStatus: ApplicationStatus) {
  const app = await this.applicationRepo.findOne({
    where: { id: applicationId },
    relations: ['jobPost', 'applicant'],
  });
  app.status = newStatus;
  const saved = await this.applicationRepo.save(app);

  // Notify talent of status change — ADD THIS:
  const fcmToken = app.applicant?.fcmToken;
  if (fcmToken) {
    const messages = {
      [ApplicationStatus.INTERVIEW]: 'Congratulations! You have been selected for an interview.',
      [ApplicationStatus.SELECTED]: 'You have been selected for the role!',
      [ApplicationStatus.REJECTED]: 'Your application was not selected this time.',
    };
    if (messages[newStatus]) {
      await this.notificationsService.sendToDevice({
        token: fcmToken,
        title: `Application Update — ${app.jobPost.title}`,
        body: messages[newStatus],
        data: { applicationId, type: 'APPLICATION_STATUS' },
      });
    }
  }
  return saved;
}
```

---

## 12. Rentals Module

### What it does
- `createItem(ownerId, data)` — registers a rental item (Generator, Mic Set, etc.)
- `getItems()` — lists all available items
- `requestReservation(renterId, itemId, startTime, endTime)` — checks overlap, validates min-hours, calculates price, creates PENDING reservation
- `confirmReservation(reservationId)` — re-validates overlap (race condition safe), transitions to CONFIRMED
- `checkOverlap(itemId, start, end)` — database query for conflicting CONFIRMED/ACTIVE reservations

### What is working
- Overlap detection using TypeORM query builder is correctly implemented
- Minimum hours billing enforced at service level
- Double-confirmation check prevents race conditions

### Issues

**Issue 37 — No location-based item filtering**
`getItems()` returns all available items globally. Flutter's rental flow requires items filtered by the customer's selected service location.

```typescript
// In rentals.service.ts — REPLACE getItems():
async getItems(location?: string, category?: string): Promise<RentalItem[]> {
  const query: any = { isAvailable: true };
  if (location) query.location = location;
  if (category) query.category = category;
  return this.rentalItemRepo.find({ where: query, relations: ['owner'] });
}

// In rentals.controller.ts — UPDATE:
@Get()
async getItems(@Query('location') location?: string, @Query('category') category?: string) {
  return this.rentalsService.getItems(location, category);
}
```

**Issue 38 — No vendor approval step**
The Gixbee rental flow is: Customer sends request → Vendor approves → Customer confirms → Day blocked.

The current implementation skips vendor approval. `requestReservation` goes directly to PENDING and `confirmReservation` moves it to CONFIRMED without any vendor action in between.

```
MISSING:
PATCH /rentals/reservations/:id/approve   — Vendor approves the request
PATCH /rentals/reservations/:id/reject    — Vendor rejects the request
```

**Issue 39 — `RentalItem` entity missing `location` and `category` fields**
`rental-item.entity.ts` needs location and category for filtering.

```typescript
// In rental-item.entity.ts — ADD:
@Column({ nullable: true })
location: string;

@Column({ nullable: true })
category: string;  // 'generator' | 'mic_set' | 'cooler' etc.
```

---

## 13. Cross-Module Wiring Issues

These are issues that span multiple modules and require changes in multiple files.

**Issue 40 — `NotificationsModule` not imported where needed**
`BookingsModule`, `HiringModule`, `WorkersModule` all need to call `NotificationsService` but likely don't import `NotificationsModule`.

```typescript
// Each affected module's .module.ts needs:
imports: [
  ...,
  NotificationsModule,
],
```

**Issue 41 — `RedisModule` not imported where needed**
`AuthModule` and `WorkerEngineModule` both need `RedisService` injected.

```typescript
// In auth.module.ts and worker-engine.module.ts:
imports: [
  ...,
  RedisModule,
],
```

**Issue 42 — No global validation pipe**
No `ValidationPipe` is configured. Any malformed request body goes directly to service methods without type checking.

```typescript
// In main.ts — ADD:
import { ValidationPipe } from '@nestjs/common';
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
  transform: true,
}));
```

**Issue 43 — `JwtAuthGuard` file may not exist**
Controllers import from `'../auth/jwt-auth.guard'` but this file is not listed in the auth directory listing. If it doesn't exist, every guarded endpoint will throw a module-not-found compile error.

```typescript
// CREATE backend/src/auth/jwt-auth.guard.ts:
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
```

---

## 14. Entity Field Gaps

Summary of all fields referenced in services but missing from entities:

| Entity File | Missing Field | Referenced In |
|---|---|---|
| `worker-profile.entity.ts` | `goLiveToggleDate: string` | `workers.service.ts` |
| `worker-profile.entity.ts` | `goLiveToggleCountToday: number` | `workers.service.ts` |
| `worker-profile.entity.ts` | `fcmToken` (via user relation) | `bookings.processor.ts` |
| `business.entity.ts` | `operatorIds: string[]` | `businesses.service.ts` |
| `business.entity.ts` | `offlineDays: string[]` | `businesses.service.ts` |
| `rental-item.entity.ts` | `location: string` | `rentals.service.ts` |
| `rental-item.entity.ts` | `category: string` | `rentals.service.ts` |
| `talent-profile.entity.ts` | `searchRank: number` | Needed for no-show penalty |
| `job-post.entity.ts` | `location: string` | `hiring.service.ts` |
| `job-post.entity.ts` | `requiredSkills: string[]` | `hiring.service.ts` |
| `job-application.entity.ts` | `interviewAccepted: boolean` | No-show tracking |
| `job-application.entity.ts` | `attended: boolean` | No-show tracking |

---

## 15. Flutter Data Layer Issues

**Issue 44 — `booking_repository.dart` missing OTP and confirmation methods**
The Flutter `arrival_otp_screen.dart` and `completion_otp_screen.dart` exist but the repository has no methods to call.

```dart
// MISSING in booking_repository.dart:
Future<void> markArrived(String bookingId) async {
  await _dio.patch('/bookings/$bookingId/arrive');
}

Future<Map<String, dynamic>> verifyArrivalOtp(String bookingId, String otp) async {
  final response = await _dio.post('/bookings/$bookingId/arrival', data: {'otp': otp});
  return response.data;
}

Future<void> markComplete(String bookingId) async {
  await _dio.patch('/bookings/$bookingId/complete');
}

Future<Map<String, dynamic>> verifyCompletionOtp(String bookingId, String otp) async {
  final response = await _dio.post('/bookings/$bookingId/completion', data: {'otp': otp});
  return response.data;
}
```

**Issue 45 — `business_repository.dart` has no real implementation**
File exists but all methods likely call placeholder endpoints that don't match the actual controller routes.

Verify that `POST /businesses` and `GET /businesses/my` are used — these match the controller.

**Issue 46 — No `Booking` model in `lib/models/`**
`booking_repository.dart` returns `List<dynamic>` and `Map<dynamic, dynamic>`. A typed `Booking` model is needed.

```dart
// CREATE lib/models/booking.dart:
class Booking {
  final String id;
  final String status;
  final String? skill;
  final String? serviceLocation;
  final double amount;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? billingHours;

  Booking.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        status = json['status'],
        skill = json['skill'],
        serviceLocation = json['serviceLocation'],
        amount = (json['amount'] as num).toDouble(),
        scheduledAt = json['scheduledAt'] != null
            ? DateTime.parse(json['scheduledAt']) : null,
        startedAt = json['startedAt'] != null
            ? DateTime.parse(json['startedAt']) : null,
        completedAt = json['completedAt'] != null
            ? DateTime.parse(json['completedAt']) : null,
        billingHours = json['billingHours'];
}
```

**Issue 47 — Firebase not initialized in `main.dart`**
`firebase_core`, `firebase_auth`, and `firebase_messaging` are in `pubspec.yaml` but `main.dart` has a comment saying initialization is pending. Push notifications will crash the app on startup.

```dart
// In main.dart — ADD before runApp:
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseMessaging.instance.requestPermission();
  runApp(const ProviderScope(child: GixbeeApp()));
}
```

---

## 16. Master Issue Checklist

### Backend — Critical (will crash or give wrong results)
- [ ] **#8** `getMyBookings` returns empty array — add DB query
- [ ] **#9** `createBooking` doesn't attach customer from JWT — fix controller
- [ ] **#16** `goLiveToggleDate` and `goLiveToggleCountToday` missing from entity
- [ ] **#17** `toggleGoLive` uses URL param instead of JWT user
- [ ] **#21** `@UseGuards(JwtAuthGuard)` on WebSocket gateway crashes — replace with manual JWT check
- [ ] **#22** Worker location not saved to Redis from gateway — GPS check always auto-cancels
- [ ] **#27** `operatorIds` and `offlineDays` missing from Business entity
- [ ] **#34** `getMyApplications` called in controller but missing from HiringService
- [ ] **#43** `jwt-auth.guard.ts` may not exist — create it

### Backend — High Priority (broken features)
- [ ] **#1** SMS not sent — integrate MSG91
- [ ] **#2** AuthModule doesn't import RedisModule — inject will fail
- [ ] **#3** FCM token never saved after login — add endpoint + Flutter call
- [ ] **#5** Wallet deduction at wrong point — move to `acceptBooking`
- [ ] **#6** No refund on auto-cancel
- [ ] **#7** No wallet top-up endpoint
- [ ] **#10** OTPs generated at booking creation — move to arrival/completion trigger
- [ ] **#11** `markArrived` and `markComplete` endpoints are empty
- [ ] **#12** `workerId` missing from queue job payload
- [ ] **#13** `sevenMinuteReminder` is a stub
- [ ] **#14** Mock FCM tokens in processor — use real `user.fcmToken`
- [ ] **#15** Strike count not incremented on auto-cancel
- [ ] **#25** NotificationsService never called from any event — wire to all status changes
- [ ] **#28** No ownership transfer for businesses
- [ ] **#35** Talent not notified when job posted
- [ ] **#36** Application status change doesn't notify talent

### Backend — Medium Priority (incomplete features)
- [ ] **#4** No rate limiting on OTP endpoint
- [ ] **#18** No location-based worker search
- [ ] **#19** No skill verification endpoint
- [ ] **#20** No-show count never incremented
- [ ] **#29** No business calendar endpoint
- [ ] **#30** Operator auth not enforced on business routes
- [ ] **#31** Talent `user` FK uses `as any` cast — fix typing
- [ ] **#32** No talent search endpoint for employers
- [ ] **#33** No-show penalty never applied to search rank
- [ ] **#37** No location filtering on rental items
- [ ] **#38** No vendor approval step in rental flow
- [ ] **#39** Rental item missing `location` and `category` fields
- [ ] **#40** NotificationsModule not imported in affected modules
- [ ] **#41** RedisModule not imported in affected modules
- [ ] **#42** No global ValidationPipe

### Flutter — Critical
- [ ] **#47** Firebase not initialized in `main.dart`
- [ ] **#44** `booking_repository.dart` missing OTP and confirmation methods

### Flutter — High Priority
- [ ] **#46** No `Booking` model — all booking data is untyped `dynamic`
- [ ] **#45** Verify `business_repository.dart` uses correct endpoint paths

### Entity Gaps (all must be added)
- [ ] `worker-profile.entity.ts` — add `goLiveToggleDate`, `goLiveToggleCountToday`
- [ ] `business.entity.ts` — add `operatorIds`, `offlineDays`
- [ ] `rental-item.entity.ts` — add `location`, `category`
- [ ] `talent-profile.entity.ts` — add `searchRank`
- [ ] `job-post.entity.ts` — verify `location`, `requiredSkills` exist
- [ ] `job-application.entity.ts` — add `interviewAccepted`, `attended`

---

*Gixbee Business Logic Audit — April 2026*
*Total issues identified: 47*
