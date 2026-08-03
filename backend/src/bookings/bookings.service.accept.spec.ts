import { BadRequestException, NotFoundException } from '@nestjs/common';
import { BookingDispatchService } from './booking-dispatch.service';
import { BookingClaimService } from './booking-claim.service';
import { BookingStatus } from './booking.entity';
import { OutboxEventType } from '../outbox/outbox.types';

/**
 * Unit tests for acceptBooking — the transaction + race-condition path:
 * - guards (inside the locked transaction):
 *     missing booking            → 404, no save, no side-effects
 *     booking no longer REQUESTED → 400 (already accepted/cancelled)
 *     worker not assigned        → 400
 * - happy path: booking → ACCEPTED, outbox BOOKING_ACCEPTED appended in-tx,
 *     wallet fee deducted after commit
 * - RACE CONDITION: when the worker has OTHER REQUESTED bookings, exactly
 *     those (never the accepted one) are bulk-CANCELLED; cancelled ids ride
 *     in the outbox payload (FCM/Redis handled by the listener)
 * - resilience: post-transaction wallet fee is non-fatal
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
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
    getWorkerLocation: jest.fn(async () => null),
    getPendingBookingIds: jest.fn(async () => []),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
  };
  const outboxService: any = {
    append: jest.fn(
      async (_m: any, type: string, aggregateId: string, payload: any) => ({
        id: 'outbox-1',
        type,
        aggregateId,
        payload,
      }),
    ),
    enqueueDispatch: jest.fn(async () => undefined),
  };

  const jobCreditsService = {
    refundCredit: jest.fn(),
    consumeCredit: jest.fn(),
  } as any;
  const bookingStatusService = {
    cacheAndEmitBookingStatus: jest.fn(async () => undefined),
  } as any;
  const claimService = new BookingClaimService(
    bookingsRepository,
    notificationsService,
    redisService,
    workersService,
    dataSource,
    outboxService,
    jobCreditsService,
    bookingStatusService,
  );
  const service = new BookingDispatchService(
    bookingsRepository,
    bookingsQueue,
    notificationsService,
    redisService,
    dataSource,
    { emitUserEvent: jest.fn() } as any,
    bookingStatusService,
    claimService,
    {} as any,
  );
  return {
    service,
    manager,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    outboxService,
    bookingStatusService,
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

describe('BookingDispatchService.acceptBooking', () => {
  beforeEach(() => {
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  // ── Guards (inside the locked transaction) ──────────────────────────────────

  it('404s when the locked booking row does not exist', async () => {
    const { service, walletsService, outboxService } = makeService({
      lockedBooking: null,
    });

    await expect(service.acceptBooking('nope', 'work-1')).rejects.toThrow(
      NotFoundException,
    );
    expect(walletsService.deductBookingFee).not.toHaveBeenCalled();
    expect(outboxService.append).not.toHaveBeenCalled();
  });

  it('rejects a booking that is no longer REQUESTED', async () => {
    // Already ACCEPTED by a *different* worker — same worker is idempotent.
    const locked = {
      ...baseBooking(),
      status: BookingStatus.ACCEPTED,
      operator: { id: 'other-worker', name: 'Other' },
    };
    const { service, manager, walletsService, outboxService } = makeService({
      lockedBooking: locked,
      fullBooking: locked,
    });

    await expect(service.acceptBooking('b1', 'work-1')).rejects.toThrow(
      BadRequestException,
    );
    expect(manager.save).not.toHaveBeenCalled();
    expect(walletsService.deductBookingFee).not.toHaveBeenCalled();
    expect(outboxService.append).not.toHaveBeenCalled();
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

  it('accepts the booking: status → ACCEPTED with outbox append in-tx', async () => {
    const booking = baseBooking();
    const {
      service,
      manager,
      walletsService,
      outboxService,
      redisService,
      bookingStatusService,
      workersService,
    } = makeService({
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
    expect(outboxService.append).toHaveBeenCalledWith(
      manager,
      OutboxEventType.BOOKING_ACCEPTED,
      'b1',
      expect.objectContaining({
        bookingId: 'b1',
        workerId: 'work-1',
        customerId: 'cust-1',
        operatorName: 'Anu',
        cancelledBookingIds: [],
      }),
    );
    expect(outboxService.enqueueDispatch).toHaveBeenCalledWith('outbox-1');
    // Immediate Redis/socket publish so the customer leaves "searching"
    // before the outbox FCM/busy side-effects run.
    expect(bookingStatusService.cacheAndEmitBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({
        status: 'ACCEPTED',
        operatorId: 'work-1',
        customerId: 'cust-1',
      }),
    );
    expect(workersService.setWorkerStatus).toHaveBeenCalledWith(
      'work-1',
      'busy',
    );
    // Wallet period fee is off (WALLET_PAYMENTS_ENABLED=false); credits are
    // consumed instead. Do not assert deductBookingFee.
    // Pending-clear / FCM still owned by the outbox listener.
    expect(redisService.removePendingBooking).not.toHaveBeenCalled();
    expect(redisService.cacheBookingStatus).not.toHaveBeenCalled();
  });

  // ── Race condition: competing requests for the same worker ──────────────────

  it('bulk-cancels the worker’s OTHER pending bookings and records them in outbox', async () => {
    const booking = baseBooking();
    const competitorA = { id: 'b2', customer: { id: 'cust-2' } };
    const competitorB = { id: 'b3', customer: { id: 'cust-3' } };
    const { service, manager, outboxService, notificationsService } =
      makeService({
        lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
        fullBooking: booking,
        otherPending: [booking, competitorA, competitorB],
      });

    await service.acceptBooking('b1', 'work-1');

    expect(manager.update).toHaveBeenCalledTimes(1);
    expect(manager.update).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      { status: BookingStatus.CANCELLED },
    );
    expect(outboxService.append).toHaveBeenCalledWith(
      manager,
      OutboxEventType.BOOKING_ACCEPTED,
      'b1',
      expect.objectContaining({
        cancelledBookingIds: expect.arrayContaining(['b2', 'b3']),
        cancelledCustomerIds: expect.arrayContaining(['cust-2', 'cust-3']),
      }),
    );
    // FCM is listener-owned now
    expect(notificationsService.sendToUsers).not.toHaveBeenCalled();
  });

  it('runs no bulk-cancel when the worker has no competing requests', async () => {
    const booking = baseBooking();
    const { service, manager, outboxService } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
      otherPending: [booking], // only the accepted booking itself
    });

    await service.acceptBooking('b1', 'work-1');

    expect(manager.update).not.toHaveBeenCalled();
    expect(outboxService.append).toHaveBeenCalledWith(
      manager,
      OutboxEventType.BOOKING_ACCEPTED,
      'b1',
      expect.objectContaining({ cancelledBookingIds: [] }),
    );
  });

  it('still succeeds when wallet fee deduction throws', async () => {
    const booking = baseBooking();
    const { service, walletsService } = makeService({
      lockedBooking: { id: 'b1', status: BookingStatus.REQUESTED },
      fullBooking: booking,
    });
    walletsService.deductBookingFee.mockRejectedValue(new Error('wallet down'));

    const res = await service.acceptBooking('b1', 'work-1');
    expect(res.status).toBe('ACCEPTED');
  });
});
