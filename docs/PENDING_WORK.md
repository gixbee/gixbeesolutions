# Gixbee — Pending Work & Missing Functionality

> Last updated: April 2026
> This document tracks every incomplete screen, missing backend module, wiring gap, and production-readiness item across the Gixbee codebase.

---

## Quick Summary

| Category | Total Items | Done | In Progress | Missing |
|---|---|---|---|---|
| Flutter Screens | 28 | 20 | 2 | 6 |
| Flutter Repositories | 5 | 3 | 2 | 0 |
| Backend Modules | 12 | 8 | 3 | 1 |
| Backend Endpoints | 22 | 14 | 4 | 4 |
| Infrastructure / Wiring | 10 | 2 | 3 | 5 |
| Production Readiness | 8 | 0 | 2 | 6 |

---

## 1. Flutter — Missing & Incomplete Screens

---

### 1.1 Home Screen — Intent-Based Redesign Required

**File:** `lib/features/home/home_screen.dart`
**Status:** ⚠️ Exists but wrong design

**Problem:**
The current home screen shows a generic 6-tile service category grid (Cleaning, Plumbing, Electrician, Repairs, Painting, Health). This does NOT match the Gixbee architecture. The correct design is 4 large intent-based entry cards.

**What it must show:**
```
┌─────────────────────────────┐
│  🛍  Book Services          │
│  Find halls, workers & more │
├─────────────────────────────┤
│  🎓  Find a Job             │
│  Apply & attend interviews  │
├─────────────────────────────┤
│  ⚡  Earn by Working        │
│  Offer skills, earn hourly  │
├─────────────────────────────┤
│  🏢  List My Business       │
│  Add hall, catering, etc.   │
└─────────────────────────────┘
```

**Each card navigates to:**
- Book Services → `BookServicesSplitScreen`
- Find a Job → `FindJobModule`
- Earn by Working → `RegisterProScreen`
- List My Business → `ListBusinessTypeScreen`

**What to remove:** The 6-tile category grid, the Gixbee/Jobs tab switcher, the featured worker cards pulled from `MockRepository`.

---

### 1.2 Calendar View Screen — Entirely Missing

**File:** `lib/features/booking/calendar_screen.dart` — **does not exist**
**Status:** ❌ Missing

**Used by:**
- Plan Services (Hall, Catering, Decoration, Photography) — show available booking dates
- Rental — show available rental dates

**Required behaviour:**
- Show a full month calendar
- Each date has one of three states:
  - Green = Available
  - Yellow = Pending (request sent, awaiting vendor)
  - Red = Booked (confirmed)
- User taps an available date to proceed with booking
- Fetch blocked dates from: `GET /bookings/calendar/{vendorId}` or `GET /rentals/{itemId}/calendar`

**Minimum fields:**
```dart
class CalendarScreen extends StatefulWidget {
  final String vendorId;
  final String vendorName;
  final String serviceType; // 'hall' | 'catering' | 'rental' etc.
}
```

---

### 1.3 Post a Job Screen — Still a Stub

**File:** `lib/features/jobs/post_job_screen.dart`
**Status:** ❌ Stub — shows `Text('Post Job form goes here')`

**Used by:** Hiring Business operators to post job roles.

**Required fields in the form:**
- Job Title (text field)
- Skills Required (multi-select chips)
- Experience Required (dropdown: Fresher / 1-2 yrs / 3-5 yrs / 5+ yrs)
- Salary (range or fixed, text field)
- Job Location (city picker)
- Job Type (Full Time / Part Time / Contract)
- Job Description (multi-line text)

**On submit:** `POST /hiring/jobs` with the form data. Show success and navigate back.

---

### 1.4 Business Unit Dashboard — Missing

**File:** `lib/features/business/business_unit_dashboard.dart` — **does not exist**
**Status:** ❌ Missing

**Problem:** After a business is listed and verified, the owner lands nowhere. There is no dashboard to manage existing units.

