import { BadRequestException, NotFoundException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Unit tests for verifyCompletionOtp — the wallet-settlement path:
 * - guards: missing booking, wrong OTP, non-ACTIVE booking
 * - WALLET + funds available   → atomic transfer, isPaid = true
 * - WALLET + transfer fails    → booking still COMPLETED, isPaid = false
 *                                (worker's cash/UPI collect flow takes over)
 * - WALLET + zero amount       → nothing to settle, isPaid = true
 * - CASH/UPI                   → no wallet movement, isPaid stays false
 * - billingHours = ceil(worked minutes / 60), minimum 1
 * - workedMinutes = round(elapsed − pause), minimum 1
 * - INSTANT totalAmount = round(rate × workedMinutes / 60)
 * - first completed job        → ₹12 bonus, exactly once
 */
function makeService(booking: any, workerProfile: any = undefined) {
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
  };
  const dataSource: any = { transaction: jest.fn() };

  const service = new BookingsService(
    bookingsRepository,
    workerProfileRepo,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    dataSource,
    { emitUserEvent: jest.fn() } as any,
    {
      append: jest.fn(async () => ({ id: 'ob' })),
      enqueueDispatch: jest.fn(async () => undefined),
    } as any,
  );
  return {
    service,
    bookingsRepository,
    workerProfileRepo,
    walletsService,
    redisService,
    workersService,
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

describe('BookingsService.verifyCompletionOtp', () => {
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
    const { service, bookingsRepository, walletsService } =
      makeService(booking);

    await expect(service.verifyCompletionOtp('b1', '9999')).rejects.toThrow(
      BadRequestException,
    );
    expect(booking.status).toBe(BookingStatus.ACTIVE);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
  });

  it('rejects completion when the job is not ACTIVE', async () => {
    const booking = { ...baseBooking(), status: BookingStatus.ACCEPTED };
    const { service, bookingsRepository } = makeService(booking);

    await expect(service.verifyCompletionOtp('b1', '1234')).rejects.toThrow(
      'Job must be active to complete',
    );
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  // ── Wallet settlement ─────────────────────────────────────────────────────

  it('settles a non-INSTANT WALLET booking: customer→worker transfer, isPaid = true', async () => {
    const booking = { ...baseBooking(), type: 'PACKAGE' };
    const {
      service,
      bookingsRepository,
      walletsService,
      redisService,
      workersService,
    } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).toHaveBeenCalledWith(
      'cust-1',
      'work-1',
      500,
      'b1',
    );
    expect(res.status).toBe('COMPLETED');
    expect(res.isPaid).toBe(true);
    expect(res.totalAmount).toBe(500);
    expect(res.paymentMethod).toBe('WALLET');
    expect(booking.status).toBe(BookingStatus.COMPLETED);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({ status: 'COMPLETED' }),
    );
    expect(workersService.setWorkerStatus).toHaveBeenCalledWith(
      'work-1',
      'available',
    );
  });

  it('skips wallet settlement for INSTANT jobs (manual cash/UPI confirm)', async () => {
    const booking = { ...baseBooking(), type: 'INSTANT', paymentMethod: 'WALLET' };
    const { service, walletsService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    expect(res.isPaid).toBe(false);
    expect(res.needsManualPayment).toBe(true);
  });

  it('still completes the job when the wallet transfer fails (collect flow takes over)', async () => {
    const booking = { ...baseBooking(), type: 'PACKAGE' };
    const { service, bookingsRepository, walletsService } =
      makeService(booking);
    walletsService.transferForBooking.mockRejectedValueOnce(
      new BadRequestException('Insufficient balance'),
    );

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.status).toBe('COMPLETED');
    expect(res.isPaid).toBe(false);
    expect(booking.status).toBe(BookingStatus.COMPLETED);
    expect(booking.isPaid).toBe(false);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
  });

  it('marks a zero-amount non-INSTANT WALLET booking paid without moving money', async () => {
    const booking = { ...baseBooking(), type: 'PACKAGE', amount: 0 };
    const { service, walletsService } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.transferForBooking).not.toHaveBeenCalled();
    expect(res.isPaid).toBe(true);
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

  it('bills a minimum of 1 worked minute / 1 billing hour when startedAt is missing', async () => {
    const booking = { ...baseBooking(), startedAt: null as any };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.workedMinutes).toBe(1);
    expect(res.billingHours).toBe(1);
  });

  it('excludes pause time from worked minutes', async () => {
    const booking = {
      ...baseBooking(),
      type: 'INSTANT',
      amount: 130,
      startedAt: new Date(Date.now() - 94 * 60 * 1000), // 94 min wall
      pausedMinutes: 22,
    };
    const { service } = makeService(booking);

    const res = await service.verifyCompletionOtp('b1', '1234');

    expect(res.workedMinutes).toBe(72);
    expect(res.pausedMinutes).toBe(22);
    expect(res.totalAmount).toBe(156); // round(130 * 72/60)
  });

  // ── First-job bonus ───────────────────────────────────────────────────────

  it('pays the ₹12 first-job bonus exactly once', async () => {
    const booking = baseBooking();
    const profile = { id: 'wp1', isFirstJobDone: false };
    const { service, walletsService, workerProfileRepo } = makeService(
      booking,
      profile,
    );

    await service.verifyCompletionOtp('b1', '1234');

    expect(walletsService.addFunds).toHaveBeenCalledWith('work-1', 12);
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
