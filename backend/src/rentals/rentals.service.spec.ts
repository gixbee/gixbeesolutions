import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { RentalsService } from './rentals.service';
import { RentalItem } from './rental-item.entity';
import { RentalReservation, RentalStatus } from './rental-reservation.entity';

/**
 * Unit tests for the peer-to-peer rental booking flow:
 * - requestReservation: validates availability, time range, min-hour floor,
 *   and calendar overlaps under a pessimistic item lock, then prices PENDING.
 * - confirmReservation: owner-only; re-checks overlap under the same item lock.
 *
 * DataSource.transaction is mocked with an in-memory EntityManager so the
 * lock + overlap branches can be toggled without a database.
 */
type Overlap = boolean;

function makeService(opts: {
  item?: any;
  reservation?: any;
  overlap?: Overlap;
}) {
  const saved: any[] = [];

  const itemLockQb: any = {
    setLock: jest.fn(() => itemLockQb),
    where: jest.fn(() => itemLockQb),
    getOne: jest.fn(async () => opts.item ?? null),
  };

  const overlapQb: any = {
    innerJoin: jest.fn(() => overlapQb),
    where: jest.fn(() => overlapQb),
    andWhere: jest.fn(() => overlapQb),
    getOne: jest.fn(async () => (opts.overlap ? { id: 'conflict-1' } : null)),
  };

  const itemRepoTx: any = {
    createQueryBuilder: jest.fn(() => itemLockQb),
    findOne: jest.fn(async () => opts.item ?? null),
  };

  const reservationRepoTx: any = {
    findOne: jest.fn(async () => opts.reservation ?? null),
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (r: any) => {
      saved.push(r);
      return r;
    }),
    createQueryBuilder: jest.fn(() => overlapQb),
  };

  const manager: any = {
    getRepository: jest.fn((entity: any) => {
      if (entity === RentalItem) return itemRepoTx;
      if (entity === RentalReservation) return reservationRepoTx;
      return reservationRepoTx;
    }),
  };

  const rentalItemRepo: any = {
    findOne: jest.fn(async () => opts.item ?? null),
    create: jest.fn((dto: any) => dto),
    save: jest.fn(async (i: any) => i),
    find: jest.fn(async () => []),
  };

  const reservationRepo: any = {
    findOne: jest.fn(async () => opts.reservation ?? null),
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (r: any) => {
      saved.push(r);
      return r;
    }),
    createQueryBuilder: jest.fn(() => overlapQb),
  };

  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const redisService: any = {
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
  };

  const service = new RentalsService(
    rentalItemRepo,
    reservationRepo,
    notificationsService,
    redisService,
    dataSource,
  );
  return {
    service,
    saved,
    rentalItemRepo,
    reservationRepo,
    itemLockQb,
    dataSource,
    manager,
  };
}

const item = (over: Partial<any> = {}) => ({
  id: 'item-1',
  name: 'Drill',
  isAvailable: true,
  hourlyRate: 50,
  minHoursToRent: 2,
  owner: { id: 'owner-1' },
  ...over,
});

// Future window (≥ 2h min floor) — service rejects past start times.
const START = new Date(Date.now() + 24 * 60 * 60 * 1000);
const END = new Date(START.getTime() + 3 * 60 * 60 * 1000);