**Required behaviour:**
- Show a card grid of all business units owned by the user
- Each card shows: business name, type, status (Verified / Pending)
- Tapping a card opens unit management (calendar, capacity, offline days, operators, transfer ownership)
- A floating `+` button lets user add another unit

**API needed:** `GET /businesses/my` — returns list of user's businesses.

---

### 1.5 Hiring Pipeline Kanban Screen — Missing

**File:** `lib/features/business/hiring_pipeline_screen.dart` — **does not exist**
**Status:** ❌ Missing

**Used by:** HR operators inside a Hiring Business to manage candidates.

**Required behaviour:**
- 4 columns: Applied | Interview | Selected | Rejected
- Each candidate is a draggable card (or tappable with status change buttons)
- Tap a candidate card → see their talent profile
- Change status → `PATCH /hiring/applications/:id {status}`
- Each state change triggers a push notification to the talent

---

### 1.6 Worker Map Screen — Needs Job-Scoped Socket

**File:** `lib/features/map/worker_map_screen.dart`
**Status:** ⚠️ Exists but broken

**Problem:** The screen listens to all WebSocket `locationUpdated` events from the server. After the gateway fix, location is now only emitted to the specific job room. The Flutter screen must join that room before listening.

**Fix required:**
```dart
// On screen init, join the job room first
socketService.joinJobRoom(jobId);

// Then listen only for locationUpdated events
socketService.onLocationUpdated((data) {
  // update marker on map
});
```

The `jobId` must be passed into this screen from the booking confirmation screen.

---

## 2. Flutter — Repository / Data Layer Gaps

---

### 2.1 Booking Repository — Missing Endpoints

**File:** `lib/data/booking_repository.dart`
**Status:** ⚠️ Partial

**Currently has:** `createBooking`, `getMyBookings`

**Missing methods:**
```dart
// Vendor approve/reject a booking request
Future<void> updateBookingStatus(String bookingId, String status);

// Customer confirm after vendor approves
Future<void> confirmBooking(String bookingId);

// Worker taps Arrived — triggers arrival OTP
Future<void> markArrived(String bookingId);

// Worker taps Finish — triggers completion OTP
Future<void> markComplete(String bookingId);

// Verify arrival OTP
Future<void> verifyArrivalOtp(String bookingId, String otp);

// Verify completion OTP
Future<void> verifyCompletionOtp(String bookingId, String otp);

// Get blocked calendar dates for a vendor
Future<List<DateTime>> getCalendarDates(String vendorId);
```

---

### 2.2 No Business Repository

**File:** `lib/data/business_repository.dart` — **does not exist**
**Status:** ❌ Missing

The `list_business_type_screen.dart` and `list_business_details_screen.dart` screens exist but have no repository to call. All business registration and management API calls must go through this layer.

**Required methods:**
```dart
Future<void> registerBusiness({type, name, location, details, documents});
Future<List<Business>> getMyBusinesses();
Future<void> addOperator(String businessId, String userId, String role);
Future<void> initiateOwnershipTransfer(String businessId, String newOwnerId);
Future<void> addOfflineDay(String businessId, DateTime date);
```

---

### 2.3 No Talent/Hiring Repository

**File:** `lib/data/hiring_repository.dart` — **does not exist**
**Status:** ❌ Missing

`talent_profile_screen.dart`, `job_alerts_screen.dart`, and `application_tracker_screen.dart` all exist but have no data layer wiring.

**Required methods:**
```dart
Future<void> saveTalentProfile(TalentProfile profile);
Future<List<JobPost>> getMatchingJobs();
Future<void> applyToJob(String jobId);
Future<List<Application>> getMyApplications();
Future<void> toggleJobAlerts(bool enabled);
```

---

## 3. Backend — Missing Modules

---

### 3.1 Businesses Module — Entirely Missing

**Path:** `backend/src/businesses/` — **does not exist**
**Status:** ❌ Missing

