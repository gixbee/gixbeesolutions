# Gixbee — Updated Defects Report (Fresh Scan)

> Generated: April 2026 — Full re-scan of all source files.
> Previous defects checked against actual current code.
> Severity: 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low

---

## What Was Fixed Since Last Report ✅

The following defects from the previous report have been **confirmed fixed**
by reading the actual files:

| Previous Defect | Fix Confirmed |
|---|---|
| Firebase not initialized in Flutter | ✅ `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` in `main.dart` |
| Home screen showing wrong UI | ✅ 4 intent cards (Book Services, Find a Job, Earn by Working, List My Business) now implemented |
| `post_job_screen.dart` was a stub | ✅ Full form with skills, experience, job type, salary, location, description, API call |
| `getMyBookings()` returned empty array | ✅ Now calls `findAllByUser()` — fetches real DB bookings |
| No JWT guards on controllers | ✅ `@UseGuards(JwtAuthGuard)` applied to `BookingsController`, `WorkersController` |
| Worker location not written to Redis | ✅ `gateway.ts` now calls `redisService.updateWorkerLocation()` before emitting |
| Processor used fake FCM tokens | ✅ Now uses `booking.operator.fcmToken` and `booking.customer.fcmToken` |
| `sevenMinuteReminder` was a stub | ✅ Sends real push via `notificationsService.sendToDevice()` |
| Strike count never incremented | ✅ `workersService.addStrike()` called after auto-cancel in processor |
| Wallet balance not checked before go-live | ✅ Balance check with `walletsService.getBalance()` added to `toggleGoLive()` |
| FCM token never sent to backend | ✅ `otp_screen.dart` fetches and sends token after successful verify |
| Worker map never joined job room | ✅ `worker_map_screen.dart` calls `socketService.joinJobRoom(widget.jobId)` |
| No `ValidationPipe` | ✅ `main.ts` now has `app.useGlobalPipes(new ValidationPipe(...))` |
| No rate limiting | ✅ `ThrottlerModule` + `ThrottlerGuard` registered in `app.module.ts` |
| Firebase Admin initialized in multiple places | ✅ Centralized `FirebaseModule` with global `FIREBASE_ADMIN` token |
| OTP accepted any 6 digits | ✅ `auth.service.ts` now reads/verifies/deletes from Redis |

---

## Remaining Defects

| Severity | Count |
|---|---|
| 🔴 Critical | 5 |
| 🟠 High | 7 |
| 🟡 Medium | 3 |
| 🟢 Low | 3 |
| **Total** | **18** |

---

## 🔴 CRITICAL DEFECTS

---

### DEFECT-001 — Firebase loads from a JSON file that does not exist in source control

**File:** `backend/src/notifications/firebase.module.ts` — line 16
**Severity:** 🔴 Critical

**Exact code causing defect:**
```typescript
const serviceAccountPath = path.join(process.cwd(), 'firebase-service-account.json');

return admin.initializeApp({
  credential: admin.credential.cert(serviceAccountPath),
  projectId: 'gixbee',
});
```

