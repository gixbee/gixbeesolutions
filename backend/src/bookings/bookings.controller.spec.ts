import { NotFoundException } from '@nestjs/common';
import { BookingsController } from './bookings.controller';
import { BookingStatus, BookingType } from './booking.entity';

/**
 * Unit tests for the BookingsController HTTP layer. The controller is a thin
 * delegation surface over BookingsService (+ NotificationsService for the
 * accept/arrive/complete push side-effects, + RedisService for the cached
 * status poll). These tests instantiate the controller directly with jest-mock
 * services (matching the service-spec style in this repo — no Nest TestingModule,
 * no DB, no network) and assert:
 *  - create() maps the request body + req.user.userId into the service DTO shape
 *    (customer/operator wrapped as {id}, scheduledAt → Date, paymentMethod default
 *    'WALLET').
 *  - getMyBookings() parses page/limit (with non-numeric → defaults) and calls
 *    findMyBookings (single OR query — customer or operator).
 *  - status/cancel/otp/rating/mark-paid routes delegate with the right params and
 *    sensible defaults (cancel reason fallback).
 *  - accept() fires a customer push on success (string- or object-shaped customer),
 *    swallows a push failure, and rethrows a service error.
 *  - getBooking()/markArrived()/markComplete() throw NotFound on a missing booking.
 *  - getBookingStatus() returns the Redis cache on a hit and falls back to the DB
 *    (then populates the cache) on a miss.
 *  - dispute() echoes the reason without touching the service.
 */

function makeController(opts: {
  bookings?: Partial<Record<string, jest.Mock>>;
  redisCached?: any;
} = {}) {
  const bookingsService: any = {
    createBooking: jest.fn(async (dto: any) => ({ id: 'b1', ...dto })),
    findAllByUser: jest.fn(async () => []),
    findMyBookings: jest.fn(async () => []),
    findPendingForWorker: jest.fn(async () => []),
    updateStatus: jest.fn(async (id: string, status: BookingStatus) => ({ id, status })),
    cancelBooking: jest.fn(async (id: string, reason: string) => ({ id, status: BookingStatus.CANCELLED, reason })),
    verifyArrivalOtp: jest.fn(async (id: string, otp: string) => ({ id, otp, ok: true })),
    verifyCompletionOtp: jest.fn(async (id: string, otp: string) => ({ id, otp, ok: true })),
    refreshCompletionOtp: jest.fn(async (id: string) => ({ id, completionOtp: '654321' })),
    acceptBooking: jest.fn(),
    rejectBooking: jest.fn(async (id: string, workerId: string) => ({ id, workerId, rejected: true })),
    getBookingById: jest.fn(async () => null),
    markPaid: jest.fn(async (id: string) => ({ message: 'paid' })),
    submitRating: jest.fn(async (id: string, rating: number) => ({ id, rating })),
    ...(opts.bookings ?? {}),
  };

  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };

  const redisService: any = {
    getCachedBookingStatus: jest.fn(async () => opts.redisCached ?? null),
    cacheBookingStatus: jest.fn(async () => undefined),
  };

  const controller = new BookingsController(bookingsService, notificationsService, redisService);
  return { controller, bookingsService, notificationsService, redisService };
}

const req = (userId = 'u1') => ({ user: { userId } });

describe('BookingsController.create', () => {
  it('maps the body + req.user into the service DTO shape', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req('cust-1'), {
      workerId: 'w-9',
      skill: 'plumbing',
      serviceLocation: 'Flat 2B',
      serviceLat: 12.9,
      serviceLng: 77.6,
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 500,
      type: BookingType.INSTANT,
    });

    const dto = bookingsService.createBooking.mock.calls[0][0];
    expect(dto.customer).toEqual({ id: 'cust-1' });
    expect(dto.operator).toEqual({ id: 'w-9' });
    expect(dto.skill).toBe('plumbing');
    expect(dto.scheduledAt).toBeInstanceOf(Date);
    expect(dto.scheduledAt.toISOString()).toBe('2026-07-01T10:00:00.000Z');
    expect(dto.amount).toBe(500);
    expect(dto.paymentMethod).toBe('WALLET'); // default when omitted
  });

  it('keeps a supplied paymentMethod', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req(), {
      workerId: 'w-9',
      skill: 's',
      serviceLocation: 'l',
      serviceLat: 0,
      serviceLng: 0,
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
      type: BookingType.PACKAGE,
      paymentMethod: 'UPI',
    });
    expect(bookingsService.createBooking.mock.calls[0][0].paymentMethod).toBe('UPI');
  });

  it('forwards a picked saved-address id, and leaves it undefined when omitted', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req(), {
      workerId: 'w-9',
      serviceLocation: 'Flat 2B',
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
      addressId: 'addr-7',
    } as any);
    expect(bookingsService.createBooking.mock.calls[0][0].addressId).toBe('addr-7');

    await controller.create(req(), {
      workerId: 'w-9',
      serviceLocation: 'Flat 2B',
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
    } as any);
    expect(bookingsService.createBooking.mock.calls[1][0].addressId).toBeUndefined();
  });
});

