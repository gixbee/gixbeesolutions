import { RentalsController } from './rentals.controller';
import { BadRequestException } from '@nestjs/common';

/**
 * Unit tests for the RentalsController HTTP layer — a thin delegation over
 * RentalsService with the controller-layer request guards + date parsing.
 * Instantiated directly with a jest-mock service (this repo's controller-spec
 * style — no Nest TestingModule, no DB/network). Asserts: list passthrough; the
 * createItem required-field guard + `minHoursToRent ?? 1` default; the
 * requestReservation required-field guard, ISO-string→Date parsing, and the
 * invalid-date BadRequest branch; and the confirm `:resId` forwarding.
 */

function makeController() {
  const rentalsService: any = {
    getItems: jest.fn(async () => [{ id: 'i1' }]),
    createItem: jest.fn(async () => ({ id: 'i2' })),
    requestReservation: jest.fn(async () => ({ id: 'res1' })),
    confirmReservation: jest.fn(async () => ({
      id: 'res1',
      status: 'CONFIRMED',
    })),
  };
  const controller = new RentalsController(rentalsService);
  return { controller, rentalsService };
}

describe('RentalsController.getItems', () => {
  it('passes the rental item list through from the service', async () => {
    const { controller, rentalsService } = makeController();
    const res = await controller.getItems();
    expect(rentalsService.getItems).toHaveBeenCalledTimes(1);
    expect(res).toEqual([{ id: 'i1' }]);
  });
});

describe('RentalsController.createItem', () => {
  it('forwards the ownerId + item data and defaults minHoursToRent to 1', async () => {
    const { controller, rentalsService } = makeController();
    await controller.createItem({
      ownerId: 'o1',
      name: 'Drill',
      hourlyRate: 50,
    } as any);
    expect(rentalsService.createItem).toHaveBeenCalledWith('o1', {
      name: 'Drill',
      hourlyRate: 50,
      minHoursToRent: 1,
      description: undefined,
    });
  });

  it('preserves an explicit minHoursToRent', async () => {
    const { controller, rentalsService } = makeController();
    await controller.createItem({
      ownerId: 'o1',
      name: 'Drill',
      hourlyRate: 50,
      minHoursToRent: 4,
      description: 'cordless',
    } as any);
    expect(rentalsService.createItem).toHaveBeenCalledWith('o1', {
      name: 'Drill',
      hourlyRate: 50,
      minHoursToRent: 4,
      description: 'cordless',
    });
  });

  it('throws BadRequest and never calls the service when a required field is missing', async () => {
    const { controller, rentalsService } = makeController();
    await expect(
      controller.createItem({ name: 'Drill', hourlyRate: 50 } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(rentalsService.createItem).not.toHaveBeenCalled();
  });
});

describe('RentalsController.requestReservation', () => {
  it('parses ISO start/end strings to Dates and forwards them', async () => {
    const { controller, rentalsService } = makeController();
    await controller.requestReservation('item-1', {
      renterId: 'r1',
      startTime: '2026-07-01T10:00:00.000Z',
      endTime: '2026-07-01T14:00:00.000Z',
    });
    expect(rentalsService.requestReservation).toHaveBeenCalledTimes(1);
    const args = rentalsService.requestReservation.mock.calls[0];
    expect(args[0]).toBe('r1');
    expect(args[1]).toBe('item-1');
    expect(args[2]).toBeInstanceOf(Date);
    expect(args[3]).toBeInstanceOf(Date);
    expect(args[2].toISOString()).toBe('2026-07-01T10:00:00.000Z');
    expect(args[3].toISOString()).toBe('2026-07-01T14:00:00.000Z');
  });

  it('throws BadRequest and never calls the service when a required field is missing', async () => {
    const { controller, rentalsService } = makeController();
    await expect(
      controller.requestReservation('item-1', {
        renterId: 'r1',
        startTime: '2026-07-01',
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(rentalsService.requestReservation).not.toHaveBeenCalled();
  });

  it('throws BadRequest on an unparseable date and never calls the service', async () => {
    const { controller, rentalsService } = makeController();
    await expect(
      controller.requestReservation('item-1', {
        renterId: 'r1',
        startTime: 'not-a-date',
        endTime: 'also-bad',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(rentalsService.requestReservation).not.toHaveBeenCalled();
  });
});

describe('RentalsController.confirmReservation', () => {
  it('forwards the URL :resId and JWT userId to confirmReservation', async () => {
    const { controller, rentalsService } = makeController();
    const res = await controller.confirmReservation('res-42', {
      user: { userId: 'owner-1' },
    });
    expect(rentalsService.confirmReservation).toHaveBeenCalledWith(
      'res-42',
      'owner-1',
    );
    expect(res).toEqual({ id: 'res1', status: 'CONFIRMED' });
  });
});