This is the most critical missing backend module. Both frontend business screens call APIs that don't exist.

**Files to create:**
```
backend/src/businesses/
├── business.entity.ts          # Business unit entity
├── operator.entity.ts          # Operator/manager relation
├── ownership-transfer.entity.ts
├── businesses.controller.ts
├── businesses.service.ts
└── businesses.module.ts
```

**Entity fields needed:**
```typescript
@Entity('businesses')
class Business {
  id: string;
  owner: User;
  type: 'SERVICE' | 'HIRING' | 'RENTAL';
  serviceType: 'HALL' | 'CATERING' | 'DECORATION' | 'PHOTOGRAPHY' | null;
  name: string;
  location: string;
  description: string;
  status: 'PENDING' | 'VERIFIED' | 'REJECTED';
  operators: BusinessOperator[];
  createdAt: Date;
}
```

**Endpoints needed:**
```
POST   /businesses              Register new business unit
GET    /businesses/my           Get all businesses owned by current user
GET    /businesses/:id          Get single business details
PATCH  /businesses/:id          Edit business details
DELETE /businesses/:id          Delete business unit
POST   /businesses/:id/operators        Add operator/manager
DELETE /businesses/:id/operators/:uid   Remove operator
POST   /businesses/:id/transfer         Initiate ownership transfer (OTP)
POST   /businesses/:id/calendar/offline Add offline day
GET    /businesses/:id/calendar         Get calendar (availability + blocked)
```

---

### 3.2 Talent Profile Module — Missing

**Path:** `backend/src/talent/` — **does not exist**
**Status:** ❌ Missing

The `talent_profile_screen.dart` screen has no backend to save to.

**Files to create:**
```
backend/src/talent/
├── talent-profile.entity.ts
├── talent.controller.ts
├── talent.service.ts
└── talent.module.ts
```

**Entity fields:**
```typescript
@Entity('talent_profiles')
class TalentProfile {
  id: string;
  user: User;
  education: string[];
  skills: string[];
  experience: string;
  currentStatus: 'FINAL_YEAR' | 'GRADUATE' | 'EXPERIENCED';
  preferredRoles: string[];
  preferredLocations: string[];
  jobAlertsEnabled: boolean;
  noShowCount: number;
  searchRank: number;  // penalty-weighted for no-shows
}
```

**Endpoints needed:**
```
POST  /talent/profile       Create or update talent profile
GET   /talent/profile       Get current user's talent profile
PATCH /talent/alerts        Toggle job alerts on/off
GET   /talent/jobs          Get matching jobs based on profile
```

---

## 4. Backend — Incomplete Implementations

---

### 4.1 Auth — OTP Still Not Using Redis

**File:** `backend/src/auth/auth.service.ts`
**Status:** ⚠️ Partial — Redis service exists but not wired

**Current state:** `requestOtp` generates a random OTP and logs it to console. `verifyOtp` accepts any 6-digit number.

**What must be done:**
```typescript
// In requestOtp:
const otp = Math.floor(100000 + Math.random() * 900000).toString();
await this.redisService.set(`otp:${phoneNumber}`, otp, 300); // 5-min TTL
await this.smsService.send(phoneNumber, `Your Gixbee OTP: ${otp}`);

// In verifyOtp:
const storedOtp = await this.redisService.get(`otp:${phoneNumber}`);
if (!storedOtp || storedOtp !== otp) {
  throw new UnauthorizedException('Invalid or expired OTP');
}
await this.redisService.del(`otp:${phoneNumber}`);
```

**Also needed:** Inject `RedisService` into `AuthService` via constructor.

---

### 4.2 Bookings — Arrival and Completion OTP Endpoints Missing

**File:** `backend/src/bookings/bookings.controller.ts`
**Status:** ⚠️ Missing endpoints

The booking lifecycle requires two OTP verification steps. Neither endpoint exists.

