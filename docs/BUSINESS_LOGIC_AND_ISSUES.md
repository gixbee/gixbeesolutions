# Gixbee — Complete Business Logic & Missing Issues

> Last updated: April 2026
> This document covers every module's intended business logic, what is currently implemented, what is missing, and the exact code/fix required for each gap.

---

## Table of Contents

1. [Auth & OTP Flow](#1-auth--otp-flow)
2. [Wallet System](#2-wallet-system)
3. [Book Services — Instant Help (Live Worker Engine)](#3-book-services--instant-help-live-worker-engine)
4. [Book Services — Plan Services (Hall, Catering, etc.)](#4-book-services--plan-services)
5. [Rental Service](#5-rental-service)
6. [Find a Job](#6-find-a-job)
7. [Earn by Working (Worker Profile & Go-Live)](#7-earn-by-working)
8. [List My Business](#8-list-my-business)
9. [Push Notifications (FCM)](#9-push-notifications-fcm)
10. [WebSocket & Real-Time Location](#10-websocket--real-time-location)
11. [Background Jobs (Bull Queue)](#11-background-jobs-bull-queue)
12. [Missing Issues Master Checklist](#12-missing-issues-master-checklist)

---

## 1. Auth & OTP Flow

### Intended Business Logic

```
User enters phone number
  → Backend generates random 6-digit OTP
  → OTP stored in Redis with 5-minute TTL (key: otp:{phone})
  → OTP sent via MSG91 SMS to phone number
  → User receives OTP on device
  → User enters OTP in app
  → Backend fetches from Redis, compares
  → If match: Redis key deleted, JWT returned
  → If mismatch or expired: error returned
  → After login: device FCM token sent to backend
```

### What is implemented ✅
- `POST /auth/request-otp` — generates random OTP ✅
- `POST /auth/verify-otp` — verifies OTP, creates user if new, returns JWT ✅
- `GET /auth/profile` — returns user profile ✅
- `verifyOtp` creates new users with Rs.100 starting wallet balance ✅
- JWT strategy with passport ✅

### What is missing ❌

#### Issue 1.1 — OTP not stored in Redis

**File:** `backend/src/auth/auth.service.ts`

`requestOtp()` generates the OTP and logs it to console only. `verifyOtp()` accepts any 6-digit number. Redis is never used.

**Fix:**
```typescript
// Inject RedisService into AuthService constructor
constructor(
  @InjectRepository(User) private usersRepository: Repository<User>,
  private jwtService: JwtService,
  private redisService: RedisService,   // ADD THIS
) {}

async requestOtp(phoneNumber: string) {
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  await this.redisService.set(`otp:${phoneNumber}`, otp, 300); // 5 min TTL
  // TODO: await this.smsService.send(phoneNumber, otp);
  console.log(`[DEV] OTP for ${phoneNumber}: ${otp}`); // Remove in production
  return { message: 'OTP sent' };
}

async verifyOtp(phoneNumber: string, otp: string) {
  const stored = await this.redisService.get(`otp:${phoneNumber}`);
  if (!stored || stored !== otp) {
    throw new UnauthorizedException('Invalid or expired OTP');
  }
  await this.redisService.del(`otp:${phoneNumber}`); // Single-use
  // ... rest of logic
}
```

**Also add to `auth.module.ts`:**
```typescript
imports: [RedisModule, ...]  // Import RedisModule
```

---

#### Issue 1.2 — No SMS Gateway Integration

**File:** `backend/src/auth/auth.service.ts`

OTP is only logged to console. In production no SMS is sent.

**Fix — MSG91 integration:**
```typescript
// Install: npm install axios
import axios from 'axios';

private async sendSms(phone: string, otp: string): Promise<void> {
  await axios.post('https://api.msg91.com/api/v5/otp', {
    authkey: process.env.MSG91_AUTH_KEY,
    mobile: phone,
    otp,
    template_id: process.env.MSG91_TEMPLATE_ID,
  });
}
```

---

#### Issue 1.3 — FCM Token Never Sent to Backend After Login

**File:** `lib/features/auth/otp_screen.dart` + `backend/src/users/users.controller.ts`

After OTP verification the Flutter app receives a JWT but never sends the device FCM token to the server. This means push notifications cannot reach the device.

**Flutter fix — add to `otp_screen.dart` after successful verify:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';

// After verifyOtp() succeeds:
final fcmToken = await FirebaseMessaging.instance.getToken();
if (fcmToken != null) {
  await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
}
```

**Flutter fix — add to `auth_repository.dart`:**
```dart
Future<void> registerFcmToken(String token) async {
  await _dio.patch('/users/fcm-token', data: {'fcmToken': token});
}
```

**Backend fix — add to `users.controller.ts`:**
```typescript
@Patch('fcm-token')
@UseGuards(JwtAuthGuard)
async updateFcmToken(@Request() req, @Body() body: { fcmToken: string }) {
  return this.usersService.updateFcmToken(req.user.sub, body.fcmToken);
}
```

**Backend fix — add to `users.service.ts`:**
```typescript
async updateFcmToken(userId: string, fcmToken: string): Promise<void> {
  await this.usersRepository.update(userId, { fcmToken });
}
```

---

#### Issue 1.4 — Firebase Not Initialized in Flutter

**File:** `lib/main.dart`

There is a comment: `// Note: Firebase initialization will be added here once config is available`

**Fix:**
```dart
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // ADD THIS
  runApp(const ProviderScope(child: GixbeeApp()));
}
```

Requires `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` from Firebase console.

---

#### Issue 1.5 — No JWT Guard on Any Controller

**All backend controllers** are publicly accessible. Any request without a token can call any endpoint.

**Fix — apply to every controller that requires auth:**
```typescript
import { UseGuards, Request } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt.strategy';

@Controller('bookings')
@UseGuards(JwtAuthGuard)  // Protect entire controller
export class BookingsController { ... }
```

**Controllers needing guards:** `bookings`, `workers`, `wallets`, `businesses`, `talent`, `hiring`, `rentals`, `users`.

---

## 2. Wallet System

### Intended Business Logic

```
Every worker must maintain Rs.12 wallet balance to go live
First job: Rs.12 not required (is_first_job_done = false)
After first job: must top-up Rs.12 to go live again
Worker earns Rs.12 bonus after first job completion
Booking fee (Rs.12) deducted from wallet on each job acceptance
If balance < Rs.12 and not first job: block go-live toggle
Payment for work is customer → worker directly (outside app for now)
Top-up via Razorpay
```

### What is implemented ✅
- `getBalance()` — fetch user wallet balance ✅
- `deductBookingFee()` — deducts Rs.12, logs transaction ✅
- `addFunds()` — credit wallet, logs transaction ✅
- `WalletTransaction` entity with CREDIT/DEBIT types ✅
- Rs.100 starting balance for new users ✅

### What is missing ❌

#### Issue 2.1 — Wallet Balance Not Checked Before Go-Live Toggle

**File:** `backend/src/workers/workers.service.ts`

`toggleGoLive()` toggles the worker's `isActive` flag but never checks if the wallet has Rs.12 minimum before allowing go-live.

**Fix — add balance check to `toggleGoLive()`:**
```typescript
async toggleGoLive(userId: string): Promise<{ isActive: boolean; message: string }> {
  // ... find profile ...

  // Only check balance when going LIVE (not when going offline)
  if (!profile.isActive) { // about to go live
    if (profile.isFirstJobDone) {
      const balance = await this.walletsService.getBalance(userId);
      if (balance < 12) {
        throw new BadRequestException(
          'Insufficient wallet balance. Minimum Rs.12 required to go live.'
        );
      }
    }
  }
  profile.isActive = !profile.isActive;
  // ...
}
```

---

#### Issue 2.2 — Rs.12 First-Job Bonus Not Credited

**File:** `backend/src/bookings/bookings.service.ts`

When a booking is completed (`verifyCompletionOtp`), the Rs.12 first-job bonus is never credited to the worker.

**Fix — add to `verifyCompletionOtp()`:**
```typescript
// After saving COMPLETED booking:
if (!booking.operator.isFirstJobDone) {
  await this.walletsService.addFunds(booking.operator.id, 12);
  // Mark first job done on worker profile
  await this.workerProfileRepo.update(
    { user: { id: booking.operator.id } },
    { isFirstJobDone: true }
  );
}
```

---

#### Issue 2.3 — No Razorpay Endpoint for Wallet Top-Up

**File:** Backend — endpoint missing entirely

The Flutter `wallet_screen.dart` shows a top-up button but there is no backend endpoint to initiate a Razorpay order.

**Fix — add to `wallets.controller.ts`:**
```typescript
// Step 1: Create Razorpay order
@Post('topup/create-order')
@UseGuards(JwtAuthGuard)
async createTopupOrder(@Body() body: { amount: number }) {
  const order = await this.razorpayService.createOrder(body.amount);
  return order; // {id, amount, currency}
}

// Step 2: Verify payment signature and credit wallet
@Post('topup/verify')
@UseGuards(JwtAuthGuard)
async verifyTopup(@Request() req, @Body() body: { 
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
  amount: number;
}) {
  await this.razorpayService.verifyPayment(body);
  return this.walletsService.addFunds(req.user.sub, body.amount / 100); // paise to rupees
}
```

---

## 3. Book Services — Instant Help (Live Worker Engine)

### Intended Business Logic

```
Customer selects service category (Electrician, Driver, etc.)
  → Customer sets service location (GPS or manual)
  → Presence Check: Self / Someone Else (On-Site Contact form)
  → System searches for active, verified workers nearby
  → Push notification sent to matched workers (90-second window)
  → First worker to accept gets the job
  → Customer confirms worker
  → Background job: 7-min reminder to worker, 10-min GPS check
  → Worker arrives → taps "Arrived"
  → Arrival OTP sent to on-site contact's phone number
  → Worker enters OTP → status: ACTIVE, job begins
  → Worker finishes → taps "Finish"
  → Completion OTP sent to customer
  → Customer enters OTP → status: COMPLETED
  → Billing: max(actual_hours, 1) × hourly_rate
  → Rs.12 deducted from worker wallet
  → If first job: Rs.12 bonus credited
```

### What is implemented ✅
- `createBooking()` — creates booking, deducts wallet fee, schedules queue jobs ✅
- `verifyArrivalOtp()` — validates OTP, sets ACTIVE, records startedAt ✅
- `verifyCompletionOtp()` — validates OTP, sets COMPLETED, calculates billingHours ✅
- Both OTP endpoints in controller ✅
- `sevenMinuteReminder` queue job fires ✅
- `tenMinuteGpsCheck` queue job fires and checks Redis location ✅
- Auto-cancel on no movement + notifications ✅
- WebSocket gateway for real-time location ✅

### What is missing ❌

#### Issue 3.1 — `getMyBookings()` Returns Empty Array

**File:** `backend/src/bookings/bookings.controller.ts`

```typescript
@Get('my')
async getMyBookings() {
  return []; // HARDCODED EMPTY ARRAY
}
```

**Fix:**
```typescript
@Get('my')
@UseGuards(JwtAuthGuard)
async getMyBookings(@Request() req) {
  return this.bookingsService.getBookingsByUser(req.user.sub);
}
```

**Add to `bookings.service.ts`:**
```typescript
async getBookingsByUser(userId: string): Promise<Booking[]> {
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

---

#### Issue 3.2 — `sevenMinuteReminder` Processor Is a Stub

**File:** `backend/src/bookings/bookings.processor.ts`

The 7-minute reminder fires but does nothing — no push notification sent, no booking status check.

**Fix:**
```typescript
@Process('sevenMinuteReminder')
async handleSevenMinuteReminder(job: Job) {
  const { bookingId } = job.data;
  const booking = await this.bookingsService.getBookingById(bookingId);
  if (!booking) return;

  // Only remind if still waiting for worker to arrive
  if (booking.status !== BookingStatus.ACCEPTED) return;

  // Remind the worker
  if (booking.operator) {
    await this.notificationsService.sendToDevice({
      token: booking.operator.fcmToken, // needs fcmToken on user
      title: 'Reminder: Customer is waiting',
      body: 'Please confirm you are on your way. GPS check in 3 minutes.',
    });
  }
  return { status: 'Reminder sent' };
}
```

---

#### Issue 3.3 — Worker FCM Token Not Available in Processor

**File:** `backend/src/bookings/bookings.processor.ts`

The processor uses placeholder strings like `` `worker_${workerId}_token` `` instead of real FCM tokens. The `Booking` relation loads `operator` (User) but `User.fcmToken` may not be in the relation.

**Fix — ensure fcmToken is included in booking query:**
```typescript
async getBookingById(id: string): Promise<Booking | null> {
  return this.bookingsRepository.findOne({
    where: { id },
    relations: ['customer', 'operator'],
    select: {
      operator: { id: true, fcmToken: true, name: true },
      customer: { id: true, fcmToken: true, name: true },
    }
  });
}
```

Then in processor:
```typescript
// Replace placeholder token strings with:
await this.notificationsService.sendToDevice({
  token: booking.operator.fcmToken,  // real FCM token
  title: '...',
  body: '...',
});
```

---

#### Issue 3.4 — No Worker Search Endpoint (Nearest Active Workers)

**File:** Backend — endpoint missing

When a customer taps "Find Workers", the Flutter app has nowhere to call. There is no endpoint that returns active workers near a location for a given skill.

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
  // Basic implementation: return all active verified workers with matching skill
  // Production: use PostGIS ST_Distance for proper geo-filtering
  const all = await this.workersRepository.find({
    where: { isActive: true, verificationStatus: VerificationStatus.VERIFIED },
    relations: ['user'],
  });

  return all
    .filter(w => w.skills?.some(s => 
      s.toLowerCase().includes(skill.toLowerCase())
    ))
    .map(w => this.mapToDto(w));
}
```

---

#### Issue 3.5 — Booking Creation Has No `workerId` or `skill` in Controller

**File:** `backend/src/bookings/bookings.controller.ts`

The `create()` endpoint only accepts `workerId`, `scheduledAt`, and `amount`. It doesn't capture `skill`, `serviceLocation`, `onSiteContact`, or `type`.

**Fix:**
```typescript
@Post()
@UseGuards(JwtAuthGuard)
async create(@Request() req, @Body() body: {
  workerId: string;
  skill: string;
  serviceLocation: string;
  serviceLat: number;
  serviceLng: number;
  onSiteContact?: { name: string; relation: string; phone: string };
  scheduledAt: string;
  amount: number;
  type: BookingType;
}) {
  return this.bookingsService.createBooking({
    customer: { id: req.user.sub } as User,
    operator: { id: body.workerId } as User,
    skill: body.skill,
    serviceLocation: body.serviceLocation,
    serviceLat: body.serviceLat,
    serviceLng: body.serviceLng,
    onSiteContact: body.onSiteContact,
    scheduledAt: new Date(body.scheduledAt),
    amount: body.amount,
    type: body.type,
  });
}
```

---

## 4. Book Services — Plan Services

### Intended Business Logic

```
Customer selects event location (NOT GPS — where the EVENT is)
  → System filters all vendors by that location
  → Customer browses vendors (Hall, Catering, Decoration, Photography)
  → Customer opens vendor → sees photos, capacity, description
  → Customer taps "Check Availability" → 3-state calendar shown
    Green = Available, Yellow = Pending, Red = Booked
  → Customer selects date
  → Customer chooses Package or Custom
    Package: select package → Request Booking → status: REQUESTED
    Custom: fill event type, guest count, special needs → status: CUSTOM_REQUESTED
  → Vendor receives push notification
  → Vendor Approves: (Custom only) sends quote + notes
  → Customer confirms → status: CONFIRMED → calendar date blocked
  → Customer ↔ Vendor coordinate directly
```

### What is missing ❌

#### Issue 4.1 — No Vendor/Service Listing Endpoint

There is no endpoint to list vendors by service type and location. No `services/` or `vendors/` module exists.

**Minimum fix — add to `businesses.controller.ts`:**
```typescript
@Get('public')
async getPublicListings(
  @Query('type') type: string,
  @Query('location') location: string,
) {
  return this.businessesService.getVerifiedByTypeAndLocation(type, location);
}
```

**Add to `businesses.service.ts`:**
```typescript
async getVerifiedByTypeAndLocation(type: string, location: string): Promise<Business[]> {
  return this.businessRepo.find({
    where: { serviceType: type as any, location, status: 'VERIFIED' },
    order: { createdAt: 'DESC' },
  });
}
```

---

#### Issue 4.2 — No Calendar Endpoint for Vendors

**File:** Backend — missing

The Flutter `calendar_screen.dart` (which doesn't exist yet either) will need to call a calendar endpoint to know which dates are blocked.

**Fix — add to `businesses.controller.ts`:**
```typescript
@Get(':id/calendar')
async getCalendar(@Param('id') id: string) {
  return this.businessesService.getCalendar(id);
}
```

**Add to `businesses.service.ts`:**
```typescript
async getCalendar(businessId: string): Promise<{ blocked: string[]; pending: string[] }> {
  const business = await this.getById(businessId);
  // blocked = confirmed bookings + offline days
  // pending = REQUESTED bookings not yet confirmed
  // TODO: join with bookings table filtered by vendorId
  return {
    blocked: business.offlineDays || [],
    pending: [],
  };
}
```

---

#### Issue 4.3 — `calendar_screen.dart` Entirely Missing in Flutter

**File:** `lib/features/booking/calendar_screen.dart` — does not exist

This screen is required for both Plan Services and Rental. Without it there is no way to check availability or select a booking date.

**Must be created with:**
- Full month calendar widget
- 3-state colour coding per date (green/yellow/red)
- Tap a date → pass selected date back to booking flow
- Fetch blocked/pending dates from API on load

---

#### Issue 4.4 — Vendor Approval/Rejection Flow Not Implemented

**File:** `backend/src/bookings/bookings.service.ts`

There is no method for a vendor to approve or reject a booking request, or to respond with a quote on custom requests.

**Fix — add to `bookings.service.ts`:**
```typescript
async vendorRespond(
  bookingId: string,
  action: 'approve' | 'reject',
  quote?: number,
  note?: string,
): Promise<Booking> {
  const booking = await this.bookingsRepository.findOne({ where: { id: bookingId } });
  if (!booking) throw new NotFoundException('Booking not found');

  if (action === 'approve') {
    booking.status = BookingStatus.ACCEPTED;
    if (quote) booking.quote = quote;
    if (note) booking.vendorNote = note;
  } else {
    booking.status = BookingStatus.REJECTED;
  }
  return this.bookingsRepository.save(booking);
}
```

---

## 5. Rental Service

### Intended Business Logic

```
Rental belongs inside Plan Services (NOT Instant Help)
Customer selects rental delivery location
  → Browses item categories (Generator, Mic Set, Cooler, etc.)
  → Opens item → sees photos, specs, hourly rate, minimum hours
  → Taps "Check Availability" → day-based calendar shown
  → Selects available date → sends rental request with optional note
  → Status: REQUESTED
  → Vendor approves or rejects
  → If approved: customer confirms → status: CONFIRMED
  → Entire day blocked in calendar
  → Billing: max(actual_hours, min_hours) × hourly_rate
  → No OTP involved — customer and vendor coordinate directly
```

### What is implemented ✅
- `RentalItem` entity ✅
- `RentalReservation` entity ✅
- `rentals.service.ts` with create/list/calendar basics ✅
- `rentals.controller.ts` with endpoints ✅

### What is missing ❌

#### Issue 5.1 — Min-Hour Billing Not Enforced

**File:** `backend/src/rentals/rentals.service.ts`

Billing calculation on rental completion does not enforce minimum hours.

**Fix:**
```typescript
calculateBilling(actualHours: number, minHours: number, hourlyRate: number): number {
  const billableHours = Math.max(actualHours, minHours);
  return billableHours * hourlyRate;
}
```

---

#### Issue 5.2 — Entire Day Not Blocked on Rental Confirmation

**File:** `backend/src/rentals/rentals.service.ts`

When a rental is confirmed, only the reservation record is saved. The item's calendar is not blocked for that day, so another customer could still book the same item on the same day.

**Fix — on confirmation, add the date to `rental_item.blockedDates`:**
```typescript
async confirmReservation(reservationId: string): Promise<RentalReservation> {
  const reservation = await this.reservationRepo.findOne({
    where: { id: reservationId },
    relations: ['item'],
  });
  reservation.status = 'CONFIRMED';
  await this.reservationRepo.save(reservation);

  // Block the entire day on the item's calendar
  const item = reservation.item;
  const days = item.blockedDates || [];
  const dateStr = reservation.date.toISOString().split('T')[0];
  if (!days.includes(dateStr)) {
    days.push(dateStr);
    item.blockedDates = days;
    await this.rentalItemRepo.save(item);
  }
  return reservation;
}
```

---

## 6. Find a Job

### Intended Business Logic

```
User opens Find a Job
  → Creates Talent Profile (education, skills, experience, status, preferred roles, preferred locations)
  → Enables Job Alerts toggle
  → When a new job is posted matching their skills + location: push notification sent
  → Talent taps alert → sees job detail → taps Apply
  → Status: APPLIED
  → Employer (HR) views applicants
  → HR moves talent: APPLIED → INTERVIEW
  → If talent accepts interview but doesn't attend → no-show count increments → search rank drops
  → HR moves: INTERVIEW → SELECTED | REJECTED
  → Each state change triggers push notification to talent
```

### What is implemented ✅
- `TalentProfile` entity ✅
- `getProfile()` — create-if-not-exists ✅
- `updateProfile()` ✅
- `toggleAlerts()` ✅
- `JobPost` entity ✅
- `applyForJob()` with duplicate-apply guard ✅
- `updateApplicationStatus()` ✅
- `getRecommendedTalent()` with skill-scoring algorithm ✅

### What is missing ❌

#### Issue 6.1 — No Talent Notification on Job Post

**File:** `backend/src/hiring/hiring.service.ts`

`createJobPost()` saves the job but never notifies matching talent. The talent matching algorithm exists in `getRecommendedTalent()` but is never called at job creation time.

**Fix — add talent notification to `createJobPost()`:**
```typescript
async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
  const job = this.jobPostRepo.create({ ...data, employer: { id: employerId } as User });
  const savedJob = await this.jobPostRepo.save(job);

  // Notify matching talent asynchronously (don't block response)
  this.notifyMatchingTalent(savedJob).catch(err =>
    console.error('Talent notification failed:', err)
  );

  return savedJob;
}

private async notifyMatchingTalent(job: JobPost): Promise<void> {
  const matched = await this.getRecommendedTalent(job.id);
  for (const profile of matched) {
    if (profile.user?.fcmToken) {
      await this.notificationsService.sendToDevice({
        token: profile.user.fcmToken,
        title: `New job: ${job.title}`,
        body: `${job.location} — tap to apply`,
      });
    }
  }
}
```

---

#### Issue 6.2 — No-Show Count Not Linked to Search Ranking

**File:** `backend/src/talent/talent.service.ts`

`TalentProfile` has a `noShowCount` field but nothing increments it when a talent accepts an interview and doesn't attend. There is also no ranking penalty applied in search results.

**Fix — add no-show tracking:**
```typescript
async recordNoShow(talentUserId: string): Promise<void> {
  const profile = await this.getProfile(talentUserId);
  profile.noShowCount = (profile.noShowCount || 0) + 1;
  // Apply ranking penalty: reduce searchRank by 10 per no-show
  profile.searchRank = Math.max(0, (profile.searchRank || 100) - 10);
  await this.talentRepo.save(profile);
}
```

**This must be called from `hiring.service.ts` when HR marks an application:**
```typescript
// In updateApplicationStatus():
if (newStatus === ApplicationStatus.NO_SHOW) {
  await this.talentService.recordNoShow(app.applicant.id);
}
```

---

#### Issue 6.3 — Application State Change Does Not Send Push Notification

**File:** `backend/src/hiring/hiring.service.ts`

`updateApplicationStatus()` changes the status in DB but never notifies the talent.

**Fix:**
```typescript
async updateApplicationStatus(applicationId: string, newStatus: ApplicationStatus) {
  const app = await this.applicationRepo.findOne({
    where: { id: applicationId },
    relations: ['jobPost', 'applicant'],
  });
  if (!app) throw new NotFoundException('Application not found');
  app.status = newStatus;
  await this.applicationRepo.save(app);

  // Notify talent of status change
  const messages: Record<ApplicationStatus, string> = {
    [ApplicationStatus.INTERVIEW]: 'You have been shortlisted for an interview!',
    [ApplicationStatus.SELECTED]: 'Congratulations! You have been selected.',
    [ApplicationStatus.REJECTED]: 'Your application was not selected this time.',
    [ApplicationStatus.APPLIED]: '',
  };
  const msg = messages[newStatus];
  if (msg && app.applicant?.fcmToken) {
    await this.notificationsService.sendToDevice({
      token: app.applicant.fcmToken,
      title: app.jobPost.title,
      body: msg,
    });
  }
  return app;
}
```

---

#### Issue 6.4 — `post_job_screen.dart` Is Still a Stub

**File:** `lib/features/jobs/post_job_screen.dart`

Shows `Text('Post Job form goes here')`. No form, no API call.

**Must include:**
- Job Title (TextField)
- Skills Required (multi-select chips from master list)
- Experience level (DropdownButton: Fresher / 1-2yr / 3-5yr / 5+yr)
- Salary (TextField with number keyboard)
- Location (city picker)
- Job Type (Full Time / Part Time / Contract)
- Description (multi-line TextField)
- Submit → `POST /hiring/jobs`

---

## 7. Earn by Working

### Intended Business Logic

```
User opens Earn by Working
  → Adds skills (multi-select from master list)
  → Each skill requires document upload + admin verification
  → Sets hourly rate (within system range, max 2 updates/day)
  → Sets weekly availability schedule
  → Toggles Go-Live:
      If first job: no wallet check
      If not first job: wallet balance must be ≥ Rs.12
  → System shows worker on customer's nearby map
  → Customer finds and requests worker
  → Worker receives push notification (90-second window)
  → Worker accepts → customer confirms
  → 7-min reminder, 10-min GPS check run in background
  → Arrival OTP → work begins
  → Completion OTP → billing calculated
  → Rs.12 deducted from wallet
  → First job: Rs.12 bonus credited
  → Strike system: 3 strikes = suspension
```

### What is implemented ✅
- `WorkerProfile` entity with all fields ✅
- `getAll()` — queries DB (not hardcoded anymore) ✅
- `toggleGoLive()` — with 2/day rate limit on toggle ✅
- `mapToDto()` helper for Flutter model compatibility ✅

### What is missing ❌

#### Issue 7.1 — `workers.controller.ts` Has No Go-Live or Rate-Update Endpoints

**File:** `backend/src/workers/workers.controller.ts`

The controller only has `GET /workers` and `GET /workers/:id`. No endpoint exists for go-live toggle or rate update.

**Fix — add to controller:**
```typescript
@Patch('toggle-live')
@UseGuards(JwtAuthGuard)
async toggleLive(@Request() req) {
  return this.workersService.toggleGoLive(req.user.sub);
}

@Patch('rate')
@UseGuards(JwtAuthGuard)
async updateRate(@Request() req, @Body() body: { hourlyRate: number }) {
  return this.workersService.updateHourlyRate(req.user.sub, body.hourlyRate);
}
```

---

#### Issue 7.2 — `updateHourlyRate()` Method Does Not Exist

**File:** `backend/src/workers/workers.service.ts`

Only `toggleGoLive()` has a rate-limit pattern. A similar method for hourly rate update with its own 2/day limit needs to be added.

**Fix:**
```typescript
async updateHourlyRate(userId: string, newRate: number): Promise<WorkerDto> {
  const profile = await this.workersRepository.findOne({
    where: { user: { id: userId } },
    relations: ['user'],
  });
  if (!profile) throw new NotFoundException('Worker profile not found');

  const todayStr = new Date().toISOString().split('T')[0];

  if (profile.rateUpdateDate !== todayStr) {
    profile.rateUpdateDate = todayStr;
    profile.rateUpdateCountToday = 0;
  }

  if (profile.rateUpdateCountToday >= 2) {
    throw new BadRequestException(
      'Hourly rate can only be updated twice per day.'
    );
  }

  profile.hourlyRate = newRate;
  profile.rateUpdateCountToday += 1;
  await this.workersRepository.save(profile);
  return this.mapToDto(profile);
}
```

---

#### Issue 7.3 — Worker Profile Creation Endpoint Missing

**File:** Backend — `POST /workers/register` does not exist

`register_pro_screen.dart` submits skill registration but there is no endpoint to receive it.

**Fix — add to `workers.controller.ts`:**
```typescript
@Post('register')
@UseGuards(JwtAuthGuard)
async register(@Request() req, @Body() body: {
  skills: string[];
  hourlyRate: number;
  bio?: string;
}) {
  return this.workersService.createProfile(req.user.sub, body);
}
```

**Add to `workers.service.ts`:**
```typescript
async createProfile(userId: string, data: {
  skills: string[];
  hourlyRate: number;
  bio?: string;
}): Promise<WorkerProfile> {
  const existing = await this.workersRepository.findOne({
    where: { user: { id: userId } },
  });
  if (existing) throw new BadRequestException('Worker profile already exists');

  const profile = this.workersRepository.create({
    user: { id: userId } as User,
    skills: data.skills,
    hourlyRate: data.hourlyRate,
    bio: data.bio,
    verificationStatus: VerificationStatus.PENDING,
    isActive: false,
    isFirstJobDone: false,
  });
  return this.workersRepository.save(profile);
}
```

---

#### Issue 7.4 — Strike Count Never Incremented

**File:** `backend/src/bookings/bookings.processor.ts`

When a booking is auto-cancelled due to no GPS movement, the code sets booking status to CANCELLED but never increments `workerProfile.strikeCount`. A worker could ignore bookings indefinitely with no consequence.

**Fix — add to `bookings.processor.ts`:**
```typescript
// After auto-cancel:
await this.bookingsService.updateStatus(bookingId, BookingStatus.CANCELLED);

// Add strike to worker
await this.workerProfileService.addStrike(workerId);
```

**Add to `workers.service.ts`:**
```typescript
async addStrike(userId: string): Promise<void> {
  const profile = await this.workersRepository.findOne({
    where: { user: { id: userId } },
  });
  if (!profile) return;

  profile.strikeCount = (profile.strikeCount || 0) + 1;

  // Suspend after 3 strikes
  if (profile.strikeCount >= 3) {
    profile.isActive = false;
    profile.verificationStatus = VerificationStatus.SUSPENDED;
  }

  await this.workersRepository.save(profile);
}
```

---

## 8. List My Business

### Intended Business Logic

```
User opens List My Business
  → Selects business category: Service / Hiring / Rental
  → Fills details (name, location, description, documents)
  → Status: PENDING (admin must verify)
  → After admin approval: VERIFIED
  → User lands on Business Unit Dashboard (card grid)
  → Each card = one business unit
  → Tapping a card opens:
      Calendar management (add offline days, view bookings)
      Edit details
      Add/remove operators (managers/HR)
      Ownership transfer (OTP from both parties, 24-hour hold)
      Delete unit
```

### What is implemented ✅
- `Business` entity ✅
- `create()` ✅
- `getMyBusinesses()` ✅
- `addOperator()` — stores operator IDs in array ✅
- `addOfflineDay()` ✅

### What is missing ❌

#### Issue 8.1 — Ownership Transfer Not Implemented

**File:** `backend/src/businesses/businesses.service.ts`

The 24-hour OTP ownership transfer is a core feature with no implementation.

**Fix — add complete transfer flow:**
```typescript
async initiateTransfer(businessId: string, newOwnerId: string): Promise<{ message: string }> {
  const business = await this.getById(businessId);
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  
  // Store transfer intent in Redis: 48hr window
  await this.redisService.set(
    `transfer:${businessId}`,
    JSON.stringify({ newOwnerId, otp, initiatedAt: new Date().toISOString() }),
    48 * 60 * 60
  );

  // TODO: Send OTP to new owner's phone
  console.log(`[DEV] Transfer OTP for business ${businessId}: ${otp}`);
  return { message: 'Transfer initiated. OTP sent to new owner.' };
}

async confirmTransfer(businessId: string, otp: string): Promise<Business> {
  const data = await this.redisService.get(`transfer:${businessId}`);
  if (!data) throw new BadRequestException('No pending transfer or transfer expired');

  const { newOwnerId, otp: storedOtp } = JSON.parse(data);
  if (storedOtp !== otp) throw new BadRequestException('Invalid OTP');

  const business = await this.getById(businessId);
  business.owner = { id: newOwnerId } as User;
  await this.businessRepo.save(business);
  await this.redisService.del(`transfer:${businessId}`);

  return business;
}
```

---

#### Issue 8.2 — Business Unit Dashboard Screen Missing in Flutter

**File:** `lib/features/business/business_unit_dashboard.dart` — does not exist

After a business is listed and verified, the user has nowhere to go. No card grid exists to manage units.

**Must be created with:**
- `GET /businesses/my` → display cards for each business
- Each card: name, type badge, status badge (Verified/Pending)
- Tap card → management options (calendar, operators, transfer, delete)
- FAB → add new business unit

---

#### Issue 8.3 — No Admin Verification Endpoint

**File:** Backend — endpoint missing

Businesses are created with `status: PENDING` but there is no admin endpoint to approve or reject them.

**Fix — add to `businesses.controller.ts`:**
```typescript
@Patch(':id/verify')
// @UseGuards(JwtAuthGuard, AdminGuard)  // Restrict to admins only
async verify(@Param('id') id: string, @Body() body: { status: 'VERIFIED' | 'REJECTED' }) {
  return this.businessesService.updateStatus(id, body.status);
}
```

---

## 9. Push Notifications (FCM)

### Intended Business Logic

Every status change in the system must trigger a push notification to the relevant party.

| Event | Sender | Recipient |
|---|---|---|
| New booking request | Booking creation | Vendor / Worker |
| Booking approved | Vendor action | Customer |
| Booking rejected | Vendor action | Customer |
| Worker accepted job | Worker action | Customer |
| 7-min reminder | Bull job | Worker |
| Auto-cancel (no movement) | Bull job | Customer + Worker |
| Arrival OTP | Worker arrived action | On-site contact |
| Completion OTP | Worker finish action | Customer |
| New job posted (alert) | Job creation | Matched talent |
| Application status change | HR action | Talent |
| Wallet balance low | Deduction | Worker |
| Business verified | Admin action | Business owner |

### What is implemented ✅
- `NotificationsService` structure exists ✅
- `sendToDevice()` method exists ✅

### What is missing ❌

#### Issue 9.1 — Firebase Admin SDK Not Initialized

**File:** `backend/src/main.ts`

The backend starts without initializing Firebase Admin SDK. `sendToDevice()` will fail silently or throw.

**Fix — add to `main.ts`:**
```typescript
import * as admin from 'firebase-admin';

async function bootstrap() {
  // Initialize Firebase Admin BEFORE creating the app
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });

  const app = await NestFactory.create(AppModule);
  // ...
}
```

---

#### Issue 9.2 — `sendToDevice()` Not Wired to Any Service Event

**File:** `backend/src/notifications/notifications.service.ts`

The service is never injected into or called from `BookingsService`, `HiringService`, `WalletsService`, or `BusinessesService`. All notification triggers are missing.

**Fix — inject `NotificationsService` into each service that needs it:**
```typescript
// In bookings.service.ts constructor:
constructor(
  @InjectRepository(Booking) private bookingsRepository: Repository<Booking>,
  @InjectQueue('bookings') private bookingsQueue: Queue,
  private walletsService: WalletsService,
  private notificationsService: NotificationsService,  // ADD
) {}

// Then call after status change:
await this.notificationsService.sendToDevice({
  token: customer.fcmToken,
  title: 'Booking Confirmed',
  body: 'Your booking has been approved by the vendor.',
});
```

Also add `NotificationsModule` to the `imports` of `BookingsModule`, `HiringModule`, `BusinessesModule`.

---

## 10. WebSocket & Real-Time Location

### Intended Business Logic

```
Worker goes live → opens app → GPS location streamed to backend via WebSocket
Worker accepts a job → joins specific job room (job_{bookingId})
Customer opens live tracking → joins same job room
Worker's GPS updates → emitted only to that job room
Customer sees worker marker moving on Google Map
10-minute GPS check reads last location from Redis cache
If no location data or stale → auto-cancel
```

### What is implemented ✅
- WebSocket gateway connects/disconnects ✅
- `updateLocation` event received and emitted to job room ✅
- `joinJobRoom` event joins socket room ✅
- Location scoped to job room (not broadcast to everyone) ✅

### What is missing ❌

#### Issue 10.1 — Location Not Stored in Redis

**File:** `backend/src/worker-engine/worker.gateway.ts`

The gateway receives location updates and emits to the job room but never writes to Redis. The `tenMinuteGpsCheck` Bull job reads from Redis — if nothing is written, every GPS check will auto-cancel every booking.

**Fix:**
```typescript
@SubscribeMessage('updateLocation')
async handleLocationUpdate(
  @MessageBody() data: { userId: string; lat: number; lng: number; jobId?: string },
  @ConnectedSocket() client: Socket,
) {
  // Store in Redis for GPS check (10-minute TTL)
  await this.redisService.setWorkerLocation(data.userId, {
    lat: data.lat,
    lng: data.lng,
    timestamp: new Date().toISOString(),
  });

  // Emit to job room
  if (data.jobId) {
    this.server.to(`job_${data.jobId}`).emit('locationUpdated', {
      userId: data.userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    });
  }
}
```

**Add `RedisService` to `WorkerEngineModule` imports.**

---

#### Issue 10.2 — WebSocket Gateway Has No JWT Authentication

**File:** `backend/src/worker-engine/worker.gateway.ts`

Any client can connect to the WebSocket and join any job room, allowing eavesdropping on other customers' live tracking.

**Fix:**
```typescript
import { JwtService } from '@nestjs/jwt';

export class WorkerGateway implements OnGatewayConnection {
  constructor(private jwtService: JwtService) {}

  handleConnection(client: Socket) {
    const token = client.handshake.auth?.token;
    try {
      const payload = this.jwtService.verify(token);
      client.data.userId = payload.sub;
      client.data.role = payload.role;
    } catch {
      console.log(`Unauthorized socket connection. Disconnecting ${client.id}`);
      client.disconnect();
    }
  }
}
```

---

#### Issue 10.3 — `worker_map_screen.dart` Does Not Join Job Room

**File:** `lib/features/map/worker_map_screen.dart`

The screen listens for `locationUpdated` events but never calls `joinJobRoom` first. After the server-side fix, no events will arrive unless the room is joined.

**Fix — call before listening:**
```dart
@override
void initState() {
  super.initState();
  final socket = ref.read(socketServiceProvider);
  socket.joinJobRoom(widget.jobId);        // JOIN ROOM FIRST
  socket.onLocationUpdated((data) {        // THEN LISTEN
    setState(() {
      _workerPosition = LatLng(
        data['lat'] as double,
        data['lng'] as double,
      );
    });
  });
}
```

---

## 11. Background Jobs (Bull Queue)

### What is implemented ✅
- `sevenMinuteReminder` fires after 7 minutes ✅
- `tenMinuteGpsCheck` fires after 10 minutes ✅
- GPS check reads from Redis, auto-cancels on no movement ✅
- Notifications sent on auto-cancel ✅

### What is missing ❌

#### Issue 11.1 — `sevenMinuteReminder` Processor Is a Stub

**File:** `backend/src/bookings/bookings.processor.ts`

Logs to console only. No push notification sent to worker.

**Fix — shown in Issue 3.2 above.**

---

#### Issue 11.2 — No Midnight Reset for Rate Limits

**File:** Backend — no scheduled task

`rateUpdateCountToday` and `goLiveToggleCountToday` reset when a request comes in on a new day, but this only works if the worker uses the app. If they log in after midnight, the counter resets correctly. However no server-side scheduled job purges these.

**For production — add a scheduled task in a NestJS `@Cron` decorator:**
```typescript
import { Cron, CronExpression } from '@nestjs/schedule';

@Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
async resetDailyRateLimits() {
  await this.workersRepository.update(
    {},
    { rateUpdateCountToday: 0, goLiveToggleCountToday: 0 }
  );
}
```

Install `@nestjs/schedule` and add `ScheduleModule.forRoot()` to `app.module.ts`.

---

## 12. Missing Issues Master Checklist

### 🔴 Critical — Breaks Core Functionality

- [ ] **OTP not stored in Redis** — any 6-digit number passes verification (`auth.service.ts`)
- [ ] **`getMyBookings()` returns empty array** — customers can't see their bookings (`bookings.controller.ts`)
- [ ] **FCM token never sent to backend** — push notifications can't reach any device (`otp_screen.dart`)
- [ ] **Firebase not initialized in Flutter** — `main.dart` has comment, no actual init
- [ ] **Firebase Admin SDK not initialized** — backend `main.ts` missing admin.initializeApp()
- [ ] **Location not stored in Redis** — GPS check always cancels every booking (`worker.gateway.ts`)
- [ ] **Worker map screen doesn't join job room** — no location updates received (`worker_map_screen.dart`)
- [ ] **No worker search endpoint** — Flutter can't find nearby workers (`workers.controller.ts`)
- [ ] **`sevenMinuteReminder` is a stub** — no push sent to worker at 7 minutes (`bookings.processor.ts`)

### 🟠 High — Feature Incomplete

- [ ] **Wallet balance not checked before go-live** (`workers.service.ts`)
- [ ] **Rs.12 first-job bonus not credited** (`bookings.service.ts`)
- [ ] **Strike count never incremented** on GPS check failure (`bookings.processor.ts`)
- [ ] **`updateHourlyRate()` method missing** (`workers.service.ts`)
- [ ] **No go-live toggle endpoint** (`workers.controller.ts`)
- [ ] **No worker registration endpoint** (`workers.controller.ts`)
- [ ] **Talent notification on job post missing** (`hiring.service.ts`)
- [ ] **Application status change has no push notification** (`hiring.service.ts`)
- [ ] **No-show count not linked to search ranking** (`talent.service.ts`)
- [ ] **Vendor approval/rejection flow missing** (`bookings.service.ts`)
- [ ] **No vendor listing endpoint** (`businesses.controller.ts`)
- [ ] **No calendar endpoint for vendors** (`businesses.controller.ts`)
- [ ] **Ownership transfer not implemented** (`businesses.service.ts`)
- [ ] **No admin verification endpoint** (`businesses.controller.ts`)
- [ ] **No Razorpay wallet top-up endpoint** (`wallets.controller.ts`)
- [ ] **NotificationsService not wired to any service event** (all service files)
- [ ] **WebSocket gateway has no JWT auth** (`worker.gateway.ts`)
- [ ] **Entire day not blocked on rental confirmation** (`rentals.service.ts`)
- [ ] **Min-hour billing not enforced in rental** (`rentals.service.ts`)
- [ ] **Booking creation missing required fields** — no skill, location, onSiteContact (`bookings.controller.ts`)

### 🟡 Medium — Screen Missing or Stub

- [ ] **`calendar_screen.dart` entirely missing** — Plan Services + Rental both need it
- [ ] **`post_job_screen.dart` is a stub** — shows placeholder text only
- [ ] **Business unit dashboard screen missing** — after business listed, nowhere to manage
- [ ] **Hiring pipeline Kanban screen missing** — HR cannot manage candidates
- [ ] **Home screen not redesigned** — still shows generic category grid instead of 4 intent cards

### 🔵 Repository / Data Layer

- [ ] **`booking_repository.dart`** missing: `markArrived`, `markComplete`, `verifyArrivalOtp`, `verifyCompletionOtp`, `getCalendarDates`, `vendorRespond`
- [ ] **`business_repository.dart`** — created but methods may be stubs, no ownership transfer method
- [ ] **`hiring_repository.dart`** — created but verify all methods match new backend endpoints

### 🟢 Production Readiness

- [ ] **No input validation (DTOs + ValidationPipe)** across all backend controllers
- [ ] **No JWT guards** on any controller
- [ ] **`synchronize: true`** in TypeORM — must switch to migrations before production
- [ ] **No rate limiting** on OTP endpoint — brute-force vulnerable
- [ ] **No pagination** on any list endpoint
- [ ] **No global error handler** — stack traces leak to clients
- [ ] **SMS not integrated** — OTP only logged to console
- [ ] **No `.env.example`** file
- [ ] **No unit tests** written for any module
- [ ] **Midnight rate-limit reset cron** not scheduled

---

*Gixbee v1.0.0 — April 2026*
