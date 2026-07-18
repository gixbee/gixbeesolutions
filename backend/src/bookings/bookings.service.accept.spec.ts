import { BadRequestException, NotFoundException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Unit tests for acceptBooking — the transaction + race-condition path:
 * - guards (inside the locked transaction):
 *     missing booking            → 404, no save, no side-effects
 *     booking no longer REQUESTED → 400 (already accepted/cancelled)
 *     worker not assigned        → 400
 * - happy path: booking → ACCEPTED, returns the plain booking payload,
 *     worker marked busy, pending list cleared, status cached
 * - RACE CONDITION: when the worker has OTHER REQUESTED bookings, exactly
 *     those (never the accepted one) are bulk-CANCELLED and their customers
 *     are notified; with no competitors, no bulk update runs
 * - resilience: post-transaction side effects (wallet fee, worker status)
 *     are non-fatal — the accept still succeeds if they throw
 *
 * acceptBooking does its atomic work inside `dataSource.transaction(cb)`,
 * so the mock runs the callback with a fake EntityManager whose
 * createQueryBuilder/findOne/find/save/update are all controllable.
 */
function makeService(opts: {
  lockedBooking: any;
  fullBooking?: any;
  otherPending?: any[];
}) {
  const { lockedBooking } = opts;
  const fullBooking = opts.fullBooking ?? lockedBooking;
  const otherPending = opts.otherPending ?? [];

  const queryBuilder: any = {
    setLock: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    getOne: jest.fn(async () => lockedBooking),
  };
  const manager: any = {
    createQueryBuilder: jest.fn(() => queryBuilder),
    findOne: jest.fn(async () => fullBooking),
    find: jest.fn(async () => otherPending),
    save: jest.fn(async (b: any) => b),
    update: jest.fn(async () => undefined),
  };

  const bookingsRepository: any = {
    findOne: jest.fn(async () => null),
    save: jest.fn(async (b: any) => b),
  };
  const workerProfileRepo: any = {
    findOne: jest.fn(async () => undefined),
    save: jest.fn(async (p: any) => p),
  };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    deductBookingFee: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    notifyBookingCancelled: jest.fn(async () => undefined),
    sendToUsers: jest.fn(async () => undefined),
  };
  const redisService: any = {
    removePendingBooking: jest.fn(async () => undefined),
    cacheBookingStatus: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
  };

  const service = new BookingsService(
    bookingsRepository,
    workerProfileRepo,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    dataSource,
  );
  return {
    service,
    manager,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
  };
}

const baseBooking = () => ({
  id: 'b1',
  status: BookingStatus.REQUESTED,
  skill: 'Plumbing',
  amount: 500,
  serviceLocation: 'Indiranagar',
  arrivalOtp: '1111',
  completionOtp: '2222',
  createdAt: new Date('2026-06-14T00:00:00Z'),
  operator: { id: 'work-1', name: 'Anu' },
  customer: { id: 'cust-1' },
});

