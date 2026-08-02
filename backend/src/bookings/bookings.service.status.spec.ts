import { NotFoundException } from '@nestjs/common';
import { BookingStatusService } from './booking-status.service';
import { BookingStatus } from './booking.entity';

/**
 * Focused coverage for getStatusForParticipant — including operatorLat/Lng
 * from Redis so the customer map poll fallback has live worker GPS.
 */
function makeService(
  opts: {
    cached?: any;
    booking?: any;
    workerLoc?: { lat: number; lng: number } | null;
  } = {},
) {
  const redisService: any = {
    getCachedBookingStatus: jest.fn(async () => opts.cached ?? null),
    cacheBookingStatus: jest.fn(async () => undefined),
    getWorkerLocation: jest.fn(async () => opts.workerLoc ?? null),
  };
  const bookingsRepository: any = {
    findOne: jest.fn(async () => opts.booking ?? null),
  };
  const messagesGateway: any = {
    emitUserEvent: jest.fn(),
  };
  const service = new BookingStatusService(
    bookingsRepository,
    redisService,
    messagesGateway,
  );
  // getBookingById is used on cache miss — stub via prototype if needed.
  if (opts.booking !== undefined) {
    jest.spyOn(service, 'getBookingById').mockResolvedValue(opts.booking);
  } else {
    jest.spyOn(service, 'getBookingById').mockResolvedValue(null as any);
  }
  return { service, redisService };
}

describe('BookingStatusService.getStatusForParticipant', () => {
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
        customer: { id: 'cust-1', phoneNumber: '+919900000001' },
        operator: { id: 'op-9', name: 'Ravi', phoneNumber: '+919900000009' },
        arrivalOtp: '9999',
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
    expect(res.counterpartPhone).toBe('+919900000009');
    expect(redisService.cacheBookingStatus).toHaveBeenCalled();
  });

  it('returns role-aware counterpartPhone from cache', async () => {
    const { service } = makeService({
      cached: {
        status: 'ACCEPTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        customerPhone: '+919911111111',
        operatorPhone: '+919922222222',
      },
    });
    const asCustomer = await service.getStatusForParticipant('b1', 'cust-1');
    expect(asCustomer.counterpartPhone).toBe('+919922222222');
    const asWorker = await service.getStatusForParticipant('b1', 'op-1');
    expect(asWorker.counterpartPhone).toBe('+919911111111');
  });

  it('prefers on-site contact phone for the worker', async () => {
    const { service } = makeService({
      booking: {
        status: BookingStatus.ACCEPTED,
        customer: { id: 'cust-1', phoneNumber: '+919911111111' },
        operator: { id: 'op-1', phoneNumber: '+919922222222' },
        onSiteContact: { name: 'Anu', relation: 'Self', phone: '9876543210' },
      },
    });
    const res = await service.getStatusForParticipant('b1', 'op-1');
    expect(res.counterpartPhone).toBe('9876543210');
  });

  it('enriches missing phones from DB when cache is stale', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'ACCEPTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        operatorName: 'Asha',
      },
      booking: {
        status: BookingStatus.ACCEPTED,
        customer: { id: 'cust-1', phoneNumber: '+919911111111' },
        operator: { id: 'op-1', name: 'Asha', phoneNumber: '+919933333333' },
      },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.counterpartPhone).toBe('+919933333333');
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
