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
  const masterEntriesService: any = {
    getConfigNumber: jest.fn(async (_k: string, fallback: number) => fallback),
  };
  const service = new BookingStatusService(
    bookingsRepository,
    redisService,
    messagesGateway,
    masterEntriesService,
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

  it('repairs a stale single-party confirmation after both participants have paid', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'COMPLETED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        isPaid: false,
        workerPaidConfirmed: true,
        customerPaidConfirmed: false,
      },
      booking: {
        status: BookingStatus.COMPLETED,
        customer: { id: 'cust-1' },
        operator: { id: 'op-1' },
        isPaid: true,
        workerPaidConfirmed: true,
        customerPaidConfirmed: true,
      },
    });
    const result = await service.getStatusForParticipant('b1', 'cust-1');
    expect(result.isPaid).toBe(true);
    expect(result.customerPaidConfirmed).toBe(true);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({ isPaid: true }),
    );
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
    expect(redisService.cacheBookingStatus).toHaveBeenCalled();
  });

  /**
   * NUMBER MASKING — participants reach each other over in-app voice, so the
   * status payload must never carry a dialable number for either side or for
   * the on-site contact.
   */
  it('never exposes a counterpart phone number to either role', async () => {
    const { service } = makeService({
      booking: {
        status: BookingStatus.ACCEPTED,
        customer: { id: 'cust-1', phoneNumber: '+919911111111' },
        operator: { id: 'op-1', phoneNumber: '+919922222222' },
        onSiteContact: { name: 'Anu', relation: 'Self', phone: '9876543210' },
      },
    });
    const asCustomer = await service.getStatusForParticipant('b1', 'cust-1');
    const asWorker = await service.getStatusForParticipant('b1', 'op-1');

    for (const res of [asCustomer, asWorker]) {
      const serialized = JSON.stringify(res);
      expect(serialized).not.toContain('+919911111111');
      expect(serialized).not.toContain('+919922222222');
      expect(serialized).not.toContain('9876543210');
    }
  });

  it('repairs a stale live status from DB without leaking phones', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'ACCEPTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        operatorName: 'Stale',
      },
      booking: {
        status: BookingStatus.COMPLETED,
        customer: { id: 'cust-1', phoneNumber: '+919911111111' },
        operator: { id: 'op-1', name: 'Asha', phoneNumber: '+919933333333' },
      },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.status).toBe('COMPLETED');
    expect(res.operatorName).toBe('Asha');
    expect(JSON.stringify(res)).not.toContain('+919933333333');
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

  it('revalidates stale REQUESTED cache when DB is already ACCEPTED', async () => {
    const { service, redisService } = makeService({
      cached: {
        status: 'REQUESTED',
        customerId: 'cust-1',
        operatorId: 'op-1',
        operatorName: null,
      },
      booking: {
        status: BookingStatus.ACCEPTED,
        customer: { id: 'cust-1', phoneNumber: '+919911111111' },
        operator: { id: 'op-1', name: 'Asha', phoneNumber: '+919922222222' },
        arrivalOtp: '4321',
        isPaid: false,
        workerPaidConfirmed: false,
        customerPaidConfirmed: false,
      },
      workerLoc: { lat: 12.9, lng: 77.6 },
    });
    const res = await service.getStatusForParticipant('b1', 'cust-1');
    expect(res.status).toBe('ACCEPTED');
    expect(res.operatorName).toBe('Asha');
    expect(res.arrivalOtp).toBe('4321');
    expect(res.operatorLat).toBe(12.9);
    expect(redisService.cacheBookingStatus).toHaveBeenCalled();
  });
});