describe('BookingsService.acceptBooking', () => {
  beforeEach(() => {
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  // ── Guards (inside the locked transaction) ──────────────────────────────────

  it('404s when the locked booking row does not exist', async () => {
    const { service, walletsService } = makeService({ lockedBooking: null });

    await expect(service.acceptBooking('nope', 'work-1')).rejects.toThrow(
      NotFoundException,
    );
    // side effects never run when the transaction throws
    expect(walletsService.deductBookingFee).not.toHaveBeenCalled();
  });

  it('rejects a booking that is no longer REQUESTED', async () => {
    const locked = { ...baseBooking(), status: BookingStatus.ACCEPTED };
    const { service, manager, walletsService } = makeService({
      lockedBooking: locked,
    });

    await expect(service.acceptBooking('b1', 'work-1')).rejects.toThrow(
      BadRequestException,
    );
    expect(manager.save).not.toHaveBeenCalled();
    expect(walletsService.deductBookingFee).not.toHaveBeenCalled();
  });

  it('rejects when the worker is not the one assigned to the booking', async () => {
    const booking = baseBooking();
    const { service, manager } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
    });

    await expect(service.acceptBooking('b1', 'someone-else')).rejects.toThrow(
      'You are not assigned to this booking.',
    );
    expect(manager.save).not.toHaveBeenCalled();
  });

  // ── Happy path ──────────────────────────────────────────────────────────────

  it('accepts the booking: status → ACCEPTED with the plain payload returned', async () => {
    const booking = baseBooking();
    const { service, manager, walletsService, redisService, workersService } =
      makeService({
        lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
        fullBooking: booking,
      });

    const res = await service.acceptBooking('b1', 'work-1');

    expect(booking.status).toBe(BookingStatus.ACCEPTED);
    expect(manager.save).toHaveBeenCalledWith(booking);
    expect(res.status).toBe('ACCEPTED');
    expect(res.message).toContain('Booking accepted');
    expect(res.booking).toEqual(
      expect.objectContaining({
        id: 'b1',
        status: BookingStatus.ACCEPTED,
        skill: 'Plumbing',
        amount: 500,
        serviceLocation: 'Indiranagar',
        arrivalOtp: '1111',
        completionOtp: '2222',
      }),
    );
    // post-transaction side effects
    expect(walletsService.deductBookingFee).toHaveBeenCalledWith('work-1');
    expect(workersService.setWorkerStatus).toHaveBeenCalledWith(
      'work-1',
      'busy',
    );
    expect(redisService.removePendingBooking).toHaveBeenCalledWith(
      'work-1',
      'b1',
    );
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({ status: 'ACCEPTED', operatorName: 'Anu' }),
    );
  });

  // ── Race condition: competing requests for the same worker ──────────────────

  it('bulk-cancels the worker’s OTHER pending bookings and notifies them', async () => {
    const booking = baseBooking();
    const competitorA = { id: 'b2', customer: { id: 'cust-2' } };
    const competitorB = { id: 'b3', customer: { id: 'cust-3' } };
    const {
      service,
      manager,
      notificationsService,
      redisService,
    } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
      // find() returns ALL requested incl. the one being accepted
      otherPending: [booking, competitorA, competitorB],
    });

    await service.acceptBooking('b1', 'work-1');

    // exactly one bulk update, with CANCELLED status, never touching b1
    expect(manager.update).toHaveBeenCalledTimes(1);
    expect(manager.update).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      { status: BookingStatus.CANCELLED },
    );
    // both losing customers notified via multicast; the winner is not
    expect(notificationsService.sendToUsers).toHaveBeenCalledTimes(1);
    expect(notificationsService.sendToUsers).toHaveBeenCalledWith(
      expect.arrayContaining(['cust-2', 'cust-3']),
      expect.objectContaining({
        title: 'Booking Cancelled',
        data: { type: 'booking_cancelled' },
      }),
    );
    expect(notificationsService.sendToUsers.mock.calls[0][0]).toHaveLength(2);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b2',
      expect.objectContaining({ status: 'CANCELLED' }),
    );
  });

  it('runs no bulk-cancel when the worker has no competing requests', async () => {
    const booking = baseBooking();
    const { service, manager, notificationsService } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
      otherPending: [booking], // only the accepted booking itself
    });

    await service.acceptBooking('b1', 'work-1');

    expect(manager.update).not.toHaveBeenCalled();
    expect(notificationsService.sendToUsers).not.toHaveBeenCalled();
    expect(notificationsService.notifyBookingCancelled).not.toHaveBeenCalled();
  });

  // ── Resilience: non-fatal post-transaction side effects ─────────────────────

  it('still succeeds when the wallet fee deduction throws (fee reconciled later)', async () => {
    const booking = baseBooking();
    const { service, walletsService } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
    });
    walletsService.deductBookingFee.mockRejectedValueOnce(
      new BadRequestException('Insufficient wallet balance'),
    );

    const res = await service.acceptBooking('b1', 'work-1');

    expect(res.status).toBe('ACCEPTED');
    expect(booking.status).toBe(BookingStatus.ACCEPTED);
  });

  it('still succeeds when marking the worker busy throws', async () => {
    const booking = baseBooking();
    const { service, workersService } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
    });
    workersService.setWorkerStatus.mockRejectedValueOnce(
      new Error('redis down'),
    );

    const res = await service.acceptBooking('b1', 'work-1');

    expect(res.status).toBe('ACCEPTED');
  });
});
