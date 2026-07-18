import { AddressesService } from './addresses.service';

/**
 * Unit tests for the addresses module:
 * - add: creates + saves a new address scoped to the user (label optional).
 * - remove: deletes by (id, user) and reports whether a row was affected.
 * - getMyAddresses: scopes to the user, newest first (delegates to repo.find).
 *
 * The Address repository is mocked in-memory so each branch toggles
 * deterministically; no database is touched.
 */
function makeService(opts: { existing?: any; affected?: number } = {}) {
  const saved: any[] = [];

  const addrRepo: any = {
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (a: any) => {
      saved.push(a);
      return a;
    }),
    find: jest.fn(async () => [opts.existing].filter(Boolean)),
    delete: jest.fn(async () => ({ affected: opts.affected ?? 0 })),
  };

  const service = new AddressesService(addrRepo);
  return { service, addrRepo, saved };
}

describe('AddressesService.add', () => {
  it('creates and saves a new address scoped to the user', async () => {
    const { service, addrRepo, saved } = makeService();

    const result = await service.add('user-1', {
      line: '12 MG Road, Bengaluru',
      label: 'Home',
    });

    expect(addrRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        user: { id: 'user-1' },
        line: '12 MG Road, Bengaluru',
        label: 'Home',
      }),
    );
    expect(saved).toHaveLength(1);
    expect(result.line).toBe('12 MG Road, Bengaluru');
  });

  it('saves without a label when none is supplied', async () => {
    const { service, addrRepo } = makeService();

    await service.add('user-1', { line: '5 Brigade Road' });

    expect(addrRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        user: { id: 'user-1' },
        line: '5 Brigade Road',
        label: undefined,
      }),
    );
  });
});

describe('AddressesService.remove', () => {
  it('reports removed:true when a row was deleted', async () => {
    const { service, addrRepo } = makeService({ affected: 1 });

    const result = await service.remove('user-1', 'addr-9');

    expect(addrRepo.delete).toHaveBeenCalledWith({
      id: 'addr-9',
      user: { id: 'user-1' },
    });
    expect(result).toEqual({ removed: true });
  });

  it('reports removed:false when nothing matched', async () => {
    const { service } = makeService({ affected: 0 });

    const result = await service.remove('user-1', 'missing');

    expect(result).toEqual({ removed: false });
  });
});

describe('AddressesService.getMyAddresses', () => {
  it('queries scoped to the user, newest first', async () => {
    const mine = { id: 'a1', user: { id: 'user-1' }, line: '12 MG Road' };
    const { service, addrRepo } = makeService({ existing: mine });

    const result = await service.getMyAddresses('user-1');

    expect(addrRepo.find).toHaveBeenCalledWith({
      where: { user: { id: 'user-1' } },
      order: { createdAt: 'DESC' },
    });
    expect(result).toEqual([mine]);
  });
});
