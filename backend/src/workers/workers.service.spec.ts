import { BadRequestException, NotFoundException } from '@nestjs/common';
import { WorkersService } from './workers.service';
import { WorkerAvailabilityService } from './worker-availability.service';
import { WorkerGoLiveService } from './worker-golive.service';
import { WorkerStrikeService } from './worker-strike.service';
import { VerificationStatus } from './worker-profile.entity';
import { BookingStatus } from '../bookings/booking.entity';
import { UserApprovalStatus } from '../users/user.entity';

/**
 * Service-level unit tests for WorkersService — the parts NOT already covered by
 * workers.service.dashboard.spec.ts (getDashboard / setActiveSkills):
 *   getAll, getById, toggleGoLive, addStrike, createProfile, updateHourlyRate,
 *   getNearby, getWorkerPackages, setWorkerStatus.
 *
 * Repositories + WalletsService + RedisService are mocked; the service is
 * constructed directly (no Nest TestingModule). Tests configure mock return
 * values per-case. No production code is touched.
 */
function setup() {
  const workersRepository: any = {
    find: jest.fn(async () => []),
    findOne: jest.fn(async () => null),
    save: jest.fn(async (p: any) => p),
    create: jest.fn((p: any) => p),
  };
  const strikesRepository: any = {
    find: jest.fn(async () => []),
    findOne: jest.fn(async () => null),
    save: jest.fn(async (p: any) => p),
    create: jest.fn((p: any) => p),
  };
  const talentRepository: any = {
    find: jest.fn(async () => []),
    findOne: jest.fn(async () => null),
  };
  const skillRepository: any = {
    find: jest.fn(async () => []),
  };
  const bookingsRepository: any = {
    find: jest.fn(async () => []),
    findOne: jest.fn(async () => null),
  };
  const walletsService: any = {
    getBalance: jest.fn(async () => 1000),
  };
  const redisService: any = {
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
    indexWorkerSkills: jest.fn(async () => undefined),
    unindexWorkerSkills: jest.fn(async () => undefined),
    removeWorkerFromGeoIndex: jest.fn(async () => undefined),
    updateWorkerLocation: jest.fn(async () => undefined),
    cacheWorkerSnapshot: jest.fn(async () => undefined),
    getWorkerSnapshot: jest.fn(async () => null),
    getWorkerLocation: jest.fn(async () => null),
    getWorkerIdsBySkill: jest.fn(async () => []),
    searchNearbyWorkerIds: jest.fn(async () => null),
    getRejectedWorkersForJob: jest.fn(async () => []),
  };

  const usersRepository: any = {
    findOne: jest.fn(async () => null),
    save: jest.fn(async (u: any) => u),
    update: jest.fn(async () => undefined),
  };

  // Go-Live limits are admin-editable CONFIGURATION master entries; the tests
  // just take the code's fallback for every key.
  const masterEntriesService: any = {
    getConfig: jest.fn(async () => null),
    getConfigNumber: jest.fn(async (_k: string, fallback: number) => fallback),
    findAll: jest.fn(async () => []),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const jobCreditRepository: any = {
    findOne: jest.fn(async () => ({ balance: 5 })),
    save: jest.fn(async (p: any) => p),
  };

  const availability = new WorkerAvailabilityService(
    workersRepository,
    bookingsRepository,
    redisService,
    masterEntriesService,
  );
  const goLive = new WorkerGoLiveService(
    workersRepository,
    talentRepository,
    bookingsRepository,
    usersRepository,
    jobCreditRepository,
    walletsService,
    redisService,
    masterEntriesService,
    notificationsService,
    availability,
  );
  const strike = new WorkerStrikeService(
    workersRepository,
    strikesRepository,
    redisService,
    notificationsService,
  );
  const service = new WorkersService(
    workersRepository,
    talentRepository,
    skillRepository,
    usersRepository,
    redisService,
    availability,
    goLive,
    strike,
  );
  return {
    service,
    availability,
    goLive,
    strike,
    workersRepository,
    strikesRepository,
    talentRepository,
    skillRepository,
    bookingsRepository,
    usersRepository,
    walletsService,
    redisService,
  };
}

/** IST calendar date — matches WorkerGoLiveService.istToday(). */
const today = () =>
  new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

/** Minimal WorkerProfile shape the mappers/branches read. */
function workerProfile(over: any = {}): any {
  return {
    id: 'wp1',
    title: 'Plumber',
    bio: 'bio',
    rating: 4.2,
    completedJobs: 7,
    reviewCount: 3,
    hourlyRate: 50,
    skills: ['plumber'],
    availabilityTags: ['Weekdays'],
    activeSkills: [],
    isActive: false,
    isFirstJobDone: false,
    verificationStatus: VerificationStatus.VERIFIED,
    strikeCount: 0,
    goLiveToggleDate: today(),
    goLiveToggleCountToday: 0,
    rateUpdateDate: today(),
    rateUpdateCountToday: 0,
    lastLat: null,
    lastLng: null,
    user: {
      id: 'u1',
      name: 'Asha',
      profileImageUrl: 'https://img/asha.png',
      isAvailableForWork: true,
      approvalStatus: UserApprovalStatus.APPROVED,
    },
    ...over,
  };
}

describe('WorkersService.getAll', () => {
  it('filters out the requester, the unavailable, and the not-approved; maps the rest', async () => {
    const { service, workersRepository } = setup();
    workersRepository.find.mockResolvedValue([
      workerProfile({
        id: 'wp-ok',
        user: {
          id: 'u-ok',
          name: 'OK',
          isAvailableForWork: true,
          approvalStatus: UserApprovalStatus.APPROVED,
        },
      }),
      workerProfile({
        id: 'wp-self',
        user: {
          id: 'u-self',
          name: 'Self',
          isAvailableForWork: true,
          approvalStatus: UserApprovalStatus.APPROVED,
        },
      }),
      workerProfile({
        id: 'wp-unavail',
        user: {
          id: 'u-unavail',
          name: 'Away',
          isAvailableForWork: false,
          approvalStatus: UserApprovalStatus.APPROVED,
        },
      }),
      workerProfile({
        id: 'wp-pending',
        user: {
          id: 'u-pending',
          name: 'Pend',
          isAvailableForWork: true,
          approvalStatus: UserApprovalStatus.PENDING,
        },
      }),
    ]);

    const res = await service.getAll('u-self');

    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({
      id: 'u-ok',
      name: 'OK',
      status: 'available',
    });
  });

  it('deduplicates a user that appears in both worker and talent profiles (worker wins)', async () => {
    const { service, workersRepository, talentRepository } = setup();
    workersRepository.find.mockResolvedValue([
      workerProfile({
        id: 'wp-dup',
        title: 'Plumber',
        user: {
          id: 'u-dup',
          name: 'FromWorker',
          isAvailableForWork: true,
          approvalStatus: UserApprovalStatus.APPROVED,
        },
      }),
    ]);
    talentRepository.find.mockResolvedValue([
      {
        id: 'tp-dup',
        experience: 'exp',
        hourlyRate: 80,
        professionalSkills: [],
        user: {
          id: 'u-dup',
          name: 'FromTalent',
          isAvailableForWork: true,
          approvalStatus: UserApprovalStatus.APPROVED,
        },
      },
    ]);

    const res = await service.getAll();

    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({ id: 'u-dup', name: 'FromWorker' });
  });

  it('resolves status from the Redis cache when present (no DB status query)', async () => {
    const { service, workersRepository, bookingsRepository, redisService } =
      setup();
    workersRepository.find.mockResolvedValue([workerProfile()]);
    redisService.get.mockImplementation(async (key: string) =>
      key.startsWith('worker:status:') ? 'busy' : null,
    );

    const res = await service.getAll();

    expect(res[0].status).toBe('busy');
    expect(bookingsRepository.findOne).not.toHaveBeenCalled();
  });
});

describe('WorkersService.getById', () => {
  it('returns the worker found directly by profile id', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne.mockResolvedValue(workerProfile());

    const dto = await service.getById('wp1');

    expect(dto).toMatchObject({ id: 'u1', name: 'Asha', status: 'available' });
  });

  it('falls back to lookup by user id when no profile matches the given id', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne
      .mockResolvedValueOnce(null) // where: { id }
      .mockResolvedValueOnce(workerProfile()); // where: { user: { id } }

    const dto = await service.getById('u1');

    expect(dto).toMatchObject({ id: 'u1', name: 'Asha' });
    expect(workersRepository.findOne).toHaveBeenCalledTimes(2);
  });

  it('throws NotFound when neither lookup finds a profile', async () => {
    const { service } = setup();
    await expect(service.getById('nope')).rejects.toThrow(NotFoundException);
  });
});