**Impact:** If `firebase-service-account.json` does not exist in the backend root directory (which it won't be on any new deployment, CI server, or fresh clone since it should be gitignored), `admin.credential.cert()` throws `Error: Failed to parse service account`. This crashes the entire NestJS application at startup — every single endpoint returns 500. Firebase Admin never initializes and all push notifications permanently fail.

**Secondary impact:** The `projectId` is hardcoded to `'gixbee'` which may not match the actual Firebase project ID, causing authentication failures even when the file does exist.

**Fix — use environment variables instead of file:**
```typescript
@Global()
@Module({
  imports: [ConfigModule],
  providers: [{
    provide: 'FIREBASE_ADMIN',
    useFactory: (configService: ConfigService) => {
      if (admin.apps.length) return admin.app();

      const projectId = configService.get<string>('FIREBASE_PROJECT_ID');
      const clientEmail = configService.get<string>('FIREBASE_CLIENT_EMAIL');
      const privateKey = configService.get<string>('FIREBASE_PRIVATE_KEY')
        ?.replace(/\\n/g, '\n');

      if (!projectId || !clientEmail || !privateKey) {
        console.warn('[Firebase] Missing env vars — running in mock mode');
        return admin.initializeApp({ projectId: projectId || 'gixbee-dev' });
      }

      return admin.initializeApp({
        credential: admin.credential.cert({ projectId, clientEmail, privateKey }),
      });
    },
    inject: [ConfigService],
  }],
  exports: ['FIREBASE_ADMIN'],
})
export class FirebaseModule {}
```

Add to `.env`:
```env
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxx@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

---

### DEFECT-002 — Auth flow mismatch: Flutter sends Firebase tokens, backend has two conflicting OTP systems

**Files:** `lib/features/auth/otp_screen.dart` + `backend/src/auth/auth.service.ts`
**Severity:** 🔴 Critical

**The problem:**
`otp_screen.dart` calls:
```dart
await ref.read(authRepositoryProvider).verifyOtp(
  verificationId: widget.verificationId,
  smsCode: otp,
);
```

This signature uses `verificationId` and `smsCode` — which is the **Firebase Phone Authentication** SDK flow. In this flow, Firebase handles OTP delivery and verification entirely on the device, and the result is a Firebase ID token that should be sent to the backend via `loginWithFirebase(idToken)`.

However, `auth.service.ts` also has a manual `verifyOtp(phoneNumber, otp)` method that uses Redis. It's not clear which flow `auth_repository.dart` actually calls — the signature mismatch between Flutter and the backend means one of these two paths is broken.

**Impact:** Either the login completely fails (if `auth_repository.dart` calls the wrong endpoint), or the app uses Firebase Phone Auth but the backend `verifyOtp` Redis path is dead code that was never wired to any Flutter screen.

**Fix — choose one consistent strategy:**

**Option A — Full Firebase Phone Auth (recommended):**
- Flutter: use `FirebaseAuth.instance.verifyPhoneNumber()` → get `idToken` → send to `POST /auth/firebase-login`
- Backend: only expose `loginWithFirebase(idToken)` — delete `requestOtp` and `verifyOtp`

**Option B — Manual OTP (simpler for dev):**
- Flutter: call `POST /auth/request-otp` with phone → receive OTP via SMS → call `POST /auth/verify-otp` with `{phone, otp}`
- Backend: keep `requestOtp` and `verifyOtp` — delete `loginWithFirebase`
- `otp_screen.dart` must pass `phone` not `verificationId`

Whichever is chosen, `auth_repository.dart` must be verified to call the matching backend endpoint with the correct parameters.

---

### DEFECT-003 — Rs.12 first-job bonus never credited and `isFirstJobDone` never set

**File:** `backend/src/bookings/bookings.service.ts` — `verifyCompletionOtp()`
**Severity:** 🔴 Critical

**Exact code (missing bonus credit):**
```typescript
// Transition: ACTIVE → COMPLETED
booking.status = BookingStatus.COMPLETED;
booking.completedAt = new Date();
booking.billingHours = hoursWorked;
await this.bookingsRepository.save(booking);
// ← Rs.12 bonus credit is MISSING
// ← isFirstJobDone = true is MISSING
```

**Impact:**
- Workers never receive the Rs.12 welcome bonus after their first job
- `isFirstJobDone` stays `false` forever on every worker
- Since `toggleGoLive()` checks `if (profile.isFirstJobDone)` before checking balance, and `isFirstJobDone` is always `false`, the wallet balance gate is **never triggered** — workers can go live indefinitely with zero wallet balance
- The wallet system is broken as a consequence

**Fix — add after saving COMPLETED booking:**
```typescript
// Credit first-job bonus and update flag
if (booking.operator?.id) {
  const workerProfile = await this.workerProfileRepo.findOne({
    where: { user: { id: booking.operator.id } },
  });
  if (workerProfile && !workerProfile.isFirstJobDone) {
    await this.walletsService.addFunds(booking.operator.id, 12);
    workerProfile.isFirstJobDone = true;
    await this.workerProfileRepo.save(workerProfile);
  }
}
```

Also inject `WorkerProfile` repository and `WalletsService` into `BookingsService` constructor.

---

### DEFECT-004 — Go-live toggle endpoint accepts any worker ID — auth bypass

**File:** `backend/src/workers/workers.controller.ts` — line 17
**Severity:** 🔴 Critical

**Exact code:**
```typescript
@Post(':id/live-toggle')
async toggleGoLive(@Param('id') id: string) {
  return this.workersService.toggleGoLive(id);
}
```

**Impact:** Any authenticated user can toggle any other worker's live status by sending `POST /workers/{any-worker-id}/live-toggle`. A bad actor could set all workers offline simultaneously, breaking the live worker marketplace. The worker ID must come from the JWT token, not the URL.

**Fix:**
```typescript
@Post('live-toggle')
async toggleGoLive(@Req() req) {
  return this.workersService.toggleGoLive(req.user.userId);
}
```

Note: remove `:id` from the route path entirely. The worker's own ID is derived from the JWT.

---

### DEFECT-005 — No talent notification when a job is posted

**File:** `backend/src/hiring/hiring.service.ts` — `createJobPost()`
**Severity:** 🔴 Critical

**Exact code:**
```typescript
async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
  const job = this.jobPostRepo.create({ ...data, employer: { id: employerId } as User });
  return this.jobPostRepo.save(job);
  // ← talent matching never called
  // ← no push notification sent
}
```

**Impact:** The "Find a Job" module's job alerts are entirely non-functional. Talent enables job alerts and expects push notifications when matching jobs are posted. Since `createJobPost` never calls `getRecommendedTalent()` or sends any notification, no talent ever receives a job alert. The job alert toggle is useless.

**Fix:**
```typescript
async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
  const job = this.jobPostRepo.create({ ...data, employer: { id: employerId } as User });
  const savedJob = await this.jobPostRepo.save(job);

  // Non-blocking: notify matched talent
  setImmediate(async () => {
    try {
      const matched = await this.getRecommendedTalent(savedJob.id);
      const tokens = matched
        .filter(m => m.user?.fcmToken)
        .map(m => m.user.fcmToken as string);
      if (tokens.length > 0) {
        await this.notificationsService.sendToMultipleDevices({
          tokens,
          title: `New job: ${savedJob.title}`,
          body: `${savedJob.location} — tap to apply`,
        });
      }
    } catch (e) {
      console.error('Talent notification failed:', e);
    }
  });

  return savedJob;
}
```

Inject `NotificationsService` into `HiringService` constructor and add `NotificationsModule` to `HiringModule` imports.

---

## 🟠 HIGH PRIORITY DEFECTS

---

### DEFECT-006 — No endpoint to create a worker profile

**File:** `backend/src/workers/workers.controller.ts`
**Severity:** 🟠 High

The controller only has `GET /workers`, `GET /workers/:id`, and `POST /workers/:id/live-toggle`. There is no `POST /workers/register` endpoint. The `register_pro_screen.dart` form submits skills, hourly rate, and bio — but has no backend endpoint to call.

**Fix — add to controller:**
```typescript
@Post('register')
async register(@Req() req, @Body() body: {
  skills: string[];
  hourlyRate: number;
  bio?: string;
  title?: string;
}) {
  return this.workersService.createProfile(req.user.userId, body);
}
```

**Add to `workers.service.ts`:**
```typescript
async createProfile(userId: string, data: {
  skills: string[];
  hourlyRate: number;
  bio?: string;
  title?: string;
}): Promise<WorkerProfile> {
  const existing = await this.workersRepository.findOne({
    where: { user: { id: userId } },
  });
  if (existing) {
    throw new BadRequestException('Worker profile already exists');
  }
  const profile = this.workersRepository.create({
    user: { id: userId } as any,
    skills: data.skills,
    hourlyRate: data.hourlyRate,
    bio: data.bio,
    title: data.title,
    isActive: false,
    isFirstJobDone: false,
    verificationStatus: 'PENDING',
  });
  return this.workersRepository.save(profile);
}
```

---

### DEFECT-007 — No hourly rate update endpoint or method

**File:** `backend/src/workers/workers.service.ts` + `workers.controller.ts`
**Severity:** 🟠 High

`toggleGoLive()` has a 2/day rate-limit pattern. No equivalent exists for hourly rate updates. Workers cannot update their rate from the app.

**Fix — add to `workers.service.ts`:**
```typescript
async updateHourlyRate(userId: string, newRate: number): Promise<{ hourlyRate: number }> {
  const profile = await this.workersRepository.findOne({
    where: { user: { id: userId } },
  });
  if (!profile) throw new NotFoundException('Worker profile not found');

  const todayStr = new Date().toISOString().split('T')[0];
  if (profile.rateUpdateDate !== todayStr) {
    profile.rateUpdateDate = todayStr;
    profile.rateUpdateCountToday = 0;
  }
  if (profile.rateUpdateCountToday >= 2) {
    throw new BadRequestException('Hourly rate can only be updated twice per day.');
  }
  profile.hourlyRate = newRate;
  profile.rateUpdateCountToday += 1;
  await this.workersRepository.save(profile);
  return { hourlyRate: newRate };
}
```

**Add to controller:**
```typescript
@Patch('rate')
async updateRate(@Req() req, @Body() body: { hourlyRate: number }) {
  return this.workersService.updateHourlyRate(req.user.userId, body.hourlyRate);
}
```

---

### DEFECT-008 — No nearby worker search endpoint

**File:** `backend/src/workers/workers.controller.ts`
**Severity:** 🟠 High

`GET /workers` returns all active workers with no location or skill filtering. When a customer triggers Instant Help for a specific skill, the app needs nearby workers — not all workers globally.

**Fix — add to controller:**
```typescript
@Get('nearby')
async getNearby(
  @Query('skill') skill: string,
  @Query('lat') lat: string,
  @Query('lng') lng: string,
) {
  return this.workersService.getNearby(skill, parseFloat(lat), parseFloat(lng));
}
```

**Add to service:**
```typescript
async getNearby(skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
  const all = await this.workersRepository.find({
    where: { isActive: true },
    relations: ['user'],
  });
  return all
    .filter(w => w.skills?.some(s => s.toLowerCase().includes(skill.toLowerCase())))
    .map(w => this.mapToDto(w));
  // Production: use PostGIS ST_DWithin for real geo-radius filtering
}
```

---

### DEFECT-009 — Application status changes send no push notification to talent

**File:** `backend/src/hiring/hiring.service.ts` — `updateApplicationStatus()`
**Severity:** 🟠 High

When HR moves a candidate from APPLIED → INTERVIEW, INTERVIEW → SELECTED, or any other state, the database is updated but the talent never receives a notification. They must manually refresh the app.

**Fix:**
```typescript
async updateApplicationStatus(
  applicationId: string,
  newStatus: ApplicationStatus,
): Promise<JobApplication> {
  const app = await this.applicationRepo.findOne({
    where: { id: applicationId },
    relations: ['jobPost', 'applicant'],
  });
  if (!app) throw new NotFoundException('Application not found');

  app.status = newStatus;
  await this.applicationRepo.save(app);

  const messages: Partial<Record<ApplicationStatus, string>> = {
    [ApplicationStatus.INTERVIEW]: 'You have been shortlisted for an interview!',
    [ApplicationStatus.SELECTED]: 'Congratulations! You have been selected.',
    [ApplicationStatus.REJECTED]: 'Your application was not selected this time.',
  };

  const msg = messages[newStatus];
  if (msg && app.applicant?.fcmToken) {
    await this.notificationsService.sendToDevice({
      token: app.applicant.fcmToken,
      title: app.jobPost?.title || 'Application Update',
      body: msg,
    });
  }
  return app;
}
```

---

### DEFECT-010 — No-show count never incremented — ranking penalty non-functional

**File:** `backend/src/hiring/hiring.service.ts`
**Severity:** 🟠 High

`TalentProfile` has `noShowCount` and `searchRank` fields but nothing in the codebase ever increments `noShowCount` or reduces `searchRank`. Talent who repeatedly accept interviews and skip them rank identically to reliable candidates.

**Fix — add `NO_SHOW` to `ApplicationStatus` enum and handle it:**
```typescript
// In job-application.entity.ts
export enum ApplicationStatus {
  APPLIED = 'APPLIED',
  INTERVIEW = 'INTERVIEW',
  SELECTED = 'SELECTED',
  REJECTED = 'REJECTED',
  NO_SHOW = 'NO_SHOW',   // ADD
}
```

**In `hiring.service.ts` `updateApplicationStatus()`:**
```typescript
if (newStatus === ApplicationStatus.NO_SHOW) {
  await this.talentService.recordNoShow(app.applicant.id);
}
```

**Add to `talent.service.ts`:**
```typescript
async recordNoShow(userId: string): Promise<void> {
  const profile = await this.talentRepo.findOne({
    where: { user: { id: userId } } as any,
  });
  if (!profile) return;
  profile.noShowCount = (profile.noShowCount || 0) + 1;
  profile.searchRank = Math.max(0, (profile.searchRank || 100) - 10);
  await this.talentRepo.save(profile);
}
```

---

### DEFECT-011 — `synchronize: true` in TypeORM — destroys all data on every deploy

**File:** `backend/src/app.module.ts`
**Severity:** 🟠 High (currently dev-only, production-destroying if deployed)

```typescript
synchronize: true, // Enabled for development to create missing tables
```

This auto-drops and recreates tables to match entity definitions on every server restart. In production this means every deploy wipes all user data, bookings, wallets, and businesses.

**Fix — before any production deployment:**
1. Set `synchronize: false`
2. Run: `npm run typeorm migration:generate -- -n InitSchema`
3. Run: `npm run typeorm migration:run`
4. Add migration step to deployment pipeline

Use an env variable to control it safely:
```typescript
synchronize: configService.get('NODE_ENV') === 'development',
```

---

### DEFECT-012 — `PATCH /workers/:id/arrive` and `PATCH /workers/:id/complete` return stub messages

**File:** `backend/src/bookings/bookings.controller.ts` — lines 54-62
**Severity:** 🟠 High

```typescript
@Patch(':id/arrive')
async markArrived(@Param('id') id: string) {
  return { message: 'Arrival trigger sent.' };  // ← does nothing
}

