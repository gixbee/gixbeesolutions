import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';
import { WorkerStrikeType } from '../workers/worker-strike.entity';

/**
 * Unit tests for addGpsStrike — progress-violation path:
 * - guards:
 *     missing booking            → returns undefined, no save, no notify
 *     non-ACCEPTED status        → returns undefined, no save, no notify
 * - 1st strike: counter increments, GPS-strike notification, status stays ACCEPTED
 * - 2nd strike: flags workerNoProgressAt (customer free cancel), worker profile
 *     strike, customer + worker notified — does NOT auto-cancel
 * - already flagged: idempotent return with freeCancelEnabled
 */
function makeService(booking: any) {
  const bookingsRepository: any = {
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
  };
  const workerProfileRepo: any = { findOne: jest.fn(), save: jest.fn() };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    reverseBookingTransfer: jest.fn(async () => undefined),
    transferForBooking: jest.fn(async () => undefined),
    addFunds: jest.fn(async () => 0),
    deductBookingFee: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
    notifyBookingCancelled: jest.fn(async () => undefined),
    notifyGpsStrike: jest.fn(async () => undefined),
  };
  const redisService: any = {
    removePendingBooking: jest.fn(async () => undefined),
    cacheBookingStatus: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
    recordStrike: jest.fn(async () => undefined),
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
    { refundCredit: jest.fn(), consumeCredit: jest.fn() } as any,
    { getConfigNumber: jest.fn(async (_k: string, f: number) => f) } as any,
  );
  return {
    service,
    bookingsRepository,
    notificationsService,
    redisService,
    workersService,
  };
}

const baseBooking = (overrides: Partial<any> = {}) => ({
  id: 'b1',
  status: BookingStatus.ACCEPTED,
  gpsStrikes: 0,
  workerNoProgressAt: null,
  skill: 'plumber',
  customer: { id: 'cust-1' },
  operator: { id: 'work-1', name: 'Asha' },
  ...overrides,
});

describe('BookingsService.addGpsStrike', () => {
  it('does nothing when the booking does not exist', async () => {
    const { service, bookingsRepository, notificationsService } =
      makeService(null);

    const res = await service.addGpsStrike('missing');

    expect(res).toBeUndefined();
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(notificationsService.notifyGpsStrike).not.toHaveBeenCalled();
  });

  it('does nothing when the booking is not ACCEPTED', async () => {
    const booking = baseBooking({ status: BookingStatus.COMPLETED });
    const { service, bookingsRepository, notificationsService } =
      makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toBeUndefined();
    expect(booking.gpsStrikes).toBe(0);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(notificationsService.notifyGpsStrike).not.toHaveBeenCalled();
  });

  it('records a first strike without enabling free cancel', async () => {
    const booking = baseBooking({ gpsStrikes: 0 });
    const {
      service,
      bookingsRepository,
      notificationsService,
      workersService,
    } = makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({ cancelled: false, strikes: 1 });
    expect(booking.gpsStrikes).toBe(1);
    expect(booking.workerNoProgressAt).toBeNull();
    expect(booking.status).toBe(BookingStatus.ACCEPTED);
    expect(bookingsRepository.save).toHaveBeenCalledTimes(1);
    expect(notificationsService.notifyGpsStrike).toHaveBeenCalledWith(
      'work-1',
      1,
    );
    expect(workersService.recordStrike).not.toHaveBeenCalled();
  });

  it('on second strike enables free cancel and records a worker strike', async () => {
    const booking = baseBooking({ gpsStrikes: 1 });
    const {
      service,
      bookingsRepository,
      notificationsService,
      redisService,
      workersService,
    } = makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({
      cancelled: false,
      strikes: 2,
      freeCancelEnabled: true,
    });
    expect(booking.gpsStrikes).toBe(2);
    expect(booking.workerNoProgressAt).toBeInstanceOf(Date);
    expect(booking.status).toBe(BookingStatus.ACCEPTED);
    expect(bookingsRepository.save).toHaveBeenCalledTimes(1);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({
        workerNoProgress: true,
        customerId: 'cust-1',
        operatorId: 'work-1',
      }),
    );
    expect(notificationsService.sendToUser).toHaveBeenCalledWith(
      'cust-1',
      expect.objectContaining({
        title: 'Pro not moving',
        data: { type: 'worker_no_progress', bookingId: 'b1' },
      }),
    );
    expect(workersService.recordStrike).toHaveBeenCalledWith(
      'work-1',
      expect.objectContaining({
        type: WorkerStrikeType.GPS_FORFEIT,
        bookingId: 'b1',
      }),
    );
    expect(notificationsService.notifyGpsStrike).not.toHaveBeenCalled();
  });

  it('is idempotent when free cancel is already enabled', async () => {
    const booking = baseBooking({
      gpsStrikes: 2,
      workerNoProgressAt: new Date('2026-01-01'),
    });
    const { service, bookingsRepository, workersService } =
      makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({
      cancelled: false,
      strikes: 2,
      freeCancelEnabled: true,
    });
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(workersService.recordStrike).not.toHaveBeenCalled();
  });
});

describe('BookingsService.evaluateWorkerProgress', () => {
  function makeBareService() {
    return makeService(null).service;
  }

  const now = Date.parse('2026-08-01T12:00:00.000Z');
  const freshTs = new Date(now - 30_000).toISOString();

  it('fails when there is no location', () => {
    const service = makeBareService();
    expect(service.evaluateWorkerProgress({ serviceLat: 12.9, serviceLng: 77.6 }, null)).toEqual(
      expect.objectContaining({ progressing: false }),
    );
  });

  it('fails when location timestamp is stale', () => {
    const service = makeBareService();
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2 },
      { lat: 12.9, lng: 77.6, timestamp: new Date(now - 120_000).toISOString() },
      now,
    );
    expect(res.progressing).toBe(false);
    expect(res.reason).toMatch(/stale/i);
  });

  it('passes when worker is within 500m of the job', () => {
    const service = makeBareService();
    // ~0.2 km north of job
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 3 },
      { lat: 12.9018, lng: 77.6, timestamp: freshTs },
      now,
    );
    expect(res.progressing).toBe(true);
  });

  it('passes when worker closed at least 300m since accept', () => {
    const service = makeBareService();
    jest.spyOn(service, 'calculateDistance').mockReturnValue(1.5);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2.0 },
      { lat: 12.91, lng: 77.61, timestamp: freshTs },
      now,
    );
    expect(res.progressing).toBe(true);
    expect(res.reason).toMatch(/closer/i);
  });

  it('fails when worker has barely moved closer', () => {
    const service = makeBareService();
    jest.spyOn(service, 'calculateDistance').mockReturnValue(1.9);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2.0 },
      { lat: 12.91, lng: 77.61, timestamp: freshTs },
      now,
    );
    expect(res.progressing).toBe(false);
  });
});