describe('WorkersService.toggleGoLive', () => {
  it('throws NotFound when the worker profile does not exist', async () => {
    const { service } = setup();
    await expect(service.toggleGoLive('ghost')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('blocks going live when first job is done and the wallet is below Rs.12', async () => {
    const { service, workersRepository, walletsService } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ isActive: false, isFirstJobDone: true }),
    );
    walletsService.getBalance.mockResolvedValue(5);

    await expect(service.toggleGoLive('wp1')).rejects.toThrow(
      BadRequestException,
    );
    expect(workersRepository.save).not.toHaveBeenCalled();
  });

  it('goes live: toggles active, warms Redis location, snapshot, and skill index', async () => {
    const { service, workersRepository, redisService } = setup();
    const profile = workerProfile({
      isActive: false,
      isFirstJobDone: false,
      skills: ['plumber'],
      activeSkills: [],
      lastLat: 12.9,
      lastLng: 77.5,
    });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.toggleGoLive('wp1');

    expect(res.isActive).toBe(true);
    expect(profile.goLiveToggleCountToday).toBe(1);
    expect(workersRepository.save).toHaveBeenCalledTimes(1);
    expect(redisService.set).toHaveBeenCalledWith(
      'worker:status:u1',
      'available',
      3600,
    );
    expect(redisService.updateWorkerLocation).toHaveBeenCalledWith(
      'u1',
      12.9,
      77.5,
    );
    expect(redisService.cacheWorkerSnapshot).toHaveBeenCalledTimes(1);
    expect(redisService.indexWorkerSkills).toHaveBeenCalledWith('u1', [
      'plumber',
    ]);
  });

  it('goes offline: clears Redis location/status/snapshot and the geo + skill indexes', async () => {
    const { service, workersRepository, redisService } = setup();
    const profile = workerProfile({ isActive: true, skills: ['plumber'] });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.toggleGoLive('wp1');

    expect(res.isActive).toBe(false);
    expect(redisService.del).toHaveBeenCalledWith('worker:location:u1');
    expect(redisService.del).toHaveBeenCalledWith('worker:status:u1');
    expect(redisService.del).toHaveBeenCalledWith('worker:snapshot:u1');
    expect(redisService.unindexWorkerSkills).toHaveBeenCalledWith('u1', [
      'plumber',
    ]);
    expect(redisService.removeWorkerFromGeoIndex).toHaveBeenCalledWith('u1');
  });

  it('enforces the daily go-live limit', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({
        isActive: false,
        isFirstJobDone: false,
        goLiveToggleDate: today(),
        goLiveToggleCountToday: 6,
      }),
    );

    await expect(service.toggleGoLive('wp1')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('persists GPS coords when going live so Instant Help can match', async () => {
    const { service, workersRepository, redisService } = setup();
    const profile = workerProfile({
      isActive: false,
      isFirstJobDone: false,
      skills: ['AC Technician'],
      lastLat: null,
      lastLng: null,
    });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.toggleGoLive('wp1', { lat: 13.0, lng: 77.6 });

    expect(res.isActive).toBe(true);
    expect(profile.lastLat).toBe(13.0);
    expect(profile.lastLng).toBe(77.6);
    expect(redisService.updateWorkerLocation).toHaveBeenCalledWith(
      'u1',
      13.0,
      77.6,
    );
  });

  it('resets the daily toggle count on a new calendar day', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({
      isActive: false,
      isFirstJobDone: false,
      goLiveToggleDate: '2000-01-01',
      goLiveToggleCountToday: 9,
      lastLat: 12.9,
      lastLng: 77.5,
    });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.toggleGoLive('wp1');

    expect(res.isActive).toBe(true);
    expect(profile.goLiveToggleDate).toBe(today());
    expect(profile.goLiveToggleCountToday).toBe(1); // reset to 0 then +1
  });
});

