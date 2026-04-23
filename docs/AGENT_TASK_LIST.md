# Gixbee — Agent Task List: Security, Memory & Performance Fixes

> Generated: April 2026
> Based on full senior developer code review of all backend source files.
> Priority order: work top to bottom. Do not skip steps.
> Every fix includes the exact file, the exact problem, and the exact replacement code.

---

## HOW TO USE THIS FILE

Read each task fully before making any change. Each task has:
- **File** — exact path to edit
- **Problem** — why it is broken
- **Current code** — the broken code (find this exactly)
- **Fix** — the replacement code to write

Do not change anything outside the specified files. After each task, run `npm run build` to confirm no TypeScript errors before moving to the next task.

---

## TASK GROUP 1 — CRITICAL SECURITY FIXES
> These must be done before any other work. They are active security holes.

---

### TASK 1.1 — Remove hardcoded admin credentials

**File:** `backend/src/auth/auth.service.ts`

**Problem:** The `adminLogin()` method compares username/password against the literal strings `'admin'` and `'admin'`. This is committed to source control. Anyone who discovers the endpoint gets a JWT with `UserRole.ADMIN` access.

**Find this code and DELETE the entire `adminLogin` method:**
```typescript
async adminLogin(username: string, password: string): Promise<{ accessToken: string }> {
  // Scaffold explicitly for the Super Admin panel Web UI
  if (username !== 'admin' || password !== 'admin') {
    throw new UnauthorizedException('Invalid admin credentials');
  }

  // Usually, you'd mint the token against a real DB admin user ID.
  // For scaffolding, we provide a valid dummy sub that allows bypass, mapped to the ADMIN role.
  const payload = { sub: 'admin-scaffold-001', role: UserRole.ADMIN, phoneNumber: 'admin' };
  return {
    accessToken: await this.jwtService.signAsync(payload),
  };
}
```

**Replace with this secure version:**
```typescript
async adminLogin(username: string, password: string): Promise<{ accessToken: string }> {
  const user = await this.usersRepository.findOne({
    where: { phoneNumber: username, role: UserRole.ADMIN },
  });
  if (!user || !user.passwordHash) {
    throw new UnauthorizedException('Invalid credentials');
  }
  const bcrypt = await import('bcrypt');
  const isValid = await bcrypt.compare(password, user.passwordHash);
  if (!isValid) {
    throw new UnauthorizedException('Invalid credentials');
  }
  const payload = { sub: user.id, role: user.role, phoneNumber: user.phoneNumber };
  return { accessToken: await this.jwtService.signAsync(payload) };
}
```

**Also install bcrypt if not already installed:**
```bash
cd backend && npm install bcrypt && npm install --save-dev @types/bcrypt
```

**Also add `passwordHash` field to the User entity** (`backend/src/users/user.entity.ts`):
```typescript
@Column({ nullable: true, select: false })
passwordHash: string;
```

---

### TASK 1.2 — Remove hardcoded dev bypass phone number

**File:** `backend/src/auth/auth.service.ts`

**Problem:** The `loginWithFirebase()` method contains a dev bypass that assigns a hardcoded Indian phone number `+919605956941` as a master account. If `NODE_ENV` is not set correctly in staging, anyone sending `'mock-token-bypass'` as the token gets admin-equivalent access to this account.

**Find this entire block and DELETE it:**
```typescript
// --- DEV BYPASS START ---
const isDev = this.configService.get('NODE_ENV') === 'development';
const isConfigMissing = !this.configService.get('FIREBASE_PROJECT_ID') || 
                        !this.configService.get('FIREBASE_CLIENT_EMAIL') || 
                        !this.configService.get('FIREBASE_PRIVATE_KEY');

if (isDev && (isConfigMissing || idToken === 'mock-token-bypass')) {
  console.warn('[AUTH] [DEV BYPASS] Bypassing Firebase token verification due to missing credentials');
  // In bypass mode, if it's a real token, we can't decode it, so we fallback to a test user
  // If the idToken contains the phone (e.g. from a previous local storage), we'd use it.
  // For now, we'll try to extract the last 10 digits as a phone number if the token looks like one
  phoneNumber = idToken.length >= 10 && idToken.startsWith('+') ? idToken : '+919605956941'; 
} else {
  // 1. Verify the ID Token with Firebase Admin SDK
  const decodedToken = await this.firebaseAdmin.auth().verifyIdToken(idToken);
  phoneNumber = decodedToken.phone_number;
}
// --- DEV BYPASS END ---
```

**Replace with just this:**
```typescript
// Verify the ID Token with Firebase Admin SDK
const decodedToken = await this.firebaseAdmin.auth().verifyIdToken(idToken);
phoneNumber = decodedToken.phone_number;
```

---

### TASK 1.3 — Replace Math.random() OTPs with cryptographic random

**File:** `backend/src/auth/auth.service.ts`

**Problem:** `Math.random()` is not cryptographically secure. OTP values are predictable.

**Find:**
```typescript
const otp = Math.floor(100000 + Math.random() * 900000).toString();
```

**Replace with:**
```typescript
const { randomInt } = await import('crypto');
const otp = randomInt(100000, 999999).toString();
```

