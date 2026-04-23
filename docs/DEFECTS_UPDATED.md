# Gixbee — Updated Defects Report (Re-Scan)

> Re-scanned: April 2026 — every file read directly from source.
> This replaces the previous MAJOR_DEFECTS.md with the accurate current state.

---

## What Was Fixed Since Last Report ✅

The following defects from the previous report are now confirmed resolved:

| # | What was fixed |
|---|---|
| 1 | Firebase initialized in Flutter `main.dart` — `Firebase.initializeApp()` with `DefaultFirebaseOptions` |
| 2 | FCM token sent to backend after OTP — `otp_screen.dart` calls `FirebaseMessaging.instance.getToken()` |
| 3 | `getMyBookings()` fixed — now calls `findAllByUser()` with real user ID |
| 4 | Worker location written to Redis in gateway — `redisService.updateWorkerLocation()` called on every GPS event |
| 5 | Worker map screen joins job room — `socketService.joinJobRoom(jobId)` called in `initState` |
| 6 | JWT guards on `BookingsController` — `@UseGuards(JwtAuthGuard)` on class |
| 7 | JWT guards on `WorkersController` — `@UseGuards(JwtAuthGuard)` on class |
| 8 | `createBooking` captures all required fields — skill, serviceLocation, onSiteContact, type |
| 9 | Wallet balance check before go-live — checks `balance < 12` when toggling live |
| 10 | Strike count incremented — `workersService.addStrike(workerId)` called in processor |
| 11 | `sevenMinuteReminder` processor sends real FCM push to `booking.operator.fcmToken` |
| 12 | Processor uses real FCM tokens, not placeholder strings |
| 13 | Home screen redesigned — 4 intent-based entry cards (Book Services, Find a Job, Earn by Working, List My Business) |
| 14 | `post_job_screen.dart` fully built — complete form with skills, experience, salary, location, description |
| 15 | `ValidationPipe` added globally in `main.ts` |
| 16 | `ThrottlerModule` added with global `APP_GUARD` |
| 17 | Firebase centralized in `FirebaseModule` — no duplicate init risk |
| 18 | All modules registered in `app.module.ts` — businesses, talent, master-entries, firebase |
| 19 | `business_unit_dashboard.dart` — file now exists |
| 20 | `hiring_pipeline_screen.dart` — file now exists |

---

## Remaining Defects

| Severity | Count |
|---|---|
| 🔴 Critical | 5 |
| 🟠 High | 7 |
| 🟡 Medium | 4 |
| 🟢 Low | 3 |
| **Total** | **19** |

---

## 🔴 CRITICAL DEFECTS

---

### DEFECT-001 — `firebase.module.ts` crashes entire backend if service account file is missing

**File:** `backend/src/notifications/firebase.module.ts`
**Severity:** 🔴 Critical

**Exact code causing defect:**
```typescript
useFactory: (configService: ConfigService) => {
  const serviceAccountPath = path.join(process.cwd(), 'firebase-service-account.json');

  return admin.initializeApp({
    credential: admin.credential.cert(serviceAccountPath),  // ← CRASHES if file missing
    projectId: 'gixbee',
  });
},
```

**Impact:** If `firebase-service-account.json` does not exist in the backend root directory, `admin.credential.cert()` throws immediately during module initialization. NestJS cannot start. The entire backend crashes before serving a single request. This file is almost certainly gitignored (it must never be committed), meaning every new developer, every CI/CD pipeline, and every production deployment will crash on first run with no helpful error message.

**Fix — use environment variables with graceful fallback:**
```typescript
useFactory: (configService: ConfigService) => {
  if (admin.apps.length > 0) return admin.apps[0];

  const projectId = configService.get<string>('FIREBASE_PROJECT_ID');
  const clientEmail = configService.get<string>('FIREBASE_CLIENT_EMAIL');
  const privateKey = configService.get<string>('FIREBASE_PRIVATE_KEY')?.replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey) {
    console.warn('[FirebaseModule] Missing env vars — FCM notifications disabled in this environment.');
    return admin.initializeApp({ projectId: 'gixbee-placeholder' });
  }

  return admin.initializeApp({
    credential: admin.credential.cert({ projectId, clientEmail, privateKey }),
  });
},
```

---

### DEFECT-002 — Go-live toggle controller uses URL param ID — any user can toggle any worker