**Add to controller:**
```typescript
// Worker taps "Arrived" — generates arrival OTP
@Patch(':id/arrive')
async markArrived(@Param('id') id: string) {}

// Verify arrival OTP entered by worker at site
@Post(':id/verify-arrival')
async verifyArrival(@Body() body: { otp: string }, @Param('id') id: string) {}

// Worker taps "Finish" — generates completion OTP
@Patch(':id/complete')
async markComplete(@Param('id') id: string) {}

// Verify completion OTP
@Post(':id/verify-completion')
async verifyCompletion(@Body() body: { otp: string }, @Param('id') id: string) {}
```

**Arrival OTP logic:**
1. Generate 4-digit OTP
2. Store in Redis: `otp:arrival:{bookingId}` with 10-min TTL
3. Send via SMS to `booking.onSiteContact.phone` (or customer if self-present)
4. Return `{message: 'OTP sent'}`

---

### 4.3 Workers — Go-Live Toggle and Rate Limit Not Enforced

**File:** `backend/src/workers/workers.service.ts`
**Status:** ⚠️ Worker entity created but business logic missing

**Missing: Go-live toggle with wallet check**
```typescript
async toggleLive(userId: string, isActive: boolean): Promise<void> {
  const profile = await this.workerProfileRepo.findOne({ where: { user: { id: userId } } });
  if (isActive && profile.isFirstJobDone) {
    const balance = await this.walletsService.getBalance(userId);
    if (balance < 12) {
      throw new BadRequestException('Minimum Rs.12 wallet balance required to go live');
    }
  }
  profile.isActive = isActive;
  await this.workerProfileRepo.save(profile);
}
```

**Missing: Rate limit on hourly rate update**
```typescript
async updateRate(userId: string, newRate: number): Promise<void> {
  const today = new Date().toISOString().split('T')[0];
  if (profile.rateUpdateDate === today && profile.rateUpdateCountToday >= 2) {
    throw new BadRequestException('Hourly rate can only be updated twice per day');
  }
  profile.hourlyRate = newRate;
  profile.rateUpdateCountToday = profile.rateUpdateDate === today
    ? profile.rateUpdateCountToday + 1 : 1;
  profile.rateUpdateDate = today;
  await this.workerProfileRepo.save(profile);
}
```

**Missing endpoint:** `PATCH /workers/toggle-live` and `PATCH /workers/rate`

---

### 4.4 GPS Movement Check — Still a Stub

**File:** `backend/src/bookings/bookings.processor.ts`
**Status:** ⚠️ Queue job fires but processor body is empty

**Current state:**
```typescript
@Process('tenMinuteGpsCheck')
async handleTenMinuteGpsCheck(job: Job) {
  console.log(`Starting 10-minute GPS check for booking: ${job.data.bookingId}`);
  // TODO: Fetch worker location from Redis
  // TODO: Verify if worker is within expected radius or moving
  return { status: 'GPS Checked' };
}
```

**Complete implementation needed:**
```typescript
@Process('tenMinuteGpsCheck')
async handleTenMinuteGpsCheck(job: Job) {
  const { bookingId, workerId } = job.data;
  const booking = await this.bookingsService.findById(bookingId);
  if (!booking || booking.status !== 'ACCEPTED') return;

  const locationJson = await this.redisService.get(`location:${workerId}`);
  if (!locationJson) {
    // No location data at all — worker has not moved
    await this.bookingsService.autoCancelWithStrike(bookingId, workerId);
    // TODO: Send push notification to customer
    return;
  }

  const { lat, lng, timestamp } = JSON.parse(locationJson);
  const ageSeconds = (Date.now() - timestamp) / 1000;
  if (ageSeconds > 600) {
    // Last known location is over 10 minutes old — no movement
    await this.bookingsService.autoCancelWithStrike(bookingId, workerId);
  }
}
```

**Also needs:** `autoCancelWithStrike` method in `BookingsService` that sets status to CANCELLED and increments `workerProfile.strikeCount`.

---