---

**File:** `backend/src/bookings/bookings.service.ts`

**Problem:** 4-digit OTPs generated with `Math.random()`. 4 digits is also too short — only 9,000 combinations, easily brute-forced within a 10-minute window.

**Find:**
```typescript
private generateOtp(): string {
  return Math.floor(1000 + Math.random() * 9000).toString();
}
```

**Replace with:**
```typescript
private async generateOtp(): Promise<string> {
  const { randomInt } = await import('crypto');
  return randomInt(100000, 999999).toString();
}
```

**Then update every call to `generateOtp()` in the same file to await it:**
```typescript
// Find:
const arrivalOtp = this.generateOtp();
const completionOtp = this.generateOtp();

// Replace with:
const arrivalOtp = await this.generateOtp();
const completionOtp = await this.generateOtp();
```

---

### TASK 1.4 — Fix WebSocket gateway: use JWT identity for location writes

**File:** `backend/src/worker-engine/worker.gateway.ts`

**Problem:** `handleLocationUpdate` reads `data.userId` from the socket message body. Any authenticated user can send `{ userId: 'victim-worker-id' }` and poison another worker's Redis location. The GPS check will then read the fake location.

**Find the `handleLocationUpdate` method and replace the entire method:**
```typescript
// FIND THIS:
@SubscribeMessage('updateLocation')
async handleLocationUpdate(
  @MessageBody() data: { userId: string; lat: number; lng: number; jobId?: string },
  @ConnectedSocket() client: Socket,
) {
  // 1. Persist to Redis so the background health-check (10-minute rule) can see it
  await this.redisService.updateWorkerLocation(data.userId, data.lat, data.lng);

  // 2. If a jobId is provided, only broadcast to that job's room
  if (data.jobId) {
    this.server.to(`job_${data.jobId}`).emit('locationUpdated', {
      userId: data.userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    });
  } else {
    // Fallback: emit only back to the sender
    client.emit('locationUpdated', {
      userId: data.userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    });
  }
}
```

**Replace with:**
```typescript
@SubscribeMessage('updateLocation')
async handleLocationUpdate(
  @MessageBody() data: { lat: number; lng: number; jobId?: string },
  @ConnectedSocket() client: Socket,
) {
  // Use the verified JWT identity — never trust client-supplied userId
  const userId = client.data.userId as string;
  if (!userId) {
    client.disconnect(true);
    return;
  }

  // 1. Persist to Redis using verified identity
  await this.redisService.updateWorkerLocation(userId, data.lat, data.lng);

  // 2. If a jobId is provided, only broadcast to that job's room
  if (data.jobId) {
    this.server.to(`job_${data.jobId}`).emit('locationUpdated', {
      userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    });
  } else {
    client.emit('locationUpdated', {
      userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    });
  }
}
```

---

### TASK 1.5 — Add JWT verification to WebSocket handleConnection

**File:** `backend/src/worker-engine/worker.gateway.ts`

**Problem:** `@UseGuards(JwtAuthGuard)` on a WebSocket class does NOT protect `handleConnection`. Unauthenticated clients connect freely and can spam the gateway.

**Add `JwtService` to the constructor and fix `handleConnection`:**

**Find the constructor:**
```typescript
constructor(private readonly redisService: RedisService) {}
```

**Replace with:**
```typescript
constructor(
  private readonly redisService: RedisService,
  private readonly jwtService: JwtService,
) {}
```

**Find `handleConnection`:**
```typescript
handleConnection(client: Socket) {
  console.log(`Client connected: ${client.id}`);
}
```

**Replace with:**
```typescript
handleConnection(client: Socket) {
  const token =
    client.handshake.auth?.token ||
    client.handshake.headers?.authorization?.split(' ')[1];

  if (!token) {
    client.disconnect(true);
    return;
  }

  try {
    const payload = this.jwtService.verify(token) as { sub: string; role: string };
    client.data.userId = payload.sub;
    client.data.role = payload.role;
    this.logger.log(`Client connected: ${client.id} | User: ${payload.sub}`);
  } catch {
    this.logger.warn(`Unauthorized socket connection attempt: ${client.id}`);
    client.disconnect(true);
  }
}
```

**Add the import at the top of the file:**
```typescript
import { JwtService } from '@nestjs/jwt';
import { Logger } from '@nestjs/common';
```

**Add `private readonly logger = new Logger(WorkerGateway.name);` as a class property.**

**Add `JwtService` to `WorkerEngineModule` imports** (`backend/src/worker-engine/worker-engine.module.ts`):
```typescript
import { JwtModule } from '@nestjs/jwt';
// Add JwtModule to the module imports array
```

---

## TASK GROUP 2 — CRITICAL RACE CONDITIONS
> These cause data corruption under concurrent load (multiple users at same time).

---

### TASK 2.1 — Make wallet deduction atomic (prevent double-spend)

**File:** `backend/src/wallets/wallets.service.ts`

**Problem:** Two simultaneous booking acceptances both read `walletBalance = 12`, both pass the balance check, both deduct — leaving the balance at `-12`. This is a classic read-modify-write race condition.

