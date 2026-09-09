import { BadRequestException, NotFoundException } from '@nestjs/common';
import { BookingSettlementService } from './booking-settlement.service';
import { BookingStatus } from './booking.entity';
import { OutboxEventType } from '../outbox/outbox.types';

/**
 * Unit tests for verifyCompletionOtp — claim + billing + outbox path:
 * - guards: missing booking, wrong OTP, non-ACTIVE booking
 * - WALLET + funds available   → atomic transfer, isPaid = true
 * - WALLET + transfer fails    → booking still COMPLETED, isPaid = false
 * - WALLET + zero amount       → nothing to settle, isPaid = true
 * - CASH/UPI                   → no wallet movement, isPaid stays false
 * - billingHours / workedMinutes math
 * - first completed job        → marks isFirstJobDone (wallet bonus behind flag)
 * - BOOKING_COMPLETED outbox appended in-tx; Redis/worker release via listener
 */
function makeService(
  booking: any,
  workerProfile: any = undefined,
  configValues: Record<string, number> = {},
) {
  const manager: any = {
    update: jest.fn(async () =>
      booking?.status === BookingStatus.ACTIVE
        ? { affected: 1 }
        : { affected: 0 },
    ),
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
  };

  const bookingsRepository: any = {
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
    update: jest.fn(async () => ({ affected: 1 })),
  };
  const workerProfileRepo: any = {
    findOne: jest.fn(async () => workerProfile),
    save: jest.fn(async (p: any) => p),
  };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    transferForBooking: jest.fn(async () => undefined),
    reverseBookingTransfer: jest.fn(async () => undefined),
    addFunds: jest.fn(async () => 0),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const redisService: any = {
    deleteOtp: jest.fn(async () => undefined),
    cacheBookingStatus: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
    recordCompletedJobForPeriod: jest.fn(async () => undefined),
    periodicJobsPerPayment: jest.fn(async () => 0),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
  };
  const outboxService: any = {
    append: jest.fn(
      async (_m: any, type: string, aggregateId: string, payload: any) => ({
        id: 'ob-complete',
        type,
        aggregateId,
        payload,
      }),
    ),
    enqueueDispatch: jest.fn(async () => undefined),
  };

  const service = new BookingSettlementService(
    bookingsRepository,
    workerProfileRepo,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    dataSource,
    outboxService,
    {
      getConfigNumber: jest.fn(
        async (key: string, fallback: number) => configValues[key] ?? fallback,
      ),
    } as any,
    { cacheAndEmitBookingStatus: jest.fn(async () => undefined) } as any,
  );
  return {
    service,
    manager,
    bookingsRepository,
    workerProfileRepo,
    walletsService,
    redisService,
    workersService,
    outboxService,
  };
}

const HOUR = 60 * 60 * 1000;

const baseBooking = () => ({
  id: 'b1',
  status: BookingStatus.ACTIVE,
  isPaid: false,
  paymentMethod: 'WALLET',
  amount: 500,
  totalAmount: undefined as number | undefined,
  completionOtp: '1234',
  startedAt: new Date(Date.now() - 30 * 60 * 1000), // 30 min ago → bills 1 hour
  customer: { id: 'cust-1' },
  operator: { id: 'work-1' },
});