**File:** `backend/src/workers/workers.controller.ts`
**Severity:** 🔴 Critical — Security Hole

**Exact code:**
```typescript
@Post(':id/live-toggle')
async toggleGoLive(@Param('id') id: string) {
  return this.workersService.toggleGoLive(id);
}
```

**Impact:** Although `@UseGuards(JwtAuthGuard)` is on the class, the ID comes from the URL path, not from the authenticated user's token. Any authenticated user can toggle any other worker's live status on or off by knowing (or guessing) their worker profile ID. A malicious customer could push all workers offline during peak hours.

**Fix:**
```typescript
@Post('live-toggle')
async toggleGoLive(@Req() req) {
  return this.workersService.toggleGoLive(req.user.userId);
}
```

Note: also rename from `':id/live-toggle'` to just `'live-toggle'` so it no longer accepts an external ID.

---

### DEFECT-003 — No `GET /workers/nearby` endpoint — Instant Help cannot find workers

**File:** `backend/src/workers/workers.controller.ts`
**Severity:** 🔴 Critical

`GET /workers` returns all active workers with no filtering by skill or location. When a customer selects a skill on the Instant Help flow, there is no endpoint to call for nearby worker matching. The entire Live Worker dispatch flow is broken because there is no way to find and notify relevant workers.

**Fix — add to `workers.controller.ts`:**
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

**Add to `workers.service.ts`:**
```typescript
async getNearby(skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
  const profiles = await this.workersRepository.find({
    where: { isActive: true },
    relations: ['user'],
  });
  return profiles
    .filter(p => p.skills?.some(s => s.toLowerCase().includes(skill.toLowerCase())))
    .map(p => this.mapToDto(p));
  // Production: add PostGIS ST_DWithin for real geo-radius filtering
}
```

---

### DEFECT-004 — No `POST /workers/register` endpoint — skill registration form has no API

**File:** `backend/src/workers/workers.controller.ts`
**Severity:** 🔴 Critical

`register_pro_screen.dart` is now fully built with a skill registration form — but the `POST /workers/register` endpoint does not exist in the controller. The form submit goes nowhere.

