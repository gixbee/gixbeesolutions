import { BadRequestException, NotFoundException } from '@nestjs/common';
import { WorkersService } from './workers.service';
import { BookingStatus } from '../bookings/booking.entity';

/**
 * Unit tests for the Go-Live panel backend:
 * - getDashboard   (GET /workers/me/dashboard — earnings aggregation)
 * - setActiveSkills (PATCH /workers/me/active-skills — per-service activation
 *                    + live Redis dispatch-index re-sync)
 *
 * Repositories and RedisService are mocked; only the aggregation arithmetic,
 * field mapping/fallbacks, and the re-sync contract are asserted.
 */
function makeService(opts: { profile?: any; bookings?: any[] }) {
  const workersRepository: any = {
    findOne: jest.fn(async () => opts.profile ?? null),
    save: jest.fn(async (p: any) => p),
  };
  const bookingsRepository: any = {
    find: jest.fn(async () => opts.bookings ?? []),
    findOne: jest.fn(async () => null),
  };
  const redisService: any = {
    indexWorkerSkills: jest.fn(async () => undefined),
    unindexWorkerSkills: jest.fn(async () => undefined),
    get: jest.fn(async () => null),
  };
  const talentRepository: any = {};
  const skillRepository: any = {};
  const walletsService: any = {};
  const usersRepository: any = {
    findOne: jest.fn(async () => null),
    save: jest.fn(async (u: any) => u),
  };
  // Admin-editable Go-Live limits — tests take the code's fallbacks.
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
  return { service, workersRepository, bookingsRepository, redisService };
}

const daysAgo = (n: number) => new Date(Date.now() - n * 24 * 60 * 60 * 1000);

describe('WorkersService.getDashboard', () => {
  it('throws NotFound when the worker profile does not exist', async () => {
    const { service } = makeService({ profile: null });

    await expect(service.getDashboard('u1')).rejects.toThrow(NotFoundException);
  });

  it('aggregates total / today / rolling-7-day earnings from COMPLETED bookings', async () => {
    const profile = {
      skills: ['plumber', 'electrician'],
      activeSkills: ['plumber'],
      isActive: true,
    };
    // Sorted updatedAt DESC, as the repository order clause would return.
    const bookings = [
      {
        id: 'b-today',
        skill: 'plumber',
        totalAmount: '450.50', // TypeORM decimal-as-string
        amount: 999, // must be ignored when totalAmount exists
        customer: { name: 'Anu' },
        updatedAt: new Date(),
      },
      {
        id: 'b-3d',
        skill: null, // → 'Service' fallback
        totalAmount: null,
        amount: 100, // → amount fallback
        customer: null, // → 'Customer' fallback
        updatedAt: daysAgo(3),
      },
      {
        id: 'b-30d',
        skill: 'electrician',
        totalAmount: 200,
        amount: null,
        customer: { name: 'Ravi' },
        updatedAt: daysAgo(30),
      },
    ];
    const { service, bookingsRepository } = makeService({ profile, bookings });

    const dash = await service.getDashboard('u1');

    // Query contract: only this operator's COMPLETED bookings.
    const findArgs = bookingsRepository.find.mock.calls[0][0];
    expect(findArgs.where).toMatchObject({
      operator: { id: 'u1' },
      status: BookingStatus.COMPLETED,
    });

    expect(dash.skills).toEqual(['plumber', 'electrician']);
    expect(dash.activeSkills).toEqual(['plumber']);
    expect(dash.isActive).toBe(true);

    expect(dash.earnings.total).toBe(750.5); // 450.50 + 100 + 200
    expect(dash.earnings.today).toBe(450.5);
    expect(dash.earnings.thisWeek).toBe(550.5); // today + 3-days-ago
    expect(dash.earnings.jobsCompleted).toBe(3);

    expect(dash.earnings.recent).toHaveLength(3);
    expect(dash.earnings.recent[0]).toMatchObject({
      id: 'b-today',
      skill: 'plumber',
      amount: 450.5,
      customerName: 'Anu',
    });
    expect(dash.earnings.recent[1]).toMatchObject({
      skill: 'Service',
      amount: 100,
      customerName: 'Customer',
    });
    expect(typeof dash.earnings.recent[0].completedAt).toBe('string');
  });

  it('returns a zeroed dashboard for a worker with no completed bookings', async () => {
    const profile = { skills: [], activeSkills: null, isActive: false };
    const { service } = makeService({ profile, bookings: [] });

    const dash = await service.getDashboard('u1');

    expect(dash.activeSkills).toEqual([]);
    expect(dash.earnings).toMatchObject({
      total: 0,
      today: 0,
      thisWeek: 0,
      jobsCompleted: 0,
      recent: [],
    });
  });
});

describe('WorkersService.setActiveSkills', () => {
  it('persists the deduped intersection with the profile skills', async () => {
    const profile = {
      skills: ['plumber', 'electrician'],
      activeSkills: [],
      isActive: false,
    };
    const { service, workersRepository, redisService } = makeService({
      profile,
    });

    const res = await service.setActiveSkills('u1', [
      'plumber',
      'plumber', // duplicate → deduped
      'astronaut', // not on profile → dropped
    ]);

    expect(res).toEqual({
      skills: ['plumber', 'electrician'],
      activeSkills: ['plumber'],
    });
    expect(workersRepository.save).toHaveBeenCalledTimes(1);
    // Offline worker: no dispatch-index churn.
    expect(redisService.unindexWorkerSkills).not.toHaveBeenCalled();
    expect(redisService.indexWorkerSkills).not.toHaveBeenCalled();
  });

  it('rejects a non-empty selection containing no profile skills', async () => {
    const profile = { skills: ['plumber'], activeSkills: [], isActive: false };
    const { service, workersRepository } = makeService({ profile });

    await expect(service.setActiveSkills('u1', ['astronaut'])).rejects.toThrow(
      BadRequestException,
    );
    expect(workersRepository.save).not.toHaveBeenCalled();
  });

  it('allows clearing the curation (empty array = every skill dispatches)', async () => {
    const profile = {
      skills: ['plumber', 'electrician'],
      activeSkills: ['plumber'],
      isActive: true,
    };
    const { service, redisService } = makeService({ profile });

    const res = await service.setActiveSkills('u1', []);

    expect(res.activeSkills).toEqual([]);
    // Live worker re-sync: drop all, re-add dispatchable set — which with an
    // empty curation is EVERY registered skill (back-compat contract).
    expect(redisService.unindexWorkerSkills).toHaveBeenCalledWith('u1', [
      'plumber',
      'electrician',
    ]);
    expect(redisService.indexWorkerSkills).toHaveBeenCalledWith('u1', [
      'plumber',
      'electrician',
    ]);
  });

  it('re-syncs the live dispatch index to exactly the curated subset', async () => {
    const profile = {
      skills: ['plumber', 'electrician', 'driver'],
      activeSkills: [],
      isActive: true,
    };
    const { service, redisService } = makeService({ profile });

    await service.setActiveSkills('u1', ['driver']);

    expect(redisService.unindexWorkerSkills).toHaveBeenCalledWith('u1', [
      'plumber',
      'electrician',
      'driver',
    ]);
    expect(redisService.indexWorkerSkills).toHaveBeenCalledWith('u1', [
      'driver',
    ]);
  });

  it('throws NotFound when the worker profile does not exist', async () => {
    const { service } = makeService({ profile: null });

    await expect(service.setActiveSkills('u1', ['plumber'])).rejects.toThrow(
      NotFoundException,
    );
  });
});
