import { BusinessesController } from './businesses.controller';
import { BadRequestException } from '@nestjs/common';

/**
 * Unit tests for the BusinessesController HTTP layer — a thin delegation over
 * BusinessesService. Real logic at this layer: pulling `req.user.userId` into the
 * owner-scoped routes (create / getMyBusinesses) and the two `BadRequestException`
 * guards on addOperator (userId required) and addOfflineDay (date required).
 * Instantiated directly with a jest-mock service (this repo's controller-spec
 * style — no Nest TestingModule, no DB/network).
 */

function makeController() {
  const service: any = {
    create: jest.fn(async (ownerId: string, data: any) => ({
      id: 'b1',
      ownerId,
      ...data,
    })),
    getMyBusinesses: jest.fn(async () => [{ id: 'b1' }, { id: 'b2' }]),
    getById: jest.fn(async () => ({ id: 'b1' })),
    addOperator: jest.fn(async () => ({ id: 'b1', operators: ['u9'] })),
    addOfflineDay: jest.fn(async () => ({
      id: 'b1',
      offlineDays: ['2026-07-01'],
    })),
    removeOfflineDay: jest.fn(async () => ({ id: 'b1', offlineDays: [] })),
  };
  const controller = new BusinessesController(service);
  return { controller, service };
}

describe('BusinessesController.create', () => {
  it('injects req.user.userId as the owner and forwards the body', async () => {
    const { controller, service } = makeController();
    const body = {
      name: 'Acme Plumbing',
      type: 'SERVICE',
      address: 'MG Road, Pune',
    };
    const res = await controller.create({ user: { userId: 'owner-7' } }, body);
    expect(service.create).toHaveBeenCalledWith('owner-7', body);
    expect(res).toEqual({ id: 'b1', ownerId: 'owner-7', ...body });
  });
});

describe('BusinessesController.getMyBusinesses', () => {
  it('scopes the list to the authenticated owner', async () => {
    const { controller, service } = makeController();
    const res = await controller.getMyBusinesses({
      user: { userId: 'owner-7' },
    });
    expect(service.getMyBusinesses).toHaveBeenCalledWith('owner-7');
    expect(res).toEqual([{ id: 'b1' }, { id: 'b2' }]);
  });
});

describe('BusinessesController.getById', () => {
  it('forwards the URL :id to getById', async () => {
    const { controller, service } = makeController();
    const res = await controller.getById('b-42');
    expect(service.getById).toHaveBeenCalledWith('b-42');
    expect(res).toEqual({ id: 'b1' });
  });
});

describe('BusinessesController.addOperator', () => {
  it('forwards :id + userId when userId is present', async () => {
    const { controller, service } = makeController();
    await controller.addOperator('b-42', { userId: 'u9' } as any);
    expect(service.addOperator).toHaveBeenCalledWith('b-42', 'u9');
  });

  it('throws BadRequest and never calls the service when userId is missing', async () => {
    const { controller, service } = makeController();
    await expect(
      controller.addOperator('b-42', { userId: '' } as any),
    ).rejects.toThrow(BadRequestException);
    expect(service.addOperator).not.toHaveBeenCalled();
  });
});

describe('BusinessesController.addOfflineDay', () => {
  it('forwards :id + date when date is present', async () => {
    const { controller, service } = makeController();
    await controller.addOfflineDay('b-42', { date: '2026-07-01' } as any);
    expect(service.addOfflineDay).toHaveBeenCalledWith('b-42', '2026-07-01');
  });

  it('throws BadRequest and never calls the service when date is missing', async () => {
    const { controller, service } = makeController();
    await expect(
      controller.addOfflineDay('b-42', { date: '' } as any),
    ).rejects.toThrow(BadRequestException);
    expect(service.addOfflineDay).not.toHaveBeenCalled();
  });
});

describe('BusinessesController.removeOfflineDay', () => {
  it('forwards :id + the date query param when present', async () => {
    const { controller, service } = makeController();
    const res = await controller.removeOfflineDay('b-42', '2026-07-01');
    expect(service.removeOfflineDay).toHaveBeenCalledWith('b-42', '2026-07-01');
    expect(res).toEqual({ id: 'b1', offlineDays: [] });
  });

  it('throws BadRequest and never calls the service when date is missing', async () => {
    const { controller, service } = makeController();
    await expect(
      controller.removeOfflineDay('b-42', '' as any),
    ).rejects.toThrow(BadRequestException);
    expect(service.removeOfflineDay).not.toHaveBeenCalled();
  });
});