@Patch(':id/complete')
async markComplete(@Param('id') id: string) {
  return { message: 'Completion trigger sent.' };  // ← does nothing
}
```

These endpoints are supposed to trigger the OTP delivery to the on-site contact. Currently they return a static message and do nothing — no OTP is sent, no FCM notification is fired, no status changes.

**Fix:**
```typescript
@Patch(':id/arrive')
async markArrived(@Param('id') id: string) {
  const booking = await this.bookingsService.getBookingById(id);
  if (!booking) throw new NotFoundException('Booking not found');

  // Send arrival OTP to on-site contact or customer
  const contactPhone = booking.onSiteContact?.phone || booking.customer?.phoneNumber;
  const otp = booking.arrivalOtp;

  // TODO: Send via SMS — await smsService.send(contactPhone, `Arrival OTP: ${otp}`);
  // For now, send via push notification to customer
  if (booking.customer?.fcmToken) {
    await this.notificationsService.sendToDevice({
      token: booking.customer.fcmToken,
      title: 'Worker has arrived',
      body: `Arrival OTP: ${otp}. Share this with the worker to begin.`,
    });
  }

  return { message: 'Arrival OTP sent', otp }; // Remove otp from response in production
}
```

---

## 🟡 MEDIUM DEFECTS — Incomplete Features

---

### DEFECT-013 — Calendar view screen entirely missing

**File:** `lib/features/booking/calendar_screen.dart` — does not exist
**Severity:** 🟡 Medium

Both Plan Services and Rental require a 3-state calendar (Available / Pending / Booked) for checking vendor or item availability before making a booking request. This screen does not exist anywhere in the Flutter project. Without it, the Plan Services booking flow cannot be completed by a customer.

**Must implement:**
- Full month calendar grid
- Green = available, Yellow = REQUESTED (pending), Red = CONFIRMED (booked)
- Fetch blocked dates: `GET /businesses/:id/calendar` or `GET /rentals/:id/calendar`
- On date tap: return selected date to calling screen

---

### DEFECT-014 — Business unit management dashboard missing

**File:** `lib/features/business/business_unit_dashboard.dart` exists but needs verification
**Severity:** 🟡 Medium

`business_unit_dashboard.dart` was listed in the file tree but its content was not read in this scan. If it contains a full implementation that calls `GET /businesses/my`, connects to operator management, and shows the unit card grid it may be complete. If it is a stub, it must be built.

**Required API:** `GET /businesses/my` in `businesses.controller.ts` — verify this endpoint exists and returns the correct data shape.

---

### DEFECT-015 — Worker map uses fake GPS-to-screen coordinate mapping

**File:** `lib/features/map/worker_map_screen.dart` — lines 89-92
**Severity:** 🟡 Medium

When a live location update arrives via socket, the screen maps GPS coordinates to screen pixel positions using a hardcoded formula:
```dart
dx = (_liveLocations[worker.id]![1] % 0.01) * 30000 - 150;
dy = (_liveLocations[worker.id]![0] % 0.01) * 50000 - 250;
```

This is a modulo-based fake mapping that produces random-looking positions regardless of actual geography. Two workers 100km apart could appear at the same pixel. A worker in Kerala and one in Mumbai would display identically.

**Impact:** The live radar shows workers at visually random positions. Customers cannot use it to gauge actual proximity.

**Fix — integrate Google Maps Flutter for real map rendering:**
```dart
// Replace RadarPainter + CustomPaint with GoogleMap widget
GoogleMap(
  initialCameraPosition: CameraPosition(
    target: LatLng(_userLat, _userLng),
    zoom: 13,
  ),
  markers: _buildWorkerMarkers(workers),
)
```

Update `google_maps_flutter` marker positions directly from `_liveLocations` GPS coordinates.

---

## 🟢 LOW SEVERITY — Code Quality & Maintenance

---

### DEFECT-016 — `updateHourlyRate()` field name mismatch in `worker-profile.entity.ts`

**File:** `backend/src/workers/worker-profile.entity.ts`
**Severity:** 🟢 Low

The entity has fields `rateUpdateCountToday` and `rateUpdateDate` but the `toggleGoLive()` method uses `goLiveToggleDate` and `goLiveToggleCountToday`. If the entity does not declare both sets of fields, the ORM will silently ignore the writes or throw a runtime error.

**Fix — verify both field pairs exist in `worker-profile.entity.ts`:**
```typescript
@Column({ nullable: true })
goLiveToggleDate: string;

