import { BadRequestException, NotFoundException } from '@nestjs/common';
import { In } from 'typeorm';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';

/**
 * Service-level unit tests for BookingsService covering the methods NOT
 * exercised by the four method-specific specs (accept / cancel / complete /
 * gpsstrike):
 *   createBooking · rejectBooking · updateStatus · findPendingForWorker ·
 *   verifyArrivalOtp · markPaid · refreshCompletionOtp · submitRating ·
 *   getBookingById · findAllByUser
 *
 * Direct-construction harness (no Nest TestingModule); every collaborator is a
 * plain jest mock so each test can assert exactly which side effects fired.
 */
function makeService() {
  const queryBuilder: any = {
    leftJoinAndSelect: jest.fn(() => queryBuilder),
    where: jest.fn(() => queryBuilder),
    andWhere: jest.fn(() => queryBuilder),
    orderBy: jest.fn(() => queryBuilder),
    skip: jest.fn(() => queryBuilder),
    take: jest.fn(() => queryBuilder),
    setLock: jest.fn(() => queryBuilder),
    getOne: jest.fn(async () => null),
    getMany: jest.fn(async () => []),
  };
  const bookingsRepository: any = {
    findOne: jest.fn(async () => null),
    find: jest.fn(async () => []),
    create: jest.fn((b: any) => ({ ...b })),
    save: jest.fn(async (b: any) => b),
    createQueryBuilder: jest.fn(() => queryBuilder),
  };
  const workerProfileQb: any = {
    setLock: jest.fn(() => workerProfileQb),
    where: jest.fn(() => workerProfileQb),
    getOne: jest.fn(async () => null),
  };
  const workerProfileRepo: any = {
    findOne: jest.fn(async () => null),
    save: jest.fn(async (p: any) => p),
    createQueryBuilder: jest.fn(() => workerProfileQb),
  };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    reverseBookingTransfer: jest.fn(async () => undefined),
    transferForBooking: jest.fn(async () => undefined),
    addFunds: jest.fn(async () => 0),
    deductBookingFee: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
    sendToUsers: jest.fn(async () => undefined),
    notifyWorkerNewBooking: jest.fn(async () => undefined),
    notifyBookingCancelled: jest.fn(async () => undefined),
    notifyCustomerJobComplete: jest.fn(async () => undefined),
    notifyGpsStrike: jest.fn(async () => undefined),
  };
  const redisService: any = {
    saveOtp: jest.fn(async () => undefined),
    deleteOtp: jest.fn(async () => undefined),
    addPendingBooking: jest.fn(async () => undefined),
    removePendingBooking: jest.fn(async () => undefined),
    getPendingBookingIds: jest.fn(async () => []),
    cacheBookingStatus: jest.fn(async () => undefined),
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => {
      const manager = {
        getRepository: (entity: any) =>
          entity === WorkerProfile ? workerProfileRepo : bookingsRepository,
        save: jest.fn(async (b: any) => {
          if (typeof bookingsRepository.save === 'function') {
            return bookingsRepository.save(b);
          }
          return b;
        }),
        create: jest.fn((_e: any, data: any) => data),
      };
      return cb(manager);
    }),
  };

  const outboxService: any = {
    append: jest.fn(
      async (_m: any, type: string, aggregateId: string, payload: any) => ({
        id: 'ob',
        type,
        aggregateId,
        payload,
      }),
    ),
    enqueueDispatch: jest.fn(async () => undefined),
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
    { consumeCredit: jest.fn(), refundCredit: jest.fn() } as any,
    { getConfigNumber: jest.fn(async (_k: string, f: number) => f) } as any,
  );
  return {
    service,
    bookingsRepository,
    workerProfileRepo,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    dataSource,
    queryBuilder,
    workerProfileQb,
    outboxService,
  };
}