### 4.5 FCM Notifications — Not Wired to Any Event

**File:** `backend/src/notifications/notifications.service.ts`
**Status:** ⚠️ Service exists but never called

The `NotificationsModule` and `NotificationsService` were created but nothing calls them. Every status change in the system should trigger a push notification.

**Must be called from these places:**

| Event | Trigger Location | Recipient |
|---|---|---|
| New booking request | `bookings.service.ts → createBooking` | Vendor |
| Booking approved | `bookings.service.ts → updateStatus` | Customer |
| Booking rejected | `bookings.service.ts → updateStatus` | Customer |
| Job request sent | `worker-engine` or `bookings` | Worker |
| Job accepted by worker | `bookings.service.ts` | Customer |
| Arrival OTP | `bookings.service.ts → markArrived` | On-site contact |
| Completion OTP | `bookings.service.ts → markComplete` | Customer |
| Job alert (new job post) | `hiring.service.ts → createJobPost` | Matched talent |
| Application status change | `hiring.service.ts → updateApplication` | Talent |
| Wallet balance low | `wallets.service.ts → deductBookingFee` | Worker |

**Firebase Admin SDK must be initialized in `main.ts`:**
```typescript
import * as admin from 'firebase-admin';
admin.initializeApp({
  credential: admin.credential.cert({
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  }),
});
```

---

### 4.6 Workers Service — Still Hardcoded Data

**File:** `backend/src/workers/workers.service.ts`
**Status:** ⚠️ Returns hardcoded array, not DB

The `getAll()` method returns a hardcoded array of 6 workers defined in the service file. There is a `WorkerProfile` entity and table but `getAll()` never queries it.

**Fix:**
```typescript
async getAll(): Promise<WorkerProfile[]> {
  return this.workerProfileRepo.find({
    where: { isActive: true, verificationStatus: VerificationStatus.VERIFIED },
    relations: ['user'],
    order: { rating: 'DESC' },
  });
}
```

Also add location-based filtering:
```typescript
async getNearby(lat: number, lng: number, skill: string): Promise<WorkerProfile[]> {
  // Use PostGIS or manual distance calculation
  // Filter by: isActive=true, verificationStatus=VERIFIED, skills contains skill
}
```

---

### 4.7 Hiring Service — Talent Matching Algorithm Missing

**File:** `backend/src/hiring/hiring.service.ts`
**Status:** ⚠️ Job post saved but no talent matching on creation

When a new job is posted, the system must:
1. Find all talent profiles where `skills[]` overlaps with the job's `skills[]`
2. Filter by `preferredLocations` matching the job's location
3. Filter by `jobAlertsEnabled = true`
4. Send push notification via FCM to each matched user's `fcmToken`

**Missing method:**
```typescript
private async notifyMatchingTalent(jobPost: JobPost): Promise<void> {
  const matches = await this.talentProfileRepo
    .createQueryBuilder('tp')
    .where('tp.jobAlertsEnabled = true')
    .andWhere('tp.preferredLocations @> :location', { location: [jobPost.location] })
    .getMany();

  for (const talent of matches) {
    await this.notificationsService.sendToUser(
      talent.user.fcmToken,
      `New job: ${jobPost.title} in ${jobPost.location}`,
    );
  }
}
```

---

## 5. Infrastructure & Wiring Gaps

---

### 5.1 Firebase Not Initialized in Flutter

**File:** `lib/main.dart`
**Status:** ❌ Missing

There is a comment in `main.dart`:
```dart
// Note: Firebase initialization will be added here once config is available
```

