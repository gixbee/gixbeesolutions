import { BookingBroadcastService } from './booking-broadcast.service';
import { BookingStatus, BookingType } from './booking.entity';

/**
 * Broadcast Instant Help dispatch. The outbox owns the pro-side push/socket
 * fan-out, but the customer's status cache and the pros' pending queues are
 * written inline so nothing is invisible between commit and the outbox worker.
 */
function makeService(nearby: any[] = [{ id: 'w-1', distance_km: 1 }]) {
  const saved = {
    id: 'b-1',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
  };
  const manager: any = {
    create: jest.fn((_entity: any, data: any) => ({ ...data })),
    save: jest.fn(async (row: any) => ({ ...row, ...saved })),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
    getRepository: jest.fn(() => ({
      findOne: jest.fn(async () => ({ id: 'cust-1', name: 'Asha Rao' })),
    })),
  };
  const calls: string[] = [];
  const redisService: any = {
    addPendingBooking: jest.fn(async () => {
      calls.push('pending');
    }),
    get: jest.fn(async () => null),
  };
  const outboxService: any = {
    append: jest.fn(async () => ({ id: 'ob-1' })),
    enqueueDispatch: jest.fn(async () => {
      calls.push('dispatch');
    }),
  };
  const bookingStatusService: any = {
    cacheAndEmitBookingStatus: jest.fn(async () => {
      calls.push('status');
    }),
    getBookingById: jest.fn(async () => null),
  };
  const service = new BookingBroadcastService(
    { add: jest.fn(async () => undefined) } as any,
    { sendToUser: jest.fn(async () => undefined) } as any,
    redisService,
    { getNearby: jest.fn(async () => nearby) } as any,
    dataSource,
    { emitUserEvent: jest.fn() } as any,
    outboxService,
    bookingStatusService,
  );
  return {
    service,
    calls,
    redisService,
    outboxService,
    bookingStatusService,
  };
}

const createData = {
  skill: 'Plumber',
  serviceLocation: 'HSR Layout',
  serviceLat: 12.91,
  serviceLng: 77.64,
  amount: 250,
};

describe('BookingBroadcastService.createBroadcastBooking', () => {
  it('publishes the open request and the pending offers before the outbox kick', async () => {
    const { service, calls, redisService, bookingStatusService } = makeService([
      { id: 'w-1', distance_km: 1 },
      { id: 'w-2', distance_km: 2 },
    ]);

    const res = await service.createBroadcastBooking('cust-1', createData);

    expect(res.notified).toBe(2);
    expect(bookingStatusService.cacheAndEmitBookingStatus).toHaveBeenCalledWith(
      'b-1',
      expect.objectContaining({
        status: 'REQUESTED',
        operatorId: null,
        customerId: 'cust-1',
      }),
    );
    expect(redisService.addPendingBooking).toHaveBeenCalledWith('w-1', 'b-1');
    expect(redisService.addPendingBooking).toHaveBeenCalledWith('w-2', 'b-1');
    // Inline publish first, outbox kick last.
    expect(calls[calls.length - 1]).toBe('dispatch');
    expect(calls.indexOf('status')).toBeLessThan(calls.indexOf('dispatch'));
  });

  it('still returns the booking when the inline publish fails', async () => {
    const { service, bookingStatusService, outboxService } = makeService();
    bookingStatusService.cacheAndEmitBookingStatus.mockRejectedValueOnce(
      new Error('redis down'),
    );

    const res = await service.createBroadcastBooking('cust-1', createData);

    expect(res.booking.id).toBe('b-1');
    // The outbox is the safety net — it must still be kicked.
    expect(outboxService.enqueueDispatch).toHaveBeenCalledWith('ob-1');
  });
});

describe('BookingBroadcastService.rebroadcastBooking', () => {
  it('registers the widened wave as pending before the outbox kick', async () => {
    const { service, calls, redisService, bookingStatusService } = makeService([
      { id: 'w-9', distance_km: 6 },
    ]);
    bookingStatusService.getBookingById.mockResolvedValueOnce({
      id: 'b-1',
      status: BookingStatus.REQUESTED,
      type: BookingType.INSTANT,
      operator: null,
      customer: { id: 'cust-1', name: 'Asha Rao' },
      skill: 'Plumber',
      serviceLocation: 'HSR Layout',
      serviceLat: 12.91,
      serviceLng: 77.64,
      amount: 250,
      arrivalOtp: '1234',
      completionOtp: '5678',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    });

    const res = await service.rebroadcastBooking('b-1');

    expect(res).toEqual({ stillOpen: true, notified: 1 });
    expect(redisService.addPendingBooking).toHaveBeenCalledWith('w-9', 'b-1');
    expect(calls.indexOf('pending')).toBeLessThan(calls.indexOf('dispatch'));
  });

  it('does nothing once the request is no longer open', async () => {
    const { service, redisService, outboxService, bookingStatusService } =
      makeService();
    bookingStatusService.getBookingById.mockResolvedValueOnce({
      id: 'b-1',
      status: BookingStatus.ACCEPTED,
      type: BookingType.INSTANT,
      operator: { id: 'w-1' },
    });

    const res = await service.rebroadcastBooking('b-1');

    expect(res).toEqual({ stillOpen: false, notified: 0 });
    expect(redisService.addPendingBooking).not.toHaveBeenCalled();
    expect(outboxService.enqueueDispatch).not.toHaveBeenCalled();
  });
});