describe('BookingsService.createBooking', () => {
  it('refuses self-booking when customer === operator', async () => {
    const { service, bookingsRepository } = makeService();

    await expect(
      service.createBooking({
        customer: { id: 'u1' } as any,
        operator: { id: 'u1' } as any,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  it('rejects booking a worker already on an ACTIVE/ARRIVED job', async () => {
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce({ id: 'active-job' });

    await expect(
      service.createBooking({
        customer: { id: 'cust-1' } as any,
        operator: { id: 'work-1' } as any,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  it('creates a REQUESTED booking with OTPs, schedules timeout, notifies + caches', async () => {
    const ctx = makeService();
    const {
      service,
      bookingsRepository,
      redisService,
      bookingsQueue,
      notificationsService,
    } = ctx;
    bookingsRepository.findOne.mockResolvedValueOnce(null); // no active job
    bookingsRepository.save.mockImplementationOnce(async (b: any) => ({
      ...b,
      id: 'new-1',
    }));

    const result = await service.createBooking({
      customer: { id: 'cust-1' } as any,
      operator: { id: 'work-1' } as any,
      skill: 'Plumbing',
    } as any);

    expect(result.id).toBe('new-1');
    const created = bookingsRepository.create.mock.calls[0][0];
    expect(created.status).toBe(BookingStatus.REQUESTED);
    expect(created.arrivalOtp).toMatch(/^\d{4}$/);
    expect(created.completionOtp).toMatch(/^\d{4}$/);
    // OTPs persisted to redis under the saved booking id
    expect(redisService.saveOtp).toHaveBeenCalledWith(
      'otp:booking:new-1:arrival',
      created.arrivalOtp,
    );
    expect(redisService.saveOtp).toHaveBeenCalledWith(
      'otp:booking:new-1:completion',
      created.completionOtp,
    );
    // 90s request timeout scheduled with stable jobId (dedupe across retries)
    expect(bookingsQueue.add).toHaveBeenCalledWith(
      'requestTimeout',
      { bookingId: 'new-1', attempt: 1 },
      {
        jobId: 'requestTimeout:new-1',
        delay: 90 * 1000,
        removeOnComplete: true,
      },
    );
    expect(redisService.addPendingBooking).toHaveBeenCalledWith(
      'work-1',
      'new-1',
    );
    expect(notificationsService.notifyWorkerNewBooking).toHaveBeenCalledWith(
      'work-1',
      'new-1',
      'Plumbing',
    );
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('new-1', {
      status: 'REQUESTED',
      operatorName: null,
      operatorId: 'work-1',
      customerId: 'cust-1',
      arrivalOtp: expect.any(String),
    });
  });

  it('defaults the notification skill to "General Help" when none supplied', async () => {
    const { service, bookingsRepository, notificationsService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(null);
    bookingsRepository.save.mockImplementationOnce(async (b: any) => ({
      ...b,
      id: 'new-2',
    }));

    await service.createBooking({
      customer: { id: 'cust-1' } as any,
      operator: { id: 'work-1' } as any,
    } as any);

    expect(notificationsService.notifyWorkerNewBooking).toHaveBeenCalledWith(
      'work-1',
      'new-2',
      'General Help',
    );
  });

  it('skips the active-job check, pending list and worker notify when there is no operator', async () => {
    const { service, bookingsRepository, redisService, notificationsService } =
      makeService();
    bookingsRepository.save.mockImplementationOnce(async (b: any) => ({
      ...b,
      id: 'new-3',
    }));

    await service.createBooking({ customer: { id: 'cust-1' } as any } as any);

    // no operator → no active-job lookup, no pending add, no worker notify
    expect(bookingsRepository.findOne).not.toHaveBeenCalled();
    expect(redisService.addPendingBooking).not.toHaveBeenCalled();
    expect(notificationsService.notifyWorkerNewBooking).not.toHaveBeenCalled();
    // status is still cached
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('new-3', {
      status: 'REQUESTED',
      operatorName: null,
      operatorId: null,
      customerId: 'cust-1',
      arrivalOtp: expect.any(String),
    });
  });

  it('accepts bare-string customer/operator ids (not wrapped objects)', async () => {
    const { service, bookingsRepository } = makeService();
    // same id as string on both → self-booking guard
    await expect(
      service.createBooking({ customer: 'u9' as any, operator: 'u9' as any }),
    ).rejects.toThrow(BadRequestException);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  it('carries the picked saved-address id (addressId) through to the created booking (P107)', async () => {
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(null); // no active job
    bookingsRepository.save.mockImplementationOnce(async (b: any) => ({
      ...b,
      id: 'new-4',
    }));

    await service.createBooking({
      customer: { id: 'cust-1' } as any,
      operator: { id: 'work-1' } as any,
      serviceLocation: '12 MG Road, Bengaluru',
      addressId: 'addr-7',
    } as any);

    const created = bookingsRepository.create.mock.calls[0][0];
    // the FK-by-id to the chosen saved Address is persisted onto the entity …
    expect(created.addressId).toBe('addr-7');
    // … alongside the independent resolved free-text location it does NOT replace
    expect(created.serviceLocation).toBe('12 MG Road, Bengaluru');
  });

  it('leaves addressId undefined when the customer free-typed an address (P107)', async () => {
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(null);
    bookingsRepository.save.mockImplementationOnce(async (b: any) => ({
      ...b,
      id: 'new-5',
    }));

    await service.createBooking({
      customer: { id: 'cust-1' } as any,
      operator: { id: 'work-1' } as any,
      serviceLocation: 'Some free-text place',
    } as any);

    const created = bookingsRepository.create.mock.calls[0][0];
    expect(created.addressId).toBeUndefined();
    expect(created.serviceLocation).toBe('Some free-text place');
  });
});

describe('BookingsService.rejectBooking', () => {
  it('404s when worker was never notified and is not the assigned operator', async () => {
    const { service, bookingsRepository, redisService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce({
      id: 'b1',
      status: BookingStatus.REQUESTED,
      operator: null,
      customer: { id: 'cust-1' },
    });
    redisService.getPendingBookingIds.mockResolvedValueOnce([]);
    redisService.get.mockResolvedValueOnce(null);
    await expect(service.rejectBooking('b1', 'work-1')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('rejects declining a booking that is not REQUESTED', async () => {
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce({
      id: 'b1',
      status: BookingStatus.ACCEPTED,
      operator: { id: 'work-1' },
      customer: { id: 'cust-1' },
    });
    await expect(service.rejectBooking('b1', 'work-1')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('declines a targeted REQUESTED booking: REJECTED, redis cleared, customer notified', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.REQUESTED,
      operator: { id: 'work-1' },
      customer: { id: 'cust-1' },
    };
    const { service, bookingsRepository, redisService, notificationsService } =
      makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    const res = await service.rejectBooking('b1', 'work-1');

    expect(booking.status).toBe(BookingStatus.REJECTED);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(redisService.removePendingBooking).toHaveBeenCalledWith(
      'work-1',
      'b1',
    );
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', {
      status: 'REJECTED',
      operatorName: null,
      operatorId: 'work-1',
      customerId: 'cust-1',
    });
    expect(notificationsService.notifyBookingCancelled).toHaveBeenCalledWith(
      'cust-1',
      expect.any(String),
    );
    expect(res.message).toBe('Booking declined.');
  });

  it('broadcast decline: removes only this worker, keeps REQUESTED for others', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.REQUESTED,
      operator: null,
      customer: { id: 'cust-1' },
    };
    const { service, bookingsRepository, redisService, notificationsService } =
      makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);
    redisService.getPendingBookingIds.mockResolvedValueOnce(['b1']);
    redisService.get.mockResolvedValueOnce(
      JSON.stringify(['work-1', 'work-2']),
    );

    const res = await service.rejectBooking('b1', 'work-1');

    expect(booking.status).toBe(BookingStatus.REQUESTED);
    expect(bookingsRepository.save).not.toHaveBeenCalled();
    expect(redisService.removePendingBooking).toHaveBeenCalledWith(
      'work-1',
      'b1',
    );
    expect(redisService.set).toHaveBeenCalledWith(
      'booking:notified:b1',
      JSON.stringify(['work-2']),
      60 * 60,
    );
    expect(notificationsService.notifyBookingCancelled).not.toHaveBeenCalled();
    expect(res.message).toBe('Booking declined.');
  });

  it('broadcast decline via notified list even if Redis pending already empty', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.REQUESTED,
      operator: null,
      customer: { id: 'cust-1' },
    };
    const { service, bookingsRepository, redisService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);
    redisService.getPendingBookingIds.mockResolvedValueOnce([]);
    redisService.get.mockResolvedValueOnce(JSON.stringify(['work-1']));

    await service.rejectBooking('b1', 'work-1');

    expect(redisService.removePendingBooking).toHaveBeenCalledWith(
      'work-1',
      'b1',
    );
    expect(redisService.del).toHaveBeenCalledWith('booking:notified:b1');
    expect(booking.status).toBe(BookingStatus.REQUESTED);
  });

  it('does not notify when a targeted reject has no customer', async () => {
    const { service, bookingsRepository, notificationsService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce({
      id: 'b1',
      status: BookingStatus.REQUESTED,
      operator: { id: 'work-1' },
      customer: null,
    });
    await service.rejectBooking('b1', 'work-1');
    expect(notificationsService.notifyBookingCancelled).not.toHaveBeenCalled();
  });
});

describe('BookingsService.updateStatus', () => {
  it('returns null when the booking does not exist', async () => {
    const { service, bookingsRepository } = makeService();
    const res = await service.updateStatus('missing', BookingStatus.ACTIVE);
    expect(res).toBeNull();
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  it('updates status, caches arrivalOtp only when ACCEPTED, keeps pending list', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.REQUESTED,
      arrivalOtp: '1234',
      operator: { id: 'work-1', name: 'Wendy' },
    };
    const { service, bookingsRepository, redisService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    await service.updateStatus('b1', BookingStatus.ACCEPTED);

    expect(booking.status).toBe(BookingStatus.ACCEPTED);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', {
      status: BookingStatus.ACCEPTED,
      operatorName: 'Wendy',
      operatorId: 'work-1',
      customerId: null,
      arrivalOtp: '1234',
    });
    // not a CANCELLED/REJECTED transition → pending list untouched
    expect(redisService.removePendingBooking).not.toHaveBeenCalled();
  });

  it('nulls cached arrivalOtp for non-ACCEPTED statuses', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.ACCEPTED,
      arrivalOtp: '1234',
      operator: { id: 'work-1', name: 'Wendy' },
    };
    const { service, bookingsRepository, redisService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    await service.updateStatus('b1', BookingStatus.ACTIVE);

    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', {
      status: BookingStatus.ACTIVE,
      operatorName: 'Wendy',
      operatorId: 'work-1',
      customerId: null,
      arrivalOtp: null,
    });
  });

  it('appends BOOKING_CANCELLED outbox when transitioning to CANCELLED', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.ACCEPTED,
      arrivalOtp: '1234',
      operator: { id: 'work-1', name: 'Wendy' },
      customer: { id: 'cust-1' },
    };
    const { service, bookingsRepository, redisService, outboxService } =
      makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    await service.updateStatus('b1', BookingStatus.CANCELLED);

    expect(outboxService.append).toHaveBeenCalledWith(
      expect.anything(),
      'booking.cancelled',
      'b1',
      expect.objectContaining({
        source: 'timeout',
        operatorId: 'work-1',
        customerId: 'cust-1',
      }),
    );
    expect(outboxService.enqueueDispatch).toHaveBeenCalledWith('ob');
    // Redis cleanup is listener-owned
    expect(redisService.removePendingBooking).not.toHaveBeenCalled();
  });
});

describe('BookingsService.findPendingForWorker', () => {
  it('returns redis-ordered bookings when redis has pending ids', async () => {
    const { service, bookingsRepository, redisService } = makeService();
    redisService.getPendingBookingIds.mockResolvedValueOnce(['b2', 'b1']);
    bookingsRepository.find.mockResolvedValueOnce([
      { id: 'b1', status: BookingStatus.REQUESTED },
      { id: 'b2', status: BookingStatus.REQUESTED },
    ]);

    const res = await service.findPendingForWorker('work-1');

    expect(bookingsRepository.find).toHaveBeenCalledWith({
      where: { id: In(['b2', 'b1']) },
      relations: ['customer', 'operator'],
    });
    // sorted to match redis order, not db order
    expect(res.map((b) => b.id)).toEqual(['b2', 'b1']);
    // redis was the source of truth → no re-population
    expect(redisService.addPendingBooking).not.toHaveBeenCalled();
  });

  it('falls back to a DB query and re-populates redis when redis is empty', async () => {
    const { service, bookingsRepository, redisService } = makeService();
    redisService.getPendingBookingIds.mockResolvedValueOnce([]);
    bookingsRepository.find.mockResolvedValueOnce([{ id: 'b7' }, { id: 'b8' }]);

    const res = await service.findPendingForWorker('work-1');

    expect(bookingsRepository.find).toHaveBeenCalledWith({
      where: { operator: { id: 'work-1' }, status: BookingStatus.REQUESTED },
      relations: ['customer', 'operator'],
      order: { createdAt: 'DESC' },
    });
    expect(res.map((b) => b.id)).toEqual(['b7', 'b8']);
    expect(redisService.addPendingBooking).toHaveBeenCalledWith('work-1', 'b7');
    expect(redisService.addPendingBooking).toHaveBeenCalledWith('work-1', 'b8');
  });

  it('returns an empty list and re-populates nothing when there is no pending work', async () => {
    const { service, bookingsRepository, redisService } = makeService();
    redisService.getPendingBookingIds.mockResolvedValueOnce([]);
    bookingsRepository.find.mockResolvedValueOnce([]);

    const res = await service.findPendingForWorker('work-1');

    expect(res).toEqual([]);
    expect(redisService.addPendingBooking).not.toHaveBeenCalled();
  });
});

describe('BookingsService.verifyArrivalOtp', () => {
  it('404s when the booking does not exist', async () => {
    const { service } = makeService();
    await expect(service.verifyArrivalOtp('b1', '1234')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('rejects a missing or mismatched OTP without saving', async () => {
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce({
      id: 'b1',
      arrivalOtp: '1234',
    });
    await expect(service.verifyArrivalOtp('b1', '9999')).rejects.toThrow(
      BadRequestException,
    );
    expect(bookingsRepository.save).not.toHaveBeenCalled();
  });

  it('activates the job, stamps startedAt and clears the redis OTP', async () => {
    const booking: any = {
      id: 'b1',
      arrivalOtp: '1234',
      status: BookingStatus.ACCEPTED,
    };
    const { service, bookingsRepository, redisService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    const res = await service.verifyArrivalOtp('b1', '1234');

    expect(booking.status).toBe(BookingStatus.ACTIVE);
    expect(booking.startedAt).toBeInstanceOf(Date);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(redisService.deleteOtp).toHaveBeenCalledWith(
      'otp:booking:b1:arrival',
    );
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', {
      status: 'ACTIVE',
      operatorName: null,
      operatorId: null,
      customerId: null,
    });
    expect(res.status).toBe('ACTIVE');
  });
});

describe('BookingsService.markPaid', () => {
  it('404s when the booking does not exist', async () => {
    const { service } = makeService();
    await expect(service.markPaid('b1', 'u1')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('records worker honesty confirm without flipping isPaid alone', async () => {
    const booking: any = {
      id: 'b1',
      isPaid: false,
      status: BookingStatus.COMPLETED,
      operator: { id: 'work-1' },
      customer: { id: 'cust-1' },
      workerPaidConfirmed: false,
      customerPaidConfirmed: false,
    };
    const { service, bookingsRepository, outboxService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    const res = await service.markPaid('b1', 'work-1', {
      honestyCheck: 'EXACT',
    });

    expect(booking.workerPaidConfirmed).toBe(true);
    expect(booking.workerHonestyCheck).toBe('EXACT');
    expect(booking.isPaid).toBe(false);
    expect(res.isPaid).toBe(false);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(outboxService.append).toHaveBeenCalledWith(
      expect.anything(),
      'booking.payment_confirmed',
      'b1',
      expect.objectContaining({ isPaid: false, workerPaidConfirmed: true }),
    );
    expect(outboxService.enqueueDispatch).toHaveBeenCalled();
  });

  it('flips isPaid when both worker and customer have confirmed', async () => {
    const booking: any = {
      id: 'b1',
      isPaid: false,
      status: BookingStatus.COMPLETED,
      operator: { id: 'work-1' },
      customer: { id: 'cust-1' },
      workerPaidConfirmed: false,
      customerPaidConfirmed: false,
    };
    const { service, bookingsRepository } = makeService();
    bookingsRepository.findOne.mockResolvedValue(booking);

    await service.markPaid('b1', 'work-1', { honestyCheck: 'TIP' });
    const res = await service.markPaid('b1', 'cust-1', {
      collectionMethod: 'UPI',
      safetyCheck: 'OK',
    });

    expect(booking.workerPaidConfirmed).toBe(true);
    expect(booking.customerPaidConfirmed).toBe(true);
    expect(booking.paymentCollectionMethod).toBe('UPI');
    expect(booking.customerSafetyCheck).toBe('OK');
    expect(booking.isPaid).toBe(true);
    expect(res.isPaid).toBe(true);
    expect(res.message).toBe('Booking marked as paid.');
  });
});

describe('BookingsService.refreshCompletionOtp', () => {
  it('404s when the booking does not exist', async () => {
    const { service } = makeService();
    await expect(service.refreshCompletionOtp('b1')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('mints a new 4-digit OTP, persists it and notifies the customer', async () => {
    const booking: any = {
      id: 'b1',
      completionOtp: '0000',
      customer: { id: 'cust-1' },
    };
    const { service, bookingsRepository, redisService, notificationsService } =
      makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    const res = await service.refreshCompletionOtp('b1');

    expect(res.completionOtp).toMatch(/^\d{4}$/);
    expect(booking.completionOtp).toBe(res.completionOtp);
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
    expect(redisService.saveOtp).toHaveBeenCalledWith(
      'otp:booking:b1:completion',
      res.completionOtp,
    );
    expect(notificationsService.notifyCustomerJobComplete).toHaveBeenCalledWith(
      'cust-1',
      res.completionOtp,
    );
  });

  it('does not notify when the booking has no customer', async () => {
    const booking: any = { id: 'b1', completionOtp: '0000', customer: null };
    const { service, bookingsRepository, notificationsService } = makeService();
    bookingsRepository.findOne.mockResolvedValueOnce(booking);

    await service.refreshCompletionOtp('b1');

    expect(
      notificationsService.notifyCustomerJobComplete,
    ).not.toHaveBeenCalled();
  });
});

describe('BookingsService.submitRating', () => {
  it('404s when the booking does not exist', async () => {
    const { service } = makeService();
    await expect(service.submitRating('b1', 5)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('rejects rating a job that is not COMPLETED', async () => {
    const booking: any = { id: 'b1', status: BookingStatus.ACTIVE };
    const { service, bookingsRepository, queryBuilder } = makeService();
    queryBuilder.getOne.mockResolvedValueOnce(booking);
    bookingsRepository.findOne.mockResolvedValueOnce(booking);
    await expect(service.submitRating('b1', 5)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('stores the rating and recomputes the worker rolling average under locks', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.COMPLETED,
      rating: null,
      operator: { id: 'work-1' },
    };
    const profile: any = { id: 'wp-1', rating: 4, reviewCount: 2 };
    const {
      service,
      bookingsRepository,
      workerProfileRepo,
      queryBuilder,
      workerProfileQb,
      dataSource,
    } = makeService();
    queryBuilder.getOne.mockResolvedValue(booking);
    bookingsRepository.findOne.mockResolvedValue(booking);
    workerProfileRepo.findOne.mockResolvedValue(profile);
    workerProfileQb.getOne.mockResolvedValue(profile);

    const res = await service.submitRating('b1', 5);

    expect(dataSource.transaction).toHaveBeenCalled();
    expect(queryBuilder.setLock).toHaveBeenCalledWith('pessimistic_write');
    expect(workerProfileQb.setLock).toHaveBeenCalledWith('pessimistic_write');
    expect(booking.rating).toBe(5);
    // (4*2 + 5) / 3 = 4.333...
    expect(profile.reviewCount).toBe(3);
    expect(profile.rating).toBeCloseTo(13 / 3, 5);
    expect(workerProfileRepo.save).toHaveBeenCalledWith(profile);
    expect(res.message).toBe('Rating submitted successfully');
  });

  it('does not fold into the average again when the booking is already rated', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.COMPLETED,
      rating: 4,
      operator: { id: 'work-1' },
    };
    const { service, bookingsRepository, workerProfileRepo, queryBuilder } =
      makeService();
    queryBuilder.getOne.mockResolvedValue(booking);
    bookingsRepository.findOne.mockResolvedValue(booking);

    const res = await service.submitRating('b1', 5);

    expect(booking.rating).toBe(4);
    expect(workerProfileRepo.findOne).not.toHaveBeenCalled();
    expect(res.message).toBe('Rating submitted successfully');
  });

  it('still saves the rating when the worker has no profile row', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.COMPLETED,
      rating: null,
      operator: { id: 'work-1' },
    };
    const { service, bookingsRepository, workerProfileRepo, queryBuilder } =
      makeService();
    queryBuilder.getOne.mockResolvedValue(booking);
    bookingsRepository.findOne.mockResolvedValue(booking);
    workerProfileRepo.findOne.mockResolvedValue(null);

    await service.submitRating('b1', 3);

    expect(booking.rating).toBe(3);
    expect(workerProfileRepo.save).not.toHaveBeenCalled();
  });

  it('skips the profile lookup when the booking has no operator', async () => {
    const booking: any = {
      id: 'b1',
      status: BookingStatus.COMPLETED,
      rating: null,
      operator: null,
    };
    const { service, bookingsRepository, workerProfileRepo, queryBuilder } =
      makeService();
    queryBuilder.getOne.mockResolvedValue(booking);
    bookingsRepository.findOne.mockResolvedValue(booking);

    await service.submitRating('b1', 4);

    expect(booking.rating).toBe(4);
    expect(workerProfileRepo.findOne).not.toHaveBeenCalled();
  });
});

describe('BookingsService.getBookingById', () => {
  it('loads the booking with customer + operator joins via the query builder', async () => {
    const booking: any = { id: 'b1' };
    const { service, bookingsRepository, queryBuilder } = makeService();
    queryBuilder.getOne.mockResolvedValueOnce(booking);

    const res = await service.getBookingById('b1');

    expect(bookingsRepository.createQueryBuilder).toHaveBeenCalledWith(
      'booking',
    );
    expect(queryBuilder.leftJoinAndSelect).toHaveBeenCalledWith(
      'booking.customer',
      'customer',
    );
    expect(queryBuilder.leftJoinAndSelect).toHaveBeenCalledWith(
      'booking.operator',
      'operator',
    );
    expect(queryBuilder.where).toHaveBeenCalledWith('booking.id = :id', {
      id: 'b1',
    });
    expect(res).toBe(booking);
  });
});

describe('BookingsService.findMyBookings', () => {
  it('builds an OR query for customer or operator with pagination', async () => {
    const { service, bookingsRepository, queryBuilder } = makeService();
    queryBuilder.getMany.mockResolvedValueOnce([{ id: 'b1' }]);

    const res = await service.findMyBookings('u1', undefined, 2, 10);

    expect(bookingsRepository.createQueryBuilder).toHaveBeenCalledWith(
      'booking',
    );
    expect(queryBuilder.where).toHaveBeenCalledWith(
      '(customer.id = :userId OR operator.id = :userId)',
      { userId: 'u1' },
    );
    expect(queryBuilder.orderBy).toHaveBeenCalledWith(
      'booking.scheduledAt',
      'DESC',
    );
    expect(queryBuilder.skip).toHaveBeenCalledWith(10);
    expect(queryBuilder.take).toHaveBeenCalledWith(10);
    expect(res).toEqual([{ id: 'b1' }]);
  });

  it('applies a single status filter', async () => {
    const { service, queryBuilder } = makeService();
    await service.findMyBookings('u1', 'accepted');
    expect(queryBuilder.andWhere).toHaveBeenCalledWith(
      'booking.status = :status',
      { status: 'ACCEPTED' },
    );
  });

  it('applies multiple statuses via IN', async () => {
    const { service, queryBuilder } = makeService();
    await service.findMyBookings('u1', 'active, completed');
    expect(queryBuilder.andWhere).toHaveBeenCalledWith(
      'booking.status IN (:...statuses)',
      { statuses: ['ACTIVE', 'COMPLETED'] },
    );
  });
});

describe('BookingsService.findAllByUser', () => {
  it('filters by customer id for the customer role', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('u1', 'customer');
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.where).toEqual({ customer: { id: 'u1' } });
    expect(arg.order).toEqual({ scheduledAt: 'DESC' });
  });

  it('filters by operator id for the operator role', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('w1', 'operator');
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.where).toEqual({ operator: { id: 'w1' } });
  });

  it('applies a single uppercased status as a plain equality filter', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('u1', 'customer', 'active');
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.where.status).toBe('ACTIVE');
  });

  it('applies multiple comma-separated statuses via In()', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('u1', 'customer', 'active, completed');
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.where.status).toEqual(In(['ACTIVE', 'COMPLETED']));
  });

  it('computes skip/take from page + limit', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('u1', 'customer', undefined, 3, 20);
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.skip).toBe((3 - 1) * 20);
    expect(arg.take).toBe(20);
  });

  it('defaults to page 1 / limit 50 when omitted', async () => {
    const { service, bookingsRepository } = makeService();
    await service.findAllByUser('u1', 'customer');
    const arg = bookingsRepository.find.mock.calls[0][0];
    expect(arg.skip).toBe(0);
    expect(arg.take).toBe(50);
  });
});

describe('BookingsService.calculateDistance (haversine)', () => {
  it('returns 0 for identical coordinates', () => {
    const { service } = makeService();
    expect(service.calculateDistance(12.9716, 77.5946, 12.9716, 77.5946)).toBe(
      0,
    );
  });

  it('measures ~111.19 km for one degree of latitude', () => {
    const { service } = makeService();
    // 1° of latitude is ~111.19 km on a 6371 km sphere, independent of longitude.
    expect(service.calculateDistance(0, 0, 1, 0)).toBeCloseTo(111.19, 1);
  });

  it('measures ~111.19 km for one degree of longitude at the equator', () => {
    const { service } = makeService();
    expect(service.calculateDistance(0, 0, 0, 1)).toBeCloseTo(111.19, 1);
  });

  it('is symmetric — distance A→B equals B→A', () => {
    const { service } = makeService();
    const ab = service.calculateDistance(12.9716, 77.5946, 13.0827, 80.2707);
    const ba = service.calculateDistance(13.0827, 80.2707, 12.9716, 77.5946);
    expect(ab).toBeCloseTo(ba, 6);
    // Bengaluru→Chennai is a few hundred km — sanity-bound the magnitude.
    expect(ab).toBeGreaterThan(250);
    expect(ab).toBeLessThan(350);
  });
});