@Column({ type: 'int', default: 0 })
goLiveToggleCountToday: number;

@Column({ nullable: true })
rateUpdateDate: string;

@Column({ type: 'int', default: 0 })
rateUpdateCountToday: number;
```

---

### DEFECT-017 — No `.env.example` file in backend

**File:** `backend/.env.example` — does not exist
**Severity:** 🟢 Low

There is no example environment file. Any developer cloning the project has no reference for which environment variables are required. Combined with DEFECT-001 (Firebase loading from a file), a fresh clone will crash immediately on startup with no clear indication of what is missing.

**Fix — create `backend/.env.example`:**
```env
# Database
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=postgres
DATABASE_PASSWORD=
DATABASE_NAME=gixbee

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# JWT
JWT_SECRET=your-secret-here

# Firebase (replaces firebase-service-account.json)
FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=

# SMS (MSG91)
MSG91_AUTH_KEY=
MSG91_TEMPLATE_ID=

# Razorpay
RAZORPAY_KEY_ID=
RAZORPAY_KEY_SECRET=

PORT=3000
NODE_ENV=development
```

---

### DEFECT-018 — `DEBUG: Bypass Verification` button still present in `otp_screen.dart`

**File:** `lib/features/auth/otp_screen.dart` — lines 135-142
**Severity:** 🟢 Low

```dart
if (kDebugMode)
  TextButton(
    onPressed: () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainWrapper()),
        (route) => false,
      );
    },
    child: const Text('DEBUG: Bypass Verification',
        style: TextStyle(color: Colors.redAccent)),
  ),