**Add `DataSource` to the constructor:**
```typescript
// Add this import at the top:
import { DataSource } from 'typeorm';

// Find the constructor:
constructor(
  @InjectRepository(User)
  private usersRepository: Repository<User>,
  @InjectRepository(WalletTransaction)
  private transactionsRepository: Repository<WalletTransaction>,
) {}

// Replace with:
constructor(
  @InjectRepository(User)
  private usersRepository: Repository<User>,
  @InjectRepository(WalletTransaction)
  private transactionsRepository: Repository<WalletTransaction>,
  private dataSource: DataSource,
) {}
```

**Find the entire `deductBookingFee` method and replace it:**
```typescript
// FIND:
async deductBookingFee(userId: string): Promise<void> {
  const user = await this.usersRepository.findOne({ where: { id: userId } });
  if (!user) throw new BadRequestException('User not found');

  const fee = 12;
  if (user.walletBalance < fee) {
    throw new BadRequestException('Insufficient wallet balance');
  }

  user.walletBalance -= fee;
  await this.usersRepository.save(user);

  const transaction = this.transactionsRepository.create({
    user,
    amount: fee,
    type: TransactionType.DEBIT,
    description: 'Gixbee Service Fee (Booking)',
  });
  await this.transactionsRepository.save(transaction);
}
```

**Replace with:**
```typescript
async deductBookingFee(userId: string): Promise<void> {
  await this.dataSource.transaction(async (em) => {
    // SELECT FOR UPDATE locks the row — prevents concurrent reads during this transaction
    const user = await em
      .getRepository(User)
      .createQueryBuilder('user')
      .setLock('pessimistic_write')
      .where('user.id = :id', { id: userId })
      .getOne();

    if (!user) throw new BadRequestException('User not found');

    const fee = 12;
    if (Number(user.walletBalance) < fee) {
      throw new BadRequestException(
        'Insufficient wallet balance. Please top up Rs.12 to continue.',
      );
    }

    user.walletBalance = Number(user.walletBalance) - fee;
    await em.save(User, user);

    const transaction = em.create(WalletTransaction, {
      user,
      amount: fee,
      type: TransactionType.DEBIT,
      description: 'Gixbee Service Fee (Booking)',
    });
    await em.save(WalletTransaction, transaction);
  });
}
```

---

### TASK 2.2 — Make OTP verification atomic (prevent double-submit)

**File:** `backend/src/bookings/bookings.service.ts`

**Problem:** If a customer double-taps "Verify", two requests simultaneously pass the OTP check and both transition the booking to ACTIVE. The second request overwrites `startedAt`, corrupting billing.

**Find the entire `verifyArrivalOtp` method:**
```typescript
async verifyArrivalOtp(bookingId: string, otp: string): Promise<{ message: string; status: string }> {
  const booking = await this.bookingsRepository.findOne({ where: { id: bookingId } });
  if (!booking) throw new NotFoundException('Booking not found');

  if (booking.arrivalOtp !== otp) {
    throw new BadRequestException('Invalid arrival OTP');
  }

  // Transition: ACCEPTED → ACTIVE (worker has arrived, job begins)
  booking.status = BookingStatus.ACTIVE;
  booking.startedAt = new Date();
  await this.bookingsRepository.save(booking);

  return { message: 'Arrival confirmed. Job is now active.', status: 'ACTIVE' };
}
```

**Replace with:**
```typescript
async verifyArrivalOtp(bookingId: string, otp: string): Promise<{ message: string; status: string }> {
  // Atomic conditional update: only succeeds if status is ACCEPTED AND otp matches
  const result = await this.bookingsRepository.update(
    {
      id: bookingId,
      status: BookingStatus.ACCEPTED,
      arrivalOtp: otp,
    },
    {
      status: BookingStatus.ACTIVE,
      startedAt: new Date(),
      arrivalOtp: '', // Invalidate OTP after use
    },
  );

  if (!result.affected || result.affected === 0) {
    // Could be wrong OTP, wrong status, or already started — check which
    const booking = await this.bookingsRepository.findOne({ where: { id: bookingId } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.status === BookingStatus.ACTIVE) {
      return { message: 'Arrival already confirmed.', status: 'ACTIVE' };
    }
    throw new BadRequestException('Invalid arrival OTP or booking is not in accepted state');
  }

  return { message: 'Arrival confirmed. Job is now active.', status: 'ACTIVE' };
}
```

**Apply the same pattern to `verifyCompletionOtp` — find and replace:**
```typescript
// In verifyCompletionOtp, find:
if (booking.completionOtp !== otp) {
  throw new BadRequestException('Invalid completion OTP');
}

if (booking.status !== BookingStatus.ACTIVE) {
  throw new BadRequestException('Job must be active to complete');
}

// ... billing calculation ...

booking.status = BookingStatus.COMPLETED;
booking.completedAt = new Date();
booking.billingHours = hoursWorked;
await this.bookingsRepository.save(booking);
```

