import { BookingProgressService } from './booking-progress.service';
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
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
    notifyBookingCancelled: jest.fn(async () => undefined),
    notifyGpsStrike: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
    recordStrike: jest.fn(async () => undefined),
  };
  const bookingStatusService: any = {
    cacheAndEmitBookingStatus: jest.fn(async () => undefined),
  };

  const service = new BookingProgressService(
    bookingsRepository,
    notificationsService,
    workersService,
    bookingStatusService,
  );
  return {
    service,
    bookingsRepository,
    notificationsService,
    workersService,
    bookingStatusService,
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

describe('BookingProgressService.addGpsStrike', () => {
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
      bookingStatusService,
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
    expect(bookingStatusService.cacheAndEmitBookingStatus).toHaveBeenCalledWith(
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
  });

  it('is idempotent once free cancel is already enabled', async () => {
    const booking = baseBooking({
      gpsStrikes: 2,
      workerNoProgressAt: new Date(),
    });
    const { service, bookingsRepository, notificationsService } =
      makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({
      cancelled: false,
      strikes: 2,
      freeCancelEnabled: true,
    });
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(notificationsService.notifyGpsStrike).not.toHaveBeenCalled();
  });
});

describe('BookingProgressService.evaluateWorkerProgress', () => {
  it('fails when there is no location', () => {
    const { service } = makeService(null);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6 },
      null,
    );
    expect(res.progressing).toBe(false);
  });

  it('passes when near the job', () => {
    const { service } = makeService(null);
    jest.spyOn(service, 'calculateDistance').mockReturnValue(0.2);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2 },
      { lat: 12.9, lng: 77.6, timestamp: new Date().toISOString() },
    );
    expect(res.progressing).toBe(true);
  });

  it('fails when not closing enough distance vs accept', () => {
    const { service } = makeService(null);
    jest.spyOn(service, 'calculateDistance').mockReturnValue(1.9);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2.0 },
      { lat: 12.91, lng: 77.61, timestamp: new Date().toISOString() },
    );
    expect(res.progressing).toBe(false);
  });

  it('passes when closed enough vs accept snapshot', () => {
    const { service } = makeService(null);
    jest.spyOn(service, 'calculateDistance').mockReturnValue(1.5);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6, acceptDistanceKm: 2.0 },
      { lat: 12.91, lng: 77.61, timestamp: new Date().toISOString() },
    );
    expect(res.progressing).toBe(true);
  });

  it('uses legacy 5km rule without accept baseline', () => {
    const { service } = makeService(null);
    jest.spyOn(service, 'calculateDistance').mockReturnValue(1.9);
    const res = service.evaluateWorkerProgress(
      { serviceLat: 12.9, serviceLng: 77.6 },
      { lat: 12.91, lng: 77.61, timestamp: new Date().toISOString() },
    );
    expect(res.progressing).toBe(true);
  });
});
