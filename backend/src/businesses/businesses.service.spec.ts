import { NotFoundException } from '@nestjs/common';
import { BusinessesService } from './businesses.service';

/**
 * Unit tests for the businesses module:
 * - create: stamps owner + forces status 'PENDING' regardless of input, saves.
 * - getMyBusinesses: scopes to the owner, newest first (delegates to repo.find).
 * - getById: returns the business with its owner relation, or NotFound.
 * - addOperator: appends a userId to operatorIds, idempotent (no dup, no save
 *   when already present), initialises a null list.
 * - addOfflineDay: appends an ISO date to offlineDays, idempotent, initialises
 *   a null list.
 *
 * The Business repository is mocked in-memory so each branch toggles
 * deterministically; no database is touched.
 */
function makeService(opts: { business?: any } = {}) {
  const saved: any[] = [];

  const businessRepo: any = {
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (b: any) => {
      saved.push(b);
      return b;
    }),
    find: jest.fn(async () => [opts.business].filter(Boolean)),
    findOne: jest.fn(async () => opts.business ?? null),
  };

  const service = new BusinessesService(businessRepo);
  return { service, businessRepo, saved };
}

describe('BusinessesService.create', () => {
  it('stamps the owner and forces status PENDING, then saves', async () => {
    const { service, businessRepo, saved } = makeService();

    const result = await service.create('owner-1', {
      name: 'Acme Halls',
      location: 'Pune',
      status: 'VERIFIED' as any, // caller cannot self-approve
    });

    expect(businessRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Acme Halls',
        location: 'Pune',
        owner: { id: 'owner-1' },
        status: 'PENDING',
      }),
    );
    expect(result.status).toBe('PENDING');
    expect(saved).toHaveLength(1);
  });
});

describe('BusinessesService.getMyBusinesses', () => {
  it('queries scoped to the owner, newest first', async () => {
    const mine = { id: 'b1', owner: { id: 'owner-1' } };
    const { service, businessRepo } = makeService({ business: mine });

    const result = await service.getMyBusinesses('owner-1');

    expect(businessRepo.find).toHaveBeenCalledWith({
      where: { owner: { id: 'owner-1' } },
      order: { createdAt: 'DESC' },
    });
    expect(result).toEqual([mine]);
  });
});

describe('BusinessesService.getById', () => {
  it('returns the business with its owner relation', async () => {
    const biz = { id: 'b1', owner: { id: 'owner-1' } };
    const { service, businessRepo } = makeService({ business: biz });

    const result = await service.getById('b1');

    expect(businessRepo.findOne).toHaveBeenCalledWith({
      where: { id: 'b1' },
      relations: ['owner'],
    });
    expect(result).toBe(biz);
  });

  it('throws NotFound when the business does not exist', async () => {
    const { service } = makeService({ business: null });

    await expect(service.getById('missing')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('BusinessesService.addOperator', () => {
  it('appends a new operator id and saves', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, operatorIds: ['u1'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOperator('b1', 'u2');

    expect(result.operatorIds).toEqual(['u1', 'u2']);
    expect(saved).toHaveLength(1);
  });

  it('initialises a null operatorIds list before appending', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, operatorIds: null };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOperator('b1', 'u1');

    expect(result.operatorIds).toEqual(['u1']);
    expect(saved).toHaveLength(1);
  });

  it('is idempotent — does not duplicate or save when already present', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, operatorIds: ['u1'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOperator('b1', 'u1');

    expect(result.operatorIds).toEqual(['u1']);
    expect(saved).toHaveLength(0);
  });
});

describe('BusinessesService.addOfflineDay', () => {
  it('appends a new offline day and saves', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: ['2026-06-18'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOfflineDay('b1', '2026-06-19');

    expect(result.offlineDays).toEqual(['2026-06-18', '2026-06-19']);
    expect(saved).toHaveLength(1);
  });

  it('initialises a null offlineDays list before appending', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: null };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOfflineDay('b1', '2026-06-19');

    expect(result.offlineDays).toEqual(['2026-06-19']);
    expect(saved).toHaveLength(1);
  });

  it('is idempotent — does not duplicate or save an existing day', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: ['2026-06-18'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.addOfflineDay('b1', '2026-06-18');

    expect(result.offlineDays).toEqual(['2026-06-18']);
    expect(saved).toHaveLength(0);
  });
});

describe('BusinessesService.removeOfflineDay', () => {
  it('removes an existing offline day and saves', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: ['2026-06-18', '2026-06-19'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.removeOfflineDay('b1', '2026-06-18');

    expect(result.offlineDays).toEqual(['2026-06-19']);
    expect(saved).toHaveLength(1);
  });

  it('is a no-op (no save) when the day is not present', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: ['2026-06-18'] };
    const { service, saved } = makeService({ business: biz });

    const result = await service.removeOfflineDay('b1', '2026-06-20');

    expect(result.offlineDays).toEqual(['2026-06-18']);
    expect(saved).toHaveLength(0);
  });

  it('handles a null offlineDays list without error', async () => {
    const biz: any = { id: 'b1', owner: { id: 'o1' }, offlineDays: null };
    const { service, saved } = makeService({ business: biz });

    const result = await service.removeOfflineDay('b1', '2026-06-20');

    expect(result.offlineDays).toBeNull();
    expect(saved).toHaveLength(0);
  });
});
