import { WorkersController } from './workers.controller';

/**
 * Unit tests for the WorkersController HTTP layer — a thin delegation surface
 * over WorkersService. Instantiated directly with a jest-mock service (matching
 * this repo's controller-spec style — no Nest TestingModule, no network).
 * Asserts request→service delegation, the JWT userId source (req.user.userId
 * rather than any URL param — the DEFECT-004 auth-bypass fix), query-string
 * number parsing for /nearby, and the active-skills null-coalesce default.
 */

function makeController() {
  const workersService: any = {
    getAll: jest.fn(async () => [{ id: 'w1' }]),
    getNearby: jest.fn(async () => [{ id: 'w2' }]),
    getDashboard: jest.fn(async () => ({ live: false, skills: [] })),
    setActiveSkills: jest.fn(async () => ({ ok: true })),
    getById: jest.fn(async () => ({ id: 'w3' })),
    toggleGoLive: jest.fn(async () => ({ live: true })),
    createProfile: jest.fn(async () => ({ id: 'w4' })),
    updateHourlyRate: jest.fn(async () => ({ hourlyRate: 500 })),
    getWorkerPackages: jest.fn(async () => [{ id: 'p1' }]),
  };
  const controller = new WorkersController(workersService);
  return { controller, workersService };
}

describe('WorkersController.getAll', () => {
  it('delegates to the service with the authed userId', async () => {
    const { controller, workersService } = makeController();
    const res = await controller.getAll({ user: { userId: 'u-1' } });
    expect(workersService.getAll).toHaveBeenCalledWith('u-1');
    expect(res).toEqual([{ id: 'w1' }]);
  });
});

describe('WorkersController.getNearby', () => {
  it('parses lat/lng to floats and forwards userId + skill', async () => {
    const { controller, workersService } = makeController();
    await controller.getNearby(
      { user: { userId: 'u-1' } },
      'plumber',
      '12.97',
      '77.59',
    );
    expect(workersService.getNearby).toHaveBeenCalledWith(
      'u-1',
      'plumber',
      12.97,
      77.59,
    );
  });

  it('passes NaN through when a coordinate is non-numeric (service guards)', async () => {
    const { controller, workersService } = makeController();
    await controller.getNearby(
      { user: { userId: 'u-1' } },
      'plumber',
      'x',
      '77.59',
    );
    const [, , lat, lng] = workersService.getNearby.mock.calls[0];
    expect(Number.isNaN(lat)).toBe(true);
    expect(lng).toBe(77.59);
  });
});

describe('WorkersController.getMyDashboard', () => {
  it('delegates to getDashboard with the authed userId', async () => {
    const { controller, workersService } = makeController();
    const res = await controller.getMyDashboard({ user: { userId: 'u-9' } });
    expect(workersService.getDashboard).toHaveBeenCalledWith('u-9');
    expect(res).toEqual({ live: false, skills: [] });
  });
});

describe('WorkersController.setActiveSkills', () => {
  it('forwards the provided skills array', async () => {
    const { controller, workersService } = makeController();
    await controller.setActiveSkills(
      { user: { userId: 'u-1' } },
      { skills: ['a', 'b'] },
    );
    expect(workersService.setActiveSkills).toHaveBeenCalledWith('u-1', [
      'a',
      'b',
    ]);
  });

  it('defaults to an empty array when the body or skills is missing', async () => {
    const { controller, workersService } = makeController();
    await controller.setActiveSkills(
      { user: { userId: 'u-1' } },
      undefined as any,
    );
    expect(workersService.setActiveSkills).toHaveBeenCalledWith('u-1', []);
  });
});

describe('WorkersController.getById', () => {
  it('delegates to the service with the URL id (public profile lookup)', async () => {
    const { controller, workersService } = makeController();
    const res = await controller.getById('w-42');
    expect(workersService.getById).toHaveBeenCalledWith('w-42');
    expect(res).toEqual({ id: 'w3' });
  });
});

describe('WorkersController.toggleGoLive', () => {
  it('uses the JWT userId (not a URL param) — DEFECT-004 fix', async () => {
    const { controller, workersService } = makeController();
    await controller.toggleGoLive({ user: { userId: 'u-7' } }, {});
    expect(workersService.toggleGoLive).toHaveBeenCalledWith('u-7', {
      lat: undefined,
      lng: undefined,
    });
  });

  it('forwards optional GPS coords for Instant Help matching', async () => {
    const { controller, workersService } = makeController();
    await controller.toggleGoLive(
      { user: { userId: 'u-7' } },
      { lat: 12.9, lng: 77.5 },
    );
    expect(workersService.toggleGoLive).toHaveBeenCalledWith('u-7', {
      lat: 12.9,
      lng: 77.5,
    });
  });
});

describe('WorkersController.register', () => {
  it('forwards the authed userId + the registration body', async () => {
    const { controller, workersService } = makeController();
    const body = { skills: ['x'], hourlyRate: 300, bio: 'b', title: 't' };
    await controller.register({ user: { userId: 'u-1' } }, body);
    expect(workersService.createProfile).toHaveBeenCalledWith('u-1', body);
  });
});

describe('WorkersController.updateRate', () => {
  it('forwards the authed userId + the new hourly rate', async () => {
    const { controller, workersService } = makeController();
    await controller.updateRate(
      { user: { userId: 'u-1' } },
      { hourlyRate: 750 },
    );
    expect(workersService.updateHourlyRate).toHaveBeenCalledWith('u-1', 750);
  });
});

describe('WorkersController.getPackages', () => {
  it('delegates to getWorkerPackages with the URL id', async () => {
    const { controller, workersService } = makeController();
    const res = await controller.getPackages('w-5');
    expect(workersService.getWorkerPackages).toHaveBeenCalledWith('w-5');
    expect(res).toEqual([{ id: 'p1' }]);
  });
});