**Replace the status check and save block with:**
```typescript
if (booking.completionOtp !== otp) {
  throw new BadRequestException('Invalid completion OTP');
}

if (booking.status !== BookingStatus.ACTIVE) {
  if (booking.status === BookingStatus.COMPLETED) {
    // Already completed — return the existing result idempotently
    return {
      message: 'Job already completed.',
      status: 'COMPLETED',
      billingHours: booking.billingHours || 1,
    };
  }
  throw new BadRequestException('Job must be active to complete');
}

// ... billing calculation stays the same ...

// Atomic update — only succeeds once
const updateResult = await this.bookingsRepository.update(
  { id: bookingId, status: BookingStatus.ACTIVE },
  { status: BookingStatus.COMPLETED, completedAt: new Date(), billingHours: hoursWorked, completionOtp: '' },
);

if (!updateResult.affected || updateResult.affected === 0) {
  throw new BadRequestException('Completion update failed — possible concurrent request');
}
```

---

### TASK 2.3 — Make GPS strike increment atomic

**File:** `backend/src/bookings/bookings.service.ts`

**Problem:** `booking.gpsStrikes += 1` followed by `save()` is a read-modify-write. Two Bull job retries can both read `gpsStrikes = 0`, both write `1`, and one strike is silently lost.

**Find inside the `addGpsStrike` method:**
```typescript
booking.gpsStrikes += 1;
await this.bookingsRepository.save(booking);
```

**Replace with:**
```typescript
// Atomic increment at DB level
await this.bookingsRepository.increment({ id: bookingId }, 'gpsStrikes', 1);
// Re-fetch the updated value
const updated = await this.bookingsRepository.findOne({
  where: { id: bookingId },
  relations: ['customer', 'operator'],
});
if (!updated) return;
// Reassign to booking variable for subsequent logic
Object.assign(booking, updated);
```

---

## TASK GROUP 3 — MEMORY & PERFORMANCE FIXES
> These cause slowdowns, high memory usage, and potential crashes under load.

---

### TASK 3.1 — Fix N+1 query problem in WorkersService.getAll()

**File:** `backend/src/workers/workers.service.ts`

**Problem:** For every worker and talent profile, `getAll()` fires one individual `getWorkerStatus()` database query. For 100 workers this is 102 separate DB queries per API call. This will saturate the DB connection pool.

**Find the entire `getAll()` method and replace it:**
```typescript
// FIND the entire getAll method:
async getAll(): Promise<WorkerDto[]> {
  // 1. Fetch from WorkerProfile
  const profiles = await this.workersRepository.find({
    relations: ['user'],
  });
  
  // 2. Fetch from TalentProfile
  const talentProfiles = await this.talentRepository.find({
    relations: ['user', 'professionalSkills'],
  });

  const allWorkerDtos: WorkerDto[] = [];

  for (const p of profiles) {
    const status = await this.getWorkerStatus(p.user?.id || p.id);
    allWorkerDtos.push(this.mapToDto(p, status));
  }

  for (const p of talentProfiles) {
    const status = await this.getWorkerStatus(p.user?.id || p.id);
    allWorkerDtos.push(this.mapTalentToDto(p, status));
  }

  // 3. Deduplicate by user ID
  const uniqueWorkersMap = new Map<string, WorkerDto>();
  for (const w of allWorkerDtos) {
    if (!uniqueWorkersMap.has(w.id)) {
      uniqueWorkersMap.set(w.id, w);
    }
  }

  return Array.from(uniqueWorkersMap.values());
}
```

**Replace with (2 queries total instead of 100+):**
```typescript
async getAll(page = 1, limit = 20): Promise<WorkerDto[]> {
  // Query 1: Get all worker profiles with pagination
  const profiles = await this.workersRepository.find({
    relations: ['user'],
    where: { isActive: true },
    skip: (page - 1) * limit,
    take: limit,
    order: { rating: 'DESC' },
  });

  if (profiles.length === 0) return [];

  // Query 2: Single batch query for all busy worker IDs
  const userIds = profiles.map(p => p.user?.id || p.id).filter(Boolean);
  const activeBookings = await this.bookingsRepository
    .createQueryBuilder('booking')
    .select('booking.operatorId')
    .where('booking.operatorId IN (:...ids)', { ids: userIds })
    .andWhere('booking.status IN (:...statuses)', {
      statuses: [BookingStatus.ACTIVE, BookingStatus.ACCEPTED, BookingStatus.CONFIRMED],
    })
    .getRawMany<{ operatorId: string }>();

  const busyUserIds = new Set(activeBookings.map(b => b.operatorId));

  // Map locally — no more per-item DB queries
  return profiles.map(p => {
    const userId = p.user?.id || p.id;
    return this.mapToDto(p, busyUserIds.has(userId) ? 'busy' : 'available');
  });
}
```

**Also fix `getNearby()` the same way:**
```typescript
// FIND:
async getNearby(skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
  const all = await this.workersRepository.find({
    where: { isActive: true },
    relations: ['user'],
  });
  const filtered = all.filter(w =>
    w.skills?.some(s => s.toLowerCase().includes(skill.toLowerCase()))
  );
  const result: WorkerDto[] = [];
  for (const w of filtered) {
    const status = await this.getWorkerStatus(w.user?.id || w.id);
    result.push(this.mapToDto(w, status));
  }
  return result;
}
```

