import { FavouritesService } from './favourites.service';

/**
 * Unit tests for the favourites module:
 * - add: idempotent — returns the existing row when the (user, worker) pair is
 *   already saved; otherwise creates + saves a new row scoped to the user.
 * - remove: deletes by (user, worker) and reports whether a row was affected.
 * - isFavourite: returns { favourited: true } only when a matching row exists.
 * - getMyFavourites: scopes to the user, newest first (delegates to repo.find).
 *
 * The Favourite repository is mocked in-memory so each branch toggles
 * deterministically; no database is touched.
 */
function makeService(
  opts: { existing?: any; count?: number; affected?: number } = {},
) {
  const saved: any[] = [];

  const favRepo: any = {
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (f: any) => {
      saved.push(f);
      return f;
    }),
    findOne: jest.fn(async () => opts.existing ?? null),
    count: jest.fn(async () => opts.count ?? 0),
    find: jest.fn(async () => [opts.existing].filter(Boolean)),
    delete: jest.fn(async () => ({ affected: opts.affected ?? 0 })),
  };

  const service = new FavouritesService(favRepo);
  return { service, favRepo, saved };
}

describe('FavouritesService.add', () => {
  it('creates and saves a new favourite scoped to the user', async () => {
    const { service, favRepo, saved } = makeService();

    const result = await service.add('user-1', 'worker-9');

    expect(favRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ user: { id: 'user-1' }, workerId: 'worker-9' }),
    );
    expect(saved).toHaveLength(1);
    expect(result.workerId).toBe('worker-9');
  });

  it('is idempotent — returns the existing row without saving a duplicate', async () => {
    const existing = { id: 'f1', user: { id: 'user-1' }, workerId: 'worker-9' };
    const { service, saved } = makeService({ existing });

    const result = await service.add('user-1', 'worker-9');

    expect(result).toBe(existing);
    expect(saved).toHaveLength(0);
  });
});

describe('FavouritesService.remove', () => {
  it('reports removed:true when a row was deleted', async () => {
    const { service, favRepo } = makeService({ affected: 1 });

    const result = await service.remove('user-1', 'worker-9');

    expect(favRepo.delete).toHaveBeenCalledWith({
      user: { id: 'user-1' },
      workerId: 'worker-9',
    });
    expect(result).toEqual({ removed: true });
  });

  it('reports removed:false when nothing matched', async () => {
    const { service } = makeService({ affected: 0 });

    const result = await service.remove('user-1', 'missing');

    expect(result).toEqual({ removed: false });
  });
});

describe('FavouritesService.isFavourite', () => {
  it('returns favourited:true when a matching row exists', async () => {
    const { service } = makeService({ count: 1 });
    await expect(service.isFavourite('user-1', 'worker-9')).resolves.toEqual({
      favourited: true,
    });
  });

  it('returns favourited:false when no row exists', async () => {
    const { service } = makeService({ count: 0 });
    await expect(service.isFavourite('user-1', 'worker-9')).resolves.toEqual({
      favourited: false,
    });
  });
});

describe('FavouritesService.getMyFavourites', () => {
  it('queries scoped to the user, newest first', async () => {
    const mine = { id: 'f1', user: { id: 'user-1' }, workerId: 'worker-9' };
    const { service, favRepo } = makeService({ existing: mine });

    const result = await service.getMyFavourites('user-1');

    expect(favRepo.find).toHaveBeenCalledWith({
      where: { user: { id: 'user-1' } },
      order: { createdAt: 'DESC' },
    });
    expect(result).toEqual([mine]);
  });
});