describe('WorkersService.addStrike', () => {
  it('is a no-op (no save) when the worker has no profile', async () => {
    const { service, workersRepository } = setup();
    await service.addStrike('u1');
    expect(workersRepository.save).not.toHaveBeenCalled();
  });

  it('increments the strike count and saves', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({ strikeCount: 1, isActive: true });
    workersRepository.findOne.mockResolvedValue(profile);

    await service.addStrike('u1');

    expect(profile.strikeCount).toBe(2);
    expect(profile.isActive).toBe(true); // not yet at the limit
    expect(workersRepository.save).toHaveBeenCalledTimes(1);
  });

  it('deactivates the worker on the third strike', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({ strikeCount: 2, isActive: true });
    workersRepository.findOne.mockResolvedValue(profile);

    await service.addStrike('u1');

    expect(profile.strikeCount).toBe(3);
    expect(profile.isActive).toBe(false);
  });
});

describe('WorkersService.createProfile', () => {
  it('upserts skills/rate when a worker profile already exists', async () => {
    const { service, workersRepository, usersRepository } = setup();
    const existing = workerProfile({ skills: ['old'], hourlyRate: 40 });
    workersRepository.findOne.mockResolvedValue(existing);

    const saved = await service.createProfile('u1', {
      skills: ['plumber'],
      hourlyRate: 50,
    });

    expect(saved.hourlyRate).toBe(50);
    expect(workersRepository.save).toHaveBeenCalledWith(existing);
    expect(usersRepository.update).toHaveBeenCalledWith('u1', {
      hasWorkerProfile: true,
    });
  });

  it('creates a PENDING, inactive profile with the supplied fields', async () => {
    const { service, workersRepository } = setup();

    await service.createProfile('u1', {
      skills: ['plumber', 'electrician'],
      hourlyRate: 75,
      bio: 'b',
      title: 't',
    });

    const created = workersRepository.create.mock.calls[0][0];
    expect(created).toMatchObject({
      skills: ['plumber', 'electrician'],
      hourlyRate: 75,
      bio: 'b',
      title: 't',
      isActive: false,
      isFirstJobDone: false,
      verificationStatus: 'PENDING',
    });
    expect(workersRepository.save).toHaveBeenCalledTimes(1);
  });
});