**Replace with:**
```typescript
async getNearby(skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
  // Filter by skill in DB, not in memory
  const profiles = await this.workersRepository
    .createQueryBuilder('w')
    .leftJoinAndSelect('w.user', 'user')
    .where('w.isActive = true')
    .andWhere(`LOWER(CAST(w.skills AS text)) LIKE :skill`, {
      skill: `%${skill.toLowerCase()}%`,
    })
    .orderBy('w.rating', 'DESC')
    .limit(30)
    .getMany();

  if (profiles.length === 0) return [];

  const userIds = profiles.map(p => p.user?.id || p.id).filter(Boolean);
  const activeBookings = await this.bookingsRepository
    .createQueryBuilder('booking')
    .select('booking.operatorId')
    .where('booking.operatorId IN (:...ids)', { ids: userIds })
    .andWhere('booking.status IN (:...statuses)', {
      statuses: [BookingStatus.ACTIVE, BookingStatus.ACCEPTED, BookingStatus.CONFIRMED],
    })
    .getRawMany<{ operatorId: string }>();

  const busyUserIds = new Set(activeBookings.map(b => b.operatorId));

  return profiles.map(p => {
    const userId = p.user?.id || p.id;
    return this.mapToDto(p, busyUserIds.has(userId) ? 'busy' : 'available');
  });
}
```

---

### TASK 3.2 — Fix memory explosion in getRecommendedTalent()

**File:** `backend/src/hiring/hiring.service.ts`

**Problem:** Loads the entire active worker table into Node.js memory and filters in JavaScript. At 10,000 workers this allocates hundreds of MB per request.

**Find:**
```typescript
const allActiveWorkers = await this.workerProfileRepo.find({
  where: { isActive: true },
  relations: ['user'],
});

const scoredWorkers = allActiveWorkers.map(worker => {
  let score = 0;
  const workerSkills = worker.skills || [];
  
  const normalizedWorkerSkills = workerSkills.map(s => s.toLowerCase().trim());
  const normalizedReqSkills = requiredSkills.map(s => s.toLowerCase().trim());

  normalizedReqSkills.forEach(req => {
    if (normalizedWorkerSkills.includes(req)) score++;
  });

  return { worker, score };
});

const matched = scoredWorkers
  .filter(sw => sw.score > 0)
  .sort((a, b) => b.score - a.score || b.worker.rating - a.worker.rating)
  .map(sw => sw.worker);

return matched;
```

**Replace with (filtering happens in PostgreSQL):**
```typescript
// Use PostgreSQL array overlap operator — only loads matching rows
const matched = await this.workerProfileRepo
  .createQueryBuilder('w')
  .leftJoinAndSelect('w.user', 'user')
  .where('w.isActive = true')
  .andWhere(
    // skills column is simple-array (comma-separated text) — use ILIKE for partial match
    requiredSkills
      .map((_, i) => `LOWER(CAST(w.skills AS text)) LIKE :skill${i}`)
      .join(' OR '),
    Object.fromEntries(
      requiredSkills.map((s, i) => [`skill${i}`, `%${s.toLowerCase().trim()}%`]),
    ),
  )
  .orderBy('w.rating', 'DESC')
  .limit(100)
  .getMany();

return matched;
```

---

### TASK 3.3 — Add pagination to all list endpoints

**File:** `backend/src/workers/workers.controller.ts`

**Problem:** `GET /workers` returns all workers with no limit.

**Find:**
```typescript
@Get()
async getAll() {
  return this.workersService.getAll();
}
```

**Replace with:**
```typescript
@Get()
async getAll(
  @Query('page') page = '1',
  @Query('limit') limit = '20',
) {
  return this.workersService.getAll(parseInt(page, 10), parseInt(limit, 10));
}
```

---

**File:** `backend/src/hiring/hiring.controller.ts`

**Problem:** `GET /hiring/jobs` returns all jobs with no limit.

**Add pagination to the `getActiveJobs` controller method and service:**

In the controller:
```typescript
@Get('jobs')
async getActiveJobs(
  @Query('page') page = '1',
  @Query('limit') limit = '20',
) {
  return this.hiringService.getActiveJobs(parseInt(page, 10), parseInt(limit, 10));
}
```

In `hiring.service.ts`, update `getActiveJobs`:
```typescript
async getActiveJobs(page = 1, limit = 20): Promise<JobPost[]> {
  return this.jobPostRepo.find({
    where: { isActive: true },
    relations: ['employer'],
    order: { createdAt: 'DESC' },
    skip: (page - 1) * limit,
    take: limit,
  });
}
```

---

**File:** `backend/src/wallets/wallets.service.ts`

**Problem:** `getTransactions()` returns all transactions with no limit. A user with 5,000 transactions will get a huge response.

**Find:**
```typescript
async getTransactions(userId: string): Promise<WalletTransaction[]> {
  return this.transactionsRepository.find({
    where: { user: { id: userId } },
    order: { timestamp: 'DESC' },
  });
}
```