**What needs to be added:**
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Request notification permissions
  await FirebaseMessaging.instance.requestPermission();

  // Get FCM token and send to backend after login
  final fcmToken = await FirebaseMessaging.instance.getToken();
  // Store in auth repository for sending to server after login

  runApp(const ProviderScope(child: GixbeeApp()));
}
```

**Also required:** `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`.

---

### 5.2 FCM Token Not Sent to Backend After Login

**File:** `lib/data/auth_repository.dart`
**Status:** ❌ Missing

After OTP verification succeeds and a JWT is returned, the device FCM token must be registered on the server so the backend can send push notifications to this device.

**Add after `verifyOtp` saves the token:**
```dart
Future<void> registerFcmToken(String fcmToken) async {
  await _dio.patch('/users/fcm-token', data: {'fcmToken': fcmToken});
}
```

**Call it in `otp_screen.dart` after successful verification.**

**Backend endpoint also missing:** `PATCH /users/fcm-token` in `users.controller.ts`.

---

### 5.3 WebSocket Gateway Has No Authentication Guard

**File:** `backend/src/worker-engine/worker.gateway.ts`
**Status:** ⚠️ Anyone can connect

The gateway accepts any socket connection with no JWT verification. A malicious client could join any job room and receive private location updates.

**Fix — add JWT guard to gateway:**
```typescript
import { JwtService } from '@nestjs/jwt';

handleConnection(client: Socket) {
  const token = client.handshake.auth?.token;
  try {
    const payload = this.jwtService.verify(token);
    client.data.userId = payload.sub;
  } catch {
    client.disconnect();
  }
}
```

---

### 5.4 `synchronize: true` in TypeORM — Must Not Go to Production

**File:** `backend/src/app.module.ts`
**Status:** ⚠️ Development-only setting, dangerous in production

```typescript
synchronize: true, // Only for development!
```

This auto-drops and recreates tables on every deploy. In production this will destroy all user data.

**Fix before any production deployment:**
1. Set `synchronize: false`
2. Generate migration: `npm run typeorm migration:generate -- -n InitialMigration`
3. Run migrations: `npm run typeorm migration:run`
4. Add migration script to CI/CD pipeline

---

### 5.5 No `.env.example` File

**Status:** ❌ Missing

New developers have no reference for what environment variables are needed. There is a `.env` file (which should never be committed) but no `.env.example`.

**Create `backend/.env.example`:**
```env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=postgres
DATABASE_PASSWORD=
DATABASE_NAME=gixbee

REDIS_HOST=localhost
REDIS_PORT=6379

JWT_SECRET=

FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=

MSG91_AUTH_KEY=
MSG91_SENDER_ID=GIXBEE
MSG91_TEMPLATE_ID=

RAZORPAY_KEY_ID=
RAZORPAY_KEY_SECRET=