describe('RentalsService.requestReservation', () => {
  it('creates a PENDING reservation and prices it duration * hourlyRate', async () => {
    const { service, saved, itemLockQb, dataSource } = makeService({
      item: item(),
      overlap: false,
    });

    const res = await service.requestReservation('renter-1', 'item-1', START, END);

    expect(res.status).toBe(RentalStatus.PENDING);
    expect(res.totalPrice).toBe(150); // 3h * 50
    expect(res.renter).toEqual({ id: 'renter-1' });
    expect(res.item).toEqual({ id: 'item-1' });
    expect(saved).toHaveLength(1);
    expect(dataSource.transaction).toHaveBeenCalled();
    expect(itemLockQb.setLock).toHaveBeenCalledWith('pessimistic_write');
  });

  it('coerces a string hourlyRate (decimal column) before multiplying', async () => {
    const { service } = makeService({
      item: item({ hourlyRate: '50.00' as any }),
      overlap: false,
    });

    const res = await service.requestReservation('renter-1', 'item-1', START, END);

    expect(res.totalPrice).toBe(150);
    expect(typeof res.totalPrice).toBe('number');
  });

  it('throws NotFound when the item does not exist', async () => {
    const { service, saved } = makeService({ item: null });

    await expect(
      service.requestReservation('renter-1', 'missing', START, END),
    ).rejects.toThrow(NotFoundException);
    expect(saved).toHaveLength(0);
  });

  it('rejects an item flagged unavailable', async () => {
    const { service, saved } = makeService({
      item: item({ isAvailable: false }),
    });

    await expect(
      service.requestReservation('renter-1', 'item-1', START, END),
    ).rejects.toThrow(BadRequestException);
    expect(saved).toHaveLength(0);
  });

  it('rejects self-booking', async () => {
    const { service, saved } = makeService({
      item: item({ owner: { id: 'renter-1' } }),
    });

    await expect(
      service.requestReservation('renter-1', 'item-1', START, END),
    ).rejects.toThrow(BadRequestException);
    expect(saved).toHaveLength(0);
  });

  it('rejects when end time is not after start time', async () => {
    const { service } = makeService({ item: item() });

    await expect(
      service.requestReservation('renter-1', 'item-1', END, START),
    ).rejects.toThrow(BadRequestException);
    await expect(
      service.requestReservation('renter-1', 'item-1', START, START),
    ).rejects.toThrow(BadRequestException);
  });

  it('enforces the minimum-hours billing floor', async () => {
    const oneHourEnd = new Date(START.getTime() + 60 * 60 * 1000);
    const { service, saved } = makeService({
      item: item({ minHoursToRent: 2 }),
      overlap: false,
    });

    await expect(
      service.requestReservation('renter-1', 'item-1', START, oneHourEnd),
    ).rejects.toThrow(BadRequestException);
    expect(saved).toHaveLength(0);
  });

  it('throws Conflict when the slot overlaps a confirmed booking', async () => {
    const { service, saved } = makeService({ item: item(), overlap: true });

    await expect(
      service.requestReservation('renter-1', 'item-1', START, END),
    ).rejects.toThrow(ConflictException);
    expect(saved).toHaveLength(0);
  });
});

describe('RentalsService.confirmReservation', () => {
  const pending = () => ({
    id: 'res-1',
    status: RentalStatus.PENDING,
    item: { id: 'item-1', name: 'Drill', owner: { id: 'owner-1' } },
    renter: { id: 'renter-1' },
    startTime: START,
    endTime: END,
  });

  it('confirms a PENDING reservation when no overlap remains', async () => {
    const { service, saved, itemLockQb } = makeService({
      item: item(),
      reservation: pending(),
      overlap: false,
    });

    const res = await service.confirmReservation('res-1', 'owner-1');

    expect(res.status).toBe(RentalStatus.CONFIRMED);
    expect(saved).toHaveLength(1);
    expect(saved[0].status).toBe(RentalStatus.CONFIRMED);
    expect(itemLockQb.setLock).toHaveBeenCalledWith('pessimistic_write');
  });

  it('throws NotFound for an unknown reservation id', async () => {
    const { service } = makeService({ reservation: null, item: item() });

    await expect(service.confirmReservation('nope', 'owner-1')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('forbids confirm by a non-owner', async () => {
    const { service, saved } = makeService({
      reservation: pending(),
      item: item(),
    });

    await expect(
      service.confirmReservation('res-1', 'stranger'),
    ).rejects.toThrow(ForbiddenException);
    expect(saved).toHaveLength(0);
  });

  it.each([
    RentalStatus.CONFIRMED,
    RentalStatus.ACTIVE,
    RentalStatus.COMPLETED,
    RentalStatus.CANCELLED,
    RentalStatus.REJECTED,
  ])('refuses to confirm a reservation already in %s', async (status) => {
    const { service, saved } = makeService({
      reservation: { ...pending(), status },
      item: item(),
    });

    await expect(service.confirmReservation('res-1', 'owner-1')).rejects.toThrow(
      BadRequestException,
    );
    expect(saved).toHaveLength(0);
  });

  it('throws Conflict if the slot was taken in the meantime', async () => {
    const { service, saved } = makeService({
      reservation: pending(),
      item: item(),
      overlap: true,
    });

    await expect(service.confirmReservation('res-1', 'owner-1')).rejects.toThrow(
      ConflictException,
    );
    expect(saved).toHaveLength(0);
  });
});