**Replace with:**
```typescript
async getTransactions(userId: string, page = 1, limit = 30): Promise<WalletTransaction[]> {
  return this.transactionsRepository.find({
    where: { user: { id: userId } },
    order: { timestamp: 'DESC' },
    skip: (page - 1) * limit,
    take: limit,
  });
}
```

---

### TASK 3.4 — Fix Redis silent failure — propagate errors correctly

**File:** `backend/src/redis/redis.service.ts`

**Problem:** `saveOtp` catches all errors and swallows them silently. When Redis is down, the user is told "OTP sent successfully" but verification will always fail because nothing was stored.

**Find:**
```typescript
async saveOtp(key: string, otp: string): Promise<void> {
  const TTL_SECONDS = 5 * 60; // 5 minutes
  try {
    await this.client.setEx(key, TTL_SECONDS, otp);
    this.logger.debug(`Saved OTP with key: ${key} (TTL: 5m)`);
  } catch (error) {
    this.logger.error(`Failed to save OTP to Redis: ${key}`, error);
  }
}
```

**Replace with:**
```typescript
async saveOtp(key: string, otp: string): Promise<void> {
  const TTL_SECONDS = 5 * 60;
  // Do NOT swallow — let callers handle Redis unavailability with a 503
  await this.client.setEx(key, TTL_SECONDS, otp);
  this.logger.debug(`Saved OTP with key: ${key} (TTL: 5m)`);
}
```

**Then update `auth.service.ts` `requestOtp()` to handle Redis being down:**
```typescript
async requestOtp(phoneNumber: string): Promise<{ message: string }> {
  const { randomInt } = await import('crypto');
  const otp = randomInt(100000, 999999).toString();
  try {
    await this.redisService.saveOtp(`otp:${phoneNumber}`, otp);
  } catch (error) {
    this.logger.error('Redis unavailable — OTP could not be stored', error);
    throw new ServiceUnavailableException(
      'OTP service is temporarily unavailable. Please try again in a moment.',
    );
  }
  // TODO: await this.smsService.send(phoneNumber, otp);
  this.logger.debug(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
  return { message: 'OTP sent successfully' };
}
```

**Add `ServiceUnavailableException` to the import:**
```typescript
import { Injectable, UnauthorizedException, NotFoundException, Inject, ServiceUnavailableException } from '@nestjs/common';
```

---

### TASK 3.5 — Fix OTP Redis also silently swallowing errors in getOtp

**File:** `backend/src/redis/redis.service.ts`

**Problem:** `getOtp` returns `null` on error instead of throwing. This causes `verifyOtp` to silently treat a Redis outage as "wrong OTP" instead of a server error.

**Find:**
```typescript
async getOtp(key: string): Promise<string | null> {
  try {
    return await this.client.get(key);
  } catch (error) {
    this.logger.error(`Failed to retrieve OTP from Redis: ${key}`, error);
    return null;
  }
}
```

**Replace with:**
```typescript
async getOtp(key: string): Promise<string | null> {
  // Let caller distinguish between "key not found" (null) and "Redis error" (throw)
  return await this.client.get(key);
}
```

---

### TASK 3.6 — Fix daily rate-limit timezone (UTC vs IST)

**File:** `backend/src/workers/workers.service.ts`

**Problem:** `new Date().toISOString().split('T')[0]` returns UTC date. Indian workers (IST = UTC+5:30) experience their "day reset" at 5:30 AM IST instead of midnight IST.

**Find every occurrence of:**
```typescript
const todayDateStr = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
```

**Replace with:**
```typescript
const todayDateStr = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Kolkata',
}).format(new Date()); // Returns YYYY-MM-DD in IST
```

This fix applies in two places in `workers.service.ts`: once in `toggleGoLive()` and once in `updateHourlyRate()`. Fix both.

---

### TASK 3.7 — Replace setImmediate fire-and-forget with Bull queue for reliability

**File:** `backend/src/hiring/hiring.service.ts`

**Problem:** `setImmediate` for talent notifications has no retry. If Firebase is temporarily down, the notification is permanently lost with only a `console.error`.

**Find:**
```typescript
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
        body: `New opportunity — tap to apply`,
      });
    }
  } catch (e) {
    console.error('Talent notification failed:', e);
  }
});
```

**Replace with a Bull queue job:**
```typescript
// Reliable: queued with retry support
await this.notificationsQueue.add(
  'notifyTalentForJob',
  { jobId: savedJob.id, title: savedJob.title },
  { attempts: 3, backoff: { type: 'exponential', delay: 5000 } },
);
```