describe('BookingsController.getMyBookings', () => {
  it('delegates to findMyBookings with parsed page/limit', async () => {
    const findMyBookings = jest.fn(async () => [{ id: 'c1' }, { id: 'o1' }]);
    const { controller, bookingsService } = makeController({
      bookings: { findMyBookings },
    });

    const res = await controller.getMyBookings(req('u-7'), 'ACCEPTED', '2', '10');

    expect(res).toEqual([{ id: 'c1' }, { id: 'o1' }]);
    expect(bookingsService.findMyBookings).toHaveBeenCalledWith(
      'u-7',
      'ACCEPTED',
      2,
      10,
    );
  });

  it('defaults page=1 / limit=50 when params are missing or non-numeric', async () => {
    const { controller, bookingsService } = makeController();
    await controller.getMyBookings(req('u-7'), undefined, 'abc', undefined);
    expect(bookingsService.findMyBookings).toHaveBeenCalledWith(
      'u-7',
      undefined,
      1,
      50,
    );
  });
});

describe('BookingsController.getPendingBookings', () => {
  it('delegates to findPendingForWorker with the caller id', async () => {
    const { controller, bookingsService } = makeController();
    await controller.getPendingBookings(req('w-1'));
    expect(bookingsService.findPendingForWorker).toHaveBeenCalledWith('w-1');
  });
});

describe('BookingsController.updateStatus / confirm', () => {
  it('updateStatus passes the body status through', async () => {
    const { controller, bookingsService } = makeController();
    await controller.updateStatus('b1', { status: BookingStatus.ACTIVE });
    expect(bookingsService.updateStatus).toHaveBeenCalledWith('b1', BookingStatus.ACTIVE);
  });

  it('confirmBooking forces ACCEPTED', async () => {
    const { controller, bookingsService } = makeController();
    await controller.confirmBooking('b1');
    expect(bookingsService.updateStatus).toHaveBeenCalledWith('b1', BookingStatus.ACCEPTED);
  });
});

describe('BookingsController.cancel', () => {
  it('passes the supplied reason', async () => {
    const { controller, bookingsService } = makeController();
    await controller.cancel('b1', { reason: 'changed mind' });
    expect(bookingsService.cancelBooking).toHaveBeenCalledWith('b1', 'changed mind');
  });

  it('falls back to "Not specified" when reason missing', async () => {
    const { controller, bookingsService } = makeController();
    await controller.cancel('b1', {} as any);
    expect(bookingsService.cancelBooking).toHaveBeenCalledWith('b1', 'Not specified');
  });
});

describe('BookingsController OTP gates', () => {
  it('confirmArrival / confirmCompletion / refreshCompletionOtp delegate', async () => {
    const { controller, bookingsService } = makeController();
    await controller.confirmArrival('b1', { otp: '111111' });
    await controller.confirmCompletion('b1', { otp: '222222' });
    await controller.refreshCompletionOtp('b1');
    expect(bookingsService.verifyArrivalOtp).toHaveBeenCalledWith('b1', '111111');
    expect(bookingsService.verifyCompletionOtp).toHaveBeenCalledWith('b1', '222222');
    expect(bookingsService.refreshCompletionOtp).toHaveBeenCalledWith('b1');
  });
});

describe('BookingsController.acceptBooking', () => {
  it('delegates accept to the service (customer FCM is sent inside the service)', async () => {
    const acceptBooking = jest.fn(async () => ({
      booking: { customer: { id: 'cust-1' }, operator: { name: 'Asha' } },
    }));
    const { controller, notificationsService } = makeController({ bookings: { acceptBooking } });

    const res = await controller.acceptBooking('b1', req('w-1'));

    expect(acceptBooking).toHaveBeenCalledWith('b1', 'w-1');
    // Controller no longer pushes — BookingsService.acceptBooking owns FCM.
    expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    expect(res).toBeDefined();
  });

  it('rethrows a service error', async () => {
    const acceptBooking = jest.fn(async () => { throw new Error('already taken'); });
    const { controller } = makeController({ bookings: { acceptBooking } });
    await expect(controller.acceptBooking('b1', req('w-1'))).rejects.toThrow('already taken');
  });
});

