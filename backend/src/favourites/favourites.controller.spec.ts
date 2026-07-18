import { FavouritesController } from './favourites.controller';

/**
 * Controller-level tests for the favourites module. The controller is a thin,
 * JwtAuthGuard-protected pass-through: its one job is to scope every call to
 * the authenticated `req.user.userId` (never a client-supplied id) and forward
 * the `:workerId` path param. These tests pin that contract with a mocked
 * service so a future refactor can't silently drop the user scoping (an IDOR
 * risk — e.g. listing or mutating another user's favourites).
 */
function makeController() {
  const service = {
    getMyFavourites: jest.fn(async () => [{ id: 'f1', workerId: 'w-1' }]),
    isFavourite: jest.fn(async () => ({ favourited: true })),
    add: jest.fn(async (_userId: string, workerId: string) => ({
      id: 'f-new',
      workerId,
    })),
    remove: jest.fn(async () => ({ removed: true })),
  };
  const controller = new FavouritesController(service as any);
  return { controller, service };
}

const req = (userId: string) => ({ user: { userId } }) as any;

describe('FavouritesController.getMyFavourites', () => {
  it('scopes the listing to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.getMyFavourites(req('user-1'));

    expect(service.getMyFavourites).toHaveBeenCalledWith('user-1');
    expect(result).toEqual([{ id: 'f1', workerId: 'w-1' }]);
  });
});

describe('FavouritesController.isFavourite', () => {
  it('checks the worker scoped to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.isFavourite(req('user-1'), 'w-9');

    expect(service.isFavourite).toHaveBeenCalledWith('user-1', 'w-9');
    expect(result).toEqual({ favourited: true });
  });
});

describe('FavouritesController.add', () => {
  it('adds the worker scoped to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.add(req('user-1'), 'w-7');

    expect(service.add).toHaveBeenCalledWith('user-1', 'w-7');
    expect(result).toEqual(
      expect.objectContaining({ id: 'f-new', workerId: 'w-7' }),
    );
  });
});

describe('FavouritesController.remove', () => {
  it('removes the worker scoped to the authenticated user', async () => {
    const { controller, service } = makeController();

    const result = await controller.remove(req('user-2'), 'w-3');

    expect(service.remove).toHaveBeenCalledWith('user-2', 'w-3');
    expect(result).toEqual({ removed: true });
  });

  it('does not substitute a client-supplied id for the authenticated user', async () => {
    const { controller, service } = makeController();

    await controller.remove(req('owner'), 'w-victim');

    // The userId arg must come from req.user, never from the path/body.
    expect(service.remove).toHaveBeenCalledWith('owner', 'w-victim');
  });
});