**Then add a new processor in a `hiring.processor.ts` file:**
```typescript
// Create: backend/src/hiring/hiring.processor.ts
import { Process, Processor } from '@nestjs/bull';
import type { Job } from 'bull';
import { Logger } from '@nestjs/common';
import { HiringService } from './hiring.service';
import { NotificationsService } from '../notifications/notifications.service';

@Processor('hiring')
export class HiringProcessor {
  private readonly logger = new Logger(HiringProcessor.name);

  constructor(
    private readonly hiringService: HiringService,
    private readonly notificationsService: NotificationsService,
  ) {}

  @Process('notifyTalentForJob')
  async handleTalentNotification(job: Job<{ jobId: string; title: string }>) {
    const { jobId, title } = job.data;
    const matched = await this.hiringService.getRecommendedTalent(jobId);
    const tokens = matched
      .filter(m => m.user?.fcmToken)
      .map(m => m.user.fcmToken as string);

    if (tokens.length > 0) {
      await this.notificationsService.sendToMultipleDevices({
        tokens,
        title: `New job: ${title}`,
        body: 'New opportunity — tap to apply',
      });
      this.logger.log(`Notified ${tokens.length} talent for job ${jobId}`);
    }
  }
}
```

**Register the queue and processor in `HiringModule`** (`backend/src/hiring/hiring.module.ts`):
```typescript
import { BullModule } from '@nestjs/bull';
import { HiringProcessor } from './hiring.processor';

// Add to imports:
BullModule.registerQueue({ name: 'hiring' }),

// Add to providers:
HiringProcessor,
```

**Add `@InjectQueue('hiring')` to `HiringService` constructor:**
```typescript
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';

constructor(
  // ... existing injections ...
  @InjectQueue('hiring') private readonly notificationsQueue: Queue,
) {}
```

---

## TASK GROUP 4 — ADDITIONAL MEMORY ISSUES

---

### TASK 4.1 — Add database indexes for frequently queried columns

**Problem:** The booking and worker queries filter by `status`, `operator.id`, `customer.id`, and `isActive` on every request. Without indexes, PostgreSQL does a full table scan every time. As data grows, queries slow from milliseconds to seconds.

**Create a migration file** `backend/src/migrations/AddIndexes.ts`:
```typescript
import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddIndexes implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    // Bookings — most queried fields
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_bookings_operator ON bookings("operatorId");
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_bookings_customer ON bookings("customerId");
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_bookings_operator_status ON bookings("operatorId", status);
    `);

    // Workers
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_worker_profiles_active ON worker_profiles("isActive");
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_worker_profiles_user ON worker_profiles("userId");
    `);

    // Job applications
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_job_applications_job ON job_applications("jobPostId");
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_job_applications_applicant ON job_applications("applicantId");
    `);

    // Wallet transactions
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user ON wallet_transactions("userId");
    `);

    // Businesses
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_businesses_owner ON businesses("ownerId");
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_businesses_status ON businesses(status);
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS idx_bookings_status`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_bookings_operator`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_bookings_customer`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_bookings_operator_status`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_worker_profiles_active`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_worker_profiles_user`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_job_applications_job`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_job_applications_applicant`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_wallet_transactions_user`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_businesses_owner`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_businesses_status`);
  }
}
```

Run it:
```bash
cd backend && npm run typeorm migration:run
```

---

### TASK 4.2 — Disable TypeORM synchronize in production

**File:** `backend/src/app.module.ts`

**Problem:** `synchronize: true` causes TypeORM to DROP and recreate tables on every server restart. In production, this deletes all data.

**Find:**
```typescript
synchronize: true, // Enabled for development to create missing tables
```

**Replace with:**
```typescript
synchronize: configService.get('NODE_ENV') === 'development',
migrations: configService.get('NODE_ENV') !== 'development' ? ['dist/migrations/*.js'] : [],
migrationsRun: configService.get('NODE_ENV') !== 'development',
```

---

### TASK 4.3 — Add Redis connection health check

**File:** `backend/src/redis/redis.service.ts`

**Problem:** If Redis is down on startup, the app starts fine but all OTP and GPS operations fail silently. There is no health check or status indicator.

**Add a `isConnected()` method to `RedisService`:**
```typescript
private _isConnected = false;

async onModuleInit() {
  try {
    await this.client.connect();
    this._isConnected = true;
  } catch (error) {
    this._isConnected = false;
    this.logger.error('Could not connect to Redis. OTP and GPS features will be unavailable.', error);
  }
}

isConnected(): boolean {
  return this._isConnected;
}

async ping(): Promise<boolean> {
  try {
    const result = await this.client.ping();
    return result === 'PONG';
  } catch {
    return false;
  }
}
```

**Create a health check endpoint** in `app.controller.ts`:
```typescript
import { RedisService } from './redis/redis.service';