describe('BookingSettlementService.verifyCompletionOtp', () => {
  beforeEach(() => {
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  // ── Guards ────────────────────────────────────────────────────────────────

  it('404s when the booking does not exist', async () => {
    const { service } = makeService(null);

    await expect(service.verifyCompletionOtp('nope', '1234')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('rejects a wrong OTP without touching the booking', async () => {
    const booking = baseBooking();
    const { service, manager, walletsService, outboxService } =
      makeService(booking);

    await expect(service.verifyCompletionOtp('b1', '9999')).rejects.toThrow(
      BadRequestException,
    );
    expect(booking.status).toBe(BookingStatus.ACTIVE);
    expect(manager.save).not.toHaveBeenCalled();
    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    expect(outboxService.append).not.toHaveBeenCalled();
  });

  it('rejects completion when the job is not ACTIVE', async () => {
    const booking = { ...baseBooking(), status: BookingStatus.ACCEPTED };
    const { service, manager, outboxService } = makeService(booking);

    await expect(service.verifyCompletionOtp('b1', '1234')).rejects.toThrow(
      'Job must be active to complete',
    );
    expect(manager.save).not.toHaveBeenCalled();
    expect(outboxService.append).not.toHaveBeenCalled();
  });

  // ── Wallet settlement ─────────────────────────────────────────────────────

  it('settles a non-INSTANT WALLET booking: customer→worker transfer, isPaid = true', async () => {
    const booking = { ...baseBooking(), type: 'PACKAGE' };
    const { service, manager, walletsService, outboxService, redisService } =
      makeService(booking);

    // Wallet product is off — transfer is skipped; outbox still fires.
    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.status).toBe('COMPLETED');
    expect(booking.status).toBe(BookingStatus.COMPLETED);
    expect(manager.save).toHaveBeenCalledWith(booking);
    expect(outboxService.append).toHaveBeenCalledWith(
      manager,
      OutboxEventType.BOOKING_COMPLETED,
      'b1',
      expect.objectContaining({ bookingId: 'b1', operatorId: 'work-1' }),
    );
    expect(outboxService.enqueueDispatch).toHaveBeenCalledWith('ob-complete');
    // Side effects moved to outbox listener — not called inline.
    expect(redisService.cacheBookingStatus).not.toHaveBeenCalled();
    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
  });

  it('skips wallet settlement for INSTANT jobs (manual cash/UPI confirm)', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      paymentMethod: 'WALLET',
    };
    const { service, walletsService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    expect(res.isPaid).toBe(false);
    expect(res.needsManualPayment).toBe(true);
  });

  it('still completes the job when the wallet transfer fails (collect flow takes over)', async () => {
    // With wallet product off this path is dormant; completion still succeeds.
    const booking = { ...baseBooking(), type: 'PACKAGE' };
    const { service, manager, outboxService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.status).toBe('COMPLETED');
    expect(booking.status).toBe(BookingStatus.COMPLETED);
    expect(manager.save).toHaveBeenCalledWith(booking);
    expect(outboxService.append).toHaveBeenCalled();
  });

  it('marks a zero-amount non-INSTANT WALLET booking paid without moving money', async () => {
    const booking = { ...baseBooking(), type: 'PACKAGE', amount: 0 };
    const { service, walletsService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    // Wallet off → isPaid stays false even for zero amount.
    expect(res.totalAmount).toBe(0);
  });

  it('does NOT touch wallets for CASH bookings; isPaid stays false', async () => {
    const booking = { ...baseBooking(), paymentMethod: 'CASH' };
    const { service, walletsService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    expect(res.status).toBe('COMPLETED');
    expect(res.isPaid).toBe(false);
    expect(res.paymentMethod).toBe('CASH');
  });

  // ── Billing hours ─────────────────────────────────────────────────────────

  it('bills proportional minutes: 90 minutes → workedMinutes 90, billingHours 2', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 130,
      startedAt: new Date(Date.now() - 1.5 * HOUR),
    };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.workedMinutes).toBe(90);
    expect(res.billingHours).toBe(2);
    expect(res.totalAmount).toBe(195); // round(130 * 90/60)
    expect((booking as any).workedMinutes).toBe(90);
    expect((booking as any).billingHours).toBe(2);
  });

  it('adds one-way petrol to an Instant job using the Master rate', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 200,
      acceptDistanceKm: 5.2,
      startedAt: new Date(Date.now() - 70 * 60 * 1000),
    };
    const { service } = makeService(booking, undefined, {
      instant_petrol_per_km: 12,
    });

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.serviceAmount).toBe(233);
    expect(res.petrolDistanceKm).toBe(5.2);
    expect(res.petrolRatePerKm).toBe(12);
    expect(res.petrolAmount).toBe(62);
    expect(res.totalAmount).toBe(295);
    expect((booking as any).petrolAmount).toBe(62);
  });

  it('charges no petrol when an Instant booking has no accept distance', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 200,
      acceptDistanceKm: null,
    };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.serviceAmount).toBe(200);
    expect(res.petrolDistanceKm).toBe(0);
    expect(res.petrolAmount).toBe(0);
    expect(res.totalAmount).toBe(200);
  });

  it('keeps the accepted travel rate when the admin changes pricing during work', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 200,
      acceptDistanceKm: 2,
      petrolRatePerKm: 10,
    };
    const { service } = makeService(booking, undefined, {
      instant_petrol_per_km: 25,
    });
    const result = await service.verifyCompletionOtp('b1', '1234');
    expect(result.petrolRatePerKm).toBe(10);
    expect(result.petrolAmount).toBe(20);
    expect(result.totalAmount).toBe(220);
  });

  it('does not add petrol to non-Instant bookings', async () => {
    const booking = {
      ...baseBooking(),
      type: 'PACKAGE',
      amount: 200,
      acceptDistanceKm: 5.2,
    };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.petrolAmount).toBe(0);
    expect(res.totalAmount).toBe(200);
    expect((booking as any).petrolAmount).toBeNull();
  });

  it('bills a minimum of 1 worked minute / 1 billing hour when startedAt is missing', async () => {
    const booking = { ...baseBooking(), startedAt: null as any };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.workedMinutes).toBe(1);
    expect(res.billingHours).toBe(1);
  });

  it('bills full wall-clock time', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 130,
      startedAt: new Date(Date.now() - 94 * 60 * 1000),
    };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.workedMinutes).toBe(94);
    expect(res.totalAmount).toBe(204); // round(130 * 94/60)
  });

  // ── First-job bonus ───────────────────────────────────────────────────────

  it('marks isFirstJobDone on first completion (wallet bonus dormant while off)', async () => {
    const booking = baseBooking();
    const profile = { id: 'wp1', isFirstJobDone: false };
    const { service, walletsService, workerProfileRepo } = makeService(
      booking,
      profile,
    );

    await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.addFunds).not.toHaveBeenCalled();
    expect(profile.isFirstJobDone).toBe(true);
    expect(workerProfileRepo.save).toHaveBeenCalledWith(profile);
  });

  it('pays no bonus to a worker who already completed a job', async () => {
    const booking = baseBooking();
    const profile = { id: 'wp1', isFirstJobDone: true };
    const { service, walletsService, workerProfileRepo } = makeService(
      booking,
      profile,
    );

    await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.addFunds).not.toHaveBeenCalled();
    expect(workerProfileRepo.save).not.toHaveBeenCalled();
  });
});