describe('WorkersService.updateHourlyRate', () => {
  it('throws NotFound when the worker profile does not exist', async () => {
    const { service } = setup();
    await expect(service.updateHourlyRate('u1', 99)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('updates the rate and increments the daily counter', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({
      rateUpdateDate: today(),
      rateUpdateCountToday: 0,
    });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.updateHourlyRate('u1', 120);

    expect(res).toEqual({ hourlyRate: 120 });
    expect(profile.hourlyRate).toBe(120);
    expect(profile.rateUpdateCountToday).toBe(1);
    expect(workersRepository.save).toHaveBeenCalledTimes(1);
  });

  it('enforces the 2-updates-per-day limit', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ rateUpdateDate: today(), rateUpdateCountToday: 2 }),
    );

    await expect(service.updateHourlyRate('u1', 120)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('resets the daily counter on a new calendar day', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({
      rateUpdateDate: '2000-01-01',
      rateUpdateCountToday: 9,
    });
    workersRepository.findOne.mockResolvedValue(profile);

    const res = await service.updateHourlyRate('u1', 60);

    expect(res).toEqual({ hourlyRate: 60 });
    expect(profile.rateUpdateDate).toBe(today());
    expect(profile.rateUpdateCountToday).toBe(1);
  });
});

describe('WorkersService.getNearby', () => {
  it('returns [] when no worker has the requested skill', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerIdsBySkill.mockResolvedValue([]);

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res).toEqual([]);
  });

  it('excludes the requester + the out-of-range, and sorts by rating desc (snapshot path)', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerIdsBySkill.mockResolvedValue([
      'low',
      'high',
      'far',
      'req',
    ]);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null); // geo index cold → keep full set
    redisService.getWorkerLocation.mockImplementation(async (id: string) =>
      id === 'far' ? { lat: 80, lng: 80 } : { lat: 0, lng: 0 },
    );
    redisService.getWorkerSnapshot.mockImplementation(async (id: string) => ({
      id,
      rating: id === 'high' ? 5 : 3,
    }));

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res.map((w) => w.id)).toEqual(['high', 'low']); // far excluded (>50km), req skipped
  });

  it('falls back to the DB and caches a snapshot when Redis has none', async () => {
    const { service, workersRepository, redisService } = setup();
    // Skill index stores user ids — must match profile.user.id from the DB.
    redisService.getWorkerIdsBySkill.mockResolvedValue(['u1']);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    redisService.getWorkerLocation.mockResolvedValue({ lat: 0, lng: 0 });
    redisService.getWorkerSnapshot.mockResolvedValue(null); // miss → DB fallback
    workersRepository.find.mockResolvedValue([workerProfile()]);

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({ id: 'u1', name: 'Asha' });
    // requester (0,0) and worker location (0,0) → real haversine distance 0
    expect(res[0].distance_km).toBe(0);
    expect(redisService.cacheWorkerSnapshot).toHaveBeenCalledTimes(1);
  });

  it('skips workers with no known location', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerIdsBySkill.mockResolvedValue(['w1']);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    redisService.getWorkerLocation.mockResolvedValue(null);

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res).toEqual([]);
  });

  it('skips busy workers from the final result', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerIdsBySkill.mockResolvedValue(['free', 'busy']);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    redisService.getWorkerLocation.mockResolvedValue({ lat: 0, lng: 0 });
    // Snapshot still says available for both — live worker:status must win.
    redisService.getWorkerSnapshot.mockImplementation(async (id: string) => ({
      id,
      rating: 4,
      status: 'available',
      service_radius_km: 50,
    }));
    redisService.get.mockImplementation(async (key: string) => {
      if (key === 'worker:status:busy') return 'busy';
      if (key === 'worker:status:free') return 'available';
      return null;
    });

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res.map((w) => w.id)).toEqual(['free']);
  });

  it('skips workers whose snapshot is stale-available but Redis status is busy', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerIdsBySkill.mockResolvedValue(['worker-a']);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    redisService.getWorkerLocation.mockResolvedValue({ lat: 0, lng: 0 });
    redisService.getWorkerSnapshot.mockResolvedValue({
      id: 'worker-a',
      rating: 5,
      status: 'available', // stale after accept
      service_radius_km: 50,
    });
    redisService.get.mockImplementation(async (key: string) =>
      key === 'worker:status:worker-a' ? 'busy' : null,
    );

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(res).toEqual([]);
  });

  it('caps candidates by distance before snapshot resolution', async () => {
    const { service, redisService } = setup();
    // 45 in-range workers; only nearest MAX_NEARBY_CANDIDATES (40) should be snapshotted.
    const ids = Array.from({ length: 45 }, (_, i) => `w${i}`);
    redisService.getWorkerIdsBySkill.mockResolvedValue(ids);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    // Place workers along lng so distance ≈ i * ~0.11 km (still within 50km).
    redisService.getWorkerLocation.mockImplementation(async (id: string) => {
      const i = Number(id.slice(1));
      return { lat: 0, lng: i * 0.001 };
    });
    redisService.getWorkerSnapshot.mockImplementation(async (id: string) => ({
      id,
      rating: 3,
      status: 'available',
      service_radius_km: 50,
    }));

    const res = await service.getNearby('req', 'plumber', 0, 0);

    expect(redisService.getWorkerSnapshot).toHaveBeenCalledTimes(40);
    expect(res).toHaveLength(40);
    // Nearest 40 are w0..w39; furthest (w40..w44) never snapshotted.
    const snapshotted = redisService.getWorkerSnapshot.mock.calls.map(
      (c: string[]) => c[0],
    );
    expect(snapshotted).not.toContain('w44');
    expect(snapshotted).toContain('w0');
  });
});