@Get('health')
async health() {
  const redisOk = await this.redisService.ping();
  return {
    status: 'ok',
    timestamp: new Date().toISOString(),
    services: {
      redis: redisOk ? 'connected' : 'disconnected',
      database: 'connected', // TypeORM throws on startup if DB is down
    },
  };
}
```

---

## TASK GROUP 5 — MISSING ENDPOINTS (BLOCKING FEATURES)

> These are features that have Flutter screens but no backend endpoint.

---

### TASK 5.1 — Add GET /workers/nearby endpoint

**File:** `backend/src/workers/workers.controller.ts`

**Add before the `@Get(':id')` route:**
```typescript
@Get('nearby')
async getNearby(
  @Query('skill') skill: string,
  @Query('lat') lat: string,
  @Query('lng') lng: string,
) {
  if (!skill || !lat || !lng) {
    throw new BadRequestException('skill, lat, and lng query params are required');
  }
  return this.workersService.getNearby(skill, parseFloat(lat), parseFloat(lng));
}
```

---

### TASK 5.2 — Add POST /workers/register endpoint

**File:** `backend/src/workers/workers.controller.ts`

**Add:**
```typescript
@Post('register')
async register(
  @Req() req,
  @Body() body: { skills: string[]; hourlyRate: number; bio?: string; title?: string },
) {
  return this.workersService.createProfile(req.user.userId, body);
}
```

---

### TASK 5.3 — Add PATCH /workers/rate endpoint

**File:** `backend/src/workers/workers.controller.ts`

**Add:**
```typescript
@Patch('rate')
async updateRate(@Req() req, @Body() body: { hourlyRate: number }) {
  if (!body.hourlyRate || body.hourlyRate <= 0) {
    throw new BadRequestException('hourlyRate must be a positive number');
  }
  return this.workersService.updateHourlyRate(req.user.userId, body.hourlyRate);
}
```

---

### TASK 5.4 — Fix PATCH /workers/:id/live-toggle to use JWT identity

**File:** `backend/src/workers/workers.controller.ts`

**Find:**
```typescript
@Post(':id/live-toggle')
async toggleGoLive(@Param('id') id: string) {
  return this.workersService.toggleGoLive(id);
}
```

**Replace with:**
```typescript
@Post('live-toggle')
async toggleGoLive(@Req() req) {
  return this.workersService.toggleGoLive(req.user.userId);
}
```

Note: Remove `:id` from the route. The identity comes from the JWT, not the URL.

---

### TASK 5.5 — Add PATCH /users/fcm-token endpoint

**File:** `backend/src/users/users.controller.ts`

**Add:**
```typescript
@Patch('fcm-token')
async updateFcmToken(@Req() req, @Body() body: { fcmToken: string }) {
  if (!body.fcmToken) throw new BadRequestException('fcmToken is required');
  return this.usersService.updateFcmToken(req.user.userId, body.fcmToken);
}
```

**Add to `users.service.ts`:**
```typescript
async updateFcmToken(userId: string, fcmToken: string): Promise<void> {
  await this.usersRepository.update(userId, { fcmToken });
}
```

---

## TASK GROUP 6 — FINAL CHECKS

After all tasks above are complete, run the following:

```bash
# 1. Build — must have zero TypeScript errors
cd backend && npm run build

# 2. Check for any remaining console.log statements (replace with Logger)
grep -rn "console.log" backend/src --include="*.ts"

# 3. Check for any remaining Math.random() calls
grep -rn "Math.random()" backend/src --include="*.ts"

# 4. Check for any remaining hardcoded credentials or phone numbers
grep -rn "919605956941\|admin/admin\|mock-token" backend/src --include="*.ts"

# 5. Confirm all controllers have @UseGuards(JwtAuthGuard)
grep -rn "@Controller\|@UseGuards" backend/src --include="*.ts"

# 6. Run database migrations
npm run typeorm migration:run
```

---

## SUMMARY — What Was Fixed and Why

| Task | Fix | Why It Mattered |
|---|---|---|
| 1.1 | Remove hardcoded admin/admin credentials | Active security breach — anyone gets ADMIN JWT |
| 1.2 | Remove hardcoded bypass phone number | Permanent master account in staging environments |
| 1.3 | Replace Math.random() with crypto.randomInt() | OTP values are predictable and brute-forceable |
| 1.4 | Use JWT identity for location writes, not client payload | Any user could poison another worker's GPS location |
| 1.5 | Verify JWT in WebSocket handleConnection | Unauthenticated clients could connect and spam gateway |
| 2.1 | Atomic wallet deduction with SELECT FOR UPDATE | Race condition allows double-spend at zero balance |
| 2.2 | Atomic OTP verification with conditional UPDATE | Double-tap corrupts startedAt and billing time |
| 2.3 | Atomic GPS strike with DB-level INCREMENT | Concurrent Bull retries lose strike counts |
| 3.1 | Batch active-booking query in getAll() | 102 DB queries reduced to 2 per request |
| 3.2 | Move talent matching to SQL | Entire worker table loaded into memory per job post |
| 3.3 | Pagination on all list endpoints | Unbounded queries cause memory spikes and slow responses |
| 3.4 | Redis saveOtp propagates errors | Users told OTP sent when Redis is down — verification always fails |
| 3.5 | Redis getOtp propagates errors | Redis outage silently returns null — treated as wrong OTP |
| 3.6 | IST timezone for rate-limit date | UTC date causes reset at 5:30 AM IST instead of midnight |
| 3.7 | Replace setImmediate with Bull queue | Fire-and-forget notifications permanently lost on Firebase errors |
| 4.1 | Add DB indexes on queried columns | Full table scans on every booking/worker query — seconds of latency at scale |
| 4.2 | Disable TypeORM synchronize in production | Drops all tables on every server restart — total data loss |
| 4.3 | Redis health check | Silent failures give no indication Redis is down |
| 5.x | Add missing controller endpoints | Flutter screens call endpoints that do not exist |

---

*Gixbee Agent Task List — April 2026*