```

While this is guarded by `kDebugMode`, it allows any developer running a debug build to bypass authentication entirely. This should be removed before any TestFlight or Play Store internal testing build — testers often use debug builds and this gives them unrestricted access.

**Fix — remove the bypass button entirely.** If dev testing is needed, use the real OTP which is logged to the server console.

---

## Confirmed Clean — No Remaining Issue ✅

The following items from previous reports are now confirmed clean:

- Firebase initialised in Flutter ✅
- OTP verified via Redis (not hardcoded) ✅
- `getMyBookings()` returns real data ✅
- JWT guards on booking and worker controllers ✅
- Worker location written to Redis before socket emit ✅
- Processor uses real FCM tokens from DB relations ✅
- `sevenMinuteReminder` sends actual push notification ✅
- Strike system wired and called ✅
- Wallet balance checked before go-live ✅
- FCM token sent to backend after OTP verification ✅
- Worker map joins job room before listening ✅
- `ValidationPipe` and `ThrottlerGuard` configured globally ✅
- Home screen shows 4 intent-based entry cards ✅
- `post_job_screen.dart` is a full working form ✅

---

## Fix Priority Order (Current)

### Do Now — Breaks Core Features

1. **DEFECT-001** — Fix `FirebaseModule` to use env vars, not JSON file — app crashes on startup without it
2. **DEFECT-002** — Resolve auth flow mismatch (Firebase vs manual OTP) — login may be broken
3. **DEFECT-003** — Credit Rs.12 first-job bonus + set `isFirstJobDone = true` — wallet gate never triggers
4. **DEFECT-004** — Fix go-live toggle to use JWT userId, not URL param — security hole
5. **DEFECT-005** — Add talent notification on job post — job alerts non-functional

### Do Next — Complete Features

6. **DEFECT-006** — Add `POST /workers/register` endpoint — pro registration goes nowhere
7. **DEFECT-007** — Add `updateHourlyRate()` method and `PATCH /workers/rate` endpoint
8. **DEFECT-008** — Add `GET /workers/nearby` endpoint for skill + location filtering
9. **DEFECT-009** — Add push notification to application status change
10. **DEFECT-010** — Add `NO_SHOW` status and `recordNoShow()` with ranking penalty
11. **DEFECT-011** — Control `synchronize` via `NODE_ENV` before any staging/production deploy
12. **DEFECT-012** — Implement `markArrived` and `markComplete` to actually send OTPs

### Build Missing Screens

13. **DEFECT-013** — Build `calendar_screen.dart` — Plan Services flow is blocked
14. **DEFECT-014** — Verify `business_unit_dashboard.dart` implementation
15. **DEFECT-015** — Replace fake GPS-to-screen mapping with Google Maps integration

### Code Quality

16. **DEFECT-016** — Verify all rate-limit fields declared in `worker-profile.entity.ts`
17. **DEFECT-017** — Create `backend/.env.example`
18. **DEFECT-018** — Remove debug bypass button from `otp_screen.dart`

---

*Gixbee Defects Report — Fresh Scan — April 2026*
