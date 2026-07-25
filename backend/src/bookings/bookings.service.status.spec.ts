import { NotFoundException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Focused coverage for getStatusForParticipant — including operatorLat/Lng
 * from Redis so the customer map poll fallback has live worker GPS.
 */
function makeService(opts: {
  cached?: any;
  booking?: any;
  workerLoc?: { lat: number; lng: number } | null;
} = {}) {
  const redisService: any = {
    getCachedBookingStatus: jest.fn(async () => opts.cached ?? null),
    cacheBookingStatus: jest.fn(async () => undefined),
    getWorkerLocation: jest.fn(async () => opts.workerLoc ?? null),
  };
  const bookingsRepository: any = {
    findOne: jest.fn(async () => opts.booking ?? null),
  };
  const service = new BookingsService(
    bookingsRepository,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    redisService,
    {} as any,
    {} as any,
    { emitUserEvent: jest.fn() } as any,
    {
      append: jest.fn(async () => ({ id: 'ob' })),
      enqueueDispatch: jest.fn(async () => undefined),
    } as any,
  );
  // getBookingById is used on cache miss — stub via prototype if needed.
  if (opts.booking !== undefined) {
    jest
      .spyOn(service, 'getBookingById')
      .mockResolvedValue(opts.booking as any);
  } else {
    jest.spyOn(service, 'getBookingById').mockResolvedValue(null as any);
  }
  return { service, redisService };
}

describe('BookingsService.getStatusForParticipant', () => {
  it('attaches Redis operator coords for ACCEPTED customer polls', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'ACCEPTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        operatorName: 'Asha',
        arrivalOtp: '1234',
      },
      workerLoc: { lat: 12.97, lng: 77.59 },
    });

    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(redisService.getWorkerLocation).toHaveBeenCalledWith('op-1');
    expect(res.operatorLat).toBe(12.97);
    expect(res.operatorLng).toBe(77.59);
    expect(res.arrivalOtp).toBe('1234');
  });

  it('returns null operator coords when Redis has no location', async () => {
    const { service } = makeService({
      cached: {
        status: 'ACCEPTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
      },
      workerLoc: null,
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.operatorLat).toBeNull();
    expect(res.operatorLng).toBeNull();
  });

  it('skips operator coords for non-tracking statuses', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'COMPLETED',
        customerId: 'cust-1',
        operatorId: 'op-1',
      },
      workerLoc: { lat: 1, lng: 2 },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(redisService.getWorkerLocation).not.toHaveBeenCalled();
    expect(res.operatorLat).toBeNull();
    expect(res.operatorLng).toBeNull();
  });

  it('returns payment confirm flags from Redis cache', async () => {
    const { service } = makeService({
      cached: {
        status: 'COMPLETED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        isPaid: false,
        workerPaidConfirmed: true,
        customerPaidConfirmed: false,
      },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.isPaid).toBe(false);
    expect(res.workerPaidConfirmed).toBe(true);
    expect(res.customerPaidConfirmed).toBe(false);
  });

  it('falls back to DB and still attaches Redis coords', async () => {
    const { service, redisService } = makeService({
      booking: {
        status: BookingStatus.ARRIVED,
        customer: { id: 'cust-1' },
        operator: { id: 'op-9', name: 'Ravi' },
        arrivalOtp: '9999',
        pauseRequestedAt: null,
        pausedAt: null,
        pausedMinutes: 0,
        isPaid: false,
        workerPaidConfirmed: false,
        customerPaidConfirmed: false,
      },
      workerLoc: { lat: 13.1, lng: 77.2 },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.status).toBe(BookingStatus.ARRIVED);
    expect(res.operatorId).toBe('op-9');
    expect(res.operatorLat).toBe(13.1);
    expect(res.operatorLng).toBe(77.2);
    expect(redisService.cacheBookingStatus).toHaveBeenCalled();
  });

  it('throws NotFound for a stranger', async () => {
    const { service } = makeService({
      booking: {
        status: BookingStatus.ACCEPTED,
        customer: { id: 'cust-1' },
        operator: { id: 'op-1' },
      },
    });
    await expect(
      service.getStatusForParticipant('b1', 'stranger'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