PORT=3000
```

---

## 6. Production Readiness — Not Started

---

### 6.1 SMS OTP Gateway Not Integrated

**File:** `backend/src/auth/auth.service.ts`
**Status:** ❌ OTP only printed to console

The system currently logs OTPs to the server console (`[DEV ONLY] OTP for +91xxx: 123456`). No actual SMS is sent.

**Integration needed:** MSG91 (recommended for India) or Firebase Auth Phone.

**MSG91 integration:**
```typescript
// Install: npm install axios
const response = await axios.post('https://api.msg91.com/api/v5/otp', {
  authkey: process.env.MSG91_AUTH_KEY,
  mobile: phoneNumber,
  otp: generatedOtp,
  template_id: process.env.MSG91_TEMPLATE_ID,
});
```

---

### 6.2 No Input Validation on Backend

**Status:** ❌ Missing across all controllers

No NestJS `ValidationPipe` or `class-validator` DTOs are set up. Any malformed request body goes directly to the service layer.

**Fix — add global validation pipe in `main.ts`:**
```typescript
import { ValidationPipe } from '@nestjs/common';
app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
```

**Then create DTOs for every endpoint:**
```typescript
// Example: CreateBookingDto
export class CreateBookingDto {
  @IsString() @IsNotEmpty() workerId: string;
  @IsDateString() scheduledAt: string;
  @IsNumber() @Min(0) amount: number;
  @IsEnum(BookingType) type: BookingType;
}
```

---

### 6.3 No Error Handling Strategy

**Status:** ❌ Missing

Unhandled exceptions will crash the server and leak stack traces to clients. A global exception filter is needed.

**Fix — create `lib/core/filters/http-exception.filter.ts`** and wire it in `main.ts`:
```typescript
app.useGlobalFilters(new HttpExceptionFilter());
```

---

### 6.4 No Pagination on List Endpoints

**Status:** ⚠️ Missing on all GET list endpoints

`GET /workers`, `GET /hiring/jobs`, `GET /bookings/my` all return entire collections with no limit. This will break at scale.

**Fix:** Add `?page=1&limit=20` query params to all list endpoints using TypeORM `skip` and `take`.

---

### 6.5 No Rate Limiting on API

**Status:** ❌ Missing

The OTP endpoint (`POST /auth/request-otp`) has no rate limiting. A bot could request thousands of OTPs per minute.

**Fix:**
```bash
npm install @nestjs/throttler
```
```typescript
// In app.module.ts
ThrottlerModule.forRoot({ ttl: 60, limit: 5 }) // Max 5 OTP requests per minute
```

---

### 6.6 No Tests

**Status:** ❌ Missing

No unit tests or integration tests exist for any module. The `test/` directory is empty.

**Minimum test coverage needed before production:**
- `auth.service.spec.ts` — OTP generation, verification, JWT creation
- `wallets.service.spec.ts` — balance deduction, insufficient balance error
- `bookings.service.spec.ts` — booking creation, status transitions
- `workers.service.spec.ts` — go-live toggle, rate limit enforcement

---

## 7. Summary Checklist

### Flutter — To Do

- [ ] Redesign `home_screen.dart` with 4 intent-based entry cards
- [ ] Create `calendar_screen.dart` with 3-state date display
- [ ] Build `post_job_screen.dart` (currently a stub)
- [ ] Create `business_unit_dashboard.dart`
- [ ] Create `hiring_pipeline_screen.dart` (Kanban)
- [ ] Fix `worker_map_screen.dart` to join job room before listening
- [ ] Add missing methods to `booking_repository.dart`
- [ ] Create `business_repository.dart`
- [ ] Create `hiring_repository.dart`
- [ ] Initialize Firebase in `main.dart`
- [ ] Send FCM token to backend after login

### Backend — To Do

- [ ] Create `businesses/` module (entity, service, controller, endpoints)
- [ ] Create `talent/` module (entity, service, controller, endpoints)
- [ ] Wire `RedisService` into `auth.service.ts` for real OTP storage
- [ ] Add arrival/completion OTP endpoints to `bookings.controller.ts`
- [ ] Implement go-live toggle with wallet check in `workers.service.ts`
- [ ] Implement rate-limit enforcement on hourly rate update
- [ ] Complete GPS movement check in `bookings.processor.ts`
- [ ] Wire `NotificationsService` into booking, hiring, and wallet events
- [ ] Initialize Firebase Admin SDK in `main.ts`
- [ ] Add `PATCH /users/fcm-token` endpoint
- [ ] Add `PATCH /workers/toggle-live` endpoint
- [ ] Replace hardcoded worker array with DB query in `workers.service.ts`
- [ ] Add talent matching on job post in `hiring.service.ts`
- [ ] Add JWT guard to WebSocket gateway
- [ ] Integrate MSG91 or Firebase SMS for OTP delivery

### Infrastructure — To Do

- [ ] Create `backend/.env.example`
- [ ] Add `google-services.json` and `GoogleService-Info.plist` (from Firebase console)
- [ ] Set `synchronize: false` and create TypeORM migrations
- [ ] Add global `ValidationPipe` with DTOs for all endpoints
- [ ] Add global HTTP exception filter
- [ ] Add `ThrottlerModule` for rate limiting
- [ ] Add pagination to all list endpoints
- [ ] Write unit tests for auth, wallets, bookings, workers modules

---

*Generated: April 2026 | Gixbee v1.0.0*
