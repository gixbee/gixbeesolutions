import { NotFoundException } from '@nestjs/common';
import { MasterEntriesService } from './master-entries.service';
import { MasterEntryType } from './master-entry.entity';

/**
 * Unit tests for the master-entries module (cached reference data):
 * - create: saves then invalidates the Redis cache.
 * - findAll: returns parsed JSON on a cache HIT (no DB query); on a MISS queries
 *   Postgres, caches the result for 1h, and builds the WHERE from optional
 *   type/isActive filters (omitted when not supplied).
 * - findOne: returns the entry or NotFound.
 * - update: Object.assign patch merge + save + cache invalidation.
 * - remove: removes the resolved entry + cache invalidation.
 * - clearCache: only calls del when matching keys exist.
 *
 * The TypeORM repo + RedisService are mocked in-memory so each branch toggles
 * deterministically; no database or Redis is touched.
 */
function makeService(opts: { entry?: any; cached?: string | null; keys?: string[] } = {}) {
  const saved: any[] = [];
  const removed: any[] = [];
  let lastFindArgs: any = null;

  const repo: any = {
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (e: any) => {
      saved.push(e);
      return e;
    }),
    find: jest.fn(async (args: any) => {
      lastFindArgs = args;
      return [opts.entry].filter(Boolean);
    }),
    findOne: jest.fn(async () => opts.entry ?? null),
    remove: jest.fn(async (e: any) => {
      removed.push(e);
      return e;
    }),
  };

  const redis: any = {
    get: jest.fn(async () => opts.cached ?? null),
    set: jest.fn(async () => undefined),
    keys: jest.fn(async () => opts.keys ?? []),
    del: jest.fn(async () => undefined),
  };

  const service = new MasterEntriesService(repo, redis);
  return { service, repo, redis, saved, removed, getFindArgs: () => lastFindArgs };
}

describe('MasterEntriesService.create', () => {
  it('saves the entry and invalidates the cache', async () => {
    const { service, saved, redis } = makeService({ keys: ['master_entries:CATEGORY:any'] });

    const result = await service.create({ label: 'Plumbing', value: 'plumbing' } as any);

    expect(saved).toHaveLength(1);
    expect(result.label).toBe('Plumbing');
    expect(redis.del).toHaveBeenCalledWith('master_entries:CATEGORY:any');
  });
});

describe('MasterEntriesService.findAll', () => {
  it('returns parsed JSON on a cache hit without querying the DB', async () => {
    const cachedEntries = [{ id: 'm1', label: 'Cached' }];
    const { service, repo, redis } = makeService({ cached: JSON.stringify(cachedEntries) });

    const result = await service.findAll();

    expect(result).toEqual(cachedEntries);
    expect(repo.find).not.toHaveBeenCalled();
    expect(redis.set).not.toHaveBeenCalled();
  });

  it('queries the DB on a miss and caches the result for 1 hour', async () => {
    const entry = { id: 'm1', label: 'Fresh' };
    const { service, redis, getFindArgs } = makeService({ entry, cached: null });

    const result = await service.findAll();

    expect(result).toEqual([entry]);
    // no filters supplied → empty WHERE
    expect(getFindArgs()).toEqual({ where: {}, order: { createdAt: 'DESC' } });
    expect(redis.set).toHaveBeenCalledWith(
      'master_entries:all:any',
      JSON.stringify([entry]),
      3600,
    );
  });

  it('builds the WHERE clause from type + isActive filters', async () => {
    const { service, redis, getFindArgs } = makeService({ entry: null, cached: null });

    await service.findAll(MasterEntryType.SERVICE, false);

    expect(getFindArgs()).toEqual({
      where: { type: MasterEntryType.SERVICE, isActive: false },
      order: { createdAt: 'DESC' },
    });
    expect(redis.get).toHaveBeenCalledWith('master_entries:SERVICE:false');
    expect(redis.set).toHaveBeenCalledWith(
      'master_entries:SERVICE:false',
      JSON.stringify([]),
      3600,
    );
  });
});

describe('MasterEntriesService.findOne', () => {
  it('returns the entry when found', async () => {
    const entry = { id: 'm1', label: 'Found' };
    const { service } = makeService({ entry });

    await expect(service.findOne('m1')).resolves.toBe(entry);
  });

  it('throws NotFound for an unknown id', async () => {
    const { service } = makeService({ entry: null });

    await expect(service.findOne('nope')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('MasterEntriesService.update', () => {
  it('merges the patch, saves, and invalidates the cache', async () => {
    const entry: any = { id: 'm1', label: 'Old', value: 'old' };
    const { service, saved, redis } = makeService({ entry, keys: ['master_entries:all:any'] });

    const result = await service.update('m1', { label: 'New' });

    expect(result.label).toBe('New');
    expect(result.value).toBe('old');
    expect(saved).toHaveLength(1);
    expect(redis.del).toHaveBeenCalled();
  });

  it('throws NotFound when updating an unknown id', async () => {
    const { service } = makeService({ entry: null });

    await expect(service.update('nope', { label: 'x' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('MasterEntriesService.remove', () => {
  it('removes the resolved entry and invalidates the cache', async () => {
    const entry: any = { id: 'm1', label: 'Doomed' };
    const { service, removed, redis } = makeService({ entry, keys: ['master_entries:all:any'] });

    await service.remove('m1');

    expect(removed).toHaveLength(1);
    expect(removed[0]).toBe(entry);
    expect(redis.del).toHaveBeenCalled();
  });

  it('throws NotFound when removing an unknown id', async () => {
    const { service, removed } = makeService({ entry: null });

    await expect(service.remove('nope')).rejects.toBeInstanceOf(NotFoundException);
    expect(removed).toHaveLength(0);
  });
});

describe('MasterEntriesService cache invalidation', () => {
  it('does not call del when there are no matching keys', async () => {
    const { service, redis } = makeService({ keys: [] });

    await service.create({ label: 'X', value: 'x' } as any);

    expect(redis.keys).toHaveBeenCalledWith('master_entries:*');
    expect(redis.del).not.toHaveBeenCalled();
  });
});