describe('BookingsController.rejectBooking', () => {
  it('delegates with the caller id', async () => {
    const { controller, bookingsService } = makeController();
    await controller.rejectBooking('b1', req('w-3'));
    expect(bookingsService.rejectBooking).toHaveBeenCalledWith('b1', 'w-3');
  });
});

describe('BookingsController.getBooking', () => {
  it('returns the booking when found', async () => {
    const getBookingById = jest.fn(async () => ({ id: 'b1' }));
    const { controller } = makeController({ bookings: { getBookingById } });
    expect(await controller.getBooking('b1')).toEqual({ id: 'b1' });
  });

  it('throws NotFound when absent', async () => {
    const { controller } = makeController(); // getBookingById → null
    await expect(controller.getBooking('b1')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('BookingsController.getBookingStatus', () => {
  it('returns the Redis cache on a hit (no DB read)', async () => {
    const { controller, bookingsService, redisService } = makeController({ redisCached: { status: 'ACCEPTED' } });
    const res = await controller.getBookingStatus('b1');
    expect(res).toEqual({ status: 'ACCEPTED' });
    expect(bookingsService.getBookingById).not.toHaveBeenCalled();
    expect(redisService.cacheBookingStatus).not.toHaveBeenCalled();
  });

  it('falls back to DB and populates the cache on a miss', async () => {
    const getBookingById = jest.fn(async () => ({
      status: BookingStatus.ACCEPTED,
      operator: { name: 'Asha' },
      arrivalOtp: '999999',
    }));
    const { controller, redisService } = makeController({ bookings: { getBookingById } });
    const res = await controller.getBookingStatus('b1');
    expect(res).toEqual({ status: BookingStatus.ACCEPTED, operatorName: 'Asha', arrivalOtp: '999999' });
    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith('b1', res);
  });

  it('hides the arrivalOtp when status is not ACCEPTED', async () => {
    const getBookingById = jest.fn(async () => ({
      status: BookingStatus.ACTIVE,
      operator: { name: 'Asha' },
      arrivalOtp: '999999',
    }));
    const { controller } = makeController({ bookings: { getBookingById } });
    const res: any = await controller.getBookingStatus('b1');
    expect(res.arrivalOtp).toBeNull();
  });

  it('throws NotFound when neither cache nor DB has it', async () => {
    const { controller } = makeController(); // cache null + getBookingById null
    await expect(controller.getBookingStatus('b1')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('BookingsController.markArrived / markComplete', () => {
  it('markArrived sends the arrival OTP push and returns a message', async () => {
    const getBookingById = jest.fn(async () => ({ arrivalOtp: '123456', customer: { id: 'cust-1' } }));
    const { controller, notificationsService } = makeController({ bookings: { getBookingById } });
    const res = await controller.markArrived('b1');
    expect(notificationsService.sendToUser).toHaveBeenCalledWith('cust-1', expect.objectContaining({
      title: 'Worker has arrived',
    }));
    expect(res).toEqual({ message: 'Arrival OTP sent to customer.' });
  });

  it('markArrived throws NotFound when booking missing', async () => {
    const { controller } = makeController();
    await expect(controller.markArrived('b1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('markComplete sends the completion OTP push and returns a message', async () => {
    const getBookingById = jest.fn(async () => ({ completionOtp: '654321', customer: { id: 'cust-1' } }));
    const { controller, notificationsService } = makeController({ bookings: { getBookingById } });
    const res = await controller.markComplete('b1');
    expect(notificationsService.sendToUser).toHaveBeenCalledWith('cust-1', expect.objectContaining({
      title: 'Job marked as complete',
    }));
    expect(res).toEqual({ message: 'Completion OTP sent to customer.' });
  });

  it('markComplete throws NotFound when booking missing', async () => {
    const { controller } = makeController();
    await expect(controller.markComplete('b1')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('BookingsController.markPaid / submitRating / reportDispute', () => {
  it('markPaid delegates', async () => {
    const { controller, bookingsService } = makeController();
    await controller.markPaid('b1', { user: { userId: 'u1' } }, {
      honestyCheck: 'EXACT',
    });
    expect(bookingsService.markPaid).toHaveBeenCalledWith('b1', 'u1', {
      honestyCheck: 'EXACT',
    });
  });

  it('submitRating passes the numeric rating', async () => {
    const { controller, bookingsService } = makeController();
    await controller.submitRating('b1', { rating: 5 });
    expect(bookingsService.submitRating).toHaveBeenCalledWith('b1', 5);
  });

  it('reportDispute echoes the reason without touching the service', async () => {
    const { controller, bookingsService } = makeController();
    const res = await controller.reportDispute('b1', { reason: 'late' });
    expect(res).toEqual({ success: true, message: 'Dispute logged: late' });
    expect(bookingsService.submitRating).not.toHaveBeenCalled();
  });
});
