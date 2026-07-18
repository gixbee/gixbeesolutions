import { AddressesController } from './addresses.controller';

/**
 * Controller-level tests for the addresses module. The controller is a thin,
 * JwtAuthGuard-protected pass-through: its one job is to scope every call to
 * the authenticated `req.user.userId` (never a client-supplied id) and forward
 * the validated body. These tests pin that contract with a mocked service so a
 * future refactor can't silently drop the user scoping (an IDOR risk).
 */
function makeController() {
  const service = {
    getMyAddresses: jest.fn(async () => [{ id: 'a1', line: '12 MG Road' }]),
    add: jest.fn(async (_userId: string, data: any) => ({
      id: 'a-new',
      ...data,
    })),
    remove: jest.fn(async () => ({ removed: true })),
  };
  const controller = new AddressesController(service as any);
  return { controller, service };
}

const req = (userId: string) => ({ user: { userId } }) as any;

describe('AddressesController.getMyAddresses', () => {
  it('scopes the listing to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.getMyAddresses(req('user-1'));

    expect(service.getMyAddresses).toHaveBeenCalledWith('user-1');
    expect(result).toEqual([{ id: 'a1', line: '12 MG Road' }]);
  });
});

describe('AddressesController.add', () => {
  it('forwards line + label scoped to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.add(req('user-1'), {
      line: '5 Brigade Road',
      label: 'Work',
    } as any);

    expect(service.add).toHaveBeenCalledWith('user-1', {
      line: '5 Brigade Road',
      label: 'Work',
    });
    expect(result).toEqual(
      expect.objectContaining({ id: 'a-new', line: '5 Brigade Road' }),
    );
  });

  it('passes label through as undefined when omitted', async () => {
    const { controller, service } = makeController();

    await controller.add(req('user-2'), { line: '5 Brigade Road' } as any);

    expect(service.add).toHaveBeenCalledWith('user-2', {
      line: '5 Brigade Road',
      label: undefined,
    });
  });
});

describe('AddressesController.remove', () => {
  it('removes by id scoped to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.remove(req('user-1'), 'addr-9');

    expect(service.remove).toHaveBeenCalledWith('user-1', 'addr-9');
    expect(result).toEqual({ removed: true });
  });
});
