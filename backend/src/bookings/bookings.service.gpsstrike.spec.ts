import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Unit tests for addGpsStrike — the 3-strike GPS forfeit path:
 * - guards:
 *     missing booking            → returns undefined, no save, no notify
 *     non-ACTIVE/ACCEPTED status → returns undefined, no save, no notify
 * - 1st/2nd strike: counter increments, booking saved once, a GPS-strike
 *     notification is sent, status stays ACCEPTED, returns
 *     { cancelled: false, strikes: n }
 * - 3rd strike (forfeit): booking → CANCELLED, status cached in redis,
 *     customer notified of cancellation, operator notified of forfeit,
 *     worker released to 'available', returns { cancelled: true, strikes: 3 }
 *
 * addGpsStrike reads/writes via the plain bookingsRepository (no
 * transaction), so the mock just needs a findOne + save and the
 * notification / redis / workers collaborators.
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
    notificationsService,
    redisService,
    workersService,
  };
}

const baseBooking = (overrides: Partial<any> = {}) => ({
  id: 'b1',
  status: BookingStatus.ACCEPTED,
  gpsStrikes: 0,
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
    expect(notificationsService.notifyBookingCancelled).not.toHaveBeenCalled();
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

  it('records a first strike without forfeiting', async () => {
    const booking = baseBooking({ gpsStrikes: 0 });
    const { service, bookingsRepository, notificationsService, workersService } =
      makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({ cancelled: false, strikes: 1 });
    expect(booking.gpsStrikes).toBe(1);
    expect(booking.status).toBe(BookingStatus.ACCEPTED);
    expect(bookingsRepository.save).toHaveBeenCalledTimes(1);
    expect(notificationsService.notifyGpsStrike).toHaveBeenCalledWith(
      'work-1',
      1,
    );
    expect(notificationsService.notifyBookingCancelled).not.toHaveBeenCalled();
    expect(workersService.setWorkerStatus).not.toHaveBeenCalled();
  });

  it('records a second strike without forfeiting', async () => {
    const booking = baseBooking({ gpsStrikes: 1 });
    const { service, notificationsService } = makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({ cancelled: false, strikes: 2 });
    expect(booking.gpsStrikes).toBe(2);
    expect(notificationsService.notifyGpsStrike).toHaveBeenCalledWith(
      'work-1',
      2,
    );
  });

  it('forfeits the job on the third strike', async () => {
    const booking = baseBooking({ gpsStrikes: 2 });
    const {
      service,
      bookingsRepository,
      notificationsService,
      redisService,
      workersService,
    } = makeService(booking);

    const res = await service.addGpsStrike('b1');

    expect(res).toEqual({ cancelled: true, strikes: 3 });
    expect(booking.gpsStrikes).toBe(3);
    expect(booking.status).toBe(BookingStatus.CANCELLED);
    // increment save + forfeit save
    expect(bookingsRepository.save).toHaveBeenCalledTimes(2);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', {
      status: 'CANCELLED',
      operatorName: 'Asha',
      operatorId: 'work-1',
      customerId: 'cust-1',
    });
    expect(notificationsService.notifyBookingCancelled).toHaveBeenCalledWith(
      'cust-1',
    );
    expect(notificationsService.sendToUser).toHaveBeenCalledWith(
      'work-1',
      expect.objectContaining({
        title: 'Booking Forfeited',
        data: { type: 'booking_forfeited', bookingId: 'b1' },
      }),
    );
    expect(workersService.setWorkerStatus).toHaveBeenCalledWith(
      'work-1',
      'available',
    );
    // the per-strike notification is NOT sent on the forfeit path
    expect(notificationsService.notifyGpsStrike).not.toHaveBeenCalled();
  });
});