describe('WorkersService.getWorkerPackages', () => {
  it('returns multiplier-based fallback packages when there is no rate chart', async () => {
    const { service, workersRepository, talentRepository } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ hourlyRate: 50 }),
    );
    talentRepository.findOne.mockResolvedValue(null);

    const pkgs = await service.getWorkerPackages('u1');

    expect(pkgs).toHaveLength(3);
    expect(pkgs[0]).toMatchObject({ name: 'Quick Fix', price: 50 });
    expect(pkgs[1]).toMatchObject({
      name: 'Half Day',
      price: 175,
      isPopular: true,
    }); // round(50 * 3.5)
    expect(pkgs[2]).toMatchObject({ name: 'Full Day', price: 300 }); // round(50 * 6)
  });

  it('builds packages from a professional skill rate chart when present', async () => {
    const { service, workersRepository, talentRepository, skillRepository } =
      setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ hourlyRate: 50 }),
    );
    talentRepository.findOne.mockResolvedValue({ id: 'tp1' });
    skillRepository.find.mockResolvedValue([
      {
        name: 'Plumbing',
        rateChart: { quickFix: 100, halfDay: 350, fullDay: 600 },
      },
    ]);

    const pkgs = await service.getWorkerPackages('u1');

    expect(pkgs).toHaveLength(3);
    expect(pkgs[0]).toMatchObject({ name: 'Quick Fix', price: 100 });
    expect(pkgs[1]).toMatchObject({ name: 'Half Day', price: 350 });
    expect(pkgs[2]).toMatchObject({ name: 'Full Day', price: 600 });
  });
});

describe('WorkersService.setWorkerStatus', () => {
  it('writes the status to Redis with a 1-hour TTL', async () => {
    const { service, redisService } = setup();
    await service.setWorkerStatus('u1', 'busy');
    expect(redisService.set).toHaveBeenCalledWith(
      'worker:status:u1',
      'busy',
      3600,
    );
  });

  it('patches a cached snapshot so discovery stays in sync', async () => {
    const { service, redisService } = setup();
    redisService.getWorkerSnapshot.mockResolvedValue({
      id: 'u1',
      status: 'available',
      rating: 4,
    });
    await service.setWorkerStatus('u1', 'busy');
    expect(redisService.cacheWorkerSnapshot).toHaveBeenCalledWith('u1', {
      id: 'u1',
      status: 'busy',
      rating: 4,
    });
  });
});