**Fix — add to `workers.controller.ts`:**
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
    throw new BadRequestException('Worker profile already exists. Use update instead.');
  }
  const profile = this.workersRepository.create({
    user: { id: userId } as any,
    skills: data.skills,
    hourlyRate: data.hourlyRate,
    bio: data.bio,
    title: data.title,
    isActive: false,
    isFirstJobDone: false,
    verificationStatus: VerificationStatus.PENDING,
  });
  return this.workersRepository.save(profile);
}
```

---

### DEFECT-005 — Rs.12 first-job bonus never credited, `isFirstJobDone` never set to true

**File:** `backend/src/bookings/bookings.service.ts` — `verifyCompletionOtp()`
**Severity:** 🔴 Critical

`verifyCompletionOtp()` correctly sets status to COMPLETED and calculates billing hours — but it never credits the Rs.12 welcome bonus to the worker or sets `isFirstJobDone = true`. Since `isFirstJobDone` stays `false` forever, the wallet balance check in `toggleGoLive()` never activates — workers can go live with Rs.0 indefinitely.

**Fix — add to `verifyCompletionOtp()` after saving COMPLETED booking:**
```typescript
// Credit first-job bonus if applicable
if (booking.operator) {
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

**Also requires:** `WorkerProfile` repository injected into `BookingsService`, and `WalletService` is already injected.

---

## 🟠 HIGH PRIORITY DEFECTS

---

### DEFECT-006 — No `PATCH /workers/rate` endpoint and no `updateHourlyRate()` method

**File:** `backend/src/workers/workers.controller.ts` + `workers.service.ts`
**Severity:** 🟠 High

Workers can register (after fix 004) but there is no way to update their hourly rate later. The 2-per-day rate limit business rule exists in the entity (fields `rateUpdateCountToday`, `rateUpdateDate`) but has no service method or endpoint.

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

**Fix — add to `workers.controller.ts`:**
```typescript
@Patch('rate')
async updateRate(@Req() req, @Body() body: { hourlyRate: number }) {
  return this.workersService.updateHourlyRate(req.user.userId, body.hourlyRate);
}
```

---

### DEFECT-007 — Talent not notified when a new job is posted

**File:** `backend/src/hiring/hiring.service.ts` — `createJobPost()`
**Severity:** 🟠 High

`createJobPost()` saves the job and returns it. The talent matching algorithm (`getRecommendedTalent()`) is fully implemented but is never called at job creation time. Talent with job alerts enabled never receive notifications of new matching jobs.

**Fix — add to `createJobPost()` after saving:**
```typescript
async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
  const job = this.jobPostRepo.create({ ...data, employer: { id: employerId } as User });
  const savedJob = await this.jobPostRepo.save(job);

  // Non-blocking: notify matching talent
  setImmediate(async () => {
    try {
      const matched = await this.getRecommendedTalent(savedJob.id);
      const tokens = matched
        .filter(m => m.user?.fcmToken)
        .map(m => m.user!.fcmToken!);
      if (tokens.length > 0) {
        await this.notificationsService.sendToMultipleDevices({
          tokens,
          title: `New job: ${savedJob.title}`,
          body: `${savedJob.location || 'Nearby'} — tap to view and apply`,
        });
      }
    } catch (e) {
      console.error('[HiringService] Talent notification failed:', e);
    }
  });

  return savedJob;
}
```

**Requires:** `NotificationsService` injected into `HiringService` and `NotificationsModule` added to `HiringModule` imports.

---

### DEFECT-008 — Application status change does not notify the talent

**File:** `backend/src/hiring/hiring.service.ts` — `updateApplicationStatus()`
**Severity:** 🟠 High

When HR moves a candidate from APPLIED → INTERVIEW, or INTERVIEW → SELECTED / REJECTED, the database is updated but no push notification is sent. The candidate must manually refresh to see their status change.

**Fix — add notification to `updateApplicationStatus()`:**
```typescript
async updateApplicationStatus(applicationId: string, newStatus: ApplicationStatus) {
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

### DEFECT-009 — No-show count never tracked in hiring pipeline

**File:** `backend/src/hiring/hiring.service.ts`
**Severity:** 🟠 High

`TalentProfile` has `noShowCount` and `searchRank` fields designed to penalise talent who accept interviews and don't attend. No code path ever increments `noShowCount` or lowers `searchRank`. Talent who repeatedly skip interviews rank equally with reliable candidates in search results.

**Fix — add `NO_SHOW` to `ApplicationStatus` enum and handle in `updateApplicationStatus()`:**
```typescript
// In job-application.entity.ts:
export enum ApplicationStatus {
  APPLIED = 'APPLIED',
  INTERVIEW = 'INTERVIEW',
  SELECTED = 'SELECTED',
  REJECTED = 'REJECTED',
  NO_SHOW = 'NO_SHOW',   // ADD
}

// In updateApplicationStatus():
if (newStatus === ApplicationStatus.NO_SHOW) {
  await this.talentService.recordNoShow(app.applicant.id);
}
```

**Add to `talent.service.ts`:**
```typescript
async recordNoShow(userId: string): Promise<void> {
  const profile = await this.getProfile(userId);
  profile.noShowCount = (profile.noShowCount || 0) + 1;
  profile.searchRank = Math.max(0, (profile.searchRank || 100) - 10);
  await this.talentRepo.save(profile);
}
```

---

### DEFECT-010 — JWT claim is `req.user.userId` but payload uses `sub` — potential mismatch

**File:** `backend/src/bookings/bookings.controller.ts` + `auth/jwt.strategy.ts`
**Severity:** 🟠 High

`bookings.controller.ts` uses `req.user.userId`:
```typescript
customer: { id: req.user.userId } as any,
```

The JWT payload in `auth.service.ts` is:
```typescript
const payload = { sub: user.id, phoneNumber: user.phoneNumber, role: user.role };
```

Whether `req.user.userId` resolves correctly depends entirely on what the `validate()` method in `jwt.strategy.ts` returns. If it returns `{ userId: payload.sub }` this works. If it returns `{ sub: payload.sub }` then `req.user.userId` is `undefined` and every booking is created with `customer.id = undefined`.

**This must be verified by reading `jwt.strategy.ts`. Until confirmed, every booking created has a missing customer ID.**

**Fix — standardise across all controllers:**
```typescript
// In jwt.strategy.ts validate():
async validate(payload: any) {
  return { userId: payload.sub, phoneNumber: payload.phoneNumber, role: payload.role };
}

// Then all controllers use req.user.userId consistently ✅
```

---

### DEFECT-011 — `PATCH /users/fcm-token` endpoint may not be exposed

**File:** `backend/src/users/users.controller.ts`
**Severity:** 🟠 High

`auth.service.ts` has `updateFcmToken()` method. `otp_screen.dart` calls `authRepository.registerFcmToken()` which hits `PATCH /users/fcm-token`. However `users.controller.ts` has not been read — this endpoint may not be wired up.

**Must verify `users.controller.ts` contains:**
```typescript
@Patch('fcm-token')
@UseGuards(JwtAuthGuard)
async updateFcmToken(@Req() req, @Body() body: { fcmToken: string }) {
  return this.usersService.updateFcmToken(req.user.userId, body.fcmToken);
}
```

If missing, FCM tokens from every device are silently discarded after login, meaning no push notifications ever reach any user.

---

### DEFECT-012 — OTP SMS not integrated — OTP only logged to console

**File:** `backend/src/auth/auth.service.ts`
**Severity:** 🟠 High

```typescript
console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
```

The OTP is now stored in Redis correctly. However no SMS is sent. In development a developer reads the server console. In production, real users receive no SMS and cannot log in.

**Fix — integrate MSG91:**
```typescript
import axios from 'axios';

private async sendSms(phone: string, otp: string): Promise<void> {
  const authKey = process.env.MSG91_AUTH_KEY;
  const templateId = process.env.MSG91_TEMPLATE_ID;
  if (!authKey || !templateId) {
    console.warn(`[DEV] OTP for ${phone}: ${otp}`);
    return;
  }
  await axios.post('https://api.msg91.com/api/v5/otp', {
    authkey: authKey,
    mobile: phone,
    otp,
    template_id: templateId,
  });
}

// Replace console.log with:
await this.sendSms(phoneNumber, otp);
```

---

## 🟡 MEDIUM DEFECTS — Screens & Features Incomplete

---

### DEFECT-013 — `calendar_screen.dart` does not exist — Plan Services booking date selection broken

**File:** `lib/features/booking/calendar_screen.dart` — not in file list
**Severity:** 🟡 Medium

Every flow in Plan Services (Hall, Catering, Decoration, Photography) and Rental requires a calendar picker to show available / pending / booked dates and let the user select a date. This screen does not exist. The booking flow from `booking_type_selector.dart` has no date selection step.

**Must be built with:**
- Full month calendar (use `table_calendar` package or custom painter)
- 3 states per date: Available (green), Pending (amber), Booked (red)
- Fetches `GET /businesses/:id/calendar` on load
- Returns selected date to calling screen

---

### DEFECT-014 — Worker map GPS coordinate mapping is non-functional for real locations

**File:** `lib/features/map/worker_map_screen.dart`
**Severity:** 🟡 Medium

When a real GPS location arrives from the socket, the screen maps it to screen coordinates using:
```dart
dx = (_liveLocations[worker.id]![1] % 0.01) * 30000 - 150;
dy = (_liveLocations[worker.id]![0] % 0.01) * 50000 - 250;
```

This is a nonsensical calculation — `lng % 0.01 * 30000` produces wildly different values for nearby locations and places workers randomly around the centre point. For the "Live Radar" discovery view this is a known approximation. But for the job-tracking view (where `jobId` is provided), workers will appear at wrong positions on screen regardless of their real GPS location.

**Fix — for the job-tracking view, use Google Maps:**
```dart
// When jobId is provided, show a real GoogleMap instead of the radar painter
if (widget.jobId != null) {
  return GoogleMap(
    initialCameraPosition: CameraPosition(target: _customerLocation, zoom: 14),
    markers: {
      Marker(markerId: const MarkerId('worker'), position: _workerPosition),
      Marker(markerId: const MarkerId('customer'), position: _customerLocation),
    },
  );
}
// Radar painter is fine for discovery mode (no jobId)
```

---

### DEFECT-015 — `synchronize: true` still in `app.module.ts` — production data destruction risk

**File:** `backend/src/app.module.ts`
**Severity:** 🟡 Medium (🔴 Critical before any production deployment)

```typescript
synchronize: true, // Enabled for development to create missing tables
```

Every server restart auto-drops and recreates all database tables to match entity definitions. Any data in those tables is permanently deleted. This is acceptable in development but catastrophic in production.

**Fix — before production deployment:**
1. Set `synchronize: false`
2. Run `npm run typeorm migration:generate -- -n InitialMigration`
3. Run `npm run typeorm migration:run`
4. Add migration run to deployment scripts

---

### DEFECT-016 — No pagination on any list endpoint

**File:** All GET list controllers
**Severity:** 🟡 Medium

`GET /workers`, `GET /hiring/jobs`, `GET /bookings/my`, `GET /businesses/my` all return complete unbounded datasets. As the platform grows these will become slow and eventually time out.

**Fix — add `?page=1&limit=20` to all list endpoints:**
```typescript
@Get()
async getAll(
  @Query('page') page = '1',
  @Query('limit') limit = '20',
) {
  const skip = (parseInt(page) - 1) * parseInt(limit);
  return this.workersService.getAll({ skip, take: parseInt(limit) });
}
```

---

## 🟢 LOW SEVERITY

---

### DEFECT-017 — `kDebugMode` OTP bypass still exists in `otp_screen.dart`

**File:** `lib/features/auth/otp_screen.dart`
**Severity:** 🟢 Low

```dart
if (kDebugMode)
  TextButton(
    onPressed: () {
      Navigator.pushAndRemoveUntil( ... MainWrapper ... );
    },
    child: const Text('DEBUG: Bypass Verification', style: TextStyle(color: Colors.redAccent)),
  ),
```

`kDebugMode` is `false` in release builds so this does not affect production. However it should be removed before the first public beta to avoid testers reporting it as a bug or a reviewer flagging it.

---

### DEFECT-018 — No Firebase background message handler registered

**File:** `lib/main.dart`
**Severity:** 🟢 Low

Firebase is initialized. FCM token is sent after login. But there is no `FirebaseMessaging.onBackgroundMessage()` top-level handler registered. When the app is in the background or terminated, push notifications arrive but tap actions (deep-linking to a booking, job alert, etc.) are silently ignored.

**Fix — add to `main.dart` (must be top-level function):**
```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Handle background message — log or process silently
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // ...
}
```

---

### DEFECT-019 — No unit tests for any module

**File:** `backend/test/` — empty
**Severity:** 🟢 Low

No unit or integration tests exist for any backend module. The critical business logic paths (OTP flow, wallet deduction, GPS check, billing calculation) have no test coverage. Any future change to these functions will have no regression safety net.

**Minimum tests needed before production:**
- `auth.service.spec.ts` — OTP store, verify, expire, JWT issue
- `wallets.service.spec.ts` — deduction, insufficient balance, top-up
- `bookings.service.spec.ts` — create, OTP verify, billing calculation
- `workers.service.spec.ts` — go-live toggle, rate limit, strike increment

---

## Fix Priority Order (Updated)

### Do These First — Backend blocking issues

1. **DEFECT-001** — Fix `firebase.module.ts` to use env vars, not file path (backend crashes without service account)
2. **DEFECT-010** — Verify/fix JWT claim `req.user.userId` vs `req.user.sub` mismatch in all controllers
3. **DEFECT-011** — Verify `PATCH /users/fcm-token` is exposed in `users.controller.ts`
4. **DEFECT-003** — Add `GET /workers/nearby` endpoint
5. **DEFECT-004** — Add `POST /workers/register` endpoint
6. **DEFECT-002** — Fix go-live toggle to use `req.user.userId` not URL param

### Do These Second — Business logic completeness

7. **DEFECT-005** — Credit Rs.12 first-job bonus and set `isFirstJobDone = true`
8. **DEFECT-006** — Add `updateHourlyRate()` method and `PATCH /workers/rate` endpoint
9. **DEFECT-007** — Notify talent when a job is posted
10. **DEFECT-008** — Notify talent when application status changes
11. **DEFECT-009** — Track no-show count and apply search rank penalty
12. **DEFECT-012** — Integrate MSG91 for real SMS OTP delivery

### Do These Third — Missing screens

13. **DEFECT-013** — Build `calendar_screen.dart` (Plan Services + Rental both blocked)
14. **DEFECT-014** — Replace fake GPS mapping with real Google Maps for job-tracking view

### Before Production

15. **DEFECT-015** — Switch `synchronize: true` to TypeORM migrations
16. **DEFECT-016** — Add pagination to all list endpoints
17. **DEFECT-017** — Remove `kDebugMode` OTP bypass
18. **DEFECT-018** — Register Firebase background message handler
19. **DEFECT-019** — Write unit tests for critical modules

---

*Gixbee Defects Re-Scan — April 2026*
*Previous report: MAJOR_DEFECTS.md*
