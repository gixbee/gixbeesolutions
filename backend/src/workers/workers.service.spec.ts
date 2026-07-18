import { BadRequestException, NotFoundException } from '@nestjs/common';
import { WorkersService } from './workers.service';
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
  };

  const usersRepository: any = {
    findOne: jest.fn(async () => null),
    save: jest.fn(async (u: any) => u),
  };

  // Go-Live limits are admin-editable CONFIGURATION master entries; the tests
  // just take the code's fallback for every key.
  const masterEntriesService: any = {
    getConfig: jest.fn(async () => null),
    getConfigNumber: jest.fn(async (_k: string, fallback: number) => fallback),
  };

  const service = new WorkersService(
    workersRepository,
    talentRepository,
    skillRepository,
    bookingsRepository,
    usersRepository,
    walletsService,
    redisService,
    masterEntriesService,
  );
  return {
    service,
    workersRepository,
    talentRepository,
    skillRepository,
    bookingsRepository,
    walletsService,
    redisService,
  };
}

const today = () => new Date().toISOString().split('T')[0];

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
      workerProfile({ id: 'wp-ok', user: { id: 'u-ok', name: 'OK', isAvailableForWork: true, approvalStatus: UserApprovalStatus.APPROVED } }),
      workerProfile({ id: 'wp-self', user: { id: 'u-self', name: 'Self', isAvailableForWork: true, approvalStatus: UserApprovalStatus.APPROVED } }),
      workerProfile({ id: 'wp-unavail', user: { id: 'u-unavail', name: 'Away', isAvailableForWork: false, approvalStatus: UserApprovalStatus.APPROVED } }),
      workerProfile({ id: 'wp-pending', user: { id: 'u-pending', name: 'Pend', isAvailableForWork: true, approvalStatus: UserApprovalStatus.PENDING } }),
    ]);

    const res = await service.getAll('u-self');

    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({ id: 'u-ok', name: 'OK', status: 'available' });
  });

  it('deduplicates a user that appears in both worker and talent profiles (worker wins)', async () => {
    const { service, workersRepository, talentRepository } = setup();
    workersRepository.find.mockResolvedValue([
      workerProfile({ id: 'wp-dup', title: 'Plumber', user: { id: 'u-dup', name: 'FromWorker', isAvailableForWork: true, approvalStatus: UserApprovalStatus.APPROVED } }),
    ]);
    talentRepository.find.mockResolvedValue([
      {
        id: 'tp-dup',
        experience: 'exp',
        hourlyRate: 80,
        professionalSkills: [],
        user: { id: 'u-dup', name: 'FromTalent', isAvailableForWork: true, approvalStatus: UserApprovalStatus.APPROVED },
      },
    ]);

    const res = await service.getAll();

    expect(res).toHaveLength(1);
    expect(res[0]).toMatchObject({ id: 'u-dup', name: 'FromWorker' });
  });

  it('resolves status from the Redis cache when present (no DB status query)', async () => {
    const { service, workersRepository, bookingsRepository, redisService } = setup();
    workersRepository.find.mockResolvedValue([workerProfile()]);
    redisService.get.mockResolvedValue('busy');

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
    await expect(service.toggleGoLive('ghost')).rejects.toThrow(NotFoundException);
  });

  it('blocks going live when first job is done and the wallet is below Rs.12', async () => {
    const { service, workersRepository, walletsService } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ isActive: false, isFirstJobDone: true }),
    );
    walletsService.getBalance.mockResolvedValue(5);

    await expect(service.toggleGoLive('wp1')).rejects.toThrow(BadRequestException);
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
    expect(redisService.set).toHaveBeenCalledWith('worker:status:u1', 'available', 3600);
    expect(redisService.updateWorkerLocation).toHaveBeenCalledWith('u1', 12.9, 77.5);
    expect(redisService.cacheWorkerSnapshot).toHaveBeenCalledTimes(1);
    expect(redisService.indexWorkerSkills).toHaveBeenCalledWith('u1', ['plumber']);
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
    expect(redisService.unindexWorkerSkills).toHaveBeenCalledWith('u1', ['plumber']);
    expect(redisService.removeWorkerFromGeoIndex).toHaveBeenCalledWith('u1');
  });

  it('enforces the 2-toggles-per-day limit', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne.mockResolvedValue(
      workerProfile({ isActive: false, isFirstJobDone: false, goLiveToggleDate: today(), goLiveToggleCountToday: 2 }),
    );

    await expect(service.toggleGoLive('wp1')).rejects.toThrow(BadRequestException);
  });

  it('resets the daily toggle count on a new calendar day', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({
      isActive: false,
      isFirstJobDone: false,
      goLiveToggleDate: '2000-01-01',
      goLiveToggleCountToday: 9,
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
  it('rejects when a worker profile already exists', async () => {
    const { service, workersRepository } = setup();
    workersRepository.findOne.mockResolvedValue(workerProfile());

    await expect(
      service.createProfile('u1', { skills: ['plumber'], hourlyRate: 50 }),
    ).rejects.toThrow(BadRequestException);
    expect(workersRepository.save).not.toHaveBeenCalled();
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
    await expect(service.updateHourlyRate('u1', 99)).rejects.toThrow(NotFoundException);
  });

  it('updates the rate and increments the daily counter', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({ rateUpdateDate: today(), rateUpdateCountToday: 0 });
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

    await expect(service.updateHourlyRate('u1', 120)).rejects.toThrow(BadRequestException);
  });

  it('resets the daily counter on a new calendar day', async () => {
    const { service, workersRepository } = setup();
    const profile = workerProfile({ rateUpdateDate: '2000-01-01', rateUpdateCountToday: 9 });
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
    redisService.getWorkerIdsBySkill.mockResolvedValue(['low', 'high', 'far', 'req']);
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
    redisService.getWorkerIdsBySkill.mockResolvedValue(['w1']);
    redisService.searchNearbyWorkerIds.mockResolvedValue(null);
    redisService.getWorkerLocation.mockResolvedValue({ lat: 0, lng: 0 });
    redisService.getWorkerSnapshot.mockResolvedValue(null); // miss → DB fallback
    workersRepository.findOne.mockResolvedValue(workerProfile());

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
});

describe('WorkersService.getWorkerPackages', () => {
  it('returns multiplier-based fallback packages when there is no rate chart', async () => {
    const { service, workersRepository, talentRepository } = setup();
    workersRepository.findOne.mockResolvedValue(workerProfile({ hourlyRate: 50 }));
    talentRepository.findOne.mockResolvedValue(null);

    const pkgs = await service.getWorkerPackages('u1');

    expect(pkgs).toHaveLength(3);
    expect(pkgs[0]).toMatchObject({ name: 'Quick Fix', price: 50 });
    expect(pkgs[1]).toMatchObject({ name: 'Half Day', price: 175, isPopular: true }); // round(50 * 3.5)
    expect(pkgs[2]).toMatchObject({ name: 'Full Day', price: 300 }); // round(50 * 6)
  });

  it('builds packages from a professional skill rate chart when present', async () => {
    const { service, workersRepository, talentRepository, skillRepository } = setup();
    workersRepository.findOne.mockResolvedValue(workerProfile({ hourlyRate: 50 }));
    talentRepository.findOne.mockResolvedValue({ id: 'tp1' });
    skillRepository.find.mockResolvedValue([
      { name: 'Plumbing', rateChart: { quickFix: 100, halfDay: 350, fullDay: 600 } },
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
    expect(redisService.set).toHaveBeenCalledWith('worker:status:u1', 'busy', 3600);
  });
});
