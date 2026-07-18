import { WalletsController } from './wallets.controller';

/**
 * Unit tests for the WalletsController HTTP layer — a thin delegation surface
 * over WalletsService (JWT-guarded). Instantiated directly with a jest-mock
 * service (matching this repo's controller-spec style — no Nest TestingModule,
 * no network). Asserts request→service delegation with the authed userId and
 * the getBalance() response-wrapping shape ({ balance }).
 */

function makeController() {
  const walletsService: any = {
    getBalance: jest.fn(async () => 1234),
    getTransactions: jest.fn(async () => [{ id: 't1', amount: 100 }]),
  };
  const controller = new WalletsController(walletsService);
  return { controller, walletsService };
}

describe('WalletsController.getBalance', () => {
  it('wraps the service balance in a { balance } envelope', async () => {
    const { controller, walletsService } = makeController();
    const res = await controller.getBalance({ user: { userId: 'u-1' } });
    expect(walletsService.getBalance).toHaveBeenCalledWith('u-1');
    expect(res).toEqual({ balance: 1234 });
  });
});

describe('WalletsController.getTransactions', () => {
  it('returns the service transactions list verbatim for the authed user', async () => {
    const { controller, walletsService } = makeController();
    const res = await controller.getTransactions({ user: { userId: 'u-2' } });
    expect(walletsService.getTransactions).toHaveBeenCalledWith('u-2', 1, 50);
    expect(res).toEqual([{ id: 't1', amount: 100 }]);
  });

  it('forwards page/limit query params', async () => {
    const { controller, walletsService } = makeController();
    await controller.getTransactions({ user: { userId: 'u-2' } }, '2', '10');
    expect(walletsService.getTransactions).toHaveBeenCalledWith('u-2', 2, 10);
  });
});
