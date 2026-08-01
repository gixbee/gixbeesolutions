import { BadRequestException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Late-cancel gates, cancel-request, and distance compensation freeze.
 */
function makeService(booking: any, userOver: any = {}) {
  const bookingsRepository: any = {
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
  };
  const workerProfileRepo: any = {
    findOne: jest.fn(async () => ({ lastLat: 12.97, lastLng: 77.59 })),
  };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    reverseBookingTransfer: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const redisService: any = {
    getWorkerLocation: jest.fn(async () => ({ lat: 12.97, lng: 77.59 })),
    cacheBookingStatus: jest.fn(async () => undefined),
    getCachedBookingStatus: jest.fn(async () => null),
  };
  const workersService: any = {};
  const customer = {
    id: 'cust-1',
    lateCancelStrikeCount: 0,
    instantHelpBlocked: false,
    ...userOver,
  };
  const usersRepo: any = {
    findOne: jest.fn(async () => ({ ...customer })),
    save: jest.fn(async (u: any) => u),
  };
  const manager: any = {
    save: jest.fn(async (b: any) => b),
    getRepository: jest.fn(() => usersRepo),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
    getRepository: jest.fn(() => usersRepo),
  };
  const outboxService: any = {
    append: jest.fn(async () => ({ id: 'ob1' })),
    enqueueDispatch: jest.fn(async () => undefined),
  };
  const jobCreditsService: any = {
    refundCredit: jest.fn(async () => undefined),
  };
  const masterEntriesService: any = {
    getConfigNumber: jest.fn(async (_k: string, f: number) => f),
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
    { emitUserEvent: jest.fn() } as any,
    outboxService,
    jobCreditsService,
    masterEntriesService,
  );
  return {
    service,
    bookingsRepository,
    notificationsService,
    usersRepo,
    redisService,
  };
}

const booking = (over: any = {}) => ({
  id: 'b1',
  status: BookingStatus.ACCEPTED,
  isPaid: false,
  paymentMethod: 'CASH',
  amount: 200,
  serviceLat: 12.9,
  serviceLng: 77.6,
  acceptedAt: new Date(Date.now() - 10 * 60 * 1000), // past grace
  cancelRequestedAt: null,
  customer: { id: 'cust-1', name: 'Cust' },
  operator: { id: 'work-1', name: 'Pro' },
  ...over,
});

describe('BookingsService late-cancel gates', () => {
  it('blocks unilateral cancel when ARRIVED', async () => {
    const { service } = makeService(booking({ status: BookingStatus.ARRIVED }));
    await expect(service.cancelBooking('b1', 'nope')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('blocks unilateral cancel when ACTIVE', async () => {
    const { service } = makeService(booking({ status: BookingStatus.ACTIVE }));
    await expect(service.cancelBooking('b1', 'nope')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('allows free cancel within grace', async () => {
    const { service } = makeService(
      booking({ acceptedAt: new Date() }), // now — in grace
    );
    const res = await service.cancelBooking('b1', 'changed mind');
    expect(res.status).toBe('CANCELLED');
    expect(res.lateCancelStrike).toBeUndefined();
  });

  it('records a late-cancel strike after grace', async () => {
    const { service } = makeService(booking(), { lateCancelStrikeCount: 0 });
    const res = await service.cancelBooking('b1', 'late');
    expect(res.lateCancelStrike).toBe(true);
    expect(res.strikeCount).toBe(1);
    expect(res.instantHelpBlocked).toBeFalsy();
  });

  it('blocks Instant Help and freezes distance compensation on 3rd strike', async () => {
    const { service } = makeService(booking(), { lateCancelStrikeCount: 2 });
    const res = await service.cancelBooking('b1', 'late again');
    expect(res.strikeCount).toBe(3);
    expect(res.instantHelpBlocked).toBe(true);
    expect(res.compensationAmount).toBeGreaterThanOrEqual(49);
    expect(res.compensationAmount).toBeLessThanOrEqual(299);
  });

  it('mutual approve cancels without strike', async () => {
    const b = booking({
      status: BookingStatus.ARRIVED,
      cancelRequestedAt: new Date(),
    });
    const { service } = makeService(b);
    const res = await service.approveCancelRequest('b1', 'work-1');
    expect(res.status).toBe('CANCELLED');
    expect(res.lateCancelStrike).toBeUndefined();
  });

  it('requestCancel notifies the worker', async () => {
    const { service, notificationsService } = makeService(
      booking({ status: BookingStatus.ACTIVE }),
    );
    const res = await service.requestCancel('b1', 'cust-1', 'emergency');
    expect(res.cancelRequested).toBe(true);
    expect(notificationsService.sendToUser).toHaveBeenCalledWith(
      'work-1',
      expect.objectContaining({
        data: expect.objectContaining({ type: 'cancel_requested' }),
      }),
    );
  });

  it('allows free cancel with no strike/credit refund when workerNoProgressAt is set', async () => {
    const b = booking({ workerNoProgressAt: new Date() });
    const { service } = makeService(b);
    const jobCredits = (service as any).jobCreditsService;
    const res = await service.cancelBooking('b1', 'pro not moving');
    expect(res.status).toBe('CANCELLED');
    expect(res.lateCancelStrike).toBeUndefined();
    expect(res.workerNoProgress).toBe(true);
    expect(jobCredits.refundCredit).not.toHaveBeenCalled();
    expect(b.cancellationReason).toContain('WORKER_NO_PROGRESS');
  });
});
